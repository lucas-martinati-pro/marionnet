---
name: marionnet-build
description: Chantier build & release de Marionnet — orchestration make→dune, phase camlp4 préalable, fichiers générés, install final/testing, i18n gettext, RPM. Charger pour toute modification de Makefile*, dune, dune-project, CONFIGME*, META, makers, ou pour builder/installer/releaser.
---

# Build & release Marionnet

## Séquence de build (à respecter, jamais la contourner)

`make` = meta (génère `bin/version.ml`+`bin/meta.ml`) → `make -C lib main-no-build`
(préprocesseurs camlp4 + stubs C compilés à la main dans `lib/_build/`) → hard links vers
`_build/` racine → `dune build`. **`dune build` seul échoue sur un clone frais.**

- Si make dit « make clean required! » : `lib/_build/` est désynchronisé des sources des
  préprocesseurs → `make clean` puis rebuild complet.
- Les règles camlp4 existent EN DOUBLE (Makefile racine, sections « Manual setting », et
  `lib/Makefile`) : toute modification doit être reportée dans les deux.
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

Toute affirmation « le build passe » exige un `make` frais lu jusqu'au bout (code retour 0).
Pour l'install testing : vérifier que `marionnet.native` démarre (`make run` ou binaire du
switch) — pas seulement que dune a linké.

Référence : `docs/ARCHITECTURE.md` § 1, 7, 10.
