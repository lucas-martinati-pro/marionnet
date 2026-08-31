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
# must be enough to get a complete compilation AND a runnable application: `dependencies'
# installs both the packages needed to BUILD Marionnet and those needed to RUN it (the tools
# spawned at run-time: vde, graphviz, xterm, iproute2, ...).

# Target version of the OCaml compiler:
# 5.4.1 (bugfix, 2026-02-17) rather than 5.5.0 (2026-06-19): nothing in 5.5 is useful here
# (modular explicits, GC pacing) and `camlp4.5.5' requires there `ocamlfind 1.9.9~preview'.
# Note that the former freeze on 4.13.1 ("the last one compatible with camlp4") is obsolete:
# camlp4 does follow OCaml 5 (see docs/migration-ocaml5.md).
OPAM_SWITCH_TO = 5.4.1

# `apt' packages required to BUILD (compile-time) :
#  - opam, pkg-config      : OCaml toolchain and detection of the `conf-*' packages
#  - build-essential       : gcc, required by the C stubs of lib/ (see `foreign_stubs' in lib/dune)
#  - libgtk-3-dev          : GTK+3 C headers, required to build the opam package `lablgtk3'
#  - libgtksourceview-3.0-dev : required by `conf-gtksourceview3' -> `lablgtk3-sourceview3'
#  - gettext               : msgfmt/msgmerge/xgettext, used by the `gettext-*' targets (i18n)
#  - glade                 : (development) GUI designer used to edit bin/gui/gui_glade3.xml
REQUIRED_PACKAGES_BUILD = opam pkg-config build-essential libgtk-3-dev libgtksourceview-3.0-dev \
                          gettext glade

