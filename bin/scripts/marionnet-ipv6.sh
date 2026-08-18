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
# THE ONE PRIVILEGED ENTRY POINT OF THE IPv6 GATE of the NAT bridge
# (work-stream modernisation-world-bridge, episode 11). It is run as root by
# marionnet-natbridge.sh through sudo, and by nothing else.
#
# --- WHAT A "GATE" IS, AND WHY IT IS NOT THREE SUDOERS LINES ---
#
# Routing IPv6 out of the bridge needs the host to forward IPv6, and IPv6
# forwarding is NOT per-interface the way ip_forward is: it makes the whole host
# a ROUTER. A router, by default, IGNORES the Router Advertisements it receives
# -- so the host would keep its own IPv6 address and default route only until the
# lifetime of the last advertisement it heard ran out, and then lose them.
# Nothing would point at Marionnet: the outage comes minutes later.
#
# The fix is one more sysctl, accept_ra=2 ("accept advertisements EVEN when
# forwarding is enabled"), applied where it matters. That is why this is a
# script and not three lines in sudoers:
#
#   * the PREVIOUS values must be remembered somewhere root can write and anyone
#     can read, so that `disable' restores the host exactly as it was found --
#     a sudoers rule cannot remember anything;
#   * a rule such as `sysctl -q -w net.ipv6.conf.*' would accept ANY key: a `*'
#     in a sudoers argument swallows whole words (measured at episode 10c with
#     `ip link add mnbr* type bridge', which accepts `mnbr1 --INJECT type
#     bridge'), and `sysctl -w' takes several assignments at once. That is an
#     arbitrary sysctl write as root.
#
# This script therefore takes NO argument at all -- its sudoers lines are
# entirely literal, so there is no glob to abuse in the first place. It follows
# the discipline of marionnet-dnsmasq.sh: nothing is sourced (bashbricks would be
# a large surface running as root, and is not nounset-clean), no environment
# variable is read, no path is ever accepted as an argument, and every file it
# touches is one whose name it computed itself.
#
# It does not even use sysctl(8): it writes the /proc entries directly, after
# building each path from a validated interface name. There is no argument to
# parse and no way to reach a key outside net.ipv6.conf.
#
# --- THE CONTRACT WITH marionnet-natbridge.sh ---
#
#   enable    make the host forward IPv6 and keep accepting advertisements.
#             Idempotent: if the state file already exists, the gate is already
#             posted and this is a success that changes nothing (in particular it
#             NEVER overwrites the remembered values -- that would remember the
#             modified state as if it were the original).
#   disable   restore every value this script changed, and forget them. With no
#             state file, there is nothing to restore and that too is a success.
#   status    print what the host currently does, and what is remembered.
#
#   exit status  0 on success, non-zero on failure. Human trace on stderr.
#
# The gate is SHARED by every NAT bridge of every Marionnet on this host: the
# caller is the one that knows when the last of them is gone (see
# ipv6_gate_release in marionnet-natbridge.sh). After a crash, `gc' releases it.
# ---------------------------------------------------------------------------

set -euo pipefail

TOOL=$(basename "$0")

# --- Constants. RUN_DIR is part of the contract with marionnet-natbridge.sh and
# --- marionnet-dnsmasq.sh (same name there): do not change one of them alone.

RUN_DIR=/run/marionnet-natbridge
STATE_FILE=$RUN_DIR/ipv6.state
CONF_DIR=/proc/sys/net/ipv6/conf

function die {
  echo "$TOOL: $*" 1>&2
  exit 1
}

# --- Reading and writing the knobs
#
# Every path is built here from a name this script found itself in $CONF_DIR, and
# validated. Nothing comes from the command line -- there is no command line.

function valid_interface_name {
  local name=$1
  [[ $name =~ ^[A-Za-z0-9_.:-]{1,15}$ ]] || return 1
  if [[ $name = all ]] || [[ $name = default ]]; then return 1; fi
  return 0
}

# knob_read SCOPE KEY: the current value, or nothing if the entry is absent (a
# kernel with IPv6 compiled out, or an interface that has just disappeared).
function knob_read {
  local file=$CONF_DIR/$1/$2
  if [[ -r $file ]]; then cat "$file"; fi
}

# knob_write SCOPE KEY VALUE: one /proc write, announced. A tool that hides what
# it does to the host is worthless (same rule as marionnet-natbridge.sh).
function knob_write {
  local file=$CONF_DIR/$1/$2
  [[ -w $file ]] || die "cannot write $file (is IPv6 available on this kernel?)"
  echo "  + $file = $3" 1>&2
  printf '%s\n' "$3" > "$file"
}

