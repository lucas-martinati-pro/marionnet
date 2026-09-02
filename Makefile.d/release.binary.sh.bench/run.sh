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
# --- The bench of the RECEIVING side of Makefile.d/release.binary.sh.
# ---
# Episode 9a built the tarball; it could not play the two gestures which make it an
# INSTALLATION, because both are root and both modify the host: writing
# /etc/marionnet/marionnet.conf, and installing the scoped sudoers rule. This bench plays
# them, in a container which is thrown away afterwards.
#
# The container carries the REQUIRED_PACKAGES_RUNTIME of the Makefile and nothing else --
# no opam, no ocaml, no build tree. So a third thing gets measured here, which nothing
# measured until now: that this dependency list is ENOUGH to start the binary. A red case
# 15 would not be a defect of the bench, it would be a hole in the list.
#
# Nothing is mounted into the container but the tarball itself, read-only, and the
# containers run with `--network none': what lands in the prefix came out of that tarball
# or did not get there at all.
#
# Conventions of driven-sessions/README.md: 0 = PASS, 77 = SKIP, anything else = FAIL;
# one PASS:/FAIL: line per case, a count at the end, and the bench cleans up. Plain bash,
# no bashbricks: like its sibling bin/scripts/marionnet-install.sh.bench/run.sh, this
# driver is a docker orchestration, and the assertions are all `grep' and exit codes.
#
# Since episode 12 the box is a parameter: the same cases are played on the four
# distributions of the roadmap (§ 5 bis of the doc). What changes from one to another is the
# glibc -- hence the gate below -- the names of the apt packages, and where bash-completion
# looks. The default is the box the previous episodes measured, so a run without arguments
# means what it has always meant.
#
# Since episode 27 the artefact may come from the SERVER instead of the local release
# directory: the argument may be an http(s) URL -- of a release directory, or of one tarball
# in it -- and the bench then measures the very bytes www.marionnet.org serves. Nothing else
# changes: what is downloaded is turned into the same local file the cases below already
# knew how to read. That is point (6) of the roadmap for this bench.
#
# Usage: run.sh [--distro IMAGE|all] [PATH-OR-URL]
#        (default distro: debian:trixie-slim; default tarball: the newest one under
#         website-repo/download/marionnet-install.sh/*/. A URL names either a release
#         directory -- the greatest revision of its SHA256SUMS is taken -- or a tarball.)
# ---

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)

# The four boxes of the roadmap. The same list is in bin/scripts/marionnet-install.sh.bench/
# run.sh: a bench has to stay runnable with nothing but docker and its own directory, so the
# two drivers each carry it rather than sharing a file across two unrelated directories.
# Image references, not nicknames: they need no table to be understood, here or in the output.
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
# case still names ONE distribution and one tarball. The exit code is the worst of the runs,
# a SKIP (77) never masking a FAIL.
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

# One suffix per box, so that the images and the containers of two distributions never get
# taken for each other -- and so that a failed run can still be looked at afterwards.
SLUG=$(printf '%s' "$DISTRO" | tr -c 'A-Za-z0-9' '-')
IMG=mrn-binary-bench-client-$SLUG
BOX=mrn-binary-bench-$SLUG
BOX_ALT=mrn-binary-bench-alt-$SLUG
# The DENUDED machine of episode 10: the same distribution as the client image, but WITHOUT
# the run-time packages -- the state of a user who downloaded the tarball and nothing else.
BARE_IMG=$DISTRO
BOX_BARE=mrn-binary-bench-bare-$SLUG
BOX_NET=mrn-binary-bench-bare-net-$SLUG
BOX_COMPL=mrn-binary-bench-completion-$SLUG

PASSED=0; FAILED=0; SKIPPED=0
function pass { echo "PASS: $*"; PASSED=$(( PASSED + 1 )); }
function fail { echo "FAIL: $*"; FAILED=$(( FAILED + 1 )); }
function skip { echo "SKIP: $*"; SKIPPED=$(( SKIPPED + 1 )); }
function skip_all { echo "SKIP: $*"; exit 77; }

BARE_UNPACK=""
function cleanup {
  docker rm -f "$BOX" "$BOX_ALT" "$BOX_BARE" "$BOX_NET" "$BOX_COMPL" >/dev/null 2>&1 || true
  test -z "$BARE_UNPACK" || rm -rf -- "$BARE_UNPACK"
  # The download of a remote run is kept for the whole `--distro all' loop and removed by
  # the invocation which created it: four boxes measure ONE artefact, not four copies of it.
  test -z "${CACHE_OWNED:-}" || rm -rf -- "$CACHE"
  return 0
}
trap cleanup EXIT

# ---
# --- Where the artefact is read from: a file, or a server (episode 27)
# ---
# The argument may be an http(s) URL, exactly as `marionnet-install.sh --from' takes a URL
# or a directory -- and for the same reason: only the two functions below know the
# difference, so a remote run exercises the real path instead of a second implementation
# of it. What arrives is written to a local file, and every case downstream stays as it was.
#
# The CHOICE, when the URL names a directory, is made in the catalogue and nowhere else:
# the greatest revision SHA256SUMS announces. Not the arch, not the glibc -- those are the
# criteria the cases below already read out of the NAME, and taking them into account here
# would silently hide the very refusal episode 12 exists to measure.
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

