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

# --- The administrator's veto (episode 37)
#
# `deny --lanbridge' writes a marker here, and blocks (b) and (c) then refuse to
# be installed at all. Why a directory of our own rather than sudoers.d: the
# marker must be READABLE WITHOUT PRIVILEGE, because the GUI has to know the
# verdict BEFORE asking for a password (bin/privileges.ml asks, then runs), and
# a sudoers.d file is 0440 root -- as it must be. Anything dropped in sudoers.d
# is also parsed BY SUDO, which is no place for a file that is not a rule.
#
# The path is absolute and prefix-independent, exactly like /etc/sudoers.d: a
# veto is a decision about THIS MACHINE, not about one installation of Marionnet.
# It is what an administrator can say, and it is worth being honest about what it
# is worth: it guards against the MISTAKE -- the teacher who clicks "yes" without
# reading and turns the host's card into a bridge -- not against a full sudoer,
# who edits /etc/sudoers.d directly and needs nobody's permission.
POLICY_DIR=${MARIONNET_SUDOERS_POLICY_DIR:-/etc/marionnet}

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

# And the same again for the device the taps are made of. /dev is volatile
# everywhere -- a devtmpfs rebuilt at every boot on a machine of its own, where
# udev puts /dev/net/tun back by itself, and a FRESH tmpfs at every start inside a
# container, where nothing does. So the node cannot be provided once at
# installation time: Marionnet asks for it at each start-up, through this door
# (its header says the rest). It takes no variable argument either, so its single
# line is entirely literal. It belongs to the socle because granting the socle
# already means "this account may create taps", and the node is the precondition
# of that very act: without it `ip tuntap' answers `open: No such file or
# directory' and the whole block grants nothing usable.
TUN_HELPER=$SCRIPT_DIR/marionnet-tun-device.sh

# And these two with bin/scripts/marionnet-lanbridge.sh (BRIDGE_PREFIX and
# ALIAS_PREFIX there):
LAN_BRIDGE_PREFIX=mnlan
LAN_ALIAS_PREFIX=marionnet-lanbridge

TOOL=$(basename "$0")

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL print     [BLOCKS] [USER...]  # write the expected sudoers rules on stdout
       $TOOL check     [BLOCKS] [USER...]  # exit 0 iff every selected block is up to date and
                                           #   grants every USER (root only: the files are 0440);
                                           #   4 if granted but STALE, 5 if granted and sudo
                                           #   REFUSES it anyway, 1 if not granted.
                                           #   Bare, it is a question about the FILE: no account
                                           #   is implied. --explain names what is out of date.
       $TOOL install   [BLOCKS] [USER...]  # grant them; needs root (re-execs with sudo)
       $TOOL uninstall [BLOCKS] [USER...]  # take the grant back; needs root (re-execs with sudo)
       $TOOL deny      BLOCK               # forbid a bridge block on this machine; needs root
       $TOOL allow     BLOCK               # lift that veto; needs root
       $TOOL policy    [BLOCK]             # exit 0 if allowed, 3 if denied (no privilege needed)

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

