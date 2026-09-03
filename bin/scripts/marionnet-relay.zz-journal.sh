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
# Guest-side journal, EPILOGUE.  Deep logging, episode 1.
#
# Companion of `marionnet-relay.00-journal', deposited by the same host code
# and sourced by the same relay loop, but AFTER the user's `.rcfile' (the loop
# globs in alphabetical order: 00- < rcfile < zz-).  Its whole job is to undo
# what the prologue installed:
#
#   - stop tracing, drop the ERR trap, put PS4 back;
#   - give the relay its standard descriptors back (kept in 3 and 4), which is
#     what stops the capture from leaking over the end of the boot;
#   - let the `tee' see its end of file and wait for it, so that the journal is
#     complete host-side even if the machine is inspected right away.
#
# Episode 2 grafts the COLLECTOR at the end of this same file (see the second
# half below): it belongs here, after the capture is closed -- what it prints
# has nothing to do with the user's startup configuration -- and it needed no
# change at all to the prologue.
#
# The SHUTDOWN HOOK of episode 7 used to be grafted here as well, and that was a
# defect: see the section which now only says where it went.
#
# Like its companion: plain Bash (no bashbricks inside a guest), everything
# guarded, and never fatal to a boot.
# ---------------------------------------------------------------------------

if [[ -n "$__mrn_journal_log" ]]; then

  { set +x ; } 2>/dev/null
  __mrn_journal_tracing=""

  # --- Drop our ERR trap and put back the one the relay may have had:
  trap - ERR
  unset -f __mrn_journal_on_error 2>/dev/null
  if [[ -n "$__mrn_journal_err_trap" ]]; then
    eval "$__mrn_journal_err_trap" 2>/dev/null
  fi
  [[ "$__mrn_journal_E_was_on" = yes ]] || set +o errtrace
  PS4="$__mrn_journal_ps4"

  echo "# end of the startup configuration: $(date '+%F %T %z' 2>/dev/null)"

  # --- Close the capture: the relay writes again where it used to, and the
  #     `tee' (if any) sees the end of its input:
  exec 1>&3 2>&4 3>&- 4>&-

  # --- Wait for the journal to be actually flushed.  `wait' works because the
  #     process substitution is a child of this shell; the bounded loop covers
  #     the Bash versions where it is not considered a job:
  if [[ -n "$__mrn_journal_tee_pid" ]]; then
    wait "$__mrn_journal_tee_pid" 2>/dev/null || {
      __mrn_journal_i=0
      while kill -0 "$__mrn_journal_tee_pid" 2>/dev/null && [[ $__mrn_journal_i -lt 50 ]]; do
        sleep 0.1
        __mrn_journal_i=$((__mrn_journal_i + 1))
      done
      unset __mrn_journal_i
    }
  fi

  # --- Marionnet's own debug mode (`-d') had put xtrace on before we did:
  [[ "$__mrn_journal_x_was_on" = yes ]] && set -x

  unset __mrn_journal_ps4 __mrn_journal_err_trap __mrn_journal_tee_pid
  unset __mrn_journal_x_was_on __mrn_journal_E_was_on __mrn_journal_tracing
fi

# ---------------------------------------------------------------------------
# COLLECTOR (episode 2).  What the boot did BEFORE the relay was reached.
#
# The prologue/epilogue pair above only sees the user's startup configuration:
# the relay is an init script (`Required-Start: $local_fs $network $syslog'),
# so the kernel, init and the services all ran before it.  The only way to say
# anything about them from here is to collect, afterwards, what they left.
#
# Written into a SECOND file, /mnt/hostfs/boot.log, on purpose: rc_config.log
# answers "what did my scenario do?", boot.log answers "did this image boot
# properly?".  Merging them would make both unreadable, and the capture of the
# first one is closed by the time we get here anyway.
#
# Independent of the block above (its own guard): if the hostfs journal could
# not even be created, the collection is still worth attempting.
#
# Three rules, all of them because this runs at the very end of a boot:
#   - never fatal, never noisy: everything goes to the file, nothing to the
#     console the student is looking at;
#   - never unbounded: every section is truncated, and every command runs
#     under `timeout' when the image has one;
#   - never blocking: no `systemctl is-system-running --wait' -- the snapshot
#     is taken at relay time and says so, services may still be starting.
# ---------------------------------------------------------------------------