# The download survives the `--distro all' loop: it is created by the invocation which finds
# the variable unset, and removed by that same one (see `cleanup').
CACHE=${MRN_BENCH_CACHE:-}
if [[ -z $CACHE ]]; then
  CACHE=$(mktemp -d -- "${TMPDIR:-/tmp}/mrn-bench-cache.XXXXXXXX")
  export MRN_BENCH_CACHE=$CACHE
  CACHE_OWNED=1
fi

# --- What is being measured: a tarball made by `make release-binary'.

TARBALL="${1:-}"
if [[ -z $TARBALL ]]; then
  TARBALL=$(ls -t "$ROOT"/website-repo/download/marionnet-install.sh/*/marionnet_*.tar.xz 2>/dev/null | head -n 1) || true
fi

if [[ -n $TARBALL ]] && is_url "$TARBALL"; then
  REMOTE=$TARBALL
  if [[ $REMOTE = *.tar.xz ]]; then
    SUMS_URL=${REMOTE%/*}/SHA256SUMS; WANT=${REMOTE##*/}
  else
    SUMS_URL=${REMOTE%/}/SHA256SUMS; WANT=""
  fi
  SUMS=$CACHE/SHA256SUMS
  test -s "$SUMS" || fetch_to "$SUMS_URL" "$SUMS" || \
    skip_all "cannot read $SUMS_URL (no downloader, or the server does not answer)"
  if [[ -z $WANT ]]; then
    # Ordered on the REVISION, numerically: it is the only field which orders two artefacts
    # of one series -- the rule release.retention.sh owns, and release.rpm.sh reads the same way.
    WANT=$(awk '{print $2}' "$SUMS" | grep -E '^marionnet_.*\.tar\.xz$' \
           | sed -E 's/^marionnet_.*-r([0-9]+)_.*/\1 &/' | sort -k1,1n | tail -n 1 | cut -d' ' -f2)
    [[ -n $WANT ]] || skip_all "the catalogue of $REMOTE announces no marionnet_*.tar.xz"
  fi
  TARBALL=$CACHE/$WANT
  if [[ ! -s $TARBALL ]]; then
    echo "--- fetching $WANT from ${SUMS_URL%/SHA256SUMS} ..."
    fetch_to "${SUMS_URL%/SHA256SUMS}/$WANT" "$TARBALL" || \
      skip_all "cannot download $WANT from ${SUMS_URL%/SHA256SUMS}/"
  fi
  # The one case a remote run adds, and it is played before anything else: what the server
  # serves is what its catalogue announces. Downstream, everything is measured on these bytes.
  if (cd -- "$CACHE" && grep -E "[ *]$WANT\$" SHA256SUMS | sha256sum -c --status -); then
    pass "the tarball served by $REMOTE matches the digest of its own SHA256SUMS"
  else
    fail "$WANT does not match the digest SHA256SUMS announces for it"
  fi
fi

[[ -n $TARBALL && -f $TARBALL ]] || \
  skip_all "no binary tarball found: run \`make release-binary' first (or pass one as argument)"

command -v docker >/dev/null 2>&1 || skip_all "docker is not installed"
docker info >/dev/null 2>&1        || skip_all "the docker daemon is not reachable"

BASE=$(basename -- "$TARBALL")
ROOTDIR=${BASE%.tar.*}     # the named root of the tarball, which install.sh needs a roof of

# The dependency list is READ, never copied: single source of truth (§ 2.4 bis of the doc).
PKGS=$(make --no-print-directory -C "$ROOT" print-required-packages-runtime | tail -n 1)
[[ -n $PKGS ]] || skip_all "make print-required-packages-runtime said nothing"

echo "--- tarball : $TARBALL"
echo "--- box     : $DISTRO"
echo "--- packages: $PKGS"

# ---
# --- Is this artefact even meant for this box? (episode 12)
# ---
# The tarball is named marionnet_<version>-r<rev>_<arch>_glibc<x.y>, and that name is what
# bin/scripts/marionnet-install.sh reads in order to CHOOSE among the published ones.
# Here the choice was made by whoever passed the tarball, so this bench has to make the same
# reading itself: on a box older than the machine which built the artefact, the cases which
# start the binary would otherwise go red for a reason which is not a defect -- a dynamically
# linked binary demands a glibc at least as recent as the one it was linked against, and the
# reverse direction is what glibc's symbol versioning guarantees.
#
# The consequence is NOT to skip the whole run. Laying the files down, the configuration, the
# sudoers rule, the bash-completion and the naming of the apt dependencies are measured just
# as well on such a box -- they are precisely what changes from one distribution to another.
# Only the five cases which START the binary step aside, and one case takes their place: the
# refusal must NAME the glibc. That is what keeps the criterion read in the name a measured
# fact rather than a decoration.
function glibc_le {   # $1 <= $2, as version numbers
  [[ $1 = "$2" ]] || [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1) = "$1" ]]
}

ART_ARCH=""; ART_GLIBC=""
if [[ $ROOTDIR =~ ^marionnet_.*-r[0-9]+_([^_]+)_glibc([0-9]+\.[0-9]+)$ ]]; then
  ART_ARCH=${BASH_REMATCH[1]}; ART_GLIBC=${BASH_REMATCH[2]}
fi
BOX_ARCH=$(docker run --rm "$BARE_IMG" dpkg --print-architecture 2>/dev/null) || BOX_ARCH=""
BOX_GLIBC=$(docker run --rm "$BARE_IMG" bash -c "ldd --version | head -n 1 | awk '{print \$NF}'" 2>/dev/null) || BOX_GLIBC=""
if [[ $BOX_GLIBC =~ ^[0-9]+\.[0-9]+ ]]; then BOX_GLIBC=${BASH_REMATCH[0]}; else BOX_GLIBC=""; fi
echo "--- artefact: arch ${ART_ARCH:-?}, glibc ${ART_GLIBC:-?} / box: arch ${BOX_ARCH:-?}, glibc ${BOX_GLIBC:-?}"

