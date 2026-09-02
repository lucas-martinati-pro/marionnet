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

# Bench: when a NAT bridge cannot be built, the warning names the cause it MEASURED, in the
# language of the user -- and the guard which should have prevented the commonest cause asks
# the right question. Work-stream modernisation-installation-marionnet, episode 41.
#
# What was reported (a lab room of MarioNUM, 2026-09-02): starting a NAT bridge showed
#   title  : "Bridge NAT « N1 » : aucun réseau privé"          (French)
#   body   : "Marionnet could not build the private bridge..." (English, in a French session)
#   advice : "...choose another IPv4 address..."               (about the network)
# while the diagnostic in between said E_SUDO_DENIED -- sudo asking for a password. Three
# independent defects, and this bench measures the three:
#
#   1. THE CAUSE. Privileges.ensure_block returns Ok WITHOUT ever offering the password as
#      soon as its probe says yes (privileges.ml), and the probe of the NAT bridge was
#      `marionnet-natbridge.sh status', which of everything block (b) grants exercises ONE
#      command, iptables-save. A rule granting that line and not `ip link add' therefore
#      passed the guard. The probe is now `check-privileges', modelled on the one the LAN
#      bridge has had since episode 7b: a real command of our own list, on a bridge name no
#      run can produce. Cases 1-3 measure that sub-command, and case 4 that the application
#      really asks it.
#   2. THE LANGUAGE. The message was written with `\'-continuations, indented: OCaml eats the
#      newline AND the blanks, the camlp4 POT extractor does not, so the msgid in the 12
#      catalogues could never match the string the program asks for. Case 5 is that exactly,
#      and it is self-guarding: the TITLE (which never had the defect) says whether a French
#      catalogue was found at all.
#   3. THE ADVICE. Cases 6-10: one message per cause, and none at all for a code we do not
#      know -- inventing a remedy is the defect being fixed.
#
# No privilege and no guest are needed: the host command is replaced by a fake one
# (MARIONNET_NATBRIDGE_SCRIPT), and the probe cases replace `sudo' itself through PATH. What
# the fake ones do NOT replace is the code under test: the OCaml classifier and the real
# do_check_privileges of the real script.
#
# Deliberately no `set -e': several commands here EXPECT a non-zero answer.
set -uo pipefail

readonly SELF="${BASH_SOURCE[0]}"
readonly ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
readonly BIN="${1:-$ROOT/_build/default/bin/marionnet.exe}"
readonly SCRIPT="$ROOT/bin/scripts/marionnet-natbridge.sh"

declare -i passed=0 failed=0 skipped=0
declare tmpdir="" sock="" pid="" fakehome="" journal="" mrn_pid="" calls=""

session_pid_from_channel() {
  local answer
  answer=$(ask status)
  [[ "$answer" =~ \"pid\"[[:space:]]*:[[:space:]]*([0-9]+) ]] && echo "${BASH_REMATCH[1]}"
}

session_pid() {
  local candidate="${mrn_pid:-}"
  [[ -n "$candidate" ]] || candidate=$(cat "/proc/${pid:-0}/task/${pid:-0}/children" 2>/dev/null)
  echo "${candidate%% *}"
}

# By exact pid, and only once /proc has confirmed it still is ours (a pid gets recycled; the
# socket path is unique to this run). SIGKILL because marionnet neutralises SIGTERM.
kill_the_session() {
  local -i target="${1:-0}" i
  (( target > 1 )) || return 0
  kill -0 "$target" 2>/dev/null || return 0
  grep -qz -- "$sock" "/proc/$target/cmdline" 2>/dev/null || return 0
  kill -9 "$target" 2>/dev/null
  for ((i = 0; i < 100; i++)); do kill -0 "$target" 2>/dev/null || return 0; sleep 0.1; done
}

cleanup() {
  kill_the_session "$(session_pid)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
     kill "$pid" 2>/dev/null
     wait "$pid" 2>/dev/null
  fi
  local d="$tmpdir"
  # Guard: never let an empty or short variable turn this into a wide removal.
  if [[ -n "$d" && "$d" == /tmp/marionnet-bench.* && -d "$d" ]]; then
     rm -rf -- "$d"
  fi
}
trap cleanup EXIT

pass() { echo "PASS: $*"; passed+=1; }
fail() { echo "FAIL: $*"; failed+=1; }
skip() { echo "SKIP: $*"; skipped+=1; }

ask() { echo "$1" | timeout 120 socat -t 60 -T 90 - "UNIX-CONNECT:$sock" 2>/dev/null; }

json_field() {   # json_field FIELD  -- one scalar out of one JSON object, on stdin
  python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get(sys.argv[1]); print("" if v is None else v)' "$1" 2>/dev/null
}

# --- part one: the probe of the script itself -------------------------------------------------
#
# `sudo' is replaced through PATH, so the three answers that matter can be played on any host,
# with no rule installed and no password: a refusal by sudo, the wording iproute2 itself
# produces when the rule DID let the command through (the device does not exist -- that is the
# whole point of the probe), and a plain success.

fake_sudo_saying() {   # fake_sudo_saying MODE
  cat > "$tmpdir/bin/sudo" <<EOF
#!/bin/bash
case "\$MODE" in
  deny)        echo "sudo: a password is required" 1>&2; exit 1 ;;
  not-found)   echo 'Cannot find device "mnbr999999999"' 1>&2; exit 1 ;;
  ok)          exit 0 ;;
