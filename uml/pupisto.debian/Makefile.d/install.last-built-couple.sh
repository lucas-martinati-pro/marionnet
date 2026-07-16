#!/usr/bin/env bash
# This file is part of marionnet
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

# ---------------------------------------------------------------------------
# Install the LAST built (kernel, filesystem-image) couple produced by
# pupisto.debian.sh into $PREFIX/share/marionnet/{kernels,filesystems}/.
#
# A "built couple" lives in a `_build.<distro>-with-linux-<ver>.<date>/'
# directory next to this script's parent (uml/pupisto.debian/). We pick the
# most recent such directory that actually contains a finalized image (proven
# by the presence of a `machine-*.conf' companion file), then:
#
#   * filesystem image `machine-<distro>-<SUM>' (+ its `.conf', + a
#     `_variants/' directory if present) -> filesystems/
#     and we restore the image MTIME recorded in the `.conf' (mandatory for
#     sharing Marionnet projects across installations -- see the conf itself);
#   * kernel: the build directory holds a `linux-<ver>' symlink to the
#     compiled UML tree; we install its `linux' binary as kernels/linux-<ver>
#     and its `.config' as kernels/linux-<ver>.config.
#
# Modern Debian images (e.g. trixie) use GHOSTIFICATION=netns: the kernel is
# NOT ghostification-patched, hence the plain `linux-<ver>' epithet (no
# `-ghost' suffix). The image `.conf' selects it via SUPPORTED_KERNELS,
# typically a regexp matching that version.
#
# Writing under /usr/local needs root, so file operations go through sudo
# (like useful-scripts/marionnet_from_scratch). Use --dry-run to preview.
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Locate ourselves: PUPISTO_DIR is uml/pupisto.debian/ (parent of Makefile.d/)
SELF="$(realpath "$0")"
PUPISTO_DIR="$(dirname "$(dirname "$SELF")")"

# --- Defaults / CLI ---------------------------------------------------------
PREFIX="/usr/local"
DRY_RUN="no"
BUILD_DIR=""   # optional: an explicit _build.* directory

function usage {
  cat 1>&2 <<EOF
Usage: $(basename "$0") [OPTIONS] [BUILD_DIR]

Install the last built (kernel, image) couple into
\$PREFIX/share/marionnet/{kernels,filesystems}/.

Options:
  -p, --prefix PATH   Installation prefix (default: $PREFIX)
  -n, --dry-run       Show what would be done, touch nothing
  -h, --help          This help

BUILD_DIR             Install this specific _build.* directory instead of
                      auto-detecting the most recent finalized one.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prefix) PREFIX="$2"; shift 2 ;;
    -n|--dry-run) DRY_RUN="yes"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo 1>&2 "Unknown option: $1"; usage; exit 1 ;;
    *) BUILD_DIR="$1"; shift ;;
  esac
done

# --- Small helpers ----------------------------------------------------------

# run: echo the command, then run it (unless dry-run). Privileged variant: run_sudo.
function run      { echo "+ $*";        [[ $DRY_RUN = yes ]] || "$@"; }
function run_sudo { echo "+ sudo $*";   [[ $DRY_RUN = yes ]] || sudo "$@"; }

function die { echo 1>&2 "Error: $*"; exit 1; }

# conf_get FILE VAR : print the value of a `VAR=value' assignment in a conf.
function conf_get {
  local file="$1" var="$2"
  sed -n -E "s/^${var}=[\"']?([^\"']*)[\"']?[[:space:]]*\$/\1/p" "$file" | tail -n 1
}

# --- 1. Detect the last finalized build ------------------------------------

# A build is finalized iff it holds a `machine-*.conf' companion file.
function last_finalized_build {
  local d
  # Reverse-lexical == reverse-chronological (dir names embed YYYY-MM-DD.HHhMM).
  while IFS= read -r d; do
    if compgen -G "$d/machine-*.conf" >/dev/null; then
      echo "$d"; return 0
    fi
  done < <(find "$PUPISTO_DIR" -maxdepth 1 -type d -name '_build.*' | sort -r)
  return 1
}

if [[ -n $BUILD_DIR ]]; then
  BUILD_DIR="$(realpath "$BUILD_DIR")"
  [[ -d $BUILD_DIR ]] || die "No such build directory: $BUILD_DIR"
  compgen -G "$BUILD_DIR/machine-*.conf" >/dev/null \
    || die "Build directory has no finalized image (missing machine-*.conf): $BUILD_DIR"
