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

# Turn a guest filesystem SNAPSHOT (a COW file, as produced by Marionnet's disk export,
# living in ~/.marionnet/filesystems/<image>_variants/) into the set of artefacts a
# release directory of marionnet.org is made of -- the shape of the reference couple
# `machine-debian-wheezy-08367':
#
#   machine-debian-wheezy-08367            the merged image (uml_moo COW + backing file)
#   machine-debian-wheezy-08367.conf       SUM/MD5SUM/DATE/MTIME/BINARY_LIST of THAT image
#   machine-debian-wheezy-08367.relay      only when the source image has one
#   machine-debian-wheezy-08367_variants/  empty directory
#   filesystems_machine-debian-wheezy-08367.tar.gz    what the installer downloads
#
# The name of the produced image carries the first field of `sum' (5 zero-padded digits),
# exactly like every image already published; MTIME is the `stat -L -c %Y' of the produced
# file, which the installer replays with `touch -d @$MTIME' -- see the comments of any .conf:
# user-mode-linux refuses a backing file whose mtime moved, so a project made on one
# installation would not open on another without this.
#
# Nothing already present is recomputed, unless -f|--force.
#
# Usage: Makefile.d/filesystem.prepare-snapshot-to-publish.sh [OPTIONS] [COW_FILE]
#
#   -o, --output-dir DIR         where to publish
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#       --print-series           print the series and exit
#   -f, --force                  redo what is already there
#       --do-not-update-binary-list
#                                keep the BINARY_LIST inherited from the source .conf
#                                (no loop mount, no sudo)
#   -y, --yes                    do not ask before building the tarball
#       --no-tarball             stop before the tarball
#   -h, --help                   this help
#
# Without COW_FILE, the most recent snapshot of ~/.marionnet/filesystems/*_variants/ is taken.
# ---

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

VARIANTS_ROOT="$HOME/.marionnet/filesystems"
SHARE_DIRS=(/usr/local/share/marionnet/filesystems /usr/share/marionnet/filesystems)

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
# META is the single source of truth for the version of the project (bin/version.ml.maker.sh
# reads it to generate Version.version, and so does useful-scripts/make_a_release_from_trunk.sh).
# A numbered version X.Y.Z publishes into the series X.Y.x. While META still says "trunk", we
# publish into 1.0.x: the series opened by the dune port (decision of episode 0 of the
# work-stream `modernisation-installation-marionnet', see docs/, § 6).
# This function is the ONLY implementation of that rule: the Makefile calls --print-series.
# ---
function publication_series {
  local version="trunk"
  if test -f "$ROOT/META"; then source "$ROOT/META"; fi
  case "$version" in
    [0-9]*.[0-9]*.[0-9]*) echo "${version%.*}.x" ;;
    [0-9]*.[0-9]*.x)      echo "$version"        ;;
    *)                    echo "1.0.x"           ;;
  esac
}

# ---
# --- Command line.
# ---
SERIES=""
OUTDIR=""
COW=""
FORCE=0
UPDATE_BINARY_LIST=1
ASSUME_YES=0
MAKE_TARBALL=1

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    --print-series)  publication_series; exit 0 ;;
    -f|--force)      FORCE=1; shift ;;
    --do-not-update-binary-list) UPDATE_BINARY_LIST=0; shift ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --no-tarball)    MAKE_TARBALL=0; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    *)               test -z "$COW" || die "at most one COW file expected"; COW="$1"; shift ;;
  esac
done

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"

# ---
# --- Requirements. `uml_moo' comes from the package `uml-utilities', already part of
# --- REQUIRED_PACKAGES_RUNTIME in the Makefile: nothing new to declare.
# ---
for cmd in uml_moo file sum md5sum tar gzip stat find awk dd sed tr; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found (uml_moo comes from the package uml-utilities)"
done

# ---
# --- 1. The COW file.
# ---
# Most recent (by mtime) among ~/.marionnet/filesystems/*_variants/*, keeping only what
# `file' recognizes as a UML COW file. LC_ALL=C: we match the ENGLISH wording of file(1).
# ---
function is_cow_file {
  LC_ALL=C file -b -- "$1" 2>/dev/null | grep -q "User-mode Linux COW file"
}

