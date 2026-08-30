#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Put a UML KERNEL and its .config into the release directory of marionnet.org, and build
# the tarball the installer downloads -- the kernel counterpart of
# Makefile.d/filesystem.prepare-snapshot-to-publish.sh:
#
#   linux-6.12.95                    the kernel itself (an ordinary ELF executable)
#   linux-6.12.95.config             the kernel configuration it was built with
#   kernels_linux-6.12.95.tar.xz     what the installer downloads
#
# A kernel is NOT a filesystem: there is nothing to merge, no .conf to write, no checksum
# in its name and -- above all -- no mtime constraint (user-mode-linux only checks the
# mtime of a BACKING FILE). So the whole job is: locate the pair, put it where the release
# lives, archive it.
#
# ONE KERNEL, ONE TARBALL. `linux-6.12.95-i386' is a name of its own, published by a second
# run; it is not slipped into the archive of `linux-6.12.95'.
#
# Nothing already present is recomputed, unless -f|--force.
#
# Usage: Makefile.d/kernel.prepare-to-publish.sh [OPTIONS] KERNEL
#
#   -o, --output-dir DIR         where to publish
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -i, --input-dir DIR          where to look for KERNEL first (before the usual
#                                installation directories)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -f, --force                  redo what is already there
#       --gz                     build a .tar.gz instead of the default .tar.xz
#       --xz                     build a .tar.xz (the default; kept to be explicit)
#   -y, --yes                    do not ask before building the tarball
#       --no-tarball             stop before the tarball
#   -h, --help                   this help
#
# KERNEL is MANDATORY. It is either a path, or a bare name (`linux-6.12.95'), looked up in
# that order: the output directory, --input-dir, then /usr/local/share/marionnet/kernels
# and /usr/share/marionnet/kernels. The directory it was found in is announced on stdout.
# ---

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

KERNEL_DIRS=(/usr/local/share/marionnet/kernels /usr/share/marionnet/kernels)

# ---
# --- Small talk.
# ---
function info { echo "==> $*"; }
function warn { echo "$0: warning: $*" >&2; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
  sed -n '/^# Usage:/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

# ---
# --- The publication series.
# ---
# The rule which turns the version of META into a series has a SINGLE implementation, in the
# filesystem script next to this one, which prints it on demand. We call it rather than
# copying it: two copies of that rule would silently disagree the day META moves.
# ---
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

# ---
# --- Command line.
# ---
SERIES=""
OUTDIR=""
INDIR=""
ARGUMENT=""
FORCE=0
ASSUME_YES=0
MAKE_TARBALL=1
USE_XZ=1

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -i|--input-dir)  INDIR="$2";  shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -f|--force)      FORCE=1; shift ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --no-tarball)    MAKE_TARBALL=0; shift ;;
    --xz)            USE_XZ=1; shift ;;
    --gz|--gzip)     USE_XZ=0; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    *)               test -z "$ARGUMENT" || die "at most one kernel expected"; ARGUMENT="$1"; shift ;;
  esac
done

# The argument is MANDATORY: unlike a filesystem snapshot, whose most recent one is a
# sensible default, there is no such thing as "the" kernel to publish.
test -n "$ARGUMENT" || { usage >&2; die "a kernel is required (for instance: linux-6.12.95)"; }

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"

for cmd in file tar gzip du sed awk; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found"
done

# ---
# --- 1. Locating the kernel and its configuration.
# ---
# A kernel is published as a PAIR: the installer lays down both files side by side in
# $PREFIX/share/marionnet/kernels/, and Marionnet reads the .config to tell the user what
# the kernel supports. A lone kernel is therefore refused, not silently published.
# ---
KERNEL_NAME=$(basename -- "$ARGUMENT")
SRC=""

