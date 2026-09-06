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

# Bench: `marionnet-sudoers.sh check' asks SUDO, not only its own file.
# Work-stream modernisation-installation-marionnet, episode 48.
#
# Reported from a classroom (2026-09-06): the file was perfect -- `install' answered
# "already up to date for: %student %teacher student teacher" and it was TRUE -- and
# sudo asked for a password on every privileged gesture of Marionnet. The cause was a
# neighbouring file: /etc/sudoers.d/student holding a plain `student ALL=(ALL:ALL) ALL',
# which sorts AFTER `marionnet' and therefore wins, sudoers keeping the LAST matching
# rule. Nothing we shipped could see it: every one of our tools judged the file.
#
# So `check' now asks the only authority, and it asks it the REAL question. `sudo -l'
# will not do: measured, `sudo -n -l /bin/true' exits 0 on a machine where running
# /bin/true would prompt -- it answers "may this user run it", not "without a
# password". The probe is therefore the one the runtime itself uses
# (Tap_provider.unavailability): `sudo -n ip tuntap del' of a tap that does not exist.
#
# No privilege and no device here: MARIONNET_SUDOERS_DIR moves the file to a temporary
# directory, and `sudo' itself is replaced through the PATH -- the technique of episode
# 41. What the bench measures is the VERDICT (exit status 5, and a diagnosis naming the
# mechanism), never a real sudoers file: it does not go near /etc.
#
# Deliberately no `set -e': several commands here are EXPECTED to fail.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly TOOL="${1:-$ROOT/bin/scripts/marionnet-sudoers.sh}"
readonly CHECK_REFUSED=5

declare -i passed=0 failed=0 skipped=0
declare tmpdir=""

cleanup() {
  local d="$tmpdir"
  if [[ -n "$d" && "$d" == /tmp/marionnet-sudoers-bench.* && -d "$d" ]]; then rm -rf -- "$d"; fi
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }

# fake_sudo <behaviour>: writes a `sudo' the probe will find first in the PATH.
#   granted  -- runs nothing, succeeds, as a NOPASSWD rule would
#   refused  -- sudo's own refusal, the sentence the needles look for
#   broken   -- the command ran and failed for a reason of its own (no device):
#               a failure which is NOT a refusal, and must not be read as one
fake_sudo() {
  cat > "$tmpdir/bin/sudo" <<FAKE
#!/bin/bash
case "$1" in
  granted) exit 0 ;;
  refused) echo "sudo: a password is required" 1>&2; exit 1 ;;
  broken)  echo "open: No such file or directory" 1>&2; exit 1 ;;
esac
FAKE
  chmod +x "$tmpdir/bin/sudo"
}

# verdict: the exit status of `check' with the fake sudo in front of the PATH.
verdict() {
  PATH="$tmpdir/bin:$PATH" MARIONNET_SUDOERS_DIR="$tmpdir/sudoers.d" \
    "$TOOL" check "$USER" >"$tmpdir/out" 2>"$tmpdir/err"
  echo $?
}

# --- the bench itself

if [[ ! -x "$TOOL" ]]; then echo "SKIP: no executable at $TOOL"; exit 77; fi
for t in ip id; do command -v "$t" >/dev/null || { echo "SKIP: $t is not installed"; exit 77; }; done
# ip_binary looks for the real iproute2 in the usual absolute paths.
ls /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip >/dev/null 2>&1 || { echo "SKIP: no iproute2"; exit 77; }

tmpdir=$(mktemp -d /tmp/marionnet-sudoers-bench.XXXXXX) || exit 1
mkdir -p "$tmpdir/bin" "$tmpdir/sudoers.d"
echo "Bench: check asks sudo, not only its own file — $TOOL"

# The file the tool itself would write for this account, put where it will look for
# it. Ordinary ownership on purpose: this is a copy for reading, not a sudoers file.
# stderr is dropped on purpose: from a source tree the tool rightly REFUSES to grant
# the tun door (a NOPASSWD rule naming a script its owner can replace is a root shell),
# and says so at length. That refusal is another episode's subject, not this one's.
if ! "$TOOL" print "$USER" 2>/dev/null | sed '/^# >>> /d' > "$tmpdir/sudoers.d/marionnet"; then
   echo "SKIP: could not generate the block for $USER"; exit 77
fi
if ! grep -q "^$USER ALL=(root) NOPASSWD:" "$tmpdir/sudoers.d/marionnet"; then
   echo "SKIP: the generated block does not name $USER, nothing to measure"; exit 77
fi

# 1. Control: the file grants, and sudo honours it. Without this case a `check'
#    which always answered 5 would pass the case below while proving nothing.
fake_sudo granted
rc=$(verdict)
if [[ "$rc" == 0 ]]; then pass "a grant sudo honours is reported as granted (0)"
else fail "a grant sudo honours should be 0, got $rc: $(tail -2 "$tmpdir/err" | tr '\n' ' ')"; fi

# 2. The episode: the file grants, sudo refuses anyway.
fake_sudo refused
rc=$(verdict)
if [[ "$rc" == "$CHECK_REFUSED" ]]; then pass "a grant sudo refuses is reported as refused ($CHECK_REFUSED)"
else fail "a grant sudo refuses should be $CHECK_REFUSED, got $rc"; fi
if grep -q "sudo REFUSES it" "$tmpdir/err"; then pass "the diagnosis says sudo refuses, not that the file is wrong"
else fail "the diagnosis does not name the refusal: $(tail -3 "$tmpdir/err" | tr '\n' ' ')"; fi
if grep -q "LAST matching rule wins" "$tmpdir/err"; then pass "the diagnosis names the mechanism (last match wins), not a re-install"
else fail "the diagnosis does not name the mechanism"; fi

# 3. Anti-false-positive: a command which merely FAILED is not a refusal. Reading
#    every failure as "sudo refuses" would send an administrator hunting for a rule
#    that is not in question -- the very defect this work-stream keeps meeting.
fake_sudo broken
rc=$(verdict)
if [[ "$rc" == 0 ]]; then pass "a probe that failed without being refused is not read as a refusal (0)"
else fail "a mere failure should stay 0, got $rc"; fi

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
[[ $failed -eq 0 ]] || exit 1
[[ $passed -gt 0 ]] || exit 77
exit 0
