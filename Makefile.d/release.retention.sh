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

# How many revisions of the application a release keeps -- and the only place that question
# is answered. A release directory ACCUMULATES: every episode which publishes leaves one more
# revision of the tarball, of the .deb and of the .rpm, and both package indexes then offer
# every one of them. Measured on 2026-09-01 (episode 25), after a single day of work: 8
# tarballs, 4 marionnet .deb and 5 marionnet .rpm, so `apt install marionnet=0~trunk+r913'
# legitimately returned a build from BEFORE the episode 21 fix, and five of the eight
# tarballs predated the floor box (glibc2.39) and were therefore refused on Debian 12 and
# served for nothing.
#
# ONLY THE APPLICATION IS CONCERNED. The other packages are NOT versioned by the revision --
# a kernel is 6.12.95, a guest image is its `sum' (18474) -- so there is never more than one
# of each, and republishing them would give them a new mtime, which is what UML checks
# (episode 23). This script does not look at them.
#
# WHY A SCRIPT OF ITS OWN, rather than an option of the depositor. Makefile.d/upload.www.
# marionnet.org.sh states, as its design rule, that it writes nothing into a release
# directory: what it deposits, someone else made. Retention is a decision about the CONTENT
# of a release, so it cannot live there. But the depositor must still be able to WARN about
# superseded revisions before spending an hour uploading them, so it asks this script --
# `--print-superseded' -- instead of computing the same thing a second time. One rule, one
# owner, two readers.
#
# WHAT IT DOES NOT DO: touch the server. Removing a file here makes the catalogue drop its
# line, which makes the depositor see the remote copy as an extra -- and an extra is NAMED,
# never removed, unless `--prune' is asked for. The two halves stay separate on purpose:
# deciding a release no longer offers r913 and reaching into a public server are not the
# same gesture, and should not be one command's side effect.
#
# THE THREE CATALOGUES ARE REWRITTEN BY THEIR OWN WRITERS, never by hand: release.sha256sums.sh
# drops the orphan lines by itself, release.apt.sh rewrites Packages/Release, release.dnf.sh
# rewrites repodata/. That is the rule episode 24 paid for, and this script obeys it rather
# than editing what it just invalidated.
#
# No bashbricks here, on purpose: like the seven scripts it joins, this one sources nothing.
#
# Usage: Makefile.d/release.retention.sh [OPTIONS]
#
#   -o, --output-dir DIR         the release directory to tidy
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -k, --keep N                 revisions of the application to keep, newest first
#                                (default: 1)
#       --print-superseded       print what is beyond --keep, one name per line, and exit
#                                (this is what the depositor's warning reads)
#   -n, --dry-run                say what would be removed, remove nothing
#       --no-reindex             do not rewrite the catalogues afterwards (rarely wanted:
#                                a removed artefact left in SHA256SUMS announces a ghost)
#       --sign [KEYID]           relayed to release.apt.sh when reindexing: rewriting Release
#                                invalidates the signature beside it, so a run which removes
#                                a revision must re-sign or leave the repository unverifiable
#   -h, --help                   this help
# ---

set -euo pipefail

umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

function info { echo "==> $*"; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
  sed -n '/^# Usage: Makefile.d/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

SERIES=""; OUTDIR=""; KEEP=1; PRINT_ONLY=0; DRYRUN=0; REINDEX=1
SIGN_ARGS=()   # relayed verbatim to the indexer, which owns the signature (episode 30)

while (($#)); do
  case "$1" in
    -o|--output-dir)     OUTDIR="$2"; shift 2 ;;
    -s|--series)         SERIES="$2"; shift 2 ;;
    -k|--keep)           KEEP="$2"; shift 2 ;;
       --print-superseded) PRINT_ONLY=1; shift ;;
    -n|--dry-run)        DRYRUN=1; shift ;;
       --no-reindex)     REINDEX=0; shift ;;
    --sign)              if test $# -ge 2 && case "$2" in -*) false ;; *) test -n "$2" ;; esac
                         then SIGN_ARGS=(--sign "$2"); shift 2
                         else SIGN_ARGS=(--sign); shift 1
                         fi ;;
    -h|--help)           usage; exit 0 ;;
    *)                   die "unknown option '$1' (try --help)" ;;
  esac
