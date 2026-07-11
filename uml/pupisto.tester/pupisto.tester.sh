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
# --- auto-network (-A): host<->guest service tap on eth42 + sshd, like Marionnet ---
# Each -A instance gets a FREE octet K (1..254) so several images can run at once:
# it keys the tap name, the umid/mconsole, and a private 172.23.K.0/24 subnet.
NET_BASE="172.23"             # /16 space; each instance carves out a 172.23.K.0/24
NET_PREFIX="24"               # host tap prefix (guest eth42 stays /16 -- marionnet-relay)
NET_TAP_PREFIX="mnt-tap"      # tap name prefix; must match the sudoers rule (mnt-tap*)
NET_SSH_KEY="$SCRIPT_DIR/tester_key"   # tester's own ssh key (generated on first use, gitignored)
NET_SUDOERS="/etc/sudoers.d/marionnet-tester"        # NOPASSWD rule for the tap commands
# Per-instance values, filled in from the free octet K when -A is used:
NET_TAP= ; NET_HOST_IP= ; NET_GUEST_IP=

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
OPTSTRING="hi:k:m:wn:dTNHt:x:XA"

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
    --auto-network-by-eth42) ARGS+=("-A");;
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
  -X/--display       show guest graphical apps (xeyes, wireshark) on the host X server:
                     eth42 service tap, GHOSTIFIED in the guest by its NATIVE relay via a
                     network namespace (student's \`ip a' hides it), X11 relayed over it.
                     xterm mode; with --headless, only the guest mechanism is set up and
                     checked from the hostfs (no local X server needed).
  -A/--auto-network-by-eth42
                     boot with a host<->guest tap on eth42 + sshd, then print a ready
                     ssh command (root@${NET_GUEST_IP}). Runs the guest attached (console
                     to stdout, no timeout); Ctrl-C / killing it tears the tap down.
                     First use provisions a NOPASSWD sudoers rule (asks for a password once).
  -d/--debug         run the kernel under gdb (xterm mode only)
  -N/--dry-run       resolve image/kernel/args and print them, but do NOT boot
  -h/--help          this help

