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

- **Mais `dune build` n'est PAS un typecheck du projet** : pour un exécutable, dune ne compile
  que la clôture atteignable depuis `marionnet.ml`. Un module mort peut donc être cassé sans que
  le build s'en aperçoive (c'est arrivé : cf. `d265946`). `make check` (`dune build @check`)
  compile *tous* les modules ; il conditionne `make ocaml-index` — donc les *references* exactes
  d'`ocamllsp` — et `make module-graph` / `make module-graph-check`, qui produisent le graphe de
  dépendances inter-modules. Mode d'emploi : skill global `ocaml-code-graph`.

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
  (`gettext-messages-pot`, `gettext-update-po`). **RPM** : `RPMS/` (specs de 2009) a été
  **supprimé** à l'épisode 17 de `modernisation-installation-marionnet` — code mort, aucune
  cible ne l'appelait ; le canal vit désormais dans `Makefile.d/release.rpm.sh`.

## Cartographie

| Où | Quoi | Détail |
|---|---|---|
| `bin/` | cœur applicatif (40 .ml) : modèle réseau à 2 niveaux + composants + Tap_provider | `bin/CLAUDE.md` |
| `bin/gui/` | complétion GTK (foncteurs `Make(State)`), glade | `bin/gui/CLAUDE.md` |
| `bin/scripts/` | scripts **complémentaires du binaire** : portes privilégiées, scripts déposés dans les invités, clients du canal (`.sh` réels + liens qui portent les noms d'usage), complétion bash, **et `marionnet-install.sh`** — qui est *aussi* le chooser d'images `marionnet-get-images` (ép. 16) | `docs/move-and-rename-useful-scripts-to-bin-scripts.md` |
| `lib/` | **ocamlbricks vendored** (bibliothèque support OCaml, 12 sous-dossiers) | `lib/CLAUDE.md` |
| `bashbricks/` | **bashbricks vendored** (bibliothèque Bash sourcée, mono-fichier) | `bashbricks/CLAUDE.md` |
| `uml/` | construction des systèmes invités (scripts pupisto, patches noyau, ethghost) | `uml/CLAUDE.md` |
| `doc-src/` | sources de documentation | — |
| `useful-scripts/` | scripts de **gestion / installation du projet** et guides développeurs — **rien qui accompagne le binaire** (liste blanche du `.gitignore`, le reste ignoré). Depuis l'ép. 16 de `modernisation-installation-marionnet`, il n'y reste que `marionnet_from_scratch` (mort) et `make_marionnet_bytecode_revno` | `docs/move-and-rename-useful-scripts-to-bin-scripts.md` |
| `etc/`, `Makefile.d/`, `CONFIGME*`, `META` | config hôte, outillage build historique, packaging (dont les 6 publieurs de release : images, noyaux, binaire, `.deb`+apt, `.rpm`) | `docs/ARCHITECTURE.md` § Build |

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
  `.mli` **sélectifs**, jamais systématiques. Critère **mesuré** (2026-08-10) : un `.mli` se
  justifie quand la **surface externe est petite devant l'implémentation** *et* que le module
  **ne publie pas de type de classe** — un `.mli` sur du code objet exige la transcription
  intégrale des méthodes (`user_level.mli` = 806 l. pour 2312, à maintenir en double), et un
  `.mli` « transparent » qui recopie tout n'apporte que de la doc à faire vieillir. Donc :
  oui aux modules « bibliothèque » et aux modules à point d'entrée unique (`control_server.mli`
  = **1 `val` pour 3541 lignes**) ; non aux 12 modules porteurs de classes (`treeview`, `state`,
  les 8 composants, les 4 `treeview_*`), aux écrans `bin/gui/`, aux modules d'exécutable
  (`marionnet.ml`, `initialization.ml`) et à `marionnet_log.ml` (`include` d'un foncteur).
  Quand un `.mli` est écrit, la doc d'**interface** y **déménage** (source unique) ; le `.ml`
  ne garde que les notes d'implémentation.
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
6. **Aucun enfant n'est forké « en direct ».** Le seul site de spawn du dépôt vit dans
   `bin/simulation_level.ml` et passe par un **thread spawner dédié et pérenne**, qui appelle
   `UnixExtra.create_process ~pdeathsig:`KILL` (ocamlbricks, `lib/EXTRA/unixExtra.ml` — c'est
   là qu'est le préfixe `setpriv --pdeathsig` et la sonde qui décide s'il est utilisable) :
   c'est ce qui empêche les auxiliaires
   (`vde_switch`, `wirefilter`, UML, xterm) de survivre à un Marionnet tué brutalement. Deux
   choses à ne pas défaire : le signal de mort du parent est relatif au **thread** qui a forké
   (d'où le thread pérenne — les composants démarrent depuis des threads éphémères de
   `Task_runner.do_in_parallel`), et il n'atteint que les enfants **directs** (les
   petits-enfants restent à la charge de `bin/scripts/marionnet-cleanup.sh`).
7. **dune ne voit pas à travers camlp4** : un fichier embarqué dans un `.ml` par `INCLUDE_AS_STRING`
   (les scripts de `bin/scripts/`) n'est une dépendance que s'il figure dans les
   `preprocessor_deps` de `bin/dune`. Sans cela, éditer le script laisse le binaire porter
   **silencieusement** la version précédente.

## Chantiers longs (work-streams)

Reprise : appliquer le skill `chantier-long`.
- **camlp4 → ppx** (sortir des 7 extensions camlp4 ; crux = `where_p4`) :
  `docs/camlp4-to-ppx.md` ; mémoire `marionnet-camlp4-ppx` ;
  `git log --grep="marionnet-camlp4-ppx"`. **NON entamé**, **priorité fortement abaissée** :
  ses deux justifications sont tombées (gel 4.13.1 levé, Merlin/LSP restauré — cf. § Build).
  Reste la dette de fond : dépendre d'un préprocesseur mort.
- **noyaux + rootfs** (intégration Dave Appadoo ; Trixie + UML 6.12 ; touche `uml/` **et** l'OCaml
  via un dispatch de boot compat SysV/systemd) : `docs/kernel-rootfs-refresh.md` ;
  mémoire `marionnet-kernel-rootfs` ; `git log --grep="marionnet-kernel-rootfs"`. **Bloque vwifi.**
  **Ép. 21 : le boot ne se terminait pas quand le prompt paraissait.** Sur l'image publiée
  `machine-debian-trixie-39212`, les `[OK]` tombaient **après** `m1 login:` : `systemd-analyze
  blame` = **`2min 956ms systemd-networkd-wait-online.service`** pour un `multi-user.target`
  atteint à 26,7 s. Cause **datée à la minute** dans l'image (`debugfs`) : un `systemctl enable
  systemd-networkd` de la session de réglage du 23-Aug a **traîné le guetteur** avec lui
  (`Also=` dans l'unité Debian) — le passage à networkd, lui, était voulu
  (`10-eth0.network`, `DHCP=yes`), donc **seul le guetteur s'en va**. **À ne pas défaire** :
  (1) `bin/simulation_level.ml` masque l'unité à la **ligne de commande noyau** de tout invité
  systemd — donc y compris sur les images **déjà publiées** — placé **hors** de la branche du
  masque `serial-getty` (conditionnée à l'enregistrement des consoles) et **hors** de
  `boot_quirks` (indexé par série de noyau, alors que ce défaut n'en dépend pas), et **rien**
  sous SysV (un argument inconnu partirait en argument à `init`) ; (2)
  `filesystem.prepare-snapshot-to-publish.sh` **refuse** de publier un instantané qui active une
  telle unité et **nomme le remède** (`--allow-slow-boot` pour le cas délibéré, `--check-image`
  pour interroger une image publiée) — la question est posée par **`debugfs`**, donc sans
  privilège et même sous `--do-not-update-binary-list`, et un `debugfs` absent **avertit** au
  lieu de condamner. Mesuré sur l'image et le noyau **publiés** : `is-enabled` →
  `masked-runtime`, **0** occurrence de l'unité dans le `boot.log`, boot en **~9 s**, plus rien
  après le prompt ; publieur : refus sur trixie, accepté sur guignol et wheezy. **Versé au
  TODO** : `add machine` **par le canal** ignore `MEMORY_SUGGESTED_SIZE` (48 Mio par défaut ⇒
  trixie **meurt d'OOM**, mesuré), et `marionnet-relay.service` coûte **16,5 s** au boot.
  **Ép. 21 bis : l'image propre est fabriquée, et le garde-fou a dû apprendre le masque.**
  `systemctl mask` ne retire **pas** le lien d'activation, donc le garde-fou aurait refusé une
  image réparée par son propre conseil : il accepte désormais **les deux** issues (lien retiré,
  ou unité masquée — `Fast link dest: "/dev/null"`). L'image a été produite en pilotant
  Marionnet (masque par `exec`, arrêt propre, export de variante par la commande **exacte** de
  la GUI) : **`machine-debian-trixie-16341`** + `.conf` + `.tar.xz` déposés dans le répertoire
  de release, `SHA256SUMS` à jour, `sum` = nom, `mtime` = `MTIME`, garde-fou **rc 0** contre
  **rc 2** sur l'ancienne, boot réel sans une seule occurrence de l'unité. **Rien n'est mis en
  ligne** : publication et rétention restent à l'auteur.
  **Ép. 22 : `history-export`, le dernier geste du menu des états.** Le canal savait tout jouer
  d'une mise à jour d'image **sauf** l'export de variante (fait au `cp` à l'ép. 21 bis) : il
  gagne `history-export <cow file> <variant name> [--force]`, dans la **famille `history-*`**
  (même identifiant — le nom du COW —, même prologue `history_row_of_cow`). **À ne pas
  défaire** : (1) la mécanique vit **une seule fois**, dans
  `Treeview_history#export_row_as_variant`, que le dialogue GUI **et** le canal appellent —
  dont `cp --sparse=always` (mesuré : **2,6 Mio réels pour 5,1 Gio apparents**) ; (2) les gardes
  sont celles **de la GUI** (`can_startup` : le COW d'une machine allumée est un système de
  fichiers non démonté ; `identifierp ~allow_dash:()` pour le nom) ; (3) **une** divergence
  voulue — le dialogue écrase une variante homonyme sans un mot, le canal **refuse** sauf
  `--force`, le chemin GUI passant `~force:true` pour rester **inchangé**. **Piège de mesure** :
  un état n'est pas la racine de `history <nom>` — la racine est la machine, les états sont ses
  `children` (c'est ce que dit déjà l'erreur du dialogue : *« you should expand the tree »*).
  **Ép. 23 : `Makefile.d/filesystem.update-published-image.sh`** — mettre à jour une image
  publiée devient **une commande** (`--image … --in-guest 'CMD'`), et les **six pièges** de
  l'ép. 21 bis deviennent du code : liens de visibilité dans `~/.marionnet/` (le binaire de
  `_build` lit le préfixe *testing*) **noyaux compris** (`Disk` filtre une distribution sans
  noyau installé), mémoire lue dans le `.conf` (les 48 Mio du canal tuent une trixie), export
  par `history-export` (donc **aucun `cp`**), arrêt **gracieux** avant l'export. **À ne pas
  défaire** : une commande d'invité qui échoue **arrête avant l'export** ; une image `router-*`
  est refusée (c'est un lien) ; rien n'est mis **en ligne**. **7ᵉ piège, trouvé par le banc et
  corrigé à sa source** : `add … --distrib=X` construit avec le filesystem **par défaut** puis
  applique le champ, et `set_epithet` ne mettait pas à jour la ligne d'historique — champ
  **fonctionnel**, qui dit où va une variante (mesuré : la variante d'un guignol partait chez
  trixie). `set_epithet` appelle désormais `redirect_history_rows_to_distrib`, **avec la garde
  du chemin d'import** (aucun état COW). Banc **sur guignol** (12 Mio, ~1 min) : chaîne complète
  `18474` → **`03149`**, marque présente dans la neuve et absente de l'ancienne, et
  `--in-guest 'false'` sort en **rc 2 sans créer de variante**.
  **Ép. 24 : la mémoire que l'image réclame.** `add machine` donnait **48 Mio** sans jamais lire
  `MEMORY_SUGGESTED_SIZE` (192 trixie / 24 guignol), que seul le dialogue GUI appliquait — d'où
  l'OOM de l'ép. 21. `cmd_add` gagne `adjust_memory_to_distrib`, **jumeau** de
  `adjust_kernel_after_distrib_change` (même endroit, même raison : « que `add` seul rende un
  composant *bootable* »), et `editable` gagne le **4ᵉ** accesseur en lecture seule de la famille,
  `memory_suggested_size_if_any`. **À ne pas défaire** : `--memory=N` gagne toujours (une valeur
  explicite est une intention) ; `set <n> distrib` n'ajuste **pas** la mémoire (la GUI le fait,
  mais un script qui a écrit `set m1 memory 512` ne doit pas se le faire effacer) ; un `.mar` reste
  souverain. Mesuré : 24 / 192 / 64 / 192, **48 partout** sur le code d'avant.
  **Ép. 25 (mesure seule) : les ~7 s du relais.** 7,264 s avec `--debug`, **6,899 s sans**, pour
  `multi-user.target` à 11,0 s. **Ce n'est pas la trace** (324 lignes contre 45, même durée), aucun
  geste ne bloque seul, et **1,30 s** sont un `daemon-reload`. La suite est instrumentale
  (`PS4`/`$EPOCHREALTIME`) : entrée `docs/TODO.md` **réécrite avec les chiffres**, plus « cause
  inconnue ».
  **Ép. 26 : le relais se date à la microseconde.** `PS4` porte `$EPOCHREALTIME` (le prompt étant
  imprimé **avant** la commande, l'écart entre deux lignes **est** son coût), aux **deux**
  endroits qui tracent — car le prologue de journal déposé par Marionnet n'a daté que **6 lignes
  sur 325** (il n'est sourcé qu'en fin de relais), l'essentiel venant du `set -x` que le relais
  active **dans l'image**. Garde : `$EPOCHREALTIME` est **bash ≥ 5.0**, choix fait **une fois** à
  la pose du `PS4` (wheezy = 4.2). **Mesuré** : 314 lignes datées, 4,55 s — **1,633 s** dans le
  bloc non tracé de `00-journal:311` (dont **1,30 s** de `systemctl daemon-reload`), **~1,02 s**
  en **huit** `systemctl stop getty@tty$i` **un par un**, le reste à ~5 ms par commande. La mesure
  a été prise dans un **COW jetable** (le relais vit dans l'image) : rien de produit, rien de
  publié. Correctifs **non faits**, chiffrés dans `docs/TODO.md` avec leurs contreparties.
  **Ép. 28 : le prompt de login est la dernière ligne de la console.** Signalé de la salle
  MarioNUM et **survivant aux ép. 21/26/27** — parce que ce n'est pas une affaire de **durée**
  mais d'**ordonnancement** : `getty@tty0` est activé dans `getty.target.wants` et n'a **aucun**
  ordre contre `multi-user.target` ni contre nos unités (mesuré sur l'image publiée `16341` :
  getty à **4,73 s**, `multi-user.target` à **10,93 s** — une fenêtre de **6,2 s** qu'aucun
  raccourcissement ne ferme). Correctif **entièrement sur l'hôte**, donc valable pour les images
  **déjà publiées** : `systemd.mask=getty.target` sur la ligne de commande noyau
  (`bin/simulation_level.ml`, à côté du masque de l'ép. 21) et démarrage du prompt **après** la
  transaction par l'épilogue du relais (`marionnet-relay.zz-journal.sh`,
  `systemd-run --no-block` qui attend `systemctl is-system-running --wait`). **À ne pas
  défaire** : (1) on masque la **target**, jamais l'instance — une target masquée ne tire plus
  rien mais l'unité reste **démarrable**, là où `systemd.mask=` sur l'instance passe par
  `/run/systemd/generator.early`, que `systemctl unmask` ne défait pas ; (2) `systemd-run`
  (unité **transitoire**) et non une unité écrite dans `/run` comme le guetteur juste au-dessus,
  parce qu'elle **ne coûte pas de `daemon-reload`** — le poste à 1,30 s de l'ép. 26 ; (3) le
  **repli** est le point : sans `systemd-run`, sans D-Bus, sur un refus, le prompt part
  immédiatement (le symptôme d'avant, **jamais** l'absence de login), et le `timeout 120` dit la
  même chose de l'attente ; (4) le relais est intact — ses `start getty@tty1..N-1` nomment les
  **instances**. **Piège durable, payé par la mesure** : le correctif « évident » — un drop-in
  `getty@tty0.service.d` disant `After=multi-user.target graphical.target`, gravé dans
  `pupisto.debian.sh` — a été écrit, joué **et jeté** : il fait un **cycle**
  (*« Found ordering cycle on getty.target/start »*, *« Job getty.target/start deleted to break
  ordering cycle »*), et le prompt ne tombait en dernier que **parce que systemd venait
  d'effacer un job en silence**. D'où **un seul mécanisme, sur l'hôte** — et donc **rien à
  graver, rien à reconstruire, rien à republier**. Mesuré : prompt **10,95 → 11,13 s** contre un
  `graphical.target` à 10,71-10,96 s, `getty.target` **masked**, `getty@tty0` **active**,
  **aucun** cycle (`NONE`), `make check` rc 0. **Reste** : `console_no > 1` garde le symptôme
  (les consoles 1..N-1 sont démarrées par le relais, tôt).
- **triage des binaires d'une image invitée** (chantier **enfant** du précédent : une image
  publiée ne doit contenir que des binaires qui **fonctionnent**, et le constat doit se refaire
  sur n'importe quelle image **sans rouvrir de chantier**) :
  `docs/triage-binaires-image-invitee.md` ; mémoire `triage-binaires-image-invitee` ;
  `git log --grep="triage-binaires-image-invitee"`. Né d'un constat en salle (`xlinks2` →
  `BadMatch X_CreateWindow` sur trixie 16341, quand `xeyes` et `wireshark` marchent). **Ép. 0
  fait** (conception seule) : **3 étages** — un script **sonde** (un boot, toutes les sondes ;
  `ldd` décide si c'est une application X, jamais une liste), un agent **décide une fois**, un
  script **applique** — et les verdicts sont **gelés** dans une politique versionnée
  (`keep`/`fix`/`drop`/`ignore`) que consomment **et** le respin **et** `pupisto`. **À ne pas
  défaire** : l'agent est *entre* la sonde et la politique, **jamais dans la boucle** (sinon
  chaque passage coûte des tokens et peut décider autrement) ; **une sonde ne publie jamais**
  (COW jetable — le nom d'une image *est* son `sum`) ; `/loop` est refusé (un boot par
  itération). Livrable de clôture : **`make` pour la mécanique, un skill pour le jugement et le
  rituel** — pas un skill coordinateur (motif : l'ép. 26 de
  `modernisation-installation-marionnet`).
  **Ép. 1 : l'étage 1 existe et a tourné** — `Makefile.d/filesystem.probe-image-binaries.sh`
  (6ᵉ de la famille, rien de sourcé) et le premier rapport, **2060 candidats en un boot**
  (`OK` 1834, `ERR` 142, `X_ALIVE` 40, `X_DIED` 33, `TIMEOUT` 8, `MISSING` 3) — donc **186 cas,
  9 %**, pour l'étage 2 : la décision « l'agent ne voit que les échecs » est chiffrée.
  **Quatre suppositions de l'ép. 0 démenties par la mesure** : (1) le crux — `exec` livre un
  environnement **nu** (`PATH` seul, guetteur sous une unité systemd sans `Environment=`), mais
  le relais a écrit `DISPLAY` dans `/etc/profile`, qu'un shell non interactif ne lit pas : un
  `. /etc/profile` suffit, le dépôt hostfs n'est pas requis **pour l'écran** ; (2) `ldd` est
  **faux** — `xlinks2` est un `#!/bin/sh` faisant `exec links2 -g`, donc classé *non-X*, et
  **417 des 2057 candidats ne sont pas des ELF** — **et trop lent** (catalogue non fini en
  300 s), d'où `grep -a libX11` sur le fichier **plus un saut** à travers le wrapper ; (3) le
  canal ne peut pas porter la boucle (~1 s l'aller-retour ⇒ ~35 min de pure attente), d'où
  **un** script déposé, lancé en arrière-plan, et un rapport que l'hôte **regarde grandir** —
  écrit **ligne à ligne**, si bien qu'un binaire qui tue l'invité est *nommé* ; (4) **le
  symptôme fondateur ne se reproduit pas** — `xlinks2` est `X_ALIVE` ici, le serveur X local
  offrant 7 profondeurs : la cause est le **relais X de l'hôte**, que le § 6 met hors
  périmètre. **À ne pas défaire** : *un verdict X est une propriété du couple (image, serveur
  X)* — l'en-tête du rapport **nomme le serveur** ; et la garde contre une sonde qui *fait
  agir* un binaire (mesuré : `tgz` écrit `--help.tgz`) n'est pas une liste de dangereux — elle
  se périmerait — c'est le **COW jetable**. **2 défauts de la sonde trouvés en lisant son
  propre rapport** (famille « juger par autre chose que ce qu'on mesure ») : `X_DIED` à **rc
  0** — **15** morts imaginaires, `xdpyinfo`/`xauth`/`appres`/`xclip`… ayant fait leur travail —
  d'où 3 issues (`X_ALIVE`/`X_OK`/`X_DIED`) ; et un garde-fou **comptant les lignes écrites**,
  qui a arrêté à **6** candidats une sonde `--x-only` qui marchait (elle n'écrit rien pour ce
  qu'elle saute) — le guest compte désormais les **candidats**. **Discriminance mesurée** en
  rejouant `--x-only` : **15 bascules `X_DIED` → `X_OK`**, seules lignes qui changent entre les
  2 rapports, et **2059** candidats traversés contre 6. **Reste ouvert** : le faux négatif du
  classificateur sur les applications liant X **indirectement** (`wireshark` via Qt), les
  2 issues évidentes étant fermées (une liste se périme ; `ldd` transitif est trop lent).
- **vwifi** (OCaml, BLOQUÉ par le kernel) : `docs/vwifi-integration.md` ; mémoire `marionnet-vwifi` ;
  `git log --grep="marionnet-vwifi"`. Analyse commune : `docs/analyse-dave-appadoo-20260708.md`.
- **rétro-compat vieux couples kernel/image** (wheezy/guignol/mandriva, userlands i386, morts
  avec `linux-3.2.64-ghost` sur hôte ≥ 6.x ; solution démontrée = UML récent `SUBARCH=i386`) :
  `docs/retro-compatibilite-kernels-images.md` ; mémoire `marionnet-retro-compat-kernels-images` ;
  `git log --grep="marionnet-retro-compat-kernels-images"`. Ép. 0→4 faits 2026-07-17
  (ép. 4 : abandon mandriva/pinocchio/lenny + remap auto kernel/distrib au chargement `.mar`).
- **modernisation-world-bridge** (rendre l'accès au vrai réseau utilisable sans config hôte
  manuelle risquée **et** compréhensible en GUI ; **objectif révisé à l'ép. 4** : le mode n'est
  plus un réglage mais **un choix de composant** — menu planète à 3 entrées *Gateway* /
  *NAT bridge* / *LAN bridge*, deux natures distinctes, privilèges sudo en 3 blocs demandés au
  moment où ils servent) : `docs/modernisation-world-bridge.md` (**§ 1 bis = l'objectif final,
  il prime sur les § 2-4 dès qu'il s'agit du « mode »** ; § 4 = découpage) ; mémoire
  `modernisation-world-bridge` ; `git log --grep="modernisation-world-bridge"`.
  Ép. 0→8 faits (**épisode 7 complet**) : le NAT auto est prouvé, le sudoers est en 3 blocs
  demandés au bon moment, la **9ᵉ nature `nat_bridge` existe** (menu planète à 3 entrées), le
  **LAN bridge est automatique de bout en bout** — `bin/lan_bridge.ml` (ex-`world_bridge.ml`,
  identité interne inchangée) appelle `bin/lan_bridge_host.ml` →
  `bin/scripts/marionnet-lanbridge.sh` (`mnlan0` partagé) — et le « mode » a **disparu du
  code** (ép. 7c) : plus de `MARIONNET_WORLD_BRIDGE_MODE` ni de `Global_options.world_bridge_mode`,
  `MARIONNET_BRIDGE` n'étant plus qu'une **surcharge** explicite, dont
  `check_bridge_existence_and_warning` (test par `/sys/class/net/<nom>/bridge`, plus par
  `brctl`) ne signale plus que le cas « surcharge pointant dans le vide ».
  **Ép. 10 COMPLET** — *le NAT bridge se configure comme la passerelle* (§ 4.5 du doc), en
  trois temps : **10a adresse IPv4**, **10b ports du commutateur intégré** (N ports
  `port1…portN`, tronc `bridge_common` paramétré et devenu un vrai switch), **10c service
  DHCP** — **10c.1 côté hôte** (`--dhcp` de `marionnet-natbridge.sh`, dnsmasq lié au seul
  bridge ; **dépendance hôte neuve `dnsmasq-base`**) et **10c.2 côté modèle** (case
  « DHCP service » du dialogue, `dhcp_enabled` dans le `.mar` et le canal, `?dhcp` sur
  `Nat_bridge_host.up`/`ensure` ; défaut **`true` même pour un `.mar` antérieur**, sans repli
  quand dnsmasq manque). **Piège durable établi à cette occasion** : une
  règle sudoers **ne peut pas** scoper une commande à arguments variables (un `*` d'argument
  avale des mots entiers, injection mesurée) — d'où `bin/scripts/marionnet-dnsmasq.sh`, porte
  privilégiée minuscule qui **valide ses arguments en root**, et n'est accordée que si elle est
  root-owned sur toute sa chaîne.
  **Ép. 11 FAIT** — *l'autoconfiguration IPv6* (§ 4.6 du doc) : le NAT bridge donne aussi une
  **adresse IPv6** (ULA `/64` **dérivé du /24**, `/64` imposé par SLAAC) et un **service RADVD**
  — les RA sont émis par le **dnsmasq déjà lancé** (`--enable-ra`, `ra-only`), donc **pas de
  radvd** — plus la traversée **NAT66**. Deux pièges durables établis ici : (1) le forwarding
  IPv6 n'est **pas** per-interface, il fait de tout l'hôte un routeur, et un routeur **ignore les
  RA reçus** → sans `accept_ra=2` l'hôte perd sa propre route v6 *minutes plus tard*, d'où la
  **3ᵉ porte privilégiée `bin/scripts/marionnet-ipv6.sh`, à ZÉRO argument** (règle sudoers
  **entièrement littérale**, plus aucun glob à détourner) qui mémorise et restitue les valeurs ;
  (2) dans sudoers, un **`:` non échappé ne casse pas le fichier, il change ce qu'il accorde**
  (mesuré). Tout l'IPv6 est **conditionné à un uplink v6** (`check-ipv6`, non privilégié) : sans
  lui, support **sauté** (`E_NO_IPV6_UPLINK`) et champs **grisés** — asymétrie assumée avec
  l'ép. 10c.2, le DHCP étant actif par défaut là où l'IPv6 est *opt-in*.
  **Ép. 12 FAIT** — *le commutateur intégré du LAN bridge* (§ 4.7 du doc) : le LAN bridge passe
  lui aussi à N ports (4/1/16), les cinq constantes de port vivant désormais dans
  `bin/bridge_common.ml` pour les deux natures. **Piège durable établi ici** : le nom d'un port
  n'est pas un libellé — un câble nomme son réceptacle dans le `.mar` et l'import **avale**
  l'échec de résolution, donc renommer `eth0` en `port1` aurait fait disparaître **en silence**
  les câbles des projets antérieurs ; d'où un **repli** vers l'ancienne convention dans
  `ports_card#port_of_user_port_name` (`bin/user_level.ml`, tenté seulement après l'échec exact,
  et jamais écrit : le projet migre en étant enregistré) et un **renommage par position** des
  lignes de défauts (`Treeview_defects#change_port_naming`, déclenché par l'**absence** de
  l'attribut `port_no`, patron de `hub.ml`).
  **Ép. 9 — l'i18n ×12, le dernier, en deux temps** (gardé pour la fin afin de ne pas traduire
  deux fois) : le refresh POT donne **423 `msgid`** et **43 trous par catalogue**, dont **2 seuls
  textes d'aide pèsent 5 956 caractères**. **9a FAIT** (§ 4.8 du doc) — les **41** chaînes courtes
  traduites dans les 12 langues, terminologie figée d'abord (`NAT`/`LAN` restent des sigles, seul
  le nom commun suit l'habitude de chaque catalogue), versées par **`msgmerge --compendium`**.
  **Piège durable établi ici** : le corps des dialogues `Simple_dialogs.error/warning/info/help`
  est un label **Pango markup** — `use-markup` est posé sur `content` dans
  `bin/gui/gui_glade3.xml`, **pas** dans `simple_dialogs.ml` où seul le *titre* reçoit un
  `set_use_markup` explicite — donc tout `<mot>` d'un `msgid` **ou** d'une traduction casse le
  parsing du message entier, et toute valeur venue de l'utilisateur doit passer par
  `Glib.Markup.escape_text` (les **tooltips**, eux, sont du texte brut : `Tooltip.set_text`).
  C'est ce qui a fait corriger `bin/nat_bridge.ml:244` en même temps.
  **Ép. 9b FAIT** (§ 4.9 du doc) — les 2 textes d'aide (5 927 car.) traduits ×12, **aucun `.ml`
  touché, aucun cycle POT** : les 12 catalogues passent à **422 traduits, 0 trou**, donc
  l'invariant « on ne supporte que des catalogues complets » est **rétabli**. Labels de puces
  repris **mot pour mot** des libellés du dialogue (un texte d'aide qui ne nomme pas les champs
  comme eux désigne autre chose) ; versement `msgmerge --compendium` validé par un essai à blanc
  (diff vide) ; audit d'arité **sur les 12 catalogues entiers** (5 064 entrées, 0 écart) où une
  regex naïve produit des **faux positifs** (`1% implies` lu comme `% i` — exclure `%%` et le
  drapeau espace) ; Pango 24/24 ; `.mo` compilés interrogés par clé exacte.
  **Ép. 13 OUVERT — le seul restant, sans code** (§ 4.10 du doc) : *les gestes que seule une
  vraie plateforme peut jouer*, repoussés parce que cette machine de dev **n'a pas d'IPv6** et
  que certains chemins privilégiés ne se jouent ni en `netns` ni sans installation — run
  privilégié réel du NAT bridge (bail DHCP dans un invité, après `make install` +
  `--enable-natbridge`), `selftest --assume-ipv6-uplink`, **sortie NAT66** (seule preuve
  *bloquée par l'environnement*), les deux ports du LAN bridge sur une carte physique, les
  textes à l'écran, et les rejeux différés des ép. 6 et 8. Le chantier **ne se clôt pas** avant.
- **bug-critique-crash-host** (crash rare non reproductible de l'hôte — reboot machine
  physique / arrêt net du conteneur Docker — corrélé à la terminaison des composants ;
  causes candidates C1-C5 classées, checklist post-mortem à exécuter au prochain crash) :
  `docs/bug-critique-crash-host.md` ; mémoire `bug-critique-crash-host` ;
  `git log --grep="bug-critique-crash-host"`. Ép. 0 (audit) fait 2026-07-18 ; **C5 clos le
  2026-07-31** (`d2d03da`, par l'ép. 9 du chantier clos `marionnet-automate-composants` — détail
  dans `docs/refonte-automate-composants.md` : master lock OCaml, gel d'appli — jamais un crash
  hôte).
- **modernisation-installation-marionnet** (chantier PARENT : remplacer l'installeur mort
  `useful-scripts/marionnet_from_scratch` par une diffusion moderne — script v2, .deb + dépôt
  apt maison, RPM, Docker officiel [MarioNUM g3], binaires précompilés sur marionnet.org ;
  essaimera des chantiers enfants par canal) : `docs/modernisation-installation-marionnet.md` ;
  mémoire `modernisation-installation-marionnet` ;
  `git log --grep="modernisation-installation-marionnet"`. **Ép. 0→9a faits** : autopsie et
  décisions (0, 2026-07-18/19), la source de vérité des dépendances remise d'aplomb dans le
  `Makefile` (1 et 2 — `REQUIRED_PACKAGES_RUNTIME` += `jq socat dnsmasq-base`, `bridge-utils`
  retiré), puis **la chaîne de release, des deux côtés** :
  - **publier** — `make filesystem.prepare-snapshot-to-publish` (ép. 3 : un snapshot COW devient
    les 4 éléments publiables + le tarball) et `make kernel.prepare-to-publish KERNEL=<nom>`
    (ép. 5) ; ép. 4 = la régression de 2014 de `sudo_fcall` qui polluait `BINARY_LIST` ;
  - **consommer** — `bin/scripts/marionnet-install.sh` (ép. 6, `ab92b8d`), germe du script v2
    n'implémentant que `--fetch-only`. **`--from` prend une URL OU un répertoire local** (miroir) :
    seules `catalog_list` et `artifact_stream` connaissent la différence, donc un run sur miroir
    exerce le vrai chemin. C'est ce qui permet de travailler **pendant que `www.marionnet.org`
    est en panne**, et ce dont a besoin une salle de TP hors ligne.
  **Invariants posés par ces trois scripts, à ne pas casser en publiant un artefact autrement** :
  le nommage est la seule clef (`filesystems_<X>.tar.*` ⇒ `share/marionnet/filesystems/<X>`,
  idem `kernels_`), d'où une idempotence sans somme ; `.tar.xz` par défaut, extrait par
  **`xz -dc -T0 | tar xf -` et jamais `tar xJf`** (facteur 4 mesuré) ; **jamais `-m`/`--touch`**
  à l'extraction et `--owner=root --group=root` à la création (le `mtime` d'un backing file est
  ce qu'UML vérifie) ; une image *router* est un **lien** vers l'image *machine* d'un **autre**
  tarball. **Le « répertoire de release », nommé partout ici, est
  `website-repo/download/marionnet-install.sh/<série>/`** — soit aujourd'hui
  `website-repo/download/marionnet-install.sh/1.0.x/` : c'est ce que les 6 publieurs
  alimentent, ce que le déposeur porte en ligne, et ce que `--from` attend.
  `website-repo/` (copie de travail du site) est **gitignoré** — donc invisible d'un `grep`
  du code, d'où ce rappel.
  Le chemin **réseau** n'est plus une supposition : l'ép. 7 le mesure sans le serveur, en
  dressant un **Apache en conteneur** (`bin/scripts/marionnet-install.sh.bench/`, 16 cas,
  discriminance rouge/vert mesurée). Trois choses à ne pas défaire : le banc sert le listing
  avec **Apache `FancyIndexing`** et non un `python3 -m http.server` (le parsing vise Apache),
  il parle **HTTP** et non HTTPS (un certificat auto-signé ferait mesurer un `wget` différent
  de celui de production), et **rien n'est monté dans le conteneur client** hormis le script.
  Piège de production qu'il a mis au jour : un `index.html` dans le répertoire de release fait
  servir la page **au lieu du listing** (200), donc catalogue **vide** sans rien de cassé côté
  publication — l'argument pour publier un fichier d'index plutôt que dépendre de
  `mod_autoindex`.
  **Ép. 8 : c'est fait, et par le même fichier que l'intégrité.** Le catalogue d'une release
  est désormais **`SHA256SUMS`** — une ligne `sha256sum` porte un nom *et* une empreinte, donc
  un seul fichier répond aux deux questions ; le listing n'en est plus que le **repli**.
  `Makefile.d/release.sha256sums.sh` en est le **seul écrivain** (cible `make
  release.sha256sums`), appelé d'eux-mêmes par les deux `*.prepare-to-publish.sh`.
  **Invariant à ne pas casser** : un artefact déposé sans passer par ce script est
  **invisible** de l'installeur, et une ligne orpheline annonce un fantôme (d'où son retrait).
  Côté installeur, l'empreinte est vérifiée **en flux** — `tee >(sha256sum)` ne convient pas,
  bash n'attendant pas une substitution de processus, d'où fifo + `wait` — et un artefact en
  écart est **retiré**, l'idempotence étant par le nom. Ce que le digest ne prouve pas : la
  **provenance** (il voyage avec les tarballs) ; la signature est une question de l'étape 1.
  **Ép. 9a : l'application elle-même devient publiable.** `Makefile.d/release.binary.sh`
  (cible `make release-binary`) produit un tarball relocatable
  `marionnet_<version>-r<rev>_<arch>_glibc<x.y>.tar.xz` — racine nommée, `install.sh` et
  `README` embarqués — déposé dans le **même** répertoire de release et le **même**
  `SHA256SUMS` que les images et les noyaux (le `binaries/` du § 3.1 est abandonné ;
  contrepartie : une ligne `marionnet_*` est **cataloguée et ignorée** par l'installeur, sans
  erreur). **À ne pas défaire** : `dune install --prefix` n'est PAS une installation — les
  scripts de `bin/scripts/` doivent aller de `share/marionnet/scripts/` vers `bin/` (Marionnet
  et la doc les nomment nus), et la règle sudoers appartient à la machine cible, donc à
  l'`install.sh` embarqué. La configuration *testing* est **refusée** (le préfixe compilé
  serait le switch opam). **Piège durable** : `marionnet.native --paths` laisse `binaries` au
  préfixe **compilé** (`bin/initialization.ml:472`) alors que les scripts compagnons sont
  appelés **par leur nom nu**, donc trouvés par le **PATH** — inoffensif pour le code, mais un
  préfixe hors PATH donne un Marionnet qui démarre puis ne trouve plus ses portes privilégiées.
  **Ép. 9b : la machine cible.** Le banc `Makefile.d/release.binary.sh.bench/` déplie le
  tarball sur une `debian:trixie-slim` portant **les seuls** `REQUIRED_PACKAGES_RUNTIME` et y
  joue `install.sh` **en root** (27 cas verts) : la configuration `/etc/marionnet/marionnet.conf`
  et la règle sudoers — bloc **(a) seul** — sont enfin mesurées. **Deux invariants payés ici** :
  (1) cette liste de dépendances était écrite **par des gens qui compilaient**, d'où `xz-utils`
  (tout artefact publié est un `.tar.xz`, et `xz` n'est pas `Essential`) et
  `libgtksourceview-3.0-1` (les libs GTK venaient de `REQUIRED_PACKAGES_BUILD` ; **un** paquet
  couvre les 13 `NEEDED`, et son nom est stable là où `libgtk-3-0` a pris un `t64`) — ne pas
  ajouter de paquet ici sans site d'appel, ni en retirer sans rejouer le banc ; (2) **republier
  un artefact sous le même nom laissait le catalogue mentir** (digest précédent conservé, donc
  l'installeur **retire** ce qu'il vient de télécharger) : les **3** publieurs appellent
  désormais `release.sha256sums.sh` avec `--force` **borné à leur seul fichier**.
  **Ép. 9c : le consommateur sait installer l'application.** `marionnet-install.sh` gagne
  `--binary` (cumulable avec `--fetch-only`, **jamais replié dedans** : les données se posent
  sans privilège là où l'application exige root, et une option publiée ne change pas de sens).
  Le choix entre les `marionnet_*` se lit **dans le nom** — arch de la machine, glibc pas plus
  récente que la sienne, puis le plus grand `rev` — et tout refus est **montré** par `--list`
  avec son critère. **À ne pas défaire** : l'artefact est déplié **à côté** (`mktemp -d`) puis
  lance l'`install.sh` **qui voyage dedans**, parce qu'il n'y a qu'**un** installeur — celui que
  lance aussi l'humain qui télécharge à la main ; ce script n'en pilote qu'un et lui relaie
  `--force`/`--no-sudoers`/`--no-config`. Banc réseau **31 → 50 cas**, et la chaîne 9a→9b→9c
  mesurée d'un geste sur le vrai tarball, en root, dans le conteneur cible.
  **Ép. 10 : les dépendances apt de la machine cible.** La liste voyage dans le tarball
  **comme donnée** (`REQUIRED-PACKAGES-RUNTIME`, un paquet par ligne, généré du `Makefile`)
  parce que le here-document d'`install.sh` est **quoté à dessein** — l'y écrire en dur
  aurait recréé la seconde source de vérité que l'ép. 1 a supprimée. `install.sh` **nomme**
  ce qui manque et n'installe rien (`--with-deps` installe, `--no-deps` ne regarde même
  pas) : poser une application et tirer une douzaine de paquets sont deux gestes, et le
  canal qui fait les deux est le `.deb`. **À ne pas défaire** : rien n'est fatal (un paquet
  absent laisse une installation complète, pas un arbre à moitié posé), l'étape sudoers
  s'efface sur `command -v visudo` — **pas** sur la liste des manquants, sinon `--no-deps`
  rendrait fatale une étape qui ne l'est pas — et le relais de `marionnet-install.sh` a
  **trois** états, le défaut ne transmettant rien. Bancs : 27 → **39** cas (3ᵉ boîte
  `trixie-slim` nue, 4ᵉ avec réseau ; discriminance 10) et 50 → **53** cas.
  **Ép. 11 : les deux derniers restes locaux de la consommation.** *11a* — la complétion
  bash est enfin installée, et c'est **douze fichiers** dans
  `$(PREFIX)/share/bash-completion/completions/` (section dune `share_root`) : bash-completion
  charge **à la demande**, en cherchant un fichier *portant le nom de la commande tapée*,
  donc une installation sous un seul nom laisserait `mrnctl`, `mrn2sh`, `mrn-verify`… muets.
  Rien ne casse en quittant `bin/scripts/` parce que `_mrn_ctl_program` retombe sur le
  **PATH**. *11b* — l'installeur ne nomme plus de téléchargeur : `http_body` /
  `http_headers` sont **`wget` ou `curl`** (`wget` d'abord). **À ne pas défaire** : le `-f`
  de curl n'est pas une commodité (sans lui, curl sort **0** sur un 404 et `artifact_stream`
  déverserait la page d'erreur dans un tarball), et l'absence de `-S` non plus (le
  `SHA256SUMS` manquant d'une release d'avant l'ép. 8 est une condition **gérée** : `wget -q`
  n'en dit rien, curl ne doit pas en dire plus). Bancs : 39 → **42** cas (3 rouges sur
  l'artefact d'avant) et 53 → **63** (6 rouges ; 2ᵉ image cliente `curl` **sans** wget, plus
  une boîte nue qui vérifie que la garde nomme les deux).
  **Ép. 12 : les quatre boîtes.** La boîte cible devient un **paramètre** des deux bancs
  (`--distro <image>`, `--distro all`, `ARG BASE_IMAGE`, noms d'images et de conteneurs
  suffixés) — défaut inchangé, donc un run sans argument veut dire ce qu'il a toujours
  voulu dire. Le banc **réseau** n'a demandé que l'`ARG` : l'ép. 9c demandait déjà l'arch
  et la glibc au **conteneur client** et non à l'hôte du banc, si bien que toute la famille
  `--binary` suit la boîte d'elle-même (63 verts × 4). Les 13 `REQUIRED_PACKAGES_RUNTIME`
  existent sous ce nom sur les quatre : le pari de l'ép. 9b est mesuré. **Le seul écart est
  Debian 12, et ce n'est pas un défaut** : un binaire est lié à la glibc de la machine qui
  l'a compilé (2.39), et cette garantie ne vaut que **vers l'avant** — il tourne sur 2.43
  (Ubuntu 26.04, mesuré) et pas sur 2.36. **À ne pas défaire** : le banc binaire lit
  arch+glibc **dans le nom du tarball**, comme `marionnet-install.sh` pour choisir ; il ne
  saute pas le run (poser les fichiers, la conf, le sudoers, la complétion et nommer les
  dépendances apt se mesurent tout aussi bien, et ce sont justement les gestes qui changent
  d'une distribution à l'autre), il n'efface que les **4 cas qui démarrent le binaire** et
  les remplace par un cas exigeant que le refus **nomme la glibc**. Conséquence à garder :
  *pour servir Debian 12, il faudra construire sur Debian 12.* **43ᵉ cas neuf** :
  `bash-completion` **trouve** la complétion sous le préfixe sans qu'on ait rien sourcé —
  ce qui valide enfin le `share_root` de l'ép. 11a — et il vérifie le **nom de la fonction
  armée**, le chargeur retombant sur `complete -o default -F _minimal` pour une commande
  inconnue (un cas naïf passait au vert sur une boîte où **rien** n'était installé).
  **Ép. 13 : combien de `.deb`, tranché sur des mesures — épisode sans code.** La décision
  du § 6 tient (grosses images hors apt : wheezy 1,8 Gio, trixie 5,1 Gio dépliés) mais
  devient **quatre** paquets : `marionnet` (amd64, ~35 Mio, les guides compris),
  `marionnet-kernels`, `marionnet-kernels-i386`, `marionnet-fs-guignol` (**all**, machine
  ET routeur). **À ne pas re-découper** : le paquet routeur du précédent RPM disparaît —
  un artefact routeur pèse **3,8 Kio** et ne contient qu'un **lien** vers l'image machine,
  donc un paquet séparé porterait un lien pendant (son propre changelog de 2009 dit
  « added symlinks ») ; les deux noyaux, eux, **se séparent**, et c'est mesuré qui le
  justifie : l'interpréteur du noyau i386 est écrit en dur (`/lib/ld-linux.so.2`) et
  `libc6-i386` ne fournit que `/usr/lib32/…` — c'est `libc6:i386`, donc
  **`dpkg --add-architecture i386`**, qui possède ce chemin. Un paquet capable de faire
  activer une architecture étrangère ne s'impose pas à tout le monde pour de la
  rétro-compatibilité. **Sa dépendance exacte est à mesurer sur les 4 boîtes au point (4)** —
  c'est la seule du découpage qui ne se dérive pas du `Makefile`. Le `Depends:` se **dérive** (`${shlibs:Depends}` + la liste générée
  de l'ép. 10, entière, sans tri à la main) : les 13 paquets se coupent en **ce que `ldd`
  voit** (1 seule bibliothèque) contre **ce que seul le `Makefile` sait** (12 commandes
  appelées par leur nom) — et la contrainte glibc que l'ép. 12 a dû écrire dans le **nom**
  du tarball devient une **métadonnée** (`libc6 (>= 2.39)`). Préfixe **`/usr` + conffile de
  relocation** : une seule compilation sert les deux canaux. **Le postinst NOMME la règle
  sudoers, il ne l'accorde pas** (`apt` ne sait pas pour qui il installe — symétrique de
  l'ép. 10 pour les dépendances). Publication en *flat repo* **sous la série**, d'où trois
  choses à ne pas oublier : deux catalogues cohabitent (`SHA256SUMS` **et** `Packages`), la
  **version d'un paquet n'encode pas la série** (un noyau se versionne `6.12.95`, une image
  `18474`), et `download/apt/` devra être le point d'entrée **stable**. **Mesuré et refusé** :
  creuser les images (trixie est pleine à 90 %, 8,0 % de zéros déjà, `xz` les efface en
  transit, et creuser un artefact publié lui donnerait un **`mtime` neuf**).
  **Ép. 14 : `doc-src/` s'installe, et c'est un fichier `dune`, pas un `.deb`.** Les 26
  fichiers écrits pour qui **n'a pas le dépôt** vont sous `$(PREFIX)/share/doc/marionnet/`
  (`doc-src/dune`, section **`share_root`** + `as doc/marionnet/…` — la section `doc` de dune
  installerait sous `$(PREFIX)/doc/`), chacun **nommé un par un** : c'est ce qui garde dehors
  les sources du manuel texinfo **et** les fichiers absents de git (guide FR, PDF), nommer un
  fichier introuvable cassant le build sur un clone frais. **À ne pas défaire** : (1)
  l'arborescence est conservée parce que les documents **se citent par chemin** — d'où les 61
  citations passées de `doc-src/…` (relatif à la racine d'un **clone**) à des chemins relatifs
  **au répertoire du document**, seule règle vraie dans le dépôt *et* sur la machine installée,
  énoncée par 3 documents d'entrée ; (2) **`dune install` pose 0644 hors `bin`/`libexec`**
  (mesuré), donc les 14 scripts d'exemple perdent leur bit — restauré par les **3** canaux
  (2 cibles du `Makefile`, `release.binary.sh`) par une règle **uniforme** (tout `*.sh` des 2
  répertoires d'exemples) et non par une liste. Banc binaire **43 → 48 cas** (48 verts, 5/5
  rouges sur l'artefact d'avant), et **3 des 5 cas neufs sont gardés sur l'existence du
  répertoire** : un `find`/`grep` sur un répertoire absent ne trouve rien, donc passait au vert
  sur l'arbre qu'il devait condamner.
  **Ép. 15a : les quatre `.deb` existent** — `Makefile.d/release.deb.sh` (cible `make
  release-deb`), **cinquième publieur** : même répertoire de release, même `SHA256SUMS` (qui
  apprend un 5ᵉ motif, `*.deb` — sans quoi un paquet déposé serait invisible). **À ne pas
  défaire** : (1) rien n'est décrit deux fois — l'application est assemblée du **staging que
  `release.binary.sh` produit** (option neuve `--staging-dir`), donc les gestes que `dune
  install` ne fait pas y sont déjà, et les paquets de données sont **dépliés de l'artefact
  publié**, seule façon de livrer le **même `mtime`** que le tarball (mesuré : image guignol
  datée `2017-06-09` des deux côtés — c'est ce qu'UML vérifie) ; (2) le `Depends:` est
  **dérivé deux fois** — `dpkg-shlibdeps` (d'où `libc6 (>= 2.38)`, la contrainte que l'ép. 12
  ne savait écrire que dans un **nom de fichier**) ∪ `REQUIRED_PACKAGES_RUNTIME` lu à travers
  `make`, le doublon retiré **par un test sur le nom** ; (3) la version **commence par `0~`**
  (`dpkg-deb` refuse `trunk-r906`, mesuré ; `0~trunk+r913` < `1.0.0`, mesuré) et celle d'un
  paquet de données est lue **dans le nom de l'artefact** ; (4) lintian tourne sur chaque
  paquet et **n'est jamais fatal** — 4 de ses remarques étaient de vrais défauts (dont
  `umask 022` : sans lui le paquet rendait `/usr/share` inscriptible par le groupe), **3 sont
  des réponses** gardées avec leur raison, dont `unstripped-binary-or-object` (−9,4 Mio
  possibles, refusés : les 2 canaux livrent **le même binaire**).
  **Ép. 15b : les quatre `.deb` s'installent, et le répertoire de release devient un dépôt
  apt.** `Makefile.d/release.apt.sh` (cible `make release-apt`, appelée d'elle-même par
  `release.deb.sh` **une fois, après la boucle**) écrit `Packages`/`Packages.gz`/`Release` —
  dépôt **à plat** (`deb [trusted=yes] <url> ./`), la série étant la suite et le répertoire
  le composant. **À ne pas défaire** : les index **ne sont pas** dans `SHA256SUMS` (ils sont
  réécrits à chaque publication, donc un digest y serait périmé tout seul — la panne de
  l'ép. 9b) ; `dpkg-scanpackages` et non `apt-ftparchive` (pas d'`apt-utils` de plus sur la
  machine de release) ; **aucun** fichier d'override, `/dev/null` en signifiant un **vide**
  et déclenchant un avertissement à chaque run ; `Architectures:` **dérivé** (sans `all`,
  apt ignorerait `marionnet-fs-guignol` sans un mot). Un **3ᵉ banc**,
  `Makefile.d/release.deb.sh.bench/` (33 cas, **sans `Dockerfile`** : la boîte est nue, tout
  le propos du canal étant qu'apt tire les 13 dépendances lui-même) — **33 verts** sur
  Debian 13 et les 2 Ubuntu, **7** sur Debian 12. Trois mesures que lui seul pouvait
  faire : **(a)** sans `dpkg --add-architecture i386`, apt refuse `marionnet-kernels-i386`
  en **nommant `libc6:i386`** (la seule dépendance non dérivée du `Makefile`, enfin
  chiffrée) ; **(b)** sur une machine où le **tarball** avait déjà écrit
  `/etc/marionnet/marionnet.conf`, un `apt install` **non interactif échoue** —
  `DEBIAN_FRONTEND=noninteractive` gouverne *debconf*, **pas** l'invite de conffile de dpkg
  — et la réponse est `-o Dpkg::Options::=--force-confold`, qui **garde** le préfixe choisi
  et laisse `.dpkg-dist` à côté : cela appartient à la **doc INSTALL**, surtout pas à un
  `postinst` qui répondrait à la place de l'administrateur ; **(c)** sur Debian 12 apt
  refuse en **nommant `libc6 (>= 2.38)`** — le `.deb` rend la contrainte *refusable*, il ne
  la résout pas. **Piège durable établi ici** : *une image Docker n'est pas une machine
  Debian* — `debian:*-slim` **et** `ubuntu:*` excluent `/usr/share/doc/*` par `path-exclude`
  (mesuré : les 26 guides de l'ép. 14 disparaissent, l'i18n survit car elle est sous
  `/usr/share/marionnet/locale`), ce que le banc du tarball n'avait jamais vu (`tar` ne
  consulte la configuration de personne) et ce dont le futur **canal Docker officiel** devra
  se charger.
  **Ép. 16 (hors feuille de route) : `marionnet-get-images`, les grosses images choisies.**
  Wheezy et trixie restent hors d'apt (§ 6, ép. 13), mais l'utilisateur qui installe par apt
  ne recevait qu'une phrase. **Refusé, et pourquoi** : un *paquet installeur* dont le
  `postinst` télécharge tiendrait le verrou d'apt pendant 1,09 Gio, laisserait dpkg
  propriétaire de **rien** (`apt remove` ne libérerait rien) et ses cases à cocher ne
  s'afficheraient pas sous `noninteractive` — la panne même que l'ép. 15b a mesurée.
  **Fait à la place** : `useful-scripts/marionnet-install.sh` **déménage en
  `bin/scripts/`** et devient AUSSI le chooser, par **dispatch sur `$0`**
  (`marionnet-get-images`, `mrn-get-images` — la forme de `mrn2sh`) ; **18 noms** installés
  au lieu de 15, donc **26** dans `bin/`. **À ne pas défaire** : (1) pas de second script —
  le chooser a besoin du catalogue, du `xz -dc -T0` et de l'empreinte vérifiée *pendant*
  l'extraction, soit ce fichier entier (une 2ᵉ implémentation est ce que l'ép. 8 a
  supprimé) ; pas de bibliothèque sourcée non plus, ce fichier étant publié **seul** et
  téléchargé par une machine qui n'a rien ; (2) `--binary` est **refusé** sous le nom du
  chooser ; (3) **sans terminal, refus** (rc 2) sous ce nom seulement — le défaut de
  `--fetch-only` est *tout ce qui est publié*, ~7 Gio ; sous le nom de l'installeur ce
  défaut est intact ; (4) l'état d'une image se lit dans son `.conf` (`MTIME`, le champ
  qu'UML vérifie), **pas** dans un digest — l'image installée est le fichier *extrait*, or
  `SHA256SUMS` porte l'empreinte du *tarball*. **Piège mesuré** : `stat -c %Y` sur une image
  **routeur** lit le `mtime` du **lien** et non de sa cible → sans `-L`, tout routeur
  fraîchement installé était dit altéré. **Trouvaille** : le `MD5SUM` du `.conf` de
  **guignol** est **périmé** (`SUM` et `MTIME` exacts, `md5sum` non — vrai à la source),
  et **rien ne lit `MD5SUM`** (`bin/disk.ml:456` le déclare et ne le consulte jamais) ;
  d'où une vérification `v <n>` qui rend compte des **deux** champs séparément au lieu d'un
  verdict unique. Ce `MD5SUM` a été **régénéré à l'ép. 23**.
  **Ép. 17 (hors feuille de route) : le canal RPM, et deux dépendances que personne ne
  porte.** `Makefile.d/release.rpm.sh` (cibles `make release-rpm` et `release-rpm-deps`),
  **6ᵉ publieur** : même répertoire de release, même `SHA256SUMS` (6ᵉ motif, `*.rpm`).
  **Le constat qui commande tout** : `vde2` (donc `vde_switch`/`wirefilter`/`slirpvde`, 19
  sites d'appel) et `uml_mconsole` **n'existent dans AUCUN dépôt RPM** — mesuré sur Rocky 9
  + EPEL + CRB + epel-next, Fedora 42 et 44. Ce n'est pas un retrait mais une **non-entrée** :
  0 projet `rpms/vde*` dans le dist-git de Fedora, aucune review request, une proposition
  morte de 2007 ; Debian les maintient (équipe VSquare, ~10 patches, amont figé depuis 2011)
  et **openSUSE ships vde2** en dépôt officiel. La fracture n'est donc pas RPM/DEB mais
  **Fedora-RHEL contre les autres**. `alien` est **refusé** (il convertit des *formats*, or
  les deux côtés sont déjà du rpm ; il ne traduit pas les noms, ne recompile pas, abîme les
  scriptlets) : les deux paquets sont **construits depuis le paquet source Debian**, série de
  patches comprise. **À ne pas défaire** : (1) **3 paquets** Marionnet et non 4 — la raison du
  `marionnet-kernels-i386` debian était `dpkg --add-architecture`, or sur RPM le multilib est
  natif et rpm **dérive lui-même** les deux classes (`libc.so.6` *et* `…()(64bit)`, mesuré),
  donc la dépendance est meilleure qu'écrite à la main ; (2) les dépendances s'écrivent **par
  fichier et par soname, jamais par nom de paquet** — c'est ce qui rend **un seul spec** valable
  sur Fedora *et* openSUSE (mesuré des 2 côtés) — avec **2 exceptions mesurées** :
  `(iproute or iproute2)` (booléenne, car `ip` n'a pas de chemin portable : usrmerge Fedora
  contre `/usr/sbin` openSUSE) et `xz` **par nom** (sinon `busybox-xz` peut fournir
  `/usr/bin/xz`, dont le `xz` ignore le `-T0`) ; (3) `rpmbuild` tourne **dans un conteneur** de
  la distribution cible, parce que le générateur automatique de dépendances de rpm **est**
  l'équivalent de `dpkg-shlibdeps` — le faire tourner sous Ubuntu ferait des métadonnées un
  artefact de la machine d'empaquetage ; rien n'est installé sur la machine de release ; (4) le
  `BuildRequires:` des paquets tiers est **appliqué** (`dnf builddep`), pas recopié dans l'image.
  **Pièges durables établis ici** : `make -j4` **casse** vde2 (course de 2011, `-j1`
  obligatoire) ; une **apostrophe inversée dans un heredoc non quoté** ouvre une substitution
  et fait perdre un paragraphe du spec **en silence** ; `local a="$1" b="$a"` lit la portée
  **appelante** (tout est développé avant les affectations) ; et **`%doc` n'est pas ce qui
  décide** — rpm marque seul comme documentation tout ce qui est sous `%{_docdir}` (26 des 31
  chemins), donc `tsflags=nodocs` de **toute** image conteneur emporte les guides, pendant exact
  du `path-exclude` de l'ép. 15b. `RPMS/` (specs 2009) **supprimé** : code mort, et son `%post`
  fabriquait un `br0` que l'ép. 7b a rendu automatique. Banc neuf
  `Makefile.d/release.rpm.sh.bench/` (sans `Dockerfile`, boîte nue) : **37 verts sur
  fedora:42**, **6 sur Rocky 9** (refus attendu, **nommant la glibc**). Restent : le dépôt
  `createrepo` *(fait à l'ép. 18)*, et une image de build à glibc ancienne pour servir
  Rocky 9 / Leap 15.6.
  **Ép. 18 : le dépôt — `dnf install marionnet`.** `Makefile.d/release.dnf.sh` (cible `make
  release-dnf`, appelée d'elle-même par `release.rpm.sh` **une fois, après la boucle**) écrit
  le `repodata/` d'un dépôt **à plat**, pendant exact de `release.apt.sh`. **Ce qu'il achète** :
  sans dépôt, il fallait **nommer les cinq paquets**, donc **savoir** que `vde2` et
  `uml-utilities` existent et pourquoi ; avec, `dnf install marionnet` les résout **du même
  répertoire** (mesuré). **À ne pas défaire** : (1) les 2 paquets de données sont `Suggests:`
  et **non** `Recommends:` — mesuré, dnf honorait la faible vers `marionnet-fs-guignol`
  (noarch) et **écartait silencieusement** celle vers `marionnet-kernels` (qui a besoin de
  multilib), or *la moitié qui arrive est pire que rien* (une image sans noyau) ; `Suggests:`
  **aligne les 2 canaux** — `apt install marionnet` et `dnf install marionnet` donnent
  l'application seule ; (2) `repodata/` **n'est pas** dans `SHA256SUMS` (réécrit à chaque
  publication ⇒ digest périmé tout seul, la panne de l'ép. 9b) ; (3) **pas de `--update`** de
  createrepo (la seule situation qu'il optimise est celle qu'il ne faut pas rater : un paquet
  republié sous le même nom) ; (4) `marionnet.repo` n'est écrit **que si `--base-url`** le dit
  — l'URL n'est pas connaissable avant que le répertoire soit servi ; sinon la strophe est
  affichée. **Trois catalogues cohabitent** dans le répertoire, aucun dérivable des autres :
  `SHA256SUMS` (artefacts), `Packages` (`.deb`), `repodata/` (`.rpm`). **Piège de banc** : un
  répertoire de release contient légitimement **plusieurs révisions**, donc
  `dnf install /rpms/*.rpm` demande 2 versions d'un même paquet et échoue — nommer les paquets
  un par un, la plus récente par `sort -V`. Banc **37 → 46 cas**, 46 verts sur `fedora:42`.
  **Ép. 19 : la correction — on testait les mauvaises boîtes** (né d'une question de
  l'utilisateur : *pourquoi Rocky 9, alors que Rocky en est à la 10.2 ?*). **Mesure qui renverse
  le cadre** : Rocky 10.2 et AlmaLinux 10.2 sont en **glibc 2.39**, Leap 16.0 en 2.40, Fedora 42
  en 2.41 — donc **toute distribution RPM courante accepte déjà notre build**, et « l'image de
  build à glibc ancienne » n'était l'artefact que d'avoir visé les versions *précédentes*.
  **Défaut de conception corrigé** : RHEL 10 a **supprimé tout le multilib 32 bits** (rien ne
  fournit `/lib/ld-linux.so.2`, CRB compris), donc le paquet de noyaux **fusionné à l'ép. 17**
  y était refusé **en entier** — l'utilisateur perdait aussi le noyau **64 bits**. D'où la
  **re-séparation** (retour aux **4 paquets**, comme Debian mais pour un motif de ce monde-ci :
  *un paquet non installable ne doit pas en emporter un qui l'est*). **2 défauts d'empaquetage** :
  `x11-xserver-utils` était mappé sur `/usr/bin/xrandr` **par devinette** alors que le `Makefile`
  dit `xhost` (et Rocky 10 n'a pas `xrandr` du tout) ; et `uml-utilities` exigeait
  `filesystem(unmerged-sbin-symlinks)`, qu'aucune boîte EL ne fournit — cause :
  `/usr/lib/rpm/filesystem.req` de Fedora se déclenche sur le **nom de base** d'un fichier, où
  qu'on l'installe, et **ne fait rien si la boîte de build n'est pas usermergée**. **RÈGLE QUI EN
  SORT, à ne pas défaire** : *on construit sur la plus ancienne boîte qu'on sert* (défaut
  `--build-image` = `rockylinux/rockylinux:10`), car le générateur applique les **conventions de
  la distribution où il tourne**, et elles voyagent dans le paquet. **Le pire défaut était dans
  le banc** : il classait « refus nommant la glibc » **tout** message contenant le mot → **PASS
  mensonger** rapporté 2 fois comme un succès ; un refus se classe désormais par le **symbole
  exact** (`unmet_of`). **2ᵉ piège de banc** : `zypper` **sort avec 0 après avoir annulé** —
  lire `rpm -q`, jamais le statut. **openSUSE Leap 16 (zypper) est la boîte qui prouve le pari** :
  notre paquet s'y installe en résolvant `/usr/bin/vde_switch` depuis **le vde2 de la
  distribution** — le nôtre n'est pas tiré ; et elle livre la **3ᵉ orthographe** de l'exclusion
  de doc (`rpm.install.excludedocs`, après `path-exclude` et `tsflags=nodocs`). Banc :
  `--distro all` sur les 4 courantes → **47 + 45 + 46 + 46 = 184 verts, 0 rouge** (+ 6 sur
  Rocky 9, refus classé exactement). **Reste** : Rocky 9 / Leap 15.6 = choix de portée (image de
  build plus ancienne, switch OCaml à compiler) ; EPEL requis sur EL (d'où vient
  `gtksourceview3`) = une ligne pour la doc INSTALL ; signature + `baseurl` avec l'étape serveur.
  **Ép. 20 (hors feuille de route) : la boîte de compilation — « matrice » ⇒ un PLANCHER.**
  La compatibilité glibc ne voyage que **vers l'avant**, donc N artefacts indexés par glibc en
  publieraient N−1 inutilisables : on en publie **un**, construit sur la plus ancienne boîte
  servie, et « où construit-on » devient un **bouton** (`--build-image`, défaut `debian:12` /
  glibc 2.36 — qui couvre les 4 boîtes Debian/Ubuntu **et** les 4 boîtes RPM courantes). C'est
  la règle de l'ép. 19 appliquée enfin à **l'application** et non aux seuls paquets tiers :
  jusque-là le plancher des 6 canaux était un **accident de la machine de l'auteur**.
  `Makefile.d/release.build-box.sh` (cible `make release-build-box`) **ne sait rien** d'une
  installation ni d'un catalogue — dans la boîte, ce sont `make rebuild-for-final` et
  `release.binary.sh` **inchangés** qui travaillent ; les paquets apt de build, le compilateur
  et les paquets opam sont lus **à travers `make`** (3 cibles `print-*`, motif de l'ép. 10),
  `OPAM_PACKAGES_DEV` volontairement non publié. **À ne pas défaire** : (1) la source est un
  `git clone` de HEAD **avec son `.git`** (un `git archive` viderait la révision en silence) —
  mais **garder le `.git` ne suffit pas**, et le 1ᵉʳ run l'a prouvé en publiant un
  `marionnet_trunk-r0_…` : le clone appartient à l'appelant, le conteneur tourne en root, et
  git ≥ 2.35.2 **refuse** un dépôt de *dubious ownership*, or les **deux** lecteurs de la
  révision (`bin/meta.ml.maker.sh:57-68` et `release.binary.sh:141`) traitent un git en échec
  comme « pas de VCS ici » — **rien n'échoue**, la release perd juste le numéro qui l'ordonne ;
  d'où `safe.directory` **et surtout** la comparaison avec la révision calculée côté hôte, qui
  **arrête le run** ; (2) la mesure du plancher cherche `marionnet.exe` **et**
  `marionnet.native` (dune produit le premier, le second est le nom d'*installation*) et
  **échoue** si elle ne trouve rien — une mesure qui peut ne pas avoir lieu n'en est pas une.
  **Rien d'autre n'a eu à changer** : `marionnet-install.sh` et le banc binaire comparent déjà
  la glibc **du nom** à celle **de la boîte**, jamais le nom de la distribution — la conception
  de l'ép. 12 tient. Mesuré : symbole glibc maximal référencé = **`GLIBC_2.35`** (le nom reste
  conservateur, il annonce la boîte de build) ; banc binaire `--distro all` = **192 verts,
  0 rouge, 0 SKIP**, dont Debian 12 qui ne savait jusqu'ici que constater un refus.
  **Ép. 20b : le `.deb` sort de la même boîte** — `release.build-box.sh --with-deb`
  (`make release-build-box WITH_DEB=1`) lance `release.deb.sh` **dans le même conteneur**,
  contre le staging qui vient d'être compilé. **Le défaut était plus large que celui qu'on avait
  nommé** : outre `libc6 (>= 2.38)` pour un binaire n'exigeant que 2.35, `dpkg-shlibdeps`
  écrivait `libgtk-3-0t64`/`libglib2.0-0t64` — les noms de la transition `time_t` 64 bits, qui
  **n'existent pas du tout sur Debian 12** ; il avait donc écrit les **noms de paquets** de sa
  machine, pas seulement leurs versions. L'asymétrie est celle de la glibc (mesuré : le t64 de
  trixie déclare `Provides: libgtk-3-0 (= …)`, donc l'ancien nom vaut **au-dessus** du plancher,
  jamais en dessous), donc la réponse est la même règle. **À ne pas défaire** : (1) pas de
  `--build-image` sur `release.deb.sh` — le `.deb` de l'application est assemblé d'un staging
  **produit en compilant**, donc empaqueter dans la boîte = compiler dans la boîte, et un 2ᵉ
  point d'entrée reclonerait HEAD et reposerait la garde `safe.directory` de l'ép. 20 ; (2) les
  outils d'empaquetage (`dpkg-dev fakeroot lintian`) sont **la dernière couche** de la boîte
  (avant le switch, toute boîte déjà bâtie recompilerait OCaml pour gagner 3 paquets apt), et
  `lintian` y est **exprès**, jugeant selon la politique de la distribution où il tourne ; (3)
  une boîte d'avant 20b compile parfaitement et n'empaquette pas → sonde `box_can_package`
  **avant** le clone et la compilation, jamais d'échec à mi-chemin. **Piège de banc, jumeau du
  PASS mensonger de l'ép. 19** : `run.sh` lisait la version « la plus grande » (son propre
  commentaire le dit) puis `Architecture:`/`Depends:` de la **première** strophe — annonçant r920
  et le jugeant sur la contrainte de r913, donc **FAIL** là où le paquet venait de s'installer
  (corrigé par `indexed_field <paquet> <version> <champ>`). Banc `.deb` **7 → 33** sur Debian 12,
  **132 verts / 0 rouge / 0 SKIP** sur les 4 boîtes.
  **Ép. 20c : le canal RPM ne compile plus rien** — et **pas** par la forme de 20b : côté Debian
  une **seule** boîte compile et empaquette, côté RPM elles sont **deux** (compilateur
  `debian:12`, `rpmbuild` `rockylinux:10`) et il n'y a pas de docker-dans-docker. Donc
  `release.rpm.sh` **déplie le `marionnet_*.tar.xz` publié** (sans `-m`), comme il déplie déjà
  les noyaux et l'image — *un paquet décrit ce que le répertoire de release contient*. **À ne pas
  défaire** : (1) l'**identité** (version, rev, arch) se lit **dans le nom de l'artefact** et non
  dans `release.binary.sh --print-name`, qui décrit l'**hôte** (mesuré : l'hôte disait
  `r921_…glibc2.39`, le répertoire publie `r920_…glibc2.36`) ; (2) plusieurs révisions cohabitant
  légitimement, la plus grande `r<rev>` gagne et **2 arch à cette révision font refuser**
  (`--app-artefact` tranche, comme `--kernel`) ; (3) le prix est **dit** — `make release-rpm`
  exige un tarball publié et nomme `make release-build-box`, là où il en fabriquait un en
  silence. Mesuré : `GLIBC_2.38` (r918, compilé ici) → **`GLIBC_2.35`** (r920, boîte), binaire
  **identique au tarball à l'octet**, paquet applicatif en **11 s**.
  **Le banc a trouvé ce que 192 + 132 verts n'avaient pas vu**, 3ᵉ défaut de la famille « juger
  par autre chose que ce qu'on mesure » (ép. 19, 20b) : le cas lisait `2>&1 | head -1`, donc
  **toute** ligne sur stderr faisait dire « the binary does not run » d'un binaire qui venait
  d'annoncer sa version. Séparé en 2 cas, dont un **rouge assumé** : **le binaire compilé dans
  la boîte écrit un `GLib-GObject-CRITICAL` au démarrage
  (`invalid cast from 'GtkSourceStyleSchemeManager'`) que celui compilé ici n'écrit pas** —
  isolé (r918 muet / r919 bavard, aucun `.ml` entre les deux), mêmes versions des deux côtés,
  cause **inconnue**, et sur **les 3 canaux** puisque le binaire est le même : **un épisode à
  part**. Banc RPM 46 → **48 cas** (46 verts `fedora:42`, 48 verts `rockylinux:10`).
  **Ép. 21 : la boîte enlevait un bâillon, elle ne changeait rien.** Le `GLib-GObject-CRITICAL`
  de 20c venait de `Gtksv_utils` (**`lablgtk3-extras`**), qui construit un
  `GtkSourceStyleSchemeManager` **à l'initialisation du module** et le fait passer par
  `g_object_ref_sink` alors que ce manager n'est pas un `GInitiallyUnowned` — Marionnet
  n'appelait rien de tout cela. **Le cast invalide était dans tous les binaires** : glib ≥ 2.80
  compile la vérification **out** dès `__OPTIMIZE__` (`_G_TYPE_CIC`), glib 2.74 (`debian:12`) la
  garde. **Piège durable** : avant de chercher ce qu'une boîte de build *change*, chercher ce
  qu'elle **cesse de taire** — et ne pas prendre un binaire silencieux pour un binaire correct.
  Correctif : `bin/dune` nommait `lablgtk3-extras` pour atteindre `GSourceView3`
  **transitivement**, alors qu'**aucun** de ses 7 modules n'est nommé dans le dépôt ; il nomme
  désormais **`lablgtk3-sourceview3`** (déjà dans `OPAM_PACKAGES`, dont `lablgtk3-extras` est
  retiré avec ses `ocf`/`xmlm`). **À ne pas défaire** : le stub amont reste faux, on s'en est
  seulement rendu indépendant — si un module d'ici appelle un jour
  `source_style_scheme_manager`, l'avertissement revient et il aura raison. Mesuré : `@check`
  rc 0, `nm` 309 → **0** `camlGtksv_utils` (862 `camlGSourceView3` intacts), breakpoint `gdb`
  sur le stub **jamais atteint**, `driven-sessions/quit-is-observable.sh` **7/7**.
  **Ép. 22 : le contrôle de chaîne, sans code**, dans l'ordre imposé par l'ép. 20 —
  `release.build-box.sh` clone **HEAD**, donc le rejeu ne pouvait venir qu'**après** le commit
  de l'ép. 21. `make release-build-box` (r923) → `make release-rpm` (rien de compilé, le tarball
  est déplié) → banc RPM : **48/0/0 sur `fedora:42`, 49/0/0 sur `rockylinux:10`**. Deux cas
  changent d'état et ce sont les deux qui comptent : *« the binary starts cleanly »*, **rouge
  exprès depuis 20c**, devient vert — c'est **la** preuve de l'ép. 21, celle que cette machine ne
  peut pas donner puisque glib ≥ 2.80 y compile la vérification **out** ; et l'**identité binaire**
  `.rpm` ↔ `.tar.xz` passe de **SKIP à vert**, r923 étant la 1ʳᵉ révision à porter les deux — le
  contrat de 20c cesse d'être une intention. **À retenir** : une preuve qui dépend de ce que la
  boîte *dit* se joue dans la boîte, et donc après le commit.
  **Ép. 23 : le `MD5SUM` régénéré, et la dérive de `mtime` qu'il a révélée.** La correction
  annoncée « peu coûteuse » l'était (`e7b651d1…` → **`afe9d7e8…`** dans les 2 `.conf` guignol,
  machine et routeur portant le même digest puisque c'est le même fichier), mais elle exigeait de
  **republier**, et la republication a montré le vrai défaut : les **3** images nues du répertoire
  de release avaient perdu leur `mtime` (copie sans `-p`, 2026-08-30) là où leurs tarballs, faits
  10 min plus tôt, portaient encore le bon. Le mode « image déjà publiée » du publieur **archive
  le `mtime` du disque** — un `--force` aurait donc publié la dérive **en silence**, c'est-à-dire
  exactement ce que le champ `MTIME` existe pour empêcher (UML refuse un *backing file* dont le
  `mtime` a bougé : les projets faits avec ces images ne s'ouvriraient plus). `sum(1)` étant resté
  celui du nom (`18474`/`08367`/`39212`), les `mtime` ont été **restaurés depuis le `.conf`**, qui
  fait foi. **À ne pas défaire** : la garde neuve **refuse** (rc 2) et **nomme** son remède
  (`touch -d @<MTIME>`) au lieu de réparer — réécrire un `mtime` n'est juste que si les octets
  n'ont pas bougé, et une image dont le contenu a changé se republie **sous un autre nom**, son
  nom *étant* son `sum` ; le mode « instantané » n'a pas besoin de la garde (il écrit le `.conf`
  depuis le disque). Republication de la famille guignol **entière** (2 tarballs + `.deb` +
  `.rpm`, tout en dérivant) et des **3** catalogues par leurs écrivains. Le commentaire de
  `image_integrity_verdict` est mis à jour **sans changer sa conception** : sa raison (guignol) a
  disparu, sa forme reste — un `.conf` ancien peut toujours porter un digest périmé, et rien ne
  lit `MD5SUM`. Mesuré : `sha256sum -c` sur 35 artefacts, `dune build` rc 0, banc réseau
  **68 PASS / 0 FAIL**.
  **Ép. 24 : le dépôt — le serveur était revenu, et le catalogue décide de ce qui monte.**
  La prémisse « bloqué par l'extérieur » traînait depuis l'ép. 3 ; **vérifiée avant d'être
  crue**, elle était fausse (site **200**, `ssh marionnet` OK, **Apache/2.4.18 à
  `FancyIndexing` qui suit les liens** — le banc de l'ép. 7 imitait donc la bonne chose).
  `Makefile.d/upload.www.marionnet.org.sh` (cible `make release-upload`) est le **7ᵉ** script
  de la famille et **le premier qui ne soit pas un publieur** : les 6 autres *fabriquent* une
  release, celui-ci ne fait que la *porter*, et **il n'écrit rien dans un répertoire de
  release** (chaque fichier déposé a un écrivain ailleurs). **À ne pas défaire** : (1) **ce qui
  monte est ce que `SHA256SUMS` nomme** — pendant exact de l'ép. 8, et ici une **panne
  évitée** : le répertoire porte aussi l'**état de travail du publieur** (les images nues,
  **7,3 des 11 Gio**) que personne ne télécharge et qui n'entrerait pas dans les **15 Gio**
  libres du serveur ; (2) la **preuve se prend sur le serveur** (`sha256sum -c` dans le
  répertoire distant : le catalogue a voyagé avec les artefacts, et la vérification ne coûte
  aucune bande passante) ; (3) les extras sont **nommés, jamais retirés** (`--prune` le fait,
  sur demande) ; (4) **deux points d'entrée stables** `download/{apt,rpm}` → série courante,
  corrigeant le défaut noté à l'ép. 13 (une ligne `sources.list` est épinglée sur la série),
  cibles **relatives**, et les deux désignent le **même** répertoire parce que 3 catalogues y
  cohabitent (ép. 18) ; (5) l'installeur est publié sous ses **2 noms** (dispatch `$0`,
  ép. 16), le second étant un **lien** — n'en publier qu'un rendrait `marionnet-get-images`
  inobtenable. **La release ne publie plus qu'une forme** : `.tar.gz` **et** `.tar.xz` étaient
  catalogués pour 4 artefacts, soit **2,16 des 3,87 Gio** — reste d'avant l'ép. 3 ; les
  fichiers supprimés, **`make release.sha256sums` a retiré leurs lignes de lui-même**
  (`31 kept, 4 dropped` — le catalogue n'est jamais édité à la main), et `--gz` se **rabat**
  proprement sur `.xz` (mesuré). Une **garde** nomme désormais ce cas *avant* le transfert.
  **Signature : câblée, non armée** — `--sign KEYID` produit `InRelease`/`Release.gpg`
  (éprouvés sur une clef jetable), mais signer, c'est décider 2 choses qui ne sont pas du
  code : la **garde** de la clef privée et sa **distribution hors bande** (`signed-by=` ne
  promet rien si la clef arrive par le dépôt qu'elle signe). Mesuré : **1,70 Gio** déposés,
  *31 catalogued artefacts, whole and intact* **côté serveur**, idempotence (2ᵉ passage :
  **1,63 Kio**), et — **jambe https du point (6), obtenue en passant** — l'installeur
  `--from https://www.marionnet.org/download/apt --list` (14 artefacts, `SUM yes`) plus un
  `apt update`/`install -s marionnet` dans une **`debian:13-slim` nue**, à travers le lien
  stable. **Piège durable payé ici** : *ne jamais éditer un script bash pendant qu'il
  tourne* — bash lit par **offsets d'octets**, et le run est mort d'une « erreur de syntaxe »
  après avoir fini le transfert, laissant les étapes suivantes non jouées.
  **Ép. 25 : une release n'est pas un journal de build.** Né d'une question devant le dépôt
  de la veille, et c'était un **défaut de l'ép. 24** — *le catalogue décide de ce qui monte*
  appliqué sans redemander si le catalogue avait raison. Le répertoire avait **8** tarballs,
  **4** `.deb` et **5** `.rpm` de l'application, un par épisode d'une journée : `Packages`
  offrait à apt **4** versions et `repodata/` **5** à dnf, donc `apt install
  marionnet=0~trunk+r913` rendait **légitimement** un binaire **d'avant le correctif de
  l'ép. 21**, et **5 des 8** tarballs étaient d'avant le plancher (`glibc2.39`, donc refusés
  sur Debian 12 et servis pour rien). `--multiversion` sert à **remplacer** une révision sans
  trou, pas à toutes les garder. **Une seule révision désormais, `r927`, sur les 3 canaux**
  (serveur : 37 → 23 entrées). **À ne pas défaire** : (1) le nettoyage passe par le **seul
  chemin licite** — supprimer les fichiers, laisser les **écrivains** des 3 catalogues se
  corriger, puis déposer avec `--prune` ; le déposeur **nomme** les révisions surnuméraires
  et n'en retire aucune (la rétention n'est pas sa décision) ; (2) le `.tar.gz` est abandonné
  **pour la publication, pas pour la lecture** — `--gz`/`--gzip` restent, parce que
  `download/marionnet_from_scratch/0.98.x/` est toujours servi et ne contient **que** des
  `.tar.gz`. **`make revno`** rend ce que `bzr revno` rendait, en le **demandant** à
  `bin/meta.ml.maker.sh --print-revision` : ce script est l'endroit de la règle, et ce numéro
  est celui dont tout artefact publié porte le nom. **Deux pièges durables payés ici** :
  (a) **`bin/gui/gui.xml` est un vestige qui n'est PAS chargé** — `bin/gui.ml` lit
  `gui_glade3.xml`, et c'est là qu'est passée la hauteur de fenêtre **840 → 860** qui rend
  enfin visible la dernière icône de la barre, la **planète** (mesuré dans les 2 sens : à 840
  la dernière icône est le nuage ; et la barre **ne grandit pas** avec la fenêtre — la planète
  est au même endroit à 860 et à 900 — donc aller au-delà n'achète rien) ; (b) **un rebond ssh coupe les rafales** — un `--prune`
  ouvrant **une connexion par fichier** s'est fait réinitialiser à mi-chemin par
  `ProxyJump lipn-ssh`, puis bannir quelques minutes ; d'où un `rm` groupé et surtout **une
  connexion maîtresse** (`ControlMaster`/`ControlPersist`) partagée par tous les appels **et
  par rsync**. Corollaire bash : il n'y a **qu'un** gestionnaire `EXIT`, un second `trap` le
  remplace en silence.
  **Ép. 26 : un seul geste, et le propriétaire de la rétention.** `make release-and-upload`
  enchaîne les 4 maillons d'une release (boîte plancher avec `.deb` → `.rpm` déplié du tarball
  → rétention → dépôt avec `--prune`). **Deux refus de conception à ne pas défaire** : (1) la
  série **ne se code pas dans un nom de cible** (elle est dérivée de `META`) et le nom **dit
  qu'il dépose** — `make release` se lirait « fabrique » alors qu'il met en ligne ; (2) **pas
  de script de regroupement** dans `Makefile.d/` : la chaîne est linéaire, chaque maillon est
  déjà une cible, elle n'a aucune connaissance propre — un script n'ajouterait qu'un endroit
  où l'ordre peut diverger. **Ce qui manquait vraiment** : personne ne possédait la
  **rétention** — l'ép. 25 a supprimé 17 révisions à la main, et la garde du déposeur savait
  les nommer sans droit de les retirer. D'où **`Makefile.d/release.retention.sh`** (cible
  `make release-retention`, **8ᵉ** script), qui possède la question *combien de révisions de
  l'application une release garde-t-elle* (défaut **1**, `KEEP=n`), que le déposeur
  **interroge** (`--print-superseded`) au lieu de recalculer. **À ne pas défaire** : il ne
  regarde **que l'application** (un noyau est `6.12.95`, une image son `sum` : republier leur
  donnerait un `mtime` neuf, ép. 23), il ne **touche pas au serveur** (ce qu'il retire devient
  un *extra* que `PRUNE=1` retire — deux gestes distincts), et il n'écrit **aucun catalogue
  lui-même**. Enfin **2 contrôles préalables**, non contournables ici à dessein : **arbre de
  travail sale** (la boîte clone HEAD, donc le non-committé **ne part pas, en silence**, et la
  release porte le nom d'une révision dont elle n'a pas le contenu) et **`CONFIGME.choice` sur
  *testing*** (refusé par `release.binary.sh` — autant le dire avant dix minutes de compilation).
  **Ép. 27 : les bancs contre le vrai serveur — le point (6) est soldé.** Les **4** bancs de
  réception prennent une **URL** là où ils prenaient un répertoire — la forme de
  `marionnet-install.sh --from` (ép. 6), donc **2 fonctions seules** connaissent la différence
  et un run distant emprunte le **vrai** chemin. **À ne pas défaire** : (1) côté `.deb` on ne
  télécharge que ce qu'un cas lit **sur l'hôte** (les 3 index + le tarball du cas `mtime`) —
  les paquets, c'est **apt** qui les rapatrie **en les vérifiant**, et la preuve d'intégrité est
  prise **sur le serveur** par le déposeur (ép. 24) ; côté RPM au contraire on télécharge, le
  geste mesuré étant `dnf install <fichier>.rpm` ; (2) le tri est **piloté par le catalogue**,
  jamais par une liste écrite dans un banc, et le cache est **partagé par `--distro all`**
  (4 boîtes = 1 release). **Trouvaille que seul le serveur pouvait donner** : **aucune image
  Debian/Ubuntu nue n'a de magasin de certificats** (les 4 boîtes RPM en ont un), donc `apt`
  n'ouvrait pas notre dépôt et l'installeur annonçait `server down, no route, wrong URL?`
  **d'un serveur debout** ; il **sonde** désormais la même URL sans vérifier le certificat —
  **pour le seul diagnostic** — et **nomme `ca-certificates`**, que la doc INSTALL devra écrire.
  **3 défauts de banc, même famille que les ép. 19/20b/20c/24** : `apt-get update` **sort avec
  0** sur une source qu'il ne peut pas rapatrier (avertissement, pas erreur — le cas « apt
  accepte le dépôt » était vert alors qu'apt l'ignorait), un verdict fondé sur le **libellé**
  d'un échec (la boîte est maintenant interrogée **deux fois** : si `ca-certificates` répare,
  c'est lui qui manquait), et un `--distro all` qui réémettait `"$@"` **sans `--from`** (trois
  boîtes vertes n'ayant jamais touché le serveur). Mesuré : **572 verts / 0 / 0** en distant
  (8 distributions) et **197 locaux inchangés** — aucun cas récrit pour le serveur.
  **Ép. 28 : les images suivent l'application, elles ne la doublent pas.** Vérification
  demandée avant l'épisode — *les 3 canaux écrivent-ils au même endroit ?* — faite en lisant
  les **4 écrivains**. Les 2 canaux **paquets** sont alignés au caractère près (`/usr` + le
  **même** `/etc/marionnet/marionnet.conf`) et le tarball garde `/usr/local` **à raison** :
  c'est le préfixe historique (`CONFIGME`) et un paquet qui écrirait là violerait la politique
  Debian **et** le FHS ; ce qui les réconcilie à l'exécution est la cascade de
  `bin/configuration.ml` (rencontre déjà mesurée à l'ép. 15b). **Le défaut était dans le 3ᵉ
  écrivain** : `marionnet-install.sh` ne lisait **pas** cette cascade — destination `/usr/local`
  écrite en dur — or les grosses images restent hors d'apt/dnf **par conception** (§ 6, ép. 13)
  et `marionnet-get-images` est *le* geste prévu (ép. 16), donc après un `apt install marionnet`
  les images atterrissaient dans `/usr/local/share/marionnet/filesystems` : **rien n'échoue**, et
  elles n'apparaissent pas. Destination désormais **dérivée de `marionnet.native --paths`**,
  **seul lecteur** de la cascade (relire le `.conf` en bash serait une 2ᵉ implémentation, ce que
  l'ép. 8 a supprimé ; le binaire est sur le `PATH` de toute machine installée, comme s'y fie
  déjà l'ép. 11a). **À ne pas défaire** : (1) `$PREFIX` — donc `--binary` — n'est **pas** dérivé,
  sinon un tarball se déplierait par-dessus un `/usr` que apt possède (ce que le chooser refuse
  déjà) ; la cohérence tient parce que `install.sh` **laisse** la conf qui nomme `/usr` ; (2)
  `--prefix` reste souverain ; (3) une conf pointant les 2 familles sur **2 chemins sans parent
  commun** est légitime pour Marionnet et **inexprimable** ici (un `filesystems_*.tar.*` porte
  son membre `filesystems/`) : elle est **nommée**, jamais avalée. Banc réseau **70/2 → 72/0**
  (4 cas neufs, dont 2 **discriminants**) ; **2 cas neufs** dans chacun des bancs paquets, où le
  geste mesuré est l'installeur **que le paquet a posé** sur une boîte que **seul apt/dnf** a
  meublée — d'où un **rouge assumé** (`.deb` 34/1, `.rpm` 49/1) : la release publiée est `r930`,
  donc le paquet porte l'installeur d'avant, et la preuve se prend **après le commit**
  (motif ép. 20c → 22).
  **Ép. 29 : la doc INSTALL — et la feuille de route n'a plus de point ouvert.**
  `doc-src/INSTALL.md`, nommée dans `doc-src/dune` (patron de l'ép. 14) et **pas** un
  `INSTALL` à la racine : ce répertoire est celui des documents écrits pour **qui n'a pas le
  dépôt**, soit exactement le lecteur d'une page d'installation — et comme **aucun canal ne
  nomme les documents un par un** (`share/doc/marionnet/` voyage entier), ce fichier `dune`
  est le **seul** endroit touché, les 3 canaux la recevant sans une ligne de plus. Les 4
  obligations héritées y sont, chacune à sa place : `ca-certificates` (ép. 27) **avant** les
  3 canaux, `-o Dpkg::Options::=--force-confold` (ép. 15b) avec sa cause,
  `dpkg --add-architecture i386` (ép. 13), et `marionnet-get-images` **sans `--prefix`**
  (ép. 28) en interdiction motivée ; plus EPEL sur la famille RHEL (ép. 19) et le **plancher
  glibc** dit comme une propriété du **nom** de l'artefact (ép. 20), jamais comme une liste
  de distributions à maintenir. **À ne pas défaire** : écrire une page d'installation, c'est
  *affirmer* que des commandes marchent — donc **les jouer telles qu'écrites**, ce qui en a
  corrigé **2** : `--list` **exige un mode** (`rc 2` sans lui ; sous le nom
  `marionnet-get-images` le mode est implicite) et `make install-final-as-root` appelle
  `sudo` **elle-même**. Mesuré contre le vrai serveur : `debian:13-slim` nue → apt résout
  `marionnet` r930 par `download/apt` ; `fedora:42` nue → `marionnet`, `vde2` et
  `uml-utilities` viennent tous trois du dépôt ; 5 URL en `200` ; le clone anonyme du § 6 a
  été **vérifié** et non supposé (le `remote` du dépôt est en ssh).
  **Ép. 30 : signer `Release` — et la signature change de main.** Les 2 décisions non-code de
  l'ép. 24 sont tranchées : **garde** = clef **rsa4096** de l'auteur, phrase de passe (vérifié
  `KEYINFO protection=P`), exp. 2031, qui **n'entre jamais dans un conteneur de build** ;
  **distribution** = la clef publique est **versionnée dans git**, donc servie par **Launchpad**
  — autre infrastructure que `www.marionnet.org` (vérifié : `/plain/<fichier>` → `200
  text/plain`). **À ne pas défaire** : `marionnet-archive-keyring.asc` n'est **jamais** déposé
  sur le serveur (une clef qui voyage à côté des paquets qu'elle signe ne prouve que ce que
  https prouve déjà). L'algorithme a été **mesuré avant d'être figé** — `signed-by=` accepte
  ed25519 comme rsa4096 sur les 4 boîtes et refuse la mauvaise clef partout ; **rsa4096** parce
  que la mesure côté RPM n'a pas abouti (`rpmsign` sans pinentry en conteneur, c'est 30b) et
  qu'on ne fige pas un type non vérifié pour une clef qui vivra des années.
  **Le défaut de conception que le banc a révélé** : `--sign` vivait dans le **déposeur**, donc
  une release **locale** n'était jamais signée et le banc `.deb` ne pouvait mesurer que
  `[trusted=yes]` ; la signature est désormais écrite par l'**indexeur**
  (`make release-apt SIGN=yes`) parce qu'`InRelease`/`Release.gpg` sont **nuls dès que
  `Release` change**. Trois conséquences **à ne pas défaire** : une release est **complète avant
  d'être déposée** ; le déposeur **retrouve sa règle sans exception** — *il n'écrit rien dans un
  répertoire de release* (ép. 24) — il ne fait plus que **vérifier** et **refuse** un
  `InRelease` qui ne vérifie pas contre la clef publiée ; et **tout script qui réécrit
  `Release` doit re-signer** (`release.retention.sh` relaie `--sign` ; sans lui l'indexeur
  **supprime** l'`InRelease` périmé — un dépôt qui **cesse** d'être signé est pire qu'un dépôt
  jamais signé). `--sign` **seul** lit l'empreinte **dans la clef publiée** (identité en un seul
  endroit, motif ép. 8/26), et signer avec une autre clef est refusé **en nommant les deux**.
  **Deux pièges** : le `trap … EXIT` du trousseau de vérification aurait **remplacé en silence**
  le `cleanup` fermant la connexion ssh maîtresse (piège ép. 25, évité par son propre
  commentaire) ; et le **6ᵉ** défaut de la famille « juger par autre chose que ce qu'on
  mesure » était dans mon cas neuf — avec une clef étrangère `apt-get update` **rejette** la
  signature **et sort avec 0** en réutilisant les index précédents, donc le verdict se lit après
  `rm -rf /var/lib/apt/lists/*`, sur ce qu'apt **peut voir**. La clef étrangère du cas est le
  **trousseau de la distribution** (`/usr/share/keyrings/*archive-keyring.gpg`) : forger une clef
  dans la boîte est mort-né (pas de pinentry). **Le canal RPM reste non signé** (`gpgcheck=0`),
  et la page INSTALL le dit avec sa raison : là-bas rpm vérifie **chaque paquet** plus
  `repomd.xml` — c'est l'ép. **30b**, avec la même clef.
  **Ép. 30 bis : le canal hors bande, mesuré — et `-L` est un piège.** Le rejeu distant a rendu
  2 rouges qui étaient tous deux des défauts de **mesure** (comparer `$(curl …)` à un fichier :
  `$(...)` **supprime les sauts de ligne finaux** ; et une boîte nue sans CA ni téléchargeur qui
  faisait rapporter le défaut de l'ép. 28 à propos d'une destination **jamais calculée** — d'où
  un **verdict distinct** quand la ligne « destination » est absente). Puis, en **nommant le code
  HTTP** au lieu de supposer « pas encore poussé », le banc a montré que `git.launchpad.net`
  répond **`302` environ 1 fois sur 6, vers `login.launchpad.net` (OpenID)**. **À ne pas
  défaire** : le banc **réessaie** et ne suit **jamais** la redirection, et la page **interdit
  `-L`** — le suivre rapporte une **page de login** (26 o) que `curl -o` écrit dans le fichier de
  clef **sans un mot** ; *un canal hors bande qui échoue en donnant les mauvais octets est pire
  qu'un canal qui échoue*, d'où la **vérification d'empreinte rendue obligatoire** dans la page.
  **Feuille de route (§ 5 bis du doc, elle PRIME sur le § 5)** : (1) finir le local *(fait,
  ép. 11)* → (2) les 4 boîtes Debian 12/13, Ubuntu 24.04/26.04 *(fait, ép. 12)* → (3) le
  découpage en `.deb` *(fait, ép. 13)* → (3 bis) `doc-src/` s'installe *(fait, ép. 14)* →
  (4) les `.deb` sur les 4 boîtes — **15a les fabriquer *(fait)*, 15b les installer
  *(fait)*** → (5) `upload.www.marionnet.org.sh` + point d'entrée apt stable
  *(fait, ép. 24)* → (6) rejeu de (2) et (4) contre le vrai serveur *(fait, ép. 27)*.
  (5 bis) la **doc INSTALL** *(fait, ép. 29)*. **Plus aucun point n'est ouvert.**
  **Plus aucun point n'est bloqué par l'extérieur** : le site est revenu le 2026-08-31 et la
  release 1.0.x y est déposée. Le décalage du canal `.deb` est **résorbé** (ép. 25 ; vérifié
  ép. 30b : `r930` sur les 3 canaux).
  **Ép. 30b : le canal RPM est signé, et `gpgkey=` par URL ne tient pas.** Deux mécanismes, pas
  un — `gpgcheck=1` vérifie **chaque paquet** (`rpmsign`, qui tourne **sur la machine de
  release** : la clef privée n'entre jamais dans un conteneur, ce qui est légitime là où les
  métadonnées de rpmbuild ne le seraient pas, ép. 19) et `repo_gpgcheck=1` vérifie **l'index**
  (`repodata/repomd.xml.asc`, écrit par l'**indexeur** — règle de l'ép. 30 : une signature
  appartient à qui écrit le fichier signé, donc `release.retention.sh` relaie `--sign`).
  `--sign` couvre **tout** le répertoire, pas seulement ce que le run a construit : re-signer
  ne doit pas vouloir dire **reconstruire** (ce que l'ép. 20c a retiré de ce canal), et signer
  réécrit le fichier — donc le catalogue est corrigé paquet par paquet.
  **À ne pas défaire** : (1) la strophe publiée nomme la clef par un **fichier local**
  (`gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet`) et **jamais** par une URL — mesuré,
  `gpgkey=https://git.launchpad.net/…` a donné **3 échecs d'installation sur 8**, chacun
  **après 188 Mio téléchargés**, parce que **dnf suit les redirections** et que ce dépôt répond
  `302` vers sa page de login ~1 fois sur 6 (ép. 30 bis) : dnf importe **26 octets** et meurt sur
  `Failed to import OpenPGP keys`. C'est le `-L` interdit de l'ép. 30 bis, côté dnf, **où il ne
  peut pas être interdit** ; d'où la clef récupérée à la main, et **regardée avant d'être
  importée** (`rpm --import` *est* l'acte de faire confiance) ; (2) **`rpm --import` n'est pas
  l'import qui compte** : la base rpm est ce que lit `gpgcheck`, tandis que `repo_gpgcheck` est
  vérifié par dnf5 contre un trousseau **à lui**, par dépôt — d'où un rouge « 0 paquet » qui
  n'était qu'une clef non acceptée (accepter est une action que dnf **demande**, donc `-y`) ;
  (3) la signature du **précédent** index est retirée *avant* d'en tenter une neuve (sinon un
  échec laisse un dépôt qui **prétend** être signé), et le paquet est **relu** après `rpmsign`
  sur `%{RSAHEADER:pgpsig}` — **`SIGPGP` revient vide** sur un paquet correctement signé
  (mesuré) ; (4) le déposeur refuse un `repomd.xml.asc` qui ne vérifie pas contre la clef
  publiée, pendant exact de sa vérification `InRelease`, **sans rien écrire** dans la release.
  **3ᵉ liste de paquets** dans le `Makefile` — `REQUIRED_PACKAGES_RELEASE` (`rpm gnupg rsync
  dpkg-dev xz-utils`, cible `make apt-release-dependencies`) : à part des deux autres **à
  dessein**, la liste de build étant lue **par la boîte de compilation** (ép. 20) où `rpm`
  signerait... rien ; **Docker volontairement absent** (`docker.io` et `docker-ce` se font
  concurrence, en nommer un dirait à apt de casser l'autre). **8ᵉ défaut de la famille « juger
  par autre chose que ce qu'on mesure »** (19, 20b, 20c, 24, 27, 30) : le banc mesurait un
  `gpgkey=file://` **qu'il écrivait lui-même** pendant qu'on publiait une URL — un cas neuf lit
  désormais **la strophe publiée**. Mesuré : **214 verts / 0 SKIP** sur les 4 boîtes (les 4
  rouges étant le seul rouge assumé de l'ép. 28), dont le cas **discriminant** — dnf **refuse**
  quand `gpgkey=` nomme une autre clef.
  **Ép. 30b bis : la preuve distante, et un SKIP qui accusait le mauvais coupable.** Dépôt fait
  (le déposeur joue sa vérification neuve, 17 artefacts intacts côté serveur), **§ 3 de la page
  joué mot pour mot** sur une `fedora:42` nue → `marionnet-0~trunk+r930` avec `vde2` et
  `uml-utilities` **du même dépôt**. **À ne pas défaire** : le banc distant rapatrie
  `repomd.xml.asc` **comme l'index** — sans ces 833 octets il SKIPait en **nommant une cause
  fausse** (« indexed without `--sign` ») à propos d'un serveur qui venait de signer, et surtout
  `REPO_SIGNED` restant à 0, les **6 cas de boîte** propres à un dépôt signé — dont le
  **discriminant** — ne tournaient **pas du tout** en distant. *Un SKIP qui accuse le mauvais
  coupable est pire qu'un SKIP.* Mesuré : **218 verts / 0 SKIP** sur les 4 boîtes contre le vrai
  serveur (le rouge unique restant celui, assumé, de l'ép. 28).
  **Ép. 30b ter : une mesure qui peut perdre une course n'est pas une mesure.** `host_glibc` de
  `release.binary.sh` lisait `ldd --version | head -n 1 | awk …` — or **`/usr/bin/ldd` est un
  script bash**, il écrit plusieurs fois, `head` ferme le tuyau, SIGPIPE, et sous `pipefail`
  toute la substitution échoue en répondant `unknown-libc` (**mesuré : 14 échecs / 400 avec le
  tuyau, 0 / 400 sans**). Le coût n'était pas l'arrêt bruyant de la release r937 mais le **même
  tirage sur l'appel qui NOMME l'artefact publié** : depuis l'ép. 12 le nom est le **seul endroit
  où le plancher glibc est écrit**. **À ne pas défaire** : capture sans tuyau (`awk` sur une
  here-string) **et** `artefact_name` qui **refuse de nommer** au lieu d'inventer `unknown-libc`
  (règle de l'ép. 20 appliquée à l'autre moitié du nom) ; le `README` du tarball lit le plancher
  **dans le nom**. Les 3 autres `| head` de `Makefile.d/` ne sont **pas** corrigés par symétrie :
  leur amont écrit en une fois, ou son statut n'est pas lu.
  **Ép. 30b quater : `make` propage ce qu'on lui donne.** `make release-and-upload SIGN=yes`
  faisait tout puis **mourait sur son dernier maillon** — make transmet aux sous-make les
  variables de **sa** ligne de commande, donc `SIGN=yes` atteignait le **déposeur**, dont la garde
  de l'ép. 30 le refuse à raison. Correctif : **affectation vide** (`$(MAKE) release-upload
  PRUNE=1 SIGN=`), celle d'un sous-make l'emportant sur l'héritée — *`SIGN` appartient à qui écrit
  un index, jamais à qui le transporte*. **`r938` est déposée** (une seule révision sur les 3
  canaux, les 2 dépôts signés) et les **2 bancs paquets rejoués contre le serveur** sont
  **entièrement verts** : `.deb` **38/0 ×4**, `.rpm` **57/0 + 55/0 + 56/0 + 54/0** — **374 cas,
  0 rouge, 0 SKIP**. Le rouge unique traîné depuis l'ép. 28 tombe : le paquet publié porte enfin
  l'installeur qui lit la cascade.
  **Ép. 30b quinquies : signer est le DÉFAUT, et ne pas signer par omission est impossible.**
  Chaque release réécrit `Release` et `repomd.xml`, ce qui **annule** les signatures d'à côté :
  un run sans `SIGN` ne saute donc pas une étape, il fait **supprimer** la précédente par les
  indexeurs — et un dépôt qui **cesse** d'être signé est refusé par tout le parc installé
  (`signed-by=` côté apt, `repo_gpgcheck=1` côté dnf), en silence de son point de vue. D'où
  (1) `make release-and-upload` **signe par défaut** (`RELEASE_SIGN`), ne pas signer s'écrivant
  `SIGN=no` ; (2) le **déposeur refuse** au lieu d'avertir, sur les 2 canaux — garde-fou du
  dernier instant qui rattrape aussi un `make release-upload` tapé à la main. **À ne pas
  défaire** : le sens de `SIGN=` est écrit **à un seul endroit** (`sign_flag` du `Makefile`,
  employé par les 5 cibles qui indexent — sans quoi `SIGN=no` se développait en `--sign no` et le
  publieur mourait en cherchant une clef nommée `no`), et la garde du déposeur teste ce que
  `SIGN` **veut dire**, pas sa présence.
  **Ép. 31 : la page d'installation en français.** `doc-src/INSTALL.FR.md` (pour le site web),
  **commitée** — d'où la différence avec `teacher-guide.FR.md`, qui se déclare lui-même
  traduction de relecture non versionnée : être dans git est le critère de l'ép. 14, donc la
  page FR est **nommée dans `doc-src/dune`** et installée par les 3 canaux, une ligne touchée.
  **À ne pas défaire** : les blocs de code sont repris **à l'identique** (ils ont été *joués* à
  l'ép. 29 ; les traduire publierait des commandes que personne n'a jouées) — seuls leurs
  commentaires sont traduits — et le tableau final nomme les pages **anglaises**, qui sont
  celles qui sont installées. **9ᵉ défaut de la famille « juger par autre chose que ce qu'on
  mesure »**, variante *fait recopié* : le banc du tarball comptait la doc livrée par un `26`
  **écrit dans le banc**, périmé par l'ép. 29 — rouge en puissance depuis 2 épisodes, invisible
  faute de rejeu depuis l'ép. 20. Le compte est désormais **lu dans `doc-src/dune`** et reste
  **exact** ; motif ancré sur une **strophe**, un `grep -c` naïf comptant le commentaire
  d'en-tête qui explique la forme.
  **Ép. 32 : le banc du tarball rejoué, sans code.** La release `r941` étant déposée juste
  après le commit de l'ép. 31, la preuve différée se prend : `release.binary.sh.bench`
  `--distro all` = **192/0/0** en local et **196/0/0** contre le serveur (49ᵉ cas par boîte =
  le digest servi, ép. 27 ; 4 glibc 2.36→2.43 contre un artefact à 2.36, le plancher de
  l'ép. 20 tient). **À ne pas défaire** : la discriminance est **mesurée** — le `run.sh` de
  `1042ff5^` rejoué sur le **même** tarball rend **47/1** (`expected 26`), donc le rouge latent
  de 2 épisodes existait bien. Motif de méthode confirmé une 3ᵉ fois (20c → 22, 28 → 30b
  quater) : *une preuve qui dépend de ce que la boîte contient se prend après le commit.*
  **Ép. 33 : la version cesse de s'appeler `trunk`.** `META` porte désormais la **série**
  (`version="1.0.x"`) et la révision qui l'ouvre (`series_base_revision="574"`) ; le niveau de
  patch est **dérivé** — `942 − 574` = **`1.0.368`** — par la **seule** implémentation de cette
  règle, `bin/meta.ml.maker.sh --print-version`, placée là où vit déjà `--print-revision` et
  par le même argument. Tous les autres **demandent** (`version.ml.maker.sh`, d'où une dep
  neuve dans `bin/dune` ; `release.binary.sh` ; `make version`), donc `Meta.version` et
  `Version.version` sont la même chaîne. **Aucun `.ml` touché** : `initialization.ml:39` teste
  déjà `^[0-9]+[.][0-9]+[.][0-9]+$`, et le `0~` des 2 publieurs n'existait que parce que META
  ne commençait pas par un chiffre — le chantier avait câblé ce jour-là sans l'écrire. **À ne
  pas défaire** : (1) une réponse **non numérique** (`1.0.x`) est ce que rend la règle quand la
  dérivation échoue (pas de VCS, pas de base, base en avance), et elle est **volontairement**
  non numérique — l'écran remontre alors la révision, et `artefact_name` **refuse de nommer**
  (rc 2, règle ép. 30b ter appliquée à l'autre moitié du nom) ; (2) **aucun motif de fichier ne
  doit épeler la version** — `release.retention.sh` le faisait dans ses 3 motifs, donc il
  n'aurait **plus rien matché**, rapporté **zéro** révision périmée, et le déposeur l'aurait
  cru (mesuré : 0 ligne contre 4 sur le même répertoire) : les formes sont ancrées sur le nom
  du paquet, le `r<chiffres>` et le champ suivant, ce qui garde dehors les paquets de données
  (aucun `+r` : ils sont versionnés par leur contenu, ép. 26) ; même défaut à une ligne dans le
  banc RPM, où il donnait un **SKIP**. **Renommer les paquets publiés ne suffit pas** (mesuré) :
  la version est dans les **métadonnées** que lisent `Packages`/`repodata/` **et compilée dans
  le binaire** ; **republier ne casse rien**, `0~trunk+r941` < `1.0.368+r943` côté dpkg **et**
  côté rpm — le `~` avait été écrit pour ce jour-là.
  **Ép. 35 : un fichier sudoers grante une salle, pas une personne.** Premier retour d'un
  **usage réel** (release 1.0.369 posée par `.deb` dans une salle MarioNUM) : `install student`
  **révoquait `teacher` sans un mot** — `install_block` régénérait le fichier pour le seul compte
  reçu — et `install student42` accordait un **compte inexistant** (`visudo -cf` ne pouvait pas
  le dire : nommer un compte à venir est légitime *pour sudo*). Même racine : le fichier était
  écrit pour **un** principal. Désormais il en grante une **liste**, `install` est **ADDITIF** et
  `uninstall USER...` est le **seul** retrait (sans USER : le fichier, comme avant). **À ne pas
  défaire** : (1) le fichier porte sa propre liste (`# principals: …`), avec repli sur le premier
  champ des règles pour un fichier d'avant ; (2) `install` régénère **tous** les comptes de
  l'union — d'où un `check` qui pose **deux** questions (grante-t-il chaque USER *et* est-il à
  jour pour ceux qu'il nomme) ; (3) `uninstall` ne valide **aucun** compte, à dessein — c'est la
  porte de sortie pour un `student42` déjà installé ; (4) un retrait qui ne retire rien ne
  réécrit pas le fichier ; (5) **`getent passwd 1000` répond, par uid**, alors que sudoers lit
  `1000` comme un **nom** — un principal numérique est refusé en nommant `#1000` ; (6) `--only`
  reste nécessaire, mais son danger a changé de sens (plus « X perd ses taps » : « Y **gagne** en
  silence le socle »). Mesuré en `debian:12` root : **10/0** sur le scénario rapporté,
  **discriminance 5/5** en rejouant le même banc sur le code d'avant, `visudo: parsed OK` sur les
  blocs (b) et (c) à deux comptes, bloc (a) intact par le chemin GUI. **Reste** : accorder à tous
  les humains sans connaître leurs logins (`%groupe` ⇒ `user *`, ou une porte privilégiée qui
  force le propriétaire depuis `$SUDO_UID`).
  **Ép. 36 : la salle entière, et ce que chaque bloc fait vraiment à la machine.** Un principal
  peut être un **`%groupe`** (validé par `getent group`) — le seul nom qui existe **avant** les
  comptes des étudiants. **`ALL` est refusé** (ce qu'un fichier accorde doit avoir été *décidé*,
  et `ALL` prendrait les comptes système ; le refus nomme `groupadd`/`gpasswd`) ; le précédent
  de la socket 0666 du daemon est ce que ce script a **terminé**, pas un modèle. **Seul
  élargissement** : la ligne du socle nomme le propriétaire du tap, qu'un groupe n'a pas
  (sudoers n'expanse pas « l'appelant » dans un argument), donc `user *` **pour les groupes
  seulement**, le fichier expliquant le joker là où il l'écrit — mesuré par `sudo -n -l` : un
  membre non-principal est **autorisé**, un non-membre **refusé**, `dev eth0` **refusé**, et
  donner un tap à un autre compte est la nuisance documentée (plus étroit que le
  `ip link set mtap* *` que tout compte autorisé a déjà). **À ne pas défaire** : `check` répond
  sur les principaux que le fichier **nomme** — un membre d'un groupe autorisé n'en est pas
  un — la question des droits **effectifs** étant `sudo -l -U <login>`. **Page INSTALL § 7
  refaite ×2 langues** : ce que chaque bloc fait à l'hôte — (b) `ip_forward` **host-wide**
  (restauré seulement s'il l'a mis), 1 MASQUERADE + 2 FORWARD **toutes tagguées**
  `marionnet-natbridge:mnbr*` (c'est ce tag exigé qui rend intouchable une règle préexistante),
  dnsmasq **lié au seul pont**, IPv6 qui fait de l'hôte un **routeur** (d'où la porte
  `accept_ra`), **carte de l'hôte jamais nommée** ; (c) carte asservie, adresse et route par
  défaut **déplacées**, MAC clonée, VM **visibles sur le vrai LAN avec leurs MAC**, 3 lignes
  restreintes à **aucune** interface. **(b) sans (c) est le défaut** et n'a rien coûté : la GUI
  exige le mot de passe sudo **de l'utilisateur** au démarrage d'un pont. **Reste** : l'admin ne
  peut toujours pas **dire non** à (c) (un verrou ne protégerait que de l'erreur ; il devrait
  être lisible **sans privilège**, la GUI demandant le mot de passe *avant* de connaître le
  verdict — `bin/privileges.ml`).
  **Ép. 37 : le veto de l'administrateur — `deny` / `allow` / `policy`.** Retirer une
  autorisation n'empêche rien (l'utilisateur suivant la redemande depuis la GUI) : l'admin peut
  désormais **interdire** un bloc de pont sur la machine. **Le marqueur n'est PAS dans
  `sudoers.d`, et c'est la GUI qui l'impose** : `privileges.ml` **demande le mot de passe
  d'abord** et apprend le verdict ensuite, or un fichier de `sudoers.d` est **0440 root** — et
  tout ce qui y traîne est **analysé par sudo**, qui n'est pas un endroit pour un non-règle.
  D'où `/etc/marionnet/<bloc>.denied` en **0644**, chemin absolu **indépendant du préfixe**
  (`MARIONNET_SUDOERS_POLICY_DIR` pour les bancs) : un veto est une décision **sur la machine**.
  **À ne pas défaire** : (1) `deny` **reprend l'octroi en place** (le laisser ferait du veto un
  mensonge — c'est ce fichier que sudo lit) ; (2) `install` refuse **avant de toucher à quoi que
  ce soit**, **rc 3** (distinct du mot de passe refusé 1 et de l'usage 2) en **nommant** la
  commande qui lève ; (3) le **bloc (a) n'a pas de veto** — l'admin l'accorde lui-même, donc
  l'interdire = ne pas taper la commande ; (4) `deny`/`allow`/`policy` refusent un USER (un veto
  vaut pour tous) et `--only`, et prennent les **sélecteurs neutres** `--natbridge`/`--lanbridge`/
  `--bridges` (acceptés partout) ; (5) côté GUI la sonde **n'est pas mémorisée** (le veto peut
  être levé pendant que Marionnet tourne) et **tout ce qui n'est pas rc 3 n'est pas un veto** —
  un script d'avant répond **2** (mesuré) : *refuser de travailler parce qu'on n'a pas pu poser
  la question est le contraire du but*. **i18n** : 1 msgid générique (le titre dit déjà quel
  pont) → **436 traduits, 0 trou ×12**, arité 1/1, **12 `.mo` interrogés par clé exacte**.
  **Ce que ça vaut, écrit dans la doc** : ça arrête l'**erreur**, pas un sudoer complet.
  **Mesuré** : veto **19/0**, commandes du § 7.4 jouées **13/0** (discriminance **3/13** sur le
  code d'avant), `make check` rc 0. **Non joué** : la branche GUI (dialogue **modal**, un banc
  `driven-sessions` s'arrêterait dessus) — le chaînon non mesuré est **un `if`**.
  **Ép. 38 : le nom que la documentation tape n'existait pas.** `type marionnet` → *non trouvé*
  sur une machine installée : **manque d'origine** (`EXECUTABLES = marionnet.native` depuis
  l'ère ocamlbuild), invisible parce qu'un développeur lance son binaire par un chemin. Or
  `doc-src/` — ce que les 3 canaux **installent** — contient **plus de 20 lignes de commande**
  en `marionnet …` (guide de l'enseignant ×2, `exam-mode`, `lab-design-skill`, exemples du
  canal, TP session-7) et **5 scripts d'exemple** qui le nomment ; et la page INSTALL ne disait
  **pas comment lancer**. **Leçon** : la règle de l'ép. 29 (*jouer les commandes qu'on écrit*)
  n'avait été appliquée qu'à **une** page — jamais aux documents qui voyagent avec le produit.
  **Correctif** : `ln -sfT marionnet.native` dans le **staging** de `release.binary.sh` (donc
  tarball + `.deb` assemblé du staging + `.rpm` déplié du tarball ; `cp -a` et `tar` gardent le
  lien — mesuré, membre tar de **0 octet** — et `%{_bindir}/*` le prend), plus
  `install-final-as-root`, `install-for-testing` et son `uninstall` (dune ne connaît pas ce
  lien). **À ne pas défaire** : (1) un **lien**, pas une copie (binaire = **27 Mio**) ; (2)
  **relatif**, donc il survit au déplacement du préfixe ; (3) `marionnet.native` **reste le vrai
  nom** (le renommer aurait un rayon d'impact sans rapport : `marionnet-install.sh`,
  `release.binary.sh`, les 3 bancs) ; (4) `bin/development_tree.ml` ne lit que des **noms de
  répertoires**, jamais le nom du binaire — vérifié avant. **Banc** : le `26 names` écrit en dur
  (faute de l'ép. 31) est **lu dans l'artefact** (`ls $UNPACKED/bin`), ce qui dit enfin la vraie
  propriété — *install.sh ne perd rien de ce que l'artefact porte* ; les bancs `.deb`/`.rpm`
  passent à 27, **écrit** car dériver du paquet qu'ils mesurent serait une tautologie.
  **Différé** (pas de release avant la fin de la campagne de bugs) : 4 cas rouges par
  construction jusqu'à la prochaine release, motif habituel.
  **Ép. 39 : la liste blanche de 2007 — on mesure, on ne devine pas.** L'avertissement
  « Fichiers creux (sparse) non pris en charge ! » au démarrage était **faux, et pour toute la
  salle à la fois** : `can-directory-host-sparse-files.sh` déduisait le type de système de
  fichiers (`df -P` + `mount -l`) et le comparait à une **liste blanche de 2007** où `overlay`
  — le stockage de **tout conteneur Docker** — ne figure pas (ni `btrfs`/`zfs`/`f2fs`/
  `bcachefs`, et `xfs` en avait été *retiré* sur une observation d'Ubuntu 12.04). Deux sites
  touchés : le dialogue de `bin/marionnet.ml:350-356` et le refus « Invalid directory » du
  sélecteur (`bin/gui/talking.ml:357`). Le script **mesure** désormais : `mktemp` **dans
  `$DIR`**, `truncate -s 1M`, `stat -c %b`, `trap … EXIT`, verdict = blocs alloués < ¼ de la
  taille apparente. **À ne pas défaire** : contrat de sortie **inchangé** (0/1/2/3, l'appelant
  ne lit que 0) ; `truncate`/`stat` manquants ⇒ **2**, pas 1 (*ne pas pouvoir mesurer n'est pas
  un verdict négatif*) ; la sonde vit **dans le répertoire testé**. **Pourquoi pas ajouter
  `overlay` à la liste** : la liste **est** le défaut — motif de l'ép. 31 (*un fait recopié se
  périme*), appliqué à une liste. `tmpfs` reste accepté (les trous y marchent) ; sa
  consommation de RAM est le **C2** de `bug-critique-crash-host`, distinct. **Mesuré** :
  overlay **rc 1 → rc 0** (discriminance), **vfat** en boucle → 2048 blocs pour un trou de
  1 Mio, **rc 1** (le cas négatif est réel) ; ext4/tmpfs/`/var/tmp` rc 0, inexistant 3, non
  inscriptible 2, **0 résidu** ; **piège n° 7 vérifié** — `strings` sur le binaire : **1**
  occurrence du texte neuf, **0** de `WHITE_LIST`.
  **Ép. 40 : l'avertissement des taps accusait le seul coupable qu'il savait nommer.** « La règle
  sudo n'est pas installée » alors qu'elle l'était : **mesuré**, le conteneur n'expose pas
  `/dev/net/tun` (et l'invité bootait avec `eth42=tuntap,wrong-tap-name,…`, d'où `xeyes` sans
  display). **L'avertissement était VRAI, son TEXTE faux** — le taire aurait masqué une panne
  réelle. `Tap_provider` rend désormais une **cause** (`No_tun_device` / `No_permission` /
  `No_sudoers_rule` / `Unclear of string`) ; `is_usable` est **conservé** (`= unavailability () =
  None`). **À ne pas défaire** : (1) le **périphérique est regardé d'abord**, et alors **aucune
  commande n'est lancée** (exact, gratuit, répond même si sudo est cassé) ; (2) `open: No such
  file or directory` est **aussi** reconnu dans le message — le test de fichier peut passer et la
  commande échouer quand même ; (3) les aiguilles « sudo » sont ses **refus**, jamais le mot
  `sudo` (`sudo: command not found` le contient : y répondre « installez la règle » serait le
  défaut qu'on corrige) ; (4) `unavailability_of_error` est **pur et exposé** (motif de
  `sessions_of_taps`). Côté GUI **un message entier par cause**, celui de la règle **inchangé à
  l'octet** (ses 12 traductions survivent) et le `%s` d'`Unclear` **échappé** (Pango, ép. 9a).
  **La cause prise à l'installation** : `bin/scripts/marionnet-tun-check.sh` (script neuf, 26ᵉ
  compagnon), appelé par les **3** canaux (install.sh, postinst, %post), **jamais fatal** — un
  `postinst` tourne aussi dans un chroot ou une image en construction, où l'absence du nœud est
  **attendue**, et il le dit — et il **ne charge aucun module** (*nommer, pas faire*, ép. 13).
  **Mesuré** : classificateur **5/5** ; le vrai code OCaml dans **5 boîtes** rend les 5 verdicts
  attendus ; le script **rc 1/1/0** sur les 3 situations ; **non-fatalité prouvée** sur un vrai
  tarball (`--output-dir` hors release) — `install.sh` rc **0**, **28 noms** dans `bin/` ; i18n
  **439/0 ×12**, **36/36** dans les `.mo`. **Reste** (versé à `docs/TODO.md`) : une VM démarre
  **sans le dire** avec `wrong-tap-name`. Bancs `.deb`/`.rpm` : compte 27 → **28**, rouges par
  construction jusqu'à la prochaine release.
  **Ép. 41 : la garde ne posait pas la bonne question, et l'avertissement accusait au hasard.**
  Le bridge NAT annonçait « aucun réseau privé » **titre en français, corps en anglais**, avec
  `E_SUDO_DENIED` et pour conseil *« choisissez une autre adresse IPv4 »* — trois défauts dans un
  message. **(1) La cause** : `Privileges.ensure_block` rend `Ok ()` **sans proposer le mot de
  passe** dès que sa sonde dit oui, et la sonde était `status` — qui, **mesuré**, n'invoque
  **aucun** `sudo` (`bash -x … status` : 0 occurrence ; il lit `/proc` et énumère les ponts avec
  un `ip` non privilégié), là où le commentaire du code prétendait qu'il « exerçait
  iptables-save ». La sonde répondait donc **oui sur toute machine**, bloc (b) installé ou non :
  sur **toute installation neuve** la GUI ne demandait jamais le mot de passe, et le refus
  tombait à `up` quand plus personne ne peut le demander. **Le remède était déjà à côté** : `check-privileges`
  du LAN bridge (ép. 7b) — une vraie commande de notre liste, sans effet — avec ses 2 pièges
  payés (verdict lu dans le **libellé**, d'où `LC_ALL=C` ; **`sudo -n -l` inutilisable**, il
  répond « autorisé » sur un poste `%sudo ALL`) ; **à ne pas défaire** : le nom de sonde est
  `mnbr999999999` et non `mnbr999`, les vrais noms portant un **pid** (plafonné à 2²²), là où un
  pid 999 existe. **(2) La langue** : les **continuations `\` indentées** d'un littéral — OCaml
  mange le saut de ligne *et* les blancs, l'extracteur POT camlp4 non — donnaient un `msgid` que
  le programme **ne demande jamais** ; c'était le seul du dépôt, d'où la règle : *un littéral
  traduisible s'écrit sur une seule ligne*. **(3) Le conseil** : `advice_of_error` (pure, patron
  ép. 40) classe le **code symbolique** — règle sudoers pour `E_SUDO_DENIED`, adresse pour
  `E_SUBNET_IN_USE`, commande nommée pour `E_NO_*`, et **rien** pour un code inconnu. i18n : les
  2 phrases déjà traduites sont **reprises** (découpées à l'endroit du `<tt>`), seule la
  conditionnelle « si le réseau … » devenant affirmative → **442/0 ×12**, 48/48 clefs exactes
  dans les `.mo`. **Banc neuf** `driven-sessions/nat-bridge-warning-names-its-cause.sh` (ni
  privilège ni invité : commande hôte fausse, et `sudo` remplacé par le `PATH`) : **11/0/0**,
  **1/10 sur le code d'avant** — le seul vert étant `E_SUBNET_IN_USE`, la cause que l'ancien
  message nommait *par hasard*. **Reste** (versé à `docs/TODO.md`) : le **LAN bridge** n'a
  toujours aucun avertissement de démarrage.
  **Ép. 42 : le périphérique manquant se répare, et c'est l'APPLICATION qui le fait.** Né du
  constat *« un contrôle sans corriger la cause »* (ép. 41 bis). La piste proposée — le `mknod`
  dans les 3 canaux d'installation — est **écartée par la mesure** : `/dev` est volatile
  **partout**, devtmpfs recréé à chaque boot (avec `CONFIG_TUN=y` et
  `50-udev-default.rules` → **udev repose le nœud tout seul**, donc rien à réparer là) et
  **tmpfs neuf à chaque démarrage de conteneur** (donc un nœud fait au build ou par un
  `postinst` a déjà disparu) — *le seul geste qui dure est celui que l'application répète à
  chaque démarrage*. Les 3 canaux restent donc inchangés, et c'est désormais juste
  **techniquement**, plus seulement par principe (ép. 40). **L'objection qui a façonné la
  conception** : `mknod` d'un périphérique caractère exige **`CAP_MKNOD`**, qu'un compte
  non-root n'a pas — même dans un conteneur qui l'a dans son *bounding set* — d'où une
  **porte + sudoers**, comme tout geste privilégié ici. **`bin/scripts/marionnet-tun-device.sh`**
  (27ᵉ compagnon, patron `marionnet-ipv6.sh` : `create`/`status`, **zéro argument variable**,
  chemin et major/minor dans le fichier ⇒ règle **entièrement littérale**) est grantée par le
  **socle, bloc (a)** : ce qu'elle accorde est *ce que udev accorde déjà partout*, et le nœud est
  la **précondition** des taps, pas un pouvoir de plus. **À ne pas défaire** : (1) ce n'est
  **pas** un `--repair` de `marionnet-tun-check.sh` — 110 lignes qui tourneraient en root, et son
  en-tête énonce qu'il ne crée aucun périphérique ; (2) un nœud déjà là est un succès qui **ne
  touche pas son mode** (un mode délibérément restreint n'est pas écrasé) et un fichier de la
  mauvaise nature est **nommé, jamais remplacé** ; (3) `Tap_provider.ensure_tun_device` (patron
  d'`ensure_sudoers_rule`) **jette le cache `verdict` et re-mesure** — créer le nœud ne prouve
  pas qu'on puisse en faire un tap (cgroup, `TUNSETIFF`) ; (4) `bin/marionnet.ml` ne l'appelle que
  sur `No_tun_device`, et **se tait quand ça marche**. **Épisode gratuit en i18n (0 `msgid`
  neuf)** : un refus de `sudo` est rendu **`No_sudoers_rule`**, dont le message existant est
  *exactement* le bon remède — **conséquence à retenir : une machine déjà grantée doit
  réinstaller le socle** pour gagner la porte (`install` est additif, ép. 35). Mesuré : banc
  conteneurs **13/0**, **discriminance 2/11** sur le code d'avant ; les 4 branches de la porte
  (créée / non-root / `--cap-drop MKNOD` / mauvaise nature) ; sur une vraie machine
  **aucune tentative, aucun `sudo`** ; compte de noms **dérivé** (27 compagnons + binaire + nom
  nu = **29**), les 2 bancs paquets 28 → 29 donc **rouges jusqu'à la prochaine release**.
  **2 défauts de banc** (famille « juger par autre chose que ce qu'on mesure ») : `echo | check`
  perd ses compteurs dans un **sous-shell**, et un montage nommé `/scripts` faisait exercer le
  script **du dépôt** au lieu de la porte **installée** — le banc condamnait un code correct.

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
  note utilisateur : `doc-src/project-format-v3.md`),
  `docs/journalisation-profonde.md` (**journalisation jusqu'à l'intérieur des invités, et le mode
  examen** — 25 épisodes, clos 2026-08-15 ; § 8 = résultat ; à lire avant de toucher les scripts
  déposés dans le hostfs (`bin/scripts/marionnet-*.sh`), un journal servi par le canal, ou
  l'archivage du mode examen ; notes utilisateur : `doc-src/teacher-guide.md`,
  `doc-src/exam-mode.md`, `doc-src/lab-design-skill.md`),
  `docs/todo-transverse.md` (**solde de la TODOLIST transverse** — 28 défauts indépendants,
  4 tournées, clos 2026-08-22 ; **§ 6 = résultat + § 6.1 index des pièges durables**, § 4/4 bis/
  4 ter/4 quater = les tournées ; à lire avant de rouvrir un défaut qu'on croit neuf, ou avant
  de toucher un banc de `driven-sessions/`),
  `docs/pilotage-par-script.md` (**canal de contrôle scriptable** — serveur in-process sur socket
  unix, requête = ligne texte, réponse = ligne **JSON** ; 14 épisodes, clos 2026-08-15 ; § 12 =
  résultat + **index des pièges durables**, § 9 = table des épisodes ; à lire avant de toucher
  `bin/control_server.ml`, `bin/script_mode.ml` ou un client du canal (`bin/scripts/`). **Invariant à
  ne jamais enfreindre** : la grammaire a **une seule** source de vérité — le serveur, publiée par
  `help` ; aucun client ne la recopie. Notes utilisateur : `doc-src/scripting/`),
  `docs/move-and-rename-useful-scripts-to-bin-scripts.md` (**où va un script, et pourquoi les
  liens** — les 5 compléments du binaire ramenés de `useful-scripts/` vers `bin/scripts/`,
  6 épisodes, clos 2026-08-23 ; § 1 = la règle fondatrice, § 2 = la forme « `.sh` réel + liens »
  qui rend la migration non cassante, § 3 = les invariants ; à lire avant de créer, déplacer ou
  renommer un script du dépôt — et avant de croire qu'un nom d'usage a disparu),
  `docs/migration-ocaml5.md`
  (OCaml 5.4.1, clos 2026-07-27), `docs/finitions-port-dune.md` (clos 2026-07-18),
  `docs/daemon-elimination-study.md` (clos 2026-07-17).
- **Bancs de session pilotée** (preuves rejouables, sans invité ni privilège) :
  `driven-sessions/README.md` — conventions (PASS 0 / SKIP 77 / FAIL autre ; un banc doit
  **échouer** sur le code d'avant) et les règles payées par la mesure : une session se termine par
  le canal ou par **SIGKILL** (SIGTERM est neutralisé), un banc qui matche un texte **fige la
  langue**, et sous `timeout` le pid à viser est celui de la **session**, jamais celui du
  mandataire. Ajouter un banc ici quand la preuve d'un correctif est rejouable partout.
- **TODOLIST transverse** : `docs/TODO.md` — améliorations repérées hors de tout chantier en cours
  (ce qui relève d'un chantier reste dans son doc, § « Reste au chantier »). Chaque entrée porte le
  constat, ce qu'on veut à la place, et l'obstacle d'implémentation déjà identifié. **Son solde a
  été un chantier, clos le 2026-08-22** (28 entrées, archive `docs/todo-transverse.md`) : il n'y
  reste que l'idée *« composer deux projets »*, hors périmètre parce qu'elle est une
  fonctionnalité. Une entrée neuve **rouvre la question**, elle ne se traite plus par ce chantier.
- **Rôle d'un fichier** : `CLAUDE-file-overview.md` du dossier (`bin/`, `bin/gui/`).
- **Chantiers** (skills à charger en l'annonçant) : `marionnet-composants`, `marionnet-build`,
  `marionnet-gui`, `marionnet-pupisto` (`.claude/skills/`).
- **Concevoir, jouer et NOTER un TP** (canal de contrôle + mode examen) : skill
  `marionnet-lab-design`, qui renvoie au document livré `doc-src/lab-design-skill.md`.
- **Code OCaml** (`bin/` + `lib/`, hors `uml/`) : skill `marionnet-ocaml` — outillage
  (`ocamllsp` via le plugin local `.claude/plugins/ocaml-lsp`, `sherlodoc` pour chercher **par
  type** dans ocamlbricks, `dune build @doc-private` pour odoc), règles d'écriture et pièges
  camlp4. **Fait établi** : `ocamlformat` ne parse pas cette syntaxe (`IFDEF`, `where_p4`,
  `INCLUDE DEFINITIONS`) — aucun formatage automatique tant que `camlp4-to-ppx` n'est pas fait.
- **Preuve datée** : `docs/audit-marionnet-20260706.md` (rapport d'audit, immuable).
