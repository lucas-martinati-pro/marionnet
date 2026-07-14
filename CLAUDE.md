# CLAUDE.md — Marionnet (port dune)

Simulateur de réseaux pédagogique basé sur User-Mode Linux (UML) : les équipements
(machines, routeurs, switchs…) sont de vrais processus Linux/vde reliés entre eux, pilotés
par une GUI GTK. OCaml + lablgtk3, GPL. Auteur : Jean-Vincent Loddo (+ Luca Saiu).
Ce dépôt est le **port dune** du projet historique (bzr/ocamlbuild → git/dune, converti 2026-07).

## Build — `dune build` seul suffit

**Sur un clone frais, `dune build` seul suffit** — plus aucun `make` préalable requis. Depuis
l'épisode 1 du chantier `finitions-port-dune` (commit `88e614b`, 2026-07-13), les préprocesseurs
**camlp4** et les stubs C sont construits **par dune** (`(rule)` dans `lib/dune`, `foreign_stubs`),
plus par `lib/Makefile` : il n'y a plus de pré-fabrication dans `lib/_build/` ni de hand-link.
Depuis l'épisode 2 (2026-07-13), `bin/version.ml` et `bin/meta.ml` sont eux aussi générés **par
dune** (`(rule)` dans `bin/dune` invoquant les makers bash), plus par le Makefile. `make` ne reste
requis que pour l'**i18n gettext**, l'**install** et le **RPM**.

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

- **Messages de commit : ANGLAIS obligatoire** pour tout le dépôt Marionnet (règle de scope
  projet). Conventional Commits ; rédiger/traduire le message en anglais avant de committer, corps
  compris. Trailer `Co-Authored-By` selon la règle utilisateur (seulement si j'ai produit le contenu).
- En tête de chaque .ml : bloc d'alias `module X = Ocamlbricks.X` (pas d'`open`) + en-tête GPL.
- Extensions camlp4 à la demande via `#load` en tête de fichier (`where_p4`,
  `include_type_definitions_p4`…) ; 3 `.mli` sont **injectés dans le .ml** par
  `INCLUDE DEFINITIONS "../../../../..."` (chemins relatifs au bac à sable dune — fragiles).
- **Bash, nouveau script uniquement** : AVANT d'écrire un **nouveau** script Bash de ce dépôt
  (`.sh`, makers, fragments dans un `dune`/`Makefile`), charger le skill `use-bashbricks` et
  employer ses helpers (`Array_*`, `Map_*`, `Set_*`, `Json_*`, `String_*`…) plutôt que du shell ad
  hoc. La lib est vendored ici (`bashbricks/bashbricks.sh`) ; la sourcer par chemin relatif.
  Pour modifier un script Bash **déjà existant** du dépôt, ne pas charger le skill
  automatiquement — suivre le style déjà en place dans le fichier ; ne le charger que sur
  demande explicite.
- **Code neuf** : les préférences modernes s'appliquent (`Result`, bash robuste) ; en revanche
  `.mli` **sélectifs** comme l'existant (modules « bibliothèque » oui, composants/écrans non).
- `Obj.magic` (25×, jointures user/simulation level) : dette tolérée, **à réduire à l'occasion**
  quand on touche ces fichiers — pas de campagne dédiée.
- GTK depuis le SEUL thread principal ; tout appel GUI depuis un autre thread passe par
  l'acteur `gMain_actor` (cf. `docs/ARCHITECTURE.md` § Concurrence).

## Pièges globaux

1. Build : sur clone frais `dune build` seul suffit (cf. § « Build »). L'ancien ordre make→dune
   obligatoire et le garde-fou « make clean required! » ont disparu avec l'épisode 1 de
   `finitions-port-dune` ; la génération de `version.ml`/`meta.ml` est passée sous dune à l'épisode 2.
