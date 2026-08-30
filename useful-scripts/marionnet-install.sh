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
# `modernisation-installation-marionnet'). For the time being it implements ONE mode,
# --fetch-only: put the released kernels and guest filesystems where Marionnet looks for
# them. Everything else -- apt dependencies, the binary itself, marionnet.conf -- belongs
# to the child work-stream `...-par-script' and exits 2 with a clear message.
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
#       --gz                 prefer .tar.gz where both forms exist (default: .tar.xz)
#   -f, --force              re-extract what is already in place
#       --no-verify          do not check the artefacts against SHA256SUMS
#   -y, --yes                do not ask for confirmation
#   -h, --help               this help
#
# The default is .tar.xz, extracted through `xz -dc -T0 | tar xf -' and NEVER through
# `tar xJf': `xz -T0' cuts the stream into blocks, which makes DEcompression parallel too
# (measured: 5.1 s against 21.6 s for the same 1.9 GiB image, and 8.3 s for gzip).
# --gz is for a machine without xz.
#
# Privilege is asked for only where it is needed: the extraction runs under sudo only when
# the destination is not writable, so a --prefix under /tmp needs none at all.
# ---

set -euo pipefail

PROGNAME="${0##*/}"

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
SOURCE=""
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

while (( $# > 0 )); do
  case "$1" in
    --fetch-only)          MODE=fetch ;;
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
    -y|--yes)              ASSUME_YES=yes ;;
    -h|--help)             usage; exit 0 ;;
    -*)                    die "unknown option \`$1' (try --help)" ;;
    *)                     die "unexpected argument \`$1' (try --help)" ;;
  esac
  shift
done

if [[ -z $MODE ]]; then
  echo "$PROGNAME: only --fetch-only is implemented so far." >&2
  echo "Installing Marionnet itself (dependencies, binary, configuration) is the business" >&2
  echo "of the child work-stream \`modernisation-installation-marionnet-par-script'." >&2
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
  command -v wget >/dev/null || die "wget is required to fetch from $SOURCE"
else
  SOURCE_KIND=dir
  [[ -d $SOURCE ]] || die "no such directory: $SOURCE (a --from without \`://' is a local mirror)"
  SOURCE=$(cd -- "$SOURCE" && pwd)
fi

MARIONNET_DIR="$PREFIX/share/marionnet"

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
    url) html=$(wget -q -O - -- "$SOURCE/") || return 1
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
    url) wget -q -O - -- "$SOURCE/$file" ;;
  esac
}

# Size in bytes, or nothing when the source cannot tell without downloading.
#
# Over HTTP the size is what a HEAD says: `wget --spider -S' prints the response headers on
# stderr, and Content-Length is read off the LAST of them -- a redirection prints one set of
# headers per hop, and only the last describes the body. A server which will not answer a
# HEAD, or which announces a chunked or compressed body, says nothing: an unknown size is
# then SHOWN as unknown (`human' prints `?'), never as zero. The short timeout is there
# because this runs once per artefact, before anything is transferred: a slow server must
# cost a moment, not a hang.
function artifact_size {
  local file="$1" headers=""
  case "$SOURCE_KIND" in
    dir) stat -c %s -- "$SOURCE/$file" 2>/dev/null || true ;;
    url) headers=$(wget --spider -S -T 10 -t 2 -- "$SOURCE/$file" 2>&1) || return 0
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
    url) text=$(wget -q -O - -- "$SOURCE/SHA256SUMS") || return 1 ;;
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
    kernels_*.tar.xz|filesystems_*.tar.xz) ext=xz ;;
    kernels_*.tar.gz|filesystems_*.tar.gz) ext=gz ;;
    *) continue ;;
  esac
  logical="${f%.tar.$ext}"
  AVAILABLE["$logical"]="${AVAILABLE[$logical]:-} $ext"
done <<< "$CATALOG"

(( ${#AVAILABLE[@]} > 0 )) || die "the source answered, but holds no kernels_*.tar.{gz,xz}\
 nor filesystems_*.tar.{gz,xz}: $SOURCE"

# The kind of an artefact, and where its content lands, are both read off its name:
# `filesystems_<X>.tar.*' carries `filesystems/<X>...', `kernels_<X>.tar.*' carries
# `kernels/<X>...'. This is also what makes the run idempotent without any checksum.
function artifact_kind { case "$1" in kernels_*) echo kernels ;; *) echo filesystems ;; esac; }
function artifact_base { echo "${1#*_}"; }
function artifact_target { echo "$MARIONNET_DIR/$(artifact_kind "$1")/$(artifact_base "$1")"; }

# The form actually retained for one artefact: the preferred one, or the other.
function artifact_format {
  local logical="$1" forms=" ${AVAILABLE[$1]} " other
  case "$PREFERRED_EXT" in xz) other=gz ;; *) other=xz ;; esac
  if   [[ $forms == *" $PREFERRED_EXT "* ]]; then echo "$PREFERRED_EXT"
  else echo "$other"; fi
}

