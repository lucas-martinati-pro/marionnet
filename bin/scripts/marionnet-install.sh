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

# The successor of `marionnet_from_scratch' (work-stream
# `modernisation-installation-marionnet'). It implements TWO modes, which combine:
#
#   --fetch-only   put the released kernels and guest filesystems where Marionnet looks for
#                  them;
#   --binary       install the application itself -- the third family of artefacts a release
#                  publishes, the tarball built by Makefile.d/release.binary.sh.
#
# What is still missing to call this an installer -- the apt dependencies of the host -- is
# the business of the child work-stream `...-par-script'; given no mode at all, the script
# says so and exits 2.
#
# WHY --binary IS NOT PART OF --fetch-only, when the three families sit in the same directory
# and the same SHA256SUMS: the first two carry DATA, whose place is fixed under
# <prefix>/share/marionnet/ and which anybody able to write there can lay down. The third
# carries an INSTALLATION -- it writes <prefix>/bin/, /etc/marionnet/marionnet.conf and a
# sudoers rule, and it demands root. Folding that into an option already published would
# change what that option does on the machines which already run it.
#
# It is deliberately SELF-CONTAINED: this file is meant to be downloaded alone and run on
# a machine where the source tree does not exist. It therefore sources nothing, and in
# particular not bashbricks/bashbricks.sh, whatever the convention of the repository is
# for the scripts which ship WITH the binary.
#
# The artefact source is a WORD, not a mode: --from takes either the URL of a release
# directory or a local directory acting as its MIRROR. Only two functions know the
# difference (catalog_list and artifact_stream); everything downstream is shared, which is
# what makes a local mirror able to prove the real mechanism instead of a variant of it.
# A mirror is also what an off-line classroom needs.
#
# What a release directory holds, and what this script does with it:
#
#   SHA256SUMS                            -- the catalogue AND the integrity of the release
#   kernels_linux-6.12.95.tar.xz          -> <prefix>/share/marionnet/kernels/linux-6.12.95
#   filesystems_machine-guignol-18474.tar.xz -> .../share/marionnet/filesystems/machine-guignol-18474
#   marionnet_0.90.6-r4213_amd64_glibc2.41.tar.xz -> unpacked ASIDE, then its own install.sh
#
# The catalogue is SHA256SUMS, not the directory listing. A `sha256sum' line carries a name
# AND a digest, so one published file answers both questions, and it is written by the same
# scripts which build the artefacts (Makefile.d/release.sha256sums.sh). Reading the LISTING
# is only the fallback for a release directory published before that file existed: it means
# parsing somebody's HTML, and it breaks in ways nothing announces -- an index.html dropped
# in the directory makes Apache serve the PAGE instead of the listing, with a 200 and an
# empty catalogue (measured), and `Options -Indexes' forbids it outright. Neither touches
# SHA256SUMS.
#
# What the digest is worth: it proves the artefact ARRIVED WHOLE. It does not prove where it
# comes from -- SHA256SUMS travels the same road as the tarballs, so a compromised server
# rewrites both. Signing it is a question for the day the site comes back, along with the
# key of the apt repository.
#
# Usage: marionnet-install.sh --fetch-only [OPTIONS]
#        marionnet-get-images [OPTIONS]        (the same file, under its other name)
#
# Called as `marionnet-get-images' (or `mrn-get-images'), this script is the guest-image
# CHOOSER of an installed Marionnet: it lists the images and kernels published for the
# series as a checkbox menu, shows as already installed -- checked, and not editable --
# every one whose mtime matches the MTIME its .conf records (the field user-mode-linux
# checks against a backing file), and fetches what was ticked. --binary is refused under
# that name: a machine which already runs Marionnet asked for images.
#
#   -F, --from URL|DIR       where the artefacts are. An existing directory is taken as a
#                            local MIRROR of the release directory; anything containing
#                            `://' is taken as a URL.
#                            (default: <site>/download/marionnet-install.sh/<series>)
#   -s, --series X.Y.x       publication series (default: 1.0.x)
#   -p, --prefix DIR         installation prefix (default: /usr/local); the artefacts land
#                            in DIR/share/marionnet/{kernels,filesystems}/
#   -l, --list               print the catalogue (name, format, size) and exit
#   -n, --dry-run            say what would be done, touch nothing
#   -o, --only PATTERN       keep only the artefacts whose name contains PATTERN (repeatable)
#   -x, --exclude PATTERN    drop the artefacts whose name contains PATTERN (repeatable)
#       --no-kernels         drop every kernels_*
#       --no-filesystems     drop every filesystems_*
#   -b, --binary             install the application too, from the marionnet_* artefact. The
#                            tarball is unpacked ASIDE and its own install.sh lays it down
#                            under --prefix; that step needs root (sudo, if not already).
#       --with-deps          (with --binary) let install.sh install the apt packages the
#                            application needs at run time and the machine has not got
#       --no-deps            (with --binary) do not even look at them (install.sh names
#                            what is missing by default, and installs nothing)
#       --no-sudoers         (with --binary) do not install the sudoers rule
#       --no-config          (with --binary) do not write /etc/marionnet/marionnet.conf
#       --gz                 prefer .tar.gz where both forms exist (default: .tar.xz)
#   -f, --force              re-extract what is already in place
#       --no-verify          do not check the artefacts against SHA256SUMS
#       --choose             offer the images as a checkbox menu (the default of
#                            marionnet-get-images; needs a terminal)
#       --no-choose          take the whole selection without asking, as --fetch-only does
#   -y, --yes                do not ask for confirmation (implies --no-choose)
#   -h, --help               this help
#
# The default is .tar.xz, extracted through `xz -dc -T0 | tar xf -' and NEVER through
# `tar xJf': `xz -T0' cuts the stream into blocks, which makes DEcompression parallel too
# (measured: 5.1 s against 21.6 s for the same 1.9 GiB image, and 8.3 s for gzip).
# --gz is for a machine without xz.
#
# Privilege is asked for only where it is needed: the extraction runs under sudo only when
# the destination is not writable, so a --prefix under /tmp needs none at all. The exception
# is --binary, whose install.sh writes outside the prefix (/etc/marionnet, /etc/sudoers.d)
# and refuses to run as anybody but root.
#
# CHOOSING AMONG THE marionnet_* ARTEFACTS: their name carries everything needed, and it is
# read here exactly as release.binary.sh wrote it -- marionnet_<version>-r<rev>_<arch>_glibc<x.y>.
# An artefact is a candidate when its <arch> is the architecture of this machine and its
# <x.y> is no more recent than the glibc of this machine (a dynamically linked binary demands
# a glibc at least as recent as the one it was linked against; the reverse direction is what
# glibc's symbol versioning guarantees). Among the candidates, the greatest <rev> wins: it is
# the only totally ordered field of the name. Everything refused is SHOWN as refused by
# --list, naming the criterion -- an i386 machine and a glibc which is too old are not the
# same problem, and a catalogue which hides what it rejects lies.
# ---

