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

REQUIRED_PACKAGES = bzr glade libgtksourceview-3.0-dev opam
OPAM_PACKAGES = camlp4 utop dune odoc ocamlformat inotify conf-glade lablgtk3 lablgtk3-extras lablgtk3-sourceview3 conf-gtksourceview3
# ---
# Target version of OCaml:
OPAM_SWITCH_TO = 4.13.1

# Should be called "apt-opam-dependencies":
dependencies:
	@echo "Required packages: $(REQUIRED_PACKAGES)"
	@which dpkg 1>/dev/null || { echo "Not a Debian system (oh my god!); please install packages corresponding to: $(REQUIRED_PACKAGES)"; exit 1; }
	@echo "About to verify or install \`apt' dependencies..."
	@dpkg 1>/dev/null -l $(REQUIRED_PACKAGES) || sudo apt install -y $(REQUIRED_PACKAGES);
	@echo "About to update & upgrade opam..."
	@opam update -y && opam upgrade -y || exit 2;
	@echo "About to create or switch to the compatible OCaml compiler version $(OPAM_SWITCH_TO)"
	@opam switch $(OPAM_SWITCH_TO) &>/dev/null || opam switch create $(OPAM_SWITCH_TO) -y || exit 3;
	@echo "About to verify or install \`opam' dependencies..."
	@opam install -y $(OPAM_PACKAGES) || exit 4;
	@echo '[WARNING] You should run: eval $$(opam env) to synchronize the environment with the current switch.'
	@echo "Success."

# Just switch with opam to the correct version of OCaml:
switch:
	@echo "About to create or switch to the compatible OCaml compiler version $(OPAM_SWITCH_TO)"
	@opam switch $(OPAM_SWITCH_TO) &>/dev/null || opam switch create $(OPAM_SWITCH_TO) -y || exit 3;
	@echo "About to verify or install \`opam' dependencies..."
	@opam install -y $(OPAM_PACKAGES) || exit 4;
	@echo '[WARNING] You should run: eval $$(opam env) to synchronize the environment with the current switch.'
	@echo "Success."


# =============================================================
#                           main
# =============================================================
# PP_OPTION = camlp4of $(OCAML4_02_OR_LATER) $(OCAML4_04_OR_LATER) -I $(OCAMLBRICKS) gettext_extract_pot_p4.cmo option_extract_p4.cmo raise_p4.cmo

main-no-build:
	make -C lib main-no-build
	mkdir -p _build
	find ./lib/_build/ -maxdepth 1 -type f -exec cp -lf {} _build/ \;
	@(echo "Success.")

all: meta main-no-build
	dune build --always-show-command-line

rebuild:
	make -C lib/ clean && make clean && make all

meta: bin/version.ml bin/meta.ml

# For testing:
run:
	_build/default/bin/marionnet.exe -d

# =============================================================
#                         install
# =============================================================

INSTALL_PREFIX=/usr/local
install-final:
	test $$(readlink "CONFIGME.choice") = "CONFIGME" || make rebuild-for-final
	dune install --prefix $(INSTALL_PREFIX)

TMPSCRIPT=_build/make_install_as_root.sh
install-final-as-root:
	test $$(readlink "CONFIGME.choice") = "CONFIGME" || make rebuild-for-final
	echo '#!/bin/bash' > $(TMPSCRIPT)
	echo $$(opam env) >> $(TMPSCRIPT)
	echo "dune install --prefix $(INSTALL_PREFIX)" >> $(TMPSCRIPT)
	chmod +x $(TMPSCRIPT)
	sudo $(TMPSCRIPT)
	rm -f $(TMPSCRIPT)
	@echo "Success."

# Alias:
install: install-final-as-root

