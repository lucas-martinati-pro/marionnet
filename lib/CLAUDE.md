# lib/ — ocamlbricks vendored

Copie locale (revno bzr 560) d'**ocamlbricks**, la bibliothèque de l'auteur
(https://launchpad.net/ocamlbricks), compilée comme bibliothèque dune `ocamlbricks`
(wrappée : accès `Ocamlbricks.Module`). **Ne pas auditer ni refactorer fichier par
fichier** : c'est une dépendance ; les évolutions de fond se font dans le projet amont.

Particularité build : les 7 préprocesseurs camlp4 (`lib/CAMLP4/*_p4`, `GETTEXT/gettext_extract_pot_p4`)
sont construits **par dune**, via 7 `(rule)` de `lib/dune` qui invoquent `ocamlfind ocamlc -pp camlp4of`
et produisent les `.cmi`/`.cmo` que `lib/dune` et `bin/dune` chargent ensuite au *preprocessing*. Ils
sont seulement **exclus des modules de la bibliothèque** (`(modules (:standard \ …))`) : le commentaire
« *Do not compile preprocessor with dune* » de `lib/dune` vise cette exclusion, pas les `(rule)`. Les
3 stubs C (`gettext-c-wrapper`, `waitpid-c-wrapper`, `does-process-exist-c-wrapper`) passent par
`foreign_stubs`. **Conséquence : `dune build` seul suffit** — plus de pré-fabrication dans
`lib/_build/`, plus de hard-link vers `_build/` (chantier `finitions-port-dune`, ép. 1, 2026-07-13).
Depuis `migration-ocaml5` ép. 5 (2026-07-27) ces rules déclarent `-package camlp4,camlp-streams,unix`.

L'écosystème de build historique de lib/ (`Makefile` et sa cible `main-no-build`, `Makefile.local`,
`configure`, `META`, `tests/`) subsiste dans l'arbre mais **n'est plus employé** — ne pas le prendre
pour référence. ⚠️ `docs/ARCHITECTURE.md` § 1 décrit encore l'ancienne chaîne make→dune : périmé.

## Rôle des sous-dossiers

| Sous-dossier | Rôle |
|---|---|
| `BASE/` | briques de base : `log_builder`, `argv` (CLI déclaratif), sugar/misc |
| `STRUCTURES/` | structures & abstractions : `forest`/`xforest`, `cortex` (réactif), `option`, `either`, `future`, `thunk`, `stateful_modules` (singletons), ipv4/6… |
| `EXTRA/` | extensions stdlib (`unixExtra`, `listExtra`, `stringExtra`, `mutexExtra`…) + 2 stubs C |
| `CHANNEL/` | concurrence par messages : canaux à la Milner, hublets, structures thread-safe |
| `CAMLP4/` | les extensions de syntaxe (compilées par les `(rule)` de `lib/dune`) |
| `SHELL/` | interaction système : `shell`, `linux` (/proc, kill descendance), `pts` |
| `WIDGETS/` | aides GTK : wrappers réactifs, environnements de widgets |
| `GETTEXT/` | i18n : `gettext_builder` + stub C, préprocesseur d'extraction POT |
| `DOT/` | génération Graphviz (AST + rendu, intégration GTK) |
| `MARSHAL/` | `oomarshal` : (dé)sérialisation objet (persistance treeviews/sketch) |
| `CORTEX/` | `spinning` (complément de cortex — séparation `?` non élucidée) |
| `CONFIGURATION/` | `configuration_files` : lecture cascadée conf + environnement |

Socle réellement utilisé par `bin/` (par fréquence) : **EXTRA** et **STRUCTURES** massivement
(Option, Forest/Xforest, Cortex, UnixExtra, ListExtra, StringExtra, MutexExtra,
Stateful_modules…), puis WIDGETS, SHELL, MARSHAL, DOT, CHANNEL (via gMain_actor), BASE.

*Index généré depuis l'audit du 2026-07-06 ; § build rectifié le 2026-07-27 (les préprocesseurs
camlp4 sont bâtis par dune depuis `finitions-port-dune` ép. 1).*
