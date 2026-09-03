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
# THE ONE PRIVILEGED ENTRY POINT that provides /dev/net/tun.
# It is run as root by Marionnet through sudo, at start-up, and by nothing else.
#
# --- WHY THE APPLICATION, AND NOT THE INSTALLATION ---
#
# /dev is volatile EVERYWHERE, and that is what decides the placement:
#
#   * on a machine of its own it is a devtmpfs rebuilt at every boot, and udev
#     puts the node back on its own -- measured, 50-udev-default.rules:
#         KERNEL=="tun", MODE="0666", OPTIONS+="static_node=net/tun"
#     so here there is nothing to repair, and this script never even runs;
#   * in a container udev does not run and the engine mounts a FRESH tmpfs over
#     /dev at every start, so a node made once -- while building the image, or by
#     a postinst -- is gone at the next start.
#
# A repair carried out at installation time would therefore hold in neither case:
# it would work the day it was measured and evaporate in service. The only gesture
# that lasts is the one repeated at every start of the application, which is why
# this door exists and why the three installation channels still only NAME what is
# missing (episode 40) instead of doing it.
#
# --- WHAT IT GRANTS, SAID PLAINLY ---
#
# The sudoers line for this script allows one thing: creating /dev/net/tun with
# mode 0666 -- the configuration every ordinary Linux desktop already has, put
# there by udev. It belongs to the socle (block a) of marionnet-sudoers.sh because
# granting the socle already means "this account may create taps", and the device
# node is the PRECONDITION of that same act, not a power of its own: without it
# `ip tuntap' answers `open: No such file or directory' and the socle grants
# nothing usable.
#
# --- WHY A SCRIPT OF ITS OWN, AND WITH NO VARIABLE ARGUMENT ---
#
# Same discipline as marionnet-ipv6.sh (episode 11) and marionnet-dnsmasq.sh
# (episode 10c): the path, the major and the minor are written HERE, in the file,
# and the subcommand is a literal word. The sudoers rule is thus entirely literal
# -- there is no glob for an argument to abuse (measured at episode 10c: a `*' in
# a sudoers argument swallows whole words). Nothing is sourced, no environment
# variable is read, and no path is ever accepted from the caller.
#
# It is deliberately NOT a `--repair' option of marionnet-tun-check.sh: that one is
# a 110-line diagnostic called by the three installation channels, whose own header
# states that it creates no device. Making it the door would run all of it as root
# and make its documentation false. A door is small and validates in root.
#
# --- THE CONTRACT WITH bin/tap_provider.ml ---
#
#   create    make sure /dev/net/tun is the character device 10:200. Idempotent:
#             a node already there is a success that changes NOTHING (its mode is
#             left exactly as the administrator set it).
#   status    say what is there. Harmless, needs no privilege.
#
#   exit status  0 on success, non-zero on failure. Human trace on stderr.
#
# Creating the node does not prove a tap can be made: opening it may still be
# refused by a container's device cgroup, and TUNSETIFF still needs CAP_NET_ADMIN.
# The caller re-measures instead of trusting this exit status (tap_provider.ml).
# ---------------------------------------------------------------------------

set -euo pipefail

TOOL=$(basename "$0")

# --- Constants. The whole point of this script: they are here, not in sudoers,
# --- and not in the caller's hands.

TUN=/dev/net/tun
TUN_DIR=/dev/net
TUN_MAJOR=10
TUN_MINOR=200
TUN_MODE=0666

function die {
  echo "$TOOL: $*" 1>&2
  exit 1
}

# device_present: 0 when $TUN exists AND is the character device we mean. A node
# of the right name but of the wrong kind is NOT ours to fix (see do_create).
function device_present {
  local major minor
  [[ -c $TUN ]] || return 1
  read -r major minor < <(stat -c '%t %T' "$TUN") || return 1
  [[ -n ${major:-} && -n ${minor:-} ]] || return 1
  (( 16#$major == TUN_MAJOR )) && (( 16#$minor == TUN_MINOR ))
}

# --- create

function do_create {
  local mode

  # Idempotent, and silent about the mode: an administrator who deliberately
  # narrowed an existing node (0600, say) is not overruled by a repair meant for
  # the case where there is NO node at all. Only a node we create ourselves gets
  # the 0666 udev gives it everywhere else.
  if device_present; then
    mode=$(stat -c '%a' "$TUN")
    echo "$TOOL: $TUN is already there (character device $TUN_MAJOR:$TUN_MINOR, mode $mode), nothing to do." 1>&2
    return 0
  fi

  # Something else answers to that name: a regular file, a directory, a device of
  # another kind. Removing it would be destroying what somebody else put there,
  # and this script is not entitled to that decision -- it names it and stops.
  if [[ -e $TUN ]]; then
    die "$TUN exists but is not the character device $TUN_MAJOR:$TUN_MINOR ($(stat -c '%F' "$TUN")): refusing to replace it"
  fi

  [[ $(id -u) = 0 ]] || die "must be run as root (through sudo, by Marionnet)"

  mkdir -p -m 0755 "$TUN_DIR" || die "cannot create $TUN_DIR"

  # mknod(2) of a character device needs CAP_MKNOD, which a container may withhold
  # even from root: say so rather than let the raw errno through.
  if ! mknod "$TUN" c "$TUN_MAJOR" "$TUN_MINOR" 2>/dev/null; then
    die "cannot create $TUN: the kernel refuses mknod (CAP_MKNOD is missing -- in a container, start it with --device $TUN instead)"
  fi
  chmod "$TUN_MODE" "$TUN" || die "created $TUN but could not set its mode to $TUN_MODE"

  echo "$TOOL: created $TUN (character device $TUN_MAJOR:$TUN_MINOR, mode $TUN_MODE)." 1>&2
}

# --- status

function do_status {
  if device_present; then
    echo "device=present"
    echo "mode=$(stat -c '%a' "$TUN")"
  elif [[ -e $TUN ]]; then
    echo "device=wrong-kind"
    echo "kind=$(stat -c '%F' "$TUN")"
  else
    echo "device=absent"
  fi
}

function usage {
  cat 1>&2 <<EOF
Usage: $TOOL create   # make sure $TUN is the character device $TUN_MAJOR:$TUN_MINOR
       $TOOL status   # say what is there (no privilege needed)

No variable argument, ever: that is what lets the sudoers rule be entirely
literal. Run as root through sudo, by Marionnet at start-up. On a machine of its
own the node is already there, put back at every boot by udev, and this script
has nothing to do; it earns its keep inside containers, where /dev is a fresh
tmpfs at every start.
EOF
}

case "${1:-}" in
  create) (( $# == 1 )) || { usage; die "create: takes no argument, got $(( $# - 1 ))"; }
          do_create ;;
  status) (( $# == 1 )) || { usage; die "status: takes no argument, got $(( $# - 1 ))"; }
          do_status ;;
  -h|--help) usage ;;
  *) usage; die "unknown or missing subcommand '${1:-}'" ;;
esac
