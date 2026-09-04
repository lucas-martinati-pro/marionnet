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

Reprise : appliquer le skill `chantier-long`. **Le journal d'un chantier vit dans son doc**
(`docs/<chantier>.md`, épisode par épisode) ; ici ne restent que **l'état** et les **gardes** —
les invariants qu'une édition de code pourrait défaire *en silence*, avec l'endroit où lire
pourquoi. Ne pas remettre de narration d'épisode dans ce fichier : il est relu à chaque session
(et un bloc de plus de ~50 lignes sans respiration coûte ~45 s de CPU au démarrage — mesuré).

- **modernisation-installation-marionnet** (chantier PARENT : diffusion moderne — installeur,
  tarball, `.deb`+apt, `.rpm`+dnf, Docker) : `docs/modernisation-installation-marionnet.md`
  (47 épisodes) ; mémoire `modernisation-installation-marionnet` ;
  `git log --grep="modernisation-installation-marionnet"`.
  **État** : feuille de route SOLDÉE — release `1.0.369+r943` signée et en ligne sur les 3 canaux,
  **6 publieurs** + déposeur + rétention, **4 bancs** rejouables contre le vrai serveur.
  **Campagne de bugs « usage réel » OUVERTE** depuis le 2026-09-02 (salle MarioNUM, ép. 35→46).
  **Consigne active : AUCUNE release avant la fin de la campagne** — d'où des cas de banc *rouges
  par construction* (le paquet publié porte l'installeur d'avant), et la règle qui en découle :
  *une preuve qui dépend de ce que la boîte contient se prend après le commit*.

  **Gardes** (le pourquoi est dans le doc, § de l'épisode cité) :
  - le **répertoire de release** est `website-repo/download/marionnet-install.sh/<série>/`, et
    `website-repo/` est **gitignoré** — donc invisible d'un `grep` du code (ép. 6) ;
  - le **nommage est la seule clef** (`filesystems_<X>.tar.*` ⇒ `share/marionnet/filesystems/<X>`) ;
    extraction par `xz -dc -T0 | tar xf -` et **jamais** `tar xJf` (facteur 4) ; **jamais** `-m` /
    `--touch`, `--owner=root --group=root` à la création — le `mtime` d'un *backing file* est ce
    qu'UML vérifie (ép. 3, 23) ; une image *router* est un **lien** vers l'image *machine* ;
  - **`SHA256SUMS` a un seul écrivain**, `Makefile.d/release.sha256sums.sh` : un artefact déposé
    autrement est **invisible** de l'installeur (ép. 8) ; les **index** (`Packages`, `repodata/`)
    n'y sont **pas** (réécrits à chaque publication ⇒ digest périmé tout seul) ; **3 catalogues**
    cohabitent, aucun dérivable des autres (ép. 15b, 18) ;
  - **on construit sur la plus ancienne boîte qu'on sert** (`--build-image`, défaut `debian:12`) :
    la compatibilité glibc ne voyage que vers l'avant, et les générateurs de dépendances écrivent
    les conventions de la distribution **où ils tournent** (ép. 19, 20, 20b, 20c) ; le plancher
    glibc est écrit dans le **nom** de l'artefact, donc `artefact_name` **refuse de nommer** plutôt
    que d'inventer (ép. 30b ter) ;
  - **la signature appartient à qui écrit le fichier signé** — les indexeurs, jamais le déposeur ;
    tout script qui réécrit `Release`/`repomd.xml` doit **re-signer**, signer est le **défaut**, et
    la clef publique se distribue **hors bande** (Launchpad), jamais à côté des paquets (ép. 30,
    30b, 30b quinquies) ;
  - **le déposeur n'écrit rien dans un répertoire de release** ; ce qui monte est ce que
    `SHA256SUMS` nomme, et la preuve d'intégrité se prend **sur le serveur** (ép. 24) ;
  - **une seule source de vérité pour les dépendances runtime** : le `Makefile`, lue à travers
    `make`, transportée **comme donnée** dans le tarball ; ne pas ajouter de paquet sans site
    d'appel ni en retirer sans rejouer le banc (ép. 1, 9b, 10) ;
  - `dune install` pose **0644 hors `bin`/`libexec`** (bit `x` des exemples restauré par les
    3 canaux) ; doc et complétion s'installent en section **`share_root`**, la complétion sous
    **un fichier par nom de commande** (ép. 11a, 14) ;
  - `marionnet.native --paths` est le **seul lecteur** de la cascade de configuration — ne pas
    relire le `.conf` en bash (ép. 28) ; `marionnet` est un **lien relatif** vers
    `marionnet.native`, qui reste le vrai nom (ép. 38) ;
  - un fichier sudoers **grante une liste** de principaux (`install` additif, `uninstall` seul
    retire ; `%groupe` accepté, `ALL` refusé), et le **veto** admin vit dans
    `/etc/marionnet/<bloc>.denied` (0644, hors de `sudoers.d`) parce que la GUI demande le mot de
    passe **avant** de connaître le verdict (ép. 35, 36, 37) ;
  - la hauteur de la fenêtre principale est **mesurée**, jamais devinée (aucun `default-height` ;
    `show-arrow=False`, sans quoi la palette **déborde** au lieu de réclamer) — et l'ajustement
    n'agit que sur une mesure **stable**, deux réveils qui s'accordent : lue au premier layout
    venu, elle voit une palette qui n'a pas encore demandé sa hauteur et laisse la fenêtre trop
    courte *une fois sur trois* (ép. 43, 43 bis) ;
  - **ne pas éditer un script bash pendant qu'il tourne** (bash lit par offsets d'octets) ; il n'y
    a **qu'un** gestionnaire `EXIT` (ép. 24, 25) ;
  - famille de défauts revenue **10 fois** : *juger par autre chose que ce qu'on mesure* — un
    verdict se lit sur le symbole exact, jamais sur un libellé, un code de retour complaisant
    (`apt-get update`, `zypper`) ou un fait recopié dans un banc (index des occurrences au doc).

