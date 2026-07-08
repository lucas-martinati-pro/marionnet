# Copyright (C) 2026  Jean-Vincent Loddo
# Copyright (C) 2026  Université numérique Île-de-France
# Copyright (C) 2026  Université Sorbonne Paris Nord
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
# Description:
#   This file is a Bash library designed to be sourced (using the `source`
#   command) by interactive shells or scripts. It simplifies the use of 
#   regular arrays and associative arrays (maps), and provides high-level 
#   tools for controlled job scheduling based on the concept of "futures".
#
#   It provides a set of structured "pseudo-modules" such as:
#  
#     - Array_*   : helpers for indexed arrays (Array_make, Array_map, ...)
#     - Map_*     : helpers for associative arrays / maps (Map_make, Map_find, ...)
#     - Set_*     : helpers for sets (implemented as associative arrays)
#     - Future_*  : helpers for asynchronous computations ("futures")
#     - Function_*: helpers for defining, cloning and composing Bash functions
#     - (other modules plus several lower-level tools: channels, predicates, regexp helpers, ...)
#
#   Once the file is sourced, every function Module_f is also available
#   under an alias Module.f, in a style reminiscent of the OCaml module
#   notation. For example:
#       Array_make  xs 10 20 30
#       Array.make  xs 10 20 30   # alias for Array_make
#
#   The whole library is designed with a functional spirit in mind
#   (persistence of values, explicit destinations) rather than a
#   purely imperative one. Most "updating" operations build new
#   values instead of mutating in-place. For instance:
#       Array_map ORIG DEST func
#   constructs a new array DEST by applying func to all elements of ORIG,
#   leaving ORIG unchanged.
#
#   For each pseudo-module, a dedicated help function is available and
#   prints detailed documentation and examples:
#       Array_help     # documentation for Array_*
#       Float_help     # documentation for Float_*
#       Future_help    # documentation for Future_*
#       Function_help  # documentation for Function_*
#       Int_help       # documentation for Int_*
#       Json_help      # documentation for Json_*
#       Map_help       # documentation for Map_*
#       Path_help      # documentation for Path_*
#       Regexp_help    # documentation for Regexp_*
#       Set_help       # documentation for Set_*
#       String_help    # documentation for Set_*
#
#   Beyond regular and associative arrays, the library also includes:
#     - controlled job scheduling based on "futures" (Future_make,
#       Future_touch, and their higher-level wrappers),
#     - helpers for parallel iteration and mapping over arrays,
#     - utilities for manipulating Bash function definitions and
#       generating fresh function names.
#
#   The goal is to make non-trivial shell scripts more modular,
#   compositional and reliable, while staying within plain Bash.
# ---

### ---------------------------------------------
###       Internal variable naming policy
### ---------------------------------------------
#
# This library makes heavy use of Bash features such as local variables,
# namerefs (`local -n` / `declare -n`), indirect expansions, dynamically built
# references, and occasional `eval`-based assignments. In plain Bash, these
# mechanisms can lead to subtle name clashes when an internal helper variable
# happens to use the same name as a variable defined by the caller or by user
# code executed through callbacks.
#
# In practice, the problem is not limited to "global" namespace pollution:
# clashes may also happen inside function scope, especially when a function
# manipulates variable names explicitly or receives names/references as
# arguments. With namerefs in particular, reusing an ordinary local name can
# produce ambiguous or circular reference behavior that is difficult to debug.
#
# To reduce this risk, all internal local variables of bashbricks are prefixed
# with `__bb_`. This prefix is reserved for the implementation of the library
# and should not be used by application code. The goal is to provide a private,
# library-specific namespace for temporary variables such as:
#
#   __bb_USAGE, __bb_NAME, __bb_KEY, __bb_TMPFILE, __bb_FNAME, ...
#
# This convention does not change Bash scoping rules, but it drastically lowers
# the probability of accidental collisions and makes internal variables easy to
# identify during maintenance, debugging, and code review. It is therefore part
# of the defensive programming style of this library.

### ---------------------------------------------
###         Options ordering convention
### ---------------------------------------------
###
### All options of functions MUST be supplied in strict alphabetical order 
### when several are combined.
### For instance, in the case of function `Json_paths', this means:
###   - -a / --append-val[ue]
###   - -k / --key-regexp
###   - -l / --leaf / --leafs
###   - -t / --type
###   - -v / --val-regexp
###
### Correct examples:
###   Json_paths -a
###   Json_paths -l
###   Json_paths -a -l
###   Json_paths -a -k 'rx' -l -t string -v 'val'
###
### Incorrect (option order violated):
###   Json_paths -l -a           # -a must come before -l
###   Json_paths -t string -k rx # -k must come before -t
###   Json_paths -v rx -t number # -t must come before -v
###
### This convention matches other helpers in bashbricks.sh and keeps
### the option parsing logic simple and predictable.


### ---------------------------------------------
###       Generic basic and meta tools
### ---------------------------------------------

# The last command in this source will be a call to this function:
function export_all_declared_functions {
  source /dev/stdin <<<"$(declare -pF | sed 's/^declare -f /declare -fx /')"
}
alias export_all_declared_functions_right_now=export_all_declared_functions

# ---
# Make and source aliases using dot instead of the first underscore 
# for function names starting with a capital letter (namespaced functions):
# ---
# alias Array.append=Array_append
# alias Array.copy=Array_copy
# alias Array.exists=Array_exists
# ...
function bashbricks_make_dot_aliases {
  local __bb_TMPFILE=$(mktemp /tmp/bashbricks_make_dot_aliases.XXXXXX)
  declare -pF \
    | LC_ALL=C awk '$3 ~ /^[A-Z][a-z]+_/ {copy=sprintf("%s",$3); sub("_",".",copy); print "alias",copy"="$3; }' \
    >${__bb_TMPFILE}
  source /dev/stdin <<<"$(<${__bb_TMPFILE})"
  rm -f ${__bb_TMPFILE}
}

# Poor-man version of binary realpath:
function File_abspath {
  local __bb_B=$(basename "$1")
  local __bb_D=$(dirname "$1")
  (builtin cd "${__bb_D}"; echo "$PWD/${__bb_B}")
}

# ---
function File_realpath_safe {
  if type realpath &>/dev/null; then realpath    "$1"; else # continue
  if type readlink &>/dev/null; then readlink -f "$1"; else # continue
  # Apply the poor-man version:
  File_abspath "$1"; 
  fi; fi;
}

# ---
export BASHBRICKS_SOURCE=$(File_realpath_safe "${BASH_SOURCE[0]}")
export BASHBRICKS_DIR=$(dirname "$BASHBRICKS_SOURCE")
export BASHBRICKS_MD5SUM=$(md5sum "$BASHBRICKS_SOURCE" | awk '{print $1}')
# ---
function bashbricks_functions_list {
  if [[ -f "$BASHBRICKS_SOURCE" ]]; then
    grep "^function [A-Za-z]" "$BASHBRICKS_SOURCE"  | awk '{print $2}'
  fi
}
# ---
function bashbricks_Array_list    { bashbricks_functions_list | \grep "^Array_"   | \grep -v Array_help   | sort | uniq; }
function bashbricks_File_list     { bashbricks_functions_list | \grep "^File_"    | \grep -v File_help    | sort | uniq; }
function bashbricks_Float_list    { bashbricks_functions_list | \grep "^Float_"   | \grep -v Float_help   | sort | uniq; }
function bashbricks_Future_list   { bashbricks_functions_list | \grep "^Future_"  | \grep -v Future_help  | sort | uniq; }
function bashbricks_Function_list { bashbricks_functions_list | \grep "^Function_"| \grep -v Function_help| sort | uniq; }
function bashbricks_Int_list      { bashbricks_functions_list | \grep "^Int_"     | \grep -v Int_help     | sort | uniq; }
function bashbricks_Json_list     { bashbricks_functions_list | \grep "^Json_"    | \grep -v Json_help    | sort | uniq; }
function bashbricks_Map_list      { bashbricks_functions_list | \grep "^Map_"     | \grep -v Map_help     | sort | uniq; }
function bashbricks_Misc_list     { bashbricks_functions_list | \grep "^Misc_"    | \grep -v Misc_help    | sort | uniq; }
function bashbricks_Path_list     { bashbricks_functions_list | \grep "^Path_"    | \grep -v Path_help    | sort | uniq; }
function bashbricks_Regexp_list   { bashbricks_functions_list | \grep "^Regexp_"  | \grep -v Regexp_help  | sort | uniq; }
function bashbricks_Set_list      { bashbricks_functions_list | \grep "^Set_"     | \grep -v Set_help     | sort | uniq; }
function bashbricks_String_list   { bashbricks_functions_list | \grep "^String_"  | \grep -v String_help  | sort | uniq; }
# ---
function bashbricks_Array_documented_list    { Array_help   | awk '/^* Array_/    {print $2}' | sort | uniq; }
function bashbricks_File_documented_list     { File_help    | awk '/^* File_/     {print $2}' | sort | uniq; }
function bashbricks_Float_documented_list    { Float_help   | awk '/^* Float_/    {print $2}' | sort | uniq; }
function bashbricks_Future_documented_list   { Future_help  | awk '/^* Future_/   {print $2}' | sort | uniq; }
function bashbricks_Function_documented_list { Function_help| awk '/^* Function_/ {print $2}' | sort | uniq; }
function bashbricks_Int_documented_list      { Int_help     | awk '/^* Int_/      {print $2}' | sort | uniq; }
function bashbricks_Json_documented_list     { Json_help    | awk '/^* Json_/     {print $2}' | sort | uniq; }
function bashbricks_Map_documented_list      { Map_help     | awk '/^* Map_/      {print $2}' | sort | uniq; }
function bashbricks_Misc_documented_list     { Misc_help    | awk '/^* Misc_/     {print $2}' | sort | uniq; }
function bashbricks_Path_documented_list     { Path_help    | awk '/^* Path_/     {print $2}' | sort | uniq; }
function bashbricks_Regexp_documented_list   { Regexp_help  | awk '/^* Regexp_/   {print $2}' | sort | uniq; }
function bashbricks_Set_documented_list      { Set_help     | awk '/^* Set_/      {print $2}' | sort | uniq; }
function bashbricks_String_documented_list   { String_help  | awk '/^* String_/   {print $2}' | sort | uniq; }

### ---------------------------------------------
###             Function_clone
### ---------------------------------------------
# ---
# Clone the definition of a Bash function.
# Usage:
#   Function_clone SRC DEST
# Effect:
#   Defines a function DEST with exactly the same body as SRC.
function Function_clone {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  # Replace references in the body:
  local __bb_REPLACE_REFS
  if [[ $1 = "-r" || $1 = "--replace" || $1 = "--replace-refs" ]]; then __bb_REPLACE_REFS="y"; shift 1; fi
  # ---
  local  __bb_SRC="$1"
  local __bb_DEST="$2"
  # ---
  # Minimal argument checks :
  [[ -n ${__bb_SRC} && -n ${__bb_DEST} ]] || { echo "Usage: Function_clone [-r|--replace-refs] SRC DEST" 1>&2; return 1; }
  # ---
  # SRC must be an existing function:
  declare -F "${__bb_SRC}" >/dev/null 2>&1 || { echo "Function_clone: '${__bb_SRC}' is not a function" 1>&2; return 2; }
  # ---
  # Retrieve SRC definition, drop the "SRC is a function" line:
  local __bb_DEF
  if [[ -z ${__bb_REPLACE_REFS} ]]; then
    __bb_DEF="$(type "${__bb_SRC}" | awk 'NR>1')" || return 3
    # ---
    # Safely replace only the function declaration line:
    #   SRC () { ... }  ->  DEST () { ... }
    # Internal references to SRC inside the body are left untouched.
    __bb_DEF="${__bb_DEF/${__bb_SRC} ()/${__bb_DEST} ()}"
  else
    # Change also internal references to SRC inside the body:
    __bb_DEF="$(type "${__bb_SRC}" | awk 'NR>1' | sed -e s@${__bb_SRC}@${__bb_DEST}@g)" || return 4
  fi
  # ---
  unalias ${__bb_DEST} &>/dev/null || true
  # Evaluate the new definition to create DEST:
  eval "${__bb_DEF}" || return 5
  # ---
  return 0
}

### ---------------------------------------------
###            Misc (miscellaneous)
### ---------------------------------------------

# ---
function Misc_eprintf { 1>&2 printf "$@"; }
function      eprintf { 1>&2 printf "$@"; }

# ---
# Usage:
#   not <COMMAND>
# ---
# Example:
#   if not false aaa bbb; then ...; fi
# ---
# This function seems preferable to the simple ‘!’ character, whose meaning differs 
# depending on whether or not it is attached to the following string (in other words, 
# depending on whether there is a space or not): “! abc” is dangerously different 
# from “!abc” (which means “search history”).
# ---
function Misc_not { ! "$@"; }
function      not { ! "$@"; }

# ---
# xargs as function and for functions:
function Misc_xargsf {
  local __bb_line
  while read -r __bb_line; do "$@" ${__bb_line}; done;
}
Function_clone Misc_xargsf xargsf

# ---
function Misc_random {
 local __bb_LIMIT=${1:-"2"} # => {0,1}
 echo $((RANDOM/(32768/${__bb_LIMIT})))
}
Function_clone Misc_random random

# ---
# Initially generated by https://www.perplexity.ai/, then marginally edited.
# ---
function Misc_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh
Misc_*: miscellaneous helpers
---
* Misc_eprintf
  Usage:
      Misc_eprintf FORMAT [ARG]...
  Description:
      Wrapper around printf that writes to standard error instead of standard
      output.
      Equivalent in spirit to:
          printf FORMAT [ARG]... >&2
      Useful for warnings, diagnostics, and usage messages.
  Aliases:
      eprintf (without the prefix "Misc_")
  Examples:
      Misc_eprintf 'Error: file not found: %s\n' '/tmp/foo'
      Misc_eprintf 'x=%d y=%d\n' 10 20

  Notes:
      - As with printf in general, FORMAT is interpreted as a printf format
        string.
      - Output is sent to stderr (file descriptor 2), not stdout.
---
* Misc_not
  Usage:
      Misc_not COMMAND [ARG]...
  Description:
      Runs COMMAND with its arguments and returns the logical negation of its
      exit status:
        - returns 0 when COMMAND fails,
        - returns non-zero when COMMAND succeeds.
      This is a functional wrapper around the shell logical negation operator !.

      The helper is intended as a readable and safer alternative in scripts
      and interactive shells, especially for users who want to avoid confusion
      with history expansion syntax involving '!'.
  Aliases:
      not (without the prefix "Misc_")
  Examples:
      Misc_not false
      # returns 0

      Misc_not test -f /does/not/exist
      # returns 0

      if Misc_not grep -q root /etc/fstab; then
        echo "root not found"
      fi
---
* Misc_xargsf
  Usage:
      PRODUCER | Misc_xargsf COMMAND [ARG]...
  Description:
      Poor-man xargs for line-oriented input.
      Reads standard input line by line, and for each input line runs:
          COMMAND [ARG]... LINE
      where LINE is appended as an additional argument.

      In other words, each input line becomes one extra positional argument
      passed to COMMAND.
      This helper is especially convenient when COMMAND is itself a shell
      function, unlike traditional xargs which is primarily command-oriented.
  Aliases:
      xargsf (without the prefix "Misc_")

  Examples:
      printf 'a\nb\nc\n' | Misc_xargsf echo item:
      # item: a
      # item: b
      # item: c

      printf '/etc/passwd\n/etc/fstab\n' | xargsf test_e -v
      # runs:
      #   test_e -v /etc/passwd
      #   test_e -v /etc/fstab

  Notes:
      - Input is read with read -r, so backslashes are preserved.
      - Splitting is line-based, not shell-word-based.
      - The current implementation invokes:
            "$@" ${__bb_line}
        so the appended line is not quoted at the call site; lines containing
        shell word-splitting characters may therefore be split unexpectedly.
---
* Misc_random
  Usage:
      Misc_random [LIMIT]
  Description:
      Prints a pseudo-random integer in the range:
          0 <= N < LIMIT
      using Bash's special RANDOM variable.

      If LIMIT is omitted, it defaults to 2, so the result is either 0 or 1.

      The current implementation computes:
          RANDOM / (32768 / LIMIT)
      which is intended for simple lightweight random choices.
  Aliases:
      random (without the prefix "Misc_")

  Examples:
      Misc_random
      # prints 0 or 1

      Misc_random 10
      # prints an integer intended to lie between 0 and 9

      if [[ $(Misc_random 2) = 0 ]]; then
        echo "heads"
      else
        echo "tails"
      fi

  Notes:
      - RANDOM is a Bash pseudo-random generator, not a cryptographic source.
      - The current formula assumes a Bash RANDOM range compatible with 0..32767.
      - For LIMIT values that do not divide 32768 evenly, the distribution is
        only approximate.
      - LIMIT should be a strictly positive integer; no explicit validation is
        currently performed by the function.
EOF
  } 2>&1 | less
}

### ---------------------------------------------
###                 File
### ---------------------------------------------

# ---
# Usage: File_test_f FILE...
function File_test_f {
  local __bb_VERBOSE=false; if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="true"; shift 1; fi
  local __bb_i; for __bb_i in "$@"; do [[ -f "${__bb_i}" ]] || { ${__bb_VERBOSE} && echo "File not found: ${__bb_i}" 1>&2; return 2; }; done
}
Function_clone File_test_f test_f

# ---
# Usage: File_test_d DIR...
function File_test_d {
  local __bb_VERBOSE=false; if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="true"; shift 1; fi
  local __bb_i; for __bb_i in "$@"; do [[ -d "${__bb_i}" ]] || { ${__bb_VERBOSE} && echo "Directory not found: ${__bb_i}" 1>&2; return 2; }; done
}
Function_clone File_test_d test_d

# ---
# Usage: File_test_e FILE...
function File_test_e {
  local __bb_VERBOSE=false; if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="true"; shift 1; fi
  local __bb_i; for __bb_i in "$@"; do [[ -e "${__bb_i}" ]] || { ${__bb_VERBOSE} && echo "File or directory not found: ${__bb_i}" 1>&2; return 2; }; done
}
Function_clone File_test_e test_e

# ---
# Usage: File_test_x FILE...
function File_test_x {
 local __bb_VERBOSE=false; if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="true"; shift 1; fi
 local __bb_i; for __bb_i in "$@"; do [[ -x "${__bb_i}" ]] || { 
  ${__bb_VERBOSE} && echo "File is missing or the user hasn't execute (or search) access: ${__bb_i}" 1>&2; 
  return 2; 
  }; 
 done
}
Function_clone File_test_x test_x 

# ---
# Usage: File_test_rw FILE...
function File_test_rw {
 local __bb_VERBOSE=false; if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="true"; shift 1; fi
 local __bb_i; for __bb_i in "$@"; do [[ -r "${__bb_i}" && -w "${__bb_i}" ]] || { 
  ${__bb_VERBOSE} && echo "File is missing or the user hasn't both the read and write access: ${__bb_i}" 1>&2; 
  return 2; 
  }; 
 done
}
Function_clone File_test_rw test_rw

# ---
# Usage: File_test_dx FILE...
function File_test_dx {
 local __bb_VERBOSE=false; if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="true"; shift 1; fi
 local __bb_i; for __bb_i in "$@"; do [[ -d "${__bb_i}" && -x "${__bb_i}" ]] || { 
  ${__bb_VERBOSE} && echo "Directory is missing or the user hasn't the search access: ${__bb_i}" 1>&2;
  return 2; 
  }; 
 done
}
Function_clone File_test_dx test_dx

# ---
# Non empty directory test:
function File_test_ds {
  local __bb_VERBOSE=false; if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="true"; shift 1; fi
  local __bb_i; for __bb_i in "$@"; do 
    [[ -d "${__bb_i}" ]] && find "${__bb_i}" -maxdepth 0 -empty -exec /bin/false "{}" + || { 
      ${__bb_VERBOSE} && echo "Directory is missing or empty: ${__bb_i}" 1>&2;
      return 2; 
      }; 
  done
}
Function_clone File_test_ds test_ds

### ---------------------------------------------
###              File_in_place
### ---------------------------------------------
# ---
# Usage: File_in_place <TARGET> <COMMAND> [ARGS]...
# Transforms a filter (0 -> 1) in a command that modify the provided existing file in place.
# ---
# Examples: 
#  $ File_in_place /etc/fstab 'sed -e s@sda@sdb@g'  # equivalent to: 
#  $ sed -i -e s@sda@sdb@g /etc/fstab
#  ---
#  $ cp /etc/fstab /tmp/fstab
#  $ File_in_place /tmp/fstab sed -e "s@vfat@ext4@g"
#  $ diff /etc/fstab /tmp/fstab 
#  13c13
#  < UUID=E1B6-672C  /boot/efi       vfat    umask=0077      0       1
#  ---
#  > UUID=E1B6-672C  /boot/efi       ext4    umask=0077      0       1
#  ---
#  $ File_in_place /tmp/fstab grep -v 'UUID=E1B6-672C'
# ---
function File_in_place {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: File_in_place FILE COMMAND [ARGS]...";
  local __bb_FORCE
  # Force writing even when the command (for instance `grep') fails:
  if [[ $1 = "-f" || $1 = "--force" ]]; then __bb_FORCE=y; shift; fi
  # ---
  local __bb_TARGET="$1" && shift || { echo "${__bb_USAGE}" 1>&2; return 1; }
  File_test_f "${__bb_TARGET}"    || { echo "${__bb_USAGE}" 1>&2; return 2; }
  local __bb_CMD=$1 && shift      || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/File_in_place.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE})
  # ---
  "${__bb_CMD}" "$@" <"${__bb_TARGET}" >${__bb_TMPFILE}
  # ---
  local __bb_CODE=$?
  if [[ ${__bb_CODE} = 0 || ${__bb_FORCE} = y ]]; then
    cat ${__bb_TMPFILE} >"${__bb_TARGET}";
  else
    echo "WARNING: File_in_place: target file leaved unchanged: '${__bb_TARGET}'" 1>&2;
  fi
  # ---
  rm ${__bb_TMPFILE}
  return ${__bb_CODE}
}
Function_clone File_in_place in_place

# Initially generated by https://www.perplexity.ai/, then marginally edited.

function File_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh
Path_*: helpers to manipulate files
---
* File_test_f
  Usage:
      File_test_f [-v|--verbose] [FILE]...
  Description:
      Returns 0 if every argument is an existing regular file.
      Returns 2 as soon as one argument is missing or is not a regular file.
      With -v or --verbose, prints an error message on stderr for the first
      failing path.
  Aliases:
      test_f (without the prefix "File_")
  Examples:
      File_test_f /etc/fstab
      File_test_f -v /etc/fstab /does/not/exist
---
* File_test_d
  Usage:
      File_test_d [-v|--verbose] [DIR]...
  Description:
      Returns 0 if every argument is an existing directory.
      Returns 2 as soon as one argument is missing or is not a directory.
      With -v or --verbose, prints an error message on stderr for the first
      failing path.
  Aliases:
      test_d (without the prefix "File_")
  Examples:
      File_test_d /tmp
      File_test_d -v /tmp /etc/passwd
---
* File_test_e
  Usage:
      File_test_e [-v|--verbose] [PATH]...
  Description:
      Returns 0 if every argument exists as either a file, a directory,
      or another filesystem entry.
      Returns 2 as soon as one argument does not exist.
      With -v or --verbose, prints an error message on stderr for the first
      failing path.
  Aliases:
      test_e (without the prefix "File_")
  Examples:
      File_test_e /etc /etc/fstab
      File_test_e -v /etc /does/not/exist
---
* File_test_x
  Usage:
      File_test_x [-v|--verbose] [FILE]...
  Description:
      Returns 0 if every argument exists and is executable.
      For directories, this effectively checks search/traversal permission.
      Returns 2 as soon as one argument is missing or lacks execute/search
      access for the current user.
      With -v or --verbose, prints an error message on stderr for the first
      failing path.
  Aliases:
      test_x (without the prefix "File_")
  Examples:
      File_test_x /bin/sh
      File_test_x -v /bin/sh /etc/passwd
---
* File_test_rw
  Usage:
      File_test_rw [-v|--verbose] [FILE]...
  Description:
      Returns 0 if every argument exists and is both readable and writable
      for the current user.
      Returns 2 as soon as one argument is missing or lacks either read
      or write access.
      With -v or --verbose, prints an error message on stderr for the first
      failing path.
  Aliases:
      test_rw (without the prefix "File_")
  Examples:
      File_test_rw /tmp/myfile
      File_test_rw -v /etc/passwd
---
* File_test_dx
  Usage:
      File_test_dx [-v|--verbose] [DIR]...
  Description:
      Returns 0 if every argument is an existing directory with search
      (execute) permission for the current user.
      Returns 2 as soon as one argument is missing, is not a directory,
      or is not searchable.
      With -v or --verbose, prints an error message on stderr for the first
      failing path.
  Aliases:
      test_dx (without the prefix "File_")
  Examples:
      File_test_dx /tmp
      File_test_dx -v /root
---
* File_test_ds
  Usage:
      File_test_ds [-v|--verbose] [DIR]...
  Description:
      Tests that every argument is an existing non-empty directory.
      Returns 0 if all directories exist and are not empty.
      Returns 2 as soon as one argument is missing, is not a directory,
      or is an empty directory.
      With -v or --verbose, prints an error message on stderr for the first
      failing path.
  Aliases:
      test_ds (without the prefix "File_")
  Examples:
      File_test_ds /etc
      File_test_ds -v /tmp/possibly-empty-dir
---
* File_in_place
  Usage:
      File_in_place [-f|--force] FILE COMMAND [ARGS]...
  Description:
      Runs COMMAND with its standard input redirected from FILE and its
      standard output redirected to a temporary file, then replaces FILE
      with the produced output.
      In other words, it turns a filter-style command (stdin -> stdout)
      into an in-place file transformation helper.

      Without -f or --force:
        - FILE is overwritten only if COMMAND exits with status 0.
        - otherwise FILE is left unchanged and a warning is printed.

      With -f or --force:
        - FILE is overwritten even if COMMAND exits with a non-zero status,
          provided that some output was produced into the temporary file.

      Return codes:
        - 1: missing FILE argument,
        - 2: FILE does not exist or is not a regular file,
        - 3: missing COMMAND,
        - otherwise: the exit status of COMMAND.

      Notes:
        - FILE must already exist and be a regular file.
        - COMMAND is invoked as:
              COMMAND [ARGS]... < FILE > TMPFILE
        - Standard error of COMMAND is not captured and remains visible.
        - A temporary file under /tmp is used internally and removed before
          returning.
  Aliases:
      in_place (without the prefix "File_")

  Examples:
      File_in_place /etc/fstab sed -e 's@sda@sdb@g'
      # similar in effect to:
      # sed -i -e 's@sda@sdb@g' /etc/fstab

      cp /etc/fstab /tmp/fstab
      File_in_place /tmp/fstab sed -e 's@vfat@ext4@g'
      diff /etc/fstab /tmp/fstab

      File_in_place /tmp/fstab grep -v 'UUID=E1B6-672C'

      # Force replacement even if grep returns 1 because no line matched
      File_in_place --force /tmp/fstab grep -v 'nonexistent-pattern'
---
* File_abspath
  Usage:
      File_abspath PATH
  Description:
      Poor-man absolute-path helper.
      Splits PATH into dirname + basename, changes directory to the dirname,
      and prints:
          $PWD/$BASENAME
      The result is therefore an absolute path, but it is not a full
      canonicalization routine:
        - symbolic links are not resolved,
        - '.' and '..' components are only handled indirectly through the
          directory change,
        - behavior depends on being able to cd into dirname(PATH).

      This helper is mainly intended as a lightweight fallback when no
      stronger path canonicalization tool is available.

  Examples:
      File_abspath ./foo.txt
      # prints an absolute path ending in /foo.txt

      File_abspath ../data/input.csv
      # prints the absolute path corresponding to that relative pathname

  Notes:
      - PATH should normally contain at least one dirname/basename split
        meaningful to dirname and basename.
      - If dirname(PATH) cannot be entered, the result may be empty or
        otherwise fail indirectly through the subshell.
---
* File_realpath_safe
  Usage:
      File_realpath_safe PATH
  Description:
      Returns an absolute path for PATH using the best available helper
      in the current environment, in the following order:
        1. realpath PATH
        2. readlink -f PATH
        3. File_abspath PATH
      So:
        - if 'realpath' is available, it is used preferentially;
        - otherwise, if 'readlink' is available, 'readlink -f' is used;
        - otherwise, a weaker fallback based on File_abspath is applied.

      When 'realpath' or 'readlink -f' is used, the result is generally a
      canonicalized absolute path with '.', '..' and symlinks resolved,
      subject to the semantics of the underlying tool.
      When the fallback File_abspath is used, the result is only a
      best-effort absolute pathname and may still preserve symlink structure.

  Examples:
      File_realpath_safe ./foo.txt
      # prints the best available absolute path for ./foo.txt

      File_realpath_safe ../data/input.csv
      # uses realpath if present, else readlink -f, else File_abspath

  Notes:
      - realpath is the preferred command for pathname canonicalization.
      - readlink -f provides similar canonicalization behavior on GNU systems.
      - The final fallback File_abspath is less strict and should be viewed
        as a portability fallback rather than a full replacement.      
EOF
  } 2>&1 | less
}

### ---------------------------------------------
###           Regexp, Float, Int
### ---------------------------------------------
###
### DEPENDENCIES: 
###   /usr/bin/bc 
###   /bin/ocaml (Float_round)
### ---------------------------------------------

