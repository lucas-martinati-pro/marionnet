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

# What is still to be done on THIS machine -- and nothing at all when the answer
# is "nothing".
#
# The two package channels used to recite a fixed text at installation time, and
# both were wrong, in opposite ways: the .deb printed it at every `configure', so
# an `apt upgrade' on a machine that had been set up months ago announced again
# that Marionnet "cannot build its network taps yet" and told its owner to do
# what they had already done; the .rpm printed it on the FIRST install only
# ([ "$1" = 1 ]), so a machine which had never been granted anything was told
# nothing when it upgraded. Counting installations cannot answer the question
# that was actually being asked -- is the socle granted here, are the images
# there? -- and an advice which is wrong is an advice that stops being read.
#
# So: this script MEASURES, and it holds the text ONCE for both channels. It is
# the sibling of marionnet-tun-check.sh (which asks the other half of the same
# question, about the tun device) and follows it in everything: it is NEVER fatal
# for its callers, it repairs nothing, and it can be run by hand any day, by the
# administrator wondering what is left to do:
#
#     marionnet-setup-check.sh
#
# Exit status: 0 = nothing to report, 1 = something is missing (and it says what).
# Callers invoke it with `|| true'.

set -uo pipefail

TOOL=$(basename "$0")

# The socle is the block (a) of marionnet-sudoers.sh, and it is that script -- not
# this one -- which knows where its file lives and what belongs in it. We only ask.
SUDOERS=marionnet-sudoers.sh
SUDOERS_STALE_RC=4   # `check': granted, but written by an older version of the script

function usage {
 cat 1>&2 <<EOF
Usage: $TOOL [--package-manager apt|dnf]

Says what is still missing before Marionnet can be used on this machine: the
scoped sudoers rule which lets it build its network taps, and the guest images
and UML kernels it boots. Says nothing when nothing is missing.

Run as root to have the sudoers rule looked at: its file is 0440, as a sudoers
file must be.

  --package-manager  which channel to name in the advice about the guest images.
                     Derived from what is installed here when not given.
EOF
}

# Written on stderr, like marionnet-tun-check.sh: both are shown by apt and by
# dnf, and a human who runs this by hand can then keep the report and drop the
# rest, or the reverse.
function say { echo "$TOOL: $*" 1>&2; }

PACKAGE_MANAGER=""
while (($#)); do
  case "$1" in
    --package-manager) shift; PACKAGE_MANAGER=${1:-}; test -n "$PACKAGE_MANAGER" || { usage; exit 2; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$TOOL: unknown option '$1'" 1>&2; usage; exit 2 ;;
  esac
  shift
done
if [[ -z $PACKAGE_MANAGER ]]; then
  if   command -v apt-get >/dev/null 2>&1; then PACKAGE_MANAGER=apt
  elif command -v dnf     >/dev/null 2>&1; then PACKAGE_MANAGER=dnf
  fi
fi
case "$PACKAGE_MANAGER" in
  apt|dnf|"") ;;
  *) echo "$TOOL: unknown package manager '$PACKAGE_MANAGER' (apt or dnf)" 1>&2; exit 2 ;;
esac

SOMETHING_MISSING=0

# ---
# --- 1. The scoped sudoers rule: the socle, block (a).
# ---
# Three states, three different things to say -- and the third one is the reason
# this measurement is worth making at all. A file written before the tun device
# door existed (episode 42) GRANTS its accounts and is nonetheless out of date:
# nobody was told, on either channel. `check' answers 0, 4 or 1 for exactly that.
if ! command -v "$SUDOERS" >/dev/null 2>&1; then
  : # Not our business to complain: the installation is not finished, or is broken
    # in a way marionnet-tun-check.sh and the channel itself will say better.
elif [[ $EUID -ne 0 ]]; then
  # Not being able to measure is not a negative verdict (the rule of episode 39):
  # a 0440 file cannot be read here, and claiming "not granted" would be the very
  # kind of false accusation this script exists to end.
  say "run me as root to have the sudoers rule looked at (its file is 0440)."