done

[[ "$KEEP" =~ ^[0-9]+$ ]] && ((KEEP >= 1)) || die "--keep wants a positive integer, got '$KEEP'"

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

# ---
# --- The three shapes the application takes, and the revision each name carries.
# ---
# The revision is read FROM THE NAME, as release.rpm.sh does since episode 20c: the name is
# what the release directory publishes, and asking the working copy instead would describe
# this machine rather than that directory.
function revision_of {  # <name> -> the r<N> it carries, or nothing
  local n="$1"
  case "$n" in
    marionnet_trunk-r*)   echo "${n#marionnet_trunk-r}"   | sed 's/_.*//' ;;
    marionnet_0~trunk+r*) echo "${n#marionnet_0~trunk+r}" | sed 's/_.*//' ;;
    marionnet-0~trunk+r*) echo "${n#marionnet-0~trunk+r}" | sed 's/-.*//' ;;
  esac
}

shopt -s nullglob
SUPERSEDED=()
for pat in 'marionnet_trunk-r*' 'marionnet_0~trunk+r*' 'marionnet-0~trunk+r*'; do
  fam=("$OUTDIR"/$pat)
  ((${#fam[@]} > KEEP)) || continue
  # Sorted by revision, oldest first; everything but the last $KEEP is superseded.
  while read -r _ name; do SUPERSEDED+=("$name"); done < <(
    for f in "${fam[@]}"; do b=$(basename -- "$f"); printf '%s\t%s\n' "$(revision_of "$b")" "$b"; done \
    | sort -n | head -n -"$KEEP")
done
shopt -u nullglob

if ((PRINT_ONLY)); then
  printf '%s\n' "${SUPERSEDED[@]:-}" | grep -v '^$' || true
  exit 0
fi

info "release dir  : $OUTDIR"
info "keeping      : the $KEEP newest revision(s) of the application, per channel"

if ((${#SUPERSEDED[@]} == 0)); then
  info "nothing to remove: no revision is beyond --keep $KEEP"
  exit 0
fi

info "superseded   : ${#SUPERSEDED[@]} file(s)"
printf '    %s\n' "${SUPERSEDED[@]}"

if ((DRYRUN)); then
  info "--dry-run: nothing was removed, and no catalogue was rewritten"
  exit 0
fi

for f in "${SUPERSEDED[@]}"; do rm -f -- "$OUTDIR/$f"; done
info "removed: ${#SUPERSEDED[@]} file(s)"

# ---
# --- The catalogues, rewritten by the scripts which own them.
# ---
# Not optional in practice: SHA256SUMS is the catalogue the installer reads, so a line left
# for a file which is gone announces a ghost -- the installer would fetch a 404. The two
# package indexes would keep offering versions apt and dnf can no longer download.
if ((REINDEX)); then
  info "rewriting the three catalogues, each by its own writer"
  bash "$ROOT/Makefile.d/release.sha256sums.sh" --series "$SERIES" --output-dir "$OUTDIR"
  # --sign relayed, and it MATTERS: rewriting Release invalidates the signature beside it, so
  # a retention run which did not re-sign would silently leave a release nobody can verify
  # (release.apt.sh removes the stale InRelease, which is the visible half of the same fact).
  bash "$ROOT/Makefile.d/release.apt.sh"        --series "$SERIES" --output-dir "$OUTDIR" \
       ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"}
  bash "$ROOT/Makefile.d/release.dnf.sh"        --series "$SERIES" --output-dir "$OUTDIR" \
       --base-url "https://www.marionnet.org/download/rpm/"
else
  info "--no-reindex: the catalogues still announce what was just removed"
fi

info "done. The remote copies are now EXTRAS: \`make release-upload PRUNE=1' removes them."