# A foreign architecture is another matter entirely: nothing of this artefact would mean
# anything on such a box, not even the installation. That one is a whole-run SKIP.
[[ -z $ART_ARCH || -z $BOX_ARCH || $ART_ARCH = "$BOX_ARCH" ]] \
  || skip_all "this artefact is $ART_ARCH and the box is $BOX_ARCH: nothing to measure here"

RUNNABLE=yes
if [[ -n $ART_GLIBC && -n $BOX_GLIBC ]] && ! glibc_le "$ART_GLIBC" "$BOX_GLIBC"; then
  RUNNABLE=no
  echo "--- the artefact was linked against glibc $ART_GLIBC and this box carries $BOX_GLIBC:"
  echo "--- the cases which START the binary step aside (see the comment above)."
fi

echo "--- building the client image ..."
docker build -q -t "$IMG" --build-arg BASE_IMAGE="$DISTRO" \
  --build-arg RUNTIME_PACKAGES="$PKGS" -f "$HERE/Dockerfile.client" "$HERE" >/dev/null

docker rm -f "$BOX" "$BOX_ALT" "$BOX_BARE" "$BOX_NET" "$BOX_COMPL" >/dev/null 2>&1 || true
docker run -d --name "$BOX"     --network none -v "$TARBALL":/artefact.tar.xz:ro "$IMG" sleep infinity >/dev/null
docker run -d --name "$BOX_ALT" --network none -v "$TARBALL":/artefact.tar.xz:ro "$IMG" sleep infinity >/dev/null

# The bare boxes get the tarball ALREADY UNPACKED, from the host: a Debian which has not got
# xz-utils cannot unpack a .tar.xz, and that is precisely the machine they stand for. What
# they are here to measure is what install.sh SAYS about the missing packages, not the
# unpacking -- which case 1 measures where it belongs.
BARE_UNPACK=$(mktemp -d -- "${TMPDIR:-/tmp}/mrn-bench-bare.XXXXXXXX")
tar -C "$BARE_UNPACK" -xf "$TARBALL"
docker run -d --name "$BOX_BARE" --network none -v "$BARE_UNPACK":/srv:ro "$BARE_IMG" sleep infinity >/dev/null

# `in_box' runs a command in the nominal container, `in_alt' in the other one; both return
# the command's own exit code, so a case can measure a FAILURE as easily as a success.
function in_box { docker exec "$BOX" bash -c "$1"; }
function in_alt { docker exec "$BOX_ALT" bash -c "$1"; }
# The nominal run is what `sudo ./install.sh' gives: SUDO_USER names who gets the rule.
function in_box_as_sudo { docker exec -e SUDO_USER=tester "$BOX" bash -c "$1"; }
function in_alt_as_sudo { docker exec -e SUDO_USER=tester "$BOX_ALT" bash -c "$1"; }
# The bare box has no `tester' account: SUDO_USER names somebody who does not exist there,
# which is fine -- the sudoers step is not reached, `sudo' itself being one of the missing
# packages. That is a case below.
function in_bare_as_sudo { docker exec -e SUDO_USER=root "$BOX_BARE" bash -c "$1"; }

# Unpacked under /srv, not under /root: /root is 0700, and one case below runs install.sh
# as an ordinary user -- who must be able to REACH it in order to be refused for the right
# reason (no write access to the prefix) rather than for the wrong one (no access to /root).
# ---------------------------------------------------------------- 0. it is PUBLISHED
#
# Host-side, before anything is measured inside a container: the artefact must be the one the
# catalogue announces. Republishing under the same name used to leave the previous digest
# in SHA256SUMS (measured at episode 9b, fixed in the three publishers), and an installer
# which checks the digest while extracting REMOVES what it just fetched -- a release which
# looks published and is unusable.
SUMS=$(dirname -- "$TARBALL")/SHA256SUMS
if test -f "$SUMS"; then
  if (cd -- "$(dirname -- "$TARBALL")" && grep -F -- "$BASE" SHA256SUMS | sha256sum -c --status -); then
    pass "the catalogue announces the digest of THIS tarball, not of a previous one"
  else
    fail "SHA256SUMS does not match $BASE: the release announces an artefact which is gone"
  fi
else
  echo "--- no SHA256SUMS beside the tarball: the catalogue case is not played"
fi

UNPACKED=/srv/$ROOTDIR
INSTALL=$UNPACKED/install.sh

# ---------------------------------------------------------------- 1. it unpacks at all

if out=$(in_box "cd /srv && tar xf /artefact.tar.xz 2>&1" ) && in_box "test -d $UNPACKED/bin && test -d $UNPACKED/share"; then
  pass "the tarball unpacks on a bare $DISTRO, under its named root ($ROOTDIR/)"
else
  fail "the tarball did not unpack with the tools of a bare $DISTRO: [$out]"
  echo "     (a missing xz would show here: the README tells the user to run \`tar xf')"
  echo "--- nothing else can be measured; count: $PASSED passed, $FAILED failed"
  exit 1
fi

# ---------------------------------------------------------------- 2. it introduces itself

if in_box "$INSTALL --help" >/dev/null 2>&1; then
  pass "install.sh --help exits 0 (and prints one usage, not two)"