# `apt' packages required to RUN Marionnet (run-time), i.e. providing the host tools that the
# application spawns. The first three are actively checked at startup by bin/marionnet.ml, which
# pops up an "Unsatisfied dependency" dialog when they are missing:
#  - vde2               : vde_switch and slirpvde (checked at startup), plus wirefilter (used to
#                         emulate the defects of a cable: loss, delay, ...)
#  - graphviz           : `dot', drawing the network graph (checked at startup)
#  - uml-utilities      : `uml_mconsole', used by bin/simulation_level.ml (#gracefully_terminate:
#                         sending `halt'/`cad' to a virtual machine) and by bin/serial.ml
#                         (which pts is assigned to a serial console). NOT for `uml_switch',
#                         which is no longer used anywhere.
#  - xterm              : default terminal used to open a console on a virtual machine
#                         (MARIONNET_TERMINAL, see etc/marionnet.conf)
#  - iproute2           : `ip', used by bin/tap_provider.ml (tap creation, `sudo -n ip tuntap ...')
#                         and by many host network inspections
#  - sudo               : the scoped-privileges model that replaced the former root daemon
#  - x11-xserver-utils  : `xhost', granting the X server access to the guests (X11 forwarding)
#  - xauth              : `xauth list', read at startup by bin/x.ml to get the MIT-MAGIC-COOKIE-1
#                         then provided to the guests (see bin/simulation_level.ml)
#  - jq                 : JSON processor, required on the HOST by three distinct users: the
#                         `Json_*' module of bashbricks/bashbricks.sh -- an INSTALLED file since
#                         the work-stream `modernisation-world-bridge', sourced by
#                         bin/scripts/marionnet-{nat,lan}bridge.sh, hence needed as soon as a
#                         bridge component is started -- and the two verifiers of the control
#                         channel, mrn-check and mrn-verify, which both refuse to start without it.
#  - socat              : the transport of marionnet-ctl, the client of the
#                         control channel (`socat - UNIX-CONNECT:<socket>'), which the delivered
#                         documentation calls by its bare name. See the NOTE below: this package
#                         used to be dismissed here as a GUEST-only dependency, which stopped
#                         being true when the work-stream `pilotage-par-script' gave the host a
#                         client of its own.
#  - dnsmasq-base       : the DHCP/DNS service which bin/scripts/marionnet-dnsmasq.sh binds to
#                         the bridge of a `nat_bridge' component (work-stream
#                         `modernisation-world-bridge'), and which also emits the IPv6 router
#                         advertisements (--enable-ra). NOT the `dnsmasq' package: that one adds
#                         a system service competing for port 53, whereas `dnsmasq-base' provides
#                         the binary alone. The service is enabled BY DEFAULT on a nat_bridge and
#                         has NO fallback when the binary is missing.
# NOTES:
#  - `bridge-utils' WAS listed here, for `brctl'. Removed on 2026-08-23: not a single call site
#    is left. The existence of a bridge is now read from sysfs (bin/global_options.ml), the LAN
#    bridge is built by bin/scripts/marionnet-lanbridge.sh with `ip link' alone, and the last
#    caller of `brctl' -- useful-scripts/prepare_bridge.sh (2007) -- has been retired from the
#    source tree. `iproute2', already required, covers everything that was asked of it;
#  - `socat' is needed on BOTH sides, for unrelated reasons: inside the GUEST systems (the
#    historical reason why it was once excluded from this list) and on the host, since the
#    control channel exists -- hence its presence above;
#  - the commands `getent', `cat', `cp', `rm', `tar', `grep', `du' also called by the code come
#    from `Essential: yes' packages (libc-bin, coreutils, tar, grep): nothing to declare.
#    `xz' is NOT among them -- MEASURED on a debian:trixie-slim by the bench
#    Makefile.d/release.binary.sh.bench, where `tar xf' of a published artefact failed with
#    "xz: Cannot exec" -- hence the package below.
#  - libgtksourceview-3.0-1 : the ONE library package a PRECOMPILED Marionnet needs and a
#                         compiling one never had to name. Until the binary tarball of the
#                         work-stream `modernisation-installation-marionnet' existed, every
#                         installation compiled, so the GTK libraries came in as dependencies of
#                         REQUIRED_PACKAGES_BUILD (liblablgtk3-ocaml-dev); a machine which only
#                         RUNS the binary has no such build package. MEASURED on a
#                         debian:trixie-slim by Makefile.d/release.binary.sh.bench: the binary
#                         died with "libgtksourceview-3.0.so.1: cannot open shared object file".
#                         `objdump -p' lists 13 direct NEEDED libraries (gtk-3, gdk-3,
#                         gtksourceview-3.0, pango, pangocairo, cairo, gdk_pixbuf, glib, gobject,
#                         fontconfig, freetype, libc, libm); this single package brings them all,
#                         being the only one which depends on gtk3, which depends on the rest.
#                         Named rather than `libgtk-3-0': that name gained a `t64' suffix in
#                         trixie/noble and did not have it in bookworm, whereas this one is
#                         stable across the three -- the release's own gtk3 is then resolved by
#                         apt, whatever it is called there.
#  - xz-utils           : every artefact this project publishes is a .tar.xz by default (the
#                         guest images, the UML kernels and the precompiled application: see
#                         Makefile.d/*.prepare-to-publish.sh and Makefile.d/release.binary.sh),
#                         and useful-scripts/marionnet-install.sh extracts them through
#                         `xz -dc -T0 | tar xf -'. Marionnet itself never calls xz: what needs
#                         it is the INSTALLATION of the images the running Marionnet then boots.
REQUIRED_PACKAGES_RUNTIME = vde2 graphviz uml-utilities xterm iproute2 sudo \
                            x11-xserver-utils xauth jq socat dnsmasq-base xz-utils \
                            libgtksourceview-3.0-1

# The whole set (historical name, kept for compatibility):
REQUIRED_PACKAGES = $(REQUIRED_PACKAGES_BUILD) $(REQUIRED_PACKAGES_RUNTIME)

# `apt' packages required only to RUN the 32-bit UML kernels (built with SUBARCH=i386) of the old
# kernel/filesystem couples on a x86_64 host (see docs/retro-compatibilite-kernels-images.md).
# Deliberately NOT part of `dependencies' (opt-in target `apt-runtime-dependencies-i386'):
# installing it implies enabling a foreign architecture on the host.
REQUIRED_PACKAGES_RUNTIME_I386 = libc6:i386

