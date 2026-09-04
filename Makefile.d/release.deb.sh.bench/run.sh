#!/bin/bash
# This file is part of Marionnet
# Copyright (C) 2026  Jean-Vincent Loddo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
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
# --- The bench of the RECEIVING side of Makefile.d/release.deb.sh + release.apt.sh.
# ---
# Episode 15a built the four packages and checked them where they were built; it could not
# play the gesture which makes them an INSTALLATION, because that gesture is `apt install'
# on a machine which is not this one. This bench plays it, in containers thrown away
# afterwards, on the four boxes of the roadmap.
#
# THIS IS A THIRD BENCH, not five more cases in release.binary.sh.bench: what is measured
# here is a different artefact reaching a machine by a different road. The tarball bench
# starts from a box already carrying REQUIRED_PACKAGES_RUNTIME, because a human had to
# install them first (episode 10 made install.sh NAME them); this one starts from a BARE
# box, because the whole promise of the .deb channel is that apt resolves that list itself.
# Merging the two would mean one of the two boxes lying about what it stands for.
#
# WHAT ONLY THIS BENCH CAN MEASURE, and why the three points were left to it at episode 15a:
#
#   (a) the exact form of the dependency of marionnet-kernels-i386. `libc6:i386' was read
#       on the developer's machine only; whether apt can satisfy it, and what it says when
#       the foreign architecture has not been enabled, is a property of the target box.
#   (b) what dpkg does with /etc/marionnet/marionnet.conf when the TARBALL wrote it first.
#       Declaring a conffile is one thing; the question it asks is another, and it can only
#       be provoked on a machine where both channels have passed.
#   (c) the glibc refusal. Episode 12 could only write that constraint into a FILE NAME, and
#       the bench had to read the name itself; here apt must refuse in its own words, naming
#       libc6 -- which is the whole point of turning the constraint into metadata.
#
# A NETWORK IS REQUIRED, unlike the tarball bench: apt has to reach the distribution's
# mirror to resolve the thirteen run-time dependencies. Without one, the whole run SKIPs out
# loud rather than measuring a repository nobody could install from.
#
# NOTHING IS MOUNTED but the release directory itself, read-only, at /repo -- so the
# repository under test is the REAL one, the very directory `make release-deb' publishes
# into, indexes and all. apt only ever reads Packages and the four .deb from it.
#
# Conventions of driven-sessions/README.md: 0 = PASS, 77 = SKIP, anything else = FAIL;
# one PASS:/FAIL: line per case, a count at the end, and the bench cleans up. Plain bash,
# no bashbricks: like its two siblings, this driver is a docker orchestration, and the
# assertions are all `grep' and exit codes.
#
# Since episode 27 the repository may be the SERVER instead of the local release directory:
# the argument may be an http(s) URL, and apt then reads Release, Packages and the four .deb
# over https, through the stable entry point -- which is point (6) of the roadmap for this
# bench. What changes is one line of sources.list and nothing else; what is downloaded HERE
# is only what a case has to read on this host (the indexes, a few kiB, and the guest image
# tarball the mtime case compares against).
#
# Usage: run.sh [--distro IMAGE|all] [PATH-OR-URL-OF-A-RELEASE-DIRECTORY]
#        (default distro: debian:trixie-slim; default directory: the newest one under
#         website-repo/download/marionnet-install.sh/)
# ---

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)

# The four boxes of the roadmap. Carried here rather than shared with the two sibling
# benches: a bench has to stay runnable with nothing but docker and its own directory.
DISTROS=(debian:bookworm-slim debian:trixie-slim ubuntu:24.04 ubuntu:26.04)
DISTRO=debian:trixie-slim

