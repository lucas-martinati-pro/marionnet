# CLAUDE.md — Marionnet (port dune)

Simulateur de réseaux pédagogique basé sur User-Mode Linux (UML) : les équipements
(machines, routeurs, switchs…) sont de vrais processus Linux/vde reliés entre eux, pilotés
par une GUI GTK. OCaml + lablgtk3, GPL. Auteur : Jean-Vincent Loddo (+ Luca Saiu).
Ce dépôt est le **port dune** du projet historique (bzr/ocamlbuild → git/dune, converti 2026-07).

## Build — `dune build` seul suffit

**Sur un clone frais, `dune build` seul suffit** — plus aucun `make` préalable requis. Les
préprocesseurs **camlp4**, les stubs C, `bin/version.ml` et `bin/meta.ml` sont tous construits
**par dune** (`(rule)` dans `lib/dune` et `bin/dune`, `foreign_stubs`) : plus de pré-fabrication
dans `lib/_build/` ni de hand-link. `make` ne reste requis que pour l'**i18n gettext**,
l'**install** et le **RPM**.

- Toolchain : **OCaml 5.4.1** (chantier `migration-ocaml5`) — depuis le 2026-07-27 le build est
  vert, le **runtime est validé** (cycle GUI réel) et l'**installation en profil *testing*** aussi ;
  le gel 4.13.1 est levé. Reste non joué : `make install-final-as-root` (root, `/usr/local`).
  Le `Makefile` (`OPAM_SWITCH_TO`) crée/pointe ce switch.
  Le motif historique du gel (« dernier compatible camlp4 ») est **caduc** : `camlp4.5.4` existe.
  **Merlin/LSP fonctionnent sur les fichiers préprocessés** depuis le 2026-07-28 (`fde2096`,
  `f0754c5`) : dune passe la commande `(preprocess (action (run camlp4of …)))` telle quelle à
  merlin, qui la rejoue **depuis le répertoire du fichier source** — d'où un `-I` absolu généré
  (`(rule)` `camlp4of-include.cfg` de `lib/dune`) et, côté préprocesseurs, un repli vers la racine
  du projet (`INCLUDE DEFINITIONS`/`INCLUDE_AS_STRING`) plus une garde par suffixe
  (`log_module_loading_p4`, que la copie temporaire `/tmp/merlinpp<hash><base>` mettait en défaut).
  Mesuré : 0 diagnostic sur les fichiers de `bin/` et `lib/`, hover correct sur les identifiants
  déplacés par `where_p4`. Restent aveugles : les 7 **sources de préprocesseurs** elles-mêmes
  (exclues des modules de la bibliothèque, donc sans config merlin). Côté éditeur, la
  configuration est **locale et gitignorée** (bac à sable opam `5.4.1`) ; `ocamlformat` y est
  volontairement **désactivé** (pas de `.ocamlformat`, style maison). Il ne reste donc **plus
  grand-chose** pour justifier `camlp4-to-ppx`.
- Install : `make install-final-as-root` (final) ou variante testing — bascule par le symlink
  `CONFIGME.choice` ; si le choix change : `make rebuild-for-{final,testing}`.
- i18n : la compilation `.po` → `.mo` **et** son installation sont **sous dune** (`i18n/dune`, site
  dune-site `locale`) ; seules l'**extraction POT** (camlp4) et le **msgmerge** restent Makefile
  (`gettext-messages-pot`, `gettext-update-po`). RPM (`RPMS/`) : 100 % Makefile, non testé sous 5.4.1.

## Cartographie

| Où | Quoi | Détail |
|---|---|---|
| `bin/` | cœur applicatif (40 .ml) : modèle réseau à 2 niveaux + composants + Tap_provider | `bin/CLAUDE.md` |
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

- **RÈGLE DE PROJET — le câblage suit la réalité.** Toute question portant sur le câblage des
  composants **via la GUI** se tranche par ce qui est **possible dans la réalité**, dans les
  limites de la virtualisation. Un geste faisable sur du matériel réel doit rester faisable dans
  Marionnet, **même si l'implémentation coûte plus cher** : typiquement, déplacer un câble d'un hub
  vers un switch **pendant que les machines tournent** (on débranche et on rebranche ailleurs, sans
  éteindre personne). Corollaire : « aligner les câbles sur les autres composants, par symétrie »
  n'est **pas** un argument recevable — c'est exactement l'erreur commise à l'épisode 8 du chantier
  `marionnet-automate-composants` (clos), **révisée à son épisode 12** : un câble s'édite et se
  supprime **en marche** (cf. `docs/refonte-automate-composants.md`).
