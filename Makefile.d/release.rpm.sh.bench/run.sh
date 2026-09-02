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

# ---
# --- The bench of the RECEIVING side of Makefile.d/release.rpm.sh.
# ---
# The publisher's own run says what it BUILT; this says what a machine DOES with it. The box
# is naked on purpose -- no Dockerfile, nothing pre-installed -- because the whole point of a
# package channel is that dnf pulls the dependencies itself. Two of them cannot come from the
# distribution at all (vde2 and uml-utilities exist in no RPM repository, measured), so this
# bench is also where "we had to package them ourselves" stops being a claim.
#
# Conventions of driven-sessions/README.md: PASS 0 / SKIP 77 / FAIL anything else.
#
# Usage: Makefile.d/release.rpm.sh.bench/run.sh [OPTIONS]
#
#   -o, --output-dir DIR   the release directory holding the packages -- a path, or since
#                          episode 27 an http(s) URL, in which case the packages measured
#                          are the ones www.marionnet.org serves and the repository of
#                          case 10 is that server (point (6) of the roadmap)
#                          (default: website-repo/download/marionnet-install.sh/<series>)
#       --distro IMAGE     the box to receive them (default: fedora:42)
#       --keep             do not remove the containers afterwards (says their names)
#   -h, --help             this help
# ---

set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# `|| exit' and not a bare cd: this bench runs without `set -e' (a failing case must be
# counted, not fatal), so nothing else would stop it from running in the wrong directory.
cd "$ROOT" || exit 2

PASSED=0; FAILED=0; SKIPPED=0
function pass { echo "PASS: $*"; PASSED=$(( PASSED + 1 )); }
function fail { echo "FAIL: $*"; FAILED=$(( FAILED + 1 )); }
function skip { echo "SKIP: $*"; SKIPPED=$(( SKIPPED + 1 )); }
function skip_all { echo "SKIP: $*"; exit 77; }
function info { echo "==> $*"; }

DISTRO="fedora:42"
OUTDIR=""
KEEP=0

while (($#)); do
  case "$1" in
    -o|--output-dir) OUTDIR="$2"; shift 2 ;;
    --distro)        DISTRO="$2"; shift 2 ;;
    --keep)          KEEP=1; shift ;;
    -h|--help)       sed -n '/^# Usage: Makefile.d/,/^# ---$/p' "${BASH_SOURCE[0]}" | \
                       sed -e 's/^# \{0,1\}//' -e '/^---$/d'; exit 0 ;;
    *)               echo "unknown option '$1'" >&2; exit 2 ;;
  esac
done

command -v docker >/dev/null || skip_all "docker is not available"

# `--distro all' runs the suite once per box, by re-invoking this script: the cases are written
# for ONE box and stay that way, and a box which fails does not stop the others. The four are
# the current members of the two RPM families -- two RHEL rebuilds, the upstream distribution,
# and openSUSE, which is the one that proves the file/soname dependencies really do cross
# families (it resolves them with zypper, not dnf).
ALL_DISTROS=(rockylinux/rockylinux:10 almalinux:10 fedora:42 opensuse/leap:16.0)
if test "$DISTRO" = all; then
  rc=0
# One download for the four boxes, not four: the loop makes the cache and the children
# inherit it through the environment (episode 27). It is removed here, by the invocation
# which made it, exactly as a single run removes its own.
  ALL_CACHE=""
  if test -z "${MRN_BENCH_CACHE:-}"; then
    ALL_CACHE=$(mktemp -d -- "${TMPDIR:-/tmp}/mrn-bench-cache.XXXXXXXX")
    export MRN_BENCH_CACHE=$ALL_CACHE
  fi
  forward=()
  test -z "$OUTDIR" || forward+=(--output-dir "$OUTDIR")
  ((KEEP)) && forward+=(--keep)
  for d in "${ALL_DISTROS[@]}"; do
    echo; echo "================================================================ $d"
    bash "${BASH_SOURCE[0]}" --distro "$d" "${forward[@]}" || rc=1
  done
  test -z "$ALL_CACHE" || rm -rf -- "$ALL_CACHE"
  exit $rc
fi

# ---
# --- The two package managers, behind four verbs.
# ---
# openSUSE is not a variant of Fedora with another name: it resolves the same file and soname
# dependencies with zypper, and that is precisely what makes it worth a box here. Everything
# the cases need is expressed through these four, so a case never has to know which family it
# is running on -- and rpm -q, which both families share, answers the rest.
# ---
case "$DISTRO" in
  *opensuse*|*suse*) FAMILY=zypper ;;
  *)                 FAMILY=dnf ;;
esac

# ---
# --- Where the release is read from: a directory, or a server (episode 27)
# ---
# The release directory may be named by an http(s) URL, exactly as `marionnet-install.sh
# --from' takes a URL or a directory -- and for the same reason: only the two functions
# below know the difference, so a remote run exercises the real path rather than a second
# implementation of it.
#
# Here, unlike the .deb bench, the packages themselves ARE downloaded: nine cases out of ten
# install a NAMED FILE (`dnf install /rpms/<name>.rpm'), which is the gesture of somebody who
# fetched a package by hand, and it is that gesture this bench was written to measure. Case
# 10 -- the repository -- is the one which does not: there dnf is pointed at the server and
# fetches by itself. Downloaded once, and kept for the whole `--distro all' loop: four boxes
# measure ONE release, not four copies of it.
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
if test -z "$CACHE"; then
  CACHE=$(mktemp -d -- "${TMPDIR:-/tmp}/mrn-bench-cache.XXXXXXXX")
  export MRN_BENCH_CACHE=$CACHE
  CACHE_OWNED=1
fi

if test -z "$OUTDIR"; then
  SERIES=$(bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series) || \
    skip_all "cannot read the publication series"
  OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
fi

