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
#   SHA256SUMS  what bin/scripts/marionnet-install.sh reads -- names and digests of the
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
# SIGNED SINCE EPISODE 30, and by THIS script. Release is where a signature attaches:
# Release.gpg beside it, or InRelease which is Release with the signature wrapped around it.
# Both are written here, by `--sign', and not by the deposit script which used to do it: they
# are void the moment Release changes, so they belong to whoever writes Release. Two things
# follow, and both were the point: a release directory is COMPLETE before anything is
# deposited -- so the local bench, which never touches a server, can measure `signed-by='
# instead of `[trusted=yes]' -- and the deposit script recovers its rule without an
# exception, writing nothing into a release directory.
#
# The key is NOT invented here: it is the one the sources publish, marionnet-archive-keyring.asc
# at the root of the tree, which users fetch from the git repository -- i.e. from an
# infrastructure other than the server serving the packages. That separation is the entire
# worth of a signature, and it is why `--sign' alone reads the fingerprint from that file.
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
#       --sign [KEYID]           sign Release: InRelease (clear-signed) and Release.gpg
#                                (detached), which is what lets a user write `signed-by='
#                                instead of `[trusted=yes]'. Given no KEYID, the key is the
#                                one the SOURCES publish -- the fingerprint read from
#                                marionnet-archive-keyring.asc at the root of the tree.
#   -h, --help                   this help
# ---

set -euo pipefail

# The indexes are public data: 0644, whatever the packager's umask is (usually 002).
umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

function info { echo "==> $*"; }
function warn { echo "==> WARNING: $*" >&2; }
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
SIGN_KEY=""
# The public key the SOURCES publish: the archive's identity, versioned in git and fetched by
# users from THERE -- i.e. from an infrastructure which is not the server this repository is
# deposited on. Signing with a key the sources do not publish would produce a repository
# nobody can verify, silently, so the two are checked against each other below.
KEYRING_ASC="$ROOT/marionnet-archive-keyring.asc"

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -c|--check)      CHECK=1; shift ;;
    --sign)          # optional argument: `--sign' alone means the published key.
                     if test $# -ge 2 && case "$2" in -*) false ;; *) test -n "$2" ;; esac
                     then SIGN_KEY="$2"; shift 2
                     else SIGN_KEY="@published"; shift 1
                     fi ;;
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

# ---
# --- The signature (episode 30).
# ---
# WRITTEN HERE, by the indexer, and no longer by the deposit script. Release says what this
# repository contains; InRelease and Release.gpg say that the same person vouches for it, and
# they are worthless the moment Release changes -- so they belong beside the file they sign,
# written by whoever writes it. Two consequences, both wanted: a release directory is
# COMPLETE before anything is deposited (so the local bench, which never touches a server,
# can measure `signed-by=' -- it could not while only the deposit signed), and the deposit
# script recovers its rule WITHOUT AN EXCEPTION: it writes nothing into a release directory.
#
# Not in SHA256SUMS, like the other indexes: they are rewritten at every publication, so a
# digest recorded for them would go stale on its own (the defect of episode 9b).
if test -n "$SIGN_KEY"; then
  command -v gpg >/dev/null || die "\`gpg' not found, but --sign was asked"
  if test "$SIGN_KEY" = "@published"; then
    test -f "$KEYRING_ASC" \
      || die "--sign was given alone, but $KEYRING_ASC does not exist: nothing says who this archive is"
    SIGN_KEY=$(gpg --with-colons --show-keys -- "$KEYRING_ASC" 2>/dev/null \
               | awk -F: '$1=="fpr" {print $10; exit}')
    test -n "$SIGN_KEY" || die "cannot read a fingerprint out of $KEYRING_ASC"
  fi
  gpg --list-secret-keys -- "$SIGN_KEY" >/dev/null 2>&1 \
    || die "no secret key '$SIGN_KEY' in this keyring"
  # The key we sign with and the key the sources publish must be the same, checked even when
  # a KEYID was given by hand -- that is precisely when the two can drift apart.
  if test -f "$KEYRING_ASC"; then
    published=$(gpg --with-colons --show-keys -- "$KEYRING_ASC" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')
    signing=$(gpg --with-colons --list-secret-keys -- "$SIGN_KEY" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')
    test "$published" = "$signing" \
      || die "the signing key ($signing) is not the one the sources publish ($published)"
  fi
  # Both forms, because apt takes either and only the detached one reaches an old apt.
  gpg --batch --yes --default-key "$SIGN_KEY" --clearsign -o "$OUTDIR/InRelease.new" -- "$OUTDIR/Release" \
    || die "signing failed (InRelease)"
  gpg --batch --yes --default-key "$SIGN_KEY" --armor --detach-sign -o "$OUTDIR/Release.gpg.new" -- "$OUTDIR/Release" \
    || die "signing failed (Release.gpg)"
  mv -f -- "$OUTDIR/InRelease.new"   "$OUTDIR/InRelease"
  mv -f -- "$OUTDIR/Release.gpg.new" "$OUTDIR/Release.gpg"
  info "signed: InRelease, Release.gpg  (key $SIGN_KEY)"
  info "One line reaches this repository, and the key comes from the SOURCES, not from here:"
  info "  deb [signed-by=/etc/apt/keyrings/marionnet.asc] <url-of-this-directory> ./"
else
  # A repository which stops being signed is worse than one which never was: every machine
  # already carrying signed-by= would refuse it. So the stale signatures go.
  for f in InRelease Release.gpg; do
    if test -f "$OUTDIR/$f"; then
      rm -f -- "$OUTDIR/$f"
      warn "removed a STALE $f: it signed a previous Release (re-run with \`--sign')"
    fi
  done
  info "One line reaches this repository, and it needs [trusted=yes] until Release is signed:"
  info "  deb [trusted=yes] <url-of-this-directory> ./"
fi
