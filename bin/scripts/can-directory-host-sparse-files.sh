#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2007  Jean-Vincent Loddo
# Copyright (C) 2007  Luca Saiu

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
# Does DIR sit on a filesystem which can host SPARSE files -- files with holes,
# whose unwritten regions cost no disk block? Marionnet needs them for the COW
# files of every virtual machine (`cp --sparse=always', bin/cow_files.ml) and for
# the 1 GiB swap file it creates per guest (bin/simulation_level.ml). Without
# holes, both are written in full: a session costs gibibytes instead of megabytes.
#
# Exit status: 0 = yes, 1 = no, 2 = cannot tell, 3 = no such directory.
# Only 0 is looked at by the caller (bin/gui/talking.ml, which embeds this file
# at preprocessing time through INCLUDE_AS_STRING).
#
# WE MEASURE, WE DO NOT GUESS.  Until 2026-09-02 this script deduced the mount
# point (df -P), read the filesystem type (mount -l) and compared it with a white
# list written in 2007: reiserfs reiser4 ext4 ext4dev ext3 ext2 udf ntfs jfs ufs
# tmpfs vxfs xiafs. That list had no `overlay' in it, so EVERY Docker container --
# a whole classroom of them -- was told at start-up that sparse files were not
# supported, while they worked perfectly (measured: a 1 MiB hole allocates 0
# blocks on overlayfs). It had no `btrfs', `zfs', `f2fs' or `bcachefs' either, and
# `xfs' had been REMOVED from it on an observation made on Ubuntu 12.04.
#
# A list of filesystem names is a promise about the future that nobody can keep.
# Making a hole and asking the kernel how many blocks it allocated is the very
# question the caller is asking, put to the only party that knows the answer, and
# it costs a couple of milliseconds.

DIR=${1:-$PWD}

[[ -d "$DIR" ]] || {
 echo "Directory doesn't exist. Exiting."
 exit 3
} >&2

# The probe file is created IN $DIR: what is being tested is the filesystem that
# directory lives on, not the one this script runs from. A dot-file, so that it is
# invisible in the rare event that something goes so wrong that the trap below
# does not run.
PROBE=$(mktemp "$DIR/.marionnet-sparse-probe.XXXXXX" 2>/dev/null) || {
 echo "Cannot create a file in $DIR. Exiting."
 exit 2
} >&2

trap 'rm -f "$PROBE"' EXIT

# 1 MiB of hole. `truncate' is coreutils, i.e. Essential on a Debian-like system;
# should it be missing, we say "cannot tell" rather than "not supported".
SIZE=1048576
truncate -s "$SIZE" "$PROBE" 2>/dev/null || {
 echo "Cannot create a file with a hole in $DIR (is truncate(1) installed?). Exiting."
 exit 2
} >&2

# %b counts 512-byte units, whatever the filesystem's own block size. A filesystem
# with holes allocates none of them (measured: 0 on ext4, on tmpfs and on overlay);
# one without allocates the lot (measured: 2048 for this very size). The threshold
# is a quarter of the apparent size -- far above the metadata a filesystem may
# legitimately charge, far below a full allocation.
BLOCKS=$(stat -c %b "$PROBE" 2>/dev/null) || {
 echo "Cannot read the allocated size of $PROBE. Exiting."
 exit 2
} >&2

(( BLOCKS * 512 < SIZE / 4 ))
