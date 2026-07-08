# CLAUDE.md — Marionnet (port dune)

Simulateur de réseaux pédagogique basé sur User-Mode Linux (UML) : les équipements
(machines, routeurs, switchs…) sont de vrais processus Linux/vde reliés entre eux, pilotés
par une GUI GTK. OCaml + lablgtk3, GPL. Auteur : Jean-Vincent Loddo (+ Luca Saiu).
Ce dépôt est le **port dune** du projet historique (bzr/ocamlbuild → git/dune, converti 2026-07).

## Build — piège n°1

**`dune build` seul ÉCHOUE sur un clone frais.** Le build est orchestré par make :
`make` = génère `bin/version.ml`+`bin/meta.ml` → précompile les préprocesseurs **camlp4**
et stubs C dans `lib/_build/` (Makefile de lib/) → `dune build`. Toujours passer par `make`.

- Toolchain **gelée OCaml 4.13.1** (dernier compatible camlp4). Merlin/LSP/ocamlformat dégradés
  sur les fichiers préprocessés (7 extensions camlp4 : voir `docs/ARCHITECTURE.md` § Camlp4).
- Install : `make install-final-as-root` (final) ou variante testing — bascule par le symlink
  `CONFIGME.choice` ; si le choix change : `make rebuild-for-{final,testing}`.
- i18n (POT/PO/MO) et RPM : **100 % Makefile** (cibles `gettext-*`, `RPMS/`), pas dune.

## Cartographie

| Où | Quoi | Détail |
|---|---|---|
| `bin/` | cœur applicatif (44 .ml) : modèle réseau à 2 niveaux + composants + daemon | `bin/CLAUDE.md` |
| `bin/gui/` | complétion GTK (foncteurs `Make(State)`), glade | `bin/gui/CLAUDE.md` |
| `lib/` | **ocamlbricks vendored** (bibliothèque support OCaml, 12 sous-dossiers) | `lib/CLAUDE.md` |
| `bashbricks/` | **bashbricks vendored** (bibliothèque Bash sourcée, mono-fichier) | `bashbricks/CLAUDE.md` |
| `uml/` | construction des systèmes invités (scripts pupisto, patches noyau, ethghost) | `uml/CLAUDE.md` |
| `doc-src/` | sources de documentation | — |
| `useful-scripts/` | scripts d'exploitation/release (7 versionnés, le reste ignoré) | — |
| `etc/`, `Makefile.d/`, `RPMS/`, `CONFIGME*`, `META` | config hôte, outillage build historique, packaging | `docs/ARCHITECTURE.md` § Build |

## Fichiers générés — ne jamais éditer

- `bin/version.ml`, `bin/meta.ml` — générés par `bin/*.maker.sh` (non versionnés).
- `bin/gui.ml` — cas particulier : **généré par lablgladecc puis modifié à la main**.
  Ne JAMAIS le régénérer (pas de procédure établie) ; l'éditer à la main. Cf. `bin/gui/CLAUDE.md`.

## Conventions transverses

- En tête de chaque .ml : bloc d'alias `module X = Ocamlbricks.X` (pas d'`open`) + en-tête GPL.
- Extensions camlp4 à la demande via `#load` en tête de fichier (`where_p4`,
  `include_type_definitions_p4`…) ; 3 `.mli` sont **injectés dans le .ml** par
  `INCLUDE DEFINITIONS "../../../../..."` (chemins relatifs au bac à sable dune — fragiles).
- **Bash (obligatoire, neuf comme ancien)** : AVANT d'écrire ou de modifier tout code Bash de ce
  dépôt (`.sh`, makers, fragments dans un `dune`/`Makefile`), charger le skill `use-bashbricks` et
  employer ses helpers (`Array_*`, `Map_*`, `Set_*`, `Json_*`, `String_*`…) plutôt que du shell ad
  hoc. La lib est vendored ici (`bashbricks/bashbricks.sh`) ; la sourcer par chemin relatif.
- **Code neuf** : les préférences modernes s'appliquent (`Result`, bash robuste) ; en revanche
  `.mli` **sélectifs** comme l'existant (modules « bibliothèque » oui, composants/écrans non).
- `Obj.magic` (25×, jointures user/simulation level) : dette tolérée, **à réduire à l'occasion**
  quand on touche ces fichiers — pas de campagne dédiée.
- GTK depuis le SEUL thread principal ; tout appel GUI depuis un autre thread passe par
  l'acteur `gMain_actor` (cf. `docs/ARCHITECTURE.md` § Concurrence).

## Pièges globaux

1. Ordre de build make→dune (ci-dessus) ; garde-fou « make clean required! » si `lib/_build/`
   désynchronisé.
2. `bin/main.ml` est un hello-world vestige, lié dans LES DEUX exécutables par
   `(modules :standard)` de `bin/dune` (le daemon embarque toute la GUI) — **à corriger**
   (chantier « finitions du port dune »), ne pas s'en inspirer.
3. `.bzr/` coexiste avec `.git/` (conversion 2026-07) : ne pas y toucher ;
   `bin/meta.ml.maker.sh` extrait encore la révision via bzr (variante git à prévoir).
4. Vestiges apparents (non confirmés par l'auteur) : `bin/gui/gui.xml` (glade-2),
   `bin/gui/*.ml-template`, `uml/startup.old/`, une partie de `Makefile.d/`,
   `bin/po/POTFILES.in` — ne pas les prendre comme référence sans vérifier.
5. Répertoires vides attendus par le build (`bin/kernels/`) non suivis par git.

## Chantiers longs (work-streams)

Reprise : appliquer le skill `chantier-long`.
- **finitions du port dune** : `docs/finitions-port-dune.md` ; mémoire `marionnet-finitions-dune` ;
  `git log --grep="marionnet-finitions-dune"`.
- **noyaux + rootfs** (intégration Dave Appadoo, touche `uml/`) : `docs/kernel-rootfs-refresh.md` ;
  mémoire `marionnet-kernel-rootfs` ; `git log --grep="marionnet-kernel-rootfs"`. **Bloque vwifi.**
- **vwifi** (OCaml, BLOQUÉ par le kernel) : `docs/vwifi-integration.md` ; mémoire `marionnet-vwifi` ;
  `git log --grep="marionnet-vwifi"`. Analyse commune : `docs/analyse-dave-appadoo-20260708.md`.

## Où puiser

- **Récit d'architecture** (build hybride, 2 niveaux, GUI, état, daemon, i18n, uml, ocamlbricks) :
  `docs/ARCHITECTURE.md` — lire la tranche pertinente, pas tout.
- **Rôle d'un fichier** : `CLAUDE-file-overview.md` du dossier (`bin/`, `bin/gui/`).
- **Chantiers** (skills à charger en l'annonçant) : `marionnet-composants`, `marionnet-build`,
  `marionnet-gui`, `marionnet-pupisto` (`.claude/skills/`).
- **Preuve datée** : `docs/audit-marionnet-20260706.md` (rapport d'audit, immuable).