else
  fail "install.sh --help failed"
fi
if [[ $(in_box "$INSTALL --help" | grep -c '^Usage:') -eq 1 ]]; then
  pass "install.sh --help prints exactly one Usage: line"
else
  fail "install.sh --help printed several Usage: lines (the sed range lost its anchor)"
fi

# ---------------------------------------------------------------- 3. the three guards

rc=0; out=$(in_box "cp $INSTALL /tmp/install.sh && cd /tmp && ./install.sh 2>&1") || rc=$?
if ((rc == 2)) && grep -q 'not an unpacked Marionnet tarball' <<<"$out"; then
  pass "run outside an unpacked tarball: rc=2 and says so"
else
  fail "run outside an unpacked tarball: rc=$rc, said [$out]"
fi

rc=0; out=$(in_box "runuser -u tester -- $INSTALL 2>&1") || rc=$?
if ((rc == 2)) && grep -q 'run me with sudo' <<<"$out"; then
  pass "run without root: rc=2 and points at sudo"
else
  fail "run without root: rc=$rc, said [$out]"
fi

# Played on a throw-away prefix, and with --no-config, so that the container the nominal
# run will use is still untouched: this case is about the LAST step, the sudoers one.
rc=0; out=$(in_box "env -u SUDO_USER -u USER $INSTALL --prefix /tmp/p5 --no-config 2>&1") || rc=$?
if ((rc == 2)) && grep -q 'cannot tell which user to grant' <<<"$out"; then
  pass "no SUDO_USER and no USER: refuses to guess who the rule is for"
else
  fail "no SUDO_USER and no USER: rc=$rc, said [$out]"
fi

# ---------------------------------------------------------------- 4. the nominal install

if out=$(in_box_as_sudo "$INSTALL 2>&1"); then
  pass "sudo ./install.sh into /usr/local: rc=0"
else
  fail "the nominal install failed: [$out]"
fi

# The expected count is READ FROM THE TARBALL, never written here: episode 31 was
# a red case latent for two episodes because a number carved into this bench had
# gone stale. What the case really asserts is that install.sh lays down in
# /usr/local/bin everything the artefact carries in its own bin/ -- and that it
# drops nothing on the way.
names=$(in_box "ls /usr/local/bin | wc -l")
expected=$(in_box "ls $UNPACKED/bin | wc -l")
if [[ $names -eq $expected ]]; then
  pass "$names names in /usr/local/bin -- exactly what the artefact carries in its bin/"
else
  fail "$names names in /usr/local/bin, but the artefact carries $expected"
fi

missing=""
for n in marionnet marionnet.native marionnet-sudoers.sh marionnet-cleanup marionnet-natbridge.sh \
         marionnet-lanbridge.sh marionnet-dnsmasq.sh marionnet-ipv6.sh mrnctl mrn-verify; do
  in_box "test -x /usr/local/bin/$n" || missing="$missing $n"
done
if [[ -z $missing ]]; then
  pass "the companion scripts are there under their BARE names, executable"
else
  fail "missing (or not executable) in /usr/local/bin:$missing"
fi

foreign=$(in_box "find /usr/local/bin /usr/local/share/marionnet ! -user root -o ! -group root | head -n 5" || true)
if [[ -z $foreign ]]; then
  pass "everything installed belongs to root:root"
else
  fail "installed files not owned by root:root: [$foreign]"
fi

# --- The Bash completion of the channel clients (episode 11a). It is NOT in bin/: it is
# --- sourced, not run, and bash-completion loads it ON DEMAND -- by looking for a file
# --- CALLED like the command being typed. Hence one file per name, which is what these
# --- three cases measure: the twelve names, the fact that sourcing one really arms the
# --- completion OF THAT NAME, and that they are root-owned like everything else.
COMPL=/usr/local/share/bash-completion/completions
missing=""
for n in marionnet-ctl.sh marionnet-ctl mrnctl mrn-control \
         marionnet-check.sh marionnet-check mrn-check mrnck mrn2sh \
         marionnet-verify.sh marionnet-verify mrn-verify; do
  in_box "test -s $COMPL/$n" || missing="$missing $n"
done
if [[ -z $missing ]]; then
  pass "the Bash completion is installed under the 12 names the clients answer to"
else
  fail "missing in $COMPL:$missing"
fi

# Sourcing mrnctl must arm `mrnctl' itself -- not only marionnet-ctl. A single installed
# file would pass the previous case for one name and fail this one for the eleven others.
if in_box ". $COMPL/mrnctl && complete -p mrnctl >/dev/null 2>&1 && complete -p mrn2sh >/dev/null 2>&1"; then
  pass "sourcing one of them arms the completion of that very name (and of its siblings)"
else
  fail "sourcing $COMPL/mrnctl did not arm the completion: [$(in_box ". $COMPL/mrnctl; complete -p mrnctl 2>&1" || true)]"
fi

foreign=$(in_box "test -d $COMPL || echo NO-SUCH-DIRECTORY; find $COMPL ! -user root -o ! -group root 2>/dev/null | head -n 5" || true)
if [[ -z $foreign ]]; then
  pass "the completion files belong to root:root too"
else
  fail "completion files not owned by root:root: [$foreign]"
fi

