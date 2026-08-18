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
# THE ONE PRIVILEGED ENTRY POINT OF THE DHCP SERVICE of the NAT bridge
# (work-stream modernisation-world-bridge, episode 10c). It is run as root by
# marionnet-natbridge.sh through sudo, and by nothing else.
#
# --- WHY A SEPARATE SCRIPT, AND WHY SO SMALL ---
#
# dnsmasq needs root only to bind the DHCP port (67) and to open its files; it
# then drops to the calling user (--user/--group), which is what lets Marionnet
# KILL IT WITHOUT SUDO afterwards. A sudoers `kill' rule would be a complete
# escalation; dropping privileges is the whole trick.
#
# But the dnsmasq command line contains two values that vary (the bridge name
# and the /24 prefix), and a sudoers rule with a wildcard argument CANNOT be
# scoped tightly enough. Measured on this very repository (episode 10c, and
# already seen at 7b bis): with the installed rule
#
#     ... NOPASSWD: /usr/sbin/ip link add mnbr* type bridge
#
# the command `ip link add mnbr999999 --INJECT type bridge' is ACCEPTED by sudo
# -- a `*' in an argument swallows whole extra words, even in the MIDDLE of the
# rule. A rule such as `dnsmasq ... --pid-file=* ...' would therefore let anyone
# slip in `--dhcp-script=/tmp/evil', i.e. run arbitrary code as root.
#
# Hence this file: the sudoers rule grants ONE command whose arguments are
# validated IN ROOT, by anchored regexps, before anything happens -- the wide
# glob of the rule is caught by a check that itself runs as root. The dnsmasq
# command line is written HERE, in full, and nothing of it can be influenced
# from the outside:
#
#   * no library is sourced (bashbricks would be a large surface running as
#     root, and it is not nounset-clean either);
#   * no environment variable is read except SUDO_USER, which sudo itself sets;
#   * no PATH lookup: every binary is an absolute path;
#   * no path is ever accepted as an argument -- the pid file and the lease file
#     are computed here, under RUN_DIR.
#
# --- THE CONTRACT WITH marionnet-natbridge.sh ---
#
#   start <BRIDGE> <NET>              DHCPv4 only (episode 10c)
#   start-both <BRIDGE> <NET> <A6>    DHCPv4 + IPv6 Router Advertisements
#   start-ra <BRIDGE> <NET> <A6>      Router Advertisements only, no DHCPv4
#
#                          BRIDGE is mnbr<pid>[-<instance>], NET a /24 prefix
#                          such as 192.168.101, A6 the IPv6 address of the
#                          bridge, always of the shape <prefix>::1/64. The
#                          bridge MUST already exist and already carry
#                          <NET>.1/24 -- and, for the two IPv6 forms, A6 as
#                          well -- that is what proves it is one of ours, built
#                          through sudoers block (b).
#                          Idempotent: an already running server of ours is a
#                          success.
#   stdout                 the pid of dnsmasq, alone on one line, and nothing
#                          else. stderr carries the human trace.
#   exit status            0 on success, non-zero on failure.
#
# Why three sub-commands rather than one with optional arguments (episode 11):
# the guard that kills argument injection is "this sub-command takes EXACTLY n
# arguments" (see below). A single `start' with a variable arity, or with a `-'
# standing for "no IPv6", would trade that guard for a sentinel to be parsed --
# and the four on/off combinations of DHCPv4 and RA cannot be told apart by a
# count alone. One name per shape keeps every arity fixed.
#
# Stopping is NOT here, and that is deliberate: the server runs as the user, so
# marionnet-natbridge.sh kills it with a plain TERM, by pid read from the pid
# file, with no privilege at all.
# ---------------------------------------------------------------------------

set -euo pipefail

TOOL=$(basename "$0")

# --- Constants. BRIDGE_PREFIX and RUN_DIR are part of the contract with
# --- bin/scripts/marionnet-natbridge.sh (same names there): do not change one
# --- of them alone.

BRIDGE_PREFIX=mnbr
RUN_DIR=/run/marionnet-natbridge

# Set by do_start to $RUN_DIR/<uid of the target user>. One directory per user,
# owned by that user: root keeps the parent (nobody may squat a name in it), and
# each user may delete their own pid and lease files -- which the caller does at
# `down', and could not do when everything sat in a root-owned directory.
USER_RUN_DIR=""

