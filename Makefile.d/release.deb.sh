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

# Turn a release into the FOURTH kind of artefact it is made of: Debian packages. The three
# others are already scripted next to this file -- guest images
# (filesystem.prepare-snapshot-to-publish.sh), UML kernels (kernel.prepare-to-publish.sh)
# and the precompiled application (release.binary.sh) -- and this one is a fifth member of
# the same family: it publishes into the SAME release directory, and records what it
# published in the SAME catalogue (release.sha256sums.sh), like the others.
#
# FOUR PACKAGES, decided at episode 13 of the work-stream (§ "La décision : quatre paquets"
# of docs/modernisation-installation-marionnet.md), and their split is not the one of the
# 2009 RPM:
#
#   marionnet              amd64  the binary, the 18 names of bin/scripts/, the twelve
#                                 completion files, share/marionnet/{share,images,scripts,
#                                 locale}, share/doc/marionnet/ (the delivered guides), and
#                                 /etc/marionnet/marionnet.conf as a CONFFILE
#   marionnet-kernels      amd64  the 64-bit UML kernel and its .config
#   marionnet-kernels-i386 amd64  the 32-bit one, for the old kernel/filesystem couples --
#                                 SEPARATE because it is the only one which makes a machine
#                                 enable a foreign architecture (see its Depends below)
#   marionnet-fs-guignol   all    the guignol guest image, machine AND router
#
# and nothing else in apt: the big images (wheezy, trixie) stay release artefacts, fetched
# by bin/scripts/marionnet-install.sh, because apt is not a way to move gibibytes.
#
# NO SOURCE PACKAGE, no dpkg-buildpackage: inclusion in Debian proper is out of the scope of
# this work-stream (§ 6, 2026-07-19), and building from source would want opam and camlp4 in
# a build chroot. These are BINARY packages, assembled from the staging that
# release.binary.sh already produces -- which is why this script calls that one rather than
# describing an installation a second time.
#
# THE FOUR INVARIANTS THIS SCRIPT EXISTS TO KEEP
#
#  1. THE MTIME OF A GUEST IMAGE IS WHAT UML CHECKS against the .conf of its backing file.
#     Both channels must therefore deliver the SAME mtime: the data packages are built by
#     extracting the PUBLISHED tarball (never `tar -m', never a fresh copy), and dpkg keeps
#     the mtimes of data.tar. A package built from the instant of its construction would
#     give a Marionnet which refuses to open a project made with the tarball's image.
#  2. THE DEPENDENCIES ARE DERIVED, NEVER RETYPED. The runtime list has one source of truth
#     since episode 1 -- REQUIRED_PACKAGES_RUNTIME of the Makefile -- and the shared
#     libraries are asked of dpkg-shlibdeps, which also turns the glibc constraint that
#     episode 12 had to write into a FILE NAME into a piece of metadata apt can refuse.
#  3. THE POSTINST NAMES THE SUDOERS RULE, IT DOES NOT GRANT IT. The tarball's install.sh
#     grants it to $SUDO_USER because a human just typed `sudo ./install.sh'; `apt install'
#     has no such answer to "for whom?" -- it may come from an image build or an unattended
#     upgrade. Same reasoning as episode 10 for the apt dependencies.
#  4. A PACKAGE WHICH NEVER REACHES SHA256SUMS IS INVISIBLE. Recorded right after being
#     moved into place, with --force scoped to that single file (episode 9b).
#
# WHERE THIS SCRIPT IS MEANT TO RUN, since episode 20b: NOT on the packager's machine, but in
# the build box, through `Makefile.d/release.build-box.sh --with-deb' (make release-build-box
# WITH_DEB=1). Invariant 2 above says the dependencies are derived; it does not say by whom,
# and dpkg-shlibdeps answers with the conventions of the distribution IT runs in -- the very
# rule episode 19 had to learn on the RPM side. Run here, it wrote libc6 (>= 2.38) for a
# binary needing 2.36, and libgtk-3-0t64 / libglib2.0-0t64, which are the names of the 64-bit
# time_t transition and do not exist on Debian 12 at all. Run on the floor it writes the
# pre-transition names, and those still resolve above it (measured: the t64 packages of trixie
# declare `Provides: libgtk-3-0 (= ...)'). Running it directly still works and is what the
# bench and a quick check do; it just produces a package whose floor is this machine.
#
# THE VERSION OF EACH PACKAGE IS ITS OWN, and does not encode the series (episode 13):
# a kernel is versioned 6.12.95, an image 18474, and only `marionnet' carries the version of
# the application. Publishing under download/marionnet-install.sh/<series>/ is WHERE they
# go, not what they are called -- otherwise opening a 1.1.x series would force rebuilding
# packages whose content did not move.
#
# No bashbricks here, on purpose: like the four scripts it joins, this one sources nothing.
#
# Usage: Makefile.d/release.deb.sh [OPTIONS] [PACKAGE...]
#
#   PACKAGE...                   which of app, kernels, kernels-i386, fs-guignol to build
#                                (default: all four, skipping those whose artefact is not
#                                in the release directory)
#   -o, --output-dir DIR         the release directory to read the artefacts from and to
#                                publish into
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -f, --force                  rebuild a package which is already there
#       --kernel NAME            the kernel to package, without the kernels_ prefix and the
#                                extension (default: the only linux-* of the directory)
#       --no-lintian             do not run lintian on what was built
#       --keep-build             do not remove the build tree afterwards (says where)
#       --print-names            print the four package file names and stop
#       --sign [KEYID]           relayed to Makefile.d/release.apt.sh, which indexes this
#                                directory at the end of the run: it signs Release, so that
#                                a user can write `signed-by=' rather than `[trusted=yes]'
#   -h, --help                   this help
# ---