REPO_URL=""
if is_url "$OUTDIR"; then
  REPO_URL=${OUTDIR%/}
  OUTDIR=$CACHE/rpms
  mkdir -p "$OUTDIR"
  fetch_to "$REPO_URL/SHA256SUMS" "$OUTDIR/SHA256SUMS" || \
    skip_all "cannot read $REPO_URL/SHA256SUMS (no downloader, or this is not a release directory)"
  # Driven by the catalogue and by nothing else -- the invariant of episode 8, seen from the
  # consumer's side: an artefact SHA256SUMS does not name is one no client can find. Two
  # tarballs come along with the packages, and each buys one case no other can play: the
  # application's, which episode 20c compares byte for byte with the installed binary, and
  # the guest image's, whose mtime is what UML checks (invariant 1). The other artefacts --
  # the kernels, the big images -- are not downloaded: no case reads them.
  for f in $(awk '{print $2}' "$OUTDIR/SHA256SUMS" | \
             grep -E '\.rpm$|^marionnet_.*\.tar\.xz$|^filesystems_machine-guignol-.*\.tar\.xz$'); do
    test -s "$OUTDIR/$f" && continue
    info "fetching $f ..."
    fetch_to "$REPO_URL/$f" "$OUTDIR/$f" || skip_all "cannot download $f from $REPO_URL/"
  done
  # And the one case a remote run adds, before any of the others: what the server serves is
  # what its own catalogue announces. Everything below is then measured on THESE bytes.
  if (cd -- "$OUTDIR" && grep -E '\.rpm$' SHA256SUMS | sha256sum -c --status -); then
    pass "the packages served by $REPO_URL match the digests of their own SHA256SUMS"
  else
    fail "what $REPO_URL serves does not match the digests SHA256SUMS announces"
  fi
fi

test -d "$OUTDIR" || skip_all "no release directory: $OUTDIR"
OUTDIR=$(cd -- "$OUTDIR" && pwd)

