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

# marionnet-cleanup.sh — find, and on request sweep, what a Marionnet session killed brutally has
# left behind on this host: auxiliary processes, socket files, run directories, and the per-guest
# directories of the UML kernels.
#
# NAMES. This file is the implementation; the names a user types are the symlinks beside it,
# `marionnet-cleanup' and `mrn-cleanup'. The first one is not decorative: bin/marionnet.ml prints
# it inside a message which is part of the 12 gettext catalogues, and runs it from two buttons of
# that warning, so it has to keep resolving whatever the file is called.
#
# WHY THIS EXISTS. Every auxiliary of a simulation (the vde_switch of a hublet, the wirefilter
# of a cable, slirpvde, the terminal emulators, the UML guests) is a direct child of Marionnet,
# and Marionnet does clean up after itself — but only on an exit that RUNS. A SIGKILL, a crash,
# or a freeze that has to be cut short defeats every one of those nets at once; the children are
# reparented to `systemd --user' and go on burning CPU and holding sockets for days. Measured on
# a development machine on 2026-08-20: 120 orphans from 17 dead sessions, 85 stale socket files,
# 359 run directories worth 1.8 GB.
#
# Since that same day, Marionnet arms a parent-death signal on each child it spawns (setpriv
# --pdeathsig KILL, see bin/simulation_level.ml), so a brutal death should no longer leave
# anything. This script remains the remedy for what is already there, for hosts without
# `setpriv', and for grandchildren, which no parent-death signal can reach.
#
# HOW AN ORPHAN IS RECOGNISED, exactly and without guessing. A process is one of ours when its
# command line names a Marionnet run directory ($TMPDIR/marionnet-<n>.dir/), OR when its working
# directory is the one Marionnet gives to its whole descendance ($(PREFIX)/share/marionnet). The
# second criterion is what catches the GRANDCHILDREN, which name no run directory and which no
# parent-death signal can reach either: measured on 2026-08-20, seven `port-helper' and five
# `uml_mconsole <name> sysrq e' (each with its `/bin/sh -c') had been stuck there for days, a
# clean-shutdown attempt on a guest that never answered. Its only conceivable false positive is
# a shell started by hand from that data directory -- which the report shows before anything is
# signalled. It is an ORPHAN
# when no live `marionnet' process shares its session id: setsid(2) makes the session id of
# these processes the pid of the Marionnet that started them, and when setsid was refused
# (interactive shell, EPERM) the session is the launching shell's, which a live Marionnet of
# that shell still shares. The only blind spot is deliberate and conservative: two Marionnet in
# the SAME shell, one dead one alive, and nothing is swept.
#
# NO bashbricks HERE, for the reason already written in mrn-check and marionnet-ctl: this script
# is meant to sit in $(PREFIX)/bin next to marionnet-ctl, and nothing installs bashbricks there.
# A relative source would work in the source tree and break once installed. Nothing below is
# about collections or JSON anyway; it is /proc and signals.
#
# RECOVERING BEFORE REMOVING. A run directory holds the UNSAVED working copy of a project, which
# is why Marionnet never removes one by itself and why --purge-dirs is implied by nothing. Since
# this script is also the one Marionnet's startup warning hands over to, it can now save that
# work instead of destroying it: --archive-dirs writes each removable run directory as an
# ordinary .mar project file (a tar.gz), built exactly the way state#private_save_project builds
# it (bin/state.ml), so that Project -> Open reopens it. Archiving first is what makes a purge
# lossless.
#
# UML MCONSOLE DIRECTORIES, the fourth kind of debris. Every guest makes its UML kernel create
# $UML_DIR/<umid>/ (default ~/.uml/<umid>/), holding a `mconsole' socket and a `pid' file, and
# nothing has ever removed one: not Marionnet on exit, not this script, which knew only about
# $TMP/marionnet-<n>.dir. Measured on this development host on 2026-08-22: eight of them, the
# oldest three weeks old, all dead. They cost a few kio, but they accumulate for ever and they
# bear the NAME OF THE MACHINE, so the residual ~/.uml/m1/ of a closed project is exactly what
# an `uml_mconsole m1' of a later session finds -- refused in milliseconds, hence harmless, but
# misleading to whoever reads the log.
#
# Alive or dead is told without asking the guest anything, and without a deadline to arm. A
# directory is LIVE when its `mconsole' socket is still bound (/proc/net/unix, as for the
# blinker sockets), OR when the pid it holds is alive AND that process's command line names the
# same `umid=' (the second half is what a recycled pid cannot fake). A FROZEN kernel -- the case
# that forced a deadline on every mconsole attempt (bin/simulation_level.ml) -- answers nothing,
# yet its socket is bound: it counts as live, which is exactly what we want. Removal is behind
# its own option, --purge-uml-dirs, implied by nothing, like everything else here.
#
# SAFETY, which is the whole point of a tool that kills things. Nothing is destroyed unless an
# explicit option asks for it. Processes are listed first and killed BY EXACT PID — never by
# pattern: `pkill -f marionnet' would match this very script (and has destroyed a KDE session
# once). A cardinality fuse refuses to act on an implausible number of processes. Run
# directories, which hold the unsaved working copy of a project, are behind their own option
# that no other implies.
#
# Requires: nothing but a Linux /proc and bash.

