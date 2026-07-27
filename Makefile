# This -*- makefile -*- is part of our build system for OCaml projects
# Copyright (C) 2022 2023  Jean-Vincent Loddo

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

# ---
# Makefiles (this one as those in other parts) use extensively the bash shell
SHELL=/bin/bash -O extglob -c

# Default entry:
main: rebuild

# =============================================================
#                     dependencies
# =============================================================

# Goal: on a bare Debian/Ubuntu box, `make dependencies && eval $$(opam env) && make build'
# must be enough to get a complete compilation.

# Target version of the OCaml compiler:
# 5.4.1 (bugfix, 2026-02-17) rather than 5.5.0 (2026-06-19): nothing in 5.5 is useful here
# (modular explicits, GC pacing) and `camlp4.5.5' requires there `ocamlfind 1.9.9~preview'.
# Note that the former freeze on 4.13.1 ("the last one compatible with camlp4") is obsolete:
# camlp4 does follow OCaml 5 (see docs/migration-ocaml5.md).
OPAM_SWITCH_TO = 5.4.1

# `apt' packages:
#  - opam, pkg-config      : OCaml toolchain and detection of the `conf-*' packages
#  - build-essential       : gcc, required by the C stubs of lib/ (see `foreign_stubs' in lib/dune)
#  - libgtk-3-dev          : GTK+3 C headers, required to build the opam package `lablgtk3'
#  - libgtksourceview-3.0-dev : required by `conf-gtksourceview3' -> `lablgtk3-sourceview3'
#  - gettext               : msgfmt/msgmerge/xgettext, used by the `gettext-*' targets (i18n)
#  - glade                 : (development) GUI designer used to edit bin/gui/gui_glade3.xml
REQUIRED_PACKAGES = opam pkg-config build-essential libgtk-3-dev libgtksourceview-3.0-dev \
                    gettext glade

# `opam' packages strictly required by the compilation (see the (libraries ...) stanzas of
# bin/dune and lib/dune; `camlp4' serves the (preprocess (run camlp4of ...)) of lib/):
#  - camlp-streams provides the `Stream' module, dropped from the Stdlib by OCaml 5.0 and still
#    used by lib/CAMLP4/include_type_definitions_p4.ml
#  - dune-site is required by i18n/dune (relocatable location of the gettext catalogues)
OPAM_PACKAGES = dune dune-site camlp4 camlp-streams inotify lablgtk3 lablgtk3-extras \
                lablgtk3-sourceview3 conf-gtksourceview3

# `opam' packages for tooling (editor support and documentation, not needed to build):
OPAM_PACKAGES_DEV = utop odoc ocamlformat ocaml-lsp-server

# ---
# Call `sudo apt' only if something is actually missing (idempotent target).
apt-dependencies:
	@which dpkg 1>/dev/null || { echo "Not a Debian system (oh my god!); please install packages corresponding to: $(REQUIRED_PACKAGES)"; exit 1; }
	@echo "About to verify or install \`apt' dependencies..."
	@missing=$$(for p in $(REQUIRED_PACKAGES); do \
	    dpkg-query -W -f='$${Status}' $$p 2>/dev/null | grep -q "ok installed" || echo $$p; \
	  done); \
	if test -n "$$missing"; then \
	  echo "Missing apt packages:" $$missing; \
	  sudo apt install -y $$missing || exit 1; \
	else \
	  echo "apt packages: nothing to do."; \
	fi

# ---
# Move to the right compiler (creating it if needed):
opam-switch:
	@echo "About to create or switch to the compatible OCaml compiler version $(OPAM_SWITCH_TO)"
	@opam switch $(OPAM_SWITCH_TO) 1>/dev/null 2>&1 || opam switch create $(OPAM_SWITCH_TO) -y || exit 2

# ---
# Updating the opam repository: NOT by default (an `opam upgrade' may bump packages and break
# a working switch). To force it:
#   make dependencies OPAM_UPDATE=yes
OPAM_UPDATE =

# IMPORTANT: pass to `opam install' only the packages that are actually ABSENT. Passing an
# already installed package forces it to its latest version (solver criterion
# `-notuptodate(request)'), hence a recompilation of the whole switch. Idempotent target:
# nothing to install => nothing to recompile.
opam-dependencies: opam-switch
	@test -z "$(OPAM_UPDATE)" || opam update -y
	@echo "About to verify or install \`opam' dependencies..."
	@installed=$$(opam list --installed --short); \
	missing=$$(for p in $(OPAM_PACKAGES) $(OPAM_PACKAGES_DEV); do \
	    echo "$$installed" | grep -qx "$$p" || echo $$p; \
	  done); \
	if test -n "$$missing"; then \
	  echo "Missing opam packages:" $$missing; \
	  opam install -y $$missing || exit 3; \
	else \
	  echo "opam packages: nothing to do."; \
	fi
	@echo '[WARNING] You should run: eval $$(opam env) to synchronize the environment with the current switch.'

# ---
dependencies: apt-dependencies  opam-dependencies
	@echo "Success."

# Aliases (`switch' is the historical entry point):
deps: dependencies
switch: opam-switch  opam-dependencies