__mrn_journal_boot_log=/mnt/hostfs/boot.log

if { : > "$__mrn_journal_boot_log" ; } 2>/dev/null; then

  # Marionnet's own debug mode (`-d') may have xtrace on at this point (the
  # block above just put it back): the collection itself has no business being
  # traced on the console, so we hold it off and restore it at the end.
  case $- in *x*) __mrn_journal_x_here=yes ;; *) __mrn_journal_x_here=no ;; esac
  { set +x ; } 2>/dev/null

  # A guest without `timeout' is not impossible (minimal userlands), hence the
  # lookup rather than a plain call -- and, since episode 20, the MEASURE rather
  # than the lookup alone: the router image (busybox, 2014) has a `timeout' with
  # the old interface (`timeout -t SECS PROG'), so the modern form tries to run a
  # program named "15" and every section of this collection reported
  # "timeout: can't execute '15'".  Presence was never the question -- episode 14
  # had already learnt it on `tee' -- so the form we are about to use is played
  # once, and a `timeout' that cannot bound anything is treated as absent.
  __mrn_journal_timeout="$(type -p timeout 2>/dev/null)"
  if [[ -n "$__mrn_journal_timeout" ]] && \
     ! "$__mrn_journal_timeout" 1 true >/dev/null 2>&1 ; then
    __mrn_journal_timeout=""
  fi
  __mrn_journal_deadline=15

  # $1 = section title, $2 = shell command line (a pipeline is expected).
  __mrn_journal_run() {
    echo
    echo "===== $1 ====="
    if [[ -n "$__mrn_journal_timeout" ]]; then
      "$__mrn_journal_timeout" "$__mrn_journal_deadline" bash -c "$2" 2>&1 \
        || echo "(no output, failed or timed out: status $?)"
    else
      eval "$2" 2>&1 || echo "(no output or failed: status $?)"
    fi
  }

  # The init system is DETECTED here rather than taken from the host: the point
  # of this file is to say what the guest really did, and the host only knows
  # what the filesystem's .conf DECLARES (INIT_SYSTEM, bin/disk.ml).  Both are
  # reported, precisely so that a disagreement -- which changes the kernel
  # arguments Marionnet picks (`boot_quirks') -- becomes visible here.
  # /run/systemd/system is systemd's own test (sd_booted(3)); journalctl is
  # required too, since it is what the systemd branch below relies on.
  if [[ -d /run/systemd/system ]] && type -p journalctl >/dev/null 2>&1; then
    __mrn_journal_init=systemd
  else
    __mrn_journal_init=sysv
  fi

  { echo "# Marionnet guest journal (system collection)"
    echo "# date: $(date '+%F %T %z' 2>/dev/null)"
    echo "# guest: $(uname -srm 2>/dev/null)"
    echo "# uptime:$(uptime 2>/dev/null | sed 's/^ *//')"
    echo "# init: detected=$__mrn_journal_init declared=${init_system:-unknown}"
    echo "# taken at the end of the relay: later services are not covered here"
    echo "# companion: rc_config.log (the startup configuration itself)"

    __mrn_journal_run "dmesg (last 400 lines)" "dmesg | tail -n 400"

    if [[ "$__mrn_journal_init" = systemd ]]; then
      # `is-system-running' exits non-zero for `degraded'/`starting', which are
      # answers, not failures -- hence the `|| true':
      __mrn_journal_run "systemctl is-system-running" \
        "systemctl is-system-running || true"
      __mrn_journal_run "systemctl --failed" \
        "systemctl --failed --no-legend --no-pager || true"
      __mrn_journal_run "journalctl -b (last 500 lines)" \
        "journalctl -b --no-pager -n 500"
    else
      # No service manager to interrogate: whatever the image's syslog kept.  The
      # listing comes first and is unconditional -- a Marionnet guest may simply
      # have no syslog installed (measured on debian-wheezy), and a collection
      # that says "nothing here" is worth more than a silently empty one.
      __mrn_journal_run "/var/log (listing)" "ls -la /var/log"
      for __mrn_journal_f in /var/log/boot /var/log/boot.log /var/log/messages /var/log/syslog; do
        [[ -f "$__mrn_journal_f" ]] || continue
        __mrn_journal_run "$__mrn_journal_f (last 200 lines)" \
          "tail -n 200 '$__mrn_journal_f'"
      done
      unset __mrn_journal_f
    fi

    echo
    echo "# end of the system collection: $(date '+%F %T %z' 2>/dev/null)"
  } >> "$__mrn_journal_boot_log" 2>/dev/null

  unset -f __mrn_journal_run 2>/dev/null
  unset __mrn_journal_timeout __mrn_journal_deadline __mrn_journal_init
  [[ "$__mrn_journal_x_here" = yes ]] && { set -x ; } 2>/dev/null
  unset __mrn_journal_x_here
