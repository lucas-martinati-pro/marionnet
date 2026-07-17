# This file is part of Marionnet
# Copyright (C) 2013  Jean-Vincent Loddo
# Copyright (C) 2013  Université Paris 13
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

help:
	@echo "Usage: make <KERNEL-VERSION>"
	@echo "   or: make <KERNEL-VERSION>-i386   (modern kernel for the old 32-bit guest images)"
	@echo "   or: make OPTIONS=--custom <KERNEL-VERSION>"
	@echo "   or: make install         (last built kernel -> \$$PREFIX/share/marionnet/kernels)"
	@echo "   or: make install-dry-run"
	@echo "   or: make show_versions"
	@echo "   or: make dependencies"
	@echo "   or: make clean"
	@echo "   or: make help"
	@echo "Example: make 3.2.48"
	@echo "Example: make 6.12.95-i386"

2.% 3.% 4.% 5.% 6.%: dependencies
	./pupisto.kernel.sh $(OPTIONS) $@

# 32-bit (SUBARCH=i386) variant of a modern (>= 5.x) kernel, for the old i386
# guest images (wheezy, guignol...). For such targets make prefers this rule
# over the `6.%' one above (shorter stem), and `$*' is the plain version.
%-i386: dependencies
	./pupisto.kernel.sh $(OPTIONS) --i386 $*

# Install the last built kernel (see also `make install' in ../pupisto.debian
# for a whole kernel+image couple):
PREFIX=/usr/local

install:
	./Makefile.d/install.last-built-kernel.sh --prefix $(PREFIX)

install-dry-run:
	./Makefile.d/install.last-built-kernel.sh --prefix $(PREFIX) --dry-run

clean:
	rm -rf _build.linux-*

# Show available (stable or longterm support) versions of the kernel
# looking to https://www.kernel.org/:
show_versions:
	@lynx 2>/dev/null --dump https://www.kernel.org/ | awk '/longterm:/ || /stable:/ {print $$1,$$2}'


# =============================================================
#                     Dependencies
# =============================================================

GCC=$(shell find /usr/bin/ -name "gcc-[0-9]*" | tr '-' ' ' | sort -n -k 2 | tail -n 1 | tr ' ' '-')

#REQUIRED_PACKAGES=binutils wget patch gcc-4.8 gcc-4.8-multilib libc6-i386 libc6-dev-i386
REQUIRED_PACKAGES=binutils wget patch gcc-12 gcc-12-multilib libc6-i386 libc6-dev-i386
dependencies:
	@echo "Required packages: $(REQUIRED_PACKAGES)"
	@which dpkg 1>/dev/null || { echo "Not a Debian system (oh my god!); please install packages corresponding to: $(REQUIRED_PACKAGES)"; exit 1; }
	@dpkg 1>/dev/null -l $(REQUIRED_PACKAGES) || \
		sudo apt-get install -q -q -q -y $(REQUIRED_PACKAGES)
	@echo "---"
	echo sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 50
	echo sudo update-alternatives --set gcc /usr/bin/gcc-4.8
	sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 50
	sudo update-alternatives --set gcc /usr/bin/gcc-12
	@echo "---"
	@echo "Note: after compilation you should restore your gcc version with:";
	@echo "sudo update-alternatives --set gcc $(GCC)"
	@echo "---"
	@echo Ok.