set -euo pipefail

# What ends up in a package is system data: directories 0755, files 0644. The packager's
# own umask is typically 002 (group-writable), and lintian catches every directory created
# here with it -- a package must not make /usr/share group-writable on the target machine.
umask 022

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# ---
# --- Small talk.
# ---
function info { echo "==> $*"; }
function warn { echo "$0: warning: $*" >&2; }
function die  { echo "$0: $*" >&2; exit 2; }

function usage {
  sed -n '/^# Usage: Makefile.d/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

# ---
# --- The publication series, and the identity of this working copy.
# ---
# Both are asked of the scripts which own them, rather than computed again here: the series
# rule lives in the filesystem script (which prints it on demand) and the identity of a
# build -- version, git revision, architecture, glibc -- is exactly what release.binary.sh
# spells out in the name of its tarball. Parsing that name is how this script stays a
# consumer of that single source of truth instead of a second implementation of it.
# ---
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

BINARY_NAME=""          # marionnet_<version>-r<rev>_<arch>_glibc<x.y>
APP_UPSTREAM=""         # what META says: `trunk' today, `1.0.0' one day
APP_REVISION=""         # the git revision count
APP_ARCH=""             # the Debian architecture name

function read_identity {
  BINARY_NAME=$(bash "$ROOT/Makefile.d/release.binary.sh" --print-name)
  [[ $BINARY_NAME =~ ^marionnet_(.+)-r([0-9]+)_([^_]+)_glibc(.+)$ ]] || \
    die "cannot read the identity of this working copy from '$BINARY_NAME'"
  APP_UPSTREAM="${BASH_REMATCH[1]}"
  APP_REVISION="${BASH_REMATCH[2]}"
  APP_ARCH="${BASH_REMATCH[3]}"
}

# ---
# --- The version of the `marionnet' package.
# ---
# A Debian version MUST start with a digit (measured: dpkg-deb refuses `trunk-r906' with
# "le numéro de version ne commence pas par un chiffre"), and META says `trunk' today. Hence
# the `0~' prefix, which is not decoration: `0~trunk+r913' compares LOWER than `1.0.0'
# (measured with dpkg --compare-versions), so the day META names a real version, apt sees
# every trunk package as an upgradable predecessor -- which is what a pre-release is.
#
# The git revision is appended with `+' rather than `-': `-' opens the Debian revision
# field, and the revision count is upstream's, not the packager's. Two builds of the same
# version are then ordered by the history they were cut at (measured: r906 < r913).
# ---
function app_deb_version {
  if [[ $APP_UPSTREAM =~ ^[0-9] ]]; then
    echo "${APP_UPSTREAM}+r${APP_REVISION}"
  else
    echo "0~${APP_UPSTREAM}+r${APP_REVISION}"
  fi
}

# ---
# --- Command line.
# ---
SERIES=""
OUTDIR=""
FORCE=0
# Relayed verbatim to the indexer, which owns the signature (episode 30): this script has no
# business knowing what a gpg key is, and repeating the option's semantics here would be the
# second source of truth this work-stream keeps removing.
SIGN_ARGS=()
KERNEL_NAME=""
RUN_LINTIAN=1
KEEP_BUILD=0
PRINT_NAMES=0
WANTED=()

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -f|--force)      FORCE=1; shift ;;
    --sign)          if test $# -ge 2 && case "$2" in -*) false ;; *) test -n "$2" ;; esac
                     then SIGN_ARGS=(--sign "$2"); shift 2
                     else SIGN_ARGS=(--sign); shift 1
                     fi ;;
    --kernel)        KERNEL_NAME="$2"; shift 2 ;;
    --no-lintian)    RUN_LINTIAN=0; shift ;;
    --keep-build)    KEEP_BUILD=1; shift ;;
    --print-names)   PRINT_NAMES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    app|kernels|kernels-i386|fs-guignol) WANTED+=("$1"); shift ;;
    *)               die "unknown package '$1': expected app, kernels, kernels-i386 or fs-guignol" ;;
  esac