function find_latest_cow {
  local ts path
  test -d "$VARIANTS_ROOT" || return 1
  # shellcheck disable=SC2034  # `ts' is only there to consume the sort key
  while read -r ts path; do
    is_cow_file "$path" && { echo "$path"; return 0; }
  done < <(find "$VARIANTS_ROOT" -mindepth 2 -maxdepth 2 -type f -printf '%T@ %p\n' | sort -rn)
  return 1
}

if test -z "$COW"; then
  COW=$(find_latest_cow) || die "no snapshot found under $VARIANTS_ROOT (give a COW file as argument)"
  info "latest snapshot found: $COW"
fi
test -f "$COW" || die "no such file: $COW"
is_cow_file "$COW" || die "not a User-mode Linux COW file: $COW"
COW=$(readlink -f -- "$COW")

# ---
# --- 2. Its backing file, hence the source image, its .conf and its .relay.
# ---
# Three sources, tried in that order, each validated by the existence of the file it names:
#  (1) the COW header itself. In a version 3 header the backing path is a NUL-terminated
#      string at offset 32 (measured on the images of this machine, and consistent with
#      struct cow_header_v3 of user-mode-linux). This is the only source which is not
#      truncated: file(1) stops its `backing file' string after ~96 characters, so a deeply
#      nested path comes back cut in the middle;
#  (2) file(1), which also covers the older header versions we do not decode;
#  (3) the name of the parent directory <image>_variants, looked up in the usual share
#      directories -- the recorded path is stale as soon as the image moved.
# ---
function backing_file_of_cow {
  local cow="$1" backing image
  # `sed -z' re-emits the NUL terminator, which a command substitution would carry along
  # (bash 5 then warns and drops it): `tr' takes it off explicitly.
  backing=$(dd if="$cow" bs=1 skip=32 count=4096 status=none | LC_ALL=C sed -z -n '1p' | tr -d '\0')
  if test -n "$backing" && test -f "$backing"; then echo "$backing"; return 0; fi
  backing=$(LC_ALL=C file -b -- "$cow" | sed -n 's/.*backing file \(.*\)$/\1/p')
  if test -n "$backing" && test -f "$backing"; then echo "$backing"; return 0; fi
  image=$(basename -- "$(dirname -- "$cow")")
  image="${image%_variants}"
  local d
  for d in "${SHARE_DIRS[@]}"; do
    test -f "$d/$image" && { echo "$d/$image"; return 0; }
  done
  return 1
}

BACKING=$(backing_file_of_cow "$COW") \
  || die "cannot locate the backing file of $COW (neither in its header nor in ${SHARE_DIRS[*]})"
SRC_NAME=$(basename -- "$BACKING")
SRC_CONF="$BACKING.conf"
SRC_RELAY="$BACKING.relay"
test -f "$SRC_CONF" || die "the source image has no configuration file: $SRC_CONF"

# machine-debian-trixie-47362 -> machine-debian-trixie
PREFIX="${SRC_NAME%-[0-9][0-9][0-9][0-9][0-9]}"
test "$PREFIX" != "$SRC_NAME" || warn "the source image name does not end with a 5-digit sum: $SRC_NAME"

info "backing file : $BACKING"
info "source .conf : $SRC_CONF"
test -f "$SRC_RELAY" && info "source .relay: $SRC_RELAY" || true
info "series       : $SERIES"
info "output dir   : $OUTDIR"

mkdir -p -- "$OUTDIR"

# ---
# --- 3. The merge (uml_moo), then the name.
# ---
# The name of the result is only known AFTER the merge (it carries the sum of the produced
# file), so an already-published result cannot be recognized beforehand -- and merging just to
# discover that would write several gibibytes for nothing. Hence the hidden marker
# <outdir>/.<name>.origin, which records WHICH snapshot produced WHICH image: it is what makes
# a second run cheap. It is hidden, and never part of the tarball.
# ---
COW_MTIME=$(stat -L -c "%Y" -- "$COW")
COW_SIZE=$(stat -L -c "%s" -- "$COW")