if [[ "$ARGUMENT" == */* ]]; then
  test -f "$ARGUMENT" || die "no such file: $ARGUMENT"
  SRC="$ARGUMENT"
else
  # A bare name: the output directory first (the usual case of a kernel already dropped
  # there by hand), then --input-dir, then the usual installation directories.
  for d in "$OUTDIR" ${INDIR:+"$INDIR"} "${KERNEL_DIRS[@]}"; do
    test -f "$d/$KERNEL_NAME" && { SRC="$d/$KERNEL_NAME"; break; }
  done
  test -n "$SRC" || die "kernel \`$KERNEL_NAME' found neither in $OUTDIR${INDIR:+, $INDIR} nor in ${KERNEL_DIRS[*]}"
fi

SRC="$(cd -- "$(dirname -- "$SRC")" && pwd)/$(basename -- "$SRC")"
SRC_CONFIG="$SRC.config"

test -f "$SRC_CONFIG" || die "the kernel has no configuration file: $SRC_CONFIG"

# LC_ALL=C: we match the ENGLISH wording of file(1). This is a sanity check, not a
# guarantee: it catches the classic mistake of passing the .config, or a tarball, instead
# of the kernel itself.
LC_ALL=C file -b -- "$SRC" | grep -q "^ELF .* executable" \
  || warn "$SRC does not look like an ELF executable -- is it really a UML kernel?"

info "kernel       : $SRC"
info "configuration: $SRC_CONFIG"
info "series       : $SERIES"
info "output dir   : $OUTDIR"

mkdir -p -- "$OUTDIR"

# ---
# --- 2. Publishing the pair.
# ---
# `cp -p' keeps mode and timestamps. The mode matters (the kernel must stay executable once
# extracted, and tar records what it sees); the timestamps do not, but there is no reason to
# make the published copy look younger than the kernel it is.
# ---
function publish_one {
  local src="$1" dst="$2"
  if test "$src" -ef "$dst"; then
    info "already in place: $dst"
  elif test -e "$dst" && ((! FORCE)); then
    info "already there, skipped: $dst (use --force to redo)"
  else
    cp -p -f -- "$src" "$dst"
    info "published: $dst"
  fi
}

KERNEL="$OUTDIR/$KERNEL_NAME"
CONFIG="$KERNEL.config"
publish_one "$SRC"        "$KERNEL"
publish_one "$SRC_CONFIG" "$CONFIG"

# ---
# --- 3. The tarball the installer downloads.
# ---
# Name and layout of the existing installer: download_our_kernels() of
# useful-scripts/marionnet_from_scratch extracts with `wget -O - "$URL" | tar 1>&2 xvzf -'
# from $PREFIX/share/marionnet/, so the entries must be prefixed with `kernels/'.
# --transform gives that prefix without copying anything around; its `S' flag restricts the
# substitution to member NAMES (a kernel is not a symbolic link today, but the flag costs
# nothing and the filesystem script was bitten by its absence).
#
# Ownership is FORCED to root:root, for the same reason as filesystems: what ends up in
# $PREFIX/share/marionnet/ is system data extracted by a privileged installer, on a machine
# where the packager's uid means nothing.
#
# xz is the default (28-31% less to download, and `xz -dc -T0' decompresses FASTER than gzip
# -- measured in the filesystem script, § 7). `--gz' remains for the installer in the field,
# whose `tar xvzf' reads gzip only. Note that download_our_kernels() looks for
# `kernels_*.tar.gz' specifically: until the v2 installer is out, the .gz is the one it sees.
# ---
TAR_OWNERSHIP=(--owner=root --group=root)
if ((USE_XZ)); then
  command -v xz >/dev/null || die "\`xz' not found (package xz-utils)"
  TARBALL="$OUTDIR/kernels_$KERNEL_NAME.tar.xz"
  TAR_COMPRESS=(-I "xz -T0")
else
  TARBALL="$OUTDIR/kernels_$KERNEL_NAME.tar.gz"
  TAR_COMPRESS=(-z)
fi

if ((! MAKE_TARBALL)); then
  info "tarball not requested (--no-tarball); nothing else to do."
  exit 0
fi

if test -f "$TARBALL" && ((! FORCE)); then
  info "already there, skipped: $TARBALL (use --force to redo)"
  exit 0
fi

MEMBERS=("$KERNEL_NAME" "$KERNEL_NAME.config")

if ((! ASSUME_YES)) && test -t 0; then
  SIZE=$(du -csh -- "${MEMBERS[@]/#/$OUTDIR/}" | tail -n 1 | awk '{print $1}')
  read -r -p "Build $TARBALL now (about $SIZE to compress)? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) info "tarball not built; run again (or with -y) when you want it."; exit 0 ;;
  esac
fi

info "building $TARBALL ..."
trap 'rm -f -- "$TARBALL.partial"' EXIT
tar -C "$OUTDIR" --transform 's,^,kernels/,S' "${TAR_OWNERSHIP[@]}" "${TAR_COMPRESS[@]}" \
    -cf "$TARBALL.partial" -- "${MEMBERS[@]}"
mv -f -- "$TARBALL.partial" "$TARBALL"
trap - EXIT
info "tarball produced: $TARBALL ($(du -h -- "$TARBALL" | awk '{print $1}'))"

# The release directory has a catalogue, and it is SHA256SUMS -- read as such by
# useful-scripts/marionnet-install.sh, whose Apache listing is only a fallback. A tarball
# which never reaches that file is invisible to the installer, so it is recorded HERE,
# right after being moved into place, and not left to a separate gesture someone forgets.
# --force, scoped to this single file: we have JUST written it, so a digest already
# recorded under that name is by construction the digest of the PREVIOUS artefact. Without
# it, republishing under the same name (which is what our own --force does) leaves the
# catalogue announcing a file which no longer exists -- and the installer, which checks the
# digest while extracting, REMOVES what it just fetched. Measured at episode 9b. Scoped, so
# the gibibytes of the neighbouring artefacts are not re-read.
bash "$ROOT/Makefile.d/release.sha256sums.sh" --output-dir "$OUTDIR" --force -- "$TARBALL" || \
  warn "$TARBALL is published but NOT in SHA256SUMS: run Makefile.d/release.sha256sums.sh"

if ((USE_XZ)); then
  info "to extract it: wget -O - <url> | xz -dc -T0 | tar xf -    (the installer in the field"
  info "               only knows \`tar xvzf' and only looks for kernels_*.tar.gz: see --gz)"
else
  info "to extract it: wget -O - <url> | tar xzf -"
fi
