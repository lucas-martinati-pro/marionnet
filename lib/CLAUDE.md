# lib/ — ocamlbricks vendored

Copie locale (revno bzr 560) d'**ocamlbricks**, la bibliothèque de l'auteur
(https://launchpad.net/ocamlbricks), compilée comme bibliothèque dune `ocamlbricks`
(wrappée : accès `Ocamlbricks.Module`). **Ne pas auditer ni refactorer fichier par
fichier** : c'est une dépendance ; les évolutions de fond se font dans le projet amont.

Particularité build : `lib/CAMLP4/` (et `GETTEXT/gettext_extract_pot_p4`) sont compilés
**hors dune** par `lib/Makefile` (cible `main-no-build`), AVANT `dune build` — voir
`docs/ARCHITECTURE.md` § Build. Le reste de l'écosystème de build historique de lib/
(Makefile.local, configure, META, tests/) est inutilisé par le port dune.

## Rôle des sous-dossiers

| Sous-dossier | Rôle |
|---|---|
| `BASE/` | briques de base : `log_builder`, `argv` (CLI déclaratif), sugar/misc |
| `STRUCTURES/` | structures & abstractions : `forest`/`xforest`, `cortex` (réactif), `option`, `either`, `future`, `thunk`, `stateful_modules` (singletons), ipv4/6… |
| `EXTRA/` | extensions stdlib (`unixExtra`, `listExtra`, `stringExtra`, `mutexExtra`…) + 2 stubs C |
| `CHANNEL/` | concurrence par messages : canaux à la Milner, hublets, structures thread-safe |
| `CAMLP4/` | les extensions de syntaxe (compilées hors dune) |
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

*Index généré depuis l'audit du 2026-07-06.*