# The guest range inside the /24. It excludes .1 (the bridge itself) by a wide
# margin, so that a teacher may still hand out static addresses below .100.
DHCP_FIRST=100
DHCP_LAST=200
DHCP_LEASE_TIME=1h

# The lifetime carried by the Router Advertisements (episode 11). Kept equal to
# the DHCPv4 lease on purpose: a student comparing the two reads one number, and
# a prefix that stops being advertised expires within the hour instead of
# lingering for a day on the guests.
RA_LIFETIME=1h

IP=""
DNSMASQ=""

function die {
  echo "$TOOL: $*" 1>&2
  exit 1
}

# binary_among WHAT CANDIDATE...: absolute path of a tool. A fixed candidate
# list, never $PATH: this runs as root, and root's PATH is not the user's.
function binary_among {
  local what=$1 candidate; shift
  for candidate in "$@"; do
    [[ -x $candidate ]] && { echo "$candidate"; return 0; }
  done
  die "$what not found (none of $* is executable)"
}

function resolve_binaries {
  IP=$(binary_among iproute2 /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip)
  DNSMASQ=$(binary_among dnsmasq /usr/sbin/dnsmasq /sbin/dnsmasq /usr/bin/dnsmasq)
}

# --- Validators.
#
# Everything below runs as root with a command line that sudo did NOT restrict
# (see the header). These are therefore not hygiene, they are THE guard.