else
  "$SUDOERS" check >/dev/null 2>&1
  case $? in
    0) ;;   # granted and up to date: silence.
    "$SUDOERS_STALE_RC")
      SOMETHING_MISSING=1
      cat 1>&2 <<EOF

==> The Marionnet sudoers rule is installed, but it was written by an earlier
    version and does not grant everything Marionnet asks for today (the door
    which provides /dev/net/tun, for one). Refresh it, as an administrator:

        sudo $SUDOERS install

    \`install' is ADDITIVE: no account already granted is taken away, and every
    rule of the file is regenerated. Name accounts to add some at the same time.
EOF
      ;;
    *)
      SOMETHING_MISSING=1
      cat 1>&2 <<EOF

==> Marionnet is installed, but it cannot build its network taps yet.

    One scoped sudoers rule is needed, and no package grants it: an installation
    cannot tell WHICH user this machine belongs to. Run, as an administrator:

        sudo $SUDOERS install <user>

    That grants the socle (block a). The NAT and LAN bridge grants are asked
    for by the user, from the interface, the day a bridge component is started.
EOF
      ;;
  esac
fi

# ---
# --- 2. The guest images and the UML kernels.
# ---
# WHERE they are expected is asked of the binary, the single reader of the
# configuration cascade (episode 28): parsing /etc/marionnet/marionnet.conf here
# would be a second implementation of it. No binary, or no answer: we say nothing
# rather than something we cannot back.
FILESYSTEMS=""; KERNELS=""
if command -v marionnet.native >/dev/null 2>&1; then
  if PATHS=$(marionnet.native --paths 2>/dev/null); then
    FILESYSTEMS=$(sed -n 's|^filesystems[[:space:]]*:[[:space:]]*||p' <<<"$PATHS")
    KERNELS=$(sed -n 's|^kernels[[:space:]]*:[[:space:]]*||p' <<<"$PATHS")
  fi
fi

# A directory holding nothing is what "not installed" looks like here: the data
# packages and marionnet-get-images both fill it, and Marionnet reads whatever
# it finds in it.
function directory_is_empty {  # <dir>
 local d=$1
 [[ -d $d ]] || return 0
 ! find "$d" -mindepth 1 -print -quit 2>/dev/null | grep -q .
}

NO_IMAGES=false; NO_KERNELS=false
[[ -n $FILESYSTEMS ]] && directory_is_empty "$FILESYSTEMS" && NO_IMAGES=true
[[ -n $KERNELS     ]] && directory_is_empty "$KERNELS"     && NO_KERNELS=true

if $NO_IMAGES || $NO_KERNELS; then
  SOMETHING_MISSING=1
  # Only what is actually missing is named: telling somebody to install a package
  # they already have is the smaller version of the very defect this script ends.
  PACKAGES=""
  $NO_IMAGES  && PACKAGES="marionnet-fs-guignol"
  $NO_KERNELS && PACKAGES="${PACKAGES:+$PACKAGES }marionnet-kernels"
  case "$PACKAGE_MANAGER" in
    apt|dnf) SMALL_ONES="$PACKAGE_MANAGER install $PACKAGES" ;;
    *)       SMALL_ONES="install the package(s): $PACKAGES" ;;
  esac
  echo 1>&2
  if $NO_IMAGES && $NO_KERNELS; then
    echo "==> Marionnet has neither a guest image nor a UML kernel to boot yet." 1>&2
  elif $NO_IMAGES; then
    echo "==> Marionnet has no guest image to boot yet ($FILESYSTEMS is empty)." 1>&2
  else
    echo "==> Marionnet has no UML kernel to boot yet ($KERNELS is empty)." 1>&2
  fi
  cat 1>&2 <<EOF

    The small ones are packaged:

        sudo $SMALL_ONES

    The larger images (Debian wheezy, Debian trixie) are not -- gibibytes are
    not what a package manager is for -- and this command offers them as a list
    to tick, where the Marionnet installed here looks for them:

        marionnet-get-images
EOF
fi

exit $SOMETHING_MISSING
