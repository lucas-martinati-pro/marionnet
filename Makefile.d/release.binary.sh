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

# Turn this working copy into the third kind of artefact a Marionnet release is made of:
# the APPLICATION itself, precompiled. The two others are already scripted next to this
# file -- guest images (filesystem.prepare-snapshot-to-publish.sh) and UML kernels
# (kernel.prepare-to-publish.sh) -- and a release which holds only those two installs
# resources for a program the user still has to compile.
#
#   marionnet_trunk-r4213_amd64_glibc2.39.tar.xz    what a machine downloads
#   \_______________ the same name, without .tar.xz, is the root directory inside
#
# Layout inside the tarball:
#
#   <name>/bin/          marionnet.native, and the 18 names of bin/scripts/
#   <name>/share/        share/marionnet/{share,images,scripts,locale,filesystems,kernels},
#                        share/bash-completion/completions/ (twelve names) and
#                        share/doc/marionnet/ (the delivered documentation, episode 14)
#   <name>/install.sh    lays that down under a prefix, and asks for the sudoers rule
#   <name>/README        what this is, what it needs, how to remove it
#   <name>/REQUIRED-PACKAGES-RUNTIME
#                        the apt packages the target machine needs, one per line, generated
#                        from REQUIRED_PACKAGES_RUNTIME of the Makefile and read back by
#                        install.sh (which names them, and installs them on --with-deps)
#
# WHY A NAMED ROOT, when the two sibling tarballs unpack straight into their destination:
# those carry data files whose place is fixed ($PREFIX/share/marionnet/{filesystems,
# kernels}/), this one carries a whole installation. A tarball which pours bin/ and share/
# directly into /usr/local cannot be looked at before being trusted, and leaves nothing to
# uninstall. The named root also gives install.sh somewhere to live.
#
# WHAT MAKES IT RELOCATABLE, and it is worth stating because nothing in the binary is
# patched: bin/configuration.ml reads a CASCADE of configuration files, of which
# /etc/marionnet/marionnet.conf is one, and MARIONNET_PREFIX & friends read there override
# the prefix COMPILED IN (Meta.prefix, from CONFIGME). install.sh writes that file. Without
# it, a tarball unpacked anywhere but /usr/local would look for its images, its icons and
# its .mo catalogues under /usr/local and find nothing -- silently, since every one of those
# lookups has a fallback. See also bin/gettext.ml, whose locale cascade ends the same way.
#
# WHY THE GLIBC IN THE NAME, and not the distribution: what a dynamically linked binary
# demands of the machine it lands on is a glibc at least as recent as the one it was linked
# against (plus GTK, which the runtime dependencies below bring). `debian13' would name a
# distribution which is not the constraint, and would say nothing about Ubuntu or Mint.
#
# No bashbricks here, on purpose: this is the fourth of a family (the two
# *.prepare-to-publish.sh and release.sha256sums.sh), none of which sources anything.
#
# Nothing already present is recomputed, unless -f|--force.
#
# Usage: Makefile.d/release.binary.sh [OPTIONS]
#
#   -o, --output-dir DIR         where to publish
#                                (default: website-repo/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x           publication series (default: derived from META)
#   -f, --force                  redo what is already there
#       --gz                     build a .tar.gz instead of the default .tar.xz
#       --xz                     build a .tar.xz (the default; kept to be explicit)
#   -y, --yes                    do not ask before building the tarball
#       --no-tarball             stop before the tarball (keeps the staging, and says where)
#       --keep-staging           do not remove the staging directory afterwards
#       --staging-dir DIR        stage into DIR instead of a fresh mktemp -d, and keep it.
#                                What the .deb publisher (release.deb.sh) calls, so that the
#                                package is assembled from THIS script's idea of what an
#                                installation is made of, rather than from a second one.
#       --print-name             print the artefact name this working copy would produce
#       --allow-testing-configuration
#                                build although CONFIGME.choice points at the testing
#                                configuration -- see below; requires --output-dir and
#                                never records anything in SHA256SUMS
#   -h, --help                   this help
#
# THE TESTING CONFIGURATION IS REFUSED BY DEFAULT. CONFIGME.choice selects the prefix which
# gets compiled into bin/meta.ml: `CONFIGME' gives /usr/local, `CONFIGME.testing.sh' gives
# $OPAM_SWITCH_PREFIX, i.e. a path under the packager's home directory. A tarball built that
# way is not wrong for its author and is quite useful to exercise this script, but it must
# never reach a release directory. Hence: allowed with an explicit flag, into an explicit
# directory, and never catalogued.
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