set -euo pipefail

PROGNAME="${0##*/}"

# ---
# --- ONE FILE, SEVERAL NAMES (episode 16).
# ---
# Invoked as `marionnet-get-images' (or `mrn-get-images'), this script is the guest-image
# CHOOSER an installed Marionnet offers its user -- the same form as marionnet-check.sh,
# which is `mrn2sh' when called by that name: one real implementation, several usage names,
# the choice made by $0.
#
# Why not a script of its own: the chooser needs the catalogue, the streaming extraction
# through `xz -dc -T0' and the digest checked WHILE extracting -- that is this file, in
# full. A second implementation of it is exactly what episode 8 removed. And this file
# cannot be made a library either: it is published alone on the website and downloaded by
# a machine which has nothing, so it sources nothing (episodes 6 and 9c).
#
# What the name takes away: --binary. Under this name the answer to "should I re-install
# the application?" is no -- a machine which already runs Marionnet asked for IMAGES, and a
# tarball laid down over a .deb would leave dpkg owning files it no longer knows.
CHOOSER=no
case "$PROGNAME" in
  marionnet-get-images|mrn-get-images) CHOOSER=yes ;;
esac

# The series is FROZEN in the published script: what a given script fetches is what the
# directory it was published next to serves. --series overrides it.
DEFAULT_SERIES="1.0.x"
DEFAULT_SITE="https://www.marionnet.org/download/marionnet-install.sh"

# ---
# --- Small talk.
# ---
function info { echo "==> $*"; }
function warn { echo "$PROGNAME: warning: $*" >&2; }
function die  { echo "$PROGNAME: $*" >&2; exit 2; }

function usage {
  sed -n '/^# Usage:/,/^# ---$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^---$/d'
}

# Bytes -> something a human reads without counting digits.
function human {
  local b="${1:-}"
  [[ $b =~ ^[0-9]+$ ]] || { echo "?"; return; }
  local u=(B KiB MiB GiB TiB) i=0
  while (( b >= 10240 && i < 4 )); do b=$(( b / 1024 )); i=$(( i + 1 )); done
  echo "$b${u[$i]}"
}

# ---
# --- Command line.
# ---
MODE=""
WANT_RESOURCES=no
WANT_BINARY=no
WITH_SUDOERS=yes
WITH_CONFIG=yes
# Three states, and they are not two: `ask' is what install.sh does on its own -- name the
# missing packages, install none. This script only forwards a DEPARTURE from that.
WITH_DEPS=ask
SOURCE=""
# wget or curl, decided once the source turns out to be a URL; empty for a local mirror,
# which needs neither (`set -u' would trip on the http_* functions otherwise).
FETCHER=""
SERIES="$DEFAULT_SERIES"
PREFIX="/usr/local"
LIST_ONLY=no
DRY_RUN=no
FORCE=no
VERIFY=yes
ASSUME_YES=no
WANT_KERNELS=yes
WANT_FILESYSTEMS=yes
PREFERRED_EXT=xz
ONLY=()
EXCLUDE=()
# Ask, when a human is there. Under the installer's own name nothing is ever asked: a
# script called from another script must not grow a prompt (and `-y' turns it off here).
CHOOSE=$CHOOSER
if [[ $CHOOSER = yes ]]; then MODE=fetch; WANT_RESOURCES=yes; fi

while (( $# > 0 )); do
  case "$1" in
    --fetch-only)          MODE=fetch; WANT_RESOURCES=yes ;;
    -b|--binary)           [[ $CHOOSER = no ]] || die "\`$PROGNAME' fetches guest images and\
 kernels; it does not install the application. That is \`marionnet-install.sh --binary',\
 and on a machine where Marionnet came from a package it is \`apt install marionnet'."
                           MODE="${MODE:-binary}"; WANT_BINARY=yes ;;
    --choose)              CHOOSE=yes ;;
    --no-choose)           CHOOSE=no ;;
    --with-deps)           WITH_DEPS=yes ;;
    --no-deps)             WITH_DEPS=no ;;
    --no-sudoers)          WITH_SUDOERS=no ;;
    --no-config)           WITH_CONFIG=no ;;
    -F|--from)             SOURCE="${2:?--from requires an argument}"; shift ;;
    -s|--series)           SERIES="${2:?--series requires an argument}"; shift ;;
    -p|--prefix)           PREFIX="${2:?--prefix requires an argument}"; shift ;;
    -l|--list)             LIST_ONLY=yes ;;
    -n|--dry-run)          DRY_RUN=yes ;;
    -o|--only)             ONLY+=("${2:?--only requires an argument}"); shift ;;
    -x|--exclude)          EXCLUDE+=("${2:?--exclude requires an argument}"); shift ;;
    --no-kernels)          WANT_KERNELS=no ;;
    --no-filesystems)      WANT_FILESYSTEMS=no ;;
    --gz)                  PREFERRED_EXT=gz ;;
    --xz)                  PREFERRED_EXT=xz ;;
    -f|--force)            FORCE=yes ;;
    --no-verify)           VERIFY=no ;;
    -y|--yes)              ASSUME_YES=yes; CHOOSE=no ;;
    -h|--help)             usage; exit 0 ;;
    -*)                    die "unknown option \`$1' (try --help)" ;;
    *)                     die "unexpected argument \`$1' (try --help)" ;;
  esac
  shift
done

if [[ -z $MODE ]]; then
  echo "$PROGNAME: nothing to do: give --fetch-only (the kernels and the guest images)," >&2
  echo "--binary (the application itself), or both." >&2
  echo "Installing the apt dependencies of the host is still the business of the child" >&2
  echo "work-stream \`modernisation-installation-marionnet-par-script'." >&2
  echo "Try --help." >&2
  exit 2
fi

# ---
# --- The source: a URL, or a local directory mirroring it.
# ---
[[ -n $SOURCE ]] || SOURCE="$DEFAULT_SITE/$SERIES"
SOURCE="${SOURCE%/}"

