# Architecture de Marionnet (port dune)

> Récit d'architecture **vivant** : mettre à jour la section touchée quand le code change.
> Estampille : généré le 2026-07-06 depuis l'audit `docs/audit-marionnet-20260706.md`,
> périmètre bin/ + bin/gui/ + uml/ + build (lib/ en survol). Lire **par sujet**.
> Rectifié le 2026-07-27 : § 1 (build) réécrit — la chaîne make→dune décrite jusque-là avait
> disparu avec `finitions-port-dune` ép. 1-2 — et § 10 (le gel 4.13.1 n'existe plus).

## 1. Build — `dune build` seul suffit

La contrainte fondatrice reste **camlp4** (7 extensions de syntaxe, § Camlp4), mais elle n'impose
plus de pré-fabrication hors dune : **sur un clone frais, `dune build` seul suffit** (chantier
`finitions-port-dune`, ép. 1-2, 2026-07-13). L'ordre est entièrement déduit par dune :

1. **Les préprocesseurs** — 7 `(rule)` de `lib/dune` invoquent `ocamlfind ocamlc -pp camlp4of`
   sur `lib/CAMLP4/*_p4` et `GETTEXT/gettext_extract_pot_p4`. Les `.cmo` produits sont ensuite
   chargés par les `(preprocess)`/`(preprocessor_deps)` de `lib/dune` et `bin/dune`, avec
   `-I ../../../../_build/default/lib/` — chemin relatif au bac à sable `_build/default/…`,
   fragile mais stable. Ces modules sont exclus de la bibliothèque par `(modules (:standard \ …))`.
2. **Les fichiers générés** — `bin/version.ml` et `bin/meta.ml` naissent de `(rule)` de `bin/dune`
   qui exécutent les makers bash à partir de `META` (mini-fichier shell name/version, PAS un META
   ocamlfind) et de `CONFIGME.choice`. Ces règles dépendent de `(universe)` : sandbox désactivée
   (les makers ont besoin du vrai dépôt pour `git rev-parse`/`git log`) et ré-exécution à chaque
   build. Corollaire : ces deux fichiers ne doivent **jamais** exister dans l'arbre source — une
   cible de règle ne peut pas coexister avec un fichier source ; `make clean` les supprime.
3. **Les bibliothèques et l'exécutable** — `ocamlbricks` (`lib/`, avec ses 3 stubs C déclarés en
   `foreign_stubs`), puis `marionnet_base`, `marionnet_tap`, `marionnet_sites`, puis l'unique
   exécutable `bin/marionnet.native`.
4. **L'i18n** — `i18n/dune` compile les 12 `.po` en `.mo` (`msgfmt`) et les installe dans le site
   dune-site `locale`, que `bin/gettext.ml` consulte en tête de sa cascade (§ i18n).

**Ce que `make` garde** : l'**installation** (`install-final-as-root` — script temporaire exécuté
par sudo, qui préserve l'env opam, et non `sudo dune install` — ou `install-for-testing`, qui
installe dans le switch opam et y symlinke kernels/filesystems), l'**extraction POT** (camlp4,
`gettext-messages-pot`) et le **msgmerge** (`gettext-update-po`), les **dépendances**
(`apt-dependencies`, `opam-switch`/`opam-dependencies`) et le **RPM** (`RPMS/Makefile`).
`all`, `rebuild`, `clean` ne sont plus que des enveloppes de `dune`.

**Toolchain : OCaml 5.4.1** (chantier `migration-ocaml5`, 2026-07-27) — build, runtime et
installation en profil *testing* validés. Le gel historique en 4.13.1, motivé par « dernier
compatible camlp4 », reposait sur une prémisse **fausse** (`camlp4.5.4` existe).

**Profil d'installation** : le symlink `CONFIGME.choice` (→ `CONFIGME` = final, ou
`CONFIGME.testing.sh` = testing) décide des préfixes gravés dans `meta.ml` ; en changer impose
`make rebuild-for-{final,testing}`. `CONFIGME` est une config shell sourcée, surchargée par
`~/.marionnet` puis par l'environnement à l'exécution.

**Vestiges à ne pas prendre pour référence** : `lib/Makefile` (cible `main-no-build`),
`lib/Makefile.local`, `lib/configure`, `lib/META`, `lib/tests/` — l'ancienne chaîne make→dune.
Il n'y a plus de `lib/_build/`, plus de hard-link vers `_build/`, plus de garde-fou
« make clean required! », et les règles camlp4 ne sont plus dupliquées entre deux Makefile.

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
Un seul exécutable : `marionnet.native` (GUI) — le second, `marionnet-daemon.native`, a été
supprimé (chantier `marionnet-daemon-elimination`, épisode 4). Les modules partagés entre la
bibliothèque `marionnet_tap` et la GUI (`marionnet_log`, `configuration`, `meta`) vivent dans
la bibliothèque `marionnet_base` (`wrapped false`, ex-`marionnet_common`).

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

