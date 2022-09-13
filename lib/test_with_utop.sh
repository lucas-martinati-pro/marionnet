#!/bin/bash

set -e

# In order to have several terminal for testing:
unset SKIP_FIRST_STEPS
if [[ $1 = "-s" || $1 = "--skip" || $1 = "--skip-first" ]]; then
  SKIP_FIRST_STEPS=y
  shift
fi

unset CALLER
if [[ $1 = "-c" || $1 = "--caller" ]]; then
  CALLER=$2
  shift 2
fi

TOPLEVEL=${1:-utop}

which $TOPLEVEL &>/dev/null || {
  echo "Error: $0: $TOPLEVEL not found; install it please."
  exit 2
}

FLATTENED_DIRECTORY=_build/_build.flattened
mkdir -p $FLATTENED_DIRECTORY

# ---
if [[ $SKIP_FIRST_STEPS != y ]]; then

  # make?
  if [[ ! $CALLER = "make" ]]; then
    make compile_for_testing rebuilding
    mkdir -p $FLATTENED_DIRECTORY
  fi

  # Copy all modules (not really copies but hard links) to a single directory:
  find _build -path $FLATTENED_DIRECTORY -prune -o -type f -exec cp -fl {} $FLATTENED_DIRECTORY/ \;
fi
# ---

# Preamble:
PREAMBLE=$(mktemp)
cat > $PREAMBLE  <<EOF
(* --- *)
#load "str.cma";;
#load "unix.cma";;
(* --- *)
#directory "+threads";;
#load "threads.cma";;
(* --- *)
#require "lablgtk2";;
#load "lablgtk.cma";;
(* --- *)
#require "inotify";;
#load "inotify.cma";;
(* --- *)
#load "./ocamlbricks.cma";;
Ocamlbricks_log.enable ();;
(* --- *)
Printexc.record_backtrace true;;
EOF

export OCAMLRUNPARAM=-b
# ---
cd $FLATTENED_DIRECTORY

# Go:
utop -init $PREAMBLE || CODE=$?
rm -f $PREAMBLE
exit $CODE
