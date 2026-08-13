#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
# Copyright (C) 2026  Université Sorbonne Paris Nord
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

# ---------------------------------------------------------------------------
# Guest-side END-OF-SESSION REPORT.  Deep logging, episode 7.
#
# This file belongs to NO guest image.  The host deposits it into the hostfs
# directory at every boot (`make_hostfs_content', bin/simulation_level.ml), and
# the epilogue `marionnet-relay.zz-journal' hooks it to the SHUTDOWN of the
# guest -- a systemd unit or a SysV `K01' link, whichever this guest uses.
#
# Its name deliberately does NOT start with `marionnet-relay': the relay sources
# /mnt/hostfs/marionnet-relay* at boot, and this script must not run then. What
# it says is only worth saying at the END of a session.
#
# WHY IT EXISTS.  In exam mode Marionnet imports <hostfs>/report.md into the
# `documents' treeview at a graceful shutdown (machine.ml, router.ml), hence
# into the .mar project file. That import has been reading a file nobody wrote
# since the historical producer died: it called `cfg2html', absent from every
# modern image, and reviving it would mean rebuilding images -- which decision
# D1 forbids. This is the replacement: sober, dependency-free, and written by
# the host into the guest rather than installed in it.
#
# WHY MARKDOWN and not HTML.  The producer is plain Bash inside a minimal guest:
# in HTML every command output would have to be escaped (`&', `<', `>'), and one
# unescaped `<' silently breaks the page. Here an output goes into a fenced
# block AS IS -- no transformation, so no corruption. A correcting agent reads
# it without walking tags, and a human reads it as plain text. The fences are
# FOUR backticks so that an output containing three (this happens) stays inside
# its block.
#
# Same three rules as the collector of episode 2, and for the same reason (this
# runs during a shutdown): never fatal, never unbounded (every command runs
# under `timeout' when the image has one), never noisy on the student's console.
#
# Plain Bash on purpose: this code runs inside the guest, which has no
# `bashbricks' (nor anything beyond a minimal userland).
# ---------------------------------------------------------------------------

# Episode 16: the same producer now answers to two callers -- the shutdown hook
# of the epilogue, and the watcher that serves an ON-DEMAND request.  The second
# one writes into a temporary file it then renames (a reader may be reading the
# published one), and the report must say WHEN it was taken: an instantaneous
# state is only worth what its timestamp says.  Both default to episode 7's
# behaviour, so a host that knows nothing of this changes nothing.
__mrn_report_out="${MARIONNET_REPORT_OUT:-/mnt/hostfs/report.md}"
__mrn_report_when="${MARIONNET_REPORT_WHEN:-shutdown}"

# Episode 20: what is asked here is a CAPACITY, never a presence.  `type -p
# timeout' answers yes on the router image (busybox, 2014), whose `timeout' has
# the old interface `timeout -t SECS PROG': the modern form then tries to run a
# program named after the number of seconds, and EVERY section of this report
# came back with "timeout: can't execute '5'".  Same lesson as episode 14 on
# `tee', same remedy: run the form we are about to use, once, and fall back
# silently on `eval' -- which this function has always been able to do.
__mrn_report_timeout="$(type -p timeout 2>/dev/null)"
if [[ -n "$__mrn_report_timeout" ]] && ! "$__mrn_report_timeout" 1 true >/dev/null 2>&1 ; then
  __mrn_report_timeout=""
fi
__mrn_report_deadline=5

# Nothing to do if the hostfs is not writable any more (the report is precisely
# what must not delay or break an ongoing shutdown):
{ : > "$__mrn_report_out" ; } 2>/dev/null || exit 0

# $1 = section title, $2... = candidate command lines; the FIRST one whose
# leading word exists in this guest is the one that runs.  A guest without any
# of them says so, instead of leaving an empty section.
__mrn_report_section() {
  local title="$1"; shift
  local candidate chosen=""
  for candidate in "$@"; do
    if type -p "${candidate%% *}" >/dev/null 2>&1; then chosen="$candidate"; break; fi
  done
  echo
  echo "## $title"
  echo
  if [[ -z "$chosen" ]]; then
    echo "_not available in this guest (tried: ${*})_"
    return 0
  fi
  echo '````text'
  echo "\$ $chosen"
  if [[ -n "$__mrn_report_timeout" ]]; then
    "$__mrn_report_timeout" "$__mrn_report_deadline" bash -c "$chosen" 2>&1 \
      || echo "(no output, failed or timed out: status $?)"
  else
    eval "$chosen" 2>&1 || echo "(no output or failed: status $?)"
  fi
  echo '````'
}