# --- The delivered documentation (episode 14). Until then, doc-src/ was installed by NO
# --- channel at all, while the guides it holds are written for a reader who never cloned
# --- anything -- and the teacher's guide tells an AI agent to READ a file which did not
# --- exist on the machine. Four cases: it is there whole, its example scripts kept the
# --- executable bit dune cannot carry, the documents cite each other by paths which resolve
# --- WHERE THEY NOW SIT, and they belong to root like everything else.
DOC=/usr/local/share/doc/marionnet
# HOW MANY files is a FACT WHICH MOVES, so it is read where it is decided -- doc-src/dune,
# which names them one by one -- and not written here. It had been written here: the number
# said 26 since episode 14 while episode 29 had added INSTALL.md, so this case was latently
# red and nobody had run it since. Same reasoning as the runtime package list above, read
# through `make' rather than recopied. An exact count is still what we want: it is what
# catches a file which stops arriving.
# The pattern anchors on a STANZA and not on the words: the header comment of that file
# explains the `as doc/marionnet/...' form, and a naive grep counted the explanation too.
EXPECTED_DOC=$(grep -cE '^[[:space:]]*\([^;]* as doc/marionnet/' -- "$ROOT/doc-src/dune" || true)
n=$(in_box "find $DOC -type f 2>/dev/null | wc -l" || echo 0)
if [[ ${EXPECTED_DOC:-0} -gt 0 && $n -eq $EXPECTED_DOC ]]; then
  pass "the $n files doc-src/dune names are under $DOC"
else
  fail "$n file(s) of documentation under $DOC, expected $EXPECTED_DOC (doc-src/dune)"
fi

# The tree is preserved, and that is not cosmetic: the guides cite each other by relative
# path, and the lab is a directory whose scripts refer to their siblings.
missing=""
for f in teacher-guide.md exam-mode.md lab-design-skill.md project-format-v3.md \
         scripting/README.md scripting/examples/01-build-a-lab.sh \
         labs/session-7/README.md labs/session-7/key.mrv labs/session-7/lab.mrn; do
  in_box "test -s $DOC/$f" || missing="$missing $f"
done
if [[ -z $missing ]]; then
  pass "the documents sit where they cite each other from (the tree is preserved)"
else
  fail "missing under $DOC:$missing"
fi

# dune installs data files 0644, measured -- so each channel restores this bit. These
# scripts are handed out to be RUN: a lab a teacher has to chmod first is a lab that does
# not run as it is. And the documents beside them must NOT have become executable.
notx=$(in_box "test -d $DOC/labs/session-7 && test -d $DOC/scripting/examples || echo NO-SUCH-DIRECTORY; find $DOC/labs/session-7 $DOC/scripting/examples -name '*.sh' ! -perm -u+x 2>/dev/null | head -n 5" || true)
x_md=$(in_box "find $DOC -name '*.md' -perm -u+x | head -n 5" || true)
if [[ -z $notx && -z $x_md ]]; then
  pass "the 14 example scripts are executable, and the documents are not"
else
  fail "executable bit wrong under $DOC: not executable [$notx], wrongly executable [$x_md]"
fi

# The citations resolve HERE. Before episode 14 they were written `doc-src/...', i.e.
# relative to the root of a clone -- a path this machine has no reason to own. A leftover
# would send an installed reader (or the agent the teacher's guide instructs) nowhere.
# What is hunted is a CITATION, not the word: three documents legitimately say where they
# live in the sources ("`doc-src/' in the sources"), and that sentence is the very thing
# which tells the reader how to read the relative paths.
# Guarded on the directory existing: a grep over nothing finds nothing, and this case
# would have gone green on the very tree it was written to condemn.
leftover=$(in_box "test -d $DOC || echo NO-SUCH-DIRECTORY; grep -rlE 'doc-src/(teacher-guide|exam-mode|lab-design-skill|project-format-v3|labs/session-7|scripting/(README|examples))' $DOC 2>/dev/null | head -n 5" || true)
if [[ -z $leftover ]]; then
  pass "no document points back at doc-src/: the relative paths resolve where they landed"
else
  fail "still citing doc-src/ under $DOC: [$leftover]"
fi

foreign=$(in_box "test -d $DOC || echo NO-SUCH-DIRECTORY; find $DOC ! -user root -o ! -group root 2>/dev/null | head -n 5" || true)
if [[ -z $foreign ]]; then
  pass "the documentation belongs to root:root too"
else
  fail "documentation not owned by root:root: [$foreign]"
fi

# ---------------------------------------------------------------- 5. /etc/marionnet/marionnet.conf

CONF=/etc/marionnet/marionnet.conf
if in_box "grep -q '^MARIONNET_PREFIX=/usr/local/share/marionnet\$' $CONF"; then
  pass "$CONF written, and it names the prefix the install used"
else
  fail "$CONF missing or not naming /usr/local/share/marionnet: [$(in_box "cat $CONF 2>&1" || true)]"
fi

in_box "echo '# SENTINEL' >> $CONF"
out=$(in_box_as_sudo "$INSTALL 2>&1")
if in_box "grep -q SENTINEL $CONF" && grep -q 'exists already, left untouched' <<<"$out"; then
  pass "a second run leaves an existing configuration alone, and says it"
else
  fail "a second run did not preserve the configuration, or did not warn: [$out]"
fi

out=$(in_box_as_sudo "$INSTALL --force 2>&1")
if ! in_box "grep -q SENTINEL $CONF"; then
  pass "--force rewrites the configuration"
else
  fail "--force left the previous configuration in place: [$out]"
fi

# ---------------------------------------------------------------- 6. the sudoers rule