# Anchored on `Usage: Makefile.d', not on `Usage:': the here-document of install.sh below
# carries a usage of its own, and an unanchored range would print both.
function usage {
  sed -n '/^# Usage: Makefile.d/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

# ---
# --- The publication series.
# ---
# Same reasoning as the kernel script: the rule which turns the version of META into a
# series has a SINGLE implementation, in the filesystem script, which prints it on demand.
# ---
function publication_series {
  bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series
}

# ---
# --- The name of the artefact.
# ---
# version    : META, the single source of truth for the version of the project (the same
#              file bin/version.ml.maker.sh reads).
# revision   : the git revision count, exactly as bin/meta.ml.maker.sh computes it, so that
#              two tarballs of the same version are ordered by the history they were cut at.
# arch       : the Debian architecture name when dpkg is there (amd64, i386, arm64), which
#              is the vocabulary of the packaging channels to come, else uname -m.
# glibc      : see the header. `ldd --version' prints it on its first line, last field.
# ---
function project_version {
  local version="trunk"
  # shellcheck source=/dev/null
  if test -f "$ROOT/META"; then source "$ROOT/META"; fi
  echo "$version"
}

function project_revision {
  if test -d "$ROOT/.git" && command -v git >/dev/null; then
    git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0
  else
    echo 0
  fi
}

function host_arch {
  if command -v dpkg >/dev/null; then dpkg --print-architecture; else uname -m; fi
}

# NO PIPE INTO `head', and this is not a matter of taste: /usr/bin/ldd is itself a bash script,
# so it writes several times, and `head -n 1' closes the pipe after the first line. Under
# `set -o pipefail' (line 94) the SIGPIPE that follows makes the whole substitution fail, and
# the old code then answered `unknown-libc'. MEASURED in the debian:12 build box: 14 failures
# out of 400 with the pipe, 0 out of 400 without it. That is a 3.5% chance, per invocation, of
# NAMING a published artefact after a glibc floor it does not state -- and the name is the only
# place that floor is written (episode 12: marionnet-install.sh and both package benches read
# arch and glibc out of the file name). It is exactly how this run died: the tarball had been
# named correctly, and release.deb.sh, asking the same question a minute later, lost the race.
function host_glibc {
  local out v
  out=$(LC_ALL=C ldd --version 2>/dev/null) || return 1
  v=$(awk 'NR==1{print $NF}' <<<"$out")
  # Keep <major>.<minor> only: the patch level of a glibc does not change what it exports.
  [[ "$v" =~ ^[0-9]+\.[0-9]+ ]] || return 1
  echo "glibc${BASH_REMATCH[0]}"
}

# AND A MEASUREMENT WHICH DID NOT HAPPEN IS NOT A MEASUREMENT (the rule of episode 20, applied
# to the other half of the name): rather than invent `unknown-libc', refuse. A tarball whose
# name does not say its floor is worse than no tarball -- marionnet-install.sh would skip it
# without knowing why, and the .deb built beside it would carry a contradiction.
function artefact_name {
  local g
  g=$(host_glibc) || die "cannot read the glibc version of this machine (\`ldd --version'):
       refusing to name an artefact after a floor nobody measured"
  echo "marionnet_$(project_version)-r$(project_revision)_$(host_arch)_$g"
}

# ---
# --- Command line.
# ---
SERIES=""
OUTDIR=""
OUTDIR_GIVEN=0
FORCE=0
ASSUME_YES=0
MAKE_TARBALL=1
KEEP_STAGING=0
STAGING_GIVEN=""
USE_XZ=1
ALLOW_TESTING=0

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; OUTDIR_GIVEN=1; shift 2 ;;
    -s|--series)     SERIES="$2"; shift 2 ;;
    -f|--force)      FORCE=1; shift ;;
    -y|--yes)        ASSUME_YES=1; shift ;;
    --no-tarball)    MAKE_TARBALL=0; KEEP_STAGING=1; shift ;;
    --keep-staging)  KEEP_STAGING=1; shift ;;
    --staging-dir)   STAGING_GIVEN="$2"; KEEP_STAGING=1; shift 2 ;;
    --xz)            USE_XZ=1; shift ;;
    --gz|--gzip)     USE_XZ=0; shift ;;
    --print-name)    artefact_name; exit 0 ;;
    --allow-testing-configuration) ALLOW_TESTING=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    -*)              die "unknown option '$1' (try --help)" ;;
    *)               die "no positional argument expected: '$1' (try --help)" ;;
  esac