# ---
# Rebuild and install the project in the opam directory for testing/debugging:
INSTALL_PREFIX_FOR_TESTING=$(shell echo $$OPAM_SWITCH_PREFIX)/share/marionnet
INSTALLED_FILESYSTEMS=$(INSTALL_PREFIX)/share/marionnet/filesystems
INSTALLED_KERNELS=$(INSTALL_PREFIX)/share/marionnet/kernels
# ---
install-for-testing:
	test $$(readlink "CONFIGME.choice") = "CONFIGME.testing.sh" || make rebuild-for-testing
	dune install
	@echo "---"
	@echo mkdir -p $(INSTALL_PREFIX_FOR_TESTING)/filesystems $(INSTALL_PREFIX_FOR_TESTING)/kernels
	@for i in $(wildcard $(INSTALLED_FILESYSTEMS)/*); do ln -sf $$i $(INSTALL_PREFIX_FOR_TESTING)/filesystems/; done
	@for i in $(wildcard $(INSTALLED_KERNELS)/*);     do ln -sf $$i $(INSTALL_PREFIX_FOR_TESTING)/kernels/; done
	@echo "---"
	which marionnet
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

EXCLUDE_FROM_EDITING=-o -name "meta.ml" -o -name "version.ml"
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



# =============================================================
#                Manual setting and compilation
# =============================================================

# Transmit the information about the compiler version in order to
# activate conditional compilation:
PP_OPTION = camlp4of -DOCAML4_OR_LATER -DOCAML4_02_OR_LATER -DOCAML4_03_OR_LATER -DOCAML4_04_OR_LATER -DOCAML4_07_OR_LATER
# ---
GETTEXT=GETTEXT
C_OBJECTS_TO_LINK = gettext-c-wrapper does-process-exist-c-wrapper waitpid-c-wrapper
OTHER_LIBRARY_FILES_TO_INSTALL = _build/{gettext-c-wrapper.o,does-process-exist-c-wrapper.o,gettext_extract_pot_p4.cmo,waitpid-c-wrapper.o,include_type_definitions_p4.cmo,include_as_string_p4.cmo,where_p4.cmo,option_extract_p4.cmo,raise_p4.cmo,log_module_loading_p4.cmo}

# Build C modules (no one, by default):
c-modules:
	@(mkdir _build &> /dev/null || true) && \
	for x in $(C_OBJECTS_TO_LINK); do \
	  make _build/$$x.o; \
	done

##################################
#    Manually generated files    #
# (i.e. not generated with dune) #
##################################

# Example:
#
# foo.byte   : manually_pre_actions
# foo.native : manually_pre_actions
#
# MANUALLY_PRE_COPY_IN_build = include_as_string_p4.ml USAGE.txt
# MANUALLY_PRE_MAKE_IN_build = include_as_string_p4.cmo
#
# _build/include_as_string_p4.cmo: include_as_string_p4.ml
#	ocamlc -c -I +camlp4 camlp4lib.cma -pp camlp4of -o $@ $<

.PHONY : manually_pre_actions

################################# PRE-ACTIONS support

# Files that must be copied in _build/ *before* the dune processing:
MANUALLY_PRE_COPY_IN_build =     \
  GETTEXT/gettext_extract_pot_p4.ml{,i} \
  GETTEXT/gettext-c-wrapper.c \
  EXTRA/does-process-exist-c-wrapper.c \
  EXTRA/waitpid-c-wrapper.c \
  CAMLP4/include_type_definitions_p4.ml{,i} \
  CAMLP4/include_as_string_p4.ml{,i} \
  CAMLP4/where_p4.ml{,i} \
  CAMLP4/option_extract_p4.ml{,i} \
  CAMLP4/common_tools_for_preprocessors.ml{,i} \
  CAMLP4/raise_p4.ml{,i} \
  CAMLP4/log_module_loading_p4.ml{,i}

# Targets that must be created in _build/ *before* the dune processing.
# For each foo.bar that appears in this list, you have to write a rule
# _build/foo.bar in this Makefile
MANUALLY_PRE_MAKE_IN_build =      \
  gettext_extract_pot_p4.cm{i,o} \
  include_type_definitions_p4.cm{i,o} \
  include_as_string_p4.cm{i,o} \
  where_p4.cm{i,o} \
  option_extract_p4.cm{i,o} \
  raise_p4.cm{i,o} \
  log_module_loading_p4.cm{i,o} \
  libocamlbricks_stubs.a


# include_type_definitions_p4
_build/include_type_definitions_p4.cmi: CAMLP4/include_type_definitions_p4.mli
	ocamlc -c -I +camlp4 -pp '$(PP_OPTION)' -o $@ $<

_build/include_type_definitions_p4.cmo: CAMLP4/include_type_definitions_p4.ml
	ocamlc -c -I +camlp4 -I _build/ -pp '$(PP_OPTION)' -o $@ $<

# include_as_string_p4
_build/include_as_string_p4.cmi: CAMLP4/include_as_string_p4.mli
	ocamlc -c -I +camlp4 -pp '$(PP_OPTION)' -o $@ $<

_build/include_as_string_p4.cmo: CAMLP4/include_as_string_p4.ml
	ocamlc -c -I +camlp4 -I _build/ -pp '$(PP_OPTION)' -o $@ $<

# where_p4
_build/where_p4.cmi: CAMLP4/where_p4.mli
	ocamlc -c -I +camlp4 -pp camlp4of -o $@ $<

_build/where_p4.cmo: CAMLP4/where_p4.ml
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of -o $@ $<

# option_extract_p4
_build/option_extract_p4.cmi: CAMLP4/option_extract_p4.mli
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of -o $@ $<

_build/option_extract_p4.cmo: CAMLP4/option_extract_p4.ml
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of -o $@ $<

# raise_p4
_build/raise_p4.cmi: CAMLP4/raise_p4.mli
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of -o $@ $<

_build/raise_p4.cmo: CAMLP4/raise_p4.ml
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of -o $@ $<

# log_module_loading_p4
_build/log_module_loading_p4.cmi: CAMLP4/log_module_loading_p4.mli
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of -o $@ $<

_build/log_module_loading_p4.cmo: CAMLP4/log_module_loading_p4.ml
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of -o $@ $<

# gettext_extract_pot_p4
_build/gettext_extract_pot_p4.cmi: $(GETTEXT)/gettext_extract_pot_p4.mli
	ocamlc -c -I +camlp4 -pp camlp4of camlp4lib.cma -o $@ $<

_build/gettext_extract_pot_p4.cmo: $(GETTEXT)/gettext_extract_pot_p4.ml
	ocamlc -c -I +camlp4 -I _build/ -pp camlp4of camlp4lib.cma -o $@ $<

# Compile gettext-c-wrapper.c according to the OCaml version:
ccopt_OCAML4_07_OR_LATER := -verbose -ccopt -DOCAML4_07_OR_LATER

# stubs
_build/libocamlbricks_stubs.a: $(GETTEXT)/gettext-c-wrapper.c  EXTRA/does-process-exist-c-wrapper.c  EXTRA/waitpid-c-wrapper.c
	@(mkdir _build &> /dev/null || true); \
	cd _build; \
	ocamlc -c $(ccopt_OCAML4_07_OR_LATER) $(GETTEXT)/gettext-c-wrapper.c; \
	ocamlc -c -verbose EXTRA/does-process-exist-c-wrapper.c; \
	ocamlc -c -verbose EXTRA/waitpid-c-wrapper.c; \
	ocamlmklib -verbose -oc ocamlbricks_stubs gettext-c-wrapper.o does-process-exist-c-wrapper.o waitpid-c-wrapper.o

# ---
manually_pre_actions: bin/version.ml bin/meta.ml
	$(call PERFORM_MANUALLY_PRE_ACTIONS, $(MANUALLY_PRE_COPY_IN_build),$(MANUALLY_PRE_MAKE_IN_build))

# Detect if "make clean" is required or copy and build manually targets
# specified in MANUALLY_PRE_COPY_IN_build and MANUALLY_PRE_MAKE_IN_build
PERFORM_MANUALLY_PRE_ACTIONS = \
	@(\
	if test -d _build/; \
	then \
	  echo "Checking if files manually copied in _build/ have been modified..."; \
	  for x in $(1); do \
	    echo "Checking \"$$x\"..."; \
	    test ! -f _build/$$x || \
	       diff -q $$x _build/$$x 2>/dev/null || \
	       { echo -e "********************\nmake clean required!\n********************"; exit 1; } ;\
	  done; \
	else \
	  mkdir _build/; \
	fi; \
	for x in $(1); do echo "Manually pre-copying \"$$x\"...";  cp --parent -f $$x _build/; done; \
	for y in $(2); do echo "Manually pre-building \"$$y\"..."; make _build/$$y || exit 1; done; \
	)

#####################
#  META and VERSION #
#####################

# version.ml is automatically generated:
bin/version.ml:
	chmod +x "./bin/version.ml.maker.sh"
	$@.maker.sh ./META $@

# meta.ml is automatically generated (according to the choice of final/testing installation):
bin/meta.ml:
	chmod +x "./bin/meta.ml.maker.sh"
	$@.maker.sh ./META ./CONFIGME.choice $@