if in_box "test -f /etc/sudoers.d/marionnet"; then
  pass "the sudoers rule is installed, in its own file /etc/sudoers.d/marionnet"
else
  fail "no /etc/sudoers.d/marionnet after a nominal install"
fi
if in_box "visudo -c >/dev/null"; then
  pass "visudo -c accepts the whole of /etc/sudoers.d after the install"
else
  fail "visudo -c rejects the sudoers directory after the install"
fi
if in_box "sudo -l -U tester 2>/dev/null | grep -q 'mtap'"; then
  pass "the rule is granted TO the user sudo named (tester), and mentions the mtap taps"
else
  fail "tester was not granted the tap commands: [$(in_box "sudo -l -U tester 2>&1" || true)]"
fi
# Block (a) alone: the bridges are granted later, by the end user, from the GUI.
if in_box "test ! -e /etc/sudoers.d/marionnet-natbridge && test ! -e /etc/sudoers.d/marionnet-lanbridge"; then
  pass "only block (a) is granted at install time: no natbridge, no lanbridge file"
else
  fail "install.sh granted a bridge block it should have left to the end user"
fi

# ---------------------------------------------------------------- 7. the binary starts HERE

if [[ $RUNNABLE = yes ]]; then
  if out=$(in_box "marionnet.native --help 2>&1"); then
    pass "marionnet.native --help runs on a $DISTRO carrying only REQUIRED_PACKAGES_RUNTIME"
  else
    fail "the binary does not start with the published dependency list: [$out]"
    echo "     (this is a hole in REQUIRED_PACKAGES_RUNTIME, not a defect of the bench)"
  fi

  # The name the delivered documentation actually types (`marionnet --exam',
  # `marionnet -r lab.mar', `marionnet --control-socket ...'). It is a symlink to
  # marionnet.native, so this case measures that install.sh KEPT it a symlink --
  # `cp' without -a would have dereferenced it into a second 27 MiB copy, which
  # would still pass a naive `--help' test but not `test -L' above.
  if out=$(in_box "marionnet --help 2>&1"); then
    pass "the bare name 'marionnet' runs the same program"
  else
    fail "the bare name 'marionnet' does not run: [$out]"
  fi

  if out=$(in_box "marionnet.native --paths 2>&1"); then
    if grep -q '^filesystems *: /usr/local/share/marionnet/filesystems' <<<"$out"; then
      pass "--paths reads the installed configuration"
    else
      fail "--paths does not point at the installed prefix: [$out]"
    fi
  else
    fail "marionnet.native --paths failed: [$out]"
  fi
else
  # The case which REPLACES the two above on a box too old for this artefact. It is not a
  # weaker version of them: it measures the very fact the name-borne criterion rests on --
  # that such a binary really does refuse to start, and says why.
  out=$(in_box "marionnet.native --help 2>&1") && rc=0 || rc=$?
  if (( rc != 0 )) && grep -qiE "GLIBC_|version .GLIBC|not found" <<<"$out"; then
    pass "linked against glibc $ART_GLIBC, the binary refuses to start on glibc $BOX_GLIBC, naming it"
  else
    fail "on glibc $BOX_GLIBC the artefact of glibc $ART_GLIBC behaved unexpectedly: rc=$rc, [$out]"
  fi
  skip "--paths reads the installed configuration (the binary cannot run on this box)"
fi

# ---------------------------------------------------------------- 8. the two refusals

in_box "marionnet-sudoers.sh uninstall >/dev/null 2>&1" || true
if in_box "test ! -e /etc/sudoers.d/marionnet" && in_box "visudo -c >/dev/null"; then
  pass "marionnet-sudoers.sh uninstall takes the rule back out (README's own recipe)"
else
  fail "the rule survived marionnet-sudoers.sh uninstall"
fi

out=$(in_box_as_sudo "$INSTALL --no-sudoers --force 2>&1")
if in_box "test ! -e /etc/sudoers.d/marionnet"; then
  pass "--no-sudoers installs the files and grants nothing"
else
  fail "--no-sudoers granted the rule anyway: [$out]"
fi

in_box "rm -f $CONF"
out=$(in_box_as_sudo "$INSTALL --no-sudoers --no-config 2>&1")
if in_box "test ! -e $CONF"; then
  pass "--no-config installs the files and writes no configuration"
else
  fail "--no-config wrote the configuration anyway: [$out]"
fi

# ---------------------------------------------------------------- 9. another prefix

ALT=/opt/marionnet
in_alt "cd /srv && tar xf /artefact.tar.xz" >/dev/null
out=$(in_alt_as_sudo "$INSTALL --prefix $ALT 2>&1") || fail "the install under $ALT failed: [$out]"

if in_alt "grep -q '^MARIONNET_PREFIX=$ALT/share/marionnet\$' $CONF"; then
  pass "under an unusual prefix, the configuration names THAT prefix"
else
  fail "the configuration does not follow the prefix: [$(in_alt "cat $CONF 2>&1" || true)]"
fi

if grep -q 'is not in your PATH' <<<"$out"; then
  pass "a prefix outside the PATH is announced (the companions are found by bare name)"
else
  fail "a prefix outside the PATH went unmentioned: [$out]"
fi

if ! in_alt "command -v marionnet-natbridge.sh >/dev/null 2>&1"; then
  pass "and indeed, nothing of $ALT/bin is reachable by its bare name yet"
else
  fail "$ALT/bin turned out to be on the PATH: the previous case measures nothing"
fi

