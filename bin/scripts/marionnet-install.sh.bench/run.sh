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
# --- The bench of the NETWORK path of bin/scripts/marionnet-install.sh.
# ---
# Episode 6 proved the script on a local mirror; that run exercises everything EXCEPT the
# two lines which differ, and those two lines are the whole point of a release server:
#
#   catalog_list  -- url branch: fetch the directory, read the names off `href="..."'
#   artifact_stream -- url branch: fetch the artefact and write it on stdout
#
# Since episode 11b neither of them names a downloader: they go through http_body /
# http_headers, which are wget OR curl. Hence a second client image, carrying curl and no
# wget, and a section which replays the whole HTTP surface on it (section 8).
#
# Episode 8 added a third thing to measure, and it is the one which makes the other two
# sturdy: a release directory publishes SHA256SUMS, which is BOTH the catalogue and the
# integrity of its artefacts. The listing is only its fallback -- so this bench serves
# directories WITH and WITHOUT that file, and the two Apache configurations which break a
# listing (an index.html shadowing it, `Options -Indexes' forbidding it) are replayed on
# both: they sink the fallback and leave the published catalogue untouched.
#
# www.marionnet.org being down, this bench stands an Apache in a container, serves it a
# synthetic release directory, and makes the script fetch from it out of a SECOND container
# which holds nothing but Debian and the script. Nothing is mounted into the client: what
# lands in its prefix got there over HTTP or did not get there at all.
#
# HTTP, not HTTPS, deliberately: a self-signed certificate would force
# `wget --no-check-certificate', that is, would make the bench measure a command DIFFERENT
# from the one production runs. The https leg is a one-line check against the real site,
# the day it comes back.
#
# Conventions of driven-sessions/README.md: 0 = PASS, 77 = SKIP, anything else = FAIL;
# one PASS:/FAIL:/SKIP: line per case, a count at the end, and the bench cleans up.
#
# Since episode 12 the CLIENT box is a parameter: the same cases are played on the four
# distributions of the roadmap (§ 5 bis of the doc). Almost nothing had to change for that,
# and the reason is a decision of episode 9c -- the arch and the glibc of the synthetic
# artefacts are asked of the client CONTAINER, never of this host, so the whole family of
# `--binary' cases follows the box on its own. The server stays what it was: httpd:2.4
# serves the same bytes whoever downloads them.
#
# Usage: run.sh [--distro IMAGE|all] [PATH-TO-marionnet-install.sh]
#        (default distro: debian:trixie-slim; default script: ../marionnet-install.sh)
# ---

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# The four boxes of the roadmap. The same list is in Makefile.d/release.binary.sh.bench/run.sh:
# a bench has to stay runnable with nothing but docker and its own directory, so the two
# drivers each carry it rather than sharing a file across two unrelated directories.
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

# `--distro all' re-plays this driver once per box, so that a red case still names ONE
# distribution. The exit code is the worst of the runs, a SKIP (77) never masking a FAIL.
if [[ $DISTRO = all ]]; then
  worst=0
  for d in "${DISTROS[@]}"; do
    echo; echo "############ $d"
    rc=0; "${BASH_SOURCE[0]}" --distro "$d" "$@" || rc=$?
    if   (( rc == 0  )); then :
    elif (( rc == 77 )); then (( worst == 0 )) && worst=77 || true
    else worst=1
    fi
  done
  echo; echo "############ the four boxes: worst exit code $worst"
  exit "$worst"
fi

SCRIPT="${1:-$HERE/../marionnet-install.sh}"

# One suffix per box, so that the images, the containers and the volumes of two distributions
# never get taken for each other.
SLUG=$(printf '%s' "$DISTRO" | tr -c 'A-Za-z0-9' '-')
NET=mrn-install-bench-net-$SLUG
IMG_SERVER=mrn-install-bench-httpd
IMG_CLIENT=mrn-install-bench-client-$SLUG
IMG_CLIENT_CURL=mrn-install-bench-client-curl-$SLUG
SRV=mrn-install-bench-server-$SLUG
SRV_NOINDEX=mrn-install-bench-server-noindex-$SLUG

PASSED=0; FAILED=0
function pass { echo "PASS: $*"; PASSED=$(( PASSED + 1 )); }
function fail { echo "FAIL: $*"; FAILED=$(( FAILED + 1 )); }
function skip_all { echo "SKIP: $*"; exit 77; }

WORK=""
function cleanup {
  docker rm -f "$SRV" "$SRV_NOINDEX" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  [[ -n $WORK && -d $WORK ]] && rm -rf -- "$WORK"
  return 0
}
trap cleanup EXIT

# ---
# --- What has to be there for the bench to mean anything.
# ---
[[ -r $SCRIPT ]] || skip_all "no such script: $SCRIPT"
command -v docker >/dev/null || skip_all "docker is not installed"
docker info >/dev/null 2>&1 || skip_all "the docker daemon does not answer (group \`docker'?)"

echo "# client box: $DISTRO"
echo "# building the two images (first run pulls httpd:2.4 and $DISTRO)"
docker build -q -t "$IMG_SERVER" -f "$HERE/Dockerfile.server" "$HERE" >/dev/null \
  || skip_all "cannot build the server image (no network to the registry?)"
docker build -q -t "$IMG_CLIENT" --build-arg BASE_IMAGE="$DISTRO" \
  -f "$HERE/Dockerfile.client" "$HERE" >/dev/null \
  || skip_all "cannot build the client image (no network to the registry?)"
# The same image with curl in place of wget: the fallback of episode 11b is measured on a
# machine which really has no wget, not on one where wget is merely not called.
docker build -q -t "$IMG_CLIENT_CURL" --build-arg BASE_IMAGE="$DISTRO" \
  -f "$HERE/Dockerfile.client.curl" "$HERE" >/dev/null \
  || skip_all "cannot build the curl client image (no network to the registry?)"

# ---
# --- A synthetic release directory, shaped like the real one.
# ---
# Shaped like it means: the four tarballs, AND the parasites which surround them on the
# real server -- the uncompressed images and kernels, their .conf/.config, a dot-file, a
# _variants directory, a README. Those are what the catalogue has to leave out, and a
# bench built on tarballs alone would not notice a parser which keeps them.
#
# The bytes are synthetic (a few hundred kiB) so that the bench costs a second, not the
# 10 GiB of the real website-repo/. A run against the real artefacts is a separate,
# manual gesture: see the README.
WORK=$(mktemp -d -t marionnet-install-bench-XXXXXX)
chmod 755 "$WORK"
MIRROR="$WORK/htdocs/download/marionnet-install.sh"
FULL="$MIRROR/1.0.x"
EMPTY="$MIRROR/no-artefact"
WITHINDEX="$MIRROR/with-index-html"
mkdir -p "$FULL" "$EMPTY" "$WITHINDEX"

STAGE="$WORK/stage"
mkdir -p "$STAGE/filesystems" "$STAGE/kernels"

# The sentinel mtime: user-mode-linux checks the mtime of a backing file against the MTIME
# field of its .conf, so an extraction which touched it would break guests silently. It is
# the invariant the header of the script insists on ("NEVER -m/--touch"), and the one thing
# here which cannot be seen by looking at the tree.
IMAGE_MTIME="2017-06-09 15:01:00"

