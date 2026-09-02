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
# without it a bare `install --enable-natbridge' also touches (a) -- for the
# CALLING user, who would then silently gain the socle nobody granted them.
# Hence: the GUI always says --only, and block (a) stays exactly as the
# administrator wrote it.
#
# Each of the three files grants a LIST of accounts, and `install' only ever adds
# to it: see the `Principals' section.  A classroom has more than one human on it,
# and until then `install student' quietly REVOKED `teacher'.
#
# For (b) and (c) the commands are NOT invented here: they are exactly what
# `marionnet-natbridge.sh print-privileged-commands' and
# `marionnet-lanbridge.sh print-privileged-commands' publish, which are the
# single sources. Keep them in step -- those scripts are the ones that run them.
#
# (a) and (b) are NARROWER than what they replace: marionnet-daemon was a
# permanent root service whose 0666 socket offered the very same tap creations to
# *every* local account, with no admin opt-in at all. (c) is NOT narrow, and
# cannot be -- see the comment above content_lanbridge. That is the whole reason
# the three blocks are three files, granted at three different moments.

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

# The DHCP service of a NAT bridge (episode 10c) is started by a script, not by
# a bare dnsmasq -- see the header of marionnet-dnsmasq.sh for why a sudoers rule
# cannot scope a dnsmasq command line. The rule must therefore name that script
# by an ABSOLUTE path, and the only defensible one is the copy sitting next to
# THIS file: both are installed together, by the same hand.
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
DHCP_HELPER=$SCRIPT_DIR/marionnet-dnsmasq.sh

# Same reasoning for the IPv6 gate (episode 11), one step further: it takes NO
# argument, so its two lines are entirely literal -- there is not even a glob to
# abuse. What it needs from us is only to be named by an absolute path, and to be
# untouchable by the user (root_owned_all_the_way, as for the DHCP helper).
IPV6_HELPER=$SCRIPT_DIR/marionnet-ipv6.sh

# And these two with bin/scripts/marionnet-lanbridge.sh (BRIDGE_PREFIX and
# ALIAS_PREFIX there):
LAN_BRIDGE_PREFIX=mnlan
LAN_ALIAS_PREFIX=marionnet-lanbridge

TOOL=$(basename "$0")

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL print     [BLOCKS] [USER...]  # write the expected sudoers rules on stdout
       $TOOL check     [BLOCKS] [USER...]  # exit 0 iff every selected block grants every USER and
                                           #   is up to date (root only: the files are 0440)
       $TOOL install   [BLOCKS] [USER...]  # grant them; needs root (re-execs with sudo)
       $TOOL uninstall [BLOCKS] [USER...]  # take the grant back; needs root (re-execs with sudo)

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
is then left alone). Named USERs make it narrower still: only their rules are
removed, and the file stays in place for the accounts it still grants.

A USER is an account, or a GROUP in sudoers spelling -- \`%students'. The group is
what a classroom needs: whoever sets a room up does not know the logins of the
students who will sit in it. \`ALL' is refused: what a file grants must have been
decided by somebody.

Several USERs may be named, and \`install' is ADDITIVE: the principals a file
already grants are kept (and their rules refreshed). Granting a second person
therefore never takes the first one's grant away -- \`uninstall USER...' is the
only way to do that. An account or a group that does not exist is REFUSED:
sudoers would happily name it, and grant it the day somebody creates it.

\`check' answers about the principals a file NAMES, not about effective rights: a
member of a granted group is not a principal. \`sudo -l -U <login>' is the question
about effective rights.

USER defaults to \$SUDO_USER, or to the current user. Blocks (a) and (b) grant
USER the iproute2 commands Marionnet needs on ${TAP_PREFIX}* and ${BRIDGE_PREFIX}* interfaces
only, plus the iptables rules carrying the ${TAG_PREFIX}: comment, and nothing
else. Block (c) is wider BY NATURE -- a LAN bridge is the host's own card, whose
name is not known in advance -- and grants USER the right to move IPv4 addresses
and the default route on this machine. Read the header of the file it installs.
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
function ip6tables_binary      { binary_among ip6tables /usr/sbin/ip6tables /sbin/ip6tables /usr/bin/ip6tables; }
function ip6tables_save_binary { binary_among ip6tables-save /usr/sbin/ip6tables-save /sbin/ip6tables-save /usr/bin/ip6tables-save; }

# default_user: who the rule is for, when not given on the command line.
function default_user {
 echo "${SUDO_USER:-$(id -un)}"
}

# --- Principals
#
# One of our files grants a LIST of accounts, not one. It used to grant exactly
# one, and `install student' therefore REVOKED `teacher' without saying so -- the
# very accident the header above describes for run-time elevations, left wide
# open on the administrator's side, where a classroom needs it least. Hence:
#
#   * `install USER...' is ADDITIVE. The accounts already named in the file are
#     kept, and their rules are regenerated along with the new ones (so a file
#     written when `ip' sat elsewhere is brought up to date for everybody).
#   * `uninstall USER...' is the way back, and it is the ONLY way to take a grant
#     away: no invocation of `install' can ever narrow a file.
#
# The list is read back from a marker line rather than guessed from the rules:
# the file is ours, so it may as well carry its own index.
PRINCIPALS_MARK='# principals:'

