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

# Turn a release into the FIFTH kind of artefact it is made of: RPM packages. It joins the
# four publishers already sitting next to it -- guest images
# (filesystem.prepare-snapshot-to-publish.sh), UML kernels (kernel.prepare-to-publish.sh),
# the precompiled application (release.binary.sh) and the Debian packages (release.deb.sh) --
# and it behaves like them: it publishes into the SAME release directory and records what it
# published in the SAME catalogue (release.sha256sums.sh).
#
# THREE MARIONNET PACKAGES, not the four of the Debian channel, and not the four of the 2009
# RPM either:
#
#   marionnet            x86_64  the binary, the 26 names of bin/, the twelve completion
#                                files, share/marionnet/{share,images,scripts,locale,gui},
#                                share/doc/marionnet/ (the delivered guides) and
#                                /etc/marionnet/marionnet.conf as a %config(noreplace)
#   marionnet-kernels    x86_64  BOTH UML kernels, 64-bit and 32-bit, and their .config
#   marionnet-fs-guignol noarch  the guignol guest image, machine AND router
#
# WHY THE i386 KERNEL IS NOT A PACKAGE OF ITS OWN HERE, when it is one in the Debian channel:
# the Debian split existed for exactly one reason -- its dependency is `libc6:i386', i.e. a
# FOREIGN ARCHITECTURE, and installing it makes the machine run `dpkg --add-architecture
# i386'. Measured on Rocky 9: the very same file, /lib/ld-linux.so.2, is owned there by
# `glibc.i686', an ordinary package of `baseos', because multilib is native to RPM. The
# reason for the split does not exist on this side, so the split does not either; and the
# dependency stays DERIVED rather than retyped, since rpm's own generator reads both ELF
# classes out of the package and asks for both libc.so.6 flavours by itself.
#
# TWO THIRD-PARTY PACKAGES, built on demand (`vde2', `uml-utilities'), because measurement
# said they had to exist: Marionnet calls vde_switch, wirefilter and slirpvde (19 call sites
# in bin/) and uml_mconsole (bin/simulation_level.ml, bin/serial.ml and two scripts), and
# NO RPM DISTRIBUTION CARRIES THEM. Measured 2026-08-31: `vde2' is absent from Rocky 9 +
# EPEL9 + CRB + epel-next, and from Fedora 42 and 44; `uml_mconsole' is provided by nobody on
# Fedora 42 nor on openSUSE Leap 15.6. This is not a retirement, it is a NON-ENTRY: Fedora's
# dist-git holds zero `rpms/vde*' project and the Red Hat Bugzilla no review request -- the
# only trace is a package submission posted to rhl-devel-list in June 2007 which never
# landed. Debian, meanwhile, keeps both alive (the VSquare Team, ~10 patches on an upstream
# frozen since 2011), and openSUSE ships vde2 in its official OSS repository. So the RPM
# channel has to carry what the Debian channel gets for free. Both are built from the DEBIAN
# SOURCE PACKAGE -- upstream tarball plus the patch series -- because those patches are the
# fifteen years of fixes that keep a 2011 codebase compiling with gcc 15.
#
# BUILT IN A CONTAINER, AND THAT IS A TECHNICAL CHOICE, NOT A CONVENIENCE. On RPM, the
# automatic dependency generator IS the derivation of "what ldd sees" -- it is what
# dpkg-shlibdeps is to the Debian channel, and it is what turns the glibc constraint episode
# 12 could only write into a FILE NAME into metadata dnf can refuse. Running it under Ubuntu
# would make our dependency metadata an artefact of the packaging host rather than of the
# target distribution. So rpmbuild runs inside a real RPM distribution, and nothing is
# installed on the machine which invokes this script.
#
# THE INVARIANTS THIS SCRIPT EXISTS TO KEEP -- the same four as the Debian channel, plus one
#
#  1. THE MTIME OF A GUEST IMAGE IS WHAT UML CHECKS against the .conf of its backing file.
#     The data packages are built by unpacking the PUBLISHED tarball (never `tar -m'), so
#     that both channels deliver the same mtime.
#  2. THE DEPENDENCIES ARE DERIVED, NEVER RETYPED. What the linker sees is left to rpm's
#     generator; what only the Makefile knows -- the commands called by their bare name --
#     comes from REQUIRED_PACKAGES_RUNTIME, read through make, and is translated by ONE
#     table (rpm_requires_of_debian_package below) which is the only place in this repository
#     where a Debian package name faces its RPM counterpart.
#  3. THE %post NAMES THE SUDOERS RULE, IT DOES NOT GRANT IT. `dnf install' has no answer to
#     "for whom?", exactly as `apt install' has none.
#  4. A PACKAGE WHICH NEVER REACHES SHA256SUMS IS INVISIBLE. Recorded right after being moved
#     into place, with --force scoped to that single file.
#  5. DEPENDENCIES ARE WRITTEN BY FILE AND BY SONAME, NEVER BY PACKAGE NAME. Measured on both
#     families: `/usr/bin/jq' and the soname libgtksourceview-3.0.so.1()(64bit) resolve on
#     Fedora 42 AND on openSUSE Leap 15.6, whereas the package names do not (gtksourceview3
#     against libgtksourceview-3_0-1). This is what makes ONE spec serve two families. The
#     two measured exceptions are commented at the table.
#
# Usage: Makefile.d/release.rpm.sh [OPTIONS] [PACKAGE...]
#
#   PACKAGE...                   which of app, kernels, fs-guignol, vde2, uml-utilities to
#                                build (default: the three Marionnet ones, skipping those
#                                whose artefact is not in the release directory; the two
#                                third-party ones are built only when asked for)
#   -o, --output-dir DIR         the release directory to read the artefacts from and to
#                                publish into
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -f, --force                  rebuild a package which is already there
#       --kernel NAME            the kernel to package, without the kernels_ prefix and the
#                                extension (default: the only linux-* of the directory)
#       --build-image IMAGE      the distribution rpmbuild runs in (default: fedora:42)
#       --no-rpmlint             do not run rpmlint on what was built
#       --keep-build             do not remove the build tree afterwards (says where)
#       --print-names            print the package file names and stop
#   -h, --help                   this help
# ---