# The durable trap of episode 9a, written down as a case so that fixing it is a decision
# and not a surprise: everything relocates except `binaries', which stays at the prefix
# COMPILED into bin/meta.ml (bin/initialization.ml:472). Harmless -- nothing reads it --
# but it is the one line of --paths which lies when the binary is relocated.
if [[ $RUNNABLE != yes ]]; then
  skip "--paths under an unusual prefix (the binary cannot run on this box)"
elif out=$(in_alt "$ALT/bin/marionnet.native --paths 2>&1"); then
  relocated=$(grep -c "^\(filesystems\|kernels\|gui\) *: $ALT/share/marionnet" <<<"$out" || true)
  if ((relocated == 3)) && grep -q '^binaries *: /usr/local/bin$' <<<"$out"; then
    pass "--paths relocates filesystems/kernels/gui and STILL prints the compiled 'binaries' (ep. 9a trap)"
  else
    fail "--paths behaved differently than episode 9a measured: [$out]"
  fi
else
  fail "marionnet.native --paths failed under $ALT: [$out]"
fi

# ---------------------------------------------------------------- 10. what it NAMES: the
# ---                                                                  apt dependencies
#
# Episode 10. Until here the bench measured a machine which HAS the run-time packages; the
# machine a user actually downloads onto has not. What install.sh owes it is a NAME for
# what is missing -- not an installation, unless asked with --with-deps: laying an
# application down and pulling a dozen packages in are two gestures, and only the first one
# was asked for.
#
# The list travels as data, REQUIRED-PACKAGES-RUNTIME beside install.sh, generated from
# REQUIRED_PACKAGES_RUNTIME of the Makefile. Host-side first: a second exemplary of that
# list, drifting from the Makefile, is the very defect episode 1 repaired.

# `|| true' throughout this section: an artefact from BEFORE episode 10 must make these
# cases go red, not make the bench abort halfway (measured: without it, a missing file or
# an unknown option stopped the run under `set -e', which reads as a bench defect).
LIST_IN_TARBALL=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' -- "$BARE_UNPACK/$ROOTDIR/REQUIRED-PACKAGES-RUNTIME" 2>/dev/null | sort | tr '\n' ' ' || true)
LIST_IN_MAKEFILE=$(printf '%s\n' $PKGS | sort | tr '\n' ' ')
if [[ -n $LIST_IN_TARBALL && $LIST_IN_TARBALL = "$LIST_IN_MAKEFILE" ]]; then
  pass "the tarball carries REQUIRED-PACKAGES-RUNTIME, and it IS the Makefile's list"
else
  fail "the list in the tarball is not the Makefile's: [$LIST_IN_TARBALL] vs [$LIST_IN_MAKEFILE]"
fi

# On the machine which has everything: it must say so, and say nothing else.
out=$(in_box_as_sudo "$INSTALL --no-sudoers --no-config --force 2>&1" || true)
if grep -q 'apt run-time dependencies: nothing to do' <<<"$out"; then
  pass "on a machine carrying the list: 'nothing to do' and no warning"
else
  fail "the complete machine was not recognised as complete: [$out]"
fi

# On the denuded machine: rc=0 -- the application IS installed -- and the missing packages
# are named, with the command which installs them.
rc=0; out=$(in_bare_as_sudo "$INSTALL 2>&1") || rc=$?
if ((rc == 0)); then
  pass "on a denuded machine: install.sh still exits 0 (a missing package is not a failure)"
else
  fail "install.sh refused to install on a denuded machine: rc=$rc, [$out]"
fi
if grep -q 'apt package(s) Marionnet needs are missing' <<<"$out" \
   && grep -q 'libgtksourceview-3.0-1' <<<"$out" \
   && grep -q 'sudo apt install' <<<"$out"; then
  pass "it names what is missing, libgtksourceview-3.0-1 included, and the apt command"
else
  fail "the missing packages were not named: [$out]"
fi
if in_bare_as_sudo "test -x /usr/local/bin/marionnet.native"; then
  pass "and the application is laid down all the same"
else
  fail "nothing was installed on the denuded machine"
fi

# `sudo' is one of the missing packages, so visudo is not there either: the sudoers step
# has to be SKIPPED, and say how to replay it. Without this, install.sh would die on
# visudo -- with a message about visudo, not about the dependencies.
if grep -q 'skipping the sudoers rule' <<<"$out" \
   && grep -q 'marionnet-sudoers.sh install' <<<"$out" \
   && in_bare_as_sudo "test ! -e /etc/sudoers.d/marionnet"; then
  pass "the 'sudo' package being missing, the sudoers step is skipped and says how to replay it"
else
  fail "the sudoers step did not step aside on a machine without sudo: [$out]"
fi

# The contre-preuve of case 15: the very binary which starts on the complete machine must
# NOT start here. If it did, the dependency list would be naming more than it needs.
# On a box too old for this artefact it would pass for the WRONG reason -- the binary does
# not start there whatever the packages -- so it steps aside rather than lying.
if [[ $RUNNABLE != yes ]]; then
  skip "the contre-preuve of the dependency list (the binary cannot run on this box at all)"
elif in_bare_as_sudo "/usr/local/bin/marionnet.native --help >/dev/null 2>&1"; then
  fail "the binary starts WITHOUT the run-time packages: the list names too much"
else
  pass "the binary does not start there: the packages it names are really needed"
fi

