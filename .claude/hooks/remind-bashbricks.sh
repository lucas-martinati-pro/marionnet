#!/bin/bash
# Hook PreToolUse (Write|Edit) — filet de rappel bashbricks.
# Quand on écrit/modifie un fichier BASH de ce dépôt, injecte un rappel « charge le
# skill use-bashbricks ». Ne bloque jamais, ne modifie rien : émet seulement du
# additionalContext (survit au compactage, garanti par le harness).
# Détection Bash : extension .sh, ou shebang bash/sh (Write→content, Edit→fichier existant).
set -u

input=$(cat)
f=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$f" ] || exit 0

is_bash=0
case "$f" in
  *.sh) is_bash=1 ;;
  *)
    content=$(jq -r '.tool_input.content // empty' <<<"$input" 2>/dev/null)
    if [ -n "$content" ]; then
      line1=$(printf '%s\n' "$content" | head -1)
    elif [ -f "$f" ]; then
      line1=$(head -1 "$f" 2>/dev/null)
    else
      line1=""
    fi
    printf '%s' "$line1" | grep -qE '^#!.*(bash|[[:space:]/]sh([[:space:]]|$))' && is_bash=1
    ;;
esac
[ "$is_bash" -eq 1 ] || exit 0

msg="Ce fichier est du Bash. Ce dépôt fournit bashbricks (bashbricks/bashbricks.sh) : charge le skill use-bashbricks (s'il ne l'est pas déjà) et privilégie ses helpers (Array_*, Map_*, Set_*, Json_*, String_*, Regexp_*, Float_*, File_*, Path_*…) au shell ad hoc."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