if [[ $SOURCE == *"://"* ]]; then
  SOURCE_KIND=url
  # One of the two, chosen once: a minimal Debian carries wget, a minimal Fedora or a
  # slim container often carries only curl, and neither is Essential. wget stays FIRST
  # because it is what every measurement of this script has been made with.
  if   command -v wget >/dev/null; then FETCHER=wget
  elif command -v curl >/dev/null; then FETCHER=curl
  else die "wget or curl is required to fetch from $SOURCE"
  fi
else
  SOURCE_KIND=dir
  [[ -d $SOURCE ]] || die "no such directory: $SOURCE (a --from without \`://' is a local mirror)"
  SOURCE=$(cd -- "$SOURCE" && pwd)
fi

MARIONNET_DIR="$PREFIX/share/marionnet"

# ---
# --- HTTP, in two verbs, so that the four functions below never name a downloader.
# ---
# THE `-f' OF curl IS NOT A COMFORT OPTION. Without it curl exits 0 on a 404 and writes the
# server's error page on stdout: `sums_read' would survive it (it COUNTS the lines it
# recognises, the guard put in at episode 8, precisely because a 200-with-an-HTML-body is a
# thing servers do), but `artifact_stream' would pour that page into a tarball, and the only
# thing standing between it and the disk would be the digest. `wget -q -O -' fails on a 404
# by itself; `-f' is what makes curl the same tool.
#
# And no `-S' either, for the symmetrical reason: `wget -q' says nothing when it fails, and
# ONE of these fetches is expected to fail on a well-formed release published before episode
# 8 -- the SHA256SUMS which is not there, whose absence the script handles by falling back to
# the listing. With -S, curl printed `curl: (22) ... 404' in the middle of a run which was
# going perfectly well (measured). Silence is not a loss here: every caller reads the exit
# status, and the message the user gets is the script's own.
#
# The headers are read the same way in both cases: the LAST Content-Length, one set of
# headers being printed per redirection hop and only the last describing the body.

function http_body {   # $1 = url
  case "$FETCHER" in
    wget) wget -q -O - -- "$1" ;;
    curl) curl -fsL -- "$1" ;;
  esac
}

function http_headers {   # $1 = url -- headers on stdout, short timeout, no body
  case "$FETCHER" in
    wget) wget --spider -S -T 10 -t 2 -- "$1" 2>&1 ;;
    curl) curl -fsSIL --max-time 10 --retry 1 -- "$1" 2>/dev/null ;;
  esac
}

# ---
# --- The two functions -- and the only two -- which know where the artefacts come from.
# ---

# Print the base names the source offers, one per line. Fails (non-zero) when the source
# cannot be READ at all -- which is not the same thing as a source holding no artefact, and
# the difference is the whole message the user gets when the site is down.
function catalog_list {
  local html
  case "$SOURCE_KIND" in
    dir) ls -1 -- "$SOURCE" ;;
    url) html=$(http_body "$SOURCE/") || return 1
         # The listing is Apache's, as it has always been: `href="..."'. This is the
         # FALLBACK now: a release directory which publishes SHA256SUMS never gets here.
         printf '%s\n' "$html" \
         | grep -o 'href="[^"]*"' \
         | sed -e 's/^href="//' -e 's/"$//' -e 's,.*/,,' || true ;;
  esac
}

# Write one artefact on stdout.
function artifact_stream {
  local file="$1"
  case "$SOURCE_KIND" in
    dir) cat -- "$SOURCE/$file" ;;
    url) http_body "$SOURCE/$file" ;;
  esac
}

# Size in bytes, or nothing when the source cannot tell without downloading.
#
# Over HTTP the size is what a HEAD says (see http_headers above), and Content-Length is
# read off the LAST set of headers. A server which will not answer a HEAD, or which
# announces a chunked or compressed body, says nothing: an unknown size is then SHOWN as
# unknown (`human' prints `?'), never as zero. The short timeout is there because this runs
# once per artefact, before anything is transferred: a slow server must cost a moment, not
# a hang.
function artifact_size {
  local file="$1" headers=""
  case "$SOURCE_KIND" in
    dir) stat -c %s -- "$SOURCE/$file" 2>/dev/null || true ;;
    url) headers=$(http_headers "$SOURCE/$file") || return 0
         printf '%s\n' "$headers" \
         | grep -i '^ *Content-Length:' | tail -n 1 \
         | sed -e 's/.*: *//' -e 's/[^0-9]//g' | grep -E '^[0-9]+$' || true ;;
  esac
}

# ---
# --- SHA256SUMS: the catalogue, and the integrity, in one file.
# ---
declare -A SUMS=()        # file name -> expected sha256

# Fill SUMS from the SHA256SUMS of the source. Fails when there is none, when it cannot be
# read, or when it holds no usable line -- a server which answers a missing file with an
# HTML error page and a 200 falls in that last case, which is why the lines are COUNTED
# instead of trusting the exit status alone.
function sums_read {
  local text hex name n=0
  case "$SOURCE_KIND" in
    dir) [[ -f $SOURCE/SHA256SUMS ]] || return 1
         text=$(cat -- "$SOURCE/SHA256SUMS") || return 1 ;;
    url) text=$(http_body "$SOURCE/SHA256SUMS") || return 1 ;;
  esac
  while read -r hex name; do
    [[ $hex =~ ^[0-9a-fA-F]{64}$ ]] || continue
    name="${name#\*}"          # sha256sum marks a binary read with a leading `*'
    [[ -n $name ]] || continue
    SUMS["$name"]="$hex"
    n=$(( n + 1 ))
  done <<< "$text"
  (( n > 0 ))
}

# ---
# --- The catalogue: logical name -> the forms available for it.
# ---
declare -A AVAILABLE=()   # logical -> " gz xz"

CATALOG=""
CATALOG_ORIGIN=SHA256SUMS
if sums_read; then
  CATALOG=$(printf '%s\n' "${!SUMS[@]}")
else
  # The distinction the outage of 2026 taught: a source which cannot be READ is not a source
  # which holds nothing. The fallback is tried first, and only ITS failure is fatal -- so the
  # absence of SHA256SUMS never gets reported as a server being down.
  CATALOG_ORIGIN=listing
  if ! CATALOG=$(catalog_list); then
    die "cannot read the catalogue at $SOURCE (unreachable source: server down, no route, wrong URL?)"
  fi
  warn "the source publishes no SHA256SUMS: the catalogue comes from the directory listing,\
 and nothing will be verified"
fi

