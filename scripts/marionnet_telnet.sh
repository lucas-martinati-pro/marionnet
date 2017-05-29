#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2017  Jean-Vincent Loddo
# Copyright (C) 2017  Université Paris 13
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
# Usage: marionnet_telnet.sh HOST PORT TIMEOUT
# Add a timeout functionality to the standard program `telnet' 
# ---

# Check dependencies:
type -t telnet &>/dev/null || exit 127
type -t grep   &>/dev/null || exit 127
type -t rm     &>/dev/null || exit 127
# ---

function usage {
  local EXIT_CODE=${1:-0}
  echo "Usage: marionnet_telnet.sh HOST [PORT] [TIMEOUT]"
  echo "---"
  echo "Add a timeout functionality to the standard program \`telnet'." 
  echo "By default, PORT is set to 23, TIMEOUT is set to 30 (seconds)."
  echo "---"
  echo "This utility is called by marionnet (on ports 2601..2612) to" 
  echo "activate Quagga terminals (CISCO-IOS-like commands)." 
  exit $EXIT_CODE
}

# I dont want suppose the presence of `mktemp':
function simple_mktemp {
  local RESULT="${TMPDIR:-/tmp}/simple_mktemp".$RANDOM
  if [[ -f $RESULT ]]; then simple_mktemp; else 
    >$RESULT
    echo $RESULT; 
  fi
}

# I suppose `grep', `rm' (and `telnet', of course) here:
function is_host_accepting_connections {
  local HOST=${1:-"172.23.0.1"} 
  local PORT=${2:-"2601"}
  # ---
  shift 2 || return 3 # invalid call
  # ---
  local TIMEOUT=${1:-"3"}
  # ---
  local TMPFILE=$(simple_mktemp)
  # ---
  telnet $HOST $PORT 1>$TMPFILE 2>/dev/null &  # job %1
  local TELNET_PID="$!"
  # ---
  (sleep $TIMEOUT; kill -9 $TELNET_PID) &>/dev/null & # job %2
  local KILLER_PID="$!"
  # ---
  wait $TELNET_PID &>/dev/null
  # ---
  local JOB1_CODE=$?
  kill -9 $TELNET_PID $KILLER_PID &>/dev/null
  # ---
  local RESULT=2 # host/port unavailable (timeout expired)
  # ---
  if [[ $JOB1_CODE = 1 ]] && grep -q "Connected to $HOST" $TMPFILE; then
    RESULT=0   # connection accepted
  elif [[ $JOB1_CODE = 1 ]]; then
    RESULT=1   # connection refused, but the host is answering: the port is not (already?) open.
  fi
  # ---
  rm -f $TMPFILE
  # ---
  return $RESULT
  }

# Main:

if [[ $1 = "-h" || $1 = "--help" ]]; then usage 0; fi
# else continue:

HOST="$1"
shift 1 || usage 3
# ---
PORT="${1:-23}"                          # the default telnet port is 23 
# ---
TOTAL_TIMEOUT="${2:-"30"}"               # 30 seconds by default
MAX_TRIALS="10"                          # 10 trials, no more
TIMEOUT="$((TOTAL_TIMEOUT/MAX_TRIALS))"  #  3 seconds per trial (10 trials) by default
[[ $TIMEOUT -lt 1 ]] && TIMEOUT=1
# ---
TIME=0
while [[ $TIME -lt $TOTAL_TIMEOUT ]]; do
  # ---
  is_host_accepting_connections "$HOST" "$PORT" "$TIMEOUT" 2>/dev/null;
  LAST_ERROR_CODE=$?
  # ---
  case $LAST_ERROR_CODE in
    # ---
    # Do it now:
    0) exec telnet $HOST $PORT;; 
    # ---
    # Sleep now because `is_host_accepting_connections' has returned immediately in this case:
    1) sleep $TIMEOUT;;
    # ---
  esac
  TIME=$((TIME+TIMEOUT))
done

# ---
# Just before exiting:
# ---
case $LAST_ERROR_CODE in
  1) echo "Connection refused by $HOST on port $PORT" 1>&2 ;;
  2) echo "Timeout exceeded trying to connect to $HOST on port $PORT" 1>&2 ;;
esac

# --- Fail with the last observed error code:
exit $LAST_ERROR_CODE
