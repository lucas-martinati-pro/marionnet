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
6. **Aucun enfant n'est forké « en direct ».** Le seul site de spawn du dépôt vit dans
   `bin/simulation_level.ml` et passe par un **thread spawner dédié et pérenne**, qui appelle
   `UnixExtra.create_process ~pdeathsig:`KILL` (ocamlbricks, `lib/EXTRA/unixExtra.ml` — c'est
   là qu'est le préfixe `setpriv --pdeathsig` et la sonde qui décide s'il est utilisable) :
   c'est ce qui empêche les auxiliaires
   (`vde_switch`, `wirefilter`, UML, xterm) de survivre à un Marionnet tué brutalement. Deux
   choses à ne pas défaire : le signal de mort du parent est relatif au **thread** qui a forké
   (d'où le thread pérenne — les composants démarrent depuis des threads éphémères de
   `Task_runner.do_in_parallel`), et il n'atteint que les enfants **directs** (les
   petits-enfants restent à la charge de `useful-scripts/marionnet-cleanup`).
7. **dune ne voit pas à travers camlp4** : un fichier embarqué dans un `.ml` par `INCLUDE_AS_STRING`
   (les scripts de `bin/scripts/`) n'est une dépendance que s'il figure dans les
   `preprocessor_deps` de `bin/dune`. Sans cela, éditer le script laisse le binaire porter
   **silencieusement** la version précédente.

## Chantiers longs (work-streams)

Reprise : appliquer le skill `chantier-long`.
- **TODO transverse** (solder les entrées de défaut de `docs/TODO.md` — **15 à l'ouverture, 16**
  depuis que l'ép. 5 y a écrit le jumeau `variant`, devenu l'ép. 7, puis **23** depuis la
  **deuxième tournée** du 2026-08-21, qui admet dans le périmètre les 7 entrées que les épisodes
  ont eux-mêmes écrites en chemin —, une par épisode, chacune
  avec au moins un commit qui **retire l'entrée du TODO** ; hors périmètre : « composer
  deux projets ») : `docs/todo-transverse.md` (**§ 3 = décisions de cadrage**, § 4 = table des
  16 épisodes de la 1ʳᵉ tournée par coût croissant, renumérotés à l'ép. 7, **§ 4 bis = les 7 de
  la 2ᵉ**) ; mémoire `marionnet-todo-transverse` ;
  `git log --grep="marionnet-todo-transverse"`. Ouvert le 2026-08-20.
  Deux conventions posées ici : les bancs **rejouables sans invité ni privilège** sont
  **versionnés dans `driven-sessions/`** (les autres restent jetables, preuve dans le journal du
  doc), et un épisode qui découvre un défaut voisin l'**écrit** dans `docs/TODO.md` au lieu de
  le corriger en passant. Ép. 0 (cadrage), 1 (label), **2 (`--control-socket` : refus de
  démarrer quand le canal ne peut pas être servi, quelle qu'en soit la cause)** et **3 (un `add`
  refusé par son propre constructeur ne laisse plus son nœud : le rattrapage de `cmd_add`
  **détruit** le nœud du nom demandé dans le même `st#network_change` que la création)** et
  **4 (`add … --ports=N` refuse exactement ce que `set … port_no` refuse, et le refuse **avant**
  de construire)**, **5 (`set/add … distrib` refuse un filesystem non installé)**, **6 (les
  répertoires de run des sessions mortes sont *signalés* au démarrage, jamais purgés)** et
  **7 (le jumeau `variant`, plus le refus du `set distrib` qui ferait perdre la variante portée)**,
  **8 (toute tentative `uml_mconsole` a une échéance mesurée de 2 s)**, **9 (deux sessions
  simultanées se disent, au démarrage et à la collision de route)**, **10 (`wait --ready` ne
  parle plus que d'un invité qui *tourne*)** et **11 (le rc d'un switch est lu à *chaque*
  démarrage : une **fonction** au lieu d'une valeur au constructeur du device, évaluée une seule
  fois par `spawn`)** faits — la 1ʳᵉ tournée est **intégralement soldée** (ép. 12→16), et la 2ᵉ
  a joué son **ép. 17** (un avertissement d'import ne naît que d'un import : la branche `aucune`
  du routeur, **et** un avertissement enregistré seulement pendant un import — drapeau porté par
  le **fil** qui importe, posé par l'unique porte de désérialisation `Xml.load_network`) et son
  **ép. 18** (la fin d'une session s'observe par le canal seul : `quit` **et** `status` publient
  le **pid**, seul signal vrai après une sortie propre *comme* après un `SIGKILL` — le fichier
  socket, lui, n'est retiré qu'à la sortie propre, donc son absence prouve une fin et sa présence
  ne prouve rien ; contrat écrit au § 6 de `doc-src/scripting/README.md`) —
  l'ép. 2 a créé **`driven-sessions/`**, le répertoire des bancs versionnés, avec son `README.md`
  (conventions : PASS 0 / SKIP 77 / FAIL autre, et un banc doit échouer sur le code d'avant) ;
  l'ép. 11 y a **précisé le critère** : ce qui rend un banc jetable n'est pas de *démarrer* quelque
  chose mais d'exiger un **invité** ou un **privilège** — un switch n'exige ni l'un ni l'autre ;
  l'ép. 18 y a ajouté deux règles payées par la mesure : une session lancée par un banc se termine
  **par le canal ou par SIGKILL** (Marionnet **neutralise SIGTERM**, `bin/marionnet.ml`, donc
  `kill` puis `wait` ne rend jamais la main), et un banc qui matche un **texte** de l'application
  **fige la langue** (`LANGUAGE=C LC_ALL=C` — depuis l'ép. 15 un binaire de `_build` est traduit,
  et un motif anglais qui ne matche plus rien laisse passer un banc qui ne prouve plus rien).
  Trois pièges durables de l'ép. 10 : (1) un `start` du canal **répond avant que le démarrage soit
  fait** (la tâche part sur le `Task_runner`), donc toute garde qui lit le disque juste après lit
  encore le boot précédent ; (2) `socat` **perd toute réponse plus lente qu'une demi-seconde**
  sans `-t`/`-T` — un `wait` réel revient **vide**, sans erreur ; (3) machines et routeurs
  **détruisent** leur device simulé en s'éteignant (fichier cow), contrairement au switch : la
  « famille » du § 3.5 du doc se réduit donc à ce dernier.
  Piège durable de l'ép. 3 : détruire un objet **à moitié construit** se fait par `#destroy`
  (LIFO des callbacks enregistrés avant la levée, `OoExtra`), pas par `del_node_by_name`, et
  `network#get_node_by_name` **lève** quand le nom est absent.
  Deux pièges durables de l'ép. 4 : (1) les bornes de ports **sont** les
  `<Kind>.Const.port_no_{min,max}` que reçoit le constructeur (`n#port_no_min` ne fait que les
  renvoyer), donc les lire dans `node_maker` n'est pas une seconde source de vérité — et il faut
  les lire **avant** de construire, `assert (ports > 1)` de `bin/gui/ledgrid.ml` tuant le
  constructeur sur `--ports=0` ; (2) **déplacer une garde en amont peut vider de sa substance le
  banc d'un épisode antérieur sans jamais le faire échouer** (mesuré : les 2 cas du banc de
  l'ép. 3 ne touchaient plus le constructeur — un 3ᵉ cas, `add machine m-1`, l'exerce à nouveau).
  Deux pièges durables de l'ép. 7 : (1) **la chaîne vide ne traverse pas le canal** — une requête
  est découpée sur les espaces, les jetons vides jetés (`parse_request`), et `set <n> <champ>`
  échoue sur l'arité : le seul mot qui **retire** une variante est `aucune` ; (2) un banc peut se
  rendre **déterministe** en lançant le binaire avec `HOME` détourné dans son temporaire — les
  filesystems et variantes *utilisateur* de l'hôte disparaissent alors du run, et le banc peut y
  **fabriquer** ceux dont il a besoin (un fichier vide suffit, cf. `read_epithet_list`).
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
  note utilisateur : `doc-src/project-format-v3.md`),
  `docs/journalisation-profonde.md` (**journalisation jusqu'à l'intérieur des invités, et le mode
  examen** — 25 épisodes, clos 2026-08-15 ; § 8 = résultat ; à lire avant de toucher les scripts
  déposés dans le hostfs (`bin/scripts/marionnet-*.sh`), un journal servi par le canal, ou
  l'archivage du mode examen ; notes utilisateur : `doc-src/teacher-guide.md`,
  `doc-src/exam-mode.md`, `doc-src/lab-design-skill.md`),
  `docs/pilotage-par-script.md` (**canal de contrôle scriptable** — serveur in-process sur socket
  unix, requête = ligne texte, réponse = ligne **JSON** ; 14 épisodes, clos 2026-08-15 ; § 12 =
  résultat + **index des pièges durables**, § 9 = table des épisodes ; à lire avant de toucher
  `bin/control_server.ml`, `bin/script_mode.ml` ou un client de `useful-scripts/`. **Invariant à
  ne jamais enfreindre** : la grammaire a **une seule** source de vérité — le serveur, publiée par
  `help` ; aucun client ne la recopie. Notes utilisateur : `doc-src/scripting/`),
  `docs/migration-ocaml5.md`
  (OCaml 5.4.1, clos 2026-07-27), `docs/finitions-port-dune.md` (clos 2026-07-18),
  `docs/daemon-elimination-study.md` (clos 2026-07-17).
- **TODOLIST transverse** : `docs/TODO.md` — améliorations repérées hors de tout chantier en cours
  (son solde est lui-même un chantier : `docs/todo-transverse.md`)
  (ce qui relève d'un chantier reste dans son doc, § « Reste au chantier »). Chaque entrée porte le
  constat, ce qu'on veut à la place, et l'obstacle d'implémentation déjà identifié.
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
