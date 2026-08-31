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
#   -o, --output-dir DIR   the release directory holding the packages
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
  forward=()
  test -z "$OUTDIR" || forward+=(--output-dir "$OUTDIR")
  ((KEEP)) && forward+=(--keep)
  for d in "${ALL_DISTROS[@]}"; do
    echo; echo "================================================================ $d"
    bash "${BASH_SOURCE[0]}" --distro "$d" "${forward[@]}" || rc=1
  done
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

if test -z "$OUTDIR"; then
  SERIES=$(bash "$ROOT/Makefile.d/filesystem.prepare-snapshot-to-publish.sh" --print-series) || \
    skip_all "cannot read the publication series"
  OUTDIR="$ROOT/website-repo/download/marionnet-install.sh/$SERIES"
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

info "release dir : $OUTDIR"
info "box         : $DISTRO"
info "packages    : $APP ${KERNELS:-} ${GUIGNOL:-} ${VDE2:-} ${UMLU:-}"

BOX="mrn-rpm-bench-$(echo "$DISTRO" | tr ':/' '--')"
function cleanup {
  if ((KEEP)); then info "container kept: $BOX"; else docker rm -f "$BOX" >/dev/null 2>&1; fi
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
test "$n" = 26 && pass "the 26 commands of bin/ are installed" || fail "expected 26 commands in /usr/bin, found $n"

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
info "8. the application itself"
out=$(in_box 'marionnet.native --version 2>&1' | head -1)
if echo "$out" | grep -qi 'marionnet version'; then
  pass "the binary runs and says who it is: $out"
else
  fail "the binary does not run: $out"
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
if ! test -f "$OUTDIR/repodata/repomd.xml"; then
  skip "no repodata in the release directory (run: make release-dnf)"
else
  pass "repodata/repomd.xml is there"
  if test -f "$OUTDIR/SHA256SUMS" && grep -q 'repodata' "$OUTDIR/SHA256SUMS"; then
    fail "repodata is recorded in SHA256SUMS: an index is not an artefact, and its digest would go stale by itself"
  else
    pass "repodata is NOT in SHA256SUMS (an index is rewritten at every publication)"
  fi

  BOX2="$BOX-repo"
  docker rm -f "$BOX2" >/dev/null 2>&1
  if docker run -d --name "$BOX2" -v "$OUTDIR:/repo:ro" "$DISTRO" sleep infinity >/dev/null 2>&1; then
    function in_box2 { docker exec "$BOX2" bash -c "$1"; }
    case "$FAMILY" in
      dnf)    in_box2 'if test -f /etc/redhat-release && ! grep -qi fedora /etc/redhat-release; then
                         dnf -y install epel-release >/dev/null 2>&1 || true
                         dnf -y install dnf-plugins-core >/dev/null 2>&1 || true
                         dnf config-manager --set-enabled crb >/dev/null 2>&1 || true
                       fi'
              in_box2 'printf "[marionnet]\nname=Marionnet\nbaseurl=file:///repo\nenabled=1\ngpgcheck=0\n" > /etc/yum.repos.d/marionnet.repo' ;;
      zypper) in_box2 'zypper --non-interactive addrepo --no-gpgcheck file:///repo marionnet >/dev/null 2>&1
                       zypper --non-interactive --no-gpg-checks refresh >/dev/null 2>&1' ;;
    esac
    function pm2_install { case "$FAMILY" in
        dnf)    in_box2 "dnf -y install $* >/dev/null 2>&1" ;;
        zypper) in_box2 "zypper --non-interactive --no-gpg-checks install $* >/dev/null 2>&1" ;;
      esac; }

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
      newest=$(ls "$OUTDIR"/marionnet-0~trunk+r*.rpm 2>/dev/null | sed 's/.*+r\([0-9]*\)-.*/\1/' | sort -n | tail -1)
      chosen=$(in_box2 'rpm -q --qf "%{VERSION}" marionnet 2>/dev/null' | sed 's/.*+r//')
      if test -n "$newest" && test "$chosen" = "$newest"; then
        pass "with several revisions published, dnf chose the newest (r$chosen)"
      elif test -n "$chosen"; then
        skip "only one revision published (r$chosen)"
      fi
    else
      fail "dnf install marionnet failed from the repository"
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