set -euo pipefail

# What ends up in a package is system data: directories 0755, files 0644. The packager's own
# umask is typically 002, and a package must not make /usr/share group-writable on the target
# machine (the lesson episode 15a paid on the Debian side).
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
# Both are asked of the scripts which own them, exactly as release.deb.sh does: the series
# rule lives in the filesystem script, and the identity of a build -- version, git revision,
# architecture -- is what release.binary.sh spells out in the name of its tarball.
# ---
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

BINARY_NAME=""          # marionnet_<version>-r<rev>_<arch>_glibc<x.y>
APP_UPSTREAM=""         # what META says: `trunk' today, `1.0.0' one day
APP_REVISION=""         # the git revision count
APP_ARCH=""             # the DEBIAN architecture name, as release.binary.sh writes it

function read_identity {
  BINARY_NAME=$(bash "$ROOT/Makefile.d/release.binary.sh" --print-name)
  [[ $BINARY_NAME =~ ^marionnet_(.+)-r([0-9]+)_([^_]+)_glibc(.+)$ ]] || \
    die "cannot read the identity of this working copy from '$BINARY_NAME'"
  APP_UPSTREAM="${BASH_REMATCH[1]}"
  APP_REVISION="${BASH_REMATCH[2]}"
  APP_ARCH="${BASH_REMATCH[3]}"
}

# The one name which differs between the two channels. release.binary.sh writes the Debian
# architecture into the name of its tarball because that channel was written first; rpm calls
# the same machine x86_64.
function rpm_arch_of {  # <debian architecture>
  case "$1" in
    amd64) echo x86_64 ;;
    i386)  echo i686 ;;
    arm64) echo aarch64 ;;
    *)     die "no RPM architecture known for the Debian architecture '$1'" ;;
  esac
}

# ---
# --- The version of the `marionnet' package.
# ---
# The same reasoning as the Debian channel, and it happens to hold word for word here: rpm
# compares `~' as LOWER than everything, including the empty string, so `0~trunk+r915' sorts
# below `1.0.0'. The day META names a real version, every trunk package is seen as an
# upgradable predecessor -- which is what a pre-release is. The `+' before the revision is
# kept as it is on the other side, and rpm accepts it in a version.
#
# Where the two channels genuinely differ: rpm splits what dpkg keeps in one string, into
# Version and Release. Release is 1 and stays 1: it numbers the PACKAGING of one upstream
# version, and here the packaging never moves without the content moving with it.
# ---
function app_rpm_version {
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
KERNEL_NAME=""
BUILD_IMAGE="fedora:42"
RUN_RPMLINT=1
KEEP_BUILD=0
PRINT_NAMES=0
WANTED=()

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -f|--force)      FORCE=1; shift ;;
    --kernel)        KERNEL_NAME="$2"; shift 2 ;;
    --build-image)   BUILD_IMAGE="$2"; shift 2 ;;
    --no-rpmlint)    RUN_RPMLINT=0; shift ;;
    --keep-build)    KEEP_BUILD=1; shift ;;
    --print-names)   PRINT_NAMES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    app|kernels|fs-guignol|vde2|uml-utilities) WANTED+=("$1"); shift ;;
    *)               die "unknown package '$1': expected app, kernels, fs-guignol, vde2 or uml-utilities" ;;
  esac
done

