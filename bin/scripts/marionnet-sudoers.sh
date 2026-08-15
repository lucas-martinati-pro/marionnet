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

# Single source of truth for the scoped sudoers rule that lets Marionnet
#   (a) build its ghost taps with iproute2 (chantier `marionnet-daemon-elimination'),
#   (b) build and destroy its private NAT bridge (chantier `modernisation-world-bridge').
# Both `make install-final-as-root' and Tap_provider (bin/tap_provider.ml) go
# through this script, so the rule text is written down in exactly one place.
#
# The rule it installs is NARROWER than what it replaces: marionnet-daemon was a
# permanent root service whose 0666 socket offered the very same tap creations to
# *every* local account, with no admin opt-in at all.
#
# For (b) the commands are NOT invented here: they are exactly what
# `marionnet-natbridge.sh print-privileged-commands' publishes, which is the
# single source. Keep the two in step -- that script is the one that runs them.

set -euo pipefail

SUDOERS_FILE=${MARIONNET_SUDOERS_FILE:-/etc/sudoers.d/marionnet}

# The three constants below MUST agree with bin/tap_provider.ml (same names there):
TAP_PREFIX=mtap
ETH42_HOST_ADDRESS=172.23.0.254
GHOST_NETWORK_PREFIX=172.23.

# The two below MUST agree with bin/scripts/marionnet-natbridge.sh (same names there):
BRIDGE_PREFIX=mnbr
TAG_PREFIX=marionnet-natbridge

TOOL=$(basename "$0")

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL print     [USER]   # write the expected sudoers rule on stdout
       $TOOL check     [USER]   # exit 0 iff $SUDOERS_FILE is present and up to date (root only:
                                #   the file is 0440, as sudoers files must be)
       $TOOL install   [USER]   # install (or refresh) the rule; needs root (re-execs with sudo)
       $TOOL uninstall          # remove the rule; needs root (re-execs with sudo)

USER defaults to \$SUDO_USER, or to the current user. The rule grants USER the
iproute2 commands Marionnet needs on ${TAP_PREFIX}* and ${BRIDGE_PREFIX}* interfaces only,
plus the iptables rules carrying the ${TAG_PREFIX}: comment, and nothing else.
EOF
}

# binary_among WHAT CANDIDATE...: absolute path of a tool. We probe a fixed
# candidate list instead of $PATH because (1) sudoers matches on the absolute
# path, (2) root's PATH is not the user's, and (3) tap_provider.ml and
# marionnet-natbridge.sh probe the very same lists: the rule and the runtime
# commands must designate the same binary.
function binary_among {
 local what=$1 i; shift
 for i in "$@"; do
   [[ -x $i ]] && { echo "$i"; return 0; }
 done
 echo "$TOOL: $what not found (none of $* is executable)" 1>&2
 return 1
}

function ip_binary            { binary_among iproute2 /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip; }
function iptables_binary      { binary_among iptables /usr/sbin/iptables /sbin/iptables /usr/bin/iptables; }
function iptables_save_binary { binary_among iptables-save /usr/sbin/iptables-save /sbin/iptables-save /usr/bin/iptables-save; }
function sysctl_binary        { binary_among sysctl /usr/sbin/sysctl /sbin/sysctl /usr/bin/sysctl /bin/sysctl; }

# default_user: who the rule is for, when not given on the command line.
function default_user {
 echo "${SUDO_USER:-$(id -un)}"
}

