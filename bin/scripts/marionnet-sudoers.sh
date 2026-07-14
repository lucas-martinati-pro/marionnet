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

# Single source of truth for the scoped sudoers rule that lets Marionnet build
# its ghost taps with iproute2 (chantier `marionnet-daemon-elimination'). Both
# `make install-final-as-root' and Tap_provider (bin/tap_provider.ml) go through
# this script, so the rule text is written down in exactly one place.
#
# The rule it installs is NARROWER than what it replaces: marionnet-daemon was a
# permanent root service whose 0666 socket offered the very same tap creations to
# *every* local account, with no admin opt-in at all.

set -euo pipefail

SUDOERS_FILE=${MARIONNET_SUDOERS_FILE:-/etc/sudoers.d/marionnet}

# The three constants below MUST agree with bin/tap_provider.ml (same names there):
TAP_PREFIX=mtap
ETH42_HOST_ADDRESS=172.23.0.254
GHOST_NETWORK_PREFIX=172.23.

TOOL=$(basename "$0")

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL print     [USER]   # write the expected sudoers rule on stdout
       $TOOL check     [USER]   # exit 0 iff $SUDOERS_FILE is present and up to date (root only:
                                #   the file is 0440, as sudoers files must be)
       $TOOL install   [USER]   # install (or refresh) the rule; needs root (re-execs with sudo)
       $TOOL uninstall          # remove the rule; needs root (re-execs with sudo)

USER defaults to \$SUDO_USER, or to the current user. The rule grants USER the
iproute2 commands Marionnet needs on ${TAP_PREFIX}* interfaces only, and nothing else.
EOF
}

# ip_binary: absolute path of iproute2's `ip'. We probe a fixed candidate list
# instead of $PATH because (1) sudoers matches on the absolute path, (2) root's
# PATH is not the user's, and (3) tap_provider.ml probes the very same list: the
# rule and the runtime commands must designate the same binary.
function ip_binary {
 local i
 for i in /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip; do
   [[ -x $i ]] && { echo "$i"; return 0; }
 done
 echo "$TOOL: iproute2 not found (no \`ip' binary among the usual paths)" 1>&2
 return 1
}

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
function sudoers_content {
 local u=$1 ip
 ip=$(ip_binary) || return 1
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