head -c 300000 /dev/urandom > "$STAGE/filesystems/machine-guignol-18474"
echo "MTIME=$IMAGE_MTIME" > "$STAGE/filesystems/machine-guignol-18474.conf"
mkdir -p "$STAGE/filesystems/machine-guignol-18474_variants"
touch -d "$IMAGE_MTIME" "$STAGE/filesystems/machine-guignol-18474"

ln -s machine-guignol-18474 "$STAGE/filesystems/router-guignol-18474"
echo "MTIME=$IMAGE_MTIME" > "$STAGE/filesystems/router-guignol-18474.conf"
mkdir -p "$STAGE/filesystems/router-guignol-18474_variants"

head -c 120000 /dev/urandom > "$STAGE/kernels/linux-6.12.95"
chmod 755 "$STAGE/kernels/linux-6.12.95"
echo "CONFIG_UML=y" > "$STAGE/kernels/linux-6.12.95.config"
head -c 90000 /dev/urandom > "$STAGE/kernels/linux-6.12.95-i386"
chmod 755 "$STAGE/kernels/linux-6.12.95-i386"
echo "CONFIG_UML=y" > "$STAGE/kernels/linux-6.12.95-i386.config"

# --owner=root --group=root, as `make {filesystem,kernel}.prepare-to-publish' does.
function tarball {
  local out="$1"; shift
  tar cf - --owner=root --group=root -C "$STAGE" "$@" | xz -T0 -c > "$out"
}
tarball "$FULL/filesystems_machine-guignol-18474.tar.xz" \
        filesystems/machine-guignol-18474 filesystems/machine-guignol-18474.conf \
        filesystems/machine-guignol-18474_variants
tarball "$FULL/filesystems_router-guignol-18474.tar.xz" \
        filesystems/router-guignol-18474 filesystems/router-guignol-18474.conf \
        filesystems/router-guignol-18474_variants
tarball "$FULL/kernels_linux-6.12.95.tar.xz" \
        kernels/linux-6.12.95 kernels/linux-6.12.95.config
tarball "$FULL/kernels_linux-6.12.95-i386.tar.xz" \
        kernels/linux-6.12.95-i386 kernels/linux-6.12.95-i386.config

# The parasites, in both the full directory and the artefact-less one.
for d in "$FULL" "$EMPTY"; do
  cp -a "$STAGE/filesystems/machine-guignol-18474"      "$d/"
  cp -a "$STAGE/filesystems/machine-guignol-18474.conf" "$d/"
  cp -a "$STAGE/kernels/linux-6.12.95"                  "$d/"
  cp -a "$STAGE/kernels/linux-6.12.95.config"           "$d/"
  ln -sf machine-guignol-18474 "$d/router-guignol-18474"
  mkdir -p "$d/machine-guignol-18474_variants"
  echo "origin" > "$d/.machine-guignol-18474.origin"
  echo "not an artefact" > "$d/README.txt"
done

