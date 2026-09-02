#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2023  Jean-Vincent Loddo
# Copyright (C) 2023  Université Sorbonne Paris Nord (USPN)
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

# ---
SRC_PROJECT_DIR="$(dirname $0)/.."
# ---
# `--print-revision' prints the revision number and exits, which is what `make revno'
# is made of -- the answer `bzr revno' used to give. It lives HERE, in front of the
# rule it prints, because this script is where the rule is: prefer git's
# `rev-list --count', fall back on bzr while .bzr is still around. Writing
# `git rev-list --count HEAD' in the Makefile instead would be a second source of
# truth for the number every published artefact is named after, and the two would
# part company the day the fallback matters. Same shape as the `--print-series' of
# Makefile.d/filesystem.prepare-snapshot-to-publish.sh.
# ---
function project_revision {
  local REPO_DIR; REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$REPO_DIR" ]] && [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" rev-list --count HEAD
  elif [[ -d "$SRC_PROJECT_DIR/.bzr" ]]; then
    bzr revno
  else
    echo 1>&2 "Error: neither git nor bzr metadata found"; return 5
  fi
}

# ---
# --- The version of the project, and the SINGLE implementation of the rule that makes it.
# ---
# META names a SERIES (`1.0.x'), not a version: the patch level counts the revisions of that
# series, and is therefore derived -- `1.0.x' plus (revision - series_base_revision) makes
# `1.0.368' out of revision 942. Deriving it is what keeps two different revisions from ever
# calling themselves the same version, which a hand-edited number cannot promise; and taking
# the base away is what keeps the patch level from counting the 574 revisions the 0.90.x and
# 0.98.x series had already spent before the dune port existed.
#
# It lives HERE, next to `--print-revision', for the same reason that one does: this script
# is where the revision is read, and the version is a function of it. Everyone else ASKS
# (`--print-version'): bin/version.ml.maker.sh for Version.version, Makefile.d/release.binary.sh
# for the name every published artefact carries, `make version' for a human.
#
# Two shapes are rendered UNCHANGED, and both mean "do not derive": a version META already
# spells out in full (`1.0.0' -- a frozen release), and anything which is not a series at all
# (`trunk'). The series itself (`1.0.x') is also what comes back when the derivation cannot be
# made -- no VCS, no base, or a base ahead of the revision. That answer is deliberately NOT a
# number: initialization.ml then shows "Version 1.0.x revno ..." instead of claiming a patch
# level nobody computed, and release.binary.sh refuses to name an artefact with it (episode
# 30b ter: a name is the only place the glibc floor is written; the same holds for the version).
# ---
function project_version {  # [META file]
  local meta="$1"; test -n "$meta" || meta="$SRC_PROJECT_DIR/META"
  local version="trunk" series_base_revision=""
  if test -f "$meta"; then source "$meta"; fi
  case "$version" in
    [0-9]*.[0-9]*.x) : ;;              # a series: derive the patch level below
    *) echo "$version"; return 0 ;;    # a full version, or `trunk': hand it back as it is
  esac
  local rev base
  rev=$(project_revision 2>/dev/null) || { echo "$version"; return 0; }
  base="$series_base_revision"
  if [[ ! $rev =~ ^[0-9]+$ ]] || [[ ! $base =~ ^[0-9]+$ ]] || (( rev <= base )); then
    echo 1>&2 "Warning: cannot derive a patch level from revision '$rev' and base '$base' => using '$version'"
    echo "$version"; return 0
  fi
  echo "${version%.x}.$(( rev - base ))"
}

if [[ "${1:-}" = "--print-revision" ]]; then project_revision; exit $?; fi
if [[ "${1:-}" = "--print-version"  ]]; then project_version "${2:-}"; exit $?; fi
# ---
SOURCE1=${1:-"$SRC_PROJECT_DIR/META"}
SOURCE2=${2:-"$SRC_PROJECT_DIR/CONFIGME"}
TARGET=${3:-"$SRC_PROJECT_DIR/bin/meta.ml"}
# ---
# If the file "meta.ml.released" exists, "meta.ml" is just a copy:
RELEASED="$TARGET.released"
if test -f $RELEASED; then
  cp -f $RELEASED $TARGET || exit 4
  exit 0
fi
# else continue:
# ---
# Example of the content of META:
# ---
# name="marionnet"
# description="A virtual network laboratory"
# version="trunk"
# requires="threads str unix lablgtk3 lablglade ocamlbricks"
# ---
# Some defaults:
version="trunk"
prefix="/usr/local"
configurationprefix="/etc"
localeprefix="/usr/local/share/locale"
documentationprefix="/usr/local/share/doc"
# ---
if ! test -f $SOURCE1; then echo 1>&2 "Error: file $SOURCE1 not found => Exiting..."; exit 1; fi
if ! test -f $SOURCE2; then echo 1>&2 "Error: file $SOURCE2 not found => Exiting..."; exit 2; fi
# ---
source $SOURCE1 && source $SOURCE2 || exit 3
# ---
# What META holds is the series; what this file publishes as Meta.version is the version,
# derived by the one function which owns that rule (see its comment above). Version.version
# (bin/version.ml.maker.sh) is the same string, asked of the same place.
version="$(project_version "$SOURCE1")"
# ---
# Provenance from the VCS. Prefer git; keep bzr as a fallback (.bzr and .git
# coexist since the 2026-07 conversion). Under dune's (rule) the CWD is the build
# dir, so we locate the repo root via `git rev-parse` rather than a fixed path.
REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -n "$REPO_DIR" ]] && [[ -d "$REPO_DIR/.git" ]]; then
  revision="$(git -C "$REPO_DIR" rev-list --count HEAD)"
  source_date="$(TZ=UTC git -C "$REPO_DIR" log -1 --format='%cd' --date=iso-local)"
  source_date_utc_yy_mm_dd="$(TZ=UTC git -C "$REPO_DIR" log -1 --format='%cd' --date=format-local:%Y-%m-%d)"
elif [[ -d "$SRC_PROJECT_DIR/.bzr" ]]; then
  revision="$(bzr revno)"
  source_date="$(bzr info --verbose | /bin/grep 'latest revision' | cut -d: -f2- | cut -d' ' -f3-)"
  DATE="$(bzr log -r $revision --timezone utc | awk '/^timestamp/' | cut -f2- -d:)"
  source_date_utc_yy_mm_dd=$(date -d "$DATE" -u '+%Y-%m-%d')
else
  echo 1>&2 "Warning: neither git nor bzr metadata found (revision left empty)";
fi
# ---
cat >$TARGET <<EOF
(* --- *)
(* Automatically generated meta-informations about the project and its building. *)
(* This file is automatically generated; please don't edit it. *)
(* --- *)
let name = "$name";;
let version = "$version";;
let prefix = "$prefix";;
let prefix_install = "$prefix_install";;
let ocaml_version = "$ocaml_version";;
let ocaml_libraryprefix = "$ocaml_libraryprefix";;
let libraryprefix = "$libraryprefix";;
let configurationprefix = "$configurationprefix";;
let localeprefix = "$localeprefix";;
let documentationprefix = "$documentationprefix";;
let uname = "$(uname -srvmo)";;
let build_date = "$(date '+%Y-%m-%d %k:%M:%S %z')";;
let revision = "$revision";;
let source_date = "$source_date";;
let source_date_utc_yy_mm_dd = "$source_date_utc_yy_mm_dd";;
EOF
# ---
echo "Success." 1<&2
