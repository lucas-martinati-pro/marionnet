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
# Usage: run.sh [--distro IMAGE|all] [PATH-TO-RELEASE-DIRECTORY]
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

SLUG=$(printf '%s' "$DISTRO" | tr -c 'A-Za-z0-9' '-')
BOX=mrn-deb-bench-$SLUG              # the nominal machine: bare, apt does everything
BOX_I386=mrn-deb-bench-i386-$SLUG    # the foreign architecture, which changes dpkg's state
BOX_CONF=mrn-deb-bench-conf-$SLUG    # the machine the tarball channel had already touched

PASSED=0; FAILED=0; SKIPPED=0
function pass { echo "PASS: $*"; PASSED=$(( PASSED + 1 )); }
function fail { echo "FAIL: $*"; FAILED=$(( FAILED + 1 )); }
function skip { echo "SKIP: $*"; SKIPPED=$(( SKIPPED + 1 )); }
function skip_all { echo "SKIP: $*"; exit 77; }

function cleanup {
  docker rm -f "$BOX" "$BOX_I386" "$BOX_CONF" >/dev/null 2>&1 || true
  return 0
}
trap cleanup EXIT

# --- What is being measured: a release directory made readable by apt.

REPO="${1:-}"
if [[ -z $REPO ]]; then
  REPO=$(ls -dt "$ROOT"/website-repo/download/marionnet-install.sh/*/ 2>/dev/null | head -n 1) || true
fi
[[ -n $REPO && -d $REPO ]] || \
  skip_all "no release directory found (run \`make release-deb', or pass one as argument)"
REPO=$(cd -- "$REPO" && pwd)

shopt -s nullglob
DEBS=("$REPO"/*.deb)
shopt -u nullglob
(( ${#DEBS[@]} )) || skip_all "no .deb in $REPO: run \`make release-deb' first"
[[ -f $REPO/Packages ]] || skip_all "no Packages in $REPO: run \`make release-apt' first"

command -v docker >/dev/null 2>&1 || skip_all "docker is not installed"
docker info >/dev/null 2>&1        || skip_all "the docker daemon is not reachable"

echo "--- repository: $REPO"
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
  if (cd -- "$REPO" && grep -E '\.deb$' SHA256SUMS | sha256sum -c --status -); then
    pass "SHA256SUMS announces the digest of THESE four packages"
  else
    fail "SHA256SUMS does not match the .deb of the directory"
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

docker run -d --name "$BOX" -v "$REPO":/repo:ro "$DISTRO" sleep infinity >/dev/null
undocker "$BOX"

function in_box  { docker exec -e DEBIAN_FRONTEND=noninteractive "$BOX" bash -c "$1"; }
function in_i386 { docker exec -e DEBIAN_FRONTEND=noninteractive "$BOX_I386" bash -c "$1"; }
function in_conf { docker exec -e DEBIAN_FRONTEND=noninteractive "$BOX_CONF" bash -c "$1"; }

# The one line of sources.list this whole episode exists to make true. `[trusted=yes]'
# because Release is not signed yet -- signing is the server episode's question, and it is
# named as such in the header of Makefile.d/release.apt.sh.
SOURCE_LINE='deb [trusted=yes] file:///repo ./'

# The network is a PRECONDITION, asked with the box's own sources and nothing of ours: a
# machine with no mirror cannot resolve the thirteen run-time dependencies, and there is
# nothing to measure there. Asked first, and separately, so that a repository apt REFUSES
# is reported as the red case it is instead of being blamed on the network.
in_box "apt-get update -qq" >/dev/null 2>&1 || \
  skip_all "no network in the containers: apt cannot resolve the run-time dependencies"

if in_box "echo '$SOURCE_LINE' > /etc/apt/sources.list.d/marionnet.list && apt-get update -qq" >/dev/null 2>&1; then
  pass "\`apt-get update' accepts the flat repository ($SOURCE_LINE)"
else
  fail "apt refuses the repository ($SOURCE_LINE): Packages or Release does not hold up"
  echo "--- nothing else can be measured; count: $PASSED passed, $FAILED failed"
  exit 1
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
  if [[ $names -eq 26 ]]; then
    pass "26 names in /usr/bin (the binary and the 25 companions of bin/scripts/)"
  else
    fail "the package owns $names names in /usr/bin, expected 26"
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
docker run -d --name "$BOX_I386" -v "$REPO":/repo:ro "$DISTRO" sleep infinity >/dev/null
undocker "$BOX_I386"
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
  docker run -d --name "$BOX_CONF" -v "$REPO":/repo:ro "$DISTRO" sleep infinity >/dev/null
  undocker "$BOX_CONF"
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
