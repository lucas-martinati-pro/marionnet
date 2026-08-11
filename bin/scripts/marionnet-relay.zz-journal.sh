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
  # lookup rather than a plain call:
  __mrn_journal_timeout="$(type -p timeout 2>/dev/null)"
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
# SHUTDOWN HOOK (episode 7).  What the session ENDED with.
#
# The two files above are written at boot time.  The exam mode, however, imports
# a report of the session at its END (machine.ml, router.ml), and nobody was
# producing it any more.  The producer is /mnt/hostfs/marionnet-report, deposited
# by the same host code as this file; all that is left to do here is to hook it
# to the shutdown of this guest.  Hooking it from HERE, at the end of the boot,
# is what makes it work on an image that knows nothing about it.
#
# The branch is decided by the GUEST, exactly as the collector above decides its
# own: what a guest declares is worth less than what it runs.
#
# THE UNIT IS THE WHOLE DIFFICULTY, and both halves of it were measured, one
# after the other, by a probe that got them wrong first:
#
#   1. `Conflicts=shutdown.target' is what makes the unit STOP -- hence run its
#      ExecStop -- during the shutdown sequence.  Written with
#      `DefaultDependencies=no' and no Conflicts, the unit is never stopped at
#      all: it is simply killed at the end, and nothing is ever written.
#      Measured: witness absent in that shape, present and dated without
#      `DefaultDependencies=no' (which carries the Conflicts implicitly).
#   2. But the implicit shape is not enough either: with the DEFAULT
#      dependencies the ExecStop is ordered against nothing, so the rest of the
#      shutdown runs in parallel and the guest powers off IN THE MIDDLE of the
#      report.  Measured: a report cut in half, mid-command.  Hence the explicit
#      shape below -- `Before=shutdown.target umount.target' puts our ExecStop
#      first, and everything else waits for it -- with `After=network.target' so
#      that the network configuration is still readable when we describe it.
#
# Never fatal, never noisy: a guest that refuses the hook simply has no report.
#
# KNOWN LIMIT, measured: on the old SysV images (wheezy, guignol), the shutdown
# sequence is NOT played at all.  Marionnet extinguishes a guest with
# `uml_mconsole cad', and their /etc/inittab answers it with `/sbin/halt'
# directly -- a deliberate Marionnet workaround (a `-r' crashes 3.2.x kernels,
# see the /sbin/shutdown wrapper of those images) which bypasses /etc/rc0.d
# entirely.  The K01 link below therefore only fires when the shutdown is asked
# from INSIDE the guest.  Those images still get their command history and their
# two boot journals, which do not depend on any shutdown.
# ---------------------------------------------------------------------------

__mrn_journal_hook=/mnt/hostfs/marionnet-report

if [[ -r "$__mrn_journal_hook" ]]; then

  case $- in *x*) __mrn_journal_x_hook=yes ;; *) __mrn_journal_x_hook=no ;; esac
  { set +x ; } 2>/dev/null

  if [[ -d /run/systemd/system ]] && type -p systemctl >/dev/null 2>&1; then
    {
      cat > /run/systemd/system/marionnet-report.service <<UNIT
[Unit]
Description=Marionnet: end-of-session report (journalisation-profonde)
DefaultDependencies=no
Conflicts=shutdown.target
Before=shutdown.target umount.target
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/bin/bash $__mrn_journal_hook
TimeoutStopSec=60
UNIT
      systemctl daemon-reload
      # `start' is enough: the unit exists only for its ExecStop, and it is the
      # shutdown that will stop it.  No `enable' (nothing must survive a reboot
      # of the guest: the host deposits everything again anyway).
      systemctl start marionnet-report.service
    } >/dev/null 2>&1
  elif [[ -d /etc/rc0.d && -d /etc/init.d ]]; then
    {
      cat > /etc/init.d/marionnet-report <<INIT
#!/bin/sh
### BEGIN INIT INFO
# Provides:          marionnet-report
# Required-Start:
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Marionnet: end-of-session report
### END INIT INFO
case "\$1" in
  stop) /bin/bash $__mrn_journal_hook ;;
  *)    : ;;
esac
INIT
      chmod +x /etc/init.d/marionnet-report
      # K01: as early as possible in the shutdown sequence, so that the hostfs is
      # still mounted and the network still configured when the report is taken.
      ln -sf ../init.d/marionnet-report /etc/rc0.d/K01marionnet-report
      [[ -d /etc/rc6.d ]] && ln -sf ../init.d/marionnet-report /etc/rc6.d/K01marionnet-report
    } >/dev/null 2>&1
  fi

  [[ "$__mrn_journal_x_hook" = yes ]] && { set -x ; } 2>/dev/null
  unset __mrn_journal_x_hook
fi
unset __mrn_journal_hook

:
