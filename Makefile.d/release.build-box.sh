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

# Compile Marionnet in a container of the OLDEST DISTRIBUTION WE SERVE, and publish the
# resulting tarball exactly as `make release-binary' does -- because that is what it runs.
#
# WHY THIS EXISTS. A dynamically linked binary demands of the machine it lands on a glibc at
# least as recent as the one it was linked against; the demand travels FORWARD only (measured:
# built here against 2.39, it runs on Ubuntu 26.04's 2.43 and not on Debian 12's 2.36). Until
# now the application was compiled on the packager's own machine, so the floor of all six
# channels was an accident of that machine. release.rpm.sh already learned the rule the hard
# way (episode 19: the dependency generator applies the CONVENTIONS OF THE DISTRIBUTION IT RUNS
# IN, and they travel inside the package); this script applies it to the application itself.
#
# WHY ONE ARTEFACT AND NOT A MATRIX. Since compatibility travels forward, N builds indexed by
# glibc would publish N-1 artefacts nobody can use: the one built on the floor serves every box
# above it. So there is no matrix -- there is a FLOOR, and it is a knob (--build-image). The
# default is debian:12 (glibc 2.36), which covers the four Debian/Ubuntu boxes of the benches
# AND the four current RPM boxes (Rocky/Alma 10 = 2.39, Leap 16 = 2.40, Fedora 42 = 2.41).
# Serving Rocky 9 (2.34) or Leap 15.6 (2.38) is a scope choice, not a prerequisite: it is
# `--build-image debian:11', and the price is another switch to compile.
#
# WHAT IS *NOT* DESCRIBED TWICE HERE:
#  - the apt build dependencies, the opam switch and the opam packages are read THROUGH make
#    (print-required-packages-build, print-opam-switch, print-opam-packages), the way
#    release.binary.sh already reads the runtime list -- never copied into this file;
#  - the artefact itself is built by `make rebuild-for-final' + `Makefile.d/release.binary.sh',
#    unmodified, INSIDE the box. This script does not know what an installation is made of,
#    what the tarball is called, or how a release directory is catalogued. It only chooses
#    WHERE the compiler runs.
#
# WHAT IS COMPILED IS WHAT IS COMMITTED. The source handed to the box is a `git clone' of this
# working copy at HEAD, not the working copy itself: `_build/', the local opam sandbox and the
# CONFIGME.choice symlink of a developer's tree have no business inside a published artefact.
# The clone KEEPS ITS .git, because bin/meta.ml.maker.sh derives the revision from
# `git rev-list --count HEAD' -- a `git archive' would silently produce an empty revision.
#
# AND KEEPING .git IS NOT ENOUGH, which is the one thing this script had to be taught (measured
# on its first run, which published a tarball called `marionnet_trunk-r0_...'): the clone
# belongs to the caller, the container runs as root, and git since 2.35.2 REFUSES a repository
# it considers of "dubious ownership". Both readers of the revision -- bin/meta.ml.maker.sh and
# release.binary.sh -- treat a failing git as "no VCS here" and fall back to an empty revision,
# a warning and the number 0. Nothing fails; a whole release just loses the number which orders
# it. Hence two things below, and the second matters more than the first: `safe.directory' so
# that git answers, and a COMPARISON against the revision computed on this side, so that a box
# which answers something else stops the run instead of publishing under a name that lies.
#
# AND THE .deb IS MADE HERE TOO (--with-deb, episode 20b). The floor is not a property of the
# tarball, it is a property of the MACHINE THE PACKAGING TOOLS RUN ON -- exactly the rule
# episode 19 paid for on the RPM side. Measured on the package this working copy had published:
#
#   Depends: libc6 (>= 2.38), ..., libglib2.0-0t64 (>= 2.36.0), libgtk-3-0t64 (>= 3.11.5), ...
#
# Two defects in one line, and only the first was foreseen. The glibc constraint is one version
# above what the binary needs; but `libgtk-3-0t64' and `libglib2.0-0t64' are the names of the
# 64-bit time_t transition, and they DO NOT EXIST on Debian 12 -- dpkg-shlibdeps wrote the
# package names of the machine it ran on. Building on the floor gives the pre-transition names
# instead, and those still resolve above it: measured on trixie, `libgtk-3-0t64' declares
# `Provides: libgtk-3-0 (= 3.24.49-3)' (idem for glib), so a versioned dependency on the old
# name is satisfied by the new package. The asymmetry is the glibc one all over again, which is
# why the answer is the same one: BUILD ON THE OLDEST BOX WE SERVE.
#
# So `--with-deb' runs Makefile.d/release.deb.sh in the SAME container, right after the tarball
# and against the staging that has just been compiled. It is not given a --build-image of its
# own, and that is deliberate: the .deb of the application is assembled from a staging which is
# PRODUCED BY COMPILING, so packaging in the box means compiling in the box -- a second entry
# point would have to clone HEAD, hand the revision across and guard `safe.directory' all over
# again. There is one place where the compiler runs, and this is it.
#
# No bashbricks here, on purpose: same family as the other publishers, none of which sources
# anything.
#
# Usage: Makefile.d/release.build-box.sh [OPTIONS]
#
#       --build-image IMAGE      the distribution the compiler runs in (default: debian:12)
#       --with-deb               also build the Debian packages, in the same box
#   -o, --output-dir DIR         where to publish
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -f, --force                  redo the tarball even if that name is already published
#       --rebuild-image          rebuild the build box even if it is already there
#       --keep                   keep the source clone afterwards (says where)
#       --print-image            print the name of the build box image and stop
#   -h, --help                   this help
# ---