- **noyaux + rootfs** (intégration Dave Appadoo ; Trixie + UML 6.12 ; touche `uml/` **et** l'OCaml
  par un dispatch de boot compat SysV/systemd) : `docs/kernel-rootfs-refresh.md` (ép. 0→28) ;
  mémoire `marionnet-kernel-rootfs` ; `git log --grep="marionnet-kernel-rootfs"`.
  **Bloque vwifi.** **État** : le boot trixie est propre et le prompt de login est enfin la
  dernière ligne de la console ; reste le test GUI intégral (`GHOSTIFICATION=netns`).

  **Gardes** :
  - deux défauts de boot sont corrigés **sur l'hôte**, à la ligne de commande noyau
    (`bin/simulation_level.ml`) — donc valables pour les images **déjà publiées**, et à ne pas
    déplacer dans une image : masque de `systemd-networkd-wait-online` (hors de la branche du
    masque `serial-getty` et hors de `boot_quirks`) et masque de **`getty.target`** — la *target*,
    jamais l'instance ; **rien** sous SysV (un argument inconnu partirait à `init`) (ép. 21, 28) ;
  - le publieur d'images **refuse** un instantané au boot lent et **nomme** son remède ; il
    accepte les deux issues (lien retiré **ou** unité masquée) ; il **refuse** aussi (rc 2) une
    image dont le `mtime` a dérivé, au lieu de la réparer — une image dont le contenu change se
    republie **sous un autre nom**, son nom *étant* son `sum` (ép. 21 bis, 23) ;
  - mettre à jour une image publiée est **une commande**
    (`filesystem.update-published-image.sh --image … --in-guest 'CMD'`), l'export de variante
    passant par `history-export` (donc **aucun `cp`**), jamais à la main (ép. 22, 23) ;
  - `add machine` lit `MEMORY_SUGGESTED_SIZE` (sans quoi trixie meurt d'OOM), mais `--memory=N`
    et un `.mar` restent souverains, et `set <n> distrib` n'ajuste **pas** la mémoire (ép. 24).

- **triage des binaires d'une image invitée** (chantier **enfant** du précédent) :
  `docs/triage-binaires-image-invitee.md` (ép. 0→7) ; mémoire `triage-binaires-image-invitee` ;
  `git log --grep="triage-binaires-image-invitee"`. **État** : les **3 étages existent** — la
  sonde (2060 candidats en un boot), la **politique** gelée
  (`uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.trixie.tsv`, 225 lignes), et les
  deux applicateurs : `Makefile.d/filesystem.apply-binary-policy.sh` pour une image publiée,
  `apply_binary_policy` de `pupisto.debian.sh` à la construction. **Rien n'a été appliqué à
  16341, et rien ne le sera** (ép. 7). Reste : l'ép. 8 (les 7 `ignore` posés sur des cassés, les
  2 `fix` réseau aux noms de paquets non vérifiés), puis la clôture.

  **Gardes** : l'agent est **entre** la sonde et la politique, **jamais dans la boucle** ; une
  sonde **ne publie jamais** (COW jetable) ; `/loop` est refusé (un boot par itération) ; un
  verdict X est une propriété du **couple (image, serveur X)**, que l'en-tête du rapport nomme ;
  la sur-approximation du classificateur est **du bon côté** (un faux positif se classe `ignore`
  une fois, un faux négatif laisse passer une application graphique sans jugement), et la colonne
  **`via`** existe pour qu'un humain puisse la contester ; **un `rc` ne dit pas si le binaire a
  démarré** — c'est le **message** qui le dit (33 cassés étaient classés `OK`, d'où `BROKEN`,
  ép. 3) ; la politique **ne porte que des exceptions**, mais **une ligne par cas examiné**,
  sans quoi 165 cas se re-jugeraient à chaque image ; **une action de politique se mesure dans
  l'invité avant d'être appliquée** (`--no-export` : mesurer sans produire d'image), et un
  verdict de **cause structurelle** se vérifie **par la structure**, jamais par le seul motif
  du message — c'est ce qui a réfuté l'action de l'ép. 3 et trouvé 7 cassés de plus (ép. 4) ;
  **la question qui décide d'un `drop` porte sur le PAQUET**, pas sur le binaire — *P a-t-il
  encore un intérêt sans X ?* —, elle se pose **à chaque maillon** de la chaîne de dépendances,
  et les paquets s'y **nomment** (jamais d'`autoremove`) : un binaire qui marche peut devoir
  partir, un paquet fautif devoir rester (ép. 6) ; **le format à 4 colonnes n'a qu'UN lecteur**
  (`--print-actions` de l'étage 3a) — `pupisto` (étage 3b, dans son chroot, juste avant
  `clean_debian_filesystem`) lui **demande** les actions au lieu de reparser ; et **une image
  publiée ne se reprend pas pour le principe** : on la reconstruit quand un binaire **du
  périmètre du TP** est cassé, pas pour un `qmake` mort — d'où 16341 laissée en l'état, et une
  politique qui décrit un état **voulu**, divergeant volontairement de l'image en ligne (ép. 7).

