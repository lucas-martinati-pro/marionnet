# bin/ — index des rôles (une ligne par fichier)

> Généré depuis l'audit du 2026-07-06 (`docs/audit-marionnet-20260706.md`). Rôle seulement —
> le contenu/les signatures se lisent dans le fichier. `?` = rôle incertain non confirmé.
> Un `.ml/.mli` signale un module dont l'**interface documentée** est dans le `.mli` : la lire
> **avant** d'ouvrir le `.ml` (politique `.mli` sélective : cf. `CLAUDE.md`, § Conventions).

## Amorçage & méta
- `version.mli` (+ `version.ml` généré) — version + date de build.
- `marionnet_log.ml` — (pas de `.mli` : `include` d'un foncteur `Log_builder`) instancie `Log_builder` (ocamlbricks) : le module `Log` utilisé partout.
- `configuration.ml/.mli` — lecture en cascade des confs (`/etc/marionnet/marionnet.conf`, `~/.marionnet`, env), API par continuations `?k`.
- `initialization.ml` — (pas de `.mli` : module-pivot, surface = 23 items sur 30 clients) parsing argv, bannière, calcul de tous les chemins (`Initialization.Path.*`), mode examen. Module-pivot importé partout.
- `global_options.ml/.mli` — options runtime mutables sous mutex récursif (debug, keep-all-snapshots…).
- `gettext.ml/.mli` — liaison gettext du binaire (domaine "marionnet", `s_`/`f_`).

## État global & projet
- `state.ml` — `project_paths` (arborescence projet .mar) + `globalState` : LA racine d'état (mainwin, network, treeviews, save/load, startup/shutdown everything).
- `marionnet.ml` — module principal GUI : globalState, application des foncteurs GUI, treeviews, probe Tap_provider (purge des taps orphelins ou dialogue sudoers), splash, checks, signaux, boucle GTK relancée sur exception.
- `motherboard_builder.ml/.mli` — foncteur `Make(S)` : câblage réactif (Cortex) état ↔ sensibilité des widgets. `.mli` injecté par `INCLUDE DEFINITIONS`.
- `icon.ml/.mli` — pixbuf d'icône de fenêtre (variante exam).
- `splash.ml/.mli` — fenêtre splash + texte de bienvenue.

## Composants réseau (user-level + simulation-level + dialogue, un fichier chacun)
- `machine.ml/.mli` — machine virtuelle UML (distribution, mémoire, ports, terminal).
- `router.ml` — routeur (UML + quagga ; config IP port 0, relais telnet).
- `hub.ml` — répéteur Ethernet (vde_switch en mode hub).
- `switch.ml` — commutateur (vde_switch ; édition VLAN via gui_source_editing).
- `cable.ml` — câbles droits/croisés (paires d'endpoints ; suspend/resume = déconnexion).
- `cloud.ml` — segment de réseau inconnu (délais/défauts aléatoires).
- `world_bridge.ml` — pont vers le réseau réel de l'hôte (tap sur bridge préexistant, via Tap_provider).
- `world_gateway.ml` — passerelle NAT vers l'extérieur (slirpvde + dhcp).
- `user_level.ml/.mli` — niveau utilisateur : classes `component`, `node_*`, `cable`, `network` ; sérialisation Xforest.
- `simulation_level.ml/.mli` — niveau processus : classe `process` et descendants (UML, vde_switch, slirpvde, xterm, hublets) ; spawn/kill/suspend/resume. `.mli` injecté par `INCLUDE DEFINITIONS`.

## Treeviews (onglets latéraux persistants ; patron commun : singleton `Stateful_modules.Variable` + `make ~window …`)
- `treeview.ml` — classe générique (colonnes typées, forêt de lignes, marshalling, menus contextuels).
- `treeview_history.ml` — historique des snapshots COW par machine ; `Startup_functions` pour découpler du réseau.
- `treeview_ifconfig.ml` — configuration IP par interface (persistée par projet).
- `treeview_defects.ml` — défauts réseau simulés (pertes, duplications, ber…) par composant/port.
- `treeview_documents.ml` — documents attachés au projet (énoncés de TP…).
- `treeview_row.ml` — la DONNÉE d'un treeview, hors Gtk+ : `Row_item`, `Row` et le codec JSON `Json` (bibliothèque `marionnet_base`, liée par `test/dune`). Pas de `.mli` : `Row_item`+`Row` sont la surface, un `.mli` serait transparent.
- `treeview_counters.ml/.mli` — codec JSON des compteurs d'adresses fraîches du treeview `ifconfig` (`states/ifconfig-counters`).

## Services système & concurrence
- `task_runner.ml/.mli` — file de tâches nommées exécutée par un worker (sérialise les opérations réseau) + `do_in_parallel`.
- `graph.ml/.mli` — graphe orienté impératif générique ; utilisé seulement par task_runner (ordonnancement).
- `message_passing.ml/.mli` — la file bloquante `['a] queue` (mutex + condition), boîte aux lettres de `task_runner`.
- `gMain_actor.ml/.mli` — l'acteur GTK : poste des fonctions GUI au thread GTK (Idle + canaux Milner), garde anti-deadlock.
- `death_monitor.ml/.mli` — registre {pid → callback} par polling : mort inattendue des processus simulés.
- `descendants_monitor.ml/.mli` — thread tueur d'orphelins à la sortie.
- `progress_bar.ml/.mli` — dialogues de progression (pulse) pour opérations longues.
- `cow_files.ml/.mli` — fichiers COW (noms frais, copies sparse) dans states/.
- `disk.ml/.mli` — inventaire des installations (filesystems/kernels/variantes) par « epithets » ; foncteur de vérification avec dialogues.
- `serial.ml/.mli` — dialogue avec `uml_mconsole` (pts d'une console UML, envoi de commandes).
- `x.ml/.mli` — gestion de `$DISPLAY` : parsing, recherche d'un display libre, relais X pour les invités.
- `sketch.ml/.mli` — état du dessin du réseau (image dot, tailles, `dotoptions`, refresh par thunk global).

## Pilotage par script (chantier `marionnet-pilotage-par-script`)
- `control_server.ml/.mli` — serveur de contrôle in-process sur socket unix (`--control-socket`) : requête = ligne texte, réponse = ligne JSON. **1 seul `val` exporté** ; le vocabulaire est publié par la commande `help`, pas par l'OCaml. Client : `useful-scripts/marionnet-ctl`.
- `script_mode.ml/.mli` — les fenêtres que Marionnet ouvre de lui-même sont **capturées puis fermées** ; `in_command` marque le thread qui sert une commande, ce qui évite d'auto-répondre aux questions posées à l'humain.

## Privilèges (taps)
- `tap_provider.ml/.mli` — création/destruction des taps (eth42, bridge) par `sudo -n` + iproute2, règle sudoers scoped, probe `is_usable`, GC `purge_orphan_taps` (remplace le daemon root, supprimé à l'épisode 4 de `marionnet-daemon-elimination`).
- `tap_provider_test.ml` — driver de preuve (`dune test` = mode sec ; `--live`, `--live-bridge=NAME` = preuve contre le noyau).

## Divers
- `compatibility/forest_backward_compatibility.ml` — relit les forêts marshallées ancien format (projets v0).
- `gui.ml` — accès typés aux widgets, **généré par lablgladecc PUIS modifié à la main : ne jamais régénérer** (cf. `bin/gui/CLAUDE.md`).

## Données embarquées
- `images/` (icônes/leds/splash), `filesystems/*.conf` (méta des invités connus), `kernels/` (vide,
  peuplé à l'installation), `share/` (conf par défaut, clé ssh de labo, colorations gtksourceview),
  `scripts/` (test sparse-files, marionnet_telnet.sh), `po/` (catalogues gettext).
