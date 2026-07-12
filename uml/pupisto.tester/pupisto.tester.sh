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
# --- auto-network (-A): host<->guest tap on a NORMAL lab interface eth0 + sshd ---
# eth0 (not eth42): the Debian 13 native relay ghostifies eth42 into a hidden netns as
# soon as ip42 is set, which would move the ssh channel out of the root namespace. eth0
# is a plain lab interface, never ghostified. Each -A instance gets a FREE octet K
# (1..254) so several images can run at once: it keys the tap name, the umid/mconsole,
# and a private 172.23.K.0/24 subnet.
NET_BASE="172.23"             # /16 space; each instance carves out a 172.23.K.0/24
NET_PREFIX="24"               # host tap prefix (guest eth0 stays /16 -- marionnet-relay)
NET_TAP_PREFIX="mnt-tap"      # tap name prefix; must match the sudoers rule (mnt-tap*)
NET_SSH_KEY="$SCRIPT_DIR/tester_key"   # tester's own ssh key (generated on first use, gitignored)
NET_SUDOERS="/etc/sudoers.d/marionnet-tester"        # NOPASSWD rule for the tap commands
# Per-instance values (X11_* for -X eth42, SSH_* for -A eth0) are filled in from a free
# octet K just before the guest is booted -- see the "Network setup" section below.

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
OPTSTRING="hi:k:m:wn:dTNHt:x:XASc"

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
    --display)   ARGS+=("-X");;
    --auto-network-by-eth0)  ARGS+=("-A");;
    --ssh-only)  ARGS+=("-S");;
    --console)   ARGS+=("-c");;
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
  -H/--headless      no xterm: boot captured on stdout under a timeout, NON-interactive
                     (stdin closed, so no login) -- for scripted/CI boot-tests
  -c/--console       no xterm: interactive console on the CURRENT terminal (stdin open,
                     so you can log in root/root), no timeout. Combinable with -A.
                     Known quirk: the UML \`fd' console channel echoes with a one-line
                     lag (the prompt shows only after you press ENTER); login still works.
                     Use -X for a fully fluid console (xterm allocates a real pty).
  -t/--timeout SEC   headless timeout before killing the guest (default ${DEFAULT_TIMEOUT})
  -x/--extra \"ARGS\"   extra kernel arguments appended to the command line
  -X/--display       show guest graphical apps (xeyes, wireshark) on the host X server:
                     eth42 service tap, GHOSTIFIED in the guest by its NATIVE relay via a
                     network namespace (student's \`ip a' hides it), X11 relayed over it.
                     xterm mode; with --headless, only the guest mechanism is set up and
                     checked from the hostfs (no local X server needed).
  -A/--auto-network-by-eth0
                     just wire a host<->guest tap on eth0 (host 172.23.K.254, guest
                     172.23.K.1), torn down on exit. Nothing else: the boot mode is
                     unchanged (xterm by default), so you get a normal login console
                     WITH a working eth0. Combinable with -X (eth42 stays the ghostified
                     X11 link). First use provisions a NOPASSWD sudoers rule (one password).
  -S/--ssh-only      autonomous headless driving: implies -A, then starts sshd in the
                     guest, authorizes the tester key, boots the guest in the background
                     (no console login) and prints a ready 'ssh root@172.23.K.1' command.
                     For scripted tests without a screen. Incompatible with -X and -H.
  -d/--debug         run the kernel under gdb (xterm mode only)
  -N/--dry-run       resolve image/kernel/args and print them, but do NOT boot
  -h/--help          this help

Examples:
  ${0##*/}                    # xterm, last image, systemd + console=tty0, COW
  ${0##*/} --headless         # scriptable boot captured on stdout (fix/retry loop, no login)
  ${0##*/} --console          # interactive login console on the current terminal (no X)
  ${0##*/} --headless --no-tty0   # same as headless, without console=tty0 (compare getty)
  ${0##*/} -X                 # xterm + guest X11 on the host (eth42 ghostified via netns)
  ${0##*/} -A                 # xterm with a working eth0 (host<->guest tap), login as usual
  ${0##*/} -X -A              # xterm + guest X11 AND a working eth0
  ${0##*/} -S                 # headless: boot in background, then ssh root@172.23.K.1"
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
CONSOLE=n   ; [[ -n $option_c ]] && CONSOLE=y
DRY_RUN=n   ; [[ -n $option_N ]] && DRY_RUN=y
DEBUG=n     ; [[ -n $option_d ]] && DEBUG=y
DISPLAY_MODE=n ; [[ -n $option_X ]] && DISPLAY_MODE=y
AUTO_NET=n  ; [[ -n $option_A ]] && AUTO_NET=y
SSH_ONLY=n  ; [[ -n $option_S ]] && SSH_ONLY=y
[[ $SSH_ONLY = y ]] && AUTO_NET=y      # -S needs the eth0 wiring that -A sets up
UMID="$DEFAULT_UMID"   # overridden to tester-<K> when a tap is set up (unique mconsole per instance)

# Throw-away COW file (and X11 socat/pty, auto-network tap/hostfs, if any) to clean up on exit:
COWFILE=
XSOCAT_PID=
X_HOST_ADDED=n
HOSTFS_DIR=
UML_PID=
CREATED_TAPS=()   # every tap we created (-X and/or -A); torn down on exit
function cleanup {
  [[ -n $UML_PID ]] && kill "$UML_PID" 2>/dev/null
  rm -f "$COWFILE"
  [[ -n $XSOCAT_PID ]] && kill "$XSOCAT_PID" 2>/dev/null
  [[ $X_HOST_ADDED = y ]] && xhost -local: >/dev/null 2>&1
  net_taps_down
  [[ -n $HOSTFS_DIR ]] && rm -rf "$HOSTFS_DIR"
}
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
#              AUTO-NETWORK (-A): tap + sshd helpers
# =============================================================

# A host<->guest `tap' carrying eth0 (a plain lab interface, never ghostified -- unlike
# eth42). The host end is 172.23.K.254/24, the guest eth0 is 172.23.K.1/16, configured
# by marionnet-relay's standard per-interface loop from ethernet_interfaces_no and
# ipv4_*_eth0 in boot_parameters. We inject the tester's public key and start sshd via
# marionnet-relay's extension mechanism (it sources every /mnt/hostfs/marionnet-relay*
# at boot). Tap creation needs root: the first run provisions a NOPASSWD sudoers rule
# scoped to the `mnt-tap*' tap commands, so later runs are non-interactive (autonomous).

