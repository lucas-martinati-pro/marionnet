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
# The "automatic private NAT bridge" of the `modernisation-world-bridge' work-
# stream (option A of docs/modernisation-world-bridge.md § 2.1): a bridge that
# Marionnet creates and destroys entirely by itself, giving its virtual machines
# access to the Internet WITHOUT EVER TOUCHING THE HOST INTERFACE. That is what
# makes the setup barrier disappear: until now an admin had to create
# MARIONNET_BRIDGE by hand, enslave the physical card and move the host address
# onto the bridge -- the last two being destructive (useful-scripts/prepare_bridge.sh).
#
# THIS SCRIPT IS THE IMPLEMENTATION, NOT A PROOF OF CONCEPT (it was one, at
# episode 2, under the name marionnet-natbridge-poc.sh in useful-scripts/). The
# OCaml side does NOT reimplement any of it: bin/nat_bridge.ml runs this command
# and reads its JSON. One sequence of `ip' and `iptables' calls, one source of
# truth -- including for the privileged command list, which
# `print-privileged-commands' publishes and bin/scripts/marionnet-sudoers.sh
# derives its rule from.
#
# --- THE OUTPUT CONTRACT (what the OCaml caller relies on) ---
#
#   stdout : EXACTLY ONE JSON object, on ONE line, on EVERY exit path, success
#            or failure. Nothing else is ever written there.
#   stderr : the human trace -- every privileged command is echoed before being
#            run. A tool that hides what it does to the host is worthless.
#            Never parsed.
#   status : 0 on success, non-zero on failure. The JSON also carries a symbolic
#            error code, because an `exit 1' does not say WHY.
#
# --- TRANSACTION ---
#
# Every successful mutating step pushes its own inverse on an undo stack. Any
# failure (including a signal, or an unexpected error caught by `trap ... ERR')
# unwinds that stack in LIFO order, and the report says honestly what could NOT
# be undone (`leftovers'), instead of claiming a clean rollback.
#
# --- WHY `set -eo pipefail' AND NOT `set -u' ---
#
# bashbricks is not nounset-clean (measured 2026-08-15 and again 2026-08-16:
# sourcing it under `set -u' aborts the shell at __bb_REPLACE_REFS, and ~59
# `local __bb_X' declarations are later tested as bare ${__bb_X}; the skill
# use-bashbricks documents this in gotchas.md § 13). So `set -u' is out.
# It is not the loss it looks like: `set -u' does NOT protect against the
# variable that is SET BUT EMPTY, which is precisely how a filtered command
# turns into a wildcard. The real guard is the explicit validator -- here
# require_pid / require_subnet / require_bridge, which every destructive
# command is preceded by, and whose regexps are anchored.
#
# What is deliberately NOT here: dnsmasq (guests get a static address; the POC
# proved they reach the Internet without DHCP) and IPv6.
#
# Naming and lifetime follow Tap_provider (bin/tap_provider.ml): every artefact
# carries the pid of the process that owns it -- the bridge is `mnbr<pid>' and
# every iptables rule carries the comment `marionnet-natbridge:mnbr<pid>' -- so
# `gc' can recognise, and only then remove, what a dead process left behind. The
# owner pid is NOT this script's pid (the script exits, the bridge must outlive
# it): it defaults to the caller's, and Marionnet passes its own with --owner-pid.
# ---------------------------------------------------------------------------

TOOL=$(basename "$0")

# --- bashbricks: sourced FIRST, with nounset off (see the header), then the
# --- shell options. The library is installed next to this script
# --- ($PREFIX/share/marionnet/scripts/, and mirrored into $PREFIX/bin/ by the
# --- Makefile) -- hence the very short probe list.

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

# --- Constants. BRIDGE_PREFIX and TAG_PREFIX are part of the contract with
# --- bin/nat_bridge.ml and with the sudoers rule: do not change them alone.

BRIDGE_PREFIX=mnbr
TAG_PREFIX=marionnet-natbridge

