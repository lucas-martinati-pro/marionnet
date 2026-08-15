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
# Proof of concept for the "automatic private NAT bridge" (chantier
# `modernisation-world-bridge', option A of docs/modernisation-world-bridge.md
# § 2.1). NO OCaml is involved: this bench proves, on a real host, that a bridge
# entirely created and destroyed by Marionnet gives its virtual machines access
# to the Internet WITHOUT EVER TOUCHING THE HOST INTERFACE -- which is what makes
# the setup barrier disappear (today an admin must create MARIONNET_BRIDGE, and
# then enslave the physical card and move the host address onto the bridge: the
# last two are destructive, see useful-scripts/prepare_bridge.sh, hence manual).
#
# It is also the SOURCE of the privileged command list that episode 3 will add to
# bin/scripts/marionnet-sudoers.sh: `print-privileged-commands' prints it.
#
# What is deliberately NOT here: dnsmasq (guests get a static address in the POC;
# whether Marionnet needs a DHCP server on the NAT bridge is to be decided later),
# and IPv6.
#
# Naming and lifetime follow Tap_provider (bin/tap_provider.ml): every artefact
# carries the pid of the process that owns it -- the bridge is `mnbr<pid>' and
# every iptables rule carries the comment `marionnet-natbridge:mnbr<pid>' -- so
# `gc' can recognise, and only then remove, what a dead process left behind. The
# owner pid is NOT this script's pid (the script exits, the bridge must outlive
# it): it defaults to the caller's, and the real bench passes Marionnet's with
# --owner-pid.
#
# Plain Bash here, NOT bashbricks, although the library is vendored in this
# repository and is the rule for new scripts: bashbricks is not `set -u'-safe
# (measured 2026-08-15 -- `source bashbricks.sh' under `set -u' aborts at
# __bb_REPLACE_REFS, and `Array_make' at __bb_PLUS), while this script runs
# privileged commands and wants `set -euo pipefail'. It has no collection to
# speak of anyway: it is a sequence of `ip' and `iptables' calls.
# ---------------------------------------------------------------------------

set -euo pipefail

TOOL=$(basename "$0")

# MUST agree with bin/tap_provider.ml when episode 3 moves this to OCaml:
BRIDGE_PREFIX=mnbr
TAG_PREFIX=marionnet-natbridge

# Where we remember the one thing the system cannot tell us afterwards: whether
# WE turned ip_forward on (so that `down' only restores what `up' changed).
STATE_DIR=${MARIONNET_NATBRIDGE_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/marionnet-natbridge}

# Candidate /24 networks, tried in order. 172.23.0.0/16 is excluded on purpose:
# it belongs to the ghost network (GHOST_NETWORK_PREFIX in tap_provider.ml).
CANDIDATE_NETS=(192.168.101 192.168.102 192.168.103 192.168.104 192.168.105 \
                192.168.106 192.168.107 192.168.108 192.168.109 192.168.110)

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL up     [--owner-pid PID]   # create the NAT bridge (idempotent)
       $TOOL down   [--owner-pid PID]   # remove it and its rules (idempotent)
       $TOOL status [--owner-pid PID]   # show what exists, for that pid or all
       $TOOL gc                         # remove the artefacts of DEAD owners only
       $TOOL selftest                   # up + a netns guest + ping/DNS + down + assert clean
       $TOOL print-privileged-commands  # the sudo commands used, for the sudoers rule

PID defaults to the caller's process (\$PPID). Pass Marionnet's pid to have the
bridge live and die with it, then point MARIONNET_BRIDGE at ${BRIDGE_PREFIX}<PID>.

The host interface, its address and its routes are NEVER touched: this is the
whole point. Everything created here is undone by \`down' (and by \`gc' after a
crash).
EOF
}

# --- Absolute binary paths: sudoers matches on the absolute path, and root's
# PATH is not the user's. Same probing discipline as bin/scripts/marionnet-sudoers.sh.

function binary_among {
 local i
 for i in "$@"; do [[ -x $i ]] && { echo "$i"; return 0; }; done
 echo "$TOOL: none of $* is executable (missing package?)" 1>&2
 return 1
}

IP=$(binary_among /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip)
IPTABLES=$(binary_among /usr/sbin/iptables /sbin/iptables /usr/bin/iptables)
IPTABLES_SAVE=$(binary_among /usr/sbin/iptables-save /sbin/iptables-save /usr/bin/iptables-save)

# --- Privileged execution
#
# Plain `sudo', not `sudo -n': the scoped sudoers rule for these commands does
# not exist yet (that is episode 3), so a password prompt is expected here. Every
# privileged command is echoed before being run -- a bench that hides what it
# does to the host is worthless.

