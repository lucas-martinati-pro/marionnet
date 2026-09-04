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
# FOUR MARIONNET PACKAGES -- the same split as the Debian channel, and not the four of the
# 2009 RPM:
#
#   marionnet              x86_64  the binary, the 26 names of bin/, the twelve completion
#                                  files, share/marionnet/{share,images,scripts,locale,gui},
#                                  share/doc/marionnet/ (the delivered guides) and
#                                  /etc/marionnet/marionnet.conf as a %config(noreplace)
#   marionnet-kernels      x86_64  the 64-bit UML kernel and its .config
#   marionnet-kernels-i386 x86_64  the 32-bit one, for the old kernel/filesystem couples
#   marionnet-fs-guignol   noarch  the guignol guest image, machine AND router
#
# THE i386 KERNEL IS A PACKAGE OF ITS OWN, and the reason is NOT the Debian one. Episode 17
# merged the two, having measured on Rocky 9 that /lib/ld-linux.so.2 is owned there by
# `glibc.i686', an ordinary package of `baseos': multilib being native to RPM, the Debian
# motive for splitting -- not making a machine enable a FOREIGN ARCHITECTURE -- did not apply.
#
# That was measured on the wrong box, and episode 19 corrected it: RHEL 10 (hence Rocky 10 and
# AlmaLinux 10, the CURRENT enterprise distributions) has dropped 32-bit multilib entirely --
# NOTHING provides /lib/ld-linux.so.2 there, not even with CRB. A merged package is therefore
# refused whole on the very distributions most users are on, and the 64-bit kernel goes down
# with the 32-bit one it was bundled with. Hence the split, for a motive of this world rather
# than a translation of Debian's: a package which cannot be installed at all must not take a
# usable one with it. Inside each package the dependency stays DERIVED -- rpm reads the ELF
# class and asks for the right libc.so.6 flavour by itself.
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
# AND THAT CONTAINER IS THE OLDEST BOX WE SERVE, not the newest -- Rocky 10 rather than
# Fedora 42. The generator does not merely read ELFs: it also applies the CONVENTIONS of the
# distribution it runs on, and those travel into the package. Measured (episode 19): built on
# Fedora 42, uml-utilities came out requiring `filesystem(unmerged-sbin-symlinks)', which no
# EL box provides, so the package was uninstallable on RHEL 9 and 10 alike. The cause is
# /usr/lib/rpm/filesystem.req, which fires on the BASENAME of a file (a hardcoded list of
# names historically found in /usr/sbin -- uml_net and friends), whatever directory it is
# installed into, and which does nothing at all when the build box is not usrmerged. Moving
# the file was therefore no fix; changing the box was. A second gain comes for free: built on
# a glibc 2.39 box, these packages ask for 2.39 rather than Fedora's 2.41, which is exactly
# the floor the application itself has.
#
# THIS SCRIPT COMPILES NOTHING (episode 20c). The application package is assembled by
# unpacking the PUBLISHED `marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz' of the release
# directory -- exactly as the data packages are made of the published kernels and images.
# Until episode 20c it called release.binary.sh to stage a fresh compilation of the working
# copy, and that was the last place where the floor of a channel was an accident of the
# packager's machine: a dynamically linked binary demands a glibc at least as recent as the one
# it was linked against, and the demand travels FORWARD only. Building rpmbuild's box on the
# oldest distribution we serve (above) fixed the metadata; it could not fix the bytes, because
# the bytes were not made there. They are made in release.build-box.sh's box -- the floor,
# debian:12 -- and this script now packages exactly those bytes.
#
# THE CONSEQUENCE IS A CONTRACT, AND IT IS THE POINT: there is nothing left to compile here, so
# the .rpm and the .tar.xz carry the SAME binary to the byte, and packaging a locally compiled
# one is no longer expressible. The price is that `make release-rpm' now requires a published
# application tarball and says so, where it used to make one silently.
#
# WHICH TARBALL, when a release directory legitimately holds several revisions: the greatest
# `r<rev>'. If two architectures share that revision the script refuses rather than guesses,
# and --app-artefact names the one wanted -- the same shape as --kernel.
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
#   PACKAGE...                   which of app, kernels, kernels-i386, fs-guignol, vde2,
#                                uml-utilities to build (default: the four Marionnet ones,
#                                skipping those whose artefact is not in the release
#                                directory; the two third-party ones are built only when
#                                asked for)
#   -o, --output-dir DIR         the release directory to read the artefacts from and to
#                                publish into
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -f, --force                  rebuild a package which is already there
#       --kernel NAME            the kernel to package, without the kernels_ prefix and the
#                                extension (default: the only linux-* of the directory)
#       --sign [KEYID]           sign every package published by this run, with rpmsign, HERE
#                                and not in the build box (the private key never enters a
#                                container). Given no KEYID, the key is the one the SOURCES
#                                publish -- the fingerprint read from
#                                marionnet-archive-keyring.asc at the root of the tree.
#       --app-artefact NAME      the published application tarball to package, as a file name
#                                of the release directory (default: the greatest revision)
#       --build-image IMAGE      the distribution rpmbuild runs in
#                                (default: rockylinux/rockylinux:10, see the header)
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
# --- The publication series, and the identity of what is being packaged.
# ---
# The series is asked of the script which owns the rule (the filesystem publisher), exactly as
# release.deb.sh does.
#
# The identity -- version, git revision, architecture -- is READ IN THE NAME OF THE PUBLISHED
# TARBALL, and no longer asked of this working copy through `release.binary.sh --print-name'.
# That indirection was right as long as this script compiled: the thing packaged was the thing
# this machine could build. Since episode 20c the thing packaged is a file of the release
# directory, so the file must be the one which says what it is -- the same rule that names the
# kernel and the guest image packages, and the same rule marionnet-install.sh applies to
# choose between artefacts. Asking the host instead would let a host at glibc 2.39 name a
# package whose binary was built against 2.36.
# ---
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

