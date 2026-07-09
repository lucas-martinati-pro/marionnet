#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
# Copyright (C) 2026  Université Sorbonne Paris Nord

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This script boots a single guest filesystem with its paired UML kernel, in a
# throw-away COW layer (the image stays intact), for a quick boot-test outside
# Marionnet. With no argument it picks the LAST built image (of pupisto.debian),
# derives the matching kernel, and reproduces Marionnet's boot dispatch through a
# couple-keyed quirks table (BOOT_QUIRKS below): the set of extra UML kernel
# arguments required for a given (kernel-series, init-system) couple. E.g. a
# systemd rootfs on a 6.12 kernel needs `console=tty0' so that
# systemd-getty-generator spawns a getty on the Marionnet console (ep.4). This
# table is the Bash counterpart of what simulation_level.ml will hold on the OCaml
# side, so the two stay in sync.
#
# Two modes:
#  * default : open the guest console in an `xterm' (interactive, needs X11);
#  * --headless : run the guest with its console on stdout, under a `timeout',
#    so the boot can be captured and driven in a fully automated fix/retry loop
#    (no X11, no sudo). No swap device is provided: the systemd rootfs marks its
#    /etc/fstab swap entry `nofail' (see pupisto.debian.sh), so a missing swap no
#    longer stalls the boot.

# =============================================================
#                AUTOMATIC LOG-FILE GENERATION
# =============================================================

MY_BASENAME=$(basename $0)
if [[ $1 = "--help" || $1 = "-h" ]]; then
  # do nothing and continue
  :
elif grep -q "log_${MY_BASENAME}[.]......$" <<<"$1"; then
  LOGFILE=$1
  shift
  # and continue
else
  LOGFILE=$(mktemp /tmp/log_${MY_BASENAME}.XXXXXX)
  EXIT_CODE_FILE=$(mktemp /tmp/exit_code_${MY_BASENAME}.XXXXXX)
  echo -e "Log file of command:\n$0" "$@" "\n---" | tee $LOGFILE
  COLUMNS=$(tput cols 2>/dev/null || echo 200)
  # Recursive call to this script, but with logging capabilities:
  { time $0 "$LOGFILE" "$@"; echo $? >$EXIT_CODE_FILE; } 2>&1 | tee -a "$LOGFILE" | cut -c1-$((COLUMNS))
  read EXIT_CODE <$EXIT_CODE_FILE
  rm -f $EXIT_CODE_FILE
  echo "---"
  echo "$MY_BASENAME: previous running logged into $LOGFILE"
  exit $EXIT_CODE
fi

# Script body:
set -e

# =============================================================
#                        DIRECTORIES
# =============================================================

# Resolve our own location (robust to the caller's CWD), then the `uml/' root and
# the sibling directory where pupisto.debian drops its `_build.debian-*' images.
SCRIPT_DIR=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)
UML_DIR=$(dirname "$SCRIPT_DIR")
REPO_DIR=$(dirname "$UML_DIR")

# bashbricks (vendored at the repo root): sourced for its Map_* pseudo-module,
# used by the boot-quirks table below.
source "$REPO_DIR/bashbricks/bashbricks.sh"

# =============================================================
#                          DEFAULTS
# =============================================================

DEFAULT_IMAGES_DIR="$UML_DIR/pupisto.debian"
DEFAULT_MEM="512M"      # the `.conf' suggests ~80M: far too little for trixie+systemd
DEFAULT_UMID="tester"
DEFAULT_TIMEOUT="120"   # headless: seconds before the guest is killed

# =============================================================
#                     BOOT-QUIRKS TABLE
# =============================================================

# Extra UML kernel arguments required only for a given (kernel-series, init-system)
# couple, keyed as "SERIES:INIT" (e.g. "6.12:systemd"). A missing key means "no
# extra argument" (e.g. any "*:sysv": /etc/inittab already starts a getty on tty0).
# This is the single place the launcher consults; keep it in sync with the OCaml
# dispatch (simulation_level.ml). `--no-tty0' overrides it for the ep.4 A/B test.
Map_make BOOT_QUIRKS
Map_set  BOOT_QUIRKS "6.12:systemd" "console=tty0"