fi
unset __mrn_journal_boot_log

# ---------------------------------------------------------------------------
# SHUTDOWN HOOK (episode 7) -- NO LONGER HERE.  It is armed by the PROLOGUE,
# `marionnet-relay.00-journal', and the move is the whole point of episode 16 of
# `marionnet-todo-transverse': sourced from the epilogue, the hook was installed
# AFTER the user's startup configuration, hence after the readiness marker that
# `wait --ready' answers on -- so a session which shut a guest down as soon as it
# said it was ready lost its report.  Measured, deterministically: a startup
# configuration which writes the marker and then keeps working for 40s leaves NO
# report.md at all.  The prologue is sourced before that configuration, so the
# hook is armed before anything the guest can be judged ready by.
#
# The watcher below stays here: it must not be started before the epilogue has
# closed the capture (see its own comment), and nothing is judged ready on it.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ON-DEMAND WATCHER (episodes 16 and 18).  What the session is doing RIGHT NOW.
#
# The hook above answers "what did the session end with?".  Episode 15 showed
# that a corrector needs the other question too -- "what is true at this
# instant?" -- and that nothing in the channel could answer it: the five
# journals are traces, and a trace says what was SAID, not what IS.
#
# The producer is the very same `marionnet-report'; all that is added here is a
# watcher which runs it when the host drops a flag file in the hostfs.  Started
# in the background, at the end of the boot, so that a machine answers `report'
# as soon as it is up.  Since episode 18 the same watcher also serves `exec',
# the verb which runs a command inside the guest -- one loop, because watching
# a hostfs costs a wakeup per second and per guest.
#
# Two branches, decided by the GUEST as everywhere else in this file, and for
# ONE reason -- the watcher must outlive the relay:
#
#   1. under systemd the relay is an LSB script run through a generated unit,
#      and a background child of a unit is killed with its control group when
#      the unit finishes.  So the watcher gets a unit of its own, exactly like
#      the shutdown hook above -- written in /run (nothing survives a reboot of
#      the guest: the host deposits everything again anyway).
#   2. under SysV nothing owns a control group: `setsid' (when the image has
#      it) puts the watcher in a session of its own, and a plain `&' does the
#      rest -- a non-interactive shell sends no SIGHUP when it ends.
#
# Never fatal, never noisy: a guest that refuses the watcher simply answers
# `report' and `exec' with a timeout, and its shutdown report is untouched.
# ---------------------------------------------------------------------------

__mrn_journal_watch=/mnt/hostfs/marionnet-watch

