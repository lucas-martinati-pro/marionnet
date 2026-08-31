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
  tarball. `website-repo/` (copie de travail du site) est gitignoré.
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
  verdict unique. Régénérer ce `MD5SUM` reste à faire.
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
  **Feuille de route (§ 5 bis du doc, elle PRIME sur le § 5)** : (1) finir le local *(fait,
  ép. 11)* → (2) les 4 boîtes Debian 12/13, Ubuntu 24.04/26.04 *(fait, ép. 12)* → (3) le
  découpage en `.deb` *(fait, ép. 13)* → (3 bis) `doc-src/` s'installe *(fait, ép. 14)* →
  (4) les `.deb` sur les 4 boîtes — **15a les fabriquer *(fait)*, 15b les installer
  *(fait)*** → (5) `upload.www.marionnet.org.sh` + point d'entrée apt stable
  ← **prochaine, mais BLOQUÉE par l'extérieur** → (6) rejeu de (2) et (4) contre le vrai
  serveur. La **doc INSTALL** est le tout dernier épisode.
  **Bloqué par l'extérieur** : l'étape « serveur » (dépôt des artefacts) attend le retour du
  site, et avec elle la configuration réelle de `www.marionnet.org` et la jambe **https**.

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