set -euo pipefail

readonly PROGNAME="${0##*/}"
readonly TMP="${TMPDIR:-/tmp}"

# Where the UML kernels put their per-guest directory. The variable is UML's own (Marionnet sets
# it nowhere, so guests get the default), and honouring it here is also what lets the bench of
# driven-sessions/ play the whole thing in a temporary directory, without a guest.
readonly UML_DIR_BASE="${UML_DIR:-$HOME/.uml}"

# Calibrated well above the nominal case (120 orphans were the worst seen): a fuse that trips on
# the normal case is worse than none, it leaves the orphans alive AND gives the illusion of a guard.
readonly MAX_PROCESSES=500

# A run directory younger than this is never touched, whatever else we believe about it.
readonly DIR_MIN_AGE_MINUTES=60

readonly EXIT_USAGE=2

usage() {
  cat <<EOF
Usage: $PROGNAME [--kill] [--purge-sockets] [--archive-dirs DEST] [--purge-dirs]
                 [--purge-uml-dirs] [--caller-marionnet PID] [--spare-dir DIR] [--help]

Reports what dead Marionnet sessions have left on this host. WITHOUT ANY OPTION IT ONLY
REPORTS: nothing is killed, nothing is removed.

  --kill            Terminate the orphan auxiliary processes (TERM, then KILL for those
                    that survive), by exact pid. Refuses beyond $MAX_PROCESSES processes.
  --purge-sockets   Remove the blinker socket files of $TMP that no live process is bound to.
  --archive-dirs DEST
                    Save each removable run directory as a Marionnet project file
                    DEST/recovered-<project>.<date>.<hh>h<mm>.mar (a .mar is a tar.gz), which
                    Project -> Open reopens. Removes NOTHING; it is what makes a later
                    --purge-dirs lossless, and it runs before it when both are given.
  --purge-dirs      Remove the run directories $TMP/marionnet-<n>.dir/ that no live process
                    refers to and that are older than $DIR_MIN_AGE_MINUTES minutes. THEY HOLD THE UNSAVED
                    WORKING COPY of the projects of those sessions. Implied by nothing, and
                    refused outright while a Marionnet is running.
                    TOGETHER WITH --archive-dirs it removes ONLY what was really archived: a run
                    directory that could not be saved is kept, whatever else it looks like.
  --purge-uml-dirs  Remove the per-guest directories $UML_DIR_BASE/<umid>/ whose UML kernel is
                    gone (socket no longer bound, and no live process bearing that umid). They
                    hold a socket and a pid file, NO work of yours. Directories of another shape
                    are left alone: this one is shared with any other UML use of yours.
  --help            This help.

Options passed by Marionnet itself, from the buttons of its startup warning; rarely useful by
hand, and never a way to act on somebody else's session:

  --caller-marionnet PID
                    PID -- which must really be a live Marionnet -- stops counting as a reason
                    to refuse --purge-dirs. Any OTHER live Marionnet still forbids it.
  --spare-dir DIR   Treat DIR as a live run directory: never archived, never removed. This is
                    how the calling Marionnet names its own working copy, which nothing else on
                    this host names as long as it has started no component.

Typical use: run it with no option, read the report, then add the options you agree with.
EOF
}

