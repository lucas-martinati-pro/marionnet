#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2013  Jean vincent Loddo
# Copyright (C) 2013  Antoine Seignard
# Copyright (C) 2013  Université Paris 13

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

# This script helps people to build a debian filesystem
# with debootstrap according to the Marionnet requirements.

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
  COLUMNS=$(tput cols)
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
#                      CMDLINE PARSING
# =============================================================

# Getopt's format used to parse the command line:
OPTSTRING="hmc:Kk:dn:s:r:t:a:L"

function parse_cmdline {
local i j flag
# Transform long format options into the short one:
for i in "$@"; do
  if [[ double_dash_found = 1 ]]; then
    ARGS+=("$i")
  else case "$i" in
    --help)
      ARGS+=("-h");
      ;;
    --custom)
      ARGS+=("-m");
     ;;
    --continue)
      ARGS+=("-c");
     ;;
    --name)
      ARGS+=("-n");
     ;;
    --arch)
      ARGS+=("-a");
     ;;
    --kernel)
      ARGS+=("-k");
     ;;
    --no-kernel)
      ARGS+=("-K");
     ;;
    --debug)
      ARGS+=("-d");
     ;;
    --release)
      ARGS+=("-r");
     ;;
    --server)
      ARGS+=("-s");
     ;;
    --fstype)
      ARGS+=("-t");
     ;;
    --no-locales)
      ARGS+=("-L");
     ;;
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

# Warning: the following two branches could not be grouped
# into the single command (`else' branch):
# set - "${ARGS[@]}";
# The behaviour is not the same when the array is empty!
if [[ ${#ARGS[@]} -eq 0 ]]; then
  set - "";
else
  set - "${ARGS[@]}";
fi
unset ARGS

function print_usage_and_exit {
 # global DEFAULT_KERNEL_VERSION  DEFAULT_FSTYPE
 echo "Usage: ${0##*/} [OPTIONS]
Build a debian filesystem suitable for Marionnet.

NOT IMPLEMENTED YET --------
If one or both files \`_build.custom_packages_{yes,no}' exist in the current
directory, their uncommented lines tell the script which Debian's packages
are wanted (yes) or unwanted (no). The list of selected packages results from
the formula:

    (required DIFF no) UNION yes

where \`required' are the few packages considered relevant by Marionnet's
developpers for pedagogical reasons.
----------------------------

Options:
  -r/--release RELEASE  set the release by name (default or \"${DEFAULT_RELEASE}\")
  -a/--arch ARCH        set the architecture i386 or amd64 (default \"${DEFAULT_ARCH}\")
  -t/--fstype TYPE      set the filesystem type (default \"${DEFAULT_FSTYPE}\")
  -m/--custom           customize the package selection interactively
  -k/--kernel VERSION   set the kernel version (default ${DEFAULT_KERNEL_VERSION})
  -K/--no-kernel        do not compile the kernel
  -c/--continue DIR     continue a previously broken execution in directory DIR
  -s/--server URL       set the HTTP/DIR Debian server
  -L/--no-locales       don't install \"locales\" and purge *.mo files
  -h/--help             Print this message and exit
---
Defaults:
  --release \"${DEFAULT_RELEASE}\"
  --arch ${DEFAULT_ARCH}
  --kernel ${DEFAULT_KERNEL_VERSION}
  --fstype ${DEFAULT_FSTYPE}
  --server \"${DEFAULT_SERVER}\"

Notes
  - If the kernel is compiled (you can disable it with -K) it will
    compiled outside the Debian filesystem.
  - We suggest to add a line like
    'Defaults timestamp_timeout=60'
    in your /etc/sudoers, to prevent the script to ask the sudo
    password several times

Examples:
$ ${0##*/} -r ${DEFAULT_RELEASE}
$ ${0##*/} -k ${DEFAULT_KERNEL_VERSION} --custom -t ${DEFAULT_FSTYPE} -r ${DEFAULT_RELEASE}"
 exit $1
}

# Defaults:

DEFAULT_RELEASE="trixie"
DEFAULT_ARCH="amd64" # previously i386
DEFAULT_SERVER="http://ftp.debian.org/debian/"

# UML kernel refresh (chantier marionnet-kernel-rootfs) : Linux 6.12.x LTS, amd64,
# construit par pupisto.kernel.sh (voie moderne : config de Dave migrée via olddefconfig).
# make_or_link_the_kernel réutilise ../pupisto.kernel/_build.linux-$KERNEL_VERSION* s'il existe,
# sinon recompile. Historiquement : 4.14.18, ou 2.6.32 (dernier noyau ghost2 statiquement lié).
DEFAULT_KERNEL_VERSION="6.12.95"

# We set this default to "ext4" in order to obtain smaller filesystems:
DEFAULT_FSTYPE="ext4"

# Manage now your options in a convenient order
#
# Option -h
if [[ -n ${option_h}  ]]; then
 print_usage_and_exit 0
fi
# Option -k --kernel
if [[ -n ${option_k} ]]; then
 KERNEL_VERSION=$option_k_arg
else
 KERNEL_VERSION=$DEFAULT_KERNEL_VERSION
fi
# Option -r --release
if [[ -n ${option_r} ]]; then
 RELEASE=$option_r_arg
else
 RELEASE=$DEFAULT_RELEASE
fi
# Init system of the target release: Debian switched to systemd in jessie (8).
# wheezy (7) is still SysV; stretch (9), trixie (13)… are systemd. This marker is
# written into the filesystem .conf (toolkit_image.sh reads $INIT_SYSTEM) and read
# back by Marionnet to pick the guest boot coordination. Filesystems built before
# this marker existed default to "sysv" on the Marionnet side.
case $RELEASE in
  squeeze|wheezy) INIT_SYSTEM="sysv" ;;
  *)              INIT_SYSTEM="systemd" ;;
esac
# Ghostification method of the service interface eth42 (the X11 transport). Legacy
# images use the kernel ghostification patch driven by the `ethghost' C tool; Debian
# 13 (vanilla 6.12 kernel) uses a hidden network namespace instead (architecture C):
# no kernel patch, no ethghost, and a distro-specific relay (marionnet-relay.trixie)
# that moves eth42 into the namespace and relays X11 over it.
case $RELEASE in
  trixie) GHOSTIFICATION="netns" ;;
  *)      GHOSTIFICATION="ethghost" ;;
esac
# Option -a --arch
if [[ -n ${option_a} ]]; then
 ARCH=$option_a_arg
else
 ARCH=$DEFAULT_ARCH
fi
# Option -t --fstype
if [[ -n ${option_t} ]]; then
 FSTYPE=$option_t_arg
else
 FSTYPE="$DEFAULT_FSTYPE"
fi
# Option -s --server
if [[ -n ${option_s} ]]; then
 HTTP_SERVER=$option_s_arg
else
 HTTP_SERVER="$DEFAULT_SERVER"
fi
# Option -d --debug
if [[ -n ${option_d} ]]; then
 DEBUGGING_MODE=y
fi
# Option -L --no-locales
if [[ -z ${option_L} ]]; then
 INSTALL_LOCALES=y
fi
# Option -c --continue
if [[ -n ${option_c} ]]; then
  if [[ -d "${option_c_arg}" ]]; then
   CONTINUE_IN_DIRECTORY="${option_c_arg}"
   CONTINUE=yes
  else
   echo "Error: ${option_c_arg} doesn't exist or is not a directory."
   echo "Exiting."
   exit 1
  fi
fi

# TODO:
if [[ ! $RELEASE = "wheezy" && ! $RELEASE = "stretch" && ! $RELEASE = "trixie" ]]; then
  echo "Sorry, currently only \`wheezy', \`stretch' and \`trixie' are supported by this script. Exiting."
  exit 1
fi

# =============================================================
#                    DEBUGGING SETUP
# =============================================================

# Source anyway, in order to able to freely leave break-points in the code.
# Defined functions:
#   ___break_point___
#   set_tracing
#   unset_tracing
#   set_debugging
#   unset_debugging
#   set_once_actions_file
#   once
# Referred global:
#  DEBUGGING_MODE
source ../pupisto.common/toolkit_debugging.sh

# In order to enrich the log:
set_tracing

# =============================================================
#                   GENERAL SETUP
# =============================================================

source ../pupisto.common/toolkit_config_files.sh
# Exported functions available now:
#   tabular_file_update
#   user_config_set
#   set_default_config_file
#   set_default_config_field_separator
#   set_config_variable
#   unset_config_variable
#   get_config_variable
#   get_config_variable_unquoting
# Examples:
# tabular_file_update -d ":" -k 1 --key-value "root" -f 7 --field-value "/bin/bash" --field-old-value "/bin/sh" etc/passwd
# user_config_set "PermitRootLogin" " " "yes" etc/sshd_config

source ../pupisto.common/toolkit_chroot.sh
# Defined functions:
# mkTMPFILE
# list_diff
# rewrite
# save_files
# restore_files
# sudo_fcall
# careful_chroot
# sudo_careful_chroot
# copy_content_into_directory
# sudo_chroot_binary_list
# sudo_fprintf

source ../pupisto.common/toolkit_image.sh
# Defined functions:
# rename_with_sum_and_make_image_dot_conf

# Vendored bashbricks (Map_*, Array_*, …): used by the kernel-feature check below.
source ../../bashbricks/bashbricks.sh

set -e
set -E # the ERR trap is inherited by shell functions

DISTRIBUTION_NAME=debian-$RELEASE

# Create the temporary working directory $TWDIR or continue in an already created
# directory:
if [[ -n $CONTINUE ]]; then
  TWDIR="$(basename $CONTINUE_IN_DIRECTORY)"
else
  TWDIR=_build.$DISTRIBUTION_NAME-with-linux-${KERNEL_VERSION}.$(date +%Y-%m-%d.%H\h%M)
  mkdir -v -p $TWDIR
  echo "Temporary Working directory: $TWDIR"
fi
DEBIANROOT=$TWDIR/debianroot
mkdir -v -p $DEBIANROOT
PUPISTO_DIR=$PWD

# Initialize the file registering actions to be performed once:
set_once_actions_file $TWDIR/ONCE_ACTIONS_FILE

PUPISTO_FILES=pupisto.debian.sh.files

# Unnecessary therefore essential ;-)
INSTALL_LINUXLOGO=y

# =============================================================
#                    HOST DEPENDENCIES
# =============================================================

# Host-side tools this script needs *outside* the guest chroot. For now just
# `debootstrap' (used right below to bootstrap the base system); the list is
# meant to grow as we discover other hard requirements of the build.
REQUIRED_HOST_PACKAGES="debootstrap"

# ensure_host_dependencies: make `./pupisto.debian.sh' self-sufficient when run
# directly -- the Makefile `dependencies' target only guards `make'-driven runs.
# Same logic as that target: if any required package is missing, apt-get installs it.
function ensure_host_dependencies {
 # global REQUIRED_HOST_PACKAGES
 which dpkg 1>/dev/null || {
   echo "Not a Debian system (oh my god!); please install: $REQUIRED_HOST_PACKAGES" 1>&2
   exit 1
   }
 # `dpkg -l PKG...' exits non-zero as soon as one package is unknown/not installed:
 if dpkg 1>/dev/null 2>/dev/null -l $REQUIRED_HOST_PACKAGES; then
   return 0
 fi
 echo "Installing missing host dependencies ($REQUIRED_HOST_PACKAGES)..."
 sudo apt-get install -q -q -q -y $REQUIRED_HOST_PACKAGES
}

# =============================================================
#                      DEBOOTSTRAP
# =============================================================

function launch_debootstrap_and_then_apt_get_install {
 # global DEBIAN_FRONTEND RELEASE DEBIANROOT HTTP_SERVER INSTALL_LOCALES (input)
 # global INCLUDED_PACKAGES (output)
 local ROOT=${1:-$DEBIANROOT}
 # Note: `makedev' (removed after buster) and `realpath' (absorbed by `coreutils'
 # since jessie) no longer exist as packages in modern Debian; including them would
 # break apt-get on trixie.
 # `jq' is required by the /usr/bin/wireshark wrapper (install_wireshark_marionnet_wrapper),
 # which lists UP interfaces itself since Wireshark's own poller is disabled.
 local MANDATORY_PACKAGES="tcpdump openssh-server traceroute jq"
 local SELECTION=$PUPISTO_FILES/package_catalog/package_catalog.$RELEASE.selection
 # ---
 if [[ $INSTALL_LINUXLOGO = y ]]; then
   MANDATORY_PACKAGES+=" linuxlogo"
 fi
 if [[ $INSTALL_LOCALES = y ]]; then
   MANDATORY_PACKAGES+=" locales"
 fi
 INCLUDED_PACKAGES=$( (for i in $MANDATORY_PACKAGES; do echo $i; done; awk <$SELECTION '$1 !~ /^#/ {print $1}') | sort -d | uniq)
 INCLUDED_PACKAGES=$(echo $INCLUDED_PACKAGES)

 local EXCLUDED_PACKAGES="udev"
 EXCLUDED_PACKAGES=$(echo $EXCLUDED_PACKAGES)

 # Note: without --foreign
 local INCLUDE="--include=${INCLUDED_PACKAGES// /,}" # unused in this version
 local EXCLUDE="--exclude=${EXCLUDED_PACKAGES// /,}"

 # Relevant for a non-interactive debootstrap running:
 export DEBIAN_FRONTEND=noninteractive

 # Ask sudo password once, please:
 sudo -v -p "[sudo] password for %u (required for chroot/mount actions): "

 # --- Launch debootstrap:
 if once --register-anyway sudo debootstrap --arch=${ARCH} --include="aptitude" $EXCLUDE $RELEASE ${ROOT} ${HTTP_SERVER}; then
   echo "Ok, \`debootstrap' managed the installation of the basic set of packages"
 else
   echo "Error: something goes wrong installing the basic set of packages with \`debootstrap'"
   return 1
 fi
 #---

 sudo -v # update cached credentials

 # --- Don't try to launch services (tricks found at http://askubuntu.com/q/74061, thanks!) running apt-get:
 local POLICY_RC=$ROOT/usr/sbin/policy-rc.d
 sudo_fprintf $POLICY_RC '#!/bin/sh\nexit 101\n'

 sudo chmod +x $POLICY_RC
 local DPKG_CUSTOM=$ROOT/etc/dpkg/dpkg.cfg.d/custom
 sudo_fprintf $DPKG_CUSTOM "no-triggers\n"
 # ---

 # --- Launch apt-get install:
 trap "sudo umount $ROOT/{proc,sys}" EXIT
 echo "I try now to continue the installation with \`apt-get'..."
 # Note: the legacy `--force-yes' was dropped in apt 1.1 (it would abort on trixie).
 # It used to bypass package authentication, no longer needed since APT keys are
 # honoured normally (the old `--no-check-gpg' was removed too). Add a granular
 # `--allow-*' here only if a real need shows up at build time.
 # NOT wrapped in `once': `once' swallows the exit code (it neutralises set -e),
 # so a failed apt-get (e.g. a package conflict) would be silently skipped on a
 # `-c' re-run, yielding an image MISSING its packages yet reported as "Success".
 # apt-get install is idempotent, so re-running it under `-c' is cheap and simply
 # completes the install; here a real failure must be fatal (set -e / ERR trap).
 sudo_careful_chroot ${ROOT} apt-get -y -f install $INCLUDED_PACKAGES
 trap "echo Bye." EXIT
 # ---

 # --- Mr proper:
 sudo rm -f $POLICY_RC $DPKG_CUSTOM
 #---

 return 0
}

# =============================================================
#                        TUNING
# =============================================================

function fix_apt_sources_update_and_upgrade {
 # global DEBIANROOT HTTP_SERVER RELEASE
 local ROOT=${1:-$DEBIANROOT}
 local TARGET=$ROOT/etc/apt/sources.list
 # Security suite: modern releases (bullseye+) use `<release>-security' on the
 # debian-security host; legacy releases used `<release>/updates'.
 local SECURITY_LINE
 case $RELEASE in
   trixie|bookworm|bullseye)
     SECURITY_LINE="deb http://security.debian.org/debian-security $RELEASE-security main";;
   *)
     SECURITY_LINE="deb http://security.debian.org/ $RELEASE/updates main";;
 esac
 sudo_fprintf $TARGET "%s\n%s\n" "deb $HTTP_SERVER $RELEASE main" "$SECURITY_LINE"
 # Update:
 # sudo_careful_chroot ${ROOT} aptitude update
 sudo_careful_chroot ${ROOT} apt-get update
 # Upgrade:
 # sudo_careful_chroot ${ROOT} aptitude -y safe-upgrade
 sudo_careful_chroot ${ROOT} apt-get -y upgrade
}

function install_package {
 # global DEBIANROOT
 # sudo_careful_chroot ${DEBIANROOT} aptitude install -y "$@"
 sudo_careful_chroot ${DEBIANROOT} apt-get install -y "$@"
}

function remove_package {
 # global DEBIANROOT
 # sudo_careful_chroot ${DEBIANROOT} aptitude remove -y "$@"
 sudo_careful_chroot ${DEBIANROOT} apt-get remove -y "$@"
}

# Fix /etc/inittab, i.e.
# (1) turn the line:
# < ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now
# into:
# > ca:12345:ctrlaltdel:/sbin/halt
# (2) add a line:
# > 0:12345:respawn:/sbin/getty 38400 tty0 xterm
# (3) comment lines in the form:
# > #1:2345:respawn:/sbin/getty 38400 tty1
# > #2:23:respawn:/sbin/getty 38400 tty2
# > ...
# > #6:23:respawn:/sbin/getty 38400 tty6
# Note that the function is idempotent.
function fix_etc_inittab {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 # systemd releases (jessie+) have no /etc/inittab. Contrary to a former (wrong)
 # assumption, `console=tty0' alone does NOT provide a login on the UML console:
 # systemd only starts getty@tty1 by default, and its getty-generator spawns a
 # console getty for SERIAL consoles, not for the tty0 virtual console. So we must
 # enable getty@tty0 explicitly -- the systemd equivalent of the old inittab
 # `getty ... tty0' line -- so that a login prompt appears on con0, i.e. the
 # console Marionnet shows. Offline enable (like `systemctl enable getty@tty0'),
 # reliable in a chroot with no running daemon. Verified by boot-test (2026-07-09).
 if [[ ${INIT_SYSTEM:-sysv} = systemd || ! -f $ROOT/etc/inittab ]]; then
   echo "systemd release: enabling getty@tty0 (login on the UML console)."
   sudo install -d -m 0755 $ROOT/etc/systemd/system/getty.target.wants
   sudo ln -sf /lib/systemd/system/getty@.service \
               $ROOT/etc/systemd/system/getty.target.wants/getty@tty0.service
   # Pin the console size for getty@tty0. Without TTYColumns/TTYRows, systemd (>=256)
   # probes the size of the sizeless UML console (con0) with an ANSI sequence (ESC[6n);
   # the terminal's reply (ESC[<row>;<col>R) then lands in the login prompt and corrupts
   # the typed username on a shared serial/UML console (e.g. `pupisto.tester -c', or any
   # real serial line). A fixed 80x24 suppresses the probe. Verified: the probe is gone
   # and the login is clean (2026-07-12, boot-tester -c).
   sudo install -d -m 0755 $ROOT/etc/systemd/system/getty@tty0.service.d
   printf '[Service]\nTTYColumns=80\nTTYRows=24\n' | \
     sudo tee $ROOT/etc/systemd/system/getty@tty0.service.d/console-size.conf >/dev/null
   return 0
 fi
 local TMPFILE=$(mktemp)
 local AWK_PROGRAM='/^1:2345:respawn:/ {print line} /^[1-6]:[1-6]*:respawn/ {print "#"$0; next} {print}'
 # Note that th -L option is very relevant to obtain a console quicly reacting to CTRL-C/CTRL-Z etc:
 sudo awk -v line="0:12345:respawn:/sbin/getty -L 38400 tty0 xterm" "$AWK_PROGRAM" "$ROOT/etc/inittab" > $TMPFILE
 tabular_file_update --ignore-unchanged -i -d ":" -k 1 --key-value "ca" -f 4 --field-value "/sbin/halt" $TMPFILE
 sudo cp $TMPFILE $ROOT/etc/inittab
 rm -f $TMPFILE
}

function fix_etc_fstab {
 # global DEBIANROOT FSTYPE INIT_SYSTEM
 local ROOT=${1:-$DEBIANROOT}
 local TYPE=${FSTYPE:-$DEFAULT_FSTYPE}
 # ubdb swap options. Under systemd, `/dev/ubdb' may never appear (UML does not
 # always expose it): `nofail' alone is NOT enough -- the generated dev-ubdb.device
 # start job still holds the boot for its full 90s timeout (verified by boot-test).
 # `x-systemd.device-timeout=1' bounds that wait to 1s, after which `nofail' lets
 # the boot proceed; if the device does show up, swap is still activated. SysV
 # swapon does not understand `x-systemd.*', so keep the legacy options there (zero
 # regression for old releases).
 local SWAP_OPTS="sw"
 [[ ${INIT_SYSTEM:-sysv} = systemd ]] && SWAP_OPTS="sw,nofail,x-systemd.device-timeout=1"
 local TMPFILE=$(mktemp)
 cat 1>$TMPFILE <<EOF
# Virtual disk partitions:
/dev/ubdb none swap $SWAP_OPTS 0 0
/dev/ubda / $TYPE defaults 0 0

# Pseudo filesystems:
proc /proc proc nodev,noexec,nosuid 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /run/shm tmpfs rw,nosuid,nodev,noexec,relatime,size=1M 0 0
EOF
 sudo cp $TMPFILE $ROOT/etc/fstab
 rm -f $TMPFILE
}

# Set the `root' passwd to "root":
function fix_root_password {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 local ENCRYPTED_PASSWORD='$6$guviKk1z$8biiuI/xnimdRLGlb0Zj0A0X6BoMv3rn3RuwOfplx7F6drBEH/DeVh7z2xYBi/9xNaS3dOuJ.49C1PFSmZd7C.'
 export ENCRYPTED_PASSWORD # because sudo_fcall transmits exported variables
 sudo_fcall tabular_file_update -i -d ":" -k 1 --key-value "root" -f 2 --field-value '$ENCRYPTED_PASSWORD' $ROOT/etc/shadow
}

# Set the `student' passwd to "student":
function fix_student_password {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 local ENCRYPTED_PASSWORD='$6$OdQbZViU$QUBmwgwlT8yEmyuYeitvgTmqIDpCC4D0o3yzYHfwUdkisnhXCsEVgk3Mz2yX4EtQ2nJs02k5orcAx5thzS/gZ/'
 export ENCRYPTED_PASSWORD # because sudo_fcall transmits exported variables
 sudo_fcall tabular_file_update -i -d ":" -k 1 --key-value "student" -f 2 --field-value '$ENCRYPTED_PASSWORD' $ROOT/etc/shadow
}

function fix_etc_securetty {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 local TARGET=$ROOT/etc/securetty
 if ! \grep -q "^tty0$" $TARGET; then
   local TMPFILE=$(mktemp)
   sudo awk '/^tty1$/ {print "tty0"} {print}' "$TARGET" > $TMPFILE
   sudo cp $TMPFILE $TARGET
   rm -f $TMPFILE
 fi
}

# Executed by `sudo_chroot_fcall' (i.e. as `root' in a chrooted environment):
# We suppose that the directory containing ethghost in the
# chrooted environment is "/tmp/ethghost":
function make_ethghost {
 local ETHGHOST=/tmp/ethghost
 make -C $ETHGHOST
 strip $ETHGHOST/ethghost
 make DESTDIR=/usr/local -C $ETHGHOST install
 rm -rf $ETHGHOST
}

# Compile ethghost into a 32-bits or 64-bits filesystem.
# Here we suppose that the apt sources have been fixed:
function compile_and_install_ethghost {
 # global DEBIANROOT GHOSTIFICATION
 local ROOT=${1:-$DEBIANROOT}
 # Architecture C images ghostify eth42 via a network namespace (in marionnet-relay),
 # not via the kernel patch + `ethghost' C tool: nothing to build or install here.
 # (On a vanilla kernel the tool's SIOCGIFGHOSTIFY ioctl does not even exist.)
 if [[ ${GHOSTIFICATION:-ethghost} = netns ]]; then
   echo "netns ghostification (architecture C): skipping ethghost build/install."
   return 0
 fi
 sudo cp -dR ../ethghost $ROOT/tmp/
 sudo chroot ${ROOT} apt-get install -y linux-libc-dev libc6-dev || true
 export -f make_ethghost
 sudo_chroot_fcall ${ROOT} make_ethghost
}

function make_symlink_etc_init_dhcpd_in_chroot {
 if [[ ! -e /etc/init.d/dhcpd  && -x /etc/init.d/isc-dhcp-server ]]; then
  ln -s isc-dhcp-server /etc/init.d/dhcpd;
 fi
}

function make_symlink_etc_init_dhcpd {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 export -f make_symlink_etc_init_dhcpd_in_chroot
 sudo_chroot_fcall ${ROOT} make_symlink_etc_init_dhcpd_in_chroot
}

function install_marionnet_relay_as_root {
 # global RELAY_SRC DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 # Dest is named explicitly: $RELAY_SRC may be a distro-specific resource whose
 # basename is not `marionnet-relay' (e.g. marionnet-relay.trixie).
 cp -v $RELAY_SRC ${ROOT}/etc/init.d/marionnet-relay
 chmod +x ${ROOT}/etc/init.d/marionnet-relay
 chroot $ROOT update-rc.d marionnet-relay defaults
}

# systemd counterpart: the same marionnet-relay script (it reads /proc/cmdline and
# accepts start|stop) is installed as /usr/local/sbin and wrapped in a native
# oneshot unit. It is NOT put in /etc/init.d/ to avoid a duplicate generated by
# systemd-sysv-generator. Enabled by creating the wants-symlink directly, which is
# what `systemctl enable' does but works reliably in an offline chroot (no daemon).
function install_marionnet_relay_systemd_as_root {
 # global RELAY_SRC DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 install -D -m 0755 $RELAY_SRC ${ROOT}/usr/local/sbin/marionnet-relay
 cat > ${ROOT}/etc/systemd/system/marionnet-relay.service <<"EOF"
[Unit]
Description=Marionnet guest startup configuration (from the kernel command line)
Documentation=man:marionnet
# marionnet-relay itself configures hostname and networking from /proc/cmdline,
# so it must only be ordered after the basic network stack is set up, not wait
# for it to be online (which it brings up).
After=network.target
DefaultDependencies=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/marionnet-relay start
ExecStop=/usr/local/sbin/marionnet-relay stop

[Install]
WantedBy=multi-user.target
EOF
 # Enable the unit offline (equivalent to `systemctl enable'):
 install -d -m 0755 ${ROOT}/etc/systemd/system/multi-user.target.wants
 ln -sf /etc/systemd/system/marionnet-relay.service \
        ${ROOT}/etc/systemd/system/multi-user.target.wants/marionnet-relay.service
}

function install_marionnet_relay {
 # global PUPISTO_FILES DEBIANROOT INIT_SYSTEM GHOSTIFICATION
 # Pick the relay resource: the netns image (architecture C) ships a distro-specific
 # relay (marionnet-relay.trixie: eth42->netns + X11 relay, no ethghost); every
 # other image uses the shared generic relay (a symlink to ../../guest/marionnet-relay).
 local RELAY_SRC=$PUPISTO_FILES/marionnet-relay
 [[ ${GHOSTIFICATION:-ethghost} = netns ]] && RELAY_SRC=$PUPISTO_FILES/marionnet-relay.trixie
 export PUPISTO_FILES DEBIANROOT RELAY_SRC
 if [[ ${INIT_SYSTEM:-sysv} = systemd ]]; then
   sudo_fcall install_marionnet_relay_systemd_as_root
 else
   sudo_fcall install_marionnet_relay_as_root
 fi
}

function install_bashrc_in_the_skeleton {
 # global PUPISTO_FILES DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 local BASHRC=$PUPISTO_FILES/bashrc
 sudo cp $BASHRC $ROOT/etc/skel/.bash_aliases
}

function copy_bashrc_in_the_root_home {
 # global PUPISTO_FILES DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 local BASHRC=$PUPISTO_FILES/bashrc
 # Make the `root' directory similar to the `student' one about Bash settings:
 sudo cp -f $ROOT/etc/skel/.bash* $ROOT/root/
 # Copy our bashrc (as bash_aliases, that will be sourced by the actual bashrc):
 sudo cp $BASHRC $ROOT/root/.bash_aliases
}

function create_user_student {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 sudo_careful_chroot $ROOT adduser --home /home/student --shell /bin/bash --uid 1001 --disabled-password --gecos "Student,,," student
 fix_student_password $ROOT
 sudo_careful_chroot $ROOT adduser student sudo
}

function configure_daemon_and_accounts_to_accept_ssh_connection_as_root {
 # global DEBIANROOT PUPISTO_FILES
 local ROOT=${1:-$DEBIANROOT}
 SSHD_CONFIG=$ROOT/etc/ssh/sshd_config
 SSH_DIR=$PUPISTO_FILES/ssh
 if [[ -f "$SSHD_CONFIG" ]]; then
  user_config_set --ignore-unchanged "PermitRootLogin"      " " "yes" $SSHD_CONFIG
  user_config_set --ignore-unchanged "StrictModes"          " " "no"  $SSHD_CONFIG
  user_config_set --ignore-unchanged "PubkeyAuthentication" " " "yes" $SSHD_CONFIG
  mkdir -p $ROOT/{home/student,root}/.ssh
  chmod 700 $ROOT/{home/student,root}/.ssh
  chown 1001:1001 $ROOT/home/student/.ssh
  cat ${SSH_DIR}/id_rsa_marionnet.pub >> $ROOT/home/student/.ssh/authorized_keys
  cat ${SSH_DIR}/id_rsa_marionnet.pub >> $ROOT/root/.ssh/authorized_keys
  chmod 644 $ROOT/{home/student,root}/.ssh/authorized_keys
 else
  echo "Warning: $SSHD_CONFIG not found. I can't configure daemon and accounts to accept Marionnet connections."
 fi
} # configure_daemon_and_accounts_to_accept_ssh_connection

function configure_daemon_and_accounts_to_accept_ssh_connection {
 # global PUPISTO_FILES DEBIANROOT
 export PUPISTO_FILES DEBIANROOT
 sudo_fcall configure_daemon_and_accounts_to_accept_ssh_connection_as_root
}

# Fix /etc/issue according to $INSTALL_LINUXLOGO
# Note that the script `marionnet_relay' will catenate the
# output of the command `linuxlogo' with the content of
# the file "/etc/issue.marionnet":
function fix_etc_issue_as_root {
 # global DEBIANROOT INSTALL_LINUXLOGO
 local ROOT=${1:-$DEBIANROOT}
 local PREVIOUS_MESSAGE TARGET
 if [[ $INSTALL_LINUXLOGO = y ]]; then
   unset $PREVIOUS_MESSAGE
   TARGET=$ROOT/etc/issue.marionnet
 else
   # For instance PREVIOUS_MESSAGE could be "Debian GNU/Linux 7"
   PREVIOUS_MESSAGE=$(awk <$ROOT/etc/issue -F "\\" '{print $1; exit 0}')
   PREVIOUS_MESSAGE+="\n"
   TARGET=$ROOT/etc/issue
 fi
 cat >$TARGET <<EOF
${PREVIOUS_MESSAGE}Built with debootstrap and adapted for Marionnet in $(LC_ALL=us date "+%B %Y")
using \`pupisto.debian.sh\' (see the Marionnet source repository)

Use the account root/root or student/student

EOF
}

function fix_etc_issue {
 # global DEBIANROOT
 export DEBIANROOT INSTALL_LINUXLOGO
 sudo_fcall fix_etc_issue_as_root
}


# Note that the option "-a reboot" of the command `exec'
# provokes a deadlock with kernel 3.2.x
# So we replace the line:
# exec -a reboot /sbin/halt "$@" -f
# with the simpler:
# exec /sbin/halt "$@" -f
function fix_reboot_as_root {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}

 # --- Fix `reboot'
 local TARGET=$ROOT/sbin/reboot
 rm -f $TARGET
 cat >$TARGET <<"EOF"
#!/bin/bash

# The option -f prevent a Marionnet crash using kernels 3.2.x
# For a similar reason, the option "-a reboot" must no be used:
exec /sbin/halt "$@" -f
EOF
 # ---
 chmod +x $TARGET

 # --- Fix `shutdown'
 TARGET=$ROOT/sbin/shutdown
 mv $TARGET $TARGET.unsafe
 cat >$TARGET <<"EOF"
#!/bin/bash

# The option -h neutralize the option -r that causes a
# Marionnet crash using kernels 3.2.x
exec -a shutdown /sbin/shutdown.unsafe "$@" -h
EOF
 # ---
 chmod +x $TARGET
} # fix_reboot_as_root

function fix_reboot {
 # global DEBIANROOT INIT_SYSTEM
 # This is an obsolete workaround for a 3.2.x-kernel deadlock: it overwrites
 # /sbin/reboot and /sbin/shutdown. Under systemd those are symlinks to systemctl,
 # so applying it would break clean shutdown. Skip on systemd releases (the modern
 # 6.12 kernel has no such deadlock).
 if [[ ${INIT_SYSTEM:-sysv} = systemd ]]; then
   echo "systemd release: skipping fix_reboot (obsolete 3.2.x-kernel workaround)."
   return 0
 fi
 export DEBIANROOT
 sudo_fcall fix_reboot_as_root
}