- **Messages de commit : ANGLAIS obligatoire** pour tout le dépôt Marionnet (règle de scope
  projet). Conventional Commits ; rédiger/traduire le message en anglais avant de committer, corps
  compris. Trailer `Co-Authored-By` selon la règle utilisateur (seulement si j'ai produit le contenu).
  - **Toute proposition de commit est BILINGUE** : le message **anglais** (celui qui sera
    réellement committé, tel quel) puis, **juste à la suite**, sa **traduction française
    intégrale** — titre *et* corps, y compris les listes et les tableaux. Motif : l'anglais est
    la langue du dépôt, mais le feu vert se donne en français ; relire une traduction fidèle est
    plus rapide et plus sûr que relire l'original. La traduction est un **support de relecture**,
    jamais un second message : elle ne part pas dans git, et si les deux divergent, c'est
    l'anglais qui fait foi (donc traduire **après** avoir figé l'anglais, pas l'inverse).
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
   obligatoire et le garde-fou « make clean required! » n'existent plus.
2. `bin/dune` ne produit plus qu'UN exécutable : `marionnet.native` — le démon
   `marionnet-daemon.native` a été supprimé (ép. 4 de `marionnet-daemon-elimination`). Les
   modules sans lablgtk partagés entre la bibliothèque `marionnet_tap` et la GUI
   (`marionnet_log`, `configuration`, `meta`) vivent dans la bibliothèque `marionnet_base`
   (`wrapped false`, ex-`marionnet_common`). Le vestige `bin/main.ml` (hello-world) a été
   supprimé. Ne plus s'attendre à un `(modules :standard)` unique ni à `main.ml`.
3. `.bzr/` coexiste avec `.git/` (conversion 2026-07) : ne pas y toucher ;
   `bin/meta.ml.maker.sh` extrait la révision via **git** (`rev-list --count`, `log`) depuis
   l'épisode 2, avec repli bzr tant que `.bzr` est présent.
4. Vestiges apparents (non confirmés par l'auteur) : `bin/gui/gui.xml` (glade-2),
   `bin/gui/*.ml-template`, `uml/startup.old/`, une partie de `Makefile.d/`,
   `bin/po/POTFILES.in` — ne pas les prendre comme référence sans vérifier.
5. Répertoires vides attendus par le build (`bin/kernels/`) non suivis par git.

## Chantiers longs (work-streams)

Reprise : appliquer le skill `chantier-long`.
- **camlp4 → ppx** (ancienne « Phase B » de finitions ; sortir des 7 extensions camlp4 ; crux =
  `where_p4`) : `docs/camlp4-to-ppx.md` ; mémoire `marionnet-camlp4-ppx` ;
  `git log --grep="marionnet-camlp4-ppx"`. **NON entamé**, et **à re-prioriser fortement à la
  baisse** : ses **deux** moitiés de justification sont tombées — « lever le gel 4.13.1 » avec
  `migration-ocaml5` (clos le 2026-07-27), puis « restaurer Merlin/LSP » le 2026-07-28
  (`fde2096`, `f0754c5` ; cf. § Build). Reliquats : les 7 sources de préprocesseurs restent sans
  config merlin, `ocamlformat` reste inutilisable sur la syntaxe camlp4, et la dette de fond
  (dépendre d'un préprocesseur mort) demeure — mais plus aucune urgence outillage.
- **noyaux + rootfs** (intégration Dave Appadoo ; Trixie + UML 6.12 ; touche `uml/` **et** l'OCaml
  via un dispatch de boot compat SysV/systemd) : `docs/kernel-rootfs-refresh.md` ;
  mémoire `marionnet-kernel-rootfs` ; `git log --grep="marionnet-kernel-rootfs"`. **Bloque vwifi.**
- **vwifi** (OCaml, BLOQUÉ par le kernel) : `docs/vwifi-integration.md` ; mémoire `marionnet-vwifi` ;
  `git log --grep="marionnet-vwifi"`. Analyse commune : `docs/analyse-dave-appadoo-20260708.md`.
- **rétro-compat vieux couples kernel/image** (wheezy/guignol/mandriva, userlands i386, morts
  avec `linux-3.2.64-ghost` sur hôte ≥ 6.x ; solution démontrée = UML récent `SUBARCH=i386`) :
  `docs/retro-compatibilite-kernels-images.md` ; mémoire `marionnet-retro-compat-kernels-images` ;
  `git log --grep="marionnet-retro-compat-kernels-images"`. Ép. 0→4 faits 2026-07-17
  (ép. 4 : abandon mandriva/pinocchio/lenny + remap auto kernel/distrib au chargement `.mar`).
- **modernisation-world-bridge** (rendre `world_bridge` — dernier bouton palette, icône planète —
  utilisable sans config hôte manuelle risquée [axe barrière, modèle daemon-elimination] **et**
  compréhensible en GUI ; direction : NAT privé auto par défaut + L2 réel en option experte) :
  `docs/modernisation-world-bridge.md` ; mémoire `modernisation-world-bridge` ;
  `git log --grep="modernisation-world-bridge"`. Ép. 0-1 faits 2026-07-18.
- **bug-critique-crash-host** (crash rare non reproductible de l'hôte — reboot machine
  physique / arrêt net du conteneur Docker — corrélé à la terminaison des composants ;
  causes candidates C1-C5 classées, checklist post-mortem à exécuter au prochain crash) :
  `docs/bug-critique-crash-host.md` ; mémoire `bug-critique-crash-host` ;
  `git log --grep="bug-critique-crash-host"`. Ép. 0 (audit) fait 2026-07-18 ; **C5 clos le
  2026-07-31** (`d2d03da`, par l'ép. 9 du chantier clos `marionnet-automate-composants` — détail
  dans `docs/refonte-automate-composants.md` : master lock OCaml, gel d'appli — jamais un crash
  hôte).
- **pilotage par script** (piloter Marionnet par script — humain **et** agent — pour tester les
  modifications risquées : serveur de contrôle **in-process** sur socket unix
  [`Network.stream_unix_server ~no_fork:()` + `GMain_actor.apply` sur `st`], GUI restant vivante
  et observable ; requête = ligne texte, réponse = ligne **JSON** [aucune dépendance OCaml
  ajoutée] ; périmètre = noyau + les 4 treeviews) : `docs/pilotage-par-script.md` ; mémoire
  `marionnet-pilotage-par-script` ; `git log --grep="marionnet-pilotage-par-script"`. Ép. 0
  (conception), ép. 1 (audit intégral de `lib/STRUCTURES/network.ml` → § 7.5, **18 défauts**),
  ép. 2 + 2b (correctifs N2/N3/N11/N4/N5/N8/N13 puis **N1** dans `lib/` vendored, + `test/marionnet.ml`),
  ép. 2c (**fumée GUI concluante** : fd stables, 0 `EBADF`), **ép. 3a** (`bin/control_server.ml` :
  `--control-socket PATH`, commandes `status`/`ls`/`open`/`quit` en JSON, **N18 corrigé** — `SIGPIPE`
  neutralisé dans `bin/marionnet.ml`, sans quoi un client qui raccroche tue Marionnet **sans trace**)
  et **ép. 3c** (`bin/script_mode.ml` : les fenêtres que Marionnet ouvre **de lui-même** — splash,
  récapitulatif des adaptations d'un vieux projet, erreur de chargement — sont **capturées puis
  fermées** ; commande `notifications`, champ `notifications` dans la réponse d'`open`, options
  `--keep-dialogs` / `--dialog-timeout` ; § 4.9 de la doc)
  et **ép. 3b** (**C5 prouvé** en session réelle, sans clic humain grâce à `-r` : 0 descripteur du
  canal hors Marionnet sur 395 processus, xterm vivant ; témoin sans `~cloexec` = 351 fds hérités
  par 88 processus, dont 21 noyaux invités)
  et **ép. 4a** (**l'automate = contrat du script**, § 4.10 de la doc : le script a les mêmes
  possibilités et limites que la GUI ; table états × actions, règle « tester `can_*` avant →
  `forbidden_transition` », exception des **câbles** qui s'éditent/se suppriment en marche,
  commande `can` ; **décision** : `can_destroy`/`can_modify` descendent dans `user_level.ml`,
  lus par la GUI **et** le serveur)
  et **ép. 4b** (implémentation : les deux prédicats dans le modèle — surchargés `true` pour les
  câbles — lus par les `dynlist` des 8 composants et par le serveur ; commandes `can [<nom>]` et
  `ls --can=<action>` ; `poweroff`/`restart` par composant **gardés** et marqués `beyond_gui` ;
  prouvé par `can-bench.sh`, deux modes : réseau éteint puis réseau réellement démarré)
  et **ép. 4c** (le « canal muet » était un **interblocage de l'application** ; règle retenue :
  **le thread GTK ne prend jamais le mutex d'un composant** — les `can_*` de `user_level.ml` et
  `cable.ml` lisent `!state` **sans verrou**, ne pas « remettre proprement » un `with_mutex` ;
  puis les 11 commandes `start`/`stop`/`suspend`/`resume`/`restart`/`poweroff`, `*-all`,
  `wait`/`wait-all` — `accepted`, jamais « fait »)
  et **ép. 4d** (fin de la « jointure par espace » : chaque commande déclare son **arité**
  `(min, max, dernier libre ?)`, un surplus est refusé avec la syntaxe en clair — fondé sur le
  fait qu'un nom de composant est un **identifiant**, donc sans espace ; puis les 4 commandes de
  projet `new`/`save`/`save-as`/`close`, qui reproduisent la **séquence du menu**
  [`shutdown_everything` → *[save]* → `close_project`] avec `--save`/`--no-save` obligatoires si
  le projet est modifié [`unsaved_changes`] ; **piège** : `camlp4` ne connaît pas `let*`)
  et **ép. 4d-2a** (les composants : `add`/`del`/`get`/`set`, uniformes sur les 8 natures —
  `#to_tree` publie les champs, `#eval_forest_attribute` les écrit, le constructeur s'enregistre
  seul)
  et **ép. 4d-2b** (les **champs structurels** : `set … name`/`port_no` et `rename` par
  `#update_structural_with` — moitié structurelle des 8 `update_<kind>_with`, déclarée sur
  `node_with_ports_card`, surchargée machine/router ; un **câble ne se renomme pas** — la GUI le
  détruit et le recrée)
  et **ép. 4d-2c** (le **modèle refuse un nom avant d'écrire** : `User_level.check_new_name`
  — identifiant **et** libre — en 1ʳᵉ instruction des 5 chemins destructeurs ; le trou principal
  n'était pas le nom mal formé mais **l'homonyme**, `network#name_exists` n'étant lu que par
  `add_node`/`add_cable` ; GUI et serveur gardent leurs tests pour la **qualité du message**, c'est
  un filet, pas une source unique de vérité ; prouvé par un **banc témoin désarmé**)
  et **ép. 4d-3** (les **câbles** : `connect <câble> <nœud>:<port> <nœud>:<port> [--crossover]`,
  port **nommé** comme en GUI ; l'épisode a rétréci de 3 livrables à 1 — `disconnect` était un
  doublon de `suspend`/`del`, et **`forest` est suspendu** : `netmodel/network.xml` est du
  **Marshal binaire**, pas du XML, donc inécrivable par un script ; la garde « port libre » vit
  dans le serveur, pas dans le modèle)
  et **ép. 4e** (la **configuration de démarrage** : `rc-get`/`rc-set`, § 4.11 — le contenu voyage
  **en clair** et c'est le *serveur* qui marshale, le champ étant reconnu à sa **forme**
  [`(bool, string)` démarshalé en `Obj.t`] et non à son nom ; `component#hostfs_directory_if_any`
  ajoutée au modèle dit **où l'invité écrit** ; **bout en bout prouvé** : scénario posé par le
  canal, machine démarrée par le canal, journal de l'invité lu côté hôte)
  et **ép. 4f** (le **couple (distribution, noyau)** : le constructeur prend le **premier noyau
  déclaré par le filesystem** — comme le dialogue — au lieu du défaut *global*, si bien qu'`add`
  produit enfin une machine **démarrable** ; `set … kernel` hors `SUPPORTED_KERNELS` refusé,
  `set … distrib` **accepté** — la GUI l'interdit — et réalignant le noyau, rapporté dans un champ
  `adjusted` ; la garde reste dans le **serveur**, durcir `check_kernel` rendrait un `.mar`
  légitime non chargeable)
  et **ép. 4g** (décision, **aucun code** : `forest` **abandonné** — le forest et
  `add`/`set`/`connect` partagent leur source de vérité [`#to_tree`/`#eval_forest_attribute`], donc
  leur couverture ; `forest` n'aurait ajouté que le **lot**, au prix d'un registre `try_to_add_*`
  qui **avale les erreurs**. Corollaire : l'**ép. 7 est absorbé** — un décor se fabrique par le
  canal puis s'enregistre par **`save-as`**, le seul producteur légitime d'un `.mar` étant
  Marionnet ; « composer deux projets » part dans `docs/TODO.md`)
  et **ép. 4h** (le **signal « invité prêt »**, § 4.7 : le scénario écrit **atomiquement**
  `/mnt/hostfs/marionnet-guest-ready` et `wait <n> --ready` l'attend, rendant sa **première ligne** ;
  fraîcheur par **datation** contre `<hostfs>/boot_parameters` — réécrit à chaque construction de
  device — donc un marqueur du run précédent est ignoré, sans rien mémoriser ni ajouter d'effet de
  bord au `start` ; **piège durable** : tout fichier `marionnet-relay*` du hostfs est **sourcé** par
  l'invité, d'où le nom retenu ; l'inotify du hostfs qu'annonçait la doc n'existe pas — il porte sur
  `.X11-unix` seul)
  et **ép. 5a** (les **4 treeviews en lecture**, § 4.6 : `ifconfig [<n>]`, `defects [<n>]`,
  `history [<n>]`, `documents` — un verbe par treeview mais **une** implémentation, la forêt servie
  **comme une forêt** ; contrat dicté par trois faits du code — classes mères différentes [`Name`
  unique, non unique, absent], hiérarchies inégales [2 / 3 / arbre / plat] et surtout
  **populations différentes** : `ifconfig` ne reçoit que les composants **adressables**,
  `defects` reçoit tout **plus les câbles** ; `columns` dans l'ordre de la GUI via `#columns`, et
  non `#column_headers` qui n'est pas ordonné)
  et **ép. 5b** (l'**écriture d'`ifconfig`**, § 4.6 :
  `ifconfig-set <nœud> <port> <champ> [<valeur>] [--restart|--no-restart]`, un champ à la fois ;
  `#set_row_field` ne **valide rien** — tout vit dans le chemin GTK *cell-edited* —, d'où
  `#constraints_verdict` neuf dans `treeview.ml`, le verdict **sans dialogue**, les mêmes
  contrôles que la GUI ; la question modale « redémarrer maintenant ? » devient une **option
  exigée du script** ; vocabulaire écrivable dérivé de `#columns` via `#is_editable`, filtré
  **aussi** par `is_reserved` ; bout en bout : `simulation_level.ml:723-742` lit ce treeview à la
  construction du device, donc l'adresse posée par le canal atteint `boot_parameters`)
  et **ép. 5c** (l'**écriture de `defects`**, § 4.6 :
  `defects-set <nœud> <port> <direction> <champ>` **ou** `defects-set <câble> <direction> <champ>`
  — deux formes sous un verbe, tranchées par le **`Type` de la racine** et non par le nombre
  d'arguments ; la direction se désigne par son `Type`, le `Name` d'une direction de câble étant
  `to m1 (eth0)` — espaces compris ; **l'application est asymétrique parce que la GUI l'était** :
  un câble connecté est `suspend`+`resume` **sans aucune question** — donc le defect atteint
  `wirefilter` **à chaud**, par recréation du process — là où un nœud exige
  `--restart`/`--no-restart` ; les 3 effets du chemin GTK (réalignement min/max, surbrillance,
  avertissement) passent dans `#edit_side_effects`, appelée par la GUI **et** par le serveur)
  et **ép. 6** (le **client**, § 5 : `useful-scripts/marionnet-ctl` + symlink `mrnctl`, **versionné**
  — il ne connaît **aucune grammaire**, c'est le serveur qui publie son vocabulaire par la commande
  **`help`** [`arity_of_command` en JSON], si bien qu'un verbe ajouté est aussitôt utilisable et
  documenté ; 4 codes de retour, sortie **brute par défaut** [`--pretty`/`--query` en options],
  mode lot `-f`, et le délai de transport **calé seul** sur le `--timeout=N` de la requête ; pas de
  `bashbricks` — mesuré ~65 ms de sourcing par invocation, pour un client appelé des centaines de
  fois ; corollaire hors dépôt : `bench-lib.sh` retire le préambule recopié dans les 8 bancs,
  `can-bench.sh` servant de témoin [−100 l., 16 assertions identiques])
  et **ép. 5d** (`history` **par ses actions**, § 4.6 : l'intitulé « history/documents en écriture »
  était trompeur — une seule colonne éditable ici, quatre de métadonnées là ; la valeur était dans
  le **menu contextuel**, d'abord **« Start in this state »**, démarrer une machine depuis un état
  de disque **donné** ; `history-start`/`history-del [--except]`/`history-set … comment`,
  **identifiant = le fichier COW** [un `Name` désigne autant de lignes que la machine a d'états],
  que la lecture servait **déjà** ; `documents` hors périmètre, motivé)
  et **ép. 7** (la **garde d'`open`** : le faux négatif intermittent était une **course** —
  `Cortex` lance **un thread par commit** pour ses `on_commit` (`cortex.ml:307-312`), si bien que la
  réaction des `dotoptions` restaurées pouvait salir le projet **après**
  `register_state_after_save_or_open` ; correctif = **retirer les callbacks** pendant la
  restauration — jamais un drapeau, qui serait lu trop tard — via `Sketch.tuning`
  (`set_persistence_reaction` / `with_persistence_reaction_suspended`), la garde d'`open` restant
  inchangée ; **7/10 → 0/10** au banc `open-bench.sh`, sous `taskset -c 0`)
  et **ép. 8** (la **documentation utilisateur**, § 5.5 : `doc-src/scripting/README.md` +
  `examples/`, versionnés, **en anglais** — le guide dit la **forme** du canal et ses
  **invariants**, plus des recettes, mais **jamais la liste des verbes** : elle appartient à
  `mrnctl help` depuis l'ép. 6, et la recopier rétablirait la seconde source de vérité qu'on avait
  supprimée ; **anti-dérive = un banc**, les 4 exemples sont **exécutables** et joués tels quels
  par `doc-bench.sh` — dont le bout en bout invité ; premier run = **6 affirmations fausses**
  écrites de bonne foi après lecture du source, que la relecture n'aurait pas vues ;
  l'**installation** du guide *et* de `marionnet-ctl` est laissée au chantier
  `modernisation-installation-marionnet`)
  et **ép. 9** (**`useful-scripts/mrn-check`**, § 5.6 : vérifier un `.mrn` **sans rien envoyer**,
  le mode lot n'ayant pas de transaction ; **3ᵉ application de la règle d'unicité** — la grammaire
  est **demandée au serveur**, `--grammar=<instantané>` pour le hors-ligne, et c'est un **cache**,
  jamais une source ; au-delà de l'arité, le fichier est **rejoué contre un modèle construit à
  partir de lui-même** [noms, ports, occupation], **cru seulement** quand le fichier part d'un
  `new` — après un `open` les contrôles d'existence s'éteignent, un linter qui invente des erreurs
  se fait désactiver ; discriminant : **même ligne d'arrêt et même motif que `mrnctl -f`**)
  et **ép. 10** (la **complétion Bash**, § 5.7 : `useful-scripts/marionnet-completion.bash`,
  **dérivée** de `help` — 4ᵉ application de la règle d'unicité — mais dont le vrai gain est que
  les **noms** viennent de la **session vivante** [composants par `can`, ports par
  `defects <nœud>`, champs de `set` par les clés de `get`, états de disque par le `File name`] ;
  hors ligne par l'instantané de l'ép. 9 ; **3 ajouts au serveur, tous « publier ce qu'il savait
  déjà »** — `help` sans argument rend `kinds`/`actions`/`beyond_gui`, un treeview rend `slugs` ;
  **piège attrapé au banc** : `slugs` doit venir d'`editable_headers`, pas de `columns`, sans quoi
  la complétion propose des champs que le serveur refuse)
  et **ép. 11** (**`mrn2sh`**, § 5.8 : traduire un `.mrn` en `.sh` pilotant `mrnctl` —
  `mrn-check --to-bash` sous un second nom, parce que les **deux** raisons qui justifient l'outil
  pointent le vérificateur : le **quoting** de la queue libre [seule l'arité dit où elle commence ;
  un `sed` produit un script qui *redirige* au lieu de transmettre] et le contrôle comme
  **précondition** [un fichier fautif ne rend **aucun** script] ; le rendu **n'invente rien** —
  pas de `wait` ajouté — sauf le chemin de projet hissé en `${1:-…}`, et **seulement** si le
  fichier n'en nomme qu'un ; discriminant : **même réseau** que `mrnctl -f`)
  et **ép. 12** (les **sept configurations Quagga du routeur**, § 4.11.1 : `--field=zebra` et les
  deux autres réglages de l'onglet [`--select`/`--unselect`, `--terminal`/`--no-terminal`] — la
  moitié des « 8 variantes » que l'ép. 4e n'avait pas livrée ; les **clés sortent du champ
  lui-même** [liste d'associations reconnue par sa forme], le **défaut ne bouge pas** [sans
  `--field`, c'est toujours le rc UNIX : en faire des candidats implicites aurait cassé
  `rc-set r1 <contenu>`], et **poser un contenu active *et* sélectionne** — un service non
  sélectionné voit son `.conf` mis en `.backup` au boot, donc son démon ne démarre pas ;
  **entorse assumée** : les deux champs d'appartenance sont tous deux `string list`, donc
  **nommés**, sous deux gardes ; **aucun fichier du modèle touché** ; discriminant = **bout en
  bout** sur un routeur réellement démarré)
  faits → **les épisodes 3, 4 (a, b, c, d, d-2a, d-2b, d-2c, d-3, e, f, g, h), 5 (a, b, c, d), 6,
  7, 8, 9, 10, 11 et 12 sont clos** — le § 9 est **entièrement soldé**. La direction du § 10 — le
  scripting **descend dans les composants** — est **ouverte, démontrée et refermée** (l'invité rend
  la main au script ; l'ép. 12 en a soldé le dernier reliquat). **Plus aucun défaut connu ouvert**,
  et la condition posée à la clôture est **levée** : le chantier est **clôturable (MODE C)**, sur
  décision de l'auteur.
- **modernisation-installation-marionnet** (chantier PARENT : remplacer l'installeur mort
  `useful-scripts/marionnet_from_scratch` par une diffusion moderne — script v2, .deb + dépôt
  apt maison, RPM, Docker officiel [MarioNUM g3], binaires précompilés sur marionnet.org ;
  essaimera des chantiers enfants par canal) : `docs/modernisation-installation-marionnet.md` ;
  mémoire `modernisation-installation-marionnet` ;
  `git log --grep="modernisation-installation-marionnet"`. Ép. 0 (autopsie + officialisation)
  fait 2026-07-18.

## Où puiser

- **Récit d'architecture** (build, 2 niveaux, GUI, état, privilèges/taps, i18n, uml, ocamlbricks) :
  `docs/ARCHITECTURE.md` — lire la tranche pertinente, pas tout.
- **Chantiers clos** (archives durables, à consulter avant de rouvrir un sujet qu'ils couvrent) :
  `docs/refonte-automate-composants.md` (automate d'état des composants **et** discipline des
  appels Gtk+ hors thread principal — 16 épisodes, clos 2026-08-03 ; à lire avant de toucher
  `user_level.ml`, `treeview*.ml` ou de déléguer un appel GUI),
  `docs/migration-marshal-to-text.md` (**format de projet `v3` en JSON**, clos 2026-08-10 — un
  `.mar` écrit par ce binaire est du texte, la lecture `v0`/`v1`/`v2` est intacte ; § 17 = index
  des pièges, à lire avant de toucher `state.ml`, un codec JSON ou le chemin d'enregistrement ;
  note utilisateur : `doc-src/project-format-v3.md`), `docs/migration-ocaml5.md`
  (OCaml 5.4.1, clos 2026-07-27), `docs/finitions-port-dune.md` (clos 2026-07-18),
  `docs/daemon-elimination-study.md` (clos 2026-07-17).
- **TODOLIST transverse** : `docs/TODO.md` — améliorations repérées hors de tout chantier en cours
  (ce qui relève d'un chantier reste dans son doc, § « Reste au chantier »). Chaque entrée porte le
  constat, ce qu'on veut à la place, et l'obstacle d'implémentation déjà identifié.
- **Rôle d'un fichier** : `CLAUDE-file-overview.md` du dossier (`bin/`, `bin/gui/`).
- **Chantiers** (skills à charger en l'annonçant) : `marionnet-composants`, `marionnet-build`,
  `marionnet-gui`, `marionnet-pupisto` (`.claude/skills/`).
- **Preuve datée** : `docs/audit-marionnet-20260706.md` (rapport d'audit, immuable).