# The interfaces the kernel currently knows, `all' and `default' excluded.
function interfaces {
  local path name
  for path in "$CONF_DIR"/*; do
    name=$(basename "$path")
    if valid_interface_name "$name"; then echo "$name"; fi
  done
}

# --- The state file
#
# Line-oriented, `KEY VALUE', and PARSED rather than sourced: a file read by a
# root script must never be executable material, even one only root can write.
# Keys are not used verbatim either -- each is recognised, then the /proc path is
# rebuilt from scratch.

function state_write {
  local temp=$STATE_FILE.tmp.$$
  mkdir -p -m 0755 "$RUN_DIR"
  cat > "$temp"
  chmod 0644 "$temp"
  # Atomic: a half-written state file is a host we could not restore.
  mv -f "$temp" "$STATE_FILE"
}

function state_exists { [[ -e $STATE_FILE ]]; }

# --- enable

function do_enable {
  local forwarding accept_ra accept_ra_default interface value

  if state_exists; then
    [[ -r $STATE_FILE ]] || die "$STATE_FILE exists but cannot be read: refusing to touch the host blindly"
    echo "$TOOL: the IPv6 gate is already posted (see $STATE_FILE), nothing to do." 1>&2
    return 0
  fi

  forwarding=$(knob_read all forwarding)
  accept_ra=$(knob_read all accept_ra)
  accept_ra_default=$(knob_read default accept_ra)
  [[ -n $forwarding ]] || die "$CONF_DIR/all/forwarding is missing: this kernel has no IPv6"

  # Remembered BEFORE anything is written, and including every interface we are
  # about to raise: `disable' must be able to put each one back where it was.
  {
    echo "all.forwarding ${forwarding:-0}"
    echo "all.accept_ra ${accept_ra:-1}"
    echo "default.accept_ra ${accept_ra_default:-1}"
    for interface in $(interfaces); do
      value=$(knob_read "$interface" accept_ra)
      # Only the interfaces that DO accept advertisements today are raised. One
      # deliberately set to 0 (a bridge of some other tool, a link the user
      # silenced) stays at 0: this gate protects the host's configuration, it
      # does not impose its own.
      if [[ $value = 1 ]]; then echo "if.$interface.accept_ra 1"; fi
    done
  } | state_write

  echo "$TOOL: posting the IPv6 gate (forwarding was ${forwarding:-0})." 1>&2

  # `default' first: an interface appearing later (USB tethering, a VPN, a dock)
  # inherits from it, and would otherwise come up at 1 -- ignoring advertisements
  # for as long as the gate is posted.
  knob_write default accept_ra 2
  knob_write all accept_ra 2
  knob_write all forwarding 1

  # Whether a write to `all' propagates to the interfaces that already exist is
  # not something this script assumes: it reads them back and raises the ones the
  # kernel left behind. Correct either way, and no measurement to trust.
  for interface in $(interfaces); do
    value=$(knob_read "$interface" accept_ra)
    if [[ $value = 1 ]]; then knob_write "$interface" accept_ra 2; fi
  done

  echo "$TOOL: IPv6 forwarding is on, and advertisements are still accepted." 1>&2
}

# --- disable

function do_disable {
  local key value interface

  if ! state_exists; then
    echo "$TOOL: no IPv6 gate is posted, nothing to restore." 1>&2
    return 0
  fi
  [[ -r $STATE_FILE ]] || die "$STATE_FILE cannot be read: refusing to guess what the host looked like"

  # Forwarding goes back FIRST, so that the host stops being a router before it
  # is told to accept advertisements the way it used to.
  while read -r key value; do
    [[ -n ${key:-} ]] || continue
    [[ $value =~ ^[0-2]$ ]] || die "$STATE_FILE: '$value' is not a value this script ever wrote"
    case $key in
      all.forwarding)     knob_write all forwarding "$value" ;;
      all.accept_ra)      knob_write all accept_ra "$value" ;;
      default.accept_ra)  knob_write default accept_ra "$value" ;;
      if.*.accept_ra)
        interface=${key#if.}; interface=${interface%.accept_ra}
        valid_interface_name "$interface" \
          || die "$STATE_FILE: '$interface' is not a plausible interface name"
        # An interface that has gone away since is not an error: there is simply
        # nothing left to restore.
        if [[ -w $CONF_DIR/$interface/accept_ra ]]; then
          knob_write "$interface" accept_ra "$value"
        else
          echo "$TOOL: $interface is gone, nothing to restore on it." 1>&2
        fi ;;
      *) die "$STATE_FILE: unknown key '$key'" ;;
    esac
  done < <(sort "$STATE_FILE")

  rm -f "$STATE_FILE"
  echo "$TOOL: the IPv6 gate is released, the host is as it was." 1>&2
}

# --- status

function do_status {
  echo "forwarding=$(knob_read all forwarding)"
  echo "all.accept_ra=$(knob_read all accept_ra)"
  echo "default.accept_ra=$(knob_read default accept_ra)"
  if state_exists; then
    echo "gate=posted"
    sed 's/^/remembered /' "$STATE_FILE"
  else
    echo "gate=absent"
  fi
}

function usage {
  cat 1>&2 <<EOF
Usage: $TOOL enable    # forward IPv6, and keep accepting advertisements
       $TOOL disable   # restore exactly what \`enable' changed
       $TOOL status    # what the host does now, and what is remembered

No argument, ever: that is what lets the sudoers rule be entirely literal.
Run as root through sudo, by bin/scripts/marionnet-natbridge.sh only. The gate is
shared by every NAT bridge on this host; the caller releases it when the last one
is gone. State: $STATE_FILE.
EOF
}

# `status' is harmless and needs no privilege; the other two write /proc.
case "${1:-}" in
  enable)  (( $# == 1 )) || { usage; die "enable: takes no argument, got $(( $# - 1 ))"; }
           [[ $(id -u) = 0 ]] || die "must be run as root (through sudo, by Marionnet)"
           do_enable ;;
  disable) (( $# == 1 )) || { usage; die "disable: takes no argument, got $(( $# - 1 ))"; }
           [[ $(id -u) = 0 ]] || die "must be run as root (through sudo, by Marionnet)"
           do_disable ;;
  status)  (( $# == 1 )) || { usage; die "status: takes no argument, got $(( $# - 1 ))"; }
           do_status ;;
  -h|--help) usage ;;
  *) usage; die "unknown or missing subcommand '${1:-}'" ;;
esac