function step {
 printf '  + sudo %s\n' "$*" 1>&2
 sudo -- "$@" || { echo "$TOOL: FAILED: sudo $*" 1>&2; return 1; }
}

# Same, but a failure is expected and harmless (idempotent teardown):
function step_optional {
 printf '  + sudo %s\n' "$*" 1>&2
 sudo -- "$@" 2>/dev/null || true
}

# --- Names and identities

function bridge_name  { echo "${BRIDGE_PREFIX}$1"; }
function tag_of       { echo "${TAG_PREFIX}:$1"; }
function state_file   { echo "$STATE_DIR/$1"; }
function link_exists  { "$IP" link show "$1" &>/dev/null; }
function pid_is_alive { [[ -d /proc/$1 ]]; }

# check_pid PID: a pid we are willing to name an artefact after. An empty or
# malformed value must NEVER reach a name we later use to select what to destroy.
function check_pid {
 local p=${1:-}
 [[ $p =~ ^[1-9][0-9]*$ ]] || { echo "$TOOL: '$p' is not a pid" 1>&2; return 1; }
}

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
   grep -qF "$net." <<<"$taken" || { echo "$net"; return 0; }
 done
 echo "$TOOL: all candidate networks (${CANDIDATE_NETS[*]}) are already in use here" 1>&2
 return 1
}

# --- up

function nat_rules_add {           # nat_rules_add BRIDGE NET
 local br=$1 net=$2 tag; tag=$(tag_of "$br")
 # Masquerade what leaves the bridge for the outside world:
 step "$IPTABLES" -t nat -A POSTROUTING -s "$net.0/24" ! -o "$br" \
      -m comment --comment "$tag" -j MASQUERADE
 # And let it be forwarded. These two are NOT redundant with the masquerade: on
 # a host running Docker the FORWARD policy is DROP, and a NAT rule alone would
 # translate packets that are then dropped.
 step "$IPTABLES" -A FORWARD -i "$br" ! -o "$br" \
      -m comment --comment "$tag" -j ACCEPT
 step "$IPTABLES" -A FORWARD -o "$br" -m conntrack --ctstate RELATED,ESTABLISHED \
      -m comment --comment "$tag" -j ACCEPT
}

function do_up {                   # do_up PID
 local pid=$1 br net fwd
 check_pid "$pid" || return 1
 br=$(bridge_name "$pid")

 if link_exists "$br"; then
   echo "$TOOL: $br already exists (subnet $(subnet_of "$br").0/24) -- nothing to do." 1>&2
   return 0
 fi

 net=$(free_subnet) || return 1
 fwd=$(cat /proc/sys/net/ipv4/ip_forward)
 mkdir -p "$STATE_DIR"

 # The bridge first, then forwarding, then NAT: each step is undone by do_down.
 {
   step "$IP" link add "$br" type bridge &&
   step "$IP" addr add "$net.1/24" dev "$br" &&
   step "$IP" link set "$br" up &&
   { [[ $fwd = 1 ]] || step sysctl -q -w net.ipv4.ip_forward=1; } &&
   nat_rules_add "$br" "$net"
 } || {
   echo "$TOOL: setup failed, rolling back." 1>&2
   printf 'SUBNET=%s\nIP_FORWARD_WAS=%s\nOWNER_PID=%s\n' "$net" "$fwd" "$pid" > "$(state_file "$br")"
   do_down "$pid"
   return 1
 }

 printf 'SUBNET=%s\nIP_FORWARD_WAS=%s\nOWNER_PID=%s\n' "$net" "$fwd" "$pid" > "$(state_file "$br")"
 cat 1>&2 <<EOF
$TOOL: $br is up on $net.0/24 (host side $net.1), NAT to the outside enabled.
       Guests: address in $net.0/24, default route $net.1.
       Marionnet: MARIONNET_BRIDGE=$br (marionnet.conf or the command line).
       Note: a bridge with no port yet stays NO-CARRIER; it comes up when the
       first tap is attached to it.
EOF
}

# --- down

