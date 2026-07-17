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
# Install the LAST built kernel produced by pupisto.kernel.sh into
# $PREFIX/share/marionnet/kernels/. Kernel-only counterpart of
# ../../pupisto.debian/Makefile.d/install.last-built-couple.sh (which installs
# a whole kernel+image couple from a pupisto.debian build).
#
# A built kernel lives in a `_build.linux-<epithet>.<date>.<rand>/' directory
# next to this script's parent (uml/pupisto.kernel/): the compiled tree holds
# a stripped `linux-<epithet>' hard link and its `linux-<epithet>.config',
# where <epithet> is `<version>' possibly suffixed (`-ghost', `-i386'...).
# The epithet is what Marionnet exposes and what the images' SUPPORTED_KERNELS
# match, hence both files are installed under that very name.
#
# Writing under /usr/local needs root, so file operations go through sudo.
# Use --dry-run to preview.
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Locate ourselves: KERNEL_BUILDS_DIR is uml/pupisto.kernel/ (parent of Makefile.d/)
SELF="$(realpath "$0")"
KERNEL_BUILDS_DIR="$(dirname "$(dirname "$SELF")")"

# --- Defaults / CLI ---------------------------------------------------------
PREFIX="/usr/local"
DRY_RUN="no"
BUILD_DIR=""   # optional: an explicit _build.* directory

function usage {
  cat 1>&2 <<EOF
Usage: $(basename "$0") [OPTIONS] [BUILD_DIR]

Install the last built kernel into \$PREFIX/share/marionnet/kernels/.

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

# --- 1. Detect the last finalized build ------------------------------------

# A build is finalized iff it holds a `linux-<epithet>.config' companion file
# (written by pupisto.kernel.sh next to the stripped binary, at the very end
# of a successful compilation).
function last_finalized_build {
  local d
  # Reverse-lexical == reverse-chronological (dir names embed YYYY-MM-DD.HHhMM).
  while IFS= read -r d; do
    if compgen -G "$d/linux-*.config" >/dev/null; then
      echo "$d"; return 0
    fi
  done < <(find "$KERNEL_BUILDS_DIR" -maxdepth 1 -type d -name '_build.*' | sort -r)
  return 1
}

if [[ -n $BUILD_DIR ]]; then
  BUILD_DIR="$(realpath "$BUILD_DIR")"
  [[ -d $BUILD_DIR ]] || die "No such build directory: $BUILD_DIR"
  compgen -G "$BUILD_DIR/linux-*.config" >/dev/null \
    || die "Build directory has no finalized kernel (missing linux-*.config): $BUILD_DIR"
else
  BUILD_DIR="$(last_finalized_build)" \
    || die "No finalized build (_build.*/linux-*.config) found under $KERNEL_BUILDS_DIR"
fi
echo "Selected build: $BUILD_DIR"

# --- 2. Resolve the kernel artefacts ----------------------------------------

KERNEL_CONFIG="$(ls -1 "$BUILD_DIR"/linux-*.config | sort | tail -n 1)"
KERNEL_BIN="${KERNEL_CONFIG%.config}"
[[ -f $KERNEL_BIN ]] || die "Kernel binary missing next to its config: $KERNEL_BIN"
KERNEL_NAME="$(basename "$KERNEL_BIN")"   # the epithet, e.g. linux-6.12.95-i386

echo "  kernel : $KERNEL_NAME  ($(du -h "$KERNEL_BIN" | cut -f1))"
echo "  config : $KERNEL_NAME.config"

# --- 3. Install ------------------------------------------------------------

KDEST="$PREFIX/share/marionnet/kernels"

echo
echo "Installing into $KDEST/"
[[ $DRY_RUN = yes ]] && echo "(dry-run: nothing will be written)"

run_sudo mkdir -p "$KDEST"
run_sudo cp -f "$KERNEL_BIN" "$KDEST/$KERNEL_NAME"
run_sudo chmod 0755 "$KDEST/$KERNEL_NAME"
run_sudo cp -f "$KERNEL_CONFIG" "$KDEST/$KERNEL_NAME.config"

echo
echo "Done."
if [[ $DRY_RUN != yes ]]; then
  echo "--- $KDEST ---"; ls -l "$KDEST/$KERNEL_NAME" "$KDEST/$KERNEL_NAME.config"
fi