function fix_wireshark_init_lua {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 local TARGET=$ROOT/etc/wireshark/init.lua
 if [[ -f $TARGET ]]; then
   sudo sed -i -e 's/dofile(DATA_DIR.."console.lua")/--dofile(DATA_DIR.."console.lua")/' $TARGET
 fi
}

# Work around a UML-kernel crash triggered by Wireshark: its welcome-screen interface
# poller opens AF_PACKET (PACKET_MMAP) rings on EVERY interface at once, and the teardown
# corrupts UML kernel memory ("Bad page map" -> panic). Two lines of defence:
#  (1) a system preference capture.no_interface_load:TRUE disables that poller for ANY
#      invocation of the real binary. It survives an `apt upgrade' that restores the
#      packaged /usr/bin/wireshark over our symlink, because the file is NOT shipped by
#      the wireshark package (dpkg never overwrites a file it does not own);
#  (2) /usr/bin/wireshark is replaced by a wrapper that also lists the UP interfaces
#      itself (explicit `-k -i', via jq) so that live capture keeps working with the poller
#      off. The real binary is kept as /usr/bin/wireshark.real.
function install_wireshark_marionnet_wrapper {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 # Nothing to do if wireshark is not part of the selection:
 [[ -e $ROOT/usr/bin/wireshark ]] || return 0
 # (1) System preference -- safety net, survives package upgrades:
 sudo mkdir -p $ROOT/usr/share/wireshark
 sudo tee $ROOT/usr/share/wireshark/preferences 1>/dev/null <<'WIRESHARK_PREF_EOF'
# Marionnet: disable Wireshark's interface poller. Its AF_PACKET (PACKET_MMAP) rings crash
# the UML kernel ("Bad page map" -> panic) on teardown. Live capture goes through the
# `wireshark' wrapper (/usr/bin/wireshark.marionnet.sh), which lists interfaces itself.
capture.no_interface_load: TRUE
WIRESHARK_PREF_EOF
 # (2) Fabricate the wrapper (HERE-document) next to the real binary:
 sudo tee $ROOT/usr/bin/wireshark.marionnet.sh 1>/dev/null <<'WIRESHARK_WRAPPER_EOF'
#!/bin/bash
# wireshark.marionnet.sh -- installed as /usr/bin/wireshark (the real binary is
# /usr/bin/wireshark.real). Works around a UML-kernel bug: Wireshark's welcome-screen
# interface poller opens AF_PACKET (PACKET_MMAP) rings on ALL interfaces at once, whose
# teardown corrupts UML kernel memory ("Bad page map" -> panic). capture.no_interface_load
# disables that poller; since Wireshark then no longer enumerates interfaces, this wrapper
# supplies the UP ones itself via explicit `-k -i <iface>'.
#
# Usage:
#   wireshark                 # live capture on every UP interface
#   wireshark IFACE           # live capture on IFACE
#   wireshark file.pcap       # offline reading (delegated to the real Wireshark)
#   wireshark -<option> ...   # options passed through to the real Wireshark

REAL=/usr/bin/wireshark.real
NO_POLL="-o capture.no_interface_load:TRUE"

# UP interfaces (Wireshark's own enumeration being disabled). Needs jq.
# Example:  $ echo $(ip_list_up_devices)  ->  lo eth0
function ip_list_up_devices {
  type ip jq 1>/dev/null 2>&1 || return 95   # Operation not supported
  ip -j addr show | jq -r '.[] | select(.flags | index("UP")) | .ifname'
}

# An argument that is an option (-x) or an existing file => "normal" use (offline, options,
# capture file): delegate as-is to the real Wireshark, poller still off to avoid the bug.
if [ "$#" -gt 0 ]; then
  case "$1" in
    -*) exec "$REAL" $NO_POLL "$@" ;;
    *)  [ -e "$1" ] && exec "$REAL" $NO_POLL "$@" ;;
  esac
fi

# Otherwise: live capture. $1 = explicit interface if given, else every UP interface.
IFACES="${1:-$(ip_list_up_devices)}"
IFACES="${IFACES:-eth0}"

OPTIONS_i=""
for i in $IFACES; do OPTIONS_i="$OPTIONS_i -i $i"; done

exec "$REAL" $NO_POLL -k $OPTIONS_i
WIRESHARK_WRAPPER_EOF
 sudo chmod +x $ROOT/usr/bin/wireshark.marionnet.sh
 # Move the real binary aside and point `wireshark' at the wrapper (idempotent):
 if [[ ! -L $ROOT/usr/bin/wireshark ]]; then
   sudo mv $ROOT/usr/bin/wireshark $ROOT/usr/bin/wireshark.real
 fi
 sudo ln -sfn wireshark.marionnet.sh $ROOT/usr/bin/wireshark
}

function fix_locales_as_root {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 [[ -n $ROOT ]] || return 1
 # ---
 cat >$ROOT/etc/locale.gen <<"EOF"
# This file lists locales that you wish to have built. You can find a list
# of valid supported locales at /usr/share/i18n/SUPPORTED. Other
# combinations are possible, but may not be well tested. If you change
# this file, you need to rerun locale-gen.
#
# XXX GENERATED XXX
#
# NOTE!!! If you change this file by hand, and want to continue
# maintaining manually, remove the above line. Otherwise, use the command
# "dpkg-reconfigure locales" to manipulate this file. You can manually
# change this file without affecting the use of debconf, however, since it
# does read in your changes.

en_US.UTF-8 UTF-8
EOF
 # ---
 # Equivalent to `dpkg-reconfigure locales':
 chroot $ROOT locale-gen
}

function fix_locales {
 # global DEBIANROOT INSTALL_LOCALES
 [[ -n $INSTALL_LOCALES ]] || return 0
 export DEBIANROOT
 sudo_fcall fix_locales_as_root
}


