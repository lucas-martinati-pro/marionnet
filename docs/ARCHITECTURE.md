# Architecture de Marionnet (port dune)

> Récit d'architecture **vivant** : mettre à jour la section touchée quand le code change.
> Estampille : généré le 2026-07-06 depuis l'audit `docs/audit-marionnet-20260706.md`,
> périmètre bin/ + bin/gui/ + uml/ + build (lib/ en survol). Lire **par sujet**.

## 1. Build hybride (make orchestre, dune exécute)

La contrainte fondatrice est **camlp4** : dune ne compile pas (dans ce montage) les
préprocesseurs avant de s'en servir. D'où la chaîne `make` (cible par défaut) :

1. `make meta` — génère `bin/version.ml` et `bin/meta.ml` via `bin/*.maker.sh`, à partir de
   `META` (mini-fichier shell name/version, PAS un META ocamlfind) et de `CONFIGME.choice`.
2. `make -C lib main-no-build` — copie et compile **avec ocamlc/camlp4of directement** les
   préprocesseurs (`lib/CAMLP4/*_p4`, `gettext_extract_pot_p4`) et les stubs C dans
   `lib/_build/` (+ `libocamlbricks_stubs.a`). Garde-fou : source ≠ copie → « make clean required! ».
3. La racine recopie (hard links) `lib/_build/*` → `_build/`.
4. `dune build` — compile `lib/` (library `ocamlbricks`) puis `bin/` (executables), chaque
   source passant par `camlp4of` avec les `.cmo` de l'étape 2 (`-I ../../../../lib/_build/`,
   chemins relatifs au bac à sable `_build/default/...`).

Conséquences : `dune build` seul échoue sur un clone frais ; OCaml épinglé **4.13.1** ;
les règles camlp4 sont **dupliquées** entre `Makefile` racine et `lib/Makefile` (piège de
maintenance). L'installation passe par `make install-final-as-root` (script temporaire sudo
qui préserve l'env opam — et non `sudo dune install`) ou la variante testing (installe dans
le switch opam) ; le choix est mémorisé par le symlink `CONFIGME.choice` et `meta.ml` en
dépend (`make rebuild-for-{final,testing}` si changement). `CONFIGME` est une config shell
sourcée, surchargée par `~/.marionnet` puis l'environnement à l'exécution.

État transitoire connu (chantier « finitions du port dune ») : placeholders de
`dune-project`, `marionnet.opam` généré mais git-ignoré, `meta.ml.maker.sh` encore bzr,
strip `lablgtk2` vs `lablgtk3` dans `CONFIGME`, `main.ml` + `(modules :standard)` (§ 2).

## 2. Les deux niveaux + composants (le cœur du modèle)

- **user_level** (`bin/user_level.ml`) — le réseau *tel que l'utilisateur le voit* : classes
  OO (`component`, `node_with_ports_card`, …, `virtual_machine_with_history_and_ifconfig`,
  `cable`) agrégées par la classe `network`. Sérialisation projet via `Xforest`.
- **simulation_level** (`bin/simulation_level.ml`) — les *processus Unix* qui simulent :
  classe virtuelle `process` et descendants (UML `linux`, `vde_switch`, `slirpvde`, `xterm`,
  hublets), spawn/kill/suspend/resume.