done

((${#WANTED[@]})) || WANTED=(app kernels kernels-i386 fs-guignol)

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"

for cmd in dpkg-deb dpkg-shlibdeps fakeroot tar sed awk du; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found (packages dpkg-dev, fakeroot)"
done

read_identity

# ---
# --- Which artefacts of the release directory the data packages are made of.
# ---
# Named by the same convention as everywhere else in this chain -- `kernels_<X>.tar.*',
# `filesystems_<X>.tar.*' -- because the name IS the key, here as in the installer. A
# package whose artefact is not there is SKIPPED rather than fatal: a release directory
# holding only kernels is a legitimate intermediate state.
# ---
function artefact_of {  # <prefix> <pattern>: prints the newest matching tarball, or nothing
  local f found=""
  shopt -s nullglob
  # $2 is deliberately UNQUOTED: it carries the glob (machine-guignol-*), and a quoted
  # expansion would make the star a literal character rather than a pattern.
  for f in "$OUTDIR"/"$1"_$2.tar.xz "$OUTDIR"/"$1"_$2.tar.gz; do found="$f"; break; done
  shopt -u nullglob
  echo "$found"
}

# A kernel published both as .tar.xz and as .tar.gz is ONE kernel, not two: the candidates
# are counted by NAME, and the .xz is preferred, as everywhere else in this chain.
function kernel_names {  # <suffix pattern to keep|drop>: prints the distinct kernel names
  local f base name
  shopt -s nullglob
  for f in "$OUTDIR"/kernels_linux-*.tar.xz "$OUTDIR"/kernels_linux-*.tar.gz; do
    base=$(basename -- "$f"); name="${base#kernels_}"; name="${name%.tar.*}"
    case "$1:$name" in
      keep-i386:*-i386) echo "$name" ;;
      drop-i386:*-i386) ;;
      drop-i386:*)      echo "$name" ;;
    esac
  done | sort -u
  shopt -u nullglob
}

