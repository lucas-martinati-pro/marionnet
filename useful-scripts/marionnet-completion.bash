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

# Bash completion for marionnet-ctl (mrnctl) and mrn-check.
#
#   . /path/to/marionnet-completion.bash      # or drop it in /etc/bash_completion.d/
#
# NOTHING HERE IS A LIST OF COMMANDS. Every verb, every arity, every option name and the two
# closed vocabularies (--kind=, --can=) are read from what the running Marionnet publishes about
# itself — `marionnet-ctl help` — for the third time in this channel's history and for the same
# reason: a second copy of the grammar is the one that drifts (docs/pilotage-par-script.md,
# episodes 4g, 6 and 9). A verb added to Marionnet completes on the day it exists.
#
# Two consequences worth knowing:
#
#   - the *names* it completes (components, ports, disk states) come from the live session, so
#     they are the real ones, not a guess;
#   - with no Marionnet running there is nothing to publish. Set MARIONNET_CTL_GRAMMAR to a
#     snapshot (`marionnet-ctl help > ~/.marionnet-grammar.json`) and verbs and options still
#     complete offline — the names, of course, cannot.
#
# Requires: jq. Without it the completion stays silent rather than guessing.

# --------------------------------------------------------------------------
#                     The vocabulary, fetched once
# --------------------------------------------------------------------------

_mrn_ctl_program() {
  local here
  if [[ -n ${MARIONNET_CTL:-} ]]; then printf '%s' "$MARIONNET_CTL"; return 0; fi
  here="$(dirname -- "${BASH_SOURCE[0]}")"
  if [[ -x "$here/marionnet-ctl" ]]; then printf '%s' "$here/marionnet-ctl"; return 0; fi
  command -v marionnet-ctl 2>/dev/null && return 0
  return 1
}

# One round trip, silent on failure: a completion that prints an error tramples the line the
# user is typing.
_mrn_ask() {  # $@ = the request
  local ctl
  ctl="$(_mrn_ctl_program)" || return 1
  [[ -n ${MARIONNET_CONTROL_SOCKET:-} ]] || return 1
  "$ctl" --socket-timeout=3 "$@" 2>/dev/null
}

# Memoised for the life of the shell, keyed by where it came from: refetching on every TAB would
# make the channel do the work of a cache.
_MRN_GRAMMAR_JSON=""
_MRN_GRAMMAR_KEY=""

_mrn_grammar() {
  local key answer
  key="${MARIONNET_CTL_GRAMMAR:-}|${MARIONNET_CONTROL_SOCKET:-}"
  if [[ $key == "$_MRN_GRAMMAR_KEY" && -n $_MRN_GRAMMAR_JSON ]]; then
    printf '%s' "$_MRN_GRAMMAR_JSON"; return 0
  fi
  if [[ -n ${MARIONNET_CTL_GRAMMAR:-} && -r ${MARIONNET_CTL_GRAMMAR:-} ]]; then
    answer="$(cat -- "$MARIONNET_CTL_GRAMMAR")"
  else
    answer="$(_mrn_ask help)" || return 1
  fi
  [[ $answer == '{"ok":true'* ]] || return 1
  _MRN_GRAMMAR_JSON="$answer"; _MRN_GRAMMAR_KEY="$key"
  printf '%s' "$answer"
}

_mrn_jq() {  # $1 = filter, reads the grammar
  local g; g="$(_mrn_grammar)" || return 1
  jq -r "$1" <<<"$g" 2>/dev/null
}

_mrn_verbs()   { _mrn_jq '.commands[].verb'; }
_mrn_kinds()   { _mrn_jq '.kinds[]?'; }
_mrn_actions() { _mrn_jq '.actions[]?'; }

# The published syntax of one verb — the string every derivation below reads.
_mrn_syntax() { # $1 = verb
  _mrn_jq ".commands[] | select(.verb==\"$1\") | .syntax"
}

# --------------------------------------------------------------------------
#             What the published syntax says, without a table here
# --------------------------------------------------------------------------

# The option names of a verb, taken from its syntax. "--<field>=<value>" is a placeholder, not an
# option name, and is left out; an option that takes a value keeps its '=' so that the caller can
# ask for no trailing space.
_mrn_options_of() {  # $1 = verb
  local syn tok
  syn="$(_mrn_syntax "$1")" || return 1
  for tok in $(grep -o -- '--[a-zA-Z][a-zA-Z0-9-]*=\?' <<<"$syn"); do
    printf '%s\n' "$tok"
  done | sort -u
}