SIGN_KEY=""             # `@published' until resolved against the keyring below
KEYRING_ASC="$ROOT/marionnet-archive-keyring.asc"   # the archive's identity, versioned in git
APP_ARTEFACT=""         # full path of the published tarball the application package is made of
BINARY_NAME=""          # marionnet_<version>-r<rev>_<arch>_glibc<x.y>
APP_UPSTREAM=""         # the version, derived from META's series: `1.0.368' since episode 33
APP_REVISION=""         # the git revision count
APP_ARCH=""             # the DEBIAN architecture name, as release.binary.sh writes it

# A release directory legitimately holds several revisions, so the greatest `r<rev>' wins
# rather than the first name a glob happens to return. Two architectures at that revision is
# not a choice this script may make on its own.
function app_artefact {
  local f base rev best_rev=-1 candidates=() base_rev
  shopt -s nullglob
  for f in "$OUTDIR"/marionnet_*.tar.xz "$OUTDIR"/marionnet_*.tar.gz; do
    base=$(basename -- "$f")
    [[ $base =~ ^marionnet_.+-r([0-9]+)_[^_]+_glibc[^_]+\.tar\.(xz|gz)$ ]] || continue
    rev="${BASH_REMATCH[1]}"
    if ((rev > best_rev)); then best_rev=$rev; candidates=("$f"); elif ((rev == best_rev)); then
      candidates+=("$f")
    fi
  done
  shopt -u nullglob
  ((${#candidates[@]})) || return 0
  ((${#candidates[@]} == 1)) || die "several application tarballs at revision r$best_rev in $OUTDIR:
name the one you want with --app-artefact. Found:
$(printf '  %s\n' "${candidates[@]##*/}")"
  echo "${candidates[0]}"
}

function read_identity {
  if test -n "$APP_ARTEFACT_GIVEN"; then
    APP_ARTEFACT="$OUTDIR/$(basename -- "$APP_ARTEFACT_GIVEN")"
    test -f "$APP_ARTEFACT" || die "no such artefact in $OUTDIR: ${APP_ARTEFACT_GIVEN##*/}"
  else
    APP_ARTEFACT=$(app_artefact)
  fi
  test -n "$APP_ARTEFACT" || die "no published application tarball in $OUTDIR.
This script packages what was compiled on the floor, it does not compile (episode 20c):
run \`make release-build-box' first, or point --output-dir at a release directory."
  BINARY_NAME=$(basename -- "$APP_ARTEFACT"); BINARY_NAME="${BINARY_NAME%.tar.*}"
  [[ $BINARY_NAME =~ ^marionnet_(.+)-r([0-9]+)_([^_]+)_glibc(.+)$ ]] || \
    die "cannot read the identity of the application from '$BINARY_NAME'"
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
# below `1.0.0'. Since episode 33 META names a series and the version is derived from it, so
# the branch taken is the first one; the second is what makes the transition harmless, every
# package published before it being seen as an upgradable predecessor (measured with
# rpmdev-vercmp in fedora:42: 0~trunk+r941-1 < 1.0.368+r943-1). The `+' before the revision is
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
APP_ARTEFACT_GIVEN=""
BUILD_IMAGE="rockylinux/rockylinux:10"
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
    --sign)          if test $# -ge 2 && case "$2" in -*) false ;; *) test -n "$2" ;; esac
                     then SIGN_KEY="$2"; shift 2
                     else SIGN_KEY="@published"; shift 1
                     fi ;;
    --app-artefact)  APP_ARTEFACT_GIVEN="$2"; shift 2 ;;
    --build-image)   BUILD_IMAGE="$2"; shift 2 ;;
    --no-rpmlint)    RUN_RPMLINT=0; shift ;;
    --keep-build)    KEEP_BUILD=1; shift ;;
    --print-names)   PRINT_NAMES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    app|kernels|kernels-i386|fs-guignol|vde2|uml-utilities) WANTED+=("$1"); shift ;;
    *)               die "unknown package '$1': expected app, kernels, kernels-i386, fs-guignol, vde2 or uml-utilities" ;;
  esac
