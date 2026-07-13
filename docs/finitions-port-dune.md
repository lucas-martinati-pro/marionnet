# Chantier « finitions du port dune » (`marionnet-finitions-dune`)

Purger les vestiges du portage bzr/ocamlbuild → git/dune, qualifiés par l'auteur au
checkpoint de l'audit du 2026-07-06 (`docs/audit-marionnet-20260706.md`, § I).

## Périmètre (4 points)

1. **`bin/main.ml` + `(modules :standard)` — FAIT (épisode 5, 2026-07-13, `474de94`)**.
   Vestige hello-world supprimé ; exécutables re-séparés via la bibliothèque `marionnet_common`
   (`wrapped false`) portant les 5 modules communs GUI/daemon sans lablgtk (`marionnet_log`,
   `daemon_parameters`, `daemon_language`, `configuration`, `meta` — clôture tracée depuis
   `marionnet_daemon`). Le daemon ne linke plus lablgtk (vérifié `ldd` : 0 dép GTK/GDK, 4,6 Mo
   vs 16,5 Mo) et ne subit plus le print parasite (`strings` : 0×). Critère d'acceptation
   atteint (build des 2 binaires par `dune build`, daemon sans lablgtk3 au link).
2. **`dune-project` / opam — FAIT (épisode 4, 2026-07-13, `f31672f`)**. Placeholder
   `(source (github username/reponame))` → `(source (uri "git+https://git.launchpad.net/marionnet"))`
   (validé : alimente `dev-repo`) ; licence SPDX `GPL-2.0-or-later` (COPYING GPLv2 + en-têtes
   « or any later version ») ; `marionnet.opam` versionné (retrait de sa ligne du `.gitignore`).
   Corrigé au passage : `(tags (topics …))` mal formé → liste de mots-clés propre.
3. **`bin/meta.ml.maker.sh` — FAIT (épisode 2, 2026-07-13)**. Révision/date extraites via git
   (`rev-list --count`, `log`), repli bzr conservé ; dépôt localisé par `git rev-parse
   --show-toplevel` (car dune exécute le maker depuis le build-dir). Élargi au-delà du point
   initial : la génération de `version.ml`/`meta.ml` est passée sous dune (`(rule)` dans
   `bin/dune`, `(universe)`), supprimant le dernier reliquat `make` pour ces modules.
4. **`CONFIGME` — FAIT (épisode 3, 2026-07-13, `09f1a30`)**. Strip `%/lablgtk2` → `%/lablgtk3`
   (aligné sur la variante testing) : la ligne 66 requête déjà `lablgtk3`, donc l'ancien strip ne
   matchait jamais et `libraryprefix` gardait à tort le composant `/lablgtk3`.

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

Reliquat make légitime (hors dune), après l'épisode 2 : deps/switch, install, i18n gettext, RPM.
(`version.ml`/`meta.ml` sont passés en `(rule)` dune à l'épisode 2, cf. point 3.)

## Journal d'avancement

- **2026-07-06** — épisode 0 : chantier officialisé (fiche mémoire `marionnet-finitions-dune`,
  cette doc, pointeur CLAUDE.md). Aucun code touché.
- **2026-07-13** — épisode 1 (`88e614b`) : Phase A — `dune build` sans pré-actions make
  (internalisation des préprocesseurs p4 en `(rule)` dune, rewiring `bin/dune`/`lib/dune`,
  dégraissage du Makefile). Points 1–4 du périmètre initial toujours à faire.
- **2026-07-13** — épisode 2 (`d10a0fd`) : point 3 du périmètre — `bin/meta.ml.maker.sh` passe
  de bzr à git (`rev-list --count`, `log`, repli bzr) ; génération de `version.ml`/`meta.ml`
  internalisée en `(rule)` dune (`bin/dune`, `(universe)`) ; Makefile allégé (cible `meta` +
  règles de génération supprimées). `dune build` seul suffit désormais aussi pour ces modules.
  Interfaces `Meta`/`Version` inchangées → zéro consommateur modifié. Vérifs rc=0 : makers en
  standalone (revision git = 608), `dune build bin/version.ml bin/meta.ml`, `dune build` complet
  (2 exécutables reliés). Points 1, 2, 4 du périmètre toujours à faire.
- **2026-07-13** — épisode 3 (`09f1a30`) : point 4 — `CONFIGME` strip `%/lablgtk2` → `%/lablgtk3`.
  Vérif : simulation shell (`ocamlfind query lablgtk3` → strip donne le lib dir parent) + cohérence
  avec `CONFIGME.testing.sh`.
- **2026-07-13** — épisode 4 (`f31672f`) : point 2 — `dune-project` `(source (uri …launchpad…))` +
  licence SPDX `GPL-2.0-or-later` + `tags` corrigés ; `marionnet.opam` versionné (retrait
  `.gitignore`). Vérif : `dune build marionnet.opam` rc=0, opam régénéré (`dev-repo`/`license`/`tags`
  corrects).
- **2026-07-13** — épisode 5 (`474de94`) : point 1 — suppression `bin/main.ml` + re-séparation des
  exécutables via la bibliothèque `marionnet_common` (`wrapped false`, 5 modules communs sans
  lablgtk). Vérifs rc=0 : `dune build` (2 binaires), `ldd` daemon sans GTK/GDK, `strings` sans
  « Hello, World ». **Périmètre initial (points 1-4) + Phase A : COMPLET.** Reste distinct :
  **Phase B** (sortir de camlp4 → ppx, lever le gel OCaml 4.13.1) = chantier à part, non entamé.