# =============================================================
#                      CMDLINE PARSING
# =============================================================

# Getopt's format used to parse the command line:
OPTSTRING="hi:k:m:wn:dTNHt:x:"

function parse_cmdline {
local i j flag
# Transform long format options into the short one:
for i in "$@"; do
  if [[ double_dash_found = 1 ]]; then
    ARGS+=("$i")
  else case "$i" in
    --help)      ARGS+=("-h");;
    --image)     ARGS+=("-i");;
    --kernel)    ARGS+=("-k");;
    --mem)       ARGS+=("-m");;
    --writable)  ARGS+=("-w");;
    --net)       ARGS+=("-n");;
    --debug)     ARGS+=("-d");;
    --no-tty0)   ARGS+=("-T");;
    --dry-run)   ARGS+=("-N");;
    --headless)  ARGS+=("-H");;
    --timeout)   ARGS+=("-t");;
    --extra)     ARGS+=("-x");;
    --)
      ARGS+=("--");
      double_dash_found=1;
      ;;
    --[a-zA-Z0-9]*)
      echo "*** Illegal long option $i.";
      exit 1;
      ;;
    -[a-zA-Z0-9]*)
      j="${i:1}";
      while [[ $j != "" ]]; do ARGS+=("-${j:0:1}"); j="${j:1}"; done;
      ;;
    *)
      ARGS+=("$i")
      ;;
  esac
  fi
done
set - "${ARGS[@]}"
unset ARGS

