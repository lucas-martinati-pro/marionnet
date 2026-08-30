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
# no bashbricks: like its sibling useful-scripts/marionnet-install.sh.bench/run.sh, this
# driver is a docker orchestration, and the assertions are all `grep' and exit codes.
#
# Usage: run.sh [PATH-TO-marionnet_*.tar.xz]
#        (default: the newest one under website-repo/download/marionnet-install.sh/*/)
# ---

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)

IMG=mrn-binary-bench-client
BOX=mrn-binary-bench
BOX_ALT=mrn-binary-bench-alt

PASSED=0; FAILED=0
function pass { echo "PASS: $*"; PASSED=$(( PASSED + 1 )); }
function fail { echo "FAIL: $*"; FAILED=$(( FAILED + 1 )); }
function skip_all { echo "SKIP: $*"; exit 77; }

function cleanup {
  docker rm -f "$BOX" "$BOX_ALT" >/dev/null 2>&1 || true
  return 0
}
trap cleanup EXIT

# --- What is being measured: a tarball made by `make release-binary'.

TARBALL="${1:-}"
if [[ -z $TARBALL ]]; then
  TARBALL=$(ls -t "$ROOT"/website-repo/download/marionnet-install.sh/*/marionnet_*.tar.xz 2>/dev/null | head -n 1) || true
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
echo "--- packages: $PKGS"
echo "--- building the client image ..."
docker build -q -t "$IMG" --build-arg RUNTIME_PACKAGES="$PKGS" -f "$HERE/Dockerfile.client" "$HERE" >/dev/null

docker rm -f "$BOX" "$BOX_ALT" >/dev/null 2>&1 || true
docker run -d --name "$BOX"     --network none -v "$TARBALL":/artefact.tar.xz:ro "$IMG" sleep infinity >/dev/null
docker run -d --name "$BOX_ALT" --network none -v "$TARBALL":/artefact.tar.xz:ro "$IMG" sleep infinity >/dev/null

# `in_box' runs a command in the nominal container, `in_alt' in the other one; both return
# the command's own exit code, so a case can measure a FAILURE as easily as a success.
function in_box { docker exec "$BOX" bash -c "$1"; }
function in_alt { docker exec "$BOX_ALT" bash -c "$1"; }
# The nominal run is what `sudo ./install.sh' gives: SUDO_USER names who gets the rule.
function in_box_as_sudo { docker exec -e SUDO_USER=tester "$BOX" bash -c "$1"; }
function in_alt_as_sudo { docker exec -e SUDO_USER=tester "$BOX_ALT" bash -c "$1"; }

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
  pass "the tarball unpacks on a bare Debian, under its named root ($ROOTDIR/)"
else
  fail "the tarball did not unpack with the tools of a bare Debian: [$out]"
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

names=$(in_box "ls /usr/local/bin | wc -l")
if [[ $names -eq 23 ]]; then
  pass "23 names in /usr/local/bin (the binary and the 22 companions of bin/scripts/)"
else
  fail "$names names in /usr/local/bin, expected 23"
fi

missing=""
for n in marionnet.native marionnet-sudoers.sh marionnet-cleanup marionnet-natbridge.sh \
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

if out=$(in_box "marionnet.native --help 2>&1"); then
  pass "marionnet.native --help runs on a Debian carrying only REQUIRED_PACKAGES_RUNTIME"
else
  fail "the binary does not start with the published dependency list: [$out]"
  echo "     (this is a hole in REQUIRED_PACKAGES_RUNTIME, not a defect of the bench)"
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
if out=$(in_alt "$ALT/bin/marionnet.native --paths 2>&1"); then
  relocated=$(grep -c "^\(filesystems\|kernels\|gui\) *: $ALT/share/marionnet" <<<"$out" || true)
  if ((relocated == 3)) && grep -q '^binaries *: /usr/local/bin$' <<<"$out"; then
    pass "--paths relocates filesystems/kernels/gui and STILL prints the compiled 'binaries' (ep. 9a trap)"
  else
    fail "--paths behaved differently than episode 9a measured: [$out]"
  fi
else
  fail "marionnet.native --paths failed under $ALT: [$out]"
fi

# ----------------------------------------------------------------

echo "--- $PASSED passed, $FAILED failed"
((FAILED == 0)) || exit 1
exit 0
