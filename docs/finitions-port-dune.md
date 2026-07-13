# Chantier « finitions du port dune » (`marionnet-finitions-dune`)

Purger les vestiges du portage bzr/ocamlbuild → git/dune, qualifiés par l'auteur au
checkpoint de l'audit du 2026-07-06 (`docs/audit-marionnet-20260706.md`, § I).

## Périmètre (4 points)

1. **`bin/main.ml` + `(modules :standard)`** — supprimer le hello-world vestige et re-séparer
   les exécutables : `marionnet-daemon.native` ne doit plus linker la GUI (lablgtk) ni subir
   d'effets de bord au démarrage. Point de départ : le stanza `executable` séparé commenté
   dans `bin/dune`. Critère d'acceptation : les deux binaires buildent par `make` et
   démarrent sans print parasite ; le daemon ne dépend plus de lablgtk3 au link.
2. **`dune-project` / opam** — remplacer les placeholders (`source`, licence SPDX vérifiée
   contre COPYING), versionner `marionnet.opam` (retrait de la ligne du `.gitignore`).
3. **`bin/meta.ml.maker.sh`** — extraire révision/date via git (repli bzr tant que `.bzr`
   est présent) ; tester dans les deux variantes `CONFIGME.choice`.
4. **`CONFIGME`** — corriger le strip `%/lablgtk2` → `%/lablgtk3` (aligné sur la variante
   testing).

Hors périmètre : **sortie** de camlp4 (Phase B, cf. point 5), i18n, vestiges non confirmés
(gui.xml, templates, startup.old, Makefile.d) — décisions séparées.

5. **Nettoyage du hybride make→dune (Phase A) — FAIT (épisode 1)**. Objectif ajouté le
   2026-07-13 (l'auteur a élargi le périmètre : ce point était initialement hors scope).
   `dune build` seul suffit désormais à builder les 2 exécutables ; le Makefile ne pré-fabrique
   plus rien. **Phase B** (remplacer les 7 extensions camlp4 par du ppx, lever le gel 4.13.1)
   reste un chantier distinct, non entamé.

## Phase A — ce qui a été fait (épisode 1, 2026-07-13)

Les préprocesseurs camlp4 et leurs stubs C étaient précompilés à la main par `lib/Makefile`
(cibles `MANUALLY_PRE_MAKE_IN_build`) puis hand-linkés dans `_build/`, ce qui forçait `make`
avant `dune build`. Inspiré de `~/DEVEL/repos/circa` (ocamlbricks + dune « propre ») :

- **`lib/dune`** : 7 `(rule)` compilent les préprocesseurs p4 (`where_p4`, `option_extract_p4`,
  `raise_p4`, `log_module_loading_p4`, `include_type_definitions_p4`, `include_as_string_p4`,
  `gettext_extract_pot_p4`) en `.cmi`/`.cmo` via `camlp4of` (recette uniforme, `progn`).
  `raise_p4` et `gettext_extract_pot_p4` déclarent en dep `CAMLP4/common_tools_for_preprocessors.ml`
  (include textuel). Le preprocess d'ocamlbricks pointe `-I` vers `_build/default/lib/` +
  `(preprocessor_deps include_type_definitions_p4.cmo)`.
- **`bin/dune`** : `-I` vers `_build/default/lib/`, `(preprocessor_deps)` des 6 `.cmo` chargés
  (3 globaux + `where_p4`/`include_type_definitions_p4`/`include_as_string_p4` via `#load`
  par-fichier). Suppression du `-cclib -locamlbricks_stubs` manuel (les `(foreign_stubs …)` de la
  lib linkent leurs stubs automatiquement).
- **`Makefile`** : −161/+4 lignes. Suppression de `main-no-build`, `PERFORM_MANUALLY_PRE_ACTIONS`,
  `MANUALLY_PRE_*`, règles `_build/*.cmo`, règle stubs, `c-modules`, double `_build/` + `cp -lf`.
  `all` = `meta` + `dune build`. Extraction gettext redirigée vers le `.cmo` construit par dune.

**Vérifs (rc=0)** : `dune build` seul depuis clean total → 2 exécutables ; `make clean && make all` ;
`make gettext-messages-pot`. Non testé (inchangé, sudo) : `install-final-as-root` (n'appelle que
`dune install`). Gel OCaml 4.13.1 + camlp4 **conservés** (Phase A ne touche pas la sémantique des sources).

Reliquat make légitime (hors dune) : `version.ml`/`meta.ml` (makers ; leur passage en `(rule)`
dune est entremêlé avec le point 3 « maker git »), deps/switch, install, i18n gettext, RPM.

## Journal d'avancement

- **2026-07-06** — épisode 0 : chantier officialisé (fiche mémoire `marionnet-finitions-dune`,
  cette doc, pointeur CLAUDE.md). Aucun code touché.
- **2026-07-13** — épisode 1 (`88e614b`) : Phase A — `dune build` sans pré-actions make
  (internalisation des préprocesseurs p4 en `(rule)` dune, rewiring `bin/dune`/`lib/dune`,
  dégraissage du Makefile). Points 1–4 du périmètre initial toujours à faire.
