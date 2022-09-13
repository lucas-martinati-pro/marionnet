(*  This file is part of our reusable OCaml BRICKS library
    Copyright (C) 2013  Jean-Vincent Loddo

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.*)

(** Automatically generate a file <source>.ml.pot during the <source>.ml parsing.

Example (in your Makefile):
---------------------------

PP_OPTIONS=camlp4of -I +ocamlbricks gettext_extract_pot_p4.cmo

# A file <source>.ml.pot will be generated for each compiled <source>.ml
target:
	ocamlc -c -pp "$PP_OPTIONS" ...

# Supposing we are working with ocamlbuild:
_build/target.pot: target.byte
	@msgcat -s --use-first $(shell find _build/ -name "*.ml.pot") > $@

*)