# sudoers_content USER: the exact content we install and expect.
# Wildcards are kept as tight as the commands allow: the address is literal, the
# routed network is prefix-bound, and every device is ${TAP_PREFIX}*. Only
# `link set' keeps a free trailing `*' (it must accept `up', and `promisc on' /
# `master <bridge>' for the world_bridge). Marionnet never passes user input
# here: tap names are generated and addresses are computed.
#
# The NAT bridge block (chantier modernisation-world-bridge) is scoped the same
# way: every device is ${BRIDGE_PREFIX}*, every address is forced to the `.1/24'
# host side of a /24, and -- the tightest guard of the three -- every iptables
# rule must carry OUR comment, `${TAG_PREFIX}:${BRIDGE_PREFIX}*'. Without that
# tag no rule can be added, and none can be deleted: the grant cannot be used to
# touch a rule Marionnet did not create.
function sudoers_content {
 local u=$1 ip iptables iptables_save sysctl
 ip=$(ip_binary) || return 1
 iptables=$(iptables_binary) || return 1
 iptables_save=$(iptables_save_binary) || return 1
 sysctl=$(sysctl_binary) || return 1
 # sudoers metacharacters MUST be backslash-escaped inside a command's arguments,
 # or visudo rejects the whole file: `!' (it is the negation operator), `,' (it
 # separates command specs) and `:' (it separates host specs). Measured with
 # `visudo -cf': all three are fatal unescaped. `=' is not, and needs nothing.
 # The escapes are sudoers SYNTAX -- what sudo compares at runtime is the plain
 # text, so these still match the commands marionnet-natbridge.sh runs.
 local bang='\!' comma='\,' tag="${TAG_PREFIX}\\:${BRIDGE_PREFIX}*"
 cat <<EOF
# Installed by $TOOL -- do not edit by hand, regenerate instead.
# Lets $u create and destroy Marionnet's ghost taps (${TAP_PREFIX}*) with iproute2.
# Replaces marionnet-daemon, the former permanent root service (chantier
# marionnet-daemon-elimination). Remove with: $TOOL uninstall
$u ALL=(root) NOPASSWD: $ip tuntap add dev ${TAP_PREFIX}* mode tap user $u
$u ALL=(root) NOPASSWD: $ip tuntap del dev ${TAP_PREFIX}* mode tap
$u ALL=(root) NOPASSWD: $ip addr add ${ETH42_HOST_ADDRESS}/32 dev ${TAP_PREFIX}*
$u ALL=(root) NOPASSWD: $ip route add ${GHOST_NETWORK_PREFIX}* dev ${TAP_PREFIX}*
$u ALL=(root) NOPASSWD: $ip link set ${TAP_PREFIX}* *
$u ALL=(root) NOPASSWD: $ip link del ${TAP_PREFIX}*
# And the private NAT bridge (${BRIDGE_PREFIX}*) of chantier modernisation-world-bridge,
# built and destroyed by marionnet-natbridge.sh. The host interface, its address
# and its routes are never named here: they cannot be touched through this rule.
$u ALL=(root) NOPASSWD: $ip link add ${BRIDGE_PREFIX}* type bridge
$u ALL=(root) NOPASSWD: $ip link del ${BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip link set ${BRIDGE_PREFIX}* up
$u ALL=(root) NOPASSWD: $ip link set ${BRIDGE_PREFIX}* down
$u ALL=(root) NOPASSWD: $ip addr add *.1/24 dev ${BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip addr del *.1/24 dev ${BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $sysctl -q -w net.ipv4.ip_forward=1
$u ALL=(root) NOPASSWD: $sysctl -q -w net.ipv4.ip_forward=0
$u ALL=(root) NOPASSWD: $iptables -t nat -A POSTROUTING -s *.0/24 $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j MASQUERADE
$u ALL=(root) NOPASSWD: $iptables -t nat -D POSTROUTING -s *.0/24 $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j MASQUERADE
$u ALL=(root) NOPASSWD: $iptables -A FORWARD -i ${BRIDGE_PREFIX}* $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $iptables -D FORWARD -i ${BRIDGE_PREFIX}* $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $iptables -A FORWARD -o ${BRIDGE_PREFIX}* -m conntrack --ctstate RELATED${comma}ESTABLISHED -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $iptables -D FORWARD -o ${BRIDGE_PREFIX}* -m conntrack --ctstate RELATED${comma}ESTABLISHED -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $iptables_save
EOF
}

# check_rule USER: is the installed file exactly what we would install now?
# Needs to READ $SUDOERS_FILE, which is 0440 root:root as sudoers files must be:
# this is an admin check, meaningful for root only. What the runtime asks instead
# is "can I run the commands without a password", which Tap_provider.is_usable
# probes with a harmless `sudo -n ip tuntap del' of a tap that does not exist.
function check_rule {
 local u=$1
 if [[ ! -r $SUDOERS_FILE ]]; then
   [[ $EUID -eq 0 || ! -e $SUDOERS_FILE ]] || \
     echo "$TOOL: $SUDOERS_FILE exists but is not readable by $(id -un); re-run as root to check it." 1>&2
   return 1
 fi
 diff -q <(sudoers_content "$u") "$SUDOERS_FILE" >/dev/null
}

# install_rule USER: idempotent. Validated by visudo BEFORE being adopted, so a
# botched generation can never lock the user out of sudo.
function install_rule {
 local u=$1
 if check_rule "$u" 2>/dev/null; then
   echo "$TOOL: $SUDOERS_FILE is already up to date for user $u." 1>&2
   return 0
 fi
 if [[ $EUID -ne 0 ]]; then
   echo "$TOOL: installing $SUDOERS_FILE requires root; re-executing with sudo." 1>&2
   sudoers_content "$u" | sed 's/^/    /' 1>&2
   exec sudo -- "$0" install "$u"
 fi
 # Global on purpose: the EXIT trap runs after this function has returned, when a
 # `local' would be long gone (and would abort the script under `set -u'):
 tmp=$(mktemp /tmp/marionnet-sudoers.XXXXXX)
 trap 'rm -f "${tmp:-}"' EXIT
 sudoers_content "$u" > "$tmp"
 chmod 0440 "$tmp"
 if ! visudo -cf "$tmp" >/dev/null; then
   echo "$TOOL: generated rule REJECTED by visudo; nothing installed." 1>&2
   return 1
 fi
 install -m 0440 -o root -g root "$tmp" "$SUDOERS_FILE"
 echo "$TOOL: installed $SUDOERS_FILE for user $u." 1>&2
}

function uninstall_rule {
 if [[ $EUID -ne 0 ]]; then
   exec sudo -- "$0" uninstall
 fi
 rm -f "$SUDOERS_FILE"
 echo "$TOOL: removed $SUDOERS_FILE." 1>&2
}

# --- Main

case "${1:-}" in
  print)     sudoers_content "${2:-$(default_user)}" ;;
  check)     check_rule      "${2:-$(default_user)}" ;;
  install)   install_rule    "${2:-$(default_user)}" ;;
  uninstall) uninstall_rule ;;
  -h|--help) usage ;;
  *)         usage; exit 2 ;;
esac