done

# The two third-party packages are NOT in the default set. They change once every few years
# (their upstreams are frozen since 2011 and 2007), they take minutes to compile, and a
# release directory which already holds them needs nothing done. `make release-rpm-deps'.
((${#WANTED[@]})) || WANTED=(app kernels kernels-i386 fs-guignol)

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"

for cmd in docker tar xz sed awk du; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found"
done

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
APP_RPM=""; KERNELS_RPM=""; KERNELS_I386_RPM=""; FS_GUIGNOL_RPM=""

function compute_package_names {
  local k k32 g
  APP_RPM="marionnet-$(app_rpm_version)-1.${RPM_ARCH}.rpm"
  k=$(kernel_artefact)
  test -z "$k" || KERNELS_RPM="marionnet-kernels-$(kernel_version_of "$k")-1.${RPM_ARCH}.rpm"
  k32=$(i386_kernel_artefact)
  test -z "$k32" || KERNELS_I386_RPM="marionnet-kernels-i386-$(kernel_version_of "$k32")-1.${RPM_ARCH}.rpm"
  g=$(artefact_of filesystems "machine-guignol-*")
  test -z "$g" || FS_GUIGNOL_RPM="marionnet-fs-guignol-$(guignol_version_of "$g")-1.noarch.rpm"
}

test -d "$OUTDIR" || die "no such release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

# Identity comes from the release directory, so it is read once the directory is known -- and
# not, as before episode 20c, from this working copy.
read_identity
RPM_ARCH=$(rpm_arch_of "$APP_ARCH")
compute_package_names

if ((PRINT_NAMES)); then
  printf '%s\n' "$APP_RPM" ${KERNELS_RPM:+"$KERNELS_RPM"} \
                ${KERNELS_I386_RPM:+"$KERNELS_I386_RPM"} ${FS_GUIGNOL_RPM:+"$FS_GUIGNOL_RPM"}
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
  # EPEL and CRB are enabled when they exist and ignored when they do not, so that the same
  # recipe serves an EL box and a Fedora one: on Rocky 10, libpcap-devel and fuse-devel live in
  # CRB and rpmlint in EPEL, while Fedora has neither repository and needs neither.
  cat > "$ctx/Dockerfile" <<EOF
FROM $BUILD_IMAGE
RUN dnf -y install dnf-plugins-core || true
RUN dnf -y install epel-release || true
RUN dnf config-manager --set-enabled crb || dnf config-manager --enable crb || true
RUN dnf -y install rpm-build findutils tar xz gzip diffutils which \\
    && (dnf -y install rpmlint || true) \\
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
# ---
# --- The signing key (episode 30b), resolved ONCE and before anything is built: a run which
# --- cannot sign must say so before spending ten minutes in a container.
# ---
# rpmsign RUNS HERE, on the release machine, and not in the box which builds the packages --
# the private key must never enter a container (rule of episode 30). That is legitimate where
# rpmbuild's own metadata is not: a signature is a cryptographic fact, not a convention of the
# distribution it is produced on. The claim is nevertheless MEASURED by the bench, which
# installs what this signs on four RPM distributions.
#
# The fingerprint is read from the key the SOURCES publish, exactly as release.apt.sh does --
# the two scripts read the same file, which is what makes the archive's identity single.
if test -n "$SIGN_KEY"; then
  command -v rpmsign >/dev/null \
    || die "\`rpmsign' not found: install it with \`make apt-release-dependencies' (package \`rpm')"
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
  if test -f "$KEYRING_ASC"; then
    published=$(gpg --with-colons --show-keys -- "$KEYRING_ASC" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')
    signing=$(gpg --with-colons --list-secret-keys -- "$SIGN_KEY" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')
    test "$published" = "$signing" \
      || die "the signing key ($signing) is not the one the sources publish ($published)"
  fi
  info "packages will be signed with $SIGN_KEY"
fi

function sign_rpm {  # <path to an rpm>
  test -n "$SIGN_KEY" || return 0
  # --addsign rather than --resign: both replace the signature, but --addsign is the spelling
  # every rpm since 4.14 accepts. The digest algorithms are left at rpm's defaults; naming them
  # here would freeze, in this script, a choice the target distributions get to make.
  rpmsign --define "_gpg_name $SIGN_KEY" --addsign "$1" >/dev/null \
    || die "rpmsign failed on $1"
  # AND THEN THE PACKAGE IS READ BACK, because a zero exit status is not a signature. rpmsign
  # does return 1 on a key it cannot find (measured), but this whole work-stream is a list of
  # tools which succeeded without doing the work -- so the fact is taken from the file itself.
  #
  # The tag is RSAHEADER, not SIGPGP: a modern rpm puts the header signature there, and SIGPGP
  # reads back EMPTY on a properly signed package (measured, and it fooled me first). The
  # short key id rpm prints is the last 16 hex digits of the fingerprint.
  local shown; shown=$(rpm -qp --qf '%{RSAHEADER:pgpsig}' -- "$1" 2>/dev/null)
  local want; want="${SIGN_KEY: -16}"; want="${want,,}"   # the last 16 hex digits, no more
  case "${shown,,}" in
    *"$want"*) : ;;
    *) die "$1 came back unsigned, or signed by another key: [${shown:-none}]" ;;
  esac
}

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
  # SIGNED BEFORE BEING CATALOGUED, and that order is not a detail: signing rewrites the file,
  # so a digest taken before it would describe a package nobody will ever download.
  sign_rpm "$OUTDIR/$rpm"
  info "published: $OUTDIR/$rpm ($(du -h -- "$OUTDIR/$rpm" | awk '{print $1}'))${SIGN_KEY:+, signed}"

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
    # `xhost' and NOT `xrandr': the Makefile's own comment says this package is here for
    # xhost (granting the X server access to the guests). Mapping it to xrandr was a guess,
    # and it was measured wrong -- Rocky 10 has no xrandr at all, even with EPEL and CRB,
    # while xhost is a package of its own there. Read what the source of truth SAYS.
    x11-xserver-utils)      echo "/usr/bin/xhost" ;;
    xauth)                  echo "/usr/bin/xauth" ;;
    jq)                     echo "/usr/bin/jq" ;;
    socat)                  echo "/usr/bin/socat" ;;
    dnsmasq-base)           echo "/usr/sbin/dnsmasq" ;;
    xz-utils)               echo "xz" ;;
    libgtksourceview-3.0-1) ;;   # derived from the soname, see above
    *)                      warn "no RPM equivalent known for the runtime package '$1': ignored" ;;
  esac
}