# --no-deps: the look itself is what is skipped.
rc=0; out=$(in_bare_as_sudo "$INSTALL --no-deps --force 2>&1") || rc=$?
if ((rc == 0)) && ! grep -qE 'apt (package|run-time)' <<<"$out"; then
  pass "--no-deps: install.sh says nothing about apt at all, and still exits 0"
else
  fail "--no-deps: rc=$rc, said [$out]"
fi

# --with-deps WITHOUT a network: apt cannot work, and that is still not a failure of the
# installation. This box has --network none, so the case is free.
rc=0; out=$(in_bare_as_sudo "$INSTALL --with-deps --force 2>&1") || rc=$?
if ((rc == 0)) && grep -q 'installing .* missing apt package' <<<"$out" \
   && grep -qE 'apt (could not install them|-get update failed)' <<<"$out"; then
  pass "--with-deps with no network: apt fails, install.sh warns and exits 0"
else
  fail "--with-deps without a network: rc=$rc, [$out]"
fi

# --with-deps WITH a network: the only case of this bench which needs the outside world, so
# it is played only if apt can reach a mirror -- and skipped out loud otherwise, the way
# the SHA256SUMS case is.
docker run -d --name "$BOX_NET" -v "$BARE_UNPACK":/srv:ro "$BARE_IMG" sleep infinity >/dev/null
if docker exec "$BOX_NET" bash -c 'apt-get update -qq' >/dev/null 2>&1; then
  rc=0; out=$(docker exec -e SUDO_USER=root "$BOX_NET" bash -c "$INSTALL --with-deps 2>&1") || rc=$?
  if ((rc == 0)) && ! grep -q 'apt package(s) Marionnet needs are missing' <<<"$out"; then
    pass "--with-deps with a network: the packages are installed, nothing is left missing"
  else
    fail "--with-deps did not install them: rc=$rc, [$out]"
  fi
  if [[ $RUNNABLE != yes ]]; then
    skip "the binary starting after --with-deps (it cannot run on this box)"
  elif docker exec "$BOX_NET" bash -c '/usr/local/bin/marionnet.native --help >/dev/null 2>&1'; then
    pass "and the binary now starts on the machine which had nothing: 9a -> 10 in one gesture"
  else
    fail "the binary still does not start after --with-deps: [$(docker exec "$BOX_NET" bash -c '/usr/local/bin/marionnet.native --help 2>&1' || true)]"
  fi
  if docker exec "$BOX_NET" bash -c 'test -e /etc/sudoers.d/marionnet && visudo -c >/dev/null'; then
    pass "sudo having arrived with the others, the sudoers rule is granted in the same run"
  else
    fail "the sudoers rule was not granted although sudo was installed in the same run"
  fi
else
  echo "--- no network in the containers: the three --with-deps cases are not played"
fi

# ---------------------------------------------------------------- 11. the completion,
# ---                                                                  LOADED ON DEMAND
#
# Episode 11a installed twelve files, and the cases of section 4 prove that SOURCING one of
# them arms the completion of that very name. What they cannot prove is the gesture a user
# actually makes: typing `mrnctl <TAB>' in a shell which sourced nothing. bash-completion
# loads on demand, by looking for a file CALLED like the command being typed, under
# ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}/bash-completion/completions -- and whether
# /usr/local/share is in that default is precisely the kind of thing which could differ from
# one distribution to another. Hence this case, played on each of the four boxes: it is what
# turns the `share_root' section of the dune stanza from a plausible choice into a measured one.
#
# It needs the `bash-completion' package, which is NOT a dependency of Marionnet and has no
# business in the client image -- so a box of its own, with a network, carrying that single
# package. Skipped out loud when no mirror can be reached, like the --with-deps cases above.
docker run -d --name "$BOX_COMPL" -v "$BARE_UNPACK":/srv:ro "$DISTRO" sleep infinity >/dev/null
if docker exec "$BOX_COMPL" bash -c \
     'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        --no-install-recommends bash-completion' >/dev/null 2>&1; then
  docker exec -e SUDO_USER=root "$BOX_COMPL" \
    bash -c "$INSTALL --no-sudoers --no-config --no-deps" >/dev/null 2>&1 || true
  # `_comp_load' is the loader of bash-completion 2.12+, `_completion_loader' the older name:
  # the four boxes do not all carry the same version, and the case is about WHERE it looks,
  # not about what it is called.
  # What is checked is the NAME of the function armed, not the mere fact that something was:
  # bash-completion's loader falls back to `complete -o default -F _minimal' for a command it
  # knows nothing about, so `complete -p mrnctl' succeeds on a box where nothing of ours was
  # installed at all (measured -- the first version of this case passed for that wrong reason).
  if docker exec "$BOX_COMPL" bash -c '
        . /usr/share/bash-completion/bash_completion 2>/dev/null || exit 3
        { _comp_load mrnctl || _completion_loader mrnctl ; } >/dev/null 2>&1
        complete -p mrnctl 2>/dev/null | grep -q _marionnet_ctl_completion'; then
    pass "bash-completion finds the completion of \`mrnctl' under the prefix, unprompted"
  else
    fail "typing \`mrnctl <TAB>' would arm nothing on $DISTRO: the prefix is not searched"
  fi
else
  echo "--- no network in the containers: the on-demand completion case is not played"
fi

# ----------------------------------------------------------------

if (( SKIPPED == 0 )); then
  echo "--- $DISTRO: $PASSED passed, $FAILED failed"
else
  echo "--- $DISTRO: $PASSED passed, $FAILED failed, $SKIPPED skipped"
fi
((FAILED == 0)) || exit 1
exit 0
