#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
# Copyright (C) 2026  Université Sorbonne Paris Nord
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

# --- Two badged icon sets for the two bridge components
#
# Since episode 7a.3.b of the work-stream `modernisation-world-bridge' there are two
# bridges, and a user must tell them apart on the drawing: the LAN bridge, which joins
# a bridge an administrator built on the host, and the NAT bridge, which Marionnet
# builds for itself. Until the announced iconography episode gives each one a drawing
# of its own, both wear the historical `ico.world_bridge.*' picture with a word stamped
# on it -- a stopgap, and an assumed one (at 32 pixels the word is barely readable).
#
# The 18 `ico.world_bridge.*' files are NOT touched: they are the SOURCE, and the two
# generated sets are named apart. That is what makes this script re-runnable: running
# it twice writes exactly the same bytes (the date chunks of the PNG are excluded on
# purpose, otherwise every run would show up as a change in git).
#
# Usage:
#   ./make-bridge-icons.sh            generate the two sets beside the sources
#   ./make-bridge-icons.sh --check    generate nothing; report whether the files on
#                                     disk are what this script would write
#
# Plain shell on purpose (no bashbricks): the whole job is a loop over 18 files, with
# no collection, no JSON and no parallelism to speak of.

set -euo pipefail

cd "$(dirname "$0")"

SOURCE_PREFIX="ico.world_bridge"

# The badge of each generated set: <prefix> <word> <background colour>
BADGES=(
  "ico.nat_bridge NAT #c1440e"
  "ico.lan_bridge LAN #1a5fb4"
)

function die {
  echo "make-bridge-icons.sh: $*" >&2
  exit 1
}

# Stamp $1 (a source icon) into $2, with the word $3 on the background colour $4.
# ---
# The badge is a fixed-size `label:' box, which lets ImageMagick pick the largest
# point size that fits, and it is placed at the bottom right OF THE SQUARE PART of
# the icon: the `pause' variants are taller than they are wide (the pause marker
# hangs below), and a badge glued to their bottom edge would sit outside the drawing.
function stamp {
  local source="$1" destination="$2" word="$3" colour="$4"
  local width height badge_width badge_height offset
  # --- The geometry is derived from the width alone, for the reason said above:
  width=$(identify -format '%w' "$source")
  height=$(identify -format '%h' "$source")
  [[ $width -ge 16 && $height -ge 16 ]] || die "$source: unexpected size ${width}x${height}"
  badge_width=$(( (width * 62) / 100 ))
  badge_height=$(( (width * 30) / 100 ))
  offset=$(( width - badge_height - 1 ))
  # --- The +set of the date properties is what makes the output reproducible:
  convert "$source" \
    \( -background "$colour" -fill white -size "${badge_width}x${badge_height}" -gravity center "label:${word}" \) \
    -gravity NorthEast -geometry "+1+${offset}" -composite \
    -define png:exclude-chunk=date,tIME,time +set date:create +set date:modify +set date:timestamp \
    "$destination"
}

which convert >/dev/null 2>&1 || die "ImageMagick's \`convert' is required"

sources=( "$SOURCE_PREFIX".*.png )
[[ ${#sources[@]} -ge 18 ]] || die "expected at least 18 \`$SOURCE_PREFIX.*.png' sources, found ${#sources[@]}"

check_only=false
if [[ $# -gt 0 ]]; then
  case "$1" in
    --check) check_only=true ;;
    *) die "unknown option \`$1' (usage: $0 [--check])" ;;
  esac
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

differences=0
generated=0

for badge in "${BADGES[@]}"; do
  read -r prefix word colour <<<"$badge"
  [[ "$prefix" != "$SOURCE_PREFIX" ]] || die "refusing to overwrite the sources"
  for source in "${sources[@]}"; do
    suffix="${source#${SOURCE_PREFIX}.}"          # e.g. "on.small.png"
    destination="${prefix}.${suffix}"
    stamp "$source" "$temporary/$destination" "$word" "$colour"
    if $check_only; then
      if ! cmp -s "$temporary/$destination" "$destination"; then
        echo "differs: $destination"
        differences=$(( differences + 1 ))
      fi
    else
      mv "$temporary/$destination" "$destination"
      generated=$(( generated + 1 ))
    fi
  done
done

if $check_only; then
  if [[ $differences -eq 0 ]]; then
    echo "up to date: the icons on disk are the ones this script generates"
  else
    echo "$differences file(s) differ; run $0 to regenerate them" >&2
    exit 1
  fi
else
  echo "$generated icons generated from $SOURCE_PREFIX.*.png (sources untouched)"
fi
