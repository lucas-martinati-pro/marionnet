# bin/ — cœur applicatif Marionnet

Deux exécutables (cf. `bin/dune`) : `marionnet.native` (GUI, module principal `marionnet.ml`) et
`marionnet-daemon.native` (démon root, `marionnet_daemon.ml`). Depuis l'épisode 5 de
`finitions-port-dune` ils sont **séparés** : les modules communs GUI/daemon sans lablgtk
(`marionnet_log`, `daemon_parameters`, `daemon_language`, `configuration`, `meta`) sont dans la
bibliothèque `marionnet_common` (`wrapped false`) ; le daemon ne linke plus lablgtk et la GUI
prend le reste via `(:standard \ …)`. Toute modification touchant un de ces 5 modules communs (ou
ajoutant un module au périmètre du daemon) doit respecter cette partition.

Architecture à deux niveaux : `user_level.ml` (modèle OO du réseau vu par l'utilisateur) /
`simulation_level.ml` (processus Unix réels : UML, vde_switch, slirpvde). Chaque composant
réseau (machine, router, hub, switch, cable, cloud, world_bridge, world_gateway) définit dans
UN fichier sa classe user-level, sa classe simulation-level et son dialogue GTK (rejeté en fin
de fichier par l'extension camlp4 `where_p4`). Récit complet : `docs/ARCHITECTURE.md`.

Préprocesseur camlp4of global sur tout le dossier (`option_extract_p4`, `raise_p4`,
`log_module_loading_p4`) ; extensions supplémentaires par `#load` en tête de fichier.
`version.ml` et `meta.ml` sont **générés** (makers bash) — ne jamais les éditer.

Rôles des fichiers : voir `CLAUDE-file-overview.md`.
Chantier composants : charger le skill `marionnet-composants`.