# Where we remember the one thing the system cannot tell us afterwards: whether
# WE turned ip_forward on (so that `down' only restores what `up' changed).
STATE_DIR=${MARIONNET_NATBRIDGE_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/marionnet-natbridge}

# Candidate /24 networks, tried in order. 172.23.0.0/16 is excluded on purpose:
# it belongs to the ghost network (GHOST_NETWORK_PREFIX in tap_provider.ml).
Array_make CANDIDATE_NETS \
  192.168.101 192.168.102 192.168.103 192.168.104 192.168.105 \
  192.168.106 192.168.107 192.168.108 192.168.109 192.168.110

# --- Mutable state of the current invocation

ACTION=""             # up | down | status | gc | selftest | ...
OWNER_PID=""          # the pid the artefacts are named after
BR=""                 # bridge name, mnbr<OWNER_PID>
NET=""                # the /24 prefix, e.g. 192.168.101
TAG=""                # the iptables comment, TAG_PREFIX:BR
FORCED_SUBNET=""      # --subnet
DRY_RUN=0             # --dry-run
FAIL_AFTER=""         # --fail-after LABEL (test only, see A8.4 of the plan)
SUDO_INTERACTIVE=0    # --sudo-interactive
LAST_ERROR=""         # diagnostic of the step that just failed
LAST_ERROR_CODE=""    # and the symbolic code that failure deserves

Map_make REPORT              # typed fields (booleans, numbers, JSON fragments)
Map_make REPORT_TEXT         # free text ONLY (see emit_report)
Array_make CREATED           # labels of the steps that succeeded
Array_make UNDO              # the same, as an undo stack
Array_make UNDONE            # labels successfully undone
Array_make LEFTOVERS         # labels we FAILED to undo -- the honest part
Array_make WARNINGS
REPORT_EMITTED=0

# --- The report
#
# Two maps, one call each, merged by jq. The split is not cosmetic: Map_to_json
# parses scalars by default (that is what turns ok=false into a JSON boolean,
# owner_pid into a number, and keeps an Array_to_json fragment an array), and
# that same parsing would turn an iptables message that merely LOOKS like JSON
# ("[1,2] not found") into a JSON array. Free text therefore goes through
# `Map_to_json -s' (stringify), which keeps it a string.
# Do NOT pre-escape with Json_escape_string: Map_to_json escapes internally, and
# doing both doubles the escaping (measured: `"' comes out as `\\"').

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

# succeed: the mirror image of `fail'.
function succeed {
 REPORT[ok]=true
 finish 0
}

# The safety net: an unexpected non-zero (set -e) or a signal must not leave the
# host half-configured, and must still honour the output contract.
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
# regexps, not `-n' tests: a non-empty but generic value is just as destructive
# as an empty one.

function require_pid {
 # Regexp_is_natural is `^(0|[1-9][0-9]*)$': it rejects the empty string, a
 # leading zero and any surrounding space. It accepts 0, which is not a pid.
 { Regexp_is_natural "${1:-}" && (( ${1:-0} >= 1 )); } \
   || fail E_BAD_PID "'${1:-}' is not a pid"
}

# No Regexp_is_* fits the two shapes below, and an anchored [[ =~ ]] is more
# direct than composing String_scanf: this is the "small native primitive" case.

function require_subnet {   # a /24 prefix: three decimal bytes, no trailing dot
 [[ ${1:-} =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]] \
   || fail E_BAD_SUBNET "'${1:-}' is not a /24 prefix such as 192.168.101"
}

function require_bridge {
 [[ ${1:-} =~ ^${BRIDGE_PREFIX}[1-9][0-9]*$ ]] \
   || fail E_INTERNAL "'${1:-}' is not one of our bridge names"
}

# --- Absolute binary paths: sudoers matches on the absolute path, and root's
# PATH is not the user's. Same probing discipline as bin/scripts/marionnet-sudoers.sh.
# Resolved lazily, so that a missing package is reported as JSON like anything else.