# ---
# Cette version capte les lettres accentuées !
# function Regexp_is_ident   { [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; } 
# ---
# Cette version (par grep) est correcte mais plus lente (double du temps) :
# function Regexp_is_ident_by_grep   { LC_ALL=C \grep -q '^[a-zA-Z_][a-zA-Z0-9_]*$' <<<"$1"; } 
# ---
function Regexp_is_ident   { local __bb_x="$1"; (LC_ALL=C; [[ "${__bb_x}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]); }
# ---
function Regexp_is_number  { [[ "$1" =~ ^[-+]?[0-9]+([.][0-9]+)?$ ]]; }
function Regexp_is_integer { [[ "$1" =~ ^(0|[-]?[1-9][0-9]*)$     ]]; }
function Regexp_is_natural { [[ "$1" =~ ^(0|[1-9][0-9]*)$         ]]; }
function Regexp_is_index   { [[ "$1" =~ ^(0|[1-9][0-9]*)$         ]]; }
# ---
function Regexp_is_word { [[ "$*" =~ ^[^[:space:]]+$ ]]; }
# On vérifie juste si le corps contient "$[1-9]" ou "$[*@]" :
function Regexp_is_function_body { [[ "$1" =~ [$][{]?[1-9*@#] ]]; }
# ---
function Regexp_is_ocaml_float { [[ "$1" =~ ^[-+]?(0|[1-9][0-9]*)\.([0-9]+([eE][+-]?[0-9]+)?$|$)      ]]; }
function Regexp_is_awk_number  { [[ "$1" =~ ^[-+]?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))([eE][+-]?[0-9]+)?$ ]]; }
function Regexp_is_bc_number   { [[ "$1" =~ ^([0-9]+|\.[0-9]+|[0-9]+\.[0-9]+|[0-9]+\.)$               ]]; }
# ---
function Float_is_bc_number { Regexp_is_bc_number $1 && [[ -n $(bc -ls <<<"$1") ]]; }
function Int_even           { Regexp_is_natural  "$1" && (( $1 % 2 == 0 )); }
function Int_odd            { Regexp_is_natural  "$1" && (( $1 % 2 == 1 )); }
# ---
function Regexp_is_command_word { local __bb_x="$*"; (LC_ALL=C; [[ "${__bb_x}" =~ ^[a-zA-Z0-9_.-/]+$ ]]); }
function Sys_is_binary     { Regexp_is_command_word "$*" && type -P &>/dev/null "$1"; }
function Sys_is_command    { Regexp_is_command_word "$*" && type    &>/dev/null "$1"; }

###
### CONDITIONAL DEFINITIONS (bc) --- BEGIN
###
if which bc &>/dev/null; then
###

# ---
# Private method:
# Example:
#  __bc_wrapper "exp" "e" "$@";
# ---
function __bc_wrapper1 { 
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_name="$1"
  local __bb_bc_name="$2"
  shift 2 || return 22  # Invalid argument
  # ---
  local __bb_x="$1"
  local __bb_USAGE="Usage: Float_${__bb_name} NUMBER";
  [[ $# = 1 ]] && Float_is_bc_number "${__bb_x}" || { echo "${__bb_USAGE}" 1>&2; return 1; }
  local __bb_y=$(bc -ls <<<"${__bb_bc_name}(${__bb_x})")
  if [[ -z "${__bb_y}" ]]; then return 2; else echo "${__bb_y}"; fi
}

# ---
# Private method:
# Example:
#  __bc_wrapper2 "pow" "^" "$@";
# ---
function __bc_wrapper2 { 
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_OPTION_MATHLIB="-l"
  if [[ $1 = "-n" || $1 = "--no-mathlib" || $1 = "+l" ]]; then __bb_OPTION_MATHLIB=""; shift 1; fi
  # ---
  local __bb_name="$1"
  local __bb_bc_name="$2"
  shift 2 || return 22  # Invalid argument
  # ---
  local __bb_x1="$1"
  local __bb_x2="$2"
  local __bb_USAGE="Usage: Float_${__bb_name} NUMBER1 NUMBER2";
  [[ $# = 2 ]] && Float_is_bc_number "${__bb_x1}" && Float_is_bc_number "${__bb_x2}" || { echo "${__bb_USAGE}" 1>&2; return 1; }
  local __bb_y=$(\bc ${__bb_OPTION_MATHLIB} -s <<<"(${__bb_x1}) ${__bb_bc_name} (${__bb_x2})")
  if [[ -z "${__bb_y}" ]]; then return 2; else echo "${__bb_y}"; fi
}

# ---
function Float_exp  { __bc_wrapper1 "exp"  "e"    "$@"; }
function Float_log  { __bc_wrapper1 "log"  "l"    "$@"; }
function Float_sqrt { __bc_wrapper1 "sqrt" "sqrt" "$@"; }
function Float_sin  { __bc_wrapper1 "sin"  "s"    "$@"; }
function Float_cos  { __bc_wrapper1 "cos"  "c"    "$@"; }
function Float_atan { __bc_wrapper1 "atan" "a"    "$@"; }
# ---
function Float_add  { __bc_wrapper2 "add"  "+"    "$@"; }
function Float_sub  { __bc_wrapper2 "sub"  "-"    "$@"; }
function Float_mul  { __bc_wrapper2 "mul"  "*"    "$@"; }
function Float_div  { __bc_wrapper2 "div"  "/"    "$@"; }
function Float_mod  { __bc_wrapper2 --no-mathlib "mod"  "%" "$@"; }

# function Float_pow  { __bc_wrapper2 "pow"  "^"    "$@"; }
# L'opérateur ^ de bc n'accepte pas les puissances non entières, donc :
function Float_pow  { 
  echo $(Float_exp $(Float_mul "$2" $(Float_log "$1")))  
 }

###
else 
  echo "WARNING: bashbricks: required binary 'bc' not found; functions depending on it were not loaded."
fi
### CONDITIONAL DEFINITIONS (bc) --- END

###
### CONDITIONAL DEFINITIONS (ocaml) --- BEGIN
###
if which ocaml &>/dev/null; then
###

# ---
# Private method:
# Example:
#   __ocaml_wrapper1 "round"  "Float.round |> int_of_float" "%d" "$@";
# ---
function __ocaml_wrapper1 { 
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_name="$1"
  local __bb_expr="$2"
  local __bb_format="$3" # '%f' or '%d' or '%s'
  shift 3 || return 22  # Invalid argument
  # ---
  local __bb_x="$1"
  local __bb_USAGE="Usage: Float_${__bb_name} NUMBER";
  [[ $# = 1 ]] && Regexp_is_ocaml_float "${__bb_x}" || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_y=$(\ocaml -stdin  <<<"let y = ((\"${__bb_x}\") |> ${__bb_expr}) in Printf.printf \"${__bb_format}\n\" y;;")
  # ---
  if [[ -z "${__bb_y}" ]]; then return 2; else echo "${__bb_y}"; fi
}

# ---
function Float_round  { __ocaml_wrapper1 "round"  "Float.of_string |> Float.round |> int_of_float" "%d" "$@"; }

###
else 
  echo "WARNING: bashbricks: required binary 'ocaml' not found; functions depending on it were not loaded."
fi
### CONDITIONAL DEFINITIONS (ocaml) --- END

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Regexp_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh
Regexp_*: helpers around Bash's native regular expressions [[ STRING =~ REGEXP ]]
---
* Regexp_is_ident
  Usage:
      Regexp_is_ident STRING
  Description:
      Returns 0 if STRING is a valid Bash identifier name in the C locale:
      - first character: [A-Za-z_]
      - subsequent characters: [A-Za-z0-9_]
      Returns non-zero otherwise.
      This helper is used to validate variable names, function names, etc.
  Examples:
      Regexp_is_ident foo       # 0
      Regexp_is_ident _x123     # 0
      Regexp_is_ident 123abc    # 1
      Regexp_is_ident 'a-b'     # 1
---
* Regexp_is_number
  Usage:
      Regexp_is_number STRING
  Description:
      Returns 0 if STRING matches a simple decimal number:
      - optional leading sign (+ or -),
      - mandatory integer part (at least one digit),
      - optional fractional part with '.' and at least one digit.
      No exponent, no leading '.', and no trailing non-digits.
  Examples:
      Regexp_is_number 42        # 0
      Regexp_is_number -3.14     # 0
      Regexp_is_number .5        # 1
      Regexp_is_number 3.        # 1
      Regexp_is_number 1e10      # 1
---
* Regexp_is_integer
  Usage:
      Regexp_is_integer STRING
  Description:
      Returns 0 if STRING is a signed integer with no leading zeros
      (except for the single value "0"):
      - "0"
      - or an optional '-' followed by a non-zero digit and digits.
      Returns non-zero otherwise.
  Examples:
      Regexp_is_integer 0        # 0
      Regexp_is_integer 42       # 0
      Regexp_is_integer -7       # 0
      Regexp_is_integer 007      # 1
      Regexp_is_integer +3       # 1 (leading '+' not allowed)
---
* Regexp_is_natural
  Usage:
      Regexp_is_natural STRING
  Description:
      Returns 0 if STRING is a natural number:
      - "0"
      - or a non-zero digit followed by digits (no leading zeros).
      Equivalent to Regexp_is_index.
  Examples:
      Regexp_is_natural 0        # 0
      Regexp_is_natural 1        # 0
      Regexp_is_natural 123      # 0
      Regexp_is_natural 01       # 1
      Regexp_is_natural -1       # 1
---
* Regexp_is_index
  Usage:
      Regexp_is_index STRING
  Description:
      Alias for Regexp_is_natural.
      Intended for array indices: 0,1,2,... without leading zeros.
  Examples:
      Regexp_is_index 0          # 0
      Regexp_is_index 10         # 0
      Regexp_is_index 01         # 1
---
* Regexp_is_word
  Usage:
      Regexp_is_word STRING
  Description:
      Returns 0 if STRINT contains no whitespace characters 
      (no spaces, tabs, newlines, etc.).
      Useful to validate "single-token" arguments.
  Examples:
      Regexp_is_word foo         # 0
      Regexp_is_word foo_bar     # 0
      Regexp_is_word 'foo bar'   # 1
      Regexp_is_word ''          # 1 (empty string)
---
* Regexp_is_function_body
  Usage:
      Regexp_is_function_body STRING
  Description:
      Heuristic predicate.
      Returns 0 if STRING contains a reference to shell positional
      parameters (e.g. $1..$9, $*, $@, $#) possibly in ${...} form.
      Intended to detect whether a snippet looks like a function body
      that expects positional arguments.
  Examples:
      Regexp_is_function_body 'echo $1 $2'       # 0
      Regexp_is_function_body 'echo "$@"'        # 0
      Regexp_is_function_body 'echo hello'       # 1
---
* Regexp_is_ocaml_float
  Usage:
      Regexp_is_ocaml_float STRING
  Description:
      Returns 0 if STRING is a floating-point literal in OCaml style:
      - optional sign (+ or -),
      - integer part: 0 or [1-9][0-9]*,
      - '.', fractional part with at least one digit,
      - optional exponent: [eE][+-]?[0-9]+.
      Examples of accepted forms: 3.14, -0.5, 2.0e3, +12.34E-2.
  Examples:
      Regexp_is_ocaml_float 3.14       # 0
      Regexp_is_ocaml_float -0.5       # 0
      Regexp_is_ocaml_float 2.0e3      # 0
      Regexp_is_ocaml_float .5         # 1 (missing integer part)
      Regexp_is_ocaml_float 3.         # 0 (missing fraction accepted)
---
* Regexp_is_awk_number
  Usage:
      Regexp_is_awk_number STRING
  Description:
      Returns 0 if STRING is a number accepted by awk:
      - optional sign,
      - either:
        * digits with optional fractional part (e.g. 10, 10., 10.5), or
        * '.' then digits (e.g. .5),
      - optional exponent [eE][+-]?[0-9]+.
      More permissive than Regexp_is_number and suitable for awk-like parsing.
  Examples:
      Regexp_is_awk_number 42        # 0
      Regexp_is_awk_number 3.        # 0
      Regexp_is_awk_number .75       # 0
      Regexp_is_awk_number 1e10      # 0
      Regexp_is_awk_number '1.2.3'   # 1
---
* Regexp_is_bc_number
  Usage:
      Regexp_is_bc_number STRING
  Description:
      Returns 0 if STRING is a bare number that bc can consume directly:
      - "123"
      - ".123"
      - "123.456"
      - "123."
      No sign, exponent, or additional characters.
      Typically used as a pre-check before passing values to bc.
  Examples:
      Regexp_is_bc_number 42         # 0
      Regexp_is_bc_number .5         # 0
      Regexp_is_bc_number 3.14       # 0
      Regexp_is_bc_number 3.         # 0
      Regexp_is_bc_number -3.14      # 1 (sign not allowed)
---
* Regexp_is_command_word
  Usage:
      Regexp_is_command_word STRING
  Description:
      Returns 0 if STRING consists only of:
      [A-Za-z0-9_.-/]
      i.e. characters acceptable in simple command names and paths.
      Intended as a sanity check before calling 'type', 'type -P', etc.
  Examples:
      Regexp_is_command_word ls               # 0
      Regexp_is_command_word /usr/bin/env     # 0
      Regexp_is_command_word 'rm -rf'         # 1 (contains space)
      Regexp_is_command_word 'weird$cmd'      # 1
EOF
  } 2>&1 | less
}

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Float_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh  
Float_*: helpers around floating-point numbers (bc/ocaml-based)
---
* Float_is_bc_number
  Usage:
      Float_is_bc_number STRING
  Description:
      Returns 0 if STRING is a number acceptable by bc and if evaluating it
      through 'bc -ls' yields some output.
      This combines Regexp_is_bc_number and a small bc check.
      Used internally by all Float_* operations as a guard.
  Examples:
      Float_is_bc_number 3.14      # 0
      Float_is_bc_number .5        # 0
      Float_is_bc_number -3.14     # 1 (sign not allowed here)
      Float_is_bc_number 'abc'     # 1
---
* Float_exp
  Usage:
      Float_exp NUMBER
  Description:
      Computes the exponential e^(NUMBER) using bc's math library:
          e(NUMBER)
      NUMBER must satisfy Float_is_bc_number, otherwise the function prints
      a usage message on stderr and returns 1.
      Returns 0 on success and prints the result on stdout.
  Examples:
      Float_exp 0          # ~1
      Float_exp 1          # ~2.718281828...
---
* Float_log
  Usage:
      Float_log NUMBER
  Description:
      Computes the natural logarithm ln(NUMBER) using bc's 'l' function.
      NUMBER must be a positive Float_is_bc_number.
      Returns the result on stdout.
  Examples:
      Float_log 1          # 0
      Float_log 2.71828    # ~1
---
* Float_sqrt
  Usage:
      Float_sqrt NUMBER
  Description:
      Computes the square root sqrt(NUMBER) with bc's sqrt().
      NUMBER must be a non-negative Float_is_bc_number.
  Examples:
      Float_sqrt 4         # 2
      Float_sqrt 2         # ~1.414213562...
---
* Float_sin
  Usage:
      Float_sin NUMBER
  Description:
      Computes sin(NUMBER) using bc's 's' function (angle in radians).
  Examples:
      Float_sin 0          # 0
      Float_sin 1.570796   # ~1
---
* Float_cos
  Usage:
      Float_cos NUMBER
  Description:
      Computes cos(NUMBER) using bc's 'c' function (angle in radians).
  Examples:
      Float_cos 0          # 1
      Float_cos 3.14159    # ~-1
---
* Float_atan
  Usage:
      Float_atan NUMBER
  Description:
      Computes atan(NUMBER) using bc's 'a' function (result in radians).
  Examples:
      Float_atan 1         # ~0.785398...
---
* Float_add
  Usage:
      Float_add NUMBER1 NUMBER2
  Description:
      Computes NUMBER1 + NUMBER2 using bc.
      Both arguments must satisfy Float_is_bc_number.
      Uses bc with the math library enabled.
  Examples:
      Float_add 1.5 2.25   # 3.75
---
* Float_sub
  Usage:
      Float_sub NUMBER1 NUMBER2
  Description:
      Computes NUMBER1 - NUMBER2 using bc.
  Examples:
      Float_sub 5 2.5      # 2.5
---
* Float_mul
  Usage:
      Float_mul NUMBER1 NUMBER2
  Description:
      Computes NUMBER1 * NUMBER2 using bc.
  Examples:
      Float_mul 1.5 4      # 6.0
---
* Float_div
  Usage:
      Float_div NUMBER1 NUMBER2
  Description:
      Computes NUMBER1 / NUMBER2 using bc.
      NUMBER2 must be non-zero.
  Examples:
      Float_div 10 4       # 2.5
---
* Float_pow
  Usage:
      Float_pow NUMBER1 NUMBER2
  Description:
      Computes the power by formula 
        exp(NUMBER2 * log NUMBER2) 
      using bc.
      Both arguments must be valid bc numbers.
  Examples:
      Float_pow 2 3        # 8
      Float_pow 9 0.5      # 3 (sqrt)
---
* Float_mod
  Usage:
      Float_mod NUMBER1 NUMBER2
  Description:
      Computes NUMBER1 % NUMBER2 using bc without the math library.
      Intended for integer-like modulus; arguments are still validated
      with Float_is_bc_number.
  Examples:
      Float_mod 10 3       # 1
---
* Float_round
  Usage:
      Float_round NUMBER
  Description:
      Rounds NUMBER to the nearest integer using OCaml when available.
      Internally calls:
          Float.of_string |> Float.round |> int_of_float
      and prints the resulting integer on stdout.
      The result is formatted with "%d" (no decimal part).
      If 'ocaml' is not installed, this function may not be defined and
      a warning is printed at module load time.
  Examples:
      Float_round 3.2      # 3
      Float_round 3.8      # 4
      Float_round -1.4     # -1
      Float_round -1.5     # -2
EOF
  } 2>&1 | less
}

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Int_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh
Int_*: helpers around Bash's native integer numbers
---
* Int_even
  Usage:
      Int_even N
  Description:
      Returns 0 if N is a natural number (Regexp_is_natural) and N % 2 == 0.
      Returns non-zero otherwise.
      Useful as a guard before performing even-only arithmetic or indexing.
  Examples:
      Int_even 0        # 0
      Int_even 2        # 0
      Int_even 3        # 1
      Int_even -2       # 1 (not natural)
---
* Int_odd
  Usage:
      Int_odd N
  Description:
      Returns 0 if N is a natural number (Regexp_is_natural) and N % 2 == 1.
      Returns non-zero otherwise.
  Examples:
      Int_odd 1         # 0
      Int_odd 3         # 0
      Int_odd 4         # 1
      Int_odd -1        # 1 (not natural)
EOF
  } 2>&1 | less
}


### ---------------------------------------------
###                   Declare
### ---------------------------------------------

# ---
function Declare_is_undefined {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Declare_is_undefined [-v|--verbose] NAME";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_diu_NAME="$1"
  [[ -n "${__bb_diu_NAME}" && $# = 1 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_CODE=0
  if declare -p ${__bb_diu_NAME} &>/dev/null; then
    __bb_CODE=1
    [[ -n ${__bb_VERBOSE} ]] && { 
      echo "Error: the provided NAME '${__bb_diu_NAME}' is already defined" 1>&2
      echo "${__bb_USAGE}" 1>&2
      }
  fi
  # ---
  return ${__bb_CODE}
}

# ---
function Declare_is_array {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Declare_is_array [-v|--verbose] NAME";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_dia_NAME="$1"
  [[ -n "${__bb_dia_NAME}" && $# = 1 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_CODE=0
  local __bb_TYPESET="$(declare -p ${__bb_dia_NAME} 2>/dev/null)"
  [[ "${__bb_TYPESET#declare -a}" != "${__bb_TYPESET}" ]] || {
    __bb_CODE=1
    [[ -n ${__bb_VERBOSE} ]] && { 
      echo "Error: the provided NAME '${__bb_dia_NAME}' is already defined but is not an array" 1>&2
      echo "${__bb_USAGE}" 1>&2
      }
    }
  # ---
  return ${__bb_CODE}
}

# ---
function Declare_are_arrays {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Declare_are_array [-v|--verbose] [NAME]...";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_daa_NAME
  for __bb_daa_NAME in "$@"; do 
    Declare_is_array -u "${__bb_USAGE}" ${__bb_VERBOSE} "${__bb_daa_NAME}" || return 1; 
  done
}

# ---
function Declare_is_map {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Declare_is_map [-v|--verbose] NAME";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_dim_NAME="$1"
  [[ -n "${__bb_dim_NAME}" && $# = 1 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_CODE=0
  local __bb_TYPESET="$(declare -p ${__bb_dim_NAME} 2>/dev/null)"
  [[ "${__bb_TYPESET#declare -A}" != "${__bb_TYPESET}" ]] || {
    __bb_CODE=1
    [[ -n ${__bb_VERBOSE} ]] && {
      echo "Error: the provided NAME '${__bb_dim_NAME}' is already defined but is not a map (associative array)" 1>&2
      echo "${__bb_USAGE}" 1>&2
      }
    }
  # ---
  return ${__bb_CODE}
}

# ---
function Declare_are_maps {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Declare_are_maps [-v|--verbose] [NAME]...";
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_dam_NAME
  for __bb_dam_NAME in "$@"; do 
    Declare_is_map -u "${__bb_USAGE}" ${__bb_VERBOSE} "${__bb_dam_NAME}" || return 1; 
  done
}

# ---
# Create a fresh (unused) Bash identifier of the form ${PREFIX}_${RANDOM}
# To be used with eval
# ---
# declare [-aAfFgiIlnrtux] [nom[=valeur]
# ---
# Examples:
#  $ Declare_fresh_name -o -A -v '()' NAME FOO
#  declare -A FOO_42682='()' && NAME=FOO_42682
#  $ eval $(Declare_fresh_name -o -A -v '()' NAME FOO)
#  $ echo $NAME 
#  FOO_28570
#  $ declare -p $NAME 
#  declare -A FOO_28570='()'
#  ---
#  Array_init A 10 
# ---
function Declare_fresh_name {  
  # ---
  local __bb_USAGE="Usage: Declare_fresh_name [-o|--options OPTIONS] [-v|--value VALUE] VARNAME PREFIX";
  # ---
  # [-aAfFgiIlnrtux]
  local __bb_declare_OPTIONS
  if [[ $1 = "-o" || $1 = "--options" ]]; then
    __bb_declare_OPTIONS="$2";
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 4; }
  fi
  # ---
  local __bb_declare_VALUE
  if [[ $1 = "-v" || $1 = "--val" || $1 = "--value" ]]; then
    __bb_declare_VALUE="$2";
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 5; }
  fi
  # ---
  local __bb_dfn_VARNAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  local      __bb_PREFIX="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local __Declare_fresh_name_NAME=${__bb_PREFIX}_${RANDOM}
  while declare -p "${__Declare_fresh_name_NAME}" &>/dev/null; do
    __Declare_fresh_name_NAME="${__bb_PREFIX}_${RANDOM}"
  done
  # ---
  if [[ -n ${__bb_declare_VALUE} ]]; then
    printf 'declare %s %s=%q && %s=%s\n' \
      "${__bb_declare_OPTIONS}"  "$__Declare_fresh_name_NAME"  "${__bb_declare_VALUE}"  "${__bb_dfn_VARNAME}"  "$__Declare_fresh_name_NAME"
  else
    printf 'declare %s %s && %s=%s\n' \
      "${__bb_declare_OPTIONS}"  "$__Declare_fresh_name_NAME"  "${__bb_dfn_VARNAME}"  "$__Declare_fresh_name_NAME"
  fi
}

### ---------------------------------------------
###                String
### ---------------------------------------------

# ---
function String_is_prefix {
  local __bb_USAGE="Usage: String_is_prefix PREFIX STRING";
  [[ $# = 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_PREFIX="$1"
  local __bb_STRING="$2"
  # ---
  [[ "${__bb_PREFIX}" = "${__bb_STRING:0:${#__bb_PREFIX}}" ]]
}
alias String.starts_with=String_is_prefix

# ---
function String_is_suffix {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: String_is_suffix SUFFIX STRING";
  [[ $# = 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_SUFFIX="$1"
  local __bb_STRING="$2"
  # ---
  [[ ${#__bb_SUFFIX} -eq 0 ]] || [[ "${__bb_STRING: -${#__bb_SUFFIX}}" = "${__bb_SUFFIX}" ]]
}
alias String.ends_with=String_is_suffix

function String_lowercase  { printf '%s\n' "${@,,}"; }
function String_capitalize { printf '%s\n' "${@^}"; }
function String_uppercase  { printf '%s\n' "${@^^}"; }
function String_length { 
  local __bb_ARG
  for __bb_ARG in "${@}"; do  printf '%d\n' "${#__bb_ARG}"; done;
}

# ---
# Examples:
#  $ String_sub abcdef 2     # cdef
#  $ String_sub abcdef 2 3   # cde
#  $ String_sub abcdef -2    # ef
#  $ String_sub abcdef -4 2  # cd
#  $ String_sub abcdef foo   # (rc=2), stderr: Usage: String_sub STRING POS [LEN]
# ---
function String_sub {
  local __bb_USAGE="Usage: String_sub STRING POS [LEN]";
  [[ $# = 2 || $# = 3 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_STRING="$1"
  local __bb_POS="$2"
  local __bb_LEN="${3:-}"
  # ---
  Regexp_is_integer "${__bb_POS}"                 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  [[ $# = 2 ]] || Regexp_is_natural "${__bb_LEN}" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  if [[ $# = 2 ]]; then
    printf '%s\n' "${__bb_STRING:${__bb_POS}}"
  else
    printf '%s\n' "${__bb_STRING:${__bb_POS}:${__bb_LEN}}"
  fi
}

# ---
# Examples:
#  $ String_split 'aa:bb:cc' ':' xs  && declare -p xs
#  declare -a xs=([0]="aa" [1]="bb" [2]="cc")
#  ---
#  $ String_split 'aa::bb:' ':' xs  && declare -p xs
#  declare -a xs=([0]="aa" [1]="" [2]="bb" [3]="")
#  ---
#  $ String_split 'aa[*]bb[*]cc' '[*]' xs  && declare -p xs
#  declare -a xs=([0]="aa" [1]="bb" [2]="cc")
#  ---
#  $ String_split 'foo?bar?baz' '?' xs  && declare -p xs
#  declare -a xs=([0]="foo" [1]="bar" [2]="baz")
# ---
function String_split {
  local __bb_USAGE="Usage: String_split STRING SEP ARRAY";
  [[ $# = 3 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_STRING="$1"     && shift 1
  local __bb_SEP="$1"        && [[ -n "$1" ]] && shift 1 || { echo "String_split: SEP must be non-empty" 1>&2; return 2; }
  local __bb_ARRAY_NAME="$1" && Array_make -u "${__bb_USAGE}" "$1" && shift 1 || return 3;
  # ---
  local -n __bb_ssp_ARRAY="${__bb_ARRAY_NAME}"
  # ---
  local __bb_N=${#__bb_STRING}
  local __bb_M=${#__bb_SEP}
  local __bb_I=0
  local __bb_J=0
  # ---
  while (( __bb_I + __bb_M <= __bb_N )); do
    if [[ "${__bb_STRING:__bb_I:__bb_M}" = "${__bb_SEP}" ]]; then
      __bb_ssp_ARRAY+=("${__bb_STRING:__bb_J:__bb_I-__bb_J}")
      ((__bb_I += __bb_M))
      __bb_J=$__bb_I
    else
      ((__bb_I++))
    fi
  done
  __bb_ssp_ARRAY+=("${__bb_STRING:__bb_J}")
}

# ---
# String_concat SEP [STRING]... 
#   concatenates the list of strings, inserting the separator string SEP between each.
# ---
# Examples:
#   $ String_concat ', ' aa bb cc
#   aa, bb, cc
#   ---
#   $ String_concat '--' 'aa bb' 'cc' ''
#   aa bb--cc--
#   ---
#   $ String_concat ''
#      (empty line)
#   ---
#   $ String_concat '' aa bb cc
#   aabbcc
# ---
function String_concat {
  local __bb_USAGE="Usage: String_concat SEP [STRING]...";
  [[ $# -ge 1 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_SEP="$1" && shift 1
  # ---
  local __bb_X
  local __bb_PREFIX=""
  # ---
  for __bb_X in "$@"; do
    printf '%s' "${__bb_PREFIX}${__bb_X}"
    __bb_PREFIX="${__bb_SEP}"
  done
  printf '\n'
}

# ---
# Examples:
#   $ String_concat_assign s ', ' aa bb cc  && echo "$s"
#   aa, bb, cc
#   ---
#   $ String_concat_assign s '--' 'aa bb' 'cc' ''  && echo "$s"
#   aa bb--cc--
#   ---
#   $ String_concat_assign s ''  && test -z "$s" && echo 'EMPTY'
#   EMPTY
# ---
function String_concat_assign {
  local __bb_USAGE="Usage: String_concat_assign VARNAME SEP [STRING]...";
  [[ $# -ge 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_VARNAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  local __bb_SEP="$1"     && shift 1
  # ---
  local -n __bb_sco_VAR="${__bb_VARNAME}"
  local __bb_OUT=""
  local __bb_X
  local __bb_PREFIX=""
  # ---
  for __bb_X in "$@"; do
    __bb_OUT+="${__bb_PREFIX}${__bb_X}"
    __bb_PREFIX="${__bb_SEP}"
  done
  __bb_sco_VAR="${__bb_OUT}"
}

### ---------------------------------------------
###              String_scanf
### ---------------------------------------------
# ---
# Poor-man scanf in Bash:
# ---
# Examples:
#  $ String_scanf "room-unif-an25-2049" "room-(.*)-an25-(.*)" A B  &&  echo $A:$B  
#  unif:2049
#  $ String_scanf "room-unif-an25-2049" "room-.*-(..)[1-9][0-9]*-.*" TYPE  && echo $TYPE
#  an
# ---
function String_scanf {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: String_scanf STRING REGEXP VAR...";
  # ---
  local __bb_STRING="$1"
  local __bb_REGEXP="$2"
  # ---
  [[ $# -ge 3 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  shift 2
  # ---
  [[ ${__bb_STRING} =~ ${__bb_REGEXP} ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_GROUPS_NB=$((${#BASH_REMATCH[@]} - 1))
  [[ ${__bb_GROUPS_NB} -eq $# ]] || { 
    echo "The number of groups (${__bb_GROUPS_NB}) differs from the number of variables ($#)" 1>&2;
    echo "${__bb_USAGE}" 1>&2; return 3; 
    }
  # ---
  local __bb_group=1
  local __bb_scf_VARNAME
  for __bb_scf_VARNAME in "$@"; do
    local -n __scanf_ref=${__bb_scf_VARNAME}        || return 4
    __scanf_ref=${BASH_REMATCH[__bb_group++]} || return 5
  done
  # ---
  return 0
}
alias String.match=String_scanf

### ---------------------------------------------
###             String_capture 
### ---------------------------------------------
# ---
# Example:
#  $ String_capture X echo hello world
#  $ echo $X
#  hello world
#  ---
#  $ String_capture -t /tmp/capture.txt RESULT my_func arg1 arg2
#  $ String_capture X cat /etc/fstab
# ---
function String_capture {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: String_capture [-k|--keep-nl|--keep-newlines] [-t|--tmpfile TMPFILE] VARNAME COMMAND..";
  # ---
  local __bb_KEEP_NL
  if [[ "$1" = "-k" || "$1" = "--keep-nl" || "$1" = "--keep-newlines" ]]; then __bb_KEEP_NL="y"; shift 1; fi
  # ---
  local __bb_TMPFILE __bb_TMPFILE_PROVIDED
  if [[ $1 = "-t" || $1 = "--tmpfile" ]]; then
    __bb_TMPFILE="$2";
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 4; }
    __bb_TMPFILE_PROVIDED=y
  fi
  # ---
  declare -n __bb_cap_varname="$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  [[ $# -gt 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  if [[ -z "${__bb_TMPFILE}" ]]; then
    local __bb_mktemp_TEMPLATE=/tmp/String_capture.XXXXXX
    __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 2
  fi
  # ---
  local __bb_CODE=0
  # ---
  local __bb_CMD="$1"; shift 1
  "${__bb_CMD}" "$@" 1>"${__bb_TMPFILE}" || __bb_CODE=$?
  # ---
  if [[ ${__bb_KEEP_NL} = y ]]; then
    local __bb_line
    unset __bb_cap_varname
    while IFS= read -r __bb_line; do __bb_cap_varname+="${__bb_line}"$'\n'; done <"${__bb_TMPFILE}"
  else  
    __bb_cap_varname=$(<"${__bb_TMPFILE}")
  fi  
  # ---
  [[ ${__bb_TMPFILE_PROVIDED} = y ]] || rm -f "${__bb_TMPFILE}"
  # ---
  return ${__bb_CODE}
}
alias String.no_subshell_substitution=String_capture



# ---
# Initially generated by https://www.perplexity.ai/, then marginally edited.
# ---
function String_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh  
Path_*: helpers to manipulate strings
---
* String_is_prefix
  Usage:
      String_is_prefix PREFIX STRING
  Description:
      Returns 0 if PREFIX is a literal prefix of STRING, non-zero otherwise.
      The test is purely positional: it does not interpret any glob or
      regular expression characters in PREFIX.
  Aliases:
      String.starts_with
  Examples:
      String_is_prefix foo foobar       # 0
      String_is_prefix '' foobar        # 0 (empty string is a prefix)
      String_is_prefix foo barfoo       # 1
      String_is_prefix 'a*b' 'a*bc'     # 0 (literal match, not a glob)
---
* String_is_suffix
  Usage:
      String_is_suffix SUFFIX STRING
  Description:
      Returns 0 if SUFFIX is a literal suffix of STRING, non-zero otherwise.
      The test is purely positional: it does not interpret any glob or
      regular expression characters in SUFFIX.
  Aliases:
      String.ends_with
  Examples:
      String_is_suffix bar foobar       # 0
      String_is_suffix '' foobar        # 0 (empty string is a suffix)
      String_is_suffix foo foobar       # 1
      String_is_suffix 'a*b' 'xxa*b'    # 0 (literal match, not a glob)
---
* String_lowercase
  Usage:
      String_lowercase [STRING]...
  Description:
      Prints each argument converted to lowercase, one per line.
      Case conversion is applied independently to each positional parameter.
      With no arguments, prints an empty line.
  Examples:
      String_lowercase 'HeLLo' 'WoRLD'
      # hello
      # world
---
* String_capitalize
  Usage:
      String_capitalize [STRING]...
  Description:
      Prints each argument with its first character converted to uppercase,
      leaving the remainder unchanged, one result per line.
      Note: this is NOT a full "title case" or "capitalize all words"
      operation; only the first character of each STRING is modified.
  Examples:
      String_capitalize 'hello' 'wORLD'
      # Hello
      # WORLD
      String_capitalize 'heLLo'
      # HeLLo
---
* String_uppercase
  Usage:
      String_uppercase [STRING]...
  Description:
      Prints each argument converted to uppercase, one per line.
      Case conversion is applied independently to each positional parameter.
  Examples:
      String_uppercase 'HeLLo' 'WoRLD'
      # HELLO
      # WORLD
---
* String_length
  Usage:
      String_length [STRING]...
  Description:
      For each argument, prints the length (number of characters) on its own
      line. When multiple arguments are provided, you get one length per line
      in the same order.
  Examples:
      String_length 'abc' '' 'hé'
      # 3
      # 0
      # 2   (byte-count semantics in Bash)
---
* String_sub
  Usage:
      String_sub STRING POS [LEN]
  Description:
      Extracts a substring from STRING using Bash's substring expansion.
      POS is a signed integer offset:
        - POS >= 0: offset from the beginning (0-based),
        - POS < 0: offset from the end.
      If LEN is provided, it must be a natural number (0,1,2,...) and at most
      LEN characters are returned. Without LEN, the substring from POS to the
      end of STRING is returned.

      Validation:
        - returns 1 if the number of arguments is not 2 or 3,
        - returns 2 if POS is not a valid integer,
        - returns 3 if LEN is provided but is not a natural number.

  Examples:
      String_sub abcdef 2       # cdef
      String_sub abcdef 2 3     # cde
      String_sub abcdef -2      # ef
      String_sub abcdef -4 2    # cd
      String_sub abcdef foo     # rc=2, stderr: Usage: String_sub STRING POS [LEN]
---
* String_split
  Usage:
      String_split STRING SEP ARRAY
  Description:
      Splits STRING on the literal separator SEP and stores the resulting
      fields into the indexed array ARRAY (created or recreated as needed).
      SEP is treated as a literal substring, not as a glob pattern; it may
      contain characters like '*', '?', '[' or ']'.
      Empty fields are preserved (e.g. leading, trailing, or consecutive
      separators all produce empty strings in the result).

      Return codes:
        - 1: invalid number of arguments,
        - 2: SEP is empty,
        - 3: ARRAY could not be created as an indexed array.

  Examples:
      String_split 'aa:bb:cc' ':' xs  && declare -p xs
      # declare -a xs=([0]="aa" [1]="bb" [2]="cc")

      String_split 'aa::bb:' ':' xs  && declare -p xs
      # declare -a xs=([0]="aa" [1]="" [2]="bb" [3]="")

      String_split 'aa[*]bb[*]cc' '[*]' xs  && declare -p xs
      # declare -a xs=([0]="aa" [1]="bb" [2]="cc")

      String_split 'foo?bar?baz' '?' xs  && declare -p xs
      # declare -a xs=([0]="foo" [1]="bar" [2]="baz")
---
* String_concat
  Usage:
      String_concat SEP [STRING]...
  Description:
      Concatenates all STRING arguments, inserting the separator SEP between
      each, and prints the resulting string followed by a newline.
      If no STRING is provided, prints an empty line.
      SEP may be empty, one character, or a longer substring.

  Examples:
      String_concat ', ' aa bb cc
      # aa, bb, cc

      String_concat '--' 'aa bb' 'cc' ''
      # aa bb--cc--

      String_concat ''
      # (empty line)

      String_concat '' aa bb cc
      # aabbcc
---
* String_concat_assign
  Usage:
      String_concat_assign VARNAME SEP [STRING]...
  Description:
      Concatenates all STRING arguments, inserting the separator SEP between
      each, and stores the resulting string into the scalar variable VARNAME.
      VARNAME must be a valid Bash identifier. The target variable is created
      or overwritten in the current shell environment.

      Return codes:
        - 1: not enough arguments,
        - 2: VARNAME is not a valid identifier.

  Examples:
      String_concat_assign X ', ' aa bb cc  && echo "$X"
      # aa, bb, cc

      String_concat_assign X '--' 'aa bb' 'cc' ''  && echo "$X"
      # aa bb--cc--

      String_concat_assign X ''  && test -z "$X" && echo 'EMPTY'
      # EMPTY
---
* String_scanf
  Usage:
      String_scanf STRING REGEXP VAR...
  Description:
      Poor-man scanf in Bash using regular-expression matching.
      Matches STRING against REGEXP using Bash's [[ STRING =~ REGEXP ]] syntax,
      and stores each captured group into the corresponding shell variable
      listed in VAR....

      More precisely:
        - REGEXP is a Bash ERE (extended regular expression) with one or more
          capturing groups `( ... )`.
        - After a successful match, BASH_REMATCH[1], ..., BASH_REMATCH[N]
          contain the captured substrings.
        - String_scanf expects exactly one VAR per capturing group and assigns
          each group to its corresponding variable name.

      Return codes:
        - 1: invalid number of arguments (missing STRING, REGEXP, or VARs),
        - 2: STRING does not match REGEXP,
        - 3: number of capturing groups differs from the number of variables,
        - 4: unable to create a nameref for one of the variables,
        - 5: unexpected error while assigning captured values.
  Aliases:
      String.match

  Examples:
      # Two capturing groups, two output variables
      String_scanf "room-unif-an25-2049" "room-(.*)-an25-(.*)" A B && echo "$A:$B"
      # unif:2049

      # One capturing group, one output variable
      String_scanf "room-unif-an25-2049" "room-.*-(..)[1-9][0-9]*-.*" TYPE && echo "$TYPE"
      # an

      # Mismatch between groups and variables
      String_scanf "abc-123" '(.*)-(.*)' X
      # stderr:
      # The number of groups (2) differs from the number of variables (1)
      # Usage: String_scanf STRING REGEXP VAR...
      # rc = 3

  Notes:
      - REGEXP is evaluated as a Bash regex, not as a literal string; any
        special regex characters (., *, +, ?, [...], etc.) must be escaped
        if they are meant literally.
      - All output variables are assigned in the current shell environment
        via namerefs; they must have valid Bash identifier names.
---
* String_capture
  Usage:
      String_capture [-k|--keep-nl|--keep-newlines] [-t|--tmpfile TMPFILE] VARNAME COMMAND...
  Description:
      Runs COMMAND with its arguments, captures its standard output, and stores
      the captured text into the scalar variable VARNAME without using command
      substitution (and without lanuching a subshell).

      By default, the captured content is assigned with:
          VARNAME=$(<TMPFILE)
      so trailing newlines are removed, just as with ordinary Bash command
      substitution.

      With -k or --keep-newlines, the temporary file is read line by line and
      reconstructed with explicit newline characters, so trailing newlines are
      preserved in the resulting variable.

      With -t or --tmpfile TMPFILE, TMPFILE is used as the capture file and is
      kept after the function returns. Otherwise, a temporary file is created
      under /tmp and removed automatically.

      The function returns the exit status of COMMAND, unless a usage or setup
      error occurs first.

      Return codes:
        - 1: invalid VARNAME or malformed argument list,
        - 2: could not create a temporary file,
        - 3: missing COMMAND,
        - 4: invalid use of -t / --tmpfile.

  Aliases:
      String.no_subshell_substitution

  Examples:
      String_capture X echo hello world
      echo "$X"
      # hello world

      String_capture X cat /etc/fstab
      printf '%s\n' "$X"
      # prints the captured file contents (without trailing final newlines)

      String_capture -k X printf 'a\nb\n\n'
      printf '%q\n' "$X"
      # $'a\nb\n\n'
      # (trailing newlines preserved)

      String_capture -t /tmp/capture.txt RESULT my_func arg1 arg2
      echo "$RESULT"
      # stdout of my_func arg1 arg2 is stored in RESULT,
      # and /tmp/capture.txt is kept

  Notes:
      - Only standard output is captured; standard error is left untouched.
      - As in Bash generally, variables containing embedded newlines should
        almost always be expanded with double quotes.      
EOF
  } 2>&1 | less
}

### ---------------------------------------------
###                Path
### ---------------------------------------------

# ---
function Path_is_absolute {
  local __bb_pir_NAME="$1"
  [[ -n ${__bb_pir_NAME} ]] || return 2
  # ---
  [[ -z "${__bb_pir_NAME##/*}" ]]
}

# ---
function Path_is_relative {
  local __bb_pir_NAME="$1"
  [[ -n ${__bb_pir_NAME} ]] || return 2
  # ---
  [[ -n "${__bb_pir_NAME##/*}" ]]
}

# ---
# "Canonicalize" file names as done by `readlink -m' but without transforming relative names into absolute ones.
# This function is not complete: we are not able to canonicalize ancestors of "./" ($PWD).
# NOTE that the canonicalization always removes the trailing "/" :
# Example:
#   Path_canonicalize ./
#   .
#   Path_canonicalize .////aaa/foo.txt
#   ./aaa/foo.txt
#   Path_canonicalize ./aaa///..//bbb//..//ccc
#   ./ccc
#   Path_canonicalize /aaa//bbb//..//ccc
#   /aaa/ccc
# ---
function Path_canonicalize {
  # { set -x; trap 'set +x' RETURN; }
  type readlink 1>/dev/null || return 95	# Operation not supported
  # ---
  local __bb_pca_NAME="${1:-./}"
  # ---
  if Path_is_relative "${__bb_pca_NAME}"; then
    # ---
    local __bb_RNAME=$(readlink -m "${__bb_pca_NAME}")
    local  __bb_HERE=$(readlink -m ./)
    # ---
    if [[ "${__bb_RNAME}" = '/' && "${__bb_HERE}" = '/' ]]; then
      echo "."
      # return 1
    elif [[ "${__bb_RNAME}" = '/' ]]; then
      echo ".${__bb_HERE}" \
      | sed -e 's@/[^/][^/]*@/..@g' -e 's@^./..$@..@' -e 's@^./../@../@'
      # return 2
    elif [[ "${__bb_HERE}" = '/' ]]; then
      echo ".${__bb_RNAME}"
      # return 3
    elif String_is_prefix "${__bb_HERE}" "${__bb_RNAME}"; then
      echo "."${__bb_RNAME#$(echo "${__bb_HERE}")}
      # return 4
    elif String_is_prefix "${__bb_RNAME}" "${__bb_HERE}"; then
      echo "."${__bb_HERE#$(echo "${__bb_RNAME}")} \
      | sed -e 's@/[^/][^/]*@/..@g' -e 's@^./..$@..@' -e 's@^./../@../@'
      # return 5
    else  
      local __bb_BASENAME=$(basename "${__bb_pca_NAME}")
      local  __bb_DIRNAME=$(dirname  "${__bb_pca_NAME}")
      echo "$(Path_canonicalize ${__bb_DIRNAME})/${__bb_BASENAME}"
      # return 6
    fi
  else
    # Path is absolute:
    readlink -m ${__bb_pca_NAME}
    # return 7
  fi
}


# Initially generated by https://www.perplexity.ai/, then marginally edited.

function Path_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh  
Path_*: helpers to manipulate pathnames
---
* Path_is_relative
  Usage:
      Path_is_relative PATH
  Description:
      Returns 0 if PATH is a non-empty relative pathname (does not start
      with '/'), non-zero otherwise.
      More precisely:
        - returns 2 if PATH is empty,
        - returns 0 if PATH does not begin with '/',
        - returns non-zero if PATH begins with '/' (absolute path).
      Intended as a fast predicate before applying relative-path-specific
      logic.
  Examples:
      Path_is_relative foo          # 0
      Path_is_relative ./foo        # 0
      Path_is_relative ../foo       # 0
      Path_is_relative /etc/passwd  # 1
      Path_is_relative ''           # 2 (empty argument)

---
* Path_is_absolute
  Usage:
      Path_is_absolute PATH
  Description:
      Returns 0 if PATH is a non-empty absolute pathname (starts with '/'),
      non-zero otherwise.
      More precisely:
        - returns 2 if PATH is empty,
        - returns 0 if PATH begins with '/',
        - returns non-zero if PATH does not begin with '/' (relative path).
      Complements Path_is_relative.
  Examples:
      Path_is_absolute /etc/passwd  # 0
      Path_is_absolute /            # 0
      Path_is_absolute foo          # 1
      Path_is_absolute ./foo        # 1
      Path_is_absolute ''           # 2 (empty argument)

---
* Path_canonicalize
  Usage:
      Path_canonicalize [PATH]
  Description:
      Canonicalizes PATH in a way similar to 'readlink -m', but with one
      important difference:
        - relative paths are kept relative to the current directory ('./'),
          instead of being turned into absolute paths.
      The normalization:
        - collapses redundant '/' and '.' segments,
        - resolves internal '..' segments as far as possible,
        - always removes a trailing '/' (except for the root '/').
      For absolute paths, it delegates directly to 'readlink -m PATH'.
      When PATH is omitted, it defaults to "./" and prints ".".

      Return codes:
        - 0: success, canonical path printed on stdout,

  Examples:
      # Default argument: "./"
      Path_canonicalize
      # .
      Path_canonicalize ./
      # .

      # Normalize redundant slashes and '.' for a relative path
      Path_canonicalize .////aaa/foo.txt
      # ./aaa/foo.txt

      # Resolve '..' inside a relative path
      Path_canonicalize ./aaa///..//bbb//..//ccc
      # ./ccc

      # Absolute path: behaves like readlink -m
      Path_canonicalize /aaa//bbb//..//ccc
      # /aaa/ccc

      # A correct number of '..' above the current directory
      (mkdir -p /tmp/a/b/c; cd /tmp/a/b/c; Path_canonicalize ../../..)
      # ../../..

      # Too many '..' above the current directory
      (mkdir -p /tmp/a/b/c; cd /tmp/a/b/c; Path_canonicalize ../../../../../../../../../../)
      ../../../..
EOF
  } 2>&1 | less
}


### ---------------------------------------------
###                    Json
### ---------------------------------------------
###
### Convention:
### 
### - Json_to_array stores each JSON array element as a string suitable for Array_to_json.
### - Json_to_set   stores each JSON array element as a string suitable for Set_to_json.
### - Json_to_map   stores each JSON object value as a string suitable for  Map_to_json.
### 
### - By default, each element/value is stored as canonical JSON text.
### 
### - With -r|--raw, JSON strings are stored as raw Bash strings, while other
###   JSON values are still stored as canonical JSON text.
### 
### - Array_to_json / Set_to_json / Map_to_json interpret stored elements/values 
###   as JSON payloads.
###   With -s|--stringify|--no-parse-scalars, every elements/values is serialized 
###   as a JSON string.
###
### DEPENDENCIES:
### jq
### Array_make
### Array_to_set
### Set_make
### Set_to_array
### Map_make
### Map_iter
### String_capture
### Regexp_is_ident
### Declare_is_array
### Declare_is_map
### ---------------------------------------------

# ---
function Json_escape_string {
  local __bb_USAGE="Usage: Json_escape_string STRING";
  [[ $# = 1 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_S="$1"
  __bb_S=${__bb_S//\\/\\\\}
  __bb_S=${__bb_S//\"/\\\"}
  __bb_S=${__bb_S//$'\b'/\\b}
  __bb_S=${__bb_S//$'\f'/\\f}
  __bb_S=${__bb_S//$'\n'/\\n}
  __bb_S=${__bb_S//$'\r'/\\r}
  __bb_S=${__bb_S//$'\t'/\\t}
  # ---
  printf '%s' "${__bb_S}"
}

# ---
# Returns 0 iff the argument is a valid JSON value.
# Examples:
#   Json_is_value '42'         # 0
#   Json_is_value '"aaa"'      # 0
#   Json_is_value '{"x":1}'    # 0
#   Json_is_value '[1,2]'      # 0
#   Json_is_value 'aaa'        # 1
#   Json_is_value '42 51'      # 1
#   Json_is_value '"aa" "bb"'  # 1
# ---
function Json_is_value {
  [[ $# = 1 ]] || return 2
  [[ $(jq -n 'reduce inputs as $x (0; . + 1)' 2>/dev/null <<<"$1") = 1 ]]
}

# --- Similar to Json_is_value but reveals errors:
function Json_check {
  [[ $# = 1 ]] || return 2
  [[ $(jq -n 'reduce inputs as $x (0; . + 1)' <<<"$1") = 1 ]]
}

# ---
# Json_deep_typeof '"user"'
# "string"
# ---
# Json_deep_typeof '3.14'
# "number"
# ---
# Json_deep_typeof '{"user": {"name": "Alice", "age": 25, "graduate": true, "address":null }, "roles":[ "manager" ] }'
# {
#   "user" : { "name":"string", "age":"number", "graduate":"boolean", "address":"null" },
#   "roles": [ "string" ]
# }
# ---
# Json_deep_typeof '["apple","green","1.20"]'
# [ "string", "string", "string" ]
# ---
# Json_deep_typeof '["apple","green", 1.20]'
# [ "string", "string", "number" ]
# ---
function Json_deep_typeof {
  type jq 1>/dev/null || return 95	# Operation not supported
  if [[ $# = 0 ]]; then cat; else printf '%s\n' "$@"; fi | jq '
    def replace_with_type: 
        if   type == "object" then map_values(replace_with_type) 
        elif type == "array"  then map(replace_with_type) 
        else type 
        end;
    replace_with_type'
}
alias Json_inspect=Json_deep_typeof
alias Json.inspect=Json_deep_typeof

# ---
# Prints one of 'object', 'array', 'string', 'number', 'boolean', or 'null'
function Json_typeof {
  type jq 1>/dev/null || return 95	# Operation not supported
  if [[ $# = 0 ]]; then jq -r 'type'; else jq -r 'type' <<<"$*"; fi
}

# ---
# Examples:
# ---
#   Json_paths '"user"'
#   .
#   ---
#   Json_paths '3.14'
#   .
#   ---
#   Json_paths '{"user": {"name": "Alice", "age": 25, "graduate": true, "address":null }, "roles":[ "manager" ] }'
#   .
#   .user
#   .user.name
#   .user.age
#   .user.graduate
#   .user.address
#   .roles
#   .roles[0]
#   ---
#   Json_paths '["apple","green","1.20"]'
#   .
#   .[0]
#   .[1]
#   .[2]
#   ---
#   Json_paths '["apple","green", 1.20]'
#   .
#   .[0]
#   .[1]
#   .[2]
#   ---
#   $ MYJSON='{"user": {"full name": "Alice", "age": 25, "graduate": true, "address":null }, "roles":[ "manager" ] }'
#   $ echo "$MYJSON" | Json_paths
#   .
#   .user
#   .user["full name"]
#   .user.age
#   .user.graduate
#   .user.address
#   .roles
#   .roles[0]
#   $ echo "$MYJSON" | Json_paths --type number
#   .user.age
#   $ echo "$MYJSON" | Json_paths --leafs
#   .user["full name"]
#   .user.age
#   .user.graduate
#   .user.address
#   .roles[0]
#   $ echo "$MYJSON" | Json_paths --leafs --type number
#   .user.age
#   ---
#   $ ip -j addr show dev enp1s0f0 | Json.paths -k 'txq'
#   .[0].txqlen
#   ---
#   $ ip -j addr show dev enp1s0f0 | Json.paths -v '192[.]168[.]'
#   .[0].addr_info[0].local
#   .[0].addr_info[0].broadcast
#   ---
#   $ ip -j addr show dev enp1s0f0 | Json.paths -k local -l -v '192[.]168[.]'
#   .[0].addr_info[0].local
#   ---
#   $ ip -j addr show dev enp1s0f0 | Json.paths -a  -v '192[.]168[.]'
#   .[0].addr_info[0].local 192.168.1.29
#   .[0].addr_info[0].broadcast 192.168.1.255
#   ---
#   $ ip -j addr show dev enp1s0f0 | Json.paths -a -k local -l -v '192[.]168[.]'
#   .[0].addr_info[0].local 192.168.1.29
#   $ MYIP=$(ip -j addr show dev enp1s0f0 | Json.paths -a -k local -l -v '192[.]168[.]' | awk '{print $2}')
#   $ echo $MYIP
#   192.168.1.29
# ---
function Json_paths {
  # { set -x; trap 'set +x' RETURN; }
  type jq 1>/dev/null || return 95  # Operation not supported
  # ---
  local __bb_USAGE='Usage: Json_paths [-a|-append-val[ue]] [-h|--help] [-k|--key-regexp REGEXP] [-l|--leaf[s]] [-t|--type TYPE] [-v|--val-regexp REGEXP] [JSON...]
TYPE among: object, array, string, number, boolean, null'
  # ---
  local __bb_APPEND_VAL="false"
  if [[ $1 = "-a" || $1 = "--append-val" || $1 = "--append-value" ]]; then __bb_APPEND_VAL="true"; shift 1; fi
  # ---
  [[ $1 = '-h' || $1 = '--help' ]] && { echo "${__bb_USAGE}" 1>&2; return 0; }
  # ---
  local __bb_KEY_REGEXP
  if [[ $1 = "-k" || $1 = "--key-regexp" ]]; then 
    __bb_KEY_REGEXP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  fi
  # ---
  local __bb_LEAFS="false"
  if [[ $1 = "-l" || $1 = "--leaf" || $1 = "--leafs" ]]; then __bb_LEAFS="true"; shift 1; fi
  # ---
  local __bb_TYPE
  if [[ $1 = "-t" || $1 = "--type" ]]; then 
    __bb_TYPE="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 2; } 
    case "$__bb_TYPE" in
      object|array|string|number|boolean|null) ;;
      *) echo "${__bb_USAGE}" 1>&2; return 3;  ;;
    esac
  fi
  # ---
  local __bb_VAL_REGEXP
  if [[ $1 = "-v" || $1 = "--val-regexp" ]]; then 
    __bb_VAL_REGEXP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 4; } 
  fi
  # ---
  if [[ $# = 0 ]]; then cat; else printf '%s\n' "$@"; fi \
    | jq -r \
        --argjson append_val "${__bb_APPEND_VAL}" \
        --arg     wanted     "${__bb_TYPE}" \
        --argjson leafs      "${__bb_LEAFS}" \
        --arg     key_regexp "${__bb_KEY_REGEXP}" \
        --arg     val_regexp "${__bb_VAL_REGEXP}" '
    def object_child_path($p; $k):
      if $k | test("^[A-Za-z_][A-Za-z0-9_]*$") then
        if $p == "." then "." + $k else $p + "." + $k end
      else
        $p + "[" + ($k | @json) + "]"
      end;

    def array_child_path($p; $i):
      $p + "[" + ($i | tostring) + "]";

    def scalar_as_string:
      if type == "string" or type == "number" or type == "boolean" or type == "null"
      then tostring
      else empty
      end;

    def emit_if_selected($p):
      if   ($wanted == "" or type == $wanted)
      and (($leafs == false) or (type != "object" and type != "array"))
      and (($key_regexp == "") or ($p | test($key_regexp)))
      and (($val_regexp == "") or (.  | scalar_as_string | test($val_regexp)))
      then 
        (if ($append_val == false) 
         then ($p)
         else ($p + " " + (.  | scalar_as_string))
        end)
      else empty
      end;

    def json_paths($p):
      emit_if_selected($p),
      if type == "object" then
        to_entries[]
        | (.key) as $k
        | .value
        | json_paths(object_child_path($p; $k))
      elif type == "array" then
        to_entries[]
        | (.key) as $i
        | .value
        | json_paths(array_child_path($p; $i))
      else
        empty
      end;

    json_paths(".")'
}

# ---
# Examples:
#   $ Json_to_array '["aaa", 42, {"x":1}, [1,2]]' xs && declare -p xs
#   declare -a xs=([0]="\"aaa\"" [1]="42" [2]="{\"x\":1}" [3]="[1,2]")
#   ---
#   $ Json_to_array -r '["aaa", 42, {"x":1}, [1,2]]' xs && declare -p xs
#   declare -a xs=([0]="aaa" [1]="42" [2]="{\"x\":1}" [3]="[1,2]")
#   ---
#   declare MYJSON='["aaa",42,"42",false,"false",{"x":1,"y":{"z":"51"}},[1,2,"bbb",false]]'
#   $ Json_to_array    "$MYJSON" xs 
#   $ Json_to_array -r "$MYJSON" rs
#   $ declare -p xs, rs
#   declare -a xs=([0]="\"aaa\"" [1]="42" [2]="\"42\"" [3]="false" [4]="\"false\"" [5]="{\"x\":1,\"y\":{\"z\":\"51\"}}" [6]="[1,2,\"bbb\",false]")
#   declare -a rs=([0]="aaa" [1]="42" [2]="42" [3]="false" [4]="false" [5]="{\"x\":1,\"y\":{\"z\":\"51\"}}" [6]="[1,2,\"bbb\",false]")
#   ---
#   $ Array_to_json -s xs
#   ["\"aaa\"","42","\"42\"","false","\"false\"","{\"x\":1,\"y\":{\"z\":\"51\"}}","[1,2,\"bbb\",false]"]
#   $ Array_to_json -s rs
#   ["aaa","42","42","false","false","{\"x\":1,\"y\":{\"z\":\"51\"}}","[1,2,\"bbb\",false]"]
#   $ Array_to_json xs
#   ["aaa",42,"42",false,"false",{"x":1,"y":{"z":"51"}},[1,2,"bbb",false]]  # is "$MYJSON"
#   $ Array_to_json rs
#   ["aaa",42,42,false,false,{"x":1,"y":{"z":"51"}},[1,2,"bbb",false]]      # is not "$MYJSON"
# ---
function Json_to_array {
  # { set -x; trap 'set +x' RETURN; }
  type jq 1>/dev/null || return 95	# Operation not supported
  # ---
  local __bb_USAGE="Usage: Json_to_array [-r|--raw] JSON ARRAY";
  # ---
  local __bb_RAW
  if [[ $1 = "-r" || $1 = "--raw" ]]; then __bb_RAW=y; shift 1; fi
  # ---
  local __bb_jta_JSON="$1" && Json_check      "$1" && shift 1 || { echo "Not a valid JSON value" 1>&2; echo "${__bb_USAGE}" 1>&2; return 1; }
  local __bb_ARR_NAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "Not a valid identifier" 1>&2; echo "${__bb_USAGE}" 1>&2; return 2; }
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  type jq &>/dev/null || { echo "Json_to_array: jq: command not found" 1>&2; return 4; }
  # ---
  local -a __bb_sta_TMPARRAY
  if [[ -z ${__bb_RAW} ]]; then
    mapfile -t __bb_sta_TMPARRAY < <(
      jq -c '
        if type=="array" then .[]
        else error("expected a JSON array")
        end
      ' <<<"${__bb_jta_JSON}"
    ) || return 5
  else
    mapfile -t __bb_sta_TMPARRAY < <(
      jq -r '
        if type=="array" then
          .[] | if type=="string" then . else tojson end
        else
          error("expected a JSON array")
        end
      ' <<<"${__bb_jta_JSON}"
    ) || return 6
  fi
  # ---
  Array_make "${__bb_ARR_NAME}" "${__bb_sta_TMPARRAY[@]}" || return 7
  # ---
  return 0
}

# ---
# Examples:
# $ Json_to_set '["aaa", {"x":1}, {"x":1}, [1,2]]' S && declare -p S
# ---
# $ Json_to_set -r '["aaa", "bbb", {"x":1}]' S && declare -p S
# ---
function Json_to_set {
  # { set -x; trap 'set +x' RETURN; }
  type jq 1>/dev/null || return 95	# Operation not supported
  # ---
  local __bb_USAGE="Usage: Json_to_set [-r|--raw] JSON SET";
  # ---
  local __bb_RAW
  if [[ $1 = "-r" || $1 = "--raw" ]]; then __bb_RAW=y; shift 1; fi
  # ---
  local __bb_jts_JSON="$1" && Json_check      "$1" && shift 1 || { echo "Not a valid JSON value" 1>&2; echo "${__bb_USAGE}" 1>&2; return 1; }
  local __bb_SET_NAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "Not a valid identifier" 1>&2; echo "${__bb_USAGE}" 1>&2; return 2; }
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local -a __bb_jts_TMPARRAY  # jts stands for "Json_to_set"
  if [[ -z ${__bb_RAW} ]]; then
    Json_to_array "${__bb_jts_JSON}" __bb_jts_TMPARRAY || return 4
  else
    Json_to_array --raw "${__bb_jts_JSON}" __bb_jts_TMPARRAY || return 5
  fi
  # declare -p __bb_jts_TMPARRAY
  Array_to_set __bb_jts_TMPARRAY "${__bb_SET_NAME}" || return 6
  # ---
  return 0
}

# ---
# Examples:
#   $ declare MYJSON='{"Z":"aaa bbb","Y":42,"X":"42","W":false,"V":"false","U":null,"T":"null","S":{"x":1,"y":[1,2]}}'
#   $ Json_to_map    "$MYJSON" m
#   $ Json_to_map -r "$MYJSON" r
#   $ declare -p m r
#   declare -A m=([Z]="\"aaa bbb\"" [Y]="42" [X]="\"42\"" [W]="false" [V]="\"false\"" [U]="null" [T]="\"null\"" [S]="{\"x\":1,\"y\":[1,2]}" )
#   declare -A r=([Z]="aaa bbb" [Y]="42" [X]="42" [W]="false" [V]="false" [U]="null" [T]="null" [S]="{\"x\":1,\"y\":[1,2]}" )
#   ---
#   $ Map_to_json -s m && Map_to_json -s r
#   {"Z":"\"aaa bbb\"","Y":"42","X":"\"42\"","W":"false","V":"\"false\"","U":"null","T":"\"null\"","S":"{\"x\":1,\"y\":[1,2]}"}
#   {"Z":"aaa bbb","Y":"42","X":"42","W":"false","V":"false","U":"null","T":"null","S":"{\"x\":1,\"y\":[1,2]}"}
#   ---
#   $ Map_to_json m && Map_to_json r
#   {"Z":"aaa bbb","Y":42,"X":"42","W":false,"V":"false","U":null,"T":"null","S":{"x":1,"y":[1,2]}}
#   {"Z":"aaa bbb","Y":42,"X":42,"W":false,"V":false,"U":null,"T":null,"S":{"x":1,"y":[1,2]}}
#   ---
#   $ [[ $(Map_to_json m) = "$MYJSON" ]] && echo 'Exactly $MYJSON'
#   Exactly $MYJSON
# ---
function Json_to_map {
  # { set -x; trap 'set +x' RETURN; }
  type jq 1>/dev/null || return 95	# Operation not supported
  # ---
  local __bb_USAGE="Usage: Json_to_map [-r|--raw] JSON MAP";
  # ---
  local __bb_RAW
  if [[ $1 = "-r" || $1 = "--raw" ]]; then __bb_RAW=y; shift 1; fi
  # ---
  local __bb_jtm_JSON="$1" && Json_check      "$1" && shift 1 || { echo "Not a valid JSON value" 1>&2; echo "${__bb_USAGE}" 1>&2; return 1; }
  local __bb_MAP_NAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "Not a valid identifier" 1>&2; echo "${__bb_USAGE}" 1>&2; return 2; }
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  type jq &>/dev/null || { echo "Json_to_map: jq: command not found" 1>&2; return 4; }
  # ---
  local -a __bb_KV
  if [[ -z ${__bb_RAW} ]]; then
    # Important d'utiliser 'jq -r' ici:
    mapfile -t __bb_KV < <(
      jq -r '
        if type=="object" then
          to_entries[] | .key, (.value | tojson)
        else
          error("expected a JSON object")
        end
      ' <<<"${__bb_jtm_JSON}"
    ) || return 5
  else
            # (if (.value | type) == "string" then .value else (.value | tojson) end)
    mapfile -t __bb_KV < <(
      jq -r '
        if type=="object" then
          to_entries[]
          | .key,
            (if (.value | type) == "string" then .value else (.value | tojson) end)
        else
          error("expected a JSON object")
        end
      ' <<<"${__bb_jtm_JSON}"
    ) || return 6
  fi
  # ---
  Map_make "${__bb_MAP_NAME}" "${__bb_KV[@]}" || return 7
  # ---
  return 0
}

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Json_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh  
Json_*: helpers to manipulate JSON values as Bash's strings
---
* Json_is_value
  Usage:
      Json_is_value JSON
  Description:
      Checks whether the given string is a single valid JSON value.
      It internally feeds the string to jq in "inputs" mode and succeeds
      iff exactly one JSON value is parsed from the input.
      Returns:
        0 if JSON is a single valid JSON value,
        1 if parsing succeeds but does not yield exactly one value,
        2 on invalid usage (wrong number of arguments),
        non-zero if jq fails.
  Examples:
      Json_is_value '42'          # 0 (valid number)
      Json_is_value '"aaa"'       # 0 (valid string)
      Json_is_value '{"x":1}'     # 0 (valid object)
      Json_is_value '[1,2]'       # 0 (valid array)

      Json_is_value 'aaa'         # 1 (not valid JSON)
      Json_is_value '42 51'       # 1 (two values, not a single JSON value)
      Json_is_value '"aa" "bb"'   # 1 (two values)
---
* Json_check
  Usage:
      Json_check JSON
  Description:
      Similar to Json_is_value, but does not silence jq's parse errors.
      It lets jq report syntax errors on stderr, then checks whether exactly
      one JSON value was parsed from the input.
      Useful when you want both a boolean answer and jq's detailed error
      messages on malformed JSON.
      Returns:
        0 if JSON is a single valid JSON value,
        1 if parsing succeeds but does not yield exactly one value,
        2 on invalid usage (wrong number of arguments),
        non-zero if jq reports a parse error.
  Examples:
      Json_check '42'           # 0
      Json_check '{"x":1}'      # 0

      Json_check '{x:1}'        # non-zero, jq prints a parse error
      Json_check '42 51'        # 1 (two values)
---
* Json_escape_string
  Usage:
      Json_escape_string STRING
  Description:
      Escapes a plain Bash string so that it can safely be embedded as a JSON
      string literal payload (without the surrounding quotes).
      It:
        - doubles backslashes,
        - escapes double quotes,
        - replaces control characters \b, \f, \n, \r, \t with their JSON
          escape sequences: \\b, \\f, \\n, \\r, \\t.
      The result does not include surrounding double quotes; you are expected
      to add them yourself if you need a full JSON string token.
      Returns:
        0 on success, non-zero on invalid usage (wrong number of arguments).
  Examples:
      Json_escape_string 'Hello "World"\n'
      # prints: Hello \"World\"\\n

      s=$(Json_escape_string 'C:\Temp\foo.txt')
      printf '"%s"\n' "$s"
      # prints a valid JSON string literal: "C:\\Temp\\foo.txt"
---
* Json_deep_typeof
  Usage:
      Json_deep_typeof [JSON...]
  Description:
      Computes the "shape" of a JSON value by replacing each leaf by its
      JSON type, recursively.
      When called with no arguments, reads JSON from standard input.
      When called with arguments, concatenates them with newlines and feeds
      them to jq.
      The transformation:
        - if value is an object: applies Json_deep_typeof to each value and
          returns an object with the same keys, but with type-annotated values,
        - if value is an array: applies Json_deep_typeof to each element and
          returns the resulting array,
        - otherwise (scalar): returns one of:
            "object", "array", "string", "number", "boolean", "null".
      Aliases:
        Json_inspect, Json.inspect
      Dependencies:
        jq
      Returns:
        0 on success, 95 if jq is not available, non-zero on jq errors.
  Examples:
      Json_deep_typeof '"user"'  # "string"
      Json_deep_typeof '3.14'    # "number"

      Json_deep_typeof '{"user": {"name": "Alice", "age": 25, "graduate": true, "address": null}, "roles": ["manager"] }'
      # { "user":  { "name": "string", "age": "number", "graduate": "boolean", "address": "null" }, "roles": [ "string" ] }

      Json_deep_typeof '["apple","green","1.20"]' # [ "string", "string", "string" ]
      Json_deep_typeof '["apple","green", 1.20]'  # [ "string", "string", "number" ]
---
* Json_typeof
  Usage:
      Json_typeof [JSON...]
  Description:
      Prints the top-level JSON type of the given value:
        one of: object, array, string, number, boolean, null.
      When called without arguments, reads JSON from standard input and runs:
          jq -r 'type'
      When called with arguments, concatenates them into a single string and
      feeds that to jq.
      This is a thin wrapper around jq's built-in "type" filter.
      Returns:
        0 on success, 95 if jq is not available, non-zero on jq errors.
  Examples:
      Json_typeof '"hello"'  # string
      Json_typeof '42'       # number
      Json_typeof 'true'     # boolean
      Json_typeof 'null'     # null
      Json_typeof '{"x":1}'  # object
      Json_typeof '[1,2,3]'  # array

      echo '[1,2,3]' | Json_typeof  # array
---      
* Json_paths
  Usage:
      Json_paths [-a|--append-val[ue]] [-h|--help]
                 [-k|--key-regexp REGEXP]
                 [-l|--leaf|--leafs]
                 [-t|--type TYPE]
                 [-v|--val-regexp REGEXP]
                 [JSON...]

  Description:
      Enumerates all jq-style paths defined by a JSON value.
      By default, prints one path per line, starting from the root ".",
      and recursing into objects and arrays:
        - object fields: .user, .user.name, .user["full name"]
        - array elements: .[0], .users[3], .users[3].roles[1]

      The function can optionally:
        - filter paths by JSON value type (object, array, string, number,
          boolean, null),
        - restrict to leaf nodes only (scalar values),
        - filter paths by a regular expression on the path string,
        - filter values by a regular expression on the scalar value,
        - append the scalar value to each path (PATH VALUE).

      JSON can be provided as arguments (concatenated and fed to jq) or
      read from standard input when no JSON argument is given.

  Options:
      (Reminder: when several options are combined, they MUST appear 
       in alphabetical order: -a before -k, before -l, before -t,
       before -v.)

      -a, --append-val, --append-value
          Instead of printing just the path, print:
              PATH VALUE
          where VALUE is the scalar JSON value converted to a string
          (string, number, boolean, null) using jq's tostring.
          Non-scalar values (objects, arrays) are ignored by the
          value-regexp filter and are not printed with -a unless they
          also match the other filters and can be converted by
          scalar_as_string.

      -h, --help
          Print a short usage message and return.

      -k REGEXP, --key-regexp REGEXP
          Keep only paths whose jq-style path string matches REGEXP.
          The regexp is applied to the path string, e.g. ".user.age",
          ".roles[0]", ".user[\"full name\"]".
          When omitted, all paths pass this filter.

      -l, --leaf, --leafs
          Keep only leaf nodes, i.e. scalar JSON values:
          string, number, boolean, null.
          Objects and arrays are excluded even if they have no children.
          Can be combined with --type and the regex filters.

      -t TYPE, --type TYPE
          Filter by JSON value type at the end of the path.
          TYPE must be one of:
              object, array, string, number, boolean, null
          Without -t, all types are accepted (subject to other filters).

      -v REGEXP, --val-regexp REGEXP
          Keep only paths whose associated VALUE matches REGEXP.
          The regexp is applied to the scalar representation of VALUE:
            - strings, numbers, booleans and null are converted to
              strings (jq tostring),
            - objects and arrays do not match this filter (they are
              skipped by scalar_as_string).
          When omitted, all values pass this filter.

  Notes:
      - Path construction is robust to object keys containing special
        characters. Simple identifiers are printed as ".key", while
        other keys are printed as ["..."] with proper JSON escaping,
        e.g.:
          .user["full name"]
          .["a.b"]
          .["x[y]"]

      - Filters are combined with logical AND:
          *type filter* AND *leaf filter (if any)* AND
          *key-regexp (if any)* AND *val-regexp (if any)*.
        A path is printed only if all enabled filters succeed.

      - When used with -a/--append-val, the value printed is the same
        scalar value used by the value-regexp filter.

  Examples:

      # Basic enumeration of all paths
      MYJSON='{"user": {"full name": "Alice", "age": 25, "graduate": true, "address":null }, "roles":[ "manager" ] }'
      echo "$MYJSON" | Json_paths
      .
      .user
      .user["full name"]
      .user.age
      .user.graduate
      .user.address
      .roles
      .roles[0]

      # Filter by JSON type
      echo "$MYJSON" | Json_paths --type number
      .user.age

      echo "$MYJSON" | Json_paths --type string
      .user["full name"]
      .roles[0]

      # Leaf-only paths
      echo "$MYJSON" | Json_paths --leafs
      .user["full name"]
      .user.age
      .user.graduate
      .user.address
      .roles[0]

      # Leaf-only and numeric
      echo "$MYJSON" | Json_paths --leafs --type number
      .user.age

      # Filter by path regexp (key-regexp)
      # Example with "ip -j addr show" JSON output
      ip -j addr show dev enp1s0f0 | Json_paths -k 'txq'
      .[0].txqlen

      # Filter by value regexp (val-regexp)
      ip -j addr show dev enp1s0f0 | Json_paths -v '192[.]168[.]'
      .[0].addr_info[0].local
      .[0].addr_info[0].broadcast

      # Combine key and value regexp, leaves only
      ip -j addr show dev enp1s0f0 | Json_paths -k local -l -v '192[.]168[.]'
      .[0].addr_info[0].local

      # Append scalar values with -a
      ip -j addr show dev enp1s0f0 | Json_paths -a -v '192[.]168[.]'
      .[0].addr_info[0].local 192.168.1.29
      .[0].addr_info[0].broadcast 192.168.1.255

      # Append value, restrict to 'local' leaves matching 192.168.*.*
      ip -j addr show dev enp1s0f0 | Json_paths -a -k local -l -v '192[.]168[.]'
      .[0].addr_info[0].local 192.168.1.29

      # Extract the local IPv4 address into a shell variable
      MYIP=$(ip -j addr show dev enp1s0f0 | Json_paths -a -k local -l -v '192[.]168[.]' | awk "{print $2}")
      echo "$MYIP"
      # 192.168.1.29
---
* Json_to_array
  Usage:
      Json_to_array [-r|--raw] JSON ARRAY
  Description:
      Parses a JSON array and stores its elements into a Bash indexed array
      named ARRAY, in a form suitable for later reconstruction by
      Array_to_json.

      Conventions:
        - Without -r/--raw:
            each element of the JSON array is stored as canonical JSON text
            (compact tojson form) in ARRAY[i].
        - With -r/--raw:
            if the JSON element is a string: store the raw Bash string;
            otherwise: store the element as canonical JSON text.
        - Array_to_json interprets elements as JSON payloads by default,
          reconstructing the original JSON array if elements were stored
          consistently; with -s|--stringify, every element is serialized
          as a JSON string instead.

      Constraints:
        - JSON must be a single JSON value representing an array, otherwise
          the function fails with an error.
        - ARRAY must be a valid Bash identifier, and is (re)created as an
          indexed array.

      Dependencies:
        jq, Json_check, Regexp_is_ident, Array_make.

      Returns:
        0 on success,
        1 if JSON is not a valid JSON value,
        2 if ARRAY is not a valid identifier,
        3 on extra arguments,
        4 if jq is missing,
        5 if JSON is not an array (jq error),
        6 if Array_make fails.

  Examples:
      # Simple array: all elements stored as canonical JSON strings
      Json_to_array '["aaa", 42, {"x":1}, [1,2]]' xs && declare -p xs
      # declare -a xs=(
      #   [0]="\"aaa\""
      #   [1]="42"
      #   [2]="{\"x\":1}"
      #   [3]="[1,2]"
      # )

      # With -r: JSON strings become raw Bash strings
      Json_to_array -r '["aaa", 42, {"x":1}, [1,2]]' xs && declare -p xs
      # declare -a xs=(
      #   [0]="aaa"
      #   [1]="42"
      #   [2]="{\"x\":1}"
      #   [3]="[1,2]"
      # )

      declare MYJSON='["aaa",42,"42",false,"false",{"x":1,"y":{"z":"51"}},[1,2,"bbb",false]]'
      Json_to_array "$MYJSON" xs
      Json_to_array -r "$MYJSON" rs
      declare -p xs rs
      # xs contains canonical JSON payloads,
      # rs stores strings as raw Bash strings, others as JSON.

      # Round-trip with Array_to_json (-s serializes every element as a JSON string):
      Array_to_json -s xs
      # ["\"aaa\"","42","\"42\"","false","\"false\"","{\"x\":1,\"y\":{\"z\":\"51\"}}","[1,2,\"bbb\",false]"]

      Array_to_json -s rs
      # ["aaa","42","42","false","false","{\"x\":1,\"y\":{\"z\":\"51\"}}","[1,2,\"bbb\",false]"]

      # By default, elements are interpreted as JSON payloads, reconstructing the array:
      Array_to_json xs
      # ["aaa",42,"42",false,"false",{"x":1,"y":{"z":"51"}},[1,2,"bbb",false]]
      # == $MYJSON
---
* Json_to_set
  Usage:
      Json_to_set [-r|--raw] JSON SET
  Description:
      Parses a JSON array and stores its elements into a Bash set (associative
      array) named SET, suitable for use with Set_to_json.

      Conventions:
        - Internally uses Json_to_array to parse the JSON array into a
          temporary indexed array.
        - Then uses Array_to_set to build the set SET where each distinct
          element becomes a key.
        - Without -r/--raw:
            elements are stored as canonical JSON text strings.
        - With -r/--raw:
            JSON strings are stored as raw Bash strings; non-strings are
            stored as canonical JSON text.

      Constraints:
        - JSON must be a single JSON value representing an array.
        - SET must be a valid Bash identifier; it is created/updated as a
          set (associative array with dummy value "1" for each key).

      Dependencies:
        jq, Json_check, Regexp_is_ident, Json_to_array, Array_to_set.

      Returns:
        0 on success,
        1 if JSON is not a valid JSON value,
        2 if SET is not a valid identifier,
        3 on extra arguments,
        4 if Json_to_array fails,
        5 if Array_to_set fails.

  Examples:
      # Build a set from JSON array, with canonical JSON payloads
      Json_to_set '["aaa", {"x":1}, {"x":1}, [1,2]]' S && declare -p S
      # S contains keys for "aaa", {"x":1}, [1,2] (deduplicated)

      # Build a set with raw strings
      Json_to_set -r '["aaa", "bbb", {"x":1}]' S && declare -p S
      # JSON strings "aaa"/"bbb" are stored as raw Bash strings "aaa"/"bbb",
      # the object {"x":1} is stored as its JSON representation.
---
* Json_to_map
  Usage:
      Json_to_map [-r|--raw] JSON MAP
  Description:
      Parses a JSON object and stores its key/value pairs into a Bash
      associative array MAP, suitable for use with Map_to_json.

      Conventions:
        - Keys: stored as plain strings (jq .key).
        - Values:
            * without -r/--raw:
                each value is stored as canonical JSON text using jq tojson;
            * with -r/--raw:
                if the JSON value is a string, store it as a raw Bash string;
                otherwise store the value as canonical JSON text.
        - Map_to_json interprets MAP values as JSON payloads by default,
          reconstructing a JSON object from the parsed payloads; with
          -s|--stringify, every value is serialized as a JSON string instead.

      Constraints:
        - JSON must be a single JSON value representing an object.
        - MAP must be a valid Bash identifier; it is (re)created as an
          associative array.

      Dependencies:
        jq, Json_check, Regexp_is_ident, Map_make.

      Returns:
        0 on success,
        1 if JSON is not a valid JSON value,
        2 if MAP is not a valid identifier,
        3 on extra arguments,
        4 if jq is missing,
        5 if JSON is not an object (jq error),
        6 if Map_make fails.

  Examples:
      declare MYJSON='{"Z":"aaa bbb","Y":42,"X":"42","W":false,"V":"false","U":null,"T":"null","S":{"x":1,"y":[1,2]}}'

      # Canonical JSON text for all values
      Json_to_map "$MYJSON" m

      # Raw strings for JSON strings, JSON text for others
      Json_to_map -r "$MYJSON" r

      declare -p m r
      # m: values are all canonical JSON text ("aaa bbb", 42, "42", false, ...)
      # r: string values are raw strings, non-strings are JSON text

      # Serialize every value as a JSON string with -s:
      Map_to_json -s m
      # {"Z":"\"aaa bbb\"","Y":"42","X":"\"42\"","W":"false","V":"\"false\"",
      #  "U":"null","T":"\"null\"","S":"{\"x\":1,\"y\":[1,2]}"}

      Map_to_json -s r
      # {"Z":"aaa bbb","Y":"42","X":"42","W":"false","V":"false","U":"null",
      #  "T":"null","S":"{\"x\":1,\"y\":[1,2]}"}

      # By default, values are interpreted as JSON payloads:
      Map_to_json m
      # {"Z":"aaa bbb","Y":42,"X":"42","W":false,"V":"false","U":null,"T":"null",
      #  "S":{"x":1,"y":[1,2]}}

      Map_to_json r
      # {"Z":"aaa bbb","Y":42,"X":42,"W":false,"V":false,"U":null,"T":null,
      #  "S":{"x":1,"y":[1,2]}}

      [[ $(Map_to_json m) = "$MYJSON" ]] && echo "Exactly MYJSON"
      # Exactly MYJSON
EOF
  } 2>&1 | less
}

### ---------------------------------------------
###          trap_EXIT      (MrProper)
### ---------------------------------------------

# Global stack (array) of cleanup commands executed on EXIT (LIFO).
# Each element is a shell command (string) to be eval'ed.
declare -ag __trap_EXIT_stack # =()
declare -ag __trap_EXIT_cleanup_verbose=n # y
shopt -s expand_aliases

# ---
function trap_EXIT_cleanup {
  # Preserve original exit status:
  local __bb_CODE=$?
  # ---
  # Execute registered cleanup commands in LIFO order:
  local __bb_i
  for (( __bb_i=${#__trap_EXIT_stack[@]}-1; __bb_i>=0; __bb_i-- )); do
    # Ignore errors in cleanup commands to not mask the original status:
    eval "${__trap_EXIT_stack[__bb_i]}" || true
  done
  # ---
  if [[ ${__trap_EXIT_cleanup_verbose} = y ]]; then
    { echo -en "---\ntrap_EXIT_cleanup: OLD stack:\n\t"; declare -p __trap_EXIT_stack; } 1>&2
  fi  
  # ---
  declare -ag __trap_EXIT_stack=()
  # ---
  if [[ ${__trap_EXIT_cleanup_verbose} = y ]]; then
    { echo -en "---\ntrap_EXIT_cleanup: NEW stack:\n\t"; declare -p __trap_EXIT_stack; } 1>&2
  fi  
  # ---
  # Restore original exit status:
  return "${__bb_CODE}"
}
alias MrProper=trap_EXIT_cleanup
alias MrProper_cleanup=trap_EXIT_cleanup
alias MrClean=trap_EXIT_cleanup

# ---
function trap_EXIT_show_stack {
  # ---
  { echo -en "---\ntrap_EXIT_show_stack: CURRENT stack:\n    "; 
    declare -p __trap_EXIT_stack; 
    echo "---"; 
    } | sed -e 's@\[@\n\t[@g' -e 's@")$@"\n\t)@g' 1>&2
  # ---
  return 0
}
alias MrProper_show=trap_EXIT_show_stack
alias MrClean_show=trap_EXIT_show_stack

# ---
# Append a new cleanup command to the stack.
# The argument is expected to be a single, properly quoted shell command.
# ---
# Example: 
#   source bashbricks.sh 
#   trap 'echo AAA' EXIT
#   trap 'echo AAA >> /tmp/51' EXIT
#   trap_EXIT_push 'echo BBB >> /tmp/51'
#   trap_EXIT_push 'echo CCC >> /tmp/51'
#   cat /tmp/51
#   cat: /tmp/51: No such file or directory
#   exit 
#   ### Now, in another terminal:
#   cat /tmp/51
#   CCC
#   BBB
#   AAA
# ---
function trap_EXIT_push {
  local __bb_EXISTING_TRAPCMD
  # ---
  # On first push, capture the currently installed EXIT trap, if any,
  # and append it to the stack so it will still run after our cleanup stack.
  if (( ${#__trap_EXIT_stack[@]} == 0 )); then
    # ---
    __bb_EXISTING_TRAPCMD=$(echo "$(trap -p EXIT)" | sed -e "s@^trap -- '@@" -e "s@' EXIT\$@@")
    # ---
    # If an EXIT trap already exists, preserve its action by pushing it first.
    # Since cleanup runs in LIFO order, this preserved action will run last.
    if [[ -n "${__bb_EXISTING_TRAPCMD}" && "${__bb_EXISTING_TRAPCMD}" != trap_EXIT_cleanup ]]; then
      __trap_EXIT_stack+=("${__bb_EXISTING_TRAPCMD}")
    fi
    # ---
    # Install EXIT trap the first time we push something:
    trap trap_EXIT_cleanup EXIT
  fi
  # ---
  # Push the new cleanup action:
  __trap_EXIT_stack+=("$1")
  # ---
  declare -p __trap_EXIT_stack 1>&2
}
alias MrProper_push=trap_EXIT_push
alias MrClean_push=trap_EXIT_push

### ---------------------------------------------
###                OneshotChannel
### ---------------------------------------------
###
### DEPENDENCIES: 
###   trap_EXIT_{push}
### ---------------------------------------------

# ---
# Examples: 
#   ---
#   $ OneshotChannel_make FIFO
#   $ for i in 42 43 44; do echo "Hello world $i" > /tmp/$i; done
#   $ OneshotChannel_send FIFO /tmp/42 /tmp/43 /tmp/44
#   $ OneshotChannel_receive FIFO
#   Hello world 42
#   Hello world 43
#   Hello world 44
#   ---
#   Avec plusieurs send, l'ordre FIFO n'est plus garantit (les écrivains en attente seront
#   en concurrence pour écrire sur le canal dès que le lecteur se mettra en réception) :
#   ---
#   $ OneshotChannel_make FIFO
#   $ OneshotChannel_send FIFO /tmp/42
#   $ OneshotChannel_send_args FIFO aaa
#   $ OneshotChannel_send FIFO /tmp/44
#   $ OneshotChannel_send_args FIFO AAA
#   $ OneshotChannel_receive FIFO
#   AAA
#   aaa
#   Hello world 44
#   Hello world 42
# ---
function OneshotChannel_make {
  # { set -x; trap 'set +x;' RETURN; }
  # ---
  local __bb_omk_channel_ref
  declare -n __bb_omk_channel_ref=$1  # ref (-n)
  # ---
  local __bb_TMPFIFO
  local __bb_mktemp_TEMPLATE=/tmp/OneshotChannel.XXXXXX
  # ---
  # grep -q "^[A-Za-z0-9_]*$" <<<"$1" || return 1
  Regexp_is_ident "$1" || return 1
  # ---
  __bb_TMPFIFO=$(mktemp -u ${__bb_mktemp_TEMPLATE}) || return 2
  mkfifo -- "${__bb_TMPFIFO}" || return 3
  # ---
  # Register FIFO cleanup on EXIT (LIFO stack):
  trap_EXIT_push "rm -f -- ${__bb_TMPFIFO}"
  # ---
  __bb_omk_channel_ref=${__bb_TMPFIFO}
}

# ---
function OneshotChannel_send_args {
  # ---
  # { set +m; set -x; trap 'set -m; set +x;' RETURN; }
  { set +m; trap 'set -m' RETURN; }
  # ---
  local __bb_SYNC
  if [[ $1 = "-s" || $1 = "--sync" || $1 = "--synchronize" ]]; then __bb_SYNC="y"; shift 1; fi
  # ---
  local __bb_osa_channel_ref
  declare -n __bb_osa_channel_ref=$1  # ref (-n)
  local __bb_TMPFIFO=$__bb_osa_channel_ref
  shift 1 || return 1
  # ---
  [[ -p ${__bb_TMPFIFO} ]] || return 2
  # ---
  local __bb_i
  if [[ ${__bb_SYNC} = y ]]; then
     for __bb_i in "$@"; do echo "${__bb_i}"; done > ${__bb_TMPFIFO}
  else
    (for __bb_i in "$@"; do echo "${__bb_i}"; done > ${__bb_TMPFIFO}) &
  fi 2>/dev/null # silent bg
  # ---
  return 0
}

# ---
function OneshotChannel_send {
  # ---
  # { set +m; set -x; trap 'set -m; set +x;' RETURN; }
  { set +m; trap 'set -m' RETURN; }
   # ---
  local __bb_SYNC
  if [[ $1 = "-s" || $1 = "--sync" || $1 = "--synchronize" ]]; then __bb_SYNC="y"; shift 1; fi
  # ---
  local __bb_ose_channel_ref
  declare -n __bb_ose_channel_ref=$1  # ref (-n)
  local __bb_TMPFIFO=$__bb_ose_channel_ref
  shift 1 || return 1
  # ---
  [[ -p ${__bb_TMPFIFO} ]] || return 2
  # ---
  if [[ ${__bb_SYNC} = y ]]; then
    cat "$@" > ${__bb_TMPFIFO}
  else
    cat "$@" | { (cat > ${__bb_TMPFIFO})& }
  fi 2>/dev/null # silent bg
  # ---
  return 0
}

# ---
function OneshotChannel_receive {
  # ---
  # { set +m; set -x; trap 'set -m; set +x;' RETURN; }
  { set +m; trap 'set -m' RETURN; }
  # ---
  local __bb_ore_channel_ref
  declare -n __bb_ore_channel_ref=$1  # ref (-n)
  local __bb_TMPFIFO=$__bb_ore_channel_ref
  shift 1 || return 1
  # ---
  [[ -p ${__bb_TMPFIFO} ]] || return 2
  # ---
  cat ${__bb_TMPFIFO} || return 3
  rm -f -- "${__bb_TMPFIFO}"
}


### ---------------------------------------------
###                Future
### ---------------------------------------------
###
### DEPENDENCIES: 
###   OneshotChannel_{make,send_args,receive}
### ---------------------------------------------

# ---
#  $ Future_make F 'sleep 10; echo AAA BBB CCC;' 
#  [2] 595356
#  $ R=$(Future_touch F)
#  $ echo $R
#  AAA BBB CCC
#  $ test -z $(Future_touch F) && echo "WARNING: the touched value is not stored as for lazy values"
#  WARNING: the touched value is not stored as for lazy values
# ---
function Future_make {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Future_make NAME COMMAND...";
  # ---
  [[ $# -ge 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  local __bb_fmk_channel_ref
  declare -n __bb_fmk_channel_ref=$1  # ref (-n)
  shift 1
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/future.XXXXXX
  local __bb_TMPFILE1=$(mktemp ${__bb_mktemp_TEMPLATE})
  local __bb_TMPFILE2=$(mktemp ${__bb_mktemp_TEMPLATE})
  # ---
  OneshotChannel_make __bb_fmk_channel_ref 2>/dev/null || return 2
  local __bb_CODE=0
  # ---
  # Disable the task control in order to eliminate 
  # noising messages about jobs termination on stderr:
  set +m; 
  # ---
  { eval "$@" 1>${__bb_TMPFILE1} 2>${__bb_TMPFILE2} || __bb_CODE=$?;
    OneshotChannel_send_args --sync __bb_fmk_channel_ref ${__bb_TMPFILE1} ${__bb_TMPFILE2} ${__bb_CODE};
  } 2>/dev/null &
  # ---
  return 0
}

# ---
# Note: a future must be touched once!
function Future_touch {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Future_touch NAME";
  # ---
  { set +m; trap 'set -m' RETURN; }
  # ---
  [[ $# -ge 1 ]] || return 1
  local __bb_fto_channel_ref
  declare -n __bb_fto_channel_ref=$1  # ref (-n)
  shift 1
  # ---
  OneshotChannel_receive __bb_fto_channel_ref | { 
    local __bb_TMPFILE1 __bb_TMPFILE2 __bb_CODE
    read __bb_TMPFILE1
    read __bb_TMPFILE2
    read __bb_CODE
    # ---
    cat ${__bb_TMPFILE1} 
    cat ${__bb_TMPFILE2} 1>&2
    # ---
    rm -f ${__bb_TMPFILE1} ${__bb_TMPFILE2}
    # ---
    exit ${__bb_CODE}
  }
}

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Future_help {
  { # less
  # ---
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh  
Future_*: helpers for asynchronous computations (futures)
---
* Future_make
Usage:
    Future_make NAME COMMAND...
Description:
    Starts COMMAND asynchronously and associates its result with the
    "future" named NAME. NAME must be the name of a variable that will
    hold the underlying one-shot channel created by OneshotChannel_make.
    The standard output and standard error of COMMAND, as well as its
    exit status, are captured and stored in temporary files until the
    future is touched.
    Returns 0 on successful creation of the future, non-zero on error.
Examples:
    # Basic future producing a value on stdout
    Future_make F 'sleep 2; echo "AAA BBB CCC";'
    # Do something else here while the command runs...

    # Later, touch the future to retrieve the result:
    R=$(Future_touch F)
    echo "$R"
    # AAA BBB CCC

    # The touched value is not stored, so touching twice yields nothing:
    test -z "$(Future_touch F 2>/dev/null)" && \
      echo "WARNING: the touched value is not stored as for lazy values"
    # WARNING: the touched value is not stored as for lazy values

    # Future whose command may fail:
    Future_make G 'sleep 1; echo "OK"; return 42;'
    if R=$(Future_touch G); then
      echo "Result: $R"
    else
      echo "Future failed with exit code $?" 1>&2
    fi
Notes:
    - Internally uses OneshotChannel_make and OneshotChannel_send_args
      to store two temp files (stdout, stderr) and the exit code.
    - The shell's job control is temporarily disabled (set +m) to avoid
      noisy messages about job termination on stderr.
---
* Future_touch
Usage:
    Future_touch NAME
Description:
    Waits for the completion of the future NAME (created by Future_make),
    then:
      - prints the captured stdout of the underlying command on stdout,
      - prints the captured stderr on stderr,
      - removes the temporary files,
      - exits with the same exit code as the underlying command.
    A future is meant to be touched exactly once: subsequent calls
    will not retrieve any value.
Examples:
    # Simple usage
    Future_make F 'sleep 1; echo "Hello";'
    R=$(Future_touch F) && echo "Got: $R"
    # Got: Hello

    # Touching again yields nothing:
    test -z "$(Future_touch F 2>/dev/null)" && \
      echo "Second touch returns empty result"

    # Propagation of errors:
    Future_make H 'echo "will fail"; return 7;'
    if R=$(Future_touch H); then
      echo "Unexpected success: $R"
    else
      echo "Underlying command failed with code $?" 1>&2
    fi
Notes:
    - Future_touch temporarily disables job control (set +m) while waiting,
      and restores it when done.
    - NAME is the name of the variable containing the underlying
      one-shot channel reference.
EOF
  } 2>&1 | less
} 


### ---------------------------------------------
###             Function_* 
### ---------------------------------------------

# ---
# Examples: 
#  ---
#  $ Function_def foobar 'test -f $1 && test -d $2'
#  $ trap 'unset foobar' RETURN;  # to do in a function, to be clean  
#  $ foobar aaa bbb && echo YES
#  $ foobar /etc/fstab /tmp && echo YES
#  YES
#  $ unset foobar
#  ---
#  $ Function_def foobar 'Float_sqrt'
#  $ trap 'unset foobar' RETURN;  # to do in a function, to be clean  
#  $ foobar 2
#  1.41421356237309504880
#  $ unset foobar
function Function_def {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Function_def NAME (FUNCNAME|BODY...)  (BODY is the function body using \$1, \$2, ...)";
  # ---
  local __bb_def_NAME=$1
  shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_BODY="$@"
  [[ $# -ge 1 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_DEF
  # ---
  if Regexp_is_ident "${__bb_BODY}" || Sys_is_command "${__bb_BODY}"; then
    # ---
    # Create an alias of the given identifier : 
    #   provided_f  ->  function g { provided_f "$@"; }
    # ---
    type "${__bb_BODY}" &>/dev/null || { type "${__bb_BODY}" 1>&2; return 3; }
    # ---
    printf -v __bb_DEF  "function ${__bb_def_NAME} {%b %b \"\$@\" %b};" '\n' "${__bb_BODY}" '\n'
    # ---
  elif Regexp_is_function_body "${__bb_BODY}"; then
    # ---
    # Compose the BODY in a function definition :
    #   provided_BODY  ->  function g { provided_BODY; }
    # ---
    printf -v __bb_DEF  "function ${__bb_def_NAME} {%b %b %b};" '\n' "${__bb_BODY}" '\n'
    # ---
  else
    echo "The user-defined body must contain at least one positional parameter (\$1, \$2, ...)" 1>&2;
    return 4;
  fi  
  # ---
  local __bb_CODE=0
  eval "${__bb_DEF}" || __bb_CODE=$?
  # ---
  return ${__bb_CODE}
}

# ---
# $ Function_fresh_name foo
# foo_5875
# ---
function Function_fresh_name { 
  # ---
  local __bb_USAGE="Usage: Function_fresh_name PREFIX";
  # ---
  local  __bb_PREFIX="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __Function_fresh_name_NAME=${__bb_PREFIX}_${RANDOM}
  while type -t "${__Function_fresh_name_NAME}" &>/dev/null; do
    __Function_fresh_name_NAME="${__bb_PREFIX}_${RANDOM}"
  done
  # ---
  printf '%s\n' "$__Function_fresh_name_NAME"
}

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Function_help {
  { # less
  # ---
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh
Function_*: helpers around Bash function definitions
---
* Function_def
  Usage:
      Function_def NAME (FUNCNAME|BODY...)
      (BODY is the function body using $1, $2, ...)
  Description:
      Defines a new Bash function NAME from:
        - either an existing function or external command FUNCNAME,
        - or an inline BODY (a shell snippet that uses positional
          parameters $1, $2, ...).
      Useful for temporary helper functions created on the fly.
      Two modes:
        1) If BODY is a valid identifier or an existing command:
            Function_def g some_fun
          defines:
            function g { some_fun "$@"; }
        2) If BODY looks like a function body (contains at least one
          positional parameter): it is wrapped as:
            function g { BODY; }

      Returns 0 on success, or a non-zero code on error:
        1: missing NAME or BODY
        2: empty BODY
        3: FUNCNAME does not resolve to a known function/command
        4: BODY does not contain any positional parameter
  Examples:
      # Wrapper around an existing command:
      Function_def is_file 'test -f "$1"'
      trap 'unset is_file' RETURN
      is_file /etc/passwd && echo "File exists"

      # Binary predicate on file and directory:
      Function_def foobar 'test -f $1 && test -d $2'
      trap 'unset foobar' RETURN
      foobar aaa bbb         && echo YES
      foobar /etc/fstab /tmp && echo YES
      # YES

      # Wrapper around another Bash function:
      Float_sqrt() { awk "BEGIN {print sqrt($1)}"; }
      Function_def mysqrt 'Float_sqrt'
      trap 'unset mysqrt' RETURN
      mysqrt 2
      # 1.41421356237309504880

      # Inline body example:
      Function_def say_hello 'echo "Hello $1"'
      say_hello World
      # Hello World
  Notes:
      - The automatically generated function is defined in the current
        shell environment (via eval).
      - For cleanliness, functions defined in a local scope should
        be unset with a trap:
            trap 'unset NAME' RETURN
---
* Function_clone
  Usage:
      Function_clone SRC DEST
      Function_clone -r|--replace-refs SRC DEST
  Description:
      Clones the definition of an existing Bash function SRC into a new
      function DEST.

      Without -r/--replace/--replace-refs:
        - The body of SRC is copied as-is.
        - Only the function declaration line is changed:
            SRC () { ... } -> DEST () { ... }
        - Internal references to SRC inside the body are left untouched.

      With -r/--replace-refs:
        - Internal references to SRC inside the body are also replaced
          by DEST (sed-based textual substitution).

      Returns:
        0: success
        1: missing arguments
        2: SRC is not a function
        3/4: error while retrieving or transforming SRC body
        5: error while evaluating the new definition
  Examples:
      # Simple clone (wrapper-style):
      my_fun() { echo "my_fun: $*"; }
      Function_clone my_fun my_fun_copy
      my_fun_copy a b
      # my_fun: a b

      # Clone with replacement of internal references:
      hello() { echo "hello from hello"; }
      Function_clone --replace-refs hello hi
      hi
      # hello from hi   (if hello was referenced in the body)

  Notes:
      - Any existing alias with name DEST is automatically removed before
        evaluating the new function definition.
      - SRC must already be a defined function (checked via declare -F).
---
* Function_fresh_name
  Usage:
      Function_fresh_name PREFIX
  Description:
      Generates a fresh function name starting with the given PREFIX,
      by appending a random suffix and checking that no function with
      that name already exists.
      The resulting name is printed on stdout, one per line.
      Useful for temporary helper functions created on the fly.
  Examples:
      # Generate a fresh name:
      FNAME=$(Function_fresh_name foo)
      echo "$FNAME"
      # foo_5875  (for example)

      # Define a temporary function with a fresh name:
      FNAME=$(Function_fresh_name tmpfunc)
      Function_def "$FNAME" 'echo "temp: $1"'
      trap "unset $FNAME" RETURN
      "$FNAME" 42
      # temp: 42
  Notes:
      - PREFIX must be a valid identifier (checked by Regexp_is_ident).
      - The function loops until it finds a name not reported by
        "type -t", so collisions are avoided even if RANDOM repeats.
EOF
  } 2>&1 | less
}

### ---------------------------------------------
###                   Array  
### ---------------------------------------------

# ---
# Examples:
#  $ Array_make xs "$@"
#  $ Array_make xs 10 20 30 40
#  $ Array_length xs
#  4
#  $ Array_print xs
#  10 20 30 40
#  $ Array_push xs 50 60
#  $ Array_print xs
#  10 20 30 40 50 60
# ---
# TEST IMPORTANT: Respect des variables locales :
#  $ function f { local -a xs; local -a ys; Array_make xs "$@"; Array_copy xs ys; declare -p xs ys; Array_print ys; }
#  $ unset xs ys  &&  Array.make xs 100 200 300  &&  f aaa bbb  &&  declare -p xs ys
#  declare -a xs=([0]="aaa" [1]="bbb")
#  declare -a ys=([0]="aaa" [1]="bbb")
#  aaa
#  bbb
#  declare -a xs=([0]="100" [1]="200" [2]="300")
#  bash: declare: ys : non trouvé
#  ---
function Array_make {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_make [-a|--append] NAME [VALUE]...";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_PLUS
  if [[ $1 = "-a" || $1 = "--append" || $1 = "--push" || $1 = "--update" ]]; then __bb_PLUS="+"; shift 1; fi
  # ---
  local __bb_amk_NAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  Declare_is_undefined "${__bb_amk_NAME}" || Declare_is_array -u "${__bb_USAGE}" -v "${__bb_amk_NAME}" || return 2;
  # ---
  local -n __Array_make_ref=${__bb_amk_NAME}
  if [[ -z ${__bb_PLUS} ]]; then
    __Array_make_ref=("$@")  || { echo "${__bb_USAGE}" 1>&2; return 3; }
  else
    __Array_make_ref+=("$@") || { echo "${__bb_USAGE}" 1>&2; return 4; }
  fi
  # ---
  return 0
}

# ---
# Alias for 'Array_make --append':
function Array_push {
  local __bb_USAGE="Usage: Array_push NAME [VALUE]...";
  # ---
  Array_make -u "${__bb_USAGE}" -a "$@"
}

# ---
# Example:
#  $ Array_init xs 8 'echo $1' && declare -p xs
#  declare -a xs=([0]="0" [1]="1" [2]="2" [3]="3" [4]="4" [5]="5" [6]="6" [7]="7")
#  ---
#  Array_init xs 8 'echo "" # ignore index $1'  && declare -p xs
#  declare -a xs=([0]="" [1]="" [2]="" [3]="" [4]="" [5]="" [6]="" [7]="")
# ---
function Array_init {
  local __bb_USAGE="Usage: Array_init NAME LENGTH (FUNCNAME|BODY...)  # BODY is the body function using index \$1 and value \$2";
  # ---
  local __bb_ain_NAME="$1" && Array_make -u "${__bb_USAGE}" "$1" && shift 1 || return 1; 
  local   __bb_LENGTH="$1" && Regexp_is_natural             "$1" && shift 1 || return 2; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_init_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Array_mapi.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  # ---
  local __bb_len=${__bb_LENGTH}
  local __bb_i __bb_ref __bb_X __bb_Y
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do 
    String_capture -t ${__bb_TMPFILE} __bb_Y ${__bb_FNAME} "${__bb_i}" || __bb_CODE=$((__bb_CODE+1));
    Array_set_unchecked ${__bb_ain_NAME} "${__bb_i}" "${__bb_Y}"
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  return ${__bb_CODE}
}

# ---
# Examples:
# ---
#  $ Array_create xs 8  && declare -p xs
#  declare -a xs=([0]="" [1]="" [2]="" [3]="" [4]="" [5]="" [6]="" [7]="")
#  ---
#  $ Array_create xs 8 0  && declare -p xs
#  declare -a xs=([0]="0" [1]="0" [2]="0" [3]="0" [4]="0" [5]="0" [6]="0" [7]="0")
#  ---
#  $ Array_create xs 8 '/tmp'  && declare -p xs
#  declare -a xs=([0]="/tmp" [1]="/tmp" [2]="/tmp" [3]="/tmp" [4]="/tmp" [5]="/tmp" [6]="/tmp" [7]="/tmp")
# ---
function Array_create {
  local __bb_USAGE="Usage: Array_create NAME LENGTH [VALUE]";
  # ---
  local __bb_acr_NAME="$1" && Array_make -u "${__bb_USAGE}" "$1" && shift 1 || return 1; 
  local   __bb_LENGTH="$1" && Regexp_is_natural             "$1" && shift 1 || return 2; 
  local    __bb_VALUE="$1"; 
  [[ $# -le 1 ]] || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local __bb_CMD=true  # true echoes nothing on stdout
  if [[ -n "${__bb_VALUE}" ]]; then
    __bb_CMD=$(printf 'echo "%b" # ignore index $1' "${__bb_VALUE}")
  fi
  # ---
  Array_init ${__bb_acr_NAME} ${__bb_LENGTH} "${__bb_CMD}"
}

# ---
# Example:
#   $ Array_import xs /etc/fstab
#   $ Array_print xs > /tmp/fstab
#   $ diff /etc/fstab /tmp/fstab && echo YES
#   YES
# ---
function Array_import {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_import NAME [FILE]...";
  # ---
  local __bb_aim_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  Array_make -u "${__bb_USAGE}" ${__bb_aim_NAME} || return 2
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Array_import.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 3
  # ---
  cat "$@" > ${__bb_TMPFILE}
  # ---
  local __bb_LINE __bb_i=0
  while IFS= read -r __bb_LINE || [[ -n ${__bb_LINE} ]]; do 
    Array_set_unchecked ${__bb_aim_NAME} "${__bb_i}" "${__bb_LINE}"
    let __bb_i=__bb_i+1
  done < ${__bb_TMPFILE}
  # ---
  rm -f ${__bb_TMPFILE}
  return 0
  # ---
}

# ---
# Example:
#  $ Array_capture xs echo -e "hello\nworld"
#  $ declare -p xs
#  declare -a xs=([0]="hello" [1]="world")
#  ---
#  Array_capture xs awk '$2 ~ /tcp/ {split($2, w, "/"); print $1, w[1];}' /etc/services
#  $ Array.length xs
#  218
#  $ Array.get xs 16
#  domain 53
# ---
function Array_capture {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_capture [-t|--tmpfile TMPFILE] NAME COMMAND..";
  # ---
  local __bb_TMPFILE __bb_TMPFILE_PROVIDED
  if [[ $1 = "-t" || $1 = "--tmpfile" ]]; then
    __bb_TMPFILE="$2";
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 5; }
    __bb_TMPFILE_PROVIDED=y
  fi
  # ---
  local __bb_acp_NAME=$1 && shift 1              || { echo "${__bb_USAGE}" 1>&2; return 1; }
  [[ $# -gt 0 ]]                                 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  Array_make -u "${__bb_USAGE}" ${__bb_acp_NAME} || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  if [[ -z "${__bb_TMPFILE}" ]]; then
    local __bb_mktemp_TEMPLATE=/tmp/Arra_capture.XXXXXX
    __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  fi
  # ---
  local __bb_CODE=0
  # ---
  local __bb_CMD="$1"; shift 1
  "${__bb_CMD}" "$@" 1>"${__bb_TMPFILE}" || __bb_CODE=$?
  # ---
  local __bb_LINE __bb_i=0
  while IFS= read -r __bb_LINE || [[ -n ${__bb_LINE} ]]; do 
    Array_set_unchecked ${__bb_acp_NAME} "${__bb_i}" "${__bb_LINE}"
    let __bb_i=__bb_i+1
  done < ${__bb_TMPFILE}
  # ---
  [[ ${__bb_TMPFILE_PROVIDED} = y ]] || rm -f "${__bb_TMPFILE}"
  # ---
  return ${__bb_CODE}
}

# ---
# Poor-man scanf in Bash.
# ---
# Examples:
#  ---
#  $ Array_scanf xs "room-unif-an25-2049" "room-(.*)-an25-(.*)" &&  declare -p xs
#  declare -a xs=([0]="unif" [1]="2049")
#  ---
#  $ Array_scanf: WARNING: REGEXP has no capturing groups; 'xs' will be an empty array.
#  declare -a xs=()
#  ---
#  $ Array_scanf --quiet xs "room-unif-an25-2049" "room-.*-an25-.*" &&  declare -p xs
#  declare -a xs=()
# ---
function Array_scanf {
  # ---
  local __bb_USAGE="Usage: Array_scanf [-q|--quiet] NAME STRING REGEXP";
  # ---
  local __bb_QUIET
  if [[ $1 = "-q" || $1 = "--quiet" ]]; then __bb_QUIET="y"; shift 1; fi
  # ---
  [[ $# -eq 3 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  local __bb_asc_NAME="$1"
  local   __bb_STRING="$2"
  local   __bb_REGEXP="$3"
  # ---
  Array_make -u "${__bb_USAGE}" ${__bb_asc_NAME} || return 3
  # ---
  [[ ${__bb_STRING} =~ ${__bb_REGEXP} ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_GROUPS_NB=$((${#BASH_REMATCH[@]} - 1))
  if [[ ${__bb_GROUPS_NB} -eq 0 ]]; then 
    [[ -n ${__bb_QUIET} ]] || echo "Array_scanf: WARNING: REGEXP has no capturing groups; '${__bb_asc_NAME}' will be an empty array." 1>&2;
    return 0;
  fi
  # ---
  local __bb_group=1 __bb_i
  for ((__bb_i=0; __bb_i<__bb_GROUPS_NB; __bb_i++)); do
    Array_set_unchecked ${__bb_asc_NAME} ${__bb_i} "${BASH_REMATCH[__bb_group++]}";
  done
  # ---
  return 0
}

# ---
function Array_print {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_print [-s|--sep|--separator SEP] NAME";
  # ---
  local __bb_SEP="\n"
  if [[ $1 = "-s" || $1 = "--sep" || $1 = "--separator" ]]; then 
    __bb_SEP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  fi
  # ---
  local __bb_apr_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  eval "local __bb_LENGTH=\${#${__bb_apr_NAME}[@]}"
  local __bb_LAST_INDEX=$((__bb_LENGTH-1))
  local __bb_NL='\n'
  local __bb_CMD='if (($1<${__bb_LAST_INDEX})); then printf "%b%b" "$2" "${__bb_SEP}"; else printf "%b%b" "$2" "${__bb_NL}"; fi'
  Array_iteri ${__bb_apr_NAME} "${__bb_CMD}"
}

# ---
function Array_has_index {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_has_index [-c|--check-is-array] [-v|--verbose] NAME INDEX";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_CHECK_IS_ARRAY
  if [[ $1 = "-c" || $1 = "--check-is-array" ]]; then __bb_CHECK_IS_ARRAY="y"; shift 1; fi
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_ahi_NAME="$1" && { [[ -z ${__bb_CHECK_IS_ARRAY} ]] || Declare_is_array -u "${__bb_USAGE}" -v "$1"; } && shift 1 || return 2
  local -i __bb_INDEX="$1" && Regexp_is_index "$1" && shift 1 || { 
    [[ -n ${__bb_VERBOSE} ]] && echo "Invalid index '$1'" 1>&2 && echo "${__bb_USAGE}" 1>&2; 
    return 3; 
    }
  # ---
  eval "local __bb_LENGTH=\${#${__bb_ahi_NAME}[@]}"
  # ---
  local __bb_CODE=0
  ((__bb_INDEX>=0 && __bb_INDEX<__bb_LENGTH)) || { 
    __bb_CODE=1
    [[ -n ${__bb_VERBOSE} ]] && echo "Error: index '${__bb_INDEX}' out of bounds 0..$((__bb_LENGTH-1))" 1>&2 && echo "${__bb_USAGE}" 1>&2; 
    }
  # ---
  return ${__bb_CODE}
}

# ---
function Array_set {
  local __bb_USAGE="Usage: Array_set [-s|--strict] NAME INDEX VALUE";
  # ---
  local __bb_STRICT
  if [[ $1 = "-s" || $1 = "--strict" ]]; then __bb_STRICT="y"; shift 1; fi
  # ---
  local __bb_ase_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  if [[ ${__bb_STRICT} = y ]]; then
    local -i __bb_INDEX="$1" && Array_has_index -u "${__bb_USAGE}" -v "${__bb_ase_NAME}" "$1" && shift 1 || return 2;
  else
    local -i __bb_INDEX="$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
  fi
  # ---
  local __bb_val="$1"  && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 4; }
  [[ $# = 0 ]]               || { echo "${__bb_USAGE}" 1>&2; return 5; } 
  # ---
  # Construction de la référence, puis affectation par eval :
  local __bb_ref="${__bb_ase_NAME}[${__bb_INDEX}]"
  eval "${__bb_ref}=\${__bb_val}"
}

# ---
function Array_set_unchecked {
  # local USAGE="Usage: Array_set_unchecked NAME INDEX VALUE";
  # ---
  [[ $# = 3 ]] || return 1; # ok, not completely unchecked...
  # ---
  local __bb_ref="${1}[${2}]"
  eval "${__bb_ref}=\${3}"
}

# ---
# This is implicitely a "strict" version (because of Array_has_index):
function Array_get {
  local __bb_USAGE="Usage: Array_get NAME INDEX";
  # ---
  local __bb_age_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v                    "$1" && shift 1 || return 1; 
  local -i __bb_INDEX="$1" && Array_has_index  -u "${__bb_USAGE}" -v "${__bb_age_NAME}" "$1" && shift 1 || return 2;
  # ---
  local __bb_ref="${__bb_age_NAME}[${__bb_INDEX}]"
  # ---
  echo ${!__bb_ref}
}

# ---
function Array_get_assign {
  local __bb_USAGE="Usage: Array_get_assign NAME INDEX VARNAME";
  # ---
  local __bb_aga_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v                    "$1" && shift 1 || return 1; 
  local -i __bb_INDEX="$1" && Array_has_index  -u "${__bb_USAGE}" -v "${__bb_aga_NAME}" "$1" && shift 1 || return 2;
  local  __bb_aga_VARNAME="$1"                                                                   && shift 1 || return 3;

  # ---
  local __bb_ref="${__bb_aga_NAME}[${__bb_INDEX}]"
  # ---
  local -n __bb_aga_VARNAME_ref="${__bb_aga_VARNAME}"
  __bb_aga_VARNAME_ref="${!__bb_ref}"
}

# ---
# Note: identique à Map_get_assign_unchecked.
function Array_get_assign_unchecked {
  # local USAGE="Usage: Array_get_assign_unchecked NAME INDEX VARNAME";
  # ---
  [[ $# = 3 ]] || return 1; # ok, not completely unchecked...
  # ---
  # Name reference to the array:
  local -n __bb_agu_NAME_ref="$1"
  # ---
  # Test existence of the index :
  if [[ -v __bb_agu_NAME_ref["$2"] ]]; then
    local -n __bb_agu_VARNAME_ref="$3"
    __bb_agu_VARNAME_ref="${__bb_agu_NAME_ref[$2]}"
    return 0
  else
    return 1
  fi
}

# ---
function Array_length {
  # { set -x; trap 'set +x' RETURN; }
  local __bb_USAGE="Usage: Array_length NAME";
  # ---
  local __bb_ale_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  local -n __Array_length_ref="${__bb_ale_NAME}"
  echo "${#__Array_length_ref[@]}"
}

# ---
# Example:
#   $ Array_set xs 2 /tmp
#   $ Array_find xs 'test -f $1'
#   $ Array_find xs 'test -d $1'
#   /tmp
#   $ Array_find xs 'test -d $1'
#   /tmp
#   $ function f { test -d $1; }
#   $ Array_find xs f
#   /tmp
# ---
function Array_find {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_find NAME (FUNCNAME|BODY...)  # BODY is the body predicate using value \$1";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_QUIET
  if [[ $1 = "-q" || $1 = "--quiet" ]]; then __bb_QUIET="y"; shift 1; fi
  # ---
  local __bb_afi_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_find_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  eval "local __bb_len=\${#${__bb_afi_NAME}[@]}"
  local __bb_i __bb_ref __bb_X
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_afi_NAME}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    if ${__bb_FNAME} "${__bb_X}"; then
      [[ -n ${__bb_QUIET} ]] || echo "${__bb_X}";
      return 0;
    fi
  done
  # ---
  return 1
}

# ---
# Usages: 
#  local len;  Array_length2 --caller "Array_map2" -v len  ARRAY1 ARRAY2 || return 22
#  local len=$(Array_length2 --caller "Array_map2" ARRAY1 ARRAY2) || return 22
function Array_length2 {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_length2 [-a|--allow-shorter-first] NAME1 NAME2";
  # ---
  local __bb_ALLOW_SHORTER_FIRST
  if [[ $1 = "-a" || $1 = "--allow-shorter-first" ]]; then __bb_ALLOW_SHORTER_FIRST="-a"; shift 1; fi
  # ---
  local __bb_CALLER="Invalid arguments"
  if [[ $1 = "-c" || $1 = "--caller" ]]; then
    __bb_CALLER="$2";
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 6; }
  fi
  # ---
  local __bb_alt_VARNAME
  if [[ $1 = "-v" || $1 = "--assign" ]]; then
    __bb_alt_VARNAME="$2" && shift 2 || { echo "${__bb_USAGE}" 1>&2; return 7; }
  fi
  # ---
  local __bb_alt_NAME1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 3;
  local __bb_alt_NAME2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 4;
  # ---
  eval "local __bb_len1=\${#${__bb_alt_NAME1}[@]}"
  eval "local __bb_len2=\${#${__bb_alt_NAME2}[@]}"
  if [[ ${__bb_len1} = ${__bb_len2} ]] || [[ -n ${__bb_ALLOW_SHORTER_FIRST} && ${__bb_len1} -le ${__bb_len2} ]] ; then
    if [[ -z ${__bb_alt_VARNAME} ]]; then echo "${__bb_len1}"; else eval ${__bb_alt_VARNAME}="${__bb_len1}"; fi
    return 0;
  fi
  # else fail:  
  if [[ -z ${__bb_ALLOW_SHORTER_FIRST} ]]; then
    echo "${__bb_CALLER}: arrays '${__bb_alt_NAME1}' and '${__bb_alt_NAME2}' do not have the same length (${__bb_len1} vs ${__bb_len2})" 1>&2; 
    return 1
  else
    echo "${__bb_CALLER}: array '${__bb_alt_NAME1}' is not shorter than '${__bb_alt_NAME2}' (${__bb_len1} vs ${__bb_len2})" 1>&2; 
    return 2
  fi  
}

# ---
# Examples:
#   $ declare -a xs=([0]="2" [1]="400" [2]="/tmp" [3]="8" [4]="999")
#   $ Array_find2 xs xs 'test -d $1 && test -f $2'
#   $ Array_find2 xs xs 'test -d $1 && test -d $2'
#   /tmp
#   /tmp
#   $ RESULTS=$(Array_find2 xs xs 'test -d $1 && test -d $2')    # RESULTS="/tmp /tmp"
# ---
function Array_find2 {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_find2 [-a|--allow-shorter-first] [-s|--sep SEP] [-q|--quiet] NAME1 NAME2 (FUNCNAME|BODY...)  # BODY is the body predicate using values \$1 and \$2";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_ALLOW_SHORTER_FIRST
  if [[ $1 = "-a" || $1 = "--allow-shorter-first" ]]; then __bb_ALLOW_SHORTER_FIRST="-a"; shift 1; fi
  # ---
  local __bb_SEP=" "
  if [[ $1 = "-s" || $1 = "--sep" || $1 = "--separator" ]]; then 
    __bb_SEP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  fi
  # ---
  local __bb_QUIET
  if [[ $1 = "-q" || $1 = "--quiet" ]]; then __bb_QUIET="y"; shift 1; fi
  # ---  
  local __bb_ORIG1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_ORIG2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_find2_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_len;  
  Array_length2 ${__bb_ALLOW_SHORTER_FIRST} --caller "Array_find2" -v __bb_len "${__bb_ORIG1}" "${__bb_ORIG2}" || { echo "${__bb_USAGE}" 1>&2; return 4; }
  # ---
  local __bb_i __bb_X1 __bb_X2 __bb_ref1 __bb_ref2
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref1="${__bb_ORIG1}[${__bb_i}]"
    __bb_ref2="${__bb_ORIG2}[${__bb_i}]"
    __bb_X1=${!__bb_ref1}
    __bb_X2=${!__bb_ref2}
    if ${__bb_FNAME} "${__bb_X1}" "${__bb_X2}"; then
      [[ -n ${__bb_QUIET} ]] || printf "%b%s%b\n" "${__bb_X1}" "${__bb_SEP}" "${__bb_X2}";
      return 0;
    fi
  done
  # ---
  return 1
}

# ---
# Just an alias for 'Array_find --quiet'.
# ---
function Array_exists {
  local __bb_USAGE="Usage: Array_exists NAME (FUNCNAME|BODY...)  # BODY is the body predicate using value \$1";
  # ---  
  Array_find -u "${__bb_USAGE}" --quiet "$@"
}

# ---
# Just an alias for 'Array_find2 --quiet'.
# ---
function Array_exists2 {
  local __bb_USAGE="Usage: Array_exists2 NAME1 NAME2 (FUNCNAME|BODY...)  # BODY is the body predicate using values \$1 and \$2";
  # ---  
  Array_find2 -u "${__bb_USAGE}" --quiet "$@"
}

#  ---
#  $ declare -a xs1=([0]="10" [1]="20" [2]="30" [3]="40")
#  $ declare -a xs2=([0]="10" [1]="20" [2]="30" [3]="40")
#  $ Array_equal xs1 xs2 && echo YES    # YES
#  $ Array_set xs1 0 1000
#  $ Array_equal xs1 xs2 || echo NO     # NO
# ---
function Array_equal {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_equal NAME1 NAME2";
  # ---
  local __bb_aeq_NAME1=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  local __bb_aeq_NAME2=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  Array_for_all2 -u "${__bb_USAGE}" ${__bb_aeq_NAME1} ${__bb_aeq_NAME2} '[[ "$1" = "$2" ]]'
}

# ---
function Array_for_all {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_for_all NAME (FUNCNAME|BODY...)  # BODY is the body predicate using value \$1";
  # ---  
  local __bb_afa_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_for_all_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 4; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  eval "local __bb_len=\${#${__bb_afa_NAME}[@]}"
  local __bb_i __bb_ref __bb_X
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_afa_NAME}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    if ${__bb_FNAME} "${__bb_X}"; then
      continue;
    else  
      return 1;
    fi
  done
  # ---
  return 0
}

# ---
function Array_for_all2 {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_for_all2 [-a|--allow-shorter-first] NAME1 NAME2 (FUNCNAME|BODY...)  # BODY is the body predicate using values \$1 and \$2";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_ALLOW_SHORTER_FIRST
  if [[ $1 = "-a" || $1 = "--allow-shorter-first" ]]; then __bb_ALLOW_SHORTER_FIRST="-a"; shift 1; fi
  # ---
  local __bb_ORIG1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_ORIG2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_for_all2_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 6; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_len;  
  Array_length2 ${__bb_ALLOW_SHORTER_FIRST} --caller "Array_for_all2" -v __bb_len "${__bb_ORIG1}" "${__bb_ORIG2}" || { echo "${__bb_USAGE}" 1>&2; return 7; }
  # ---
  local __bb_i __bb_X1 __bb_X2 __bb_ref1 __bb_ref2
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref1="${__bb_ORIG1}[${__bb_i}]"
    __bb_ref2="${__bb_ORIG2}[${__bb_i}]"
    __bb_X1=${!__bb_ref1}
    __bb_X2=${!__bb_ref2}
    if ${__bb_FNAME} "${__bb_X1}" "${__bb_X2}"; then
      continue;
    else  
      return 1;
    fi
  done
  # ---
  return 0
}

# ---
# Example:
#  $ declare -p xs
#  declare -a xs=([0]="2" [1]="4" [2]="6" [3]="8")
#  $ Array_filter xs ys '(($2>5))'
#  $ Array_print ys    # 6 8
# ---
function Array_filter {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_filter ORIG DEST (FUNCNAME|BODY...)  # BODY is the body predicate using index \$1 and value \$2";
  # ---  
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 1; 
  local __bb_DEST="$1" && Array_make "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_filter_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # --- 
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_ref __bb_X
  local __bb_j=0
  # ---
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_ORIG}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    # ---
    if ${__bb_FNAME} "${__bb_i}" "${__bb_X}"; then
      Array_set_unchecked ${__bb_DEST} "${__bb_j}" "${__bb_X}";
      let __bb_j=__bb_j+1
    fi
    # ---
  done
  # ---
  return 0;
}

# ---
function Array_member {
  local __bb_USAGE="Usage: Array_member NAME VALUE";
  # ---  
  [[ $# = 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---  
  Array_find --quiet "$1" "[[ \$1 = \"$2\" ]]"
}
alias Array_mem=Array_member

# ---
# Returns the number of errors (may be 0).
function Array_iter {
  local __bb_USAGE="Usage: Array_iter NAME (FUNCNAME|BODY...)  # BODY is the body function using value \$1";
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_iter_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_ref __bb_X
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_ORIG}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    ${__bb_FNAME} "${__bb_X}" || __bb_CODE=$((__bb_CODE+1));
  done
  # ---
  return ${__bb_CODE}
}

# ---
# Same job of 'Array_iter' but in parallel (with futures)
# Returns the number of errors (may be 0).
# Examples:
#   $ Array_make xs 2 4 6
#   ---
#   # Sequential call (Array_iter):
#   ---
#   $ time Array_iter xs 'sleep 4; echo "hello $1:$1";' 2>/dev/null
#   hello 2:2
#   hello 4:4
#   hello 6:6
#   
#   real    0m12,023s   # <= 12 seconds (of course: 3 * sleep 4)
#   user    0m0,004s
#   sys     0m0,020s
#   ---
#   # Parallel call (Array_iter_parallel):
#   ---
#   $ time Array_iter_parallel xs 'sleep 4; echo "hello $1:$1";' 2>/dev/null
#   hello 2:2
#   hello 4:4
#   hello 6:6
#   real    0m4,092s    # <= 4 seconds !!!
#   user    0m0,023s
#   sys     0m0,115s
#   ---
#   $ Array_iter_parallel xs 'sleep 3; echo "hello $1:$1"; return 64;'
#   # same output but with $? = 3 (because all 3 commands were exited with the error code 64)
#   ---
#   $ Array_import xs <(find /etc/apache2/ -type d) 
#   $ Array_length xs # 7
#   $ Array_iter_parallel xs 'find $1 -maxdepth 1 -type f -name "*ssl*conf*"'
#   /etc/apache2/sites-available/default-ssl.conf
#   /etc/apache2/mods-available/ssl.conf
# ---
function Array_iter_parallel {
  # { set -x; trap 'set +x' RETURN; }
  local __bb_USAGE="Usage: Array_iter_parallel NAME (FUNCNAME|BODY...)  # BODY is the body function using value \$1";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_OPTION_i
  if [[ $1 = "-i" || $1 = "--index" || $1 = "--call-with-index" ]]; then __bb_OPTION_i="y"; shift 1; fi
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_iter_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i
  # --- 
  # First loop: create all needed local names (one per future):
  # --- 
  local -a __bb_LOCAL_NAMES
  local __bb_TMPNAME
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    # --- Examples:
    # local __Array_iter_parallel_28570
    # TMPNAME=__Array_iter_parallel_28570
    eval $(Declare_fresh_name __bb_TMPNAME __Array_iter_parallel)
    # ---
    Array_set_unchecked __bb_LOCAL_NAMES "${__bb_i}" "${__bb_TMPNAME}"
  done
  ### declare -p LOCAL_NAMES
  ### Array_iter LOCAL_NAMES 'declare -p "$1"'
  # ---
  local __bb_ref __bb_X __bb_localName_ref
  # ---
  # Main loop 1 (make all futures):
  # ---
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_ORIG}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    __bb_localName_ref="${__bb_LOCAL_NAMES}[${__bb_i}]"
    ### set -x;
    if [[ -z ${__bb_OPTION_i} ]]; then
      Future_make "${__bb_localName_ref}" ${__bb_FNAME} "${__bb_X}"
    else
      Future_make "${__bb_localName_ref}" ${__bb_FNAME} "${__bb_i}" "${__bb_X}"
    fi  
    ### set +x;
  done
  # ---
  # Main loop 2 (touch all futures):
  # ---
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_localName_ref="${__bb_LOCAL_NAMES}[${__bb_i}]"
    __bb_X=${!__bb_localName_ref}
    ### set -x;
    Future_touch "${__bb_localName_ref}" || __bb_CODE=$((__bb_CODE+1));
    ### set +x;
  done
  # ---
  return ${__bb_CODE}
}

# ---
# Alias for 'Array_iter_parallel --call_with_index':
# ---
# Example:
#  $ Array_iteri_parallel xs 'sleep 3; echo "hello $1:$2"; return 64;'
#  hello 0:2
#  hello 1:4
#  hello 2:6
#  # with $? = 3
# ---
function Array_iteri_parallel {
  local __bb_USAGE="Usage: Array_iteri_parallel NAME (FUNCNAME|BODY...)  # BODY is the body function using index \$1 and value \$2";
  # ---
  Array_iter_parallel -u "${__bb_USAGE}" -i "$@"
}

# ---
# Returns the number of errors (may be 0).
# ---
# Example:
#  $ declare -a xs=([0]="2" [1]="4" [2]="6")
#  $ Array_map xs ys 'echo /tmp/tmpfile-$1'
#  /tmp/tmpfile-2
#  /tmp/tmpfile-4
#  /tmp/tmpfile-6
# ---
function Array_map {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_map ORIG DEST (FUNCNAME|BODY...)  # BODY is the body function using value \$1";
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Array_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_map_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Array_map.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_ref __bb_X __bb_Y
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_ORIG}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    String_capture -t ${__bb_TMPFILE} __bb_Y ${__bb_FNAME} "${__bb_X}" || __bb_CODE=$((__bb_CODE+1));
    Array_set_unchecked ${__bb_DEST} "${__bb_i}" "${__bb_Y}"
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  return ${__bb_CODE}
}

# ---
# Example:
#  $ Array_make xs a b c
#  $ time Array_map_parallel xs ys 'sleep 3; echo "/home/$1"'
#  real    0m3,094s
#  user    0m0,033s
#  sys     0m0,110s
#  $ Array_print ys
#  /home/a
#  /home/b
#  /home/c
# ---
function Array_map_parallel {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_map_parallel ORIG DEST (FUNCNAME|BODY...)  # BODY is the body function using value \$1";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_OPTION_i
  if [[ $1 = "-i" || $1 = "--index" || $1 = "--call-with-index" ]]; then __bb_OPTION_i="y"; shift 1; fi
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Array_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_map_parallel_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Array_map_parallel.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i
  # --- 
  # First loop: create all needed local names (one per future):
  # --- 
  local -a __bb_LOCAL_NAMES
  local __bb_TMPNAME
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    # --- Examples:
    # local __Array_iter_parallel_28570
    # TMPNAME=__Array_iter_parallel_28570
    eval $(Declare_fresh_name __bb_TMPNAME __Array_iter_parallel)
    # ---
    Array_set_unchecked __bb_LOCAL_NAMES "${__bb_i}" "${__bb_TMPNAME}"
  done
  ### declare -p LOCAL_NAMES
  ### Array_iter LOCAL_NAMES 'declare -p "$1"'
  # ---
  local __bb_ref __bb_X __bb_localName_ref
  # ---
  # Main loop 1 (make all futures):
  # ---
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_ORIG}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    __bb_localName_ref="${__bb_LOCAL_NAMES}[${__bb_i}]"
    ### set -x;
    if [[ -z ${__bb_OPTION_i} ]]; then
      Future_make "${__bb_localName_ref}" ${__bb_FNAME} "${__bb_X}"
    else
      Future_make "${__bb_localName_ref}" ${__bb_FNAME} "${__bb_i}" "${__bb_X}"
    fi  
    ### set +x;
  done
  # ---
  # Main loop 2 (touch all futures):
  # ---
  local __bb_Y __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_localName_ref="${__bb_LOCAL_NAMES}[${__bb_i}]"
    __bb_X=${!__bb_localName_ref}
    ### set -x;
    String_capture -t ${__bb_TMPFILE} __bb_Y Future_touch "${__bb_localName_ref}" || __bb_CODE=$((__bb_CODE+1));
    ### set +x;
    Array_set_unchecked ${__bb_DEST} "${__bb_i}" "${__bb_Y}"
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  return ${__bb_CODE}
}

# ---
# Alias for 'Array_map_parallel --call_with_index':
# ---
# Example:
#  $ Array_make xs a b c
#  $ Array_mapi_parallel xs ys 'sleep 3; echo "hello $1:$2"; return 64;'  # returns 3
#  $ Array_print ys
#  hello 0:a
#  hello 1:b
#  hello 2:c
# ---
function Array_mapi_parallel {
  local __bb_USAGE="Usage: Array_mapi_parallel ORIG DEST (FUNCNAME|BODY...)  # BODY is the body function using index \$1 and value \$2";
  # ---
  Array_map_parallel -u "${__bb_USAGE}" -i "$@"
}

# ---
# Returns the number of errors (may be 0).
# ---
# Example:
#  Array_map2 xs ys zs 'echo /tmp/tmpfile-$1-$2'
# ---
function Array_map2 {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_map2 [-a|--allow-shorter-first] ORIG1 ORIG2 DEST (FUNCNAME|BODY...)  # BODY is the body function using values \$1 and \$2";
  # ---
  local __bb_ALLOW_SHORTER_FIRST
  if [[ $1 = "-a" || $1 = "--allow-shorter-first" ]]; then __bb_ALLOW_SHORTER_FIRST="-a"; shift 1; fi
  # ---
  local __bb_ORIG1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 1; 
  local __bb_ORIG2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 2; 
  # ---
  local __bb_len
  Array_length2 ${__bb_ALLOW_SHORTER_FIRST} --caller "Array_map2" -v __bb_len "${__bb_ORIG1}" "${__bb_ORIG2}" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local __bb_DEST="$1" && Array_make -u "${__bb_USAGE}" "$1" && shift 1 || return 4;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_map2_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 5; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Array_map2.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 6
  # ---
  local __bb_i __bb_X1 __bb_X2 __bb_Y __bb_ref1 __bb_ref2
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref1="${__bb_ORIG1}[${__bb_i}]"
    __bb_ref2="${__bb_ORIG2}[${__bb_i}]"
    __bb_X1=${!__bb_ref1}
    __bb_X2=${!__bb_ref2}
    String_capture -t ${__bb_TMPFILE} __bb_Y ${__bb_FNAME} "${__bb_X1}" "${__bb_X2}" || __bb_CODE=$((__bb_CODE+1));
    Array_set_unchecked ${__bb_DEST} "${__bb_i}" "${__bb_Y}"
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  return ${__bb_CODE}
}

# ---
# Returns the number of errors (may be 0).
# ---
# Example:
#  Array_mapi xs ys 'echo /tmp/tmpfile-$1-$2'
# ---
function Array_mapi {
  local __bb_USAGE="Usage: Array_mapi ORIG DEST (FUNCNAME|BODY...)  # BODY is the body function using index \$1 and value \$2";
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Array_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_mapi_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Array_mapi.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_ref __bb_X __bb_Y
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do 
    __bb_ref="${__bb_ORIG}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    String_capture -t ${__bb_TMPFILE} __bb_Y ${__bb_FNAME} "${__bb_i}" "${__bb_X}" || __bb_CODE=$((__bb_CODE+1));
    Array_set_unchecked ${__bb_DEST} "${__bb_i}" "${__bb_Y}"
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  return ${__bb_CODE}
}

# ---
# Returns the number of errors (may be 0).
# ---
# Example:
#  $ Array_mapi2 xs ys zs 'echo /home/$1-$2$2$2-$(basename $3)'
# ---
function Array_mapi2 {
  local __bb_USAGE="Usage: Array_mapi2 [-a|--allow-shorter-first] ORIG1 ORIG2 DEST (FUNCNAME|BODY...)  # BODY is the body function using index \$1 and values \$2 and \$3";
  # ---
  local __bb_ALLOW_SHORTER_FIRST
  if [[ $1 = "-a" || $1 = "--allow-shorter-first" ]]; then __bb_ALLOW_SHORTER_FIRST="-a"; shift 1; fi
  # ---
  local __bb_ORIG1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 1; 
  local __bb_ORIG2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 2; 
  # ---
  local __bb_len
  Array_length2 ${__bb_ALLOW_SHORTER_FIRST} --caller "Array_mapi2" -v __bb_len "${__bb_ORIG1}" "${__bb_ORIG2}" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local __bb_DEST="$1" && Array_make -u "${__bb_USAGE}" "$1" && shift 1 || return 4;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_mapi2_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 5; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Array_mapi2.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 6
  # ---
  local __bb_i __bb_X1 __bb_X2 __bb_Y __bb_ref1 __bb_ref2
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref1="${__bb_ORIG1}[${__bb_i}]"
    __bb_ref2="${__bb_ORIG2}[${__bb_i}]"
    __bb_X1=${!__bb_ref1}
    __bb_X2=${!__bb_ref2}
    String_capture -t ${__bb_TMPFILE} __bb_Y ${__bb_FNAME} "${__bb_i}" "${__bb_X1}" "${__bb_X2}" || __bb_CODE=$((__bb_CODE+1));
    Array_set_unchecked ${__bb_DEST} "${__bb_i}" "${__bb_Y}"
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  return ${__bb_CODE}
}


# ---
# Returns the number of errors (may be 0).
# Example:
#   $ Array.make xs 3 5 7
#   $ Array_iteri xs 'echo /home/$1-$2$2$2'
#   /home/0-333
#   /home/1-555
#   /home/2-777
# ---
function Array_iteri {
  local __bb_USAGE="Usage: Array_iteri NAME (FUNCNAME|BODY...)  # BODY is the body function using index \$1 and value \$2";
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 1; 
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_iteri_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_ref __bb_X
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref="${__bb_ORIG}[${__bb_i}]"
    __bb_X=${!__bb_ref}
    ${__bb_FNAME} "${__bb_i}" "${__bb_X}" || __bb_CODE=$((__bb_CODE+1));
  done
  # ---
  return ${__bb_CODE}
}

# ---
# Returns the number of errors (may be 0).
function Array_iter2 {
  local __bb_USAGE="Usage: Array_iter2 [-a|--allow-shorter-first] NAME1 NAME2 (FUNCNAME|BODY...)  # BODY is the body function using values \$1 and \$2";
  # ---
  local __bb_ALLOW_SHORTER_FIRST
  if [[ $1 = "-a" || $1 = "--allow-shorter-first" ]]; then __bb_ALLOW_SHORTER_FIRST="-a"; shift 1; fi
  # ---
  local __bb_ORIG1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 1; 
  local __bb_ORIG2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 2; 
  # ---
  local __bb_len
  Array_length2 ${__bb_ALLOW_SHORTER_FIRST} --caller "Array_iter2" -v __bb_len "${__bb_ORIG1}" "${__bb_ORIG2}" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_iter2_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_len;
  # ---
  local __bb_i __bb_X1 __bb_X2 __bb_ref1 __bb_ref2
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref1="${__bb_ORIG1}[${__bb_i}]"
    __bb_ref2="${__bb_ORIG2}[${__bb_i}]"
    __bb_X1=${!__bb_ref1}
    __bb_X2=${!__bb_ref2}
    ${__bb_FNAME} "${__bb_X1}" "${__bb_X2}" || __bb_CODE=$((__bb_CODE+1));
  done
  # ---
  return ${__bb_CODE}
}

# ---
# Returns the number of errors (may be 0).
function Array_iteri2 {
  local __bb_USAGE="Usage: Array_iter2 [-a|--allow-shorter-first] NAME1 NAME2 (FUNCNAME|BODY...)  # BODY is the body function using index \$1 and values \$2 and \$3";
  # ---
  local __bb_ALLOW_SHORTER_FIRST
  if [[ $1 = "-a" || $1 = "--allow-shorter-first" ]]; then __bb_ALLOW_SHORTER_FIRST="-a"; shift 1; fi
  # ---  
  local __bb_ORIG1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 1; 
  local __bb_ORIG2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 ||  return 2; 
  # ---
  local __bb_len
  Array_length2 ${__bb_ALLOW_SHORTER_FIRST} --caller "Array_iteri2" -v __bb_len "${__bb_ORIG1}" "${__bb_ORIG2}" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Array_iteri2_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_i __bb_X1 __bb_X2 __bb_ref1 __bb_ref2
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_ref1="${__bb_ORIG1}[${__bb_i}]"
    __bb_ref2="${__bb_ORIG2}[${__bb_i}]"
    __bb_X1=${!__bb_ref1}
    __bb_X2=${!__bb_ref2}
    ${__bb_FNAME} "${__bb_i}" "${__bb_X1}" "${__bb_X2}" || __bb_CODE=$((__bb_CODE+1));
  done
  # ---
  return ${__bb_CODE}
}

# ---
function Array_copy {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_copy ORIG DEST";
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Array_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  Array_iteri ${__bb_ORIG} Array_set_unchecked ${__bb_DEST} '$1' '"$2"'
}

# ---
# Reverse an array.
# ---
# Example:
#  $ Array.make xs "alpha" "beta gamma" "delta" "chi" "phi"
#  $ Array.rev xs ys
#  $ declare -p xs ys
#  declare -a xs=([0]="alpha" [1]="beta gamma" [2]="delta" [3]="chi" [4]="phi")
#  declare -a ys=([0]="phi" [1]="chi" [2]="delta" [3]="beta gamma" [4]="alpha")
# ---
function Array_rev {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_rev ORIG DEST";
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Array_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  local -i __bb_N
  String_capture __bb_N Array_length "${__bb_ORIG}"
  Array_iteri ${__bb_ORIG} Array_set_unchecked ${__bb_DEST} '$((__bb_N - 1 - $1))' '"$2"'
}

# ---
# Example:
#  $ Array_make xs aaa "bbb ccc" ddd
#  $ Array_unpack -v xs x0 x1 x2
#  declare -- x0="aaa"
#  declare -- x1="bbb ccc"
#  declare -- x2="ddd"
# ---
function Array_unpack {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Array_unpack [-v|--verbose] NAME VAR...";
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local -a __Array_unpack_vars
  Array_make __Array_unpack_vars "$@" || return 2;
  # ---
  # Version fragile avec eval :
  # Array_iter2 --allow-shorter-first __Array_unpack_vars $ORIG 'unset $1 && eval $1=\"$2\"' || return 3
  # ---
  Array_iter2 --allow-shorter-first __Array_unpack_vars "${__bb_ORIG}" '
    local -n __Array_unpack_ref="$1";
    unset "$1";
    __Array_unpack_ref="$2";
    ' || return 3
  # ---
  [[ -n ${__bb_VERBOSE} ]] && declare -p "$@" 1>&2
}
alias Array_unfold=Array_unpack
alias Array.unfold=Array_unpack
alias Array_destruct=Array_unpack
alias Array.destruct=Array_unpack

# ---
function Array_append {
  local __bb_USAGE="Usage: Array_append ORIG1 ORIG2 DEST";
  # ---
  local __bb_ORIG1="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_ORIG2="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2; 
  local  __bb_DEST="$1" && Array_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 3;
  # ---
  eval "local __bb_len1=\${#${__bb_ORIG1}[@]}"
  Array_iteri ${__bb_ORIG1} Array_set_unchecked ${__bb_DEST} '$1' '"$2"'
  Array_iteri ${__bb_ORIG2} Array_set_unchecked ${__bb_DEST} '$((__bb_len1+$1))' '"$2"'
}

# ---
# Example:
#   $ Array.make xs aaa bbb ccc
#   $ Array.make ys 11 22 
#   $ Array.make zs
#   $ Array.make ts yes no may be
#   $ Array_concat CAT xs ys zs ts && declare -p CAT
#   declare -a CAT=([0]="aaa" [1]="bbb" [2]="ccc" [3]="11" [4]="22" [5]="yes" [6]="no" [7]="may" [8]="be")
# ---
function Array_concat {
  local __bb_USAGE="Usage: Array_concat DEST [ORIG]...";
  # ---
  local  __bb_DEST="$1" && Array_make -u "${__bb_USAGE}" "$1" && shift 1 || return 1;
  # ---
  local __bb_len1=0
  local __bb_len2
  local __bb_ORIG2
  # ---
  for __bb_ORIG2 in "$@"; do
    Declare_is_array -u "${__bb_USAGE}" -v "${__bb_ORIG2}" || return 2;
    eval "__bb_len2=\${#${__bb_ORIG2}[@]}"
    Array_iteri ${__bb_ORIG2} Array_set_unchecked ${__bb_DEST} '$((__bb_len1+$1))' '"$2"'
    let __bb_len1+=__bb_len2
  done  
  # ---
}
alias Array_flatten=Array_concat
alias Array.flatten=Array_concat

# ---
function Array_sort {
  local __bb_USAGE="Usage: Array_sort NAME [sort-binary-OPTIONS]";
  # ---
  local __bb_ars_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  # Check the [sort-binary-OPTIONS]:
  sort "$@" <<<"" 1>/dev/null || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  # Go:
  mapfile -t ${__bb_ars_NAME} < <(Array_iter ${__bb_ars_NAME} 'printf "%s\n" "$1"' | sort "$@")
  # ---
  return 0
}

# ---
# Examples: 
#    $ Array_make xs 10 2 30 4 50 5
#    ---
#    $ Array_sort xs  &&  Array_print xs
#    10 2 30 4 5 50
#    ---
#    $ Array_sort xs -n  &&  Array_print xs
#    2 4 5 10 30 50
#    ---
#    $ Array_sort xs -n -r  &&  Array_print xs
#    50 30 10 5 4 2
#    ---
#    $ Array_sorted_copy xs ts  &&  Array_print ts
#    10 2 30 4 5 50
#    ---
#    $ Array_sorted_copy xs ts -r  &&  Array_print ts
#    50 5 4 30 2 10
# ---
function Array_sorted_copy {
  local __bb_USAGE="Usage: Array_sorted_copy ORIG DEST [sort-binary-OPTIONS]";
  # ---
  local __bb_ORIG="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  [[ ${__bb_DEST} != ${__bb_ORIG} ]] && { Array_make -u "${__bb_USAGE}" "${__bb_DEST}" || return 3; }
  # ---
  # Check the [sort-binary-OPTIONS]:
  sort "$@" <<<"" 1>/dev/null || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  mapfile -t ${__bb_DEST} < <(Array_iter ${__bb_ORIG} 'printf "%s\n" "$1"' | sort "$@")
  # ---
  return 0
}
alias Array_copy_sort=Array_sorted_copy
alias Array.copy_sort=Array_sorted_copy

# ---
# Example
# ---
#   $ Array_make xs 200 300 '1000\n1001' 'aaa' 'bbb ccc'
#   $ Array_to_json -s xs
#   ["200","300","1000\\n1001","aaa","bbb ccc"]
#   $ X=$(Array.get xs 2) && echo "$X"
#   1000\n1001
#   $ echo $(Array.get xs 2)
#   1000\n1001
#   $ printf "%s\n" "$(Array.get xs 2)"
#   1000\n1001
#   $ printf "%b\n" "$(Array.get xs 2)"
#   1000
#   1001
#   Array_to_json -s xs | jq -c .
#   ["200","300","1000\\n1001","aaa","bbb ccc"]
#   $ Array_to_json xs | jq -c .
#   [200,300,"1000\\n1001","aaa","bbb ccc"]
# ---
function Array_to_json {
  local __bb_USAGE="Usage: Array_to_json [-s|--stringify|--no-parse-scalars] NAME";
  # ---
  local __bb_JSON_VALUES=y
  if [[ $1 = "-s" || $1 = "--stringify" || $1 = "--no-parse-scalars" ]]; then 
    unset __bb_JSON_VALUES; 
    shift 1; 
  fi
  # ---
  local __bb_atj_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local -n __bb_atj_NAME_ref="${__bb_atj_NAME}"
  local __bb_I  __bb_ESC  __bb_VAL
  # ---
  printf '['
  for ((__bb_I=0; __bb_I<${#__bb_atj_NAME_ref[@]}; __bb_I++)); do
    [[ ${__bb_I} -eq 0 ]] || printf ','
    __bb_VAL="${__bb_atj_NAME_ref[__bb_I]}"
    if [[ -n ${__bb_JSON_VALUES} ]] && Json_is_value "${__bb_VAL}"; then
      # ---
      printf '%s' "${__bb_VAL}"
      # ---
    else
      # ---
      __bb_ESC=$(Json_escape_string "${__bb_VAL}") || return 3
      printf '"%s"' "${__bb_ESC}"
      # ---
    fi
  done
  printf ']\n'
}


# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Array_help {
  { # less
  # ---
  cat 1>&2 <<"EOF"
---  
Usage: source bashbricks.sh  
Array_*: helpers around Bash's native arrays
---  
* Array_make
  Usage:     
      Array_make [-a|--append] NAME [VALUE]...
  Examples:  
      Array_make xs "$@"
      Array_make xs 10 20 30 40 
      Array_make xs /tmp/* /etc/*
      Array_make files "a b" "c d" "e"
---  
* Array_push
  Usage:     
      Array_push NAME [VALUE]...
  Description:
      Equivalent to "Array_make --append"
  Examples:  
      Array_push xs "$@"
      Array_make xs 10 20
      Array_push xs 30 40
      Array_push xs /var/log/*      
---
* Array_create
  Usage:
      Array_create NAME LENGTH [VALUE]
  Description:
      Convenience wrapper around Array_init to create an indexed array
      NAME of given LENGTH, all initialized with the same VALUE.
      If VALUE is omitted, elements are initialized with the empty string.
      NAME is (re)created as an indexed array.
  Examples:
      Array_create xs 4 && declare -p xs
      # declare -a xs=([0]="" [1]="" [2]="" [3]="")
      # ---
      Array_create xs 4 0 && declare -p xs
      # declare -a xs=([0]="0" [1]="0" [2]="0" [3]="0")
      # ---
      Array_create xs 4 '/tmp' && declare -p xs
      # declare -a xs=([0]="/tmp" [1]="/tmp" [2]="/tmp" [3]="/tmp")
  Notes:
      Internally uses Array_init with a BODY that ignores the index
      and always echoes VALUE. Without VALUE, 
        Array_create NAME LENGTH       is equivalent to:
        Array_init   NAME LENGTH true
---
* Array_init
  Usage:
      Array_init NAME LENGTH (FUNCNAME|BODY...)
      (BODY is the body function using index $1 and value $2)
  Description:
      Initializes an indexed array NAME with LENGTH elements.
      For each index i in [0, LENGTH-1], BODY is called as:
          BODY i
      and its standard output is captured as the value stored at index i.
      Returns the number of BODY failures (non-zero exit codes).
      NAME is (re)created as an indexed array.
  Examples:
      Array_init xs 8 'echo $1' && declare -p xs
      # declare -a xs=([0]="0" [1]="1" [2]="2" [3]="3" [4]="4" [5]="5" [6]="6" [7]="7")
      ---
      Array_init xs 8 'echo "" # ignore index $1' && declare -p xs
      # declare -a xs=([0]="" [1]="" [2]="" [3]="" [4]="" [5]="" [6]="" [7]="")
      ---
      Array_init xs 8 true && declare -p xs
      # declare -a xs=([0]="" [1]="" [2]="" [3]="" [4]="" [5]="" [6]="" [7]="")
  Notes:
      BODY can be either a function name or an inline command body.
      The index is always passed as first argument ($1).
---
* Array_import
  Usage:     
      Array_import NAME [FILE]...
  Description:
      Import lines from files (catenation) or STDIN by default
  Examples:
      Array_import xs /etc/fstab
      Array_print xs > /tmp/fstab
      diff /etc/fstab /tmp/fstab && echo YES  # YES
      Array_import A <(awk '/80[/]tcp.*/' /etc/services)
---
* Array_capture
    Usage:     
        Array_capture [-t|--tmpfile TMPFILE] NAME COMMAND...
    Description:
        Runs COMMAND with its arguments and captures each line of its
        standard output into the array NAME (NAME[0] is the first line,
        NAME[1] the second, etc.). The function returns the exit status
        of COMMAND, unless a usage error occurs.
        If -t/--tmpfile is provided, TMPFILE is used as the temporary
        file and is NOT removed by Array_capture; otherwise a temporary
        file is created and removed automatically.
    Examples:  
        Array_capture xs echo -e "hello\nworld"
        declare -p xs
        # declare -a xs=([0]="hello" [1]="world")

        Array_capture xs awk '$2 ~ /tcp/ {split($2, w, "/"); print $1, w[1];}' /etc/services
        Array_length xs
        #  218
        Array.get xs 16
        #  domain 53
---
* Array_scanf
  Usage:
      Array_scanf [-q|--quiet] NAME STRING REGEXP
  Description:
      Poor-man scanf in Bash.
      Matches STRING against REGEXP using Bash regular expressions
      and stores the captured groups into the indexed array NAME.
      If REGEXP defines N capturing groups, then:
          NAME[0], ..., NAME[N-1]
      are assigned to the corresponding captured substrings.
      If REGEXP contains no capturing group, NAME is left as an empty array.
      By default, a warning is printed on stderr when REGEXP has no
      capturing groups. Use -q|--quiet to suppress this warning.
  Returns:
      0 on successful match, even when REGEXP defines no capturing groups,
      1 if STRING does not match REGEXP,
      2 on invalid arguments,
      3 if NAME could not be created as an array.
  Examples:
      Array_scanf xs "room-unif-an25-2049" "room-(.*)-an25-(.*)" && declare -p xs
      # declare -a xs=([0]="unif" [1]="2049")

      Array_scanf xs "room-unif-an25-2049" "room-.*-an25-.*" && declare -p xs
      # Array_scanf: WARNING: REGEXP has no capturing groups; 'xs' will be an empty array.
      # declare -a xs=()

      Array_scanf --quiet xs "room-unif-an25-2049" "room-.*-an25-.*" && declare -p xs
      # declare -a xs=()
  Notes:
      - Captured groups are stored in a conventional Bash array starting
        at index 0.
      - Internally, the function skips BASH_REMATCH[0] (the full match)
        and stores only the capturing groups.
      - If no capturing group is present, the result is the empty array.
      - This function is useful as a lightweight alternative to scanf-like
        destructuring when using Bash regular expressions.
---
* Array_print
  Usage:     
      Array_print [-s|--sep|--separator SEP] NAME
  Examples:  
      Array_make xs 10 20 30
      Array_print xs           # 10\n20\n30\n
      Array_print -s "," xs    # 10,20,30\n
      Array_make paths /tmp /etc
      Array_print paths
---
* Array_unpack
  Usage:
      Array_unpack [-v|--verbose] NAME VAR...
  Description:
      Unpacks the contents of an indexed array NAME into scalar variables
      VAR..., in order. Each variable VARk is assigned the value of NAME[k],
      for k = 0, 1, 2, ... up to the number of provided VAR names.
      Existing variables with the same names are unset before assignment.
      Returns 0 on success, non-zero on error:
        1: NAME is not a valid array
        2: could not build internal variable list
        3: error while iterating over pairs (VAR, value)
  Examples:
      Array.make xs aaa "bbb ccc" ddd
      Array_unpack xs x0 x1 x2
      declare -p x0 x1 x2
      # declare -- x0="aaa"
      # declare -- x1="bbb ccc"
      # declare -- x2="ddd"

      # With verbose flag: variables are printed on stderr after unpacking
      Array_unpack -v xs x0 x1 x2 2>/dev/null
      # declare -- x0="aaa"
      # declare -- x1="bbb ccc"
      # declare -- x2="ddd"

      # Partial unpack: only the first two elements
      Array_unpack xs first second
      echo "$first / $second"
      # aaa / bbb ccc

  Notes:
      - The function only binds as many elements as there are VAR names.
        Extra elements in NAME are ignored.
      - Several aliases are provided for convenience:
          Array_unfold   (alias for Array_unpack)
          Array_destruct (alias for Array_unpack)
          Array.unfold   (OCaml-style alias)
          Array.destruct (OCaml-style alias)
---  
* Array_get
  Usage:     
      Array_get NAME INDEX
  Examples:  
      Array_make xs a b c
      Array_get xs 0
      Array_get xs 2
---
* Array_get_assign
  Usage:
      Array_get_assign NAME INDEX VAR
  Description:
      Reads the element at INDEX in the array NAME (as with Array_get)
      and stores its value into the scalar variable VAR, without printing
      anything on stdout.
      This is roughly equivalent to:
          VAR=$(Array_get NAME INDEX)
      but avoids a subshell.
  Returns:
      0 on success,
      non-zero if NAME is not a valid array or INDEX is invalid
  Examples:
      Array_make xs aaa bbb ccc
      Array_get_assign xs 1 x
      echo "$x"
      # bbb
---
* Array_get_assign_unchecked
  Usage:
      Array_get_assign_unchecked NAME INDEX VAR
  Description:
      Lighter version of Array_get_assign with fewer checks.
      Directly fetches NAME[INDEX] and assigns the value to VAR 
      without validating that NAME is an array or that INDEX is in range.
  Returns:
      0 on success,
      non-zero if the underlying access or assignment fails.
  Examples:
      Array_make xs aaa bbb ccc
      Array_get_assign_unchecked xs 2 last
      echo "$last"
      # ccc
  Notes:
      - Prefer Array_get_assign when you want bounds checking and
        clearer error messages. Use this unchecked variant only when
        you know NAME and INDEX are valid.
      - See Array_get_assign and Array_get for the fully-checked
        behavior.
---  
* Array_set
  Usage:     
      Array_set [-s|--strict] NAME INDEX VALUE
  Options:
      -s, --strict : returns an error if NAME does not already contain the INDEX.
  Examples:  
      Array_make xs a b c
      Array_set xs 1 B
      Array_get xs 1
---
* Array_set_unchecked
  Usage:
      Array_set_unchecked NAME INDEX VALUE
  Description:
      Low-level variant of Array_set with no safety checks:
      - does not verify that NAME is an array,
      - does not check that INDEX is valid or already present.
      Intended for internal use where bounds and types are guaranteed.
  Examples:
      Array_make xs a b c
      Array_set_unchecked Ys 10 Z  # creates Ys and writes at index 10 without error
      Array_set_unchecked xs 10 Z  # writes at index 10 without error (unlike Array_set --strict)
      Array_set_unchecked xs  1 B  # equivalent to Array_set xs 1 B
---   
* Array_length
  Usage:     
      Array_length NAME
  Examples:  
      Array_make xs 10 20 30 40
      Array_length xs
      Array_make ys
      Array_length ys
---
* Array_length2
  Usage:
      Array_length2 [-a|--allow-shorter-first] [--caller NAME] [-v|--assign VAR] NAME1 NAME2
  Description:
      Checks that arrays NAME1 and NAME2 have the same length.
      If they do, returns 0 and:
      - prints the common length on stdout, or
      - assigns it to VAR when -v/--assign VAR is used.
      If lengths differ, prints an error on stderr and returns 1.
  Options:
      -a|--allow-shorter-first : relax length equality: accept when length(NAME1) <= length(NAME2)
      --caller NAME            : prefix error message with the caller's name.
      -v, --assign V           : assign the common length to variable V instead of printing.
  Examples:
      Array_make xs 10 20 30
      Array_make ys aa bb cc
      Array_length2 xs ys         # prints 3
      Array_length2 -v LEN xs ys  # sets LEN=3
      Array_make zs 1 2
      Array_length2 xs zs         # error: different lengths, returns 1
---
* Array_has_index
  Usage:
      Array_has_index [-c|--check-is-array] [-v|--verbose] NAME INDEX
  Description:
      Returns 0 if INDEX is a valid index for the array NAME
      (i.e. 0 <= INDEX < Array_length NAME).
      Use the -c/--check-is-array option to first check whether NAME is an array.      
      With -v/--verbose, prints an error message on invalid index.
  Examples:
      Array_make xs a b c
      Array_has_index xs 0    # success
      Array_has_index xs 2    # success
      Array_has_index xs 3    # failure (out of range)
      Array_has_index xs -1   # failure (invalid index)
---
* Array_equal
  Usage:
      Array_equal NAME1 NAME2
  Description:
      Returns 0 if arrays NAME1 and NAME2 have the same length and
      identical elements at each index (string equality).
      Returns 1 otherwise.
  Examples:
      Array_make xs a b c
      Array_make ys a b c
      Array_make zs a x c
      Array_equal xs ys && echo "xs == ys"   # xs == ys
      Array_equal xs zs || echo "xs != zs"   # xs != zs
---
* Array_find
  Usage:     
      Array_find [-q|--quiet] NAME (FUNCNAME|BODY...) 
      (BODY is the body command using value $1)
  Description:
      Returns the first element X of the array such that:
          BODY X
      succeeds (exit code 0).
  Examples:  
      Array_make xs /does/not/exist /bin/ls
      Array_find xs 'test -x $1'
      Array_make xs /does/not/exist /tmp /etc /bin
      Array_find xs File_test_d
---
* Array_find2
  Usage:
      Array_find2 [-a|--allow-shorter-first] [-s|--sep SEP] [-q|--quiet] NAME1 NAME2 (FUNCNAME|BODY...)
      (BODY is the body predicate using values $1 and $2)
  Description:
      Searches in parallel arrays NAME1 and NAME2 for the first pair (X1,X2)
      such that BODY X1 X2 succeeds (exit code 0).
      If found, prints X1 and X2 separated by a space on stdout (SEP default).
      With -s/--sep SEP, prints X1 and X2 with another separator.
      With -q/--quiet, prints nothing and only returns 0/1.
      NAME1 and NAME2 must have the same length.
  Examples:
      Array_make xs 2 400 /tmp 8 999
      Array_make ys A B C D E
      Array_find2 xs ys 'test -d "$1"'      # prints: /tmp C
      Array_find2 xs ys 'test -f "$1"'      # (likely prints nothing, returns 1)
      Array_find2 --quiet xs ys 'test -d "$1"' && echo OK
---
* Array_exists
  Usage:     
      Array_exists NAME (FUNCNAME|BODY...) 
      (BODY is the body command using value $1)
  Description:
      Returns 0 if there exists an element X in the array such that:
          BODY X
      succeeds (exit code 0). 
      (Note: Array_exists NAME BODY = Array_find --quiet NAME BODY)
  Examples:  
      Array_make xs /tmp /etc /does/not/exist
      Array_exists xs 'test -d $1'
      Array_exists xs 'test -f $1'
      Array_exists xs  File_test_f
      Array_exists xs 'File_test_f -v $1'
---  
* Array_exists2
  Usage:     
      Array_exists2 [-a|--allow-shorter-first] NAME1 NAME2 (FUNCNAME|BODY...) 
      (BODY is the body command using values $1 and $2)
  Description:
      Returns 0 if there exists a couple of corresponding elements X1 X2 
      in the arrays NAME1 and NAME2 such that:
          BODY X1 X2
      succeeds (exit code 0). 
  Examples:  
      Array_make xs /tmp /etc /does/not/exist
      Array_exists xs 'test -d $1'
      Array_exists xs 'test -f $1'
      Array_exists xs  File_test_f
      Array_exists xs 'File_test_f -v $1'
---  
* Array_for_all
  Usage:     
      Array_for_all NAME (FUNCNAME|BODY...) 
      (BODY is the body command using value $1)
  Description:
      Returns 0 if BODY X succeeds for all elements X in the array.
  Examples:  
      Array_make xs 2 4 6 8
      Array_for_all xs '(( $1 % 2 == 0 ))'
      Array_for_all xs Int_even
      Array_for_all xs Int_odd
      Array_make ys 2 3 4
      Array_for_all ys '(( $1 % 2 == 0 ))'
---  
* Array_for_all2
  Usage:     
      Array_for_all2 [-a|--allow-shorter-first] NAME1 NAME2 (FUNCNAME|BODY...) 
      (BODY is the body command using values $1 and $2)
  Description:
      Returns 0 if BODY X1 X2 succeeds for all corresponding elements of NAME1 and NAME2.
  Examples:  
      Array_make xs 2 4 6 8
      Array_make ys 3 5 7 9
      Array_for_all2 xs ys '(( $1 < $2 ))'   && echo YES    # YES
      Array_for_all2 xs ys '(( 2*$1 < $2 ))' || echo NO     # NO
---  
* Array_member
  Usage:     
      Array_member NAME VALUE
  Description:
      Returns 0 if VALUE is equal (string equality) to one element of NAME.
  Examples:  
      Array_make xs a b c
      Array_member xs b
      Array_member xs d
---  
* Array_iter
  Usage:     
      Array_iter NAME (FUNCNAME|BODY...) 
      (BODY is the body command using variable $1)
  Description:
      Applies BODY X to each element X of the array.
      Returns the number of BODY command failures (non-zero exit codes).
  Examples:
      Array_make xs 2 4 6
      Array_iter xs 'echo $1'
      Array_iter xs '(( $1 % 2 == 0 ))'
---  
* Array_iteri
  Usage:     
      Array_iteri NAME (FUNCNAME|BODY...) 
      (BODY is the body command using index $1 and value $2)
  Description:
      Applies BODY i X to each element X, where i is the index.
      Returns the number of BODY failures.
  Examples:  
      Array_make xs a b c
      Array_iteri xs 'echo index: $1'      
      Array_iteri xs 'echo "$1 -> $2"'
---  
* Array_iter2
  Usage:     
      Array_iter2 [-a|--allow-shorter-first] NAME1 NAME2 (FUNCNAME|BODY...) 
      (BODY is the body command using values $1 and $2)
  Description:
      Applies BODY X1 X2 to corresponding elements of NAME1 and NAME2.
      Arrays must have the same length.
      Returns the number of BODY failures.
  Examples:  
      Array_make xs a b c
      Array_make ys 1 2 3
      Array_iter2 xs ys 'echo "$1 $2"'
      Array_iter2 xs ys 'test $1 = $2'   # return 3
      Array_iter2 xs ys 'test $1 != $2'  # return 0
---
* Array_iteri2
  Usage:     
      Array_iteri2 [-a|--allow-shorter-first] NAME1 NAME2 (FUNCNAME|BODY...) 
      (BODY is the body command using index $1, and values $2 and $3)
  Description:
      Applies BODY i X1 X2 to corresponding elements of NAME1 and NAME2.
      NAME1 must not be longer than NAME2.
      Returns the number of BODY failures.
  Examples:  
      Array_make xs a b
      Array_make ys 1 2
      Array_iteri2 xs ys 'echo "$1: ($2, $3)"'  # 0: (a, 1)    1: (b, 2)
---
* Array_iter_parallel
  Usage:
      Array_iter_parallel NAME (FUNCNAME|BODY...)
      Array_iter_parallel -i|--index NAME (FUNCNAME|BODY...)
      (BODY is the body function using value $1 (or index $1 and value $2 with -i))
  Description:
      Same job as Array_iter, but runs all iterations in parallel using futures.
      For each element x of array NAME, it launches BODY in a background future.
      When all futures are done, it returns the number of BODY failures
      (non-zero exit codes), which may be 0.
      With -i|--index|--call-with-index, BODY is called as:
          BODY index value
      otherwise as:
          BODY value
  Examples:
      Array_make xs 2 4 6

      # Sequential version:
      Array_iter xs 'sleep 4; echo "hello $1:$1";' 2>/dev/null
      # hello 2:2
      # hello 4:4
      # hello 6:6
      # (takes ~ 12 seconds)

      # Parallel version:
      Array_iter_parallel xs 'sleep 4; echo "hello $1:$1";' 2>/dev/null
      # hello 2:2
      # hello 4:4
      # hello 6:6
      # (takes ~ 4 seconds)

      # Propagation of errors:
      Array_iter_parallel xs 'sleep 3; echo "hello $1:$1"; return 64;'
      # same output but $? = 3 (three failures)

      # Exemple I/O-bound : tests de présence de fichiers en parallèle
      Array_import paths < <(find /etc -maxdepth 1 -type f | head -n 5)
      Array_iter_parallel paths '[[ -r "$1" ]] && echo "readable: $1"' 2>/dev/null
      # Affiche en parallèle tous les fichiers lisibles parmi les 5 premiers de /etc

      # Exemple I/O-bound : traitement de répertoires en parallèle
      Array_import dirs < <(find /etc/apache2/ -type d)
      # On cherche en parallèle les fichiers de configuration SSL dans chaque répertoire
      Array_iter_parallel dirs 'find "$1" -maxdepth 1 -type f -name "*ssl*conf*"' 2>/dev/null      
  Notes:
      This function is useful when BODY is I/O-bound or involves waiting,
      and the order of completion does not matter.
---
* Array_iteri_parallel
  Usage:
      Array_iteri_parallel NAME (FUNCNAME|BODY...)
      (BODY is the body function using index $1 and value $2)
  Description:
      Convenience wrapper over Array_iter_parallel -i.
      For an indexed array NAME, runs BODY i x in parallel for each index i
      and element x = NAME[i], using futures.
      Returns the number of BODY failures (non-zero exit codes), which may be 0.
  Examples:
      Array_make xs a b c
      Array_iteri_parallel xs 'printf "%d:%s\n" "$1" "$2"'
      # 0:a
      # 1:b
      # 2:c
  Notes:
      Equivalent to:
          Array_iter_parallel -i NAME BODY
---
* Array_copy
  Usage:     
      Array_copy ORIG DEST
  Description:
      Copies the content of ORIG into DEST.
  Examples:  
      Array_make xs a b c
      Array_copy xs ys
      Array_print ys
---
* Array_rev  
  Usage:     
      Array_rev ORIG DEST
  Description:
      Reverse an array into another array.
      Creates DEST as the reverse of ORIG (DEST is ORIG[last], etc.).
  Examples:  
      Array_make xs "alpha" "beta gamma" "delta" "chi" "phi"
      Array_rev xs ys
      declare -p xs ys
      # declare -a xs=([0]="alpha" [1]="beta gamma" [2]="delta" [3]="chi" [4]="phi")
      # declare -a ys=([0]="phi" [1]="chi" [2]="delta" [3]="beta gamma" [4]="alpha")
---  
* Array_append
  Usage:     
      Array_append ORIG1 ORIG2 DEST
  Description:
      DEST := ORIG1 followed by ORIG2.
  Examples:  
      Array_make xs 1 2
      Array_make ys 3 4 5
      Array_append xs ys zs
      Array_print zs
---
* Array_concat (alias: Array_flatten)
  Usage:     
      Array_concat DEST [ORIG]...
  Description:
      Concatenates all the arrays ORIG... into DEST. DEST is (re)created
      and filled with the elements of the first array, followed by the
      elements of the second array, and so on. Empty arrays are simply
      skipped. DEST must be given as a variable name.
  Examples:  
      Array_make xs aa bb cc
      Array_make ys 11 22
      Array_make zs
      Array_make ts yes no may be
      Array_concat CAT xs ys zs ts && declare -p CAT
      # declare -a CAT=([0]="aa" [1]="bb" [2]="cc" [3]="11" [4]="22" [5]="yes" [6]="no" [7]="may" [8]="be")      
---
* Array_sort
  Usage:     
      Array_sort NAME [sort-binary-OPTIONS]
  Description:
      Sorts NAME in place using the 'sort' command.
      Options are passed directly to 'sort'.
  Examples:  
      Array_make xs 10 2 30 4
      Array_sort xs
      Array_print xs
      Array_make ys 10 2 30 4
      Array_sort ys -n -r
      Array_print ys  # 30 10 4 2
---  
* Array_sorted_copy
  Usage:     
      Array_sorted_copy NAME1 NAME2 [sort-binary-OPTIONS]
  Description:
      Copies NAME1 into NAME2, sorted using 'sort'.
      Options are passed directly to 'sort'.
  Examples:  
      Array_make xs 10 2 30 4
      Array_sorted_copy xs ys
      Array_print ys
      Array_sorted_copy xs ys -n -r
      Array_print ys
---  
* Array_filter
  Usage:    
      Array_filter ORIG DEST FUNCNAME|BODY...
      BODY is the body predicate using index $1 and value $2.
  Description:     
      Builds DEST as a sub-array of ORIG with the elements for which
      BODY i X (i = index, X = value) succeeds (exit code 0).
  Examples: 
      Array_make xs a bb ccc dddd
      Array_filter xs ys 'test $1 -ge 2'
      Array_print ys    # ccc  dddd
---
* Array_map
  Usage:    
      Array_map ORIG DEST FUNCNAME|BODY...
      BODY is the body function using value $1.
  Description:     
      Builds DEST by applying BODY X to each element X of ORIG.
      DEST[i] contains the output of BODY X (captured stdout).
      Returns the number of failures (BODY with non-zero exit code).
  Examples: 
      Array_make xs a b c
      Array_map xs ys 'echo "/home/$1"'
      Array_print ys
---  
* Array_map2
  Usage:    
      Array_map2 [-a|--allow-shorter-first] ORIG1 ORIG2 DEST FUNCNAME|BODY...
      BODY is the body function using values $1 and $2.
  Description:     
      Builds DEST by applying BODY X1 X2 to each pair from ORIG1/ORIG2.
      Both arrays must have the same length.
      DEST[i] contains the output of BODY X1 X2.
      Returns the number of failures.
  Examples: 
      Array_make xs a b c
      Array_make ys 1 2 3
      Array_map2 xs ys zs 'echo "/home/$1/$2"'
      Array_print zs    # /home/a/1  /home/b/2  /home/c/3
---  
* Array_mapi
  Usage:    
      Array_mapi ORIG DEST FUNCNAME|BODY...
      BODY is the body function using index $1 and value $2.
  Description:     
      Builds DEST by applying BODY i X to each element X of ORIG.
      DEST[i] contains the output of BODY i X.
      Returns the number of failures.
  Examples: 
    Array_make xs a b c
    Array_mapi xs ys 'echo "$1:$2"'
    Array_print ys    # 0:a  1:b  2:c
---  
* Array_mapi2
  Usage:    
      Array_mapi2 [-a|--allow-shorter-first] ORIG1 ORIG2 DEST FUNCNAME|BODY...
      BODY is the body function using index $1 and values $2 and $3.
  Description:     
      Builds DEST by applying BODY i X1 X2 to each pair of elements.
      ORIG1 and ORIG2 must have the same length.
      DEST[i] contains the output of BODY i X1 X2.
      Returns the number of failures.
  Examples: 
      Array_make xs a b
      Array_make ys 1 2
      Array_mapi2 xs ys zs 'echo "$1:$2/$3"'
      Array_print zs    # 0:a/1  1:b/2
---
* Array_map_parallel
  Usage:
      Array_map_parallel ORIG DEST (FUNCNAME|BODY...)
      Array_map_parallel -i|--index ORIG DEST (FUNCNAME|BODY...)
      (BODY is the body function using value $1, or index $1 and value $2 with -i)
  Description:
      Parallel version of Array_map.
      For each element x of array ORIG, it runs BODY in a future and captures
      its stdout as the mapped value in DEST at the same index.
      DEST is (re)created as an indexed array.
      Returns the number of BODY failures (non-zero exit codes), which may be 0.
      With -i|--index|--call-with-index, BODY is called as:
          BODY index value
      otherwise as:
          BODY value
  Examples:
      Array_make xs 10 20 30

      # Double all values in parallel:
      Array_map_parallel xs ys 'echo "$(($1 * 2))"' 2>/dev/null
      # ys = (20 40 60)

      # Using index and value:
      Array_map_parallel -i xs zs 'echo "i=$1,v=$2"' 2>/dev/null
      # zs = ("i=0,v=10" "i=1,v=20" "i=2,v=30")

      # Exemple I/O-bound : récupérer la taille de fichiers en parallèle
      Array_import files < <(find /var/log -maxdepth 1 -type f | head -n 5)
      Array_map_parallel files sizes 'stat -c "%s" "$1"' 2>/dev/null
      # files[i] contient le chemin, sizes[i] la taille (en octets) du même fichier

      # Exemple I/O-bound : extraire la première ligne de plusieurs fichiers en parallèle
      Array_import confs < <(find /etc -maxdepth 1 -type f -name "*.conf" | head -n 3)
      Array_map_parallel confs first_lines 'head -n 1 "$1"' 2>/dev/null
      # first_lines[i] contient la première ligne du fichier confs[i]      
  Notes:
      The order of values in DEST respects the original indices of ORIG,
      even though the computations run in parallel.
---
* Array_mapi_parallel
  Usage:
      Array_mapi_parallel ORIG DEST (FUNCNAME|BODY...)
      (BODY is the body function using index $1 and value $2)
  Description:
      Convenience wrapper over Array_map_parallel -i.
      For each index i and element x of ORIG, runs BODY i x in parallel
      and stores the stdout of BODY as DEST[i].
      DEST is (re)created as an indexed array.
      Returns the number of BODY failures (non-zero exit codes), which may be 0.
  Examples:
      Array_make xs a b c
      Array_mapi_parallel xs ys 'echo "$1:$2"'
      # ys = ("0:a" "1:b" "2:c")
  Notes:
      Equivalent to:
          Array_map_parallel -i ORIG DEST BODY
---
* Array_to_set
  Usage:
      Array_to_set NAME SET
  Description:
      Builds the set SET from the contents of the indexed array NAME.
      Each element of NAME becomes an element of SET, represented as a
      key of an associative array mapped to the string "1".
      Duplicate elements in NAME are removed by construction.
  Examples:
      Array_make xs aaa bbb ccc aaa
      Array_to_set xs S
      declare -p S
      # declare -A S=([aaa]="1" [bbb]="1" [ccc]="1")
      Set_to_json S
      # ["bbb","ccc","aaa"]   # order not guaranteed
---
* Array_to_json
  Usage:
      Array_to_json [-s|--stringify|--no-parse-scalars] NAME
  Description:
      Prints a JSON array built from indexed array NAME, on a single line 
      (as with `jq -c`).
      By default, each Bash element is interpreted as follows:
        - if it is valid JSON text, it is emitted as the corresponding JSON value;
        - otherwise it is escaped and emitted as a JSON string.
      As a consequence, numbers, booleans, null, objects, arrays, and already
      quoted JSON strings are preserved as JSON values instead of being
      stringified again.
      With -s|--stringify|--no-parse-scalars, this automatic JSON parsing is
      disabled and every Bash element is serialized as a JSON string.
  Examples:
      Array_make xs 200 300 "1000+200" hello true
      Array_to_json    xs            # [200,300,"1000+200","hello",true]
      Array_to_json    xs | jq -c .  # [200,300,"1000+200","hello",true]
      Array_to_json -s xs | jq -c .  # ["200","300","1000+200","hello","true"]

      Array_make ys 42 null '{"x":1}' '[1,2]' '"already a JSON string"' plain
      Array_to_json    ys | jq -c .  # [42,null,{"x":1},[1,2],"already a JSON string","plain"]
      Array_to_json -s ys | jq -c .  # ["42","null","{\"x\":1}","[1,2]","\"already a JSON string\"","plain"]
EOF
  } 2>&1 | less
}

### ---------------------------------------------
###                   Map  
### ---------------------------------------------

# ---
# Examples:
#  $ Map_make m "nom de famille" "Dupont" "prénom" "Jean Pierre"
#  $ declare -p m
#  declare -A m=(["nom de famille"]="Dupont" [prénom]="Jean Pierre" )
#  $ Map_make -a m "age" "42" "portable" "06 99 98 97 96"
#  $ declare -p m
#  declare -A m=(["nom de famille"]="Dupont" [portable]="06 99 98 97 96" [age]="42" [prénom]="Jean Pierre" )
# ---
# TEST IMPORTANT: Respect des variables locales :
# ---
# $ function f { local -A xs; local -A ys; Map_make xs "$@"; Map_copy xs ys; declare -p xs ys; Map_print ys; }
# $ unset xs ys  &&  Map_make xs Name Dupont  &&  f aaa 111 bbb 222  &&  declare -p xs ys
# declare -A xs=([bbb]="222" [aaa]="111" )
# declare -A ys=([bbb]="222" [aaa]="111" )
# bbb 222
# aaa 111
# declare -A xs=([Name]="Dupont" )
# bash: declare: ys : non trouvé
# ---
function Map_make {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_make [-a|--append] NAME [KEY VAL]...";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_PLUS
  if [[ $1 = "-a" || $1 = "--append" || $1 = "--push" || $1 = "--update" ]]; then __bb_PLUS="+"; shift 1; fi
  # ---
  local __bb_mma_NAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  # Soit indéfinie (=> globale), soit déjà déclarée comme map (qu'elle soit locale ou globale) :
  Declare_is_undefined "${__bb_mma_NAME}" || Declare_is_map -u "${__bb_USAGE}" -v "${__bb_mma_NAME}" || return 2;
  # ---
  # Si la variable est indéfinie, on la considère comme variable globale (en réalité
  # ce n'est pas un choix, on ne peut pas faire autrement) :
  if Declare_is_undefined "${__bb_mma_NAME}"; then
    declare -Ag "${__bb_mma_NAME}=()"
  fi
  # ---
  local -n __Map_make_ref=${__bb_mma_NAME}
  if [[ -z ${__bb_PLUS} ]]; then
    __Map_make_ref=()
  else
    __Map_make_ref+=()
  fi
  # ---
  # Remplissage par Map_set_unchecked NAME KEY VAL :
  local __bb_key __bb_val
  while (( $# > 0 )); do
    __bb_key="$1"; shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
    __bb_val="$1"; shift 1 || { echo "${__bb_USAGE}" 1>&2; return 4; }
    Map_set_unchecked __Map_make_ref "${__bb_key}" "${__bb_val}"
  done
  # ---
  return 0  
}

# ---
# Alias for 'Map_make --append':
function Map_push {
  local __bb_USAGE="Usage: Map_push NAME [KEY VAL]...";
  # ---
  Map_make -u "${__bb_USAGE}" -a "$@"
}

# ---
# Example:
# ---
#   $ Map_capture TCP awk '$2 ~ /tcp/ {split($2, w, "/"); print $1, w[1];}' /etc/services
#   $ Map.get TCP domain
#   53
#   $ Map_inverse TCP SRV_OF_PORT
#   $ Map.get SRV_OF_PORT 80
#   http
#   $ Map.get SRV_OF_PORT 443
#   https
# ---
function Map_inverse {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_inverse ORIG DEST";
  # ---
  local __bb_ORIG="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Map_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  Map_iter ${__bb_ORIG} 'Map_set_unchecked '${__bb_DEST}' "$2" "$1"' 
  # ---
  local __bb_len_orig=$(Map_length ${__bb_ORIG})
  local __bb_len_dest=$(Map_length ${__bb_DEST})
  # ---
  if [[ ${__bb_len_orig} != ${__bb_len_dest} ]]; then
    echo "Map_inverse: WARNING: '${__bb_ORIG}' cannot be inverted properly (it contains $((__bb_len_orig-__bb_len_dest)) duplicated value(s))" 1>&2;  
    return 3
  fi
  # ---
  return 0
}

# ---
function Map_import {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_import [-k|--kv-sep|--key-value-sep SEP] NAME [FILE]...";
  # ---
  local __bb_KVSEP
  if [[ $1 = "-k" || $1 = "--kv-sep" || $1 = "--key-value-sep" ]]; then 
    __bb_KVSEP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  fi
  # ---
  local __bb_mim_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  Map_make ${__bb_mim_NAME}         || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Map_import.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 3
  # ---
  cat "$@" > ${__bb_TMPFILE}
  # ---
  local __bb_key __bb_LINE
  if [[ -z ${__bb_KVSEP} ]]; then
    while read -r __bb_key __bb_LINE || [[ -n ${__bb_key} ]]; do
      [[ -n "${__bb_key}" ]] && Map_set_unchecked ${__bb_mim_NAME} "${__bb_key}" "${__bb_LINE}"
    done 
  else
    while IFS="${__bb_KVSEP}" read -r __bb_key __bb_LINE || [[ -n ${__bb_key} ]]; do
      [[ -n "${__bb_key}" ]] && Map_set_unchecked ${__bb_mim_NAME} "${__bb_key}" "${__bb_LINE}"
    done 
  fi < ${__bb_TMPFILE}
  # ---
  rm -f ${__bb_TMPFILE}
  return 0
  # ---
}

# ---
# Example:
#   $ Map_capture M awk '/81[/]tcp.*/ {print $1,$2}' /etc/services
#   $ declare -p M
#   declare -A M=([kamanda]="10081/tcp" [tproxy]="8081/tcp" )
#   ---
#   $ Map_capture TCP awk '$2 ~ /tcp/ {split($2, w, "/"); print $1, w[1];}' /etc/services
#   $ Map.get TCP domain
#   53
#   $ Map.get TCP http
#   80
#   $ Map.get TCP https
#   443
# ---
function Map_capture {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_capture [-k|--kv-sep|--key-value-sep SEP] NAME COMMAND...";
  # ---
  local __bb_KVSEP
  if [[ $1 = "-k" || $1 = "--kv-sep" || $1 = "--key-value-sep" ]]; then 
    __bb_KVSEP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 5; } 
  fi
  # ---
  local __bb_TMPFILE __bb_TMPFILE_PROVIDED
  if [[ $1 = "-t" || $1 = "--tmpfile" ]]; then
    __bb_TMPFILE="$2";
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 5; }
    __bb_TMPFILE_PROVIDED=y
  fi
  # ---
  local __bb_mac_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  [[ $# -gt 0 ]]                || { echo "${__bb_USAGE}" 1>&2; return 2; }
  Map_make ${__bb_mac_NAME}         || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  if [[ -z "${__bb_TMPFILE}" ]]; then
    local __bb_mktemp_TEMPLATE=/tmp/Map_capture.XXXXXX
    __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  fi
  # ---
  local __bb_CODE=0
  # ---
  local __bb_CMD="$1"; shift 1
  "${__bb_CMD}" "$@" 1>"${__bb_TMPFILE}" || __bb_CODE=$?
  # ---
  local __bb_key __bb_LINE
  if [[ -z ${__bb_KVSEP} ]]; then
    while read -r __bb_key __bb_LINE || [[ -n ${__bb_key} ]]; do
      [[ -n "${__bb_key}" ]] && Map_set_unchecked ${__bb_mac_NAME} "${__bb_key}" "${__bb_LINE}"
    done 
  else
    while IFS="${__bb_KVSEP}" read -r __bb_key __bb_LINE || [[ -n ${__bb_key} ]]; do
      [[ -n "${__bb_key}" ]] && Map_set_unchecked ${__bb_mac_NAME} "${__bb_key}" "${__bb_LINE}"
    done 
  fi < ${__bb_TMPFILE}
  # ---
  [[ ${__bb_TMPFILE_PROVIDED} = y ]] || rm -f "${__bb_TMPFILE}"
  # ---
  return ${__bb_CODE}
  # ---
}

# ---
# Example:
#   $ Map_make m "nom de famille" "Dupont" "prénom" "Jean Pierre"
#   $ Map_print m 
#   nom de famille Dupont
#   prénom Jean Pierre
#   ---
#   $ declare -A m=([aa]="10" [bb]="20" [cc]="30" [dd]="40")
#   $ Map_import m2 <(Map_print m)
#   $ Map_print -k ':' m2
#   dd:40
#   aa:10
#   cc:30
#   bb:20
# ---
function Map_print {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_print [-k|--kv-sep|--key-value-sep SEP] [-s|--sep|--separator SEP] NAME";
  # ---
  local __bb_KVSEP=" "
  if [[ $1 = "-k" || $1 = "--kv-sep" || $1 = "--key-value-sep" ]]; then 
    __bb_KVSEP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  fi
  # ---
  local __bb_SEP="\n"
  if [[ $1 = "-s" || $1 = "--sep" || $1 = "--separator" ]]; then 
    __bb_SEP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  fi
  # ---
  local __bb_mpr_NAME="$1" && Declare_is_map -v "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  eval "local __bb_LENGTH=\${#${__bb_mpr_NAME}[@]}"
  local __bb_LAST_INDEX=$((__bb_LENGTH-1))
  local __bb_NL="${__bb_SEP}"
  # ---
  local __bb_CMD='printf "%b%b%b%b" "$1" "${__bb_KVSEP}" "$2" "${__bb_NL}"'
  # ---
  Map_iter ${__bb_mpr_NAME} "${__bb_CMD}"
}

# ---
# The Bash basic get operator succeeds even when 
# the key does not belong the associative array. 
# So we need this low-level function.
# ---
# Map_get: returns 0 iff KEY exists in associative array NAME
#          prints the value (may be empty string).
function Map_get_unchecked {
  # local USAGE="Usage: Map_get_unchecked NAME KEY";
  # ---
  [[ $# = 2 ]] || return 1; # ok, not completely unchecked...
  # ---
  # Name reference to the associative array
  local -n __bb_mgu_NAME_ref="$1"
  # ---
  # Test existence of the key (even if value is "")
  if [[ -v __bb_mgu_NAME_ref["$2"] ]]; then
    printf '%s\n' "${__bb_mgu_NAME_ref[$2]}"
    return 0
  else
    return 1
  fi
}

# ---
function Map_get_assign_unchecked {
  # local USAGE="Usage: Map_get_assign_unchecked NAME KEY VARNAME";
  # ---
  [[ $# = 3 ]] || return 1; # ok, not completely unchecked...
  # ---
  # Name reference to the associative array
  local -n __bb_mga_NAME_ref="$1"
  # ---
  # Test existence of the key (even if value is "")
  if [[ -v __bb_mga_NAME_ref["$2"] ]]; then
    local -n __bb_mga_VARNAME_ref="$3"
    __bb_mga_VARNAME_ref="${__bb_mga_NAME_ref[$2]}"
    return 0
  else
    return 1
  fi
}

# ---
# Examples:
#   $ declare -A m=([30]="cc" [20]="bb" [40]="dd" [10]="aa" )
#   $ Map_has_key m a   # returns 1
#   $ Map_has_key m aa  # returns 1
#   $ Map_has_key m 10  # returns 0
#   $ Map_has_key m 11  # returns 1
# ---
function Map_has_key {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_has_key [-c|--check-is-map] [-v|--verbose] NAME KEY";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_CHECK_IS_MAP
  if [[ $1 = "-c" || $1 = "--check-is-map" ]]; then __bb_CHECK_IS_MAP="y"; shift 1; fi
  # ---
  local __bb_VERBOSE
  if [[ $1 = "-v" || $1 = "--verbose" ]]; then __bb_VERBOSE="-v"; shift 1; fi
  # ---
  local __bb_mhk_NAME="$1" && { [[ -z ${__bb_CHECK_IS_MAP} ]] || Declare_is_map -v "$1"; } && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  local  __bb_key="$1" && shift 1 || { 
    [[ -n ${__bb_VERBOSE} ]] && echo "Invalid key '$1'" 1>&2 && echo "${__bb_USAGE}" 1>&2; 
    return 3; 
    }
  # ---
  # Name reference to the associative array:
  local -n __Map_has_key_NAME_ref="${__bb_mhk_NAME}"
  local __bb_CODE=0
  # ---
  # Test existence of the key (even if value is "")
  [[ -v __Map_has_key_NAME_ref["${__bb_key}"] ]] || {
    __bb_CODE=1
    [[ -n ${__bb_VERBOSE} ]] && echo "Error: key '${__bb_key}' not in the associative array '${__bb_mhk_NAME}'" 1>&2 && echo "${__bb_USAGE}" 1>&2; 
    }
  # ---
  return ${__bb_CODE}
}

# ---
# Examples:
#   $ declare -A m=([aa]="10" [bb]="20" [cc]="30" [dd]="40" )
#   $ Map_member m a  10    # returns 1
#   $ Map_member m aa 1     # returns 1
#   $ Map_member m aa 10    # returns 0
# ---
function Map_member {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_member NAME KEY VALUE";
  [[ $# = 3 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---  
  local __bb_val
  __bb_val=$(Map_has_key -u "${__bb_USAGE}" --check-is-map -v "$1" "$2" && Map_get_unchecked "$1" "$2")
  local __bb_CODE=$?
  # ---  
  if [[ ${__bb_CODE} = 0 && "${__bb_val}" = "$3" ]]; then
    return 0
  else  
    return 1
  fi  
}

# ---
function Map_member_unchecked {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  # local __bb_USAGE="Usage: Map_member_unchecked NAME KEY VALUE";
  [[ $# = 3 ]] || return 3
  # ---  
  local __bb_val
  __bb_val=$(Map_has_key "$1" "$2" && Map_get_unchecked "$1" "$2")
  local __bb_CODE=$?
  # ---  
  if [[ ${__bb_CODE} = 0 && "${__bb_val}" = "$3" ]]; then
    return 0
  else  
    return 1
  fi  
}

# ---
function Map_set {
  local __bb_USAGE="Usage: Map_set [-s|--strict] NAME KEY VAL";
  # ---
  local __bb_STRICT
  if [[ $1 = "-s" || $1 = "--strict" ]]; then __bb_STRICT="y"; shift 1; fi
  # ---
  local __bb_mse_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  # ---
  local __bb_key
  if [[ ${__bb_STRICT} = y ]]; then
    __bb_key="$1" && Map_has_key -u "${__bb_USAGE}" -v "${__bb_mse_NAME}" "$1" && shift 1 || return 2;
  else
    __bb_key="$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
  fi
  # ---
  local __bb_val="$1"  && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 4; }
  [[ $# = 0 ]]                    || { echo "${__bb_USAGE}" 1>&2; return 5; }
  # ---
  # Construction de la référence, puis affectation par eval :
  local __bb_ref="${__bb_mse_NAME}['${__bb_key}']"
  eval "${__bb_ref}=\${__bb_val}"
}

# ---
function Map_set_unchecked {
  # local USAGE="Usage: Map_set_unchecked NAME KEY VALUE";
  # ---
  [[ $# = 3 ]] || return 1; # ok, not completely unchecked...
  # ---
  local __bb_ref="${1}['${2}']"
  eval "${__bb_ref}=\${3}"
}

# ---
# This is implicitely a "strict" version (because of Map_has_key):
function Map_get {
  local __bb_USAGE="Usage: Map_get NAME KEY";
  # ---
  local __bb_mge_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v                    "$1" && shift 1 || return 1; 
  local      __bb_key="$1" && Map_has_key    -u "${__bb_USAGE}" -v "${__bb_mge_NAME}" "$1" && shift 1 || return 2;
  # ---
  local __bb_ref="${__bb_mge_NAME}[${__bb_key}]"
  # ---
  echo "${!__bb_ref}"
}

# ---
function Map_get_assign {
  local __bb_USAGE="Usage: Map_get_assign NAME KEY VARNAME";
  # ---
  local    __bb_mga_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v                    "$1" && shift 1 || return 1; 
  local         __bb_key="$1" && Map_has_key    -u "${__bb_USAGE}" -v "${__bb_mga_NAME}" "$1" && shift 1 || return 2;
  local __bb_mga_VARNAME="$1"                                                                 && shift 1 || return 3;
  # ---
  # Name reference to the associative array:
  local -n __bb_mga_NAME_ref="${__bb_mga_NAME}"
  # ---
  # Test existence of the key (even if value is "")
  if [[ -v __bb_mga_NAME_ref["${__bb_key}"] ]]; then
    local -n __bb_mga_VARNAME_ref="${__bb_mga_VARNAME}"
    __bb_mga_VARNAME_ref="${__bb_mga_NAME_ref[${__bb_key}]}"
    return 0
  else
    return 1
  fi
}


# ---
# Note: identical to Array_length
function Map_card {
  local __bb_USAGE="Usage: Map_card NAME";
  # ---
  local __bb_mca_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  eval "local __bb_LENGTH=\${#${__bb_mca_NAME}[@]}"
  echo "${__bb_LENGTH}"
}
# alias Map_length=Map_card
# function Map_length { Map_card "$@"; }
Function_clone --replace-refs  Map_card  Map_length

# ---
# Examples:
#  ---
#  $ Array_make xs 10 20 30 40
#  $ Array_make ys aa bb cc dd
#  $ Map_combine m xs ys
#  $ declare -p m
#  declare -A m=([30]="cc" [20]="bb" [40]="dd" [10]="aa" )
#  ---
#  $ Map_combine -a m ys xs    ### --append here
#  $ declare -p m
#  declare -A m=([30]="cc" [dd]="40" [aa]="10" [20]="bb" [cc]="30" [40]="dd" [10]="aa" [bb]="20" )
#  ---
#  $ Map_combine m ys xs       ### without --append => recreate
#  $ declare -p m
#  declare -A m=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
# ---
function Map_combine {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_combine [-a|--append] NAME KEY-ARRAY VAL-ARRAY";
  # ---
  local __bb_APPEND
  if [[ $1 = "-a" || $1 = "--append" || $1 = "--push" || $1 = "--update" ]]; then __bb_APPEND="-a"; shift 1; fi
  # ---
  local __bb_mca_NAME="$1" && Regexp_is_ident  "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  local    __bb_KNAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2
  local    __bb_VNAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 3
  # ---
  Map_make ${__bb_APPEND} ${__bb_mca_NAME} || return 4
  # ---
  Array_iter2 ${__bb_KNAME} ${__bb_VNAME} 'Map_set_unchecked '${__bb_mca_NAME}' "$1" "$2"'
}

# ---
function Map_split {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_split NAME KEY-ARRAY VAL-ARRAY";
  # ---
  local __bb_msp_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  local    __bb_KNAME="$1" && Regexp_is_ident  "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  local    __bb_VNAME="$1" && Regexp_is_ident  "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  # __NAME_ref is a nameref to the associative array NAME:
  local -n __bb_msp_NAME_ref="${__bb_msp_NAME}" # declare -n
  # ---
  # Build KEY and VAL arrays from the map:
  Array_make "${__bb_KNAME}" "${!__bb_msp_NAME_ref[@]}" || return 4
  Array_make "${__bb_VNAME}"  "${__bb_msp_NAME_ref[@]}" || return 5
  # ---
  return 0  
}

# ---
function Map_to_key_array {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_to_key_array NAME KEY-ARRAY";
  # ---
  local __bb_mtk_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  local    __bb_KNAME="$1" && Regexp_is_ident  "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  # __NAME_ref is a nameref to the associative array NAME:
  local -n __bb_mtk_NAME_ref="${__bb_mtk_NAME}" # declare -n
  # ---
  # Build KEY array from the map:
  Array_make "${__bb_KNAME}" "${!__bb_mtk_NAME_ref[@]}" || return 3
  # ---
  return 0  
}

# ---
function Map_to_array {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_to_array NAME VAL-ARRAY";
  # ---
  local __bb_mta_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  local    __bb_VNAME="$1" && Regexp_is_ident  "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  # __NAME_ref is a nameref to the associative array NAME:
  local -n __bb_mta_NAME_ref="${__bb_mta_NAME}" # declare -n
  # ---
  # Build VAL array from the map:
  Array_make "${__bb_VNAME}"  "${__bb_mta_NAME_ref[@]}" || return 4
  # ---
  return 0  
}
# alias Map_to_val_array=Map_to_array
# function Map_to_val_array { Map_to_array "$@"; }
Function_clone --replace-refs  Map_to_array  Map_to_val_array

# ---
# Example:
#   $ Map_make m "nom de famille" "Dupont" portable "06 99 98 97 96" age 42 "prénom" "Jean Pierre"
#   $ Map_to_json m
#   {"nom de famille":"Dupont","portable":"06 99 98 97 96","age":"42","prénom":"Jean Pierre"}
#   $ Map_to_json m | jq .
# ---
function Map_to_json {
  # { set -x; trap 'set +x' RETURN; }
  local __bb_USAGE="Usage: Map_to_json [-s|--stringify|--no-parse-scalars] NAME";
  # ---
  local __bb_JSON_VALUES=y
  if [[ $1 = "-s" || $1 = "--stringify" || $1 = "--no-parse-scalars" ]]; then 
    unset __bb_JSON_VALUES; 
    shift 1; 
  fi
  # ---
  local __bb_mtj_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local -n __bb_mtj_NAME_ref="${__bb_mtj_NAME}"
  local __bb_KEY __bb_ESC_KEY __bb_ESC_VAL __bb_VAL
  local __bb_FIRST=y
  # ---
  printf '{'
  for __bb_KEY in "${!__bb_mtj_NAME_ref[@]}"; do
    [[ ${__bb_FIRST} = y ]] || printf ','
    __bb_FIRST=
    __bb_ESC_KEY=$(Json_escape_string "${__bb_KEY}") || return 3
    __bb_VAL="${__bb_mtj_NAME_ref[${__bb_KEY}]}"
    if [[ -n ${__bb_JSON_VALUES} ]] && Json_is_value "${__bb_VAL}"; then
      # ---
      printf '"%s":%s' "${__bb_ESC_KEY}" "${__bb_VAL}"
      # ---
    else
      # ---
      __bb_ESC_VAL=$(Json_escape_string "${__bb_VAL}") || return 5
      printf '"%s":"%s"' "${__bb_ESC_KEY}" "${__bb_ESC_VAL}"
      # ---
    fi
  done
  printf '}\n'
}


# ---
# Returns the number of errors (may be 0).
# ---
# Example:
#   Map_iter m 'printf "%s -> %s\n" "$1" "$2"'
# ---
function Map_iter {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_iter NAME (FUNCNAME|BODY...)  # BODY is the body command using key \$1 and value \$2";
  # ---
  local __bb_mit_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Map_iter_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_mit_NAME} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_mit_NAME}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do 
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    ${__bb_FNAME} "${__bb_key}" "${__bb_val}" || __bb_CODE=$((__bb_CODE+1));
  done
  # ---
  return ${__bb_CODE}
}

# ---
# Example:
#  $ Map.make CASES a 'echo AAA' b 'echo BBB' c 'echo CCC' d 'false' e 'true'
#  $ Map_case_do CASES a
#  AAA
#  $ Map_case_do CASES d || echo NO    # => NO
#  $ Map_case_do CASES e && echo YES   # => YES
# ---
function Map_case_do {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_case_do [-n|--dry-run] NAME KEY";
  # ---
  local __bb_DRY_RUN
  if [[ $1 = "-n" || $1 = "--just-print" || $1 = "--dry-run" ]]; then __bb_DRY_RUN="echo"; shift; fi
  # ---
  local __bb_mcd_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1"                    && shift 1 || return 1;
  local      __bb_key="$1" && Map_has_key    -u "${__bb_USAGE}" -v "${__bb_mcd_NAME}" "$1" && shift 1 || return 2;
  # ---
  local __bb_BODY
  Map_get_assign_unchecked "${__bb_mcd_NAME}" "${__bb_key}" __bb_BODY
  # ---
  ${__bb_DRY_RUN}  ${__bb_BODY};
  # ---
  return $?
}
alias Map_run_action=Map_case_do
alias Map.run_action=Map_case_do

# ---
# Returns the number of errors (may be 0).
# ---
# Example:
#   $ declare -A m=([k1]="200" [k2]="300" [k3]="1000" )
#   $ Map_iteri m 'printf "%s: %s -> %s\n" "$1" "$2" "$3"'
#   0: k1 -> 200
#   1: k2 -> 300
#   2: k3 -> 1000
# ---
function Map_iteri {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_iteri NAME (FUNCNAME|BODY...)  # BODY is the body command using key \$1 and value \$2";
  # ---
  local __bb_mri_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Map_iter_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_mri_NAME} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_mri_NAME}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do 
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    ${__bb_FNAME} "${__bb_i}" "${__bb_key}" "${__bb_val}" || __bb_CODE=$((__bb_CODE+1));
  done
  # ---
  return ${__bb_CODE}
}

# ---
# Example:
#   $ declare -A m=([aa]="10" [bb]="20" [cc]="30" [dd]="40" )
#   $ Map_map m m1 'echo "/home/$1/$2"'
#   $ declare -p m1
#   declare -A m1=([dd]="/home/dd/40" [aa]="/home/aa/10" [cc]="/home/cc/30" [bb]="/home/bb/20" )
# ---
function Map_map {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_map ORIG DEST (FUNCNAME|BODY...)  # BODY is the body function using key \$1 and value \$2";
  # ---
  local __bb_ORIG="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Map_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Map_map_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Map_map.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_ORIG} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef __bb_Y
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    String_capture -t ${__bb_TMPFILE} __bb_Y ${__bb_FNAME} "${__bb_key}" "${__bb_val}" || __bb_CODE=$((__bb_CODE+1));
    Map_set_unchecked ${__bb_DEST} "${__bb_key}" "${__bb_Y}"
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  return ${__bb_CODE}
}

# ---
# Example: 
#   $ declare -A m=([aa]="10" [bb]="20" [cc]="30" [dd]="40" )
#   $ Map_find m '[[ $1 = "cc" ]]'
#   cc 30
#   $ Map_find -s ':' m '[[ $1 = "cc" ]]'
#   cc:30
#   $ Map_find -s ':' m '[[ $1 =~ "c" ]]'
#   cc:30
#   $ Map_find -s ':' m '[[ $1 =~ "qq" ]]' && echo YES
#   $ Map_find -s ':' m '[[ $1 =~ "c" && $2 -gt 30 ]]' && echo YES
#   $ Map_find -s ':' m '[[ $1 =~ "c" && $2 -gt 29 ]]' && echo YES
#   cc:30
#   YES
#   ---
function Map_find {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_find NAME [-s|--sep|--separator SEP] (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1 and value \$2";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_SEP=" "
  if [[ $1 = "-s" || $1 = "--sep" || $1 = "--separator" ]]; then 
    __bb_SEP="$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  fi
  # ---
  local __bb_QUIET
  if [[ $1 = "-q" || $1 = "--quiet" ]]; then __bb_QUIET="y"; shift 1; fi
  # ---
  local __bb_mfi_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Map_find_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_mfi_NAME} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_mfi_NAME}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    # ---
    if ${__bb_FNAME} "${__bb_key}" "${__bb_val}"; then
      [[ -n ${__bb_QUIET} ]] || echo "${__bb_key}${__bb_SEP}${__bb_val}";
      return 0;
    fi
    # ---
  done
  # ---
  return 1;
}

# ---
# Just an alias for 'Map_find --quiet'.
# ---
# Examples: 
#  $ declare -A m=([aa]="10" [bb]="20" [cc]="30" [dd]="40" )
#  $ Map_exists m '[[ $1 =~ "c" && $2 -gt 29 ]]' && echo YES
#  YES
#  $ Map_exists m '[[ $1 =~ "c" && $2 -gt 30 ]]' || echo NO
#  NO
# ---
function Map_exists {
  # ---
  local __bb_USAGE="Usage: Map_exists NAME (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1 and value \$2";
  # ---
  Map_find -u "${__bb_USAGE}" --quiet "$@"
}

# ---
#  $ declare -A m=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
#  $ Map_for_all m '[[ $2 -ge 0 ]]' && echo YES
#  YES
#  $ Map_for_all m '[[ $2 -ge 11 ]]' && echo YES    # no
#  $ Map_exists  m '[[ $2 -ge 11 ]]' && echo YES
#  YES
#  ---
function Map_for_all {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_for_all NAME (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1 and value \$2";
  # ---
  local __bb_mfa_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Map_for_all_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # --- 
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_mfa_NAME} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_mfa_NAME}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    # ---
    if ${__bb_FNAME} "${__bb_key}" "${__bb_val}"; then
      continue;
    else  
      return 1;
    fi
    # ---
  done
  # ---
  return 0;
}

#  ---
#  $ declare -A m1=([aa]="10" [bb]="20" [cc]="30" [dd]="40")
#  $ declare -A m2=([aa]="10" [bb]="20" [cc]="30" [dd]="40")
#  $ Map_equal m1 m2 && echo YES    # YES
#  $ Map_set m1 aa 1000
#  $ Map_equal m1 m2 || echo NO     # NO
# ---
function Map_equal {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_equal NAME1 NAME2";
  # ---
  local __bb_meq_NAME1="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  local __bb_meq_NAME2="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  Map_for_all ${__bb_meq_NAME1} 'Map_member_unchecked '${__bb_meq_NAME2}' "$1" "$2"' && \
  Map_for_all ${__bb_meq_NAME2} 'Map_member_unchecked '${__bb_meq_NAME1}' "$1" "$2"'
}

# ---
# Examples:
#  $ declare -A m=([aa]="10" [bb]="20" [cc]="30" [dd]="40" )
#  $ Map_filter m m1 '[[ $2 -gt 20 ]]'
#  $ Map_filter m m2 '[[ $2 -ge 20 ]]'
#  $ declare -p m m1 m2
#  declare -A  m=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
#  declare -A m1=([dd]="40" [cc]="30" )
#  declare -A m2=([dd]="40" [cc]="30" [bb]="20" )
# ---
function Map_filter {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_filter ORIG DEST (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1 and value \$2";
  # ---
  local __bb_ORIG="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Map_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Map_filter_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  # --- 
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_ORIG} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  # ---
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    # ---
    if ${__bb_FNAME} "${__bb_key}" "${__bb_val}"; then
      Map_set_unchecked ${__bb_DEST} "${__bb_key}" "${__bb_val}"  
    fi
    # ---
  done
  # ---
  return 0;
}

# ---
# Example:
#  $ declare -A m=([aa]="10" [bb]="20" [cc]="30" [dd]="40" )
#  $ Map_copy m c
#  $ declare -p m c
#  declare -A m=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
#  declare -A c=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
# ---
function Map_copy {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_copy ORIG DEST";
  # ---
  local __bb_ORIG="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Map_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  Map_iter ${__bb_ORIG} 'Map_set_unchecked '${__bb_DEST}' "$1" "$2"'
}

# ---
# Note: fonctionne parfaitement mais en construisant 2 copies (Map_filter + Map_copy).
# ---
# Example:
#   $ declare -A m=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
#   ---
#   $ Map_filter_inplace m '[[ $2 -ge 20 ]]' && declare -p m
#   declare -A m=([dd]="40" [cc]="30" [bb]="20" )
#   ---
#   $ Map_filter_inplace m '[[ $2 -gt 20 ]]' && declare -p m
#   declare -A m=([dd]="40" [cc]="30" )
#   ---
#   $ Map_filter_inplace m '[[ $2 -gt 30 ]]' && declare -p m
#   declare -A m=([dd]="40" )
# ---
function Map_filter_inplace {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_filter_inplace NAME (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1 and value \$2";
  [[ $# -ge 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---  
  local __bb_mfp_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_TMPNAME
  # Ex: declare tmpName_4718 && TMPNAME=tmpName_4718
  eval $(Declare_fresh_name __bb_TMPNAME tmpName)
  declare -A "${__bb_TMPNAME}" # local map
  # ---
  Map_filter "${__bb_mfp_NAME}" "${__bb_TMPNAME}" "$@" || return 3
  Map_copy "${__bb_TMPNAME}" "${__bb_mfp_NAME}"        || return 4
  return 0
}

# ---
#  $ declare -A m1=([aa]="10" [bb]="20")
#  $ declare -A m2=([cc]="30" [dd]="40")
#  $ Map_merge m1 m2 MERGE && declare -p MERGE
#  declare -A MERGE=([aa]="10" [bb]="20" [cc]="30" [dd]="40")
# ---
function Map_merge {
  local __bb_USAGE="Usage: Map_merge ORIG1 ORIG2 DEST";
  # ---
  local __bb_ORIG1="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_ORIG2="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2; 
  local  __bb_DEST="$1" && Map_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 3;
  # ---
  Map_iter ${__bb_ORIG1} 'Map_set_unchecked '${__bb_DEST}' "$1" "$2"'
  Map_iter ${__bb_ORIG2} 'Map_set_unchecked '${__bb_DEST}' "$1" "$2"'
  # ---
  local __bb_len_orig1=$(Map_length ${__bb_ORIG1})
  local __bb_len_orig2=$(Map_length ${__bb_ORIG2})
  local  __bb_len_dest=$(Map_length ${__bb_DEST})
  # ---
  if [[ $((__bb_len_orig1+__bb_len_orig2)) != ${__bb_len_dest} ]]; then
    echo "Map_merge: WARNING: '${__bb_ORIG1}' and '${__bb_ORIG2}' cannot be merged properly (their union contains $((__bb_len_orig1+__bb_len_orig2-__bb_len_dest)) duplicated key(s))" 1>&2;  
    return 4
  fi
  # ---
  return 0
}

# ---
#  $ declare -A m1=([aa]="10" [bb]="20")
#  $ declare -A m2=([cc]="30" [dd]="40")
#  $ declare -A m3=([ee]="50" [ff]="60")
#  $ Map_union UNION m1 m2 m3 && declare -p UNION
#  declare -A UNION=([aa]="10" [bb]="20" [cc]="30" [dd]="40" [ee]="50" [ff]="60")
# ---
function Map_union {
  local __bb_USAGE="Usage: Map_union DEST [ORIG]...";
  # ---
  local __bb_DEST="$1" && Map_make -u "${__bb_USAGE}" "$1" && shift 1 || return 1;
  # ---
  local __bb_len1=0
  local __bb_len2
  local __bb_ORIG2
  # ---
  for __bb_ORIG2 in "$@"; do
    Declare_is_map -u "${__bb_USAGE}" -v "${__bb_ORIG2}" || return 2;
    # ---
    Map_iter ${__bb_ORIG2} 'Map_set_unchecked '${__bb_DEST}' "$1" "$2"'
    # ---
    __bb_len2=$(Map_length ${__bb_ORIG2})
    let __bb_len1+=__bb_len2
  done  
  # ---
  local  __bb_len_dest=$(Map_length ${__bb_DEST})
  # ---
  if [[ $((__bb_len1)) != ${__bb_len_dest} ]]; then
    echo "Map_union: WARNING: maps cannot be merged properly (their union contains $((__bb_len1-__bb_len_dest)) duplicated key(s))" 1>&2;  
    return 3
  fi
  # ---
  return 0
}

# ---
# Example:
#  $ declare -A m0=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
#  $ Map_remove m0 m1 "dd" && declare -p m0 m1
#  declare -A m1=([aa]="10" [cc]="30" [bb]="20" )
# ---
function Map_remove {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_remove ORIG DEST KEY";
  [[ $# = 3 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_KEY_filter=$(printf '[[ $1 != "%b" ]]' "$3")
  Map_filter "$1" "$2" "${__bb_KEY_filter}"
}

# ---
# Fonctionne parfaitement mais en faisant 2 copies (Map_filter + Map_copy):
# ---
# Example:
#  $ declare -A m0=([dd]="40" [aa]="10" [cc]="30" [bb]="20" )
#  $ Map_remove_inplace m0 "dd" && declare -p m0
# ---
function Map_remove_inplace {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Map_remove_inplace ORIG KEY";
  [[ $# = 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_TMPNAME
  # Ex: declare tmpName_4718 && TMPNAME=tmpName_4718
  eval $(Declare_fresh_name __bb_TMPNAME tmpName)
  declare -A "${__bb_TMPNAME}" # local map
  # ---
  Map_remove "$1" "${__bb_TMPNAME}" "$2" || return 2
  Map_copy "${__bb_TMPNAME}" "$1"        || return 3
  return 0
}

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Map_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh
Map_*: helpers around Bash's native associative arrays
---  
* Map_make
  Usage:     
      Map_make [-a|--append|--push|--update] NAME [KEY VAL]...
  Description:
      Creates or updates an associative array NAME.
      Without -a: recreates NAME with the given KEY/VAL pairs.
      With -a: appends/updates the given KEY/VAL pairs to NAME.
  Examples:  
      Map_make xys "$@"
      Map_make m "nom de famille" "Dupont" "prénom" "Jean Pierre"
      declare -p m
      Map_make -a m "age" "42" "portable" "06 99 98 97 96"
      declare -p m
      Map_make config host "localhost" port "5432"
---
* Map_push
  Usage:
      Map_push NAME [KEY VAL]...
  Description:
      Alias for "Map_make --append".
      Adds or updates bindings in associative array NAME without
      recreating it.
  Examples:
      Map_push xys "$@"
      Map_make m aa 10
      Map_push m bb 20 cc 30
      # m now contains aa->10, bb->20, cc->30
---  
* Map_set
  Usage:     
      Map_set NAME KEY VAL
  Description:
      Sets NAME[KEY]=VAL in the associative array NAME.
      If KEY already exists, its value is overwritten.
  Examples:  
      Map_make m
      Map_set m "foo" "1"
      Map_set m "bar" "2"
      declare -p m
      Map_set m "foo" "10"   # overwrite
      declare -p m
---
* Map_set_unchecked
Usage:
    Map_set_unchecked NAME KEY VALUE
Description:
    Low-level set operation on associative array NAME:
    directly assigns VALUE to KEY in NAME without any checks.
    Does not verify that NAME is a map, nor that KEY already exists.
    Intended for internal or performance-critical use where callers
    have already validated their inputs.
Examples:
    declare -A m
    Map_set_unchecked m aa 10
    Map_set_unchecked m bb "with spaces"
    # m now contains keys aa and bb with given values      
---  
* Map_get
  Usage:     
      Map_get NAME KEY
  Description:
      Looks up KEY in associative array NAME.
      If KEY does not exist prints nothing, returns 1.
  Examples:  
      Map_make m foo "1" bar ""
      Map_get m foo
      Map_get m bar
      Map_get m baz
---
* Map_get_unchecked
  Usage:
      Map_get_unchecked NAME KEY
  Description:
      Low-level get operation on associative array NAME.
      Returns 0 if KEY exists in NAME (even if its value is the empty string),
      prints the associated value on stdout.
      Returns 1 if KEY does not exist.
      Does not check that NAME is a map and does not print usage messages.
  Examples:
      declare -A m=([aa]="" [bb]="20")
      Map_get_unchecked m aa   # prints "" and returns 0
      Map_get_unchecked m bb   # prints "20" and returns 0
      Map_get_unchecked m cc   # returns 1
---
* Map_get_assign
  Usage:
      Map_get_assign NAME KEY VAR
  Description:
      Looks up KEY in the associative array NAME (as with Map_get) and
      stores the corresponding value into the scalar variable VAR,
      without printing anything on stdout.
      This is roughly equivalent to:
          VAR=$(Map_get NAME KEY)
      but avoids a subshell.
  Returns:
      0 on success,
      non-zero if NAME is not a valid map or KEY is missing.
  Examples:
      Map_make m an ANIMATED sf SELF_SERVICE
      Map_get_assign m an kind
      echo "$kind"
      # ANIMATED
---
* Map_get_assign_unchecked
  Usage:
      Map_get_assign_unchecked NAME KEY VAR
  Description:
      Lighter version of Map_get_assign with fewer checks.
      Directly fetches NAME[KEY] and assigns the value to VAR
      without validating that NAME is a map or that KEY exists.
  Returns:
      0 on success,
      non-zero if the underlying access or assignment fails.
  Examples:
      Map_make m an ANIMATED sf SELF_SERVICE
      Map_get_assign_unchecked m sf label
      echo "$label"
      # SELF_SERVICE
  Notes:
      - Prefer Map_get_assign when you want presence checks and clear
        error messages. Use this unchecked variant only when NAME and
        KEY are known to be valid.
---
* Map_has_key
  Usage:
      Map_has_key [-c|--check-is-map] [-v|--verbose] NAME KEY
  Description:
      Returns 0 if KEY exists in associative array NAME
      (even if its value is the empty string), and 1 otherwise.
      Use the -c/--check-is-map option to first check whether NAME is a map.
      With -v/--verbose, prints an error message on stderr when KEY
      does not exist in NAME.
  Examples:
      declare -A m=([10]="aa" [20]="bb")
      Map_has_key m 10    # returns 0
      Map_has_key m 11    # returns 1
      Map_has_key -v m 11 # prints error on stderr and returns 1
---
* Map_member
  Usage:
      Map_member NAME KEY VALUE
  Description:
      Returns 0 if associative array NAME contains the binding
      KEY -> VALUE (string equality on VALUE).
      Returns 1 otherwise (key missing or value different).
  Examples:
      declare -A m=([aa]="10" [bb]="20")
      Map_member m aa 10   # returns 0
      Map_member m aa 1    # returns 1
      Map_member m cc 10   # returns 1
---
* Map_member_unchecked
  Usage:
      Map_member_unchecked NAME KEY VALUE
  Description:
      Low-level membership test on associative array NAME.
      Returns 0 if NAME contains the binding KEY -> VALUE
      (string equality on VALUE), and 1 otherwise.
      Does not validate that NAME is a map and does not print usage
      messages; intended for internal or performance-critical use where
      callers have already validated their inputs.
  Examples:
      declare -A m=([aa]="10" [bb]="20")
      Map_member_unchecked m aa 10   # returns 0
      Map_member_unchecked m aa 1    # returns 1
      Map_member_unchecked m cc 10   # returns 1
---  
* Map_card (alias: Map_length)
  Usage:     
      Map_card NAME
      Map_length NAME
  Description:
      Returns the number of entries (cardinality) of associative array NAME.
  Examples:  
      Map_make m aa 10 bb 20
      Map_card m
      Map_length m
---
* Map_equal
  Usage:
      Map_equal NAME1 NAME2
  Description:
      Returns 0 if NAME1 and NAME2 have exactly the same keys
      and the same associated values (string equality).
      Returns 1 otherwise.
  Examples:
      declare -A m1=([aa]="10" [bb]="20")
      declare -A m2=([bb]="20" [aa]="10")
      declare -A m3=([aa]="10" [bb]="30")
      Map_equal m1 m2 && echo "m1 == m2"
      Map_equal m1 m3 || echo "m1 != m3"
---
* Map_copy
  Usage:
      Map_copy ORIG DEST
  Description:
      Copies the associative array ORIG into DEST.
      DEST is (re)created and all key/value bindings are duplicated.
  Examples:
      declare -A m=([aa]="10" [bb]="20")
      Map_copy m m2
      # m2 now contains the same bindings as m
---
* Map_combine
  Usage:     
      Map_combine [-a|--append|--push|--update] NAME KEY-ARRAY VAL-ARRAY
  Description:
      Builds or updates the associative array NAME from two indexed arrays
      of keys and values. KEY-ARRAY and VAL-ARRAY must have the same length.
      Without -a: recreates NAME from KEY-ARRAY/VAL-ARRAY.
      With -a: appends/updates entries into NAME.
  Examples:  
      Array_make ks 10 20 30 40
      Array_make vs aa bb cc dd
      Map_combine m ks vs
      declare -p m
      Array_make ks2 10 50
      Array_make vs2 zz yy
      Map_combine -a m ks2 vs2   # 10 is updated to zz, 50 is added
      declare -p m
---  
* Map_split
  Usage:     
      Map_split NAME KEY-ARRAY VAL-ARRAY
  Description:
      Splits associative array NAME into two indexed arrays:
      - KEY-ARRAY contains all keys,
      - VAL-ARRAY contains the corresponding values,
      with matching indices.
      The order of keys is not guaranteed.
  Examples:  
      Map_make m aa 10 bb 20 cc 30
      Map_split m ks vs
      Array_print ks
      Array_print vs
---  
* Map_to_key_array
  Usage:     
      Map_to_key_array NAME KEY-ARRAY
  Description:
      Fills KEY-ARRAY with all keys from associative array NAME.
      Order is not guaranteed.
  Examples:  
      Map_make m aa 10 bb 20 cc 30
      Map_to_key_array m ks
      Array_print ks
---  
* Map_to_array (alias Map_to_val_array)
  Usage:     
      Map_to_array NAME VAL-ARRAY
  Description:
      Fills VAL-ARRAY with all values from associative array NAME.
      Order is not guaranteed.
  Examples:  
      Map_make m aa 10 bb 20 cc 30
      Map_to_array m vs
      Array_print vs
---  
* Map_print
  Usage:     
      Map_print [-k|--kv-sep|--key-value-sep SEP] [-s|--sep|--separator SEP] NAME
  Description:
      Prints each key/value pair of associative array NAME, one per line,
      in the form:
          $key $value
      The iteration order is not guaranteed.
      With -k/--kv-sep/--key-value-sep SEP, the separator between key
      and value is SEP.
      With -s|--sep|--separator SEP, the separator between bindings (lines)
      is SEP instead of '\n' 
  Examples:  
      Map_make m "nom de famille" "Dupont" "prénom" "Jean Pierre"
      Map_make -a m "age" "42" "portable" "06 99 98 97 96"
      Map_print m
---
* Map_import
  Usage:
      Map_import [-k|--kv-sep|--key-value-sep SEP] NAME [FILE]...
  Description:
      Imports bindings into associative array NAME from one or more files,
      or from STDIN if no files are provided.
      Each input line is split into KEY and VALUE and stored as:
          NAME[KEY] = VALUE
      By default, KEY and VALUE are separated by the first whitespace.
      With -k/--kv-sep/--key-value-sep SEP, the separator between key
      and value is SEP.
  Examples:
      Map_import m < <(printf 'aa 10\nbb 20\n')
      Map_print m
      Map_import -k ':' services < /etc/services
---
* Map_capture
  Usage:     
      Map_capture [-k|--key-value-sep SEP] [-t|--tmpfile TMPFILE] NAME COMMAND...
  Description:
      Runs COMMAND with its arguments and captures its standard output
      into the associative array NAME. For each non-empty output line,
      the first field becomes the key and the rest of the line becomes
      the value. If -k/--kv-sep is provided, lines are split on SEP
      instead of on the first whitespace. The function returns the
      exit status of COMMAND, unless a usage error occurs. If -t is
      used, TMPFILE is not removed; otherwise a temporary file is
      created and removed automatically.
  Examples:  
      Map_capture M awk '/81[/]tcp.*/ {print $1,$2}' /etc/services
      declare -p M 
      # declare -A M=([kamanda]="10081/tcp" [tproxy]="8081/tcp" )

      Map_capture TCP awk '$2 ~ /tcp/ {split($2, w, "/"); print $1, w[1];}' /etc/services
      Map_get TCP domain   # 53
      Map_get TCP http     # 80
      Map_get TCP https    # 443      
---
* Map_inverse
  Usage:     
      Map_inverse ORIG DEST
  Description:
      Builds DEST as the inverse of ORIG: for each (key, value) pair in
      ORIG, DEST[value] is set to key. If ORIG contains duplicated
      values, some entries are lost when building DEST; in that case,
      a warning is printed on stderr and the function returns 3.
  Examples:  
      Map_capture TCP awk '$2 ~ /tcp/ {split($2, w, "/"); print $1, w[1];}' /etc/services
      Map_get TCP domain     # 53
      Map_get TCP http       # 80
      Map_get TCP https      # 443

      Map_inverse TCP SRV_OF_PORT
      Map_get SRV_OF_PORT 80   # http
      Map_get SRV_OF_PORT 443  # https
---
* Map_to_json
  Usage:
      Map_to_json [-s|--stringify|--no-parse-scalars] NAME
  Description:
      Prints a JSON object built from associative array NAME, on a single line
      (as with `jq -c`).

      Keys are always serialized as JSON strings.

      By default, each Bash value is treated as a candidate JSON fragment:
        - if the value is valid JSON text, it is emitted as the corresponding JSON value;
        - otherwise it is escaped and emitted as a JSON string.
      Therefore values such as 42, true, null, {"x":1}, [1,2], or
      "already a JSON string" keep their JSON meaning, whereas a plain Bash
      value such as hello becomes the JSON string "hello".

      With -s|--stringify|--no-parse-scalars, this parsing step is disabled and
      every value is serialized as a JSON string.

      The order of keys is not guaranteed.
  Examples:
      Map_make m "nom de famille" "Dupont" "prénom" "Jean Pierre"
      Map_make -a m "age" "42"
      Map_to_json    m            # {"nom de famille":"Dupont","age":42,"prénom":"Jean Pierre"}
      Map_to_json    m | jq -c .  # {"nom de famille":"Dupont","age":42,"prénom":"Jean Pierre"}
      Map_to_json -s m | jq -c .  # {"nom de famille":"Dupont","age":"42","prénom":"Jean Pierre"}

      Map_make n a 42 b true c '{"x":1}' d '[1,2]' e plain
      Map_to_json    n | jq -c .  # {"e":"plain","d":[1,2],  "c":{"x":1},    "b":true,  "a":42}
      Map_to_json -s n | jq -c .  # {"e":"plain","d":"[1,2]","c":"{\"x\":1}","b":"true","a":"42"}
---  
* Map_iter
  Usage:     
      Map_iter NAME (FUNCNAME|BODY...) 
      (BODY is the body command using key $1 and value $2)
  Description:
      Iterates over all key/value pairs of associative array NAME and
      evaluates BODY "$key" "$value" for each pair.
      Returns the number of BODY failures (non-zero exit codes).
      BODY is wrapped into a helper function Map_iter_cmd.
  Examples:  
      Map_make m aa 10 bb 20 cc 30
      # print all pairs:
      Map_iter m 'printf "%s = %s\n" "$1" "$2"'
      # sum all values:
      sum=0
      Map_iter m '(( sum += $2 ))'
      echo "$sum"
---  
* Map_iteri
  Usage:     
      Map_iteri NAME (FUNCNAME|BODY...) 
      (BODY is the body command using iteration index $1, key $2 and value $3)
  Description:
      Iterates over all key/value pairs of associative array NAME and
      evaluates BODY "$i" "$key" "$value" for each pair.
      Returns the number of BODY failures (non-zero exit codes).
      BODY is wrapped into a helper function Map_iteri_cmd.
  Examples:  
      Map_make m aa 10 bb 20 cc 30
      # print all pairs:
      Map_iteri m 'printf "%s: %s = %s\n" "$1" "$2" "$3"'
      # 0: aa = 10
      # 1: cc = 30
      # 2: bb = 20
---
* Map_map
  Usage:
      Map_map ORIG DEST FUNCNAME|BODY...
      (BODY is the body function using key $1 and value $2)
  Description:
      Builds DEST by applying BODY K V to each binding (K,V) of ORIG.
      For each binding, BODY receives key and value and its stdout
      is captured to produce the new value in DEST for the same key.
      Keys are preserved, only values are transformed.
      Returns the number of BODY failures (non-zero exit codes).
  Examples:
      declare -A m=([k1]=10 [k2]=20)
      Map_map m m2 'echo "$2:unit"'   # m2[k1]="10:unit", m2[k2]="20:unit"
---
* Map_find
  Usage:
      Map_find [-q|--quiet] NAME (FUNCNAME|BODY...)
      (BODY is the body predicate using key $1 and value $2)
  Description:
      Searches in associative array NAME for the first binding (K,V)
      such that:
          BODY K V
      succeeds (exit code 0).
      By default, prints "K SEP V" on stdout and returns 0,
      where SEP is the separator chosen with Map_print/Map_import.
      With -q/--quiet, prints nothing and only returns 0/1.
  Examples:
      declare -A m=([aa]="10" [bb]="20" [cc]="30")
      Map_find m '[[ $2 -gt 15 ]]'      # prints first matching pair
      Map_find --quiet m '[[ $2 -gt 15 ]]' && echo "found"
      Map_find m '[[ $2 -gt 100 ]]'     # returns 1      
---
* Map_filter
  Usage:     
      Map_filter ORIG DEST (FUNCNAME|BODY...)
      (BODY is the predicate using key $1 and value $2)
  Description:
      Builds DEST as the filtered version of ORIG.
      For each key/value pair (k,v) of ORIG, BODY "$k" "$v" is evaluated:
        - if BODY returns 0, (k,v) is copied into DEST;
        - otherwise it is skipped.
      DEST is recreated as a new associative array.
  Examples:  
      Map_make m aa 10 bb 20 cc 30 dd 40
      Map_filter m m_ge '[[ $2 -ge 20 ]]'
      Map_filter m m_gt '[[ $2 -gt 20 ]]'
      Map_print m_ge
      Map_print m_gt
---  
* Map_filter_inplace
  Usage:     
      Map_filter_inplace NAME (FUNCNAME|BODY...)
      (BODY is the predicate using key $1 and value $2)
  Description:
      In-place version of Map_filter.
      Replaces NAME with its filtered version, keeping only pairs (k,v)
      such that BODY "$k" "$v" returns 0.
      Internally uses Map_filter followed by a copy back into NAME.
  Examples:  
      Map_make m aa 10 bb 20 cc 30 dd 40
      Map_filter_inplace m '[[ $2 -ge 20 ]]'
      Map_print m
      Map_filter_inplace m '[[ $2 -gt 30 ]]'
      Map_print m
---
* Map_for_all
  Usage:
      Map_for_all NAME (FUNCNAME|BODY...)
      (BODY is the body predicate using key $1 and value $2)
  Description:
      Returns 0 if BODY K V succeeds for all bindings (K,V) in NAME.
      Returns 1 as soon as one binding makes BODY fail.
  Examples:
      declare -A m=([aa]="10" [bb]="20" [cc]="30")
      Map_for_all m '[[ $2 -gt 0 ]]'      # succeeds
      Map_for_all m '[[ $2 -lt 25 ]]'     # fails (on cc)      
---
* Map_exists
  Usage:
      Map_exists NAME (FUNCNAME|BODY...)
      (BODY is the body predicate using key $1 and value $2)
  Description:
      Returns 0 if there exists at least one binding (K,V) in NAME
      such that:
          BODY K V
      succeeds (exit code 0).
      Equivalent to: Map_find --quiet NAME BODY.
  Examples:
      declare -A m=([aa]="10" [bb]="20" [cc]="30")
      Map_exists m '[[ $2 -gt 20 ]]'     # succeeds (key cc)
      Map_exists m '[[ $2 -gt 100 ]]'    # fails
---
* Map_case_do
  Usage:
      Map_case_do [-n|--dry-run|--just-print] NAME KEY
  Description:
      Treats the associative array NAME as a dispatch table from keys to
      shell commands. Looks up KEY in NAME, retrieves the associated
      command string, and executes it.
      The exit status of Map_case_do is the exit status of the executed
      command.
      With -n, --dry-run or --just-print, the command is printed on
      stdout instead of being executed.
  Returns:
      0 if the associated command succeeds (exit code 0),
      non-zero if the associated command fails,
      1 if NAME is not a valid map,
      2 if KEY is not present in NAME.
  Examples:
      Map.make CASES a 'echo AAA' b 'echo BBB' c 'echo CCC' d 'false' e 'true'

      Map_case_do CASES a
      # AAA

      Map_case_do CASES d || echo NO
      # NO

      Map_case_do CASES e && echo YES
      # YES

      # Dry-run: only print the command associated with the key
      Map_case_do --dry-run CASES a
      # echo AAA
  Notes:
      - This function assumes that the values stored in NAME are 
        complete shell command strings.
      - Several aliases are provided for convenience:
          Map_run_action   (alias for Map_case_do)
          Map.run_action   (OCaml-style alias)
---
* Map_merge
  Usage:     
      Map_merge ORIG1 ORIG2 DEST
  Description:
      Merges the associative arrays ORIG1 and ORIG2 into DEST. DEST is
      (re)created and filled with all key/value pairs from ORIG1, then
      all key/value pairs from ORIG2; if a key is present in both
      maps, the value coming from ORIG2 overwrites the one from ORIG1.
      If some keys are duplicated between ORIG1 and ORIG2, a warning
      is printed on stderr and the function returns 4.
  Examples:
      declare -A m1=([aa]="10" [bb]="20")
      declare -A m2=([cc]="30" [dd]="40")
      Map_merge m1 m2 MERGE
      declare -p MERGE
      # declare -A MERGE=([aa]="10" [bb]="20" [cc]="30" [dd]="40")          
---
* Map_union
  Usage:     
      Map_union DEST [ORIG]...
  Description:
      Builds DEST as the union of all the associative arrays ORIG...
      DEST is (re)created and filled with all key/value pairs from the
      first map, then from the second, and so on; if a key appears in
      several maps, the value coming from the last map overrides the
      previous ones. If some keys are duplicated across the input
      maps, a warning is printed on stderr and the function returns 3.
  Examples:  
      declare -A m1=([aa]="10" [bb]="20")
      declare -A m2=([cc]="30" [dd]="40")
      declare -A m3=([ee]="50" [ff]="60")
      Map_union UNION m1 m2 m3
      declare -p UNION
      # declare -A UNION=([aa]="10" [bb]="20" [cc]="30" [dd]="40" [ee]="50" [ff]="60")
---
* Map_remove
  Usage:     
      Map_remove ORIG DEST KEY
  Description:
      Functional removal of a key.
      Builds DEST as a copy of ORIG without the entry whose key is KEY.
      If KEY is not present, DEST is just a copy of ORIG.
      Internally uses Map_filter with a predicate that excludes KEY.
  Examples:  
      Map_make m aa 10 bb 20 cc 30 dd 40
      Map_remove m m_no_cc "cc"
      Map_print m_no_cc
---  
* Map_remove_inplace
  Usage:     
      Map_remove_inplace ORIG KEY
  Description:
      In-place removal of a key from associative array ORIG.
      Replaces ORIG by a copy where the entry with key KEY has been removed.
      Internally uses Map_remove + Map_copy (according to current implementation).
  Examples:  
      Map_make m aa 10 bb 20 cc 30 dd 40
      Map_remove_inplace m "cc"
      Map_print m
EOF
  } 2>&1 | less
}


### ---------------------------------------------
###                   Set  
### ---------------------------------------------

# ---
# Examples:
#  $ Set.make S /etc/f*
#  $ Set.member S /etc/fstab  # returns 0
#  $ Set.member S /etc/FSTAB  # returns 1
#  ---
#  $ Set.make S 1 2 3 3 3 2 2 1 && Set.to_json S
#  ["3","2","1"]
#  ---
#  $ Set.make S "$@"
# ---
function Set_make {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_make [-a|--append] NAME [KEY]...";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_PLUS
  if [[ $1 = "-a" || $1 = "--append" || $1 = "--push" || $1 = "--update" ]]; then __bb_PLUS="+"; shift 1; fi
  # ---
  local __bb_smk_NAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  # Soit indéfinie (=> globale), soit déjà déclarée comme map (qu'elle soit locale ou globale) :
  Declare_is_undefined "${__bb_smk_NAME}" || Declare_is_map -u "${__bb_USAGE}" -v "${__bb_smk_NAME}" || return 2;
  # ---
  # Si la variable est indéfinie, on la considère comme variable globale (en réalité
  # ce n'est pas un choix, on ne peut pas faire autrement) :
  if Declare_is_undefined "${__bb_smk_NAME}"; then
    declare -Ag "${__bb_smk_NAME}=()"
  fi
  # ---
  local -n __Set_make_ref=${__bb_smk_NAME}
  if [[ -z ${__bb_PLUS} ]]; then
    __Set_make_ref=()
  else
    __Set_make_ref+=()
  fi
  # ---
  # Remplissage par Map_set_unchecked NAME KEY VAL :
  local __bb_key
  while (( $# > 0 )); do
    __bb_key="$1"; shift 1 || { echo "${__bb_USAGE}" 1>&2; return 3; }
    Map_set_unchecked __Set_make_ref "${__bb_key}" "1"
  done
  # ---
  return 0  
}

# ---
# Alias for 'Set_make --append':
function Set_push {
  local __bb_USAGE="Usage: Set_push NAME [KEY]...";
  # ---
  Set_make -u "${__bb_USAGE}" -a "$@"
}

# ---
# Examples:
#  $ Set.make S /etc/f*
#  $ Set.member S /etc/fstab  # returns 0
#  $ Set.member S /etc/FSTAB  # returns 1
# ---
function Set_member {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_member NAME KEY";
  [[ $# = 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---  
  local __bb_val
  __bb_val=$(Map_has_key -u "${__bb_USAGE}" --check-is-map "$1" "$2" && Map_get_unchecked "$1" "$2")
  local __bb_CODE=$?
  # ---  
  if [[ ${__bb_CODE} = 0 && "${__bb_val}" = 1 ]]; then
    return 0
  else  
    return 1
  fi  
}

# ---
function Set_member_unchecked {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  # local __bb_USAGE="Usage: Set_member_unchecked NAME KEY";
  [[ $# = 2 ]] || return 2;
  # ---  
  local __bb_val
  __bb_val=$(Map_has_key "$1" "$2" && Map_get_unchecked "$1" "$2")
  local __bb_CODE=$?
  # ---  
  if [[ ${__bb_CODE} = 0 && "${__bb_val}" = 1 ]]; then
    return 0
  else  
    return 1
  fi  
}

# ---
function Set_add {
  local __bb_USAGE="Usage: Set_add NAME KEY";
  # ---
  local __bb_sad_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local      __bb_key="$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  Map_set_unchecked ${__bb_sad_NAME} ${__bb_key} 1
}

# ---
# On suppose ici que toute clef soit associée à 1 !
function Set_card {
  local __bb_USAGE="Usage: Set_card NAME";
  # ---
  local __bb_scd_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  eval "local __bb_LENGTH=\${#${__bb_scd_NAME}[@]}"
  echo "${__bb_LENGTH}"
}

# ---
# Identical to Map_to_key_array
# ---
function Set_to_array {
  # ---
  local __bb_USAGE="Usage: Set_to_array NAME ARRAY";
  # ---
  local __bb_sta_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  local __bb_ARR_NAME="$1" && Regexp_is_ident  "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  # __NAME_ref is a nameref to the associative array NAME:
  local -n __bb_sta_NAME_ref="${__bb_sta_NAME}" # declare -n
  # ---
  # Build KEY array from the map:
  Array_make "${__bb_ARR_NAME}" "${!__bb_sta_NAME_ref[@]}" || return 3
  # ---
  return 0  
}

# ---
# Examples:
#  $ declare -a xs=([0]="aaa" [1]="bbb" [2]="ccc")
#  $ Array.to_set xs S && Set.to_json S
#  ["bbb","ccc","aaa"]
# ---
function Array_to_set {
  # ---
  local __bb_USAGE="Usage: Array_to_set NAME SET";
  # ---
  local __bb_ats_NAME="$1" && Declare_is_array -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  local __bb_SET_NAME="$1" && Regexp_is_ident "$1" && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  # __NAME_ref is a nameref to the array NAME:
  local -n __bb_ats_NAME_ref="${__bb_ats_NAME}" # declare -n
  # ---
  Set_make "${__bb_SET_NAME}" "${__bb_ats_NAME_ref[@]}" || return 3
  # ---
  return 0  
}

# ---
# Example:
#   $ echo -e "aaa\naaa\nbbb\nccc" > /tmp/tmpfile.42  # Notice "aaa" twice
#   $ Set.import S /tmp/tmpfile.42 && Set.to_json S
#   ["bbb","ccc","aaa"]
# ---
function Set_import {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_import NAME [FILE]...";
  # ---
  local __bb_sim_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local -a __bb_sim_TMPARRAY
  Array_import __bb_sim_TMPARRAY "$@"
  Array_to_set __bb_sim_TMPARRAY "${__bb_sim_NAME}"
}

# ---
# Example:
#  $ Set_capture S echo -e "hello\nworld" && Set.to_json S
#  ["hello","world"]
#  ---
#  $ Set.capture TCP_PORTS awk '$2 ~ /tcp/ {split($2, w, "/"); print w[1];}' /etc/services
#  $ Set.member TCP_PORTS 80    # return 0
#  $ Set.member TCP_PORTS 8042  # return 1
# ---
function Set_capture {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_capture [-t|--tmpfile TMPFILE] NAME COMMAND..";
  # ---
  local -a __bb_CAPTURE_OPTS=()
  if [[ $1 = "-t" || $1 = "--tmpfile" ]]; then
    __bb_CAPTURE_OPTS=(-t "$2")    
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 5; }
  fi
  # ---
  local __bb_sca_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local -a __bb_sca_TMPARRAY
  local __bb_CODE=0
  Array_capture "${__bb_CAPTURE_OPTS[@]}" __bb_sca_TMPARRAY "$@" || __bb_CODE=$?
  # Capture and make a set even in case of error (i.e. ${__bb_CODE} != 0)
  # (as for Array_capture and Map_capture):
  Array_to_set __bb_sca_TMPARRAY "${__bb_sca_NAME}"
  # ---
  return ${__bb_CODE}  
}

# ---
# Example:
#  $ Set_capture S echo -e "hello\nhello\nworld" && Set.print S
# hello
# world
#  ---
function Set_print {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_print [-s|--sep|--separator SEP] NAME";
  # ---
  local __bb_SEP_OPTION
  if [[ $1 = "-s" || $1 = "--sep" || $1 = "--separator" ]]; then 
    __bb_SEP_OPTION="-s ""$2"; 
    shift 2 || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  fi
  # ---
  local __bb_spr_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local -a __bb_spr_TMPARRAY
  Set_to_array "${__bb_spr_NAME}" __bb_spr_TMPARRAY
  Array_print ${__bb_SEP_OPTION} __bb_spr_TMPARRAY
  # ---
}


# ---
# La représentation json d'un Set est l'array.
# ---
# Example:
#   $ Set.make S /etc/d*.conf && declare -p S
#   declare -A S=([/etc/debconf.conf]="1" [/etc/dhcpcd.conf]="1" [/etc/deluser.conf]="1")
#   $ Set_to_json S | jq .
#   [
#     "/etc/debconf.conf",
#     "/etc/dhcpcd.conf",
#     "/etc/deluser.conf"
#   ]
# ---
function Set_to_json {
  local __bb_USAGE="Usage: Set_to_json [-s|--stringify|--no-parse-scalars] NAME";
  # ---
  local __bb_JSON_VALUES=y
  if [[ $1 = "-s" || $1 = "--stringify" || $1 = "--no-parse-scalars" ]]; then 
    unset __bb_JSON_VALUES; 
    shift 1; 
  fi
  # ---
  local __bb_stj_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local -a __bb_stj_TMPARRAY
  Set_to_array "${__bb_stj_NAME}" __bb_stj_TMPARRAY || return 3
  if [[ -n ${__bb_JSON_VALUES} ]]; then
    Array_to_json __bb_stj_TMPARRAY || return 4
  else
    Array_to_json --stringify __bb_stj_TMPARRAY || return 5
  fi
}

# ---
# Returns the number of errors (may be 0).
# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set_iter S 'printf "%s\n" "$1"'
# ---
function Set_iter {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_iter NAME (FUNCNAME|BODY...)  # BODY is the body command using key \$1";
  # ---
  local __bb_sit_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Set_iter_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_sit_NAME} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_sit_NAME}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do 
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    [[ "${__bb_val}" = 1 ]] || continue  # Note: this line is not in Map_iter
    ${__bb_FNAME} "${__bb_key}" || __bb_CODE=$((__bb_CODE+1));
  done
  # ---
  return ${__bb_CODE}
}

# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set_map S SB 'basename "$1"'
#   $ Set_map S SD 'dirname  "$1"'
#   Set_map: WARNING: the provided mapping appears to be not injective (original card is 3 while resulting card is 1)
#   $ declare -p S SB SD
#   declare -A S=([/etc/debconf.conf]="1" [/etc/dhcpcd.conf]="1" [/etc/deluser.conf]="1" )
#   declare -A SB=([dhcpcd.conf]="1" [deluser.conf]="1" [debconf.conf]="1" )
#   declare -A SD=([/etc]="1" )
# ---
function Set_map {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_map ORIG DEST (FUNCNAME|BODY...)  # BODY is the body function using key \$1 and value \$2";
  # ---
  local __bb_ORIG="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Set_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Set_map_cmd")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local __bb_mktemp_TEMPLATE=/tmp/Set_map.XXXXXX
  local __bb_TMPFILE=$(mktemp ${__bb_mktemp_TEMPLATE}) || return 4
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_ORIG} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len_orig=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef __bb_Y
  local __bb_CODE=0
  for ((__bb_i=0; __bb_i<__bb_len_orig; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    [[ "${__bb_val}" = 1 ]] || continue  # Note: this line is not in Map_map
    String_capture -t "${__bb_TMPFILE}" __bb_Y "${__bb_FNAME}" "${__bb_key}" || __bb_CODE=$((__bb_CODE+1));
    Map_set_unchecked ${__bb_DEST} "${__bb_Y}" 1
  done
  # ---
  rm -f ${__bb_TMPFILE}
  # ---
  eval "local __bb_len_dest=\${#${__bb_DEST}[@]}"
  # ---
  if [[ ${__bb_len_orig} != ${__bb_len_dest} ]]; then
    echo "Set_map: WARNING: the provided mapping appears to be not injective (original card is ${__bb_len_orig} while resulting card is ${__bb_len_dest})" 1>&2;  
  fi
  # ---
  return ${__bb_CODE}
}

# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set_find S '[[ "$1" =~ deb ]]'
#   /etc/debconf.conf
# ---
function Set_find {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_find NAME (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1";
  # ---
  if [[ $1 = "-u" || $1 = "--usage" || $1 = "--set-usage" ]]; then
    __bb_USAGE="$2";
    shift 2 || { echo "Usage: ${FUNCNAME[0]} [-u|--usage STRING] [OTHER-OPTIONS-AND-ARGS].." 1>&2; return 22; }
  fi
  # ---
  local __bb_QUIET
  if [[ $1 = "-q" || $1 = "--quiet" ]]; then __bb_QUIET="y"; shift 1; fi
  # ---
  local __bb_sfi_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Set_find_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # ---
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_sfi_NAME} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_sfi_NAME}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    # ---
    [[ "${__bb_val}" = 1 ]] || continue  # Note: this line is not in Map_find
    # ---
    if ${__bb_FNAME} "${__bb_key}"; then
      [[ -n ${__bb_QUIET} ]] || echo "${__bb_key}";
      return 0;
    fi
    # ---
  done
  # ---
  return 1;
}

# ---
# Just an alias for 'Set_find --quiet'.
# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set.exists S '[[ "$1" =~ deb ]]'  # returns 0 (because of /etc/debconf.conf)
#   $ Set.exists S '[[ "$1" =~ ZZZ ]]'  # returns 1
# ---
function Set_exists {
  # ---
  local __bb_USAGE="Usage: Set_exists NAME (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1";
  # ---
  Set_find -u "${__bb_USAGE}" --quiet "$@"
}

# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set.for_all S '[[ "$1" =~ deb ]]' # returns 1
#   $ Set.for_all S '[[ "$1" =~ etc ]]' # returns 0
# ---
function Set_for_all {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_for_all NAME (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1 and value \$2";
  # ---
  local __bb_sfa_NAME="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Set_for_all_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 2; } 
  # --- 
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_sfa_NAME} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_sfa_NAME}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    # ---
    [[ "${__bb_val}" = 1 ]] || continue  # Note: this line is not in Map_for_all
    # ---
    if ${__bb_FNAME} "${__bb_key}"; then
      continue;
    else  
      return 1;
    fi
    # ---
  done
  # ---
  return 0;
}

#   $ Set.make S1 1 2 3
#   $ Set.make S2 3 2 1
#   $ Set.make S3 3 2 1 0
#   $ Set.equal S1 S2  # returns 0
#   $ Set.equal S1 S3  # returns 1
# ---
function Set_equal {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_equal NAME1 NAME2";
  # ---
  local __bb_seq_NAME1="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1;
  local __bb_seq_NAME2="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2;
  [[ $# = 0 ]] || { echo "${__bb_USAGE}" 1>&2; return 3; }
  # ---
  Set_for_all   "${__bb_seq_NAME1}" 'Set_member_unchecked '"${__bb_seq_NAME2}"' "$1"' && \
    Set_for_all "${__bb_seq_NAME2}" 'Set_member_unchecked '"${__bb_seq_NAME1}"' "$1"'
}

# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set.filter S DEB '[[ "$1" =~ deb ]]' && declare -p S DEB
#   declare -A S=([/etc/debconf.conf]="1" [/etc/dhcpcd.conf]="1" [/etc/deluser.conf]="1" )
#   declare -A DEB=([/etc/debconf.conf]="1" 
# ---
function Set_filter {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_filter ORIG DEST (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1";
  # ---
  local __bb_ORIG="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Set_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  local __bb_BODY="$@"
  local __bb_FNAME=$(Function_fresh_name "Set_filter_pred")
  [[ -n ${__bb_BODY} ]] && Function_def ${__bb_FNAME} "$@" || { echo "${__bb_USAGE}" 1>&2; return 3; } 
  # --- 
  trap "unset ${__bb_FNAME}" RETURN;
  # ---
  local -a __bb_KARRAY __bb_VARRAY
  Map_split ${__bb_ORIG} __bb_KARRAY __bb_VARRAY
  # ---
  eval "local __bb_len=\${#${__bb_ORIG}[@]}"
  local __bb_i __bb_key __bb_val __bb_keyRef __bb_valRef
  # ---
  for ((__bb_i=0; __bb_i<__bb_len; __bb_i++)); do
    __bb_keyRef="__bb_KARRAY[${__bb_i}]"
    __bb_valRef="__bb_VARRAY[${__bb_i}]"
    __bb_key=${!__bb_keyRef}
    __bb_val=${!__bb_valRef}
    # ---
    [[ "${__bb_val}" = 1 ]] || continue  # Note: this line is not in Map_filter
    # ---
    if ${__bb_FNAME} "${__bb_key}"; then
      Map_set_unchecked ${__bb_DEST} "${__bb_key}" 1
    fi
    # ---
  done
  # ---
  return 0;
}

# ---
function Set_copy {
  # { set -x; trap 'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_copy ORIG DEST";
  # ---
  local __bb_SANITIZE
  if [[ $1 = "-s" || $1 = "--sanitize" ]]; then __bb_SANITIZE="y"; shift 1; fi
  # ---
  local __bb_ORIG="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 1; 
  local __bb_DEST="$1" && Set_make       -u "${__bb_USAGE}"    "$1" && shift 1 || return 2;
  # ---
  if [[ $__bb_SANITIZE = y ]]; then
    # Removes bindings to something else than "1":
    Set_filter "${__bb_ORIG}" "${__bb_DEST}" true
  else
    Set_iter ${__bb_ORIG} 'Map_set_unchecked '${__bb_DEST}' "$1" 1'
  fi  
}

# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set.filter_inplace S '[[ "$1" =~ deb ]]' && declare -p S
#   declare -A S=([/etc/debconf.conf]="1" )
# ---
function Set_filter_inplace {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_filter_inplace NAME (FUNCNAME|BODY...)  # BODY is the body predicate using key \$1";
  [[ $# -ge 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---  
  local __bb_sfi_NAME=$1 && shift 1 || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_TMPNAME
  # Ex: declare tmpName_4718 && TMPNAME=tmpName_4718
  eval $(Declare_fresh_name __bb_TMPNAME tmpName)
  declare -A "${__bb_TMPNAME}" # local map
  # ---
  Set_filter "${__bb_sfi_NAME}" "${__bb_TMPNAME}" "$@" || return 3
  Set_copy "${__bb_TMPNAME}" "${__bb_sfi_NAME}"        || return 4
  return 0
}

# ---
# Example:
#   $ Set.make S1 /etc/d*.conf
#   $ Set.make S2 /etc/h*.conf
#   $ Set.union U S1 S2
#   $ echo $(Set.card S1) $(Set.card S2) $(Set.card U)
#   3 2 5
#   $ Set.union U S1 S2 S1
#   Map_union: WARNING: union was not disjoint (3 duplicated key(s))
#   $ Set.union --quiet U S1 S2 S1 && echo $(Set.card U)
#   5 
# ---
function Set_union {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_union DEST [ORIG]...";
  # ---
  local __bb_QUIET
  if [[ $1 = "-q" || $1 = "--quiet" ]]; then __bb_QUIET="y"; shift 1; fi
  # ---
  local __bb_DEST="$1" && Set_make -u "${__bb_USAGE}" "$1" && shift 1 || return 1;
  # ---
  local __bb_len1=0
  local __bb_len2
  local __bb_ORIG2
  # ---
  for __bb_ORIG2 in "$@"; do
    Declare_is_map -u "${__bb_USAGE}" -v "${__bb_ORIG2}" || return 2;
    # ---
    Set_iter ${__bb_ORIG2} 'Map_set_unchecked '${__bb_DEST}' "$1" 1'
    # ---
    __bb_len2=$(Set_card ${__bb_ORIG2})
    let __bb_len1+=__bb_len2
  done  
  # ---
  if [[ -z ${__bb_QUIET} ]]; then
    local  __bb_len_dest=$(Set_card ${__bb_DEST})
    # ---
    if [[ $((__bb_len1)) != ${__bb_len_dest} ]]; then
      echo "Set_union: WARNING: union was not disjoint ($((__bb_len1-__bb_len_dest)) duplicated key(s))" 1>&2;
    fi
  fi
  # ---
  return 0
}

# ---
# Example:
#   $ Set.make A 1 2 3
#   $ Set.make B 2 3 4
#   $ Set.make C 3 4 5
#   $ Set.make D 4 5 6
#   $ Set.intersection I         && Set.to_json I    # []
#   $ Set.intersection I A       && Set.to_json I    # ["3","2","1"]
#   $ Set.intersection I A B     && Set.to_json I    # ["3","2"]
#   $ Set.intersection I A B C   && Set.to_json I    # ["3"]
#   $ Set.intersection I A B C D && Set.to_json I    # []
# ---
function Set_intersection {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_intersection DEST [ORIG]...";
  # ---
  local __bb_DEST="$1" && Set_make -u "${__bb_USAGE}" "$1" && shift 1 || return 1;
  # ---
  [[ $# = 0 ]] && return 0
  # ---
  local __bb_ORIG1="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2;
  Set_copy --sanitize "${__bb_ORIG1}" "${__bb_DEST}" || return 3
  # ---
  [[ $# = 0 ]] && return 0
  # ---
  local __bb_ORIG2
  # ---
  for __bb_ORIG2 in "$@"; do
    Declare_is_map -u "${__bb_USAGE}" -v "${__bb_ORIG2}" || return 4;
    # ---
    Set_filter_inplace "${__bb_DEST}" 'Set_member_unchecked '${__bb_ORIG2}' "$1"' || return 5
    # ---
  done
  # ---
  return 0
}

# ---
# Example:
#   $ Set.make A 1 2 3
#   $ Set.make B 2 3 4
#   $ Set.make C 3 4 5
#   $ Set.make D 4 5 6
#   $ Set.difference X A       && Set.to_json X    # ["3","2","1"]
#   $ Set.difference X A B     && Set.to_json X    # ["1"]
#   $ Set.difference X A C D   && Set.to_json X    # ["2","1"]
#   $ Set.difference X A D     && Set.to_json X    # ["3","2","1"]
# ---
function Set_difference {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_difference DEST ORIG [SET]...";
  # ---
  local __bb_DEST="$1" && Set_make -u "${__bb_USAGE}" "$1" && shift 1 || return 1;
  # ---
  [[ $# = 0 ]] && return 0
  # ---
  local __bb_ORIG1="$1" && Declare_is_map -u "${__bb_USAGE}" -v "$1" && shift 1 || return 2;
  Set_copy --sanitize "${__bb_ORIG1}" "${__bb_DEST}"
  # ---
  [[ $# = 0 ]] && return 0
  # ---
  local __bb_ORIG2
  # ---
  for __bb_ORIG2 in "$@"; do
    Declare_is_map -u "${__bb_USAGE}" -v "${__bb_ORIG2}" || return 3;
    # ---
    Set_filter_inplace "${__bb_DEST}" '! Set_member_unchecked '${__bb_ORIG2}' "$1"'
    # ---
  done  
  # ---
  return 0
}



# ---
# Example:
#   $ Set.make S /etc/d*.conf
#   $ Set.remove S T "/etc/dhcpd.conf" && declare -p T
# ---
function Set_remove {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_remove ORIG DEST KEY";
  [[ $# = 3 ]] || { echo "${__bb_USAGE}" 1>&2; return 2; }
  # ---
  local __bb_KEY_filter=$(printf '[[ $1 != "%b" ]]' "$3")
  Set_filter "$1" "$2" "${__bb_KEY_filter}"
}

# ---
# Fonctionne parfaitement mais en faisant 2 copies (Set_filter + Set_copy):
# ---
function Set_remove_inplace {
  # { set -x; trap  'set +x' RETURN; }
  # ---
  local __bb_USAGE="Usage: Set_remove_inplace ORIG KEY";
  [[ $# = 2 ]] || { echo "${__bb_USAGE}" 1>&2; return 1; }
  # ---
  local __bb_TMPNAME
  # Ex: declare tmpName_4718 && TMPNAME=tmpName_4718
  eval $(Declare_fresh_name __bb_TMPNAME tmpName)
  declare -A "${__bb_TMPNAME}" # local map
  # ---
  Set_remove "$1" "${__bb_TMPNAME}" "$2" || return 2
  Set_copy "${__bb_TMPNAME}" "$1"        || return 3
  return 0
}

# ---
# Initially generated by https://www.perplexity.ai/, then lightly reviewed.
# ---
function Set_help {
  { # less
  cat 1>&2 <<"EOF"
---
Usage: source bashbricks.sh
Set_*: helpers around set structures implemented as associative arrays
---
* Set_make
  Usage:
      Set_make [-a|--append|--push|--update] NAME [KEY]...
  Description:
      Creates or updates a set stored as an associative array NAME where
      each key in the set is mapped to the string "1".
      Without -a: recreates NAME with exactly the given keys.
      With -a/--append/--push/--update: adds the given keys to NAME,
      keeping existing ones.
      NAME may be a previously undeclared variable (created as a global
      associative array) or an existing associative array.
  Examples:
      Set_make S 1 2 3 3 2 1
      declare -p S
      # declare -A S=([1]="1" [2]="1" [3]="1")
      Set_make -a S 4 5
      declare -p S
      # S now contains 1,2,3,4,5
---
* Set_push
  Usage:
      Set_push NAME [KEY]...
  Description:
      Alias for "Set_make --append".
      Adds the given keys to the existing set NAME, without recreating it.
  Examples:
      Set_make S 1 2 3
      Set_push S 3 4 5
      # S now contains 1,2,3,4,5
---
* Set_add
  Usage:
      Set_add NAME KEY
  Description:
      Adds a single KEY to the set NAME.
      Fails if NAME is not a valid associative-array-based set.
      Equivalent to setting NAME[KEY]=1.
  Examples:
      Set_make S 1 2
      Set_add S 3
      # S now contains 1,2,3
---
* Set_member
  Usage:
      Set_member NAME KEY
  Description:
      Tests whether KEY is a member of set NAME.
      Returns 0 if NAME[KEY] exists and is equal to "1".
      Returns 1 otherwise.
      This is the "checked" variant: it validates that NAME is a map and
      produces usage errors when arguments are missing.
  Examples:
      Set_make S /etc/fstab /etc/hosts
      Set_member S /etc/fstab   # returns 0
      Set_member S /etc/FSTAB   # returns 1
---
* Set_member_unchecked
  Usage:
      Set_member_unchecked NAME KEY
  Description:
      Lighter, unchecked membership test.
      Returns 0 if NAME[KEY] exists and equals "1", 1 otherwise.
      Does not validate that NAME is a map and does not print usage
      messages; intended for internal or performance-critical use where
      callers have already validated their inputs.
  Examples:
      declare -A S=([aa]="1" [bb]="1")
      Set_member_unchecked S aa  # returns 0
      Set_member_unchecked S cc  # returns 1
---
* Set_card
  Usage:
      Set_card NAME
  Description:
      Returns the cardinality of the set NAME, that is, the number of
      keys currently present in NAME.
  Examples:
      Set_make S 1 2 3 3 2
      Set_card S     # prints 3
---
* Set_to_array
  Usage:
      Set_to_array NAME ARRAY
  Description:
      Fills the indexed ARRAY with all keys from the set NAME.
      Order is not guaranteed.
      This is essentially the same as Map_to_key_array for sets.
  Examples:
      Set_make S aa bb cc
      Set_to_array S xs
      Array_print xs
---
* Set_to_json
  Usage:
      Set_to_json [-s|--stringify|--no-parse-scalars] NAME
  Description:
      Prints a JSON array built from the elements of set NAME, on a
      single line (as with `jq -c`):
          [elem1,elem2,...]
      By default, each element is first tested as a JSON value:
        - if it is a valid JSON value, it is emitted as-is;
        - otherwise it is escaped and emitted as a JSON string.
      With -s|--stringify|--no-parse-scalars, every set element is serialized 
      as a JSON string.
      The order is not guaranteed.
  Examples:
      Set_make S 3 2 1
      Set_to_json    S            # [3,2,1]
      Set_to_json    S | jq -c .  # [3,2,1]
      Set_to_json -s S | jq -c .  # ["3","2","1"]

      Set_make T 42 true null '{"x":1}' '[1,2]' plain
      Set_to_json    T | jq -c .  # [true,[1,2],42,null,"plain",{"x":1}]
      Set_to_json -s T | jq -c .  # ["true","[1,2]","42","null","plain","{\"x\":1}"]
---
* Array_to_set
  Usage:
      Array_to_set NAME SET
  Description:
      Builds the set SET from the contents of the indexed array NAME.
      Each element of NAME becomes an element of the resulting set SET
      (duplicates are removed by construction).
  Examples:
      Array_make xs aaa bbb ccc aaa
      Array_to_set xs S
      Set_to_json S
      # ["bbb","ccc","aaa"] (order not guaranteed)
---
* Set_import
  Usage:
      Set_import NAME [FILE]...
  Description:
      Imports elements into the set NAME from one or more files, or
      from STDIN if no files are given.
      Each non-empty input line becomes an element of the set.
      Duplicates lines are ignored by construction.
  Examples:
      printf 'aaa\naaa\nbbb\nccc\n' > /tmp/lines.txt
      Set_import S /tmp/lines.txt
      Set_to_json S
      # ["bbb","ccc","aaa"] (order not guaranteed)
---
* Set_capture
  Usage:
      Set_capture [-t|--tmpfile TMPFILE] NAME COMMAND...
  Description:
      Runs COMMAND with its arguments and captures its standard output
      into the set NAME.
      Each non-empty output line becomes an element of the set.
      By default, a temporary file is created and removed automatically.
      With -t/--tmpfile TMPFILE, uses the given TMPFILE and does not
      remove it (for debugging).
      Returns the exit status of COMMAND (unless a usage error occurs).
  Examples:
      Set_capture S echo -e "hello\nworld"
      Set_to_json S
      # ["hello","world"]
      Set_capture TCP_PORTS awk '$2 ~ /tcp/ {split($2,w,"/"); print w[1];}' /etc/services
      Set_member TCP_PORTS 80    # returns 0
      Set_member TCP_PORTS 8042  # returns 1
---
* Set_print
  Usage:
      Set_print [-s|--sep|--separator SEP] NAME
  Description:
      Prints all elements of set NAME using Array_print.
      By default, elements are printed one per line.
      With -s/--sep/--separator SEP, uses SEP as the separator between
      elements instead of '\n'.
      Order is not guaranteed.
  Examples:
      Set_make S 3 2 1
      Set_print S
      Set_print -s ', ' S   # e.g. "3, 2, 1"
---
* Set_iter
  Usage:
      Set_iter NAME (FUNCNAME|BODY...)
      (BODY is the body command using key $1)
  Description:
      Iterates over all elements of the set NAME and evaluates:
          BODY "$key"
      for each key such that NAME[key] == "1".
      Returns the number of BODY failures (non-zero exit codes).
      BODY is wrapped into a helper function Set_iter_cmd.
  Examples:
      Set_make S aa bb cc
      Set_iter S 'printf "%s\n" "$1"'
---
* Set_find
  Usage:
      Set_find [-q|--quiet] NAME (FUNCNAME|BODY...)
      (BODY is the body predicate using key $1)
  Description:
      Searches in the set NAME for the first element K such that:
          BODY K
      succeeds (exit code 0).
      By default, prints K on stdout and returns 0.
      With -q/--quiet, prints nothing and only returns 0/1.
  Examples:
      Set_make S /etc/d*.conf
      Set_find S '[[ "$1" =~ deb ]]'           # prints first matching element
      Set_find --quiet S '[[ "$1" =~ deb ]]' && echo "found"
      Set_find S '[[ "$1" =~ ZZZ ]]'           # returns 1
---
* Set_exists
  Usage:
      Set_exists NAME (FUNCNAME|BODY...)
      (BODY is the body predicate using key $1)
  Description:
      Returns 0 if there exists at least one element K in NAME such that
          BODY K
      succeeds (exit code 0).
      Equivalent to: Set_find --quiet NAME BODY.
  Examples:
      Set_make S /etc/d*.conf
      Set_exists S '[[ "$1" =~ deb ]]'   # returns 0
      Set_exists S '[[ "$1" =~ ZZZ ]]'   # returns 1
---
* Set_for_all
  Usage:
      Set_for_all NAME (FUNCNAME|BODY...)
      (BODY is the body predicate using key $1)
  Description:
      Returns 0 if BODY K succeeds for all elements K in the set NAME.
      Returns 1 as soon as one element makes BODY fail.
  Examples:
      Set_make S /etc/d*.conf
      Set_for_all S '[[ "$1" =~ etc ]]'   # usually returns 0
      Set_for_all S '[[ "$1" =~ deb ]]'   # typically returns 1
---
* Set_map
  Usage:
      Set_map ORIG DEST (FUNCNAME|BODY...)
      (BODY is the body function using key $1)
  Description:
      Builds DEST as the image of ORIG by the mapping given by BODY.
      For each element K in ORIG, BODY K is evaluated and its stdout is
      captured as a new element Y in DEST.
      DEST is (re)created as a set; duplicates in the image are removed
      by construction. If the mapping is not injective (i.e. DEST
      contains fewer elements than ORIG), a warning is printed on stderr.
      The function returns the number of BODY failures.
  Examples:
      Set_make S /etc/d*.conf
      Set_map S SB 'basename "$1"'
      Set_map S SD 'dirname "$1"'
      # SB contains all basenames, SD contains all parent directories.
---
* Set_copy
  Usage:
      Set_copy [--sanitize|-s] ORIG DEST
  Description:
      Copies the set ORIG into DEST.
      DEST is (re)created and all elements of ORIG are duplicated.
      With --sanitize, first removes any binding in ORIG whose value is
      not exactly "1" before copying, thus cleaning up inconsistent
      maps used as sets.
  Examples:
      Set_make S 1 2 3
      Set_copy S T
      # T now contains the same elements as S
      # sanitize example:
      # (if S has some keys mapped to values different from "1")
      Set_copy --sanitize S Clean
---
* Set_equal
  Usage:
      Set_equal NAME1 NAME2
  Description:
      Returns 0 if NAME1 and NAME2 represent exactly the same set of
      keys (all elements of NAME1 are in NAME2 and conversely).
      Returns 1 otherwise.
      Both NAME1 and NAME2 must be valid set-like associative arrays.
  Examples:
      Set_make S1 1 2 3
      Set_make S2 3 2 1
      Set_make S3 3 2 1 0
      Set_equal S1 S2 && echo "S1 == S2"
      Set_equal S1 S3 || echo "S1 != S3"
---
* Set_filter
  Usage:
      Set_filter ORIG DEST (FUNCNAME|BODY...)
      (BODY is the predicate using key $1)
  Description:
      Builds DEST as the filtered version of ORIG.
      For each element K of ORIG, BODY "$K" is evaluated:
        - if BODY returns 0, K is kept in DEST;
        - otherwise it is skipped.
      DEST is recreated as a new set.
  Examples:
      Set_make S /etc/d*.conf
      Set_filter S DEB '[[ "$1" =~ deb ]]'
      declare -p DEB
---
* Set_filter_inplace
  Usage:
      Set_filter_inplace NAME (FUNCNAME|BODY...)
      (BODY is the predicate using key $1)
  Description:
      In-place version of Set_filter.
      Replaces NAME with its filtered version, keeping only elements K
      such that BODY "$K" returns 0.
      Internally uses Set_filter followed by a copy back into NAME.
  Examples:
      Set_make S /etc/d*.conf
      Set_filter_inplace S '[[ "$1" =~ deb ]]'
      declare -p S
---
* Set_union
  Usage:
      Set_union [-q|--quiet] DEST [ORIG]...
  Description:
      Builds DEST as the union of all sets ORIG...
      DEST is (re)created and filled with all elements from the first
      set, then from the second, and so on.
      As sets are implemented as maps to "1", duplicated elements simply
      collapse to a single key. The function still compares the sum of
      input cardinalities to the resulting cardinality; if they differ
      and --quiet is not given, a warning is printed on stderr.
  Examples:
      Set_make S1 1 2 3
      Set_make S2 3 4
      Set_make S3 5
      Set_union U S1 S2 S3
      Set_card U    # prints 5
      Set_union --quiet U S1 S2 S1
---
* Set_intersection
  Usage:
      Set_intersection DEST [ORIG]...
  Description:
      Builds DEST as the intersection of all sets ORIG...
      With no ORIG, DEST is left empty.
      With a single ORIG, DEST is a sanitized copy of ORIG.
      With several sets, DEST starts as ORIG1, then is filtered in place
      to keep only elements that belong to every subsequent set.
  Examples:
      Set_make A 1 2 3
      Set_make B 2 3 4
      Set_make C 3 4 5
      Set_intersection I A B C
      Set_to_json I   # [3]
---
* Set_difference
  Usage:
      Set_difference DEST ORIG [SET]...
  Description:
      Builds DEST as the difference between ORIG and the sets listed
      in SET...
      DEST is initialized as a copy of ORIG, then all elements that
      appear in any of the SET arguments are removed.
      With only ORIG, DEST is just a copy of ORIG.
  Examples:
      Set_make A 1 2 3
      Set_make B 2 3 4
      Set_difference X A B
      Set_to_json X   # [1]
---
* Set_remove
  Usage:
      Set_remove ORIG DEST KEY
  Description:
      Functional removal of a single KEY from the set ORIG.
      Builds DEST as a copy of ORIG without KEY.
      If KEY is not present, DEST is just a copy of ORIG.
      Internally uses Set_filter with a predicate that excludes KEY.
  Examples:
      Set_make S 1 2 3
      Set_remove S T 2
      Set_to_json T   # [3,1] (order not guaranteed)
---
* Set_remove_inplace
  Usage:
      Set_remove_inplace ORIG KEY
  Description:
      In-place removal of KEY from the set ORIG.
      Replaces ORIG by a copy where KEY has been removed, if present.
      Internally uses Set_remove followed by Set_copy.
  Examples:
      Set_make S 1 2 3
      Set_remove_inplace S 2
      Set_to_json S   # [3,1] (order not guaranteed)
EOF
  } 2>&1 | less
}

# Make aliases using the dot character '.' instead of the first underscore '_' 
# for function names starting with a capital letter:
bashbricks_make_dot_aliases
