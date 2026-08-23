#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
# Copyright (C) 2026  Université Sorbonne Paris Nord

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# ---------------------------------------------------------------------------
# The "LAN bridge" of the `modernisation-world-bridge' work-stream (option B of
# docs/modernisation-world-bridge.md § 2.1, promoted to a component of its own at
# episode 4): the bridge that puts Marionnet's virtual machines on the REAL local
# network of the host -- real addresses, real DHCP, real services -- instead of
# behind a private NAT (that is marionnet-natbridge.sh, option A).
#
# It replaces useful-scripts/prepare_bridge.sh (2007: brctl, ifconfig, mii-tool,
# all three dead tools; that script was itself retired from the source tree on
# 2026-08-23, archived outside git), and above all it replaces the GESTURE that script stood
# for: an administrator building `br0' by hand before Marionnet could be used at
# all. Here the bridge is built and undone by Marionnet itself, on demand.
#
# --- WHAT MAKES IT DIFFERENT FROM THE NAT BRIDGE (read this before editing) ---
#
# The NAT bridge NEVER touches the host interface -- that is what makes it safe.
# This one has to: a LAN bridge is precisely the host's own network card,
# enslaved to a bridge, with the host's address and default route moved onto that
# bridge. Everything below follows from that:
#
#   * ONE LAN bridge per host, `mnlan0', NOT `mnlan<pid>'. A card has exactly one
#     master, so two Marionnet processes cannot each have their own -- they share
#     this one, exactly as they used to share the hand-made `br0'.
#   * OWNERSHIP IS READ FROM THE SYSTEM, not from a state file. The ports named
#     `mtap<pid>-<n>' are Marionnet's taps, so the bridge itself says which live
#     processes are using it (the trick `gc' already plays in marionnet-natbridge.sh),
#     and `down' only dismantles when none is left. The creator additionally
#     stamps `alias marionnet-lanbridge:<pid>:<card>' on the bridge: the pid closes
#     the window between "the bridge exists" and "a tap is attached to it", and
#     the card is the one fact no deduction can be trusted with (see
#     set_physical_port).
#   * RESTORING THE HOST IS READ FROM THE SYSTEM TOO: the bridge carries the
#     address, the default route and, in its alias, the card they came from.
#     Hence NO state file at all (the NAT bridge needs
#     one only for ip_forward, which does not exist here), and hence a teardown
#     that still works after a crash, from another account, or from `gc'.
#   * NO iptables: a LAN bridge does no NAT and no forwarding. The privileged
#     command list is pure iproute2.
#
# --- ORDER OF OPERATIONS (the reason it is what it is) ---
#
# The address is put ON THE BRIDGE FIRST, and only then removed from the card:
#   bridge / mac / alias / up  ->  addr add (bridge)  ->  addr del (card)
#                              ->  enslave            ->  default route (bridge)
# so the host address is never nowhere, not even for a moment -- and the LIFO
# rollback then unwinds in the only order that works: delete the route, RELEASE
# the card (`nomaster') and only then give it its address and its default route
# back. Restoring an address on a still-enslaved card would half-work, and
# re-adding its default route would simply fail.
#
# There remains a window of a few milliseconds, between `addr del' on the card
# and the default route on the bridge, during which the host has no route out.
# A SIGKILL there leaves the address ON THE BRIDGE (not lost), which is exactly
# what `down' and `gc' know how to give back.
#
# --- WHAT IT REFUSES TO DO ---
#
# Wi-Fi (an access point refuses several MAC addresses behind one association),
# a card that is already enslaved to somebody else's bridge, an ambiguous default
# route, and IPv6 (not handled at all -- same choice as the NAT bridge).
#
# --- THE OUTPUT CONTRACT, `set -u', VALIDATORS: same as marionnet-natbridge.sh ---
#
#   stdout : EXACTLY ONE JSON object, on ONE line, on EVERY exit path.
#   stderr : the human trace -- every privileged command is echoed before it runs.
#   status : 0 on success; the JSON also carries a symbolic error code.
#
# No `set -u': bashbricks is not nounset-clean (gotchas.md § 13 of the skill
# use-bashbricks), and `set -u' would not protect against the variable that is
# SET BUT EMPTY anyway. The guard is the anchored validator -- require_pid,
# require_iface, require_cidr, require_bridge -- through which every value
# reaches a destructive command.
# ---------------------------------------------------------------------------

TOOL=$(basename "$0")

# --- bashbricks: sourced FIRST, with nounset off (see the header), then the
# --- shell options. Same three-candidate probe as marionnet-natbridge.sh: the
# --- library is installed next to this script.

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

function source_bashbricks {
 local candidate
 for candidate in \
   ${MARIONNET_BASHBRICKS:+"$MARIONNET_BASHBRICKS"} \
   "$SCRIPT_DIR/bashbricks.sh" \
   "$SCRIPT_DIR/../../bashbricks/bashbricks.sh"
 do
   if [[ -r $candidate ]]; then
     # shellcheck disable=SC1090
     source "$candidate" && return 0
   fi
 done
 # No bashbricks means no Json_*, hence no report: this one message is the only
 # thing this script may ever write to stdout that is not built by the library.
 printf '{"ok":false,"action":"init","error":"E_INTERNAL","message":"%s"}\n' \
   "$TOOL: cannot find bashbricks.sh (tried \$MARIONNET_BASHBRICKS, $SCRIPT_DIR/bashbricks.sh, $SCRIPT_DIR/../../bashbricks/bashbricks.sh)"
 echo "$TOOL: cannot find bashbricks.sh -- is Marionnet correctly installed?" 1>&2
 exit 3
}

source_bashbricks >/dev/null || exit 3

# -E so that the ERR trap is inherited by functions; no -u, see the header.
set -eEo pipefail

# --- Constants. BRIDGE and ALIAS_PREFIX are part of the contract with the OCaml
# --- side and with the sudoers rule (bin/scripts/marionnet-sudoers.sh, block (c),
# --- whose device pattern is ${BRIDGE_PREFIX}*): do not change them alone.

BRIDGE_PREFIX=mnlan
BRIDGE_INDEX=0             # one card, one master, one bridge -- see the header
ALIAS_PREFIX=marionnet-lanbridge
TAP_PREFIX=mtap            # MUST agree with bin/tap_provider.ml

BR="${BRIDGE_PREFIX}${BRIDGE_INDEX}"

# --- Mutable state of the current invocation

ACTION=""             # up | down | status | gc | selftest | ...
OWNER_PID=""          # the pid that claims the bridge (stamped in its alias)
IFACE=""              # the host card the bridge is built on
FORCED_IFACE=""       # --interface
MAC=""                # its MAC address, cloned onto the bridge
GATEWAY=""            # the default gateway seen through IFACE
ROUTE_METRIC=""       # the metric of that default route (empty when it has none)
NETNS=""              # --netns: TEST ONLY (selftest), see run_ip
DRY_RUN=0             # --dry-run
FORCE=0               # --force
FAIL_AFTER=""         # --fail-after LABEL (test only)
SUDO_INTERACTIVE=0    # --sudo-interactive
LAST_ERROR=""         # diagnostic of the step that just failed
LAST_ERROR_CODE=""    # and the symbolic code that failure deserves