function do_down {                 # do_down PID
 local pid=$1 br net tag st
 check_pid "$pid" || return 1
 br=$(bridge_name "$pid")
 tag=$(tag_of "$br")
 st=$(state_file "$br")

 # The subnet is needed to delete the NAT rule; the system knows it, the state
 # file is only the fallback (and the sole source for IP_FORWARD_WAS).
 net=$(subnet_of "$br" || true)
 # shellcheck disable=SC1090
 if [[ -r $st ]]; then source "$st"; fi
 [[ -n ${net:-} ]] || net=${SUBNET:-}

 if [[ -z $net ]] && ! link_exists "$br"; then
   if sudo -- "$IPTABLES_SAVE" | grep -qF -- "$tag"; then
     echo "$TOOL: $br is gone but rules tagged $tag remain; cannot rebuild the" 1>&2
     echo "       command to delete them (no subnet known). Showing them instead:" 1>&2
     sudo -- "$IPTABLES_SAVE" | grep -F -- "$tag" 1>&2
     return 1
   fi
   echo "$TOOL: nothing to remove for pid $pid." 1>&2
   return 0
 fi

 if [[ -n $net ]]; then
   step_optional "$IPTABLES" -t nat -D POSTROUTING -s "$net.0/24" ! -o "$br" \
                 -m comment --comment "$tag" -j MASQUERADE
   step_optional "$IPTABLES" -D FORWARD -i "$br" ! -o "$br" \
                 -m comment --comment "$tag" -j ACCEPT
   step_optional "$IPTABLES" -D FORWARD -o "$br" -m conntrack --ctstate RELATED,ESTABLISHED \
                 -m comment --comment "$tag" -j ACCEPT
 fi

 if link_exists "$br"; then step_optional "$IP" link del "$br"; fi

 # Only restore what we changed:
 if [[ ${IP_FORWARD_WAS:-1} = 0 ]]; then step_optional sysctl -q -w net.ipv4.ip_forward=0; fi

 rm -f "$st"
 echo "$TOOL: $br removed." 1>&2
 return 0
}

# --- status / gc

function all_bridges {
 "$IP" -oneline link show type bridge 2>/dev/null \
   | awk -F': ' -v p="^${BRIDGE_PREFIX}[0-9]+$" '$2 ~ p {print $2}'
}

