# bin/ — cœur applicatif Marionnet

Un seul exécutable (cf. `bin/dune`) : `marionnet.native` (GUI, module principal `marionnet.ml`) —
le démon root `marionnet-daemon.native` a été supprimé (épisode 4 de
`marionnet-daemon-elimination` ; remplaçant : `tap_provider.ml`, sudo -n + iproute2). Partition
des stanzas : les modules sans lablgtk partagés entre la bibliothèque `marionnet_tap`
(`tap_provider`, linkée aussi par le test `tap_provider_test`) et la GUI — `marionnet_log`,
`configuration`, `meta` — vivent dans la bibliothèque `marionnet_base` (`wrapped false`,
ex-`marionnet_common`) ; la GUI prend le reste via `(:standard \ …)`. Toute modification touchant
ces modules partagés doit respecter cette partition (dune interdit un module dans deux stanzas).

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