# --- Scanning /proc ------------------------------------------------------------------------
#
# The whole scan is done by reading /proc directly, in bash, on purpose: a `ps | grep <pattern>'
# pipeline puts the pattern in the command line of its own processes, which then show up in
# their own output.

# --- What the calling Marionnet tells us about itself
#
# --purge-dirs refuses to act while a Marionnet is running, and rightly so: a live session's own
# working copy lives in one of these directories and NOTHING else on the host names it --
# Marionnet does not put it on its command line, and it has no child naming it until a component
# is started. The startup warning of Marionnet (bin/marionnet.ml) offers buttons that recover and
# clean, so the caller must be able to say `that one is me': it gives its pid AND its own run
# directory. Any other live Marionnet still forbids the purge -- two simultaneous sessions are a
# supported case, and the second one's directory would be just as invisible.
CALLER_MARIONNET=""
ARCHIVE_DEST=""
declare -a SPARE_DIRS=()

# By the EXECUTABLE, never by the name: bash puts a script's name into /proc/<pid>/comm, which is
# what once made this very script count as a live Marionnet (see the second pass of scan below).
is_a_marionnet_exe() {
  local exe
  exe=$(readlink "/proc/$1/exe" 2>/dev/null) || return 1
  [[ "${exe##*/}" == marionnet || "${exe##*/}" == marionnet.* ]]
}

declare -a ORPHAN_PIDS=()          # pids of the auxiliaries of dead sessions
declare -A ORPHAN_CMD=()           # pid -> command line
declare -A ORPHAN_SID=()           # pid -> session id
declare -A LIVE_RUNDIRS=()         # run directory -> 1, for every LIVE process referring to it
declare -a LIVE_MARIONNETS=()      # pids of the live marionnet processes

# Session id of a process, from field 6 of /proc/<pid>/stat. The command name (field 2) may
# itself contain spaces and parentheses, hence the split on the LAST ')'.
session_id_of() {
  local pid="$1" stat rest
  stat=$(< "/proc/$pid/stat") || return 1
  rest="${stat##*) }"
  # rest = state ppid pgrp session ...
  echo "$rest" | { read -r _state _ppid _pgrp session _rest; echo "${session:-}"; }
}

# The run directories named by a command line, one per line.
rundirs_of_cmdline() {
  local cmd="$1"
  grep -oE "${TMP}/marionnet-[0-9]+\.dir" <<< "$cmd" | sort -u || true
}