# file_principals FILE: the accounts FILE grants, in the order it names them, on
# one line. Falls back to the first field of the rule lines, so that a file
# written by a version of this script older than the marker is still understood
# (and, being regenerated, gains the marker).
function file_principals {
 local f=$1 line
 [[ -r $f ]] || return 0
 line=$(sed -n "s/^${PRINCIPALS_MARK} *//p" "$f" | head -n 1)
 if [[ -n $line ]]; then
   echo "$line"
 else
   awk '$2 == "ALL=(root)" { if (!seen[$1]++) printf "%s ", $1 } END { print "" }' "$f"
 fi
}

# member_of NEEDLE HAYSTACK...: `case' and not a loop, because a loop whose last
# test fails returns non-zero, and this script runs under `set -e'.
function member_of {
 local needle=$1; shift
 local x
 for x in "$@"; do if [[ $x = "$needle" ]]; then return 0; fi; done
 return 1
}

# union_principals FILE USER...: what FILE must grant after an `install'.
function union_principals {
 local f=$1; shift
 local -a existing=() result=()
 read -r -a existing <<<"$(file_principals "$f")"
 local p
 for p in "${existing[@]}" "$@"; do
   if ! member_of "$p" "${result[@]}"; then result+=("$p"); fi
 done
 echo "${result[*]}"
}

# minus_principals FILE USER...: what FILE must grant after an `uninstall USER...'.
# The accounts to drop are NOT checked for existence, on purpose: the one to
# remove is quite likely the one that should never have been granted (a typo, a
# `student42'), or an account since deleted.
function minus_principals {
 local f=$1; shift
 local -a existing=() result=()
 read -r -a existing <<<"$(file_principals "$f")"
 local p
 for p in "${existing[@]}"; do
   if ! member_of "$p" "$@"; then result+=("$p"); fi
 done
 echo "${result[*]}"
}

# is_group PRINCIPAL: a principal is either an account or, in sudoers spelling, a
# GROUP -- `%students'. A classroom is the reason: an administrator setting up a
# room does not know the logins of the students who will sit in it, and cannot
# wait to know them. The group is the only name that exists before they do.
function is_group {
 [[ $1 = %* ]]
}

