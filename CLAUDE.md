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
- **pilotage par script** (piloter Marionnet par script — humain **et** agent : serveur de
  contrôle **in-process** sur socket unix, GUI vivante et observable ; requête = ligne texte,
  réponse = ligne **JSON**, aucune dépendance OCaml ajoutée ; périmètre = noyau + les 4
  treeviews) : `docs/pilotage-par-script.md` ; mémoire `marionnet-pilotage-par-script` ;
  `git log --grep="marionnet-pilotage-par-script"`. Épisodes 0→12 **tous clos** (§ 9 entièrement
  soldé ; § 10 — le scripting descend dans les composants — ouvert, démontré, refermé).
  Livrables versionnés : `bin/control_server.ml`, `bin/script_mode.ml`,
  `useful-scripts/marionnet-ctl` (+ `mrnctl`), `mrn-check`, `mrn2sh`,
  `marionnet-completion.bash`, `doc-src/scripting/`. **Invariant transverse** : la grammaire a
  **une seule** source de vérité — le serveur, publiée par `help` ; ne jamais la recopier
  ailleurs (règle appliquée 4 fois : `mrnctl`, `mrn-check`, `mrn2sh`, complétion). **Plus aucun
  défaut connu ouvert** → **clôturable (MODE C)**, sur décision de l'auteur.