if [[ -r "$__mrn_journal_watch" ]]; then

  case $- in *x*) __mrn_journal_x_watch=yes ;; *) __mrn_journal_x_watch=no ;; esac
  { set +x ; } 2>/dev/null

  if [[ -d /run/systemd/system ]] && type -p systemctl >/dev/null 2>&1; then
    {
      cat > /run/systemd/system/marionnet-watch.service <<UNIT
[Unit]
Description=Marionnet: on-demand report and exec watcher (journalisation-profonde)
DefaultDependencies=no
Conflicts=shutdown.target
Before=shutdown.target

[Service]
Type=simple
ExecStart=/bin/bash $__mrn_journal_watch
Restart=on-failure
RestartSec=5
UNIT
      systemctl daemon-reload
      # `--no-block' AND `DefaultDependencies=no'. MEASURED, in this order: written the obvious
      # way -- default dependencies, blocking `start' -- the unit simply does not run, and a
      # trixie whose boot has otherwise completed answers `report' with a timeout because
      # nothing is watching. We are being sourced by the relay, which systemd is itself
      # starting, so the request is an ordering into a transaction already under way; the
      # watcher needs no ordering at all (it waits for a file), hence no dependencies and no
      # waiting for the answer.
      # `Conflicts=shutdown.target' brings back the one thing `DefaultDependencies=no' removes
      # and which we do want: being stopped when the guest shuts down, so that the watcher is
      # gone before the end-of-session report is taken (episode 7's hook).
      systemctl start --no-block marionnet-watch.service
    } >/dev/null 2>&1
  else
    # The redirections are NOT decoration: without them the watcher inherits the
    # descriptors of this shell, hence the student's console for the whole life
    # of the machine -- and, if it were started before the epilogue closed the
    # capture, it would hold the `tee' pipe open for ever.
    if type -p setsid >/dev/null 2>&1; then
      setsid /bin/bash "$__mrn_journal_watch" </dev/null >/dev/null 2>&1 &
    else
      /bin/bash "$__mrn_journal_watch" </dev/null >/dev/null 2>&1 &
    fi
  fi

  [[ "$__mrn_journal_x_watch" = yes ]] && { set -x ; } 2>/dev/null
  unset __mrn_journal_x_watch
fi
unset __mrn_journal_watch

# ---------------------------------------------------------------------------
# The login prompt, LAST.  (Work-stream `marionnet-kernel-rootfs'.)
#
# Reported from the MarioNUM classroom: the console showed `m1 login:' and then
# five more `[ OK ]' lines, so the prompt was buried and the student believed
# the machine was still busy.  MEASURED in the published image 16341:
# getty@tty0 active at 4.95 s, our relay at 11.31 s, multi-user.target at
# 11.33 s -- a 6.4 s window which is NOT a matter of duration but of ordering
# (the getty inherits no ordering against multi-user.target), which is why
# three episodes of shortening the relay never touched it.
#
# The host side masks `getty.target' on the kernel command line
# (bin/simulation_level.ml), so nothing starts the prompt any more: starting it
# is now this epilogue's job, and it does so only once the boot transaction is
# over.  `systemd-run' rather than a unit file of our own, on purpose: a
# transient unit costs no `systemctl daemon-reload', and that reload was
# measured at 1.30 s of an 11 s boot (episode 26).
#
# `--no-block' is not an optimisation, it is the same reason as the watcher
# above: we are being sourced BY the relay, which systemd is itself starting,
# so a blocking request would order us into a transaction we are part of.  The
# `systemctl start' inside the transient unit, on the contrary, is deliberately
# blocking -- by then the transaction is finished.
#
# THE FALLBACK IS THE POINT: whatever fails here (no `systemd-run', no D-Bus,
# a refusal), the prompt is started straight away instead.  A guest that gets
# its prompt too early is the defect we are fixing; a guest that never gets one
# is a guest nobody can log into.  Same reason for the `timeout': waiting for
# the end of a boot which never ends must not cost the login.
# ---------------------------------------------------------------------------

if [[ -d /run/systemd/system ]] && type -p systemctl >/dev/null 2>&1; then

  case $- in *x*) __mrn_x_prompt=yes ;; *) __mrn_x_prompt=no ;; esac
  { set +x ; } 2>/dev/null

  __mrn_prompt_started=no
  if type -p systemd-run >/dev/null 2>&1; then
    systemd-run --no-block --quiet --unit=marionnet-console-prompt \
      --description="Marionnet: the login prompt, once the boot is over" \
      /bin/sh -c 'timeout 120 systemctl is-system-running --wait >/dev/null 2>&1; exec systemctl start getty@tty0.service' \
      >/dev/null 2>&1 && __mrn_prompt_started=yes
  fi
  if [[ "$__mrn_prompt_started" != yes ]]; then
    systemctl start --no-block getty@tty0.service >/dev/null 2>&1
  fi
  unset __mrn_prompt_started

  [[ "$__mrn_x_prompt" = yes ]] && { set -x ; } 2>/dev/null
  unset __mrn_x_prompt
fi

:
