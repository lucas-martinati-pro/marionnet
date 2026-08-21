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
# Inter-module dependency graph of the whole tree (bin/ + lib/ + the generated
# i18n/Locations.ml), computed by `codept' seen through camlp4 (Makefile.d/codept-pp.sh).
#
# Why codept and not `ocamldep' / dune's own dependency files: ocamldep is purely
# syntactic, so (a) it collapses every reference to a module of the ocamlbricks
# library into the single wrapper name `Ocamlbricks', and (b) it misses the
# dependencies induced by a SIGNATURE (Cage uses Channel, whose interface exposes
# Res / Lock_clubs / Hashset: the compiler must load those .cmi, ocamldep does not
# say so).  codept resolves both.  Measured against dune's own ocamldep output
# (_build/**/*.impl.d), this graph has 100% recall -- it contains every edge dune
# knows about -- plus ~320 finer bin->ocamlbricks edges; `--check' recomputes that
# comparison.
#
# Usage:  Makefile.d/module-graph.sh [--check] [--outdir DIR]
# ---

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

OUTDIR="$ROOT/_build/module-graph"
CHECK=0
while (($#)); do
  case "$1" in
    --check)  CHECK=1; shift ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help) sed -n '/^# Usage:/p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "$0: unknown option '$1'" >&2; exit 2 ;;
  esac
done

command -v codept >/dev/null || { echo "$0: codept not found (opam install codept)" >&2; exit 2; }

# ---
# --- 1. Build what the analysis needs: the camlp4 filters loaded by codept-pp.sh,
# ---    and the generated module of the marionnet_sites library.
# ---
echo "==> dune build (camlp4 preprocessors + generated modules)"
dune build \
  lib/option_extract_p4.cmo lib/raise_p4.cmo lib/log_module_loading_p4.cmo \
  lib/where_p4.cmo lib/include_type_definitions_p4.cmo lib/include_as_string_p4.cmo \
  i18n/Locations.ml

# ---
# --- 2. The unit lists, mirroring the dune stanzas.
# ---
# Only implementations: a .mli restricts what a module EXPORTS, so feeding both
# makes codept report the (much poorer) interface dependencies instead of the real
# ones -- measured: 66 edges with the .mli, 250 without, on lib/ alone.
# The modules excluded below are the camlp4 syntax extensions themselves, which
# lib/dune also excludes from the ocamlbricks library (they are build tools, and
# they depend on Camlp4, not on the project).
# ---
P4_MODULES='common_tools_for_preprocessors|include_as_string_p4|include_type_definitions_p4|option_extract_p4|log_module_loading_p4|raise_p4|where_p4|gettext_extract_pot_p4'

mapfile -t LIB_ML < <(find lib -name '*.ml' | grep -vE "/($P4_MODULES)\.ml$" | sort)
mapfile -t BIN_ML < <(find bin -name '*.ml' | sort)
SITES_ML=_build/default/i18n/Locations.ml