Map_make REPORT              # typed fields (booleans, numbers, JSON fragments)
Map_make REPORT_TEXT         # free text ONLY (see emit_report)
Array_make HOST_ADDRS        # the card's global IPv4 addresses, as `ip addr' argv
Array_make CREATED           # labels of the steps that succeeded
Array_make UNDO              # the same, as an undo stack
Array_make UNDONE            # labels successfully undone
Array_make LEFTOVERS         # labels we FAILED to undo -- the honest part
Array_make WARNINGS
REPORT_EMITTED=0

# --- The report
#
# Two maps, one call each, merged by jq. The split is not cosmetic: Map_to_json
# parses scalars by default (that is what keeps ok=false a JSON boolean and an
# Array_to_json fragment an array), and that same parsing would turn an error
# message that merely LOOKS like JSON into a JSON value. Free text therefore goes
# through `Map_to_json -s' (stringify).
# Do NOT pre-escape with Json_escape_string: Map_to_json escapes internally, and
# doing both doubles the escaping.

function emit_report {
 [[ $REPORT_EMITTED = 1 ]] && return 0
 REPORT_EMITTED=1
 REPORT[action]=$ACTION
 REPORT[created]=$(Array_to_json CREATED)
 REPORT[undone]=$(Array_to_json UNDONE)
 REPORT[leftovers]=$(Array_to_json LEFTOVERS)
 REPORT[warnings]=$(Array_to_json WARNINGS)
 printf '%s\n%s\n' "$(Map_to_json REPORT)" "$(Map_to_json -s REPORT_TEXT)" \
   | jq -c -s '.[0] * .[1]'
}

# finish RC: the single exit door. Every path out of this script goes through it.
function finish {
 local rc=${1:-0}
 emit_report
 exit "$rc"
}

# fail CODE MESSAGE...: report the cause, unwind whatever we built, exit 1.
function fail {
 local code=$1; shift
 REPORT[ok]=false
 REPORT[error]=$code
 REPORT_TEXT[message]="$*"
 echo "$TOOL: $code: $*" 1>&2
 rollback
 finish 1
}

function succeed {
 REPORT[ok]=true
 finish 0
}

# The safety net: an unexpected non-zero (set -e) or a signal must not leave the
# HOST half-configured -- here that would mean a machine with no address.
function on_error {
 local rc=$1
 trap - ERR INT TERM
 [[ $REPORT_EMITTED = 1 ]] && exit "$rc"
 fail E_INTERNAL "${LAST_ERROR:-unexpected failure (status $rc)}"
}
trap 'on_error $?' ERR
trap 'on_error 130' INT TERM

# --- Validators.
#
# THE guard of this script (see the header on `set -u'). A value that has not
# passed through here never reaches a command that destroys something. Anchored
# regexps, not `-n' tests.

function require_pid {
 { Regexp_is_natural "${1:-}" && (( ${1:-0} >= 1 )); } \
   || fail E_BAD_PID "'${1:-}' is not a pid"
}

# Linux interface names: 1..15 characters, no space, no slash (IFNAMSIZ = 16
# including the final NUL). No Regexp_is_* fits, and an anchored [[ =~ ]] is more
# direct than composing String_scanf: the "small native primitive" case.
function require_iface {
 [[ ${1:-} =~ ^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,14}$ ]] \
   || fail E_BAD_IFACE "'${1:-}' is not an interface name"
}

function require_cidr {   # an IPv4 address with its prefix length, e.g. 192.168.1.42/24
 [[ ${1:-} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] \
   || fail E_BAD_ADDRESS "'${1:-}' is not an IPv4 address with a prefix length"
}

function require_ipv4 {
 [[ ${1:-} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
   || fail E_BAD_ADDRESS "'${1:-}' is not an IPv4 address"
}

function require_mac {
 [[ ${1:-} =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]] \
   || fail E_BAD_MAC "'${1:-}' is not a MAC address"
}

function require_bridge {
 [[ ${1:-} =~ ^${BRIDGE_PREFIX}[0-9]+$ ]] \
   || fail E_INTERNAL "'${1:-}' is not one of our bridge names"
}

# --- Absolute binary paths: sudoers matches on the absolute path, and root's
# PATH is not the user's. Same probing discipline as bin/scripts/marionnet-sudoers.sh.

IP=""

function binary_among {   # binary_among CODE CANDIDATE...
 local code=$1 candidate; shift
 for candidate in "$@"; do
   if [[ -x $candidate ]]; then echo "$candidate"; return 0; fi
 done
 fail "$code" "none of $* is executable (missing package?)"
}

function resolve_binaries {
 [[ -n $IP ]] && return 0
 IP=$(binary_among E_NO_IPROUTE2 /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip)
 if [[ -n $NETNS ]]; then IP_CMD=("$IP" -netns "$NETNS"); else IP_CMD=("$IP"); fi
}

# --- Privileged execution
#
# `sudo -n' by default: this is a machine interface, and block (c) of
# bin/scripts/marionnet-sudoers.sh is what makes it work without a password.

function sudo_run {
 if [[ $SUDO_INTERACTIVE = 1 ]]; then sudo -- "$@"; else sudo -n -- "$@"; fi
}

# --- `ip' in two flavours
#
# IP_CMD : the head of a PRIVILEGED ip command, to be expanded before the
#          arguments of every `step' -- an ARRAY, so that nothing depends on word
#          splitting.
# read_ip: an unprivileged read.
#
# --netns exists for the selftest alone: it lets the whole destructive path be
# played inside a network namespace, on a fake card, without touching the real
# machine. Inside a namespace even reading needs root, and none of these commands
# match the sudoers rule (which names `ip link ...', not `ip -netns NS link ...'),
# so --netns forces the interactive sudo -- exactly like the netns harness of
# marionnet-natbridge.sh, which is out of the rule on purpose.

IP_CMD=()

function read_ip {
 if [[ -n $NETNS ]]; then sudo -- "$IP" -netns "$NETNS" "$@"; else "$IP" "$@"; fi
}

# step LABEL COMMAND ARG...: run a privileged command and, on success, record
# LABEL both as "created" and on the undo stack. Returns 1 on failure, leaving
# the diagnostic in LAST_ERROR -- it never exits by itself, because the caller
# decides which error code the failure deserves.
function step {
 local label=$1; shift
 printf '  + sudo %s\n' "$*" 1>&2
 if [[ $FAIL_AFTER = "$label" ]]; then
   LAST_ERROR="injected failure at step '$label' (--fail-after)"
   LAST_ERROR_CODE=E_INTERNAL
   return 1
 fi
 if [[ $DRY_RUN = 1 ]]; then
   Array_push CREATED "$label"; Array_push UNDO "$label"; return 0
 fi
 local output rc=0
 output=$(sudo_run "$@" 2>&1) || rc=$?
 if [[ $rc = 0 ]]; then
   Array_push CREATED "$label"; Array_push UNDO "$label"; return 0
 fi
 LAST_ERROR="\`sudo $*' failed: $output"
 LAST_ERROR_CODE=E_SUDO_DENIED
 return 1
}

function fail_step { fail "${LAST_ERROR_CODE:-E_INTERNAL}" "$LAST_ERROR"; }

# restore_default_route DEV: give DEV the host's default route back, metric
# included (see route_metric_of). The metric-less form is a FALLBACK, not a
# preference: should a sudoers rule stricter than the one we ship refuse the
# argument, losing the metric is a blemish, whereas leaving the host with no
# default route at all is a breakdown.
function restore_default_route {
 local dev=$1
 if [[ -n $ROUTE_METRIC ]]; then
   sudo_run "${IP_CMD[@]}" route add default via "$GATEWAY" dev "$dev" metric "$ROUTE_METRIC" && return 0
   Array_push WARNINGS "the default route of $dev came back without its metric ($ROUTE_METRIC): the privileged command carrying it was refused"
 fi
 sudo_run "${IP_CMD[@]}" route add default via "$GATEWAY" dev "$dev"
}

# undo_step LABEL: the exact inverse of the step of that name. It must NEVER call
# `fail' (it runs from inside the rollback) and never abort the script.
#
# `addr_del:<i>' is the one composite inverse, and deliberately so: removing the
# card's address took its default route with it (the kernel drops routes whose
# source address is gone), so giving the address back has to give the route back
# too. There is no forward step to be the route's mirror.
function undo_step {
 local label=$1 index
 [[ $DRY_RUN = 1 ]] && return 0
 case $label in
   route)
     if [[ -n $ROUTE_METRIC ]]; then
       sudo_run "${IP_CMD[@]}" route del default via "$GATEWAY" dev "$BR" metric "$ROUTE_METRIC" && return 0
     fi
     sudo_run "${IP_CMD[@]}" route del default via "$GATEWAY" dev "$BR" ;;
   addr_del:*)
     index=${label#addr_del:}
     # Word splitting on HOST_ADDRS[index] is INTENDED: the entry holds the argv
     # tail `<cidr> [brd <addr>]' exactly as `ip addr add' expects it. It comes
     # from `ip', not from a user, and every field went through require_cidr /
     # require_ipv4.
     #
     # Both restorations are CONDITIONAL: the card's manager may have put them
     # back already, in the milliseconds it took us to get here, and adding them
     # a second time is what used to leave the host with a duplicate default
     # route (see route_metric_of).
     if ! addr_present "$IFACE" "${HOST_ADDRS[index]%% *}"; then
       # `metric' here is for the PREFIX route the kernel derives from the address
       # (`192.168.95.0/24 dev <IF>'), the same reason the default route carries
       # one: without it the kernel makes that route with metric 0 and the
       # manager's own, metric 100, sits next to it.
       # shellcheck disable=SC2086
       sudo_run "${IP_CMD[@]}" addr add ${HOST_ADDRS[index]} dev "$IFACE" ${ROUTE_METRIC:+metric $ROUTE_METRIC} || return 1
     fi
     if [[ -n $GATEWAY ]] && ! default_route_present "$IFACE"; then
       restore_default_route "$IFACE" || return 1
     fi
     ;;
   addr_add:*)
     # Deleting an address takes the CIDR alone: `brd' belongs to the `add' form,
     # and the fewer words a destructive command carries, the narrower the
     # sudoers line that has to authorise it.
     index=${label#addr_add:}
     sudo_run "${IP_CMD[@]}" addr del "${HOST_ADDRS[index]%% *}" dev "$BR" ;;
   enslave)   sudo_run "${IP_CMD[@]}" link set "$IFACE" nomaster ;;
   bridge_up) sudo_run "${IP_CMD[@]}" link set "$BR" down ;;
   alias)     return 0 ;;   # the alias dies with the bridge
   mac)       return 0 ;;   # so does the cloned MAC
   link)      sudo_run "${IP_CMD[@]}" link del "$BR" ;;
   *)         return 1 ;;
 esac
}