# known_principal_or_die PRINCIPAL...: sudoers is perfectly happy to name an
# account that does not exist -- for sudo that is a legitimate case (the account
# may be created later), so `visudo -cf' has nothing to say about `student42',
# and the rule was installed. Here it is never legitimate: we grant a power to
# somebody, and "somebody" must be a person, or a group of them. NSS is the
# authority, and it answers for LDAP/SSSD accounts and groups exactly as it does
# for local ones.
function known_principal_or_die {
 local u rc=0
 for u in "$@"; do
   # `ALL' is sudoers' own keyword for "every account on this machine", system
   # ones included, and it would be accepted here without a word. It is refused,
   # and the refusal says what to do instead: what a file grants must have been
   # DECIDED by somebody. (The old marionnet-daemon did offer these very tap
   # creations to every local account through a 0666 socket -- that is what this
   # script exists to have ended, not a precedent to follow.)
   if [[ $u = ALL ]]; then
     echo "$TOOL: refusing 'ALL': it would grant every account on this machine, system ones included." 1>&2
     echo "$TOOL: name a group instead:  groupadd marionnet; gpasswd -a <login> marionnet; $TOOL install %marionnet" 1>&2
     rc=2
     continue
   fi
   if is_group "$u"; then
     if ! getent group -- "${u#%}" >/dev/null 2>&1; then
       echo "$TOOL: no such group: '${u#%}'. Nothing installed." 1>&2
       rc=2
     fi
     continue
   fi
   # `getent passwd 1000' answers -- by UID. But sudoers would read `1000' as a
   # NAME, not as a uid (that is spelled `#1000'), so accepting the digits here
   # would install a rule for an account that does not exist. Refuse, and say how.
   if [[ $u =~ ^[0-9]+$ ]]; then
     echo "$TOOL: '$u' is a number, and sudoers reads it as a user NAME. Give the login name (or write it '#$u' to mean the uid)." 1>&2
     rc=2
     continue
   fi
   if ! getent passwd -- "$u" >/dev/null 2>&1; then
     echo "$TOOL: no such account: '$u'. Nothing installed." 1>&2
     rc=2
   fi
 done
 return $rc
}

# --- (a) The ghost taps -- chantier marionnet-daemon-elimination

# content_taps_rules USER: the rules granted to ONE account (see content_taps for
# the file as a whole).
# Wildcards are kept as tight as the commands allow: the address is literal, the
# routed network is prefix-bound, and every device is ${TAP_PREFIX}*. Only
# `link set' keeps a free trailing `*' (it must accept `up', and `promisc on' /
# `master <bridge>' for the world_bridge). Marionnet never passes user input
# here: tap names are generated and addresses are computed.
function content_taps_rules {
 local u=$1 ip owner
 ip=$(ip_binary) || return 1
 # The tap is created for its future user, whose LOGIN the rule names -- which a
 # group principal, by definition, does not have. sudoers has no way to spell
 # "the caller" in a command argument (no %u expansion there; the escapes are
 # for Defaults), so the owner becomes a wildcard for groups, and stays exact for
 # every named account. What that opens is bounded and stated in the file itself:
 # a member may create a tap OWNED BY somebody else -- a nuisance, not a way in,
 # since a tap one does not own cannot be opened. It stays narrower than the
 # `link set ${TAP_PREFIX}* *' line above, which every granted account already has.
 if is_group "$u"; then
   owner='*'
   cat <<EOF
# $u is a group: the tap owner below cannot be bound to the caller's login (see
# content_taps_rules). A member may give a tap away; nobody gains a tap they can open.
EOF
 else
   owner=$u
 fi
 cat <<EOF
$u ALL=(root) NOPASSWD: $ip tuntap add dev ${TAP_PREFIX}* mode tap user $owner
$u ALL=(root) NOPASSWD: $ip tuntap del dev ${TAP_PREFIX}* mode tap
$u ALL=(root) NOPASSWD: $ip addr add ${ETH42_HOST_ADDRESS}/32 dev ${TAP_PREFIX}*
$u ALL=(root) NOPASSWD: $ip route add ${GHOST_NETWORK_PREFIX}* dev ${TAP_PREFIX}*
$u ALL=(root) NOPASSWD: $ip link set ${TAP_PREFIX}* *
$u ALL=(root) NOPASSWD: $ip link del ${TAP_PREFIX}*
EOF
}

# --- (b) The private NAT bridge -- chantier modernisation-world-bridge