# The runtime list, printed on demand. Makefile.d/release.binary.sh writes it into the README
# of the binary tarball -- the machine which unpacks that tarball has no Makefile to read.
# Reading it through here, rather than copying the list into that script, is what keeps the
# single source of truth single (see § 2.4 bis of docs/modernisation-installation-marionnet.md).
print-required-packages-runtime:
	@echo $(REQUIRED_PACKAGES_RUNTIME)

# `opam' packages strictly required by the compilation (see the (libraries ...) stanzas of
# bin/dune and lib/dune; `camlp4' serves the (preprocess (run camlp4of ...)) of lib/):
#  - camlp-streams provides the `Stream' module, dropped from the Stdlib by OCaml 5.0 and still
#    used by lib/CAMLP4/include_type_definitions_p4.ml
#  - dune-site is required by i18n/dune (relocatable location of the gettext catalogues)
#  - yojson and base64 serve the JSON codec of lib/STRUCTURES/xforest.ml, i.e. the textual
#    format of a project (work-stream `migration-marshal-to-text'): base64 is the fallback
#    for the strings which are not valid UTF-8, without which the emitted file would not be
#    valid JSON at all. Debian equivalents, for the packaging channels:
#    libyojson-ocaml-dev and libbase64-ocaml-dev.
#  - cmarkit renders the guest end-of-session report (Markdown, work-stream
#    `journalisation-profonde') into HTML, in-process: the rendering must be the SAME on every
#    machine which opens a graded project, and its `~safe:true' mode neutralizes the raw HTML of
#    a file written inside a guest, i.e. on a machine the student controls. ISC, no dependency.
#    NOTE for the packaging channels (`modernisation-installation-marionnet'): unlike yojson and
#    base64, cmarkit has NO Debian/Ubuntu package as of 2026-08 -- it must come from opam, or be
#    vendored.
OPAM_PACKAGES = dune dune-site camlp4 camlp-streams inotify lablgtk3 lablgtk3-extras \
                lablgtk3-sourceview3 conf-gtksourceview3 yojson base64 cmarkit

# `opam' packages for tooling (editor support and documentation, not needed to build):
# `sherlodoc' searches the odoc output BY TYPE (`dune build @doc-private' first), which is how
# one checks whether `ocamlbricks' already provides a function before writing it again.
# `ocamlformat' is listed for completeness only: it cannot parse the camlp4 syntax of this
# source tree (IFDEF, where_p4, INCLUDE DEFINITIONS), so it stays unused until `camlp4-to-ppx'.
OPAM_PACKAGES_DEV = utop odoc ocamlformat ocaml-lsp-server sherlodoc codept codept-lib

# ---
# Verify a list of `apt' packages, calling `sudo apt' only if something is actually missing
# (hence the idempotency of the targets below).
# Usage in a recipe: $(call apt_install_if_missing,<kind>,<package list>)
define apt_install_if_missing
	@which dpkg 1>/dev/null || { echo "Not a Debian system (oh my god!); please install packages corresponding to: $(2)"; exit 1; }
	@echo "About to verify or install \`apt' $(1) dependencies..."
	@missing=$$(for p in $(2); do \
	    dpkg-query -W -f='$${Status}' $$p 2>/dev/null | grep -q "ok installed" || echo $$p; \
	  done); \
	if test -n "$$missing"; then \
	  echo "Missing apt packages ($(1)):" $$missing; \
	  sudo apt install -y $$missing || exit 1; \
	else \
	  echo "apt packages ($(1)): nothing to do."; \
	fi
endef

apt-build-dependencies:
	$(call apt_install_if_missing,build,$(REQUIRED_PACKAGES_BUILD))

apt-runtime-dependencies:
	$(call apt_install_if_missing,run-time,$(REQUIRED_PACKAGES_RUNTIME))