while read -r f; do
  [[ -n $f ]] || continue
  case "$f" in
    kernels_*.tar.xz|filesystems_*.tar.xz|marionnet_*.tar.xz) ext=xz ;;
    kernels_*.tar.gz|filesystems_*.tar.gz|marionnet_*.tar.gz) ext=gz ;;
    *) continue ;;
  esac
  logical="${f%.tar.$ext}"
  AVAILABLE["$logical"]="${AVAILABLE[$logical]:-} $ext"
done <<< "$CATALOG"

(( ${#AVAILABLE[@]} > 0 )) || die "the source answered, but holds no kernels_*.tar.{gz,xz},\
 no filesystems_*.tar.{gz,xz} and no marionnet_*.tar.{gz,xz}: $SOURCE"

# The kind of an artefact, and where its content lands, are both read off its name:
# `filesystems_<X>.tar.*' carries `filesystems/<X>...', `kernels_<X>.tar.*' carries
# `kernels/<X>...'. This is also what makes the run idempotent without any checksum.
function artifact_kind {
  case "$1" in
    kernels_*)   echo kernels ;;
    marionnet_*) echo binary ;;
    *)           echo filesystems ;;
  esac
}
function artifact_base { echo "${1#*_}"; }

# Where the presence of an artefact is read, which is also what makes a run idempotent
# without any checksum. The application has no directory of its own under share/marionnet:
# what says it is there is the binary its install.sh lays down.
function artifact_target {
  case "$(artifact_kind "$1")" in
    binary) echo "$PREFIX/bin/marionnet.native" ;;
    *)      echo "$MARIONNET_DIR/$(artifact_kind "$1")/$(artifact_base "$1")" ;;
  esac
}

# The form actually retained for one artefact: the preferred one, or the other.
function artifact_format {
  local logical="$1" forms=" ${AVAILABLE[$1]} " other
  case "$PREFERRED_EXT" in xz) other=gz ;; *) other=xz ;; esac
  if   [[ $forms == *" $PREFERRED_EXT "* ]]; then echo "$PREFERRED_EXT"
  else echo "$other"; fi
}

# ---
# --- The application: which of the published binaries this machine can run.
# ---
# The two facts about the host, obtained the way release.binary.sh obtained them when it
# NAMED the tarball -- reading them differently here would compare two different things.
function host_arch {
  if command -v dpkg >/dev/null; then dpkg --print-architecture; else uname -m; fi
}
function host_glibc {
  local v
  v=$(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}') || true
  # <major>.<minor> only: the patch level of a glibc does not change what it exports.
  [[ $v =~ ^[0-9]+\.[0-9]+ ]] && echo "${BASH_REMATCH[0]}" || true
}

HOST_ARCH=$(host_arch)
HOST_GLIBC=$(host_glibc)

# marionnet_<version>-r<rev>_<arch>_glibc<x.y> -> "<rev> <arch> <x.y>", or nothing.
# The <version> is whatever META holds (`0.90.6', `trunk'), so the name is read from its
# TAIL, which is the part release.binary.sh builds itself.
function binary_fields {
  [[ $1 =~ ^marionnet_.*-r([0-9]+)_([^_]+)_glibc([0-9]+\.[0-9]+)$ ]] || return 1
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
}

# `a <= b' on two <major>.<minor>, numerically (2.9 is older than 2.36, string order is not).
function glibc_le {
  local a="$1" b="$2"
  if (( ${a%%.*} == ${b%%.*} ))
    then (( ${a#*.} <= ${b#*.} ))
    else (( ${a%%.*} <  ${b%%.*} ))
  fi
}

# Why an artefact is, or is not, a candidate for THIS machine: ok | arch | glibc | malformed.
declare -A BINARY_VERDICT=()
BINARY_CHOSEN=""
BINARY_BEST_REV=-1
for logical in "${!AVAILABLE[@]}"; do
  [[ $(artifact_kind "$logical") = binary ]] || continue
  if ! fields=$(binary_fields "$logical"); then
    BINARY_VERDICT["$logical"]=malformed
    continue
  fi
  read -r b_rev b_arch b_glibc <<< "$fields"
  if [[ $b_arch != "$HOST_ARCH" ]]; then
    BINARY_VERDICT["$logical"]="arch"
  elif [[ -n $HOST_GLIBC ]] && ! glibc_le "$b_glibc" "$HOST_GLIBC"; then
    # An unreadable host glibc (no ldd, another libc) rejects nothing: the name would then
    # be compared against nothing, and refusing everything on that ground would be a guess.
    BINARY_VERDICT["$logical"]="glibc"
  else
    BINARY_VERDICT["$logical"]=ok
    if (( b_rev > BINARY_BEST_REV )); then
      BINARY_BEST_REV=$b_rev
      BINARY_CHOSEN="$logical"
    fi
  fi
done

# What --list and the plan say about one binary artefact.
function binary_state {
  local logical="$1"
  case "${BINARY_VERDICT[$logical]:-}" in
    ok)        [[ $logical = "$BINARY_CHOSEN" ]] && echo "chosen" || echo "superseded" ;;
    arch)      echo "not $HOST_ARCH" ;;
    glibc)     echo "needs a newer glibc than ${HOST_GLIBC:-?}" ;;
    malformed) echo "unreadable name" ;;
    *)         echo "-" ;;
  esac
}

