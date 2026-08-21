#!/bin/bash
# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Jean-Vincent Loddo
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

# ---
# camlp4 front-end for `codept', to be used as `codept -pp <this script> ...'.
# Marionnet's sources are not plain OCaml (WHERE, IFDEF/ELSE/ENDIF, INCLUDE_*),
# so any source-level analyser must see them through camlp4 first.
#
# Three facts drive the shape of this script; all three were measured, and each
# one silently produces garbage or a fatal error if ignored:
#
#   1. camlp4of infers implementation vs interface FROM THE EXTENSION, and
#      refuses a file that has none ("don't know what to do with ..."), so the
#      choice is made explicit here with -impl / -intf.
#
#   2. Without `-printer o', camlp4of emits a MARSHALLED ast.  ocamlc accepts
#      that form (this is what bin/dune and lib/dune rely on), codept does not:
#      it re-reads it as text and dies on "Illegal character (\132)".
#
#   3. codept applies the preprocessor TWICE: once to the real source file,
#      then a second time to the temporary file holding the output of the first
#      pass (verified by logging the calls).  That second file is already plain
#      OCaml -- and re-running camlp4 on it is not merely wasteful, it FAILS on
#      some units, because camlp4's original-syntax printer emits constructs its
#      own parser rejects (e.g. `(object ... end : <class type>)' in bin/disk.ml
#      -> "Parse error: [class_type] expected after \":\" (in [class_expr])").
#      Hence: an input with no .ml/.mli extension is passed through untouched.
#
# The camlp4 recipe must stay in sync with the (preprocess (action ...)) stanzas
# of bin/dune and lib/dune: same -D flags -- single source of truth,
# lib/camlp4of-flags.cfg -- and same globally loaded syntax extensions.  The -I
# is what lets camlp4of find them, and also the per-file `#load "where_p4.cmo"'.
#
# Mind the ASYMMETRY between the two stanzas, which this script reproduces:
# bin/dune loads three GLOBAL filters (option_extract_p4, raise_p4 and
# log_module_loading_p4), lib/dune loads NONE -- there, camlp4of is invoked with
# the -I and the -D flags only.  Loading them for lib/ too is not harmless:
# log_module_loading_p4 prepends `Marionnet_log.printf1 "Loading module ..."' to
# every unit, which invents a dependency towards Marionnet_log for each of the
# ~90 modules of ocamlbricks -- a dependency dune's own ocamldep does not have.
# ---

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LIB_BUILD="$ROOT/_build/default/lib"
FLAGS_CFG="$ROOT/lib/camlp4of-flags.cfg"

input="${1:?usage: $0 <file>}"

# --- Second pass of codept: already preprocessed, hand it back unchanged.
case "$input" in
  *.ml|*.mli) ;;
  *) exec cat -- "$input" ;;
esac

[[ -f "$FLAGS_CFG" ]] || { echo "$0: missing $FLAGS_CFG" >&2; exit 2; }
[[ -f "$LIB_BUILD/where_p4.cmo" ]] || {
  echo "$0: missing $LIB_BUILD/where_p4.cmo -- run 'dune build lib/where_p4.cmo' first" >&2
  exit 2
}

# One -D flag per line in the .cfg:
mapfile -t FLAGS < "$FLAGS_CFG"

case "$input" in
  *.mli) KIND=-intf ;;
  *)     KIND=-impl ;;
esac

# Global filters: bin/ only -- see the ASYMMETRY note above.
FILTERS=()
case "$(cd -- "$(dirname -- "$input")" && pwd)/" in
  "$ROOT/bin/"*) FILTERS=(option_extract_p4.cmo raise_p4.cmo log_module_loading_p4.cmo) ;;
esac

exec camlp4of -printer o -I "$LIB_BUILD" "${FLAGS[@]}" \
     ${FILTERS[@]+"${FILTERS[@]}"} "$KIND" "$input"
