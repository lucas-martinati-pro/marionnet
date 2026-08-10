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
- **migration-marshal-to-text** (les **8 fichiers de données d'un `.mar` sont des vidages
  `Marshal`** — dont `netmodel/network.xml`, qui n'est pas du XML ; format non auto-descriptif,
  donc fragile au changement de type [segfauts déjà évités par renommage, `state.ml:270-278`],
  inécrivable hors OCaml, non diffable. Cible : écrire une version de projet **`v3` en JSON**
  [`yojson`, **pas** `ocf`], **lecture `v0`/`v1`/`v2` intacte**, + conversion en lot) :
  `docs/migration-marshal-to-text.md` ; mémoire `migration-marshal-to-text` ;
  `git log --grep="migration-marshal-to-text"`. Ép. 0 (officialisation) fait 2026-08-09 ;
  **ép. 1 (le filet) fait le 2026-08-09** — corpus de 7 `.mar` de TP réels + 1 projet fabriqué par
  le canal, et banc `_claude-local/bench/marshal-bench.sh` **vert** (hors dépôt, comme les 8 bancs
  du chantier pilotage). Il mesure **un** invariant, indépendant du format : *ce que le canal dit
  d'un projet ne change pas au travers d'un cycle sauvegarde → relecture*. Trois faits mesurés en
  dictent la forme et valent pour quiconque touche au chemin d'enregistrement (§ 7.5 de la doc) :
  l'**ordre des nœuds s'inverse à chaque cycle** (période 2 — comparer UN cycle échoue sur du `v2`
  intact), **enregistrer aussitôt après l'ouverture** fige l'état transitoire de la restauration
  dans `dotoptions.marshal`, et `states/ifconfig-counters` **change à chaque enregistrement** sur
  les 4 octets d'un champ déclaré obsolète.
  **Ép. 2 (le codec du forest) fait le 2026-08-09**, § 8 de la doc — `Xforest.{to,of}_JSON_{string,file}`
  dans `lib/STRUCTURES/xforest.ml`, `yojson` **et `base64`** dans `lib/dune`, `test/xforest_json.ml`
  joué par `dune test` (`test/dune` passe de `test` à `tests`) : les tests **unitaires** sont
  **versionnés**, contrairement au banc de l'ép. 1 qui, lui, exige la GUI. **Rien n'est branché** :
  `state.ml` écrit toujours du `Marshal`. Le point durable est que **la mesure a corrigé la
  conception** — `yojson` 3.0.0 écrit les octets non-UTF-8 **verbatim** et les **relit à
  l'identique**, donc le repli base64 n'est pas une protection contre la perte de données mais la
  seule façon d'émettre du **JSON valide** ; corollaire : un banc bâti sur le seul aller-retour
  est **vert sur un codec cassé** (vérifié : repli désarmé → 7 assertions tombent, tous les
  round-trips passent). **Ép. 2b** : `lib/STRUCTURES/xforest.mli`, qui n'existait pas — les 16 noms
  de l'implémentation deviennent privés et **`yojson` n'apparaît dans aucune signature** ; surtout,
  l'écriture de l'interface a révélé que le banc vérifiait « sortie UTF-8 valide » avec **le
  prédicat même qui décide du repli** (circulaire), d'où un validateur indépendant dans le test et
  une **remesure** de la discriminance.
  **Ép. 3 (codecs des treeviews et des compteurs) fait le 2026-08-09**, § 9 de la doc : les
  **trois** schémas du § 4 sont désormais **figés et implémentés**, et **rien n'est toujours
  branché**. Deux décisions de structure, prises parce que le § 5 annonçait le codec « dans
  `bin/treeview.ml` » et que c'était intenable : (1) une stanza `(tests)` ne lie que des
  **bibliothèques**, donc la **donnée** d'un treeview (`Row`, `Row_item`) déménage dans
  `bin/treeview_row.ml` (biblio `marionnet_base`, sans Gtk+) avec son codec, les compteurs dans
  `bin/treeview_counters.ml` — `treeview.ml` garde les noms historiques par alias, **aucun des
  7 appelants** ne change, et déplacer un type de somme ne change **pas** son encodage `Marshal`
  (banc de l'ép. 1 rejoué : 41 assertions vertes sur 8 projets) ; (2) la plomberie JSON (validateur
  UTF-8, repli base64, `Malformed`, en-tête `format`/`version`, I/O) devient **un** module,
  `lib/STRUCTURES/json_bricks.ml{,i}`, sur lequel les trois codecs s'adossent — `yojson` apparaît
  dans **cette** interface, ce qui est assumé (`xforest.mli` n'en parle toujours pas). `dune test`
  = 134 assertions, 0 échec ; discriminance **remesurée** (repli désarmé → 5 assertions du nouveau
  banc tombent, tous les round-trips passent).
  **Ép. 4 (le branchement) fait le 2026-08-09**, § 10 de la doc : **tout `.mar` que Marionnet
  écrit est désormais du `v3`** — sept fichiers JSON plus `version`, lecture `v0`/`v1`/`v2`
  **intacte**. Le branchement lui-même n'a rien appris (le type `[ `v0|`v1|`v2|`v3 ]` a désigné à
  la compilation les 6 endroits qui décident) ; ce que l'épisode a tranché tient ailleurs :
  (1) **écrire le `v3` ne suffisait pas, il fallait effacer le `v2`** — un projet ouvert en `v2`
  garde ses anciens fichiers dans le répertoire de travail dont l'archive est faite, et un vieux
  binaire, ne comprenant pas `"v3"`, retombe sur **son propre repli de détection**, trouve
  `states/ifconfig` et ouvre l'état **d'avant**, sans un mot (d'où `legacy_data_files`, supprimés
  avant l'archivage, et une assertion **inverse** au banc) ; (2) l'**inversion d'ordre des nœuds
  est conservée** (décision de l'auteur : elle vient du modèle, pas du format → `docs/TODO.md`) ;
  (3) les attributs marshalés dans le forest sont **HUIT et non six** — `shuffler` et
  `invertedCables` de `dotoptions` (`sketch.ml:281,288`) s'ajoutent aux 6 du § 5, ce qui **corrige
  le périmètre de l'ép. 5** ; (4) l'**ép. 6 dépend de l'ép. 5, pas de l'ép. 4** — la valeur d'un
  `rc_config` reste marshalée *en mémoire*, seul son transport change, si bien que `rc-bench.sh`
  est vert **bout en bout** sans une ligne touchée au serveur. Preuve : banc de l'ép. 1 **vert
  (49 assertions)** sur les 8 projets, **112 fichiers JSON** relus en UTF-8 strict par `python3`
  (0 invalide), les 3 bancs du chantier pilotage qui inspectent le `.mar` rejoués verts.
  **Ép. 5 (la désimbrication) fait le 2026-08-10**, § 11 de la doc : **plus aucun attribut d'un
  `.mar` écrit par ce binaire n'est un vidage `Marshal`** — « tout scalaire, à plat », le routeur
  éclaté **par service**, et le **contenu** d'un rc parti dans un fichier `states/rc_config.XXXXXXXXX`
  (comme `states/document-XXXXXXXXX` de `treeview_documents.ml`) parce qu'un rc est un **script**,
  pas une valeur : en clair dans l'attribut, c'était un mur de texte échappé devenant un blob base64
  entier au premier octet non-UTF-8. La contrainte qui a dicté la conception n'est pas le format
  mais que **`#to_tree` ne peut pas faire d'I/O** — le serveur de contrôle l'appelle à chaque `get`,
  donc un fichier par requête ; d'où basename alloué sans I/O à la construction, écriture (et
  **balayage des orphelins**) dans `network#save_rc_files`, que `state.ml` appelle juste avant de
  sérialiser. L'enseignement est ailleurs : **le filet mesurait ces huit champs par `rc-get`**, que
  l'épisode rend muet — il serait donc resté **vert en cessant de regarder** (72 → 58 requêtes au
  dump, sans une assertion qui bronche). Deux assertions neuves hors canal, **corrigées deux fois
  par la mesure** : la plupart des `.mar` du corpus sont **antérieurs aux champs rc**, si bien que
  « ce qu'on écrit doit venir de l'original » est faux (les contenus viennent des **défauts du
  modèle** — ce que l'ép. 1 avait pris pour « 7 configurations Quagga renseignées » était ce que
  `rc-get` *affichait*), et une chaîne vide peut être la bonne réponse. Preuve : banc **65
  assertions, 0 échec** (49 avant), discriminance mesurée, `dune test` inchangé (134),
  `treeview-bench` vert, `components-bench` vert (134) après **retournement** d'une assertion — et
  **`rc-bench` rouge à dessein** (15), c'est la dette de l'ép. 6.
  **Ép. 6 (le réaccord du canal) fait le 2026-08-10**, § 12 de la doc : `rc-get`/`rc-set`
  reconnaissent leur champ à sa **paire de clés** (`<radical>_active` + `<radical>_file`, plus
  `_selected`/`_terminal` pour un rc **de service**) et non plus à l'en-tête magique de `Marshal`,
  si bien que **`bin/control_server.ml` ne contient plus un seul `Marshal` ni `Obj`** (~150 lignes
  d'inspection de forme en moins). La règle de l'ép. 4e survit — aucune liste de noms de champs,
  les radicaux sortent du forest — et un seul nom subsiste, le préfixe `quagga_`, retiré à la
  publication pour ne pas changer le vocabulaire `--field=zebra`. Le point dur était ailleurs : le
  **contenu** ayant quitté le forest, le lire dans `states/<basename>` serait **faux trois fois**
  (composant fraîchement ajouté, projet ouvert depuis un `v2`, entre deux enregistrements) — il
  transite donc par le modèle, `component#{rc_contents,set_rc_content}` sans I/O, dont
  `#save_rc_files`/`#rc_file_basenames` **dérivent** désormais. L'enseignement prolonge celui de
  l'ép. 5 : **le banc regardait au mauvais endroit** — deux assertions cherchaient le contenu dans
  `network.json`, où il n'est plus ; réparées en **suivant le lien**, avec pour vrai discriminant
  « aucune ligne du script dans `network.json` », plus une assertion périmée retournée
  (`omitted` vide) et un **défaut de banc** (une variable globale renseignée dans un sous-shell
  rendait un rapport qui ment). Preuve : `rc-bench` **104 assertions, 0 échec**, bout en bout
  compris (la conf ZEBRA posée par le canal est dans `/etc/quagga/zebra.conf` de l'invité) ;
  **discriminance mesurée** — écriture du contenu désarmée → **17 assertions tombent** ;
  `dune test` (134), `treeview-bench` et `components-bench` (134) inchangés.
  **Ép. 8a (la compat descendante, mesurée) fait le 2026-08-10**, § 13 de la doc, **aucun code de
  production** : le témoin n'est pas une simulation mais un **vrai binaire** (worktree git sur
  `a4055b1`, qui porte déjà le canal — donc pilotable par `mrnctl` sans un clic). Mis devant un
  `.mar` `v3`, il **refuse** (`internal`), reste **vivant**, ne montre **aucun composant**, son
  journal porte `project version cannot be identified` sans une trace de démarshalage, et le
  fichier est **intact**. Deux enseignements : (1) l'assertion statique de la première rédaction —
  « les deux archives ont des noms **disjoints** » — était **fausse**, les
  `hostfs/<n>/{boot_parameters,GUESTNAME}` étant recopiés d'un enregistrement à l'autre ;
  reformulée en « **aucun fichier commun n'est un vidage `Marshal`** » (en-tête magique), elle dit
  le danger *et* évite la liste de noms qui aurait fait une seconde source de vérité face à
  `marshal-bench.sh` ; (2) le **contrôle négatif** — un `.mar` **hybride**, le `v3` avec les
  fichiers `v2` remis — montre le vieux binaire **ouvrir** le projet, annoncer « Projet dans un
  ancien format » et **proposer de le convertir** : la perte de données que `legacy_data_files`
  (ép. 4) tenait à distance est **réelle**, et désormais mesurée. Preuve : **17 assertions,
  0 échec**, discriminance **6 assertions tombent**, `dune test` (134) inchangé.
  **Ép. 8b (le message) fait le 2026-08-10**, § 14 de la doc : le « Please ensure that the file be
  well-formed » servi à un fichier parfaitement formé mais plus récent est remplacé par **deux**
  messages, portés par une **exception dédiée** (`Unsupported_project_version of string option`)
  dont l'argument est le **tag brut** du fichier `version` — `Some "v4"` = projet du futur,
  `None` = rien d'identifiable ; les 4 chaînes neuves sont **sans format** (`s_`, jamais `f_`), le
  nom de fichier et le tag voyageant hors gettext, seule protection contre une traduction d'arité
  fausse (que `msgfmt -c` ne voit pas). Les 12 catalogues sont passés par le **pipeline officiel**,
  mesuré sans danger (`added=4 changed=0 removed=0` partout). Le point durable est ailleurs : la
  preuve prévue — rejouer les ouvertures **en français** — s'est révélée **impossible depuis
  `_build`**, `strace` montrant que le binaire ouvre `/usr/share/locale/fr/LC_MESSAGES/marionnet.mo`,
  le catalogue du Marionnet **installé**, et jamais celui du dépôt (2 correctifs essayés,
  **retirés faute d'effet mesuré** → `docs/TODO.md`) ; le banc prouve donc les 12 catalogues par
  `dgettext` et **mesure** le catalogue réellement ouvert au lieu de conclure. Preuve : banc
  **30 assertions, 0 échec**, discriminance **7 tombent**, `dune test` (134) et `backward-bench`
  (17) inchangés.
  **Prochaine étape = ép. 9** (documentation et clôture).
  *(Ép. 7 `mar2v3` abandonné : 3 lignes de `mrnctl`.)*

## Où puiser

- **Récit d'architecture** (build, 2 niveaux, GUI, état, privilèges/taps, i18n, uml, ocamlbricks) :
  `docs/ARCHITECTURE.md` — lire la tranche pertinente, pas tout.
- **Chantiers clos** (archives durables, à consulter avant de rouvrir un sujet qu'ils couvrent) :
  `docs/refonte-automate-composants.md` (automate d'état des composants **et** discipline des
  appels Gtk+ hors thread principal — 16 épisodes, clos 2026-08-03 ; à lire avant de toucher
  `user_level.ml`, `treeview*.ml` ou de déléguer un appel GUI), `docs/migration-ocaml5.md`
  (OCaml 5.4.1, clos 2026-07-27), `docs/finitions-port-dune.md` (clos 2026-07-18),
  `docs/daemon-elimination-study.md` (clos 2026-07-17).
- **TODOLIST transverse** : `docs/TODO.md` — améliorations repérées hors de tout chantier en cours
  (ce qui relève d'un chantier reste dans son doc, § « Reste au chantier »). Chaque entrée porte le
  constat, ce qu'on veut à la place, et l'obstacle d'implémentation déjà identifié.
- **Rôle d'un fichier** : `CLAUDE-file-overview.md` du dossier (`bin/`, `bin/gui/`).
- **Chantiers** (skills à charger en l'annonçant) : `marionnet-composants`, `marionnet-build`,
  `marionnet-gui`, `marionnet-pupisto` (`.claude/skills/`).
- **Preuve datée** : `docs/audit-marionnet-20260706.md` (rapport d'audit, immuable).