scan() {
  local pid comm cmd cwd sid dir
  local -a candidates=()
  local -A live_sids=()

  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$'); do
    [ -r "/proc/$pid/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
    [ -n "$cmd" ] || continue                       # kernel thread
    # NOT `$(< file 2>/dev/null)': bash only applies its read-the-file shortcut when the input
    # redirection stands ALONE, so the extra 2> makes the substitution expand to the EMPTY
    # STRING -- silently, which had every live Marionnet go unrecognised (and therefore
    # unprotected) until it was measured on 2026-08-20.
    read -r comm < "/proc/$pid/comm" 2>/dev/null || continue

    # A live Marionnet: its session protects everything that shares it. Recognised by its
    # EXECUTABLE, never by its name: bash puts the name of a script into /proc/<pid>/comm, so
    # `marionnet-cleanup' itself matched a `marionnet*' test on comm -- this very script then
    # counted as a live Marionnet, refused every --purge-dirs, and spared any orphan sharing
    # the terminal it was run from. Measured on 2026-08-20.
    if is_a_marionnet_exe "$pid"; then
      sid=$(session_id_of "$pid") || continue
      [ -n "$sid" ] && live_sids["$sid"]=1
      LIVE_MARIONNETS+=("$pid")
    fi

    # (a) it names a run directory, or (b) it sits in the working directory Marionnet gives to
    # its descendance -- the criterion that catches the grandchildren (see the header).
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
    if [[ "$cmd" == *"${TMP}/marionnet-"*".dir/"* ]] || [[ "$cwd" == */share/marionnet ]]; then
      candidates+=("$pid")
      ORPHAN_CMD["$pid"]="$cmd"
    fi
  done

  # Second pass: a candidate is an orphan unless a live Marionnet shares its session. The run
  # directories of the SPARED ones are live, and must survive --purge-dirs.
  for pid in "${candidates[@]:-}"; do
    [ -n "$pid" ] || continue
    [ -e "/proc/$pid" ] || continue
    sid=$(session_id_of "$pid") || continue
    if [ -n "${live_sids[${sid:-x}]:-}" ]; then
      while read -r dir; do [ -n "$dir" ] && LIVE_RUNDIRS["$dir"]=1; done < <(rundirs_of_cmdline "${ORPHAN_CMD[$pid]}")
      unset "ORPHAN_CMD[$pid]"
    else
      ORPHAN_SID["$pid"]="$sid"
      ORPHAN_PIDS+=("$pid")
    fi
  done

  # The run directory of a live Marionnet is live too, even when it has started nothing yet:
  # its project's working copy is in there.
  for pid in "${LIVE_MARIONNETS[@]:-}"; do
    [ -n "$pid" ] || continue
    [ -r "/proc/$pid/cmdline" ] || continue
    while read -r dir; do [ -n "$dir" ] && LIVE_RUNDIRS["$dir"]=1
    done < <(rundirs_of_cmdline "$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)")
  done
}

# --- Sockets -------------------------------------------------------------------------------
#
# The safe test is not the file's date — /tmp is shared and two Marionnet at once are a known
# case — but whether a socket is still BOUND to that path. The last column of /proc/net/unix is
# the path of every bound unix socket on the host; a file that is not in there is dead.

bound_unix_paths() {
  awk '{ print $NF }' /proc/net/unix 2>/dev/null | grep '^/' | sort -u || true
}

declare -a DEAD_SOCKETS=()
declare -a LIVE_SOCKETS=()

scan_sockets() {
  local bound f
  bound=$(bound_unix_paths)
  for f in "$TMP"/.marionnet-blinker-server-socket-* "$TMP"/blinker-killer-client-socket-*; do
    [ -O "$f" ] || continue                        # not ours: /tmp is shared
    if [ -S "$f" ]; then
      if grep -qxF "$f" <<< "$bound"; then LIVE_SOCKETS+=("$f"); else DEAD_SOCKETS+=("$f"); fi
    elif [ -f "$f" ] && [ ! -s "$f" ]; then
      # An ordinary empty file of the same name is debris too, and dead by construction: the
      # name is made by a temp_file, which creates such a file before the bind replaces it.
      DEAD_SOCKETS+=("$f")
    fi
  done
}

# --- Run directories -----------------------------------------------------------------------

declare -a DEAD_DIRS=()

scan_dirs() {
  local d
  for d in "$TMP"/marionnet-*.dir; do
    [ -d "$d" ] || continue
    [ -O "$d" ] || continue
    [ -n "${LIVE_RUNDIRS[$d]:-}" ] && continue
    # Too young to judge: a session may be starting up right now.
    [ -n "$(find "$d" -maxdepth 0 -mmin "+$DIR_MIN_AGE_MINUTES" 2>/dev/null)" ] || continue
    DEAD_DIRS+=("$d")
  done
}

# The run directories the caller vouches for are live by decree. Added to the set the scan
# builds, hence honoured by scan_dirs -- so by --archive-dirs and --purge-dirs alike, which both
# read DEAD_DIRS and nothing else.
apply_spare_dirs() {
  local d
  for d in "${SPARE_DIRS[@]:-}"; do
    [ -n "$d" ] && LIVE_RUNDIRS["$d"]=1
  done
  return 0
}

# --- UML mconsole directories --------------------------------------------------------------
#
# See the header for what these are and why they survive. Three baskets, not two: what does not
# have the expected shape is neither live nor removable, it is simply none of our business.

declare -a DEAD_UML_DIRS=()
declare -a LIVE_UML_DIRS=()
declare -a ODD_UML_DIRS=()

# $UML_DIR is shared with every other UML the user may run, and this script must not become a
# general-purpose remover of directories it does not understand. Ours hold `mconsole' and `pid',
# and nothing else.
uml_dir_shape_is_ours() {
  local d="$1" f
  for f in "$d"/* "$d"/.[!.]* "$d"/..?*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in mconsole|pid) ;; *) return 1 ;; esac
  done
  return 0
}

# Live by either half, and the two halves cover different failures: the bound socket answers for
# a kernel which is frozen (it says nothing, but it still holds its socket), the pid answers for
# the instant between the mkdir and the bind. The pid alone would not do -- a recycled pid would
# make a dead directory immortal -- hence the `umid=' of the command line, which only the real
# kernel bears.
uml_dir_is_live() {
  local d="$1" bound="$2" pid
  local umid="${d##*/}"          # two `local's on purpose: within one, $d is not assigned yet
  grep -qxF "$d/mconsole" <<< "$bound" && return 0
  [ -r "$d/pid" ] || return 1
  read -r pid < "$d/pid" 2>/dev/null || return 1
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF "umid=$umid"
}

