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

Hors périmètre : sortie de camlp4, i18n, vestiges non confirmés (gui.xml, templates,
startup.old, Makefile.d) — décisions séparées.

## Journal d'avancement

- **2026-07-06** — épisode 0 : chantier officialisé (fiche mémoire `marionnet-finitions-dune`,
  cette doc, pointeur CLAUDE.md). Aucun code touché.