shopt -s nullglob
RPMS=("$OUTDIR"/*.rpm)
shopt -u nullglob
((${#RPMS[@]})) || skip_all "no .rpm in $OUTDIR (run: make release-rpm && make release-rpm-deps)"

# The five packages this bench knows about, found by name rather than by position.
# A release directory legitimately holds SEVERAL revisions of the application at once, while
# one replaces the other -- which is why the newest is picked here rather than the first
# matching name. Measured the hard way: with r916 and r917 both published, installing
# /rpms/*.rpm asks dnf for two versions of one package and it refuses, "conflicting requests".
function rpm_named {  # <package name>: prints the file name of that package, newest first
  local f base out=""
  for f in "${RPMS[@]}"; do
    base=$(basename -- "$f")
    # <name>-<version>-<release>.<arch>.rpm: the name is what precedes the version, so the
    # candidate matches only if what follows its name is a dash and then a digit.
    [[ $base =~ ^$1-[0-9~] ]] && out+="$base"$'\n'
  done
  test -n "$out" || return 1
  echo "$out" | grep -v '^$' | sort -V | tail -1
}

APP=$(rpm_named marionnet) || skip_all "no marionnet package in $OUTDIR"
KERNELS=$(rpm_named marionnet-kernels || true)
GUIGNOL=$(rpm_named marionnet-fs-guignol || true)
VDE2=$(rpm_named vde2 || true)
UMLU=$(rpm_named uml-utilities || true)

info "release dir : ${REPO_URL:-$OUTDIR}"
info "box         : $DISTRO"
info "packages    : $APP ${KERNELS:-} ${GUIGNOL:-} ${VDE2:-} ${UMLU:-}"

BOX="mrn-rpm-bench-$(echo "$DISTRO" | tr ':/' '--')"
function cleanup {
  if ((KEEP)); then info "container kept: $BOX"; else docker rm -f "$BOX" >/dev/null 2>&1; fi
  # The two boxes of the repository part, removed here too: a run interrupted between them
  # would otherwise leave containers behind, and the next run fails on the name.
  ((KEEP)) || docker rm -f "${BOX}-repo" "${BOX}-foreign" >/dev/null 2>&1 || true
  if test -n "${CACHE_OWNED:-}" && ((KEEP == 0)); then rm -rf -- "$CACHE"; fi
}
trap cleanup EXIT

docker rm -f "$BOX" >/dev/null 2>&1
docker run -d --name "$BOX" -v "$OUTDIR:/rpms:ro" "$DISTRO" sleep infinity >/dev/null || \
  skip_all "cannot start a $DISTRO container"
function in_box { docker exec "$BOX" bash -c "$1"; }

# The four verbs. `pm_install' takes files or names indifferently -- both families accept
# either -- and prints what the manager said, so that a case can read the REASON of a refusal
# instead of guessing it from a word.
function pm_install {  # <targets...>
  case "$FAMILY" in
    dnf)    in_box "dnf -y install $* 2>&1" ;;
    zypper) in_box "zypper --non-interactive --no-gpg-checks install --allow-unsigned-rpm $* 2>&1" ;;
  esac
}
function pm_remove {   # <name>
  case "$FAMILY" in
    dnf)    in_box "dnf -y remove $* >/dev/null 2>&1" ;;
    zypper) in_box "zypper --non-interactive remove $* >/dev/null 2>&1" ;;
  esac
}
# EPEL and CRB where they exist: a gtksourceview3 lives in EPEL on an EL box, and asking a
# naked RHEL rebuild to find it without EPEL would measure our packaging against a machine no
# user of GTK software actually runs. This is the one thing the INSTALL documentation will
# have to say for this family.
function pm_extra_repos {
  case "$FAMILY" in
    dnf) in_box 'if test -f /etc/redhat-release && ! grep -qi fedora /etc/redhat-release; then
                   dnf -y install epel-release >/dev/null 2>&1 || true
                   dnf -y install dnf-plugins-core >/dev/null 2>&1 || true
                   dnf config-manager --set-enabled crb >/dev/null 2>&1 || true
                 fi' ;;
    zypper) : ;;
  esac
}
# The unmet dependencies of a refusal, one per line, whatever the manager: this is what lets a
# case say WHICH requirement was not met instead of matching a word anywhere in the output --
# the false PASS episode 19 had to repair (a refusal caused by a missing xrandr was reported as
# "the refusal names glibc", because the word appeared elsewhere in the message).
function unmet_of {  # reads the output of pm_install on stdin
  grep -oE "nothing provides [^ ]+( needed by [^ ]+)?" | sed 's/nothing provides //' | sort -u
}

pm_extra_repos

# ---------------------------------------------------------------- 0. the catalogue
# An artefact which never reaches SHA256SUMS is invisible to the installer -- the invariant
# episode 8 established and episode 9b had to repair. A package sitting in the directory
# without a line, or with the line of its predecessor, is exactly what this checks.
info "0. the catalogue"
if test -f "$OUTDIR/SHA256SUMS"; then
  missing=0
  for f in "${RPMS[@]}"; do
    grep -q "  $(basename -- "$f")\$" "$OUTDIR/SHA256SUMS" || { missing=1; echo "    not catalogued: $(basename -- "$f")"; }
  done
  ((missing)) && fail "every .rpm has a line in SHA256SUMS" || pass "every .rpm has a line in SHA256SUMS"

  if (cd "$OUTDIR" && grep '\.rpm$' SHA256SUMS | sha256sum -c --quiet -) 2>/dev/null; then
    pass "the recorded digests are the digests of the files"
  else
    fail "a recorded digest does not match its file (republished without --force?)"
  fi
else
  fail "no SHA256SUMS in the release directory"
fi

# ---------------------------------------------------------------- 1. the box is naked
info "1. the box before anything"
if in_box 'command -v vde_switch >/dev/null || command -v uml_mconsole >/dev/null'; then
  fail "the box already provides vde_switch or uml_mconsole: it is not naked"
else
  pass "the box provides neither vde_switch nor uml_mconsole (they exist in no RPM repository)"
fi
# Both answers are legitimate, and which one a box gives is the whole point of episode 17:
# openSUSE ships vde2 in its official repository, Fedora and the RHEL rebuilds do not. What
# matters is that ONE package serves both, and it does because its dependency is written by
# FILE: where the distribution provides /usr/bin/vde_switch, ours is simply never pulled.
if in_box 'case "$(command -v zypper)" in ?*) zypper --non-interactive search --match-exact vde2 2>/dev/null | grep -q "| vde2 " ;; *) dnf -q repoquery vde2 2>/dev/null | grep -q . ;; esac'; then
  HAS_DISTRO_VDE2=1
  pass "this distribution ships vde2 itself, so ours will not be pulled here (the gain of a file dependency)"
else
  HAS_DISTRO_VDE2=0
  pass "this distribution has no vde2: the reason release.rpm.sh builds one"
fi

# ---------------------------------------------------------------- 2. the application alone
# The application alone MUST be refused on a distribution which carries no vde2 and no
# uml-utilities, and the refusal must NAME what is missing. This is the whole argument of the
# channel in one measurement: the dependencies are written by file (invariant 5), so dnf can
# say "nothing provides /usr/bin/vde_switch" -- it does not install something which cannot
# start a single component and let the student discover it later.
#
# It is also what says the twelve OTHER runtime dependencies resolve from the distribution's
# own repositories: they are not in this message.
info "2. the application alone, on a box which has no vde2"
# What must be named depends on what the box already has: uml_mconsole always (no RPM
# distribution provides it), and vde_switch only where the distribution has no vde2 of its own.
#
# And the RESULT is read from rpm, never from the exit status: measured on openSUSE, zypper
# prints the problem, cancels, and exits 0. A bench which trusted that would call a refusal a
# success.
out=$(pm_install "/rpms/$APP"; true)
expected_named=1
echo "$out" | grep -q '/usr/bin/uml_mconsole' || expected_named=0
if ((! HAS_DISTRO_VDE2)); then
  echo "$out" | grep -q '/usr/bin/vde_switch' || expected_named=0
fi
if in_box 'rpm -q marionnet >/dev/null 2>&1'; then
  fail "the application was installed although this box cannot provide what it needs"
  pm_remove marionnet
elif ((expected_named)); then
  if ((HAS_DISTRO_VDE2)); then
    pass "refused, naming the one file this box lacks (/usr/bin/uml_mconsole); its own vde2 answered for vde_switch"
  else
    pass "refused, naming BOTH missing files (and nothing else: the twelve others resolved)"
  fi
else
  fail "refused, but without naming what is missing: $(echo "$out" | unmet_of | tr '\n' ' ')"
fi

# ---------------------------------------------------------------- 2 bis. all five together
# And the counterpart of what episode 12 measured on Debian 12: a package built against a
# glibc newer than the box's must be refused, and the refusal must name it. Read from the
# METADATA rather than from a file name -- the whole gain of a package over a tarball.
info "2 bis. the five packages together"
# Named one by one, and not /rpms/*.rpm: the directory may hold several revisions of the
# application, and a glob would ask the manager for two versions of the same package.
# The four Marionnet packages minus the i386 kernel, plus the two third-party ones. The i386
# kernel is deliberately NOT here: it is the one package whose installability depends on the
# distribution (RHEL 10 dropped 32-bit multilib), and case 3 bis is where that is measured.
FIVE=""
for p in "$APP" "$KERNELS" "$GUIGNOL" "$VDE2" "$UMLU"; do test -n "$p" && FIVE+=" /rpms/$p"; done
out=$(pm_install "$FIVE"; true)
unmet=$(echo "$out" | unmet_of)
if test -z "$unmet"; then
  pass "the five packages install together"
  INSTALLED=1
elif echo "$unmet" | grep -q 'libc\.so\.6'; then
  # Classified by the EXACT unmet requirement, never by a word found anywhere in the output.
  pass "refused, and what is unmet is a libc symbol: $(echo "$unmet" | head -1)"
  INSTALLED=0
else
  fail "refused, and what is unmet is not a libc symbol: $(echo "$unmet" | tr '\n' ' ')"
  INSTALLED=0
fi

if ((! INSTALLED)); then
  echo "---- $PASSED passed, $FAILED failed, $SKIPPED skipped (box too old for this build)"
  ((FAILED)) && exit 1 || exit 0
fi

# ---------------------------------------------------------------- 3. what dnf pulled by itself
info "3. the dependencies dnf resolved on its own"
pm_install "$FIVE" >/dev/null 2>&1

for probe in "vde_switch:vde2" "wirefilter:vde2" "slirpvde:vde2" "uml_mconsole:uml-utilities"; do
  cmd="${probe%%:*}"; from="${probe##*:}"
  if in_box "command -v $cmd >/dev/null"; then
    pass "$cmd is there (from our $from package)"
  else
    fail "$cmd is missing: Marionnet cannot run a single component without it"
  fi
done

# xhost and not xrandr: the Makefile's comment names xhost as what x11-xserver-utils is
# for, and Rocky 10 has no xrandr at all -- the mistake episode 19 had to correct.
for cmd in dot jq socat dnsmasq xterm xauth xhost ip xz sudo; do
  if in_box "command -v $cmd >/dev/null"; then
    pass "$cmd pulled from the distribution"
  else
    fail "$cmd absent: a Requires: of the table did not resolve"
  fi
done

# The one runtime library, which no table names: rpm reads its soname out of the binary, and
# that soname resolves on both RPM families where the package names do not.
if in_box "rpm -q --requires marionnet 2>/dev/null | grep -q libgtksourceview-3.0.so.1"; then
  pass "libgtksourceview is required BY SONAME (derived, not translated)"
else
  fail "the gtksourceview dependency is not derived from the soname"
fi

# ------------------------------------------------- 3 bis. the i386 kernel, alone in its fate
# The package episode 17 had merged into marionnet-kernels and episode 19 split out again. It
# is the ONE package whose installability depends on the distribution: RHEL 10 and its rebuilds
# dropped 32-bit multilib entirely (measured: nothing provides /lib/ld-linux.so.2, CRB
# included), so it cannot be installed there -- and that is exactly why it must be separate.
# What this case really checks is that its refusal costs nothing to anybody else: the 64-bit
# kernel, installed just above, is still there afterwards.
info "3 bis. the 32-bit kernel"
KERNELS_I386=$(rpm_named marionnet-kernels-i386 || true)
if test -z "$KERNELS_I386"; then
  skip "no marionnet-kernels-i386 package in the release directory"
else
  out=$(pm_install "/rpms/$KERNELS_I386"; true)
  unmet=$(echo "$out" | unmet_of)
  if test -z "$unmet"; then
    if in_box 'test -f /usr/share/marionnet/kernels/linux-6.12.95-i386'; then
      pass "this box has 32-bit multilib, and the i386 kernel is installed"
    else
      fail "the i386 kernel package reported success but put no kernel down"
    fi
  elif echo "$unmet" | grep -q 'libc\.so\.6'; then
    pass "refused for want of a 32-bit libc, which this distribution no longer has: $(echo "$unmet" | head -1)"
    if test -n "$KERNELS" && in_box 'test -f /usr/share/marionnet/kernels/linux-6.12.95'; then
      pass "and the 64-bit kernel is UNHARMED -- which the merged package of episode 17 could not manage"
    else
      fail "the refusal of the i386 kernel took the 64-bit one with it"
    fi
  else
    fail "the i386 kernel was refused for an unexpected reason: $(echo "$unmet" | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------- 4. what landed
info "4. what the packages put on the machine"
n=$(in_box "rpm -ql marionnet 2>/dev/null | grep -c '^/usr/bin/'")
# 27 since the bare name `marionnet' is staged beside marionnet.native (see the
# twin case of the .deb bench for why this number is written and not derived).
test "$n" = 28 && pass "the 28 commands of bin/ are installed" || fail "expected 28 commands in /usr/bin, found $n"

n=$(in_box "ls /usr/share/bash-completion/completions/ 2>/dev/null | grep -cE 'mrn|marionnet'")
test "$n" = 12 && pass "the twelve completion files are installed (episode 11a)" || \
  fail "expected 12 completion files, found $n"

if in_box 'test -f /etc/marionnet/marionnet.conf'; then pass "the configuration file is installed"
else fail "no /etc/marionnet/marionnet.conf"; fi

if in_box "rpm -qc marionnet 2>/dev/null | grep -q '^/etc/marionnet/marionnet.conf$'"; then
  pass "it is declared %config(noreplace): a machine which edited it keeps its version"
else
  fail "the configuration file is not declared as a config file"
fi

# The 64-bit kernel only: the 32-bit one is a package of its own since episode 19, and whether
# it could be installed is the business of case 3 bis, not of this one.
if test -n "$KERNELS"; then
  if in_box 'test -f /usr/share/marionnet/kernels/linux-6.12.95'; then
    pass "the 64-bit kernel is installed, whatever became of the 32-bit one"
  else
    fail "the 64-bit kernel is missing from /usr/share/marionnet/kernels"
  fi
fi

if test -n "$GUIGNOL"; then
  if in_box 'test -f /usr/share/marionnet/filesystems/machine-guignol-18474 && test -L /usr/share/marionnet/filesystems/router-guignol-18474'; then
    pass "the guignol image is there, machine AND router (the router being the symlink it is)"
  else
    fail "the guignol image or its router link is missing"
  fi
fi

# ---------------------------------------------------------------- 5. the sudoers rule
# Invariant 3: `dnf install' has no answer to "for whom?", so the %post NAMES the rule and
# never grants it. A bench which only checked that Marionnet works would never catch a channel
# which quietly gave a user root over ip and iptables.
info "5. the sudoers rule"
if in_box 'ls /etc/sudoers.d/ 2>/dev/null | grep -q marionnet'; then
  fail "the package GRANTED a sudoers rule: it must only name it"
else
  pass "no sudoers rule was granted (the %post only names it)"
fi

# ---------------------------------------------------------------- 6. the mtime UML checks
# Invariant 1, and the reason the data packages are built by unpacking the published tarball:
# UML compares the mtime of a backing file against what the .conf records. Two channels which
# disagree here give a Marionnet which refuses to open a project made with the other one.
info "6. the mtime of the guest image"
if test -n "$GUIGNOL"; then
  from_rpm=$(in_box "stat -c %Y /usr/share/marionnet/filesystems/machine-guignol-18474 2>/dev/null")
  tarball=$(ls "$OUTDIR"/filesystems_machine-guignol-*.tar.xz 2>/dev/null | head -1)
  if test -n "$tarball" && test -n "$from_rpm"; then
    from_tar=$(tar tvJf "$tarball" --full-time 2>/dev/null | \
               awk '/filesystems\/machine-guignol-[0-9]+$/{print $4" "$5; exit}')
    from_tar_epoch=$(date -d "$from_tar" +%s 2>/dev/null || echo "")
    if test "$from_rpm" = "$from_tar_epoch"; then
      pass "the image carries the same mtime as the published tarball ($(date -u -d @"$from_rpm" '+%F %H:%M') UTC)"
    else
      fail "mtime differs: rpm $(date -u -d @"$from_rpm" '+%F %H:%M') vs tarball $from_tar"
    fi
  else
    skip "no guignol tarball beside the package to compare the mtime against"
  fi
fi

# ---------------------------------------------------------------- 7. the delivered guides
# An image is not a machine. Every RPM container image sets tsflags=nodocs in /etc/dnf/dnf.conf,
# and rpm flags everything under %{_docdir} as documentation BY ITSELF -- measured: 26 of the
# 31 paths -- so the guides are absent HERE and present on a real installation. The exact
# counterpart of the path-exclude episode 15b measured on debian:*-slim.
info "7. the guides of episode 14, and the difference between an image and a machine"
# Three families, three spellings of the same thing: path-exclude in dpkg (episode 15b),
# tsflags=nodocs in dnf, and rpm.install.excludedocs in zypp. An image is not a machine.
if in_box 'grep -q tsflags=nodocs /etc/dnf/dnf.conf 2>/dev/null || \
           grep -qE "^[^#]*rpm.install.excludedocs *= *yes" /etc/zypp/zypp.conf 2>/dev/null'; then
  pass "this image excludes documentation (so the guides are legitimately absent from it)"
  n=$(in_box "rpm -qpd /rpms/$APP 2>/dev/null | wc -l")
  test "$n" -ge 26 && pass "the package nevertheless CARRIES the $n documentation files" || \
    fail "the package carries only $n documentation files, expected at least 26"
  in_box "sed -i '/tsflags=nodocs/d' /etc/dnf/dnf.conf 2>/dev/null; \
          sed -i 's/^\\(rpm.install.excludedocs *=\\) *yes/\\1 no/' /etc/zypp/zypp.conf 2>/dev/null; true"
  case "$FAMILY" in
    dnf)    in_box "dnf -y reinstall /rpms/$APP >/dev/null 2>&1" ;;
    zypper) in_box "zypper --non-interactive --no-gpg-checks install --allow-unsigned-rpm -f /rpms/$APP >/dev/null 2>&1" ;;
  esac
  n=$(in_box 'ls /usr/share/doc/marionnet/ 2>/dev/null | wc -l')
  test "$n" -ge 5 && pass "once the image stops excluding documentation, the guides are installed ($n entries)" || \
    fail "the guides are still absent after removing tsflags=nodocs"
else
  n=$(in_box 'ls /usr/share/doc/marionnet/ 2>/dev/null | wc -l')
  test "$n" -ge 5 && pass "the guides are installed ($n entries)" || fail "the guides are absent"
fi

# ---------------------------------------------------------------- 8. it runs
# TWO QUESTIONS, AND THEY ARE NOT THE SAME ONE -- which is what this case had to be taught
# (episode 20c, the third bench defect of the same family as episodes 19 and 20b). It used to
# read `2>&1 | head -1' and look for the version there, so ANY line written on stderr before
# the answer turned "the binary ran and said who it is" into "the binary does not run" -- a
# FAIL announcing something the run disproves. Whether it runs is read in the whole output;
# whether it starts CLEANLY is a case of its own, so that a warning is reported as a warning.
info "8. the application itself"
out=$(in_box 'marionnet.native --version 2>/dev/null')
err=$(in_box 'marionnet.native --version 2>&1 >/dev/null')
if echo "$out" | grep -qi 'marionnet version'; then
  pass "the binary runs and says who it is: $(echo "$out" | head -1)"
else
  fail "the binary does not run: ${out:-nothing on stdout}${err:+ (stderr: $(echo "$err" | head -1))}"
fi

# This case was RED on purpose from episode 20c to episode 21, and what it caught is worth
# keeping written down. The binary compiled IN THE BUILD BOX wrote `GLib-GObject-CRITICAL:
# invalid cast from GtkSourceStyleSchemeManager to GInitiallyUnowned' at startup, where the one
# compiled on the packager's machine wrote nothing -- same lablgtk3, same libgtksourceview, same
# box to run in. The box was NOT changing the binary's behaviour: it was removing a gag. The
# invalid cast is emitted by the lablgtk3-sourceview3 stub in EVERY build; whether the runtime
# check survives compilation depends on the glib HEADERS -- glib >= 2.80 compiles it out under
# __OPTIMIZE__, glib 2.74 (debian:12) keeps it (both macros read, episode 21). The call itself
# came from `Gtksv_utils' of lablgtk3-extras, a library this tree linked without naming a single
# one of its modules; bin/dune now names lablgtk3-sourceview3 directly and the call is gone.
# So: green from episode 21 on, and a regression here means either the library came back or an
# equally unnamed module started talking at startup. A note is what nobody re-measures.
if test -z "$err"; then
  pass "the binary starts cleanly (nothing on stderr)"
else
  fail "the binary writes on stderr at startup: $(echo "$err" | grep -v '^$' | head -1)"
fi

# The images follow the application (episode 28), measured on the RPM side of the same
# question the .deb bench asks: the big guest images stay outside the package manager on
# purpose, so the installer the PACKAGE itself lays down is how the user of an .rpm gets
# them -- and until episode 28 it aimed at /usr/local/share/marionnet, one directory away
# from where the Marionnet dnf had just installed was looking. `--dry-run' sees it and
# downloads nothing; /rpms is the release directory this bench already mounts.
if in_box "command -v marionnet-install.sh >/dev/null && command -v marionnet-get-images >/dev/null"; then
  pass "the package carries the installer under both of its names"
else
  fail "marionnet-install.sh / marionnet-get-images are not on the PATH of an rpm machine"
fi
rc=0; out=$(in_box "marionnet-install.sh --fetch-only --from /rpms --dry-run 2>&1") || rc=$?
if ((rc == 0)) && grep -q 'destination : /usr/share/marionnet' <<<"$out"; then
  pass "the images of an rpm machine go to /usr/share/marionnet, where its Marionnet looks"
else
  fail "the installer aims beside the installation dnf made: rc=$rc, [$(grep -i destination <<<"$out")]"
fi

# THE CONTRACT OF EPISODE 20c, and it is the one thing no other case can see: since this
# channel compiles nothing, the binary it installs must be -- to the byte -- the one inside the
# published tarball of the same revision. Read here rather than at packaging time, because what
# matters is what LANDS on the machine, after rpm has copied, chowned and possibly post-
# processed it. If the tarball of that revision is not in the release directory the case is
# skipped: the package may legitimately predate episode 20c.
app_rev=$(echo "$APP" | sed -n 's/^marionnet-[0-9~]*[^+]*+r\([0-9]\+\)-.*/\1/p')
app_tar=$(cd "$OUTDIR" && ls marionnet_*-r"${app_rev:-none}"_*.tar.xz 2>/dev/null | head -1)
if test -z "$app_tar"; then
  skip "no published tarball at r${app_rev:-?} to compare the installed binary with"
else
  pm_install xz tar >/dev/null 2>&1
  same=$(in_box "cd /tmp && rm -rf cmp && mkdir cmp && \
                 xz -dc -T0 -- /rpms/$app_tar | tar -C cmp -xf - && \
                 a=\$(sha256sum < /usr/bin/marionnet.native) && \
                 b=\$(sha256sum < cmp/*/bin/marionnet.native) && \
                 test \"\$a\" = \"\$b\" && echo same || echo \"\$a vs \$b\"")
  test "$same" = "same" \
    && pass "the installed binary is the published tarball's, to the byte ($app_tar)" \
    || fail "the package does NOT carry the published binary of r$app_rev: $same"
fi

# bash-completion loads on demand, by looking for a file named after the command being typed
# -- which is why episode 11a had to install twelve files rather than one. Checking that the
# loader ARMS a function of ours, rather than falling back to _minimal, is what tells the two
# apart (a naive check passes on a box where nothing is installed at all).
#
# bash-completion is NOT a dependency of the package -- Marionnet works without it -- so the
# box does not have it until this case asks for it. Installing it here is the point: it proves
# the completion files are installed where the LOADER looks, not merely where we put them.
pm_install bash-completion >/dev/null 2>&1
armed=$(in_box 'source /usr/share/bash-completion/bash_completion 2>/dev/null; \
                _completion_loader mrnctl >/dev/null 2>&1; complete -p mrnctl 2>/dev/null')
if echo "$armed" | grep -qE '_mrn|marionnet'; then
  pass "bash-completion finds and arms our completion for mrnctl"
else
  fail "the completion loader did not arm our function for mrnctl (got: ${armed:-nothing})"
fi

# ---------------------------------------------------------------- 9. removing it
#
# The configuration file is EDITED before the removal, because that is the case which matters:
# an untouched %config is rpm's to take away, but one an administrator changed must survive as
# .rpmsave. A bench which removed a pristine file would call the right behaviour a loss.
info "9. removing the application, after the configuration was edited"
in_box 'echo "# edited by the administrator" >> /etc/marionnet/marionnet.conf'
pm_remove marionnet
if in_box '! test -x /usr/bin/marionnet.native'; then
  pass "the application can be removed"
else
  fail "removing the application left it behind"
fi
if in_box 'test -f /etc/marionnet/marionnet.conf.rpmsave || test -f /etc/marionnet/marionnet.conf'; then
  pass "the edited configuration survives the removal (kept, or set aside as .rpmsave)"
else
  fail "the edited configuration was destroyed by the removal"
fi

# ---------------------------------------------------------------- 10. the repository
# What release.dnf.sh buys, measured where it shows: with repodata/ in the directory, the two
# dependencies no RPM distribution carries are resolved BY DNF, from that same directory.
# Without it, whoever installs has to name vde2 and uml-utilities on the command line -- which
# means knowing they exist, and why.
#
# A SECOND, FRESH container: the box above has been installed into, removed from and had its
# dnf configuration edited. Measuring "what a plain dnf install gives" needs a machine to which
# nothing has been done.
info "10. the repository (a fresh box, nothing but the repo)"
# Remotely, the index is asked of the SERVER: a repodata/ in the local mirror would say
# nothing about what dnf is going to find at the other end of the URL.
if test -n "$REPO_URL"; then
  fetch_to "$REPO_URL/repodata/repomd.xml" "$CACHE/repomd.xml" >/dev/null 2>&1 && \
    { mkdir -p "$OUTDIR/repodata"; cp -- "$CACHE/repomd.xml" "$OUTDIR/repodata/repomd.xml"; }
  # THE DETACHED SIGNATURE TOO (episode 30b), 833 bytes: without it the verification below
  # SKIPPED in every remote run and said "this directory was indexed without --sign" -- about a
  # server which had signed its index. A skip which names the wrong cause is worse than a skip.
  # Fetched, not deduced: what is verified is then the pair the SERVER serves.
  fetch_to "$REPO_URL/repodata/repomd.xml.asc" "$CACHE/repomd.xml.asc" >/dev/null 2>&1 && \
    { mkdir -p "$OUTDIR/repodata"; cp -- "$CACHE/repomd.xml.asc" "$OUTDIR/repodata/repomd.xml.asc"; }
fi
if ! test -f "$OUTDIR/repodata/repomd.xml"; then
  skip "no repodata in the release directory (run: make release-dnf)"
else
  pass "repodata/repomd.xml is there"
  if test -f "$OUTDIR/SHA256SUMS" && grep -q 'repodata' "$OUTDIR/SHA256SUMS"; then
    fail "repodata is recorded in SHA256SUMS: an index is not an artefact, and its digest would go stale by itself"
  else
    pass "repodata is NOT in SHA256SUMS (an index is rewritten at every publication)"
  fi

  # ---------------------------------------------- the signature, read in the files themselves
  # Episode 30b. Two facts, because rpm has two mechanisms: every package carries a signature
  # of its own (rpmsign), and the index carries a detached one (repomd.xml.asc). A repository
  # where only one of them holds is a repository which protects half of what it serves.
  KEYRING="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/marionnet-archive-keyring.asc"
  if test -f "$KEYRING" && command -v gpg >/dev/null && command -v rpm >/dev/null; then
    FPR=$(gpg --with-colons --show-keys -- "$KEYRING" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')
    KEYID="${FPR: -16}"; KEYID="${KEYID,,}"
    unsigned=0; total=0
    for f in "$OUTDIR"/*.rpm; do
      test -e "$f" || continue
      total=$((total + 1))
      shown=$(rpm -qp --qf '%{RSAHEADER:pgpsig}' -- "$f" 2>/dev/null)
      case "${shown,,}" in *"$KEYID"*) : ;; *) unsigned=$((unsigned + 1)) ;; esac
    done
    if ((total > 0 && unsigned == 0)); then
      pass "the $total published packages are signed by the key the sources publish ($KEYID)"
    elif ((total > 0)); then
      fail "$unsigned of $total packages are unsigned, or signed by another key"
    fi
    if test -f "$OUTDIR/repodata/repomd.xml.asc"; then
      V=$(mktemp -d)
      if gpg --homedir "$V" --batch --quiet --import -- "$KEYRING" 2>/dev/null && \
         gpg --homedir "$V" --batch --quiet --trust-model always \
             --verify -- "$OUTDIR/repodata/repomd.xml.asc" "$OUTDIR/repodata/repomd.xml" 2>/dev/null; then
        pass "repomd.xml.asc verifies against that same key (what repo_gpgcheck=1 reads)"
      else
        fail "repomd.xml.asc does not verify against $KEYRING"
      fi
      rm -rf -- "$V"
    else
      skip "no repomd.xml.asc: this directory was indexed without \`--sign'"
    fi
  else
    skip "no archive key, gpg or rpm on this host: the signature was not measured"
  fi

  # ------------------------------------- and the stanza we PUBLISH, not the one the bench uses
  # This case exists because everything above measures a `gpgkey=file://' the bench itself
  # wrote, while what a reader actually gets is `marionnet.repo' from the release directory.
  # Measuring one and shipping the other is how a channel goes green while being broken --
  # and it WAS broken: with `gpgkey=' naming git.launchpad.net, dnf follows the 302 towards
  # the OpenID login page it answers about one request in six, imports 26 bytes, and the
  # transaction dies AFTER downloading the packages (3 failures in 8, measured). dnf cannot
  # be told not to follow redirects, so the key is named as a local file and fetched by hand.
  REPO_STANZA="$OUTDIR/marionnet.repo"
  if test -n "$REPO_URL"; then
    fetch_to "$REPO_URL/marionnet.repo" "$CACHE/marionnet.repo" >/dev/null 2>&1 \
      && REPO_STANZA="$CACHE/marionnet.repo"
  fi
  if ! test -f "$REPO_STANZA"; then
    skip "no marionnet.repo published (release.dnf.sh was run without --base-url)"
  elif grep -qE '^[[:space:]]*gpgkey[[:space:]]*=[[:space:]]*https?://' -- "$REPO_STANZA"; then
    fail "marionnet.repo fetches its key over http(s): dnf follows redirects, and the key host does redirect"
  elif grep -qE '^[[:space:]]*gpgkey[[:space:]]*=[[:space:]]*file://' -- "$REPO_STANZA"; then
    pass "marionnet.repo names the key as a local file (fetched and checked by the reader)"
  else
    skip "the published marionnet.repo declares no gpgkey (unsigned directory)"
  fi

  BOX2="$BOX-repo"
  docker rm -f "$BOX2" >/dev/null 2>&1
  # Nothing is mounted in a remote run: the repository under test is on the other side of
  # the network, which is the whole point of the exercise.
  MOUNT2=(-v "$OUTDIR:/repo:ro")
  test -z "$REPO_URL" || MOUNT2=()
  BASE_URL=${REPO_URL:-file:///repo}
  if docker run -d --name "$BOX2" "${MOUNT2[@]}" "$DISTRO" sleep infinity >/dev/null 2>&1; then
    function in_box2 { docker exec "$BOX2" bash -c "$1"; }

    # SIGNED SINCE EPISODE 30b, and the stanza says so. Unlike apt -- where one signature on
    # Release chains down to the packages by digest -- rpm has TWO mechanisms: gpgcheck
    # verifies each package (rpmsign put that signature inside it) and repo_gpgcheck verifies
    # the index (repomd.xml.asc). Both are asked for here, or this bench would measure neither.
    #
    # The key is handed over OUT OF BAND, by `docker cp' from the source tree, exactly as the
    # .deb bench does and for the same reason: the worth of a signature is that its key does
    # not travel beside the packages it signs. `gpgkey=file://' then costs no network.
    ARCHIVE_KEY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/marionnet-archive-keyring.asc"
    KEY_IN_BOX=/etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet
    REPO_SIGNED=0
    test -f "$OUTDIR/repodata/repomd.xml.asc" && REPO_SIGNED=1
    function install_archive_key2 {  # <container>
      docker exec "$1" mkdir -p /etc/pki/rpm-gpg
      docker cp -- "$ARCHIVE_KEY" "$1:$KEY_IN_BOX" >/dev/null
    }
    # AND IMPORTED -- BUT `rpm --import' IS NOT THE IMPORT THAT COUNTS HERE, measured on the
    # three dnf boxes: rpm's own database is what `gpgcheck' (each package) reads, while
    # `repo_gpgcheck' (the index) is verified by dnf5 against a keyring OF ITS OWN, per
    # repository, which `rpm --import' does not feed. So after `rpm --import' a bare
    # `dnf -q list' still gave up on the repository and reported ZERO packages -- a red which
    # looked exactly like a broken repository and was in fact a key nobody had accepted.
    #
    # Accepting a key is an action dnf ASKS FOR, so the bench performs it explicitly, once,
    # with the only spelling that answers the question (`-y'). That is also what a human does:
    # dnf shows the fingerprint and waits. Everything measured afterwards is then measured on a
    # machine which has agreed to trust this key, and nothing else -- which is precisely what
    # the foreign-key case below has to break.
    if ((REPO_SIGNED)); then
      install_archive_key2 "$BOX2"
      in_box2 "rpm --import $KEY_IN_BOX" >/dev/null 2>&1 || true
    fi
    if ((REPO_SIGNED)); then
      GPG_STANZA="gpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file://$KEY_IN_BOX"
    else
      GPG_STANZA="gpgcheck=0"
    fi
    case "$FAMILY" in
      dnf)    in_box2 'if test -f /etc/redhat-release && ! grep -qi fedora /etc/redhat-release; then
                         dnf -y install epel-release >/dev/null 2>&1 || true
                         dnf -y install dnf-plugins-core >/dev/null 2>&1 || true
                         dnf config-manager --set-enabled crb >/dev/null 2>&1 || true
                       fi'
              in_box2 "printf '[marionnet]\nname=Marionnet\nbaseurl=$BASE_URL\nenabled=1\n$GPG_STANZA\n' > /etc/yum.repos.d/marionnet.repo" ;;
      zypper) if ((REPO_SIGNED)); then
                in_box2 "rpm --import $KEY_IN_BOX >/dev/null 2>&1
                         zypper --non-interactive addrepo --gpgcheck $BASE_URL marionnet >/dev/null 2>&1
                         zypper --non-interactive refresh >/dev/null 2>&1"
              else
                in_box2 "zypper --non-interactive addrepo --no-gpgcheck $BASE_URL marionnet >/dev/null 2>&1
                         zypper --non-interactive --no-gpg-checks refresh >/dev/null 2>&1"
              fi ;;
    esac
    # NO --no-gpg-checks when the repository is signed: waiving the check is exactly what this
    # episode exists to stop doing, and a bench which waives it measures nothing about it.
    function pm2_install { case "$FAMILY" in
        dnf)    in_box2 "dnf -y install $* >/dev/null 2>&1" ;;
        zypper) if ((REPO_SIGNED)); then in_box2 "zypper --non-interactive install $* >/dev/null 2>&1"
                else in_box2 "zypper --non-interactive --no-gpg-checks install $* >/dev/null 2>&1"; fi ;;
      esac; }

    # The key acceptance itself (see the comment above): `-y' is what lets dnf import the key
    # named by `gpgkey=' into its own keyring. Without this line the listing below reads a
    # repository dnf has just given up on.
    if ((REPO_SIGNED)) && [[ $FAMILY = dnf ]]; then
      in_box2 'dnf -y makecache >/dev/null 2>&1' || true
      if in_box2 'dnf -q repolist marionnet 2>/dev/null | grep -q marionnet'; then
        pass "dnf accepts the signed repository once its key is accepted (repo_gpgcheck=1)"
      else
        fail "dnf still refuses the repository after its key was accepted"
      fi
    fi
    case "$FAMILY" in
      dnf)    n=$(in_box2 'dnf -q list --available "marionnet*" vde2 uml-utilities 2>/dev/null | grep -c marionnet') ;;
      zypper) n=$(in_box2 'zypper --non-interactive search --repo marionnet 2>/dev/null | grep -c marionnet') ;;
    esac
    test "$n" -ge 3 && pass "dnf lists the packages of the repository" || \
      fail "dnf sees only $n package(s) in the repository"

    if pm2_install marionnet; then
      pass "dnf install marionnet -- by NAME, not by path"
      if in_box2 'rpm -q vde2 >/dev/null 2>&1 && rpm -q uml-utilities >/dev/null 2>&1'; then
        pass "vde2 and uml-utilities came WITH it, resolved from the same directory"
      else
        fail "the two third-party dependencies were not resolved from the repository"
      fi
      # The same gesture must give the same thing on both channels: `apt install marionnet'
      # brings the application alone, and so must this one. Recommends: was tried and measured
      # to be honoured for one of the two data packages and silently skipped for the other.
      if in_box2 'rpm -q marionnet-kernels >/dev/null 2>&1 || rpm -q marionnet-fs-guignol >/dev/null 2>&1'; then
        fail "a data package was installed although both are Suggests: (the Debian channel gives the application alone)"
      else
        pass "the data packages stayed out, as Suggests: and as on the Debian channel"
      fi
      case "$FAMILY" in
        dnf)    n=$(in_box2 'dnf -q repoquery --suggests marionnet 2>/dev/null | grep -c marionnet') ;;
        zypper) n=$(in_box2 'rpm -q --suggests marionnet 2>/dev/null | grep -c marionnet') ;;
      esac
      test "$n" -ge 2 && pass "and they are VISIBLE as suggestions ($n)" || \
        fail "the suggestions are not readable from the repository"
      pm2_install marionnet-kernels marionnet-fs-guignol
      if in_box2 'rpm -q marionnet-kernels >/dev/null 2>&1'; then
        pass "and they install on demand"
      else
        fail "the data packages cannot be installed from the repository"
      fi
      # A release directory legitimately holds several revisions of the application while one
      # replaces the other; the index must not hide any, and dnf must pick the newest.
      # The version is NOT spelled out here (episode 33): the pattern used to say
      # `marionnet-0~trunk+r*', which stopped matching the day META named a series -- and a
      # pattern that matches nothing turns this case into a silent SKIP. What is invariant is
      # the `+r<digits>-<release>' the revision is written as, and it also keeps the data
      # packages out (they carry no `+r' at all).
      newest=$(ls "$OUTDIR"/marionnet-*+r*.rpm 2>/dev/null \
                 | sed -n 's/.*\/marionnet-.*+r\([0-9]\+\)-[0-9]\+\..*\.rpm$/\1/p' | sort -n | tail -1)
      chosen=$(in_box2 'rpm -q --qf "%{VERSION}" marionnet 2>/dev/null' | sed 's/.*+r//')
      if test -n "$newest" && test "$chosen" = "$newest"; then
        pass "with several revisions published, dnf chose the newest (r$chosen)"
      elif test -n "$chosen"; then
        skip "only one revision published (r$chosen)"
      fi
    else
      fail "dnf install marionnet failed from the repository"
    fi
    # ------------------------------------------ and a foreign key must make it all fall down
    # Without this, everything above would go green on a box which verifies nothing.
    #
    # IT NEEDS A THIRD, VIRGIN BOX, and that is a fact about rpm worth keeping: a key which has
    # been imported STAYS in rpm's own database, so rewriting `gpgkey=' in BOX2 would change
    # where dnf fetches a key it already has, and nothing else -- the case went green on a
    # repository which was still being verified with OUR key (measured). The foreign key is the
    # distribution's own, which every RPM box carries: a real key, simply not ours.
    if ((REPO_SIGNED)) && [[ $FAMILY = dnf ]]; then
      BOX3="$BOX-foreign"
      docker rm -f "$BOX3" >/dev/null 2>&1
      if docker run -d --name "$BOX3" "${MOUNT2[@]}" "$DISTRO" sleep infinity >/dev/null 2>&1; then
        function in_box3 { docker exec "$BOX3" bash -c "$1"; }
        foreign=$(in_box3 "ls -1 /etc/pki/rpm-gpg/RPM-GPG-KEY-* 2>/dev/null | head -1" || true)
        if [[ -n ${foreign:-} ]]; then
          in_box3 "printf '[marionnet]\nname=Marionnet\nbaseurl=$BASE_URL\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=file://$foreign\n' \
                     > /etc/yum.repos.d/marionnet.repo" >/dev/null 2>&1 || true
          in_box3 "dnf -y install marionnet" >/dev/null 2>&1 || true
          if in_box3 'rpm -q marionnet >/dev/null 2>&1'; then
            fail "dnf installed marionnet with a FOREIGN key in gpgkey=: nothing is verified"
          else
            pass "dnf REFUSES the repository when gpgkey= names another key ($(basename "$foreign"))"
          fi
        else
          skip "this box carries no distribution key to offer as a foreign one"
        fi
        ((KEEP)) && info "container kept: $BOX3" || docker rm -f "$BOX3" >/dev/null 2>&1
      else
        skip "cannot start the third container"
      fi
    fi
    ((KEEP)) && info "container kept: $BOX2" || docker rm -f "$BOX2" >/dev/null 2>&1
  else
    skip "cannot start the second container"
  fi
fi

# ----------------------------------------------------------------
echo "---- $PASSED passed, $FAILED failed, $SKIPPED skipped"
((FAILED)) && exit 1
exit 0
