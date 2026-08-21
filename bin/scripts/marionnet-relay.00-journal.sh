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
# Guest-side journal, PROLOGUE.  Deep logging, episode 1.
#
# This file belongs to NO guest image.  The host deposits it, at every boot,
# into the hostfs directory (`make_hostfs_content', bin/simulation_level.ml),
# under the name `marionnet-relay.00-journal'.  The guest relay ends its
# startup by sourcing /mnt/hostfs/{<image>.,marionnet-}relay* in ALPHABETICAL
# order (uml/guest/marionnet-relay), hence:
#
#     marionnet-relay.00-journal   <- this prologue
#     marionnet-relay.rcfile       <- the user's startup configuration
#     marionnet-relay.zz-journal   <- the epilogue, which undoes all of this
#
# so the user's configuration is framed without touching a single image.
#
# What it buys: whatever the startup configuration prints (standard output AND
# standard error), the trace of the commands themselves, and the exit status of
# the ones that fail, all survive host-side in /mnt/hostfs/rc_config.log.  Until
# this episode, a failing rc_config left nothing at all behind.
#
# Since episode 16 of `marionnet-todo-transverse' it also arms the SHUTDOWN HOOK
# (last section of this file).  Position, there, is the whole point: the hook must
# be in place before the user's startup configuration runs, because that is what
# writes the readiness marker `wait --ready' answers on.
#
# Two constraints drive every line below, both coming from the fact that this
# file is sourced INSIDE the relay's own shell (in its `start' function):
#
#   1. any redirection installed here would leak over the whole end of the boot
#      (`clear', `linuxlogo', the console banner).  So we save here what the
#      epilogue puts back: xtrace, errtrace, PS4, the ERR trap, and above all
#      the standard descriptors (kept in 3 and 4);
#   2. nothing here may break a boot.  Every step is guarded, and this file
#      always returns success.
#
# Plain Bash on purpose: this code runs inside the guest, which has no
# `bashbricks' (nor anything beyond a minimal userland).
# ---------------------------------------------------------------------------

__mrn_journal_log=/mnt/hostfs/rc_config.log

# --- Save the state the epilogue will restore:
case $- in *x*) __mrn_journal_x_was_on=yes ;; *) __mrn_journal_x_was_on=no ;; esac
case $- in *E*) __mrn_journal_E_was_on=yes ;; *) __mrn_journal_E_was_on=no ;; esac
__mrn_journal_ps4="$PS4"
__mrn_journal_err_trap="$(trap -p ERR 2>/dev/null)"

# --- The hostfs is a LIVING journal (decision D3): one boot, one file.  If it
#     cannot even be created, we degrade to a no-op rather than break the boot:
if ! { : > "$__mrn_journal_log" ; } 2>/dev/null; then
  __mrn_journal_log=""
fi

if [[ -n "$__mrn_journal_log" ]]; then

  { echo "# Marionnet guest journal (startup configuration)"
    echo "# date: $(date '+%F %T %z' 2>/dev/null)"
    echo "# host: $(uname -srm 2>/dev/null)"
  } >> "$__mrn_journal_log" 2>/dev/null

  # --- Keep the standard descriptors aside, then capture.  With `tee' the
  #     student keeps seeing the boot on the console; without it, the journal
  #     wins over the console (and says so):
  exec 3>&1 4>&2

  # `tee' is reached through a PROCESS SUBSTITUTION, and bash implements that one
  # by opening /dev/fd/<n> IN THIS SHELL.  A 2013 image does not necessarily have
  # /dev/fd when it runs: the symlink shipped in the image is masked by the tmpfs
  # mounted over /dev at boot, and its init never puts it back (Debian does that
  # in mountdevsubfs.sh).  Measured on debian-wheezy-08367, episode 14: the `exec'
  # below then FAILS -- silently, and as a whole, `2>&1' included -- the shell
  # carries on with its original descriptors, and the journal keeps nothing but
  # the header written above.  `type -p tee' never was the right question: tee is
  # there, it is the substitution that cannot be opened.
  #
  # So, in order: put /dev/fd back if it is missing (a tmpfs: no image, not even
  # the COW, is written to), then MEASURE whether the substitution works, and
  # only then choose -- the measure covers every cause, not just this one.
  if [[ ! -e /dev/fd && -d /proc/self/fd ]]; then
    ln -s /proc/self/fd /dev/fd 2>/dev/null
  fi
  if ! type -p tee >/dev/null 2>&1; then
    __mrn_journal_why="no tee in this image"
  elif ! ( exec 9> >(cat >/dev/null) ) 2>/dev/null; then
    __mrn_journal_why="no usable /dev/fd in this image"
  else
    __mrn_journal_why=""
  fi
  if [[ -z "$__mrn_journal_why" ]]; then
    exec > >(tee -a "$__mrn_journal_log") 2>&1
    __mrn_journal_tee_pid=$!
    echo "# capture: tee (console and journal)"
  else
    exec >> "$__mrn_journal_log" 2>&1
    __mrn_journal_tee_pid=""
    echo "# capture: journal only ($__mrn_journal_why), the console keeps nothing"
  fi
  unset __mrn_journal_why

  # --- A sourced file does not abort on error: the exit status of a failing
  #     command would be lost.  This trap is what makes it visible.  `errtrace'
  #     extends it to the functions and subshells of the configuration:
  #     Tracing is suspended inside the trap and put back on the way out: the point of the
  #     journal is a readable failure, not the trace of the reporting machinery itself.
  __mrn_journal_on_error() {
    local __mrn_status=$?
    { set +x ; } 2>/dev/null
    echo "!! FAILED (status $__mrn_status): $BASH_COMMAND"
    if [[ -n "$__mrn_journal_tracing" ]]; then { set -x ; } 2>/dev/null; fi
  }
  __mrn_journal_tracing=yes
  set -o errtrace
  trap '__mrn_journal_on_error' ERR

  PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
  set -x