esac
exit 1
EOF
  chmod +x "$tmpdir/bin/sudo"
  export MODE="$1"
}

probe_verdict() {   # probe_verdict -- what check-privileges answers, as true|false|<empty>
  PATH="$tmpdir/bin:$PATH" "$SCRIPT" check-privileges 2>/dev/null | json_field privileged
}

case_probe_refused() {
  fake_sudo_saying deny
  local verdict; verdict=$(probe_verdict)
  if [[ "$verdict" == "False" || "$verdict" == "false" ]]; then
     pass "check-privileges: sudo refusing a password answers privileged=false"
  else
     fail "check-privileges: sudo refused, yet the answer is '$verdict' (expected false)"
  fi
}

case_probe_let_through() {
  # The command RAN and failed on its own terms: rc is 1 all the same, so the verdict can only
  # be read in the wording -- hence LC_ALL=C in the script, sudo's diagnostics being translated
  # and iproute2's not.
  fake_sudo_saying not-found
  local verdict; verdict=$(probe_verdict)
  if [[ "$verdict" == "True" || "$verdict" == "true" ]]; then
     pass "check-privileges: iproute2 answering \"Cannot find device\" answers privileged=true"
  else
     fail "check-privileges: the command went through, yet the answer is '$verdict' (expected true)"
  fi
}

case_probe_plain_success() {
  fake_sudo_saying ok
  local verdict; verdict=$(probe_verdict)
  if [[ "$verdict" == "True" || "$verdict" == "true" ]]; then
     pass "check-privileges: a command that simply succeeds answers privileged=true"
  else
     fail "check-privileges: rc 0, yet the answer is '$verdict' (expected true)"
  fi
}

# --- part two: the session --------------------------------------------------------------------

# The fake host command: everything nat_bridge_host.ml may ask, with the failure code of the
# moment for `up'. It also RECORDS its sub-commands, which is what case 4 reads.
write_fake_host_command() {
  cat > "$tmpdir/fake-natbridge.sh" <<'EOF'
#!/bin/bash
# Fake marionnet-natbridge.sh, for driven-sessions/nat-bridge-warning-names-its-cause.sh.
here=$(dirname "$0")
echo "$1" >> "$here/calls"
case "$1" in
  check-privileges) echo '{"privileged":true,"ok":true}' ;;
  status)           echo '{"bridges":[],"ok":true}' ;;
  check-ipv6)       echo '{"uplink":false,"ok":true}' ;;
  up)               code=$(cat "$here/code" 2>/dev/null || echo E_SUDO_DENIED)
                    printf '{"ok":false,"error":"%s","message":"the host command refused"}\n' "$code"
                    exit 1 ;;
  *)                echo '{"ok":true}' ;;
