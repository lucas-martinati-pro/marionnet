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

# Maintain the SHA256SUMS of a release directory -- the file which is BOTH the catalogue
# and the integrity of a Marionnet release.
#
# One file, not two. A `sha256sum' line carries a name AND a digest, so a published
# SHA256SUMS answers the two questions the installer asks:
#
#   what does this release hold?     -- the names, without parsing anyone's HTML listing
#   did this artefact arrive whole?  -- the digest, checked while it is extracted
#
# An index file and a sums file would be two truths able to disagree; there is one.
#
# CONSEQUENCE, and it is the point: for useful-scripts/marionnet-install.sh, SHA256SUMS
# IS the catalogue (the Apache listing is only its fallback). An artefact dropped into the
# release directory without passing through here is INVISIBLE, and a line left behind by a
# removed artefact advertises something which is not there -- which is why stale lines are
# dropped, not kept.
#
# No bashbricks here, on purpose: this script is the third of a family (the two
# *.prepare-to-publish.sh next to it), none of which sources anything, and what it does --
# read a sums file, hash a few names, write it back sorted -- is native shell all the way.
# Sourcing a library to iterate one associative array would add indirection, not safety.
#
# Nothing already present is recomputed, unless -f|--force: a digest is a full re-read of
# the file, and a filesystem tarball weighs gibibytes. This is the same reasoning as the
# `.<image>.origin' witness of Makefile.d/filesystem.prepare-snapshot-to-publish.sh.
#
# Usage: Makefile.d/release.sha256sums.sh [OPTIONS] [FILE...]
#
#   -o, --output-dir DIR         the release directory
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -f, --force                  recompute the digests already recorded
#   -c, --check                  verify the directory against SHA256SUMS, and stop
#   -n, --dry-run                say what would change, write nothing
#   -h, --help                   this help
#
# Without FILE, every kernels_*.tar.{gz,xz}, filesystems_*.tar.{gz,xz} and
# marionnet_*.tar.{gz,xz} of the directory is considered. With FILE (a bare name or a path inside the directory), only those are --
# that is how the two *.prepare-to-publish.sh scripts call this one, right after they have
# moved a fresh tarball into place.
# ---

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

SUMS_FILE=SHA256SUMS

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
# Same reason as in the kernel script: the rule which turns the version of META into a
# series has a SINGLE implementation, in the filesystem script, which prints it on demand.
# ---
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

# ---
# --- Command line.
# ---
SERIES=""
OUTDIR=""
FORCE=0
CHECK=0
DRY_RUN=0
ARGUMENTS=()

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -f|--force)      FORCE=1; shift ;;
    -c|--check)      CHECK=1; shift ;;
    -n|--dry-run)    DRY_RUN=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; ARGUMENTS+=("$@"); break ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    *)               ARGUMENTS+=("$1"); shift ;;
  esac
done

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"

command -v sha256sum >/dev/null || die "\`sha256sum' not found (package coreutils)"

test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

# ---
# --- --check: hand the whole thing to sha256sum itself.
# ---
# Re-reading a published release is exactly what `sha256sum -c' does, and the file we write
# is in its format precisely so that it can. Nothing to reimplement.
# ---
if ((CHECK)); then
  test -f "$OUTDIR/$SUMS_FILE" || die "no $SUMS_FILE in $OUTDIR (nothing to check)"
  info "checking $OUTDIR/$SUMS_FILE"
  cd "$OUTDIR" && exec sha256sum -c -- "$SUMS_FILE"
fi

# ---
# --- What the file says today.
# ---
declare -A RECORDED=()   # name -> digest
if test -f "$OUTDIR/$SUMS_FILE"; then
  # The format is sha256sum's own: <64 hex digits><two spaces or ` *'><name>. The name may
  # hold spaces, so it is everything past the separator, not a field.
  while IFS= read -r line; do
    test -n "$line" || continue
    if [[ $line =~ ^([0-9a-fA-F]{64})[[:space:]][[:space:]*](.+)$ ]]; then
      RECORDED["${BASH_REMATCH[2]}"]="${BASH_REMATCH[1]}"
    else
      warn "$SUMS_FILE: line ignored, not in sha256sum format: $line"
    fi
  done < "$OUTDIR/$SUMS_FILE"