# ---
.PHONY: apt-dependencies opam-switch opam-dependencies dependencies deps switch


# =============================================================
#                           main
# =============================================================
# PP_OPTION = camlp4of $(OCAML4_02_OR_LATER) $(OCAML4_04_OR_LATER) -I $(OCAMLBRICKS) gettext_extract_pot_p4.cmo option_extract_p4.cmo raise_p4.cmo

all:
	dune build --always-show-command-line

rebuild:
	make clean && make all

# For quickly testing (without installation):
run:
	_build/default/bin/marionnet.exe -d

# =============================================================
#                         install
# =============================================================

# ---
EXECUTABLES = marionnet.native  marionnet_telnet.sh

# ---
# In marionnet_from_scratch we can override the installation prefix editing
# the file "./CONFIGME" with `sed' in this way:
#   sed -i -e "s@^prefix=.*@prefix=$PREFIX@" ./CONFIGME
# ---
PREFIX_INSTALL_DEFAULT=/usr/local
PREFIX_INSTALL=$(shell source ./CONFIGME && echo $${prefix_install:-$(PREFIX_INSTALL_DEFAULT)})
# ---
SHARE_DIR=$(PREFIX_INSTALL)/share/marionnet
# install-final:
# 	test $$(readlink "CONFIGME.choice") = "CONFIGME" || make rebuild-for-final
# 	dune install --prefix $(PREFIX_INSTALL)

# ---
TMPSCRIPT=_build/make_install_as_root.sh
install-final-as-root:
	test $$(readlink "CONFIGME.choice") = "CONFIGME" || make rebuild-for-final
	# ---
	echo '#!/bin/bash' > $(TMPSCRIPT)
	echo $$(opam env) >> $(TMPSCRIPT)
	echo "dune install --prefix $(PREFIX_INSTALL)" >> $(TMPSCRIPT)
	echo "for i in $(SHARE_DIR)/scripts/*; do chmod +x \$$i && cp -lf \$$i $(PREFIX_INSTALL)/bin/; done" >> $(TMPSCRIPT)
	# The scoped sudoers rule letting Tap_provider build the ghost taps with
	# iproute2 (chantier marionnet-daemon-elimination). The script is the single
	# place where the rule text lives, and it was just copied into bin/ above.
	# Remove the rule with: marionnet-sudoers.sh uninstall
	echo "$(PREFIX_INSTALL)/bin/marionnet-sudoers.sh install \"\$$SUDO_USER\"" >> $(TMPSCRIPT)
	# Note: the gettext .mo catalogues are compiled AND installed by `dune install'
	# above (see i18n/dune, dune-site `locale' site). No `make gettext-install-mo'.
	# ---
	@chmod +x $(TMPSCRIPT)
	@echo "---"
	@echo "About to execute $(TMPSCRIPT) as superuser (sudo)"
	sudo $(TMPSCRIPT)
	@echo "---"
	sudo which $(EXECUTABLES)
	@echo "---"
	@echo "Success."

# Alias:
install: install-final-as-root