**Règles acquises par mesure** (chantier `marionnet-automate-composants`, ép. 9-15 ; détail et
preuves : `docs/refonte-automate-composants.md`) : (1) appeler Gtk+ hors du thread principal
**fige tout le processus** — le trampoline `marshal` de lablgtk réclame le master lock du
runtime, déjà détenu et non réentrant : ni exception ni CPU, juste une fenêtre morte ; (2) un
site n'est dangereux que si **trois** conditions se réunissent — thread ≠ principal, appel qui
émet un signal **synchronement** (`store#remove/append`, `expand/collapse_row`, `#destroy` —
mais **pas** `#run ()` d'un dialogue, dont la boucle imbriquée relâche le lock), et callback
OCaml connecté à ce signal ; (3) déléguer avec **`apply_extract`**, jamais `delegate`, qui
`ignore` l'`Either` et **avale l'exception** ; (4) enrober une méthode qui prend un mutex doit
**englober le verrou**, sinon l'appelant le détient en attendant le thread principal, et tout
`lock; corps; unlock` nu se protège par `Fun.protect`. Invariant : **toute** mutation du modèle
Gtk+ — ajout, suppression, surlignage — part du thread principal. Corollaire de lecture : ne
jamais lire une identité ni une valeur **dans le widget** (forêt interne uniquement).

## 6. Privilèges (taps) — Tap_provider

Le service root permanent `marionnet-daemon` a été **supprimé** (chantier
`marionnet-daemon-elimination`, épisodes 0-4 ; étude : `docs/daemon-elimination-study.md`).
Les taps (eth42 par VM, raccord au bridge du world_bridge) sont créés/détruits par
`bin/tap_provider.ml` via **`sudo -n` + iproute2**, sous une règle sudoers *scoped*
(`/etc/sudoers.d/marionnet`, déposée par `bin/scripts/marionnet-sudoers.sh` — source unique
du texte, partagée install ↔ runtime). Contrat réseau du daemon reproduit à l'identique
(nom `mtap<pid>-<seq>`, `172.23.0.254/32`, route host-specific, promisc+master). GC des
orphelins : `purge_orphan_taps` au démarrage (ne touche que les taps d'un pid **mort**).
Sans la règle (probe `is_usable` négatif) : mode dégradé + dialogue expliquant
`marionnet-sudoers.sh install`. Doc admin : `docs/admin-taps-and-bridge.md`.

## 7. i18n (gettext — extraction Makefile, compile+install dune)

**Frontière (depuis l'épisode 6 de `finitions-port-dune`, dune-site)** :
- **Extraction + merge = Makefile** (tâches développeur) : extraction des chaînes par le
  préprocesseur camlp4 `gettext_extract_pot_p4` sur copies des .ml (`make
  gettext-all-ml-pot-files` → `bin/po/messages.pot`), puis `gettext-update-po` (msgmerge).
  L'extraction reste couplée camlp4 → traitée avec le chantier `camlp4 → ppx`.
- **Compile + install = dune** (`i18n/dune`) : `msgfmt` sur `bin/po/*.po` → `.mo`, installés dans
  la *site* dune-site `locale` (`dune-project` : `(sites (share locale))`), soit
  `<prefix>/share/marionnet/locale/<lang>/LC_MESSAGES/marionnet.mo`. Plus de
  `gettext-compile-mo`/`install-mo` ni de `LOCALE_PREFIX` issu de CONFIGME.

Langues actives : `bin/po/LINGUAS` (fr it ar es pt ro zh) — à garder en phase avec les 7 `(rule)`
de `i18n/dune`. À l'exécution, `bin/gettext.ml` (wrapper de lib/GETTEXT + stub C) expose `s_` et
`f_` ; il choisit le `localeprefix` par cascade décroissante : **`Marionnet_sites.Locations.Sites.locale`**
(dirs de la site dune-site, relocatable, généré par `(generate_sites_module)` dans `i18n/dune`),
puis env `MARIONNET_LOCALEPREFIX`, puis `Meta.localeprefix` (figé par CONFIGME, repli conservé),
puis inférence désespérée sous `/usr`. `bin/po/POTFILES.in` référence des fichiers disparus (vestige).

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
dépliage). Ce n'est **plus** un verrou de toolchain : `camlp4.5.4` existe et le projet compile
sur OCaml 5.4.1 (§ 1) ; ne subsiste que la dégradation de **Merlin/LSP/ocamlformat** sur les
fichiers préprocessés — seule justification restante du chantier `camlp4-to-ppx`.