\`check' answers about the principals a file NAMES -- a member of a granted group
is not a principal -- and, since episode 48, about whether sudo HONOURS what the
file says: it exits 5 when the grant is there and sudo refuses it anyway, which a
broader rule parsed after this file does silently. Do NOT use \`sudo -l -U <login>'
for that: measured, it answers "may this user run it", not "without a password"
(\`sudo -n -l /bin/true' exits 0 on a machine where running it would prompt). The
question about effective rights is asked by running one of the granted commands
under \`sudo -n', which is what \`check' now does.

THE VETO. \`deny --lanbridge' (or --natbridge, or --bridges) forbids that block on
this machine: it is then refused to everybody, the grant already in place is taken
back, and Marionnet says so in its interface instead of asking for a password.
\`allow' lifts it -- and grants nothing: a user still has to ask. Block (a) has no
veto: the administrator grants it himself, by hand, so forbidding it would be not
typing the command. What a veto is worth, plainly: it stops the MISTAKE, not a
full sudoer, who edits ${SUDOERS_DIR} directly and needs nobody's permission.

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
 local u=$1 ip owner why=""
 local -a helper_lines=()
 ip=$(ip_binary) || return 1
 # The device the taps are made of, granted only when the script that provides it
 # cannot be tampered with -- same condition as the DHCP and IPv6 helpers of
 # block (b), and for the same reason (a NOPASSWD rule naming a script a non-root
 # account can replace is a root shell for that account). Refusing loudly beats
 # granting silently: without this line Marionnet still works wherever the node is
 # already there, which is every machine of its own, and says what is missing
 # where it is not.
 if why=$(root_owned_all_the_way "$TUN_HELPER"); then
   helper_lines+=("$u ALL=(root) NOPASSWD: $TUN_HELPER create")
 elif [[ -z ${TUN_REFUSAL_SAID:-} ]]; then
   # Said once: the content of a block is generated twice (once to check that it
   # CAN be generated here, once to write it), and one warning is one warning.
   TUN_REFUSAL_SAID=1
   echo "$TOOL: NOT granting the tun device: $why." 1>&2
   helper_refusal_advice "$why"
 fi
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
 local line
 for line in ${helper_lines[@]+"${helper_lines[@]}"}; do echo "$line"; done
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
#
# Returns 0 and prints nothing when the path is usable. Otherwise it PRINTS THE
# CAUSE on stdout -- one sentence, the only true one -- and returns 1. Naming it is
# not a nicety: this refusal used to read "is missing, or it (or a directory above
# it) is not root-owned and unwritable by others", three very different situations
# in one `or', leaving the administrator to guess. MEASURED in a classroom
# container where both helpers were present, root-owned and 0755, and the fault was
# /usr and /usr/bin at 775, two levels up -- which is why the path NAMED here is
# the one that fails, never the argument. Same lesson as episodes 40 and 41: a
# warning must name its cause.
function root_owned_all_the_way {
 local path=$1 owner mode fault out=""
 local -a faults=()
 path=$(readlink -f "$path" 2>/dev/null) || { echo "no such file: $1"; return 1; }
 [[ -e $path ]] || { echo "no such file: $path"; return 1; }
 # The WHOLE chain is walked even after a fault, and every fault is reported. On the
 # machine that prompted this both /usr and /usr/bin were 775: stopping at the first
 # one would have had the administrator run the command, fix one directory, run it
 # again, fix the other -- a remedy delivered one instalment at a time.
 while : ; do
   read -r owner mode < <(stat -c '%u %a' "$path") || { echo "cannot stat: $path"; return 1; }
   [[ $owner = 0 ]] || faults+=("$path is owned by uid $owner, not by root")
   # No write bit for group or other. Counted from the RIGHT: %a is three digits,
   # or four when a setuid/sticky bit is set.
   (( (0${mode: -2:1} & 2) == 0 && (0${mode: -1} & 2) == 0 )) || \
     faults+=("$path is mode $mode, writable by group or others")
   if [[ $path = / ]]; then break; fi
   path=$(dirname "$path")
 done
 ((${#faults[@]})) || return 0
 # Joined by "; " -- helper_refusal_advice splits on the semicolon to gather the
 # paths of each kind, so that one `chmod' names them all.
 for fault in "${faults[@]}"; do out+="${out:+; }$fault"; done
 echo "$out"
 return 1
}

# helper_refusal_advice CAUSE: the remedies that match CAUSE -- as produced by
# root_owned_all_the_way, which may report several faults joined by "; " -- said once
# per distinct advice. This used to be a single unconditional line, "install Marionnet
# first, then run this from the INSTALLED scripts", which on the machine that prompted
# this (Marionnet installed, /usr and /usr/bin at 775) was simply FALSE. Saying the
# same advice twice buries it, since the two helpers sit in the same directory and so
# usually fail for the same reason; two DIFFERENT causes still get two.
#
# The cause is parsed back from the string because root_owned_all_the_way runs in a
# command substitution: a subshell, which can hand nothing back but its output.
function helper_refusal_advice {
 local cause=$1 part advice="" install_needed=0
 local -a modes=() owners=() lines=()
 local IFS=';'
 for part in $cause; do
   part=${part# }
   case $part in
     "no such file: "*)     install_needed=1 ;;
     *" is mode "*)         modes+=("${part%% is mode *}") ;;
     *" is owned by uid "*) owners+=("${part%% is owned by uid *}") ;;
   esac
 done
 IFS=' '
 ((install_needed)) && lines+=("install Marionnet first, then run this from the INSTALLED scripts -- a NOPASSWD rule on an editable script is a root shell.")
 ((${#owners[@]})) && lines+=("give the path(s) back to root (\`chown root ${owners[*]}') and run this again -- a NOPASSWD rule naming a script its owner can replace is a root shell for that owner.")
 ((${#modes[@]})) && lines+=("remove the group and other write bits (\`chmod go-w ${modes[*]}') and run this again -- a NOPASSWD rule naming a script that a non-root account can replace is a root shell for that account.")
 ((${#lines[@]})) || return 0
 for part in "${lines[@]}"; do advice+="${advice:+
}$part"; done
 [[ ${HELPER_ADVICE_SAID:-} = "$advice" ]] && return 0
 HELPER_ADVICE_SAID=$advice
 for part in "${lines[@]}"; do echo "$TOOL: $part" 1>&2; done
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
 local why=""
 if why=$(root_owned_all_the_way "$DHCP_HELPER"); then
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
   echo "$TOOL: NOT granting the DHCP service: $why." 1>&2
   helper_refusal_advice "$why"
 fi
 # The IPv6 gate, under exactly the same condition and for the same reason.
 # Without these two lines the NAT bridge still works: it simply stays IPv4-only,
 # and says so (E_NO_IPV6_UPLINK is not the only way IPv6 can be absent).
 if why=$(root_owned_all_the_way "$IPV6_HELPER"); then
   helper_lines+=("$u ALL=(root) NOPASSWD: $IPV6_HELPER enable")
   helper_lines+=("$u ALL=(root) NOPASSWD: $IPV6_HELPER disable")
 elif [[ -z ${IPV6_REFUSAL_SAID:-} ]]; then
   IPV6_REFUSAL_SAID=1
   echo "$TOOL: NOT granting the IPv6 gate: $why." 1>&2
   helper_refusal_advice "$why"
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

# policy_file BLOCK: where the veto on BLOCK is written. Block (a) has none, and
# that is not an omission: the socle is granted by the administrator TO somebody,
# at install time, by hand. There is nothing to forbid -- forbidding it would be
# not typing the command.
function policy_file {
 case $1 in
   natbridge) echo "$POLICY_DIR/natbridge.denied" ;;
   lanbridge) echo "$POLICY_DIR/lanbridge.denied" ;;
 esac
}

function block_is_denied {
 local f
 f=$(policy_file "$1")
 [[ -n $f && -e $f ]]
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
#
# TWO questions, therefore TWO answers, and they are not the same news: 1 says
# the grant is NOT there, 4 says it is there but STALE -- the file was written by
# an older version of this script and does not name everything we would name now
# (the tun device door of `marionnet-tun-device.sh' is exactly such a line: a
# machine granted before it existed has a file that passes for granted and does
# not carry it). Whoever asks needs to tell those apart to say the right thing;
# the file itself is the only place that knows, so the distinction is made here
# rather than guessed by the caller. The old contract -- 0 versus non-0 -- is
# untouched for everybody who only ever asked "is it granted?".
CHECK_STALE=4
# A FOURTH state, and the classroom paid for it (2026-09-06). `check' above reads
# the FILE: it answers "does /etc/sudoers.d/marionnet say what we would write?".
# That question is worth asking and it is not the one that decides. In sudoers the
# LAST matching rule wins, so a broader entry parsed AFTER ours -- a plain
# `student ALL=(ALL:ALL) ALL' dropped in /etc/sudoers.d/student, which sorts after
# `marionnet' -- silently cancels every NOPASSWD line of a file that is perfect.
# Measured: the file granted, `install' answered "already up to date", and sudo
# asked for a password on every privileged gesture of the application.
#
# The only authority is sudo, and it has to be ASKED THE REAL QUESTION: `sudo -l'
# will not do -- measured, it answers "may this user run it", not "without a
# password" (`sudo -n -l /bin/true' exits 0 on a machine where running it prompts).
# So the probe is the one the runtime itself uses (Tap_provider.unavailability):
# `sudo -n ip tuntap del' of a tap that does not exist -- a successful no-op when
# the grant works, and covered by the very rule we are checking.
#
# The needles are sudo's REFUSALS, and they are the same four as
# bin/tap_provider.ml (unavailability_of_error): the two sides read the same
# sentences and must keep agreeing. LC_ALL/LANGUAGE are frozen for the same reason
# as there -- a French sudo says `il est necessaire de saisir un mot de passe', and
# that is exactly how this defect stayed invisible.
CHECK_REFUSED=5
function sudo_refusal_for {
 local u=$1 out ip
 ip=$(ip_binary) || return 1
 local -a probe=(env LC_ALL=C LANGUAGE= sudo -n "$ip" tuntap del dev "${TAP_PREFIX}probe" mode tap)
 if [[ $EUID -eq 0 && $u != root ]]; then
   command -v runuser >/dev/null || return 1   # cannot ask on someone else's behalf
   out=$(runuser -u "$u" -- "${probe[@]}" 2>&1)
 elif [[ $EUID -ne 0 && $u != "$(id -un)" ]]; then
   return 1                                    # only root may ask for another account
 else
   out=$("${probe[@]}" 2>&1)
 fi
 case $out in
   *"a password is required"*|*"not allowed to execute"*|*"may not run"*|*"no tty present"*)
     printf '%s\n' "$out"; return 0 ;;
 esac
 return 1
}

# report_refusal BLOCK USER...: says, for the accounts it can ask about, that the
# file grants them and sudo refuses anyway -- and names the mechanism, because
# "sudo refuses" without "a later rule wins" sends an administrator to re-install
# a file which is already right. Group principals (%name) are skipped: one cannot
# run a command on behalf of a group.
function report_refusal {
 local b=$1; shift
 local u out found=1
 for u in "$@"; do
   [[ $u == %* ]] && continue
   out=$(sudo_refusal_for "$u") || continue
   found=0
   echo "$TOOL: $(block_file "$b") grants $u, but sudo REFUSES it:" 1>&2
   echo "$TOOL:   $(head -1 <<<"$out")" 1>&2
   echo "$TOOL: in sudoers the LAST matching rule wins, so a broader entry parsed" 1>&2
   echo "$TOOL: after this file cancels it. Look for one, and make it parse FIRST:" 1>&2
   echo "$TOOL:   sudo -ll ; ls /etc/sudoers.d/" 1>&2
   echo "$TOOL: (files are read in lexical order; renaming the broad one 00-<name>" 1>&2
   echo "$TOOL:  puts it before this one, without changing what it grants)." 1>&2
 done
 return $found
}
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
 diff -q <(block_content "$b" "${granted[@]}") "$f" >/dev/null || return $CHECK_STALE
}

# granted_commands: the COMMANDS a block file grants, one per line, sorted and
# deduplicated -- the right-hand side of `<principal> ALL=(root) NOPASSWD: ...'.
# The principal is dropped on purpose: WHO is granted is the other question, the
# one `check USER' answers; this one is about WHAT the file allows.
function granted_commands {
 sed -n 's/^[^[:space:]]* ALL=(root) NOPASSWD: //p' | sort -u
}

# explain_block BLOCK: what refreshing the file would change, in the only terms
# that mean anything to an administrator -- commands gained (`+') and lost (`-').
# MEASURED, never illustrated: the message which sent us here named /dev/net/tun
# as an example baked into its own text, which happened to be right on the machine
# that reported it and would have been wrong on the next one (episodes 40 and 41:
# a warning names the cause it measured).
#
# Prints nothing when the two sets agree -- which is a REAL case, not an oversight:
# the file may differ by its header or by its `# principals:' line alone. Whoever
# asks must have a sentence for that, and marionnet-setup-check.sh has one.
function explain_block {
 local b=$1 f installed now
 f=$(block_file "$b")
 [[ -r $f ]] || return 0
 local -a granted=()
 read -r -a granted <<<"$(file_principals "$f")"
 now=$(block_content "$b" ${granted[@]+"${granted[@]}"} | granted_commands) || return 0
 installed=$(granted_commands < "$f")
 comm -13 <(echo "$installed") <(echo "$now") | sed '/^$/d; s/^/+ /'
 comm -23 <(echo "$installed") <(echo "$now") | sed '/^$/d; s/^/- /'
 return 0
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
   # What the FILE grants, not what was asked for -- the very thing the line below
   # says when it writes. Since `install' became additive (a classroom grants one
   # student at a time), printing "$*" here UNDER-REPORTED the file: asked for
   # `teacher' on a file granting `teacher student', it answered "already up to
   # date for: teacher", which reads as though student had been dropped.
   echo "$TOOL: $f is already up to date for: $(file_principals "$f")." 1>&2
   # ... which is a statement about the FILE. Whether sudo honours it is another
   # question, and the one the user actually asked (episode 48).
   report_refusal "$b" $(file_principals "$f") || true
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

# --- The veto

# deny_block BLOCK: write the marker, and TAKE BACK the grant if there is one.
# Leaving a granted file behind a veto would make the veto a lie -- and the file
# is what sudo actually reads.
function deny_block {
 local b=$1 f g
 f=$(policy_file "$b")
 g=$(block_file "$b")
 mkdir -p "$POLICY_DIR"
 chmod 0755 "$POLICY_DIR"
 cat > "$f" <<EOF
# Written by $TOOL deny -- the administrator of this machine has disabled
# Marionnet's '$b' block. While this file exists:
#   * $TOOL refuses to install that block, for anybody;
#   * Marionnet says so in its interface instead of asking for a password.
# Lift it with: $TOOL allow --$b
# Denied on: $(date -Is)
EOF
 chmod 0644 "$f"
 echo "$TOOL: '$b' is now denied on this host ($f)." 1>&2
 if [[ -e $g ]]; then
   rm -f "$g"
   echo "$TOOL: the grant that was in place has been taken back ($g)." 1>&2
 fi
}

function allow_block {
 local b=$1 f
 f=$(policy_file "$b")
 if [[ ! -e $f ]]; then
   echo "$TOOL: '$b' was not denied; nothing to lift." 1>&2
   return 0
 fi
 rm -f "$f"
 echo "$TOOL: '$b' is allowed again ($f removed). Nothing is granted by this: a user still has to ask." 1>&2
}

# report_policy BLOCK: one line per DENIED block, on STDOUT -- this is the only
# subcommand whose stdout is read by another program (the GUI shows it to the
# user), and the only one that needs no privilege whatsoever.
function report_policy {
 local b=$1 f
 f=$(policy_file "$b")
 if [[ -e $f ]]; then
   echo "$b: denied by the administrator of this machine ($f)"
   return 3
 fi
 return 0
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
EXPLAIN=false

function parse_command_line {
 local a
 COMMAND=${1:-}; shift || true
 for a in "$@"; do
   case "$a" in
     # The neutral spellings (--natbridge, --lanbridge, --bridges) say WHICH
     # block without saying what is done to it, and work everywhere. `deny',
     # `allow' and `policy' take only those: `deny --enable-lanbridge' would be
     # a sentence that contradicts itself.
     --enable-natbridge|--disable-natbridge|--natbridge)   WANT_NAT=true; EXPLICIT_SELECTION=true ;;
     --enable-lanbridge|--disable-lanbridge|--lanbridge)   WANT_LAN=true; EXPLICIT_SELECTION=true ;;
     --enable-bridges|--disable-bridges|--bridges)         WANT_NAT=true; WANT_LAN=true; EXPLICIT_SELECTION=true ;;
     --only)                                   ONLY=true ;;
     --explain)                                EXPLAIN=true ;;
     -*) echo "$TOOL: unknown option '$a'" 1>&2; return 2 ;;
     *) PRINCIPALS+=("$a") ;;
   esac
 done
 # --only is a modifier of the selection, not a selection: on its own it would
 # mean "apply to nothing", which is never what anybody meant.  And on `uninstall'
 # it would be noise: --disable-* already leaves (a) alone.
 if $EXPLAIN && [[ $COMMAND != check ]]; then
   echo "$TOOL: --explain belongs to 'check': it says what is out of date, and changes nothing" 1>&2
   return 2
 fi
 if $ONLY; then
   case $COMMAND in
     uninstall)
       echo "$TOOL: --only makes no sense for 'uninstall' (--disable-* already spares block (a))" 1>&2
       return 2 ;;
     deny|allow|policy)
       echo "$TOOL: --only makes no sense for '$COMMAND': it applies to the named block and to nothing else" 1>&2
       return 2 ;;
   esac
   if ! $EXPLICIT_SELECTION; then
     echo "$TOOL: --only needs a selection (--enable-natbridge, --enable-lanbridge or --enable-bridges)" 1>&2
     return 2
   fi
 fi
 # `if' rather than `$WANT_NAT && BLOCKS+=(...)': under `set -e' the latter is a
 # failing AND-list whenever the flag is false, which is exactly the kind of
 # silent early exit this script must not have.
 if [[ $COMMAND = deny || $COMMAND = allow || $COMMAND = policy ]]; then
   # These three never reach block (a): it has no veto (see policy_file), and a
   # principal makes no sense for them -- a veto holds for everybody.
   if ((${#PRINCIPALS[@]} > 0)); then
     echo "$TOOL: '$COMMAND' takes no USER: a veto holds for everybody on this machine" 1>&2
     return 2
   fi
   if $WANT_NAT; then BLOCKS+=(natbridge); fi
   if $WANT_LAN; then BLOCKS+=(lanbridge); fi
   if ! $EXPLICIT_SELECTION; then
     if [[ $COMMAND = policy ]]; then
       # A bare `policy' is a question about the machine: answer for both blocks.
       BLOCKS=(natbridge lanbridge)
     else
       echo "$TOOL: '$COMMAND' needs a block: --natbridge, --lanbridge or --bridges" 1>&2
       return 2
     fi
   fi
 elif [[ $COMMAND = uninstall ]]; then
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

# denied_blocks_or_die: refuse BEFORE touching anything, like
# available_blocks_or_die and for the same reason. A veto is not a warning: the
# administrator said no, and `install' does not argue -- it names the marker and
# the command that lifts it. Exit code 3, which the GUI tells apart from a
# refused password (1) and from a usage error (2).
function denied_blocks_or_die {
 local b denied=false
 for b in "${BLOCKS[@]}"; do
   if block_is_denied "$b"; then
     echo "$TOOL: '$b' is denied on this host by $(policy_file "$b"); nothing installed." 1>&2
     echo "$TOOL: an administrator lifts it with: $TOOL allow --$b" 1>&2
     denied=true
   fi
 done
 $denied && exit 3
 return 0
}

parse_command_line "$@" || { usage; exit 2; }
# `uninstall' with no account means the whole file, as it always has; `deny',
# `allow' and `policy' take no account at all; `print' and `install' need somebody
# -- they PRODUCE a content, which has to name an account -- and that somebody
# defaults to the caller.
#
# `check' is NOT in that list, and the difference is the whole point: it produces
# nothing, so it has no "for whom?" to fill in. Bare, it is a question about the
# FILE -- is it up to date for the accounts it names -- which is what its own
# header says and what the administrator's guide promises. Adding $SUDO_USER to it
# silently asked something else, and answered 1 ("not granted") on a machine where
# the file grants somebody ELSE: measured on a classroom case -- teacher granted,
# `apt upgrade' run by root -- where the postinst then told the administrator that
# Marionnet could not build a tap, which was false. Naming USERs still asks the
# other question, and asks it of every one of them.
case "$COMMAND" in
  print|install)
     if ((${#PRINCIPALS[@]} == 0)); then PRINCIPALS=("$(default_user)"); fi ;;
esac
# Never for `uninstall': the account to drop may be exactly the one that should
# never have existed here.
case "$COMMAND" in
  print|check|install) known_principal_or_die "${PRINCIPALS[@]}" || exit 2 ;;
esac
case "$COMMAND" in print|check|install|uninstall) available_blocks_or_die "$COMMAND" ;; esac
case "$COMMAND" in install) denied_blocks_or_die ;; esac

case "$COMMAND" in
  print)
     for b in "${BLOCKS[@]}"; do
       echo "# >>> $(block_file "$b")"
       # shellcheck disable=SC2046 -- word splitting is what turns the list into arguments
       block_content "$b" $(principals_for_install "$b")
     done
     ;;
  check)
     # The worst verdict of the selected blocks wins, and "not granted" is worse
     # than "stale": a caller which learns 4 is told to REFRESH a grant, which
     # would be the wrong advice for a block that has none.
     rc=0
     for b in "${BLOCKS[@]}"; do
       brc=0
       check_block "$b" ${PRINCIPALS[@]+"${PRINCIPALS[@]}"} || brc=$?
       if [[ $brc -ne 0 ]]; then
         if [[ $brc -eq $CHECK_STALE && $rc -ne 1 ]]; then rc=$CHECK_STALE; else rc=1; fi
         if $EXPLAIN; then
           if ((${#BLOCKS[@]} > 1)); then echo "# >>> $(block_file "$b")"; fi
           explain_block "$b"
         fi
       # The file is right; ask the only authority whether it is EFFECTIVE. Worse
       # than "stale" and better than "not granted": the grant exists, something
       # else cancels it, and re-installing would change nothing.
       elif report_refusal "$b" $(file_principals "$(block_file "$b")"); then
         if [[ $rc -eq 0 ]]; then rc=$CHECK_REFUSED; fi
       fi
     done
     exit $rc
     ;;
  policy)
     # No privilege, and none needed: this is the question the GUI asks before it
     # asks anything of the user. Silence means "allowed".
     rc=0
     for b in "${BLOCKS[@]}"; do report_policy "$b" || rc=3; done
     exit $rc
     ;;
  install|uninstall|deny|allow)
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
       case "$COMMAND" in
         install)   install_block   "$b" "${PRINCIPALS[@]}" ;;
         uninstall) uninstall_block "$b" "${PRINCIPALS[@]}" ;;
         deny)      deny_block  "$b" ;;
         allow)     allow_block "$b" ;;
       esac
     done
     ;;
  -h|--help) usage ;;
  *)         usage; exit 2 ;;
esac