function prevent_non_vital_services_from_starting {
 # global DEBIANROOT INIT_SYSTEM
 local ROOT=${1:-$DEBIANROOT}
 # The SysV branch below scans /etc/init.d and calls `update-rc.d remove', keeping
 # only a whitelist (REQUIRED_SERVICES). The systemd branch mirrors that philosophy,
 # stricter: a lab machine must boot *bare*. Starting a service -- the network
 # included -- is an administration decision with a cost (security, resources), so it
 # is OFF by default; students enable what they need during the labs. We keep only
 # the vital units and disable *every* other service enabled at multi-user level.
 #
 # Kept (vital): the systemd core (never symlinked under multi-user.target.wants on
 # Debian -- pulled by static deps, so untouched by this loop), getty (handled by
 # fix_etc_inittab, lives under getty.target.wants) and marionnet-relay (host<->guest
 # bring-up). Consequence to keep in mind: networking.service is off too, so `lo' and
 # the interfaces are down until the student brings them up.
 #
 # We remove the `Wants' symlink DIRECTLY rather than via `systemctl --root=...
 # disable': the latter silently no-ops offline here (a host systemctl refuses to
 # operate on the chroot -- verified by boot-test: every daemon was still enabled and
 # nmbd stalled the boot ~90s "waiting for interface"). A plain `rm' of the symlink is
 # exactly what `disable' would do and cannot no-op. The daemon stays installed and
 # startable by hand. Socket-activated units (their .socket lives under
 # sockets.target.wants) are left alone: they start on demand, not at boot.
 #
 # Two passes are needed, because a service can be enabled through two independent
 # mechanisms: (1) NATIVE systemd units, symlinked under some `*.target.wants/'; and
 # (2) SysV-only init scripts (no native unit) enabled via `/etc/rc*.d/', which
 # systemd-sysv-generator turns into units at boot (e.g. isc-dhcp-server, dhcpd) --
 # invisible to pass 1. Both must be disabled or the machine is not really bare.
 if [[ ${INIT_SYSTEM:-sysv} = systemd ]]; then
   local sysd="$ROOT/etc/systemd/system"
   # Pass 1 -- native units. Discover the enabled non-vital services from
   # multi-user.target.wants (where server daemons land), then unlink them from
   # EVERY `*.target.wants/': a unit may be pulled by more than one target (e.g.
   # networking.service is WantedBy both multi-user.target and network-online.target,
   # so cleaning only multi-user would leave it running).
   local KEEP_ENABLED="marionnet-relay"   # getty is under getty.target.wants, untouched
   local unit base name
   for unit in "$sysd"/multi-user.target.wants/*.service; do
     # `-L' (symlink) not just `-e' (exists): these Wants links carry an ABSOLUTE
     # path into the GUEST's /usr/lib/systemd/system, so `-e' -- which follows the
     # link -- is FALSE on the host for any unit the host itself lacks (babeld,
     # named, nmbd, kea...), silently skipping exactly the server daemons we must
     # disable. `-L' catches dangling-on-host symlinks; both together still skip
     # the literal `*.service' glob when the directory has no match.
     [[ -e $unit || -L $unit ]] || continue
     base=$(basename "$unit"); name=${base%.service}
     # Defensive: never touch systemd's own units, should any be symlinked here.
     case $name in systemd-*|dbus|user@*|user-runtime-dir@*) continue;; esac
     case " $KEEP_ENABLED " in *" $name "*) continue;; esac
     sudo rm -f "$sysd"/*.target.wants/"$base"
     echo "  disabled: $name"
   done
   # Pass 2 -- SysV-only scripts still enabled via /etc/rc*.d (no native unit shadows
   # them). Keep only what we want at boot: `linuxlogo' prints the Marionnet banner on
   # the console. `update-rc.d remove' drops the rc?.d symlinks so the generator no
   # longer pulls them in.
   local KEEP_SYSV="marionnet-relay linuxlogo"
   local s
   for s in $(find "$ROOT/etc/init.d" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null); do
     # a native systemd unit shadows the SysV script -> the script is inert, skip it
     [[ -e $ROOT/lib/systemd/system/$s.service || -e $ROOT/usr/lib/systemd/system/$s.service ]] && continue
     case " $KEEP_SYSV " in *" $s "*) continue;; esac
     ls "$ROOT"/etc/rc[2-5].d/S*"$s" >/dev/null 2>&1 || continue   # only if actually enabled
     sudo chroot "$ROOT" update-rc.d -f "$s" remove >/dev/null 2>&1 || true
     echo "  disabled (SysV): $s"
   done
   # Pass 3 -- systemd timers. Passes 1-2 disable *services*; periodic maintenance
   # timers under timers.target.wants/ survive them. On an ephemeral lab VM they are
   # all noise: each carries Persistent=true, so a missed run is caught up *at boot*
   # (the guest clock starts behind), firing them in a burst right when the student
   # begins. None is a teachable service (those are the daemons handled above) --
   # apt-daily even locks dpkg mid-lab, man-db reindexes every boot, e2scrub_all is a
   # no-op (no LVM), fstrim a no-op on ubd, lighttpd-maint an orphan (lighttpd off).
   # Same offline-safe `rm' of the Wants symlink as pass 1. Whitelist empty.
   # Rationale table: docs/kernel-rootfs-refresh.details.md (2026-07-10).
   local tw="$sysd/timers.target.wants"
   for unit in "$tw"/*.timer; do
     [[ -e $unit || -L $unit ]] || continue
     base=$(basename "$unit")
     sudo rm -f "$tw/$base"
     echo "  disabled (timer): ${base%.timer}"
   done
   echo "systemd release: only vital units kept (marionnet-relay + linuxlogo + getty + systemd core); network, all servers and maintenance timers OFF."
   return 0
 fi
 # Note that `console-screen.sh' creates a second windows. So, we don't consider it as required.
 # Note that `linuxlogo' is lanched manually by `marionnet_relay'. So, we don't consider it as required.
 # The service `x11-common' should be required for x-nested machines.
 local REQUIRED_SERVICES="bootlogs bootmisc.sh checkroot-bootclean.sh checkroot.sh cron halt hostname.sh killprocs kmod marionnet-relay mountall-bootclean.sh mountall.sh mtab.sh networking procps rc rc.local rcS reboot rmnologin sendsigs single skeleton sudo sysfsutils sysstat umountfs umountroot urandom"
 local TMPFILE1=$(mktemp)
 local TMPFILE2=$(mktemp)
 find $ROOT/etc/init.d/ -mindepth 1 -maxdepth 1 -name "[a-z][a-z.\-0-9]*" -exec basename {} \; > $TMPFILE1
 echo $REQUIRED_SERVICES | tr ' ' '\n' > $TMPFILE2
 SERVICES_TO_REMOVE=$(list_diff $TMPFILE1 $TMPFILE2)
 # Example: SERVICES_TO_REMOVE="apache2 atftpd babeld bind9 checkfs.sh courier-authdaemon courier-imap courier-ldap courier-mta dbus dhcpd etc-setserial hwclock.sh inetutils-inetd inetutils-syslogd isc-dhcp-server lighttpd motd mountdevsubfs.sh mountkernfs.sh mountnfs-bootclean.sh mountnfs.sh nfs-common nfs-kernel-server nis ntp pppd-dns quagga racoon radvd rpcbind rsync setkey setserial slapd snmpd ssh udev udev-mtab umountnfs.sh x11-common"
 rm -f $TMPFILE1 $TMPFILE2
 local i
 for i in $SERVICES_TO_REMOVE; do
   sudo chroot $ROOT update-rc.d -f "$i" remove || true
 done
 # Fix some annoying messages on boot:
 local TARGET=$ROOT/etc/init.d/mountall.sh
 if [[ -f $TARGET ]]; then
  sudo sed -i -e 's/kill -s USR1/kill 2>\/dev\/null -s USR1/' $TARGET
 fi

}

function install_ipv6_care_in_chroot {
 cd /tmp
 wget 'http://sourceforge.net/projects/ipv6-care/files/latest/' -O ipv6_care-latest.tar.gz || return 1
 tar xvzf ipv6_care-latest.tar.gz
 cd ipv6_care-*
 { ./configure && make && make install; } || return 2
}

function install_ipv6_care {
 # global DEBIANROOT
 local ROOT=${1:-$DEBIANROOT}
 export -f install_ipv6_care_in_chroot
 sudo_chroot_fcall $ROOT install_ipv6_care_in_chroot
}

function clean_debian_filesystem {
 # global DEBIANROOT INSTALL_LOCALES TWDIR
 local ROOT=${1:-$DEBIANROOT}
 [[ -n $ROOT ]] || return 1

 # 1) apt-get install deborphan
 echo "* Installing deborphan if necessary...";
 install_package deborphan || true

 # 2) apt-clean
 echo "* Cleaning..."
 sudo chroot "$ROOT" bash -c "apt-get -y clean; apt-get -y autoremove"
 sudo chroot "$ROOT" bash -c "dpkg -l | grep '^rc' && COLUMNS=200 dpkg -l | grep '^rc' | awk '{print \$2}' | xargs dpkg -P" || true

 # 3) deborphan
 echo "* Removing orphans..."
 sudo chroot "$ROOT" bash -c "deborphan | xargs apt-get -y --purge remove 2>/dev/null"

 # 4) clean /var/cache
 echo "* Removing all directories in /var/cache..."
 sudo find "$ROOT"/var/cache/* -type f -exec rm -f {} \;

 # 5) clean tmp/
 echo "* Cleaning /tmp and /root..."
 sudo chroot "$ROOT" bash -c ">root/.bash_history; rm -rf tmp/*; rm -rf .rr_moved; >var/mail/root"

 # 6) locales
 if [[ $INSTALL_LOCALES = y ]]; then
   echo "* File *.mo in /usr/share/locale NOT removed"
 else
   echo "* Removing files *.mo from /usr/share/locale..."
   sudo find "$ROOT"/usr/share/locale/ -type f -name "*.mo" -exec rm {} \;
 fi

 # 7) accelerate future 'apt-get update' (very slow with cow-files):
 local TARGET=$ROOT/etc/apt/apt.conf.d/99translations
 sudo_fprintf $TARGET 'Acquire::Languages "none";\n'

 sudo find $ROOT/var/lib/apt/lists -name "*i18n_Translation*" -exec rm {} \;

 # 8) remove /var/lib/apt/lists/*
 # sudo chroot "$ROOT" bash -c "apt-get update; aptitude update"
 echo "* Removing /var/lib/apt/lists/* ..."
 sudo rm -rf "$ROOT"/var/lib/apt/lists/*

 # 9) move /debootstrap to $TWDIR
 sudo mv "$ROOT"/debootstrap $TWDIR/
 sudo chown -R ${USER:-nobody} $TWDIR/debootstrap/
 grep "conflict" $TWDIR/debootstrap/debootstrap.log | sort | uniq >> $TWDIR/README.debootstrap.conflicts

 echo "Success."
}


function make_the_image {
 # global DEBIANROOT IMAGE (or TWDIR and RELEASE)
 local IMAGE=${1:-$TWDIR/machine-debian-${RELEASE}}
 local FS_SIZE IMAGE_SIZE # Megabytes
 local MOUNTDIR
 local RETURN_CODE=0
 # ---
 FS_SIZE=$(sudo du -sm $DEBIANROOT | awk '{print $1}')
 # Add 20%
 let IMAGE_SIZE="FS_SIZE*120/100"
 echo "Creating the image (${IMAGE_SIZE}M) ..."
 dd if=/dev/zero of=$IMAGE bs=1M count=$IMAGE_SIZE
 # ---
 echo "Formatting the image ($FSTYPE) ..."
 local MKFS_OPTIONS
 case $FSTYPE in ext?) MKFS_OPTIONS="-q -F";; esac
 sudo mkfs.$FSTYPE $MKFS_OPTIONS $IMAGE ### TODO: check the existence of mkfs.$FSTYPE at the beginning of the script
 # ---
 MOUNTDIR=$IMAGE.mnt
 mkdir -v -p $MOUNTDIR
 echo "Mounting the image ($MOUNTDIR) ..."
 sudo mount -o loop $IMAGE $MOUNTDIR
 # ---
 echo "Copying the filesystem content into the image..."
 sudo_fcall copy_content_into_directory $DEBIANROOT/ $MOUNTDIR/ || RETURN_CODE=$?
 # ---
 echo "Unmounting the image ($MOUNTDIR) ..."
 sudo umount $MOUNTDIR
 rmdir $MOUNTDIR
 # ---
 if [[ $RETURN_CODE = 0 ]]; then
   echo "Image built into: $IMAGE"
   echo "Success."
 else
   return $RETURN_CODE
 fi
}

# This function is not called directly here but is called by the generic function
# `rename_with_sum_and_make_image_dot_conf' defined in ../pupisto.common/toolkit_image.
function set_X11_SUPPORT_and_related_variables_according_to_choosed_packages {
  # global (input)  DEBIANROOT FSTYPE
  # global (output) X11_SUPPORT MEMORY_MIN_SIZE MEMORY_SUGGESTED_SIZE
  # ---
  # The file compression used with btrfs (lzo) requires more memory:
  if [[ $FSTYPE = btrfs ]]; then
    if sudo chroot $DEBIANROOT dpkg -l | \grep -q "ii[ ][ ]*libx11-"; then
      if sudo chroot $DEBIANROOT dpkg -l | \grep -q "ii[ ][ ]*xserver-"; then
	X11_SUPPORT="xnested"
	MEMORY_MIN_SIZE=128
	MEMORY_SUGGESTED_SIZE=192
      else
	X11_SUPPORT="xhosted"
	MEMORY_MIN_SIZE=96 # tested
	MEMORY_SUGGESTED_SIZE=128
      fi
    else
      X11_SUPPORT="none"
      MEMORY_MIN_SIZE=32 # tested
      MEMORY_SUGGESTED_SIZE=40
    fi
  else # Normal case (no btrfs):
    if sudo chroot $DEBIANROOT dpkg -l | \grep -q "ii[ ][ ]*libx11-"; then
      if sudo chroot $DEBIANROOT dpkg -l | \grep -q "ii[ ][ ]*xserver-"; then
	X11_SUPPORT="xnested"
	MEMORY_MIN_SIZE=64
	MEMORY_SUGGESTED_SIZE=128
      else
	X11_SUPPORT="xhosted"
	MEMORY_MIN_SIZE=64 # tested
	MEMORY_SUGGESTED_SIZE=80 # tested
      fi
    else
      X11_SUPPORT="none"
      MEMORY_MIN_SIZE=24 # tested
      MEMORY_SUGGESTED_SIZE=32
    fi
  fi # btrfs or not
}

function mknod_for_virtual_disks_in_chroot {
 local i j p
 rm -f /dev/ubd*
 # ---
 for i in {0..7}; do mknod /dev/ubd$i b 98 $((i*16)); done
 # Generated:
 #  mknod /dev/ubd0 b 98 0
 #  mknod /dev/ubd1 b 98 16
 #  ...
 #  mknod /dev/ubd7 b 98 112

 let j=0; for i in {a..h}; do mknod /dev/ubd$i b 98 $((j*16)); let j=j+1; done
 # Generated:
 #  mknod /dev/ubda b 98 0
 #  mknod /dev/ubdb b 98 16
 #  ...
 #  mknod /dev/ubdh b 98 112

 let j=0; for i in {a..h}; do for p in {1..4}; do mknod /dev/ubd$i$p b 98 $((j*16+p)); done; let j=j+1; done
 # Generated:
 # ---
 #  mknod /dev/ubda1 b 98 1
 #  mknod /dev/ubda2 b 98 2
 #  mknod /dev/ubda3 b 98 3
 #  mknod /dev/ubda4 b 98 4
 #
 #  mknod /dev/ubdb1 b 98 17
 #  mknod /dev/ubdb2 b 98 18
 #  mknod /dev/ubdb3 b 98 19
 #  mknod /dev/ubdb4 b 98 20
 #  ...
 #  mknod /dev/ubdh1 b 98 113
 #  mknod /dev/ubdh2 b 98 114
 #  mknod /dev/ubdh3 b 98 115
 #  mknod /dev/ubdh4 b 98 116
}

function mknod_for_virtual_disks {
 # global DEBIANROOT PUPISTO_FILES
 local ROOT=${1:-$DEBIANROOT}
 export -f mknod_for_virtual_disks_in_chroot
 sudo_chroot_fcall $ROOT mknod_for_virtual_disks_in_chroot
 sudo tar -C $ROOT -xz --keep-newer-files --keep-old-files -f $PUPISTO_FILES/dev.tar.gz || true
}

# =============================================================
#                         KERNEL
# =============================================================

function make_or_link_the_kernel {
 # global option_K TWDIR KERNEL_VERSION
 local EXISTING_KERNEL_DIR BUILT_DIR
 local DOWNLOADS_DIRECTORY=../pupisto.kernel/_build.downloads
 # ---
 # Option -K/--no-kernel
 if [[ -z ${option_K} ]]; then
   EXISTING_KERNEL_DIR=$(find ../pupisto.kernel/ -maxdepth 1 -type d -name "_build.linux-$KERNEL_VERSION*" | sort | tail -n 1)
   if [[ -d $EXISTING_KERNEL_DIR ]]; then
     echo 1>&2 "A directory \`$EXISTING_KERNEL_DIR' already exists: making a symlink to!"
     ln -s ../"$EXISTING_KERNEL_DIR" "$TWDIR/linux-$KERNEL_VERSION"
   else
     # In order to have a unique log, we will use the script as
     # a library of functions instead of as a standalone program:
     source ../pupisto.kernel/pupisto.kernel.sh --source
     # Now call the function:
     download_patch_and_compile_kernel ${KERNEL_VERSION} ${TWDIR} ${DOWNLOADS_DIRECTORY}
     # Move the whole directory to the good place (../pupisto.kernel/)
     # in order to potentially share it among other filesystem building:
     BUILT_DIR=_build.linux-${KERNEL_VERSION}.$(date +%Y-%m-%d.%H\h%M).$RANDOM
     echo "Moving \`$TWDIR/linux-$KERNEL_VERSION' -> \`../pupisto.kernel/$BUILT_DIR'"
     mv $TWDIR/linux-$KERNEL_VERSION ../pupisto.kernel/$BUILT_DIR
     ln -s ../../pupisto.kernel/$BUILT_DIR $TWDIR/linux-$KERNEL_VERSION
   fi
 else # --no-kernel
   echo 1>&2 "Option -K (--no-kernel) selected: nothing to do"
 fi
} # make_or_link_the_kernel


# =============================================================
#            KERNEL-FEATURE CHECK (selection vs .config)
# =============================================================
#
# Single source of truth: a curated map `selected package -> kernel CONFIG_*
# symbols it needs BUILT-IN (=y)'. It serves two purposes:
#   1. it documents/justifies which symbols the UML kernel config
#      (uml/kernel/CONFIG-modern-base, frozen as CONFIG-$VERSION) must enable;
#   2. check_kernel_features_for_selection reads the paired compiled `.config'
#      and fails the build (fatal) if a selected package needs a feature that is
#      not =y in that kernel (e.g. trixie's iptables-nft needs CONFIG_NF_TABLES).
#
# Only built-in (=y) counts, not =m: these UML images do not load kernel modules
# at runtime, so a feature compiled as a module would be unusable.
#
# Extend the map when a new package with non-trivial kernel needs enters the
# .selection. Symbols are space-separated. Membership is driven by the .selection
# file (the curated image-content source of truth), not by a runtime variable.
Map_make KERNEL_REQUIREMENTS
# iptables: framework + x_tables matches/targets (iptables-nft compat AND legacy)
# + the iptables-legacy / ip6tables-legacy backends themselves.
Map_set KERNEL_REQUIREMENTS iptables     "CONFIG_NETFILTER CONFIG_NF_CONNTRACK CONFIG_NF_NAT CONFIG_NF_TABLES CONFIG_NFT_COMPAT CONFIG_NETFILTER_XT_MATCH_STATE CONFIG_NETFILTER_XT_MATCH_CONNTRACK CONFIG_NETFILTER_XT_MATCH_MULTIPORT CONFIG_NETFILTER_XT_TARGET_LOG CONFIG_NETFILTER_XT_TARGET_MASQUERADE CONFIG_IP_NF_IPTABLES CONFIG_IP_NF_FILTER CONFIG_IP_NF_TARGET_REJECT CONFIG_IP_NF_NAT CONFIG_IP6_NF_IPTABLES CONFIG_IP6_NF_FILTER CONFIG_IP6_NF_TARGET_REJECT"
# nftables: inet family + native expressions used by firewall labs (the `counter'
# statement is built into the nf_tables core, so it has no separate symbol).
Map_set KERNEL_REQUIREMENTS nftables     "CONFIG_NF_TABLES CONFIG_NF_TABLES_INET CONFIG_NFT_REJECT CONFIG_NFT_LOG CONFIG_NFT_MASQ CONFIG_NFT_LIMIT CONFIG_NFT_REDIR"
Map_set KERNEL_REQUIREMENTS bridge-utils "CONFIG_BRIDGE"
Map_set KERNEL_REQUIREMENTS vlan         "CONFIG_VLAN_8021Q"
Map_set KERNEL_REQUIREMENTS iproute2     "CONFIG_NET_SCHED CONFIG_VETH CONFIG_NET_NS"
Map_set KERNEL_REQUIREMENTS openvpn      "CONFIG_TUN"
Map_set KERNEL_REQUIREMENTS ppp          "CONFIG_PPP"
Map_set KERNEL_REQUIREMENTS tcpdump      "CONFIG_PACKET"
Map_set KERNEL_REQUIREMENTS wireshark    "CONFIG_PACKET"
Map_set KERNEL_REQUIREMENTS tshark       "CONFIG_PACKET"

# Locate the compiled .config of the kernel paired with this build (most recent match).
function paired_kernel_config_file {
  find ../pupisto.kernel/ -maxdepth 2 -type f -name .config -path "*_build.linux-${KERNEL_VERSION}*" \
    | sort | tail -n 1
}

# True iff CONFIG symbol $1 is built-in (=y) in .config file $2.
function kernel_symbol_is_builtin {
  grep -qE "^$1=y\$" "$2"
}

# Fatal by default: every feature the SELECTED packages require must be =y in the
# paired kernel. Override with MARIONNET_KERNEL_CHECK={strict|warn|off}.
function check_kernel_features_for_selection {
  local mode=${MARIONNET_KERNEL_CHECK:-strict}
  [[ $mode = off ]] && { echo "Kernel feature check: disabled (MARIONNET_KERNEL_CHECK=off)"; return 0; }
  local config; config=$(paired_kernel_config_file)
  if [[ -z $config || ! -f $config ]]; then
    echo 1>&2 "Kernel feature check: no compiled .config found for $KERNEL_VERSION (skipping; build without -K)"
    return 0
  fi
  local SELECTION=$PUPISTO_FILES/package_catalog/package_catalog.$RELEASE.selection
  local selected; selected=$(awk '$1 !~ /^#/ {print $1}' "$SELECTION")
  local pkg sym
  local -a keys=() violations=()
  Map_to_key_array KERNEL_REQUIREMENTS keys
  for pkg in "${keys[@]}"; do
    grep -qxF "$pkg" <<<"$selected" || continue   # package not selected → nothing to check
    for sym in $(Map_get KERNEL_REQUIREMENTS "$pkg"); do
      kernel_symbol_is_builtin "$sym" "$config" || violations+=("$pkg -> $sym")
    done
  done
  if ((${#violations[@]})); then
    echo 1>&2 "=========================================================="
    echo 1>&2 "KERNEL FEATURE CHECK FAILED ($(basename "$(dirname "$config")"))"
    echo 1>&2 "Selected packages need kernel features NOT built-in (=y):"
    printf 1>&2 '  - %s\n' "${violations[@]}"
    echo 1>&2 "Fix: enable these =y in uml/kernel/CONFIG-modern-base, regenerate"
    echo 1>&2 "CONFIG-${KERNEL_VERSION} and rebuild the kernel."
    echo 1>&2 "=========================================================="
    [[ $mode = warn ]] && { echo 1>&2 "(MARIONNET_KERNEL_CHECK=warn: continuing anyway)"; return 0; }
    return 1
  fi
  echo "Kernel feature check: OK ($(basename "$(dirname "$config")"))"
}


# =============================================================
#                        ACTIONS
# =============================================================

# Make sure the host-side tools we need (debootstrap, ...) are installed:
ensure_host_dependencies

# The first step is to create the Debian directory with debootstrap:
once launch_debootstrap_and_then_apt_get_install

# Fix apt sources, update and upgrade:
once fix_apt_sources_update_and_upgrade

# Fix locales (if installed) to "en_US.UTF-8":
#once fix_locales

# Remove package `udev' (and packages depending to it)
#once remove_package udev || true

# Fix /etc/inittab:
once fix_etc_inittab

# Fix /etc/securetty:
once fix_etc_securetty

# Fix /etc/fstab:
once fix_etc_fstab

# Fix the problem of /sbin/reboot and /sbin/shutdown that may
# provoke a Marionnet crash:
once fix_reboot

# Set the `root' passwd to "root":
once fix_root_password

# Compile ethghost into the 32-bits filesystem:
once compile_and_install_ethghost # <=

# Make a symlink: /etc/init.d/dhcpd -> isc-dhcp-server
once make_symlink_etc_init_dhcpd

# Install our marionnet-startup script:
once install_marionnet_relay # <=

# Install our bashrc into $DEBIANROOT/etc/skel/
once install_bashrc_in_the_skeleton

# Copy our bashrc in the root's home directory:
once copy_bashrc_in_the_root_home

# Create user "student" (with the modified skeleton):
once create_user_student

# Configure the ssh daemon and root/student accounts to accept Marionnet connections:
once configure_daemon_and_accounts_to_accept_ssh_connection

# Login message.
once fix_etc_issue

# Do not start services at boot (except the vital ones):
once prevent_non_vital_services_from_starting

# Create devices /dev/ubd? for virtual disks:
# once mknod_for_virtual_disks

# Prevent a noising warning window to appear when
# wireshark is called as root (that is usual with
# Marionnet):
once fix_wireshark_init_lua

# Replace /usr/bin/wireshark by a wrapper avoiding a UML-kernel crash (Wireshark's
# interface poller opens AF_PACKET rings whose teardown panics the guest kernel):
once install_wireshark_marionnet_wrapper

# Install this nice program, useful for labs about IPv6 compliance:
# once install_ipv6_care || true

# Final cleaning:
once clean_debian_filesystem

# Get the binary list:
BINARY_LIST=$(sudo_chroot_binary_list $DEBIANROOT)

# Go:
FS_LOC=$TWDIR/machine-debian-${RELEASE}
once make_the_image "$FS_LOC"

# Build image's meta-data.
# This call defines FS_NAME
once rename_with_sum_and_make_image_dot_conf "$FS_LOC"

# Make now the kernel or just link it:
once make_or_link_the_kernel $KERNEL_VERSION

# Verify the paired kernel provides (=y) every feature the selected software needs.
# Fatal by default (override with MARIONNET_KERNEL_CHECK=warn|off). NOT wrapped in
# `once' (must run every build; `once' would also swallow the exit code — see the
# note near launch_debootstrap about `once' neutralising set -e).
check_kernel_features_for_selection

# =============================================================
#                         GREETINGS
# =============================================================

# Store the log file into the output directory:
# make_a_human_readable_log_into_working_directory

# [[ -f $CUSTOM_PACKAGES_NO  ]] && mv $CUSTOM_PACKAGES_NO  $TWDIR/
# [[ -f $CUSTOM_PACKAGES_YES ]] && mv $CUSTOM_PACKAGES_YES $TWDIR/

echo "---"
ls -l $TWDIR
echo "---"
echo "Pay attention to move (or copy with option \`-a') the filesystem in order to preserve the MTIME."
echo "If something goes wrong installing your filesystem, you can restore the correct"
echo "MTIME with the following command:"
echo "sudo touch -d \$(date -d '@$MTIME') $FS_NAME"
echo
echo "Success."

# Copy log and exit:
cat $LOGFILE > $TWDIR/$(basename $LOGFILE)
exit 0