fi

# ---
# --- Which artefacts we are asked about.
# ---
# A published artefact is recognised by its NAME, here as everywhere else in this chain:
# `filesystems_<X>.tar.*', `kernels_<X>.tar.*' and -- since Makefile.d/release.binary.sh --
# `marionnet_<version>-r<rev>_<arch>_<libc>.tar.*', the application itself. Anything else in
# the directory (the images themselves, their .conf, this very file) is not an artefact to
# publish.
#
# The installer only fetches the first two: a `marionnet_*' line is catalogued and, for now,
# ignored by useful-scripts/marionnet-install.sh. It is recorded all the same, because the
# catalogue is what says WHAT A RELEASE HOLDS, and because the digest of the binary is
# exactly what the channel which will install it needs.
# ---
CANDIDATES=()
if ((${#ARGUMENTS[@]})); then
  for a in "${ARGUMENTS[@]}"; do
    name=$(basename -- "$a")
    test -f "$OUTDIR/$name" || die "not in the release directory: $name ($OUTDIR)"
    CANDIDATES+=("$name")
  done
else
  shopt -s nullglob
  for f in "$OUTDIR"/kernels_*.tar.gz "$OUTDIR"/kernels_*.tar.xz \
           "$OUTDIR"/filesystems_*.tar.gz "$OUTDIR"/filesystems_*.tar.xz \
           "$OUTDIR"/marionnet_*.tar.gz "$OUTDIR"/marionnet_*.tar.xz; do
    CANDIDATES+=("$(basename -- "$f")")
  done
  shopt -u nullglob
fi

info "release dir  : $OUTDIR"
info "series       : $SERIES"

# ---
# --- Stale lines: an entry with no file behind it is a phantom in the catalogue.
# ---
# Only meaningful when we looked at the whole directory; a call naming one fresh tarball
# knows nothing about the others.
# ---
DROPPED=0
if ((! ${#ARGUMENTS[@]})); then
  for name in "${!RECORDED[@]}"; do
    if ! test -f "$OUTDIR/$name"; then
      warn "dropping the line of a file which is no longer there: $name"
      unset 'RECORDED[$name]'
      DROPPED=$(( DROPPED + 1 ))
    fi
  done
fi

# ---
# --- The digests.
# ---
ADDED=0
KEPT=0
for name in "${CANDIDATES[@]}"; do
  if test -n "${RECORDED[$name]:-}" && ((! FORCE)); then
    KEPT=$(( KEPT + 1 ))
    continue
  fi
  if ((DRY_RUN)); then
    info "would compute: $name"
    ADDED=$(( ADDED + 1 ))
    continue
  fi
  info "computing: $name ($(du -h -- "$OUTDIR/$name" | awk '{print $1}')) ..."
  RECORDED["$name"]=$( (cd "$OUTDIR" && sha256sum -- "$name") | awk '{print $1}')
  ADDED=$(( ADDED + 1 ))
done

if (( ADDED == 0 && DROPPED == 0 )); then
  info "nothing to do: $KEPT digest(s) already recorded (--force to redo)"
  exit 0
fi

if ((DRY_RUN)); then
  info "dry run: nothing written ($ADDED to compute, $DROPPED to drop, $KEPT kept)"
  exit 0
fi

# ---
# --- Writing, atomically and sorted.
# ---
# Sorted so that two runs which recorded the same artefacts produce the same file, whatever
# the order they were published in -- a diff on a release directory then says something.
# LC_ALL=C so that the order does not depend on the locale of whoever publishes.
# ---
PARTIAL="$OUTDIR/.$SUMS_FILE.partial.$$"
trap 'rm -f -- "$PARTIAL"' EXIT
: > "$PARTIAL"
for name in "${!RECORDED[@]}"; do
  printf '%s  %s\n' "${RECORDED[$name]}" "$name"
done | LC_ALL=C sort -k2 >> "$PARTIAL"
chmod 644 -- "$PARTIAL"
mv -f -- "$PARTIAL" "$OUTDIR/$SUMS_FILE"
trap - EXIT

info "$SUMS_FILE written: ${#RECORDED[@]} artefact(s) ($ADDED computed, $KEPT kept\
$( ((DROPPED)) && echo ", $DROPPED dropped"))"
