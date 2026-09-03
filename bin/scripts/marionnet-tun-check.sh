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

# What this machine must provide BESIDES the packages: the tun device.
#
# Marionnet builds one `mtap*' interface per virtual machine (the eth42 channel:
# X11 inside the guests, the router terminals), and every one of them goes
# through /dev/net/tun. No device, no tap -- and the sudoers rule, however
# perfect, is not even reached. That distinction is the whole reason this script
# exists: a user of a MarioNUM classroom was told at start-up to install a
# sudoers rule that was already there, while their container simply had no
# device (work-stream `modernisation-installation-marionnet').
#
# It is called by the three installation channels -- the tarball's install.sh,
# the .deb postinst and the .rpm %post -- and it is NEVER fatal for them: it
# NAMES what is missing and repairs nothing, exactly as those three already do
# for the apt/dnf dependencies (episode 10) and for the sudoers rule (episode 13).
# It loads no module and creates no device: that is the administrator's decision,
# on a machine this script knows nothing about.
#
# Exit status: 0 = taps can be created here, 1 = they cannot (and it says why).

TOOL=$(basename "$0")
TUN=/dev/net/tun

# Same candidate list as bin/tap_provider.ml and bin/scripts/marionnet-sudoers.sh,
# and for the same reason: whatever $PATH says, root's PATH is not the user's.
function ip_binary {
 local i
 for i in /usr/sbin/ip /sbin/ip /usr/bin/ip /bin/ip; do
   [[ -x $i ]] && { echo "$i"; return 0; }
 done
 return 1
}

function say { echo "$TOOL: $*" 1>&2; }

if [[ ! -c $TUN ]]; then
 cat 1>&2 <<EOF
$TOOL: this machine does not provide $TUN.
$TOOL:
$TOOL: Marionnet cannot create a single network interface (tap) without it: no
$TOOL: graphics inside the virtual machines, no router terminals. The sudoers
$TOOL: rule is not in question -- it is not even reached.
$TOOL:
$TOOL:   * in a container started fresh each time (docker run):
$TOOL:         docker run --device $TUN --cap-add NET_ADMIN ...
$TOOL:   * in an image whose container is (re)started by a script you control (a
$TOOL:     classroom image, say): create the node THERE, at each start -- Docker
$TOOL:     remounts a fresh tmpfs over /dev, so a node baked into the image at
$TOOL:     build time will not survive it:
$TOOL:         mkdir -p /dev/net && [ -e $TUN ] || mknod $TUN c 10 200 && chmod 666 $TUN
$TOOL:   * on a machine of its own, the tun module may simply not be loaded:
$TOOL:         sudo modprobe tun
$TOOL:     and, to keep it across reboots: echo tun | sudo tee /etc/modules-load.d/tun.conf
$TOOL:
$TOOL: If you are BUILDING an image right now, this is expected: it is the
$TOOL: container which will RUN Marionnet that needs the device.
EOF
 exit 1
fi

# The device is there. If we are root and iproute2 is installed, ask the kernel
# the very question Marionnet asks at start-up -- deleting a tap that does not
# exist is a no-op -- because a container may expose the device and still refuse
# the operation (measured: `--device' without `--cap-add NET_ADMIN' answers
# `ioctl(TUNSETIFF): Operation not permitted'). Not root, or no `ip': we have
# checked what we could, and we say nothing we cannot back.
IP=$(ip_binary) || {
 say "$TUN is there; iproute2 is not installed yet, so nothing more could be checked."
 exit 0
}

if [[ $EUID -ne 0 ]]; then
 say "$TUN is there. Run me as root to check the capability as well."
 exit 0
fi

if OUTPUT=$("$IP" tuntap del dev mtapprobe mode tap 2>&1); then
 exit 0
fi

if [[ $OUTPUT = *"Operation not permitted"* || $OUTPUT = *TUNSETIFF* ]]; then
 cat 1>&2 <<EOF
$TOOL: $TUN is there, but the kernel refuses to use it: CAP_NET_ADMIN is missing.
$TOOL: Marionnet will not be able to create its taps (no graphics inside the
$TOOL: virtual machines, no router terminals), and the sudoers rule cannot help.
$TOOL:
$TOOL:   * in a container, add the capability:
$TOOL:         docker run --device $TUN --cap-add NET_ADMIN ...
EOF
else
 say "$TUN is there, but a tap could not be created, and the reason is not one I know how to name:"
 say "  $OUTPUT"
fi
exit 1