- **modernisation-world-bridge** (l'accès au vrai réseau sans config hôte risquée ; le « mode »
  est devenu un **choix de composant** : menu planète *Gateway* / *NAT bridge* / *LAN bridge*) :
  `docs/modernisation-world-bridge.md` (**§ 1 bis = l'objectif final, il prime sur les § 2-4**) ;
  mémoire `modernisation-world-bridge` ; `git log --grep="modernisation-world-bridge"`.
  **État** : ép. 0→12 faits (NAT auto, 9ᵉ nature `nat_bridge`, LAN bridge automatique, N ports des
  deux côtés, DHCP, IPv6/SLAAC/NAT66, i18n ×12 complète). **Ép. 13 OUVERT, sans code** : les
  gestes que seule une vraie plateforme joue (run privilégié réel, NAT66 — cet hôte n'a pas
  d'IPv6, LAN bridge sur carte physique). **Le chantier ne se clôt pas avant.**

  **Gardes** :
  - une règle sudoers **ne peut pas** scoper une commande à arguments variables (un `*` avale des
    mots entiers, injection mesurée) : d'où des **portes privilégiées** minuscules qui valident
    leurs arguments en root, et `marionnet-ipv6.sh` à **zéro argument** (règle entièrement
    littérale) ; dans sudoers, un **`:` non échappé change ce qui est accordé**, sans casser le
    fichier (ép. 10c, 11) ;
  - le forwarding IPv6 n'est **pas** per-interface : il fait de l'hôte un routeur, qui **ignore
    les RA reçus** — sans `accept_ra=2` l'hôte perd sa propre route v6 minutes plus tard (ép. 11) ;
  - le nom d'un port **n'est pas un libellé** : un câble nomme son réceptacle dans le `.mar` et
    l'import **avale** l'échec de résolution — d'où le repli vers l'ancienne convention dans
    `ports_card#port_of_user_port_name` et le renommage par position de
    `Treeview_defects#change_port_naming` (ép. 12) ;
  - le corps des dialogues `Simple_dialogs.error/warning/info/help` est un label **Pango markup**
    (`use-markup` posé sur `content` dans `gui_glade3.xml`, pas dans `simple_dialogs.ml`) : tout
    `<mot>` casse le message entier, et toute valeur venue de l'utilisateur passe par
    `Glib.Markup.escape_text` — les **tooltips**, eux, sont du texte brut (ép. 9a).

- **bug-critique-crash-host** (crash rare non reproductible de l'hôte, corrélé à la terminaison
  des composants) : `docs/bug-critique-crash-host.md` ; mémoire `bug-critique-crash-host` ;
  `git log --grep="bug-critique-crash-host"`. C1 clos, C3 cloisonné, **C5 clos** (c'était un gel,
  pas un crash) ; restent **C2** (OOM) et **C4** (image Docker obsolète) ; **checklist post-mortem
  à exécuter au prochain crash**.

- **rétro-compat vieux couples kernel/image** (wheezy/guignol/mandriva, userlands i386 ; solution
  démontrée = UML récent `SUBARCH=i386`) : `docs/retro-compatibilite-kernels-images.md` ; mémoire
  `marionnet-retro-compat-kernels-images` ; `git log --grep="marionnet-retro-compat-kernels-images"`.
  Ép. 0→4 faits (remap auto kernel/distrib au chargement `.mar` ; abandon mandriva/pinocchio/lenny).

- **vwifi** (OCaml) : `docs/vwifi-integration.md` ; mémoire `marionnet-vwifi` ;
  `git log --grep="marionnet-vwifi"`. **BLOQUÉ** par le chantier noyau. Analyse commune :
  `docs/analyse-dave-appadoo-20260708.md`.

- **camlp4 → ppx** (sortir des 7 extensions camlp4 ; crux = `where_p4`) : `docs/camlp4-to-ppx.md` ;
  mémoire `marionnet-camlp4-ppx` ; `git log --grep="marionnet-camlp4-ppx"`. **NON entamé**,
  **priorité fortement abaissée** : ses deux justifications sont tombées (gel 4.13.1 levé,
  Merlin/LSP restauré — cf. § Build). Reste la dette de fond : dépendre d'un préprocesseur mort.

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
