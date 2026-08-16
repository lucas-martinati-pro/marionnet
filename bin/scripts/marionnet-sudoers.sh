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

# Single source of truth for the scoped sudoers rules that let Marionnet
#   (a) build its ghost taps with iproute2 (chantier `marionnet-daemon-elimination'),
#   (b) build and destroy its private NAT bridge (chantier `modernisation-world-bridge'),
#   (c) build and destroy its LAN bridge, host interface included (same chantier).
# `make install-final-as-root', Tap_provider (bin/tap_provider.ml) and the GUI
# elevation dialog all go through this script, so the rule text is written down
# in exactly one place.
#
# The three blocks are NOT granted at the same moment, nor by the same person:
#
#   (a) INSTALL TIME, by the administrator.  Nothing works without it (every
#       component needs taps), and whoever installs Marionnet is often NOT the
#       person who will use it.  This is what `install' grants by default.
#   (b) and (c) RUN TIME, by the end user, when a NAT bridge or a LAN bridge
#       component is started for the first time: the GUI asks for the sudo
#       password and re-runs us with --only --enable-natbridge / --enable-lanbridge
#       (--enable-bridges is the shorthand for both).  Granting at install time
#       the right to touch the host's network card -- which (c) implies -- would
#       be granting a power nobody needs yet, to an account nobody has chosen.
#
# One file per block in /etc/sudoers.d/ rather than one file of varying content:
# each block is then installed, checked and removed independently, and -- what
# matters most -- a run-time elevation NEVER has to rewrite the file carrying
# (a), the one without which Marionnet cannot start a single component.
# (No dot in those file names: sudo silently ignores such files in sudoers.d.)
# Separate files are only half of that guarantee: --only is the other half, since
# without it a bare `install --enable-natbridge' also refreshes (a) -- for the
# CALLING user.  Let the administrator grant (a) to X, then let Y activate the NAT
# bridge from the GUI, and X silently loses its taps.  Hence: the GUI always says
# --only, and block (a) then stays exactly as the administrator wrote it.
#
# For (b) the commands are NOT invented here: they are exactly what
# `marionnet-natbridge.sh print-privileged-commands' publishes, which is the
# single source. Keep the two in step -- that script is the one that runs them.
# (c) awaits its own script, marionnet-lanbridge.sh (episode 8 of the chantier):
# writing that grant before the script that justifies it, line by line, is how
# one ends up with a rule wider than the deed. Until then --enable-lanbridge
# refuses to install anything, loudly.
#
# The rules installed are NARROWER than what they replace: marionnet-daemon was
# a permanent root service whose 0666 socket offered the very same tap creations
# to *every* local account, with no admin opt-in at all.

set -euo pipefail

SUDOERS_DIR=${MARIONNET_SUDOERS_DIR:-/etc/sudoers.d}

# MARIONNET_SUDOERS_FILE keeps overriding the (a) file alone, as it always did.
SUDOERS_FILE_TAPS=${MARIONNET_SUDOERS_FILE:-$SUDOERS_DIR/marionnet}
SUDOERS_FILE_NATBRIDGE=$SUDOERS_DIR/marionnet-natbridge
SUDOERS_FILE_LANBRIDGE=$SUDOERS_DIR/marionnet-lanbridge

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
Usage: $TOOL print     [BLOCKS] [USER]   # write the expected sudoers rules on stdout
       $TOOL check     [BLOCKS] [USER]   # exit 0 iff every selected block is present and up to
                                         #   date (root only: the files are 0440, as they must be)
       $TOOL install   [BLOCKS] [USER]   # install (or refresh) them; needs root (re-execs with sudo)
       $TOOL uninstall [BLOCKS]          # remove them; needs root (re-execs with sudo)