IP=""; IPTABLES=""; IPTABLES_SAVE=""; SYSCTL=""

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
 IPTABLES=$(binary_among E_NO_IPTABLES /usr/sbin/iptables /sbin/iptables /usr/bin/iptables)
 IPTABLES_SAVE=$(binary_among E_NO_IPTABLES /usr/sbin/iptables-save /sbin/iptables-save /usr/bin/iptables-save)
 # Absolute too: sudoers matches on the path, so `sysctl' bare would never match
 # the rule that marionnet-sudoers.sh installs.
 SYSCTL=$(binary_among E_NO_SYSCTL /usr/sbin/sysctl /sbin/sysctl /usr/bin/sysctl /bin/sysctl)
}

# --- Privileged execution
#
# `sudo -n' by default: this is a machine interface, and the scoped rule of
# bin/scripts/marionnet-sudoers.sh is what makes it work without a password.
# A human wanting the prompt passes --sudo-interactive.

function sudo_run {
 if [[ $SUDO_INTERACTIVE = 1 ]]; then sudo -- "$@"; else sudo -n -- "$@"; fi
}

# The `selftest' harness -- the veth pair and the network namespace that play the
# guest -- is NOT part of what Marionnet needs, and is deliberately absent from
# the sudoers rule (see print-privileged-commands). So `sudo -n' is refused for
# it, and it uses an interactive sudo instead: a human running `selftest' can be
# asked for a password. The product path being proven (the `up' and `down'
# sub-invocations) keeps `sudo -n' -- demonstrating that it needs no password is
# the whole point of the exercise.
function sudo_test_run { sudo -- "$@"; }

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

# fail_step: report the failure of the step that just ran, with the code IT
# decided. Guessing E_SUDO_DENIED at every call site would have made an injected
# test failure look like a sudo refusal.
function fail_step { fail "${LAST_ERROR_CODE:-E_INTERNAL}" "$LAST_ERROR"; }

# undo_step LABEL: the exact inverse of the step of that name. It must NEVER
# call `fail' (it runs from inside the rollback) and never abort the script.
function undo_step {
 local label=$1
 [[ $DRY_RUN = 1 ]] && return 0
 case $label in
   nat_masquerade)
     sudo_run "$IPTABLES" -t nat -D POSTROUTING -s "$NET.0/24" ! -o "$BR" \
              -m comment --comment "$TAG" -j MASQUERADE ;;
   forward_out)
     sudo_run "$IPTABLES" -D FORWARD -i "$BR" ! -o "$BR" \
              -m comment --comment "$TAG" -j ACCEPT ;;
   forward_in)
     sudo_run "$IPTABLES" -D FORWARD -o "$BR" -m conntrack --ctstate RELATED,ESTABLISHED \
              -m comment --comment "$TAG" -j ACCEPT ;;
   ip_forward)  sudo_run "$SYSCTL" -q -w net.ipv4.ip_forward=0 ;;
   link_up)     sudo_run "$IP" link set "$BR" down ;;
   addr)        sudo_run "$IP" addr del "$NET.1/24" dev "$BR" ;;
   link)        sudo_run "$IP" link del "$BR" ;;
   *)           return 1 ;;
 esac
}