((${#LIB_ML[@]})) || { echo "$0: no lib/*.ml found" >&2; exit 2; }
((${#BIN_ML[@]})) || { echo "$0: no bin/*.ml found" >&2; exit 2; }

# codept "file groups": Ocamlbricks[a.ml,b.ml] maps a.ml to the module path
# Ocamlbricks.A, which is exactly how dune's WRAPPED libraries name them and how
# bin/ refers to them (module StringExtra = Ocamlbricks.StringExtra).
join_by_comma() { local IFS=,; echo "$*"; }
LIB_GROUP="Ocamlbricks[$(join_by_comma "${LIB_ML[@]}")]"
SITES_GROUP="Marionnet_sites[$SITES_ML]"

# -open Ocamlbricks: inside a wrapped library the modules see each other
# unqualified, and dune achieves this by passing -open to every unit of the
# library.  Without it, no edge INSIDE ocamlbricks is resolved.
CODEPT_OPTS=(-pp "$ROOT/Makefile.d/codept-pp.sh"
             -k -verbosity error
             -no-implicits          # do not pull the .mli of a given .ml
             -expand-deps           # exact dependencies, not a transitively reduced subset
             -open Ocamlbricks)

mkdir -p "$OUTDIR"
DOT="$OUTDIR/module-graph.dot"
SVG="$OUTDIR/module-graph.svg"
DEPS="$OUTDIR/module-graph.deps"

echo "==> codept: ${#LIB_ML[@]} modules in lib/, ${#BIN_ML[@]} in bin/, 1 generated"
codept "${CODEPT_OPTS[@]}" "$LIB_GROUP" "$SITES_GROUP" "${BIN_ML[@]}" -dot > "$DOT.raw"
codept "${CODEPT_OPTS[@]}" "$LIB_GROUP" "$SITES_GROUP" "${BIN_ML[@]}" -modules > "$DEPS"

# codept's raw dot output is not usable as such: group-qualified names
# (Ocamlbricks.Cortex) are printed UNQUOTED, which graphviz rejects ("syntax error
# near '.'"), the qualification is applied to some modules only, and a name that
# clashes with a dot keyword comes back already quoted ("Graph").  So it is
# normalised here: one node = one short module name (basenames are unique across
# bin/ and lib/ -- checked), quoted, and coloured by the dune stanza it belongs to.
module_name_of() { basename "$1" .ml | sed 's/^\(.\)/\U\1/'; }
: > "$OUTDIR/.modules"
for f in "${LIB_ML[@]}"; do printf 'lib\t%s\n' "$(module_name_of "$f")"; done >> "$OUTDIR/.modules"
for f in "${BIN_ML[@]}" "$SITES_ML"; do printf 'bin\t%s\n' "$(module_name_of "$f")"; done >> "$OUTDIR/.modules"

awk -v modfile="$OUTDIR/.modules" '
  function clean(s) { gsub(/"/, "", s); sub(/^Ocamlbricks\./, "", s); sub(/^Marionnet_sites\./, "", s); return s }
  BEGIN {
     FS = "\t"
     while ((getline line < modfile) > 0) {
        split(line, p, "\t")
        if (p[1] == "lib") is_lib[p[2]] = 1
        seen[p[2]] = 1          # an isolated module must appear too
     }
     FS = " "
  }
  /->/ {
     a = clean($1); b = clean($3)
     seen[a] = 1; seen[b] = 1
     key = a SUBSEP b
     if (!(key in done)) { done[key] = 1; edges[++n] = "  \"" a "\" -> \"" b "\";" }
  }
  END {
     print "digraph G {"
     # Top-to-bottom and merged parallel edges: on this graph (156 nodes, ~975
     # edges) it gives a 8400x2000pt sheet, against 3500x14500 with rankdir=LR.
     print "  rankdir=TB; concentrate=true; ranksep=0.6; nodesep=0.15;"
     print "  node [shape=box, style=filled, fontname=\"sans\", fontsize=10];"
     for (m in seen) {
        c = (m in is_lib) ? "\"#cfe8cf\"" : "\"#cfd8e8\""   # ocamlbricks : bin/
        print "  \"" m "\" [fillcolor=" c "];"
     }
     for (i = 1; i <= n; i++) print edges[i]
     print "}"
  }
' "$DOT.raw" > "$DOT"
rm -f "$DOT.raw" "$OUTDIR/.modules"

if command -v dot >/dev/null; then
  dot -Tsvg "$DOT" -o "$SVG"
else
  echo "    (graphviz absent: $SVG not produced)" >&2
  SVG='(not produced)'
fi

EDGES=$(grep -c -- ' -> ' "$DOT" || true)
NODES=$(grep -c -- 'fillcolor=' "$DOT" || true)
SOURCES=$(awk -F'"' '/ -> /{print $2}' "$DOT" | sort -u | wc -l)

echo "==> $DOT"
echo "    $SVG"
echo "    $DEPS   (one line per unit, greppable)"
echo "    nodes: $NODES   edges: $EDGES   modules with at least one dependency: $SOURCES"

((CHECK)) || exit 0

# ---
# --- 3. Cross-check against dune's own ocamldep output (post-camlp4), which is
# ---    written as a side effect of the build in _build/**/*.impl.d.
# ---    Requires a build that compiled every module, i.e. `dune build @check'.
# ---
echo "==> cross-check against dune's ocamldep (_build/**/*.impl.d)"
python3 - "$DOT" <<'PY'
import os, re, sys
dot = sys.argv[1]
gt, srcs = set(), set()
files = [os.path.join(r, f)
         for r, _, fs in os.walk('_build/default') for f in fs if f.endswith('.impl.d')]
for f in files:
    txt = open(f).read().strip()
    if not txt:
        continue
    left, _, right = txt.partition(':')
    src = os.path.basename(left).replace('.pp.ml', '').replace('.ml', '')
    src = src[:1].upper() + src[1:]
    srcs.add(src)
    gt.update((src, m) for m in right.split())

short = lambda x: x.split('.')[-1]
cp = set()
for line in open(dot):
    m = re.match(r'\s*"?([\w.]+)"?\s*->\s*"?([\w.]+)"?', line)
    if m:
        cp.add((short(m.group(1)), short(m.group(2))))

nodes = {a for a, _ in cp} | {b for _, b in cp}
common = srcs & nodes
GT = {e for e in gt if e[0] in common and e[1] in nodes}
CP = {e for e in cp if e[0] in common and e[1] in nodes}
inter = GT & CP
print("    .impl.d files: %d   modules compared: %d" % (len(files), len(common)))
print("    ocamldep edges: %d   codept edges: %d   common: %d" % (len(GT), len(CP), len(inter)))
print("    edges MISSED by codept: %d   (recall %.1f%%)"
      % (len(GT - inter), 100.0 * len(inter) / len(GT) if GT else 0.0))
print("    edges codept adds: %d   (finer bin->ocamlbricks resolution + signature-level deps)"
      % len(CP - GT))
for e in sorted(GT - CP)[:20]:
    print("      missed: %s -> %s" % e)
sys.exit(1 if GT - CP else 0)
PY