# ---
# --- The kernels and the guest image: Suggests: here, where the Debian channel Recommends: the kernel
# ---
# Recommends: was tried first and measured, which is how the choice stopped being a matter of
# taste: dnf honoured the weak dependency on marionnet-fs-guignol (noarch) and SILENTLY SKIPPED
# the one on marionnet-kernels -- which installs perfectly well when asked for by name, pulling
# glibc.i686 with it. A weak dependency whose effect depends on whether the package happens to
# need multilib is not a promise this channel can make, and half of it arriving is worse than
# none: the user gets an image and no kernel, and nothing says why. Hence Suggests:, and a %post
# which names what is still missing.
#
# The .deb channel DOES Recommends: marionnet-kernels, and the difference is deliberate (see the
# control file in release.deb.sh): apt has no such trap -- it installs the weak dependency or
# says why it cannot. What the two channels owe each other is the same PROMISE, not the same
# keyword: after one command, a machine that can boot, and a message naming what is left. Where
# a package manager cannot keep that promise silently, the message keeps it.
function suggests_lines {
  echo "Suggests:       marionnet-kernels"
  echo "Suggests:       marionnet-fs-guignol"
  echo "Suggests:       marionnet-kernels-i386"
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
# Assembled by unpacking the PUBLISHED tarball, and not from a second description of what an
# installation is: release.binary.sh already put in it the two things `dune install' does not
# do (the scripts of bin/scripts/ go to bin/, the example scripts of the delivered
# documentation get their executable bit back), and since episode 20c it did so IN THE BUILD
# BOX. Unpacked without `-m', like the data packages and for the same reason (invariant 1).
#
# What does NOT enter the package, of the four things that tarball carries at its root:
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

  info "unpacking $(basename -- "$APP_ARTEFACT") ..."
  unpack_artefact_into "$APP_ARTEFACT" "$staging"
  local prefix="$staging/$BINARY_NAME"
  test -d "$prefix/bin" && test -d "$prefix/share" || \
    die "the artefact does not unpack into a directory called '$BINARY_NAME': $APP_ARTEFACT"

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
$(suggests_lines)

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
suggests -- install marionnet-kernels first, since nothing boots without it -- and
the larger images are downloaded by marionnet-get-images.

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
# What is left to do on the machine, MEASURED rather than recited -- and with no
# "\$1 = 1" guard around it, which is the point. Counting installations cannot answer
# the question being asked (is the socle granted here, are the images there?): on the
# first install only, this text was withheld from a machine which had never been
# granted anything and was merely upgrading, and it could never report a socle written
# by an older version of marionnet-sudoers.sh. The text itself lives once, in the
# script, shared with the .deb channel. Never fatal: a %post runs in image builds too.
[ -x /usr/bin/marionnet-setup-check.sh ] && /usr/bin/marionnet-setup-check.sh --package-manager dnf || true
# What the machine must provide besides the packages (episode 40). Never fatal:
# this runs in image builds too, where the device is legitimately absent -- it is
# the container that RUNS Marionnet which needs it, and the script says so.
[ -x /usr/bin/marionnet-tun-check.sh ] && /usr/bin/marionnet-tun-check.sh || true
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

# The 64-bit kernel. Its dependency is derived like every other: rpm reads the ELF and asks
# for libc.so.6()(64bit), which every distribution provides.
function package_kernels {
  local t; t=$(kernel_artefact)
  test -n "$t" || { warn "no 64-bit kernel artefact in $OUTDIR: marionnet-kernels skipped"; return 0; }
  cat > "$BUILD/desc.kernels" <<'EOF'
The 64-bit User-Mode Linux kernel the virtual machines of Marionnet boot, with
the .config it was built from. It is patched for "ghostification": the ability
to hide a network interface from the guest, which is what lets a lab show a
machine with no network at all.

Installed under /usr/share/marionnet/kernels, where Marionnet looks for it.
EOF
  package_data marionnet-kernels "$(kernel_version_of "$t")" "$KERNELS_RPM" "$RPM_ARCH" \
               "UML kernels for the Marionnet virtual network laboratory" \
               "$BUILD/desc.kernels" "$t"
}

# The 32-bit kernel, and the one package of the four whose installability depends on the
# distribution rather than on us. Its ELF names /lib/ld-linux.so.2 as its interpreter, so rpm
# derives a 32-bit libc.so.6 requirement -- satisfied by glibc.i686 on Fedora and on RHEL 9,
# and satisfiable NOWHERE on RHEL 10, which dropped 32-bit multilib (measured: nothing
# provides that path, CRB included).
#
# That is precisely why it is separate, and why episode 19 undid the merge of episode 17: on
# a current enterprise box this package is refused, and it must be able to be refused ALONE.
# Bundled with the 64-bit kernel, it made a package that works everywhere unavailable exactly
# where most users are.
function package_kernels_i386 {
  local t; t=$(i386_kernel_artefact)
  test -n "$t" || { warn "no 32-bit kernel artefact in $OUTDIR: marionnet-kernels-i386 skipped"; return 0; }
  cat > "$BUILD/desc.kernels-i386" <<'EOF'
The 32-bit User-Mode Linux kernel (SUBARCH=i386), which is what makes the old
kernel/filesystem couples of Marionnet -- i386 userlands built years ago --
boot again on a modern 64-bit host.

It needs a 32-bit C library (glibc.i686). Distributions which have dropped
32-bit multilib altogether, RHEL 10 and its rebuilds among them, cannot install
it; that is why it is a package of its own, so that its refusal costs nothing to
the rest of Marionnet.

Installed under /usr/share/marionnet/kernels, where Marionnet looks for it.
EOF
  package_data marionnet-kernels-i386 "$(kernel_version_of "$t")" "$KERNELS_I386_RPM" "$RPM_ARCH" \
               "32-bit UML kernel for the Marionnet virtual network laboratory" \
               "$BUILD/desc.kernels-i386" "$t"
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
rm -f %{buildroot}%{_libdir}/*.la %{buildroot}%{_libdir}/*.a
# vde_tunctl is installed into /usr/sbin, which on a usrmerged box (Fedora) IS /usr/bin and on
# an EL box is not. Moved, so that ONE file list below is right on every build box rather than
# one list per usrmerge state.
if [ -d %{buildroot}/usr/sbin ]; then
  mkdir -p %{buildroot}%{_bindir}
  mv %{buildroot}/usr/sbin/* %{buildroot}%{_bindir}/
  rmdir %{buildroot}/usr/sbin
fi'
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
      # /usr/lib/uml is written literally, not as %%{_libdir}: the 2007 Makefile hardcodes
      # LIB_DIR=/usr/lib/uml, never lib64.
      files='%{_bindir}/*
/usr/lib/uml'
      # readline-devel is what uml_mconsole -- the one binary Marionnet actually calls -- needs,
      # and fuse-devel is FUSE *2*, for uml_mount. The whole set is built rather than the two
      # tools Marionnet uses: a package which carries a distribution's name and half of its
      # commands is a trap for whoever installs it by that name. Measured on Fedora 42: the
      # deprecated fuse-devel 2.9.9 is still there, so being faithful costs nothing today.
      buildreq='gcc, make, patch, readline-devel, fuse-devel'
      build_recipe='make -j1'
      # jail_uml lands in /usr/sbin, which on a usrmerged box IS /usr/bin and on an EL box is
      # not. Moved for the same reason as vde_tunctl above: one file list, right everywhere.
      # (Moving it does NOT remove the filesystem(unmerged-sbin-symlinks) requirement Fedora
      # adds -- that generator fires on the BASENAME, wherever the file goes. Building on an
      # EL box is what removes it; see the header.)
      install_recipe='make install DESTDIR=%{buildroot}
if [ -d %{buildroot}/usr/sbin ]; then
  mkdir -p %{buildroot}%{_bindir}
  mv %{buildroot}/usr/sbin/* %{buildroot}%{_bindir}/
  rmdir %{buildroot}/usr/sbin
fi'
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
    kernels-i386)     package_kernels_i386 ;;
    fs-guignol)       package_fs_guignol ;;
    vde2|uml-utilities) package_thirdparty "$what" ;;
  esac
done

if ((KEEP_BUILD)); then info "build tree kept: $BUILD"; fi

# The index dnf reads is rewritten from WHAT IS THERE, once, after the loop -- never per
# package: repodata describes the whole directory, so writing it five times would only make
# the first four wrong for a moment. Called even when every package was already published and
# skipped: the reason a run finds nothing to do is often that a previous one was interrupted
# before this line.
# ---
# --- Every package of the directory, signed -- including the ones this run did not build.
# ---
# A package which is THERE but NOT SIGNED is work not done, so `--sign' covers the whole
# directory and not merely what this run produced. Without this, signing a release would mean
# rebuilding six packages to change nothing but their signature -- and rebuilding is precisely
# what episode 20c removed from this channel. rpmsign is idempotent (it says "already contains
# identical signature, skipping", measured), so a second run costs nothing.
#
# Signing rewrites the file, hence the catalogue is corrected for each one: the digest recorded
# before describes a package nobody will download (the lesson of episode 9b, again).
if test -n "$SIGN_KEY"; then
  want="${SIGN_KEY: -16}"; want="${want,,}"
  for f in "$OUTDIR"/*.rpm; do
    test -e "$f" || continue
    shown=$(rpm -qp --qf '%{RSAHEADER:pgpsig}' -- "$f" 2>/dev/null)
    case "${shown,,}" in
      *"$want"*) continue ;;                       # already ours
    esac
    info "signing $(basename -- "$f") ..."
    sign_rpm "$f"
    bash "$ROOT/Makefile.d/release.sha256sums.sh" --output-dir "$OUTDIR" --force -- "$(basename -- "$f")" \
      || warn "$(basename -- "$f") is signed but NOT in SHA256SUMS"
  done
fi

bash "$ROOT/Makefile.d/release.dnf.sh" --output-dir "$OUTDIR" --series "$SERIES" \
     --build-image "$BUILD_IMAGE" ${SIGN_KEY:+--sign "$SIGN_KEY"} || \
  warn "the packages are published but dnf cannot read the directory: run Makefile.d/release.dnf.sh"

info "done. The packages are in $OUTDIR, in its SHA256SUMS, and in its repodata."