# ---
# Rebuild and install the project in the opam directory for testing/debugging:
SHARE_DIR_FOR_TESTING=$(shell echo $$OPAM_SWITCH_PREFIX)/share/marionnet
# ---
INSTALLED_FILESYSTEMS=$(PREFIX_INSTALL_DEFAULT)/share/marionnet/filesystems
INSTALLED_KERNELS=$(PREFIX_INSTALL_DEFAULT)/share/marionnet/kernels
# ---
install-for-testing:
	test $$(readlink "CONFIGME.choice") = "CONFIGME.testing.sh" || make rebuild-for-testing
	dune install
	@echo "---"
	@mkdir -p $(SHARE_DIR_FOR_TESTING)/filesystems -p $(SHARE_DIR_FOR_TESTING)/kernels
	@# Purge the dangling symlinks left by a previous install whose targets have
	@# been removed since (e.g. a replaced image); `ln -sf' below never removes them:
	@for i in $(SHARE_DIR_FOR_TESTING)/filesystems/* $(SHARE_DIR_FOR_TESTING)/kernels/*; do { test -L $$i && test ! -e $$i && rm -v $$i; } || true; done
	@for i in $(wildcard $(INSTALLED_FILESYSTEMS)/*); do ln -sf $$i $(SHARE_DIR_FOR_TESTING)/filesystems/; done
	@for i in $(wildcard $(INSTALLED_KERNELS)/*);     do ln -sf $$i $(SHARE_DIR_FOR_TESTING)/kernels/; done
	@# Shell glob, NOT $(wildcard): make expands wildcard when parsing the recipe,
	@# i.e. BEFORE `dune install' above has populated share/marionnet/scripts/.
	@for i in $(SHARE_DIR_FOR_TESTING)/scripts/*; do test -e $$i || continue; chmod +x $$i && ln -sf $$i $$OPAM_SWITCH_PREFIX/bin/; done
	@echo "---"
	which $(EXECUTABLES)
	@echo "Success."

# ---
rebuild-for-testing: configure-for-testing
	make rebuild
# ---
rebuild-for-final: configure-for-final
	make rebuild
# ---
configure-for-testing:
	ln -sf "CONFIGME.testing.sh" "CONFIGME.choice"
# ---
configure-for-final:
	ln -sf "CONFIGME" "CONFIGME.choice"
# ---
configure: configure-for-final

# ---
uninstall-for-testing:
	dune uninstall
	@echo "Success."


# =============================================================
#                           edit
# =============================================================

EXCLUDE_FROM_EDITING=-o -name "meta.ml" -o -name "version.ml" -o -name "uml"
INCLUDE_FOR_EDITING=-o -name "dune-project" -o -name "Makefile" -o -name "dune"

# Edit all ml/mli files and other interesting source files with your $EDITOR
edit:
	test -n "$$EDITOR" && \
	eval $$EDITOR $$(find . \( -name "_build*" $(EXCLUDE_FROM_EDITING) \) -prune -o -type f -a \( -name "*.ml" -o -name "*.mli" $(INCLUDE_FOR_EDITING) \) -print) &


edit-gui:
	glade bin/gui/gui_glade3.xml


# =============================================================
#                           help
# =============================================================

ocamlc-warn-help:
	ocamlc -warn-help


# =============================================================
#                           clean
# =============================================================

clean:
	rm -f bin/version.ml bin/meta.ml
	dune clean
	@echo "Success."



#####################
#  META and VERSION #
#####################

# bin/version.ml and bin/meta.ml are now generated by dune itself, via (rule)s in
# bin/dune that invoke the bash makers (bin/{version,meta}.ml.maker.sh). `make` no
# longer pre-generates them; `dune build` alone suffices on a fresh clone. The
# `clean` target above still removes any stale source-tree copy so the dune rule
# targets never collide with a source file.


#####################
#      GETTEXT      #
#####################

# install-data-local: copy-failsafe-marionnet.conf
# install-local: install-mo
# uninstall-local: uninstall-mo

copy-failsafe-marionnet.conf:
	cp etc/marionnet.conf share/

# ---
PO_DIR = ./bin/po
# ---
POTGEN_TMPDIR=_build/pot/pot/default
POTGEN_MOVE_BACK=../../../..
gettext-all-ml-pot-files:
	dune build lib/gettext_extract_pot_p4.cmo
	@(mkdir -p $(POTGEN_TMPDIR)/bin; cd $(POTGEN_TMPDIR)/bin; \
	  for i in $(shell find _build/default/bin/ -name "*.ml" -o -name "*.mli" | grep -v "[.]pp[.]ml"); do \
	    cp -l ../$(POTGEN_MOVE_BACK)/$$i ./; \
	  done;\
	  cd ..; \
	  for i in $$(find bin/ -type f -name "*.ml"); do \
	    (camlp4of -I $(POTGEN_MOVE_BACK)/_build/default/lib/ gettext_extract_pot_p4.cmo  $$i >/dev/null) && echo "Generated $(POTGEN_TMPDIR)/$$i.pot"; \
	  done;)

# ---
_build/marionnet.pot: gettext-all-ml-pot-files
	@msgcat -s --use-first $(shell find $(POTGEN_TMPDIR) -name "*.ml.pot") > $@
	cp $@ $(PO_DIR)/messages.pot

# ---
gettext-messages-pot: _build/marionnet.pot
	cp $< $(PO_DIR)/messages.pot

# main-local: gettext-messages-pot
MANUALLY_POST_MAKE_IN_build = marionnet.pot

# ---
# Useful to discover widgets containing translatable strings
# gui.po: bin/gui/gui_glade3.xml
# 	xml2po $< > /tmp/$@
# 	@echo "Generated file: /tmp/$@"

# ---
# We can take the list of supported languages from $(PO_DIR)/LINGUAS.
LANGUAGES = $(shell grep -v "^\#" $(PO_DIR)/LINGUAS)# camlp4of _build/gettext_extract_pot_p4.cmo ./_build/default/bin/state.ml > /dev/null

gettext-show-languages:
	@echo $(LANGUAGES)

# Note: compilation of .po -> .mo (msgfmt) has moved to dune (i18n/dune), which
# also installs the catalogues via the dune-site `locale' site. Extraction
# (gettext-messages-pot) and merge (gettext-update-po) stay here (developer
# tasks; extraction is camlp4-coupled -> chantier camlp4->ppx).

# Dependency: gettext: /usr/bin/msgmerge
# Launch this target with caution (see bin/po/LISEZMOI.mise_a_jour_des_langues):
gettext-update-po: gettext-messages-pot
	@(cd $(PO_DIR); \
	for i in $(LANGUAGES); do \
	  (msgmerge --no-fuzzy-matching -s --update $$i.po messages.pot || exit -1) && echo "Updated "$$i.po; \
	done;)

# ---
# Install / uninstall of the .mo catalogues is handled by `dune install' /
# `dune uninstall' through the dune-site `locale' site (see i18n/dune). The
# former gettext-install-mo / gettext-uninstall-mo targets (which baked
# LOCALE_PREFIX from CONFIGME) are gone.
# ---
gettext-clean-mo:
	@(cd $(PO_DIR); \
	rm -rf *.mo *~ ;)