# ---
# --- Selection.
# ---
function is_selected {
  local logical="$1" pat
  case "$(artifact_kind "$logical")" in
    kernels)     [[ $WANT_RESOURCES = yes && $WANT_KERNELS     = yes ]] || return 1 ;;
    filesystems) [[ $WANT_RESOURCES = yes && $WANT_FILESYSTEMS = yes ]] || return 1 ;;
    binary)      [[ $WANT_BINARY    = yes ]] || return 1 ;;
  esac
  if (( ${#EXCLUDE[@]} > 0 )); then
    for pat in "${EXCLUDE[@]}"; do [[ $logical == *"$pat"* ]] && return 1; done
  fi
  if (( ${#ONLY[@]} > 0 )); then
    for pat in "${ONLY[@]}"; do [[ $logical == *"$pat"* ]] && return 0; done
    return 1
  fi
  return 0
}

# A `router' image is a SYMLINK to the `machine' image it shares its bytes with, and that
# image comes in ANOTHER tarball: extracted alone, the link is installed dangling, silently.
function machine_counterpart_of {
  local logical="$1" base
  base=$(artifact_base "$logical")
  case "$base" in
    router-*) echo "filesystems_machine-${base#router-}" ;;
    *) : ;;
  esac
}

# The application first, then the machines, then the routers. The last two are ordered
# because a router image is a LINK into the machine tarball, and the link must resolve as
# soon as it is created; the application comes first for another reason -- it is the short,
# privileged step, and a machine which cannot receive it should learn so before gigabytes
# of images have travelled.
SELECTED=()
for pass_wanted in binary machine router; do
  for logical in $(printf '%s\n' "${!AVAILABLE[@]}" | sort); do
    is_selected "$logical" || continue
    if   [[ $(artifact_kind "$logical") = binary ]]; then this_pass=binary
    elif [[ $(artifact_base "$logical") == router-* ]]; then this_pass=router
    else this_pass=machine
    fi
    if [[ $this_pass = "$pass_wanted" ]]; then SELECTED+=("$logical"); fi
  done
done

if [[ $WANT_BINARY = yes ]] && (( ${#BINARY_VERDICT[@]} == 0 )); then
  die "--binary: the source publishes no marionnet_* artefact, so there is no application\
 to install from $SOURCE (a release built before episode 9a publishes only its images and\
 its kernels)"
fi

(( ${#SELECTED[@]} > 0 )) || die "the selection retains no artefact (see --list)"

# ---
# --- --list, and the plan of what is to be done.
# ---
if [[ $LIST_ONLY = yes ]]; then
  printf '%-46s %-8s %-8s %-5s %s\n' "ARTEFACT" "FORMAT" "SIZE" "SUM" "STATE"
  for logical in "${SELECTED[@]}"; do
    ext=$(artifact_format "$logical")
    target=$(artifact_target "$logical")
    if [[ $(artifact_kind "$logical") = binary ]]; then
      state=$(binary_state "$logical")
      if [[ -e $target ]]; then state="$state, installed"; fi
    elif [[ -e $target || -L $target ]]; then state="installed"
    else state="-"
    fi
    if [[ -n ${SUMS[$logical.tar.$ext]:-} ]]; then sum="yes"; else sum="-"; fi
    printf '%-46s %-8s %-8s %-5s %s\n' \
      "$logical" ".tar.$ext" "$(human "$(artifact_size "$logical.tar.$ext")")" "$sum" "$state"
  done
  exit 0
fi

# ---
# --- The chooser (episode 16): what `marionnet-get-images' shows.
# ---
# WHY IT IS HERE AND NOT IN A postinst. Fetching a 5.1 GiB image from a package's postinst
# would hold apt's lock for the whole transfer, leave the package half-configured when the
# link drops, and give dpkg the ownership of nothing at all -- so `apt remove' would free no
# byte of it. The .deb NAMES this command instead, the way it names the sudoers rule: name,
# do not do. And because the chooser is a mode of this file rather than a package, it serves
# the three channels -- apt, tarball, sources -- with one implementation.
#
# WHY THE STATE IS READ FROM THE .conf AND NOT FROM A DIGEST OF THE IMAGE. An installed
# image is the EXTRACTED file; SHA256SUMS holds the digest of the tarball it came in, so the
# two cannot be compared. What travels beside the image is its `.conf', which records SUM,
# MD5SUM and MTIME -- and MTIME is the field UML checks against the backing file before
# booting it. Comparing mtime and size is therefore both O(1) and the check that actually
# decides whether Marionnet will open a project made with that image. The md5sum is there
# for whoever asks for it: `v <n>' reads the whole file, which on a 5 GiB image is a
# deliberate wait, not something to impose on the opening of a menu.
#
# An image which is present AND intact is shown checked and CANNOT be unchecked: there is
# nothing to decide about it. One which is present but altered is shown as such and stays
# editable -- that is the row a user wants to be able to re-fetch.

# Prints: ok | altered | absent
function image_state {   # $1 = logical name
  local target conf mtime on_disk
  target=$(artifact_target "$1")
  [[ -e $target || -L $target ]] || { echo absent; return; }
  conf="$target.conf"
  # A kernel travels without a .conf; its presence is all there is to read.
  [[ -f $conf ]] || { echo ok; return; }
  mtime=$(sed -n 's/^MTIME=\([0-9][0-9]*\).*/\1/p' "$conf" | head -n 1)
  [[ -n $mtime ]] || { echo ok; return; }
  # -L, and it is not a detail: a ROUTER image is a symbolic link to the machine image, and
  # its .conf records the MTIME of what the link points AT (both .conf carry the same
  # MD5SUM -- it is the same file). Without -L, stat reads the mtime of the link itself and
  # every freshly installed router is reported as altered (measured).
  # A dangling link answers nothing, and that is exactly a row worth re-fetching.
  on_disk=$(stat -Lc %Y -- "$target" 2>/dev/null) || { echo altered; return; }
  [[ $on_disk = "$mtime" ]] && echo ok || echo altered
}

# Reads the whole file, and reports BOTH fields the .conf carries, each for what it is.
#
# SUM first, and it is not a matter of taste: the BSD `sum' of an image IS the number the
# artefact is named after (machine-guignol-18474 -> SUM=18474), so it is the field the
# whole naming convention of this chain rests on. MD5SUM is extra.
#
# MEASURED, and the reason this function does not pronounce a single verdict: on the
# published 1.0.x release, wheezy agrees on both fields, while GUIGNOL agrees on SUM and
# MTIME but NOT on MD5SUM -- its .conf carries a digest of some earlier state of the image.
# Nothing in Marionnet reads MD5SUM (bin/disk.ml parses it and never consults it), so this
# is stale metadata rather than a broken image; but a chooser which cried "corrupted" at
# every freshly installed guignol would be a chooser nobody believes twice.
function image_integrity_verdict {   # $1 = logical name -- reads the whole file
  local target conf want got out=""
  target=$(artifact_target "$1"); conf="$target.conf"
  [[ -f $conf ]] || { echo "no .conf beside it: nothing to compare"; return; }

  want=$(sed -n 's/^SUM=0*\([0-9]*\).*/\1/p' "$conf" | head -n 1)
  if [[ -n $want ]]; then
    got=$(sum -- "$target" | awk '{print $1+0}')
    if [[ $got = "$want" ]]; then out="SUM ok ($got, the number this artefact is named after)"
    else out="SUM DIFFERS: .conf says $want, the file is $got -- this image is not the one it claims to be"
    fi
  fi

  want=$(sed -n 's/^MD5SUM=\([0-9a-f]*\).*/\1/p' "$conf" | head -n 1)
  if [[ -n $want ]]; then
    got=$(md5sum -- "$target" | cut -d" " -f1)
    if [[ $got = "$want" ]]; then out="$out; md5sum ok"
    else out="$out; md5sum disagrees with the .conf (nothing in Marionnet reads that field)"
    fi
  fi
  echo "${out:-its .conf records neither SUM nor MD5SUM}"
}

# No terminal, no menu -- and under this name, no fallback either. The default selection of
# --fetch-only is EVERYTHING published, which here would be some 7 GiB nobody asked for:
# `marionnet-get-images </dev/null' must not become a way to start that by surprise. Under
# the installer's own name that default is the long-standing documented behaviour and is
# left exactly as it was.
if [[ $CHOOSE = yes && ( ! -t 0 || ! -t 1 ) ]]; then
  die "no terminal to ask on, and the default of this command would be everything published\
 (some GiB). Name what you want with --only PATTERN, or see it with --list."
fi

if [[ $CHOOSE = yes ]]; then
  # The application is never a row of this menu: this command is about images and kernels.
  ROWS=(); STATE=(); PICKED=(); LOCKED=()
  for logical in "${SELECTED[@]}"; do
    [[ $(artifact_kind "$logical") != binary ]] || continue
    st=$(image_state "$logical")
    ROWS+=("$logical"); STATE+=("$st")
    case "$st" in
      ok) PICKED+=(yes); LOCKED+=(yes) ;;   # present and intact: nothing to decide
      *)  PICKED+=(no);  LOCKED+=(no)  ;;
    esac
  done
  (( ${#ROWS[@]} > 0 )) || die "the catalogue of $SERIES holds no image and no kernel"

  function chooser_show {
    local i mark size note num
    echo
    printf '%s\n' "  Guest images and UML kernels published for the $SERIES series"
    printf '%s\n' "  from: $SOURCE"
    printf '%s\n' "  into: $MARIONNET_DIR"
    echo
    for i in "${!ROWS[@]}"; do
      if [[ ${PICKED[$i]} = yes ]]; then mark="[x]"; else mark="[ ]"; fi
      # A locked row carries neither a number nor brackets: there is nothing to type at it,
      # and a checkbox one cannot uncheck is a checkbox which lies about being one.
      num=$(printf '%2d' "$(( i + 1 ))")
      if [[ ${LOCKED[$i]} = yes ]]; then num="  "; mark=" x "; fi
      size=$(human "$(artifact_size "${ROWS[$i]}.tar.$(artifact_format "${ROWS[$i]}")")")
      case "${STATE[$i]}" in
        ok)      note="already installed" ;;
        altered) note="installed, BUT its mtime is not the one its .conf records" ;;
        *)       note="" ;;
      esac
      printf '  %s %s %-40s %8s  %s\n' "$num" "$mark" \
             "$(artifact_base "${ROWS[$i]}")" "$size" "$note"
    done
    echo
    echo "  <n> toggle   a all   n none   v <n> verify an installed one"
    echo "  q quit       <RET> fetch what is checked and not yet installed"
  }

  while true; do
    chooser_show
    read -r -p "  > " answer || { echo; exit 0; }
    case "$answer" in
      q|Q) info "nothing done"; exit 0 ;;
      "")  break ;;
      a|A) for i in "${!ROWS[@]}"; do [[ ${LOCKED[$i]} = yes ]] || PICKED[$i]=yes; done ;;
      n|N) for i in "${!ROWS[@]}"; do [[ ${LOCKED[$i]} = yes ]] || PICKED[$i]=no;  done ;;
      v\ *|V\ *)
        i=$(( ${answer#* } - 1 ))
        if (( i >= 0 && i < ${#ROWS[@]} )) && [[ ${STATE[$i]} != absent ]]; then
          info "reading $(artifact_base "${ROWS[$i]}") in full ..."
          info "$(image_integrity_verdict "${ROWS[$i]}")"
          read -r -p "  (RET) " _ || true
        else
          warn "v wants the number of an artefact which is installed"
        fi ;;
      *[!0-9]*) warn "not a number, and not one of the letters above: $answer" ;;
      *)
        i=$(( answer - 1 ))
        if (( i < 0 || i >= ${#ROWS[@]} )); then warn "no row number $answer"
        elif [[ ${LOCKED[$i]} = yes ]]; then
          warn "$(artifact_base "${ROWS[$i]}") is already installed and intact:\
 --force is how one re-fetches it"
        else
          [[ ${PICKED[$i]} = yes ]] && PICKED[$i]=no || PICKED[$i]=yes
        fi ;;
    esac
  done

  # What the menu decided becomes the selection the rest of this script already knows how to
  # carry out: no second code path, and --dry-run, --force, the digest check and the plan
  # below keep working exactly as they do for --only.
  CHOSEN=()
  for i in "${!ROWS[@]}"; do
    [[ ${PICKED[$i]} = yes ]] || continue
    [[ ${LOCKED[$i]} = no || $FORCE = yes ]] || continue
    CHOSEN+=("${ROWS[$i]}")
  done
  SELECTED=("${CHOSEN[@]}")
  if (( ${#SELECTED[@]} == 0 )); then
    info "nothing selected: nothing to do"
    exit 0
  fi
  # The menu WAS the confirmation: it showed every name, every size and both directories,
  # and the user pressed RET on it. Asking `Proceed? [y/N]' straight after is asking the
  # same question twice, which teaches people to answer without reading.
  ASSUME_YES=yes
fi

# Said AFTER --list on purpose: when nothing published can run here, the listing is exactly
# what the reader needs, and it must not be denied to them by this refusal.
if [[ $WANT_BINARY = yes && -z $BINARY_CHOSEN ]]; then
  for logical in $(printf '%s\n' "${!BINARY_VERDICT[@]}" | sort); do
    warn "$logical: $(binary_state "$logical")"
  done
  die "--binary: none of the ${#BINARY_VERDICT[@]} published application(s) can run on this\
 machine (${HOST_ARCH}, glibc ${HOST_GLIBC:-unknown}). Building from source remains the way\
 in; see --list for what the release does offer."
fi

TODO=()
SKIPPED=0
TOTAL_BYTES=0
UNKNOWN_SIZES=0
for logical in "${SELECTED[@]}"; do
  # The others were listed so that their refusal could be read; only one is transferred.
  if [[ $(artifact_kind "$logical") = binary && $logical != "$BINARY_CHOSEN" ]]; then
    continue
  fi
  target=$(artifact_target "$logical")
  if [[ ( -e $target || -L $target ) && $FORCE != yes ]]; then
    SKIPPED=$(( SKIPPED + 1 ))
    continue
  fi
  TODO+=("$logical")
  size=$(artifact_size "$logical.tar.$(artifact_format "$logical")")
  if [[ $size =~ ^[0-9]+$ ]]
    then TOTAL_BYTES=$(( TOTAL_BYTES + size ))
    else UNKNOWN_SIZES=$(( UNKNOWN_SIZES + 1 ))
  fi
done

BINARY_TODO=no
for logical in "${TODO[@]}"; do
  if [[ $(artifact_kind "$logical") = binary ]]; then BINARY_TODO=yes; fi
done

# Warn about a router kept without the machine it points at -- neither already installed,
# nor about to be.
for logical in "${SELECTED[@]}"; do
  counterpart=$(machine_counterpart_of "$logical") || true
  [[ -n ${counterpart:-} ]] || continue
  target=$(artifact_target "$counterpart")
  if [[ -e $target || -L $target ]]; then continue; fi
  found=no
  for other in "${SELECTED[@]}"; do
    if [[ $other == "$counterpart" ]]; then found=yes; fi
  done
  [[ $found = yes ]] || warn "$logical is a symbolic link to $(artifact_base "$counterpart"), \
which is neither installed nor selected: the link will be dangling"
done

if (( ${#TODO[@]} == 0 )); then
  info "nothing to do: ${SKIPPED} artefact(s) already in place (--force to redo)"
  exit 0
fi

info "source      : $SOURCE ($SOURCE_KIND)"
info "catalogue   : $CATALOG_ORIGIN"
if [[ $BINARY_TODO = yes ]]; then
  info "destination : $PREFIX (the application, laid down by its own install.sh, as root)"
  if [[ $WANT_RESOURCES = yes ]]; then info "              $MARIONNET_DIR (the images and the kernels)"; fi
else
  info "destination : $MARIONNET_DIR"
fi
# The figure the user is about to accept: never rounded up out of a hole. When some sizes
# could not be obtained, the total is announced for what it is -- a lower bound, or nothing.
if   (( UNKNOWN_SIZES == 0 ));  then TRANSFER="$(human "$TOTAL_BYTES") to transfer"
elif (( TOTAL_BYTES > 0 ));     then TRANSFER="at least $(human "$TOTAL_BYTES") to transfer\
 (${UNKNOWN_SIZES} of unknown size)"
else                                 TRANSFER="size unknown"
fi
info "to install  : ${#TODO[@]} artefact(s), $TRANSFER\
$( (( SKIPPED > 0 )) && echo " (${SKIPPED} already in place)")"
for logical in "${TODO[@]}"; do
  echo "    $logical.tar.$(artifact_format "$logical")"
  if [[ $(artifact_kind "$logical") = binary ]]; then
    echo "        unpacked aside, then: install.sh --prefix $PREFIX\
$( [[ $WITH_DEPS = yes ]] && echo " --with-deps")$( [[ $WITH_DEPS = no ]] && echo " --no-deps")\
$( [[ $WITH_SUDOERS = no ]] && echo " --no-sudoers")$( [[ $WITH_CONFIG = no ]] && echo " --no-config")"
  fi
done

if [[ $DRY_RUN = yes ]]; then
  info "dry run: nothing done"
  exit 0
fi

# ---
# --- Tools, privilege, and the extraction itself.
# ---
command -v tar >/dev/null || die "tar is required"
if [[ $VERIFY = yes ]] && ! command -v sha256sum >/dev/null; then
  warn "sha256sum not found: the artefacts will be installed without being verified"
  VERIFY=no
fi
for logical in "${TODO[@]}"; do
  if [[ $(artifact_format "$logical") = xz ]]; then
    command -v xz >/dev/null || die "xz is required for the .tar.xz artefacts (try --gz)"
    break
  fi
done

# The application is not laid down here: its own install.sh is, and it refuses to run as
# anybody but root. Said BEFORE the transfer -- learning it after 40 MiB is a waste, and
# after the images have landed, a half-installation.
PRIV=()
if [[ $BINARY_TODO = yes && $(id -u) -ne 0 ]]; then
  command -v sudo >/dev/null \
    || die "installing the application needs root, and sudo is not here: run me as root"
  PRIV=(sudo)
  info "the application will be installed under sudo"
fi

SUDO=()
if [[ ! -d $MARIONNET_DIR ]]; then
  parent="$MARIONNET_DIR"
  while [[ ! -d $parent ]]; do parent=$(dirname -- "$parent"); done
  [[ -w $parent ]] || SUDO=(sudo)
elif [[ ! -w $MARIONNET_DIR ]]; then
  SUDO=(sudo)
fi
if (( ${#SUDO[@]} > 0 )); then
  info "$MARIONNET_DIR is not writable: the extraction will run under sudo"
fi

if [[ $ASSUME_YES != yes ]]; then
  if [[ ! -t 0 ]]; then die "not a terminal: pass --yes to confirm"; fi
  read -r -p "Proceed? [y/N] " answer
  [[ ${answer:-} = [yY] ]] || { info "aborted"; exit 1; }
fi

# Only when something is going there: --binary alone has no business creating it, and even
# less asking for a password to do so.
if [[ $WANT_RESOURCES = yes ]]; then
  "${SUDO[@]}" mkdir -p -- "$MARIONNET_DIR"
fi

# Extract one artefact, hashing it AS IT FLOWS, into DEST.
#
# The tarball is never written to disk -- that is the streaming design, and a 1.5 GiB
# temporary file to check a digest before extracting would undo it. So the digest is
# computed on the way through and compared right after. `tee >(sha256sum)' will NOT do:
# bash does not wait for a process substitution, so the comparison could read a digest
# which is not finished being written. Hence an explicit fifo, an explicit pid, an
# explicit `wait'.
#
# DEST is a parameter, and PRIVILEGED says whether the extraction runs under sudo: the two
# data families land in a system directory, the application lands in a temporary directory
# of this user, which needs nothing.
#
# Returns 0 when the digest matches, 1 when it does not, 2 when the transfer or the
# extraction itself failed -- three different things to say to the user.
function extract_verified {
  local file="$1" ext="$2" expected="$3" dest="$4" privileged="${5:-yes}"
  local tmpdir fifo digestfile pid rc=0 got=""
  local -a S=()
  if [[ $privileged = yes ]]; then S=("${SUDO[@]}"); fi
  tmpdir=$(mktemp -d) || die "cannot create a temporary directory"
  fifo="$tmpdir/stream"; digestfile="$tmpdir/digest"
  mkfifo "$fifo"
  sha256sum < "$fifo" > "$digestfile" &
  pid=$!
  case "$ext" in
    xz) artifact_stream "$file" | tee "$fifo" | xz -dc -T0 | "${S[@]}" tar xf - -C "$dest" ;;
    gz) artifact_stream "$file" | tee "$fifo" | gzip -dc   | "${S[@]}" tar xf - -C "$dest" ;;
  esac || rc=$?
  wait "$pid" || true
  [[ -s $digestfile ]] && got=$(awk '{print $1}' "$digestfile")
  rm -rf -- "$tmpdir"
  (( rc == 0 )) || return 2
  [[ -n $got && $got = "$expected" ]] || return 1
  return 0
}

# The same, for whoever passed --no-verify or for a release which publishes no digest.
#
# NEVER `tar xJf' (see the header), and NEVER -m/--touch: user-mode-linux checks the
# mtime of a backing file, which is the whole point of the MTIME field of the .conf.
function extract_plain {
  local file="$1" ext="$2" dest="$3" privileged="${4:-yes}"
  local -a S=()
  if [[ $privileged = yes ]]; then S=("${SUDO[@]}"); fi
  case "$ext" in
    xz) artifact_stream "$file" | xz -dc -T0 | "${S[@]}" tar xf - -C "$dest" ;;
    gz) artifact_stream "$file" | gzip -dc   | "${S[@]}" tar xf - -C "$dest" ;;
  esac
}

# ---
# --- The application: unpacked aside, then laid down by its own install.sh.
# ---
# Aside, and not into the prefix: this artefact carries a NAMED ROOT and a whole
# installation, not data files whose place is fixed. Unpacking it where it is going would
# pour bin/ and share/ over the system before anything had been verified, and would leave
# nothing to look at and nothing to remove. What lays it down is the install.sh which
# travels with it -- the same one a human runs after downloading the tarball by hand, so
# there is exactly one installer, and this script does not become a second one.
BINARY_TMP=""
function binary_cleanup {
  if [[ -n $BINARY_TMP && -d $BINARY_TMP ]]; then rm -rf -- "$BINARY_TMP"; fi
  BINARY_TMP=""
}
trap binary_cleanup EXIT

function install_binary {
  local logical="$1" ext="$2" file="$3" expected="$4" started="$5"
  local root rc=0
  BINARY_TMP=$(mktemp -d) || die "cannot create a temporary directory"
  if [[ $VERIFY = yes && -n $expected ]]; then
    extract_verified "$file" "$ext" "$expected" "$BINARY_TMP" no || rc=$?
    case "$rc" in
      0) echo "ok, verified ($(( SECONDS - started ))s)" ;;
      1) echo "FAILED"
         binary_cleanup
         die "$file: sha256 mismatch. The artefact did not arrive whole (transfer error), or\
 the SHA256SUMS of the source is stale. NOTHING was installed: the tarball is unpacked aside,\
 and what had been unpacked was removed. Use --no-verify to install it anyway." ;;
      *) echo "FAILED"
         binary_cleanup
         die "$file: transfer or extraction failed" ;;
    esac
  else
    extract_plain "$file" "$ext" "$BINARY_TMP" no
    echo "ok ($(( SECONDS - started ))s)"
  fi

  # The named root is the contract of the artefact (Makefile.d/release.binary.sh): the
  # directory inside is the name of the tarball without its extension.
  root="$BINARY_TMP/$logical"
  [[ -d $root ]] \
    || { binary_cleanup; die "$file: no directory \`$logical' inside: this does not look like\
 an application artefact"; }
  [[ -f $root/install.sh ]] \
    || { binary_cleanup; die "$file: no install.sh inside \`$logical': this artefact cannot\
 install itself"; }

  local -a cmd=(bash "$root/install.sh" --prefix "$PREFIX")
  if [[ $FORCE        = yes ]]; then cmd+=(--force); fi
  if [[ $WITH_DEPS    = yes ]]; then cmd+=(--with-deps); fi
  if [[ $WITH_DEPS    = no  ]]; then cmd+=(--no-deps); fi
  if [[ $WITH_SUDOERS = no  ]]; then cmd+=(--no-sudoers); fi
  if [[ $WITH_CONFIG  = no  ]]; then cmd+=(--no-config); fi
  info "the artefact installs itself: ${cmd[*]}"
  "${PRIV[@]}" "${cmd[@]}" || { binary_cleanup; die "$file: install.sh failed"; }
  binary_cleanup
}

for logical in "${TODO[@]}"; do
  ext=$(artifact_format "$logical")
  file="$logical.tar.$ext"
  size=$(artifact_size "$file")
  echo -n "* $file ($(human "${size:-}")) ... "
  started=$SECONDS
  expected="${SUMS[$file]:-}"
  if [[ $(artifact_kind "$logical") = binary ]]; then
    install_binary "$logical" "$ext" "$file" "$expected" "$started"
    continue
  fi
  if [[ $VERIFY = yes && -n $expected ]]; then
    rc=0
    extract_verified "$file" "$ext" "$expected" "$MARIONNET_DIR" || rc=$?
    case "$rc" in
      0) echo "ok, verified ($(( SECONDS - started ))s)" ;;
      1) echo "FAILED"
         # What was extracted must GO: the run is idempotent by the NAME of the target, so
         # a corrupt artefact left in place would be taken for an installed one ever after.
         # Removing the target alone is enough to make a new run redo the whole artefact,
         # its .conf and its _variants/ included -- they are rewritten by the extraction.
         "${SUDO[@]}" rm -rf -- "$(artifact_target "$logical")"
         die "$file: sha256 mismatch. The artefact did not arrive whole (transfer error), or\
 the SHA256SUMS of the source is stale. What had been extracted was removed; nothing else\
 was touched. Use --no-verify to install it anyway." ;;
      *) echo "FAILED"
         die "$file: transfer or extraction failed" ;;
    esac
  else
    extract_plain "$file" "$ext" "$MARIONNET_DIR"
    echo "ok ($(( SECONDS - started ))s)"
  fi
done

if [[ $BINARY_TODO = yes && $WANT_RESOURCES = yes ]]; then
  info "done: ${#TODO[@]} artefact(s) installed, in $MARIONNET_DIR and under $PREFIX"
elif [[ $BINARY_TODO = yes ]]; then
  info "done: the application is installed under $PREFIX"
else
  info "done: ${#TODO[@]} artefact(s) installed in $MARIONNET_DIR"
fi