scan_uml_dirs() {
  local d bound
  [ -d "$UML_DIR_BASE" ] || return 0
  bound=$(bound_unix_paths)
  for d in "$UML_DIR_BASE"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    [ -O "$d" ] || continue                        # not ours
    if ! uml_dir_shape_is_ours "$d"; then ODD_UML_DIRS+=("$d"); continue; fi
    if uml_dir_is_live "$d" "$bound"; then LIVE_UML_DIRS+=("$d"); continue; fi
    # Too young to judge, exactly as for the run directories: a guest may be starting right now,
    # its directory made and its socket not bound yet.
    [ -n "$(find "$d" -maxdepth 0 -mmin "+$DIR_MIN_AGE_MINUTES" 2>/dev/null)" ] || continue
    DEAD_UML_DIRS+=("$d")
  done
}

# --- Reporting ---------------------------------------------------------------------------

report() {
  local pid sid n
  echo "== Orphan auxiliary processes =="
  n=${#ORPHAN_PIDS[@]}
  if [ "$n" -eq 0 ]; then
    echo "  none."
  else
    for sid in $(for pid in "${ORPHAN_PIDS[@]}"; do echo "${ORPHAN_SID[$pid]}"; done | sort -un); do
      echo "  session $sid (no live Marionnet in it):"
      for pid in "${ORPHAN_PIDS[@]}"; do
        [ "${ORPHAN_SID[$pid]}" = "$sid" ] || continue
        printf '    %-8s %s\n' "$pid" "$(cut -c1-100 <<< "${ORPHAN_CMD[$pid]}")"
      done
    done
    echo "  total: $n process(es) --- use --kill to terminate them."
  fi

  echo
  echo "== Blinker socket files in $TMP =="
  echo "  dead (nobody bound): ${#DEAD_SOCKETS[@]} --- use --purge-sockets to remove them."
  echo "  still bound (spared): ${#LIVE_SOCKETS[@]}"

  echo
  echo "== Run directories in $TMP =="
  if [ "${#DEAD_DIRS[@]}" -eq 0 ]; then
    echo "  none to remove."
  else
    echo "  removable: ${#DEAD_DIRS[@]} directory(ies), $(du -sh --total "${DEAD_DIRS[@]}" 2>/dev/null | tail -1 | cut -f1) in total."
    echo "  THEY HOLD THE UNSAVED WORKING COPY of the projects of those sessions."
    echo "  oldest: $(ls -dt "${DEAD_DIRS[@]}" | tail -1)"
    echo "  use --archive-dirs DIR to save them as .mar project files, --purge-dirs to remove them."
  fi
  echo "  in use by a live session (spared): ${#LIVE_RUNDIRS[@]}"
  if [ -n "$CALLER_MARIONNET" ]; then
    echo "  caller: pid $CALLER_MARIONNET is the Marionnet asking, and does not forbid the purge."
  fi
  if [ "${#SPARE_DIRS[@]}" -gt 0 ]; then
    echo "  spared on request: ${SPARE_DIRS[*]}"
  fi

  echo
  echo "== UML mconsole directories in $UML_DIR_BASE =="
  if [ "${#DEAD_UML_DIRS[@]}" -eq 0 ]; then
    echo "  none to remove."
  else
    echo "  removable: ${#DEAD_UML_DIRS[@]} directory(ies) --- a socket and a pid file, NO work of yours."
    echo "  oldest: $(ls -dt "${DEAD_UML_DIRS[@]}" | tail -1)"
    echo "  use --purge-uml-dirs to remove them."
  fi
  echo "  still holding a live UML (spared): ${#LIVE_UML_DIRS[@]}"
  if [ "${#ODD_UML_DIRS[@]}" -gt 0 ]; then
    echo "  not of the expected shape, none of our business: ${#ODD_UML_DIRS[@]}"
  fi
  return 0
}

# --- Acting ------------------------------------------------------------------------------

# Never signal these, whatever the scan believes. `systemd --user' matters most: it is the
# reaper that adopted the orphans, hence their common parent -- killing it takes the whole
# graphical session down with it.
is_protected() {
  local pid="$1" comm
  [ "$pid" -eq 1 ] && return 0
  [ "$pid" -eq "$$" ] && return 0
  [ "$pid" -eq "$BASHPID" ] && return 0
  [ "$pid" -eq "$PPID" ] && return 0
  read -r comm < "/proc/$pid/comm" 2>/dev/null || return 0
  [ "$comm" = "systemd" ] && return 0
  return 1
}

do_kill() {
  local pid n=${#ORPHAN_PIDS[@]}
  local -a targets=() survivors=()
  [ "$n" -eq 0 ] && { echo "$PROGNAME: no orphan process to kill."; return 0; }
  if [ "$n" -gt "$MAX_PROCESSES" ]; then
    echo "$PROGNAME: $n orphan processes is beyond the fuse of $MAX_PROCESSES: refusing to act." >&2
    echo "$PROGNAME: check the list above, then raise MAX_PROCESSES in this script if it is really what you want." >&2
    return 1
  fi
  for pid in "${ORPHAN_PIDS[@]}"; do
    is_protected "$pid" && { echo "$PROGNAME: refusing to signal the protected pid $pid."; continue; }
    # The pid may have been reused since the scan: check that it is still the process we saw.
    [ "$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)" = "${ORPHAN_CMD[$pid]}" ] || continue
    targets+=("$pid")
  done
  echo "$PROGNAME: sending TERM to ${#targets[@]} process(es)..."
  for pid in "${targets[@]:-}"; do [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true; done
  sleep 2
  for pid in "${targets[@]:-}"; do [ -n "$pid" ] && [ -e "/proc/$pid" ] && survivors+=("$pid"); done
  if [ "${#survivors[@]}" -gt 0 ]; then
    echo "$PROGNAME: ${#survivors[@]} process(es) ignored TERM; sending KILL..."
    for pid in "${survivors[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
    sleep 1
  fi
  local left=0
  for pid in "${targets[@]:-}"; do [ -n "$pid" ] && [ -e "/proc/$pid" ] && left=$((left+1)); done
  echo "$PROGNAME: done; $left of ${#targets[@]} still alive."
}

do_purge_sockets() {
  local f n=0
  for f in "${DEAD_SOCKETS[@]:-}"; do [ -n "$f" ] && rm -f -- "$f" && n=$((n+1)); done
  echo "$PROGNAME: removed $n dead socket file(s); ${#LIVE_SOCKETS[@]} still bound, spared."
}

# No global refusal here, unlike --purge-dirs: a live Marionnet is not a reason to spare
# anything. What that refusal protects is the working copy of a session which NOTHING on the
# host names; here the belonging is exact, told by the bound socket or by the umid of a live
# command line, so a running session's own directories are already in LIVE_UML_DIRS.
do_purge_uml_dirs() {
  local d n=0
  [ "${#DEAD_UML_DIRS[@]}" -eq 0 ] && { echo "$PROGNAME: no UML mconsole directory to remove."; return 0; }
  echo "$PROGNAME: removing ${#DEAD_UML_DIRS[@]} UML mconsole directory(ies) of dead guests..."
  for d in "${DEAD_UML_DIRS[@]}"; do
    case "$d" in "$UML_DIR_BASE"/?*) rm -rf -- "$d" && n=$((n+1)) ;; *) ;; esac
  done
  echo "$PROGNAME: removed $n; ${#LIVE_UML_DIRS[@]} still holding a live UML, spared."
}

do_purge_dirs() {
  local d pid n=0
  local -a blocking=()
  # The caller identified itself and named the directory to spare (--caller-marionnet,
  # --spare-dir), so it is not a reason to refuse. Every OTHER live Marionnet still is.
  for pid in "${LIVE_MARIONNETS[@]:-}"; do
    [ -n "$pid" ] || continue
    [ "$pid" = "$CALLER_MARIONNET" ] && continue
    blocking+=("$pid")
  done
  if [ "${#blocking[@]}" -gt 0 ]; then
    echo "$PROGNAME: a Marionnet is running (pid ${blocking[*]}); refusing to remove any run directory." >&2
    echo "$PROGNAME: close it first -- its own working copy lives in one of these directories." >&2
    return 1
  fi
  # With --archive-dirs in the same run, the purge is restricted to what the archiving REALLY
  # saved: a run directory it had to skip (an unexpected shape) still holds work nobody has a copy
  # of, and removing it because it was in the same list would be exactly the loss this option
  # exists to prevent. Without --archive-dirs, nothing changes: the whole list goes.
  local -a victims=()
  local x
  if [ -n "$ARCHIVE_DEST" ]; then
    for x in "${ARCHIVED_DIRS[@]:-}"; do [ -n "$x" ] && victims+=("$x"); done
    if [ "${#victims[@]}" -lt "${#DEAD_DIRS[@]}" ]; then
      echo "$PROGNAME: keeping $(( ${#DEAD_DIRS[@]} - ${#victims[@]} )) run directory(ies) that could not be archived."
    fi
  else
    for x in "${DEAD_DIRS[@]:-}"; do [ -n "$x" ] && victims+=("$x"); done
  fi
  [ "${#victims[@]}" -eq 0 ] && { echo "$PROGNAME: no run directory to remove."; return 0; }
  if [ -n "$ARCHIVE_DEST" ]
  then echo "$PROGNAME: removing ${#victims[@]} run directory(ies), whose work is now in $ARCHIVE_DEST..."
  else echo "$PROGNAME: removing ${#victims[@]} run directory(ies) and the unsaved work they hold..."
  fi
  for d in "${victims[@]}"; do
    case "$d" in "$TMP"/marionnet-*.dir) rm -rf -- "$d" && n=$((n+1)) ;; *) ;; esac
  done
  echo "$PROGNAME: removed $n."
}