fi

# ---------------------------------------------------------------------------
# COMMAND HISTORY (episode 7).  What the student typed, host-side and dated.
#
# The exam mode imports <hostfs>/bash_history.text at shutdown (machine.ml,
# router.ml) and NOBODY was writing it: the historical producer copied
# /root/.bash_history from a shutdown script (uml/startup.old), which is
# fragile -- an interactive Bash killed during shutdown writes nothing at all.
#
# So the history is written CONTINUOUSLY instead of being grabbed at the end:
# the history file *is* the one in the hostfs, and every prompt appends to it.
# Three consequences: no shutdown hook is needed for it, the file can be read
# WHILE the machine runs (the channel serves it under the name `history'), and
# it is already there when the exam mode imports it.
#
# It is dated, and that is the point: with HISTTIMEFORMAT set, Bash writes a
# `#<epoch>' line before every command, so the sessions of m1, m2, r1... merge
# into one chronology -- which is what a corrector (human or agent) needs. The
# PROMPT (PS1) is deliberately NOT touched: a clock in the prompt would suggest
# to the student that speed is being measured, and it is not.
#
# Deposited in two places because a shell reads only one of them: /etc/profile.d
# for login shells, and appended to the guest's bashrc for the others. Both are
# in the COW file, so no image is modified (decision D1). Independent of the
# capture above -- its own guard -- because a journal that could not be created
# is no reason to lose the history too.
# ---------------------------------------------------------------------------

__mrn_history_snippet=/etc/profile.d/marionnet-journal.sh

if mkdir -p /etc/profile.d 2>/dev/null && [[ -d /mnt/hostfs ]]; then

  if ! cat > "$__mrn_history_snippet" 2>/dev/null <<'__MRN_HISTORY__'
# Marionnet, deep logging (journalisation-profonde, episode 7).  Deposited at
# every boot by the host into the guest's COW file: this file belongs to no
# image, and editing it here has no effect beyond the current session.
#
# Keeps this guest's command history on the HOST side, timestamped, and up to
# date at every prompt rather than at the death of the shell.
if [ -n "${BASH_VERSION:-}" ] && [ -d /mnt/hostfs ]; then
  HISTFILE=/mnt/hostfs/bash_history.text
  HISTTIMEFORMAT='%F %T '
  HISTSIZE=10000
  HISTFILESIZE=100000
  shopt -s histappend 2>/dev/null
  # `history -a' appends only what THIS shell typed, so several consoles on the
  # same guest cannot overwrite each other.  Prepended, and only once:
  case ";${PROMPT_COMMAND:-};" in
    *";history -a;"*) : ;;
    *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
  esac
fi
__MRN_HISTORY__
  then
    __mrn_history_snippet=""
  fi

  # A login shell reads /etc/profile.d; an interactive non-login shell (the
  # usual case under a Marionnet xterm) reads a bashrc only.  Appended at the
  # END so that whatever the image's own bashrc does is done first:
  if [[ -n "$__mrn_history_snippet" ]]; then
    for __mrn_history_rc in /root/.bashrc /etc/bash.bashrc; do
      [[ -f "$__mrn_history_rc" ]] || continue
      grep -q 'marionnet-journal[.]sh' "$__mrn_history_rc" 2>/dev/null && continue
      printf '\n# Marionnet deep logging (episode 7):\n. %s\n' \
        "$__mrn_history_snippet" >> "$__mrn_history_rc" 2>/dev/null
    done
    unset __mrn_history_rc
  fi

fi
unset __mrn_history_snippet

# ---------------------------------------------------------------------------
# SHUTDOWN HOOK (episode 7).  What the session ENDED with.
#
# Everything above is written while the guest boots.  The exam mode, however,
# imports a report of the session at its END (machine.ml, router.ml), and nobody
# was producing it any more.  The producer is /mnt/hostfs/marionnet-report,
# deposited by the same host code as this file; all that is left to do here is to
# hook it to the shutdown of this guest.  Hooking it from a file the host deposits
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
#
# WHY IT IS HERE, IN THE PROLOGUE, AND NOT IN THE EPILOGUE (episode 16 of
# `marionnet-todo-transverse').  It used to be armed by marionnet-relay.zz-journal,
# i.e. AFTER the user's startup configuration -- and the readiness marker that
# `wait --ready' answers on is written BY that configuration.  A session which did
# what every bench and every teacher does, `wait --ready' then shut the guest down,
# therefore raced the arming of its own hook.  Measured, and deterministic: with a
# startup configuration which writes the marker and then keeps working for 40s,
# `wait --ready' answers after 8.6s, the hook is armed 40s later, and the graceful
# shutdown asked in between leaves NO report.md at all.  Sourced from here, the
# hook is armed before the guest can be declared ready by anything.
#
# The blocking `systemctl start' is deliberate and is what the move buys: when that
# line returns, the unit IS active, hence armed.  `--no-block' (which the watcher
# below needs, for its own reason) would put a smaller race back in place of the big
# one.  `After=network.target' is kept for the STOP ordering it gives -- systemd
# stops in reverse start order, so it is what keeps the network up while the report
# is being taken -- and not for the start.
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