# rollback: unwind the undo stack, LIFO. `link' being last is not an accident --
# deleting the link takes its address and its state with it, so undoing `addr'
# afterwards would fail and be reported as a leftover for nothing.
function rollback {
 local index label
 (( ${#UNDO[@]} == 0 )) && return 0
 trap - ERR   # inside the rollback a failing command is data, not an abort

 # The validators are inlined here rather than called: require_* calls `fail',
 # and `fail' calls this function -- the recursion would be unbounded. A name
 # we cannot validate is a name we refuse to build a destructive command from,
 # so everything left on the stack is declared a leftover, loudly.
 if [[ ! $BR =~ ^${BRIDGE_PREFIX}[1-9][0-9]*$ ]] \
    || { [[ -n $NET ]] && [[ ! $NET =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]]; }; then
   echo "$TOOL: REFUSING to roll back: bridge '$BR' / subnet '$NET' did not validate." 1>&2
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
   # The root cause stays in `error' (that is what the caller must act on);
   # the incomplete cleanup is reported by `leftovers' and this warning.
   Array_push WARNINGS E_ROLLBACK_INCOMPLETE
 else
   REPORT[rolled_back]=true
 fi
}

# --- Names and identities

function bridge_name  { echo "${BRIDGE_PREFIX}$1"; }
function tag_of       { echo "${TAG_PREFIX}:$1"; }
function state_file   { echo "$STATE_DIR/$1"; }
function link_exists  { "$IP" link show "$1" &>/dev/null; }
function pid_is_alive { [[ -d /proc/$1 ]]; }

# subnet_of BRIDGE: the /24 we gave it, read back from the system (so that
# `down' and `gc' work even if the state file is gone).
function subnet_of {
 "$IP" -4 -oneline addr show dev "$1" 2>/dev/null \
   | awk '{for(i=1;i<=NF;i++) if($i=="inet") {split($(i+1),a,"."); print a[1]"."a[2]"."a[3]; exit}}'
}

# free_subnet: the first candidate absent from the host's routes AND addresses.
# Skipping this check is how a NAT bridge silently steals the host's own LAN
# prefix and leaves the guests without Internet.
function free_subnet {
 local taken net
 taken=$("$IP" -4 route show; "$IP" -4 -oneline addr show)
 for net in "${CANDIDATE_NETS[@]}"; do
   if ! grep -qF "$net." <<<"$taken"; then echo "$net"; return 0; fi
 done
 fail E_NO_FREE_SUBNET "all candidate networks (${CANDIDATE_NETS[*]}) are already in use here"
}

# --- up

function do_up {
 local ip_forward_was
 require_pid "$OWNER_PID"
 resolve_binaries
 BR=$(bridge_name "$OWNER_PID"); require_bridge "$BR"
 TAG=$(tag_of "$BR")
 REPORT[bridge]=$BR
 REPORT[owner_pid]=$OWNER_PID

 if link_exists "$BR"; then
   # Idempotent: an existing bridge of ours is a success, not an error, and the
   # caller still gets the addressing it needs.
   NET=$(subnet_of "$BR")
   require_subnet "$NET"
   describe_network
   REPORT_TEXT[message]="$BR already exists, nothing to do"
   echo "$TOOL: $BR already exists (subnet $NET.0/24) -- nothing to do." 1>&2
   succeed
 fi

 if [[ -n $FORCED_SUBNET ]]; then NET=$FORCED_SUBNET; else NET=$(free_subnet); fi
 require_subnet "$NET"
 ip_forward_was=$(cat /proc/sys/net/ipv4/ip_forward)
 REPORT[ip_forward_was]=$ip_forward_was
 describe_network

 # The bridge first, then forwarding, then NAT. Each step records its inverse.
 step link    "$IP" link add "$BR" type bridge            || fail_step
 step addr    "$IP" addr add "$NET.1/24" dev "$BR"        || fail_step
 step link_up "$IP" link set "$BR" up                     || fail_step
 if [[ $ip_forward_was != 1 ]]; then
   step ip_forward "$SYSCTL" -q -w net.ipv4.ip_forward=1     || fail_step
 fi
 # These two FORWARD rules are NOT redundant with the masquerade: on a host
 # running Docker the FORWARD policy is DROP, and a NAT rule alone would
 # translate packets that are then dropped.
 step nat_masquerade "$IPTABLES" -t nat -A POSTROUTING -s "$NET.0/24" ! -o "$BR" \
      -m comment --comment "$TAG" -j MASQUERADE           || fail_step
 step forward_out "$IPTABLES" -A FORWARD -i "$BR" ! -o "$BR" \
      -m comment --comment "$TAG" -j ACCEPT               || fail_step
 step forward_in "$IPTABLES" -A FORWARD -o "$BR" -m conntrack --ctstate RELATED,ESTABLISHED \
      -m comment --comment "$TAG" -j ACCEPT               || fail_step

 if [[ $DRY_RUN != 1 ]]; then
   mkdir -p "$STATE_DIR"
   printf 'SUBNET=%s\nIP_FORWARD_WAS=%s\nOWNER_PID=%s\n' \
     "$NET" "$ip_forward_was" "$OWNER_PID" > "$(state_file "$BR")"
 fi

 cat 1>&2 <<EOF
$TOOL: $BR is up on $NET.0/24 (host side $NET.1), NAT to the outside enabled.
       Guests: address in $NET.0/24, default route $NET.1.
       Note: a bridge with no port yet stays NO-CARRIER; it comes up when the
       first tap is attached to it.
EOF
 succeed
}

# The addressing the caller needs in order to configure its guests.
function describe_network {
 REPORT[subnet]=$NET
 REPORT[prefix_length]=24
 REPORT[host_address]="$NET.1"
 REPORT[gateway]="$NET.1"
 REPORT[guest_range]="$NET.2-$NET.254"
}

# --- down
#
# `down' is `rollback' applied to what the SYSTEM says exists, rather than to
# what this invocation built: after a crash there is no undo stack to unwind,
# and the tagged rules plus the bridge name are enough to find everything.

function do_down {
 require_pid "$OWNER_PID"
 resolve_binaries
 BR=$(bridge_name "$OWNER_PID"); require_bridge "$BR"
 TAG=$(tag_of "$BR")
 REPORT[bridge]=$BR
 REPORT[owner_pid]=$OWNER_PID

 NET=$(subnet_of "$BR" || true)
 local state; state=$(state_file "$BR")
 local ip_forward_was=1
 if [[ -r $state ]]; then
   # shellcheck disable=SC1090
   source "$state"
   [[ -n $NET ]] || NET=${SUBNET:-}
   ip_forward_was=${IP_FORWARD_WAS:-1}
 fi

 local rules_remain=0
 if sudo_run "$IPTABLES_SAVE" 2>/dev/null | grep -qF -- "$TAG"; then rules_remain=1; fi

 if [[ -z $NET ]] && ! link_exists "$BR"; then
   if [[ $rules_remain = 1 ]]; then
     sudo_run "$IPTABLES_SAVE" | grep -F -- "$TAG" 1>&2 || true
     fail E_INTERNAL "$BR is gone but rules tagged $TAG remain, and no subnet is known to rebuild the delete commands (they are listed on stderr)"
   fi
   REPORT_TEXT[message]="nothing to remove for pid $OWNER_PID"
   echo "$TOOL: nothing to remove for pid $OWNER_PID." 1>&2
   succeed
 fi

 # Rebuild the undo stack in the order `up' would have built it, so that the
 # LIFO unwinding is the same, then let `rollback' do the work.
 if link_exists "$BR"; then
   Array_push UNDO link
   [[ -n $NET ]] && Array_push UNDO addr
   Array_push UNDO link_up
 fi
 [[ $ip_forward_was = 0 ]] && Array_push UNDO ip_forward
 if [[ $rules_remain = 1 && -n $NET ]]; then
   Array_push UNDO nat_masquerade
   Array_push UNDO forward_out
   Array_push UNDO forward_in
 fi

 rollback
 [[ $DRY_RUN = 1 ]] || rm -f "$state"

 if (( ${#LEFTOVERS[@]} > 0 )); then
   fail E_ROLLBACK_INCOMPLETE "$BR: ${#LEFTOVERS[@]} artefact(s) could not be removed"
 fi
 echo "$TOOL: $BR removed." 1>&2
 succeed
}

# --- status / gc

function all_bridges {
 "$IP" -oneline link show type bridge 2>/dev/null \
   | awk -F': ' -v p="^${BRIDGE_PREFIX}[0-9]+$" '$2 ~ p {print $2}'
}

function do_status {
 resolve_binaries
 local bridge pid list
 Array_make entries
 if [[ -n $OWNER_PID ]]; then
   require_pid "$OWNER_PID"
   list=$(bridge_name "$OWNER_PID")
 else
   list=$(all_bridges)
 fi
 REPORT[ip_forward]=$(cat /proc/sys/net/ipv4/ip_forward)
 for bridge in $list; do
   link_exists "$bridge" || continue
   pid=${bridge#"$BRIDGE_PREFIX"}
   Map_make entry \
     bridge     "$bridge" \
     owner_pid  "$pid" \
     subnet     "$(subnet_of "$bridge")" \
     owner_alive "$(pid_is_alive "$pid" && echo true || echo false)" \
     ports      "$(ports_of_json "$bridge")"
   Array_push entries "$(Map_to_json entry)"
 done
 REPORT[bridges]=$(Array_to_json entries)
 REPORT[ok]=true
 finish 0
}

function ports_of_json {
 Array_make ports
 local port
 for port in $("$IP" -oneline link show master "$1" 2>/dev/null | awk -F': ' '{print $2}'); do
   Array_push ports "$port"
 done
 Array_to_json ports
}

function do_gc {
 resolve_binaries
 local bridge pid
 Array_make collected
 Array_make kept
 for bridge in $(all_bridges); do
   pid=${bridge#"$BRIDGE_PREFIX"}
   if pid_is_alive "$pid"; then
     Array_push kept "$bridge"
     echo "$TOOL: keeping $bridge (pid $pid is alive)." 1>&2
   else
     echo "$TOOL: collecting $bridge (pid $pid is gone)." 1>&2
     # A sub-invocation, so that one unremovable artefact does not abort the
     # sweep and does not pollute this report's undo bookkeeping.
     # NOT ${DRY_RUN:+...}: DRY_RUN is 0 or 1, and "0" is non-empty.
     local dry_run_flag=(); [[ $DRY_RUN = 1 ]] && dry_run_flag=(--dry-run)
     if "$0" down --owner-pid "$pid" "${dry_run_flag[@]}" >/dev/null 2>&1; then
       Array_push collected "$bridge"
     else
       Array_push LEFTOVERS "$bridge"
     fi
   fi
 done
 REPORT[collected]=$(Array_to_json collected)
 REPORT[kept]=$(Array_to_json kept)
 if (( ${#LEFTOVERS[@]} > 0 )); then
   fail E_ROLLBACK_INCOMPLETE "${#LEFTOVERS[@]} dead bridge(s) could not be collected"
 fi
 REPORT[ok]=true
 finish 0
}

# --- selftest: a network namespace plays the guest

function do_selftest {
 resolve_binaries
 local ns veth peer failures=0
 OWNER_PID=$$
 ns="mnbrns$$"; veth="vnbr$$a"; peer="vnbr$$b"

 echo "== 1. bringing the NAT bridge up" 1>&2
 # A sub-invocation: `up' owns its own transaction and its own report.
 local up_json
 up_json=$("$0" up --owner-pid $$ ${FORCED_SUBNET:+--subnet "$FORCED_SUBNET"}) \
   || fail E_INTERNAL "the 'up' leg failed: $up_json"
 BR=$(jq -r '.bridge' <<<"$up_json")
 NET=$(jq -r '.subnet' <<<"$up_json")
 require_bridge "$BR"; require_subnet "$NET"
 TAG=$(tag_of "$BR")

 echo "== 2. attaching a netns guest ($ns) to $BR" 1>&2
 {
   sudo_test_run "$IP" link add "$veth" type veth peer name "$peer" &&
   sudo_test_run "$IP" link set "$veth" master "$BR" &&
   sudo_test_run "$IP" link set "$veth" up &&
   sudo_test_run "$IP" netns add "$ns" &&
   sudo_test_run "$IP" link set "$peer" netns "$ns" &&
   sudo_test_run "$IP" -netns "$ns" addr add "$NET.2/24" dev "$peer" &&
   sudo_test_run "$IP" -netns "$ns" link set lo up &&
   sudo_test_run "$IP" -netns "$ns" link set "$peer" up &&
   sudo_test_run "$IP" -netns "$ns" route add default via "$NET.1"
 } || { echo "$TOOL: could not build the test guest." 1>&2; failures=$((failures + 1)); }

 if (( failures == 0 )); then
   echo "== 3. from the guest: ICMP to the outside" 1>&2
   sudo_test_run "$IP" netns exec "$ns" ping -c1 -W3 9.9.9.9 1>&2 || failures=$((failures + 1))
   echo "== 4. from the guest: UDP/53 to the outside" 1>&2
   if command -v dig >/dev/null; then
     sudo_test_run "$IP" netns exec "$ns" dig +short +time=3 +tries=1 @9.9.9.9 example.org 1>&2 \
       || failures=$((failures + 1))
   else
     Array_push WARNINGS "dig is not installed, the DNS leg was skipped (install dnsutils)"
     echo "$TOOL: dig not installed, skipping the DNS leg." 1>&2
   fi
 fi

 echo "== 5. tearing everything down" 1>&2
 sudo_test_run "$IP" netns del "$ns" >/dev/null 2>&1 || true
 if link_exists "$veth"; then sudo_test_run "$IP" link del "$veth" >/dev/null 2>&1 || true; fi
 "$0" down --owner-pid $$ >/dev/null || failures=$((failures + 1))

 echo "== 6. asserting that nothing survives" 1>&2
 if link_exists "$BR"; then
   Array_push LEFTOVERS "bridge $BR"; failures=$((failures + 1))
 fi
 if "$IP" netns list 2>/dev/null | grep -qw "$ns"; then
   Array_push LEFTOVERS "netns $ns"; failures=$((failures + 1))
 fi
 if sudo_run "$IPTABLES_SAVE" 2>/dev/null | grep -qF -- "$TAG"; then
   Array_push LEFTOVERS "iptables rules tagged $TAG"; failures=$((failures + 1))
 fi

 REPORT[bridge]=$BR
 REPORT[subnet]=$NET
 REPORT[ip_forward]=$(cat /proc/sys/net/ipv4/ip_forward)
 if (( failures == 0 )); then
   echo "$TOOL: SELFTEST PASSED (guest reached the Internet, host untouched)." 1>&2
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
# derives its rule from this, it does not maintain a second copy.

function do_print_privileged_commands {
 resolve_binaries
 Array_make commands \
   "$IP link add <BR> type bridge" \
   "$IP addr add <NET>.1/24 dev <BR>" \
   "$IP link set <BR> up" \
   "$IP link set <BR> down" \
   "$IP addr del <NET>.1/24 dev <BR>" \
   "$IP link del <BR>" \
   "$SYSCTL -q -w net.ipv4.ip_forward=1" \
   "$SYSCTL -q -w net.ipv4.ip_forward=0" \
   "$IPTABLES -t nat -{A,D} POSTROUTING -s <NET>.0/24 ! -o <BR> -m comment --comment <TAG> -j MASQUERADE" \
   "$IPTABLES -{A,D} FORWARD -i <BR> ! -o <BR> -m comment --comment <TAG> -j ACCEPT" \
   "$IPTABLES -{A,D} FORWARD -o <BR> -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment <TAG> -j ACCEPT" \
   "$IPTABLES_SAVE"
 REPORT[commands]=$(Array_to_json commands)
 REPORT[bridge_pattern]="${BRIDGE_PREFIX}*"
 REPORT[tag_prefix]=$TAG_PREFIX
 REPORT[ok]=true
 cat 1>&2 <<EOF
# Privileged commands used by the automatic private NAT bridge (option A).
# <BR> is ${BRIDGE_PREFIX}<pid>, <NET> the chosen /24 prefix, <TAG> ${TAG_PREFIX}:<BR>.
# Already covered by the existing tap rule ($IP link set mtap* *), nothing to add
# for the attachment itself:
#   $IP link set mtap<pid>-<n> master <BR>
$(printf '%s\n' "${commands[@]}")
#
# Test harness only (selftest), NOT part of what Marionnet needs:
#   $IP link add/del <VETH> type veth peer name <PEER>
#   $IP netns add/del/exec <NS> ...
EOF
 finish 0
}

# --- Usage and argument parsing

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL up     [OPTION]...        # create the NAT bridge (idempotent)
       $TOOL down   [OPTION]...        # remove it and its rules (idempotent)
       $TOOL status [OPTION]...        # what exists, for one pid or for all
       $TOOL gc                        # remove the artefacts of DEAD owners only
       $TOOL selftest                  # up + a netns guest + ping/DNS + down + assert clean
                                       #   (MAY ASK FOR A PASSWORD: its veth/netns guest is
                                       #   test-only and not in the sudoers rule, on purpose)
       $TOOL print-privileged-commands # the sudo commands used, for the sudoers rule

Options:
  --owner-pid PID     name the artefacts after PID (default: the caller, \$PPID).
                      Marionnet passes its own pid, so that the bridge lives and
                      dies with it.
  --subnet PREFIX     force the /24, e.g. --subnet 192.168.101 (default: the
                      first candidate free of the host's routes and addresses)
  --candidates A,B,C  replace the default candidate list
  --state-dir DIR     where to remember whether WE turned ip_forward on
                      (default: \$MARIONNET_NATBRIDGE_STATE_DIR or $STATE_DIR)
  --dry-run           print the report and the commands, change nothing
  --sudo-interactive  use \`sudo' instead of \`sudo -n' (allows a password prompt)

Output: stdout is ALWAYS exactly one JSON object, on one line, success or
failure; stderr is the human trace; the exit status is 0 on success. The JSON
carries a symbolic error code among: E_USAGE, E_BAD_PID, E_BAD_SUBNET,
E_NO_IPROUTE2, E_NO_IPTABLES, E_NO_SYSCTL, E_SUDO_DENIED, E_NO_FREE_SUBNET,
E_ROLLBACK_INCOMPLETE, E_INTERNAL.

The host interface, its address and its routes are NEVER touched: that is the
whole point. Everything created here is undone by \`down' (and by \`gc' after a
crash).
EOF
}

function parse_options {
 while (( $# > 0 )); do
   case $1 in
     --owner-pid)   OWNER_PID=${2:-}; require_pid "$OWNER_PID"; shift 2 ;;
     --subnet)      FORCED_SUBNET=${2:-}; require_subnet "$FORCED_SUBNET"; shift 2 ;;
     --candidates)  String_split "${2:-}" "," CANDIDATE_NETS
                    (( ${#CANDIDATE_NETS[@]} > 0 )) || fail E_USAGE "--candidates: empty list"
                    local net; for net in "${CANDIDATE_NETS[@]}"; do require_subnet "$net"; done
                    shift 2 ;;
     --state-dir)   STATE_DIR=${2:-}
                    [[ -n $STATE_DIR ]] || fail E_USAGE "--state-dir: empty path"
                    shift 2 ;;
     --dry-run)          DRY_RUN=1; shift ;;
     --sudo-interactive) SUDO_INTERACTIVE=1; shift ;;
     --fail-after)  FAIL_AFTER=${2:-}; shift 2 ;;   # test only, see the plan § A8.4
     *)             usage; fail E_USAGE "unexpected argument '$1'" ;;
   esac
 done
}

ACTION=${1:-}
shift || true
case $ACTION in
  up|down)   parse_options "$@"; [[ -n $OWNER_PID ]] || OWNER_PID=$PPID
             if [[ $ACTION = up ]]; then do_up; else do_down; fi ;;
  status)    parse_options "$@"; do_status ;;
  gc)        parse_options "$@"; do_gc ;;
  selftest)  parse_options "$@"; do_selftest ;;
  print-privileged-commands) parse_options "$@"; do_print_privileged_commands ;;
  -h|--help) ACTION=help; usage; REPORT[ok]=true; finish 0 ;;
  *)         ACTION=${ACTION:-none}; usage; fail E_USAGE "unknown subcommand '$ACTION'" ;;
esac
