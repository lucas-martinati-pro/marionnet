#!/bin/bash
# Hook PreToolUse (Write) — filet de rappel bashbricks, NOUVEAU script seulement.
# Quand on crée un fichier BASH qui n'existe pas encore dans ce dépôt, injecte un rappel
# « charge le skill use-bashbricks ». Un script déjà existant du dépôt n'est PAS concerné
# (on suit son style déjà en place ; le skill ne se charge alors que sur demande explicite).
# Ne bloque jamais, ne modifie rien : émet seulement du additionalContext (survit au
# compactage, garanti par le harness).
# Détection Bash : extension .sh, ou shebang bash/sh dans le contenu écrit.
set -u

input=$(cat)
f=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$f" ] || exit 0

# Ancien script (déjà présent sur disque) : pas de rappel automatique.
[ -e "$f" ] && exit 0

is_bash=0
case "$f" in
  *.sh) is_bash=1 ;;
  *)
    content=$(jq -r '.tool_input.content // empty' <<<"$input" 2>/dev/null)
    line1=$(printf '%s\n' "$content" | head -1)
    printf '%s' "$line1" | grep -qE '^#!.*(bash|[[:space:]/]sh([[:space:]]|$))' && is_bash=1
    ;;
esac
[ "$is_bash" -eq 1 ] || exit 0

msg="Nouveau script Bash. Ce dépôt fournit bashbricks (bashbricks/bashbricks.sh) : charge le skill use-bashbricks (s'il ne l'est pas déjà) et privilégie ses helpers (Array_*, Map_*, Set_*, Json_*, String_*, Regexp_*, Float_*, File_*, Path_*…) au shell ad hoc."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