esac
EOF
  chmod +x "$tmpdir/fake-natbridge.sh"
}

# One component per cause: the warning is shown ONCE per start-up (already_warned), and a
# component whose bridge never came up is not re-armed by a stop.
#
# The notification is picked by the NAME of its component, never by its rank: a machine with
# abandoned session directories greets every session with a warning of its own (measured), and
# a bench that reads "the last one" would read that.
# The name is an ARGUMENT and not a counter: every call below happens inside a command
# substitution, i.e. in a subshell, where an incremented counter dies with it -- and every
# component would then be called N1, the second `add' refusing a name already taken.
warning_for_code() {   # warning_for_code NAME CODE -- the body of the warning, or empty
  local name="$1" code="$2" answer body
  echo "$code" > "$tmpdir/code"
  answer=$(ask "add nat_bridge $name")
  [[ "$answer" == *'"ok":true'* ]] || { echo "add $name: $answer" >> "$tmpdir/refusals"; echo ""; return 1; }
  answer=$(ask "start $name")
  [[ "$answer" == *'"ok":true'* ]] || { echo "start $name: $answer" >> "$tmpdir/refusals"; echo ""; return 1; }
  local -i i
  for ((i = 0; i < 60; i++)); do
     body=$(ask "notifications" | python3 -c '
import json,sys
d=json.load(sys.stdin)
name=sys.argv[1]
hit=[n for n in d.get("notifications",[]) if name in n.get("title","")]
print(hit[-1]["body"] if hit else "")' "$name" 2>/dev/null)
     [[ -n "$body" ]] && { echo "$body"; return 0; }
     sleep 0.5
  done
  echo ""
  return 1
}

title_of_component() {   # title_of_component NAME
  ask "notifications" | python3 -c '
import json,sys
d=json.load(sys.stdin)
name=sys.argv[1]
hit=[n for n in d.get("notifications",[]) if name in n.get("title","")]
print(hit[-1]["title"] if hit else "")' "$1" 2>/dev/null
}

case_the_application_asks_the_probe() {
  # The point of the episode: before it, the only sub-commands a start-up used were `status'
  # and `up'.
  if grep -qx "check-privileges" "$calls" 2>/dev/null; then
     pass "the application probes the host with check-privileges (not with status)"
  else
     fail "no check-privileges among the sub-commands the application called: $(sort -u "$calls" | tr '\n' ' ')"
  fi
}

case_body_is_translated() {
  local body="$1" title="$2"
  local english="Marionnet could not build the private bridge"
  if [[ "$title" != *"Bridge NAT"* && "$title" != *"pont"* && "$title" != *"réseau privé"* ]]; then
     skip "the body's language: no French catalogue was found (the title itself is '$title')"
     return
  fi
  if [[ "$body" == *"$english"* ]]; then
     fail "the title is French and the body is English: the msgid does not match what the program asks for"
  else
     pass "the body is translated like its title (the msgid matches the string the program asks for)"
  fi
}

advice_of() {   # advice_of BODY -- what follows the raw diagnostic, if anything
  printf '%s' "${1##*</tt>}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

case_advice_for() {   # case_advice_for NAME CODE NEEDLE FORBIDDEN LABEL
  local name="$1" code="$2" needle="$3" forbidden="$4" label="$5" body advice
  body=$(warning_for_code "$name" "$code") || { fail "$label: no warning was shown at all"; return; }
  advice=$(advice_of "$body")
  if [[ "$advice" != *"$needle"* ]]; then
     fail "$label: the advice does not name '$needle': ${advice:-(none)}"
     return
  fi
  if [[ -n "$forbidden" && "$advice" == *"$forbidden"* ]]; then
     fail "$label: the advice still carries '$forbidden'"
     return
  fi
  pass "$label: the advice names '$needle'"
}

case_no_advice_for_an_unknown_code() {
  local body advice
  body=$(warning_for_code "N5" "E_ROLLBACK_INCOMPLETE") || { fail "unknown code: no warning at all"; return; }
  advice=$(advice_of "$body")
  if [[ -z "$advice" ]]; then
     pass "a code we do not classify gets the diagnostic and no invented remedy"
  else
     fail "a code we do not classify got an advice all the same: $advice"
  fi
}

# --- main -------------------------------------------------------------------------------------

if [[ ! -x "$BIN" ]]; then
   echo "SKIP: no executable at $BIN (build it first: dune build)"
   exit 77
fi
if [[ ! -x "$SCRIPT" ]]; then
   echo "SKIP: no host command at $SCRIPT"
   exit 77
fi
if [[ -z "${DISPLAY:-}" ]]; then
   echo "SKIP: this bench drives a real session, which needs a DISPLAY (marionnet initialises Gtk+)"
   exit 77
fi
if ! command -v socat >/dev/null; then
   echo "SKIP: socat is needed to talk to the control channel"
   exit 77
fi

tmpdir=$(mktemp -d /tmp/marionnet-bench.XXXXXX) || exit 1
mkdir -p "$tmpdir/bin" "$tmpdir/home"
fakehome="$tmpdir/home"
journal="$tmpdir/journal"
calls="$tmpdir/calls"
# sun_path holds 107 bytes: the socket cannot live under a long temporary path.
sock=$(mktemp -u /tmp/mrn-bench-XXXXXX.sock)
echo "Bench: the NAT bridge warning names the cause it measured — $BIN"

case_probe_refused
case_probe_let_through
case_probe_plain_success
unset MODE

write_fake_host_command

# LANGUAGE=fr is the point of case 5: the report was written by a French user. LC_ALL is left
# alone -- gettext reads LANGUAGE first, and the bench must not depend on the locales installed.
timeout -k 5 300 env HOME="$fakehome" LANGUAGE=fr \
   MARIONNET_NATBRIDGE_SCRIPT="$tmpdir/fake-natbridge.sh" \
   "$BIN" --debug --control-socket "$sock" >/dev/null 2>"$journal" &
pid=$!
for ((i = 0; i < 90; i++)); do [[ -S "$sock" ]] && break; sleep 1; done
[[ -S "$sock" ]] || { echo "FAIL: no socket at $sock after 90s"; exit 1; }
mrn_pid=$(session_pid_from_channel)

[[ "$(ask "new $tmpdir/bench.mar")" == *'"ok":true'* ]] || {
   echo "FAIL: could not create the project"; exit 1; }

# The first component carries three cases at once: the probe was asked, the body is in the
# language of the title, and the advice is the one E_SUDO_DENIED deserves.
body=$(warning_for_code "N1" "E_SUDO_DENIED")
if [[ -z "$body" ]]; then
   echo "FAIL: no warning was shown for E_SUDO_DENIED"; failed+=1
   [[ -s "$tmpdir/refusals" ]] && sed 's/^/      /' "$tmpdir/refusals"
else
   title=$(title_of_component N1)
   case_the_application_asks_the_probe
   case_body_is_translated "$body" "$title"
   advice=$(advice_of "$body")
   if [[ "$advice" == *"--enable-natbridge"* ]]; then
      pass "E_SUDO_DENIED: the advice names the command which grants the sudoers rule"
   else
      fail "E_SUDO_DENIED: the advice does not name the sudoers command: ${advice:-(none)}"
   fi
   if [[ "$advice" == *"IPv4"* ]]; then
      fail "E_SUDO_DENIED: the advice still blames the chosen network (IPv4 address)"
   else
      pass "E_SUDO_DENIED: the advice no longer blames the chosen network"
   fi
fi

case_advice_for N2 E_SUBNET_IN_USE "IPv4"    "--enable-natbridge" "E_SUBNET_IN_USE"
case_advice_for N3 E_NO_DNSMASQ    "dnsmasq" "IPv4"               "E_NO_DNSMASQ"
case_advice_for N4 E_NO_IPROUTE2   "ip"      "IPv4"               "E_NO_IPROUTE2"
case_no_advice_for_an_unknown_code

ask quit >/dev/null
wait "$pid" 2>/dev/null
pid=""
mrn_pid=""

echo "---"
echo "passed: $passed, failed: $failed, skipped: $skipped"
(( failed == 0 )) || exit 1
exit 0