# content_natbridge_rules USER: the NAT bridge rules granted to ONE account (see
# content_natbridge for the file as a whole). Scoped the same
# way as (a): every device is ${BRIDGE_PREFIX}*, every address is forced to the
# `.1/24' host side of a /24, and -- the tightest guard of the three -- every
# iptables rule must carry OUR comment, `${TAG_PREFIX}:${BRIDGE_PREFIX}*'. Without that tag
# no rule can be added, and none can be deleted: the grant cannot be used to
# touch a rule Marionnet did not create. The host interface, its address and its
# routes are never named here: they cannot be touched through this rule.
#
# The last line, when it is there, is the DHCP service (episode 10c). It grants
# a SCRIPT rather than dnsmasq itself, because sudoers cannot scope a dnsmasq
# command line: a `*' in an argument swallows extra words (measured), so
# `--dhcp-script=/tmp/evil' would slip through and run as root. marionnet-dnsmasq.sh
# takes exactly two arguments and validates them AS ROOT before doing anything;
# and this rule is only written when that script is root-owned and unwritable by
# others, all the way up its path -- see root_owned_all_the_way.
# root_owned_all_the_way PATH: is PATH, and every directory above it, owned by
# root and unwritable by anyone else? Granting `NOPASSWD: <script>' on a file the
# grantee may edit -- or that lives in a directory they may edit -- is granting a
# root shell, plainly. Being able to say NO is worth these few lines: an
# administrator installing from an unpacked source tree would otherwise hand out
# exactly that, and never know.
function root_owned_all_the_way {
 local path=$1 owner mode
 path=$(readlink -f "$path") || return 1
 [[ -e $path ]] || return 1
 while : ; do
   read -r owner mode < <(stat -c '%u %a' "$path") || return 1
   [[ $owner = 0 ]] || return 1
   # No write bit for group or other. Counted from the RIGHT: %a is three digits,
   # or four when a setuid/sticky bit is set.
   (( (0${mode: -2:1} & 2) == 0 && (0${mode: -1} & 2) == 0 )) || return 1
   if [[ $path = / ]]; then break; fi
   path=$(dirname "$path")
 done
 return 0
}