BLOCKS selects what the command applies to. Block (a) -- the ghost taps -- is
selected by default: it is the socle, and it is what a bare \`install' grants.
Only --only takes it out of the selection.

       --enable-natbridge   also (b): the private NAT bridge (${BRIDGE_PREFIX}*)
       --enable-lanbridge   also (c): the LAN bridge and the host interface
       --enable-bridges     shorthand for both
       --only               apply to the selected blocks ONLY, leaving (a) alone.
                            This is what the GUI uses when the end user activates
                            a bridge: block (a) must never be rewritten -- it may
                            well have been granted to somebody else.

\`uninstall' removes everything by default, and takes --disable-natbridge,
--disable-lanbridge or --disable-bridges to remove those blocks only (block (a)
is then left alone).

USER defaults to \$SUDO_USER, or to the current user. The rules grant USER the
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

# --- (a) The ghost taps -- chantier marionnet-daemon-elimination

# content_taps USER: the exact content we install and expect in $SUDOERS_FILE_TAPS.
# Wildcards are kept as tight as the commands allow: the address is literal, the
# routed network is prefix-bound, and every device is ${TAP_PREFIX}*. Only
# `link set' keeps a free trailing `*' (it must accept `up', and `promisc on' /
# `master <bridge>' for the world_bridge). Marionnet never passes user input
# here: tap names are generated and addresses are computed.
function content_taps {
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

# --- (b) The private NAT bridge -- chantier modernisation-world-bridge

# content_natbridge USER: what goes into $SUDOERS_FILE_NATBRIDGE. Scoped the same
# way as (a): every device is ${BRIDGE_PREFIX}*, every address is forced to the
# `.1/24' host side of a /24, and -- the tightest guard of the three -- every
# iptables rule must carry OUR comment, `${TAG_PREFIX}:${BRIDGE_PREFIX}*'. Without that tag
# no rule can be added, and none can be deleted: the grant cannot be used to
# touch a rule Marionnet did not create. The host interface, its address and its
# routes are never named here: they cannot be touched through this rule.
function content_natbridge {
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
# Installed by $TOOL --enable-natbridge -- do not edit by hand, regenerate instead.
# Lets $u build and destroy Marionnet's private NAT bridge (${BRIDGE_PREFIX}*), the one
# marionnet-natbridge.sh creates for the "NAT bridge" component (chantier
# modernisation-world-bridge). Remove with: $TOOL uninstall --disable-natbridge
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

# --- (c) The LAN bridge -- chantier modernisation-world-bridge, episode 8

# content_lanbridge USER: not written yet, ON PURPOSE. This block is the only one
# that will name the HOST's own interface, its address and its default route --
# the very things (a) and (b) are careful never to mention. Such a grant is
# derived, command by command, from the script that runs them
# (marionnet-lanbridge.sh, episode 8); guessing it beforehand is how a rule ends
# up wider than the deed it authorises. So: refuse, explicitly.
function content_lanbridge {
 echo "$TOOL: block (c) is not available yet: bin/scripts/marionnet-lanbridge.sh does not exist" 1>&2
 echo "$TOOL: (chantier modernisation-world-bridge, episode 8 -- the grant is derived from that script)" 1>&2
 return 3
}

# --- Blocks as a whole

# block_file BLOCK / block_content BLOCK USER: the two per-block dispatchers.
# Everything below is written once and applied to whichever blocks were selected.
function block_file {
 case $1 in
   taps)      echo "$SUDOERS_FILE_TAPS" ;;
   natbridge) echo "$SUDOERS_FILE_NATBRIDGE" ;;
   lanbridge) echo "$SUDOERS_FILE_LANBRIDGE" ;;
 esac
}

function block_content {
 case $1 in
   taps)      content_taps      "$2" ;;
   natbridge) content_natbridge "$2" ;;
   lanbridge) content_lanbridge "$2" ;;
 esac
}

# check_block BLOCK USER: is the installed file exactly what we would install now?
# Needs to READ the file, which is 0440 root:root as sudoers files must be: this
# is an admin check, meaningful for root only. What the runtime asks instead is
# "can I run the commands without a password", which Tap_provider.is_usable
# probes with a harmless `sudo -n ip tuntap del' of a tap that does not exist.
function check_block {
 local b=$1 u=$2 f
 f=$(block_file "$b")
 if [[ ! -r $f ]]; then
   [[ $EUID -eq 0 || ! -e $f ]] || \
     echo "$TOOL: $f exists but is not readable by $(id -un); re-run as root to check it." 1>&2
   return 1
 fi
 diff -q <(block_content "$b" "$u") "$f" >/dev/null
}

# install_block BLOCK USER: idempotent -- an up-to-date file is not rewritten at
# all. Validated by visudo BEFORE being adopted, so a botched generation can
# never lock the user out of sudo.
function install_block {
 local b=$1 u=$2 f tmp
 f=$(block_file "$b")
 if check_block "$b" "$u" 2>/dev/null; then
   echo "$TOOL: $f is already up to date for user $u." 1>&2
   return 0
 fi
 tmp=$(mktemp /tmp/marionnet-sudoers.XXXXXX)
 # Global on purpose: the EXIT trap runs after this function has returned, when a
 # `local' would be long gone (and would abort the script under `set -u'):
 TMPFILE=$tmp
 trap 'rm -f "${TMPFILE:-}"' EXIT
 block_content "$b" "$u" > "$tmp"
 chmod 0440 "$tmp"
 if ! visudo -cf "$tmp" >/dev/null; then
   echo "$TOOL: generated rule for block '$b' REJECTED by visudo; nothing installed." 1>&2
   return 1
 fi
 install -m 0440 -o root -g root "$tmp" "$f"
 echo "$TOOL: installed $f for user $u." 1>&2
}

function uninstall_block {
 local f
 f=$(block_file "$1")
 rm -f "$f"
 echo "$TOOL: removed $f." 1>&2
}

