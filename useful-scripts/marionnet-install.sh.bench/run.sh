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
# --- The bench of the NETWORK path of useful-scripts/marionnet-install.sh.
# ---
# Episode 6 proved the script on a local mirror; that run exercises everything EXCEPT the
# two lines which differ, and those two lines are the whole point of a release server:
#
#   catalog_list  -- url branch: wget the directory, read the names off `href="..."'
#   artifact_stream -- url branch: wget -O -
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
# Usage: run.sh [PATH-TO-marionnet-install.sh]      (default: ../marionnet-install.sh)
# ---

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="${1:-$HERE/../marionnet-install.sh}"

NET=mrn-install-bench-net
IMG_SERVER=mrn-install-bench-httpd
IMG_CLIENT=mrn-install-bench-client
SRV=mrn-install-bench-server
SRV_NOINDEX=mrn-install-bench-server-noindex

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

echo "# building the two images (first run pulls httpd:2.4 and debian:trixie-slim)"
docker build -q -t "$IMG_SERVER" -f "$HERE/Dockerfile.server" "$HERE" >/dev/null \
  || skip_all "cannot build the server image (no network to the registry?)"
docker build -q -t "$IMG_CLIENT" -f "$HERE/Dockerfile.client" "$HERE" >/dev/null \
  || skip_all "cannot build the client image (no network to the registry?)"

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

cp -a "$FULL"/*.tar.xz "$WITHINDEX/"
echo '<html><body>Marionnet downloads</body></html>' > "$WITHINDEX/index.html"

IMAGE_SHA=$(sha256sum < "$STAGE/filesystems/machine-guignol-18474" | cut -d' ' -f1)
KERNEL_SHA=$(sha256sum < "$STAGE/kernels/linux-6.12.95" | cut -d' ' -f1)
chmod -R a+rX "$WORK/htdocs"

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
VOL=mrn-install-bench-prefix
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
trap 'cleanup; docker volume rm "$VOL" >/dev/null 2>&1 || true' EXIT

echo
echo "# --- 1. the catalogue read off an Apache listing"

out=$(client --fetch-only --from "$BASE/1.0.x" --list) || out="EXIT $?
$out"
got=$(printf '%s\n' "$out" | awk 'NR>1 {print $1}' | grep . | sort | tr '\n' ' ')
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
echo "# ---"
echo "# PASS $PASSED, FAIL $FAILED"
(( FAILED == 0 )) || exit 1
exit 0