function kernel_artefact {  # the 64-bit kernel: linux-* without the -i386 suffix
  if test -n "$KERNEL_NAME"; then artefact_of kernels "$KERNEL_NAME"; return; fi
  local names; mapfile -t names < <(kernel_names drop-i386)
  ((${#names[@]} <= 1)) || die "several 64-bit kernels in $OUTDIR: name the one you want
with --kernel, without the kernels_ prefix and the extension. Found:
$(printf '  %s\n' "${names[@]}")"
  ((${#names[@]})) || return 0
  artefact_of kernels "${names[0]}"
}

function i386_kernel_artefact {
  if test -n "$KERNEL_NAME"; then artefact_of kernels "${KERNEL_NAME}-i386"; return; fi
  local names; mapfile -t names < <(kernel_names keep-i386)
  ((${#names[@]} <= 1)) || die "several 32-bit kernels in $OUTDIR: use --kernel"
  ((${#names[@]})) || return 0
  artefact_of kernels "${names[0]}"
}

# The version of a data package is read from the name of its artefact, and from nowhere
# else: kernels_linux-6.12.95.tar.xz gives 6.12.95, filesystems_machine-guignol-18474.tar.xz
# gives 18474. That is what "the version of a package does not encode the series" means in
# practice -- these versions move when their CONTENT moves, not when a series opens.
function kernel_version_of {  # <basename of a kernels_ artefact>
  local base="${1##*/}"; base="${base#kernels_linux-}"; base="${base%.tar.*}"; base="${base%-i386}"
  echo "$base"
}

function guignol_version_of {  # <basename of a filesystems_machine-guignol- artefact>
  local base="${1##*/}"; base="${base#filesystems_machine-guignol-}"; base="${base%.tar.*}"
  echo "$base"
}

# ---
# --- The names of the four packages.
# ---
APP_DEB=""; KERNELS_DEB=""; KERNELS_I386_DEB=""; FS_GUIGNOL_DEB=""

function compute_package_names {
  local k k32 g
  APP_DEB="marionnet_$(app_deb_version)_${APP_ARCH}.deb"
  k=$(kernel_artefact)
  test -z "$k" || KERNELS_DEB="marionnet-kernels_$(kernel_version_of "$k")_${APP_ARCH}.deb"
  k32=$(i386_kernel_artefact)
  test -z "$k32" || KERNELS_I386_DEB="marionnet-kernels-i386_$(kernel_version_of "$k32")_${APP_ARCH}.deb"
  g=$(artefact_of filesystems "machine-guignol-*")
  test -z "$g" || FS_GUIGNOL_DEB="marionnet-fs-guignol_$(guignol_version_of "$g")_all.deb"
}

test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)
compute_package_names

if ((PRINT_NAMES)); then
  printf '%s\n' "$APP_DEB" ${KERNELS_DEB:+"$KERNELS_DEB"} \
                ${KERNELS_I386_DEB:+"$KERNELS_I386_DEB"} ${FS_GUIGNOL_DEB:+"$FS_GUIGNOL_DEB"}
  exit 0
fi

info "release dir  : $OUTDIR"
info "series       : $SERIES"
info "application  : $BINARY_NAME  ->  $APP_DEB"

# ---
# --- The build tree.
# ---
BUILD=$(mktemp -d -- "${TMPDIR:-/tmp}/marionnet-release-deb.XXXXXXXX")
function cleanup_build { ((KEEP_BUILD)) || rm -rf -- "$BUILD"; }
trap cleanup_build EXIT

MAINTAINER="Jean-Vincent Loddo <loddo@lipn.univ-paris13.fr>"
HOMEPAGE="https://www.marionnet.org"

# ---
# --- The three files every one of the four packages carries.
# ---
# /usr/share/doc/<package>/{copyright,changelog.Debian.gz} are not decoration: they are what
# says, on the target machine, under which licence the thing sitting there may be
# redistributed. The application's own doc directory is /usr/share/doc/marionnet, which is
# ALSO where episode 14 installs the delivered guides -- same package, no collision.
# ---
function write_package_documentation {  # <buildroot> <package>
  local root="$1" pkg="$2" doc="$1/usr/share/doc/$2"
  mkdir -p -- "$doc"
  cat > "$doc/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: marionnet
Source: $HOMEPAGE

Files: *
Copyright: 2007-2026 Jean-Vincent Loddo
           2007-2026 Luca Saiu
License: GPL-2+
 This program is free software: you can redistribute it and/or modify it under
 the terms of the GNU General Public License as published by the Free Software
 Foundation, either version 2 of the License, or (at your option) any later
 version.
 .
 This program is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 .
 On Debian systems, the complete text of the GNU General Public License version 2
 can be found in /usr/share/common-licenses/GPL-2.
EOF
  # changelog.gz, not changelog.Debian.gz: these versions carry no Debian revision, so
  # dpkg calls them NATIVE packages, whose changelog is the upstream one (measured: lintian
  # says wrong-name-for-changelog-of-native-package otherwise).
  cat > "$doc/changelog" <<EOF
$pkg ($3) $SERIES; urgency=medium

  * Built by Makefile.d/release.deb.sh from the artefacts of the release
    directory download/marionnet-install.sh/$SERIES/, git revision $APP_REVISION.
    The packaging is described in docs/modernisation-installation-marionnet.md.

 -- $MAINTAINER  $(date -R)
EOF
  gzip -9n -- "$doc/changelog"
}

# ---
# --- What ldd sees, asked of dpkg-shlibdeps.
# ---
# Used by two of the four packages -- the application, and the 64-bit UML kernel, which is a
# dynamically linked ELF too (measured: `ldd' names libc.so.6, and lintian says
# missing-dependency-on-libc when the Depends: does not). It reads the symbols actually
# used, so the glibc constraint episode 12 could only write into a FILE NAME becomes here a
# piece of metadata apt is able to refuse: libc6 (>= 2.38).
#
# dpkg-shlibdeps wants to be run from a source tree: it gets a minimal debian/control and a
# debian/<package> symlink pointing at the tree being built, so that the file it is asked
# about is, as it expects, inside the package it belongs to.
# ---
function shlibdeps_of {  # <buildroot> <package> <arch> <path relative to the buildroot>
  local root="$1" pkg="$2" arch="$3" rel="$4" work="$BUILD/shlibdeps.$2" out
  mkdir -p -- "$work/debian"
  printf 'Source: marionnet\n\nPackage: %s\nArchitecture: %s\n' "$pkg" "$arch" > "$work/debian/control"
  ln -sfn -- "$root" "$work/debian/$pkg"
  out=$( (cd "$work" && dpkg-shlibdeps -O --ignore-missing-info "debian/$pkg/$rel" 2>/dev/null) | \
         sed -e 's/^shlibs:Depends=//')
  test -n "$out" || die "dpkg-shlibdeps said nothing about $rel of $pkg"
  echo "$out"
}

# ---
# --- Building one package, once its tree and its control file are ready.
# ---
# fakeroot, because what a package holds is root:root system data and this script is not run
# as root -- the same reason the three sibling publishers pass --owner=root --group=root to
# tar. dpkg-deb reads the ownership from the tree it is given, so there is no such option to
# pass to it: the tree has to LOOK owned by root while it is read.
# ---
# Asked BEFORE anything expensive -- before the compilation of the application, before the
# 57 MiB of a guest image are unpacked -- and asked again inside build_package, which any
# future caller might reach by another road. Nothing already present is recomputed, as in
# the four sibling publishers.
function already_published {  # <deb file name>
  test -f "$OUTDIR/$1" && ((! FORCE))
}

function build_package {  # <buildroot> <package> <version> <deb file name>
  local root="$1" pkg="$2" version="$3" deb="$4" size
  size=$(du -sk --apparent-size -- "$root" | awk '{print $1}')
  echo "Installed-Size: $size" >> "$root/DEBIAN/control"
  chmod 755 -- "$root/DEBIAN"
  local script
  for script in postinst prerm postrm preinst; do
    test -f "$root/DEBIAN/$script" && chmod 755 -- "$root/DEBIAN/$script"
  done

  if test -f "$OUTDIR/$deb" && ((! FORCE)); then
    info "already there, skipped: $deb (use --force to redo)"
    return 0
  fi

  info "building $deb ($(du -sh -- "$root" | awk '{print $1}')) ..."
  fakeroot dpkg-deb --build -Zxz -- "$root" "$BUILD/$deb" >/dev/null

  if ((RUN_LINTIAN)) && command -v lintian >/dev/null; then
    # Never fatal: lintian judges a package against the policy of the distribution it runs
    # on, and this is not a package meant for Debian proper (§ 6). Its output is read, not
    # obeyed. Two of its complaints are KEPT ON PURPOSE, and it is worth saying which:
    #   arch-dependent-file-in-usr-share  the UML kernels are executables, and they live in
    #     /usr/share/marionnet/kernels because that is where Marionnet looks for them
    #     (MARIONNET_KERNELS_PATH, and the same path in the tarball channel). Moving them to
    #     /usr/lib to please the policy would make the two channels disagree.
    #   custom-library-search-path / hardening-*  properties of the UML kernels themselves,
    #     which are built by uml/pupisto.*, not by this packaging.
    # And three more, on the application, which are ANSWERS rather than oversights:
    #   executable-in-usr-share-doc  the four example scripts of the delivered documentation
    #     are meant to be RUN by the reader; giving them back their bit is exactly what
    #     episode 14 had to add to all three channels (dune installs data files 0644).
    #   missing-depends-on-sensible-utils  measured: `sensible-editor' is one of five
    #     CANDIDATES in bin/treeview_documents.ml, each tested for existence before use
    #     (xdg-open comes first). lintian only sees the string in the binary. Nothing to add
    #     to REQUIRED_PACKAGES_RUNTIME -- unlike xz-utils and libgtksourceview-3.0-1, which
    #     episode 9b added because they were called with no fallback at all.
    #   unstripped-binary-or-object  measured: stripping saves 9.4 MiB of the 27.6 MiB
    #     binary, and the stripped one still runs. Not done, on purpose: the .deb and the
    #     tarball must ship the SAME binary -- one compilation serves both channels
    #     (episode 13) -- and a channel which strips is a channel whose bug reports carry
    #     different backtraces from the other's.
    lintian --no-tag-display-limit -- "$BUILD/$deb" 2>&1 | sed -e 's/^/    /' || true
  fi

  mv -f -- "$BUILD/$deb" "$OUTDIR/$deb"
  info "published: $OUTDIR/$deb ($(du -h -- "$OUTDIR/$deb" | awk '{print $1}'))"

  # The catalogue of a release directory, exactly as the four sibling publishers do it, and
  # with --force scoped to this single file: we have just written it, so a digest already
  # recorded under that name is by construction the digest of the PREVIOUS package.
  bash "$ROOT/Makefile.d/release.sha256sums.sh" --output-dir "$OUTDIR" --force -- "$deb" || \
    warn "$deb is published but NOT in SHA256SUMS: run Makefile.d/release.sha256sums.sh"
}

# ---
# --- 1. marionnet: the application.
# ---
# Assembled from the staging release.binary.sh produces, and not from a second description
# of what an installation is: that script already knows the two things `dune install' does
# not do (the scripts of bin/scripts/ go to bin/, the example scripts of the delivered
# documentation get their executable bit back).
#
# What does NOT enter the package, of the three files that staging carries at its root:
# install.sh (dpkg is the installer here), README (its INSTALL section describes install.sh)
# and REQUIRED-PACKAGES-RUNTIME (the list becomes Depends: below, which is what a package
# manager can act on).
#
# THE PREFIX IS /usr, and the binary is the SAME as the tarball's -- compiled for
# /usr/local. That is not an oversight: bin/configuration.ml reads a cascade ending at
# /etc/marionnet/marionnet.conf, so the compiled-in prefix is a mere default, and the
# conffile below overrides it. Recompiling with CONFIGME set to /usr would remove the
# conffile at the price of a second compilation and a second artefact to catalogue and to
# test, per release.
# ---
function package_app {
  local root="$BUILD/marionnet" staging="$BUILD/staging"
  local version; version=$(app_deb_version)

  if already_published "$APP_DEB"; then
    info "already there, skipped: $APP_DEB (use --force to redo)"
    return 0
  fi

  info "staging the application (through release.binary.sh) ..."
  bash "$ROOT/Makefile.d/release.binary.sh" --staging-dir "$staging" --no-tarball \
       --output-dir "$OUTDIR" --series "$SERIES" >/dev/null || \
    die "release.binary.sh could not stage this working copy (run it alone to see why)"
  local prefix="$staging/$BINARY_NAME"
  test -d "$prefix/bin" && test -d "$prefix/share" || die "no staging in $prefix"

  mkdir -p -- "$root/usr" "$root/DEBIAN" "$root/etc/marionnet"
  cp -a -- "$prefix/bin" "$prefix/share" "$root/usr/"

  # The conffile. Its content is the one install.sh writes, with the prefix apt installs
  # under. Declared in DEBIAN/conffiles so that dpkg never silently overwrites a machine
  # where it was edited -- including a machine where the TARBALL wrote it first, in which
  # case dpkg sees a locally modified conffile and asks. That is the intended behaviour.
  cat > "$root/etc/marionnet/marionnet.conf" <<'EOF'
# Installed by the marionnet Debian package.
# It is the last but one step of the cascade read by Marionnet at startup (the last one
# being ~/.marionnet/marionnet.conf, where a single user overrides these for themselves).
# Removing this file makes Marionnet fall back to the prefix it was COMPILED with.
MARIONNET_PREFIX=/usr/share/marionnet
MARIONNET_FILESYSTEMS_PATH=${MARIONNET_PREFIX}/filesystems
MARIONNET_KERNELS_PATH=${MARIONNET_PREFIX}/kernels
MARIONNET_LOCALEPREFIX=/usr/share/marionnet/locale
EOF
  echo "/etc/marionnet/marionnet.conf" > "$root/DEBIAN/conffiles"

  # --- Depends: derived twice over, and typed nowhere.
  #
  # (a) what ldd sees -- asked of dpkg-shlibdeps, which reads the symbols the binary
  #     actually uses and turns them into versioned dependencies. This is where the glibc
  #     constraint comes from: episode 12 could only write it in the NAME of a tarball
  #     (_glibc2.39), here it is `libc6 (>= ...)', which apt can refuse with a sentence.
  # (b) what only the Makefile knows -- the twelve commands Marionnet calls by their bare
  #     name (vde_switch, dot, jq, socat, dnsmasq, xterm...), which no linker can see.
  #     REQUIRED_PACKAGES_RUNTIME, read through make, has been their single source of truth
  #     since episode 1; the whole list is passed on, without hand-picking, since a name
  #     already brought in by (a) is a harmless repetition.
  #
  local shlibs
  shlibs=$(shlibdeps_of "$root" marionnet "$APP_ARCH" "usr/bin/marionnet.native")

  local runtime
  runtime=$(make --no-print-directory -C "$ROOT" print-required-packages-runtime 2>/dev/null || echo "")
  test -n "$runtime" || die "could not read REQUIRED_PACKAGES_RUNTIME from the Makefile"

  # The one name the two halves have in common is dropped from (b), not chosen away by
  # hand: libgtksourceview-3.0-1 is in the Makefile's list BECAUSE episode 9b measured that
  # a machine which only runs the binary needs it, and dpkg-shlibdeps finds it too, with a
  # version. Keeping both would put the same package twice in Depends: -- harmless to dpkg,
  # but a control file which says a thing twice is a control file nobody trusts. The test is
  # on the package NAME, so a versioned constraint from (a) still shadows the bare name.
  local pkg keep=()
  for pkg in $runtime; do
    case ", $shlibs," in
      *", $pkg,"*|*", $pkg "*) ;;
      *) keep+=("$pkg") ;;
    esac
  done
  runtime=$(printf '%s, ' "${keep[@]}"); runtime="${runtime%, }"

  cat > "$root/DEBIAN/control" <<EOF
Package: marionnet
Version: $version
Section: net
Priority: optional
Architecture: $APP_ARCH
Maintainer: $MAINTAINER
Homepage: $HOMEPAGE
Depends: $shlibs, $runtime
Suggests: marionnet-kernels, marionnet-fs-guignol, marionnet-kernels-i386
Description: virtual network laboratory
 Marionnet lets a student define, configure and run a complete computer network
 -- machines, routers, switches, hubs, cables, gateways -- on a single host, with
 no physical setup at all. The virtual machines are real Linux systems running as
 User-Mode Linux processes, wired together by vde switches, so what is learned
 here is what happens on real equipment.
 .
 This package holds the application: the GTK interface, the clients of its control
 channel (mrnctl, mrn-check, mrn2sh, mrn-verify), their bash completion, the
 marionnet-get-images command which fetches the larger guest images, and the
 delivered documentation in /usr/share/doc/marionnet.
 .
 The UML kernels and the guest images it boots are in the packages this one
 suggests, and the larger images are downloaded by marionnet-install.sh.
EOF

  # The scoped sudoers rule Marionnet needs to build its ghost taps. NAMED here, not
  # granted: `apt install' does not know which human this machine belongs to (see the
  # header, invariant 3). The rule text itself lives in exactly one place -- the script.
  cat > "$root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
case "$1" in
  configure)
    cat <<'MESSAGE'
==> Marionnet is installed, but it cannot build its network taps yet.

    One scoped sudoers rule is needed, and this package does not grant it: a
    package installation cannot tell WHICH user this machine belongs to. Run,
    as an administrator:

        sudo marionnet-sudoers.sh install <user>

    That grants the socle (block a). The NAT and LAN bridge grants are asked
    for by the user, from the interface, the day a bridge component is started.

    Guest images and UML kernels: apt install marionnet-fs-guignol
    marionnet-kernels for the small ones. The larger images (Debian wheezy,
    Debian trixie) are not in apt -- gibibytes are not what a package manager
    is for -- and this command offers them as a list to tick:

        marionnet-get-images
MESSAGE
    ;;
esac
exit 0
EOF

  cat > "$root/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
case "$1" in
  remove)
    if [ -x /usr/bin/marionnet-sudoers.sh ]; then
      echo "==> If you installed the Marionnet sudoers rule, remove it with:"
      echo "        sudo marionnet-sudoers.sh uninstall"
      echo "    (this package never granted it, so it does not take it away)"
    fi
    ;;
esac
exit 0
EOF

  write_package_documentation "$root" marionnet "$version"
  build_package "$root" marionnet "$version" "$APP_DEB"
}

# ---
# --- 2-4. The data packages.
# ---
# Each is the PUBLISHED tarball, unpacked under /usr/share/marionnet -- which is what its
# paths already say: `kernels_<X>.tar.*' carries kernels/<X>, `filesystems_<X>.tar.*'
# carries filesystems/<X>. Unpacked WITHOUT -m (invariant 1) and with the ownership the
# tarball records (root:root, put there by the publishing scripts), so that dpkg stores
# exactly what the other channel delivers.
# ---
function unpack_artefact_into {  # <tarball> <destination>
  local tarball="$1" dest="$2"
  mkdir -p -- "$dest"
  case "$tarball" in
    *.tar.xz) xz -dc -T0 -- "$tarball" | fakeroot tar -C "$dest" -xf - ;;
    *.tar.gz) fakeroot tar -C "$dest" -xzf "$tarball" ;;
    *)        die "unknown artefact compression: $tarball" ;;
  esac
}

function package_data {  # <package> <version> <deb file> <description file> <depends> <arch> [shlibdeps] <tarball>...
  local pkg="$1" version="$2" deb="$3" descfile="$4" depends="$5" arch="$6"; shift 6
  local with_shlibdeps=0
  if test "${1:-}" = "shlibdeps"; then with_shlibdeps=1; shift; fi
  if already_published "$deb"; then
    info "already there, skipped: $deb (use --force to redo)"
    return 0
  fi
  local root="$BUILD/$pkg" t
  mkdir -p -- "$root/DEBIAN" "$root/usr/share/marionnet"
  for t in "$@"; do
    info "unpacking $(basename -- "$t") ..."
    unpack_artefact_into "$t" "$root/usr/share/marionnet"
  done
  if ((with_shlibdeps)); then
    local elf="" f
    shopt -s nullglob
    for f in "$root"/usr/share/marionnet/kernels/linux-*; do
      case "$f" in *.config) continue ;; esac
      elf="usr/share/marionnet/kernels/${f##*/}"; break
    done
    shopt -u nullglob
    test -n "$elf" || die "$pkg: no kernel image to ask dpkg-shlibdeps about"
    depends="$depends, $(shlibdeps_of "$root" "$pkg" "$arch" "$elf")"
  fi
  {
    cat <<EOF
Package: $pkg
Version: $version
Section: net
Priority: optional
Architecture: $arch
Maintainer: $MAINTAINER
Homepage: $HOMEPAGE
Depends: $depends
EOF
    cat "$descfile"
  } > "$root/DEBIAN/control"
  write_package_documentation "$root" "$pkg" "$version"
  build_package "$root" "$pkg" "$version" "$deb"
}

function package_kernels {
  local t; t=$(kernel_artefact)
  test -n "$t" || { warn "no 64-bit kernel artefact in $OUTDIR: marionnet-kernels skipped"; return 0; }
  cat > "$BUILD/desc.kernels" <<'EOF'
Description: UML kernels for the Marionnet virtual network laboratory
 The 64-bit User-Mode Linux kernel the virtual machines of Marionnet boot, with
 the .config it was built from. It is patched for "ghostification": the ability
 to hide a network interface from the guest, which is what lets a lab show a
 machine with no network at all.
 .
 Installed under /usr/share/marionnet/kernels, where Marionnet looks for it.
EOF
  # The 64-bit UML kernel is itself dynamically linked, so this package owes libc6 what
  # dpkg-shlibdeps says it owes. Its dependency is derived, exactly like the application's;
  # the i386 one below is the single exception of the four, and says why.
  package_data marionnet-kernels "$(kernel_version_of "$t")" "$KERNELS_DEB" \
               "$BUILD/desc.kernels" "marionnet" "$APP_ARCH" shlibdeps "$t"
}

# The one package of the four whose dependency is NOT derived from the Makefile's list, and
# the reason it is a package of its own: the 32-bit kernel is an ELF whose interpreter is
# written INTO the binary as /lib/ld-linux.so.2 (measured). On an amd64 machine, the
# `native' 32-bit runtime package `libc6-i386' provides only /usr/lib32/ld-linux.so.2 --
# it is `libc6:i386', i.e. the FOREIGN architecture, which owns that path, and installing it
# implies `dpkg --add-architecture i386'. Making a machine enable a foreign architecture is
# not something to impose on everyone for a retro-compatibility feature most installations
# will never use, hence the split; the exact form of this dependency is measured on the four
# boxes at the next episode.
function package_kernels_i386 {
  local t; t=$(i386_kernel_artefact)
  test -n "$t" || { warn "no 32-bit kernel artefact in $OUTDIR: marionnet-kernels-i386 skipped"; return 0; }
  cat > "$BUILD/desc.kernels-i386" <<'EOF'
Description: 32-bit UML kernels for the Marionnet virtual network laboratory
 The 32-bit User-Mode Linux kernel (SUBARCH=i386), which is what makes the
 old kernel/filesystem couples of Marionnet -- i386 userlands built years
 ago -- boot again on a modern 64-bit host.
 .
 It depends on libc6:i386, so installing it makes apt enable the i386
 foreign architecture on this machine (dpkg --add-architecture i386). That
 is why it is a package of its own: nothing else in Marionnet asks that of
 a host.
 .
 Installed under /usr/share/marionnet/kernels, where Marionnet looks for it.
EOF
  package_data marionnet-kernels-i386 "$(kernel_version_of "$t")" "$KERNELS_I386_DEB" \
               "$BUILD/desc.kernels-i386" "marionnet, libc6:i386" "$APP_ARCH" "$t"
}

# Machine AND router in ONE package, where the 2009 RPM had two. Measured at episode 13: a
# router artefact weighs 3.8 KiB and holds a SYMBOLIC LINK to the machine image, its .conf
# and an empty variants directory. A separate package would carry a dangling link until its
# neighbour is installed -- a strict Depends: between two packages, one of which is empty,
# is a joint, not a split.
function package_fs_guignol {
  local m r
  m=$(artefact_of filesystems "machine-guignol-*")
  test -n "$m" || { warn "no guignol image in $OUTDIR: marionnet-fs-guignol skipped"; return 0; }
  local version; version=$(guignol_version_of "$m")
  r=$(artefact_of filesystems "router-guignol-$version")
  test -n "$r" || warn "no router-guignol-$version artefact: the package will hold the machine only"
  cat > "$BUILD/desc.fs-guignol" <<'EOF'
Description: guignol guest image for the Marionnet virtual network laboratory
 The small guest filesystem Marionnet boots by default, in its two flavours: the
 machine image and the router image, which is a symbolic link to it plus the
 configuration which turns it into a Quagga router. Together they are what makes
 a freshly installed Marionnet able to run a lab straight away.
 .
 The larger images (Debian wheezy, Debian trixie) weigh gibibytes and are not in
 apt: marionnet-install.sh downloads them from www.marionnet.org.
 .
 Installed under /usr/share/marionnet/filesystems, where Marionnet looks
 for them.
EOF
  package_data marionnet-fs-guignol "$version" "$FS_GUIGNOL_DEB" \
               "$BUILD/desc.fs-guignol" "marionnet" "all" "$m" ${r:+"$r"}
}

# ---
# --- Doing it.
# ---
for what in "${WANTED[@]}"; do
  case "$what" in
    app)          package_app ;;
    kernels)      package_kernels ;;
    kernels-i386) package_kernels_i386 ;;
    fs-guignol)   package_fs_guignol ;;
  esac
done

if ((KEEP_BUILD)); then info "build tree kept: $BUILD"; fi

# The indexes apt reads are rewritten from WHAT IS THERE, once, after the loop -- never per
# package: Packages describes the whole directory, so writing it four times would only make
# the first three wrong for a moment. Called even when every package was already published
# and skipped: the reason a run finds nothing to do is often that a previous one was
# interrupted before this line.
bash "$ROOT/Makefile.d/release.apt.sh" --output-dir "$OUTDIR" --series "$SERIES" \
     ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} || \
  warn "the packages are published but apt cannot read the directory: run Makefile.d/release.apt.sh"

info "done. The packages are in $OUTDIR, in its SHA256SUMS, and in its Packages/Release."
