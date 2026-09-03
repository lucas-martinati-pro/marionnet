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

# Render the four installation pages of doc-src/ as standalone HTML, for the web site.
#
# WHAT THIS IS NOT. It is not a publisher: the six *.prepare-to-publish / release.* scripts
# next to it each build a piece of a RELEASE, and everything they write is named by
# SHA256SUMS. These pages are named by nothing, they describe no release, and they do not
# belong to a series -- they are the same kind of thing as bin/scripts/marionnet-install.sh,
# which upload.www.marionnet.org.sh publishes in the PARENT of the series directory. The
# uploader carries them there by the same block, and for the same reason.
#
# HENCE THE DEFAULT OUTPUT DIRECTORY, and it is not the release directory. A file dropped in
# website-repo/download/marionnet-install.sh/<series>/ is rsynced INTO the remote series and,
# being absent from SHA256SUMS, is classified an `extra' -- which `make release-and-upload'
# (PRUNE=1) then deletes. Published at the wrong URL, then erased. The parent is both the
# right URL and out of that machinery entirely.
#
# WHY PANDOC AND NOT A CONVERTER OF OUR OWN: writing a Markdown renderer to publish four
# files would be the second implementation of something that exists, which is what episode 8
# of this work-stream removed. pandoc is asked for, and its absence is said (rc 2) rather
# than worked around: a half-rendered page is worse than no page.
#
# WHY THE STYLE SHEET IS IN THE REPOSITORY (doc-src/marionnet-doc.css) and inlined
# (--embed-resources): the pages are copied one by one to a server which serves no asset of
# ours, so a page which names an external stylesheet is a page rendered naked. And a release
# script cannot depend on a file living in somebody's private configuration directory.
#
# THE COPY BUTTONS (doc-src/marionnet-doc-copy.html, inlined by --include-after-body) copy the
# block VERBATIM, and that is only honest because of a property of these pages: not one of
# their code blocks carries a `$' prompt or an interleaved output -- measured, 24 blocks per
# page, 0 prompt lines -- so what a block shows IS what one pastes. A page which showed
# `$ cmd' followed by its output would need the button to edit the text before copying it,
# which is where such buttons usually start lying.
#
# No bashbricks here, on purpose: like the eight scripts of Makefile.d/ it joins, this one
# sources nothing. Rendering four files in a loop is native shell all the way, and sourcing a
# library for it would add indirection, not safety.
#
# Usage: Makefile.d/release.install-pages.sh [OPTIONS]
#
#   -o, --output-dir DIR   where to write the .html
#                          (default: website-repo/download/marionnet-install.sh)
#   -n, --dry-run          say what would be rendered, write nothing
#   -h, --help             this help
#
# Exit: 0 rendered, 2 usage error or missing tool.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

function info { echo "==> $*"; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage { sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; }

# The four pages, and nothing else in doc-src/. The long pages and their quick guides are what
# somebody reads BEFORE having a machine to read them on; the teacher's guide, the exam mode
# and the scripting pages address a reader who has already installed Marionnet, and travel
# with the product (doc-src/dune) rather than with the web site.
PAGES=(INSTALL.md INSTALL.FR.md INSTALL-quick-guide.md INSTALL-quick-guide.FR.md)

OUTDIR=""
DRYRUN=0

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="${2%/}"; shift 2 ;;
    -n|--dry-run)    DRYRUN=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown option: $1 (try --help)" ;;
  esac
done

test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh"

command -v pandoc >/dev/null 2>&1 \
  || die "pandoc is not installed, and these pages are rendered with it: sudo apt install pandoc"

CSS="$ROOT/doc-src/marionnet-doc.css"
test -f "$CSS" || die "no such file: $CSS"
AFTER="$ROOT/doc-src/marionnet-doc-copy.html"
test -f "$AFTER" || die "no such file: $AFTER"

((DRYRUN)) || mkdir -p -- "$OUTDIR"
info "rendering ${#PAGES[@]} pages into $OUTDIR"

for md in "${PAGES[@]}"; do
  SRC="$ROOT/doc-src/$md"
  test -f "$SRC" || die "no such file: $SRC"
  DST="$OUTDIR/${md%.md}.html"

  # The <title> is the document's own first heading, read from it -- a title written here
  # would be a second place to keep in step with the page. It is given as `pagetitle' and not
  # as `title' on purpose: pandoc's HTML template renders `title' as an <h1 class="title"> of
  # its own, which would print the heading twice.
  TITLE=$(sed -n '1s/^# *//p' "$SRC")
  test -n "$TITLE" || die "$md does not start with a level-1 heading"

  # The French pages say so in the document element: a screen reader, and a browser's
  # translation offer, both read that attribute and nothing else.
  case "$md" in *.FR.md) LANG_TAG=fr ;; *) LANG_TAG=en ;; esac

  if ((DRYRUN)); then
    info "would render $md -> ${DST#"$ROOT"/} (lang=$LANG_TAG)"
    continue
  fi

  # Rendered beside the destination and moved into place: a run interrupted half way leaves
  # the page which was already served, never a truncated one.
  TMP=$(mktemp -- "$DST.XXXXXX")
  trap 'rm -f -- "$TMP"' EXIT
  pandoc "$SRC" -o "$TMP" \
         --from=gfm --to=html5 --standalone --embed-resources \
         --toc --toc-depth=2 \
         --css "$CSS" \
         --include-after-body "$AFTER" \
         --metadata pagetitle="$TITLE" \
         --metadata lang="$LANG_TAG"
  mv -f -- "$TMP" "$DST"
  chmod 644 -- "$DST"
  trap - EXIT
  info "$md -> ${DST#"$ROOT"/} ($(numfmt --to=iec --suffix=B "$(stat -c %s "$DST")"))"
done

((DRYRUN)) && info "nothing was written." || true