# A third served directory: the four artefacts plus one the server LISTS but will not
# serve -- an artefact left unreadable by whoever published it (mode 000, so Apache answers
# 403). It is the realistic way a release directory offers something whose size cannot be
# obtained, and the only way to exercise the "some sizes known, some not" arm of the plan.
# A dangling symlink would NOT do: mod_autoindex drops from the listing what it cannot stat
# (measured), so such a file never even reaches the catalogue.
mkdir -p "$MIRROR/one-size-unknown"
cp -a "$FULL"/*.tar.xz "$MIRROR/one-size-unknown/"
cp -a "$FULL/kernels_linux-6.12.95.tar.xz" "$MIRROR/one-size-unknown/kernels_linux-locked.tar.xz"

cp -a "$FULL"/*.tar.xz "$WITHINDEX/"
echo '<html><body>Marionnet downloads</body></html>' > "$WITHINDEX/index.html"

# Three more served directories, all of them publishing a SHA256SUMS -- written by the
# very script which writes it in production, not by a hand-rolled `sha256sum >' here: the
# bench then measures the two halves of episode 8 against each other, and a change of
# format on one side is caught instead of being copied on both.
#
#   with-sums             the four artefacts and their digests
#   with-sums-and-index   the same, plus the index.html which sinks a LISTING (case 5b)
#   with-sums-corrupt     one digest deliberately wrong: what a truncated transfer looks like
# Three levels up, not two, since episode 16 moved this bench with its script from
# useful-scripts/ to bin/scripts/. A relative path out of a directory is exactly what a move
# breaks, and it broke here: the bench SKIPped instead of running (measured).
SUMS_TOOL="$HERE/../../../Makefile.d/release.sha256sums.sh"
[[ -r $SUMS_TOOL ]] || skip_all "not found: $SUMS_TOOL (this bench needs the source tree)"

WITHSUMS="$MIRROR/with-sums"
WITHSUMS_INDEX="$MIRROR/with-sums-and-index"
WITHSUMS_BAD="$MIRROR/with-sums-corrupt"
mkdir -p "$WITHSUMS" "$WITHSUMS_INDEX" "$WITHSUMS_BAD"
cp -a "$FULL"/*.tar.xz "$WITHSUMS/"
bash "$SUMS_TOOL" --series 1.0.x --output-dir "$WITHSUMS" >/dev/null \
  || skip_all "$SUMS_TOOL could not write a SHA256SUMS"

cp -a "$WITHSUMS"/* "$WITHSUMS_INDEX/"
echo '<html><body>Marionnet downloads</body></html>' > "$WITHSUMS_INDEX/index.html"

cp -a "$FULL/filesystems_machine-guignol-18474.tar.xz" "$WITHSUMS_BAD/"
bash "$SUMS_TOOL" --series 1.0.x --output-dir "$WITHSUMS_BAD" >/dev/null
# One digit off: the artefact is intact, the digest is not -- which is what a truncated
# transfer, or a stale SHA256SUMS, looks like from the client's side. The flip has to keep
# the field 64 hex digits long (a 65th character would make the line unreadable, and an
# unread digest verifies nothing), and it has to be idempotent-proof: a `sed' of two
# substitutions applies the second to the output of the first and hands back the original
# (measured -- the case then passed for the wrong reason).
cp -a "$WITHSUMS_BAD/SHA256SUMS" "$WORK/SHA256SUMS.before-corruption"
awk '{ c = substr($0, 1, 1); print (c == "0" ? "1" : "0") substr($0, 2) }' \
  "$WORK/SHA256SUMS.before-corruption" > "$WITHSUMS_BAD/SHA256SUMS"
cmp -s "$WORK/SHA256SUMS.before-corruption" "$WITHSUMS_BAD/SHA256SUMS" \
  && skip_all "the bench failed to corrupt a digest: cases 6e/6f would prove nothing"
grep -qE '^[0-9a-f]{64}  ' "$WITHSUMS_BAD/SHA256SUMS" \
  || skip_all "the corrupted SHA256SUMS is no longer in sha256sum format"

# ---
# --- The third family: the application itself (episode 9c).
# ---
# The artefact built by Makefile.d/release.binary.sh is a NAMED ROOT holding bin/, share/
# and an install.sh which lays that down under a prefix. What the client has to get right
# is the CHOICE among the published ones and the CONTRACT with that install.sh -- not what
# a real Marionnet does once installed. So the tarballs here carry a stub install.sh which
# records how it was called; the real one is measured by Makefile.d/release.binary.sh.bench/,
# on a real tarball, as root, and there is no reason to measure it twice.
#
# The arch and the glibc are asked of the CLIENT CONTAINER, not of this host: the choice is
# made where the script runs, and a bench which named its own libc would be measuring the
# wrong machine as soon as the two differ.
CLIENT_ARCH=$(docker run --rm "$IMG_CLIENT" dpkg --print-architecture 2>/dev/null) \
  || skip_all "the client image cannot say its architecture"
CLIENT_GLIBC=$(docker run --rm "$IMG_CLIENT" bash -c \
  "ldd --version | head -n 1 | awk '{print \$NF}'" 2>/dev/null) \
  || skip_all "the client image cannot say its glibc"
[[ $CLIENT_GLIBC =~ ^[0-9]+\.[0-9]+ ]] \
  || skip_all "unreadable glibc version in the client image: [$CLIENT_GLIBC]"
CLIENT_GLIBC="${BASH_REMATCH[0]}"

BIN_CHOSEN="marionnet_9.9-r10_${CLIENT_ARCH}_glibc${CLIENT_GLIBC}"
BIN_OLDER="marionnet_9.9-r7_${CLIENT_ARCH}_glibc${CLIENT_GLIBC}"
BIN_OTHER_ARCH="marionnet_9.9-r99_zx81_glibc${CLIENT_GLIBC}"
BIN_TOO_NEW="marionnet_9.9-r99_${CLIENT_ARCH}_glibc99.9"

function binary_tarball {
  local name="$1"
  local dest="$2"
  local root="$STAGE/$name"
  rm -rf -- "$root"
  mkdir -p "$root/bin" "$root/share/marionnet"
  echo "not really a binary" > "$root/bin/marionnet.native"
  chmod 755 "$root/bin/marionnet.native"
  cat > "$root/install.sh" <<'STUB'
#!/bin/bash
# Stands for the install.sh which travels inside a real application artefact. It records
# what it was called with -- and from where -- because that IS the contract the client
# script has to honour: a named root, and `install.sh --prefix DIR' run as root.
args="$*"
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
prefix=/usr/local
while (( $# > 0 )); do case "$1" in --prefix) prefix="$2"; shift ;; esac; shift; done
mkdir -p -- "$prefix/bin"
cp -a -- "$here/bin/marionnet.native" "$prefix/bin/"
{ echo "args=$args"; echo "uid=$(id -u)"; echo "root=$here"; } > "$prefix/install.sh.witness"
STUB
  chmod 755 "$root/install.sh"
  echo "what this is, what it needs, how to remove it" > "$root/README"
  tar cf - --owner=root --group=root -C "$STAGE" "$name" | xz -T0 -c > "$dest"
}

# (a) A release which publishes the three families at once, with its digests.
WITHBIN="$MIRROR/with-sums-binary"
mkdir -p "$WITHBIN"
cp -a "$FULL"/*.tar.xz "$WITHBIN/"
for n in "$BIN_CHOSEN" "$BIN_OLDER" "$BIN_OTHER_ARCH" "$BIN_TOO_NEW"; do
  binary_tarball "$n" "$WITHBIN/$n.tar.xz"
done
bash "$SUMS_TOOL" --series 1.0.x --output-dir "$WITHBIN" >/dev/null \
  || skip_all "$SUMS_TOOL could not catalogue the application artefacts"

# (b) A release whose applications cannot run here: neither this arch, nor this glibc.
BINBAD="$MIRROR/binary-incompatible"
mkdir -p "$BINBAD"
cp -a "$WITHBIN/$BIN_OTHER_ARCH.tar.xz" "$WITHBIN/$BIN_TOO_NEW.tar.xz" "$BINBAD/"
bash "$SUMS_TOOL" --series 1.0.x --output-dir "$BINBAD" >/dev/null

# (c) The application, with a digest which does not match it.
BINCORRUPT="$MIRROR/binary-corrupt"
mkdir -p "$BINCORRUPT"
cp -a "$WITHBIN/$BIN_CHOSEN.tar.xz" "$BINCORRUPT/"
bash "$SUMS_TOOL" --series 1.0.x --output-dir "$BINCORRUPT" >/dev/null
awk '{ c = substr($0, 1, 1); print (c == "0" ? "1" : "0") substr($0, 2) }' \
  "$BINCORRUPT/SHA256SUMS" > "$WORK/SHA256SUMS.binary-corrupted"
mv -- "$WORK/SHA256SUMS.binary-corrupted" "$BINCORRUPT/SHA256SUMS"
grep -qE '^[0-9a-f]{64}  ' "$BINCORRUPT/SHA256SUMS" \
  || skip_all "the corrupted SHA256SUMS of the application is no longer in sha256sum format"

IMAGE_SHA=$(sha256sum < "$STAGE/filesystems/machine-guignol-18474" | cut -d' ' -f1)
KERNEL_SHA=$(sha256sum < "$STAGE/kernels/linux-6.12.95" | cut -d' ' -f1)
chmod -R a+rX "$WORK/htdocs"
chmod 000 "$MIRROR/one-size-unknown/kernels_linux-locked.tar.xz"   # listed, but 403

# ---
# --- The two servers, and how the client speaks to them.
# ---
docker network create "$NET" >/dev/null
docker run -d --rm --name "$SRV" --network "$NET" \
  -v "$WORK/htdocs:/usr/local/apache2/htdocs:ro" "$IMG_SERVER" >/dev/null
docker run -d --rm --name "$SRV_NOINDEX" --network "$NET" \
  -v "$WORK/htdocs:/usr/local/apache2/htdocs:ro" "$IMG_SERVER" \
  httpd-foreground -DNOINDEX >/dev/null

BASE="http://$SRV/download/marionnet-install.sh"
BASE_NOINDEX="http://$SRV_NOINDEX/download/marionnet-install.sh"

# Wait for Apache, from the client's own point of view: what matters is that the CLIENT
# can reach it, not that the host can.
ready=no
for _ in $(seq 1 30); do
  if docker run --rm --network "$NET" "$IMG_CLIENT" \
       wget -q -O /dev/null "$BASE/1.0.x/" 2>/dev/null; then ready=yes; break; fi
  sleep 0.5
done
[[ $ready = yes ]] || skip_all "the Apache container never answered"

# One client run. Nothing but the script is mounted: no mirror, no repository.
# `install' is the prefix inside the container; --prefix under /opt needs no privilege
# there, so the bench proves the fetching path and not a sudo path.
function client {
  docker run --rm --network "$NET" \
    -v "$SCRIPT:/marionnet-install.sh:ro" \
    "$IMG_CLIENT" bash /marionnet-install.sh "$@" 2>&1
}

# A client run which keeps its prefix between invocations (idempotence, --force).
VOL=mrn-install-bench-prefix-$SLUG
docker volume rm "$VOL" >/dev/null 2>&1 || true
docker volume create "$VOL" >/dev/null
function client_p {
  docker run --rm --network "$NET" \
    -v "$SCRIPT:/marionnet-install.sh:ro" -v "$VOL:/opt/mrn" \
    "$IMG_CLIENT" bash /marionnet-install.sh --prefix /opt/mrn "$@" 2>&1
}
function in_prefix {
  docker run --rm -v "$VOL:/opt/mrn" "$IMG_CLIENT" bash -c "$1" 2>&1
}

# Two more independent prefixes, named this time. Each verification case must start from
# an EMPTY one: a case which finds the artefact already in place measures nothing but the
# idempotence, and the failure it is supposed to catch never runs (measured -- that is how
# the first version of case 6e passed for the wrong reason).
VOL2=mrn-install-bench-prefix-verified-$SLUG
VOL3=mrn-install-bench-prefix-corrupt-$SLUG
VOL4=mrn-install-bench-prefix-binary-$SLUG
VOL5=mrn-install-bench-prefix-binary-corrupt-$SLUG
VOL6=mrn-install-bench-prefix-both-$SLUG
VOL7=mrn-install-bench-prefix-curl-$SLUG
for v in "$VOL2" "$VOL3" "$VOL4" "$VOL5" "$VOL6" "$VOL7"; do
  docker volume rm "$v" >/dev/null 2>&1 || true
  docker volume create "$v" >/dev/null
done
function client_in {
  local vol="$1"; shift
  docker run --rm --network "$NET" \
    -v "$SCRIPT:/marionnet-install.sh:ro" -v "$vol:/opt/mrn" \
    "$IMG_CLIENT" bash /marionnet-install.sh --prefix /opt/mrn "$@" 2>&1
}
function in_vol {
  local vol="$1"; shift
  docker run --rm -v "$vol:/opt/mrn" "$IMG_CLIENT" bash -c "$1" 2>&1
}

# The same two runners, on the image which has curl and no wget (episode 11b).
function client_curl {
  docker run --rm --network "$NET" \
    -v "$SCRIPT:/marionnet-install.sh:ro" \
    "$IMG_CLIENT_CURL" bash /marionnet-install.sh "$@" 2>&1
}
function client_curl_in {
  local vol="$1"; shift
  docker run --rm --network "$NET" \
    -v "$SCRIPT:/marionnet-install.sh:ro" -v "$vol:/opt/mrn" \
    "$IMG_CLIENT_CURL" bash /marionnet-install.sh --prefix /opt/mrn "$@" 2>&1
}
trap 'cleanup; docker volume rm "$VOL" "$VOL2" "$VOL3" "$VOL4" "$VOL5" "$VOL6" "$VOL7" \
        >/dev/null 2>&1 || true' EXIT

echo
echo "# --- 1. the catalogue read off an Apache listing"

out=$(client --fetch-only --from "$BASE/1.0.x" --list) || out="EXIT $?
$out"
# The first column of the artefact lines. Selected by NAME rather than by line number:
# a release directory without SHA256SUMS makes the script warn on stderr, and the bench
# merges stderr into stdout.
got=$(printf '%s\n' "$out" | awk '$1 ~ /^(filesystems|kernels)_/ {print $1}' | sort | tr '\n' ' ')
want="filesystems_machine-guignol-18474 filesystems_router-guignol-18474 kernels_linux-6.12.95 kernels_linux-6.12.95-i386 "
if [[ $got = "$want" ]]; then
  pass "--list over HTTP finds exactly the four artefacts of the release directory"
else
  fail "--list over HTTP: expected [$want], got [$got]"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# What a plain `href' harvest would have kept, and must not: the uncompressed image, the
# .conf, the .config, the dot-file, the _variants directory, the README -- and, FancyIndexing
# being on, the `?C=N;O=D' sorting links and the absolute Parent Directory link.
if printf '%s\n' "$out" | grep -qE '\?C=|README|\.conf|\.config|_variants|^\.|download'; then
  fail "--list over HTTP let a non-artefact through"
  printf '%s\n' "$out" | sed 's/^/      /'
else
  pass "--list over HTTP filters out the parasites AND the FancyIndexing sort links"
fi

# The size of an artefact is the one figure the user reads before accepting the transfer.
# On a mirror it is a stat(); over HTTP it is what a HEAD answers. The bench does not
# re-implement the arithmetic: it makes the TWO branches of artifact_size describe the same
# directory, and requires them to agree column for column. `?' means the source could not
# tell -- which is the honest answer, but not the one an Apache serving static files owes.
list_http=$(client --fetch-only --from "$BASE/1.0.x" --list) || true
list_dir=$(docker run --rm \
  -v "$SCRIPT:/marionnet-install.sh:ro" \
  -v "$FULL:/mirror:ro" "$IMG_CLIENT" \
  bash /marionnet-install.sh --fetch-only --from /mirror --list 2>&1) || true
cols_http=$(printf '%s\n' "$list_http" | awk '$1 ~ /^(filesystems|kernels)_/ {print $1, $2, $3}')
cols_dir=$(printf '%s\n' "$list_dir"  | awk '$1 ~ /^(filesystems|kernels)_/ {print $1, $2, $3}')
if [[ -n $cols_http && $cols_http = "$cols_dir" ]]; then
  pass "--list over HTTP announces the same sizes as the same directory read as a mirror"
else
  fail "--list sizes differ between the HTTP and the mirror branch"
  diff <(printf '%s\n' "$cols_dir") <(printf '%s\n' "$cols_http") | sed 's/^/      /' || true
fi
printf '%s\n' "$cols_http" | awk '{print $3}' | grep -q '?' \
  && fail "--list over HTTP still shows an unknown size (\`?')" \
  || pass "no artefact comes back with an unknown size over HTTP"

# And the figure carried into the plan, which is the one actually shown before the transfer.
out=$(client --fetch-only --from "$BASE/1.0.x" --dry-run --yes) || true
if printf '%s\n' "$out" | grep -qE "to install  : 4 artefact\(s\), [0-9]+(B|KiB|MiB|GiB) to transfer"; then
  pass "the plan announces a real total, neither 0B nor \`size unknown'"
else
  fail "the plan does not announce a usable total"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# An artefact whose size the server cannot give is announced as such: the total becomes a
# lower bound and says how many are missing from it, instead of quietly under-counting.
out=$(client --fetch-only --from "$BASE/one-size-unknown" --dry-run --yes) || true
if printf '%s\n' "$out" | grep -qE "at least [0-9]+(B|KiB|MiB|GiB) to transfer \(1 of unknown size\)"; then
  pass "one artefact of unknown size turns the total into an announced lower bound"
else
  fail "a partially unknown total is not announced as such"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

echo
echo "# --- 2. fetching for real, over HTTP"

out=$(client_p --fetch-only --from "$BASE/1.0.x" --yes) || { fail "the fetch failed"; printf '%s\n' "$out" | sed 's/^/      /'; }
tree=$(in_prefix 'cd /opt/mrn/share/marionnet && find . -mindepth 1 -maxdepth 2 | sort | tr "\n" " "')
for expected in ./filesystems/machine-guignol-18474 ./filesystems/router-guignol-18474 \
                ./kernels/linux-6.12.95 ./kernels/linux-6.12.95-i386; do
  if [[ " $tree " == *" $expected "* ]]; then
    pass "landed: ${expected#./}"
  else
    fail "missing after an HTTP fetch: ${expected#./} (tree: $tree)"
  fi
done

got=$(in_prefix 'sha256sum < /opt/mrn/share/marionnet/filesystems/machine-guignol-18474' | cut -d' ' -f1)
[[ $got = "$IMAGE_SHA" ]] \
  && pass "the image came through HTTP byte for byte" \
  || fail "the image differs after an HTTP fetch ($got != $IMAGE_SHA)"
got=$(in_prefix 'sha256sum < /opt/mrn/share/marionnet/kernels/linux-6.12.95' | cut -d' ' -f1)
[[ $got = "$KERNEL_SHA" ]] \
  && pass "the kernel came through HTTP byte for byte" \
  || fail "the kernel differs after an HTTP fetch ($got != $KERNEL_SHA)"

# The invariant of the chantier: NEVER -m/--touch.
want_epoch=$(date -d "$IMAGE_MTIME" +%s)
got_epoch=$(in_prefix 'stat -c %Y /opt/mrn/share/marionnet/filesystems/machine-guignol-18474')
[[ $got_epoch = "$want_epoch" ]] \
  && pass "the mtime of the backing file survived the extraction ($IMAGE_MTIME)" \
  || fail "the mtime was rewritten: $(date -d "@$got_epoch" 2>/dev/null) instead of $IMAGE_MTIME"

# The router image is a symlink whose target lives in ANOTHER tarball. Both were fetched
# here, so what this proves is that the link arrived AS a link and that its target arrived
# too -- not the extraction order, which is unobservable once both are in (measured: the
# bench is green on a build with the two passes swapped). The order is proved by the case
# below, where the machine is NOT fetched.
in_prefix 'test -L /opt/mrn/share/marionnet/filesystems/router-guignol-18474 \
        && test -e /opt/mrn/share/marionnet/filesystems/router-guignol-18474' >/dev/null 2>&1 \
  && pass "the router arrived as a symlink, and it resolves" \
  || fail "the router symlink is dangling after an HTTP fetch"

# A router kept without its machine -- neither installed nor selected -- gets a warning
# naming the link which would be laid down broken. This is the case where a silent success
# would put an unusable image on a classroom machine.
out=$(client --fetch-only --from "$BASE/1.0.x" --only router --dry-run --yes) || true
printf '%s\n' "$out" | grep -q "will be dangling" \
  && pass "a router fetched alone warns that its link would be dangling" \
  || { fail "a router fetched alone did not warn"; printf '%s\n' "$out" | sed 's/^/      /'; }

echo
echo "# --- 3. idempotence, over HTTP"

out=$(client_p --fetch-only --from "$BASE/1.0.x" --yes)
printf '%s\n' "$out" | grep -q "nothing to do" \
  && pass "a second HTTP run transfers nothing (idempotence by the name alone)" \
  || { fail "a second HTTP run did not say \`nothing to do'"; printf '%s\n' "$out" | sed 's/^/      /'; }

echo
echo "# --- 4. the two failures a release server must not confuse"

# Unreachable: no such host at all.
out=$(client --fetch-only --from "http://no-such-host.invalid/1.0.x" --list) && rc=0 || rc=$?
if (( rc != 0 )) && printf '%s\n' "$out" | grep -q "cannot read the catalogue"; then
  pass "an unreachable source dies on \`cannot read the catalogue' (rc=$rc)"
else
  fail "an unreachable source: rc=$rc, said [$out]"
fi

# Reachable, readable, but holding no artefact: a DIFFERENT message. Confusing the two
# sends the reader hunting a publication bug where there is only a server which is off.
out=$(client --fetch-only --from "$BASE/no-artefact" --list) && rc=0 || rc=$?
if (( rc != 0 )) && printf '%s\n' "$out" | grep -q "answered, but holds no"; then
  pass "a source which answers but holds no artefact says so, and not the other thing"
else
  fail "empty release directory: rc=$rc, said [$out]"
fi

echo
echo "# --- 5. the two ways an Apache stops publishing a listing"

# (a) autoindex off -> 403. This is the bench's RED case: if case 1 passed here too, it
# would mean case 1 never read the listing at all.
out=$(client --fetch-only --from "$BASE_NOINDEX/1.0.x" --list) && rc=0 || rc=$?
if (( rc != 0 )) && printf '%s\n' "$out" | grep -q "cannot read the catalogue"; then
  pass "autoindex turned off (403) is reported as an unreadable source, not as an empty one"
else
  fail "autoindex off: rc=$rc, said [$out]"
fi

# (b) an index.html in the directory: Apache serves IT instead of the listing, with a 200.
# The artefacts are there, the catalogue comes back empty. A live trap for the day the
# release directory gets a landing page -- and the reason the script's open question (b),
# `publish an index file next to the artefacts', is worth settling.
out=$(client --fetch-only --from "$BASE/with-index-html" --list) && rc=0 || rc=$?
if (( rc != 0 )) && printf '%s\n' "$out" | grep -q "answered, but holds no"; then
  pass "an index.html hiding the listing is caught (200, empty catalogue) instead of half-working"
else
  fail "index.html shadowing the listing: rc=$rc, said [$out]"
fi

echo
echo "# --- 6. the catalogue PUBLISHED, and the integrity that comes with it"

# (a) The four artefacts found without an Apache listing being involved at all, and no
# warning about a missing SHA256SUMS.
out=$(client --fetch-only --from "$BASE/with-sums" --list) || out="EXIT $?
$out"
got=$(printf '%s\n' "$out" | awk '$1 ~ /^(filesystems|kernels)_/ {print $1}' | sort | tr '\n' ' ')
if [[ $got = "$want" ]]; then
  pass "--list reads the four artefacts off the published SHA256SUMS"
else
  fail "--list from SHA256SUMS: expected [$want], got [$got]"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
if printf '%s\n' "$out" | grep -q "publishes no SHA256SUMS"; then
  fail "the fallback warning was printed although SHA256SUMS is published"
else
  pass "no fallback warning: the catalogue really came from the file"
fi
# Every artefact carries a digest, and the script says so before transferring anything.
if printf '%s\n' "$out" | awk '$1 ~ /^(filesystems|kernels)_/ {print $4}' | grep -qv '^yes$'; then
  fail "--list shows an artefact without a digest"
  printf '%s\n' "$out" | sed 's/^/      /'
else
  pass "--list announces a digest for each of the four artefacts"
fi

# (b) The index.html which empties a LISTING (case 5b) does nothing at all here. This is
# the whole argument of episode 8, measured: the two directories differ by one file.
out=$(client --fetch-only --from "$BASE/with-sums-and-index" --list) || out="EXIT $?
$out"
got=$(printf '%s\n' "$out" | awk '$1 ~ /^(filesystems|kernels)_/ {print $1}' | sort | tr '\n' ' ')
[[ $got = "$want" ]] \
  && pass "an index.html no longer hides anything: the catalogue is the published file" \
  || { fail "index.html + SHA256SUMS: expected [$want], got [$got]"; \
       printf '%s\n' "$out" | sed 's/^/      /'; }

# (c) Neither does `Options -Indexes' (case 5a): a release directory can now serve its
# artefacts with autoindex off, which is what a hardened server does by default.
out=$(client --fetch-only --from "$BASE_NOINDEX/with-sums" --list) || out="EXIT $?
$out"
got=$(printf '%s\n' "$out" | awk '$1 ~ /^(filesystems|kernels)_/ {print $1}' | sort | tr '\n' ' ')
[[ $got = "$want" ]] \
  && pass "autoindex off no longer blinds the client: the catalogue is fetched, not scraped" \
  || { fail "autoindex off + SHA256SUMS: expected [$want], got [$got]"; \
       printf '%s\n' "$out" | sed 's/^/      /'; }

# (d) A real fetch, verified while it flows.
out=$(client_in "$VOL2" --fetch-only --from "$BASE/with-sums" --only guignol-18474 --yes) || \
  { fail "the verified fetch failed"; printf '%s\n' "$out" | sed 's/^/      /'; }
printf '%s\n' "$out" | grep -q "ok, verified" \
  && pass "an artefact whose digest is published is announced as verified" \
  || { fail "the fetch did not say \`ok, verified'"; printf '%s\n' "$out" | sed 's/^/      /'; }
got=$(in_vol "$VOL2" 'sha256sum < /opt/mrn/share/marionnet/filesystems/machine-guignol-18474' | cut -d' ' -f1)
[[ $got = "$IMAGE_SHA" ]] \
  && pass "the verified image is byte for byte the one which was published" \
  || fail "the verified image differs ($got != $IMAGE_SHA)"

# (e) A digest which does not match: the run STOPS, and what had been extracted is gone.
# Leaving it would be worse than not checking at all -- the run is idempotent by the NAME
# of the target, so a corrupt image would be taken for an installed one ever after.
out=$(client_in "$VOL3" --fetch-only --from "$BASE/with-sums-corrupt" --yes) && rc=0 || rc=$?
if (( rc != 0 )) && printf '%s\n' "$out" | grep -q "sha256 mismatch"; then
  pass "a digest which does not match stops the run (rc=$rc)"
else
  fail "a wrong digest was not caught: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
in_vol "$VOL3" 'test ! -e /opt/mrn/share/marionnet/filesystems/machine-guignol-18474' \
  >/dev/null 2>&1 \
  && pass "the artefact which failed its digest was removed, not left in place" \
  || fail "a corrupt artefact stayed in the prefix"

# (f) ... and the user who knows better can still say so.
out=$(client_in "$VOL3" --fetch-only --from "$BASE/with-sums-corrupt" --yes --no-verify) && rc=0 || rc=$?
if (( rc == 0 )) && in_vol "$VOL3" \
     'test -e /opt/mrn/share/marionnet/filesystems/machine-guignol-18474' >/dev/null 2>&1; then
  pass "--no-verify installs the very artefact the digest rejected"
else
  fail "--no-verify did not install: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (g) The file we publish is in sha256sum's own format -- checked by sha256sum itself,
# inside the client container, on what it downloaded. Nothing here re-implements it.
out=$(docker run --rm --network "$NET" "$IMG_CLIENT" bash -c \
  "cd /tmp && wget -q -r -np -nH --cut-dirs=2 -R 'index.html*' '$BASE/with-sums/' \
   && cd with-sums && sha256sum -c SHA256SUMS" 2>&1) && rc=0 || rc=$?
if (( rc == 0 )); then
  pass "the published SHA256SUMS is checked by sha256sum -c on the downloaded directory"
else
  fail "sha256sum -c refused the published file: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

echo
echo "# --- 7. the third family: the application itself"

# (a) NON-REGRESSION, and it is the point of the option not being folded into the other:
# --fetch-only alone sees a release which publishes an application and installs none of it.
out=$(client --fetch-only --from "$BASE/with-sums-binary" --list) || out="EXIT $?
$out"
if printf '%s\n' "$out" | grep -q '^marionnet_'; then
  fail "--fetch-only listed the application, which is --binary's business"
  printf '%s\n' "$out" | sed 's/^/      /'
else
  got=$(printf '%s\n' "$out" | awk '$1 ~ /^(filesystems|kernels)_/ {print $1}' | sort | tr '\n' ' ')
  [[ $got = "$want" ]] \
    && pass "--fetch-only ignores the marionnet_* artefacts and still finds the other four" \
    || fail "--fetch-only on a three-family release: expected [$want], got [$got]"
fi

# (b) The choice, and the reason for every refusal, read off the names alone.
out=$(client --binary --from "$BASE/with-sums-binary" --list) || out="EXIT $?
$out"
BINLIST="$out"
# The STATE column, which is the last one and holds spaces ("not i386", "needs a newer
# glibc than 2.41"): the four fixed columns are blanked and what is left is the state.
function binary_state_of {
  printf '%s\n' "$BINLIST" \
  | awk -v n="$1" '$1 == n { $1=""; $2=""; $3=""; $4=""; sub(/^ +/, ""); print }'
}
[[ $(binary_state_of "$BIN_CHOSEN")     = "chosen"      ]] \
  && pass "the greatest revision this machine can run is the chosen one" \
  || fail "the chosen artefact is not $BIN_CHOSEN: [$(binary_state_of "$BIN_CHOSEN")]"
[[ $(binary_state_of "$BIN_OLDER")      = "superseded"  ]] \
  && pass "a lower revision is listed as superseded, not hidden" \
  || fail "the older revision is not announced as superseded: [$(binary_state_of "$BIN_OLDER")]"
[[ $(binary_state_of "$BIN_OTHER_ARCH") = "not $CLIENT_ARCH" ]] \
  && pass "an artefact built for another architecture says WHICH criterion refused it" \
  || fail "the foreign arch is not named: [$(binary_state_of "$BIN_OTHER_ARCH")]"
printf '%s\n' "$(binary_state_of "$BIN_TOO_NEW")" | grep -q "newer glibc" \
  && pass "an artefact linked against a newer glibc says so, and does not say \`arch'" \
  || fail "the glibc refusal is not named: [$(binary_state_of "$BIN_TOO_NEW")]"

# (c) The installation itself: the artefact is unpacked ASIDE and lays itself down through
# the install.sh it travels with. What is measured is that contract -- the prefix passed on,
# the identity it ran under, and the fact that the client did not become a second installer.
out=$(client_in "$VOL4" --binary --from "$BASE/with-sums-binary" --yes) && rc=0 || rc=$?
if (( rc == 0 )); then
  pass "--binary installs over HTTP (rc=0)"
else
  fail "--binary failed: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
printf '%s\n' "$out" | grep -q "ok, verified" \
  && pass "the application is verified against the published digest while it flows" \
  || { fail "the application was not announced as verified"; printf '%s\n' "$out" | sed 's/^/      /'; }
witness=$(in_vol "$VOL4" 'cat /opt/mrn/install.sh.witness 2>/dev/null' || true)
printf '%s\n' "$witness" | grep -q -- "args=--prefix /opt/mrn" \
  && pass "the embedded install.sh was called with the prefix the client was given" \
  || { fail "install.sh did not receive --prefix /opt/mrn"; printf '%s\n' "$witness" | sed 's/^/      /'; }
printf '%s\n' "$witness" | grep -q "^uid=0$" \
  && pass "the embedded install.sh ran as root" \
  || fail "install.sh did not run as root: [$(printf '%s\n' "$witness" | grep '^uid=')]"
# The line itself, not `grep -v': a three-line witness always holds a line which does not
# match, so `grep -qv' would pass whatever install.sh reported (measured).
unpacked_at=$(printf '%s\n' "$witness" | sed -n 's/^root=//p')
[[ -n $unpacked_at && $unpacked_at != /opt/mrn/* ]] \
  && pass "the tarball was unpacked ASIDE ($unpacked_at), not into the prefix it installs to" \
  || fail "the artefact was unpacked into the prefix: [$unpacked_at]"
in_vol "$VOL4" 'test -x /opt/mrn/bin/marionnet.native' >/dev/null 2>&1 \
  && pass "the application landed in <prefix>/bin/" \
  || fail "nothing in /opt/mrn/bin after --binary"
in_vol "$VOL4" 'test ! -d /opt/mrn/'"$BIN_CHOSEN" >/dev/null 2>&1 \
  && pass "the temporary unpacking left nothing behind" \
  || fail "the named root of the artefact was left in the prefix"

# (d) Idempotence, by the same rule as the other two families: the NAME of what is in place.
out=$(client_in "$VOL4" --binary --from "$BASE/with-sums-binary" --yes) && rc=0 || rc=$?
printf '%s\n' "$out" | grep -q "nothing to do" \
  && pass "a second --binary run installs nothing (idempotence by the name)" \
  || { fail "a second --binary run did not say \`nothing to do'"; printf '%s\n' "$out" | sed 's/^/      /'; }

# (e) The two pass-through options, which only exist because the embedded install.sh has them.
out=$(client_in "$VOL4" --binary --from "$BASE/with-sums-binary" --yes --force \
        --no-sudoers --no-config) && rc=0 || rc=$?
witness=$(in_vol "$VOL4" 'cat /opt/mrn/install.sh.witness 2>/dev/null' || true)
if (( rc == 0 )) && printf '%s\n' "$witness" | grep -q -- "--no-sudoers" \
   && printf '%s\n' "$witness" | grep -q -- "--no-config" \
   && printf '%s\n' "$witness" | grep -q -- "--force"; then
  pass "--force, --no-sudoers and --no-config reach the embedded install.sh"
else
  fail "the pass-through options did not reach install.sh (rc=$rc): [$witness]"
fi

# (e bis) Episode 10: the apt dependencies of the host. Three states, and the third one --
# the default -- is that NOTHING is forwarded: install.sh then does what it does on its own,
# which is to NAME what is missing and install none of it. A relay which turned the default
# into an explicit option would silently decide for the user.
out=$(client_in "$VOL4" --binary --from "$BASE/with-sums-binary" --yes --force --with-deps) && rc=0 || rc=$?
witness=$(in_vol "$VOL4" 'cat /opt/mrn/install.sh.witness 2>/dev/null' || true)
if (( rc == 0 )) && printf '%s\n' "$witness" | grep -q -- "--with-deps"; then
  pass "--with-deps reaches the embedded install.sh"
else
  fail "--with-deps did not reach install.sh (rc=$rc): [$witness]"
fi

out=$(client_in "$VOL4" --binary --from "$BASE/with-sums-binary" --yes --force --no-deps) && rc=0 || rc=$?
witness=$(in_vol "$VOL4" 'cat /opt/mrn/install.sh.witness 2>/dev/null' || true)
if (( rc == 0 )) && printf '%s\n' "$witness" | grep -q -- "--no-deps"; then
  pass "--no-deps reaches the embedded install.sh"
else
  fail "--no-deps did not reach install.sh (rc=$rc): [$witness]"
fi

out=$(client_in "$VOL4" --binary --from "$BASE/with-sums-binary" --yes --force) && rc=0 || rc=$?
witness=$(in_vol "$VOL4" 'cat /opt/mrn/install.sh.witness 2>/dev/null' || true)
if (( rc == 0 )) && ! printf '%s\n' "$witness" | grep -q -- "-deps"; then
  pass "by default neither is forwarded: install.sh keeps its own default (name, install nothing)"
else
  fail "a -deps option was forwarded although none was asked for: [$witness]"
fi

# (f) A release whose applications cannot run here. The refusal names the criterion for each,
# because an i386 machine and a glibc which is too old are not the same problem.
out=$(client_in "$VOL5" --binary --from "$BASE/binary-incompatible" --yes) && rc=0 || rc=$?
if (( rc != 0 )) \
   && printf '%s\n' "$out" | grep -q "not $CLIENT_ARCH" \
   && printf '%s\n' "$out" | grep -q "newer glibc"; then
  pass "a release with no runnable application is refused, naming both criteria (rc=$rc)"
else
  fail "an incompatible release: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (g) A digest which does not match: nothing at all is installed. Unlike the data families,
# there is nothing to remove either -- which is exactly why the tarball is unpacked aside.
out=$(client_in "$VOL5" --binary --from "$BASE/binary-corrupt" --yes) && rc=0 || rc=$?
if (( rc != 0 )) && printf '%s\n' "$out" | grep -q "sha256 mismatch"; then
  pass "a wrong digest on the application stops the run (rc=$rc)"
else
  fail "a wrong digest on the application was not caught: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
in_vol "$VOL5" 'test ! -e /opt/mrn/bin/marionnet.native' >/dev/null 2>&1 \
  && pass "nothing was installed by the run which failed its digest" \
  || fail "the application was installed although its digest did not match"

# (h) The two modes in one run, which is what a fresh machine actually asks for.
out=$(client_in "$VOL6" --fetch-only --binary --from "$BASE/with-sums-binary" \
        --only guignol-18474 --only marionnet_ --yes) && rc=0 || rc=$?
if (( rc == 0 )); then
  pass "--fetch-only --binary runs both halves in one go (rc=0)"
else
  fail "the combined run failed: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
in_vol "$VOL6" 'test -x /opt/mrn/bin/marionnet.native \
             && test -e /opt/mrn/share/marionnet/filesystems/machine-guignol-18474' \
  >/dev/null 2>&1 \
  && pass "one run left both the application and the image it needs" \
  || fail "the combined run did not leave both"

echo
echo "# --- 8. the same paths on a machine which has curl and no wget (episode 11b)"

# The whole HTTP surface of the script is four calls, and they reduce to two verbs: a BODY
# (the catalogue, the listing when there is none, an artefact) and a set of HEADERS (the
# size). The cases below exercise both through curl, on the same served directories as
# above, so that a difference between the two downloaders shows up as a difference in the
# RESULT and not merely in the command line.

# (a) The image really is what it claims to be. Without this, everything below could be
# measuring wget one more time.
if docker run --rm "$IMG_CLIENT_CURL" bash -c 'command -v curl >/dev/null && ! command -v wget >/dev/null'; then
  pass "the second client image has curl and no wget"
else
  fail "the curl client image is not what it claims: it still has wget, or has no curl"
fi

# (b) SHA256SUMS as the catalogue: a BODY fetched by curl.
out=$(client_curl --fetch-only --from "$BASE/with-sums" --list) || out="EXIT $?
$out"
if printf '%s\n' "$out" | grep -qE "^filesystems_machine-guignol-18474 +\.tar\.xz .* yes " \
   && printf '%s\n' "$out" | grep -qE "^kernels_linux-6\.12\.95 +\.tar\.xz .* yes "; then
  pass "curl reads the catalogue: SHA256SUMS names the artefacts, and their digests"
else
  fail "curl could not read the catalogue"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (c) The FALLBACK path, which is a different body and a different parse: no SHA256SUMS, so
# the names come out of Apache's listing.
out=$(client_curl --fetch-only --from "$BASE/1.0.x" --list) || out="EXIT $?
$out"
if printf '%s\n' "$out" | grep -q "publishes no SHA256SUMS" \
   && printf '%s\n' "$out" | grep -qE "^filesystems_machine-guignol-18474 +\.tar\.xz "; then
  pass "curl reads the LISTING too, when the directory publishes no SHA256SUMS"
else
  fail "curl could not read the Apache listing"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
# ...and it does so SILENTLY. The SHA256SUMS which is not there is a handled condition, not
# an incident: `wget -q' says nothing about it, and curl must not either (with -S it printed
# `curl: (22) ... 404' in the middle of a run which was going perfectly well).
if ! printf '%s\n' "$out" | grep -qi "^curl:"; then
  pass "and the 404 on the absent SHA256SUMS leaves no downloader message in the run"
else
  fail "curl printed its own error on a condition the script handles"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (d) HEADERS: a size announced, and one which cannot be. `curl -I' has to behave like
# `wget --spider -S' here, down to the lower-bound wording.
out=$(client_curl --fetch-only --from "$BASE/one-size-unknown" --dry-run --yes) || true
if printf '%s\n' "$out" | grep -qE "at least [0-9]+(B|KiB|MiB|GiB) to transfer \(1 of unknown size\)"; then
  pass "curl asks for the headers: sizes known, and the unknown one announced as such"
else
  fail "the sizes read through curl do not match what wget gives"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# (e) A real transfer, verified against the published digest -- the body which matters.
out=$(client_curl_in "$VOL7" --fetch-only --from "$BASE/with-sums" --yes) && rc=0 || rc=$?
if (( rc == 0 )); then
  pass "curl fetches for real, and the digests check out (rc=0)"
else
  fail "the fetch through curl failed: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
if docker run --rm -v "$VOL7:/opt/mrn" "$IMG_CLIENT_CURL" bash -c \
     'test -e /opt/mrn/share/marionnet/filesystems/machine-guignol-18474 \
      && test -x /opt/mrn/share/marionnet/kernels/linux-6.12.95' >/dev/null 2>&1; then
  pass "and the artefacts landed where Marionnet looks for them"
else
  fail "the curl fetch left nothing usable under the prefix"
fi

# (f) THE TRAP THIS EPISODE IS ABOUT. kernels_linux-locked.tar.xz is listed and answered
# with a 403. Without `-f', curl exits 0 and hands the error PAGE to the extractor: the run
# would go on and the digest would be the only thing left standing between an HTML page and
# the disk. The run must fail, and nothing may be laid down under that name.
out=$(client_curl_in "$VOL7" --fetch-only --from "$BASE/one-size-unknown" \
        --only linux-locked --yes) && rc=0 || rc=$?
if (( rc != 0 )); then
  pass "a 403 answered to curl stops the run: -f makes curl fail like wget"
else
  fail "a 403 went through: curl was called without -f, or its output was accepted"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
if docker run --rm -v "$VOL7:/opt/mrn" "$IMG_CLIENT_CURL" bash -c \
     'test ! -e /opt/mrn/share/marionnet/kernels/linux-locked' >/dev/null 2>&1; then
  pass "and the server's error page was not written under the artefact's name"
else
  fail "something was written for an artefact the server refused"
fi

# (g) Neither of the two. The bare image is the base of both clients, with nothing added:
# the guard has to name BOTH downloaders, or the message sends the user after the wrong one.
out=$(docker run --rm --network "$NET" -v "$SCRIPT:/marionnet-install.sh:ro" \
        debian:trixie-slim bash /marionnet-install.sh --fetch-only --from "$BASE/with-sums" --list 2>&1) \
  && rc=0 || rc=$?
if (( rc != 0 )) && printf '%s\n' "$out" | grep -qi "wget or curl"; then
  pass "with neither wget nor curl, the script names both and stops (rc=$rc)"
else
  fail "the missing-downloader guard did not name both: rc=$rc"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# ---------------------------------------------------------------- the other name (ep. 16)
#
# The same file, mounted under the name `marionnet-get-images': that IS the dispatch, since
# the script reads ${0##*/}. Mounting it twice is not a trick of the bench -- it is exactly
# what `dune install' lays down, a real .sh and the names beside it.
#
# What is measured here needs no terminal, on purpose: the menu itself is an interactive
# thing, but the three answers this name owes a SCRIPT are not, and they are the ones which
# would let a 7 GiB transfer start by surprise.
function chooser {   # runs the script under its other name
  docker run --rm -v "$SCRIPT:/marionnet-get-images:ro" -v "$FULL:/mirror:ro" \
    "$IMG_CLIENT" bash /marionnet-get-images "$@" 2>&1
}

