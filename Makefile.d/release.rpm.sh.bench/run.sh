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
function rpm_named {  # <package name>: prints the file name of that package, or nothing
  local f base
  for f in "${RPMS[@]}"; do
    base=$(basename -- "$f")
    # <name>-<version>-<release>.<arch>.rpm: the name is what precedes the version, so the
    # candidate matches only if what follows its name is a dash and then a digit.
    [[ $base =~ ^$1-[0-9~] ]] && { echo "$base"; return 0; }
  done
  return 1
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
if in_box 'dnf -q repoquery vde2 2>/dev/null | grep -q .'; then
  fail "this distribution has a vde2 of its own: the third-party package is not needed here"
else
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
out=$(in_box "dnf -y install /rpms/$APP 2>&1"; true)
if echo "$out" | grep -q 'nothing provides /usr/bin/vde_switch' && \
   echo "$out" | grep -q 'nothing provides /usr/bin/uml_mconsole'; then
  pass "refused, naming BOTH missing files (and nothing else: the twelve others resolved)"
elif echo "$out" | grep -qiE 'complete!|installed'; then
  fail "the application installed although this box provides no vde_switch: it cannot work"
else
  fail "refused for an unexpected reason: $(echo "$out" | grep -iE 'nothing provides|problem' | tr '\n' ' ')"
fi

# ---------------------------------------------------------------- 2 bis. all five together
# And the counterpart of what episode 12 measured on Debian 12: a package built against a
# glibc newer than the box's must be refused, and the refusal must name it. Read from the
# METADATA rather than from a file name -- the whole gain of a package over a tarball.
info "2 bis. the five packages together"
out=$(in_box "dnf -y install /rpms/*.rpm 2>&1"; true)
if echo "$out" | grep -qiE 'complete!'; then
  pass "the five packages install together"
  INSTALLED=1
elif echo "$out" | grep -qiE 'libc\.so\.6|glibc'; then
  pass "refused, and the refusal names glibc (the constraint is metadata, not a file name)"
  INSTALLED=0
else
  fail "refused for a reason which is neither glibc nor named: $(echo "$out" | tail -3 | tr '\n' ' ')"
  INSTALLED=0
fi

if ((! INSTALLED)); then
  echo "---- $PASSED passed, $FAILED failed, $SKIPPED skipped (box too old for this build)"
  ((FAILED)) && exit 1 || exit 0
fi

# ---------------------------------------------------------------- 3. what dnf pulled by itself
info "3. the dependencies dnf resolved on its own"
in_box "dnf -y install /rpms/*.rpm >/dev/null 2>&1"

for probe in "vde_switch:vde2" "wirefilter:vde2" "slirpvde:vde2" "uml_mconsole:uml-utilities"; do
  cmd="${probe%%:*}"; from="${probe##*:}"
  if in_box "command -v $cmd >/dev/null"; then
    pass "$cmd is there (from our $from package)"
  else
    fail "$cmd is missing: Marionnet cannot run a single component without it"
  fi
done

for cmd in dot jq socat dnsmasq xterm xauth xrandr ip xz sudo; do
  if in_box "command -v $cmd >/dev/null"; then
    pass "$cmd pulled from the distribution"
  else
    fail "$cmd absent: a Requires: of the table did not resolve"
  fi
done

# The dependency the Debian channel had to WRITE (libc6:i386) and this one only had to let rpm
# derive, because both ELF classes sit in the same package and multilib is native here.
if test -n "$KERNELS"; then
  if in_box 'rpm -q glibc.i686 >/dev/null 2>&1'; then
    pass "glibc.i686 pulled BY DERIVATION (the 32-bit kernel's interpreter), no foreign architecture asked for"
  else
    fail "glibc.i686 absent: the i386 kernel cannot run"
  fi
fi

# The one runtime library, which no table names: rpm reads its soname out of the binary, and
# that soname resolves on both RPM families where the package names do not.
if in_box "rpm -q --requires marionnet 2>/dev/null | grep -q libgtksourceview-3.0.so.1"; then
  pass "libgtksourceview is required BY SONAME (derived, not translated)"
else
  fail "the gtksourceview dependency is not derived from the soname"
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

if test -n "$KERNELS"; then
  if in_box 'test -f /usr/share/marionnet/kernels/linux-6.12.95 && test -f /usr/share/marionnet/kernels/linux-6.12.95-i386'; then
    pass "both kernels are in one package (the i386 split has no reason to exist on RPM)"
  else
    fail "a kernel is missing from /usr/share/marionnet/kernels"
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
if in_box 'grep -q tsflags=nodocs /etc/dnf/dnf.conf 2>/dev/null'; then
  pass "this image sets tsflags=nodocs (so the guides are legitimately absent from it)"
  n=$(in_box "rpm -qpd /rpms/$APP 2>/dev/null | wc -l")
  test "$n" -ge 26 && pass "the package nevertheless CARRIES the $n documentation files" || \
    fail "the package carries only $n documentation files, expected at least 26"
  in_box "sed -i '/tsflags=nodocs/d' /etc/dnf/dnf.conf && dnf -y reinstall /rpms/$APP >/dev/null 2>&1"
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
in_box 'dnf -y install bash-completion >/dev/null 2>&1'
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
if in_box 'dnf -y remove marionnet >/dev/null 2>&1 && ! test -x /usr/bin/marionnet.native'; then
  pass "the application can be removed"
else
  fail "removing the application left it behind"
fi
if in_box 'test -f /etc/marionnet/marionnet.conf.rpmsave || test -f /etc/marionnet/marionnet.conf'; then
  pass "the edited configuration survives the removal (kept, or set aside as .rpmsave)"
else
  fail "the edited configuration was destroyed by the removal"
fi

# ----------------------------------------------------------------
echo "---- $PASSED passed, $FAILED failed, $SKIPPED skipped"
((FAILED)) && exit 1
exit 0
