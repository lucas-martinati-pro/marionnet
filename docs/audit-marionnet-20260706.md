# Audit / cartographie — Marionnet (port dune), 2026-07-06

Dépôt : `/home/jean/.shared/DEVEL/repos/MARIONNET-dune-project`
Périmètre : bin/ + bin/gui/ (complet), uml/ (complet), build & config (complet), lib/ (cartographie légère).
Hors périmètre (existence signalée seulement) : `doc-src/` (29 fichiers versionnés, sources de documentation), `useful-scripts/` (7 fichiers versionnés + nombreux non versionnés, scripts d'exploitation/release).

Conventions de doute : **?role** = rôle incertain · **?convention** = violation possible d'une convention · **?intent** = intention de conception non élucidée. Récapitulatif en fin de rapport.

---

## 0. Vue d'ensemble

| Partie | Contenu | Volume |
|---|---|---|
| A. Build & config | dune-project, 3 `dune`, Makefile + lib/Makefile, Makefile.d/, CONFIGME*, META + makers, RPMS/, etc/ | ~15 fichiers actifs + reliquats |
| B. bin/ (cœur) | 44 .ml + 17 .mli, modèle réseau à 2 niveaux + état global + services système | ~20 000 l. |
| C. bin/gui/ | 14 .ml + 4 .mli + gui_glade3.xml, complétion GTK de l'interface | ~4 200 l. |
| D. lib/ | ocamlbricks **vendored** (copie locale, revno 560), 191 fichiers dans 12 sous-dossiers | ~50 000 l. |
| E. uml/ | scripts bash « pupisto » (construction noyaux + filesystems invités), patches noyau, outil C ethghost | 124 fichiers |

**Points d'entrée (exécutables produits)** :
- `marionnet` (public name `marionnet.native`) — l'application GTK, module principal `bin/marionnet.ml` (pas `main.ml` !).
- `marionnet_daemon` (public name `marionnet-daemon.native`) — démon privilégié (root) gérant taps/bridges, module principal `bin/marionnet_daemon.ml`.
- `marionnet_telnet.sh` (script installé dans bin/ à l'installation).

---

## A. Build & configuration — qui fait quoi entre dune et Makefile

### A.1 Architecture du build hybride (l'élucidation demandée)

Le build est **orchestré par make, exécuté par dune**, avec une phase manuelle préalable imposée par **camlp4** : dune ne sait pas (dans ce montage) compiler les préprocesseurs camlp4 avant de s'en servir, donc ils sont compilés à la main par le Makefile de lib/.

Chaîne complète de `make` (cible par défaut `main` → `rebuild` → `clean` + `all`) :

1. `make meta` → génère `bin/version.ml` (via `bin/version.ml.maker.sh` depuis `META`) et `bin/meta.ml` (via `bin/meta.ml.maker.sh` depuis `META` + `CONFIGME.choice`). **Fichiers générés, à ne jamais éditer** (ni versionnés).
2. `make -C lib main-no-build` → cible `manually_pre_actions` + `c-modules` du `lib/Makefile` : copie les sources des préprocesseurs (`lib/CAMLP4/*_p4.ml{,i}`, `lib/GETTEXT/gettext_extract_pot_p4.ml`) et les 3 stubs C dans `lib/_build/`, puis les compile **avec ocamlc + camlp4of directement** (règles make explicites), y compris `libocamlbricks_stubs.a` (via `ocamlmklib`). Garde-fou : si un fichier copié dans `_build/` diffère de sa source, make exige un `make clean` (détection de désynchronisation).
3. Le Makefile racine recopie (hard links) `lib/_build/*` dans `_build/` racine.
4. `dune build` : compile `lib/` (bibliothèque `ocamlbricks`, stanza `library` de `lib/dune`) et `bin/` (stanza `executables` de `bin/dune`), en préprocessant chaque source par `camlp4of` avec les `.cmo` préparés en (2) — d'où les `-I ../../../../lib/_build/` (chemins relatifs depuis le bac à sable `_build/default/...`).

**Conséquence piège** : `dune build` seul sur un clone frais **échoue** ; il faut passer par `make`. L'ordre de build (préprocesseurs avant dune) est le point de fragilité central du port.

**Répartition des responsabilités** :

| Tâche | Outil |
|---|---|
| Compilation OCaml + link + stubs C de lib (stanza `foreign_stubs`) | dune |
| Compilation des préprocesseurs camlp4 + `libocamlbricks_stubs.a` de pré-amorçage | Makefile (lib/) |
| Génération `version.ml` / `meta.ml` | Makefile racine (+ scripts maker bash) |
| Installation binaire + données `share/` | `dune install` (section `install` de `bin/dune`), **enveloppé** par `make install-final-as-root` (script temporaire exécuté via sudo, qui préserve l'env opam, ajoute le chmod des scripts et l'installation gettext) |
| i18n (POT/PO/MO) | **Makefile racine exclusivement** (cibles `gettext-*` : extraction par camlp4 `gettext_extract_pot_p4.cmo`, `msgmerge`, `msgfmt`, install des `.mo`) |
| Dépendances système/opam | Makefile racine (`make dependencies`, switch opam épinglé **4.13.1** — contrainte camlp4) |
| Releases RPM | `RPMS/Makefile` (appelé depuis la racine ; structure rpmbuild + specs) |
| opam file | dune (`generate_opam_files true`) — mais `marionnet.opam` est **git-ignoré** |

### A.2 Fichiers de la partie

- `dune-project` — méta-projet dune (lang 3.7, package marionnet). **?convention** : `(source (github username/reponame))` est un placeholder non rempli ; `(license "GNU-GPL-v2")` n'est pas un identifiant SPDX (`GPL-2.0-or-later` attendu) ; `generate_opam_files true` alors que `marionnet.opam` est ignoré par git — cohérent avec « fichier généré », mais inhabituel (opam-repository attend le fichier versionné). À confirmer si c'est un choix ou un reste de `dune init`.
- `bin/dune` — stanza `executables` (marionnet + marionnet_daemon) avec `(include_subdirs unqualified)` (gui/ et compatibility/ fusionnés dans le même espace de modules), préprocesseur camlp4of global (`option_extract_p4`, `raise_p4`, `log_module_loading_p4` ; **`gettext_extract_pot_p4` commenté** — l'extraction POT est faite hors build par le Makefile — **?intent** : déplacement définitif ou provisoire ?), link avec `-locamlbricks_stubs`, section `install` (share : xml glade, scripts, filesystems/kernels conf, images). `(modules :standard)` : **tous** les modules de bin/ sont liés dans **les deux** exécutables.
- `lib/dune` — stanza `library ocamlbricks` (str unix threads inotify lablgtk3), stubs C (gettext, waitpid, does-process-exist), **exclut** les modules préprocesseurs de la compilation dune (liste `\` dans `(modules ...)`), flags d'env dev désactivant beaucoup de warnings (`-w -27 -67 -3 -6 -16 -32`) — assumé pour du code hérité.
- `test/dune` + `test/marionnet.ml` — stanza test liant ocamlbricks ; le .ml est **vide**. **?role** : simple placeholder du port dune ?
- `Makefile` (racine) — orchestrateur : dépendances apt/opam, meta, pré-actions lib, dune build, run, install final/testing (bascule par symlink `CONFIGME.choice`), cibles gettext, edit. Reproduit aussi (sections « Manual setting ») les règles de compilation des préprocesseurs — **dupliquées** avec `lib/Makefile` (piège de maintenance : deux copies des mêmes règles).
- `lib/Makefile`, `lib/Makefile.local`, `lib/Makefile.d/`, `lib/configure`, `lib/META`, `lib/CONFIGME`… — build system embarqué d'ocamlbricks, même famille que celui de la racine ; seul `main-no-build` est réellement appelé par la racine.
- `CONFIGME` — configuration **shell sourcée** (prefix d'installation, chemins OCaml, variables reprises dans `meta.ml`). Style historique « ./configure à la main ». **?convention** : `libraryprefix=${libraryprefix%/lablgtk2}` strippe un suffixe **lablgtk2** alors que la requête ocamlfind porte sur **lablgtk3** (la variante testing strippe bien `/lablgtk3`) — très probablement un oubli de mise à jour, sans effet si le suffixe ne matche pas, mais incohérent.
- `CONFIGME.testing.sh` — variante « testing » : installe dans le switch opam (`$OPAM_SWITCH_PREFIX`), `set -x` si exécuté. `CONFIGME.choice` (symlink) mémorise le choix courant ; `make rebuild-for-{final,testing}` rebâtit tout si le choix change (car `meta.ml` en dépend).
- `META` — mini fichier shell (name/description/version/requires) source des makers. À ne pas confondre avec un META ocamlfind.
- `bin/version.ml.maker.sh`, `bin/meta.ml.maker.sh` — générateurs bash de `version.ml`/`meta.ml`. **?intent** : `meta.ml.maker.sh` extrait revno/date via **bzr** (`.bzr` encore présent) ; après la conversion git, `revision`/`source_date` deviendront vides (le script warn seulement). Prévoir l'équivalent git ?
- `Makefile.d/` — boîte à outils historique : `configure`, `CONFIGME` (doc), `bzr_date`, `marionnet-toplevel`/`marionnet-utop` (toplevels de debug **basés sur le log ocamlbuild**, donc a priori cassés sous dune), `Makefile.local`/`Makefile.luca` (build ocamlbuild d'origine), `marionnet.odocl` (odoc), scripts po. **?role** : conservé comme référence du build historique ou encore partiellement actif ? `test_with_utop.sh` semble, lui, encore pertinent (référencé par un commentaire dans `treeview_ifconfig.ml`).
- `RPMS/` — specs RPM (common, fs-machines, fs-routers, kernels) + `RPMS/Makefile` de packaging (structure rpmbuild dans `~/tmp/rpm`). Dépend de cibles `READ_META` définies ailleurs (build historique) — probablement à re-valider sous le port dune.
- `etc/marionnet.conf` — configuration hôte par défaut (identique à `bin/share/marionnet.conf` qui, elle, est installée) : variables `MARIONNET_*` sourcées comme du shell ; surchargables par `~/.marionnet` puis par l'environnement.
- `etc/gettext_extract_pot_p4.conf` — config du préprocesseur d'extraction POT.
- `.gitignore` — documente lui-même la transposition bzr→git (2026-07-06) ; ignore `marionnet.opam`, `bin/po/*.mo`, gros artefacts uml/.

### A.3 i18n (résumé du circuit)

1. Extraction : cible make `gettext-all-ml-pot-files` → camlp4 `gettext_extract_pot_p4.cmo` sur les .ml copiés dans `_build/pot/...` → `msgcat` → `bin/po/messages.pot`.
2. Mise à jour : `gettext-update-po` (msgmerge, à lancer « with caution »).
3. Compilation/installation : `gettext-compile-mo` / `gettext-install-mo` (dans `$localeprefix`). Langues actives : `bin/po/LINGUAS` = fr it ar es pt ro zh (+ de/el/ru/sk/tr… présents, et un dossier `obsolete/`).
4. À l'exécution : `bin/gettext.ml` (wrapper de `lib/GETTEXT/gettext_builder` + stub C) expose `s_` et `f_`.

**?convention** : `bin/po/POTFILES.in` référence des fichiers disparus (`../gui/gui_cable.ml`, `gui_dialog_CABLE.ml`, …) — vestige de l'ancienne organisation (les dialogues ont été absorbés dans `machine.ml`, `cable.ml`… via `where_p4`). Fichier mort à purger ou régénérer ?

---

## B. bin/ — le cœur applicatif

### B.1 Architecture en niveaux

Le modèle central est une architecture à **deux niveaux + une couche composants** :

- **user_level** (`user_level.ml/.mli`, 1759+685 l.) — le réseau *tel que l'utilisateur le voit* : classes OO `component`, `node_with_ports_card`, `node_with_defects`, `node_with_ledgrid_and_defects`, `virtual_machine_with_history_and_ifconfig`, `cable`, et la classe `network` agrégeant tout. Sérialisation projet via `Xforest` (forêts XML d'ocamlbricks).
- **simulation_level** (`simulation_level.ml/.mli`, 1861+411 l.) — les *processus Unix* qui simulent : classe virtuelle `process` et descendants (processus UML `linux`, `vde_switch`, `slirpvde`, `xterm`, hublets…), spawn/kill/suspend/resume, redirections.
- **composants** — un module par type d'équipement, chacun définissant *en un seul fichier* la classe user-level, la classe simulation-level et le dialogue GTK d'ajout/édition (module `Dialog_...` rejeté en fin de fichier grâce à l'extension camlp4 `where_p4`) : `machine.ml`, `router.ml`, `hub.ml`, `switch.ml`, `cable.ml`, `cloud.ml`, `world_bridge.ml`, `world_gateway.ml`.

Le passage user-level → simulation-level se fait par des méthodes de fabrique, et les casts remontants utilisent `Obj.magic` (25 occurrences dans 10 fichiers, essentiellement les composants et `treeview.ml`). **?convention** : ces `Obj.magic` sont clairement un choix assumé de contournement du typage des classes (commentaire `Just_for_testing` dans marionnet.ml inclus), mais c'est le point le plus fragile du typage du projet — à confirmer comme « dette connue et volontaire ».

### B.2 Rôle de chaque fichier (bin/, tous les .ml)

**Amorçage & méta**
- `main.ml` (5 l.) — *hello-world de test* (compte des 'c' via `StringExtra`, `cat /etc/fstab`). **?role/?intent** (doute majeur) : avec `(modules :standard)`, ce module est **lié dans les deux exécutables** et ses effets de bord (3 print, dont le contenu de `/etc/fstab`) s'exécutent à chaque démarrage. Reste du port dune (test de liaison ocamlbricks ?) à exclure/supprimer, ou délibéré ?
- `version.mli` (+ `version.ml` **généré**) — version + date de build.
- (`meta.ml` **généré**, non versionné) — constantes d'installation (prefix, localeprefix, revision bzr…).
- `marionnet_log.ml` — instancie `Log_builder` (ocamlbricks) : le module `Log` utilisé partout (`Log.printf`, niveaux, synchronisé pour threads).
- `configuration.ml/.mli` — lecture en cascade des fichiers de conf (`/etc/marionnet/marionnet.conf`, `~/.marionnet`, env) via `Configuration_files` ; API par continuations (`?k`) sur `(string * source) option`.
- `initialization.ml` — parsing argv (module `Argv` d'ocamlbricks), bannière, calcul de **tous les chemins** (`Initialization.Path.*` : filesystems, kernels, images, tmpdir…), mode examen, options de désactivation de warnings. Module-pivot importé par presque tout le reste.
- `global_options.ml` — options runtime mutables protégées par mutex récursif (debug mode, keep-all-snapshots…), via `Stateful_modules`.
- `gettext.ml/.mli` — liaison gettext du binaire (domaine "marionnet", heuristique de localisation du répertoire locale).

**État global & projet**
- `state.ml` — `class project_paths` (arborescence d'un projet .mar dézippé : classtest/hostfs/netmodel/scripts/states/tmp) et `class globalState` (918 l.) : LA racine d'état (mainwin, network, treeviews, save/load projet, startup/shutdown everything, quit asynchrone). Monolithe impératif assumé.
- `marionnet.ml` — **module principal de l'exécutable GUI** : chdir vers marionnet_home, crée `st = new State.globalState`, applique les foncteurs GUI (`Gui_window_MARIONNET.Make`, `Gui_toolbar_COMPONENTS.Make`), construit les 4 treeviews, connecte le daemon (dégradation gracieuse si absent), splash, choix du tmpdir (test sparse-files), vérifie non-root + dépendances (filesystems/kernels par défaut, vde_switch, slirpvde, dot), branche signaux SIGTERM/SIGINT, `at_exit` tueur de descendants, et boucle `GtkThread.main` **relancée sur exception** (résilience de l'UI).
- `motherboard_builder.ml/.mli` — foncteur `Make(S)` : câblage **réactif** (Cortex) entre l'état projet et la sensibilité des widgets (`sensitive_widgets_initializer`) ; le `.mli` est injecté dans le `.ml` par `INCLUDE DEFINITIONS`.
- `icon.ml` — pixbuf d'icône de fenêtre (variante exam).
- `splash.ml` — fenêtre splash + texte de bienvenue (timeout GMain).

**Composants réseau (user-level + simulation-level + dialogue, un fichier chacun)**
- `machine.ml/.mli` — machine virtuelle UML (distribution invitée, mémoire, ports, terminal).
- `router.ml` — routeur (UML + quagga ; config port 0 IP, relais telnet).
- `hub.ml` — répéteur Ethernet (vde_switch en mode hub).
- `switch.ml` — commutateur (vde_switch, dialogue d'édition de la config VLAN via gui_source_editing).
- `cable.ml` — câbles droits/croisés (paires d'endpoints, suspend/resume = déconnexion).
- `cloud.ml` — « nuage » : segment de réseau inconnu (délais/défauts aléatoires).
- `world_bridge.ml` — pont vers le monde réel (bridge hôte `br0`, nécessite le daemon).
- `world_gateway.ml` — passerelle NAT vers l'extérieur (slirpvde + dhcp).
- `user_level.ml/.mli`, `simulation_level.ml/.mli` — cf. B.1.

**Treeviews (onglets latéraux de données)**
- `treeview.ml` (1774 l.) — classe générique de treeview persistant (colonnes typées `Row_item`, forêt de lignes, marshalling fichier, menus contextuels). Commentaire d'auteur : « could be moved to WIDGET/ » (candidat lib/).
- `treeview_history.ml` — historique des états disques (snapshots COW) par machine ; expose `Startup_functions` (Stateful_modules) pour découpler du réseau.
- `treeview_ifconfig.ml` — configuration IP par interface (persistée par projet).
- `treeview_defects.ml` — défauts réseau simulés (pertes, duplications, ber…) par composant/port.
- `treeview_documents.ml` — documents attachés au projet (énoncés de TP…).
- Tous suivent le même patron : `module The_unique_treeview = Stateful_modules.Variable(...)` = **singleton global mutable** + fonction `make ~window ~hbox ...`.

**Services système & concurrence**
- `task_runner.ml/.mli` — file de tâches nommées exécutées par un worker (sérialisation des opérations réseau) + `do_in_parallel` ; `open Graph` + `open Message_passing`.
- `graph.ml` — graphe orienté impératif générique ; **utilisé seulement par task_runner** (ordonnancement par dépendances).
- `message_passing.ml` — files bloquantes + classe `thread_message_passing_queue` (synchronisation transparente).
- `gMain_actor.ml/.mli` — transforme le thread GTK en **acteur** : tout thread client peut lui « poster » des fonctions GUI (via `GMain.Idle.add` + canaux Milner), avec garde anti-deadlock si l'appelant *est* le thread GTK. Pièce maîtresse de la discipline « GTK depuis un seul thread ».
- `death_monitor.ml/.mli` — registre {pid → callback} scruté par polling ; détection de mort inattendue des processus simulés.
- `descendants_monitor.ml/.mli` — thread suivant la descendance du processus principal pour tuer les orphelins à la sortie.
- `progress_bar.ml` — dialogues de barre de progression (pulse) pour opérations longues.
- `cow_files.ml/.mli` — gestion des fichiers COW (noms frais, copies sparse) dans states/.
- `disk.ml/.mli` — inventaire des **installations** (filesystems machine/router, kernels, variantes) par « epithets » (type fantôme `'a epithet`), listes de recherche user/root, `Make_and_check_installations` (foncteur de vérification avec dialogues d'avertissement).
- `serial.ml/.mli` — dialogue avec `uml_mconsole` (récupération du pts d'une console UML, envoi de commandes).
- `x.ml/.mli` — gestion de `$DISPLAY` : parsing host:display.screen, recherche d'un display libre par `xset`, socket relay pour l'X des invités.
- `sketch.ml/.mli` — état du **dessin du réseau** (image dot générée, tailles, options d'affichage `dotoptions`, refresh via thunk global `Refresh_sketch_thunk`).

**Daemon & protocole**
- `marionnet_daemon.ml` — **module principal du démon** : boucle select sur socket Unix, gestion de clients (id séquentiels), ressources par client (multimap), destruction des ressources orphelines après timeout keepalive (120 s), création/destruction effective de taps/bridges (privilèges root).
- `daemon_language.ml` — protocole : AST des requêtes/réponses, messages **taille fixe 128 octets**, parsing avec **validation défensive** (`checked_*` retournant `(request, error_string) Either.t` — seul endroit du code en style « result »), gestion SIGPIPE.
- `daemon_parameters.ml` — constantes du protocole (timeouts, keepalive).
- `daemon_client.ml` — côté client : socket global + mutex récursif, thread de keepalives, `disable_daemon_support` (mode dégradé sans root).

**Divers**
- `compatibility/forest_backward_compatibility.ml` — relit les forêts marshallées à l'ancien format (`Empty | NonEmpty`) et convertit vers `Forest.t` ; utilisé par sketch/user_level/treeview pour ouvrir les vieux projets `v0`.
- `gui.ml` (à la racine de bin/, 422 l.) — classes d'accès aux widgets **générées par lablgladecc depuis `gui_glade3.xml` puis modifiées à la main** (GBuilder, cast explicites). **Piège** : mi-généré mi-manuel — ne pas régénérer aveuglément. **?role** : quelle est la procédure de régénération prévue quand `gui_glade3.xml` change (diff manuel ?).

### B.3 Données embarquées de bin/
- `bin/images/` — icônes des composants (états on/off/pause, 4 tailles), leds, splash, logos. Installées via la section install de `bin/dune`.
- `bin/filesystems/*.conf` — méta-données des filesystems invités connus (versionnés) ; `bin/kernels/` existe mais est **vide et non versionné** (peuplé à l'installation ; le glob dune est vide sans erreur).
- `bin/share/` — marionnet.conf par défaut, clé ssh de laboratoire `id_rsa_marionnet`, colorations gtksourceview (quagga, vde).
- `bin/scripts/` — `can-directory-host-sparse-files.sh` (test tmpdir), `marionnet_telnet.sh` (installé comme exécutable).
- `bin/po/` — catalogues gettext (cf. A.3).

---

## C. bin/gui/ — complétion GTK

Patron générateur : `gui_glade3.xml` (source **de vérité** de l'interface, éditée avec glade : `make edit-gui`) → `bin/gui.ml` (accès typé aux widgets) → modules « gui completion » qui **finissent** l'interface par code. La plupart sont des **foncteurs `Make (State : sig val st : State.globalState end)`** appliqués dans `marionnet.ml` — c'est le mécanisme d'injection de l'état global dans la GUI (à la place de variables globales croisées).

Rôles fichier par fichier :
- `gui_bricks.ml/.mli` (1122 l.) — boîte à outils de construction de dialogues : `form` (tables étiquetées + tooltips), spin/combo/entrées IP, `Dialog.yes_or_cancel_question`, wrappers réactifs (Cortex). Socle de tous les dialogues composants.
- `gui_window_MARIONNET.ml` — complétion de la fenêtre principale (labels, sensibilité, sous-foncteurs, expose `Motherboard`).
- `gui_menubar_MARIONNET.ml` — menus (Projet/Options/…) : callbacks de création/ouverture/sauvegarde de projet, export dot/png, quit (`Created_entry_project_quit.callback` réutilisé par SIGINT).
- `gui_toolbar_COMPONENTS.ml` — palette verticale des composants ; instancie pour chaque composant son menu Add/Properties/Remove/Startup/Stop… en s'appuyant sur les modules composants de bin/.
- `gui_toolbar_COMPONENTS_layouts.ml/.mli` — les **layouts génériques** (foncteurs paramétrés par `Toolbar_entry`, `Add`, `Properties`…) factorisant la construction des menus de composants ; note un workaround lablgtk (`~label:""` obligatoire dans `GMenu.image_menu_item`).
- `gui_toolbar_DOT_TUNING.ml` — barre de réglage du dessin (zoom, nodesep, splines, inversions…), branchée réactivement (Cortex) sur `sketch`.
- `gui_dialog_A_PROPOS.ml` — dialogue « À propos ».
- `gui_dialog_toolkit.ml` — petit foncteur utilitaire (labels/tooltips markup d'un dialogue glade).
- `gui_source_editing.ml` — éditeur GtkSourceView (config vde_switch, zebra…) avec gestion de langages par id/mime.
- `menu_factory.ml/.mli` — fabrique générique de menus (attachés menubar/menu_item/menu), `INCLUDE DEFINITIONS` de son .mli.
- `simple_dialogs.ml` — dialogues messages (info/warning/error/confirm) prêts à l'emploi.
- `talking.ml/.mli` — messages d'aide et d'erreur « parlés » à l'utilisateur (Msg.help_*), + utilitaires (caractères shell spéciaux, test sparse files — embarque `can-directory-host-sparse-files.sh` **par inclusion camlp4** `include_as_string_p4`).
- `ledgrid.ml` — widget custom « grille de LEDs » (dessin, flash/blink par timeouts GMain) + un main de démo commenté/inactif en fin de fichier.
- `ledgrid_manager.ml` — serveur de fenêtres ledgrid piloté par **socket datagramme** depuis les processus simulés (les vde_switch patchés émettent l'activité des ports) ; thread dédié.
- `gui.xml` + `glade-2.0.dtd` — **?role** : interface **glade-2 héritée**, plus référencée nulle part (seul `gui_glade3.xml` l'est) ; code mort apparent conservé pour mémoire ?
- `gui_component-node-{with,without}-state.ml-template` — gabarits pour créer un nouveau composant. **?role** : ils réfèrent un « gui_machine.ml » qui n'existe plus (l'organisation a changé : dialogues dans les modules composants) — encore utilisables tels quels ?
- `bin/gui/Makefile` — une seule cible : `edit-gui` (lance glade).

**Patterns lablgtk observés** : un seul thread GTK (`GtkThread.main`) + acteur `gMain_actor` pour les appels inter-threads ; timeouts/Idle GMain plutôt que threads pour les animations ; casts `GtkWindow.Dialog.cast (builder#get_object ...)` centralisés dans le `gui.ml` généré ; foncteurs plutôt qu'objets pour composer l'interface.

---

## D. lib/ — ocamlbricks vendored (cartographie légère)

Copie locale de la bibliothèque de l'auteur (revno bzr 560 d'ocamlbricks), compilée comme bibliothèque dune `ocamlbricks` avec wrapping (accès `Ocamlbricks.Module`). Rôle d'une ligne par sous-dossier :

| Sous-dossier | Rôle (une ligne) |
|---|---|
| `BASE/` (16) | Briques de base : `log_builder` (journalisation paramétrable), `argv` (parsing CLI déclaratif), sugar/fix/flip/misc, `ocamlbricks_log`, `mrproper`. |
| `STRUCTURES/` (85) | Structures de données et abstractions : `forest`/`xforest` (forêts + XML), `cortex`/`cortex_lib` (variables **réactives** protégées), `option`, `either`, `future`, `egg`, `thunk`, `stateful_modules` (singletons d'état), ipv4/ipv6, network, hashmap/hashmmap, cache, memo, counter, lazy_perishable… |
| `EXTRA/` (34) | Extensions de la stdlib (`unixExtra`, `listExtra`, `stringExtra`, `strExtra`, `mutexExtra` (mutex récursifs), `threadExtra`, `stackExtra`, `ooExtra`, …) + 2 stubs C (waitpid, does-process-exist). |
| `CHANNEL/` (20) | Concurrence par messages : canaux à la **Milner**, hublets, collector, lock_clubs, structures thread-safe paresseuses. |
| `CAMLP4/` (14) | Les extensions de syntaxe (cf. § conventions) + outillage commun ; compilées **hors dune** par le Makefile. |
| `SHELL/` (8) | Interaction système : `shell` (commandes), `linux` (…/proc, kill de descendance), `pts`, wrapper. |
| `WIDGETS/` (4) | Aides GTK : `widget` (wrappers réactifs), `environments` (env de widgets par nom). |
| `GETTEXT/` (4) | i18n : `gettext_builder` (foncteur + stub C `gettext-c-wrapper.c`), `gettext_extract_pot_p4` (préprocesseur d'extraction). |
| `DOT/` (4) | Génération Graphviz : `dot` (AST + rendu), `dot_widget` (intégration GTK). |
| `MARSHAL/` (2) | `oomarshal` : (dé)sérialisation objet vers fichiers (persistance treeviews/sketch). |
| `CORTEX/` (2) | `spinning` : complément de cortex (attente active ?). **?role** : pourquoi séparé de `STRUCTURES/cortex.ml` ? |
| `CONFIGURATION/` (2) | `configuration_files` : lecture cascadée fichiers de conf + environnement. |

**Adossement de bin/ sur lib/** (fréquence des références `Ocamlbricks.X` dans bin/) : les sous-dossiers **EXTRA** (Option¹, UnixExtra 15, ListExtra 13, StringExtra 11, StrExtra 10, MutexExtra 10, OoExtra 8, StackExtra 5…) et **STRUCTURES** (Forest 15, Cortex 11, Xforest 10, Either 6, Stateful_modules 6, Lazy_perishable 5, Future 5, Ipv4/6…) sont le socle massif ; viennent ensuite WIDGETS (Environments 7, Widget 6), SHELL (Shell 6, Linux 4), MARSHAL (Oomarshal 6), DOT (3+2), CHANNEL (Milner, Channel — surtout via gMain_actor), BASE (Argv, Log_builder), GETTEXT et CONFIGURATION (1-2 chacun). ¹Option est comptée 23 fois (STRUCTURES).

**Piège** : lib/ garde son propre écosystème de build historique (Makefile.local, configure, META, tests/) inutilisé par le port dune, sauf la partie préprocesseurs.

---

## E. uml/ — construction des systèmes invités (bash)

- `uml/README` — répartition : patches noyau (ghostification, travail Roudière/Saiu) vs scripts pupisto (Loddo/Seignard).
- `uml/kernel/` — patches de « ghostification » (interfaces réseau fantômes invisibles de l'invité) et configs `.config` pour noyaux UML 2.6.x → 3.x ; `older-versions/` archivées ; doc dédiée (`doc/README.Ghostification`, erreurs connues fr/en).
- `uml/ethghost/` — outil C userland (+ Makefile) pilotant la ghostification des interfaces dans l'invité.
- `uml/guest/` — fichiers à installer dans l'invité : `marionnet-relay` (init de communication invité↔hôte), faux serveur X (`marionnet-dummy-xserver`/`xservice`), clé ssh, `make-tarball-for-guest-system.sh`.
- `uml/pupisto.common/` — bibliothèques sourcées : `toolkit_image.sh` (création/montage d'images), `toolkit_chroot.sh`, `toolkit_config_files.sh`, `toolkit_debugging.sh`.
- `uml/pupisto.debian/` + `pupisto.debian.sh` — construction d'un filesystem Debian par debootstrap (catalogues de paquets par release dans `package_catalog/`).
- `uml/pupisto.buildroot/` + `pupisto.buildroot.sh` — idem via Buildroot (avec overlays : quagga, dhcpd, radvd, ethghost.mk…).
- `uml/pupisto.kernel/` + `pupisto.kernel.sh` — téléchargement + patch + compilation des noyaux UML (`_build.downloads/` et sources git-ignorés).
- `uml/startup.old/` — anciens scripts de démarrage invité (grab_config, prepare_startup/shutdown, cfg2html…). **?role** : supersédé par `uml/guest/marionnet-relay` ? (le nom `.old` le suggère, mais le contenu reste versionné).

**Conventions bash observées** : les orchestrateurs (`pupisto.*.sh`) utilisent `set -e` et beaucoup de **fonctions nommées** (38 dans pupisto.debian.sh) ; motif remarquable d'**auto-journalisation** (le script se ré-exécute lui-même sous `tee` avec fichier de log mktemp et code de sortie récupéré). En revanche : pas de `set -u` ni `pipefail` nulle part (**?convention** — pour du bash 2013 c'est cohérent d'époque, mais en-deçà de ta pratique actuelle) ; variables souvent non quotées ; les bibliothèques `toolkit_*.sh` et les scripts destinés à l'invité (`marionnet-relay`, busybox sh) n'ont pas de `set -e` (justifiable : sourcés / environnement busybox). `marionnet-relay` active `set -x` si `MARIONNET_DEBUG=true` (couplage propre avec le mode debug de l'hôte).

---

## F. Conventions transverses OCaml (observées sur bin/ + lib/)

**Style : OO + impératif contrôlé, pas de style « moderne result »**
- 87 classes dans bin/ ; héritage profond côté user_level ; le projet est délibérément **orienté objets + foncteurs** (foncteurs `Make(State)` pour l'injection de dépendances, `Stateful_modules.Variable` pour les singletons, `MutexExtra.Just_give_me_an_apply_with_mutex (struct end)` pour générer un mutex frais par module).
- État global réel mais **canalisé** : `st : globalState` unique, treeviews singletons, options sous mutex récursif, variables réactives Cortex. Refs mutables toplevel présentes mais généralement protégées (daemon_client, death_monitor).
- **Gestion d'erreurs : exceptions dominantes** (128 `failwith`/`raise` dans bin/), `Option.extract` partiel très utilisé ; **pas de `Result`** (le code précède result ; l'équivalent maison `Either` n'est utilisé en style erreur que dans `daemon_language` — validation défensive du protocole, seul endroit où l'entrée n'est pas de confiance). La boucle principale **rattrape tout** et relance GTK. Cohérent historiquement ; en contradiction avec ta préférence actuelle result — mais un refactor serait massif.
- **Couverture .mli partielle et intentionnelle** : 17/44 dans bin/, 4/14 dans gui/. Les .mli existent pour les modules « bibliothèque » (disk, user_level, simulation_level, machine, monitors, task_runner, gui_bricks, menu_factory, talking…) et manquent pour les composants/écrans (hub, switch, treeview_*, marionnet…). Trois .mli sont de plus **injectés dans le .ml** par `INCLUDE DEFINITIONS` (simulation_level, motherboard_builder, menu_factory) pour ne pas dupliquer les définitions de types — technique maison à connaître avant toute édition (chemins `../../../../` relatifs au bac à sable dune !).

**Camlp4 — inventaire précis (impact toolchain fort)**
- Chaîne appliquée à *tout* bin/ (bin/dune) : `option_extract_p4` (sucre d'extraction d'options), `raise_p4` (enrichissement des raise avec localisation), `log_module_loading_p4` (log au chargement des modules).
- À la demande par fichier (`#load` en tête, lu par camlp4of) : `where_p4` (clause `where` à la Haskell — machine, cable, switch, cloud, hub, world_bridge, world_gateway, router) ; `include_type_definitions_p4` (injection de .mli — 3 fichiers) ; `include_as_string_p4` (embarque un fichier comme chaîne — talking.ml) ; conditionnels `IFDEF OCAML4_02_OR_LATER` etc. (serial, gettext, ledgrid_manager, router) pilotés par `lib/camlp4of-flags.cfg`.
- Conséquences : (1) OCaml épinglé 4.13.1 (dernier compatible camlp4) ; (2) impossible de builder sans la phase make préalable ; (3) tout outillage moderne (merlin/LSP sur fichiers préprocessés, ocamlformat) est dégradé ; (4) migration future = réécrire ces 7 extensions (ppx ou dépliage manuel).

**Threads** : bibliothèque `threads` (pas de domains — OCaml 4), GTK confiné au thread principal, `gMain_actor` (acteur) pour la traversée de frontière, mutex récursifs partout, monitors par polling, `task_runner` sérialisant les opérations réseau, `Future`/canaux Milner pour l'async ponctuel.

**Micro-conventions de code** : en-tête GPL systématique ; bloc d'alias `module X = Ocamlbricks.X` en tête de chaque fichier (à la place d'`open` — dépendances explicites, très lisible) ; séparateurs `(* --- *)` ; widgets glade nommés en MAJUSCULES suffixées (`window_MARIONNET`, `toolbar_COMPONENTS`) ; identifiants parfois francophones côté messages (`help_repertoire_de_travail`).

---

## G. Flux global (démarrage → GUI → machines UML)

1. **(Optionnel, root)** `marionnet-daemon` tourne (init script dans useful-scripts) : écoute la socket Unix, prêt à créer taps/bridges pour les clients, détruit les ressources des clients silencieux > 120 s.
2. **Démarrage GUI** : effets de bord de chargement des modules dans l'ordre de dépendance — `initialization` (argv + conf + chemins) → … → `marionnet.ml` : chdir, `globalState`, foncteurs GUI, treeviews, connexion daemon (sinon mode dégradé), splash, tmpdir sparse, checks (non-root, filesystems/kernels par défaut, vde patché, graphviz), signaux + at_exit, `GtkThread.main`.
3. **Projet** : création/ouverture (.mar = arborescence projet) via state.ml ; le réseau (user_level.network) est (dé)sérialisé en Xforest ; le **sketch** est regénéré par dot et affiché ; les treeviews chargent leurs forêts marshallées.
4. **Démarrage d'un composant** : user_level crée les objets simulation_level → spawn des processus (kernel UML avec filesystem COW dans states/, vde_switch par hub/switch et « hublets » par port, slirpvde pour la passerelle, xterm/consoles via serial + uml_mconsole) → death_monitor surveille ; ledgrid_manager reçoit l'activité des ports par socket datagramme ; les défauts (treeview_defects) sont appliqués aux câbles/ports ; l'accès X des invités passe par x.ml ; ce qui exige des privilèges (tap du world_bridge) est demandé au daemon.
5. **Arrêt** : shutdown gracieux ou poweroff par composant ; à la sortie, kill brutal de toute la descendance + orphelins (contournement des noyaux 3.2.x qui relancent des port-helpers).

**Frontières entre couches** : GUI (bin/gui/*, gui.ml) ↔ état/modèle (state, user_level, sketch, treeviews) ↔ simulation (simulation_level, serial, cow_files, monitors) ↔ système (lib/SHELL, stubs C, daemon). L'injection `Make(State)` et l'acteur GTK sont les deux mécanismes qui empêchent ces couches de se court-circuiter.

---

## H. Points d'attention et pièges (synthèse)

1. **Fichiers générés à ne pas éditer** : `bin/version.ml`, `bin/meta.ml` (makers bash) ; `bin/gui.ml` cas particulier **généré-puis-modifié** (édition manuelle obligatoire mais régénération interdite sans diff).
2. **Ordre de build** : make avant dune (préprocesseurs + stubs) ; garde-fou « make clean required! » si désynchronisation `_build/`.
3. **`main.ml` linké dans les 2 exécutables** avec effets de bord au démarrage (voir doute n°1) .
4. **Duplication des règles camlp4** entre `Makefile` racine et `lib/Makefile`.
5. **Chemins `../../../../` codés en dur** dans les `INCLUDE DEFINITIONS` et `bin/dune` (dépendants de la profondeur du bac à sable dune).
6. **Code mort apparent** : `bin/gui/gui.xml` + dtd, `bin/po/POTFILES.in`, `uml/startup.old/`, `Makefile.d/{Makefile.luca,marionnet-utop,…}`, templates `.ml-template`, `test/marionnet.ml` vide, demo main commenté de `ledgrid.ml`.
7. **Dépendances bzr résiduelles** : `meta.ml.maker.sh` (revno), `Makefile.d/bzr_date`, `REQUIRED_PACKAGES` contient encore `bzr`.
8. **Obj.magic** (25×) aux jointures user/simulation level.
9. **Toolchain gelée** : camlp4 ⇒ OCaml 4.13.1 ; lablgtk3 + gtksourceview3 ; toute mise à jour d'ampleur passe par l'abandon de camlp4.
10. `CONFIGME` : strip `lablgtk2` vs `lablgtk3` (incohérence final/testing).

---

## I. Doutes estampillés — à soumettre à l'auteur

**?role (8)**
1. `bin/main.ml` : hello-world de test ; quel est son statut dans le port dune (à exclure de `(modules :standard)` ? à supprimer ?).
2. `bin/gui/gui.xml` + `glade-2.0.dtd` : interface glade-2 héritée non référencée — morte ou gardée comme référence ?
3. `bin/gui/gui_component-node-{with,without}-state.ml-template` : gabarits qui citent un `gui_machine.ml` disparu — encore la procédure officielle pour ajouter un composant ?
4. `uml/startup.old/` : remplacé par `uml/guest/marionnet-relay` ?
5. `Makefile.d/` : archive du build ocamlbuild/bzr, ou certains scripts (marionnet-toplevel, marionnet-utop, test_with_utop.sh) sont-ils censés fonctionner sous dune ?
6. `lib/CORTEX/spinning.ml` : pourquoi hors de `STRUCTURES/` (où vit cortex.ml) — découpage thématique voulu ?
7. `test/marionnet.ml` vide + stanza test : placeholder en attente de vrais tests ?
8. `bin/gui.ml` : procédure prévue de mise à jour quand `gui_glade3.xml` évolue (lablgladecc + report manuel des modifications ?).

**?convention (5)**
1. `CONFIGME` (final) : `libraryprefix=${libraryprefix%/lablgtk2}` — oubli (testing strippe `/lablgtk3`) ?
2. `dune-project` : placeholders `(github username/reponame)`, licence non-SPDX `GNU-GPL-v2`, `marionnet.opam` généré mais git-ignoré — état transitoire du port ou choix ?
3. `bin/po/POTFILES.in` : références à des fichiers disparus — à purger/régénérer ?
4. `Obj.magic` (25×, 10 fichiers) aux jointures de niveaux : dette connue et assumée ?
5. uml/ : absence générale de `set -u`/`pipefail` (et `set -e` absent des toolkits sourcés) — assumé pour compatibilité busybox/sourçage ?

**?intent (4)**
1. `(modules :standard)` dans `bin/dune` lie tous les modules (dont `main.ml` et ses effets de bord, et tout le code GUI) dans **marionnet-daemon** aussi — le daemon embarque-t-il volontairement lablgtk, ou est-ce une simplification temporaire du port (l'ancien stanza `executable` séparé pour le daemon est commenté juste en dessous) ?
2. `gettext_extract_pot_p4.cmo` retiré (commenté) de la chaîne preprocess de `bin/dune` : extraction POT déplacée définitivement vers les cibles make ?
3. `make install-final-as-root` : génération d'un script exécuté par sudo (plutôt que `sudo dune install`) — motivé par la préservation de l'env opam sous root ?
4. `meta.ml.maker.sh` : après la conversion bzr→git, `revision`/`source_date` seront vides — prévoir la variante git, ou l'information n'a plus d'importance ?
