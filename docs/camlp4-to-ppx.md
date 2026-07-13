# Chantier « camlp4 → ppx » (`marionnet-camlp4-ppx`)

Sortir des extensions **camlp4** de Marionnet pour **lever le gel OCaml 4.13.1** (dernier
compilateur compatible camlp4) et restaurer une toolchain moderne (Merlin / LSP / ocamlformat,
aujourd'hui dégradés sur tous les fichiers préprocessés).

Ce chantier est l'ancienne **« Phase B »** essaimée depuis `finitions-port-dune`
(`docs/finitions-port-dune.md`, COMPLET). Il est **distinct** et, au 2026-07-14, **non entamé**.

## Enjeu

Le gel 4.13.1 est le **dernier verrou** du port dune : tant que `camlp4of` est requis dans le
pipeline de preprocess (`lib/dune`, `bin/dune`), la version d'OCaml ne peut pas monter. En prime,
les `.mli` injectés textuellement par `include_type_definitions_p4` utilisent des chemins
`../../../../` relatifs au bac à sable dune (fragiles). Récit toolchain : `docs/ARCHITECTURE.md`
§10 (Camlp4).

## Inventaire et stratégie de sortie (7 extensions + l'extraction i18n)

Chaque extension a une difficulté de migration très différente ; c'est ce qui fait de ce sujet un
chantier multi-sessions et non une finition. Ordre d'attaque recommandé : les 3 « faciles »
d'abord (dérisque, aucun rewriter à écrire), puis les moyennes, `where_p4` **en dernier** (le crux).

| Extension | Chargement | Rôle | Sortie visée | Difficulté |
|---|---|---|---|---|
| `include_type_definitions_p4` | `#load` par-fichier | injecte le `.mli` dans le `.ml` (`simulation_level`, `motherboard_builder`, `menu_factory`) | dépliage manuel ou `(rule)` dune de concaténation | faible |
| `include_as_string_p4` | `#load` par-fichier | embarque un fichier comme string (`talking.ml`) | `[%blob]` (ppxlib) / `ocaml-crunch` / `(rule)` | faible |
| `IFDEF …` | `lib/camlp4of-flags.cfg` | compilation conditionnelle (`serial`, `gettext`, `ledgrid_manager`, `router`) | **`cppo`** (préprocesseur C-like standard et maintenu) | faible-moyen |
| `log_module_loading_p4` | global (`bin/dune`) | trace le chargement de chaque module | drop pur, ou petit rewriter ppxlib | moyen |
| `raise_p4` | global (`bin/dune`) | localise les `raise` (ajoute la position source) | petit rewriter ppxlib | moyen |
| `option_extract_p4` | global (`bin/dune`) | sucre syntaxique d'extraction d'options | rewriter ppxlib | moyen |
| `where_p4` | `#load` par-fichier | **clause `where`** (style Haskell) sur les 8 composants réseau — le dialogue GTK est rejeté en fin de fichier | rewriter ppxlib **de langage** OU dépliage manuel de chaque `where` | **ÉLEVÉ — le verrou** |
| `gettext_extract_pot_p4` | build-tooling (Makefile) | extraction des chaînes → `bin/po/messages.pot` | à traiter **avec** ce chantier (voir ci-dessous) | à part |

## Frontière avec l'i18n (déjà tranchée)

La **localisation runtime** des `.mo` et leur **compile+install** ont été modernisées séparément
(épisode 6 de `finitions-port-dune`, via **dune-site**, camlp4-free). Il **reste ici** uniquement
`gettext_extract_pot_p4` : l'**extraction POT** (harvest des chaînes depuis les `.ml`), qui est du
build-tooling développeur couplé camlp4. Elle demeure Makefile jusqu'à ce chantier ; sa sortie
(xgettext + extracteur OCaml, ou un ppx d'extraction) se traite avec la migration camlp4.

## Crux : `where_p4`

`where_p4` n'est pas du sucre local mais une **feature de langage** posée sur tout le code des 8
composants (`machine`, `router`, `hub`, `switch`, `cable`, `cloud`, `world_bridge`,
`world_gateway`) : la classe user-level, la classe simulation-level et le dialogue GTK cohabitent
dans un fichier, le dialogue étant « rejeté » en fin via `where`. La migrer = soit écrire un
**vrai rewriter ppxlib** (non trivial : réordonnancement de définitions), soit **déplier
manuellement** chaque `where` dans les 8 fichiers. Dans les deux cas : **impact sémantique large +
revalidation Merlin/LSP** sur l'ensemble de `bin/`. C'est ce qui impose l'ordre (facile → moyen →
`where_p4`) et le caractère multi-sessions.

## Critère de fin

- Plus aucun `camlp4of` dans le pipeline de preprocess (`lib/dune`, `bin/dune`).
- Gel OCaml 4.13.1 **levé** : version montée dans le switch/deps, `dune build` rc=0 sur les 2 exécutables.
- Merlin / LSP / ocamlformat opérationnels sur `bin/` (fin de la dégradation sur fichiers préprocessés).

## Journal d'avancement

- **2026-07-14** — épisode 0 : chantier officialisé (fiche mémoire `marionnet-camlp4-ppx`, cette doc,
  pointeur `CLAUDE.md` § Chantiers longs). Aucun code de migration touché.