- **journalisation-profonde** (pousser la journalisation **au-delà de Marionnet**, jusqu'à
  l'intérieur des UML — machines, routeurs — et des switchs, sous une forme qu'un script/agent
  peut lire ; `-d` n'y répond pas : booléen **global**, trace dans un xterm, rien par composant ni
  en fichier) : `docs/journalisation-profonde.md` ; mémoire `journalisation-profonde` ;
  `git log --grep="journalisation-profonde"`. **Ép. 0 fait 2026-08-10** (officialisation, aucun
  code) ; **ép. 1 fait 2026-08-10** (le **prologue injecté** : `bin/scripts/marionnet-relay.00-journal.sh`
  et son épilogue `…zz-journal.sh` — **indissociables**, la redirection fuirait sinon sur la fin du
  boot — déposés dans le hostfs par `make_hostfs_content` et **embarqués** par `INCLUDE_AS_STRING` ;
  un `rc_config` fautif laisse enfin trace, erreur **et statut** dans `/mnt/hostfs/rc_config.log`.
  Piège transverse au dépôt : **dune ne voit pas à travers camlp4** — un `.sh` embarqué doit figurer
  dans les `preprocessor_deps` de `bin/dune`, sans quoi le binaire garde silencieusement la version
  précédente) ; **ép. 2 fait 2026-08-10** (le **collecteur**, greffé à la fin du même épilogue :
  un **second** fichier `/mnt/hostfs/boot.log` dit ce que le boot a fait **avant** que le relais
  soit atteint — `dmesg`, puis `systemctl --failed`/`journalctl -b` ou listing + extraits de
  `/var/log` ; la branche est décidée par l'**invité** — `/run/systemd/system`, le test de systemd
  lui-même — la déclaration de l'hôte n'étant qu'un **témoin** journalisé, d'où l'unique ligne
  OCaml de l'épisode : la liaison `init_system` de `boot_parameters`. **D1 est mesuré, plus
  seulement raisonné** : une `debian-wheezy` de 2013 produit sa collecte sans qu'aucune image ne
  soit reconstruite. Pièges neufs : une image Marionnet peut n'avoir **aucun syslog**, et sous
  systemd `journalctl -b` **rapporte nos propres lignes**) ; **ép. 3 fait 2026-08-11** (le canal
  **lit** : verbe `log <component> [<file>|--file=<file>] [--tail=<n>]`, `file ∈ {rc_config, boot}`,
  défaut `rc_config` — forme et refus décalqués de `rc-get` et de `wait --ready`, dont la recherche
  du hostfs est **extraite et partagée** (`find_hostfs`) ; deux plafonds de nature différente :
  400 lignes pour la réponse, 2 Mio pour le lecteur, parce que le fichier est écrit par l'invité ;
  une ligne non-UTF-8 est **écartée et comptée**, la réponse restant une ligne JSON. 5ᵉ application
  de la règle d'unicité : `help` publie la paire de noms (`logs`), que la complétion **demande** —
  piège de l'épisode, `--file` appartenait déjà au **client** `mrnctl`) ; **ép. 4 fait 2026-08-11**
  (le **switch** cesse de jeter les réponses de son rc : le protocole de la socket mgmt a été
  **mesuré** avant d'être analysé — l'invite `vde$ ` n'a pas de saut de ligne et préfixe donc la
  réponse suivante, mais **pas** la ligne de statut d'une réponse **à données**, ce qui condamnait
  le lecteur booléen gardé « useful for testing », supprimé ; le journal est écrit **par
  Marionnet** dans `<working_directory du projet>/<nom>-rc_config.log`, servi par le **même** verbe
  `log` grâce à une **source** à trois cas — un répertoire, un fichier, rien — d'où trois refus qui
  ne disent pas la même chose ; la ligne `!! FAILED (status N)` reprend la forme des ép. 1-2, donc
  un seul `grep` répond pour machine, routeur **et** switch. Pièges neufs : **lire la réponse *est*
  le cadencement** de l'envoi — l'ancien code jetait et compensait par un délai — et une lecture
  sur cette socket doit être bornée en temps, sinon un switch muet retient thread et connexion pour
  la vie du projet) ; **ép. 5 fait 2026-08-11** (l'**instantané** : verbe `switch-info <switch>
  [<table>|--table=<table>]`, **miroir** de `log` — l'un sert ce qui a été *écrit* et survit à
  l'extinction, l'autre demande ce que le switch *sait*, qui n'existe que pendant la marche ;
  **quatre** tables (`ports`, `macs`, `vlans`, `fstp`), `vlan/print` ayant rejoint les trois de D4
  parce que c'est elle qui **répond à l'épisode 4** ; chaque table porte `entries` (analysé) *et*
  `lines` (les mots du switch), et les analyseurs lisent des **mots** — `Str` n'est pas réentrant.
  Piège neuf, structurel : une **valeur d'instance n'est pas dans l'interface**, donc `val state`
  est invisible depuis une sous-classe d'un autre module — la méthode a déménagé dans
  `simulated_device`, où elle n'est redéfinie *nulle part*, `get_management_socket_name` sur la
  classe `device` répondant déjà `None` pour tous les autres genres, hub compris) ; **ép. 6 fait
  2026-08-11** (la **console enregistrée** : option `--console-log`, implicite en `--exam` — la
  sortie du processus UML va dans `<projet>/<nom>-console.log`, servie par le **même** verbe `log`
  sous le nom `console`. La mesure a retourné la question : un UML écrit **déjà** sur la sortie
  d'erreur de son processus tant qu'aucun `console=` n'est passé, donc rediriger stdout/stderr
  suffit ; on n'ajoute une ligne série — `ssl0=null,fd:1` + `console=ttyS0` **en tête**, pour que
  le dernier `console=` reste celui qui était là — que là où un `console=` explicite a éteint la
  console par défaut, et alors **il faut** masquer le `serial-getty@ttyS0` que
  `systemd-getty-generator` instancie, sans quoi le boot attend 90 s un `dev-ttyS0.device` que UML
  ne crée jamais. Côté canal, la source à trois cas de l'ép. 4 devient une **liste** portant, pour
  chaque journal, la phrase à dire quand le fichier manque — attendre l'invité, démarrer le
  composant, ou relancer Marionnet avec l'option ; la complétion reçoit le 3ᵉ nom **sans être
  touchée**. Piège neuf : on ne peut **plus** fabriquer par le canal un couple kernel/image qui ne
  boote pas — remap auto, puis refus `SUPPORTED_KERNELS` — donc un démarrage qui n'aboutit pas se
  mesure en coupant le courant en plein boot) ; **ép. 7 fait 2026-08-11** (le **mode examen
  réanimé** : le § 2.4 était mort **deux fois** — personne n'écrivait `report.html`/
  `bash_history.text`, **et** `import_file` **lève** sur un fichier absent en ouvrant un dialogue,
  si bien qu'éteindre une machine en `--exam` produisait une exception depuis des années. Livré :
  l'**historique horodaté**, écrit **en continu** par un fragment que le prologue pose dans
  `/etc/profile.d` (`HISTFILE` dans le hostfs, `HISTTIMEFORMAT` → une ligne `#<epoch>` par
  commande, `history -a` au `PROMPT_COMMAND`) — 4ᵉ journal du verbe `log`, nommé **`commands`** et
  non `history`, ce mot étant déjà un **verbe** de la grammaire ; le **rapport Markdown**
  `report.md` (`bin/scripts/marionnet-report.sh`, déposé dans le hostfs, accroché à l'**arrêt** par
  l'épilogue), **section pare-feu** comprise, en Markdown parce qu'en HTML chaque sortie de commande
  demanderait un échappement qu'un script d'invité rate tôt ou tard ; et l'**import unique et
  gardé** (`import_exam_documents`), appelé par `machine.ml` **et** `router.ml` — l'asymétrie du
  § 2.4 est tranchée — qui archive rapport, historique **et console**, cette dernière **copiée** et
  non déplacée pour que `log … console` continue de répondre. Quatre corrections **par la mesure** :
  `bash -ic "cmd"` n'écrit aucun historique ; une unité systemd sans `Conflicts=shutdown.target`
  n'est **jamais arrêtée** ; avec les dépendances **par défaut** elle l'est mais sans ordre, et
  l'invité s'éteint **au milieu** du rapport ; et `stop` **rend la main avant la fin** — l'archivage
  est le dernier geste de l'extinction, d'où `wait <c> --state=off` avant de lire `documents`.
  Limites mesurées, toutes deux extérieures à l'épisode : les vieilles images SysV n'ont **pas** de
  séquence d'arrêt (leur `inittab` répond au ctrl-alt-del par `/sbin/halt`), et l'unique image de
  routeur installée — guignol, 2014 — n'atteint pas son relais) ; **ép. 8 fait 2026-08-12** (le
  **terminal de l'étudiant enregistré** : option `--terminal-log`, implicite en `--exam`, pour
  avoir les commandes **avec leurs sorties**, telles qu'il les voit. Le seul crochet que le noyau
  offre est le **premier champ** de `xterm=<émulateur>,-T,-e` — `UML_PORT_HELPER`, mesuré deux
  fois, n'est lu que par le canal `port:` — et il n'y a rien à intercepter dans le port-helper,
  qui passe le **descripteur** de son terminal au noyau puis dort (donc le vendorer aurait voulu
  dire réécrire `script(1)` en C, sans même libérer de `uml-utilities`, que `uml_mconsole` retient).
  Livré : `bin/scripts/marionnet-terminal-record.sh`, déposé exécutable dans le répertoire du
  projet, qui relance le vrai émulateur avec `script(1)` autour du port-helper — repli sur
  l'émulateur intact dès que quelque chose manque, **une fenêtre doit toujours s'ouvrir** ; les
  trois valeurs dont il a besoin passent par l'**environnement du processus UML**, d'où un
  `?environment` sur la classe `process`. 5ᵉ journal du verbe `log`, nommé `terminal` et jamais
  fusionné dans `console` — deux flux, deux écrivains, deux fichiers, et c'est le discriminant
  (un témoin écrit sur `/dev/tty0` est dans l'un et **jamais** dans l'autre). Le brut et son
  fichier de timing restent servis par le canal (rejouables par `scriptreplay`), le mode examen
  archivant une copie **nettoyée** des séquences ANSI — filtre qui **n'applique pas** les
  effacements, pour ne rien supprimer de ce qu'un correcteur veut voir. Défaut antérieur tombé
  en mesurant : `Treeview_documents#import_document` acceptait un `~move` et ne le transmettait
  **jamais** à `import_file`, si bien que tout import était une copie ; corrigé, intentions
  rendues explicites — rapport et historique **copiés** (déplacer `bash_history.text` ferait taire
  `log … commands` après une extinction), seule la copie nettoyée du terminal déplacée) ;
  **ép. 9 fait 2026-08-12** (la **documentation utilisateur**, la première du chantier : § 11 neuf
  du guide `doc-src/scripting/README.md` — « Recipe E — the journals », d'où une renumérotation
  11→15 — la note **`doc-src/exam-mode.md`** pour l'enseignant qui ne pilote pas Marionnet par
  script, et deux exemples versionnés joués **tels quels** par les bancs. Tension tranchée
  explicitement : l'invariant d'unicité interdit de recopier la grammaire, mais un § qui ne
  nommerait aucun journal n'apprendrait rien — la valeur de la page est **qui écrit quoi** (trois
  journaux vivent dans un hostfs que l'étudiant peut réécrire, deux sont écrits par l'hôte), ce que
  `help` ne dit pas ; donc la doc **cite** et le banc **compare** ce tableau à `.logs` de `help` à
  chaque passage. Corrigé par la mesure : `wait <c> --state=off` **ne suffit pas** pour lire
  `documents` — la transition d'état précède l'import du mode examen — d'où une attente **bornée**
  du treeview dans l'exemple, et une section d'`exam-bench.sh` devenue idempotente puisque
  l'exemple éteint la machine lui-même). Deux faits
  mesurés qui commandent tout
  le reste : (1) le relais invité **source déjà**
  `/mnt/hostfs/{<image>.,marionnet-}relay*` en ordre alphabétique, donc un **prologue** et un
  **épilogue** s'injectent depuis l'hôte **sans reconstruire aucune image** — d'où **aucune
  dépendance** envers `marionnet-kernel-rootfs` ; (2) le **mode examen** importe déjà
  `report.html`/`bash_history.text` dans le treeview `documents` (donc dans le `.mar`) mais
  **aucune image ne les produit** — le chantier rend un producteur à une destination vivante
  (ép. 7 : et cette destination, elle-même, ne fonctionnait pas).
  Décisions : hostfs = journal **vivant**, `documents` = **archive** ; console UML capturée parce
  qu'elle seule échappe à l'invité (notation) ; switch = d'abord **ne plus jeter les réponses** de
  son rc (`switch.ml:593` : `--rcfile` est mort), puis instantané par la socket mgmt ; collecteur
  **toujours actif**, enregistrement de session **sur option** — donc **aucun attribut persisté
  ajouté**, le format v3 n'est pas rouvert.
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
- **Code OCaml** (`bin/` + `lib/`, hors `uml/`) : skill `marionnet-ocaml` — outillage
  (`ocamllsp` via le plugin local `.claude/plugins/ocaml-lsp`, `sherlodoc` pour chercher **par
  type** dans ocamlbricks, `dune build @doc-private` pour odoc), règles d'écriture et pièges
  camlp4. **Fait établi** : `ocamlformat` ne parse pas cette syntaxe (`IFDEF`, `where_p4`,
  `INCLUDE DEFINITIONS`) — aucun formatage automatique tant que `camlp4-to-ppx` n'est pas fait.
- **Preuve datée** : `docs/audit-marionnet-20260706.md` (rapport d'audit, immuable).