{
  __mrn_report_name="$(cat /mnt/hostfs/GUESTNAME 2>/dev/null)"
  [[ -n "$__mrn_report_name" ]] || __mrn_report_name="$(hostname 2>/dev/null)"

  if [[ "$__mrn_report_when" = on-demand ]]; then
    echo "# Marionnet — on-demand report: ${__mrn_report_name:-unknown}"
  else
    echo "# Marionnet — end-of-session report: ${__mrn_report_name:-unknown}"
  fi
  echo
  echo "- date: $(date '+%F %T %z' 2>/dev/null)"
  echo "- guest: $(uname -srm 2>/dev/null)"
  echo "- uptime:$(uptime 2>/dev/null | sed 's/^ *//')"
  echo "- exam mode: ${exam:-0}"
  echo "- taken: $__mrn_report_when"
  echo
  if [[ "$__mrn_report_when" = on-demand ]]; then
    echo "> Taken **while this guest was running**, on request (the channel's \`report\`"
    echo "> verb).  It is a SNAPSHOT: everything below was true at the date above and"
    echo "> may have changed since -- ask again to see the difference."
  else
    echo "> Taken **during the shutdown** of this guest, by a hook the host injected."
    echo "> Services already stopped at this point are missing from the process list;"
    echo "> the network configuration below is the one the session ended with."
  fi
  echo ">"
  echo "> Companions in the same directory: \`rc_config.log\` (what the startup"
  echo "> configuration did), \`boot.log\` (what the boot did before it), and"
  echo "> \`bash_history.text\` (the commands typed, each one dated)."

  echo
  echo "# Network"

  __mrn_report_section "Interfaces" \
    "ip -o addr show" "ifconfig -a"

  __mrn_report_section "Link layer" \
    "ip -o link show" "ifconfig -a"

  __mrn_report_section "Routing table (IPv4)" \
    "ip route show" "route -n"

  __mrn_report_section "Routing table (IPv6)" \
    "ip -6 route show" "route -6 -n"

  __mrn_report_section "Neighbours (ARP)" \
    "ip neigh show" "arp -an"

  __mrn_report_section "IP forwarding" \
    "sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding" \
    "cat /proc/sys/net/ipv4/ip_forward"

  __mrn_report_section "Name resolution" \
    "cat /etc/resolv.conf"

  __mrn_report_section "Persistent interface configuration" \
    "cat /etc/network/interfaces"

  echo
  echo "# Firewall"
  echo
  echo "The low-level tables, as a corrector wants to read them: the counted rules"
  echo "first, then the replayable form."

  __mrn_report_section "iptables — filter" \
    "iptables -L -vv -n"

  __mrn_report_section "iptables — nat" \
    "iptables -t nat -L -vv -n"

  __mrn_report_section "iptables — mangle" \
    "iptables -t mangle -L -vv -n"

  __mrn_report_section "iptables — replayable form" \
    "iptables-save"

  __mrn_report_section "ip6tables — filter" \
    "ip6tables -L -vv -n"

  __mrn_report_section "nftables — ruleset" \
    "nft list ruleset"

  echo
  echo "# System"

  __mrn_report_section "Listening sockets" \
    "ss -tulpn" "netstat -tulpn"

  __mrn_report_section "Services in failure" \
    "systemctl --failed --no-legend --no-pager"

  __mrn_report_section "Processes" \
    "ps aux" "ps -ef"

  __mrn_report_section "Mounted filesystems" \
    "df -h"

  __mrn_report_section "Mounts" \
    "cat /proc/mounts"

  echo
  echo "---"
  echo
  echo "_end of the report: $(date '+%F %T %z' 2>/dev/null)_"
} >> "$__mrn_report_out" 2>/dev/null

sync 2>/dev/null
exit 0