# --- Command line
#
# The selection is the same for every subcommand, which is why it is parsed once:
# block (a) is implicit (`install' alone is the administrator's install-time
# gesture), --enable-* add the others. `uninstall' inverts the defaults -- it
# removes everything unless --disable-* names a subset.

BLOCKS=()
COMMAND=""
USER_ARG=""
WANT_NAT=false
WANT_LAN=false
EXPLICIT_SELECTION=false
ONLY=false

function parse_command_line {
 local a
 COMMAND=${1:-}; shift || true
 for a in "$@"; do
   case "$a" in
     --enable-natbridge|--disable-natbridge)   WANT_NAT=true; EXPLICIT_SELECTION=true ;;
     --enable-lanbridge|--disable-lanbridge)   WANT_LAN=true; EXPLICIT_SELECTION=true ;;
     --enable-bridges|--disable-bridges)       WANT_NAT=true; WANT_LAN=true; EXPLICIT_SELECTION=true ;;
     --only)                                   ONLY=true ;;
     -*) echo "$TOOL: unknown option '$a'" 1>&2; return 2 ;;
     *)
       if [[ -n $USER_ARG ]]; then
         echo "$TOOL: unexpected argument '$a' (USER is already '$USER_ARG')" 1>&2
         return 2
       fi
       USER_ARG=$a
       ;;
   esac
 done
 # --only is a modifier of the selection, not a selection: on its own it would
 # mean "apply to nothing", which is never what anybody meant.  And on `uninstall'
 # it would be noise: --disable-* already leaves (a) alone.
 if $ONLY; then
   if [[ $COMMAND = uninstall ]]; then
     echo "$TOOL: --only makes no sense for 'uninstall' (--disable-* already spares block (a))" 1>&2
     return 2
   fi
   if ! $EXPLICIT_SELECTION; then
     echo "$TOOL: --only needs a selection (--enable-natbridge, --enable-lanbridge or --enable-bridges)" 1>&2
     return 2
   fi
 fi
 # `if' rather than `$WANT_NAT && BLOCKS+=(...)': under `set -e' the latter is a
 # failing AND-list whenever the flag is false, which is exactly the kind of
 # silent early exit this script must not have.
 if [[ $COMMAND = uninstall ]]; then
   # Removing everything is the default; --disable-* narrows it, and then block
   # (a) is deliberately left in place (the user is dropping a bridge grant, not
   # uninstalling Marionnet).
   if $EXPLICIT_SELECTION; then
     if $WANT_NAT; then BLOCKS+=(natbridge); fi
     if $WANT_LAN; then BLOCKS+=(lanbridge); fi
   else
     BLOCKS=(taps natbridge lanbridge)
   fi
 else
   # Block (a) is implicit -- unless --only, which is precisely the promise made
   # to the administrator: a run-time activation touches its file for nothing.
   if $ONLY; then BLOCKS=(); else BLOCKS=(taps); fi
   if $WANT_NAT; then BLOCKS+=(natbridge); fi
   if $WANT_LAN; then BLOCKS+=(lanbridge); fi
 fi
 return 0
}

# available_blocks_or_die COMMAND: refuse BEFORE touching anything. Installing
# (b) and then dying on (c) would leave the system in a state nobody asked for;
# `uninstall' is exempt, since removing a file that was never written is a no-op.
function available_blocks_or_die {
 local b
 if [[ $1 = uninstall ]]; then return 0; fi
 for b in "${BLOCKS[@]}"; do
   if [[ $b = lanbridge ]]; then content_lanbridge || exit $?; fi
 done
 return 0
}

parse_command_line "$@" || { usage; exit 2; }
USER_ARG=${USER_ARG:-$(default_user)}
case "$COMMAND" in print|check|install|uninstall) available_blocks_or_die "$COMMAND" ;; esac

case "$COMMAND" in
  print)
     for b in "${BLOCKS[@]}"; do
       echo "# >>> $(block_file "$b")"
       block_content "$b" "$USER_ARG"
     done
     ;;
  check)
     rc=0
     for b in "${BLOCKS[@]}"; do check_block "$b" "$USER_ARG" || rc=1; done
     exit $rc
     ;;
  install|uninstall)
     if [[ $EUID -ne 0 ]]; then
       echo "$TOOL: this requires root; re-executing with sudo." 1>&2
       if [[ $COMMAND = install ]]; then
         for b in "${BLOCKS[@]}"; do block_content "$b" "$USER_ARG" | sed 's/^/    /' 1>&2; done
       fi
       # "$@" and not a rebuilt command line: the user's own words go through,
       # so a re-exec can never grant a block the caller did not ask for.
       exec sudo -- "$0" "$@"
     fi
     for b in "${BLOCKS[@]}"; do
       if [[ $COMMAND = install ]]; then install_block "$b" "$USER_ARG"; else uninstall_block "$b"; fi
     done
     ;;
  -h|--help) usage ;;
  *)         usage; exit 2 ;;
esac