# net_free_octet: echo the first octet K in 1..254 whose 172.23.K.0/24 is free (no
# 172.23.K.254 address already assigned and no mnt-tapK interface). Lets several -A
# instances coexist. Fails if all are taken.
function net_free_octet {
 local k
 for k in $(seq 1 254); do
   ip -o -4 addr show 2>/dev/null | grep -q "${NET_BASE//./\\.}\.$k\.254/" && continue
   ip -o link show "${NET_TAP_PREFIX}${k}" &>/dev/null && continue
   echo "$k"; return 0
 done
 return 1
}

# net_sudoers_content: echo the exact sudoers rule we expect/install.
function net_sudoers_content {
 local u ipbin; u=$(id -un); ipbin=$(command -v ip)
 cat <<EOF
# Installed by pupisto.tester.sh (--auto-network-by-eth0). Scope: mnt-tap* only.
$u ALL=(root) NOPASSWD: $ipbin tuntap add dev mnt-tap* mode tap user $u
$u ALL=(root) NOPASSWD: $ipbin tuntap del dev mnt-tap* mode tap
$u ALL=(root) NOPASSWD: $ipbin addr add * dev mnt-tap*
$u ALL=(root) NOPASSWD: $ipbin link set mnt-tap* *
$u ALL=(root) NOPASSWD: $ipbin link del mnt-tap*
EOF
}

# ensure_net_sudoers: install the NOPASSWD rule if missing (interactive sudo, once).
function ensure_net_sudoers {
 local want; want=$(net_sudoers_content)
 echo "* Auto-network needs a NOPASSWD sudoers rule for the tap commands." 1>&2
 echo "  Installing $NET_SUDOERS (you may be asked for your password once):" 1>&2
 printf '%s\n' "$want" | sed 's/^/    /' 1>&2
 printf '%s\n' "$want" | sudo tee "$NET_SUDOERS" >/dev/null || { echo "  FAILED to write $NET_SUDOERS" 1>&2; return 1; }
 sudo chmod 0440 "$NET_SUDOERS"
 sudo visudo -cf "$NET_SUDOERS" >/dev/null || { echo "  sudoers syntax check FAILED; removing." 1>&2; sudo rm -f "$NET_SUDOERS"; return 1; }
 echo "  Installed. Next runs won't ask for a password." 1>&2
}