- **composants** — un fichier par équipement (machine, router, hub, switch, cable, cloud,
  world_bridge, world_gateway) contenant classe user-level + classe simulation-level +
  dialogue GTK (`module Dialog_…` rejeté en fin de fichier par l'extension `where_p4`).

Le passage user→simulation se fait par méthodes de fabrique ; les casts remontants utilisent
`Obj.magic` (25×, 10 fichiers) — dette à réduire à l'occasion quand on touche ces fichiers.
Deux exécutables : `marionnet.native` (GUI) et `marionnet-daemon.native` ; actuellement
`(modules :standard)` lie tout dans les deux (dont le vestige `main.ml` et ses effets de
bord au démarrage) — à corriger, l'ancien stanza séparé du daemon est commenté dans `bin/dune`.

## 3. GUI (glade → gui.ml → foncteurs de complétion)

`bin/gui/gui_glade3.xml` est la **source de vérité** (édition : `make edit-gui`).
`bin/gui.ml` donne l'accès typé aux widgets : **généré par lablgladecc puis modifié à la
main** — aucune procédure de régénération n'est établie, donc ne jamais régénérer, éditer à
la main. Les modules `bin/gui/gui_*` *finissent* l'interface par code ; la plupart sont des
foncteurs `Make (State : sig val st : State.globalState end)` appliqués dans
`bin/marionnet.ml` — le mécanisme d'injection de l'état global (à la place de globals croisés).
`gui_bricks` est le socle des dialogues ; `gui_toolbar_COMPONENTS_layouts` factorise les
menus de composants par foncteurs ; `ledgrid_manager` reçoit l'activité des ports par socket
datagramme depuis les vde_switch patchés.

## 4. État global & persistance

Racine d'état unique : `st : State.globalState` (bin/state.ml) — fenêtre, `network`
(user_level), les 4 treeviews, save/load projet, startup/shutdown everything. Un projet
`.mar` est une arborescence dézippée (classtest/hostfs/netmodel/scripts/states/tmp) gérée
par `project_paths`. Le réseau se (dé)sérialise en **Xforest** ; les treeviews et le sketch
se marshalent (`Oomarshal`) ; `compatibility/forest_backward_compatibility.ml` relit les
projets v0. Les singletons d'état suivent le patron `Stateful_modules.Variable` ;
les options runtime vivent sous mutex récursif (`global_options`). Le dessin du réseau
(`sketch.ml`) est régénéré via Graphviz (lib/DOT) et rafraîchi par thunk global.
`motherboard_builder` câble réactivement (Cortex) l'état projet ↔ sensibilité des widgets.

## 5. Concurrence

Bibliothèque `threads` (OCaml 4, pas de domains). Règles : GTK confiné au **thread
principal** (`GtkThread.main`, relancé sur exception — résilience UI) ; tout autre thread
poste ses actions GUI à l'**acteur** `gMain_actor` (GMain.Idle + canaux Milner, garde
anti-deadlock si l'appelant est déjà le thread GTK). Les opérations réseau sont sérialisées
par `task_runner` (file de tâches nommées + worker, dépendances ordonnancées par `graph.ml`) ;
`death_monitor` (polling pid→callback) et `descendants_monitor` (tueur d'orphelins)
surveillent les processus ; mutex récursifs (`MutexExtra`) partout ailleurs.

## 6. Daemon & privilèges

`marionnet-daemon` (root) crée taps/bridges pour les clients GUI non privilégiés :
socket Unix, boucle select, ressources par client (multimap), destruction des ressources
d'un client silencieux > 120 s (keepalives émis par `daemon_client`, thread dédié).
Protocole : messages **taille fixe 128 octets**, AST requêtes/réponses dans
`daemon_language.ml`, validation défensive en style result (`Either`) — seul endroit du code
où l'entrée n'est pas de confiance. La GUI se dégrade gracieusement sans daemon
(`disable_daemon_support`) : world_bridge indisponible, le reste fonctionne.

## 7. i18n (gettext, hors dune)

Circuit 100 % Makefile : extraction des chaînes par le préprocesseur camlp4
`gettext_extract_pot_p4` sur copies des .ml (`make gettext-all-ml-pot-files` →
`bin/po/messages.pot`), `gettext-update-po` (msgmerge), `gettext-compile-mo`/`install-mo`.
Langues actives : `bin/po/LINGUAS` (fr it ar es pt ro zh). À l'exécution, `bin/gettext.ml`
(wrapper de lib/GETTEXT + stub C) expose `s_` et `f_`. L'extraction a été retirée de la
chaîne preprocess dune (commentée dans `bin/dune`) au profit des cibles make.
`bin/po/POTFILES.in` référence des fichiers disparus (vestige).

## 8. Systèmes invités (uml/) et frontière hôte/invité

Les invités sont fabriqués par les scripts **pupisto** : `pupisto.debian.sh` (debootstrap),
`pupisto.buildroot.sh` (Buildroot + overlays), `pupisto.kernel.sh` (noyaux UML patchés).
Les patches de **ghostification** (uml/kernel/) rendent invisibles à l'invité les interfaces
de service ; `ethghost` (C) les pilote depuis l'invité. `uml/guest/marionnet-relay` est
l'init de communication invité↔hôte (X via `bin/x.ml`, consoles via `bin/serial.ml` +
`uml_mconsole`). À l'exécution, chaque machine démarre un noyau UML sur un filesystem COW
(`cow_files`, sparse) dans `states/` du projet ; l'inventaire des filesystems/kernels
installés est géré par `bin/disk.ml` (« epithets »).

## 9. Adossement à ocamlbricks (lib/)

ocamlbricks est **vendored** (revno 560) et wrappé (`Ocamlbricks.X`) ; chaque fichier de
bin/ ouvre ses dépendances par alias `module X = Ocamlbricks.X` en tête (lisibilité des
dépendances). Socle massif : EXTRA (UnixExtra, ListExtra, StringExtra, MutexExtra…) et
STRUCTURES (Forest/Xforest, Cortex, Option, Either, Stateful_modules, Future…) ; voir
`lib/CLAUDE.md` pour la carte des sous-dossiers. Les évolutions de fond de lib/ se font
dans le projet amont ocamlbricks, pas ici.

## 10. Camlp4 — inventaire (impact toolchain)

Global sur bin/ (via `bin/dune`) : `option_extract_p4` (sucre d'extraction d'options),
`raise_p4` (localisation des raise), `log_module_loading_p4`. Par fichier (`#load` en tête) :
`where_p4` (clause `where` — les 8 composants), `include_type_definitions_p4` (injection du
.mli dans le .ml — simulation_level, motherboard_builder, menu_factory ; chemins
`../../../../` relatifs au bac à sable dune), `include_as_string_p4` (talking.ml),
conditionnels `IFDEF` (serial, gettext, ledgrid_manager, router ; pilotés par
`lib/camlp4of-flags.cfg`). Toute migration hors camlp4 = réécrire ces 7 extensions (ppx ou
dépliage) — c'est le verrou qui fige OCaml à 4.13.1.