# The two third-party packages are NOT in the default set. They change once every few years
# (their upstreams are frozen since 2011 and 2007), they take minutes to compile, and a
# release directory which already holds them needs nothing done. `make release-rpm-deps'.
((${#WANTED[@]})) || WANTED=(app kernels fs-guignol)

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"

for cmd in docker tar sed awk du; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found"
done

read_identity
RPM_ARCH=$(rpm_arch_of "$APP_ARCH")

# ---
# --- Which artefacts of the release directory the data packages are made of.
# ---
# Named by the same convention as everywhere else in this chain -- `kernels_<X>.tar.*',
# `filesystems_<X>.tar.*' -- because the name IS the key, here as in the installer. A package
# whose artefact is not there is SKIPPED rather than fatal.
# ---
function artefact_of {  # <prefix> <pattern>: prints the newest matching tarball, or nothing
  local f found=""
  shopt -s nullglob
  # $2 is deliberately UNQUOTED: it carries the glob (machine-guignol-*).
  for f in "$OUTDIR"/"$1"_$2.tar.xz "$OUTDIR"/"$1"_$2.tar.gz; do found="$f"; break; done
  shopt -u nullglob
  echo "$found"
}

function kernel_names {  # <keep-i386|drop-i386>: prints the distinct kernel names
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

# The version of a data package is read from the name of its artefact and from nowhere else:
# a kernel is versioned 6.12.95 and an image 18474, so these versions move when their CONTENT
# moves, not when a series opens.
function kernel_version_of {  # <basename of a kernels_ artefact>
  local base="${1##*/}"; base="${base#kernels_linux-}"; base="${base%.tar.*}"; base="${base%-i386}"
  echo "$base"
}

function guignol_version_of {  # <basename of a filesystems_machine-guignol- artefact>
  local base="${1##*/}"; base="${base#filesystems_machine-guignol-}"; base="${base%.tar.*}"
  echo "$base"
}

# ---
# --- The names of the packages.
# ---
# An RPM file is named <name>-<version>-<release>.<arch>.rpm, where the Debian one is
# <name>_<version>_<arch>.deb. Knowing the names before building anything is what lets
# --print-names exist and what lets a package already published be skipped without cost.
# ---
APP_RPM=""; KERNELS_RPM=""; FS_GUIGNOL_RPM=""

function compute_package_names {
  local k k32 g kver
  APP_RPM="marionnet-$(app_rpm_version)-1.${RPM_ARCH}.rpm"
  k=$(kernel_artefact); k32=$(i386_kernel_artefact)
  if test -n "$k"; then kver=$(kernel_version_of "$k")
  elif test -n "$k32"; then kver=$(kernel_version_of "$k32")
  else kver=""; fi
  test -z "$kver" || KERNELS_RPM="marionnet-kernels-${kver}-1.${RPM_ARCH}.rpm"
  g=$(artefact_of filesystems "machine-guignol-*")
  test -z "$g" || FS_GUIGNOL_RPM="marionnet-fs-guignol-$(guignol_version_of "$g")-1.noarch.rpm"
}

test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)
compute_package_names

if ((PRINT_NAMES)); then
  printf '%s\n' "$APP_RPM" ${KERNELS_RPM:+"$KERNELS_RPM"} ${FS_GUIGNOL_RPM:+"$FS_GUIGNOL_RPM"}
  exit 0
fi

info "release dir  : $OUTDIR"
info "series       : $SERIES"
info "build box    : $BUILD_IMAGE"
info "application  : $BINARY_NAME  ->  $APP_RPM"

# ---
# --- The build tree.
# ---
BUILD=$(mktemp -d -- "${TMPDIR:-/tmp}/marionnet-release-rpm.XXXXXXXX")
function cleanup_build { ((KEEP_BUILD)) || rm -rf -- "$BUILD"; }
trap cleanup_build EXIT

PACKAGER="Jean-Vincent Loddo <loddo@lipn.univ-paris13.fr>"
HOMEPAGE="https://www.marionnet.org"

# ---
# --- The box rpmbuild runs in.
# ---
# Built once and kept: the tag is derived from the image name, so asking for another
# distribution with --build-image gives it its own builder rather than silently reusing the
# previous one. The compilers are here for the two third-party packages; the Marionnet
# packages need nothing but rpm-build, since what they hold is already compiled.
# ---
BUILDER_IMAGE=""

function ensure_builder_image {
  local tag; tag=$(echo "$BUILD_IMAGE" | tr ':/' '--')
  BUILDER_IMAGE="mrn-rpm-builder-$tag"
  if docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then return 0; fi
  info "building the rpmbuild box $BUILDER_IMAGE (once) ..."
  local ctx="$BUILD/builder"; mkdir -p -- "$ctx"
  cat > "$ctx/Dockerfile" <<EOF
FROM $BUILD_IMAGE
RUN dnf -y install rpm-build rpmlint dnf-plugins-core findutils tar xz gzip diffutils which \\
    && dnf clean all
EOF
  docker build -q -t "$BUILDER_IMAGE" -- "$ctx" >/dev/null || \
    die "could not build the rpmbuild box from $BUILD_IMAGE"
}

# rpmbuild is handed a _topdir it owns entirely, so that everything it writes lands in the
# bind-mounted work directory and nothing needs to exist in the caller's HOME.
#
# It runs as ROOT in the box, which is what lets %install chown the tree to root:root so that
# the package records the ownership system data must have -- the counterpart of the fakeroot
# the Debian channel needs. The price is paid on the way out: everything rpmbuild wrote is
# then owned by root in a directory belonging to the caller, who could not so much as move the
# package away (measured). Hence the chown back to the invoking user, inside the same run, and
# AFTER rpmbuild's own status has been captured -- a failed build must still leave a readable
# log behind.
#
# RPMBUILD_BUILDDEP asks dnf to install the spec's own BuildRequires before building. It is
# set for the two third-party packages and only for them: a BuildRequires: nobody acts upon is
# decoration, and the alternative -- listing their build dependencies in the builder image --
# would put that list in a second place, free to drift from the spec which declares it.
# (Measured: the image carried compilers but not readline-devel, and uml_mconsole -- the one
# binary Marionnet actually calls -- was exactly what failed to compile.) The Marionnet
# packages do not need it: what they hold is already compiled.
RPMBUILD_BUILDDEP=0

function rpmbuild_in_container {  # <work dir> <spec basename> [extra docker args...]
  local work="$1" spec="$2"; shift 2
  docker run --rm -v "$work:/work" -w /work "$@" "$BUILDER_IMAGE" bash -c '
    rc=0
    if test "$5" = 1; then dnf -y builddep "SPECS/$2" >/dev/null || rc=$?; fi
    if test $rc = 0; then
      rpmbuild --define "_topdir /work" --define "packager $1" \
               --define "_build_id_links none" -bb "SPECS/$2"
      rc=$?
    fi
    chown -R "$3:$4" /work
    exit $rc
  ' -- "$PACKAGER" "$spec" "$(id -u)" "$(id -g)" "$RPMBUILD_BUILDDEP"
}

# ---
# --- Publishing one package, once rpmbuild has written it.
# ---
function already_published {  # <rpm file name>
  test -f "$OUTDIR/$1" && ((! FORCE))
}

function publish_rpm {  # <path to the built rpm>
  local built="$1" rpm; rpm=$(basename -- "$built")

  if ((RUN_RPMLINT)); then
    # Never fatal, exactly as lintian is on the Debian side: rpmlint judges a package against
    # the policy of a distribution this one is not trying to enter. Its output is read, not
    # obeyed. The complaints kept ON PURPOSE are the same three as the Debian channel's:
    #   unstripped-binary-or-object   the two channels must ship the SAME binary (episode 13),
    #     and a channel which strips is a channel whose bug reports carry other backtraces.
    #   arch-dependent-file-in-usr-share  the UML kernels live where Marionnet looks for them
    #     (MARIONNET_KERNELS_PATH), and moving them would make the channels disagree.
    #   script-in-usr-share-doc  the example scripts of the delivered documentation are meant
    #     to be RUN by the reader; giving them back their bit is what episode 14 had to add.
    docker run --rm -v "$(dirname -- "$built"):/out" "$BUILDER_IMAGE" \
      rpmlint "/out/$rpm" 2>&1 | sed -e 's/^/    /' || true
  fi

  mv -f -- "$built" "$OUTDIR/$rpm"
  info "published: $OUTDIR/$rpm ($(du -h -- "$OUTDIR/$rpm" | awk '{print $1}'))"

  # With --force scoped to this single file: we have just written it, so a digest already
  # recorded under that name is by construction the digest of the PREVIOUS package. This is
  # the lesson episode 9b paid -- republishing under the same name left the catalogue lying,
  # and an installer then removes what it has just downloaded.
  bash "$ROOT/Makefile.d/release.sha256sums.sh" --output-dir "$OUTDIR" --force -- "$rpm" || \
    warn "$rpm is published but NOT in SHA256SUMS: run Makefile.d/release.sha256sums.sh"
}

# rpmbuild writes into RPMS/<arch>/; which arch it chose is its business, so the file is
# looked for rather than assumed.
function built_rpm_in {  # <work dir>
  local f
  shopt -s nullglob
  for f in "$1"/RPMS/*/*.rpm; do echo "$f"; return 0; done
  shopt -u nullglob
  return 1
}

# ---
# --- What only the Makefile knows: the commands Marionnet calls by their bare name.
# ---
# REQUIRED_PACKAGES_RUNTIME has been the single source of truth for the runtime dependencies
# since episode 1, and it is written in DEBIAN package names. This table is the translation,
# and it is deliberately the only place in the repository where the two vocabularies meet.
#
# Everything that can be said BY FILE is said by file (invariant 5): a file dependency is
# resolved identically by dnf and by zypper (measured on Fedora 42 and openSUSE Leap 15.6),
# whereas a package name is right on one family and wrong on the other. Two entries could not
# be written that way, and both are measured:
#
#   iproute2  -> (iproute or iproute2), a BOOLEAN dependency, because `ip' has no portable
#     path: Fedora 42 has completed the usrmerge (/usr/sbin -> bin, so `ip' is /usr/bin/ip)
#     while openSUSE keeps /usr/sbin/ip. A file dependency would be right on exactly one of
#     the two. The package name is the same word on Fedora (iproute) and on openSUSE
#     (iproute2), so naming both is enough, and rpm >= 4.13 understands the parenthesis.
#   xz-utils  -> xz, by NAME, because the file dependency has a WRONG ANSWER available: on
#     openSUSE, /usr/bin/xz is also provided by `busybox-xz', whose xz does not implement the
#     -T of `xz -dc -T0' that bin/scripts/marionnet-install.sh uses to unpack an image (the
#     factor 4 measured at episode 6). The package is called `xz' on both families.
#
# No bashbricks here, on purpose: like the five scripts it joins, this one sources nothing.
#
# libgtksourceview-3.0-1 has NO entry: it is a shared library, so rpm's own generator asks
# for its soname, which resolves on both families (measured: gtksourceview3 on Fedora,
# libgtksourceview-3_0-1 on openSUSE). Deriving beats translating whenever it is possible.
# ---
function rpm_requires_of_debian_package {  # <debian package name>: prints one Requires: value
  case "$1" in
    vde2)                   echo "/usr/bin/vde_switch" ;;
    uml-utilities)          echo "/usr/bin/uml_mconsole" ;;
    graphviz)               echo "/usr/bin/dot" ;;
    xterm)                  echo "/usr/bin/xterm" ;;
    iproute2)               echo "(iproute or iproute2)" ;;
    sudo)                   echo "/usr/bin/sudo" ;;
    x11-xserver-utils)      echo "/usr/bin/xrandr" ;;
    xauth)                  echo "/usr/bin/xauth" ;;
    jq)                     echo "/usr/bin/jq" ;;
    socat)                  echo "/usr/bin/socat" ;;
    dnsmasq-base)           echo "/usr/sbin/dnsmasq" ;;
    xz-utils)               echo "xz" ;;
    libgtksourceview-3.0-1) ;;   # derived from the soname, see above
    *)                      warn "no RPM equivalent known for the runtime package '$1': ignored" ;;
  esac
}

function runtime_requires {  # prints the Requires: lines of the application
  local runtime pkg req
  runtime=$(make --no-print-directory -C "$ROOT" print-required-packages-runtime 2>/dev/null || echo "")
  test -n "$runtime" || die "could not read REQUIRED_PACKAGES_RUNTIME from the Makefile"
  for pkg in $runtime; do
    req=$(rpm_requires_of_debian_package "$pkg")
    test -z "$req" || echo "Requires:       $req"
  done
}

# ---
# --- 1. marionnet: the application.
# ---
# Assembled from the staging release.binary.sh produces, and not from a second description of
# what an installation is: that script already knows the two things `dune install' does not do
# (the scripts of bin/scripts/ go to bin/, the example scripts of the delivered documentation
# get their executable bit back).
#
# What does NOT enter the package, of the four things that staging carries at its root:
# install.sh (dnf is the installer here), README (its INSTALL section describes install.sh),
# REQUIRED-PACKAGES-RUNTIME (the list becomes Requires: above) and lib/marionnet (the
# dune-package metadata of a library nobody links against from outside).
#
# THE PREFIX IS /usr and the binary is the SAME as the tarball's -- compiled for /usr/local.
# bin/configuration.ml reads a cascade ending at /etc/marionnet/marionnet.conf, so the
# compiled-in prefix is a mere default and the %config below overrides it. Recompiling for
# /usr would cost a second compilation and a second artefact to catalogue, per release.
# ---
function package_app {
  local work="$BUILD/work.app" tree staging="$BUILD/staging"
  local version; version=$(app_rpm_version)

  if already_published "$APP_RPM"; then
    info "already there, skipped: $APP_RPM (use --force to redo)"
    return 0
  fi

  info "staging the application (through release.binary.sh) ..."
  bash "$ROOT/Makefile.d/release.binary.sh" --staging-dir "$staging" --no-tarball \
       --output-dir "$OUTDIR" --series "$SERIES" >/dev/null || \
    die "release.binary.sh could not stage this working copy (run it alone to see why)"
  local prefix="$staging/$BINARY_NAME"
  test -d "$prefix/bin" && test -d "$prefix/share" || die "no staging in $prefix"

  tree="$work/SOURCES/tree"
  mkdir -p -- "$tree/usr" "$tree/etc/marionnet" "$work/SPECS"
  cp -a -- "$prefix/bin" "$prefix/share" "$tree/usr/"

  # The conffile, with the prefix dnf installs under. %config(noreplace) is the rpm spelling
  # of what DEBIAN/conffiles says on the other side: a machine where this file was edited --
  # including one where the TARBALL wrote it first -- keeps its version, and the package's
  # lands beside it as .rpmnew. That asymmetry with dpkg is worth knowing: dpkg ASKS, rpm
  # keeps and tells. Neither ever silently overwrites.
  cat > "$tree/etc/marionnet/marionnet.conf" <<'EOF'
# Installed by the marionnet RPM package.
# It is the last but one step of the cascade read by Marionnet at startup (the last one
# being ~/.marionnet/marionnet.conf, where a single user overrides these for themselves).
# Removing this file makes Marionnet fall back to the prefix it was COMPILED with.
MARIONNET_PREFIX=/usr/share/marionnet
MARIONNET_FILESYSTEMS_PATH=${MARIONNET_PREFIX}/filesystems
MARIONNET_KERNELS_PATH=${MARIONNET_PREFIX}/kernels
MARIONNET_LOCALEPREFIX=/usr/share/marionnet/locale
EOF

  # The here-document below is UNQUOTED on purpose: it interpolates the version, the derived
  # Requires: and the date. One consequence, and it is a trap this script fell into once
  # (measured): NO BACKQUOTE may appear in the spec text. The `word' quoting style used in the
  # comments of this file would open a command substitution there and swallow everything up to
  # the next backquote -- the shell only says "unexpected EOF" and the spec silently loses a
  # paragraph. Double quotes inside the spec, always.
  {
    cat <<EOF
# Generated by Makefile.d/release.rpm.sh -- do not edit, and do not keep a copy: the spec of
# a package is a description of what the release directory holds, so it is written where that
# is known, and nowhere else.

# No debuginfo subpackage, and no post-install processing at all: the second line is what
# keeps rpm from STRIPPING the binary, and shipping the same binary as the tarball channel is
# a decision of episode 13, not an oversight. (The 2009 spec of RPMS/ had both lines too, for
# the same reason applied to bytecode.)
%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           marionnet
Version:        $version
Release:        1
Summary:        Virtual network laboratory
License:        GPL-2.0-or-later
URL:            $HOMEPAGE
BuildArch:      $RPM_ARCH
$(runtime_requires)
Recommends:     marionnet-kernels
Recommends:     marionnet-fs-guignol

%description
Marionnet lets a student define, configure and run a complete computer network
-- machines, routers, switches, hubs, cables, gateways -- on a single host, with
no physical setup at all. The virtual machines are real Linux systems running as
User-Mode Linux processes, wired together by vde switches, so what is learned
here is what happens on real equipment.

This package holds the application: the GTK interface, the clients of its control
channel (mrnctl, mrn-check, mrn2sh, mrn-verify), their bash completion, the
marionnet-get-images command which fetches the larger guest images, and the
delivered documentation in /usr/share/doc/marionnet.

The UML kernels and the guest images it boots are in the packages this one
recommends, and the larger images are downloaded by marionnet-get-images.

%install
cp -a %{_sourcedir}/tree/. %{buildroot}/
# What a package holds is root:root system data. rpmbuild runs as root in the box, but the
# tree it copies from is bind-mounted from the packager's working copy and carries their uid.
chown -R root:root %{buildroot}

%files
%config(noreplace) /etc/marionnet/marionnet.conf
%dir /etc/marionnet
/usr/bin/*
/usr/share/marionnet
/usr/share/bash-completion/completions/*
# Listed as ordinary files rather than with %%doc -- which changes NOTHING, and that is the
# point worth writing down here. Measured on the built package: rpm flags every file under
# %%{_docdir} as documentation BY ITSELF (26 of the 31 paths below), so "tsflags=nodocs" --
# which every RPM container image sets, in /etc/dnf/dnf.conf -- throws the guides away
# whatever this spec says about %%doc. It is the exact counterpart of the "path-exclude"
# episode 15b measured on debian:*-slim and ubuntu:*, it has the same cause (an image is not
# a machine) and the same answer: not a packaging trick, but the business of the Docker
# channel to come. On an ordinary machine the 26 guides install and find each other by the
# relative paths episode 14 gave them.
/usr/share/doc/marionnet

%post
if [ "\$1" = 1 ]; then
cat <<'MESSAGE'
==> Marionnet is installed, but it cannot build its network taps yet.

    One scoped sudoers rule is needed, and this package does not grant it: a
    package installation cannot tell WHICH user this machine belongs to. Run,
    as an administrator:

        sudo marionnet-sudoers.sh install <user>

    That grants the socle (block a). The NAT and LAN bridge grants are asked
    for by the user, from the interface, the day a bridge component is started.

    Guest images and UML kernels: dnf install marionnet-fs-guignol
    marionnet-kernels for the small ones. The larger images (Debian wheezy,
    Debian trixie) are not in the repository -- gibibytes are not what a package
    manager is for -- and this command offers them as a list to tick:

        marionnet-get-images
MESSAGE
fi
exit 0

%preun
if [ "\$1" = 0 ] && [ -x /usr/bin/marionnet-sudoers.sh ]; then
  echo "==> If you installed the Marionnet sudoers rule, remove it with:"
  echo "        sudo marionnet-sudoers.sh uninstall"
  echo "    (this package never granted it, so it does not take it away)"
fi
exit 0

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') $PACKAGER - $version-1
- Built by Makefile.d/release.rpm.sh from the artefacts of the release directory
  download/marionnet-install.sh/$SERIES/, git revision $APP_REVISION.
EOF
  } > "$work/SPECS/marionnet.spec"

  ensure_builder_image
  info "building $APP_RPM ..."
  rpmbuild_in_container "$work" marionnet.spec >/dev/null || die "rpmbuild failed for marionnet"
  local built; built=$(built_rpm_in "$work") || die "rpmbuild wrote no package for marionnet"
  publish_rpm "$built"
}

# ---
# --- 2-3. The data packages.
# ---
# Each is the PUBLISHED tarball, unpacked under /usr/share/marionnet -- which is what its
# paths already say: `kernels_<X>.tar.*' carries kernels/<X>, `filesystems_<X>.tar.*' carries
# filesystems/<X>. Unpacked WITHOUT -m (invariant 1), so that rpm stores the mtime the other
# channel delivers.
# ---
function unpack_artefact_into {  # <tarball> <destination>
  local tarball="$1" dest="$2"
  mkdir -p -- "$dest"
  case "$tarball" in
    *.tar.xz) xz -dc -T0 -- "$tarball" | tar -C "$dest" -xf - ;;
    *.tar.gz) tar -C "$dest" -xzf "$tarball" ;;
    *)        die "unknown artefact compression: $tarball" ;;
  esac
}

function package_data {  # <package> <version> <rpm file> <arch> <summary> <description file> <tarball>...
  local pkg="$1" version="$2" rpm="$3" arch="$4" summary="$5" descfile="$6"; shift 6
  if already_published "$rpm"; then
    info "already there, skipped: $rpm (use --force to redo)"
    return 0
  fi
  local work="$BUILD/work.$pkg" tree t
  tree="$work/SOURCES/tree"
  mkdir -p -- "$tree/usr/share/marionnet" "$work/SPECS"
  for t in "$@"; do
    info "unpacking $(basename -- "$t") ..."
    unpack_artefact_into "$t" "$tree/usr/share/marionnet"
  done
  {
    cat <<EOF
# Generated by Makefile.d/release.rpm.sh -- do not edit.
%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           $pkg
Version:        $version
Release:        1
Summary:        $summary
License:        GPL-2.0-or-later
URL:            $HOMEPAGE
BuildArch:      $arch
Requires:       marionnet

%description
EOF
    cat "$descfile"
    cat <<EOF

%install
cp -a %{_sourcedir}/tree/. %{buildroot}/
chown -R root:root %{buildroot}

%files
%dir /usr/share/marionnet
/usr/share/marionnet/*

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') $PACKAGER - $version-1
- Unpacked by Makefile.d/release.rpm.sh from the artefacts published in
  download/marionnet-install.sh/$SERIES/, mtimes preserved.
EOF
  } > "$work/SPECS/$pkg.spec"

  ensure_builder_image
  info "building $rpm ..."
  rpmbuild_in_container "$work" "$pkg.spec" >/dev/null || die "rpmbuild failed for $pkg"
  local built; built=$(built_rpm_in "$work") || die "rpmbuild wrote no package for $pkg"
  publish_rpm "$built"
}

# BOTH kernels in one package, where the Debian channel has two -- see the header. The
# package is x86_64 rather than noarch although one of the two files is a 32-bit ELF: a
# package is not noarch merely because it holds no code of the host's architecture, and
# rpm's generator reads both ELF classes here, asking for libc.so.6 in its 64-bit and its
# 32-bit flavour. That second one is what pulls glibc.i686, and it is DERIVED, which is
# exactly what the Debian side had to write by hand as `libc6:i386'.
function package_kernels {
  local k k32 version; k=$(kernel_artefact); k32=$(i386_kernel_artefact)
  test -n "$k$k32" || { warn "no kernel artefact in $OUTDIR: marionnet-kernels skipped"; return 0; }
  if test -n "$k"; then version=$(kernel_version_of "$k"); else version=$(kernel_version_of "$k32"); fi
  cat > "$BUILD/desc.kernels" <<'EOF'
The User-Mode Linux kernels the virtual machines of Marionnet boot, with the
.config files they were built from: the 64-bit one, and the 32-bit one
(SUBARCH=i386) which is what makes the old kernel/filesystem couples of
Marionnet -- i386 userlands built years ago -- boot again on a modern host.

They are patched for "ghostification": the ability to hide a network interface
from the guest, which is what lets a lab show a machine with no network at all.

Installed under /usr/share/marionnet/kernels, where Marionnet looks for them.
EOF
  package_data marionnet-kernels "$version" "$KERNELS_RPM" "$RPM_ARCH" \
               "UML kernels for the Marionnet virtual network laboratory" \
               "$BUILD/desc.kernels" ${k:+"$k"} ${k32:+"$k32"}
}

# Machine AND router in ONE package, where the 2009 RPM of RPMS/ had two. Measured at
# episode 13: a router artefact weighs 3.8 KiB and holds a SYMBOLIC LINK to the machine
# image, its .conf and an empty variants directory. A separate package would carry a dangling
# link until its neighbour is installed -- a strict Requires: between two packages, one of
# which is empty, is a joint, not a split. The 2009 changelog says as much itself:
# "2009-11-08: rename router -> routers, added symlinks".
function package_fs_guignol {
  local m r version
  m=$(artefact_of filesystems "machine-guignol-*")
  test -n "$m" || { warn "no guignol image in $OUTDIR: marionnet-fs-guignol skipped"; return 0; }
  version=$(guignol_version_of "$m")
  r=$(artefact_of filesystems "router-guignol-$version")
  test -n "$r" || warn "no router-guignol-$version artefact: the package will hold the machine only"
  cat > "$BUILD/desc.fs-guignol" <<'EOF'
The small guest filesystem Marionnet boots by default, in its two flavours: the
machine image and the router image, which is a symbolic link to it plus the
configuration which turns it into a Quagga router. Together they are what makes
a freshly installed Marionnet able to run a lab straight away.

The larger images (Debian wheezy, Debian trixie) weigh gibibytes and are not in
the repository: marionnet-get-images downloads them from www.marionnet.org.

Installed under /usr/share/marionnet/filesystems, where Marionnet looks for them.
EOF
  package_data marionnet-fs-guignol "$version" "$FS_GUIGNOL_RPM" noarch \
               "Guignol guest image for the Marionnet virtual network laboratory" \
               "$BUILD/desc.fs-guignol" "$m" ${r:+"$r"}
}

# ---
# --- 4-5. The two runtime dependencies no RPM distribution carries.
# ---
# Built from the DEBIAN SOURCE PACKAGE -- upstream tarball plus the patch series -- and not
# from upstream alone: those patches are what fifteen years of Debian maintenance put between
# a 2011 (vde2) or 2007 (uml-utilities) codebase and a compiler of 2026. Measured on Rocky 9:
# the ten patches of vde2 apply without a single failure, and the build then produces
# vde_switch, wirefilter and slirpvde.
#
# ONE MEASURED TRAP, and it is why -j1 is written below rather than %{?_smp_mflags}: vde2
# builds fine with `make -j1' and FAILS with `make -j4' (a race in its 2011 autotools
# makefiles). A parallel build here would be an intermittent failure in the release chain,
# which is the worst kind.
#
# The packages are named after what they provide -- `vde2', `uml-utilities' -- rather than
# `marionnet-vde2': the Requires: of the application are written BY FILE (invariant 5), so on
# a machine where the distribution already provides /usr/bin/vde_switch (openSUSE does, in
# its official OSS repository) ours is simply never pulled. Naming them apart would have
# forced a choice between the two providers where none is needed.
# ---
function package_thirdparty {  # <vde2|uml-utilities>
  # Two statements rather than one: in a single `local', every word is expanded BEFORE the
  # assignments take effect, so a work= referring to $pkg would read the caller's scope --
  # where there is no pkg at all, which is exactly what set -u caught here.
  local pkg="$1"
  local work="$BUILD/work.$pkg" orig debian version summary desc files build_recipe install_recipe buildreq

  case "$pkg" in
    vde2)
      version="2.3.2+r586"
      orig="vde2_2.3.2+r586.orig.tar.gz"
      debian="vde2_2.3.2+r586-12.2.debian.tar.xz"
      summary="Virtual Distributed Ethernet"
      # Measured by building it: besides the commands and the four shared libraries, vde2
      # installs its management scripts under /etc/vde2 and a helper under /usr/libexec. An
      # unlisted file is a FATAL error for rpmbuild, which is the opposite of dpkg-deb's
      # silence and, here, an improvement: a package cannot forget half of itself.
      files='%{_bindir}/*
%{_libdir}/*
%{_libexecdir}/*
%{_mandir}/*/*
%config(noreplace) %{_sysconfdir}/vde2'
      buildreq='gcc, gcc-c++, make, automake, autoconf, libtool, patch, openssl-devel, libpcap-devel'
      build_recipe='autoreconf -fi
%configure
# -j1 ON PURPOSE: measured, this tree builds with -j1 and FAILS with -j4 (a race in its
# 2011 autotools makefiles). A parallel build here would be an intermittent failure in the
# release chain, which is the worst kind.
make -j1'
      install_recipe='%make_install
# Neither upstream is a library anyone links against from outside Marionnet, so there is no
# -devel package to put these in: the headers go, and with them the .la files, which name
# build-time paths that do not exist on the target machine.
rm -rf %{buildroot}%{_includedir}
rm -f %{buildroot}%{_libdir}/*.la %{buildroot}%{_libdir}/*.a'
      desc="VDE is a virtual network switch: vde_switch, the switch itself, wirefilter,
which puts delay, loss and bandwidth limits on a wire, and slirpvde, which
gives a virtual network a way out to the real one. Marionnet is built on
them -- every switch, hub and cable of a virtual laboratory is a vde object.

Built from the Debian source package, whose patch series is what keeps an
upstream frozen since 2011 compiling with a compiler of today. No RPM
distribution carries vde2: measured on Rocky 9 (with EPEL, CRB and epel-next)
and on Fedora 42 and 44."
      ;;
    uml-utilities)
      version="20070815.4"
      orig="uml-utilities_20070815.4.orig.tar.gz"
      debian="uml-utilities_20070815.4-2.1.debian.tar.xz"
      summary="User-Mode Linux utilities"
      # No autotools at all here: a hand-written Makefile of 2007 whose top rule walks its
      # subdirectories, with BIN_DIR and LIB_DIR exported rather than a prefix. `make install'
      # builds what it installs, so the two recipes below are what Debian's own rules do.
      # /usr/lib/uml and /usr/sbin are written literally, not as %%{_libdir} and %%{_sbindir}:
      # the 2007 Makefile hardcodes LIB_DIR=/usr/lib/uml (never lib64), and jail_uml lands in
      # /usr/sbin whatever the usrmerge state of the build box.
      files='%{_bindir}/*
/usr/sbin/*
/usr/lib/uml'
      # readline-devel is what uml_mconsole -- the one binary Marionnet actually calls -- needs,
      # and fuse-devel is FUSE *2*, for uml_mount. The whole set is built rather than the two
      # tools Marionnet uses: a package which carries a distribution's name and half of its
      # commands is a trap for whoever installs it by that name. Measured on Fedora 42: the
      # deprecated fuse-devel 2.9.9 is still there, so being faithful costs nothing today.
      buildreq='gcc, make, patch, readline-devel, fuse-devel'
      build_recipe='make -j1'
      install_recipe='make install DESTDIR=%{buildroot}'
      desc="The tools which talk to a running User-Mode Linux instance, chiefly
uml_mconsole, through which Marionnet asks a virtual machine to halt, reboot
or report -- see bin/simulation_level.ml and bin/serial.ml -- and uml_moo,
which merges a COW file back into its backing image.

Built from the Debian source package. No RPM distribution provides
uml_mconsole: measured on Fedora 42 and on openSUSE Leap 15.6."
      ;;
    *) die "unknown third-party package '$pkg'" ;;
  esac

  local rpm="$pkg-$version-1.${RPM_ARCH}.rpm"
  if already_published "$rpm"; then
    info "already there, skipped: $rpm (use --force to redo)"
    return 0
  fi

  mkdir -p -- "$work/SOURCES" "$work/SPECS"
  local pool="http://deb.debian.org/debian/pool/main/${pkg:0:1}/$pkg"
  local f
  for f in "$orig" "$debian"; do
    info "fetching $f ..."
    curl -sSL --fail -o "$work/SOURCES/$f" "$pool/$f" || \
      die "cannot fetch $pool/$f (no network, or Debian moved this version: see --help)"
  done

  # %prep unpacks upstream, then the Debian directory beside it, then applies the series in
  # order. `patch -p1' rather than %patch: the series is Debian's own file and its entries are
  # -p1 by construction, so replaying it as it stands is what keeps this spec from becoming a
  # second, hand-maintained copy of a list Debian already keeps.
  cat > "$work/SPECS/$pkg.spec" <<EOF
# Generated by Makefile.d/release.rpm.sh -- do not edit.
%global debug_package %{nil}

Name:           $pkg
Version:        $version
Release:        1
Summary:        $summary
License:        GPL-2.0-or-later
URL:            https://tracker.debian.org/pkg/$pkg
Source0:        $orig
Source1:        $debian
BuildRequires:  $buildreq

%description
$desc

%prep
# Unpacked by hand rather than with %%setup, and with --strip-components=1: the Debian orig
# tarball of these two does NOT unfold into a directory named after the Debian version
# (vde2_2.3.2+r586.orig.tar.gz gives vde2-2.3.2), so every %%setup form would either look for
# the wrong directory or leave the sources one level too deep -- measured, the patches then
# find no file to patch and %%prep dies asking a question no batch build can answer.
rm -rf %{_builddir}/%{name}-build
mkdir -p %{_builddir}/%{name}-build
cd %{_builddir}/%{name}-build
tar xzf %{SOURCE0} --strip-components=1
tar xJf %{SOURCE1}
# The series is Debian's own file and its entries are -p1 by construction, so replaying it as
# it stands is what keeps this spec from becoming a second, hand-maintained copy of a list
# Debian already keeps up to date.
for p in \$(grep -v '^#' debian/patches/series); do
  patch -p1 -s --no-backup-if-mismatch < "debian/patches/\$p"
done

%build
cd %{_builddir}/%{name}-build
$build_recipe

%install
cd %{_builddir}/%{name}-build
$install_recipe

%files
$files

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') $PACKAGER - $version-1
- Built by Makefile.d/release.rpm.sh from the Debian source package, patch series
  included, for the RPM distributions which do not carry this software.
EOF

  ensure_builder_image
  RPMBUILD_BUILDDEP=1
  info "building $rpm (this compiles from source, -j1) ..."
  rpmbuild_in_container "$work" "$pkg.spec" >"$work/build.log" 2>&1 || {
    tail -25 "$work/build.log" >&2
    die "rpmbuild failed for $pkg (full log: $work/build.log; --keep-build keeps it)"
  }
  local built; built=$(built_rpm_in "$work") || die "rpmbuild wrote no package for $pkg"
  publish_rpm "$built"
}

# ---
# --- Doing it.
# ---
for what in "${WANTED[@]}"; do
  case "$what" in
    app)              package_app ;;
    kernels)          package_kernels ;;
    fs-guignol)       package_fs_guignol ;;
    vde2|uml-utilities) package_thirdparty "$what" ;;
  esac
done

if ((KEEP_BUILD)); then info "build tree kept: $BUILD"; fi

info "done. The packages are in $OUTDIR and in its SHA256SUMS."