out=$(chooser --help) || true
if grep -q 'marionnet-get-images \[OPTIONS\]' <<<"$out" && grep -q -- '--choose' <<<"$out"; then
  pass "under its other name the script introduces itself as the image chooser"
else
  fail "--help does not mention the chooser: the two names share one usage block"
fi

rc=0; out=$(chooser --binary --from /mirror) || rc=$?
if (( rc == 2 )) && grep -q 'does not install the application' <<<"$out"; then
  pass "marionnet-get-images --binary: refused (rc=2), and it names what does install it"
else
  fail "--binary was not refused under the chooser's name: rc=$rc, said [$out]"
fi

# The one that matters: no terminal, no menu -- and NO silent fallback to "everything
# published". Under the installer's own name that default is the documented behaviour, and
# the next case checks it is still there.
rc=0; out=$(chooser --from /mirror --prefix /tmp/p </dev/null) || rc=$?
if (( rc == 2 )) && grep -q 'no terminal' <<<"$out"; then
  pass "no terminal: the chooser refuses instead of fetching everything published"
else
  fail "without a terminal the chooser did not refuse: rc=$rc, said [$(tail -n 3 <<<"$out")]"
fi

rc=0; out=$(docker run --rm -v "$SCRIPT:/marionnet-install.sh:ro" -v "$FULL:/mirror:ro" \
  "$IMG_CLIENT" bash /marionnet-install.sh --fetch-only --from /mirror --prefix /tmp/p \
  --dry-run </dev/null 2>&1) || rc=$?