Examples:
  ${0##*/}                    # xterm, last image, systemd + console=tty0, COW
  ${0##*/} --headless         # scriptable boot captured on stdout (fix/retry loop)
  ${0##*/} --headless --no-tty0   # same, without console=tty0 (compare getty)
  ${0##*/} -X                 # xterm + guest X11 on the host (eth42 ghostified via netns)"
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
DISPLAY_MODE=n ; [[ -n $option_X ]] && DISPLAY_MODE=y
AUTO_NET=n  ; [[ -n $option_A ]] && AUTO_NET=y
UMID="$DEFAULT_UMID"   # overridden to tester-<K> in -A mode (unique mconsole per instance)

# Throw-away COW file (and X11 socat/pty, auto-network tap/hostfs, if any) to clean up on exit:
COWFILE=
XSOCAT_PID=
X_HOST_ADDED=n
HOSTFS_DIR=
UML_PID=
AUTO_NET_ON=n
function cleanup {
  [[ -n $UML_PID ]] && kill "$UML_PID" 2>/dev/null
  rm -f "$COWFILE"
  [[ -n $XSOCAT_PID ]] && kill "$XSOCAT_PID" 2>/dev/null
  [[ $X_HOST_ADDED = y ]] && xhost -local: >/dev/null 2>&1
  [[ $AUTO_NET_ON = y ]] && net_tap_down
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

# Reproduce Marionnet's service interface: a host<->guest `tap' carrying eth42.
# The host end is 172.23.0.254/16, the guest eth42 is 172.23.0.1/16 (set by
# marionnet-relay from ip42 in boot_parameters). We inject the tester's public key
# and start sshd via marionnet-relay's extension mechanism (it sources every
# /mnt/hostfs/marionnet-relay* at boot). Tap creation needs root: the first run
# provisions a NOPASSWD sudoers rule scoped to the `mnt-tap*' tap commands, so
# later runs are non-interactive (autonomous).

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
# Installed by pupisto.tester.sh (--auto-network-by-eth42). Scope: mnt-tap* only.
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

# net_tap_down: best-effort removal of our tap (ignore errors, e.g. rule not yet there).
function net_tap_down {
 local ipbin; ipbin=$(command -v ip)
 sudo -n "$ipbin" link del "$NET_TAP" 2>/dev/null || true
}

# net_tap_up: create the tap and bring it up (non-interactive; provisions on first fail).
function net_tap_up {
 local ipbin u; ipbin=$(command -v ip); u=$(id -un)
 net_tap_down
 if ! sudo -n "$ipbin" tuntap add dev "$NET_TAP" mode tap user "$u" 2>/dev/null; then
   ensure_net_sudoers || return 1
   sudo -n "$ipbin" tuntap add dev "$NET_TAP" mode tap user "$u" || return 1
 fi
 sudo -n "$ipbin" addr add "$NET_HOST_IP/$NET_PREFIX" dev "$NET_TAP" 2>/dev/null || true
 sudo -n "$ipbin" link set "$NET_TAP" up || return 1
}

# ensure_ssh_key: generate the tester's own ssh key pair if missing (no passphrase).
function ensure_ssh_key {
 [[ -f $NET_SSH_KEY && -f ${NET_SSH_KEY}.pub ]] && return 0
 ssh-keygen -t ed25519 -N '' -C "pupisto.tester" -f "$NET_SSH_KEY" >/dev/null || return 1
 chmod 600 "$NET_SSH_KEY"
}

# make_ssh_hostfs DIR: populate a hostfs dir with boot_parameters (=> marionnet-relay
# configures eth42) and a sourced relay patch that authorizes our key and starts sshd.
function make_ssh_hostfs {
 local dir="$1" pub="${NET_SSH_KEY}.pub"
 [[ -r $pub ]] || { echo "Error: ssh public key '$pub' not found." 1>&2; return 1; }
 { echo "ip42='$NET_GUEST_IP'"
   echo "hostname='$UMID'"
   echo "virtual_disk='$IMAGE'"
 } > "$dir/boot_parameters"
 cp "$pub" "$dir/id_rsa_marionnet.pub"
 cat > "$dir/marionnet-relay-ssh" <<'EOF'
# Sourced by marionnet-relay at boot (glob /mnt/hostfs/marionnet-relay*), in its
# bash context. Authorize the tester's key for root and start sshd on the bare guest.
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat /mnt/hostfs/id_rsa_marionnet.pub > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A >/dev/null 2>&1
systemctl start ssh 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
EOF
}

# make_x11_hostfs DIR: populate a hostfs dir so the guest's NATIVE marionnet-relay
# (Debian 13, architecture C) performs the X11 setup itself. We provide only (1)
# boot_parameters with host_display_ip -- so the relay ghostifies eth42 into the
# `marionnet-mgmt' netns and starts the X11 socat relay towards the host bridge -- and
# (2) a READ-ONLY diagnostic patch, sourced by the relay AFTER its ghostification (it
# matches the /mnt/hostfs/marionnet-relay* glob), that logs the resulting state to the
# hostfs so the host can check it without ssh (eth42's move into the netns would cut an
# eth42 ssh anyway). We do NOT ghostify here: that now belongs to the guest relay.
function make_x11_hostfs {
 local dir="$1"
 { echo "ip42='$NET_GUEST_IP'"
   echo "hostname='$UMID'"
   echo "virtual_disk='$IMAGE'"
   echo "host_display_ip='$NET_HOST_IP'"
 } > "$dir/boot_parameters"
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
}

# wait_for_guest_ssh: poll until the guest answers ssh (or give up after ~60s).
function wait_for_guest_ssh {
 local i
 for ((i=0; i<60; i++)); do
   ssh -i "$NET_SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       -o ConnectTimeout=2 -o BatchMode=yes root@"$NET_GUEST_IP" true 2>/dev/null && return 0
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

# X11 forwarding to the host X server (architecture C) -- driven by the guest's NATIVE
# marionnet-relay (Debian 13): the relay ghostifies eth42 into a hidden network
# namespace (the student's `ip a' never lists it) and relays the guest display :0 (a
# pathname Unix socket, visible across namespaces) over eth42 to the host. This tester
# only provides the HOST side: a service tap on eth42, boot_parameters telling the relay
# the host endpoint (host_display_ip), and -- when a local X server is available -- a
# bridge from TCP <NET_HOST_IP>:6000 to the real X server's Unix socket (defeating
# `-nolisten tcp') plus local-client authorization. X11 multiplexes natively over the
# tap: `xeyes & wireshark' just works. With --headless the guest mechanism is exercised
# and checked from the hostfs (make_x11_hostfs) without needing a local X server.
HOST_X_SOCKET=
if [[ $DISPLAY_MODE = y ]]; then
  [[ $AUTO_NET = y ]] && { echo "Error: -X is incompatible with -A." 1>&2; exit 1; }
  command -v socat >/dev/null || { echo "Error: 'socat' not found on the host." 1>&2; exit 4; }
  [[ $HEADLESS = n ]] && { command -v xterm >/dev/null || { echo "Error: 'xterm' not found on the host." 1>&2; exit 4; }; }
  # Service tap on eth42 (same free-octet plumbing as -A):
  K=$(net_free_octet) || { echo "Error: no free ${NET_BASE}.K.0/24 subnet (1..254 all taken)." 1>&2; exit 5; }
  NET_TAP="${NET_TAP_PREFIX}${K}"; NET_HOST_IP="${NET_BASE}.${K}.254"; NET_GUEST_IP="${NET_BASE}.${K}.1"
  UMID="tester-${K}"; AUTO_NET_ON=y
  net_tap_up || { echo "Error: could not set up the tap '$NET_TAP'." 1>&2; exit 5; }
  HOSTFS_DIR=$(mktemp -d /tmp/pupisto.tester.hostfs.XXXXXX)
  make_x11_hostfs "$HOSTFS_DIR" || exit 5
  KOPTS="$KOPTS eth42=tuntap,$NET_TAP hostfs=$HOSTFS_DIR"
  # Host-side X bridge (guest reaches <NET_HOST_IP>:6000 over eth42) + local auth, when a
  # local X server is reachable. In --headless with no DISPLAY we skip it and validate
  # only the guest mechanism (ghostification + relay unit + display socket) via hostfs.
  if [[ -n $DISPLAY ]]; then
    X_HOST_PART=${DISPLAY%%:*}
    if [[ -n $X_HOST_PART && $X_HOST_PART != localhost ]]; then
      echo "Error: -X supports only a LOCAL X server; DISPLAY='$DISPLAY' looks remote." 1>&2; exit 4
    fi
    X_HOST_DNUM=${DISPLAY##*:}; X_HOST_DNUM=${X_HOST_DNUM%%.*}
    HOST_X_SOCKET="/tmp/.X11-unix/X${X_HOST_DNUM}"
  fi
  if [[ -S $HOST_X_SOCKET ]] && command -v xhost >/dev/null; then
    socat TCP-LISTEN:6000,bind="$NET_HOST_IP",reuseaddr,fork UNIX-CONNECT:"$HOST_X_SOCKET" &
    XSOCAT_PID=$!
    xhost +local: >/dev/null 2>&1 && X_HOST_ADDED=y || true
  elif [[ $HEADLESS = n ]]; then
    echo "Error: -X (xterm) needs a local X server (DISPLAY set, its socket, and xhost)." 1>&2; exit 4
  else
    echo "Note: no local X bridge (DISPLAY unset) -- validating the guest mechanism only." 1>&2
  fi
fi

# Auto-network (-A): host<->guest tap on eth42 + sshd, for autonomous ssh tests.
if [[ $AUTO_NET = y ]]; then
  [[ $HEADLESS = y ]]    && { echo "Error: -A is incompatible with --headless." 1>&2; exit 1; }
  [[ $DISPLAY_MODE = y ]] && { echo "Error: -A is incompatible with -X for now." 1>&2; exit 1; }
  # Pick a free octet K => unique tap, umid/mconsole and 172.23.K.0/24 subnet.
  K=$(net_free_octet) || { echo "Error: no free ${NET_BASE}.K.0/24 subnet (1..254 all taken)." 1>&2; exit 5; }
  NET_TAP="${NET_TAP_PREFIX}${K}"
  NET_HOST_IP="${NET_BASE}.${K}.254"
  NET_GUEST_IP="${NET_BASE}.${K}.1"
  UMID="tester-${K}"
  AUTO_NET_ON=y
  ensure_ssh_key || { echo "Error: could not generate the tester ssh key." 1>&2; exit 5; }
  net_tap_up || { echo "Error: could not set up the tap '$NET_TAP'." 1>&2; exit 5; }
  HOSTFS_DIR=$(mktemp -d /tmp/pupisto.tester.hostfs.XXXXXX)
  make_ssh_hostfs "$HOSTFS_DIR" || exit 5
  KOPTS="$KOPTS eth42=tuntap,$NET_TAP hostfs=$HOSTFS_DIR"
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
echo " pupisto.tester -- boot-test ($([[ $HEADLESS = y ]] && echo headless || echo xterm))"
echo "   image        : $IMAGE"
echo "   kernel       : $KERNEL"
echo "   init system  : $INIT_SYSTEM  (from ${CONF##*/})"
echo "   kernel series: ${KSERIES:-<unknown>}"
echo "   boot quirks  : ${QUIRK_KEY} -> ${KOPTS:-<none>}"
echo "   memory       : $MEM"
echo "   console=tty0 : $([[ $KOPTS = *console=tty0* ]] && echo yes || echo no)"
echo "   network      : $([[ -n $TAP ]] && echo "eth0=tuntap,$TAP" || echo none)"
echo "   X11 display  : $([[ $DISPLAY_MODE = y ]] && echo "on -- eth42 ghostified in netns; guest :0 -> host ${HOST_X_SOCKET} via ${NET_HOST_IP}:6000" || echo off)"
echo "   auto-network : $([[ $AUTO_NET = y ]] && echo "eth42=tuntap,$NET_TAP  host $NET_HOST_IP/$NET_PREFIX  guest $NET_GUEST_IP  (ssh root@$NET_GUEST_IP)" || echo off)"
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

# Boot.
if [[ $AUTO_NET = y ]]; then
  # Attached run (no xterm, no timeout): guest console to stdout, guest kept alive so
  # the caller can ssh into it; the tap/hostfs are torn down by `cleanup' on exit.
  echo "+ (auto-network) $CMDLINE con=null con0=fd:0,fd:1"
  $CMDLINE con=null con0=fd:0,fd:1 </dev/null &
  UML_PID=$!
  echo "guest booting (pid $UML_PID); waiting for ssh on $NET_GUEST_IP ..."
  if wait_for_guest_ssh; then
    echo "=============================================================="
    echo "READY: ssh -i $NET_SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$NET_GUEST_IP"
    echo "  stop: Ctrl-C or kill $UML_PID  (tap $NET_TAP torn down on exit)"
    echo "=============================================================="
  else
    echo "WARNING: ssh not reachable after ~60s; guest still running (pid $UML_PID). See console above." 1>&2
  fi
  wait "$UML_PID"
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