# Both kinds (historical entry point):
apt-dependencies: apt-build-dependencies  apt-runtime-dependencies

# ---
# Opt-in (not required by `dependencies'): support for the 32-bit UML kernels of the old
# kernel/filesystem couples. On a x86_64 host this implies enabling the i386 foreign architecture.
apt-runtime-dependencies-i386:
	@test "$$(dpkg --print-architecture)" = "amd64" || { echo "Not an amd64 host: nothing to do."; exit 0; }
	@dpkg --print-foreign-architectures | grep -qx i386 || { \
	  echo "About to enable the i386 foreign architecture (needed to execute 32-bit UML kernels)..."; \
	  sudo dpkg --add-architecture i386 && sudo apt update; }
	$(call apt_install_if_missing,run-time i386,$(REQUIRED_PACKAGES_RUNTIME_I386))

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
.PHONY: apt-build-dependencies apt-runtime-dependencies apt-runtime-dependencies-i386 \
        apt-dependencies opam-switch opam-dependencies dependencies deps switch


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
# The delivered documentation (doc-src/dune, work-stream `modernisation-installation-marionnet'
# episode 14). Only its EXAMPLE SCRIPTS need anything from here: dune installs data files with
# mode 0644, and those scripts are meant to be run, exactly like the ones of scripts/ below.
DOC_DIR=$(PREFIX_INSTALL)/share/doc/marionnet
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
	echo "chmod +x $(DOC_DIR)/labs/session-7/*.sh $(DOC_DIR)/scripting/examples/*.sh" >> $(TMPSCRIPT)
	# The scoped sudoers rule letting Tap_provider build the ghost taps with
	# iproute2 (chantier marionnet-daemon-elimination). The script is the single
	# place where the rule text lives, and it was just copied into bin/ above.
	# Deliberately WITHOUT --enable-bridges: install time grants block (a) only,
	# the socle without which nothing works. The NAT and LAN bridge grants are
	# asked for by the end user, from the GUI, the day a bridge component is
	# started (chantier modernisation-world-bridge).
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
DOC_DIR_FOR_TESTING=$(shell echo $$OPAM_SWITCH_PREFIX)/share/doc/marionnet
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
	@chmod +x $(DOC_DIR_FOR_TESTING)/labs/session-7/*.sh $(DOC_DIR_FOR_TESTING)/scripting/examples/*.sh
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
#                  code intelligence (OCaml)
# =============================================================
# `dune build' only compiles the module closure reachable from marionnet.ml, so a
# module nobody references is never typechecked -- and no .cmt/.ocaml-index file is
# produced for it.  `make check' compiles EVERY module of every stanza, and is the
# prerequisite of anything that reads the compiler's own knowledge of the code.

check:
	dune build @check

# Project-wide occurrences for ocamllsp / merlin (needs OCaml >= 5.2, dune >= 3.16).
ocaml-index: check
	dune build @ocaml-index

# Inter-module dependency graph (_build/module-graph/*.dot|svg|deps), computed by
# `codept' read through camlp4 -- see Makefile.d/module-graph.sh, which documents
# why ocamldep is not enough here.  The `-check' variant compares the graph against
# dune's own ocamldep output and fails if codept missed an edge.
module-graph:
	bash Makefile.d/module-graph.sh

module-graph-check: check
	bash Makefile.d/module-graph.sh --check

# ---
.PHONY: check ocaml-index module-graph module-graph-check


# =============================================================
#                        publication
# =============================================================
# Work-stream `modernisation-installation-marionnet'.

# The publication series. META is the single source of truth for the version of the
# project (bin/version.ml.maker.sh reads it to generate Version.version, and so does
# useful-scripts/make_a_release_from_trunk.sh); the rule which turns a version into a
# series lives in ONE place, the script below, which prints it on demand. Override it
# on the command line if needed: make <target> PUBLICATION_SERIES=1.1.x
PUBLICATION_SERIES := $(shell bash Makefile.d/filesystem.prepare-snapshot-to-publish.sh --print-series)

# Turn the most recent guest filesystem snapshot of ~/.marionnet/filesystems/ (a COW
# file, produced by Marionnet's disk export) into the artefacts a release directory is
# made of: the merged image named after its `sum', its .conf (checksums, MTIME and
# BINARY_LIST recomputed), its .relay when there is one, an empty _variants/ and the
# tarball the installer downloads. Nothing already there is recomputed (--force does).
# Options (another snapshot, another output directory, no sudo, no tarball): --help.
filesystem.prepare-snapshot-to-publish:
	bash Makefile.d/filesystem.prepare-snapshot-to-publish.sh --series $(PUBLICATION_SERIES)

# Put a UML kernel and its .config into the release directory, and build the tarball the
# installer downloads (kernels_<kernel>.tar.xz). The kernel is MANDATORY: unlike a
# filesystem snapshot, there is no sensible "most recent one" to guess. One kernel, one
# tarball: the i386 flavour is published by a second call. Options (another kernel
# directory, another output directory, gzip instead of xz, no tarball): --help.
kernel.prepare-to-publish:
	@test -n "$(KERNEL)" || { echo "usage: make $@ KERNEL=linux-6.12.95"; exit 2; } >&2
	bash Makefile.d/kernel.prepare-to-publish.sh --series $(PUBLICATION_SERIES) $(KERNEL)

# Maintain SHA256SUMS in the release directory -- which is not merely an integrity file
# but the CATALOGUE useful-scripts/marionnet-install.sh reads (the Apache listing being
# only its fallback). The two targets above call the script themselves for the tarball
# they have just built; this target is for the other cases: bootstrapping the file over a
# release directory published before it existed, or after an artefact was put there by
# hand. Nothing already recorded is recomputed. `make release.sha256sums CHECK=1' verifies
# the directory instead of completing it. Other options (another directory): --help.
release.sha256sums:
	bash Makefile.d/release.sha256sums.sh --series $(PUBLICATION_SERIES) $(if $(CHECK),--check)

# Turn this working copy into the third kind of artefact a release is made of: the
# application itself, precompiled. A clean build, `dune install' into a staging directory,
# the scripts of bin/scripts/ put into its bin/ (as install-final-as-root does), a
# self-contained install.sh + README, and the tarball -- recorded in SHA256SUMS like the
# other two. REFUSED while CONFIGME.choice points at the testing configuration: the prefix
# compiled into bin/meta.ml would be the opam switch (`make rebuild-for-final' first).
# Options (another output directory, gzip instead of xz, keep the staging): --help.
release-binary:
	bash Makefile.d/release.binary.sh --series $(PUBLICATION_SERIES)

# ---
.PHONY: filesystem.prepare-snapshot-to-publish kernel.prepare-to-publish release.sha256sums
.PHONY: release-binary print-required-packages-runtime


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

# install-local: install-mo
# uninstall-local: uninstall-mo

# The failsafe copy of marionnet.conf used to be produced here, by copying etc/marionnet.conf
# into a `share/' directory -- a rule already unhooked (and pointing at a directory which does
# not exist) when episode 25 of `marionnet-todo-transverse' looked at it. dune installs that
# single source directly now, see etc/dune.

# ---
PO_DIR = ./bin/po
# ---
POTGEN_TMPDIR=_build/pot/pot/default
POTGEN_MOVE_BACK=../../../..
gettext-all-ml-pot-files:
	dune build lib/gettext_extract_pot_p4.cmo
	# The snapshot below is made of HARD LINKS, and `cp -l' FAILS when the target
	# already exists: without this wipe a second run silently re-extracts the
	# PREVIOUS snapshot (measured 2026-08-12: messages.pot came back unchanged
	# while bin/ had grown seven new strings). Wiping the whole directory also
	# drops the .pot of a module that no longer exists, which msgcat would
	# otherwise still concatenate.
	@rm -rf $(POTGEN_TMPDIR)
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
