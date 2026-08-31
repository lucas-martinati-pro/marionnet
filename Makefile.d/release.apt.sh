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

# Make the release directory readable BY APT: write the two index files a flat repository
# is made of -- Packages (+ Packages.gz) and Release -- beside the .deb that
# Makefile.d/release.deb.sh published there.
#
# A FLAT repository ("./"), not a dists/ tree with pools. The reason is not laziness: a
# release of Marionnet is ALREADY one directory per series (download/marionnet-install.sh/
# 1.0.x/), holding the guest images, the kernels, the precompiled tarball and now the four
# packages. The series IS the suite, the directory IS the component, and a dists/pool tree
# would put the same four files at a second place under a second name. One line in
# sources.list reaches it:
#
#     deb [trusted=yes] https://www.marionnet.org/download/marionnet-install.sh/1.0.x/ ./
#
# TWO CATALOGUES COHABIT IN THAT DIRECTORY, on purpose (episode 13):
#   SHA256SUMS  what useful-scripts/marionnet-install.sh reads -- names and digests of the
#               ARTEFACTS (images, kernels, tarball, and the .deb it lists and ignores);
#   Packages    what apt reads -- the control fields of the .deb ONLY.
# They answer different questions to different readers, and neither can be derived from the
# other: SHA256SUMS knows nothing of a Depends:, Packages knows nothing of a 5 GiB image.
#
# THE INDEXES ARE NOT ARTEFACTS, so they are NOT recorded in SHA256SUMS. Three reasons, and
# the first alone would be enough: they are rewritten every time a package is published, so
# a digest recorded for them would go stale by itself -- exactly the failure episode 9b had
# to repair. Then, apt already carries their integrity: Release holds the size and the
# digests of the Packages files, and only Release would ever need a signature. Last, an
# installer which reads SHA256SUMS as a list of things to download must not be offered an
# index as if it were an artefact.
#
# UNSIGNED, TODAY. Release is where a signature attaches (Release.gpg beside it, or an
# InRelease which embeds it), and until then apt wants `[trusted=yes]' spelled out in the
# sources.list line. Signing is the question of the SERVER episode -- it decides the key
# apt would name in `signed-by=' -- and inventing a key here would be inventing the answer.
#
# dpkg-scanpackages, not apt-ftparchive: the first comes with dpkg-dev, which
# Makefile.d/release.deb.sh already demands (dpkg-deb, dpkg-shlibdeps), and the second would
# add apt-utils to what a release machine must carry -- for a Release file which is ten
# lines of text.
#
# No bashbricks here, on purpose: like the five publishers it joins, this script sources
# nothing.
#
# Usage: Makefile.d/release.apt.sh [OPTIONS]
#
#   -o, --output-dir DIR         the release directory to index
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -c, --check                  say what the indexes hold, write nothing
#   -h, --help                   this help
# ---

set -euo pipefail

# The indexes are public data: 0644, whatever the packager's umask is (usually 002).
umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

function info { echo "==> $*"; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
  sed -n '/^# Usage: Makefile.d/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

# The series rule lives in the script which owns it, and is asked of it -- as in the four
# sibling publishers -- rather than computed a second time here.
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

SERIES=""
OUTDIR=""
CHECK=0

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -c|--check)      CHECK=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown option '$1' (try --help)" ;;
  esac
done

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

command -v dpkg-scanpackages >/dev/null || die "\`dpkg-scanpackages' not found (package dpkg-dev)"

shopt -s nullglob
DEBS=("$OUTDIR"/*.deb)
shopt -u nullglob

if ((CHECK)); then
  if test -f "$OUTDIR/Packages"; then
    info "$OUTDIR/Packages announces:"
    awk '/^Package: /{p=$2} /^Version: /{v=$2} /^Architecture: /{printf "    %s %s (%s)\n", p, v, $2}' \
        "$OUTDIR/Packages"
  else
    info "no Packages in $OUTDIR: this release is not readable by apt yet"
  fi
  test -f "$OUTDIR/Release" && info "Release is there ($(wc -l < "$OUTDIR/Release") lines)" \
                            || info "no Release in $OUTDIR"
  info "${#DEBS[@]} .deb in the directory"
  exit 0
fi

((${#DEBS[@]})) || die "no .deb in $OUTDIR: run \`make release-deb' first"

info "release dir  : $OUTDIR"
info "packages     : ${#DEBS[@]}"

# ---
# --- Packages.
# ---
# Run FROM the directory, with `.' as the binary path, so that the Filename: fields come
# out relative (./marionnet_0~trunk+r913_amd64.deb): apt resolves them against the URL of
# the sources.list line, which is this very directory. An absolute path here would publish
# the packager's home directory into the index.
#
# --multiversion keeps every version of a package instead of the newest only: a release
# directory may legitimately hold two revisions of the application while one is being
# replaced, and an index which hides one of them makes `apt install marionnet=<old>' fail
# for no reason a reader could see.
#
# NO override file argument. An override file is how a distribution overrules the Section
# and the Priority a package declares; here there is nobody above the packager -- both
# fields are written by release.deb.sh. Passing /dev/null does NOT mean "no override": it
# means an EMPTY one, and dpkg-scanpackages then warns, on every run, that the four
# packages are missing from it (measured).
( cd -- "$OUTDIR" && dpkg-scanpackages --multiversion . ) > "$OUTDIR/Packages.new" \
  || die "dpkg-scanpackages failed"
mv -f -- "$OUTDIR/Packages.new" "$OUTDIR/Packages"
gzip -9nc -- "$OUTDIR/Packages" > "$OUTDIR/Packages.gz"

# ---
# --- Release.
# ---
# Written here rather than by apt-ftparchive (see the header). The fields are the ones apt
# actually reads on a flat repository: it checks the digests of the Packages files it
# fetched against the ones listed here, and refuses an Architectures: line which does not
# mention the architecture of the machine.
#
# Architectures: is DERIVED from the packages present, not typed: `all' is there because
# marionnet-fs-guignol is arch-independent, and forgetting it would make apt ignore that
# package without a word.
# The two index files, listed for each digest section of Release: name, size and digest,
# in the layout apt parses (one leading space, then digest, size, path).
function digest_lines {  # <md5sum|sha256sum>
  local f
  for f in Packages Packages.gz; do
    printf ' %s %16d %s\n' "$("$1" -- "$OUTDIR/$f" | cut -d' ' -f1)" "$(stat -c%s -- "$OUTDIR/$f")" "$f"
  done
}

ARCHES=$(awk '/^Architecture: /{print $2}' "$OUTDIR/Packages" | sort -u | tr '\n' ' ')
ARCHES=${ARCHES% }

{
  echo "Origin: Marionnet"
  echo "Label: Marionnet"
  echo "Suite: $SERIES"
  echo "Codename: $SERIES"
  echo "Architectures: $ARCHES"
  echo "Components: "
  echo "Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
  echo "Description: Marionnet, the virtual network laboratory -- series $SERIES"
  # A flat repository has no component, hence the empty Components: above; the two index
  # files are listed by a path relative to this directory, and each digest section repeats
  # the whole list. `apt' picks the strongest one it understands.
  echo "MD5Sum:"
  digest_lines md5sum
  echo "SHA256:"
  digest_lines sha256sum
} > "$OUTDIR/Release.new"
mv -f -- "$OUTDIR/Release.new" "$OUTDIR/Release"

info "written: Packages, Packages.gz, Release  (architectures: $ARCHES)"
info "One line reaches this repository, and it needs [trusted=yes] until Release is signed:"
info "  deb [trusted=yes] <url-of-this-directory> ./"
