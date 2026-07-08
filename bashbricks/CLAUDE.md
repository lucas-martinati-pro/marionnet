# bashbricks/ — bibliothèque Bash vendored

Copie locale de **bashbricks** (bibliothèque Bash de l'auteur), à sourcer :
`source "$root"/bashbricks/bashbricks.sh`. Mono-fichier, auto-contenu, aucune compilation.
Fournit des pseudo-modules `Array_*`, `Map_*`, `Set_*`, `Json_*`, `String_*`, `Regexp_*`,
`Float_*`, `File_*`, `Path_*`, `Declare_*`, `Int_*`, `Function_*`, `Future_*`.

## Provenance (vendored)

- Amont : dépôt git `bashbricks` de l'auteur.
- Commit vendored : **80a1a795b9ab09c3101ddecc4bc8a978620eb38c** (2026-07-03).
- Introduit dans Marionnet le 2026-07-08 (copie vendored, cf. ocamlbricks dans `lib/`).

**Rafraîchir** (re-copie explicite, jamais de submodule) : recopier `bashbricks.sh` depuis
l'amont, puis mettre à jour le commit ci-dessus. Ne pas éditer la copie ici — corriger en amont.

## Usage dans Marionnet

- **Disponible pour le code Bash NEUF** de ce dépôt. L'existant (`uml/pupisto.common/toolkit_*.sh`,
  `bin/scripts/`, makers) n'est PAS refondu dessus pour l'instant — ne pas le « migrer » au passage.
- Préférer les helpers `Array_*`/`Map_*`/`Json_*`… à du shell ad hoc quand on écrit un nouveau
  script (cf. skill `use-bashbricks`).
- Intégration : sourçage par chemin relatif suffit pour les scripts **hôte** (build, pupisto).
  Un script **installé** ou **côté invité** qui en dépendrait devra faire embarquer `bashbricks.sh`
  par `dune install` / le tarball invité — sinon la lib manque à l'exécution.

*Note générée le 2026-07-08.*