# Interpret short format options:
while [[ $# -gt 0 ]]; do
  OPTIND=1
  while getopts ":$OPTSTRING" flag; do
    if [[ $flag = '?' ]]; then
      echo "ERROR: illegal option -$OPTARG.";
      exit 1;
    fi
    eval "option_${flag}=$OPTIND"
    eval "option_${flag}_arg='$OPTARG'"
  done
  for ((j=1; j<OPTIND; j++)) do
    if [[ $1 = "--" ]]; then
      shift;
      for i in "$@"; do ARGS+=("$i"); shift; done
      break 2;
    else
      shift;
    fi
  done
  # Get just the first argument and reloop:
  for i in "$@"; do ARGS+=("$i"); shift; break; done
done
} # end of parse_cmdline()

declare -a ARGS
parse_cmdline "$@" # read OPTSTRING and set ARGS

if [[ ${#ARGS[@]} -eq 0 ]]; then
  set - "";
else
  set - "${ARGS[@]}";
fi
unset ARGS

function print_usage_and_exit {
 echo "\
Usage: ${0##*/} [OPTIONS]
Boot-test a guest filesystem with its paired UML kernel, in a throw-away COW.

With no option, the LAST image built under \`${DEFAULT_IMAGES_DIR##*/}/_build.debian-*'
is booted, the matching kernel is derived from it, and \`console=tty0' is added
when the rootfs is a systemd one (INIT_SYSTEM=systemd in its .conf).

Options:
  -i/--image FILE    ext4 image to boot (default: last built one)
  -k/--kernel FILE   UML kernel binary (default: derived from the image's _build)
  -m/--mem SIZE      guest memory (default ${DEFAULT_MEM})
  -n/--net TAP       attach eth0=tuntap,TAP (default: no network -- base test)
  -T/--no-tty0       do NOT add console=tty0 (A/B test of the ep.4 hypothesis)
  -w/--writable      boot WITHOUT a COW layer (WARNING: writes into the image)
  -H/--headless      no xterm: console on stdout, under a timeout (scriptable)
  -t/--timeout SEC   headless timeout before killing the guest (default ${DEFAULT_TIMEOUT})
  -x/--extra \"ARGS\"   extra kernel arguments appended to the command line
  -d/--debug         run the kernel under gdb (xterm mode only)
  -N/--dry-run       resolve image/kernel/args and print them, but do NOT boot
  -h/--help          this help

Examples:
  ${0##*/}                    # xterm, last image, systemd + console=tty0, COW
  ${0##*/} --headless         # scriptable boot captured on stdout (fix/retry loop)
  ${0##*/} --headless --no-tty0   # same, without console=tty0 (compare getty)"
 exit ${1:-0}
}

[[ -n $option_h ]] && print_usage_and_exit 0

# =============================================================
#                     OPTION VALUES
# =============================================================

IMAGE=${option_i_arg:-}
KERNEL=${option_k_arg:-}
MEM=${option_m_arg:-$DEFAULT_MEM}
TAP=${option_n_arg:-}
EXTRA=${option_x_arg:-}
TIMEOUT=${option_t_arg:-$DEFAULT_TIMEOUT}
ADD_TTY0=y  ; [[ -n $option_T ]] && ADD_TTY0=n
USE_COW=y   ; [[ -n $option_w ]] && USE_COW=n
HEADLESS=n  ; [[ -n $option_H ]] && HEADLESS=y
DRY_RUN=n   ; [[ -n $option_N ]] && DRY_RUN=y
DEBUG=n     ; [[ -n $option_d ]] && DEBUG=y

# Throw-away COW file to clean up on exit:
COWFILE=
function cleanup { rm -f "$COWFILE"; }
trap cleanup EXIT

# =============================================================
#                        RESOLUTION
# =============================================================

# find_latest_image: echo the last-built `machine-debian-*' image (excluding the
# `.conf' side-file), searching the newest `_build.debian-*' directory first.
function find_latest_image {
 local d
 for d in $(ls -dt "$DEFAULT_IMAGES_DIR"/_build.debian-*/ 2>/dev/null); do
   local img=$(ls "$d"machine-debian-* 2>/dev/null | \grep -v '[.]conf$' | head -n 1)
   if [[ -n $img ]]; then echo "$img"; return 0; fi
 done
 return 1
}

# kernel_of_image IMAGE: echo the UML kernel binary paired with IMAGE. The image
# lives in a `_build.debian-*/' directory holding a `linux-<version>' symlink to
# the kernel build directory, whose `linux' file is the ELF executable.
function kernel_of_image {
 local img="$1"
 local build=$(dirname "$img")
 local k=$(ls -d "$build"/linux-*/linux 2>/dev/null | head -n 1)
 [[ -n $k ]] || return 1
 echo "$k"
}

# read_conf_field KEY CONF: echo the value of `KEY=...' in the image .conf, with
# surrounding quotes stripped. Empty if absent.
function read_conf_field {
 local key="$1" conf="$2"
 [[ -f $conf ]] || return 0
 \grep -E "^${key}=" "$conf" | head -n 1 | cut -d= -f2- | tr -d "'\""
}

# kernel_series_of KERNEL: echo the "MAJOR.MINOR" series of the UML kernel. The
# version is embedded in the path as `linux-<version>' -- either the per-image
# `linux-6.12.95' symlink or, once realpath'd, the resolved build directory
# `_build.linux-6.12.95...'. We grep the first `linux-MAJOR.MINOR' occurrence, so
# both spellings work. Empty for a path without it (e.g. a custom -k binary), in
# which case the BOOT_QUIRKS lookup simply misses (shown in the recap).
function kernel_series_of {
 local s=$(echo "$1" | \grep -oE 'linux-[0-9]+\.[0-9]+' | head -n 1)
 echo "${s#linux-}"
}

# =============================================================
#                          MAIN
# =============================================================

# Resolve the image:
if [[ -z $IMAGE ]]; then
  IMAGE=$(find_latest_image) || {
    echo "Error: no image found under $DEFAULT_IMAGES_DIR/_build.debian-*/ (build one with 'make trixie')." 1>&2
    exit 2
  }
fi
[[ -f $IMAGE ]] || { echo "Error: image '$IMAGE' not found." 1>&2; exit 2; }
IMAGE=$(realpath "$IMAGE")
CONF="$IMAGE.conf"

# Resolve the kernel:
if [[ -z $KERNEL ]]; then
  KERNEL=$(kernel_of_image "$IMAGE") || {
    echo "Error: no kernel 'linux-*/linux' next to the image ($(dirname "$IMAGE"))." 1>&2
    exit 3
  }
fi
[[ -x $KERNEL ]] || { echo "Error: kernel '$KERNEL' not found or not executable." 1>&2; exit 3; }
KERNEL=$(realpath "$KERNEL")

# Reproduce Marionnet's boot dispatch (ep.4) via the couple-keyed quirks table:
# look up "SERIES:INIT" in BOOT_QUIRKS for the extra UML arguments.
INIT_SYSTEM=$(read_conf_field INIT_SYSTEM "$CONF"); INIT_SYSTEM=${INIT_SYSTEM:-sysv}
KSERIES=$(kernel_series_of "$KERNEL")
QUIRK_KEY="$KSERIES:$INIT_SYSTEM"
KOPTS=""
if Map_has_key BOOT_QUIRKS "$QUIRK_KEY"; then KOPTS=$(Map_get BOOT_QUIRKS "$QUIRK_KEY"); fi
# --no-tty0: drop console=tty0 for an A/B comparison of the ep.4 hypothesis.
[[ $ADD_TTY0 = n ]] && KOPTS=${KOPTS/console=tty0/}
[[ -n $TAP ]] && KOPTS="$KOPTS eth0=tuntap,$TAP"

# Root filesystem: a throw-away COW layer keeps the image intact.
if [[ $USE_COW = y ]]; then
  COWFILE=$(mktemp /tmp/pupisto.tester.XXXXXXX.cow); rm -f "$COWFILE" # UML creates it
  UBDA="$COWFILE,$IMAGE"
else
  UBDA="$IMAGE"
fi

# Common UML kernel command line (kernel + arguments). No swap device: the systemd
# rootfs marks its fstab swap entry `nofail', so a missing swap no longer stalls.
CMDLINE="$KERNEL keyboard_layout=us ubda=$UBDA umid=$DEFAULT_UMID mem=$MEM root=98:0 hostname=$DEFAULT_UMID guestkind=machine $KOPTS $EXTRA"

# Recap:
echo "=============================================================="
echo " pupisto.tester -- boot-test ($([[ $HEADLESS = y ]] && echo headless || echo xterm))"
echo "   image        : $IMAGE"
echo "   kernel       : $KERNEL"
echo "   init system  : $INIT_SYSTEM  (from ${CONF##*/})"
echo "   kernel series: ${KSERIES:-<unknown>}"
echo "   boot quirks  : ${QUIRK_KEY} -> ${KOPTS:-<none>}"
echo "   memory       : $MEM"
echo "   console=tty0 : $([[ $KOPTS = *console=tty0* ]] && echo yes || echo no)"
echo "   network      : $([[ -n $TAP ]] && echo "eth0=tuntap,$TAP" || echo none)"
echo "   COW          : $([[ $USE_COW = y ]] && echo "yes (image kept intact)" || echo "NO -- writing into the image!")"
[[ $HEADLESS = y ]] && echo "   timeout      : ${TIMEOUT}s"
echo "=============================================================="

if [[ $DRY_RUN = y ]]; then echo "(dry-run: not booting)"; exit 0; fi

# Boot.
if [[ $HEADLESS = y ]]; then
  # Console on stdout, all other consoles/serials to null; stdin closed; killed
  # after $TIMEOUT. `timeout' returns 124 on expiry -- expected, not an error here.
  echo "+ (headless, ${TIMEOUT}s) $CMDLINE con=null con0=fd:0,fd:1"
  set +e
  timeout --foreground -s KILL "$TIMEOUT" \
    $CMDLINE con=null con0=fd:0,fd:1 </dev/null
  RC=$?
  set -e
  [[ $RC = 137 || $RC = 124 ]] && echo "(guest killed after ${TIMEOUT}s timeout -- expected)"
else
  GDB=
  [[ $DEBUG = y ]] && GDB='gdb -ex "handle SIGSEGV nostop noprint" -ex "handle SIGUSR1 nopass stop print" -ex run --args '
  xterm -l -sb -T "$DEFAULT_UMID" -e "${GDB}${CMDLINE}"
  echo "fuser -k:"; fuser -k "$IMAGE" 2>/dev/null || true
fi