# rollback: unwind the undo stack, LIFO. The order matters more here than in the
# NAT bridge: `enslave' must be undone BEFORE the card is given its address and
# its route back (see the header), and the stack is built so that it is.
function rollback {
 local index label
 (( ${#UNDO[@]} == 0 )) && return 0
 trap - ERR   # inside the rollback a failing command is data, not an abort

 # The validators are inlined here rather than called: require_* calls `fail',
 # and `fail' calls this function -- the recursion would be unbounded. A name we
 # cannot validate is a name we refuse to build a destructive command from.
 if [[ ! $BR =~ ^${BRIDGE_PREFIX}[0-9]+$ ]] \
    || { [[ -n $IFACE ]] && [[ ! $IFACE =~ ^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,14}$ ]]; }; then
   echo "$TOOL: REFUSING to roll back: bridge '$BR' / interface '$IFACE' did not validate." 1>&2
   for label in "${UNDO[@]}"; do Array_push LEFTOVERS "$label"; done
   Array_make UNDO
   REPORT[rolled_back]=false
   Array_push WARNINGS E_ROLLBACK_INCOMPLETE
   trap 'on_error $?' ERR
   return 0
 fi

 echo "$TOOL: rolling back ${#UNDO[@]} step(s)." 1>&2
 for (( index=${#UNDO[@]} - 1; index >= 0; index-- )); do
   label=${UNDO[index]}
   if undo_step "$label" >/dev/null 2>&1; then
     Array_push UNDONE "$label"
   else
     Array_push LEFTOVERS "$label"
     echo "$TOOL: COULD NOT UNDO '$label' -- it survives on this host." 1>&2
   fi
 done
 Array_make UNDO
 trap 'on_error $?' ERR
 if (( ${#LEFTOVERS[@]} > 0 )); then
   REPORT[rolled_back]=false
   Array_push WARNINGS E_ROLLBACK_INCOMPLETE
 else
   REPORT[rolled_back]=true
 fi
}

# --- Reading the system
#
# Everything this script needs to know -- and everything a LATER invocation needs
# in order to undo it -- is read back from the kernel. There is no state file.

function link_exists  { read_ip link show "$1" &>/dev/null; }
function pid_is_alive { [[ -d /proc/$1 ]]; }

# detect_iface: SETS IFACE to the card carrying the default route. Zero or
# several distinct ones is not something to guess about.
#
# It sets a global instead of echoing, and every other function that may `fail'
# does the same: `fail' emits the report and exits, so calling it from inside a
# `$(...)' would kill the SUBSHELL only -- the JSON would land in the variable
# being assigned instead of on stdout, and the caller would carry on.
function detect_iface {
 local devices count
 devices=$(read_ip -4 route show default 2>/dev/null \
   | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u)
 count=$(grep -c . <<<"$devices" || true)
 case $count in
   0) fail E_NO_DEFAULT_ROUTE "this host has no IPv4 default route: there is no LAN to bridge to (use --interface to name a card anyway)" ;;
   1) IFACE=$devices ;;
   *) fail E_AMBIGUOUS_ROUTE "several cards carry a default route ($(tr '\n' ' ' <<<"$devices")): say which one with --interface" ;;
 esac
}

function gateway_of {   # gateway_of IFACE
 read_ip -4 route show default dev "$1" 2>/dev/null \
   | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}'
}

# route_metric_of DEV: the metric of the IPv4 default route through DEV, empty when
# there is none, or when it is the implicit 0 (which is what `ip' prints nothing for).
#
# WHY THE METRIC IS CARRIED AROUND AT ALL (episode 7b bis, measured on a real card).
# A network manager owns the card and gives its routes a metric of its own -- 100
# for NetworkManager. Restoring the host's default route WITHOUT that metric makes
# a SECOND route, of metric 0, i.e. one that wins over everything, including the
# manager's own and including the other cards of a laptop. And it is not a race we
# can win by looking first: the manager reinstalls its routes some milliseconds
# after we hand the card back, so whoever writes last leaves a duplicate. Restoring
# the metric makes the two the SAME route -- the kernel then keeps exactly one,
# whatever the order. The value travels on the bridge's own default route, so it is
# read back from the system like everything else here, with still no state file.
function route_metric_of {
 read_ip -4 route show default dev "$1" 2>/dev/null \
   | awk '{for(i=1;i<=NF;i++) if($i=="metric") {print $(i+1); exit}}'
}

# addr_present DEV CIDR / default_route_present DEV: is it there already? Asked
# before restoring, because a managed card gets its address and its route back
# from its manager, and adding them twice is what leaves the duplicate above.
function addr_present {
 read_ip -4 -oneline addr show dev "$1" scope global 2>/dev/null \
   | awk -v cidr="$2" '{for(i=1;i<=NF;i++) if($i=="inet" && $(i+1)==cidr) {found=1; exit}} END{exit !found}'
}

function default_route_present {
 read_ip -4 route show default dev "$1" 2>/dev/null \
   | awk -v gw="$GATEWAY" '{for(i=1;i<=NF;i++) if($i=="via" && $(i+1)==gw) {found=1; exit}} END{exit !found}'
}

function mac_of {
 read_ip -oneline link show "$1" 2>/dev/null \
   | awk '{for(i=1;i<=NF;i++) if($i=="link/ether") {print $(i+1); exit}}'
}

function master_of {
 read_ip -oneline link show "$1" 2>/dev/null \
   | awk '{for(i=1;i<=NF;i++) if($i=="master") {print $(i+1); exit}}'
}

function alias_of {
 read_ip -oneline -detail link show "$1" 2>/dev/null \
   | awk '{for(i=1;i<=NF;i++) if($i=="alias") {print $(i+1); exit}}'
}

# read_addresses DEV: fills HOST_ADDRS with the global IPv4 addresses of DEV, each
# entry being the argv tail of an `ip addr add', i.e. `<cidr>' or `<cidr> brd <a>'.
function read_addresses {
 local line cidr brd
 Array_make HOST_ADDRS
 while read -r line; do
   [[ -z $line ]] && continue
   cidr=$(awk '{for(i=1;i<=NF;i++) if($i=="inet") {print $(i+1); exit}}' <<<"$line")
   brd=$(awk '{for(i=1;i<=NF;i++) if($i=="brd") {print $(i+1); exit}}' <<<"$line")
   [[ -z $cidr ]] && continue
   require_cidr "$cidr"
   if [[ -n $brd ]]; then
     require_ipv4 "$brd"
     Array_push HOST_ADDRS "$cidr brd $brd"
   else
     Array_push HOST_ADDRS "$cidr"
   fi
 done < <(read_ip -4 -oneline addr show dev "$1" scope global 2>/dev/null)
}

# ports_of BRIDGE: the names of the interfaces enslaved to BRIDGE. `veth' ports
# are shown as `name@peer' -- the peer is not part of the name.
function ports_of {
 read_ip -oneline link show master "$1" 2>/dev/null \
   | awk -F': ' '{sub(/@.*/, "", $2); print $2}'
}

# live_users BRIDGE [EXCEPT_PID]: the pids of the LIVE Marionnet processes using
# BRIDGE, read from the names of its `mtap<pid>-<n>' ports, plus the pid stamped
# in the bridge alias when it is still alive (that one covers the moment between
# "the bridge is up" and "the first tap is attached").
# The accumulator is called __lb_users and not `users': Array_make refuses a name
# that already exists and is not an array, and `Array_make X' inside a function
# writes the GLOBAL X (it assigns through a nameref). A caller with a `local
# users' would therefore break this function -- measured, at the first selftest.
function live_users {
 local bridge=$1 except=${2:-} port pid stamped
 Array_make __lb_users
 for port in $(ports_of "$bridge"); do
   [[ $port =~ ^${TAP_PREFIX}([1-9][0-9]*)- ]] || continue
   pid=${BASH_REMATCH[1]}
   [[ -n $except && $pid = "$except" ]] && continue
   pid_is_alive "$pid" || continue
   Array_member __lb_users "$pid" || Array_push __lb_users "$pid"
 done
 stamped=$(alias_of "$bridge")
 if [[ $stamped =~ ^${ALIAS_PREFIX}:([1-9][0-9]*): ]]; then
   pid=${BASH_REMATCH[1]}
   if [[ -z $except || $pid != "$except" ]] && pid_is_alive "$pid"; then
     Array_member __lb_users "$pid" || Array_push __lb_users "$pid"
   fi
 fi
 printf '%s\n' ${__lb_users[@]+"${__lb_users[@]}"}
}

# set_physical_port BRIDGE: SETS IFACE to the card the host's address came from,
# i.e. the card this bridge must give back. Empty if there is none (a bridge whose
# card has already been released). Sets a global rather than echoing, for the
# reason given above detect_iface.
#
# THE CARD IS READ FROM THE BRIDGE ALIAS -- `marionnet-lanbridge:<pid>:<card>' --
# which `up' stamps there. The first version deduced it instead ("the only port
# that is not an mtap"), and the selftest killed that idea on its first run: any
# third party may add a port to a bridge (the test guest did), and then the
# deduction has to choose between two cards, which is exactly what one must never
# do to somebody's network. The alias makes it a fact, readable after a crash and
# from another account, with still no state file anywhere.
#
# The deduction survives as a FALLBACK, for a bridge stamped by nothing (an older
# version, or a `mnlan0' built by hand): one non-tap port is unambiguous, more
# than one is a refusal.
function set_physical_port {
 local bridge=$1 stamped port count=0 named=""
 IFACE=""
 stamped=$(alias_of "$bridge")
 # <card> is the rest of the string: an interface name may itself contain `:'.
 if [[ $stamped =~ ^${ALIAS_PREFIX}:[1-9][0-9]*:(.+)$ ]]; then named=${BASH_REMATCH[1]}; fi
 for port in $(ports_of "$bridge"); do
   if [[ -n $named && $port = "$named" ]]; then IFACE=$named; return 0; fi
   [[ $port =~ ^${TAP_PREFIX}[1-9][0-9]*- ]] && continue
   IFACE=$port; count=$((count + 1))
 done
 if [[ -n $named ]]; then
   # Stamped, but that card is no longer a port: somebody released it already.
   IFACE=""
   Array_push WARNINGS "$bridge is stamped with card '$named', which is not one of its ports any more"
   return 0
 fi
 (( count <= 1 )) \
   || fail E_INTERNAL "$1 has $count ports that are not Marionnet taps and no card stamped in its alias; refusing to guess which one the host address belongs to"
}

# --- up

function do_up {
 local index master
 [[ -n $OWNER_PID ]] || OWNER_PID=$PPID
 require_pid "$OWNER_PID"
 resolve_binaries
 require_bridge "$BR"
 REPORT[bridge]=$BR
 REPORT[owner_pid]=$OWNER_PID

 # Idempotent, and this is the SHARED case: a LAN bridge that is already up is
 # the one this host has, whoever built it. We adopt it and say so.
 if link_exists "$BR"; then
   set_physical_port "$BR"
   read_addresses "$BR"
   GATEWAY=$(gateway_of "$BR")
   ROUTE_METRIC=$(route_metric_of "$BR")
   REPORT[adopted]=true
   describe_bridge
   REPORT_TEXT[message]="$BR already exists, nothing to do"
   echo "$TOOL: $BR already exists (card ${IFACE:-none}) -- nothing to do." 1>&2
   succeed
 fi
 REPORT[adopted]=false

 if [[ -n $FORCED_IFACE ]]; then IFACE=$FORCED_IFACE; else detect_iface; fi
 require_iface "$IFACE"
 link_exists "$IFACE" || fail E_BAD_IFACE "there is no interface called '$IFACE' here"
 refuse_wireless "$IFACE"
 master=$(master_of "$IFACE")
 [[ -z $master ]] || fail E_ALREADY_ENSLAVED "$IFACE is already enslaved to '$master'"

 MAC=$(mac_of "$IFACE");        require_mac "$MAC"
 GATEWAY=$(gateway_of "$IFACE")
 [[ -z $GATEWAY ]] || require_ipv4 "$GATEWAY"
 # The metric travels with the route (see route_metric_of). A value we cannot
 # validate is dropped rather than passed on to a privileged command.
 ROUTE_METRIC=$(route_metric_of "$IFACE")
 if [[ ! $ROUTE_METRIC =~ ^[0-9]{1,10}$ ]] || [[ $ROUTE_METRIC = 0 ]]; then ROUTE_METRIC=""; fi
 read_addresses "$IFACE"
 (( ${#HOST_ADDRS[@]} > 0 )) \
   || fail E_NO_ADDRESS "$IFACE carries no global IPv4 address: there is nothing to move onto the bridge"
 warn_about_network_manager "$IFACE"
 describe_bridge

 cat 1>&2 <<EOF
$TOOL: about to move $IFACE onto $BR.
       address(es): ${HOST_ADDRS[*]}
       default gateway: ${GATEWAY:-none}${ROUTE_METRIC:+ (metric $ROUTE_METRIC)}
       THE HOST LOSES ITS NETWORK FOR A FRACTION OF A SECOND.
EOF

 step link      "${IP_CMD[@]}" link add "$BR" type bridge                     || fail_step
 step mac       "${IP_CMD[@]}" link set "$BR" address "$MAC"                  || fail_step
 # The alias carries BOTH facts the system cannot otherwise tell a later
 # invocation: who claimed the bridge, and which card it took over.
 step alias     "${IP_CMD[@]}" link set "$BR" alias "$ALIAS_PREFIX:$OWNER_PID:$IFACE" || fail_step
 step bridge_up "${IP_CMD[@]}" link set "$BR" up                              || fail_step

 # The address goes onto the bridge BEFORE it leaves the card (see the header):
 # the host address is then never nowhere. The bridge has no port yet, so nothing
 # answers twice on the wire.
 for index in "${!HOST_ADDRS[@]}"; do
   # The metric follows the address too: it is what the kernel gives the prefix
   # route it derives from it, and the host had that route with a metric.
   # shellcheck disable=SC2086
   step "addr_add:$index" "${IP_CMD[@]}" addr add ${HOST_ADDRS[index]} dev "$BR" ${ROUTE_METRIC:+metric $ROUTE_METRIC} || fail_step
 done
 for index in "${!HOST_ADDRS[@]}"; do
   # The CIDR alone identifies the address; see undo_step.
   step "addr_del:$index" "${IP_CMD[@]}" addr del "${HOST_ADDRS[index]%% *}" dev "$IFACE" || fail_step
 done

 step enslave "${IP_CMD[@]}" link set "$IFACE" master "$BR" || fail_step

 # The metric goes onto the bridge's route as well: it is both what the host had
 # and where `down' will read it back from (see route_metric_of).
 if [[ -n $GATEWAY ]]; then
   if [[ -n $ROUTE_METRIC ]]; then
     step route "${IP_CMD[@]}" route add default via "$GATEWAY" dev "$BR" metric "$ROUTE_METRIC" || fail_step
   else
     step route "${IP_CMD[@]}" route add default via "$GATEWAY" dev "$BR" || fail_step
   fi
 fi

 cat 1>&2 <<EOF
$TOOL: $BR is up, $IFACE is one of its ports, and the host address moved onto it.
       Guests attached to $BR are now ON THE REAL LAN: real addresses (static or
       from the LAN's own DHCP server), real services, real neighbours.
EOF
 succeed
}

function describe_bridge {
 REPORT[interface]=$IFACE
 REPORT[mac]=$MAC
 REPORT[gateway]=$GATEWAY
 REPORT[metric]=$ROUTE_METRIC
 REPORT[addresses]=$(Array_to_json HOST_ADDRS)
}

# refuse_wireless: an access point associates ONE MAC address; a bridge puts
# several behind it, and the AP drops them. This is not a limitation we can work
# around, so it is a refusal, not a warning.
function refuse_wireless {
 if [[ -n $NETNS ]]; then return 0; fi   # /sys is not the namespace's, and a test card is never Wi-Fi
 if [[ -d /sys/class/net/$1/wireless || -e /sys/class/net/$1/phy80211 ]]; then
   fail E_WIRELESS "$1 is a Wi-Fi card: an access point refuses the several MAC addresses a bridge puts behind it. Use a NAT bridge instead (that one works over Wi-Fi)."
 fi
}

# NetworkManager is not an obstacle we can remove, but staying silent about it
# would be dishonest: it may reconfigure the card behind our back, and the
# address we move is a STATIC COPY -- no DHCP lease is renewed on the bridge.
function warn_about_network_manager {
 local state
 command -v nmcli >/dev/null 2>&1 || return 0
 state=$(nmcli -t -f GENERAL.STATE device show "$1" 2>/dev/null | head -n1) || true
 [[ -z $state || $state = *unmanaged* ]] && return 0
 Array_push WARNINGS "NetworkManager manages $1: it may reconfigure it behind our back. Consider marking it unmanaged while the LAN bridge is up."
 Array_push WARNINGS "the address is copied statically onto $BR: no DHCP lease is renewed there, so a long-lived lease may expire."
 echo "$TOOL: warning: NetworkManager manages $1 (see the report's warnings)." 1>&2
}

# --- down
#
# `down' unwinds what the SYSTEM says exists, not what this invocation built:
# after a crash there is no undo stack, and the bridge itself carries everything
# needed -- its ports, its address, its default route.

function do_down {
 local users pid index
 [[ -n $OWNER_PID ]] || OWNER_PID=$PPID
 require_pid "$OWNER_PID"
 resolve_binaries
 require_bridge "$BR"
 REPORT[bridge]=$BR
 REPORT[owner_pid]=$OWNER_PID

 if ! link_exists "$BR"; then
   REPORT[removed]=false
   REPORT_TEXT[message]="$BR does not exist, nothing to remove"
   echo "$TOOL: $BR does not exist -- nothing to remove." 1>&2
   succeed
 fi

 # THE difference with the NAT bridge: this one is shared. Somebody else's
 # virtual machines may be riding on it, and taking it down would take the HOST's
 # network with it.
 users=$(live_users "$BR" "$OWNER_PID")
 if [[ -n $users && $FORCE != 1 ]]; then
   Array_make remaining
   for pid in $users; do Array_push remaining "$pid"; done
   REPORT[removed]=false
   REPORT[kept]=true
   REPORT[users]=$(Array_to_json remaining)
   REPORT_TEXT[message]="$BR is still used by pid(s) ${remaining[*]}"
   echo "$TOOL: $BR is still in use by pid(s) ${remaining[*]} -- keeping it." 1>&2
   succeed
 fi

 set_physical_port "$BR"
 read_addresses "$BR"
 GATEWAY=$(gateway_of "$BR")
 # Read back from the bridge what `up' put there, the metric included: it is the
 # metric the card had before, and the one it must get back (see route_metric_of).
 ROUTE_METRIC=$(route_metric_of "$BR")
 if [[ ! $ROUTE_METRIC =~ ^[0-9]{1,10}$ ]] || [[ $ROUTE_METRIC = 0 ]]; then ROUTE_METRIC=""; fi
 REPORT[interface]=$IFACE
 REPORT[addresses]=$(Array_to_json HOST_ADDRS)
 REPORT[gateway]=$GATEWAY
 REPORT[metric]=$ROUTE_METRIC

 # Rebuild the undo stack in the order `up' would have built it, so that the LIFO
 # unwinding is the same, then let `rollback' do the work.
 Array_push UNDO link
 Array_push UNDO bridge_up
 if [[ -n $IFACE ]]; then
   require_iface "$IFACE"
   for index in "${!HOST_ADDRS[@]}"; do Array_push UNDO "addr_add:$index"; done
   for index in "${!HOST_ADDRS[@]}"; do Array_push UNDO "addr_del:$index"; done
   Array_push UNDO enslave
 fi
 [[ -n $GATEWAY ]] && Array_push UNDO route

 rollback

 if (( ${#LEFTOVERS[@]} > 0 )); then
   fail E_ROLLBACK_INCOMPLETE "$BR: ${#LEFTOVERS[@]} artefact(s) could not be removed"
 fi
 REPORT[removed]=true
 echo "$TOOL: $BR removed${IFACE:+, $IFACE has its address and its default route back}." 1>&2
 succeed
}

# --- status / gc

function do_status {
 resolve_binaries
 local port pid users
 Array_make ports
 Array_make user_entries
 REPORT[bridge]=$BR
 if ! link_exists "$BR"; then
   REPORT[exists]=false
   REPORT[ok]=true
   finish 0
 fi
 REPORT[exists]=true
 set_physical_port "$BR"
 read_addresses "$BR"
 GATEWAY=$(gateway_of "$BR")
 MAC=$(mac_of "$BR")
 describe_bridge
 for port in $(ports_of "$BR"); do Array_push ports "$port"; done
 REPORT[ports]=$(Array_to_json ports)
 users=$(live_users "$BR")
 for pid in $users; do
   Map_make user_entry pid "$pid" alive true
   Array_push user_entries "$(Map_to_json user_entry)"
 done
 REPORT[users]=$(Array_to_json user_entries)
 REPORT[alias]=$(alias_of "$BR")
 REPORT[ok]=true
 finish 0
}

# gc: remove the bridge if -- and only if -- nobody alive is using it any more.
# The alias stamped by `up' is what makes this safe for a process that has
# created the bridge but not yet attached its first tap.
function do_gc {
 resolve_binaries
 local users
 REPORT[bridge]=$BR
 if ! link_exists "$BR"; then
   REPORT[collected]=false
   echo "$TOOL: $BR does not exist -- nothing to collect." 1>&2
   REPORT[ok]=true
   finish 0
 fi
 users=$(live_users "$BR")
 if [[ -n $users ]]; then
   REPORT[collected]=false
   REPORT_TEXT[message]="$BR is used by live pid(s) $(echo $users | tr '\n' ' ')"
   echo "$TOOL: keeping $BR (live pid(s): $(echo $users | tr '\n' ' '))." 1>&2
   REPORT[ok]=true
   finish 0
 fi
 echo "$TOOL: collecting $BR (no live user left)." 1>&2
 FORCE=1
 do_down
}

# --- selftest: a whole fake host, inside network namespaces
#
# The destructive path of this script CANNOT be tried out on the machine that
# runs the test suite -- it moves the address of the card one is sitting on. So
# the test builds a host of its own:
#
#   ns_lan (the LAN and its gateway)  <-- veth -->  ns_host (a card, an address,
#   ns_guest (a virtual machine)      <-- veth -->  a default route: a whole host)
#
# and plays `up' and `down' INSIDE ns_host with --netns. What is proven is what
# matters: the gateway is still reachable after the migration, a guest attached
# to the bridge reaches the LAN through it (that is the whole point of a LAN
# bridge), and `down' gives the card back its address AND its default route.
#
# Like the netns harness of marionnet-natbridge.sh, none of this is in the
# sudoers rule, on purpose: it is a test scaffold, not a product path. Hence the
# interactive sudo (it may ask for a password).

function sudo_test_run { sudo -- "$@"; }

function do_selftest {
 resolve_binaries
 local ns_host ns_lan ns_guest hveth lveth gveth bveth net failures=0 rc=0
 ns_host="mnlanh$$"; ns_lan="mnlanl$$"; ns_guest="mnlang$$"
 # Interface names must fit in 15 characters: `vlan' + the pid + one letter.
 hveth="vlan$$h"; lveth="vlan$$l"; bveth="vlan$$b"
 # The guest end attached to the bridge is named EXACTLY as Tap_provider names
 # its taps -- `mtap<pid>-<n>'. Not cosmetic: it is what makes the port a
 # recognised user of the bridge, so the test exercises `live_users' and the
 # refusal to dismantle a bridge somebody is still riding on.
 gveth="${TAP_PREFIX}$$-1"
 net=10.99.99

 echo "== 1. building a fake host ($ns_host), a fake LAN ($ns_lan) and a guest ($ns_guest)" 1>&2
 {
   sudo_test_run "$IP" netns add "$ns_host" &&
   sudo_test_run "$IP" netns add "$ns_lan" &&
   sudo_test_run "$IP" netns add "$ns_guest" &&
   sudo_test_run "$IP" link add "$hveth" type veth peer name "$lveth" &&
   sudo_test_run "$IP" link set "$hveth" netns "$ns_host" &&
   sudo_test_run "$IP" link set "$lveth" netns "$ns_lan" &&
   sudo_test_run "$IP" -netns "$ns_host" link set lo up &&
   sudo_test_run "$IP" -netns "$ns_host" link set "$hveth" up &&
   sudo_test_run "$IP" -netns "$ns_host" addr add "$net.2/24" dev "$hveth" &&
   sudo_test_run "$IP" -netns "$ns_host" route add default via "$net.1" &&
   sudo_test_run "$IP" -netns "$ns_lan" link set lo up &&
   sudo_test_run "$IP" -netns "$ns_lan" link set "$lveth" up &&
   sudo_test_run "$IP" -netns "$ns_lan" addr add "$net.1/24" dev "$lveth"
 } || { echo "$TOOL: could not build the test host." 1>&2; failures=$((failures + 1)); }

 if (( failures == 0 )); then
   echo "== 2. before: the fake host reaches its gateway through its card" 1>&2
   sudo_test_run "$IP" netns exec "$ns_host" ping -c1 -W3 "$net.1" 1>&2 || failures=$((failures + 1))
 fi

 if (( failures == 0 )); then
   echo "== 3. the LAN bridge takes the card over (the real thing, in the namespace)" 1>&2
   "$0" up --netns "$ns_host" --interface "$hveth" --owner-pid $$ 1>&2 || failures=$((failures + 1))
 fi

 if (( failures == 0 )); then
   echo "== 4. after: the gateway is STILL reachable, now through $BR" 1>&2
   sudo_test_run "$IP" netns exec "$ns_host" ping -c1 -W3 "$net.1" 1>&2 || failures=$((failures + 1))
   sudo_test_run "$IP" -netns "$ns_host" -4 addr show dev "$BR" 1>&2 || true

   echo "== 5. a guest attached to $BR is on the LAN (that is the whole point)" 1>&2
   {
     sudo_test_run "$IP" -netns "$ns_host" link add "$gveth" type veth peer name "$bveth" &&
     sudo_test_run "$IP" -netns "$ns_host" link set "$gveth" master "$BR" &&
     sudo_test_run "$IP" -netns "$ns_host" link set "$gveth" up &&
     sudo_test_run "$IP" -netns "$ns_host" link set "$bveth" netns "$ns_guest" &&
     sudo_test_run "$IP" -netns "$ns_guest" link set lo up &&
     sudo_test_run "$IP" -netns "$ns_guest" link set "$bveth" up &&
     sudo_test_run "$IP" -netns "$ns_guest" addr add "$net.3/24" dev "$bveth" &&
     sudo_test_run "$IP" netns exec "$ns_guest" ping -c1 -W3 "$net.1"
   } 1>&2 || { echo "$TOOL: the guest could not reach the LAN through $BR." 1>&2; failures=$((failures + 1)); }

   echo "== 6. a bridge somebody is riding on is NOT dismantled ($gveth belongs to a live pid)" 1>&2
   rc=0
   "$0" down --netns "$ns_host" --owner-pid 1 2>/dev/null | jq -e '.ok and .kept and (.removed | not)' >/dev/null || rc=1
   if (( rc != 0 )); then
     echo "$TOOL: down should have KEPT the bridge (a live user has a tap on it)." 1>&2
     failures=$((failures + 1))
   fi
 fi

 echo "== 7. tearing the bridge down and giving the card back" 1>&2
 "$0" down --netns "$ns_host" --owner-pid $$ --force 1>&2 || failures=$((failures + 1))

 echo "== 8. asserting that the fake host is exactly as it was" 1>&2
 if sudo_test_run "$IP" -netns "$ns_host" link show "$BR" &>/dev/null; then
   Array_push LEFTOVERS "bridge $BR"; failures=$((failures + 1))
 fi
 rc=0
 sudo_test_run "$IP" -netns "$ns_host" -4 -oneline addr show dev "$hveth" 2>/dev/null \
   | grep -qF "$net.2/24" || rc=1
 if (( rc != 0 )); then
   Array_push LEFTOVERS "the card did not get its address back"; failures=$((failures + 1))
 fi
 rc=0
 sudo_test_run "$IP" -netns "$ns_host" -4 route show default 2>/dev/null \
   | grep -qF "via $net.1" || rc=1
 if (( rc != 0 )); then
   Array_push LEFTOVERS "the card did not get its default route back"; failures=$((failures + 1))
 fi
 if (( failures == 0 )); then
   sudo_test_run "$IP" netns exec "$ns_host" ping -c1 -W3 "$net.1" 1>&2 || {
     Array_push LEFTOVERS "the restored card cannot reach the gateway"; failures=$((failures + 1)); }
 fi

 echo "== 9. removing the scaffold" 1>&2
 sudo_test_run "$IP" netns del "$ns_guest" >/dev/null 2>&1 || true
 sudo_test_run "$IP" netns del "$ns_host"  >/dev/null 2>&1 || true
 sudo_test_run "$IP" netns del "$ns_lan"   >/dev/null 2>&1 || true

 REPORT[bridge]=$BR
 if (( failures == 0 )); then
   echo "$TOOL: SELFTEST PASSED (guest on the LAN through the bridge, fake host restored, real host untouched)." 1>&2
   REPORT[ok]=true
   finish 0
 fi
 echo "$TOOL: SELFTEST FAILED." 1>&2
 REPORT[ok]=false
 REPORT[error]=E_INTERNAL
 REPORT_TEXT[message]="$failures leg(s) of the selftest failed"
 finish 1
}

# --- The sudoers material
#
# THE source of the privileged command list: bin/scripts/marionnet-sudoers.sh
# derives block (c) from this, it does not maintain a second copy.

# --- check-privileges: can we run our privileged commands WITHOUT a password?
#
# The OCaml side (bin/lan_bridge_host.ml, episode 7b) needs that answer before it
# offers to ask the user for a password, and `status' cannot give it: status
# reads the host with an UNPRIVILEGED `ip', so it succeeds exactly the same
# whether block (c) is installed or not.
#
# The probe follows the discipline of bin/tap_provider.ml (`ip tuntap del' on a
# name that cannot designate a real tap): a REAL command from our own list,
# covered by the rule, with no effect on anything. Here it is `ip link del
# ${BRIDGE_PREFIX}999' -- a bridge we never create, ours being always $BR --
# matched by the ${BRIDGE_PREFIX}* pattern of block (c).
#
# Unlike the tap probe, deleting a device that does not exist FAILS (rc 1), so
# the verdict cannot be read from the exit status: what tells "sudo let it
# through" from "sudo refused" is WHICH of the two wrote the message. Hence
# LC_ALL=C -- sudo's diagnostics are translated, iproute2's are not -- and a
# verdict read from iproute2's own wording.
#
# `sudo -n -l <command>' is NOT an alternative: on an ordinary desktop
# (%sudo ALL=(ALL:ALL) ALL) it answers "allowed" even with no rule of ours
# installed, and the `sudo -n' that follows then asks for a password (measured,
# see the comment in tap_provider.ml).
function do_check_privileges {
 resolve_binaries
 local probe="${BRIDGE_PREFIX}999" out rc=0
 require_bridge "$probe"
 REPORT[bridge]=$BR
 REPORT[probe]=$probe
 # A device of that name would be somebody else's: we must not delete it, and we
 # have no other harmless command to ask the question with.
 if link_exists "$probe"; then
   REPORT[privileged]=false
   REPORT_TEXT[message]="$probe exists on this host: refusing to use it as a probe"
   REPORT[ok]=true
   finish 0
 fi
 out=$(LC_ALL=C sudo -n -- "$IP" link del "$probe" 2>&1) || rc=$?
 if [[ $rc = 0 || $out == *"Cannot find device"* ]]; then
   REPORT[privileged]=true
   REPORT_TEXT[message]="the privileged commands of the LAN bridge run without a password"
 else
   REPORT[privileged]=false
   REPORT_TEXT[message]="$out"
 fi
 REPORT[ok]=true
 finish 0
}

function do_print_privileged_commands {
 resolve_binaries
 Array_make commands \
   "$IP link add <BR> type bridge" \
   "$IP link del <BR>" \
   "$IP link set <BR> address <MAC>" \
   "$IP link set <BR> alias ${ALIAS_PREFIX}:<PID>:<IF>" \
   "$IP link set <BR> up" \
   "$IP link set <BR> down" \
   "$IP addr add <CIDR> [brd <ADDR>] dev <BR> [metric <N>]" \
   "$IP addr del <CIDR> dev <BR>" \
   "$IP route add default via <GW> dev <BR> [metric <N>]" \
   "$IP route del default via <GW> dev <BR> [metric <N>]" \
   "$IP link set <IF> master <BR>" \
   "$IP link set <IF> nomaster" \
   "$IP addr del <CIDR> dev <IF>" \
   "$IP addr add <CIDR> [brd <ADDR>] dev <IF> [metric <N>]" \
   "$IP route add default via <GW> dev <IF> [metric <N>]"
 REPORT[commands]=$(Array_to_json commands)
 REPORT[bridge_pattern]="${BRIDGE_PREFIX}*"
 REPORT[alias_prefix]=$ALIAS_PREFIX
 REPORT[ok]=true
 cat 1>&2 <<EOF
# Privileged commands used by the LAN bridge (option B).
# <BR> is $BR, <IF> the host's own card, <CIDR>/<GW>/<MAC> its address, gateway
# and hardware address, <N> the metric that default route already had (it is
# carried over so that restoring the route cannot leave a duplicate one -- see
# route_metric_of). The bracketed tails are optional arguments, and the sudoers
# rule below covers them because a \`*' there matches several words, exactly as it
# already does for \`[brd <ADDR>]' (measured against the installed block (c)).
# Already covered by the existing tap rule ($IP link set
# ${TAP_PREFIX}* *), nothing to add for the attachment itself:
#   $IP link set ${TAP_PREFIX}<pid>-<n> master <BR>
$(printf '%s\n' "${commands[@]}")
#
# READ THIS BEFORE TURNING THE LAST THREE INTO A SUDOERS RULE: they name the
# HOST's card, which has no fixed name, so they cannot be narrowed to a device
# pattern the way the <BR> ones can. The grant they form says, in plain words:
# "this user may reconfigure the IPv4 addressing of this host". That IS the
# feature -- which is why it is a separate, opt-in block, asked for from the GUI
# at the moment it is needed, and never granted at install time.
#
# Test harness only (selftest), NOT part of what Marionnet needs:
#   $IP netns add/del/exec <NS> ...
#   $IP link add <VETH> type veth peer name <PEER>, $IP -netns <NS> ...
EOF
 finish 0
}

# --- Usage and argument parsing

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL up     [OPTION]...        # build the LAN bridge on the host's card (idempotent)
       $TOOL down   [OPTION]...        # give the card back, if nobody else is using it
       $TOOL status [OPTION]...        # what exists, and who is using it
       $TOOL gc                        # remove it if no live process uses it any more
       $TOOL check-privileges          # can we run our commands without a password?
                                       #   (i.e. is block (c) of the sudoers rule in place)
       $TOOL selftest                  # the whole thing, played in network namespaces
                                       #   (MAY ASK FOR A PASSWORD: its netns scaffold is
                                       #   test-only and not in the sudoers rule, on purpose)
       $TOOL print-privileged-commands # the sudo commands used, for the sudoers rule

There is ONE LAN bridge per host, called $BR: a network card has exactly one
master, so several Marionnet processes share it -- \`down' only dismantles it
when no live process has a tap on it any more.

Options:
  --interface IF      build the bridge on IF (default: the card carrying the
                      IPv4 default route; a Wi-Fi card is refused)
  --owner-pid PID     the pid claiming the bridge; it is stamped in the bridge
                      alias (${ALIAS_PREFIX}:PID:CARD), which is what keeps
                      \`gc' from collecting a bridge whose owner is alive but has
                      not attached a tap yet. Default: the caller, \$PPID.
  --force             \`down': dismantle even if other processes are using it
  --dry-run           print the report and the commands, change nothing
  --sudo-interactive  use \`sudo' instead of \`sudo -n' (allows a password prompt)
  --netns NS          TEST ONLY: run inside the network namespace NS (implies
                      --sudo-interactive; used by \`selftest')

Output: stdout is ALWAYS exactly one JSON object, on one line, success or
failure; stderr is the human trace; the exit status is 0 on success. The JSON
carries a symbolic error code among: E_USAGE, E_BAD_PID, E_BAD_IFACE,
E_BAD_ADDRESS, E_BAD_MAC, E_NO_IPROUTE2, E_SUDO_DENIED, E_NO_DEFAULT_ROUTE,
E_AMBIGUOUS_ROUTE, E_WIRELESS, E_ALREADY_ENSLAVED, E_NO_ADDRESS,
E_ROLLBACK_INCOMPLETE, E_INTERNAL.

UNLIKE marionnet-natbridge.sh, THIS TOOL TOUCHES THE HOST'S OWN NETWORK: the
card is enslaved to the bridge and its address and default route are moved
there. The host loses its network for a fraction of a second, and a failure at
any step is rolled back to the state found on entry.
EOF
}

function parse_options {
 while (( $# > 0 )); do
   case $1 in
     --owner-pid)   OWNER_PID=${2:-}; require_pid "$OWNER_PID"; shift 2 ;;
     --interface)   FORCED_IFACE=${2:-}; require_iface "$FORCED_IFACE"; shift 2 ;;
     --netns)       NETNS=${2:-}
                    [[ $NETNS =~ ^[A-Za-z0-9_.-]+$ ]] || fail E_USAGE "--netns: '$NETNS' is not a namespace name"
                    SUDO_INTERACTIVE=1   # nothing in a namespace matches the sudoers rule
                    shift 2 ;;
     --force)            FORCE=1; shift ;;
     --dry-run)          DRY_RUN=1; shift ;;
     --sudo-interactive) SUDO_INTERACTIVE=1; shift ;;
     --fail-after)  FAIL_AFTER=${2:-}; shift 2 ;;   # test only
     *)             usage; fail E_USAGE "unexpected argument '$1'" ;;
   esac
 done
}

ACTION=${1:-}
shift || true
case $ACTION in
  up|down)   parse_options "$@"
             if [[ $ACTION = up ]]; then do_up; else do_down; fi ;;
  status)    parse_options "$@"; do_status ;;
  gc)        parse_options "$@"; do_gc ;;
  selftest)  parse_options "$@"; do_selftest ;;
  check-privileges) parse_options "$@"; do_check_privileges ;;
  print-privileged-commands) parse_options "$@"; do_print_privileged_commands ;;
  -h|--help) ACTION=help; usage; REPORT[ok]=true; finish 0 ;;
  *)         ACTION=${ACTION:-none}; usage; fail E_USAGE "unknown subcommand '$ACTION'" ;;
esac