else
  BUILD_DIR="$(last_finalized_build)" \
    || die "No finalized build (_build.*/machine-*.conf) found under $PUPISTO_DIR"
fi
echo "Selected build: $BUILD_DIR"

# --- 2. Resolve the filesystem-image artefacts -----------------------------

CONF="$(ls -1 "$BUILD_DIR"/machine-*.conf | sort | tail -n 1)"
IMAGE="${CONF%.conf}"
[[ -f $IMAGE ]] || die "Image file missing next to its conf: $IMAGE"
IMAGE_NAME="$(basename "$IMAGE")"
VARIANTS_DIR="${IMAGE}_variants"   # optional
MTIME="$(conf_get "$CONF" MTIME)"

echo "  image  : $IMAGE_NAME  ($(du -h "$IMAGE" | cut -f1))"
echo "  conf   : $(basename "$CONF")  (MTIME=${MTIME:-none}, SUPPORTED_KERNELS=$(conf_get "$CONF" SUPPORTED_KERNELS))"
[[ -d $VARIANTS_DIR ]] && echo "  variants: $(basename "$VARIANTS_DIR")/"

# --- 3. Resolve the kernel artefacts (tolerate --no-kernel builds) ----------

KERNEL_NAME=""; KERNEL_BIN=""; KERNEL_CONFIG=""
KERNEL_LINK="$(find "$BUILD_DIR" -maxdepth 1 -name 'linux-*' \( -type l -o -type d \) | sort | tail -n 1 || true)"
if [[ -n $KERNEL_LINK ]]; then
  KERNEL_NAME="$(basename "$KERNEL_LINK")"        # e.g. linux-6.12.95
  KERNEL_TREE="$(realpath "$KERNEL_LINK")"
  # UML kernel binary is `linux' (== vmlinux); its config is `.config'.
  if [[ -f $KERNEL_TREE/linux ]]; then KERNEL_BIN="$KERNEL_TREE/linux"
  elif [[ -f $KERNEL_TREE/vmlinux ]]; then KERNEL_BIN="$KERNEL_TREE/vmlinux"
  fi
  [[ -f $KERNEL_TREE/.config ]] && KERNEL_CONFIG="$KERNEL_TREE/.config"
fi

if [[ -n $KERNEL_BIN ]]; then
  echo "  kernel : $KERNEL_NAME  ($(du -h "$KERNEL_BIN" | cut -f1))"
  [[ -n $KERNEL_CONFIG ]] && echo "  config : $KERNEL_NAME.config"
else
  echo "  kernel : (none -- installing the image only)"
fi

# --- 4. Install ------------------------------------------------------------

SHARE="$PREFIX/share/marionnet"
KDEST="$SHARE/kernels"
FDEST="$SHARE/filesystems"

echo
echo "Installing into $SHARE/{kernels,filesystems}/"
[[ $DRY_RUN = yes ]] && echo "(dry-run: nothing will be written)"

run_sudo mkdir -p "$KDEST" "$FDEST"

# 4a. Filesystem image (+ conf, + variants), then restore MTIME.
run_sudo cp -f "$IMAGE" "$FDEST/$IMAGE_NAME"
run_sudo cp -f "$CONF"  "$FDEST/$(basename "$CONF")"
if [[ -d $VARIANTS_DIR ]]; then
  run_sudo cp -a "$VARIANTS_DIR" "$FDEST/"
fi
if [[ -n $MTIME ]]; then
  run_sudo touch -d "@$MTIME" "$FDEST/$IMAGE_NAME"
fi

# 4b. Kernel (only if present).
if [[ -n $KERNEL_BIN ]]; then
  run_sudo cp -f "$KERNEL_BIN" "$KDEST/$KERNEL_NAME"
  run_sudo chmod 0755 "$KDEST/$KERNEL_NAME"
  if [[ -n $KERNEL_CONFIG ]]; then
    run_sudo cp -f "$KERNEL_CONFIG" "$KDEST/$KERNEL_NAME.config"
  fi
fi

echo
echo "Done."
if [[ $DRY_RUN != yes ]]; then
  echo "--- $FDEST ---"; ls -l "$FDEST/$IMAGE_NAME" "$FDEST/$(basename "$CONF")"
  if [[ -n $KERNEL_BIN ]]; then
    echo "--- $KDEST ---"; ls -l "$KDEST/$KERNEL_NAME" ${KERNEL_CONFIG:+"$KDEST/$KERNEL_NAME.config"}
  fi
fi
