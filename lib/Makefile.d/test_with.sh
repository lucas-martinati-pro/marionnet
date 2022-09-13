#!/bin/bash

#    This file is part of our reusable OCaml BRICKS library
#    Copyright (C) 2013  Jean-Vincent Loddo
#    Copyright (C) 2013  Université Paris 13
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

TOPLEVEL=${1:-utop}
# ---
if [[ $2 = "lablgtk2" || $2 = "widgets" ]]; then
  TEST_WIDGETS='
#require "lablgtk2.auto-init";;
let window = GWindow.window ~width:400 ~height:800 ~title:"Testing" ~border_width:10 ();;
let _ = window#connect#destroy ~callback:GMain.Main.quit ;;
let vbox = GPack.vbox ~packing:window#add () ;;
let packing = vbox#pack ~padding:5 ;;
let main () = let () = window#show () in GMain.main () ;;
let t = Thread.create main () ;;
let () = Printf.printf "---
You can create and try widgets simply in this way:
(defined objects are: window vbox packing)
---
let b = GButton.button ~packing ~label:\"my text\" () ;;
---";;
'
fi

which $TOPLEVEL &>/dev/null || {
  echo "Error: $0: $TOPLEVEL not found; install it please."
  exit 2
}

FLATTENED_DIRECTORY=_build/_build.flattened
if [[ ! -d $FLATTENED_DIRECTORY ]]; then
  mkdir -p $FLATTENED_DIRECTORY
  find _build -path $FLATTENED_DIRECTORY -prune -o -type f -exec cp -fl {} $FLATTENED_DIRECTORY/ \;
fi

PREAMBLE=$(mktemp)
cat > $PREAMBLE  <<EOF
Printexc.record_backtrace true;;
Ocamlbricks_log.enable ();;
$TEST_WIDGETS
EOF

export OCAMLRUNPARAM=-b
LIBRARYPREFIX=${CAML_LD_LIBRARY_PATH%stublibs}
if [[ ! -d "$LIBRARYPREFIX" ]]; then
  LIBRARYPREFIX=$(find $(ocamlc -where)/.. -type d -name "lablgtk2")
  LIBRARYPREFIX=${LIBRARYPREFIX%lablgtk2}
fi

# ---
cd $FLATTENED_DIRECTORY
case "$TOPLEVEL" in

  utop)
	CMD="utop -I +threads -I $LIBRARYPREFIX/lablgtk2 -I . str.cma lablgtk.cma ./ocamlbricks.cma -init $PREAMBLE"
	$CMD || CODE=$?
        ;;

 ocaml)
	CMD="ocaml -I +threads -I $LIBRARYPREFIX/lablgtk2 -I . str.cma unix.cma threads.cma lablgtk.cma ./ocamlbricks.cma -init $PREAMBLE"
	if which rlwrap >/dev/null; then
	  rlwrap $CMD || CODE=$?
	else
	  echo "Suggestion: install rlwrap for testing with readline (on a debian/ubuntu: apt-get install rlwrap)"
	  $CMD || CODE=$?
	fi
	;;
esac

rm -f $PREAMBLE
exit $CODE
