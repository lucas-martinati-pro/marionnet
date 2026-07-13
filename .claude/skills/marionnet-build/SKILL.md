---
name: marionnet-build
description: Chantier build & release de Marionnet — make (génère version.ml/meta.ml) puis dune build seul (camlp4 + stubs C construits par dune), fichiers générés, install final/testing, i18n gettext, RPM. Charger pour toute modification de Makefile*, dune, dune-project, CONFIGME*, META, makers, ou pour builder/installer/releaser.
---

# Build & release Marionnet

## Séquence de build

Sur un **clone frais** : `make` une fois (génère `bin/version.ml`+`bin/meta.ml` via les
makers bash), **puis `dune build` seul suffit**. Depuis l'épisode 1 du chantier
`finitions-port-dune` (`88e614b`, 2026-07-13), les préprocesseurs **camlp4** et les stubs C
sont construits **par dune** (`(rule)` dans `lib/dune`, `foreign_stubs`), plus par
`lib/Makefile` : plus de pré-fabrication dans `lib/_build/`, plus de hand-link vers
`_build/` racine, plus de garde-fou « make clean required! ». `make all` = meta + `dune build`.

- `make` reste requis seulement pour `version.ml`/`meta.ml` (et i18n gettext, install, RPM).
- Source unique des règles camlp4 : `lib/dune` (l'ancienne duplication Makefile racine ↔
  `lib/Makefile` a disparu avec l'épisode 1).
- Toolchain gelée : OCaml **4.13.1** (camlp4). Ne monte pas de version sans plan de sortie
  de camlp4 (7 extensions à réécrire, cf. `docs/ARCHITECTURE.md` § 10).

## Fichiers générés / config

- `bin/version.ml`, `bin/meta.ml` : générés par `bin/*.maker.sh` depuis `META` (mini-shell,
  pas un META ocamlfind) et `CONFIGME.choice`. Ne les édite jamais ; modifie les makers.
- `meta.ml.maker.sh` extrait la révision via **bzr** — variante git à écrire (chantier
  « finitions du port dune », cf. mémoire projet).
- `CONFIGME` (final) vs `CONFIGME.testing.sh` : bascule par symlink `CONFIGME.choice` ;
  `meta.ml` en dépend → `make rebuild-for-{final,testing}` après changement.

## Install / i18n / RPM

- Install finale : `make install-final-as-root` (script temporaire sudo préservant l'env
  opam ; ajoute chmod des scripts + install gettext). Testing : dans le switch opam.
- i18n : cibles make exclusivement — `gettext-all-ml-pot-files` (extraction par camlp4),
  `gettext-update-po` (msgmerge, prudence), `gettext-compile-mo`, `gettext-install-mo`.
  Langues : `bin/po/LINGUAS`. `POTFILES.in` est un vestige, ne t'y fie pas.
- RPM : `RPMS/Makefile` (structure rpmbuild) — dépend de cibles du build historique,
  re-valider avant usage sous le port dune.

## Vérification

Toute affirmation « le build passe » exige une commande de build fraîche lue jusqu'au bout
(code retour 0) : `dune build` seul (clone déjà « maké »), ou `make all` (qui enchaîne meta +
`dune build`). Pour l'install testing : vérifier que `marionnet.native` démarre (`make run`
ou binaire du switch) — pas seulement que dune a linké.

Référence : `docs/ARCHITECTURE.md` § 1, 7, 10.
