# This -*- makefile -*- is part of our build system for OCaml projects
# Copyright (C) 2022  Jean-Vincent Loddo

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

# Version of ocamlbricks project corresponding
# to the content of our local copy ocamlbricks/
OCAMLBRICKS_ORIGINAL_REVNO=560

# Makefiles (this one as those in other parts) use extensively the bash shell
SHELL=/bin/bash

##############
#    main    #
##############

# The main target. Its implementation is entirely project-dependant:
main: manually_pre_actions c-modules
	dune build --release
	@(echo "Success.")

# The main target. Its implementation is entirely project-dependant:
main-dev: manually_pre_actions c-modules
	dune build
	@(echo "Success.")

main-no-build: manually_pre_actions c-modules
	@(echo "Success.")

##############
#    edit    #
##############

EXCLUDE_FROM_EDITING=-o -name "meta.ml" -o -name "version.ml" -o -name "gui.ml"
INCLUDE_FOR_EDITING=-o -name "dune-project" -o -name "Makefile" -o -name "dune"

# Edit all ml/mli files and other interesting source files with your $EDITOR
edit:
	test -n "$$EDITOR" && \
	eval $$EDITOR $$(find . \( -name "_build*" $(EXCLUDE_FROM_EDITING) \) -prune -o -type f -a \( -name "*.ml" -o -name "*.mli" $(INCLUDE_FOR_EDITING) \) -print) &


##############
#   help     #
##############

ocamlc-warn-help:
	ocamlc -warn-help

##############
#   clean    #
##############

clean:
	@(dune clean && rm -rf _build/; \
	echo "Success.")


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
manually_pre_actions:
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