done

test -n "$SERIES" || SERIES=$(publication_series)
test -n "$OUTDIR" || OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"

for cmd in tar du sed awk dune; do
  command -v "$cmd" >/dev/null || die "\`$cmd' not found"
done

# ---
# --- 1. The configuration this working copy is set to build for.
# ---
CHOICE=$(readlink -- "$ROOT/CONFIGME.choice" 2>/dev/null || echo "")
test -n "$CHOICE" || die "CONFIGME.choice is missing or not a symbolic link: run \`make configure'"

if test "$CHOICE" != "CONFIGME"; then
  if ((! ALLOW_TESTING)); then
    die "CONFIGME.choice points at \`$CHOICE': this working copy builds for the opam switch,
not for a release. Run \`make rebuild-for-final' first (it is a full rebuild, which is why
this script will not do it for you), or pass --allow-testing-configuration together with an
explicit --output-dir to build a tarball for your own use."
  fi
  ((OUTDIR_GIVEN)) || die "--allow-testing-configuration requires an explicit --output-dir:
a tarball whose compiled-in prefix is the opam switch must not reach a release directory."
  warn "building with \`$CHOICE': the prefix compiled into bin/meta.ml is the opam switch."
  warn "this tarball will NOT be recorded in SHA256SUMS."
fi

NAME=$(artefact_name)
info "artefact     : $NAME"
info "series       : $SERIES"
info "output dir   : $OUTDIR"

if ((USE_XZ)); then
  command -v xz >/dev/null || die "\`xz' not found (package xz-utils)"
  TARBALL="$OUTDIR/$NAME.tar.xz"
  TAR_COMPRESS=(-I "xz -T0")
else
  TARBALL="$OUTDIR/$NAME.tar.gz"
  TAR_COMPRESS=(-z)
fi

if test -f "$TARBALL" && ((! FORCE)) && ((MAKE_TARBALL)); then
  info "already there, skipped: $TARBALL (use --force to redo)"
  exit 0
fi

# ---
# --- 2. Building, and staging what an installation is made of.
# ---
# `dune install --prefix' is NOT the whole of an installation: Makefile's
# install-final-as-root does two more things, and this script has to do the same two, or the
# tarball would be an installation nobody can use. They are, in order:
#
#   (a) the scripts of bin/scripts/ are put into $PREFIX/bin/ -- dune installs them under
#       share/marionnet/scripts/ (they are data files of the `share' section), which is not
#       on anybody's PATH, while Marionnet, the sudoers rule and the delivered documentation
#       all name them bare: marionnet-cleanup, mrnctl, mrn-verify, mrn2sh...
#   (b) the sudoers rule -- which belongs to the TARGET machine, not to the packager's, so
#       it moves into install.sh below.
#
# The copy of (a) is `cp -a', not `cp -lf' as the Makefile does: a hard link into the same
# tree makes sense on an installed system (one inode, two names), a staging directory about
# to be tarred gains nothing from it. What matters, and what -a preserves, is that most of
# those names are SYMBOLIC LINKS to the real .sh next to them -- and for two of them
# (mrn2sh, mrnck) the name IS the behaviour, the script reading ${0##*/}.
# ---
if test -n "$STAGING_GIVEN"; then
  mkdir -p -- "$STAGING_GIVEN" || die "cannot create the staging directory: $STAGING_GIVEN"
  STAGING=$(cd -- "$STAGING_GIVEN" && pwd)