# A .mar project file is a tar.gz of the run directory's single subdirectory -- the project root
# -- with `tmp' excluded and sparse files preserved: exactly what state#private_save_project
# writes (bin/state.ml), which is what makes the result openable by Project -> Open. Nothing is
# removed here, and DEAD_DIRS is the same list --purge-dirs works on, so what is archived is
# precisely what a purge would destroy.
#
# A run directory of an unexpected shape (no subdirectory, or more than one) is SKIPPED rather
# than archived whole: Marionnet takes the tarball's root directory for the project root, so an
# archive of the run directory itself would load into nonsense instead of failing.
declare -a ARCHIVED_DIRS=()        # run directories really saved by do_archive_dirs

do_archive_dirs() {
  local d root stamp target i n=0 skipped=0
  local -a roots=()
  if [ ! -d "$ARCHIVE_DEST" ] || [ ! -w "$ARCHIVE_DEST" ]; then
    echo "$PROGNAME: --archive-dirs: \`$ARCHIVE_DEST' is not a writable directory." >&2
    return 1
  fi
  [ "${#DEAD_DIRS[@]}" -eq 0 ] && { echo "$PROGNAME: no run directory to archive."; return 0; }
  stamp=$(date +%Y-%m-%d.%Hh%M)
  for d in "${DEAD_DIRS[@]}"; do
    roots=()
    while read -r root; do [ -n "$root" ] && roots+=("$root")
    done < <(find "$d" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null)
    if [ "${#roots[@]}" -ne 1 ]; then
      echo "$PROGNAME: skipping $d: it holds ${#roots[@]} project directories (exactly 1 expected)."
      skipped=$((skipped+1))
      continue
    fi
    root="${roots[0]}"
    target="$ARCHIVE_DEST/recovered-$root.$stamp.mar"
    i=2
    while [ -e "$target" ]; do target="$ARCHIVE_DEST/recovered-$root.$stamp-$i.mar"; i=$((i+1)); done
    if tar -cSzf "$target" -C "$d" --exclude tmp "$root"; then
      echo "$PROGNAME: wrote $target ($(du -h "$target" | cut -f1)), from $d"
      ARCHIVED_DIRS+=("$d")
      n=$((n+1))
    else
      echo "$PROGNAME: FAILED to archive $d" >&2
      rm -f -- "$target"
      skipped=$((skipped+1))
    fi
  done
  if [ "$skipped" -eq 0 ]
  then echo "$PROGNAME: archived $n run directory(ies)."
  else echo "$PROGNAME: archived $n run directory(ies), skipped $skipped."
  fi
  return 0
}