# net_taps_down: best-effort removal of every tap we created (ignore errors, e.g. a rule
# not yet present). Iterates CREATED_TAPS so -X and -A taps are both cleaned up.
function net_taps_down {
 local ipbin tap; ipbin=$(command -v ip)
 for tap in "${CREATED_TAPS[@]}"; do
   sudo -n "$ipbin" link del "$tap" 2>/dev/null || true
 done
}

# net_tap_up TAP HOSTIP: create TAP, give it HOSTIP/NET_PREFIX and bring it up
# (non-interactive; provisions the sudoers rule on first failure). Records TAP in
# CREATED_TAPS so cleanup tears it down. Several taps can coexist (-X eth42 + -A eth0).
function net_tap_up {
 local tap="$1" hostip="$2"
 local ipbin u; ipbin=$(command -v ip); u=$(id -un)
 sudo -n "$ipbin" link del "$tap" 2>/dev/null || true   # drop a stale tap of the same name
 if ! sudo -n "$ipbin" tuntap add dev "$tap" mode tap user "$u" 2>/dev/null; then
   ensure_net_sudoers || return 1
   sudo -n "$ipbin" tuntap add dev "$tap" mode tap user "$u" || return 1
 fi
 CREATED_TAPS+=("$tap")
 sudo -n "$ipbin" addr add "$hostip/$NET_PREFIX" dev "$tap" 2>/dev/null || true
 sudo -n "$ipbin" link set "$tap" up || return 1
}

# ensure_ssh_key: generate the tester's own ssh key pair if missing (no passphrase).
function ensure_ssh_key {
 [[ -f $NET_SSH_KEY && -f ${NET_SSH_KEY}.pub ]] && return 0
 ssh-keygen -t ed25519 -N '' -C "pupisto.tester" -f "$NET_SSH_KEY" >/dev/null || return 1
 chmod 600 "$NET_SSH_KEY"
}

# hostfs_write DIR: write the guest hostfs -- boot_parameters plus the sourced
# marionnet-relay* extension files -- for the requested mode(s). -X (eth42, ghostified,
# X11), -A (eth0, root namespace) and -S (sshd on eth0) compose: eth42 and eth0 then
# coexist on two separate taps/subnets. Values come from the X11_*/ETH0_* globals set
# during setup.
function hostfs_write {
 local dir="$1"
 { echo "hostname='$UMID'"
   echo "virtual_disk='$IMAGE'"
   if [[ $AUTO_NET = y ]]; then
     # -A (also implied by -S): a plain lab interface eth0 (never ghostified), configured
     # by the relay's standard per-interface loop (ethernet_interfaces_no + ipv4_*_eth0).
     echo "ethernet_interfaces_no=1"
     echo "ipv4_address_eth0='$ETH0_GUEST_IP'"
     echo "ipv4_netmask_eth0='255.255.0.0'"
   fi
   if [[ $DISPLAY_MODE = y ]]; then
     # -X: setting ip42 makes the Debian 13 native relay ghostify eth42 into the hidden
     # `marionnet-mgmt' netns and start the X11 socat relay towards host_display_ip.
     echo "ip42='$X11_GUEST_IP'"
     echo "host_display_ip='$X11_HOST_IP'"
   fi
 } > "$dir/boot_parameters"
 # -S: authorize the tester key and start sshd (sourced by the relay in its bash context).
 if [[ $SSH_ONLY = y ]]; then
   cp "${NET_SSH_KEY}.pub" "$dir/id_rsa_marionnet.pub"
   cat > "$dir/marionnet-relay-ssh" <<'EOF'
# Sourced by marionnet-relay at boot (glob /mnt/hostfs/marionnet-relay*), in its
# bash context. Authorize the tester's key for root and start sshd on the bare guest.
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat /mnt/hostfs/id_rsa_marionnet.pub > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A >/dev/null 2>&1
systemctl start ssh 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
EOF
 fi
 # -X: architecture C is NATIVE to the Debian 13 relay, so we only add a READ-ONLY
 # diagnostic patch (sourced AFTER ghostification) that logs the resulting state to the
 # hostfs, so the host can check it without ssh.
 if [[ $DISPLAY_MODE = y ]]; then
   cat > "$dir/marionnet-relay-x11check" <<'EOF'
# Sourced by marionnet-relay at boot (glob /mnt/hostfs/marionnet-relay*), AFTER it has
# ghostified eth42 and started the X11 relay: architecture C is NATIVE to this Debian
# 13 relay, so here we only OBSERVE the result and log it to the hostfs.
{ echo "=== marionnet-x11 guest state (native relay) ==="
  echo "-- root netns links (eth42 must be ABSENT, ghostified):"; ip -br link
  echo "-- mgmt netns links (eth42 must be PRESENT):"; ip -n marionnet-mgmt -br link 2>&1
  echo "-- x11 relay unit: $(systemctl is-active marionnet-x11-relay 2>/dev/null || echo n/a)"
  echo "-- guest display socket:"; ls -l /tmp/.X11-unix/ 2>/dev/null
  echo "-- ethghost present? $(command -v ethghost || echo no)"
} > /mnt/hostfs/x11-setup.log 2>&1
EOF
 fi
}