set -euo pipefail

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
# --- Command line.
# ---
BUILD_IMAGE="debian:12"
OUTDIR=""
SERIES=""
FORCE=0
REBUILD_IMAGE=0
KEEP=0
PRINT_IMAGE=0
WITH_DEB=0

while (($#)); do
  case "$1" in
    --build-image)   BUILD_IMAGE="$2"; shift 2 ;;
    --with-deb)      WITH_DEB=1; shift ;;
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -f|--force)      FORCE=1; shift ;;
    --rebuild-image) REBUILD_IMAGE=1; shift ;;
    --keep)          KEEP=1; shift ;;
    --print-image)   PRINT_IMAGE=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    *)               die "no positional argument expected: '$1' (try --help)" ;;
  esac
done

# The tag is derived from the base image, so asking for another floor gives it its own box
# rather than silently reusing the previous one (the pattern of release.rpm.sh).
BUILDER_IMAGE="mrn-build-$(echo "$BUILD_IMAGE" | tr ':/' '--')"
((! PRINT_IMAGE)) || { echo "$BUILDER_IMAGE"; exit 0; }

for cmd in docker git make; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found"
done
test -d "$ROOT/.git" || die "not a git working copy: this script publishes what is committed"

# The series has a single implementation, in the filesystem publisher, which prints it on
# demand -- the same indirection release.binary.sh and release.deb.sh use.
test -n "$SERIES" || \
  SERIES=$(bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
mkdir -p -- "$OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

info "build box    : $BUILD_IMAGE  ($BUILDER_IMAGE)"
info "series       : $SERIES"
info "output dir   : $OUTDIR"
((! WITH_DEB)) || info "also building : the Debian packages (release.deb.sh, in the same box)"

# ---
# --- 1. The box the compiler runs in.
# ---
# Built once and kept: what it holds is a whole OCaml switch compiled from source, which is
# the only expensive part of this script. The three lists it needs come from the Makefile,
# read through `make' at the moment the Dockerfile is written -- so a package added there is
# in the next box, and nowhere in this file.
#
# `glade' is in REQUIRED_PACKAGES_BUILD although only a developer editing gui_glade3.xml needs
# it: filtering the list here would be exactly the second source of truth episode 1 removed.
#
# opam runs as root in the box (OPAMROOTISOK) and without its sandbox: bubblewrap needs
# privileges a plain `docker run' does not have, and the box is disposable anyway.
#
# The packaging tools are a LAYER OF THEIR OWN, and the last one: they were added by episode
# 20b to a box that already existed, and putting them before the switch would have made every
# box built so far recompile OCaml from source to gain three apt packages. Last, they cost one
# `apt-get install' -- docker replays the two layers above from its cache, the Dockerfile being
# regenerated identically as long as the three Makefile lists have not moved. lintian is one of
# them on purpose: it judges a package against the policy of the distribution IT RUNS IN, so
# the box where the packages are now made is the box where it has something to say.
# ---
PACKAGING_PACKAGES="dpkg-dev fakeroot lintian"

function make_variable {  # <make target printing it>
  local v; v=$(make --no-print-directory -C "$ROOT" "$1" 2>/dev/null) || \
    die "\`make $1' failed: the Makefile of this working copy does not publish that list"
  test -n "$v" || die "\`make $1' printed nothing"
  echo "$v"
}

# A box built before episode 20b compiles perfectly well and cannot package at all. Rather
# than failing halfway through -- after the switch, the clone and the compilation -- the
# absence is found here, and answered by a rebuild the docker cache makes cheap.
function box_can_package {
  docker run --rm "$BUILDER_IMAGE" sh -c 'command -v dpkg-deb && command -v fakeroot' \
    >/dev/null 2>&1
}

function ensure_builder_image {
  if ((! REBUILD_IMAGE)) && docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
    if ((! WITH_DEB)) || box_can_package; then
      info "build box already there (--rebuild-image to redo it)"
      return 0
    fi
    info "the build box predates --with-deb: adding the packaging tools (cached rebuild) ..."
  fi
  local build_packages opam_switch opam_packages
  build_packages=$(make_variable print-required-packages-build)
  opam_switch=$(make_variable print-opam-switch)
  opam_packages=$(make_variable print-opam-packages)
  info "OCaml switch : $opam_switch"
  info "building the box $BUILDER_IMAGE (once; the switch is compiled from source) ..."
  local ctx; ctx=$(mktemp -d)
  cat > "$ctx/Dockerfile" <<EOF
FROM $BUILD_IMAGE
ENV DEBIAN_FRONTEND=noninteractive
ENV OPAMROOTISOK=1
ENV OPAMYES=1
RUN apt-get update \\
 && apt-get install -y --no-install-recommends $build_packages git ca-certificates xz-utils \\
 && rm -rf /var/lib/apt/lists/*
RUN opam init --bare --disable-sandboxing -y \\
 && opam switch create $opam_switch -y \\
 && opam install -y $opam_packages \\
 && opam clean -a -c -s --logs
RUN apt-get update \\
 && apt-get install -y --no-install-recommends $PACKAGING_PACKAGES \\
 && rm -rf /var/lib/apt/lists/*
EOF
  docker build -t "$BUILDER_IMAGE" -- "$ctx" || \
    { rm -rf -- "$ctx"; die "could not build the box from $BUILD_IMAGE"; }
  rm -rf -- "$ctx"
}

ensure_builder_image

# ---
# --- 2. The source: a clone at HEAD, with its .git.
# ---
# --no-hardlinks: the clone is bind-mounted into a container which writes into it as root,
# and hard links would put those writes inside this repository's object store.
#
# bin/kernels/ is a directory the build expects and git does not track (a directory with no
# file in it): on a working copy it is simply there, on a fresh clone it is not.
# ---
SRC=$(mktemp -d -t mrn-build-src-XXXXXX)
function cleanup { ((KEEP)) || rm -rf -- "$SRC"; }
trap cleanup EXIT

info "cloning HEAD into $SRC ..."
git clone --quiet --no-hardlinks --shared=false "$ROOT" "$SRC/marionnet" 2>/dev/null || \
  git clone --quiet --no-hardlinks "$ROOT" "$SRC/marionnet"
mkdir -p -- "$SRC/marionnet/bin/kernels"

if test -n "$(git -C "$ROOT" status --porcelain)"; then
  warn "this working copy has uncommitted changes: they are NOT in the artefact"
fi

# ---
# --- 3. The build.
# ---
# `make rebuild-for-final' first: the tarball refuses the testing configuration (episode 9a),
# and the box has no CONFIGME.choice at all since git does not carry that symlink.
#
# Everything the container writes lands either in the clone (thrown away) or in the release
# directory (the caller's). The ownership is given back INSIDE the same run and AFTER the
# status has been captured -- a failed build must still leave a readable tree behind.
# ---
FORCE_FLAG=""; ((! FORCE)) || FORCE_FLAG="--force"
# Since episode 33 the VERSION is derived from that same revision (plus the series META
# names), so this one comparison still covers the whole name: the clone is HEAD, it carries
# the same META, and a box which agrees on the revision cannot disagree on the version.
EXPECTED_REV=$(git -C "$ROOT" rev-list --count HEAD)
info "revision     : r$EXPECTED_REV"

info "compiling in $BUILDER_IMAGE ..."
docker run --rm \
  -v "$SRC/marionnet:/src" -v "$OUTDIR:/out" -w /src \
  -e "SERIES=$SERIES" -e "FORCE_FLAG=$FORCE_FLAG" -e "EXPECTED_REV=$EXPECTED_REV" \
  -e "WITH_DEB=$WITH_DEB" \
  -e "CALLER_UID=$(id -u)" -e "CALLER_GID=$(id -g)" \
  "$BUILDER_IMAGE" bash -c '
    set -uo pipefail
    eval $(opam env)
    rc=0
    # The clone belongs to the caller and this runs as root: without this, git refuses the
    # repository and every reader of the revision silently falls back to 0 (see the header).
    git config --global --add safe.directory /src
    rev=$(git -C /src rev-list --count HEAD 2>/dev/null || echo "")
    if test "$rev" != "$EXPECTED_REV"; then
      echo "the box reads revision [$rev] where this working copy reads [$EXPECTED_REV]:" >&2
      echo "refusing to publish an artefact whose name would not order it." >&2
      exit 3
    fi
    make rebuild-for-final || rc=$?
    if test $rc = 0; then
      # The proof of the floor, and it does not depend on the name of the file: the highest
      # versioned glibc symbol the binary references is what a machine must be able to supply.
      # dune calls it marionnet.exe; marionnet.native is the name it is INSTALLED under.
      bin=$(find /src/_build -type f \( -name marionnet.exe -o -name marionnet.native \) | head -n 1)
      if test -z "$bin"; then
        echo "built, but no marionnet binary found under /src/_build: cannot measure the floor" >&2
        rc=4
      else
        echo "==> max glibc symbol referenced: $(readelf -V "$bin" 2>/dev/null \
              | grep -o "GLIBC_[0-9.]*[0-9]" | sort -u -V | tail -n 1)"
      fi
    fi
    if test $rc = 0; then
      bash Makefile.d/release.binary.sh --series "$SERIES" --output-dir /out -y $FORCE_FLAG || rc=$?
    fi
    # The Debian packages, in the same box and against the staging just compiled: what a
    # package DEMANDS is written by tools which apply the conventions of the machine they run
    # on, so the .deb has the same floor as the binary it carries only if it is made here.
    # The data packages are unpacked from the artefacts already published in /out; those which
    # are not there are skipped by that script, not by this one.
    if test $rc = 0 && test "$WITH_DEB" = 1; then
      bash Makefile.d/release.deb.sh --series "$SERIES" --output-dir /out $FORCE_FLAG || rc=$?
    fi
    find /out /src -user 0 -exec chown "$CALLER_UID:$CALLER_GID" {} + 2>/dev/null
    exit $rc
  ' || die "the build failed in $BUILDER_IMAGE (see above for what was published, if anything)"

((! KEEP)) || info "source clone kept: $SRC/marionnet"
info "Success."