function content_natbridge_rules {
 local u=$1 ip iptables iptables_save sysctl ip6tables ip6tables_save
 ip=$(ip_binary) || return 1
 iptables=$(iptables_binary) || return 1
 iptables_save=$(iptables_save_binary) || return 1
 sysctl=$(sysctl_binary) || return 1
 # Episode 11. The same package ships both families, so a host that resolved
 # iptables resolves these too; a host that does not could not do IPv6 anyway.
 ip6tables=$(ip6tables_binary) || return 1
 ip6tables_save=$(ip6tables_save_binary) || return 1
 # sudoers metacharacters MUST be backslash-escaped inside a command's arguments,
 # or visudo rejects the whole file: `!' (it is the negation operator), `,' (it
 # separates command specs) and `:' (it separates host specs). Measured with
 # `visudo -cf': all three are fatal unescaped. `=' is not, and needs nothing.
 # The escapes are sudoers SYNTAX -- what sudo compares at runtime is the plain
 # text, so these still match the commands marionnet-natbridge.sh runs.
 local bang='\!' comma='\,' tag="${TAG_PREFIX}\\:${BRIDGE_PREFIX}*"
 # The IPv6 patterns, spelled once because of that same `:' rule -- and here it
 # bites harder than elsewhere: MEASURED with visudo, an unescaped `*::/64' does
 # not merely make the file invalid, it ends the command spec at the first colon
 # and reads the rest of the line as a NEW spec, so the file would grant
 # something nobody wrote. `/' and `*' need nothing.
 local addr6_pattern='*\:\:1/64' net6_pattern='*\:\:/64'
 # The DHCP line is granted only when the script it names cannot be tampered
 # with. Refusing loudly beats granting silently: without this line the NAT
 # bridge still works, guests are simply addressed by hand, as before episode 10c.
 local -a helper_lines=()
 if root_owned_all_the_way "$DHCP_HELPER"; then
   # Three sub-commands, three lines: the trailing globs are harmless because the
   # script itself refuses any call whose argument COUNT is not the one it expects
   # (episodes 10c and 11).
   helper_lines+=("$u ALL=(root) NOPASSWD: $DHCP_HELPER start ${BRIDGE_PREFIX}* *")
   helper_lines+=("$u ALL=(root) NOPASSWD: $DHCP_HELPER start-both ${BRIDGE_PREFIX}* * *")
   helper_lines+=("$u ALL=(root) NOPASSWD: $DHCP_HELPER start-ra ${BRIDGE_PREFIX}* * *")
 elif [[ -z ${DHCP_REFUSAL_SAID:-} ]]; then
   # Said once: the content of a block is generated twice (once to check that it
   # CAN be generated here, once to write it), and one warning is one warning.
   DHCP_REFUSAL_SAID=1
   echo "$TOOL: NOT granting the DHCP service: $DHCP_HELPER is missing, or it (or a directory above it) is not root-owned and unwritable by others." 1>&2
   echo "$TOOL: install Marionnet first, then run this from the INSTALLED scripts -- a NOPASSWD rule on an editable script is a root shell." 1>&2
 fi
 # The IPv6 gate, under exactly the same condition and for the same reason.
 # Without these two lines the NAT bridge still works: it simply stays IPv4-only,
 # and says so (E_NO_IPV6_UPLINK is not the only way IPv6 can be absent).
 if root_owned_all_the_way "$IPV6_HELPER"; then
   helper_lines+=("$u ALL=(root) NOPASSWD: $IPV6_HELPER enable")
   helper_lines+=("$u ALL=(root) NOPASSWD: $IPV6_HELPER disable")
 elif [[ -z ${IPV6_REFUSAL_SAID:-} ]]; then
   IPV6_REFUSAL_SAID=1
   echo "$TOOL: NOT granting the IPv6 gate: $IPV6_HELPER is missing, or it (or a directory above it) is not root-owned and unwritable by others." 1>&2
 fi
 cat <<EOF
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
#
# The IPv6 half (episode 11): the same shapes on the other family, plus the
# gate -- the only two lines here with NO wildcard at all, which is exactly why
# the gate is a script and not three \`sysctl -w' rules.
$u ALL=(root) NOPASSWD: $ip -6 addr add $addr6_pattern dev ${BRIDGE_PREFIX}* nodad
$u ALL=(root) NOPASSWD: $ip -6 addr del $addr6_pattern dev ${BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip6tables -t nat -A POSTROUTING -s $net6_pattern $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j MASQUERADE
$u ALL=(root) NOPASSWD: $ip6tables -t nat -D POSTROUTING -s $net6_pattern $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j MASQUERADE
$u ALL=(root) NOPASSWD: $ip6tables -A FORWARD -i ${BRIDGE_PREFIX}* $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $ip6tables -D FORWARD -i ${BRIDGE_PREFIX}* $bang -o ${BRIDGE_PREFIX}* -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $ip6tables -A FORWARD -o ${BRIDGE_PREFIX}* -m conntrack --ctstate RELATED${comma}ESTABLISHED -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $ip6tables -D FORWARD -o ${BRIDGE_PREFIX}* -m conntrack --ctstate RELATED${comma}ESTABLISHED -m comment --comment $tag -j ACCEPT
$u ALL=(root) NOPASSWD: $ip6tables_save
EOF
 # Appended after the heredoc, and not inside it: a heredoc terminator must sit
 # alone on its line, and optional lines cannot be expressed there.
 local line
 for line in "${helper_lines[@]}"; do echo "$line"; done
}

# --- (c) The LAN bridge -- chantier modernisation-world-bridge, episode 8

# content_lanbridge_rules USER: the LAN bridge rules granted to ONE account (see
# content_lanbridge for the file as a whole). Derived, command
# by command, from `marionnet-lanbridge.sh print-privileged-commands' -- that
# script is the one that runs them, and the single source of the list.
#
# READ THIS BEFORE WIDENING ANYTHING HERE. Blocks (a) and (b) are careful never
# to name the host's own card: they act on ${TAP_PREFIX}* and ${BRIDGE_PREFIX}* devices, and
# nothing else on the machine can be reached through them. Block (c) CANNOT be
# written that way, and no amount of care would change it: a LAN bridge IS the
# host's card, enslaved to a bridge, with the host's address and default route
# moved onto it -- and that card has no fixed name. The last three lines below
# therefore say, in plain words: "$u may reconfigure the IPv4 addressing of this
# host". They make the ${LAN_BRIDGE_PREFIX}*-scoped lines above them redundant,
# and those are kept all the same, because they say what the tool actually does
# and because the day the migration is done differently, dropping the three wide
# lines will be the whole change.
#
# This is precisely why (c) is a block of its own, off by default, asked for from
# the GUI at the moment a LAN bridge component is started, and never granted at
# install time by an administrator who is not the user.
function content_lanbridge_rules {
 local u=$1 ip
 ip=$(ip_binary) || return 1
 # `:' separates host specs in sudoers and must be escaped inside a command
 # argument, or visudo rejects the whole file (measured at episode 3 with `!'
 # and `,'). What sudo compares at runtime is the plain text, so the escaped
 # form still matches the alias the script really sets.
 local colon='\:'
 cat <<EOF
$u ALL=(root) NOPASSWD: $ip link add ${LAN_BRIDGE_PREFIX}* type bridge
$u ALL=(root) NOPASSWD: $ip link del ${LAN_BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip link set ${LAN_BRIDGE_PREFIX}* address *
$u ALL=(root) NOPASSWD: $ip link set ${LAN_BRIDGE_PREFIX}* alias ${LAN_ALIAS_PREFIX}${colon}*
$u ALL=(root) NOPASSWD: $ip link set ${LAN_BRIDGE_PREFIX}* up
$u ALL=(root) NOPASSWD: $ip link set ${LAN_BRIDGE_PREFIX}* down
$u ALL=(root) NOPASSWD: $ip addr add * dev ${LAN_BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip addr del * dev ${LAN_BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip route add default via * dev ${LAN_BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip route del default via * dev ${LAN_BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip link set * master ${LAN_BRIDGE_PREFIX}*
$u ALL=(root) NOPASSWD: $ip link set * nomaster
$u ALL=(root) NOPASSWD: $ip addr del * dev *
$u ALL=(root) NOPASSWD: $ip addr add * dev *
$u ALL=(root) NOPASSWD: $ip route add default via * dev *
EOF
}

# --- Whole files: a header, the marker line, then one group of rules per account

# content_taps USER...: the exact content we install and expect in
# $SUDOERS_FILE_TAPS. The three functions below share one shape, and the loop is
# written out three times rather than factored: each block has its own header,
# and a header is the only place where what is granted is said in words.
function content_taps {
 local u
 cat <<EOF
# Installed by $TOOL -- do not edit by hand, regenerate instead.
# Lets the accounts listed below create and destroy Marionnet's ghost taps
# (${TAP_PREFIX}*) with iproute2. Replaces marionnet-daemon, the former permanent
# root service (chantier marionnet-daemon-elimination).
# Grant one more with: $TOOL install <user>     (the others are kept)
# Take one back with:  $TOOL uninstall <user>
# Take them all back:  $TOOL uninstall
$PRINCIPALS_MARK $*
EOF
 for u in "$@"; do echo; content_taps_rules "$u" || return 1; done
}

function content_natbridge {
 local u
 cat <<EOF
# Installed by $TOOL --enable-natbridge -- do not edit by hand, regenerate instead.
# Lets the accounts listed below build and destroy Marionnet's private NAT bridge
# (${BRIDGE_PREFIX}*), the one marionnet-natbridge.sh creates for the "NAT bridge"
# component (chantier modernisation-world-bridge).
# Take one back with: $TOOL uninstall --disable-natbridge <user>
# Take them all back: $TOOL uninstall --disable-natbridge
$PRINCIPALS_MARK $*
EOF
 for u in "$@"; do echo; content_natbridge_rules "$u" || return 1; done
}

function content_lanbridge {
 local u
 cat <<EOF
# Installed by $TOOL --enable-lanbridge -- do not edit by hand, regenerate instead.
# Lets the accounts listed below build and destroy Marionnet's LAN bridge
# (${LAN_BRIDGE_PREFIX}*), the one marionnet-lanbridge.sh puts the host's own network
# card into, so that virtual machines sit on the REAL local network (chantier
# modernisation-world-bridge).
# Take one back with: $TOOL uninstall --disable-lanbridge <user>
# Take them all back: $TOOL uninstall --disable-lanbridge
#
# The last three lines of each group below are NOT restricted to a device: the
# host's card has no fixed name. Granting them means granting the right to
# reconfigure the IPv4 addressing of this machine. That is what a LAN bridge
# does; it is why this block is separate, and why it is the end user -- not the
# installer -- who asks for it.
$PRINCIPALS_MARK $*
EOF
 for u in "$@"; do echo; content_lanbridge_rules "$u" || return 1; done
}

# --- Blocks as a whole

# block_file BLOCK / block_content BLOCK USER...: the two per-block dispatchers.
# Everything below is written once and applied to whichever blocks were selected.
function block_file {
 case $1 in
   taps)      echo "$SUDOERS_FILE_TAPS" ;;
   natbridge) echo "$SUDOERS_FILE_NATBRIDGE" ;;
   lanbridge) echo "$SUDOERS_FILE_LANBRIDGE" ;;
 esac
}

function block_content {
 local b=$1; shift
 case $b in
   taps)      content_taps      "$@" ;;
   natbridge) content_natbridge "$@" ;;
   lanbridge) content_lanbridge "$@" ;;
 esac
}