function published_image_of_this_cow {
  # The whole body runs in a subshell: `nullglob' stays local, and so do the variables that
  # sourcing a marker overwrites (a marker sets COW, COW_MTIME, COW_SIZE and IMAGE).
  ( shopt -s nullglob
    local_marker=""; name=""
    for local_marker in "$OUTDIR"/.*.origin; do
      # shellcheck disable=SC1090
      name=$( source "$local_marker" 2>/dev/null
              if test "${COW:-}" = "$1" && test "${COW_MTIME:-}" = "$2" && test "${COW_SIZE:-}" = "$3"
              then echo "${IMAGE:-}"; fi )
      if test -n "$name" && test -f "$OUTDIR/$name"; then echo "$name"; exit 0; fi
    done
    exit 1 )
}

IMAGE_NAME=""
if ((! FORCE)); then
  IMAGE_NAME=$(published_image_of_this_cow "$COW" "$COW_MTIME" "$COW_SIZE") || IMAGE_NAME=""
  test -n "$IMAGE_NAME" && info "already merged, skipped: $OUTDIR/$IMAGE_NAME (use --force to redo)" || true
fi

if test -z "$IMAGE_NAME"; then
  PARTIAL="$OUTDIR/.$PREFIX.partial.$$"
  trap 'rm -f -- "$PARTIAL"' EXIT
  info "merging the snapshot with its backing file (uml_moo), this takes a while..."
  uml_moo -b "$BACKING" "$COW" "$PARTIAL"
  info "computing the checksum which names the image (sum)..."
  SUM=$(sum -- "$PARTIAL" | awk '{print $1}')
  IMAGE_NAME="$PREFIX-$SUM"
  if test -f "$OUTDIR/$IMAGE_NAME" && ((! FORCE)); then
    info "$IMAGE_NAME is already published: the freshly merged copy is dropped (use --force to replace it)"
    rm -f -- "$PARTIAL"
  else
    mv -f -- "$PARTIAL" "$OUTDIR/$IMAGE_NAME"
    info "image produced: $OUTDIR/$IMAGE_NAME"
  fi
  trap - EXIT
  cat > "$OUTDIR/.$IMAGE_NAME.origin" <<EOF
# Which snapshot produced this image (written by $(basename -- "${BASH_SOURCE[0]}")).
IMAGE="$IMAGE_NAME"
COW="$COW"
COW_MTIME="$COW_MTIME"
COW_SIZE="$COW_SIZE"
EOF
fi

IMAGE="$OUTDIR/$IMAGE_NAME"