if (( rc == 0 )) && grep -q 'dry run' <<<"$out"; then
  pass "and under the installer's own name, --fetch-only still takes everything, unasked"
else
  fail "the installer's long-standing default changed with the chooser: rc=$rc"
fi

# The menu itself, answered `q': it must show the rows and leave without touching anything.
#
# The pty is allocated INSIDE the container, by `script', and not by `docker run -t': a
# container given -t cannot also be fed from a pipe ("the input device is not a TTY",
# measured). `script' comes with util-linux, which every one of these boxes has.
rc=0; out=$(docker run --rm -v "$SCRIPT:/marionnet-get-images:ro" -v "$FULL:/mirror:ro" \
  "$IMG_CLIENT" bash -c "printf 'q\n' | script -qec \
     'bash /marionnet-get-images --from /mirror --prefix /tmp/p' /dev/null" 2>&1) || rc=$?
if (( rc == 0 )) && grep -q 'machine-guignol' <<<"$out" && grep -q 'nothing done' <<<"$out"; then
  pass "with a terminal the menu lists the images, and \`q' leaves without fetching"
else
  fail "the menu did not come up, or did not leave cleanly: rc=$rc, said [$(tail -n 5 <<<"$out")]"
fi

echo
echo "# ---"
echo "# $DISTRO: PASS $PASSED, FAIL $FAILED"
(( FAILED == 0 )) || exit 1
exit 0