function valid_bridge {
  local name=$1
  [[ $name =~ ^${BRIDGE_PREFIX}[1-9][0-9]*(-[1-9][0-9]*)?$ ]] || return 1
  (( ${#name} <= 15 )) || return 1   # IFNAMSIZ - 1; the kernel refuses, it does not truncate
}

function valid_subnet {
  local net=$1 byte
  [[ $net =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]] || return 1
  for byte in ${net//./ }; do
    (( byte >= 0 && byte <= 255 )) || return 1
  done
  # `if', not `[[ ... ]] && ...': under `set -e' a false test as the last command
  # of a function makes the function return 1, which here would mean the opposite.
  if [[ $net =~ ^0\. ]]; then return 1; fi
  return 0
}

# valid_address6 A6: the IPv6 address of the bridge, and nothing else. The shape
# is deliberately narrow -- <prefix>::1/64, lower case, one to four hex groups --
# because that is exactly what Marionnet computes, and because the prefix
# announced to the guests is then derived by removing a fixed suffix rather than
# by parsing. A /64 is not a taste: SLAAC does not work on anything else.
function valid_address6 {
  local a=$1
  [[ $a =~ ^[0-9a-f]{1,4}(:[0-9a-f]{1,4}){0,3}::1/64$ ]] || return 1
  # Link-local (fe80::/10), the deprecated site-local range and multicast
  # (ff00::/8) are not networks one advertises; `::1/64' alone (no group at all) is
  # the loopback, and the regexp above already refuses it. `f[ef]' and not `fe80'
  # so that fe81:: does not slip through -- and it leaves fc00::/7 (the ULA range,
  # which is what we normally get) alone.
  if [[ $a =~ ^f[ef] ]]; then return 1; fi
  return 0
}

# prefix6_of_address6 A6: the prefix dnsmasq must advertise, e.g.
# fd00:192:168:101::1/64 -> fd00:192:168:101::. Safe only because
# valid_address6 has already imposed the suffix.
function prefix6_of_address6 { echo "${1%1/64}"; }

# The target user is the one sudo came from -- never a name given to us. Running
# this script as root outside sudo is refused rather than guessed: dnsmasq would
# then stay root, and Marionnet could no longer stop it without privileges.
function target_user {
  local user=${SUDO_USER:-}
  [[ -n $user ]] || die "no SUDO_USER: this command is meant to be run through sudo, by Marionnet"
  [[ $user =~ ^[a-z_][a-z0-9_-]*\$?$ ]] || die "SUDO_USER '$user' is not a plausible user name"
  if [[ $user = root ]]; then
    die "refusing to run the DHCP server as root: it must be killable without sudo"
  fi
  id -u "$user" >/dev/null 2>&1 || die "unknown user '$user'"
  echo "$user"
}

# --- Files. Their paths are COMPUTED, never received: a path taken from the
# --- command line would let a caller have root write a file wherever it likes.

function pid_file   { echo "$USER_RUN_DIR/$1.pid"; }
function lease_file { echo "$USER_RUN_DIR/$1.leases"; }

# running_pid BRIDGE: the pid of OUR dnsmasq for that bridge, if it is alive.
# Identity is checked, never assumed: a pid file may name a pid that has been
# recycled by a completely unrelated process.
function running_pid {
  local bridge=$1 file pid cmdline
  file=$(pid_file "$bridge")
  [[ -r $file ]] || return 1
  read -r pid < "$file" || return 1
  [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
  [[ -d /proc/$pid ]] || return 1
  cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
  [[ $cmdline == *"--interface=$bridge "* ]] || return 1
  echo "$pid"
}

# --- start

function do_start {
  local mode=$1 bridge=$2 net=$3 addr6=${4:-} prefix6="" user group pid
  case $mode in dhcp4|dhcp4+ra|ra) ;; *) die "internal error: unknown mode '$mode'" ;; esac
  valid_bridge "$bridge" || die "invalid bridge name '$bridge' (expected ${BRIDGE_PREFIX}<pid>[-<instance>], at most 15 characters)"
  valid_subnet "$net"    || die "invalid /24 prefix '$net' (expected three bytes, e.g. 192.168.101)"
  if [[ $mode != dhcp4 ]]; then
    valid_address6 "$addr6" \
      || die "invalid IPv6 address '$addr6' (expected <prefix>::1/64 in lower case, e.g. fd00:192:168:101::1/64)"
    prefix6=$(prefix6_of_address6 "$addr6")
  fi
  resolve_binaries
  user=$(target_user)
  group=$(id -gn "$user")
  USER_RUN_DIR=$RUN_DIR/$(id -u "$user")

  # The bridge must already be ours and already be addressed: block (b) of the
  # sudoers rule is the only way to reach that state, so this check is what ties
  # the DHCP service to a bridge Marionnet really built.
  "$IP" link show "$bridge" type bridge >/dev/null 2>&1 \
    || die "no bridge named '$bridge' on this host"
  "$IP" -oneline -4 addr show dev "$bridge" | grep -qE "inet $net\.1/24( |$)" \
    || die "'$bridge' does not carry $net.1/24 -- refusing to serve a network it does not own"
  # Same reasoning for IPv6: only sudoers block (b) can have put that address
  # there, and dnsmasq could not bind it anyway.
  if [[ -n $prefix6 ]]; then
    "$IP" -oneline -6 addr show dev "$bridge" | grep -qE "inet6 $addr6( |$)" \
      || die "'$bridge' does not carry $addr6 -- refusing to advertise a prefix it does not own"
  fi

  if pid=$(running_pid "$bridge"); then
    echo "$TOOL: a DHCP server of ours is already running on $bridge (pid $pid)." 1>&2
    echo "$pid"
    return 0
  fi

  # The parent stays root's (0755): nobody but root may create a name in it, so
  # no user can prepare a directory in another user's place. The per-user one is
  # theirs, so that they may delete their own files afterwards.
  mkdir -p -m 0755 "$RUN_DIR"
  mkdir -p -m 0755 "$USER_RUN_DIR"
  chown "$user:$group" "$USER_RUN_DIR"
  rm -f "$(pid_file "$bridge")"

  # The lease file is written by dnsmasq AFTER it has dropped its privileges,
  # so it must belong to the user beforehand.
  local leases; leases=$(lease_file "$bridge")
  [[ -e $leases ]] || : > "$leases"
  chown "$user:$group" "$leases"
  chmod 0644 "$leases"

  # THE command line. Every option is literal; only $bridge, $net, $user,
  # $group and the two computed paths vary, and all five have been validated.
  #   --conf-file=/dev/null : never inherit /etc/dnsmasq.conf from the host.
  #   --bind-interfaces + --interface + --listen-address : this server exists
  #     only on that bridge; nothing of the host is exposed, and there is no
  #     conflict with systemd-resolved (127.0.0.53).
  #   --no-hosts : do not serve the host's /etc/hosts to the guests.
  #   --user/--group : drop to the user, so that a plain TERM stops it later.
  local command=(
    "$DNSMASQ"
    --conf-file=/dev/null
    --pid-file="$(pid_file "$bridge")"
    --user="$user" --group="$group"
    --bind-interfaces --except-interface=lo
    --interface="$bridge" --listen-address="$net.1"
    --no-hosts
    --dhcp-leasefile="$leases"
  )
  if [[ $mode != ra ]]; then
    command+=(
      --dhcp-authoritative
      --dhcp-range="$net.$DHCP_FIRST,$net.$DHCP_LAST,255.255.255.0,$DHCP_LEASE_TIME"
    )
  fi
  # The IPv6 half (episode 11). --enable-ra is the master switch; `ra-only' in
  # the range means "advertise the prefix, hand out no DHCPv6 lease", which is
  # precisely stateless autoconfiguration. The DNS server is announced INSIDE
  # the advertisement (RDNSS), so a guest reaches it over IPv6 even though the
  # upstream resolver of this dnsmasq is reached over IPv4.
  if [[ -n $prefix6 ]]; then
    command+=(
      --enable-ra
      --dhcp-range="$prefix6,ra-only,64,$RA_LIFETIME"
      --dhcp-option=option6:dns-server,"[${prefix6}1]"
      --listen-address="${prefix6}1"
    )
  fi
  # Echoed in full before being run: a tool that hides what it does to the host
  # is worthless (same rule as marionnet-natbridge.sh).
  printf '  + %s\n' "${command[*]}" 1>&2
  "${command[@]}" || die "dnsmasq refused to start on $bridge"

  # dnsmasq daemonises and writes its pid file before returning, but a race
  # would be silent, so the pid is read back and verified rather than assumed.
  pid=$(running_pid "$bridge") \
    || die "dnsmasq returned success on $bridge but left no usable pid file"
  if [[ $mode != ra ]]; then
    echo "$TOOL: DHCP server up on $bridge ($net.$DHCP_FIRST-$net.$DHCP_LAST, lease $DHCP_LEASE_TIME), pid $pid, running as $user." 1>&2
  else
    echo "$TOOL: server up on $bridge with NO DHCPv4 (DNS only on $net.1), pid $pid, running as $user." 1>&2
  fi
  if [[ -n $prefix6 ]]; then
    echo "       Router Advertisements for ${prefix6}/64 (SLAAC, lifetime $RA_LIFETIME), DNS announced at ${prefix6}1." 1>&2
  fi
  echo "$pid"
}

function usage {
  cat 1>&2 <<EOF
Usage: $TOOL start      <BRIDGE> <NET>        # DHCPv4 and DNS
       $TOOL start-both <BRIDGE> <NET> <A6>   # ... and IPv6 advertisements
       $TOOL start-ra   <BRIDGE> <NET> <A6>   # advertisements, no DHCPv4

  BRIDGE  ${BRIDGE_PREFIX}<pid>[-<instance>], an existing bridge carrying <NET>.1/24
  NET     the /24 prefix it is addressed on, e.g. 192.168.101
  A6      the IPv6 address the bridge already carries, <prefix>::1/64,
          e.g. fd00:192:168:101::1/64

Run as root through sudo, by bin/scripts/marionnet-natbridge.sh only. dnsmasq
drops to \$SUDO_USER, hands out $DHCP_FIRST-$DHCP_LAST of the /24, advertises the /64 for
stateless autoconfiguration when asked, and is stopped later by a plain TERM --
no privilege needed for that, which is why there is no \`stop' here. Prints the
pid on stdout.
EOF
}

# One arity per sub-command, checked before anything else: this is the guard that
# makes the wide glob of the sudoers rule harmless (see the header).
case "${1:-}" in
  start)
    (( $# == 3 )) || { usage; die "start: expected exactly two arguments, got $(( $# - 1 ))"; }
    do_start dhcp4 "$2" "$3" ;;
  start-both)
    (( $# == 4 )) || { usage; die "start-both: expected exactly three arguments, got $(( $# - 1 ))"; }
    do_start dhcp4+ra "$2" "$3" "$4" ;;
  start-ra)
    (( $# == 4 )) || { usage; die "start-ra: expected exactly three arguments, got $(( $# - 1 ))"; }
    do_start ra "$2" "$3" "$4" ;;
  -h|--help) usage ;;
  *) usage; die "unknown or missing subcommand '${1:-}'" ;;
esac