function do_status {               # do_status [PID]
 local pid=${1:-} br list
 if [[ -n $pid ]]; then list=$(bridge_name "$pid"); else list=$(all_bridges); fi
 echo "ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"
 if [[ -z $list ]]; then echo "no ${BRIDGE_PREFIX}* bridge here."; return 0; fi
 for br in $list; do
   link_exists "$br" || { echo "$br: absent"; continue; }
   printf '%s: subnet %s.0/24, owner pid %s (%s), ports: %s\n' \
     "$br" "$(subnet_of "$br")" "${br#"$BRIDGE_PREFIX"}" \
     "$(pid_is_alive "${br#"$BRIDGE_PREFIX"}" && echo alive || echo DEAD)" \
     "$("$IP" -oneline link show master "$br" | awk -F': ' '{printf "%s ", $2}')"
 done
 sudo -- "$IPTABLES_SAVE" | grep -F -- "$TAG_PREFIX:" || echo "(no tagged iptables rule)"
}

function do_gc {
 local br pid found=0
 for br in $(all_bridges); do
   pid=${br#"$BRIDGE_PREFIX"}
   if pid_is_alive "$pid"; then
     echo "$TOOL: keeping $br (pid $pid is alive)." 1>&2
   else
     found=1
     echo "$TOOL: collecting $br (pid $pid is gone)." 1>&2
     do_down "$pid" || true
   fi
 done
 if [[ $found = 0 ]]; then echo "$TOOL: nothing to collect." 1>&2; fi
 return 0
}

# --- selftest: a network namespace plays the guest

function do_selftest {
 local pid=$$ br net ns veth peer rc=0
 br=$(bridge_name "$pid"); ns="mnbrns$pid"; veth="vnbr${pid}a"; peer="vnbr${pid}b"

 echo "== 1. bringing the NAT bridge up" 1>&2
 do_up "$pid"
 net=$(subnet_of "$br")

 echo "== 2. attaching a netns guest ($ns) to $br" 1>&2
 {
   step "$IP" link add "$veth" type veth peer name "$peer" &&
   step "$IP" link set "$veth" master "$br" &&
   step "$IP" link set "$veth" up &&
   step "$IP" netns add "$ns" &&
   step "$IP" link set "$peer" netns "$ns" &&
   step "$IP" -netns "$ns" addr add "$net.2/24" dev "$peer" &&
   step "$IP" -netns "$ns" link set lo up &&
   step "$IP" -netns "$ns" link set "$peer" up &&
   step "$IP" -netns "$ns" route add default via "$net.1"
 } || { echo "$TOOL: could not build the test guest." 1>&2; rc=1; }

 if [[ $rc = 0 ]]; then
   echo "== 3. from the guest: ICMP to the outside" 1>&2
   step "$IP" netns exec "$ns" ping -c1 -W3 9.9.9.9 || rc=1
   echo "== 4. from the guest: UDP/53 to the outside" 1>&2
   if command -v dig >/dev/null; then
     step "$IP" netns exec "$ns" dig +short +time=3 +tries=1 @9.9.9.9 example.org || rc=1
   else
     echo "$TOOL: dig not installed, skipping the DNS leg (install dnsutils)." 1>&2
   fi
 fi

 echo "== 5. tearing everything down" 1>&2
 step_optional "$IP" netns del "$ns"
 if link_exists "$veth"; then step_optional "$IP" link del "$veth"; fi
 do_down "$pid"

 echo "== 6. asserting that nothing survives" 1>&2
 if link_exists "$br"; then echo "LEFTOVER: bridge $br" 1>&2; rc=1; fi
 if "$IP" netns list | grep -qw "$ns"; then echo "LEFTOVER: netns $ns" 1>&2; rc=1; fi
 if sudo -- "$IPTABLES_SAVE" | grep -qF -- "$(tag_of "$br")"; then
   echo "LEFTOVER: iptables rules" 1>&2; rc=1
 fi
 echo "ip_forward is now $(cat /proc/sys/net/ipv4/ip_forward)" 1>&2

 if [[ $rc = 0 ]]; then
   echo "$TOOL: SELFTEST PASSED (guest reached the Internet, host untouched)." 1>&2
 else
   echo "$TOOL: SELFTEST FAILED." 1>&2
 fi
 return $rc
}

# --- the sudoers material for episode 3

function do_print_privileged_commands {
 cat <<EOF
# Privileged commands used by the automatic private NAT bridge (option A).
# <BR> is ${BRIDGE_PREFIX}<pid>, <NET> the chosen /24 prefix, <TAG> ${TAG_PREFIX}:<BR>.
# Episode 3 turns these into a scoped rule in bin/scripts/marionnet-sudoers.sh.
#
# Already covered by the existing rule (\`ip link set mtap* *' -- TAP_PREFIX is
# mtap in bin/scripts/marionnet-sudoers.sh), no change needed for the attachment:
#   $IP link set mtap<pid>-<n> master <BR>
# To be added:
$IP link add <BR> type bridge
$IP addr add <NET>.1/24 dev <BR>
$IP link set <BR> up
$IP link del <BR>
sysctl -w net.ipv4.ip_forward=1
$IPTABLES -t nat -{A,D} POSTROUTING -s <NET>.0/24 ! -o <BR> -m comment --comment <TAG> -j MASQUERADE
$IPTABLES -{A,D} FORWARD -i <BR> ! -o <BR> -m comment --comment <TAG> -j ACCEPT
$IPTABLES -{A,D} FORWARD -o <BR> -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment <TAG> -j ACCEPT
$IPTABLES_SAVE
#
# Test harness only (selftest), NOT part of what Marionnet would need:
#   $IP link add/del <VETH> type veth peer name <PEER>
#   $IP netns add/del/exec <NS> ...
EOF
}

# --- Main

function owner_pid_argument {      # owner_pid_argument [--owner-pid PID]
 case "${1:-}" in
   --owner-pid) check_pid "${2:-}" && echo "$2" ;;
   '')          echo "$PPID" ;;
   *)           echo "$TOOL: unexpected argument '$1'" 1>&2; return 2 ;;
 esac
}

case "${1:-}" in
  up)     shift; do_up     "$(owner_pid_argument "$@")" ;;
  down)   shift; do_down   "$(owner_pid_argument "$@")" ;;
  status) shift; if [[ $# = 0 ]]; then do_status; else do_status "$(owner_pid_argument "$@")"; fi ;;
  gc)     do_gc ;;
  selftest) do_selftest ;;
  print-privileged-commands) do_print_privileged_commands ;;
  -h|--help) usage ;;
  *)      usage; exit 2 ;;
esac