# check_block BLOCK USER...: does the installed file grant every USER, and is it
# exactly what we would write now for the accounts IT names? Two questions, and
# both matter: the first is the one that was asked for, the second is what keeps
# a file written when `ip' sat elsewhere from passing as up to date.
# Needs to READ the file, which is 0440 root:root as sudoers files must be: this
# is an admin check, meaningful for root only. What the runtime asks instead is
# "can I run the commands without a password", which Tap_provider.is_usable
# probes with a harmless `sudo -n ip tuntap del' of a tap that does not exist.
function check_block {
 local b=$1; shift
 local f u
 f=$(block_file "$b")
 if [[ ! -r $f ]]; then
   [[ $EUID -eq 0 || ! -e $f ]] || \
     echo "$TOOL: $f exists but is not readable by $(id -un); re-run as root to check it." 1>&2
   return 1
 fi
 local -a granted=()
 read -r -a granted <<<"$(file_principals "$f")"
 for u in "$@"; do
   if ! member_of "$u" "${granted[@]}"; then return 1; fi
 done
 diff -q <(block_content "$b" "${granted[@]}") "$f" >/dev/null
}

# write_block_file BLOCK FILE USER...: generate, validate, adopt. Validated by
# visudo BEFORE being adopted, so a botched generation can never lock the user
# out of sudo. Shared by install and uninstall, which now BOTH rewrite a file.
function write_block_file {
 local b=$1 f=$2; shift 2
 local tmp
 tmp=$(mktemp /tmp/marionnet-sudoers.XXXXXX)
 # Global on purpose: the EXIT trap runs after this function has returned, when a
 # `local' would be long gone (and would abort the script under `set -u'):
 TMPFILE=$tmp
 trap 'rm -f "${TMPFILE:-}"' EXIT
 block_content "$b" "$@" > "$tmp"
 chmod 0440 "$tmp"
 if ! visudo -cf "$tmp" >/dev/null; then
   echo "$TOOL: generated rule for block '$b' REJECTED by visudo; nothing installed." 1>&2
   return 1
 fi
 install -m 0440 -o root -g root "$tmp" "$f"
}

