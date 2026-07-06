#!/bin/bash
# Hook PostToolUse (Write|Edit) — fraîcheur des index de rôles (couche E).
# Quand un fichier source CATALOGUÉ est modifié, marque l'index de son dossier
# « à revérifier » dans .claude/stale.log. Signale seulement, ne régénère rien.
# Contrat : ne JAMAIS bloquer ni propager d'échec (exit 0 systématique).
set -u

f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$f" ] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
rel="${f#"$root"/}"
[ "$rel" = "$f" ] && exit 0          # fichier hors du dépôt

# Dossiers catalogués (bin/gui avant bin : premier motif gagnant)
case "$rel" in
  bin/gui/*.ml|bin/gui/*.mli) idx="bin/gui" ;;
  bin/*.ml|bin/*.mli)         idx="bin" ;;
  uml/*.sh)                   idx="uml" ;;
  *) exit 0 ;;
esac

log="$root/.claude/stale.log"
grep -q "^STALE: $rel " "$log" 2>/dev/null && exit 0   # déjà marqué
echo "STALE: $rel (index $idx) $(date +%F)" >> "$log" 2>/dev/null
exit 0