ARGS=()
while (( $# )); do
  case $1 in
    --distro) [[ $# -ge 2 ]] || { echo "--distro wants an image reference, or \`all'" >&2; exit 2; }
              DISTRO="$2"; shift 2 ;;
    --distro=*) DISTRO="${1#*=}"; shift ;;
    -h|--help) sed -n '/^# Usage:/,/^# ---$/p' -- "${BASH_SOURCE[0]}"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
if (( ${#ARGS[@]} )); then set -- "${ARGS[@]}"; else set --; fi

# `--distro all' is not a mode of this driver: it re-plays it once per box, so that a red
# case still names ONE distribution. The exit code is the worst of the runs, a SKIP (77)
# never masking a FAIL.
if [[ $DISTRO = all ]]; then
  worst=0
# One download for the four boxes, not four: the loop makes the cache and the children
# inherit it through the environment (episode 27). It is removed here, by the invocation
# which made it, exactly as a single run removes its own.
  ALL_CACHE=""
  if [[ -z ${MRN_BENCH_CACHE:-} ]]; then
    ALL_CACHE=$(mktemp -d -- "${TMPDIR:-/tmp}/mrn-bench-cache.XXXXXXXX")
    export MRN_BENCH_CACHE=$ALL_CACHE
  fi
  for d in "${DISTROS[@]}"; do
    echo; echo "############ $d"
    rc=0; "${BASH_SOURCE[0]}" --distro "$d" "$@" || rc=$?
    if   (( rc == 0  )); then :
    elif (( rc == 77 )); then (( worst == 0 )) && worst=77 || true
    else worst=1
    fi
  done
  [[ -z $ALL_CACHE ]] || rm -rf -- "$ALL_CACHE"
  echo; echo "############ the four boxes: worst exit code $worst"
  exit "$worst"
fi

SLUG=$(printf '%s' "$DISTRO" | tr -c 'A-Za-z0-9' '-')
BOX=mrn-deb-bench-$SLUG              # the nominal machine: bare, apt does everything
BOX_I386=mrn-deb-bench-i386-$SLUG    # the foreign architecture, which changes dpkg's state
BOX_CONF=mrn-deb-bench-conf-$SLUG    # the machine the tarball channel had already touched

PASSED=0; FAILED=0; SKIPPED=0
function pass { echo "PASS: $*"; PASSED=$(( PASSED + 1 )); }
function fail { echo "FAIL: $*"; FAILED=$(( FAILED + 1 )); }
function skip { echo "SKIP: $*"; SKIPPED=$(( SKIPPED + 1 )); }
function skip_all { echo "SKIP: $*"; exit 77; }

TMPFILES=()   # scratch files of the run (the archive key fetched from the out-of-band channel)
function cleanup {
  docker rm -f "$BOX" "$BOX_I386" "$BOX_CONF" >/dev/null 2>&1 || true
  ((${#TMPFILES[@]})) && rm -f -- "${TMPFILES[@]}"

  # What a remote run downloaded is kept for the whole `--distro all' loop and removed by the
  # invocation which created it: four boxes read ONE catalogue, not four copies of it.
  test -z "${CACHE_OWNED:-}" || rm -rf -- "$CACHE"
  return 0
}
trap cleanup EXIT

# ---
# --- Where the repository is read from: a directory, or a server (episode 27)
# ---
# The argument may be an http(s) URL, exactly as `marionnet-install.sh --from' takes a URL
# or a directory -- and for the same reason: only the two functions below know the
# difference, so a remote run exercises the real path instead of a second implementation
# of it.
#
# WHAT IS DOWNLOADED HERE, and what is not. Only what a case has to read on THIS host: the
# three indexes (a few kiB) and, for the mtime case, the published guest image tarball. The
# .deb themselves are fetched by apt, in the box, over https -- and apt verifies each one
# against the digest and the size Packages announces while it fetches it, which is the very
# claim this bench makes. Downloading them a second time here to re-check a digest would
# prove nothing new: that proof is taken ON THE SERVER by the uploader (episode 24), where
# it costs no bandwidth at all.
#
# `curl -f' is not a decoration: without it curl exits 0 on a 404 and the error page would
# land in the file (episode 11b).
function is_url { [[ $1 = http://* || $1 = https://* ]]; }

function fetch_to {   # <url> <destination file>
  if   command -v wget >/dev/null 2>&1; then wget -q -O "$2" -- "$1"
  elif command -v curl >/dev/null 2>&1; then curl -fsS -o "$2" -- "$1"
  else return 127
  fi
}

CACHE=${MRN_BENCH_CACHE:-}
if [[ -z $CACHE ]]; then
  CACHE=$(mktemp -d -- "${TMPDIR:-/tmp}/mrn-bench-cache.XXXXXXXX")
  export MRN_BENCH_CACHE=$CACHE
  CACHE_OWNED=1
fi

# --- What is being measured: a release directory made readable by apt.

REPO="${1:-}"
if [[ -z $REPO ]]; then
  REPO=$(ls -dt "$ROOT"/website-repo/download/marionnet-install.sh/*/ 2>/dev/null | head -n 1) || true
fi

# In a remote run, REPO_URL is what apt is told and REPO becomes the local mirror of the
# indexes -- so every host-side case below keeps reading files, and reads the ones the server
# is serving right now.
REPO_URL=""
if [[ -n $REPO ]] && is_url "$REPO"; then
  REPO_URL=${REPO%/}
  REPO=$CACHE/apt-index
  mkdir -p "$REPO"
  for f in Packages Release SHA256SUMS; do
    test -s "$REPO/$f" && continue
    fetch_to "$REPO_URL/$f" "$REPO/$f" || \
      { [[ $f = SHA256SUMS ]] && continue
        skip_all "cannot read $REPO_URL/$f (no downloader, or this is not a release directory)"; }
  done
fi

[[ -n $REPO && -d $REPO ]] || \
  skip_all "no release directory found (run \`make release-deb', or pass one as argument)"
REPO=$(cd -- "$REPO" && pwd)

shopt -s nullglob
DEBS=("$REPO"/*.deb)
shopt -u nullglob
if [[ -n $REPO_URL ]]; then
  # Remotely, the count of packages is read in the index rather than in the directory: what
  # a flat repository OFFERS is what Packages says, and nothing else is even reachable.
  DEBS=($(awk '/^Filename: /{print $2}' "$REPO/Packages"))
fi
(( ${#DEBS[@]} )) || skip_all "no .deb in ${REPO_URL:-$REPO}: run \`make release-deb' first"
[[ -f $REPO/Packages ]] || skip_all "no Packages in $REPO: run \`make release-apt' first"

command -v docker >/dev/null 2>&1 || skip_all "docker is not installed"
docker info >/dev/null 2>&1        || skip_all "the docker daemon is not reachable"

echo "--- repository: ${REPO_URL:-$REPO}"
echo "--- box       : $DISTRO"
echo "--- packages  : ${#DEBS[@]}"

# The version of each package is read from the index, never typed here: the bench must not
# be a second place where a package version is written down (it moves with its content).
#
# The GREATEST version, not the first one listed: a release directory may legitimately hold
# two revisions of the application at once -- which is why release.apt.sh indexes them with
# --multiversion -- and what apt offers is the highest. Compared with `dpkg', because Debian
# version ordering is its own (`sort -V' does not know what `0~trunk+r913' means).
function indexed_version {  # <package name>
  local v best=""
  while read -r v; do
    if [[ -z $best ]] || dpkg --compare-versions "$v" gt "$best"; then best=$v; fi
  done < <(awk -v p="$1" '/^Package: /{cur=$2} /^Version: /{if (cur==p) print $2}' "$REPO/Packages")
  printf '%s\n' "$best"
}
APP_VERSION=$(indexed_version marionnet)
[[ -n $APP_VERSION ]] || skip_all "the index does not announce a \`marionnet' package"
echo "--- application: marionnet $APP_VERSION"

# ---
# --- Is this repository even installable on this box? (the criterion of episode 12,
# --- now read where it belongs: in the metadata)
# ---
# The tarball bench had to read the glibc out of a FILE NAME, because a tarball has no
# metadata. Here the constraint is a Depends: field, so the bench asks the index for it --
# and the box for what it carries. On a box older than that, the cases which install the
# application step aside, and ONE case takes their place: apt must refuse, and must NAME
# libc6. That is what makes "the .deb turns the constraint into something apt can refuse"
# a measured sentence rather than a hopeful one.
function glibc_le {   # $1 <= $2, as version numbers
  [[ $1 = "$2" ]] || [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1) = "$1" ]]
}

# Of the CANDIDATE stanza, never of the first one listed -- the same lesson `indexed_version'
# above already spells out, and which these two lines were quietly ignoring two lines further
# down. Measured at episode 20b: a release directory holding r913 (built here, libc6 >= 2.38)
# beside r920 (built in the box, 2.35) made the bench announce r920 and then judge it by
# r913's constraint, so it went on expecting a refusal from a box which had just installed the
# package -- a FAIL as misleading as the PASS episode 19 had to kill.
function indexed_field {  # <package name> <version> <field name>: of THAT stanza
  awk -v p="$1" -v want="$2" -v f="$3: " '
    /^Package: /{cur=$2; ver=""} /^Version: /{ver=$2}
    index($0, f)==1 {if (cur==p && ver==want) {print substr($0, length(f)+1); exit}}' "$REPO/Packages"
}

PKG_ARCH=$(indexed_field marionnet "$APP_VERSION" Architecture)
PKG_GLIBC=$(indexed_field marionnet "$APP_VERSION" Depends \
            | sed -n 's/.*libc6 (>= \([0-9][0-9.]*\)).*/\1/p' | head -n 1)
BOX_ARCH=$(docker run --rm "$DISTRO" dpkg --print-architecture 2>/dev/null) || BOX_ARCH=""
BOX_GLIBC=$(docker run --rm "$DISTRO" bash -c "ldd --version | head -n 1 | awk '{print \$NF}'" 2>/dev/null) || BOX_GLIBC=""
if [[ $BOX_GLIBC =~ ^[0-9]+\.[0-9]+ ]]; then BOX_GLIBC=${BASH_REMATCH[0]}; else BOX_GLIBC=""; fi
echo "--- package: arch ${PKG_ARCH:-?}, wants glibc ${PKG_GLIBC:-?} / box: arch ${BOX_ARCH:-?}, glibc ${BOX_GLIBC:-?}"

[[ -z $PKG_ARCH || -z $BOX_ARCH || $PKG_ARCH = "$BOX_ARCH" || $PKG_ARCH = all ]] \
  || skip_all "these packages are $PKG_ARCH and the box is $BOX_ARCH: nothing to measure here"

INSTALLABLE=yes
if [[ -n $PKG_GLIBC && -n $BOX_GLIBC ]] && ! glibc_le "$PKG_GLIBC" "$BOX_GLIBC"; then
  INSTALLABLE=no
  echo "--- the package wants libc6 >= $PKG_GLIBC and this box carries $BOX_GLIBC:"
  echo "--- the cases which INSTALL the application step aside (see the comment above)."
fi

# ---------------------------------------------------------------- 0. the two catalogues
#
# Host-side, before any container: a release directory now holds TWO catalogues, and each
# has one job. They must agree about the .deb -- and must NOT be confused with each other.

SUMS=$REPO/SHA256SUMS
if test -f "$SUMS"; then
  if [[ -z $REPO_URL ]]; then
    if (cd -- "$REPO" && grep -E '\.deb$' SHA256SUMS | sha256sum -c --status -); then
      pass "SHA256SUMS announces the digest of THESE four packages"
    else
      fail "SHA256SUMS does not match the .deb of the directory"
    fi
  else
    # Remotely the same question is asked of the two CATALOGUES rather than of the bytes:
    # SHA256SUMS and Packages both record a SHA256 for every .deb, and they are written by
    # two different scripts (release.sha256sums.sh, dpkg-scanpackages through
    # release.apt.sh). If they disagree, one of the two is describing a file the server no
    # longer holds -- which is exactly the failure of episode 9b, seen from the outside and
    # without downloading 75 MiB to see it. What the bytes are worth is measured where it
    # costs nothing: by the uploader, on the server (episode 24), and by apt itself below.
    disagree=0; checked=0
    while read -r want name; do
      # Compared as STRINGS, never as a pattern: a Debian version is full of characters a
      # regex reads (0~trunk+r930), and `+' alone would make the match fail in silence.
      got=$(awk -v f="$name" '/^Filename: /{cur=$2; sub(/^.*\//, "", cur)}
                              /^SHA256: /{if (cur == f) {print $2; exit}}' "$REPO/Packages")
      [[ -z $got ]] && continue
      checked=$(( checked + 1 ))
      [[ $got = "$want" ]] || { disagree=1; echo "      $name: SHA256SUMS $want, Packages $got"; }
    done < <(grep -E '\.deb$' "$SUMS")
    if (( checked > 0 )) && (( disagree == 0 )); then
      pass "the two catalogues agree on the digest of the $checked published .deb"
    elif (( checked == 0 )); then
      fail "no .deb is announced by BOTH SHA256SUMS and Packages"
    else
      fail "SHA256SUMS and Packages disagree about what the server holds"
    fi
  fi
  # The indexes are rewritten at every publication, so a digest recorded for them would go
  # stale on its own -- the very failure episode 9b had to repair for the artefacts.
  if grep -qE ' (Packages|Packages\.gz|Release)$' "$SUMS"; then
    fail "an apt index is recorded in SHA256SUMS: it will be stale at the next publication"
  else
    pass "the apt indexes are NOT in SHA256SUMS (they are not artefacts)"
  fi
else
  echo "--- no SHA256SUMS in the release directory: the catalogue cases are not played"
fi

# What apt itself verifies before trusting Packages: the digest and the size Release
# announces for it. A Release written beside a Packages it does not describe is a
# repository apt refuses without saying much.
rel_sha=$(awk '/^SHA256:/{s=1;next} /^[A-Z]/{s=0} s && $3=="Packages" {print $1; exit}' "$REPO/Release" 2>/dev/null || true)
rel_size=$(awk '/^SHA256:/{s=1;next} /^[A-Z]/{s=0} s && $3=="Packages" {print $2; exit}' "$REPO/Release" 2>/dev/null || true)
if [[ -n $rel_sha ]] && [[ $rel_sha = $(sha256sum -- "$REPO/Packages" | cut -d' ' -f1) ]] \
   && [[ $rel_size = $(stat -c%s -- "$REPO/Packages") ]]; then
  pass "Release announces the digest and the size of THIS Packages"
else
  fail "Release does not describe the Packages beside it (apt would refuse the repository)"
fi

# ---------------------------------------------------------------- the boxes
#
# BARE boxes, and that is the point: no REQUIRED_PACKAGES_RUNTIME preinstalled, unlike the
# tarball bench's client image. Whether apt pulls the thirteen by itself is precisely what
# the Depends: derived at episode 15a claims, and claims are what a bench is for.
docker rm -f "$BOX" "$BOX_I386" "$BOX_CONF" >/dev/null 2>&1 || true

# A DOCKER IMAGE IS NOT A DEBIAN MACHINE, and this is the one place it matters here: both
# families of base image ship a dpkg configuration which EXCLUDES /usr/share/doc/* (measured
# on debian:*-slim and on ubuntu:*, where the file also drops man pages and translations).
# Left in place, the box would throw away the twenty-six guides episode 14 had installed --
# and the bench would report a defect of the package which is a trait of the box.
#
# So it is removed, in every box, before anything is installed. The tarball bench never met
# this because tar consults nobody's configuration; it is precisely what makes the .deb
# channel deliver LESS than the tarball on such an image -- something the future official
# Docker image of Marionnet will have to face rather than inherit (see the README).
function undocker { docker exec "$1" bash -c 'rm -f /etc/dpkg/dpkg.cfg.d/docker /etc/dpkg/dpkg.cfg.d/excludes'; }

# In a remote run nothing is mounted: the repository under test is on the other side of the
# network, which is the whole point of the exercise.
MOUNT=(-v "$REPO":/repo:ro)
[[ -z $REPO_URL ]] || MOUNT=()

docker run -d --name "$BOX" "${MOUNT[@]}" "$DISTRO" sleep infinity >/dev/null
undocker "$BOX"

function in_box  { docker exec -e DEBIAN_FRONTEND=noninteractive "$BOX" bash -c "$1"; }
function in_i386 { docker exec -e DEBIAN_FRONTEND=noninteractive "$BOX_I386" bash -c "$1"; }
function in_conf { docker exec -e DEBIAN_FRONTEND=noninteractive "$BOX_CONF" bash -c "$1"; }

# The one line of sources.list this whole episode exists to make true. Since episode 30 it
# names a KEY instead of waiving the question: `signed-by=' is what makes apt verify Release
# against the archive key, and `[trusted=yes]' -- what this line said until r930 -- told apt
# to accept an unsigned index. The repository under test must therefore be signed, which is
# what `make release-upload SIGN=yes' does.
ARCHIVE_KEY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/marionnet-archive-keyring.asc"
KEYRING_IN_BOX=/etc/apt/keyrings/marionnet.asc
SOURCE_LINE="deb [signed-by=$KEYRING_IN_BOX] ${REPO_URL:-file:///repo} ./"

# HOW THE KEY REACHES A BOX, and why not from the repository under test: the whole worth of
# a signature is that the key does NOT travel beside the packages it signs (episode 30). The
# bench therefore hands it over out of band -- `docker cp' from the source tree, which is the
# host's own copy -- exactly as a user is told to fetch it from the git repository and not
# from www.marionnet.org. Case 0 bis below measures that real channel.
function install_archive_key {  # <container>
  docker exec "$1" mkdir -p /etc/apt/keyrings
  docker cp -- "$ARCHIVE_KEY" "$1:$KEYRING_IN_BOX" >/dev/null
}
test -f "$ARCHIVE_KEY" || { echo "no $ARCHIVE_KEY: the sources publish no archive key"; exit 1; }
install_archive_key "$BOX"

# The network is a PRECONDITION, asked with the box's own sources and nothing of ours: a
# machine with no mirror cannot resolve the thirteen run-time dependencies, and there is
# nothing to measure there. Asked first, and separately, so that a repository apt REFUSES
# is reported as the red case it is instead of being blamed on the network.
in_box "apt-get update -qq" >/dev/null 2>&1 || \
  skip_all "no network in the containers: apt cannot resolve the run-time dependencies"

function add_source_and_update {  # <in_* function>: prints apt's own words, never fails
  $1 "echo '$SOURCE_LINE' > /etc/apt/sources.list.d/marionnet.list && apt-get update 2>&1" || true
}

# A CA STORE IS A DEPENDENCY OF THE https CHANNEL, and a bare Debian image has none: apt
# then cannot read our repository at all. Made explicit here rather than papered over,
# because it is a sentence the INSTALL documentation owes its reader -- the .deb channel
# over https needs `ca-certificates' on the machine before anything of ours can be fetched.
# Either way the case is green, and either way it NAMES what this box was carrying: the two
# outcomes are two different facts about the box, not two spellings of the same one.
function ca_ready {  # <in_* function>: give that box a CA store if the repository is https
  [[ ${REPO_URL:-} = https://* ]] || return 0
  $1 "test -s /etc/ssl/certs/ca-certificates.crt || \
      (apt-get update -qq && apt-get install -y -qq ca-certificates)" >/dev/null 2>&1 || true
}

CA_NOTE=""
if [[ ${REPO_URL:-} = https://* ]]; then
  out=$(add_source_and_update in_box)
  if grep -qiE 'certificate verify failed|SSL connection failed|not trusted' <<<"$out"; then
    pass "on a bare $DISTRO the https repository is unreadable, and apt names the certificate"
    ca_ready in_box
    CA_NOTE=" (once ca-certificates is installed)"
  else
    pass "this $DISTRO carries a CA store of its own: the https repository is readable as it is"
  fi
fi

# WHAT `apt-get update' DOES NOT SAY, and this bench took its silence for consent until
# episode 27 measured it: a source apt CANNOT FETCH is a warning, not an error -- the exit
# code stays 0 and the run goes on with the repository quietly ignored. The first remote run
# printed `Err: ... certificate verify failed' and this very case still went green, which is
# the fifth of the family "judging by something other than what one measures" (episodes 19,
# 20b, 20c, 24). So the verdict is read in apt's OWN WORDS, and confirmed by what it can SEE.
out=$(add_source_and_update in_box)
cand0=$(in_box "apt-cache policy marionnet 2>/dev/null | awk '/Candidat|Candidate/{print \$2}'" || true)
if ! grep -qE '^(Err|E):' <<<"$out" && [[ -n $cand0 && $cand0 != '(none)' ]]; then
  pass "\`apt-get update' accepts the flat repository$CA_NOTE ($SOURCE_LINE)"
else
  fail "apt does not read the repository ($SOURCE_LINE): Packages or Release does not hold up"
  grep -E '^(Err|E|W):' <<<"$out" | sed 's/^/      /' || true
  echo "--- nothing else can be measured; count: $PASSED passed, $FAILED failed"
  exit 1
fi

# ------------------------------------------------------- 0 bis. the key comes from ELSEWHERE
# The signature is worth exactly what the channel carrying the public key is worth, and that
# channel is deliberately NOT the server serving the packages: the key is versioned in git,
# so it is served by Launchpad -- another infrastructure, another account. What is measured
# here is that the URL the INSTALL page names really carries the key this bench just trusted,
# byte for byte. SKIP, not FAIL, while the commit which publishes it has not been pushed:
# the file exists here before it exists there, and that is not a defect of the channel.
KEY_URL="https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc"
# COMPARED AS FILES, never as shell strings: `$(...)' strips every trailing newline, so a
# comparison of two command substitutions declares two identical keys different -- measured,
# and it is the same defect this episode is about (judging by something other than what one
# measures). `cmp' on what was downloaded and what is versioned settles it, byte for byte.
KEY_FETCHED=$(mktemp); TMPFILES+=("$KEY_FETCHED")
# The HTTP code is read, and not merely the exit status: "not pushed yet" (404) and "could not
# ask" (no downloader, no network, anything else) are two different facts about this run, and a
# SKIP which names the wrong one is the very defect this episode keeps finding.
#
# RETRIED, AND NEVER FOLLOWED. Measured on 2026-09-01: git.launchpad.net answers 200 most of
# the time and, about one request in six, 302 towards login.launchpad.net (OpenID). So the
# request is repeated -- the condition is transient -- and `-L' is deliberately absent: following
# that redirect yields a LOGIN PAGE, which curl would write into the key file without a word.
# An out-of-band channel that fails by handing you the wrong bytes is worse than one that fails.
KEY_HTTP=000
for _try in 1 2 3; do
  KEY_HTTP=$(curl -s -o "$KEY_FETCHED" -w '%{http_code}' --max-time 30 "$KEY_URL" 2>/dev/null || echo "000")
  [[ $KEY_HTTP = 200 ]] && break
  sleep 2
done
if [[ $KEY_HTTP = 200 && -s $KEY_FETCHED ]]; then
  if cmp -s -- "$KEY_FETCHED" "$ARCHIVE_KEY"; then
    pass "the archive key is served by Launchpad, out of band, byte for byte the versioned one"
  else
    fail "$KEY_URL serves a DIFFERENT key from $ARCHIVE_KEY"
  fi
elif [[ $KEY_HTTP = 404 ]]; then
  skip "$KEY_URL does not serve the archive key yet (the commit which adds it is not pushed)"
else
  skip "cannot ask $KEY_URL (HTTP $KEY_HTTP): the out-of-band channel was not measured"
fi

# ------------------------------------------------------- 0 ter. a wrong key must be refused
# Without this case the one above proves nothing: an apt which accepted the repository no
# matter which key sits in /etc/apt/keyrings would go green just the same. So the box is
# given SOMEBODY ELSE'S key and must then refuse.
#
# The foreign key is the DISTRIBUTION'S OWN archive keyring, which every Debian and Ubuntu
# image carries: a real key, properly formed, simply not ours. Forging one in the box was
# tried first and is a trap -- gpg wants a pinentry it has not got, so the case died instead
# of measuring anything (the same missing-tty pitfall as the key generation of this episode).
FOREIGN_KEY=$(in_box "ls -1 /usr/share/keyrings/*archive-keyring.gpg 2>/dev/null | head -1" 2>/dev/null || true)
if [[ -n ${FOREIGN_KEY:-} ]]; then
  # THE LISTS ARE WIPED FIRST, and that is the whole difficulty of this case. Measured on
  # debian:trixie-slim: with a foreign key apt DOES reject the signature (`Err: ... Missing
  # key <fingerprint>') and STILL EXITS 0, saying "the previous index files will be used" --
  # so the package stayed visible and a naive verdict went green on a repository apt had just
  # refused. Sixth of the family "judging by something other than what one measures"
  # (episodes 19, 20b, 20c, 24, 27). The verdict below therefore rests on what apt can SEE
  # once nothing old is left, and the message is only read to confirm why.
  in_box "rm -rf /var/lib/apt/lists/* && cp -- '$FOREIGN_KEY' $KEYRING_IN_BOX" >/dev/null 2>&1 || true
  out=$(add_source_and_update in_box)
  cand=$(in_box "apt-cache policy marionnet 2>/dev/null | awk '/Candidat|Candidate/{print \$2}'" || true)
  if [[ -z $cand || $cand = '(none)' ]] \
     && grep -qiE 'Missing key|NO_PUBKEY|BADSIG|not signed|GPG error|signature verification failed' <<<"$out"; then
    pass "apt REFUSES the repository when signed-by= names another key ($(basename "$FOREIGN_KEY"))"
  else
    fail "apt still offers marionnet ($cand) with a foreign key in $KEYRING_IN_BOX"
    grep -E '^(Err|E|W):' <<<"$out" | sed 's/^/      /' || true
  fi
  # Put the real key back, and wipe the lists again: what follows must measure the repository
  # and not what apt remembers of the refused run.
  install_archive_key "$BOX"
  in_box "rm -rf /var/lib/apt/lists/*" >/dev/null 2>&1 || true
  add_source_and_update in_box >/dev/null
else
  skip "this box carries no distribution keyring: nothing to offer apt as a foreign key"
fi

# ---------------------------------------------------------------- 1. apt sees the four
seen=$(in_box "apt-cache policy marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol 2>/dev/null | grep -c '^marionnet'")
if [[ $seen -eq 4 ]]; then
  pass "apt sees the four packages of the repository"
else
  fail "apt sees $seen of the four packages (Architectures: of Release, or a missing index?)"
fi

cand=$(in_box "apt-cache policy marionnet | awk '/Candidat|Candidate/{print \$2}'")
if [[ $cand = "$APP_VERSION" ]]; then
  pass "the candidate version is the one the index announces ($APP_VERSION)"
else
  fail "apt offers [$cand], the index announces [$APP_VERSION]"
fi

# ---------------------------------------------------------------- 2. installing it
if [[ $INSTALLABLE = no ]]; then
  # The replacement case of episode 12, now played where the criterion lives. What matters
  # is not that it fails -- an unsatisfiable dependency always does -- but that the sentence
  # apt prints NAMES libc6, so that a user reading it knows what to do with it.
  rc=0; out=$(in_box "apt-get install -y marionnet 2>&1") || rc=$?
  if ((rc != 0)) && grep -q 'libc6' <<<"$out"; then
    pass "on $DISTRO (glibc $BOX_GLIBC) apt refuses, and its refusal names libc6"
  else
    fail "the refusal on $DISTRO did not name libc6: rc=$rc, said [$(tail -n 5 <<<"$out")]"
  fi
  echo "--- the rest of the application cases are not played on this box (see above)."
else
  rc=0; out=$(in_box "apt-get install -y marionnet 2>&1") || rc=$?
  if ((rc == 0)); then
    pass "\`apt install marionnet' on a BARE $DISTRO: rc=0, apt pulled the dependencies itself"
  else
    fail "\`apt install marionnet' failed: [$(tail -n 15 <<<"$out")]"
  fi

  # Episode 15a derived Depends: from two sources; this is where the derivation is judged.
  # A missing name shows up as a package apt did not pull -- not as a build error.
  missing=""
  for cmd in vde_switch dot jq socat xterm ip sudo xauth dnsmasq xz; do
    in_box "command -v $cmd >/dev/null" || missing="$missing $cmd"
  done
  if [[ -z $missing ]]; then
    pass "the derived Depends: brought in the commands Marionnet calls by their bare name"
  else
    fail "apt installed marionnet without:$missing (a hole in REQUIRED_PACKAGES_RUNTIME)"
  fi

  # ------------------------------------------------------------ 3. what landed where
  # Counted from what the PACKAGE declares (dpkg -L), not from what the directory holds:
  # /usr/bin and the completions directory belong to the distribution, and every dependency
  # apt pulled in has put its own files there. A count of the directory would measure the
  # box. (And not by name either: one of the 23 is `bashbricks.sh'.)
  names=$(in_box "dpkg -L marionnet | grep -c '^/usr/bin/.'")
  # The binary, its bare name (staged beside marionnet.native, episode 38) and the
  # companions of bin/scripts/. Written
  # here and not derived: unlike the tarball bench -- which compares the installed
  # prefix with the artefact's own bin/ -- what this case measures IS the package's
  # file list, so deriving it from the package would be a tautology.
  if [[ $names -eq 30 ]]; then
    pass "30 names in /usr/bin (the binary, its bare name, and the 28 companions of bin/scripts/)"
  else
    fail "the package owns $names names in /usr/bin, expected 30"
  fi

  compl=$(in_box "dpkg -L marionnet | grep -c '/share/bash-completion/completions/.'")
  if [[ $compl -eq 12 ]]; then
    pass "the twelve completion files are under the prefix (episode 11a, through apt)"
  else
    fail "the package owns $compl completion files, expected 12"
  fi

  if in_box "test -f /usr/share/doc/marionnet/teacher-guide.md && test -d /usr/share/doc/marionnet/scripting"; then
    pass "the delivered guides are in /usr/share/doc/marionnet (episode 14, through apt)"
  else
    fail "the guides of episode 14 did not arrive in /usr/share/doc/marionnet"
  fi

  if in_box "test -f /usr/share/doc/marionnet/copyright && test -f /usr/share/doc/marionnet/changelog.gz"; then
    pass "the package carries its copyright and its changelog, beside the guides"
  else
    fail "no copyright/changelog.gz in /usr/share/doc/marionnet"
  fi

  # ------------------------------------------------------------ 4. the conffile
  if in_box "dpkg-query -W -f='\${Conffiles}' marionnet | grep -q /etc/marionnet/marionnet.conf"; then
    pass "/etc/marionnet/marionnet.conf is registered as a CONFFILE, not as a plain file"
  else
    fail "the conf is not a conffile: an upgrade would silently overwrite a customised one"
  fi
  if in_box "grep -q '^MARIONNET_PREFIX=/usr/share/marionnet$' /etc/marionnet/marionnet.conf"; then
    pass "the conffile redirects the compiled-in prefix to /usr, where apt installed"
  else
    fail "the conffile does not name /usr/share/marionnet: the binary would look elsewhere"
  fi

  # ------------------------------------------------------------ 5. the sudoers rule
  # Invariant 3 of release.deb.sh: the postinst NAMES the rule, it does not grant it.
  if grep -q 'marionnet-sudoers.sh install' <<<"$out"; then
    pass "the postinst NAMES the sudoers rule to install (\`apt' cannot know for whom)"
  else
    fail "the installation said nothing about the sudoers rule Marionnet needs"
  fi
  if in_box "test ! -e /etc/sudoers.d/marionnet"; then
    pass "and it granted nothing: no rule in /etc/sudoers.d"
  else
    fail "the package granted a sudoers rule by itself, to a user it cannot know"
  fi

  # ------------------------------------------------------------ 5 bis. and it says it
  # only while it is true (marionnet-setup-check.sh)
  #
  # The defect this section measures was reported from a MarioNUM classroom: an
  # `apt upgrade' of a machine set up months earlier printed, word for word, the text
  # above -- install the sudoers rule, fetch the images -- for gestures which had been
  # made. A postinst runs at every `configure', so a FIXED text is bound to be wrong on
  # every upgrade; the .rpm channel guarded it with "$1 = 1" and was wrong the other way
  # round. Hence one script, called by both, which measures before it speaks. What is
  # proved here is the discriminance: the same command on the same box says the thing and
  # then stops saying it.
  # `set -e' is on: a check which exits 1 -- which is precisely the case being measured --
  # must not take the bench down with it.
  rc_before=0; before=$(in_box "marionnet-setup-check.sh 2>&1") || rc_before=$?
  if ((rc_before != 0)) && grep -q 'marionnet-sudoers.sh install' <<<"$before"; then
    pass "on a box where nothing is granted, the check SPEAKS and names \`install' (rc $rc_before)"
  else
    fail "the check said nothing about the missing socle on a fresh box: [$(tail -n 3 <<<"$before")]"
  fi
  # Granting for real, with the script the package installed: this is also the only case
  # of this bench which exercises marionnet-sudoers.sh through apt's own files (root-owned
  # all the way, which the rule REQUIRES).
  if in_box "marionnet-sudoers.sh install root" >/dev/null 2>&1; then
    after=$(in_box "marionnet-setup-check.sh 2>&1") || true
    if ! grep -q 'marionnet-sudoers.sh install' <<<"$after"; then
      pass "once the socle is granted, the check no longer asks for it (the upgrade defect)"
    else
      fail "the check still asks for a socle which is granted: [$(tail -n 3 <<<"$after")]"
    fi
    # The third state, which no channel could report before: the file GRANTS its accounts
    # and is out of date (episode 42 -- a machine granted before the tun device door
    # existed). `check' answers 4 for that, and the advice changes accordingly.
    stale=$(in_box "echo '# written by an older version' >> /etc/sudoers.d/marionnet; marionnet-setup-check.sh 2>&1") || true
    if grep -q 'earlier version' <<<"$stale" && grep -q 'ADDITIVE' <<<"$stale"; then
      pass "a socle written by an older version is reported as STALE, and refreshing is additive"
    else
      fail "a stale socle was not reported as such: [$(tail -n 3 <<<"$stale")]"
    fi
    in_box "marionnet-sudoers.sh uninstall" >/dev/null 2>&1 || true
  else
    fail "marionnet-sudoers.sh install root failed on a box furnished by apt alone"
  fi

  # ------------------------------------------------------------ 6. it starts
  # The same measurement the tarball bench makes, on the other channel: the point is that
  # the two channels ship the SAME binary, so what starts there must start here.
  if in_box "marionnet.native --version" >/dev/null 2>&1; then
    pass "marionnet.native --version runs on a box apt alone has furnished"
  else
    fail "the binary does not start after \`apt install marionnet' alone"
  fi
  if in_box "marionnet.native --paths 2>&1 | grep -q '/usr/share/marionnet'"; then
    pass "--paths reads the conffile: the prefix apt installed under is the one used"
  else
    fail "--paths does not name /usr/share/marionnet (the conffile is not being read)"
  fi

  # ------------------------------------------------------------ 6 bis. and the images
  # follow the application (episode 28)
  #
  # The cross-channel measurement, made where it belongs: on a machine furnished by apt
  # alone, with the installer THE PACKAGE ITSELF laid down in /usr/bin (episode 16 gave
  # that one file eighteen names). The big guest images stay outside apt on purpose
  # (§ 6 of the doc, episode 13), so this script is how the user of a .deb gets them --
  # and until episode 28 it wrote them into /usr/local/share/marionnet, one directory
  # away from where the Marionnet apt had just installed was looking. Nothing failed:
  # the images simply never appeared. `--dry-run' is enough to see it, and downloads
  # nothing.
  if in_box "command -v marionnet-install.sh >/dev/null && command -v marionnet-get-images >/dev/null"; then
    pass "the package carries the installer under both of its names"
  else
    fail "marionnet-install.sh / marionnet-get-images are not on the PATH of an apt machine"
  fi
  # THE BOX MUST BE ABLE TO REACH THE CATALOGUE BEFORE THIS MEANS ANYTHING. On a remote run
  # the box is bare: no CA store (episode 27) and no downloader at all, so the installer exits
  # 2 having read nothing -- and the case would report "aims beside" about a destination it
  # never computed. Same shape as the CA case above: give the box what the channel needs, then
  # measure. What is measured stays the DESTINATION, and nothing else.
  if [[ ${REPO_URL:-} = https://* ]]; then
    ca_ready in_box
    in_box "command -v wget >/dev/null || command -v curl >/dev/null || \
            apt-get install -y -qq wget" >/dev/null 2>&1 || true
  fi
  rc=0; out2=$(in_box "marionnet-install.sh --fetch-only --from ${REPO_URL:-/repo} --dry-run 2>&1") || rc=$?
  dest=$(grep -i destination <<<"$out2" || true)
  if ((rc == 0)) && grep -q 'destination : /usr/share/marionnet' <<<"$out2"; then
    pass "the images of an apt machine go to /usr/share/marionnet, where its Marionnet looks"
  elif [[ -z $dest ]]; then
    # No destination line at all: the installer never got as far as choosing one, so this is
    # not the defect of episode 28 and must not be reported as it.
    fail "the installer could not read the catalogue (rc=$rc), so the destination was not measured"
    grep -iE 'error|no route|down|certificate|downloader' <<<"$out2" | head -2 | sed 's/^/      /' || true
  else
    fail "the installer aims beside the installation apt made: rc=$rc, [$dest]"
  fi

  # ------------------------------------------------------------ 7. the data packages
  # Invariant 1 of release.deb.sh: the mtime of a guest image is what UML checks against the
  # .conf of its backing file, so BOTH channels must deliver the same one. Measured here on
  # the machine, against the mtime recorded in the published tarball.
  rc=0; out2=$(in_box "apt-get install -y marionnet-kernels marionnet-fs-guignol 2>&1") || rc=$?
  if ((rc == 0)); then
    pass "\`apt install marionnet-kernels marionnet-fs-guignol': rc=0"
  else
    fail "the data packages did not install: [$(tail -n 10 <<<"$out2")]"
  fi

  img=$(in_box "ls /usr/share/marionnet/filesystems/machine-guignol-* 2>/dev/null | head -n 1" || true)
  if [[ -n $img ]]; then
    got=$(in_box "stat -c %Y '$img'")
    art=$(ls "$REPO"/filesystems_machine-guignol-*.tar.xz 2>/dev/null | head -n 1 || true)
    if [[ -z $art && -n $REPO_URL ]]; then
      # The one payload a remote run downloads, and it is worth its 16 MiB: this case is
      # invariant 1 of release.deb.sh -- the mtime UML checks -- and comparing the .deb apt
      # just installed against the tarball THE SERVER SERVES is the only way to see that the
      # two channels still agree once published. Kept for the whole `--distro all' loop.
      art=$(awk '{print $2}' "$REPO/SHA256SUMS" | grep -E '^filesystems_machine-guignol-.*\.tar\.xz$' | head -n 1)
      if [[ -n $art ]]; then
        if [[ ! -s $CACHE/$art ]]; then
          echo "--- fetching $art (the mtime case compares against it) ..."
          fetch_to "$REPO_URL/$art" "$CACHE/$art" || art=""
        fi
        [[ -z $art ]] || art=$CACHE/$art
      fi
    fi
    want=""
    if [[ -n $art ]]; then
      # No `exit' in this awk, and it is not a detail: `tar' would then be writing into a
      # closed pipe, and `set -o pipefail' turns that SIGPIPE into a failure of the whole
      # bench (measured: the run died with 141 right here). The listing is four lines long.
      want=$(tar tvf "$art" --full-time 2>/dev/null | awk '$NF ~ /machine-guignol-[0-9]+$/ && !seen {print $4" "$5; seen=1}')
      want=$(date -d "$want" +%s 2>/dev/null || echo "")
    fi
    if [[ -n $want && $got = "$want" ]]; then
      pass "the image installed by apt carries the mtime of the published tarball ($(date -d @"$got" '+%F %T'))"
    elif [[ -z $want ]]; then
      skip "could not read the mtime out of the published tarball to compare with"
    else
      fail "mtime $(date -d @"$got" '+%F %T') through apt, $(date -d @"$want" '+%F %T') in the tarball: UML would refuse the backing file"
    fi
  else
    fail "no guignol image under /usr/share/marionnet/filesystems after installing the package"
  fi

  if in_box "test -L /usr/share/marionnet/filesystems/router-guignol-$(indexed_version marionnet-fs-guignol)"; then
    pass "the router image is still a SYMBOLIC LINK, as in the tarball (episode 13)"
  else
    fail "the router image is not a link: the package copied 57 MiB twice, or lost it"
  fi

  if in_box "test -x /usr/share/marionnet/kernels/linux-$(indexed_version marionnet-kernels)"; then
    pass "the UML kernel is installed, executable, where MARIONNET_KERNELS_PATH looks"
  else
    fail "no executable kernel under /usr/share/marionnet/kernels"
  fi

  # ------------------------------------------------------------ 8. removing it
  rc=0; out3=$(in_box "apt-get remove -y marionnet 2>&1") || rc=$?
  if ((rc == 0)) && grep -q 'marionnet-sudoers.sh uninstall' <<<"$out3"; then
    pass "\`apt remove' says how to take back the rule it never granted (the prerm)"
  else
    fail "removal rc=$rc, and it did not name the sudoers rule: [$(tail -n 5 <<<"$out3")]"
  fi
  if in_box "test -f /etc/marionnet/marionnet.conf"; then
    pass "remove keeps the conffile (only purge takes a configuration away)"
  else
    fail "\`apt remove' deleted the configuration: an upgrade would lose the local prefix"
  fi
  in_box "apt-get purge -y marionnet" >/dev/null 2>&1 || true
  if in_box "test ! -e /etc/marionnet/marionnet.conf"; then
    pass "\`apt purge' does take it away"
  else
    fail "the conffile survived a purge"
  fi
fi

# ---------------------------------------------------------------- 9. the foreign architecture
#
# Measurement (a): the ONE dependency of the four which is not derived from the Makefile.
# `libc6:i386' was read on the developer's machine at episode 15a; here it faces a box which
# has not enabled the i386 architecture -- the state every fresh machine is in.
#
# Played only where the application itself installs: marionnet-kernels-i386 depends on
# `marionnet', so on a box refused for its glibc it is refused for THAT reason -- and the
# first case below would go green while naming somebody else's libc6 (measured on Debian 12,
# where the alternation `libc6:i386|libc6' passed for the wrong reason).
if [[ $INSTALLABLE = no ]]; then
  echo "--- the foreign-architecture cases are not played on this box (see above)."
else
docker run -d --name "$BOX_I386" "${MOUNT[@]}" "$DISTRO" sleep infinity >/dev/null
install_archive_key "$BOX_I386"
undocker "$BOX_I386"
ca_ready in_i386
if in_i386 "echo '$SOURCE_LINE' > /etc/apt/sources.list.d/marionnet.list && apt-get update -qq" >/dev/null 2>&1; then
  rc=0; out=$(in_i386 "apt-get install -y --no-install-recommends marionnet-kernels-i386 2>&1") || rc=$?
  if ((rc != 0)) && grep -q 'libc6:i386' <<<"$out"; then
    pass "without \`dpkg --add-architecture i386', apt refuses, and names libc6:i386"
  else
    fail "expected a refusal naming libc6:i386, got rc=$rc: [$(tail -n 8 <<<"$out")]"
  fi

  # And with the architecture enabled -- which is exactly what the package's own description
  # warns the reader it will have to do, and why the 32-bit kernel is a package of its own.
  rc=0; out=$(in_i386 "dpkg --add-architecture i386 && apt-get update -qq && \
                       apt-get install -y --no-install-recommends marionnet-kernels-i386 2>&1") || rc=$?
  if ((rc == 0)); then
    pass "with the i386 architecture enabled, marionnet-kernels-i386 installs"
    if in_i386 "test -e /lib/ld-linux.so.2 || test -e /lib32/ld-linux.so.2"; then
      pass "and the interpreter written into that kernel (/lib/ld-linux.so.2) is there"
    else
      fail "libc6:i386 came in but /lib/ld-linux.so.2 did not: the kernel could not exec"
    fi
  else
    fail "marionnet-kernels-i386 did not install even with i386 enabled: [$(tail -n 10 <<<"$out")]"
  fi
else
  skip "no network in the i386 box: the foreign architecture case is not played"
fi
fi

# ---------------------------------------------------------------- 10. the two channels meet
#
# Measurement (b) of the header, and the one which taught this episode something. The
# machine is one a user had already installed the TARBALL on: /etc/marionnet/marionnet.conf
# is there, it names a /usr/local prefix, and it belongs to no package. Then the .deb
# arrives, declaring that same path as a conffile with a different content.
#
# WHAT WAS MEASURED, and it is not what one would have guessed: an UNATTENDED `apt install'
# FAILS there. DEBIAN_FRONTEND=noninteractive governs debconf, not dpkg's conffile prompt;
# dpkg asks, finds no stdin, and leaves the package unconfigured ("end of file on stdin at
# conffile prompt"). That is Debian behaving exactly as it should -- a configuration a human
# wrote is never overwritten in silence -- and it is a REAL consequence for us, because the
# two channels of this work-stream meet on the machines of the very users who try the
# tarball first. It belongs in the INSTALL documentation, not in a force flag hidden in a
# postinst: a package which answers that question on the administrator's behalf is a package
# which throws away the prefix they chose.
#
# So both halves are measured: the refusal, and what the administrator's answer does.
if [[ $INSTALLABLE = yes ]]; then
  docker run -d --name "$BOX_CONF" "${MOUNT[@]}" "$DISTRO" sleep infinity >/dev/null
  install_archive_key "$BOX_CONF"
  undocker "$BOX_CONF"
  ca_ready in_conf
  if in_conf "echo '$SOURCE_LINE' > /etc/apt/sources.list.d/marionnet.list && apt-get update -qq" >/dev/null 2>&1; then
    # What the tarball's install.sh writes, for its default /usr/local prefix: a different
    # file, and a legitimate one -- that machine's Marionnet does live under /usr/local.
    in_conf "mkdir -p /etc/marionnet && printf '%s\n' \
               '# Installed by the Marionnet tarball install.sh.' \
               'MARIONNET_PREFIX=/usr/local/share/marionnet' > /etc/marionnet/marionnet.conf"

    rc=0; out=$(in_conf "apt-get install -y marionnet 2>&1") || rc=$?
    if ((rc != 0)) && grep -q 'conffile prompt' <<<"$out"; then
      pass "unattended, apt STOPS at the conffile question instead of overwriting /usr/local"
    else
      fail "expected the conffile prompt to stop an unattended install, got rc=$rc"
    fi
    if in_conf "grep -q '/usr/local/share/marionnet' /etc/marionnet/marionnet.conf"; then
      pass "and the prefix the user chose is still the one in the file"
    else
      fail "the local conffile was replaced without an answer being given"
    fi

    # The administrator's answer, spelled the way the INSTALL documentation will have to
    # spell it. --force-confold is "keep mine"; dpkg then leaves its own version beside it,
    # so the choice remains reversible without downloading anything again.
    rc=0; out=$(in_conf "apt-get install -y -o Dpkg::Options::=--force-confold marionnet 2>&1") || rc=$?
    if ((rc == 0)); then
      pass "with --force-confold the installation completes on such a machine"
    else
      fail "even --force-confold did not finish the installation: [$(tail -n 8 <<<"$out")]"
    fi
    if in_conf "grep -q '/usr/local/share/marionnet' /etc/marionnet/marionnet.conf"; then
      pass "the answer was honoured: the tarball's prefix survived the package"
    else
      fail "--force-confold did not keep the local file"
    fi
    if in_conf "test -f /etc/marionnet/marionnet.conf.dpkg-dist"; then
      pass "and dpkg left its own version as .dpkg-dist: switching to /usr is one cp away"
    else
      fail "the package's version of the conffile is nowhere: the user cannot switch to /usr"
    fi
  else
    skip "no network in the conffile box: the two-channel case is not played"
  fi
fi

# ----------------------------------------------------------------

if (( SKIPPED == 0 )); then
  echo "--- $DISTRO: $PASSED passed, $FAILED failed"
else
  echo "--- $DISTRO: $PASSED passed, $FAILED failed, $SKIPPED skipped"
fi
((FAILED == 0)) || exit 1
exit 0