2. `bin/dune` sépare désormais les 2 exécutables (épisode 5 de `finitions-port-dune`) : les
   modules communs GUI/daemon sans lablgtk (`marionnet_log`, `daemon_parameters`,
   `daemon_language`, `configuration`, `meta`) vivent dans la bibliothèque `marionnet_common`
   (`wrapped false`) que les deux linkent ; `marionnet-daemon.native` ne linke plus lablgtk
   (vérifié `ldd`). Le vestige `bin/main.ml` (hello-world) a été supprimé. Ne plus s'attendre à
   un `(modules :standard)` unique ni à `main.ml`.
3. `.bzr/` coexiste avec `.git/` (conversion 2026-07) : ne pas y toucher ;
   `bin/meta.ml.maker.sh` extrait la révision via **git** (`rev-list --count`, `log`) depuis
   l'épisode 2, avec repli bzr tant que `.bzr` est présent.
4. Vestiges apparents (non confirmés par l'auteur) : `bin/gui/gui.xml` (glade-2),
   `bin/gui/*.ml-template`, `uml/startup.old/`, une partie de `Makefile.d/`,
   `bin/po/POTFILES.in` — ne pas les prendre comme référence sans vérifier.
5. Répertoires vides attendus par le build (`bin/kernels/`) non suivis par git.

## Chantiers longs (work-streams)

Reprise : appliquer le skill `chantier-long`.
- **finitions du port dune** : `docs/finitions-port-dune.md` ; mémoire `marionnet-finitions-dune` ;
  `git log --grep="marionnet-finitions-dune"`.
- **camlp4 → ppx** (ancienne « Phase B » de finitions ; sortir des 7 extensions camlp4 pour lever le
  gel OCaml 4.13.1 et restaurer Merlin/LSP ; crux = `where_p4`) : `docs/camlp4-to-ppx.md` ; mémoire
  `marionnet-camlp4-ppx` ; `git log --grep="marionnet-camlp4-ppx"`. **NON entamé.**
- **noyaux + rootfs** (intégration Dave Appadoo ; Trixie + UML 6.12 ; touche `uml/` **et** l'OCaml
  via un dispatch de boot compat SysV/systemd) : `docs/kernel-rootfs-refresh.md` ;
  mémoire `marionnet-kernel-rootfs` ; `git log --grep="marionnet-kernel-rootfs"`. **Bloque vwifi.**
- **vwifi** (OCaml, BLOQUÉ par le kernel) : `docs/vwifi-integration.md` ; mémoire `marionnet-vwifi` ;
  `git log --grep="marionnet-vwifi"`. Analyse commune : `docs/analyse-dave-appadoo-20260708.md`.
- **élimination du daemon** (supprimer le service root permanent `marionnet-daemon` ;
  étape 1 = sudo scoped + iproute2, netns optionnel ensuite) : `docs/daemon-elimination-study.md` ;
  mémoire `marionnet-daemon-elimination` ; `git log --grep="marionnet-daemon-elimination"`.
  **ACTIF** : ép. 1 fait — `bin/tap_provider.ml(i)` (sudo -n + iproute2) et sa règle sudoers
  (`bin/scripts/marionnet-sudoers.sh`) existent et sont prouvés, mais **rien ne les appelle
  encore** : le daemon reste en place. Prochain pas = bascule eth42 de `simulation_level.ml`.

## Où puiser

- **Récit d'architecture** (build hybride, 2 niveaux, GUI, état, daemon, i18n, uml, ocamlbricks) :
  `docs/ARCHITECTURE.md` — lire la tranche pertinente, pas tout.
- **Rôle d'un fichier** : `CLAUDE-file-overview.md` du dossier (`bin/`, `bin/gui/`).
- **Chantiers** (skills à charger en l'annonçant) : `marionnet-composants`, `marionnet-build`,
  `marionnet-gui`, `marionnet-pupisto` (`.claude/skills/`).
- **Preuve datée** : `docs/audit-marionnet-20260706.md` (rapport d'audit, immuable).