# install_block BLOCK USER...: idempotent -- an up-to-date file is not rewritten
# at all -- and ADDITIVE: the accounts already granted are kept. An `install'
# never narrows a file; `uninstall USER...' is the only way to take a grant back.
function install_block {
 local b=$1; shift
 local f
 f=$(block_file "$b")
 if check_block "$b" "$@" 2>/dev/null; then
   echo "$TOOL: $f is already up to date for: $*." 1>&2
   return 0
 fi
 local -a users=()
 read -r -a users <<<"$(union_principals "$f" "$@")"
 write_block_file "$b" "$f" "${users[@]}" || return 1
 echo "$TOOL: installed $f for: ${users[*]}." 1>&2
}

# uninstall_block BLOCK [USER...]: with no USER the file goes (that is what
# `uninstall' has always meant, and what the packages' removal messages say).
# With USERs, only their rules go, and the file survives for the others -- the
# symmetry install needed: a classroom grants and revokes one student at a time.
function uninstall_block {
 local b=$1; shift
 local f u
 f=$(block_file "$b")
 if (($# == 0)); then
   rm -f "$f"
   echo "$TOOL: removed $f." 1>&2
   return 0
 fi
 # Silently, and on purpose: taking an account back is asked for the three blocks
 # at once (that is what `uninstall USER' means), and two of the three files are
 # normally absent. Saying so three times would bury the one line that matters.
 if [[ ! -e $f ]]; then return 0; fi
 local -a granted=() users=()
 read -r -a granted <<<"$(file_principals "$f")"
 for u in "$@"; do
   if ! member_of "$u" "${granted[@]}"; then
     echo "$TOOL: $f does not grant '$u'; nothing to take back for that account." 1>&2
   fi
 done
 read -r -a users <<<"$(minus_principals "$f" "$@")"
 # Nothing to drop: leave the file alone rather than rewrite it identically. A
 # sudoers file whose mtime moves for no reason is a question an administrator
 # should never have to ask.
 if [[ "${users[*]}" = "${granted[*]}" ]]; then return 0; fi
 if ((${#users[@]} == 0)); then
   rm -f "$f"
   echo "$TOOL: removed $f (no account left in it)." 1>&2
   return 0
 fi
 write_block_file "$b" "$f" "${users[@]}" || return 1
 echo "$TOOL: rewrote $f for: ${users[*]}." 1>&2
}

# --- Command line
#
# The selection is the same for every subcommand, which is why it is parsed once:
# block (a) is implicit (`install' alone is the administrator's install-time
# gesture), --enable-* add the others. `uninstall' inverts the defaults -- it
# removes everything unless --disable-* names a subset.

BLOCKS=()
COMMAND=""
PRINCIPALS=()
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
     *) PRINCIPALS+=("$a") ;;
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
#
# Until episode 8 this was a special case for (c), whose content REFUSED to be
# produced (marionnet-lanbridge.sh did not exist yet). Now that all three blocks
# generate, the check is the general one it should always have been: every
# selected block must be producible -- `ip_binary' and friends can still fail on
# a machine missing a package.
function available_blocks_or_die {
 local b rc=0
 if [[ $1 = uninstall ]]; then return 0; fi
 for b in "${BLOCKS[@]}"; do
   block_content "$b" "${PRINCIPALS[@]}" >/dev/null || rc=$?
   if [[ $rc -ne 0 ]]; then
     echo "$TOOL: block '$b' cannot be generated on this machine; nothing installed." 1>&2
     exit $rc
   fi
 done
 return 0
}

# principals_for_install BLOCK: what `install' would put in that block's file --
# the accounts it already grants, plus the ones just named. Used by `print' too,
# so that what is shown is what would be written. Non-root cannot read the file
# (0440), and then this is just the accounts named on the command line: `print'
# stays useful without privilege, and says less rather than something false.
function principals_for_install {
 union_principals "$(block_file "$1")" "${PRINCIPALS[@]}"
}

parse_command_line "$@" || { usage; exit 2; }
# `uninstall' with no account means the whole file, as it always has; every other
# command needs somebody, and that somebody defaults to the caller.
if ((${#PRINCIPALS[@]} == 0)) && [[ $COMMAND != uninstall ]]; then
  PRINCIPALS=("$(default_user)")
fi
# Never for `uninstall': the account to drop may be exactly the one that should
# never have existed here.
case "$COMMAND" in
  print|check|install) known_principal_or_die "${PRINCIPALS[@]}" || exit 2 ;;
esac
case "$COMMAND" in print|check|install|uninstall) available_blocks_or_die "$COMMAND" ;; esac

case "$COMMAND" in
  print)
     for b in "${BLOCKS[@]}"; do
       echo "# >>> $(block_file "$b")"
       # shellcheck disable=SC2046 -- word splitting is what turns the list into arguments
       block_content "$b" $(principals_for_install "$b")
     done
     ;;
  check)
     rc=0
     for b in "${BLOCKS[@]}"; do check_block "$b" "${PRINCIPALS[@]}" || rc=1; done
     exit $rc
     ;;
  install|uninstall)
     if [[ $EUID -ne 0 ]]; then
       echo "$TOOL: this requires root; re-executing with sudo." 1>&2
       if [[ $COMMAND = install ]]; then
         # shellcheck disable=SC2046 -- see principals_for_install
         for b in "${BLOCKS[@]}"; do block_content "$b" $(principals_for_install "$b") | sed 's/^/    /' 1>&2; done
       fi
       # "$@" and not a rebuilt command line: the user's own words go through,
       # so a re-exec can never grant a block the caller did not ask for.
       exec sudo -- "$0" "$@"
     fi
     for b in "${BLOCKS[@]}"; do
       if [[ $COMMAND = install ]]
         then install_block   "$b" "${PRINCIPALS[@]}"
         else uninstall_block "$b" "${PRINCIPALS[@]}"
       fi
     done
     ;;
  -h|--help) usage ;;
  *)         usage; exit 2 ;;
esac