# wait_for_guest_ssh: poll until the guest answers ssh (or give up after ~60s).
function wait_for_guest_ssh {
 local i
 for ((i=0; i<60; i++)); do
   ssh -i "$NET_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       -o ConnectTimeout=2 -o BatchMode=yes root@"$ETH0_GUEST_IP" true 2>/dev/null && return 0
   sleep 1
 done
 return 1
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

# Network setup for -X (X11 over eth42) and/or -A (plain eth0; -S adds sshd on it). The
# two links can COEXIST: eth42 is ghostified by the native relay into the hidden
# `marionnet-mgmt' netns for X11, while eth0 stays in the root namespace -- two separate
# taps on two 172.23.K.0/24 subnets, described in a single hostfs. X11 multiplexes
# natively over eth42 (`xeyes & wireshark' just work on the host X server). Order matters:
# each tap is created before the next free octet is picked (net_free_octet reads live
# interfaces).
X11_TAP= ; X11_HOST_IP= ; X11_GUEST_IP=
ETH0_TAP= ; ETH0_HOST_IP= ; ETH0_GUEST_IP=
HOST_X_SOCKET=

# Preflight (host tools / option clashes), before creating anything:
if [[ $DISPLAY_MODE = y ]]; then
  command -v socat >/dev/null || { echo "Error: 'socat' not found on the host." 1>&2; exit 4; }
  [[ $HEADLESS = n ]] && { command -v xterm >/dev/null || { echo "Error: 'xterm' not found on the host." 1>&2; exit 4; }; }
fi
if [[ $SSH_ONLY = y ]]; then
  [[ $HEADLESS = y ]]     && { echo "Error: -S is incompatible with --headless." 1>&2; exit 1; }
  [[ $DISPLAY_MODE = y ]] && { echo "Error: -S is incompatible with -X." 1>&2; exit 1; }
  ensure_ssh_key || { echo "Error: could not generate the tester ssh key." 1>&2; exit 5; }
fi
if [[ $CONSOLE = y ]]; then
  # -c is one boot mode among {-X, -H, -S}: they drive the console differently.
  [[ $DISPLAY_MODE = y ]] && { echo "Error: -c is incompatible with -X." 1>&2; exit 1; }
  [[ $HEADLESS = y ]]     && { echo "Error: -c is incompatible with --headless." 1>&2; exit 1; }
  [[ $SSH_ONLY = y ]]     && { echo "Error: -c is incompatible with -S." 1>&2; exit 1; }
fi

# -X: service tap on eth42 (ghostified guest-side). Create the tap first, so the eth0 octet
# below is guaranteed distinct.
if [[ $DISPLAY_MODE = y ]]; then
  K=$(net_free_octet) || { echo "Error: no free ${NET_BASE}.K.0/24 subnet (1..254 all taken)." 1>&2; exit 5; }
  X11_TAP="${NET_TAP_PREFIX}${K}"; X11_HOST_IP="${NET_BASE}.${K}.254"; X11_GUEST_IP="${NET_BASE}.${K}.1"
  UMID="tester-${K}"
  net_tap_up "$X11_TAP" "$X11_HOST_IP" || { echo "Error: could not set up the tap '$X11_TAP'." 1>&2; exit 5; }
  KOPTS="$KOPTS eth42=tuntap,$X11_TAP"
fi

# -A (also implied by -S): plain tap on eth0 (root namespace). Its octet also names the
# guest (tester-K); -S later starts sshd on it.
if [[ $AUTO_NET = y ]]; then
  K=$(net_free_octet) || { echo "Error: no free ${NET_BASE}.K.0/24 subnet (1..254 all taken)." 1>&2; exit 5; }
  ETH0_TAP="${NET_TAP_PREFIX}${K}"; ETH0_HOST_IP="${NET_BASE}.${K}.254"; ETH0_GUEST_IP="${NET_BASE}.${K}.1"
  UMID="tester-${K}"
  net_tap_up "$ETH0_TAP" "$ETH0_HOST_IP" || { echo "Error: could not set up the tap '$ETH0_TAP'." 1>&2; exit 5; }
  KOPTS="$KOPTS eth0=tuntap,$ETH0_TAP"
fi

# One hostfs describing whichever interface(s) were set up:
if [[ $DISPLAY_MODE = y || $AUTO_NET = y ]]; then
  HOSTFS_DIR=$(mktemp -d /tmp/pupisto.tester.hostfs.XXXXXX)
  hostfs_write "$HOSTFS_DIR" || exit 5
  KOPTS="$KOPTS hostfs=$HOSTFS_DIR"
fi

# -X host-side X bridge: TCP <X11_HOST_IP>:6000 -> the real X server's Unix socket
# (defeating `-nolisten tcp') + local-client authorization, when a local X server is
# reachable. In --headless with no DISPLAY we skip it and validate only the guest
# mechanism (ghostification + relay unit + display socket) via the hostfs.
if [[ $DISPLAY_MODE = y ]]; then
  if [[ -n $DISPLAY ]]; then
    X_HOST_PART=${DISPLAY%%:*}
    if [[ -n $X_HOST_PART && $X_HOST_PART != localhost ]]; then
      echo "Error: -X supports only a LOCAL X server; DISPLAY='$DISPLAY' looks remote." 1>&2; exit 4
    fi
    X_HOST_DNUM=${DISPLAY##*:}; X_HOST_DNUM=${X_HOST_DNUM%%.*}
    HOST_X_SOCKET="/tmp/.X11-unix/X${X_HOST_DNUM}"
  fi
  if [[ -S $HOST_X_SOCKET ]] && command -v xhost >/dev/null; then
    socat TCP-LISTEN:6000,bind="$X11_HOST_IP",reuseaddr,fork UNIX-CONNECT:"$HOST_X_SOCKET" &
    XSOCAT_PID=$!
    xhost +local: >/dev/null 2>&1 && X_HOST_ADDED=y || true
  elif [[ $HEADLESS = n ]]; then
    echo "Error: -X needs a local X server (DISPLAY set, its socket, and xhost)." 1>&2; exit 4
  else
    echo "Note: no local X bridge (DISPLAY unset) -- validating the guest mechanism only." 1>&2
  fi
fi

# Root filesystem: a throw-away COW layer keeps the image intact.
if [[ $USE_COW = y ]]; then
  COWFILE=$(mktemp /tmp/pupisto.tester.XXXXXXX.cow); rm -f "$COWFILE" # UML creates it
  UBDA="$COWFILE,$IMAGE"
else
  UBDA="$IMAGE"
fi

# Common UML kernel command line (kernel + arguments). No swap device: the systemd
# rootfs marks its fstab swap entry `nofail', so a missing swap no longer stalls.
CMDLINE="$KERNEL keyboard_layout=us ubda=$UBDA umid=$UMID mem=$MEM root=98:0 hostname=$UMID guestkind=machine $KOPTS $EXTRA"

# Recap:
echo "=============================================================="
echo " pupisto.tester -- boot-test ($([[ $SSH_ONLY = y ]] && echo ssh-only || { [[ $CONSOLE = y ]] && echo console || { [[ $HEADLESS = y ]] && echo headless || echo xterm; }; }))"
echo "   image        : $IMAGE"
echo "   kernel       : $KERNEL"
echo "   init system  : $INIT_SYSTEM  (from ${CONF##*/})"
echo "   kernel series: ${KSERIES:-<unknown>}"
echo "   boot quirks  : ${QUIRK_KEY} -> ${KOPTS:-<none>}"
echo "   memory       : $MEM"
echo "   console=tty0 : $([[ $KOPTS = *console=tty0* ]] && echo yes || echo no)"
echo "   network      : $([[ -n $TAP ]] && echo "eth0=tuntap,$TAP" || echo none)"
echo "   X11 display  : $([[ $DISPLAY_MODE = y ]] && echo "on -- eth42 ghostified in netns; guest :0 -> host ${HOST_X_SOCKET} via ${X11_HOST_IP}:6000" || echo off)"
echo "   auto-network : $([[ $AUTO_NET = y ]] && echo "eth0=tuntap,$ETH0_TAP  host $ETH0_HOST_IP/$NET_PREFIX  guest $ETH0_GUEST_IP" || echo off)"
echo "   ssh-only     : $([[ $SSH_ONLY = y ]] && echo "on  (background boot; ssh root@$ETH0_GUEST_IP once up)" || echo off)"
echo "   COW          : $([[ $USE_COW = y ]] && echo "yes (image kept intact)" || echo "NO -- writing into the image!")"
[[ $HEADLESS = y ]] && echo "   timeout      : ${TIMEOUT}s"
echo "=============================================================="

if [[ $DISPLAY_MODE = y && $HEADLESS = n ]]; then
  echo "X11 (architecture C) -- guest side done by the NATIVE relay (eth42 ghostified + relay started)."
  echo "  After login (root/root) in the xterm, just:"
  echo "    export DISPLAY=:0"
  echo "    xeyes                 # then: wireshark ; xeyes & wireshark (native multiplexing)"
  echo "  Check the ghostification:  ip a     # eth42 must NOT appear"
  echo "  Guest setup log (host side): ${HOSTFS_DIR}/x11-setup.log"
  echo "  If xeyes says \"Can't open display\", widen host auth: xhost +  (revert: xhost -)"
  echo "=============================================================="
fi

if [[ $DRY_RUN = y ]]; then echo "(dry-run: not booting)"; exit 0; fi

# Boot.  Three exclusive launch modes: -S (background, ssh only), --headless (timeout,
# console on stdout), or the default xterm (interactive console; also covers -A and -X).
if [[ $SSH_ONLY = y ]]; then
  # Background run (no xterm, no timeout, stdin closed): the guest console goes to stdout
  # only as a boot log -- it is NOT a login (getty on con0 reads EOF from /dev/null). The
  # guest is driven by ssh; the tap/hostfs are torn down by `cleanup' on exit.
  echo "+ (ssh-only) $CMDLINE con=null con0=fd:0,fd:1"
  $CMDLINE con=null con0=fd:0,fd:1 </dev/null &
  UML_PID=$!
  echo "guest booting (pid $UML_PID); waiting for ssh on $ETH0_GUEST_IP ..."
  if wait_for_guest_ssh; then
    echo "=============================================================="
    echo "READY: ssh -i $NET_SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ETH0_GUEST_IP"
    echo "  stop: Ctrl-C or kill $UML_PID  (taps torn down on exit)"
    echo "=============================================================="
  else
    echo "WARNING: ssh not reachable after ~60s; guest still running (pid $UML_PID). See console above." 1>&2
  fi
  wait "$UML_PID"
elif [[ $CONSOLE = y ]]; then
  # Interactive console on the current terminal (no xterm, no timeout): stdin stays open
  # so getty on con0 gives a real login prompt (root/root). Foreground: the script blocks
  # until the guest halts, then `cleanup' tears down the COW/tap/hostfs.
  # Known UML quirk: the `fd' console channel (con0=fd:0,fd:1) drives a sizeless terminal
  # with no line discipline of its own, so the display lags one line behind (the prompt
  # appears only after ENTER). Login is correct; the CPR/ESC[6n pollution is fixed upstream
  # by TTYColumns/TTYRows on getty@tty0 (baked into pupisto.debian.sh). For a fluid
  # interactive console use -X (xterm allocates a real pty with a proper winsize).
  echo "+ (console) $CMDLINE con=null con0=fd:0,fd:1"
  $CMDLINE con=null con0=fd:0,fd:1
elif [[ $HEADLESS = y ]]; then
  # Console on stdout, all other consoles/serials to null; stdin closed; killed
  # after $TIMEOUT. `timeout' returns 124 on expiry -- expected, not an error here.
  echo "+ (headless, ${TIMEOUT}s) $CMDLINE con=null con0=fd:0,fd:1"
  set +e
  timeout --foreground -s KILL "$TIMEOUT" \
    $CMDLINE con=null con0=fd:0,fd:1 </dev/null
  RC=$?
  set -e
  [[ $RC = 137 || $RC = 124 ]] && echo "(guest killed after ${TIMEOUT}s timeout -- expected)"
  if [[ $DISPLAY_MODE = y && -f $HOSTFS_DIR/x11-setup.log ]]; then
    echo "--- guest X11 state (architecture C, from hostfs) ---"
    cat "$HOSTFS_DIR/x11-setup.log"
    echo "-----------------------------------------------------"
  fi
else
  GDB=
  [[ $DEBUG = y ]] && GDB='gdb -ex "handle SIGSEGV nostop noprint" -ex "handle SIGUSR1 nopass stop print" -ex run --args '
  xterm -l -sb -T "$UMID" -e "${GDB}${CMDLINE}"
  echo "fuser -k:"; fuser -k "$IMAGE" 2>/dev/null || true
fi