# The positional placeholders of a verb, in order. A placeholder is what stands between < and >,
# and only that: everything else in a published syntax — "[--ports=<n>]", "(--state=...", "|" —
# is an option or a piece of punctuation. Some placeholders hold a space ("<absolute path>",
# "<cow file>"), hence the accumulation rather than one token per word. `defects-set` publishes
# two shapes separated by "  |  "; the first is the one a completion can follow.
_mrn_placeholders_of() {  # $1 = verb
  local syn tok acc="" p
  syn="$(_mrn_syntax "$1")" || return 1
  syn="${syn%%|  *}"          # keep the first shape when a verb publishes two
  syn="${syn#* }"             # drop the verb itself
  for tok in $syn; do
    if [[ -z $acc ]]; then
      [[ $tok == '<'* || $tok == '[<'* ]] || continue
      acc="$tok"
    else
      acc="$acc $tok"
    fi
    if [[ $acc == *'>' || $acc == *'>]' ]]; then
      p="${acc#[}"; p="${p%]}"
      printf '%s\n' "$p"
      acc=""
    fi
  done
}

# --------------------------------------------------------------------------
#                 What only the live session can answer
# --------------------------------------------------------------------------

# Every component of the open project, cables included: `can` is the view that covers them all.
_mrn_components() { _mrn_ask -q '.components[].name' can 2>/dev/null; }
_mrn_nodes()      { _mrn_ask -q '.nodes[].name' ls 2>/dev/null; }

# The ports of a node, by their user-visible names. The defects treeview is the one that receives
# every component, and its second level is the ports.
_mrn_ports_of() { # $1 = node
  _mrn_ask -q '[.rows[0].children[].fields.Name] | .[]' defects "$1" 2>/dev/null
}

# The disk states of a machine are named by their COW file, which the read side already serves.
_mrn_cow_files() {
  _mrn_ask -q '[.. | objects | select(has("fields")) | .fields."File name"?]
               | map(select(. != null)) | .[]' history 2>/dev/null
}

# The writable field names of a treeview, as the server spells them (episode 10 serves them
# beside the headers, so nothing here recomputes the slug rule).
_mrn_slugs_of() { # $1 = treeview verb (ifconfig|defects|history)
  _mrn_ask -q '.slugs[]?' "$1" 2>/dev/null
}

# The settable fields of a component are the keys `get` publishes — the same source `set` writes.
_mrn_fields_of() { # $1 = component
  _mrn_ask -q '.fields | keys[]' get "$1" 2>/dev/null
}

# --------------------------------------------------------------------------
#                            Completion helpers
# --------------------------------------------------------------------------

_mrn_reply() {  # $1 = candidate list (newline or space separated)
  local IFS=$' \t\n'
  # shellcheck disable=SC2207  # compgen output is the intended word split
  COMPREPLY=( $(compgen -W "$1" -- "$_mrn_cur") )
  # A candidate that ends with '=' or ':' is a prefix, not a finished word.
  if [[ ${#COMPREPLY[@]} -eq 1 && ( ${COMPREPLY[0]} == *= || ${COMPREPLY[0]} == *: ) ]]; then
    compopt -o nospace 2>/dev/null
  fi
}

_mrn_reply_files() { compopt -o default 2>/dev/null; COMPREPLY=(); }

# "m1:eth0": the node part completes into "node:", the rest into that node's ports.
_mrn_complete_endpoint() {
  local node ports p out=""
  if [[ $_mrn_cur != *:* ]]; then
    for node in $(_mrn_nodes); do out+="$node: "; done
    _mrn_reply "$out"
    compopt -o nospace 2>/dev/null
    return 0
  fi
  node="${_mrn_cur%%:*}"
  ports="$(_mrn_ports_of "$node")" || return 0
  for p in $ports; do out+="$node:$p "; done
  _mrn_reply "$out"
}

# One placeholder of a published syntax -> what may stand there.
_mrn_complete_placeholder() {  # $1 = placeholder, $2 = verb, $3… = the words already given
  local ph="$1" verb="$2"; shift 2
  case "$ph" in
    *'<node>:<port>'*)          _mrn_complete_endpoint ;;
    '<component>'|'<node>'|'<cable>')
                                _mrn_reply "$(_mrn_components)" ;;
    '<kind>')                   _mrn_reply "$(_mrn_kinds)" ;;
    '<command>')                _mrn_reply "$(_mrn_verbs)" ;;
    '<cow'*)                    _mrn_reply "$(_mrn_cow_files)" ;;
    '<absolute'*|'<path>')      _mrn_reply_files ;;
    '<port>')                   _mrn_reply "$(_mrn_ports_of "${1:-}")" ;;
    '<field>')
      case "$verb" in
        ifconfig-set|defects-set|history-set) _mrn_reply "$(_mrn_slugs_of "${verb%-set}")" ;;
        get|set)                              _mrn_reply "$(_mrn_fields_of "${1:-}")" ;;
        *)                                    COMPREPLY=() ;;
      esac ;;
    '<'*'|'*'>')
      # An enumeration published in the syntax itself: <inward|outward>, <leftward|rightward>.
      local alts="${ph#<}"; alts="${alts%>}"
      _mrn_reply "${alts//|/ }" ;;
    *)                          COMPREPLY=() ;;
  esac
}

