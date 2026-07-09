# This file is part of marionnet
# Copyright (C) 2013, 2014  Jean-Vincent Loddo
# Copyright (C) 2013, 2014  Université Paris 13
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


# =============================================================
#                     Building `wheezy'
# =============================================================

WHEEZY_KERNEL_VERSION=3.2.60
WHEEZY_ARCH=i386
WHEEZY_FSTYPE=ext2

wheezy: dependencies
	./pupisto.debian.sh --kernel $(WHEEZY_KERNEL_VERSION) -t $(WHEEZY_FSTYPE) -a $(WHEEZY_ARCH) -r wheezy

wheezy-no-kernel: dependencies
	./pupisto.debian.sh --kernel $(WHEEZY_KERNEL_VERSION) -t $(WHEEZY_FSTYPE) -a $(WHEEZY_ARCH) --no-kernel -r wheezy

wheezy-custom: dependencies
	@echo "./pupisto.debian.sh --kernel $(WHEEZY_KERNEL_VERSION) -t $(WHEEZY_FSTYPE) -a $(WHEEZY_ARCH) -r wheezy --custom"
	@echo "NOT IMPLEMENTED YET"

wheezy-edit:
	$(EDITOR) pupisto.debian.sh.files/package_catalog/package_catalog.wheezy.selection


# =============================================================
#                     Building `stretch'
# =============================================================

STRETCH_KERNEL_VERSION=4.14.36
STRETCH_ARCH=amd64
STRETCH_FSTYPE=ext4

stretch: dependencies
	./pupisto.debian.sh --kernel $(STRETCH_KERNEL_VERSION) -t $(STRETCH_FSTYPE) -a $(STRETCH_ARCH) -r stretch

stretch-no-kernel: dependencies
	./pupisto.debian.sh --kernel $(STRETCH_KERNEL_VERSION) -t $(STRETCH_FSTYPE) -a $(STRETCH_ARCH) --no-kernel -r stretch

stretch-custom: dependencies
	@echo "./pupisto.debian.sh --kernel $(STRETCH_KERNEL_VERSION) -t $(STRETCH_FSTYPE) -a $(STRETCH_ARCH) -r stretch --custom"
	@echo "NOT IMPLEMENTED YET"

stretch-edit:
	$(EDITOR) pupisto.debian.sh.files/package_catalog/package_catalog.stretch.selection


# =============================================================
#                     Building `trixie'
# =============================================================

TRIXIE_KERNEL_VERSION=6.12.95
TRIXIE_ARCH=amd64
TRIXIE_FSTYPE=ext4

trixie: dependencies
	./pupisto.debian.sh --kernel $(TRIXIE_KERNEL_VERSION) -t $(TRIXIE_FSTYPE) -a $(TRIXIE_ARCH) -r trixie

trixie-no-kernel: dependencies
	./pupisto.debian.sh --kernel $(TRIXIE_KERNEL_VERSION) -t $(TRIXIE_FSTYPE) -a $(TRIXIE_ARCH) --no-kernel -r trixie

trixie-custom: dependencies
	@echo "./pupisto.debian.sh --kernel $(TRIXIE_KERNEL_VERSION) -t $(TRIXIE_FSTYPE) -a $(TRIXIE_ARCH) -r trixie --custom"
	@echo "NOT IMPLEMENTED YET"

trixie-edit:
	$(EDITOR) pupisto.debian.sh.files/package_catalog/package_catalog.trixie.selection

# =============================================================
#                     Dependencies
# =============================================================

# REQUIRED_PACKAGES=debootstrap fakeroot fakechroot
REQUIRED_PACKAGES=debootstrap
# realpath is now in coreutils

dependencies:
	@echo "Required packages: $(REQUIRED_PACKAGES)"
	@which dpkg 1>/dev/null || { echo "Not a Debian system (oh my god!); please install packages corresponding to: $(REQUIRED_PACKAGES)"; exit 1; }
	@dpkg 1>/dev/null -l $(REQUIRED_PACKAGES) || \
		sudo apt-get install -q -q -q -y $(REQUIRED_PACKAGES)
	@echo Ok.


# =============================================================
#                      clean & help
# =============================================================

clean:
	sudo rm -rf _build.*
	rm -f wget-log* *~
	$(MAKE) -C pupisto.debian.sh.files/package_catalog clean

help:
	@echo "Usage: make trixie"
	@echo "   or: make stretch"
	@echo "   or: make wheezy"
	@echo "   or: make dependencies"
	@echo "   or: make clean"
	@echo "   or: make help-pupisto"
	@echo "   or: make help"

help-pupisto:
	./pupisto.debian.sh --help

edit:
	$(EDITOR) Makefile *.sh pupisto.debian.sh.files/package_catalog/package_catalog.*.selection ../pupisto.common/*.sh