# --- Main --------------------------------------------------------------------------------

# An option that takes a value: fails loudly on a missing one rather than swallowing the next
# option as its argument.
value_of() {  # value_of <option-name> <remaining args...>
  local opt="$1"; shift
  if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
    echo "$PROGNAME: $opt needs a value" >&2
    return $EXIT_USAGE
  fi
  echo "$2"
}

main() {
  local kill_them=0 purge_sockets=0 purge_dirs=0 purge_uml_dirs=0 value
  while [ $# -gt 0 ]; do
    case "$1" in
      --kill)           kill_them=1 ;;
      --purge-sockets)  purge_sockets=1 ;;
      --purge-dirs)     purge_dirs=1 ;;
      --purge-uml-dirs) purge_uml_dirs=1 ;;
      # --- The three options below take a value.
      --archive-dirs)
        value=$(value_of "$1" "$@") || return $EXIT_USAGE
        ARCHIVE_DEST="$value"
        shift ;;
      --caller-marionnet)
        value=$(value_of "$1" "$@") || return $EXIT_USAGE
        case "$value" in ''|*[!0-9]*)
          echo "$PROGNAME: --caller-marionnet: \`$value' is not a pid" >&2; return $EXIT_USAGE ;;
        esac
        # Only a LIVE Marionnet may excuse itself, and it is checked here, not taken on trust:
        # the option lifts a guard, so an arbitrary pid must not be able to lift it.
        is_a_marionnet_exe "$value" || {
          echo "$PROGNAME: --caller-marionnet: pid $value is not a live Marionnet" >&2
          return $EXIT_USAGE; }
        CALLER_MARIONNET="$value"
        shift ;;
      --spare-dir)
        value=$(value_of "$1" "$@") || return $EXIT_USAGE
        value="${value%/}"
        case "$value" in "$TMP"/marionnet-*.dir) ;; *)
          echo "$PROGNAME: --spare-dir: \`$value' is not a run directory of $TMP" >&2
          return $EXIT_USAGE ;;
        esac
        SPARE_DIRS+=("$value")
        shift ;;
      -h|--help)        usage; return 0 ;;
      *) echo "$PROGNAME: unknown option \`$1'" >&2; usage >&2; return $EXIT_USAGE ;;
    esac
    shift
  done

  scan
  apply_spare_dirs
  scan_sockets
  scan_dirs
  scan_uml_dirs
  report

  [ "$kill_them" -eq 1 ]      && { echo; do_kill; }
  [ "$purge_sockets" -eq 1 ]  && { echo; do_purge_sockets; }
  [ "$purge_uml_dirs" -eq 1 ] && { echo; do_purge_uml_dirs; }
  # Archiving first, always: a purge that follows in the same run then destroys nothing that has
  # not been saved.
  [ -n "$ARCHIVE_DEST" ]      && { echo; do_archive_dirs; }
  [ "$purge_dirs" -eq 1 ]     && { echo; do_purge_dirs; }
  return 0
}

main "$@"