# The value of an option, when the syntax names it.
_mrn_complete_option_value() {  # $1 = "--opt=partial", $2 = verb
  local opt="${1%%=*}" partial="${1#*=}" verb="$2" syn alts
  case "$opt" in
    --kind)    _mrn_cur="$partial"; _mrn_reply "$(_mrn_kinds)" ;;
    --can)     _mrn_cur="$partial"; _mrn_reply "$(_mrn_actions)" ;;
    --from|--grammar|--socket|--file|--ctl) _mrn_reply_files ;;
    --state)
      syn="$(_mrn_syntax "$verb")"
      alts="$(grep -o -- '--state=[a-z|]*' <<<"$syn" | head -1)"; alts="${alts#--state=}"
      _mrn_cur="$partial"; _mrn_reply "${alts//|/ }" ;;
    *)         COMPREPLY=() ;;
  esac
  # The word being completed is "--opt=value": give back the whole thing.
  local i
  for i in "${!COMPREPLY[@]}"; do COMPREPLY[i]="$opt=${COMPREPLY[i]}"; done
}

# --------------------------------------------------------------------------
#                          marionnet-ctl / mrnctl
# --------------------------------------------------------------------------

# The client options, and which of them eat the next word. They belong to the client, not to the
# channel, so they are the one list this file does hold — and `marionnet-ctl --help` is where it
# comes from.
_MRN_CTL_OPTS='-s --socket= -q --query= -p --pretty -f --file= --keep-going --socket-timeout= -h --help'
_MRN_CTL_OPTS_WITH_VALUE=' -s --socket -q --query -f --file '

_marionnet_ctl_completion() {
  local i word verb="" verb_index=0 skip=0 pos=0
  local -a given=()
  _mrn_cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()
  command -v jq >/dev/null 2>&1 || return 0

  # Where does the verb start? Same rule as the client's: client options stop at the first token
  # that is not one of them, and that token is the verb.
  for (( i=1; i < COMP_CWORD; i++ )); do
    word="${COMP_WORDS[i]}"
    if (( skip )); then skip=0; continue; fi
    case "$word" in
      -*)
        [[ $_MRN_CTL_OPTS_WITH_VALUE == *" $word "* ]] && skip=1
        continue ;;
      *)
        verb="$word"; verb_index=$i; break ;;
    esac
  done

  # Still before the verb: client options, or the value of one of them.
  if [[ -z $verb ]]; then
    if (( COMP_CWORD > 1 )) &&
       [[ $_MRN_CTL_OPTS_WITH_VALUE == *" ${COMP_WORDS[COMP_CWORD-1]} "* ]]; then
      _mrn_reply_files; return 0
    fi
    case "$_mrn_cur" in
      --*=*) _mrn_complete_option_value "$_mrn_cur" ""; return 0 ;;
      -*)    _mrn_reply "$_MRN_CTL_OPTS"; return 0 ;;
      *)     _mrn_reply "$(_mrn_verbs) $_MRN_CTL_OPTS"; return 0 ;;
    esac
  fi

  # From here the line belongs to the channel.
  case "$_mrn_cur" in
    --*=*) _mrn_complete_option_value "$_mrn_cur" "$verb"; return 0 ;;
    --*)   _mrn_reply "$(_mrn_options_of "$verb")"; return 0 ;;
  esac

  # Which positional argument is being typed, counting only the positional ones.
  for (( i=verb_index+1; i < COMP_CWORD; i++ )); do
    word="${COMP_WORDS[i]}"
    [[ $word == --* && ${#word} -gt 2 ]] && continue
    given+=("$word"); pos=$((pos+1))
  done

  local -a phs=()
  mapfile -t phs < <(_mrn_placeholders_of "$verb")
  if (( pos < ${#phs[@]} )); then
    _mrn_complete_placeholder "${phs[pos]}" "$verb" ${given[@]+"${given[@]}"}
  fi
  return 0
}

# --------------------------------------------------------------------------
#                                mrn-check
# --------------------------------------------------------------------------

_MRN_CHECK_OPTS='-s --socket= -g --grammar= --ctl= -q --quiet -h --help'

_mrn_check_completion() {
  _mrn_cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  case "$prev" in
    -s|--socket|-g|--grammar|--ctl) _mrn_reply_files; return 0 ;;
  esac
  case "$_mrn_cur" in
    --*=*) _mrn_complete_option_value "$_mrn_cur" ""; return 0 ;;
    -*)    _mrn_reply "$_MRN_CHECK_OPTS"; return 0 ;;
  esac
  # A .mrn file, or "-" for standard input.
  _mrn_reply_files
  return 0
}

complete -F _marionnet_ctl_completion marionnet-ctl mrnctl
complete -F _mrn_check_completion mrn-check
