# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2013  Jean vincent Loddo
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

# This Makefile helps people to build a debian filesystem
# with debootstrap according to the Marionnet requirements.

# ----------------------
#       binary_list
# ----------------------

binary_list.UNION:
	cat binary_list.*.* | sort -d | uniq > $@

# ----------------------
#  wheezy, squeeze, trixie, ... (generic pattern, one recipe for every release)
# ----------------------
# `make trixie' runs a real sudo debootstrap + apt-file update in a chroot,
# querying one package per listed binary (~1h, network required) -- see README.

RELEASES=wheezy squeeze trixie

# Pattern rules treat freshly-created files as disposable intermediates and
# `rm' them once a longer chain (e.g. .COMPLETE.COMMENTED.selection) is done
# building. GENERATED/COMPLETE.COMMENTED are expensive (GENERATED costs a real
# ~1h debootstrap run) and worth keeping around like wheezy/squeeze's already
# do (pre-existing files are never auto-removed): mark them precious.
.PRECIOUS: package_catalog.%.GENERATED package_catalog.%.COMPLETE.COMMENTED

$(RELEASES): binary_list.UNION
	chmod +x ./make_package_catalog_from_binary_list.sh
	./make_package_catalog_from_binary_list.sh $@

# GNU Make silently ignores pattern rules without a recipe (unlike explicit
# rules), so this needs one: it just checks that the release recipe above did
# leave the expected file behind (the script writes it as a side effect).
package_catalog.%.GENERATED: %
	@test -f $@ || { echo "Erreur : $@ n'a pas été produit par \`make $*'" >&2; exit 1; }

package_catalog.%.COMPLETE.COMMENTED: package_catalog.%.GENERATED
	touch package_catalog.$*.additional
	cat $< package_catalog.$*.additional | sort -k 1,1 -d | awk '{print "#"$$0}' > $@

package_catalog.%.COMPLETE.COMMENTED.selection: package_catalog.%.COMPLETE.COMMENTED
	cp -f $< $@;
	SELECTION=package_catalog.$*.selection; \
	if [[ -f $$SELECTION ]]; then for i in $$(\grep -v '^#' $$SELECTION | awk '{print $$1}'); do sed -i -e "s/^#$${i} /$${i} /" $@; done; else cp -f $< $$SELECTION; fi

# ----------------------
#     Dependencies
# ----------------------

REQUIRED_PACKAGES=debootstrap coreutils
dependencies:
	@echo "Required packages: $(REQUIRED_PACKAGES)"
	@which dpkg 1>/dev/null || { echo "Not a Debian system (oh my god!); please install packages corresponding to: $(REQUIRED_PACKAGES)"; exit 1; }
	@dpkg 1>/dev/null -l $(REQUIRED_PACKAGES) || \
		if which aptitude; then \
		  sudo aptitude install -q -q -q -y $(REQUIRED_PACKAGES); \
		elif which apt-get; then \
		  sudo apt-get  install -q -q -q -y $(REQUIRED_PACKAGES); \
		else \
		  exit 1; \
		fi
	@echo Ok.

# ----------------------
#       clean
# ----------------------

clean:
	sudo rm -rf _build.*;
	rm -f *~
	rm -f package_catalog.*.COMPLETE.COMMENTED  package_catalog.*.COMPLETE.COMMENTED.selection
	@for r in $(RELEASES); do \
	  if test -f package_catalog.$$r.GENERATED; then echo "Warning: file \`package_catalog.$$r.GENERATED' not removed; please remove it manually if you really know what are you doing."; fi; \
	done

