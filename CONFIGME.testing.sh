#!/bin/bash

# This -*- sh -*- script is part of the Marionnet project
# Copyright (C) 2023 Jean-Vincent Loddo

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
# This file should be source, but it can be called
# as a standalone script for debugging:
[[ "$0" = "$BASH_SOURCE" ]] && set -x

# ---
# Start restoring the opam env:
eval $(opam env)
# ---
# The effect is something like this:
# OPAM_SWITCH_PREFIX='/home/jean/.opam/4.13.1';
# CAML_LD_LIBRARY_PATH='/home/jean/.opam/4.13.1/lib/stublibs:/home/jean/.opam/4.13.1/lib/ocaml/stublibs:/home/jean/.opam/4.13.1/lib/ocaml';
# OCAML_TOPLEVEL_PATH='/home/jean/.opam/4.13.1/lib/toplevel';
# PKG_CONFIG_PATH='/home/jean/.opam/4.13.1/lib/pkgconfig:';
# MANPATH='/usr/local/man:/usr/local/share/man:/usr/man:/usr/share/man:/home/jean/.opam/4.13.1/man';
# PATH='/home/jean/.opam/4.13.1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:';

# ---
# Run-time prefix, where resources will be really installed and available
# when the software will be launched. Examples are /usr or /usr/local.
# *No* trailing slash should be included.
prefix=${OPAM_SWITCH_PREFIX}  # /usr/local

# ---
# Prefix for temporary or final installation; you should probably keep the
# default setting, which is ${prefix}. This variable has been introduced to
# deal with some specific packaging methods (Archlinux).
# *No* trailing slash should be included.
prefix_install=${prefix}

# ---
# Prefix for host-wide configuration files; you should probably keep the
# default setting:
configurationprefix=$prefix/marionnet/etc  # /etc

# ---
# Prefix for the locale files (at run-time)
localeprefix=${prefix}/share/locale

# ---
# Prefix for documentation files; you should probably keep the
# default setting:
documentationprefix=${prefix}/share/doc

# ---
# Version of OCaml we are using to compile the project:
ocaml_version=$(ocamlc -version || exit -1)

# ---
# Location of the standard Ocaml libraries required to compile
# and link the project.
# *No* trailing slash should be included.
ocaml_libraryprefix=$(ocamlc -where || exit -1)

# ---
# Installation prefix for OCaml libraries built by the project.
# By default they will be installed into the same directory of the `lablgtk3'
# library or into ${ocaml_libraryprefix}, but you  can change it if you really
# want to install into a different, custom prefix.
# *No* trailing slash should be included.
libraryprefix=$(which 1>/dev/null ocamlfind && ocamlfind query lablgtk3)
libraryprefix=${libraryprefix%/lablgtk3}
libraryprefix=${libraryprefix:-$ocaml_libraryprefix}

# This should be defined as the absolute path to a directory containing
# the already configured OCaml source; in alternative, is your GNU/Linux
# distribution packages OCaml headers (debian and its offspring install
# headers in /usr/include/caml), you can set this to the full path of
# the directory containing OCaml headers.
ocaml_sources=${ocaml_libraryprefix}/caml