else
  STAGING=$(mktemp -d -- "${TMPDIR:-/tmp}/marionnet-release-binary.XXXXXXXX")
fi
PREFIX_DIR="$STAGING/$NAME"

function cleanup_staging {
  ((KEEP_STAGING)) || rm -rf -- "$STAGING"
}
trap cleanup_staging EXIT

# The opam environment: this script may be called from make, from a shell where nobody ran
# `eval $(opam env)'. bin/meta.ml.maker.sh does exactly the same, for the same reason.
if command -v opam >/dev/null; then eval "$(opam env)"; fi

info "building (dune build @install) ..."
dune build @install

info "staging into $PREFIX_DIR ..."
mkdir -p -- "$PREFIX_DIR"
dune install --prefix "$PREFIX_DIR" 2>&1 | sed -e 's/^/    /' || die "dune install failed"

test -x "$PREFIX_DIR/bin/marionnet.native" || die "no marionnet.native in the staging: $PREFIX_DIR/bin"

SCRIPTS_DIR="$PREFIX_DIR/share/marionnet/scripts"
test -d "$SCRIPTS_DIR" || die "no scripts directory in the staging: $SCRIPTS_DIR"
shopt -s nullglob
SCRIPTS=("$SCRIPTS_DIR"/*)
shopt -u nullglob
((${#SCRIPTS[@]})) || die "the scripts directory of the staging is empty: $SCRIPTS_DIR"
chmod +x -- "${SCRIPTS[@]}"
cp -a -- "${SCRIPTS[@]}" "$PREFIX_DIR/bin/"
info "staged: $(find "$PREFIX_DIR/bin" -mindepth 1 -maxdepth 1 | wc -l) name(s) in bin/, from the binary and bin/scripts/"

# The delivered documentation (doc-src/dune, episode 14) rides in share/doc/marionnet/, so
# it is already staged by `dune install' above and will be copied by install.sh with the
# rest of share/. The one thing dune cannot carry is the executable bit -- it installs data
# files with mode 0644, measured -- and the example scripts of the two lab directories are
# meant to be RUN by the reader. Same treatment as the scripts above, same reason.
DOC_DIR="$PREFIX_DIR/share/doc/marionnet"
test -d "$DOC_DIR" || die "no delivered documentation in the staging: $DOC_DIR"
shopt -s nullglob
DOC_SCRIPTS=("$DOC_DIR"/labs/session-7/*.sh "$DOC_DIR"/scripting/examples/*.sh)
shopt -u nullglob
((${#DOC_SCRIPTS[@]})) || die "no example script in the staged documentation: $DOC_DIR"
chmod +x -- "${DOC_SCRIPTS[@]}"
info "staged: $(find "$DOC_DIR" -type f | wc -l) file(s) of documentation, ${#DOC_SCRIPTS[@]} of them executable"

# Empty, but expected: Marionnet reads these two directories at startup, and the release
# directory next to this tarball is where their content comes from.
mkdir -p -- "$PREFIX_DIR/share/marionnet/filesystems" "$PREFIX_DIR/share/marionnet/kernels"

# ---
# --- 3. What the target machine needs, taken from the single source of truth.
# ---
# The runtime dependencies live in the Makefile (REQUIRED_PACKAGES_RUNTIME, § 2.4 bis of
# docs/modernisation-installation-marionnet.md) and are asked for there by name. Reading
# them through make, rather than copying the list here, is what keeps this tarball honest
# the day a new host command is called.
# ---
RUNTIME_PACKAGES=$(make --no-print-directory -C "$ROOT" print-required-packages-runtime 2>/dev/null || echo "")
test -n "$RUNTIME_PACKAGES" || warn "could not read REQUIRED_PACKAGES_RUNTIME from the Makefile"

# The same list, but as DATA rather than as prose: install.sh below reads this file to tell
# the target machine what it is missing. It could not simply carry the list inside itself --
# its here-document is quoted on purpose (nothing of the packager's shell leaks into the
# script the user runs), so a second exemplary of the list would have had to be written by
# hand, which is the very defect episode 1 of this work-stream repaired. One package per
# line, comments allowed: install.sh strips them.
REQUIRED_PACKAGES_FILE="$PREFIX_DIR/REQUIRED-PACKAGES-RUNTIME"
{
  echo "# The apt packages a machine RUNNING this Marionnet needs, one per line."
  echo "# Generated by Makefile.d/release.binary.sh from REQUIRED_PACKAGES_RUNTIME of the"
  echo "# Makefile, which is their single source of truth. Read by install.sh next to me."
  printf '%s\n' $RUNTIME_PACKAGES
} > "$REQUIRED_PACKAGES_FILE"

# ---
# --- 4. install.sh and README, the two files which make the tarball self-contained.
# ---
cat > "$PREFIX_DIR/install.sh" <<'INSTALL_SH_EOF'
#!/bin/bash
# Install this precompiled Marionnet under a prefix.
#
# Usage: sudo ./install.sh [--prefix DIR] [--with-deps|--no-deps] [--no-sudoers]
#                          [--no-config] [--force] [-h]
#
#   --prefix DIR    where to install (default: /usr/local)
#   --with-deps     install the missing apt packages Marionnet needs at run time
#                   (they are only NAMED by default: installing them is a second
#                   installation, and this script was asked for the first one)
#   --no-deps       do not even look at them
#   --no-sudoers    do not install the sudoers rule (Marionnet will not be able to build
#                   the ghost taps, i.e. no networking; useful to look before leaping)
#   --no-config     do not write /etc/marionnet/marionnet.conf
#   --force         overwrite an existing /etc/marionnet/marionnet.conf
#   -h, --help      this help
# ---
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PREFIX=/usr/local
WITH_SUDOERS=1
WITH_CONFIG=1
FORCE=0
CHECK_DEPS=1
INSTALL_DEPS=0

function info { echo "==> $*"; }
function warn { echo "install.sh: warning: $*" >&2; }
function die  { echo "install.sh: $*" >&2; exit 2; }
function usage { sed -n '/^# Usage:/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'; }

while (($#)); do
  case "$1" in
    --prefix)     PREFIX="$2"; shift 2 ;;
    --with-deps)  INSTALL_DEPS=1; CHECK_DEPS=1; shift ;;
    --no-deps)    CHECK_DEPS=0; INSTALL_DEPS=0; shift ;;
    --no-sudoers) WITH_SUDOERS=0; shift ;;
    --no-config)  WITH_CONFIG=0; shift ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument '$1' (try --help)" ;;
  esac
done

if ! { test -d "$HERE/bin" && test -d "$HERE/share"; }; then
  die "this is not an unpacked Marionnet tarball: $HERE"
fi

mkdir -p -- "$PREFIX" 2>/dev/null || die "cannot create $PREFIX (run me with sudo?)"
test -w "$PREFIX" || die "$PREFIX is not writable (run me with sudo?)"

info "installing into $PREFIX ..."
cp -a -- "$HERE/bin" "$HERE/share" "$PREFIX/"

# What this Marionnet needs from the host, read from the file the packager generated next
# to me -- REQUIRED_PACKAGES_RUNTIME of the Makefile, its single source of truth. Checked
# BEFORE the sudoers step on purpose: that step runs visudo, which arrives with the `sudo'
# package, so a machine missing it would die here with a message about visudo instead of a
# message about its dependencies.
#
# Named, not installed, unless --with-deps: this script was asked to lay an application
# down, and pulling a dozen packages in is a second installation, which the person running
# it may well want to see coming. Nothing here is ever fatal: a Marionnet installed beside
# a missing library is a Marionnet one `apt install' away from starting, whereas a failed
# install.sh leaves a half-installed tree.
MISSING=()

if ((CHECK_DEPS)); then
  DEPS_FILE="$HERE/REQUIRED-PACKAGES-RUNTIME"
  if ! test -r "$DEPS_FILE"; then
    warn "no REQUIRED-PACKAGES-RUNTIME next to me: cannot tell what this Marionnet needs"
  else
    mapfile -t WANTED < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' -- "$DEPS_FILE")
    if ! command -v dpkg-query >/dev/null; then
      info "not a dpkg system: Marionnet needs these packages, or their local equivalent:"
      info "  ${WANTED[*]}"
    else
      for p in ${WANTED[@]+"${WANTED[@]}"}; do
        dpkg-query -W -f='${Status}' -- "$p" 2>/dev/null | grep -q "ok installed" || MISSING+=("$p")
      done
      if ((! ${#MISSING[@]})); then
        info "apt run-time dependencies: nothing to do (${#WANTED[@]} package(s) already there)."
      elif ((INSTALL_DEPS)); then
        info "installing ${#MISSING[@]} missing apt package(s): ${MISSING[*]}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq || warn "apt-get update failed; installing with the lists at hand"
        if apt-get install -y --no-install-recommends -- "${MISSING[@]}"; then
          MISSING=()
        else
          warn "apt could not install them; Marionnet is installed all the same"
        fi
      else
        warn "${#MISSING[@]} apt package(s) Marionnet needs are missing: ${MISSING[*]}"
        warn "install them with:  sudo apt install ${MISSING[*]}"
        warn "or replay me with --with-deps (--no-deps to stop looking)"
      fi
    fi
  fi
fi

# The configuration cascade of bin/configuration.ml ends at /etc/marionnet/marionnet.conf,
# and THAT is what makes this tarball relocatable: the prefix compiled into the binary is
# only a default. Written whatever the prefix -- including /usr/local, where it merely
# restates the default -- because a file which exists only in the unusual case is a file
# nobody remembers when things go wrong.
if ((WITH_CONFIG)); then
  CONF=/etc/marionnet/marionnet.conf
  if test -e "$CONF" && ((! FORCE)); then
    warn "$CONF exists already, left untouched (--force to overwrite)"
    warn "check that MARIONNET_PREFIX names $PREFIX/share/marionnet"
  else
    mkdir -p -- /etc/marionnet 2>/dev/null || die "cannot create /etc/marionnet (run me with sudo, or pass --no-config)"
    cat > "$CONF" <<EOF
# Written by the install.sh of a precompiled Marionnet tarball.
# It is the last but one step of the cascade read by Marionnet at startup (the last one
# being ~/.marionnet/marionnet.conf, where a single user overrides these for themselves).
# Removing this file makes Marionnet fall back to the prefix it was COMPILED with.
MARIONNET_PREFIX=$PREFIX/share/marionnet
MARIONNET_FILESYSTEMS_PATH=\${MARIONNET_PREFIX}/filesystems
MARIONNET_KERNELS_PATH=\${MARIONNET_PREFIX}/kernels
MARIONNET_LOCALEPREFIX=$PREFIX/share/marionnet/locale
EOF
    info "written: $CONF"
  fi
fi

# The scoped sudoers rule which lets Marionnet build the ghost taps with iproute2. The
# script is the single place where the rule text lives. Deliberately WITHOUT
# --enable-bridges: this grants block (a) only, the socle without which nothing works; the
# NAT and LAN bridge grants are asked for by the end user, from the GUI, the day a bridge
# component is started. Remove the rule with: marionnet-sudoers.sh uninstall
# Asked of visudo itself, rather than of the list above: the condition is that the tool be
# there, and --no-deps (which skips the whole look) must not turn a skippable step into a
# fatal one. visudo arrives with the `sudo' package.
if ((WITH_SUDOERS)) && ! command -v visudo >/dev/null; then
  warn "the 'sudo' package is missing: skipping the sudoers rule (it is validated by visudo)."
  warn "once the packages above are there:  $PREFIX/bin/marionnet-sudoers.sh install <user>"
elif ((WITH_SUDOERS)); then
  USER_TO_GRANT="${SUDO_USER:-${USER:-}}"
  test -n "$USER_TO_GRANT" || die "cannot tell which user to grant (neither SUDO_USER nor USER is set)"
  "$PREFIX/bin/marionnet-sudoers.sh" install "$USER_TO_GRANT"
fi

# Marionnet calls its companion scripts BY THEIR BARE NAME -- marionnet-sudoers.sh,
# marionnet-natbridge.sh, marionnet-cleanup... -- so it finds them through the PATH, not
# through the prefix it was compiled with (measured: `marionnet.native --paths' prints a
# `binaries' line derived from that compiled prefix, and nothing reads it). A prefix outside
# the PATH therefore gives a Marionnet which starts and then cannot build a tap.
case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) warn "$PREFIX/bin is not in your PATH: Marionnet looks up its companion scripts"
     warn "(marionnet-sudoers.sh, marionnet-natbridge.sh, marionnet-cleanup...) by name."
     warn "Add it to the PATH, or install under a prefix which is already in it." ;;
esac

info "done. Try: $PREFIX/bin/marionnet.native --help"
if ((${#MISSING[@]})); then
  warn "...but not before those ${#MISSING[@]} package(s) are installed: the binary is linked"
  warn "against libraries they bring (libgtksourceview-3.0-1 among them) and will not start."
fi
info "Guest images and UML kernels are NOT in this tarball: they are published beside it"
info "and fetched by marionnet-install.sh (see the README next to me)."
INSTALL_SH_EOF
chmod +x -- "$PREFIX_DIR/install.sh"

cat > "$PREFIX_DIR/README" <<README_EOF
Marionnet -- a virtual network laboratory -- precompiled
========================================================

  artefact : $NAME
  version  : $(project_version), git revision $(project_revision)
  built on : $(host_arch), against ${NAME##*_}   # the floor, read where it is written:
                                                  # in the artefact name (episode 12)
  built the: $(date -u '+%Y-%m-%d %H:%M UTC')

WHAT THIS IS
  The application only. The guest filesystems and the UML kernels are published as separate
  artefacts (filesystems_*.tar.*, kernels_*.tar.*) beside this one, because they weigh
  gibibytes and change on their own schedule. Marionnet starts without them, and says so.

INSTALL
  ./install.sh --prefix /usr/local          (as root; --help for the options)

  install.sh copies bin/ and share/ under the prefix, writes /etc/marionnet/marionnet.conf
  -- which is what lets this tarball live anywhere, the prefix compiled in being only a
  default -- and installs the scoped sudoers rule Marionnet needs to build its taps.

  share/doc/marionnet/ travels with it too: INSTALL.md (the three channels, the guest images,
  the sudoers rule, and how to remove all of it), the teacher's guide, the guide to the control
  channel and its runnable examples, the exam mode, the lab-design page an AI agent is told
  to follow, the .mar format, and a complete replayable lab (labs/session-7/). The example
  scripts are installed executable; the documents cite each other by relative path, so they
  can be read where they are.

  share/bash-completion/completions/ travels with it: the clients of the control channel
  (mrnctl, mrn-check, mrn2sh, mrn-verify...) complete their verbs and the names of the
  running components, in a new shell, provided the prefix is one bash-completion looks in
  (/usr, /usr/local) and jq is there.

WHAT THE MACHINE MUST HAVE (Debian/Ubuntu package names)
  $RUNTIME_PACKAGES

  The same list, one name per line and meant to be read by a program rather than by you,
  is in REQUIRED-PACKAGES-RUNTIME next to me. install.sh looks at it: by default it merely
  NAMES what is missing; with --with-deps it installs it; with --no-deps it skips the look.

  By hand, on a Debian-like system: sudo apt install $RUNTIME_PACKAGES

REMOVE
  marionnet-sudoers.sh uninstall
  rm -rf <prefix>/share/marionnet <prefix>/share/doc/marionnet /etc/marionnet
  rm -f  <prefix>/bin/marionnet.native <prefix>/bin/marionnet* <prefix>/bin/mrn* \\
         <prefix>/bin/bashbricks.sh
  rm -f  <prefix>/share/bash-completion/completions/{marionnet-*,mrn*}

LICENCE
  GNU General Public License, version 2 or later. Source: https://www.marionnet.org
README_EOF

# ---
# --- 5. The tarball.
# ---
# root:root for the same reason as the two sibling scripts: what ends up under a prefix is
# system data, laid down by a privileged installer, on a machine where the packager's uid
# means nothing. xz -T0 by default (see the kernel script for the measurement).
# ---
if ((! MAKE_TARBALL)); then
  info "tarball not requested (--no-tarball); the staging is: $PREFIX_DIR"
  exit 0
fi

mkdir -p -- "$OUTDIR"

if ((! ASSUME_YES)) && test -t 0; then
  SIZE=$(du -sh -- "$PREFIX_DIR" | awk '{print $1}')
  read -r -p "Build $TARBALL now (about $SIZE to compress)? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) info "tarball not built; run again (or with -y) when you want it."; exit 0 ;;
  esac
fi

info "building $TARBALL ..."
trap 'rm -f -- "$TARBALL.partial"; cleanup_staging' EXIT
tar -C "$STAGING" --owner=root --group=root "${TAR_COMPRESS[@]}" \
    -cf "$TARBALL.partial" -- "$NAME"
mv -f -- "$TARBALL.partial" "$TARBALL"
trap cleanup_staging EXIT
info "tarball produced: $TARBALL ($(du -h -- "$TARBALL" | awk '{print $1}'))"

# The catalogue of a release directory is SHA256SUMS, and an artefact which never reaches
# that file is invisible to bin/scripts/marionnet-install.sh. Recorded here, right after
# being moved into place, exactly as the two sibling scripts do.
if test "$CHOICE" = "CONFIGME"; then
  # --force, scoped to this single file: we have JUST written it, so a digest already
  # recorded under that name is by construction the digest of the PREVIOUS artefact. Without
  # it, republishing under the same name (which is what our own --force does) leaves the
  # catalogue announcing a file which no longer exists -- and the installer, which checks the
  # digest while extracting, REMOVES what it just fetched. Measured at episode 9b. Scoped, so
  # the gibibytes of the neighbouring artefacts are not re-read.
  bash "$ROOT/Makefile.d/release.sha256sums.sh" --output-dir "$OUTDIR" --force -- "$TARBALL" || \
    warn "$TARBALL is published but NOT in SHA256SUMS: run Makefile.d/release.sha256sums.sh"
else
  info "not recorded in SHA256SUMS (built with $CHOICE, see --allow-testing-configuration)"
fi

info "to install it: tar xf $(basename -- "$TARBALL") && sudo ./$NAME/install.sh"