# ---
# --- Selection.
# ---
function is_selected {
  local logical="$1" pat
  case "$(artifact_kind "$logical")" in
    kernels)     [[ $WANT_KERNELS     = yes ]] || return 1 ;;
    filesystems) [[ $WANT_FILESYSTEMS = yes ]] || return 1 ;;
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

# Machines first, then routers: the link resolves as soon as it is created.
SELECTED=()
for pass_wanted in machine router; do
  for logical in $(printf '%s\n' "${!AVAILABLE[@]}" | sort); do
    is_selected "$logical" || continue
    if [[ $(artifact_base "$logical") == router-* ]]
      then this_pass=router
      else this_pass=machine
    fi
    if [[ $this_pass = "$pass_wanted" ]]; then SELECTED+=("$logical"); fi
  done
done

(( ${#SELECTED[@]} > 0 )) || die "the selection retains no artefact (see --list)"

# ---
# --- --list, and the plan of what is to be done.
# ---
if [[ $LIST_ONLY = yes ]]; then
  printf '%-46s %-8s %-8s %-5s %s\n' "ARTEFACT" "FORMAT" "SIZE" "SUM" "STATE"
  for logical in "${SELECTED[@]}"; do
    ext=$(artifact_format "$logical")
    target=$(artifact_target "$logical")
    if [[ -e $target || -L $target ]]; then state="installed"; else state="-"; fi
    if [[ -n ${SUMS[$logical.tar.$ext]:-} ]]; then sum="yes"; else sum="-"; fi
    printf '%-46s %-8s %-8s %-5s %s\n' \
      "$logical" ".tar.$ext" "$(human "$(artifact_size "$logical.tar.$ext")")" "$sum" "$state"
  done
  exit 0
fi

TODO=()
SKIPPED=0
TOTAL_BYTES=0
UNKNOWN_SIZES=0
for logical in "${SELECTED[@]}"; do
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
info "destination : $MARIONNET_DIR"
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

"${SUDO[@]}" mkdir -p -- "$MARIONNET_DIR"

# Extract one artefact, hashing it AS IT FLOWS.
#
# The tarball is never written to disk -- that is the streaming design, and a 1.5 GiB
# temporary file to check a digest before extracting would undo it. So the digest is
# computed on the way through and compared right after. `tee >(sha256sum)' will NOT do:
# bash does not wait for a process substitution, so the comparison could read a digest
# which is not finished being written. Hence an explicit fifo, an explicit pid, an
# explicit `wait'.
#
# Returns 0 when the digest matches, 1 when it does not, 2 when the transfer or the
# extraction itself failed -- three different things to say to the user.
function extract_verified {
  local file="$1" ext="$2" expected="$3"
  local tmpdir fifo digestfile pid rc=0 got=""
  tmpdir=$(mktemp -d) || die "cannot create a temporary directory"
  fifo="$tmpdir/stream"; digestfile="$tmpdir/digest"
  mkfifo "$fifo"
  sha256sum < "$fifo" > "$digestfile" &
  pid=$!
  case "$ext" in
    xz) artifact_stream "$file" | tee "$fifo" | xz -dc -T0 | "${SUDO[@]}" tar xf - -C "$MARIONNET_DIR" ;;
    gz) artifact_stream "$file" | tee "$fifo" | gzip -dc   | "${SUDO[@]}" tar xf - -C "$MARIONNET_DIR" ;;
  esac || rc=$?
  wait "$pid" || true
  [[ -s $digestfile ]] && got=$(awk '{print $1}' "$digestfile")
  rm -rf -- "$tmpdir"
  (( rc == 0 )) || return 2
  [[ -n $got && $got = "$expected" ]] || return 1
  return 0
}

for logical in "${TODO[@]}"; do
  ext=$(artifact_format "$logical")
  file="$logical.tar.$ext"
  size=$(artifact_size "$file")
  echo -n "* $file ($(human "${size:-}")) ... "
  started=$SECONDS
  expected="${SUMS[$file]:-}"
  if [[ $VERIFY = yes && -n $expected ]]; then
    rc=0
    extract_verified "$file" "$ext" "$expected" || rc=$?
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
    # NEVER `tar xJf' (see the header), and NEVER -m/--touch: user-mode-linux checks the
    # mtime of a backing file, which is the whole point of the MTIME field of the .conf.
    case "$ext" in
      xz) artifact_stream "$file" | xz -dc -T0 | "${SUDO[@]}" tar xf - -C "$MARIONNET_DIR" ;;
      gz) artifact_stream "$file" | gzip -dc   | "${SUDO[@]}" tar xf - -C "$MARIONNET_DIR" ;;
    esac
    echo "ok ($(( SECONDS - started ))s)"
  fi
done

info "done: ${#TODO[@]} artefact(s) installed in $MARIONNET_DIR"