# ---
# --- 4. BINARY_LIST, read INSIDE the produced image.
# ---
# Same definition as `binary_list' of uml/pupisto.common/toolkit_chroot.sh, except that the
# directories are named explicitly (we have no PATH of the guest here). Read-only loop mount,
# so the mtime of the image -- which the .conf is about to record -- is left alone.
# ---
function binary_list_of_image {
  local image="$1" mnt
  mnt=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "sudo umount -- '$mnt' 2>/dev/null || true; rmdir -- '$mnt' 2>/dev/null || true" RETURN
  sudo mount -o loop,ro -- "$image" "$mnt" || return 1
  local d dirs=()
  for d in bin sbin usr/bin usr/sbin usr/local/bin usr/local/sbin; do
    test -d "$mnt/$d" && dirs+=("$mnt/$d")
  done
  ((${#dirs[@]})) || return 1
  find "${dirs[@]}" -perm -u=x ! -type d ! -name "*[.]so*" -printf '%f\n' | sort -u | tr '\n' ' '
}

BINARY_LIST=""
if ((UPDATE_BINARY_LIST)); then
  info "rebuilding BINARY_LIST from the image (read-only loop mount, sudo required)..."
  BINARY_LIST=$(binary_list_of_image "$IMAGE") || BINARY_LIST=""
  if test -n "$BINARY_LIST"; then
    info "BINARY_LIST: $(wc -w <<<"$BINARY_LIST") binaries found"
  else
    warn "could not read the image: BINARY_LIST is INHERITED from $SRC_CONF and may be stale"
  fi
else
  warn "BINARY_LIST is INHERITED from $SRC_CONF (--do-not-update-binary-list) and may be stale"
fi

# ---
# --- 5. The .conf: the source one, with the fields which describe the image recomputed.
# ---
# `user_config_set' (uml/pupisto.common/toolkit_config_files.sh) is what pupisto.debian.sh
# already uses to write these very fields (toolkit_image.sh); reusing it keeps a single way of
# editing a .conf. Two of its habits are handled here: it returns 1 when the value was already
# right (hence --ignore-unchanged), and it predates `set -u' (hence the local relaxation).
# ---
source "$ROOT/uml/pupisto.common/toolkit_config_files.sh"

function conf_set {
  local rc=0
  set +u +e
  user_config_set --ignore-unchanged "$1" "=" "$2" "$3" || rc=$?
  set -u -e
  return $rc
}

CONF="$IMAGE.conf"
if test -f "$CONF" && ((! FORCE)); then
  info "already there, skipped: $CONF (use --force to redo)"
else
  info "computing MD5SUM..."
  MD5SUM=$(md5sum -- "$IMAGE" | awk '{print $1}')
  SUM=$(sum -- "$IMAGE" | awk '{print $1}')
  MTIME=$(stat -L -c "%Y" -- "$IMAGE")
  DATE=$(date -d "@$MTIME" +"%Y-%m-%d")
  cp -f -- "$SRC_CONF" "$CONF"
  conf_set "MD5SUM" "$MD5SUM"   "$CONF"
  conf_set "SUM"    "$SUM"      "$CONF"
  conf_set "DATE"   "$DATE"     "$CONF"
  conf_set "MTIME"  "$MTIME"    "$CONF"
  test -n "$BINARY_LIST" && conf_set "BINARY_LIST" "'$BINARY_LIST'" "$CONF" || true
  bash -n "$CONF" || die "the produced configuration file is not valid Bash: $CONF"
  info "configuration produced: $CONF (SUM=$SUM MD5SUM=$MD5SUM MTIME=$MTIME DATE=$DATE)"
fi

# ---
# --- 6. The .relay (only when the source image has one) and the empty _variants/.
# ---
if test -f "$SRC_RELAY"; then
  if test -f "$IMAGE.relay" && ((! FORCE)); then
    info "already there, skipped: $IMAGE.relay (use --force to redo)"
  else
    cp -f -- "$SRC_RELAY" "$IMAGE.relay"
    info "relay hook produced: $IMAGE.relay"
  fi
fi

if test -d "${IMAGE}_variants"; then
  info "already there, skipped: ${IMAGE}_variants/"
else
  mkdir -- "${IMAGE}_variants"
  info "variants directory created: ${IMAGE}_variants/"
fi

# ---
# --- 7. The tarball the installer downloads.
# ---
# Name and layout of the existing installer: download_our_large_filesystems() of
# useful-scripts/marionnet_from_scratch extracts with `wget -O - "$URL" | tar 1>&2 xvzf -'
# from $PREFIX/share/marionnet/, so the entries must be prefixed with `filesystems/'.
# --transform gives that prefix without copying gibibytes around.
# ---
TARBALL="$OUTDIR/filesystems_$IMAGE_NAME.tar.gz"

if ((! MAKE_TARBALL)); then
  info "tarball not requested (--no-tarball); nothing else to do."
  exit 0
fi

if test -f "$TARBALL" && ((! FORCE)); then
  info "already there, skipped: $TARBALL (use --force to redo)"
  exit 0
fi

MEMBERS=("$IMAGE_NAME" "$IMAGE_NAME.conf" "${IMAGE_NAME}_variants")
test -f "$IMAGE.relay" && MEMBERS+=("$IMAGE_NAME.relay") || true

if ((! ASSUME_YES)) && test -t 0; then
  SIZE=$(du -csh -- "${MEMBERS[@]/#/$OUTDIR/}" | tail -n 1 | awk '{print $1}')
  read -r -p "Build $TARBALL now (about $SIZE to compress, several minutes)? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) info "tarball not built; run again (or with -y) when you want it."; exit 0 ;;
  esac
fi

info "building $TARBALL ..."
trap 'rm -f -- "$TARBALL.partial"' EXIT
tar -C "$OUTDIR" --transform 's,^,filesystems/,' -czf "$TARBALL.partial" -- "${MEMBERS[@]}"
mv -f -- "$TARBALL.partial" "$TARBALL"
trap - EXIT
info "tarball produced: $TARBALL ($(du -h -- "$TARBALL" | awk '{print $1}'))"
