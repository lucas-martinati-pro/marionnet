# Chantier : modernisation-world-bridge

> Chantier long, ouvert le 2026-07-18. Cible : le composant **`world_bridge`**
> (`bin/world_bridge.ml`, dernier bouton de la palette gauche, icône planète), qui
> raccorde le réseau virtuel au **vrai réseau L2 de l'hôte**. Deux axes : (1) éliminer
> sa **barrière de mise en œuvre** (config hôte manuelle hors GUI), sur le modèle du
> chantier `daemon-elimination` ; (2) un **travail GUI** rendant le composant
> compréhensible pour enseignants et étudiants. Skill de pilotage : `chantier-long`.
>
> ⚠️ **Objectif final révisé le 2026-08-16 (épisode 4)** : le mode d'accès au monde n'est
> plus un *réglage global* de `world_bridge` mais **le choix d'un composant** dans la GUI.
> Lire le **§ 1 bis** en premier : il prime sur tout ce que les § 2 à 4 disent du « mode ».

## 1. Contexte et objectif

`world_bridge` est le **seul composant qui rompt le bac à sable** : tous les autres
équipements (y compris `world_gateway`, NAT `slirpvde` auto-suffisant) sont des processus
purement virtuels sans contact avec le vrai réseau. `world_bridge`, lui, crée un *tap* via
`Tap_provider` (sudo scoped + iproute2, hérité de `daemon-elimination` ép. 3) et l'attache
à un **bridge Linux préexistant côté hôte** (`MARIONNET_BRIDGE`, `marionnet.conf`), puis
relie ce tap à l'unique hublet du composant par un `vde_switch` 2 ports en mode *hub*.

Deux usages (help `bin/world_bridge.ml`, `Dialog_add_or_update.help_callback`) :

1. **Accès L2 *bridgé* au vrai LAN/Internet** : les VM obtiennent de vraies IP sur le vrai
   sous-réseau et voient les **vrais services** (DHCP, DNS, NFS…).
2. **Lab distribué multi-machines** : relier des instances Marionnet tournant sur des
   **postes physiques différents** en un même domaine de diffusion — son *killer feature*
   pédagogique, sans substitut.

### Le problème — deux frictions

- **Barrière de mise en œuvre.** Rien n'est *self-service*. L'admin doit, **à la main et
  hors GUI** : (a) créer le bridge hôte `MARIONNET_BRIDGE`, (b) **y asservir la carte
  physique** (`eth0`), (c) **migrer l'IP de l'hôte sur le bridge**. `daemon-elimination` a
  déjà supprimé le *daemon root* pour la création du tap (`Tap_provider`), mais **pas** ces
  trois gestes hôte — c'est la barrière résiduelle. Note critique : (b)+(c) sont
  **destructeurs** — asservir la carte primaire d'un vrai poste peut **couper la
  connectivité de l'hôte** en cours de route. C'est précisément *pourquoi* c'est resté
  manuel.
- **Opacité GUI.** Deux composants « monde » côte à côte (`world_bridge`, `world_gateway`)
  prêtent à confusion ; le texte d'aide est daté (« ethernet socket », `ifconfig/route`,
  renvoi wiki) ; l'étudiant ne sait pas *lequel* choisir ni *pourquoi* l'un « ne marche
  pas » sans préparation hôte.

### Objectif du chantier

Rendre `world_bridge` **utilisable sans préparation hôte manuelle risquée** (axe barrière)
et **compréhensible dans la GUI** (axe pédagogique), sans dégrader ses deux usages ni la
surface de sécurité obtenue par `daemon-elimination`.

## 1 bis. Objectif final révisé (épisode 4, 2026-08-16)

L'objectif ci-dessus est **tenu**, mais la forme que prend sa livraison change, et ce
changement rend caduques plusieurs décisions des § 2 à 4. En une phrase :

> **Les deux modes d'accès au monde ne sont pas un réglage, ce sont deux composants.**
> L'utilisateur ne choisit plus « quel mode pour `world_bridge` » (variable d'environnement,
> invisible, globale au processus) : il choisit **quel équipement il pose sur son réseau**,
> dans le menu de la palette, au même endroit et de la même façon qu'il choisit entre un hub
> et un switch.

### 1 bis.1 Ce que voit l'utilisateur

Le bouton « planète » de la palette (`ico.world.palette.png`, libellé *Real world access*,
défini dans `bin/gui/gui_toolbar_COMPONENTS.ml`) offre aujourd'hui deux entrées, *Gateway* et
*Bridge*. Il en offrira **trois** :

| Entrée du menu | Composant | Ce que ça fait | Privilèges |
|---|---|---|---|
| **Gateway** | `world_gateway` (inchangé) | NAT applicatif `slirpvde`, purement en espace utilisateur | **aucun** |
| **NAT bridge** | *nouveau composant* | réseau privé automatique : bridge dédié `mnbr*` + MASQUERADE, créé et détruit par Marionnet | sudo scoped (b) |
| **LAN bridge** | `world_bridge` (l'actuel) | vrai accès L2 : les VM sont sur le vrai LAN de l'hôte, vraies IP, vrais services | sudo scoped (c) |

Le vocabulaire est arrêté : **« LAN bridge »** et non « Level 2 » (jargon OSI), « raw » (ne
veut rien dire pour un humain) ou « manual » (nomme la contrainte d'hier, pas l'effet). Ces
libellés disent l'**effet obtenu** — réseau privé *vs* vrai LAN — ce qui est exactement la
question que se pose l'étudiant devant la palette.

### 1 bis.2 Décisions structurantes (et leur *pourquoi*)

1. **Deux natures de composants distinctes**, pas une nature à attribut. Coût assumé (9ᵉ
   nature : grammaire du canal de contrôle, format `.mar`, treeviews, icônes, i18n) en
   échange de la seule chose qui compte pédagogiquement : deux équipements **visiblement**
   différents sur le dessin du réseau, avec chacun son dialogue, son aide et ses
   avertissements. Un attribut caché dans un dialogue aurait reconduit l'opacité que ce
   chantier combat.
2. **`MARIONNET_WORLD_BRIDGE_MODE` disparaît.** Introduite à l'épisode 3 comme sélecteur
   provisoire, elle n'a plus d'objet : le mode *est* le composant. Avec elle disparaît le
   « défaut conservateur » (`Manual` si `MARIONNET_BRIDGE` est configuré) — un projet qui
   contient un `world_bridge` reste un **LAN bridge**, donc son comportement d'hier, sans
   qu'aucune variable n'ait à le décider.
3. **Un bridge NAT par composant.** Deux composants *NAT bridge* dans un projet donnent deux
   réseaux privés séparés (`mnbr<pid>-1`, `mnbr<pid>-2`, un /24 chacun) : c'est ce qu'un
   étudiant attend en posant deux équipements distincts. L'`ensure` mémoïsé de
   `Nat_bridge` (épisode 3, un seul bridge par processus) devient une table indexée par
   composant — fait à l'épisode 7a.2, dans `Nat_bridge_host`.
4. **Le LAN bridge devient automatique lui aussi**, par un script hôte symétrique
   **`bin/scripts/marionnet-lanbridge.sh`** : détection de la carte qui porte la route par
   défaut, asservissement au bridge, migration de l'adresse et des routes, rollback
   transactionnel. C'est l'**option B** du § 2.1, promue de « peut-être un jour » à
   composant de plein droit. Son risque ne disparaît pas pour autant : le dialogue
   d'ajout/modification **avertit explicitement d'une coupure possible de l'hôte**, et
   l'asservissement d'une carte Wi-Fi reste impossible (l'AP refuse plusieurs MAC).
   *Rectifié à l'épisode 8* : contrairement au NAT, ce bridge **n'est pas par processus** et
   ne s'appelle donc pas `mnlan<pid>` mais **`mnlan0`**, un par hôte — une carte n'a qu'un
   master, donc deux Marionnet le **partagent**, exactement comme ils partageaient le `br0`
   fabriqué à la main. Voir § 4.3.
5. **Les privilèges se demandent au moment où ils servent.** Voir § 1 bis.3 : c'est le
   changement le plus profond, car il déplace la frontière entre l'admin et l'utilisateur.

### 1 bis.3 Privilèges : un socle admin, deux extensions à la demande

`bin/scripts/marionnet-sudoers.sh` est la source unique de la règle sudoers. Elle porte
désormais **trois blocs**, qui ne s'installent pas au même moment ni par la même personne :

| Bloc | Contenu | Qui l'installe | Quand |
|---|---|---|---|
| **(a)** | taps fantômes `mtap*` (iproute2) — chantier `marionnet-daemon-elimination` | l'**administrateur**, à l'installation de Marionnet | `marionnet-sudoers.sh install` (sans option) |
| **(b)** | bridge NAT privé `mnbr*` — `marionnet-natbridge.sh` | l'**utilisateur final**, depuis la GUI | `--enable-natbridge` |
| **(c)** | bridge LAN `mnlan*` + carte de l'hôte — `marionnet-lanbridge.sh` | l'**utilisateur final**, depuis la GUI | `--enable-lanbridge` |

Le raccourci **`--enable-bridges`** vaut `--enable-natbridge --enable-lanbridge`.

Le *pourquoi* de cette séparation : à l'installation, celui qui exécute le script est
souvent un **administrateur qui n'est pas l'utilisateur final** ; lui faire accorder
d'emblée le droit de toucher à la carte réseau de l'hôte serait accorder à l'aveugle un
pouvoir dont personne n'a encore le besoin. Le socle (a) est ce sans quoi **rien** ne
fonctionne (tout composant crée des taps) ; (b) et (c) ne servent qu'à qui pose un bridge.

**Trois fichiers séparés** dans `/etc/sudoers.d/` (`marionnet`, `marionnet-natbridge`,
`marionnet-lanbridge`) plutôt qu'un fichier au contenu variable : chaque bloc s'installe, se
vérifie et se retire indépendamment, et surtout l'activation *run-time* n'a jamais à
réécrire le fichier (a) — celui sans lequel Marionnet ne démarre plus un seul composant.

*Rectifié à l'épisode 6* : les fichiers séparés n'étaient que la moitié de cette garantie. Le
bloc (a) restant **toujours sélectionné**, `install --enable-natbridge` le réécrivait — au nom
de **l'appelant**. L'administrateur accorde (a) à `X`, `Y` active le NAT bridge depuis la GUI,
et `X` perd silencieusement ses taps. D'où le sélecteur **`--only`** : « n'appliquer la commande
qu'aux blocs explicitement demandés ». C'est celui que la GUI emploie ; le geste par défaut de
l'administrateur, lui, ne change pas.

**Élévation depuis la GUI** : `sudo` est déjà une dépendance dure du projet (tout
`Tap_provider` repose dessus), donc s'appuyer sur lui **ne suppose aucune distribution**
particulière — contrairement à `pkexec`/PolicyKit, absent des systèmes minimaux et des
conteneurs. Marionnet affiche son propre dialogue de mot de passe et le passe à `sudo`.

**Ce que l'utilisateur apprend, et quand** : à l'**ajout** d'un composant *NAT bridge* ou
*LAN bridge*, le dialogue annonce que ce composant **ne pourra pas démarrer sans droits
d'administrateur** — l'information arrive au moment du geste, pas sous forme d'un échec
inexpliqué au démarrage. L'élévation, elle, est demandée au **premier démarrage** effectif.

## 2. Axe A — élimination de la barrière de mise en œuvre

Principe repris de `daemon-elimination` : ce qui était une **action admin permanente et
hors-bande** doit devenir un **provisionnement runtime, scoped et réversible** (sudo étroit +
iproute2), ou disparaître. Ici la difficulté nouvelle vs le daemon : l'un des gestes à
automatiser (asservir la carte de l'hôte) est intrinsèquement **dangereux**.

### 2.1 Options évaluées

| # | Solution | Sémantique | Barrière | Risque hôte | Complexité | Verdict |
|---|---|---|---|---|---|---|
| A | **NAT bridge privé auto** (bridge dédié `mnbr0` + IP côté hôte + `iptables -t nat MASQUERADE` sur la sortie, +`dnsmasq` DHCP optionnel) | NAT (VM derrière l'hôte, pas sur le vrai LAN) | **quasi nulle** (tout créé par Marionnet) | **nul** (ne touche pas la carte de l'hôte) | moyenne | **retenu — défaut** |
| B | **L2 réel auto** (détecter la carte route-défaut, l'asservir au bridge, migrer l'IP, rollback à la sortie) | L2 fidèle (VM sur le vrai LAN) | faible | **élevé** (coupure hôte possible) | haute (garde-fous + rollback) | **retenu — option experte opt-in** |
| C | **variante D** (taps pré-provisionnés par l'admin, `docs/admin-taps-and-bridge.md`, déjà documentée non câblée) | L2 | admin one-shot | faible | faible | conservée en repli documenté |
| D | **statu quo manuel** (`MARIONNET_BRIDGE` à la main) | L2 | forte | assumé par l'admin | nulle | conservé comme mode « expert manuel » |

**Décision de cadrage (2026-07-18) : « les deux » — A par défaut, B en option experte.**
- **A (NAT privé auto)** tue la barrière pour le cas d'usage majoritaire (« mes VM ont
  besoin d'Internet / des services de l'hôte ») sans jamais risquer la connectivité du
  poste. C'est le modèle éprouvé de libvirt (réseau *default*) : bridge hôte dédié + NAT +
  dnsmasq. Sémantiquement c'est du NAT, pas du L2-sur-le-vrai-LAN — à assumer et à **dire
  dans la GUI**.
- **B (L2 réel auto)** préserve l'usage « vraies IP sur le vrai LAN » et le **lab distribué
  multi-machines**, mais reste opt-in explicite, encadré de garde-fous (détection de la
  carte, avertissement, rollback `at_exit`/erreur), car il peut couper l'hôte.

### 2.1 bis Ce que le POC a prouvé (2026-08-15, épisode 2)

Banc d'essai : `useful-scripts/marionnet-natbridge-poc.sh` (`up`/`down`/`status`/`gc`/
`selftest`/`print-privileged-commands`), **sans une ligne d'OCaml**. Deux paliers, tous
deux verts sur le poste de développement :

- **Palier 1 — système seul** (`selftest`) : bridge `mnbr<pid>` + `192.168.101.1/24` +
  MASQUERADE, un *network namespace* jouant l'invité ; depuis cet invité, `ping 9.9.9.9`
  (55,8 ms) **et** résolution DNS (UDP/53) ; puis démontage et assertion « rien ne survit »
  (bridge, netns, règles, `ip_forward`) — passée.
- **Palier 2 — bout en bout** : `MARIONNET_BRIDGE=mnbr<pid>` et un vrai Marionnet piloté par
  le canal de contrôle (`--control-socket`). Maquette `m1 --- w1` (machine
  `debian-trixie-47362` / noyau `6.12.95`, `world_bridge`), `start-all`, puis depuis
  **l'invité UML** : `ping -c2 9.9.9.9` → **2 reçus, 0 % de perte** (78,3 / 57,9 ms) et
  `nslookup example.org 9.9.9.9` → réponse complète. Pendant ce temps la route par défaut de
  l'hôte est restée `via 192.168.198.41 dev wlp0s20f3`, intacte.

Trois enseignements qui engagent la suite :

1. **`world_bridge` n'a eu besoin d'AUCUNE modification.** Il a créé son tap et l'a attaché à
   un bridge qu'il n'a pas eu à trouver préexistant : côté hôte, `mnbr<pid>` avait pour port
   `mtap<pid Marionnet>-1`, et il est passé `UP,LOWER_UP`. Ce que l'épisode 3 doit écrire en
   OCaml se réduit donc à **créer/détruire le bridge et les règles NAT** ; l'attachement, lui,
   marche déjà (`Tap_provider.make_bridge_tap` est indifférent à l'origine du bridge).
2. **L'option B est inapplicable sur ce poste** : il sort par le **Wi-Fi** (`wlp0s20f3`).
   Asservir une carte Wi-Fi à un bridge ne fonctionne pas (le point d'accès n'accepte pas
   plusieurs MAC derrière un client). Le NAT de l'option A, purement L3, s'en moque. La
   décision « A par défaut » n'était donc pas seulement la moins risquée : sur les postes
   nomades — le cas majoritaire d'un enseignant — elle est la **seule** qui marche.
3. **dnsmasq reste inutile** (point dur § 2.2.3, tranché par YAGNI) : l'invité configuré en
   statique a atteint l'Internet. Reste à décider *où* l'étudiant pose cette configuration
   (à la main, ou par le treeview `ifconfig` de la GUI) — question d'épisode 3, pas de DHCP.

Commandes privilégiées à ajouter au motif sudoers (sortie de `print-privileged-commands`) :
`ip link add/del <BR> type bridge`, `ip addr add <NET>.1/24 dev <BR>`, `ip link set <BR> up`,
`sysctl -w net.ipv4.ip_forward=1`, et les trois `iptables -{A,D}` (une `-t nat POSTROUTING
MASQUERADE`, deux `FORWARD`). L'attachement `ip link set mtap* master <BR>` est **déjà**
couvert par la règle existante.

### 2.2 Points durs identifiés (à traiter aux épisodes d'implémentation)

1. **Périmètre sudoers.** A et B ajoutent des commandes iproute2/iptables au motif scoped de
   `bin/scripts/marionnet-sudoers.sh` (`ip link add … type bridge`, `ip link del`,
   `iptables -t nat …`). Reprendre la discipline de `daemon-elimination` (littéraux, pas de
   `*` libre au-delà du strict nécessaire ; revue sécurité dédiée).
2. **GC des bridges/règles NAT.** Comme les taps `mtap<pid>-*`, nommer `mnbr<pid>-*` et
   purger au lancement les artefacts d'un pid mort (bridge + règle NAT). Garde `owner_pid`
   sur tout `at_exit` (piège `daemon-elimination` ép. 6).
3. **dnsmasq optionnel.** DHCP côté bridge NAT : dépendance + cycle de vie (spawn/kill via la
   classe `process`, `simulation_level.ml`). YAGNI possible : sans dnsmasq, les VM ont une IP
   statique/host-route ; à trancher au POC.
4. **B — détection carte + rollback.** Détecter la carte de route par défaut (`ip route show
   default`), sauvegarder l'état IP, rollback fiable même sur crash. Interaction AppArmor/
   NetworkManager du poste. C'est le vrai coût de B.
5. **Netns (synergie `daemon-elimination` ép. 5).** L'option netns « zéro sudo » différée là-bas
   laissait justement `world_bridge` **hors** de son bénéfice (bridge en ns racine,
   `daemon-elimination.md §12.3` point 1). A/B ici sont orthogonaux au netns ; à recouper si
   ce besoin se concrétise.

### 2.3 Conventions établies par le POC (**tenues par le script**, cf. § 4.1)

- **Nommage et propriété.** Bridge `mnbr<pid>` (≤ 15 car., `IFNAMSIZ`) et **chaque règle
  iptables porte le commentaire `marionnet-natbridge:mnbr<pid>`** (`-m comment`). Conséquence
  voulue : `down` et `gc` retrouvent leurs artefacts **en interrogeant le système**, sans
  dépendre d'un fichier d'état qu'un crash aurait laissé mentir. Même discipline `owner_pid`
  que `Tap_provider` (piège `daemon-elimination` ép. 6) : on ne détruit que ce dont le pid est
  mort, et un pid vide ou malformé est rejeté avant de servir à sélectionner quoi que ce soit.
- **Les deux règles `FORWARD` ne sont pas redondantes avec le MASQUERADE.** Sur un hôte où
  tourne Docker, la politique de la chaîne `FORWARD` est `DROP` : le NAT traduirait des
  paquets qui seraient ensuite jetés. Il faut la règle sortante et la règle retour
  (`conntrack --ctstate RELATED,ESTABLISHED`).
- **`ip_forward` : ne restaurer que ce qu'on a changé.** C'est la seule information que le
  système ne redonne pas après coup (et sur ce poste il valait déjà 1, mis par Docker) : c'est
  le seul contenu du fichier d'état, et son absence vaut « ne pas y toucher ».
- **Choisir le /24 en écartant ce qui est déjà routé ou adressé sur l'hôte** (candidats
  `192.168.101` … `192.168.110` ; `172.23.0.0/16` exclu, c'est le ghost network). Sans ce
  test, un bridge NAT peut voler le préfixe du vrai LAN et priver les invités d'Internet.
- **Amorçage.** `MARIONNET_BRIDGE` est lu **à l'initialisation** (`global_options.ml`) : au
  POC le bridge doit donc préexister au lancement. En OCaml la question disparaît — c'est
  Marionnet qui créera le bridge, et il connaît son propre pid.

## 3. Axe B — travail GUI (comprehensibilité enseignants/étudiants)

Objectif : qu'un étudiant sache *en lisant la GUI* ce que fait `world_bridge`, quand le
préférer à `world_gateway`, et ce qu'il faut (ou plus, après l'axe A) pour qu'il marche.

- **Texte d'aide** (`help_callback`) réécrit : rôle, `world_bridge` **vs** `world_gateway`,
  prérequis (et, à terme, le mode NAT auto sans prérequis). Purge du vocabulaire daté
  (« ethernet socket », `ifconfig/route`) et du `TODO rename` obsolète.
- **Tooltips** (palette, nom, image du dialogue) enrichis pour distinguer les deux composants
  « monde ».
- *(révisé à l'épisode 4 — cf. § 1 bis)* : **pas** de sélecteur de mode dans le dialogue. Le
  choix se fait **une entrée de menu plus haut**, dans la palette : *Gateway* / *NAT bridge* /
  *LAN bridge*. Restent au titre de l'axe GUI : l'aide et les tooltips propres à chaque
  composant, l'**avertissement de coupure hôte** du LAN bridge, et l'**annonce du besoin de
  droits d'administrateur** au moment de l'ajout.

## 4. Découpage en épisodes

1. **ép. 0** — *officialisation + étude* (ce document, fiche mémoire, pointeur CLAUDE.md).
   Aucun code fonctionnel. **Fait 2026-07-18.**
2. **ép. 1** — *GUI comprehensibilité (increment 1)* : `help_callback` réécrit + tooltips
   clarifiant `world_bridge` vs `world_gateway`. Sources anglaises seules ; **refresh gettext
   des 12 langues différé** à un épisode i18n consolidé (méthode `daemon-elimination`).
   **Fait 2026-07-18.**
3. **ép. 2** — *POC système « NAT bridge privé auto »* (option A), sans OCaml :
   `useful-scripts/marionnet-natbridge-poc.sh`, prouvé aux deux paliers (§ 2.1 bis), et liste
   des commandes privilégiées produite pour l'épisode suivant. **Fait 2026-08-15.**
4. **ép. 3** — *le POC devient un outil hôte, et l'OCaml l'appelle*. **Fait 2026-08-16.**
   Détail et **révision de cadrage** en § 4.1.
5. **ép. 4** — *restructuration du chantier* : objectif final révisé (§ 1 bis), nouveau
   découpage (ci-dessous), fiche mémoire et pointeur `CLAUDE.md` alignés. Aucun code
   fonctionnel. **Fait 2026-08-16.**

À partir d'ici, la suite est celle qu'ouvre le § 1 bis. Elle est ordonnée par
**dépendance**, pas par difficulté : chaque épisode est prouvable seul, et aucun n'exige que
le suivant existe.

6. **ép. 5** *(à venir)* — **la règle sudoers en trois blocs**. `marionnet-sudoers.sh`
   installe (a) seul par défaut ; `--enable-natbridge`, `--enable-lanbridge` et le raccourci
   `--enable-bridges` ajoutent (b) et (c) dans **leurs propres fichiers** de
   `/etc/sudoers.d/`. `print`/`check`/`install`/`uninstall` deviennent par-bloc. C'est la
   fondation de tout le reste, et elle se prouve sans une ligne d'OCaml (`visudo -cf`, puis
   le cycle `up`/`down` de `marionnet-natbridge.sh` toujours vert en `sudo -n`).
7. **ép. 6** — **l'élévation depuis la GUI**. **Fait 2026-08-16.** Le point ouvert a été
   tranché pour le **dialogue interne + `sudo -S`** (aucun exécutable neuf, aucune hypothèse
   de distribution) : `bin/gui/simple_dialogs.ml` (`ask_password`), `bin/privileges.ml(i)`
   (sonde, `sudo -n` puis `sudo -S`, 3 essais, verdict mémoïsé), `--only` côté script, et le
   message d'information dans le dialogue du composant. Détail en § 4.2.
8. **ép. 7** *(à venir)* — **le dédoublement des composants** : nature *NAT bridge* neuve à
   côté de `world_bridge` (devenu *LAN bridge*), menu planète à trois entrées, N bridges NAT
   (un par composant), retrait de `MARIONNET_WORLD_BRIDGE_MODE` et de la variable de
   configuration associée, propagation au canal de contrôle, au format `.mar` et aux
   treeviews. Le gros morceau OCaml/GUI.
9. **ép. 8** — **`bin/scripts/marionnet-lanbridge.sh`** : bridge **`mnlan0`** (un par hôte, et
   non un par processus : voir § 4.3), détection de la carte de route par défaut,
   asservissement, migration de l'adresse et des routes, rollback transactionnel et
   `selftest`, sur le patron exact de `marionnet-natbridge.sh` (contrat JSON, `--fail-after`),
   **plus le bloc (c) du sudoers**, qui refusait de s'installer tant que ce script n'existait
   pas. **Zéro OCaml** : l'avertissement de coupure hôte part avec l'épisode 7, qui refond de
   toute façon le dialogue du composant. **Fait 2026-08-16**, détail en § 4.3.
10. **ép. 9** *(à venir)* — **refresh i18n consolidé ×12**, qui solde aussi la dette des
    trois chaînes de l'épisode 1 (§ 5).

### 4.1 Épisode 3 en détail — révision de cadrage : appeler, ne pas réécrire

Le § 2.3 ci-dessus disait « conventions à reprendre **en OCaml** », et le découpage prévoyait de
porter le POC dans `tap_provider.ml`. **Cette décision est abandonnée**, pour une raison qui n'est
apparue qu'une fois le POC prouvé : la séquence `ip`/`iptables` est **déjà** la source de vérité de
la règle sudoers (`print-privileged-commands`). La réécrire en OCaml aurait créé un **deuxième
exemplaire** de cette séquence, à tenir en phase avec le premier et avec la règle — pour ne rien
gagner : le code OCaml aurait fait les mêmes appels système, en moins lisible.

Le POC devient donc l'**implémentation**, sous la forme d'une **commande hôte auxiliaire** de
Marionnet — le motif existe déjà dans ce dépôt (`marionnet-sudoers.sh`, appelée par son nom nu
depuis `tap_provider.ml`). Ce que l'épisode a livré :

- `bin/scripts/marionnet-natbridge.sh` (déplacé depuis `useful-scripts/`, `git mv`, renommé) :
  - **contrat de sortie** — stdout = **exactement un objet JSON, sur une ligne, sur tous les
    chemins de sortie** ; stderr = la trace humaine (chaque commande privilégiée est affichée
    avant d'être lancée) ; code de retour 0/≠0, doublé d'un **code d'erreur symbolique**
    (`E_SUDO_DENIED`, `E_NO_FREE_SUBNET`, `E_BAD_PID`, `E_ROLLBACK_INCOMPLETE`…) ;
  - **transaction** — chaque étape mutante réussie empile son inverse ; toute défaillance (y
    compris un signal, ou une erreur inattendue via `trap … ERR`) dépile en LIFO et **rapporte
    honnêtement** ce qui n'a pas pu être défait (`leftovers`, `rolled_back:false`) au lieu de
    prétendre à un nettoyage propre. `down` est le **même** dépilement, appliqué à ce que le
    système dit exister — c'est ce qui le rend correct après un crash ;
  - **paramétrage** — `--owner-pid`, `--subnet`, `--candidates`, `--state-dir`, `--dry-run`,
    `--sudo-interactive`, plus `--fail-after LABEL` (test : provoque l'échec d'une étape nommée,
    c'est ce qui rend le rollback **prouvable**) ;
  - **bashbricks** — `Map_to_json` / `Array_to_json` fabriquent tout le JSON (aucun échappement
    fait main). `set -eEo pipefail` mais **pas `set -u`** : la lib n'est pas *nounset-safe*, et
    `set -u` ne protège de toute façon pas du cas « liée mais **vide** ». La garde réelle est le
    **validateur explicite** (`require_pid`/`require_subnet`/`require_bridge`, regex ancrées), qui
    précède chaque commande destructrice.
- `bin/nat_bridge.ml(i)` : **mince**, il n'implémente rien. Il lance la commande, lit son JSON
  (`Yojson`), verse stderr au journal, et rend `(t, error) result` où `error` porte le **code
  symbolique**. `ensure ()` mémoïse le `up` et n'enregistre l'`at_exit` qu'après succès, avec la
  **garde de pid** de `Tap_provider` (sans elle, la fermeture d'un relais X11 forké détruirait le
  bridge des VM en marche).
- **La couture** : `MARIONNET_BRIDGE` est lu à l'initialisation, or le bridge NAT n'existe qu'après
  `up`. Le nom du bridge est donc résolu **au démarrage du composant**
  (`world_bridge.ml`, `resolve_bridge_name`), pas à l'initialisation. Échec du mode auto ⇒ repli
  sur le nom configuré : le composant se comporte alors exactement comme avant ce chantier.
- **Le mode** : `Global_options.world_bridge_mode`. Défaut **conservateur** — `Manual` dès que
  `MARIONNET_BRIDGE` est configuré quelque part (un admin a fait le travail, on continue de
  l'honorer), `Nat` sinon. `MARIONNET_WORLD_BRIDGE_MODE=nat|manual` tranche explicitement, et
  **tient lieu de sélecteur** jusqu'à l'épisode 4. En mode `Nat`,
  `check_bridge_existence_and_warning` est un no-op : avertir que `br0` n'existe pas reviendrait à
  réclamer la préparation manuelle que ce chantier supprime.
- **Installation** — les **quatre** fichiers au même endroit,
  `/usr/local/share/marionnet/scripts/` : `marionnet-sudoers.sh`, `marionnet_telnet.sh`,
  `marionnet-natbridge.sh` et **`bashbricks.sh`** (`bashbricks/dune`, neuf — la bibliothèque
  n'était jamais installée jusqu'ici, aucun livrable ne la sourçait). Les deux boucles du
  `Makefile` (236 : liens durs vers `$PREFIX/bin/` ; 276 : liens symboliques en *testing*) les
  reprennent sans modification. La sonde de bashbricks s'en trouve triviale : la bibliothèque est
  **voisine** du script dans les deux emplacements.
- **Règle sudoers** étendue (`marionnet-sudoers.sh`), toujours dérivée de
  `print-privileged-commands`. Garde la plus serrée : **toute règle iptables doit porter notre
  commentaire** `marionnet-natbridge:mnbr*` — sans ce tag, la règle n'autorise ni l'ajout ni la
  suppression, donc elle ne peut pas servir à toucher une règle que Marionnet n'a pas créée.
  **Piège mesuré** : `!`, `,` et `:` sont des métacaractères sudoers et doivent être échappés
  (`\!`, `\,`, `\:`) dans les arguments d'une commande, sinon **`visudo` rejette tout le fichier**.
- **Dépendance hôte neuve** : `jq` (le module `Json_*` de bashbricks s'en sert). Déjà sur la liste
  du chantier `modernisation-installation-marionnet`, à répercuter dans les paquets.

### 4.2 Épisode 6 en détail — qui demande, et à qui

Quatre décisions, dont **deux prises contre l'intuition initiale, par la mesure**.

1. **`sudo -S` derrière un dialogue à nous**, plutôt qu'un binaire askpass (`sudo -A`) ou un
   terminal externe. `bin/dune` ne produit qu'un exécutable, et `sudo` est déjà dépendance
   dure : c'est le seul des trois qui n'ajoute **ni fichier ni hypothèse de distribution**. Le
   secret ne passe jamais par `argv` (que `ps` publie à tout le monde) ni par un fichier : il
   est écrit sur le **stdin** du processus, dont on ferme aussitôt le tuyau. La sortie du
   script part dans un fichier temporaire et non dans un second tuyau — deux tuyaux et un seul
   lecteur, c'est un interblocage qui attend son jour.
2. **`--only`, sans quoi les trois fichiers ne garantissaient rien** (§ 1 bis.3, rectifié).
3. **La garde du mode piloté est `Script_mode.enabled`, pas `must_auto_answer`** — trouvé au
   premier run du banc, pas déduit. `must_auto_answer` n'est vrai que **pendant** le service
   d'une commande du canal ; or le dialogue s'ouvre depuis un **thread de tâche**, bien après
   que `start` a répondu « accepted ». Avec la garde étroite, la fenêtre de mot de passe a
   réellement surgi au milieu d'une session pilotée et la tâche a attendu un humain. Un mot de
   passe est d'ailleurs la seule réponse pour laquelle aucun défaut ne peut tenir lieu de
   réponse : en session pilotée on refuse, bruyamment, et l'appelant rapporte un échec net.
4. **Le verdict d'échec est mémoïsé, et c'est `Privileges` qui parle à l'utilisateur.**
   Démarrer *un* composant résout son bridge **deux fois** (construction de l'objet de
   simulation, puis démarrage) : sans mémoire, l'utilisateur qui annule était questionné puis
   sermonné deux fois dans la même seconde. Un refus est une réponse ; redemander pour le même
   geste est du harcèlement. Le refus vaut pour la session — pour changer d'avis, relancer
   Marionnet ou lancer le script à la main (la commande exacte figure dans le dialogue d'échec).
   Le succès, lui, n'a besoin d'aucune mémoire : `Nat_bridge.is_usable` répond `true` ensuite.

### 4.3 Épisode 8 en détail — le bridge qui touche à l'hôte

Le NAT bridge (épisode 3) est sûr parce qu'il **ne touche jamais** la carte de l'hôte. Celui-ci
n'a pas cette option : un LAN bridge **est** la carte de l'hôte, asservie à un bridge, avec
l'adresse et la route par défaut déplacées dessus. Tout ce qui suit en découle.

**1. Un seul bridge LAN par hôte, `mnlan0`, et non `mnlan<pid>`.** Une carte n'a qu'**un**
master : deux instances de Marionnet ne peuvent pas avoir chacune le leur. Elles le
**partagent** — ce qui est aussi ce qu'elles faisaient du `br0` fabriqué à la main. Le § 1 bis.2
point 4 est corrigé en conséquence.

**2. La propriété se lit sur le système, pas dans un fichier d'état.** Les ports du bridge
nommés `mtap<pid>-<n>` **sont** la liste de ses usagers ; `down` ne démonte que si plus aucun
n'appartient à un processus vivant. Le créateur ajoute `alias marionnet-lanbridge:<pid>` sur le
bridge, ce qui ferme la fenêtre entre « le bridge existe » et « le premier tap y est attaché »
— sans quoi le `gc` d'une seconde instance pourrait ramasser le bridge sous les pieds de la
première. Corollaire du même choix : **la restauration de l'hôte se relit elle aussi sur le
système** (le bridge porte l'adresse et la route ; le port physique est le seul port non-`mtap`),
donc **aucun fichier d'état** — ni à partager entre comptes Unix, ni à retrouver après un crash.
C'est plus simple que le NAT bridge, qui en garde un pour la seule mémoire de `ip_forward`.

**3. L'ordre des opérations est la sûreté même.** L'adresse est posée **sur le bridge avant**
d'être retirée de la carte : elle n'est donc *jamais nulle part*, pas même un instant, et comme
le bridge n'a pas encore de port, rien ne répond deux fois sur le fil. Le déroulé LIFO en découle
et c'est le seul qui marche : supprimer la route, **libérer la carte** (`nomaster`), *puis*
seulement lui rendre son adresse et sa route. Restaurer une adresse sur une carte encore esclave
ne marcherait qu'à moitié, et y rajouter une route par défaut échouerait. Reste une fenêtre de
quelques millisecondes, entre le retrait de l'adresse et la route sur le bridge, où l'hôte n'a
plus de sortie ; un `SIGKILL` pile là laisse l'adresse **sur le bridge** — ce que `down` et `gc`
savent précisément rendre.

**4. Le bloc (c) du sudoers est large, et le dit.** Les lignes qui nomment le bridge sont bornées
à `mnlan*` comme ailleurs ; les trois dernières (`ip addr add/del * dev *`, `ip route add default
via * dev *`) ne peuvent pas l'être, la carte de l'hôte n'ayant pas de nom fixe. Le droit
accordé est donc, en clair, « reconfigurer l'adressage IPv4 de cette machine » — ce qui *est* la
fonctionnalité. L'en-tête du fichier installé l'écrit sans euphémisme, et c'est exactement
pourquoi ce bloc est séparé, désactivé par défaut, et demandé par l'**utilisateur** au moment où
il pose un LAN bridge, jamais accordé d'avance par un administrateur.

**5. Trois refus, plutôt qu'un demi-succès** : le Wi-Fi (l'AP refuse les MAC multiples d'un
bridge — le NAT bridge, lui, marche en Wi-Fi et c'est ce que le message conseille), une carte
déjà asservie, et une route par défaut ambiguë (zéro ou plusieurs cartes). Plus deux
avertissements non bloquants : NetworkManager gère la carte (il peut la reconfigurer dans notre
dos), et l'adresse est **recopiée en statique** — aucun bail DHCP n'est renouvelé sur le bridge.

**6. `--netns`, ou comment prouver un chemin destructeur sans casser la machine qui teste.** Le
`selftest` ne peut pas déplacer l'adresse de la carte sur laquelle on est assis : il se construit
donc un hôte à lui, dans des espaces de noms réseau — un netns « hôte » (une fausse carte, une
adresse, une route par défaut), un netns « LAN » (la passerelle) et un netns « invité » —, et y
joue le vrai `up` puis le vrai `down` via `--netns`. Ce qui est prouvé est ce qui compte : la
passerelle reste joignable **après** la migration, un invité accroché au bridge atteint le LAN à
travers lui (la promesse même du LAN bridge), et la carte **retrouve** adresse et route par
défaut. Comme le banc netns du NAT bridge, tout cela est hors règle sudoers **par choix** : c'est
un échafaudage de test, pas un chemin produit — d'où le `sudo` interactif.

### 4.4 Épisode 7 en détail — le dédoublement, en trois temps

L'épisode 7 est le seul gros morceau OCaml/GUI du chantier, et il couvre six sujets qui n'ont
pas la même nature (un script hôte, un module d'appel, une nature de composant, un dialogue,
une suppression). Il se joue donc en **trois sous-épisodes**, chacun prouvable et committable
seul :

| Sous-épisode | Contenu | OCaml |
|---|---|---|
| **7a** | la nature *NAT bridge* : script hôte multi-instances, `Nat_bridge_host` indexé, composant neuf, menu planète à 3 entrées, `.mar`, canal, treeviews | oui (le gros) |
| **7b** | le *LAN bridge* devient automatique : `Lan_bridge_host` appelant `marionnet-lanbridge.sh`, bloc (c) demandé depuis la GUI, avertissement de coupure hôte | oui |
| **7c** | retrait de `MARIONNET_WORLD_BRIDGE_MODE` et de `Global_options.world_bridge_mode` ; `check_bridge_existence_and_warning` **gardé mais retourné** (cf. journal du 2026-08-17) | oui (suppression) |

**Nomenclature des modules** (arrêtée avant d'écrire la première ligne, parce que le nom
`nat_bridge` était déjà pris par l'appelant de l'épisode 3) : le suffixe **`_host`** désigne
l'appelant OCaml mince d'un **script hôte**, et le **nom nu** le **composant** du réseau
virtuel. D'où `bridge_common.ml` (le tronc commun), `lan_bridge.ml` (ex-`world_bridge.ml`) et
`nat_bridge.ml` (neuf) pour les composants ; `nat_bridge_host.ml(i)` (ex-`nat_bridge.ml(i)`) et
`lan_bridge_host.ml(i)` (neuf) pour les appelants.

**L'identité interne du LAN bridge ne change pas** : `string_of_devkind` reste `"world_bridge"`,
la racine `.mar` et le `kind` du canal de contrôle aussi. Seuls les **libellés** deviennent
« LAN bridge ». Un `.mar` écrit hier reste lisible, et les scripts de TP publiés (qui disent
`add world_bridge`) continuent de fonctionner sans alias ni migration : le renommage ne se voit
que là où un humain lit, ce qui est précisément l'objet de ce chantier.

**7a.1 — le script hôte apprend à en tenir plusieurs.** `marionnet-natbridge.sh` nommait son
bridge `mnbr<pid>` : **un par processus**. Un bridge par composant impose un suffixe
d'instance, `mnbr<pid>-<n>`, sur le patron exact des taps (`mtap<pid>-<n>`). L'option
`--instance N` est **optionnelle** : sans elle le nom reste celui d'hier, donc l'appelant OCaml
actuel et tout ce qui existe déjà continuent de marcher inchangés. Trois points méritent d'être
notés :

1. **`mnbr123` est un préfixe de `mnbr123-1`.** Chercher un tag iptables par sous-chaîne
   (`grep -F`) faisait donc croire au `down` du bridge non suffixé que les règles de l'instance 1
   étaient les siennes — et il aurait tenté de les supprimer avec le mauvais sous-réseau.
   D'où `tagged_rules_exist`, qui exige que le tag soit suivi d'autre chose qu'un chiffre ou un
   tiret. C'est le genre de bogue qu'aucun test à une seule instance ne peut révéler.
2. **Un nom d'interface ne dépasse pas 15 caractères** (`IFNAMSIZ - 1`) et le noyau **refuse**
   au lieu de tronquer. `require_bridge` mesure donc la longueur et rend `E_BAD_INSTANCE` avant
   toute action : un pid à 7 chiffres laisse la place à 3 chiffres d'instance.
3. **Le `gc` reste exact** parce qu'il déduit du nom, désormais, *et* le pid *et* l'instance
   (`pid_of_bridge` / `instance_of_bridge`) : un processus mort qui laisse trois bridges se fait
   ramasser en trois `down` ciblés, sans fichier d'état.

**Le bloc (b) du sudoers n'a eu aucune modification à recevoir** : ses lignes bornent le device
à `mnbr*` et le tag à `marionnet-natbridge\:mnbr*`, deux globs que la forme suffixée satisfait.
Ce n'est pas une supposition — la couverture a été rejouée par la méthode de l'épisode 8
(correspondance `fnmatch`, le modèle de sudo) sur les trois formes de nom : **15/15** pour
`mnbr<pid>`, `mnbr<pid>-1` et `mnbr<pid>-42`.

**7a.2 — l'appelant OCaml prend le nom qui lui revient, et sait en tenir plusieurs.** Deux
gestes, tous deux préalables au composant :

1. **Le nom `nat_bridge` est libéré.** `bin/nat_bridge.ml(i)` devient
   `bin/nat_bridge_host.ml(i)` (`git mv`), conformément à la nomenclature ci-dessus : le nom nu
   appartient au **composant** (7a.3), le suffixe `_host` à l'**appelant du script hôte**. Le
   renommage ne touche que des références de modules (`world_bridge.ml`, `privileges.ml(i)`,
   `global_options.ml(i)`) et deux renvois en commentaire dans le script lui-même ; `bin/dune`
   est inchangé (les modules de la GUI sont pris par `(:standard \ …)`), et aucune chaîne
   traduite n'est touchée, donc **aucune dette i18n** n'est créée.
2. **Le mémo d'un bridge devient une table de bridges.** `ensure` mémoïsait un
   `t option ref` — un bridge par processus, ce que l'épisode 3 suffisait à justifier. Il tient
   désormais une `(int option, t) Hashtbl.t` dont la **clé est l'argument d'instance**, `None`
   étant le nom non suffixé. `up` et `down` prennent un `?instance` qu'ils transmettent au
   script ; `t` gagne un champ `instance : int option`, lu dans le rapport — c'est ce qui
   permettra à 7a.3 de savoir quels numéros sont déjà pris en lisant `status`, toujours **sans
   fichier d'état**. L'`at_exit`, enregistré une seule fois et gardé par le pid comme avant,
   démonte **toutes** les entrées de la table : en oublier une laisserait un bridge et ses
   règles NAT derrière, à la charge du `gc` d'un run ultérieur.

**Ce que 7a.2 ne fait délibérément pas** : allouer les numéros (c'est le composant qui les
possède, un par bridge), et fournir un `release ~instance` — personne ne détruit encore un
bridge sans quitter l'application ; cette fonction viendra en 7a.3 avec son usage, à l'arrêt
d'un composant.

**7a.3 — la 9ᵉ nature, elle-même en deux temps.** Le découpage d'abord envisagé (« a : la
nature vit, prouvée par le canal ; b : le menu planète ») **ne tient pas**, et c'est le code
qui le dit : un composant n'est relu depuis un `.mar` que si sa procédure d'import a été
souscrite (`network#subscribe_a_try_to_add_procedure`), or cette souscription est faite **dans
le foncteur `Make_menus`** de chaque composant, instancié par `bin/gui/gui_toolbar_COMPONENTS.ml`.
Sans entrée de menu, pas de rechargement : la GUI n'est pas détachable de « la nature existe ».
Le découpage effectivement prouvable sépare donc le **refactor** de l'**ajout** :

| | Contenu | Nature |
|---|---|---|
| **7a.3.a** | `bin/bridge_common.ml`, tronc commun extrait de `world_bridge.ml` | refactor pur, aucune nature nouvelle |
| **7a.3.b** | `bin/nat_bridge.ml`, devkind `` `Nat_bridge ``, icônes, menu planète à 3 entrées, canal, treeviews, `.mar`, allocation et libération d'instance | ajout |

**7a.3.a — ce que les deux bridges ont en commun.** Un composant bridge est un nœud à un seul
port dont le périphérique simulé est un hub vde à deux ports : un tun/tap de l'hôte d'un côté,
le hublet du composant de l'autre. Ce mécanisme est identique que le tap rejoigne un bridge
posé par un administrateur (le LAN bridge d'aujourd'hui) ou le bridge privé que Marionnet se
construit. La seule chose qui diffère est **quel** bridge — d'où la forme retenue : le tronc
reçoit une **fonction** `resolve_bridge_name : unit -> string`, il n'inspecte aucun mode.
`bin/bridge_common.ml` contient donc `Const`, `Data`, la classe user-level `bridge` (virtuelle :
le périphérique simulé est précisément ce qui distingue les deux natures ; son `kind_name`
donne à la fois la racine du sous-arbre `.mar`, le `device_type` des défauts et le préfixe des
icônes) et la classe `bridge_device` (tap, hub, câble interne, cycle de vie), avec deux points
d'extension : `resolve_bridge_name`, et un `?after_terminate` appelé après la destruction du
tap — c'est par là que le NAT bridge rendra son numéro d'instance en 7a.3.b.

Ce qui n'y est **pas**, délibérément : le squelette `Make_menus` et les dialogues. Les huit
composants du programme les répètent déjà à l'identique — c'est le patron maison — et **aucun**
des mots des deux bridges n'est le même (libellés, tooltips, aide) : un foncteur à une dizaine
de paramètres textuels alignerait ce qui n'a aucune raison de l'être.

**7b — le LAN bridge devient automatique.** L'épisode 8 avait écrit et prouvé le script hôte
`marionnet-lanbridge.sh` ; personne ne l'appelait. 7b est l'OCaml qui manquait :
`bin/lan_bridge_host.ml(i)` (l'appelant mince, jumeau de `nat_bridge_host`),
`Privileges.ensure_lanbridge` (le bloc (c), demandé depuis la GUI comme (b) l'est depuis
l'épisode 6) et `bin/world_bridge.ml` → **`bin/lan_bridge.ml`**, qui résout enfin son bridge
au lieu d'attendre qu'un administrateur en ait posé un. Quatre choses méritent d'être écrites,
parce qu'aucune ne se redevine :

1. **`MARIONNET_BRIDGE` reste une surcharge explicite** — et c'est ce qui rend l'épisode
   rétro-compatible sans le moindre alias : la variable configurée signifie « un administrateur
   a fait le travail, n'y touche pas », son absence signifie « construis-le toi-même ». Mais la
   variable était **livrée définie** (`etc/marionnet.conf` portait `MARIONNET_BRIDGE=br0` depuis
   2008) : sans rien d'autre, l'automatique n'aurait **jamais** tourné nulle part. La ligne est
   donc commentée, et une valeur **vide** compte pour non configurée — sur un poste mis à jour
   plutôt qu'installé, `/etc/marionnet/marionnet.conf` garde l'ancienne ligne et seul root peut
   la changer, alors que `MARIONNET_BRIDGE=` dans `~/.marionnet/marionnet.conf` suffit.
   `Global_options.explicit_world_bridge_name : string option` porte cette distinction, qu'un
   simple `string` ne pouvait pas porter (« br0 » est à la fois le défaut et une réponse
   plausible). `check_bridge_existence_and_warning` s'y raccroche aussi : avertir qu'un bridge
   manque n'a de sens que si quelqu'un l'a réclamé.
2. **La sonde de privilèges a dû être ajoutée au script.** Pour le NAT bridge, `status`
   faisait l'affaire : il lance `iptables-save`, donc il traverse le même `sudo` que le reste.
   Ici `status` lit l'hôte avec un `ip` **non privilégié** et réussit que le bloc (c) soit
   installé ou non : il ne prouve rien. D'où **`check-privileges`**, qui suit la discipline de
   `tap_provider.ml` — exécuter une vraie commande de notre liste, sans effet : `ip link del`
   sur `mnlan999`, un bridge que nous ne créons jamais et que le glob `mnlan*` du bloc (c)
   couvre. Différence avec la sonde des taps : détruire un device absent **échoue**, donc le
   verdict ne se lit pas dans le code de retour mais dans **qui** a écrit le message — d'où
   `LC_ALL=C` (les diagnostics de sudo sont traduits, ceux d'iproute2 non) et un verdict tiré
   du « Cannot find device » d'iproute2. `sudo -n -l` reste exclu, pour la raison déjà mesurée
   dans `tap_provider.ml` : sur un poste ordinaire il répond « autorisé » sans aucune règle de
   nous, et le `sudo -n` qui suit réclame un mot de passe.
3. **Le mémo d'`ensure` ne s'oublie que si le bridge a vraiment été retiré.** `mnlan0` est
   **partagé** : le `down` d'un composant est très normalement refusé parce qu'un autre
   composant, ou un autre Marionnet, y a encore un tap — et c'est un succès (`kept`), pas une
   erreur. Oublier le mémo là serait faux deux fois : l'`at_exit` ne trouverait plus rien à
   rendre, et l'`ensure` suivant relancerait un `up` sur un bridge que nous tenons déjà. D'où
   un `down` qui **rend le booléen `removed`**, et un `release` qui ne fait **rien du tout**
   quand nous ne tenons rien : un `down` que personne n'a demandé pourrait démonter le bridge
   qu'une autre instance vient de construire et sur lequel elle n'a pas encore attaché de tap.
   Côté composant, un `asked_for_the_automatic_bridge : bool ref` garde la même invariance —
   seul celui qui a demandé rend.
4. **Le renommage ne se voit que là où un humain lit.** `git mv world_bridge.ml lan_bridge.ml`,
   modules et libellés en « LAN bridge » ; **inchangés** : le devkind `` `World_bridge ``, le
   `kind_name "world_bridge"` (donc la racine `.mar`, le `device_type` des défauts), le motif
   d'import (`world_bridge` **et** `gateway`), le `kind` du canal de contrôle et le préfixe de
   socket. Vérifié au run : `help` publie toujours `world_bridge` parmi ses `kinds`, et un
   projet sauvegardé porte `world_bridge` dans `netmodel/network.json` comme dans
   `states/defects.json`.

## 5. Points de vigilance transverses

- **Messages de commit en anglais** (règle dépôt) ; tag/scope = `modernisation-world-bridge`.
- **i18n** : toute modification de `s_`/`f_` déclenche un refresh POT/PO ×12 — regrouper (cf.
  invariant « on ne supporte que des catalogues complets », mémoire `marionnet-i18n`).
  **Dette ouverte, à solder par ce chantier** (constaté le 2026-08-12, épisode 13 de
  `journalisation-profonde`) : les **3 seules** chaînes non traduites des douze catalogues sont
  les longs textes d'aide introduits par l'épisode 1 d'ici — `msgid` de `world_bridge.ml:63`,
  `:196` et `:220`. Elles sont dans le POT et attendent leur `msgstr` dans les 12 langues ;
  tant qu'elles y sont, l'invariant reste faux **du fait de ce chantier seul**.
- **Sécurité** : ne pas élargir le motif sudoers au-delà du nécessaire ; garde `owner_pid`
  sur les `at_exit` (piège `daemon-elimination` ép. 6).
- **Ne pas régresser** le lab distribué multi-machines (usage 2) ni la surface plus étroite
  obtenue par `daemon-elimination`.
- **Pièges rencontrés à l'épisode 2**, hors sujet du chantier mais coûteux :
  - un chemin de `--control-socket` **trop long** (> 108 octets, la limite de `sun_path`)
    fait démarrer Marionnet **sans jamais créer le socket ni rien signaler** ;
  - le rootfs `debian-trixie-47362` **n'écrit pas le marqueur `marionnet-guest-ready`** :
    `wait --ready` a expiré au bout de 240 s sur une machine parfaitement fonctionnelle (les
    `exec` suivants ont tous répondu en ~1 s). À verser au chantier `marionnet-kernel-rootfs` ;
  - **bashbricks n'est pas `set -u`-safe** (mesuré : `source` échoue sur `__bb_REPLACE_REFS`,
    `Array_make` sur `__bb_PLUS`) — d'où le Bash nu du POC, justifié dans son en-tête.

## Journal d'avancement

- **2026-07-18 — épisode 0** : officialisation du chantier `modernisation-world-bridge`
  (fiche mémoire `modernisation-world-bridge`, tag de commits `modernisation-world-bridge`,
  ce document + pointeur `CLAUDE.md`). Étude de l'axe barrière : tableau comparatif (§ 2.1),
  décision de cadrage « A par défaut + B option experte », points durs (§ 2.2). Aucun code
  fonctionnel touché. Prochain pas : épisode 1 (GUI comprehensibilité).
- **2026-07-18 — épisode 1** : GUI comprehensibilité, increment 1. `bin/world_bridge.ml` —
  `help_callback` réécrit (rôle, `world_bridge` vs `world_gateway`, prérequis ; vocabulaire
  daté et `TODO rename` purgés) ; tooltips palette/nom/image enrichis. Sources anglaises
  seules ; refresh gettext ×12 **différé** à un épisode i18n consolidé (catalogues
  temporairement incomplets sur ces chaînes). Vérif : `dune build` rc=0 ; pas de run GUI
  (rig indisponible ; changements = texte d'aide/tooltip). Prochain pas : épisode 2 (POC
  système NAT bridge privé auto, axe A).
- **2026-08-15 — épisode 2** : axe A, POC système du « NAT bridge privé auto », sans OCaml.
  Nouveau `useful-scripts/marionnet-natbridge-poc.sh` (`up`/`down`/`status`/`gc`/`selftest`/
  `print-privileged-commands`) : bridge `mnbr<pid>`, /24 choisi en évitant ce qui est déjà
  routé, MASQUERADE + deux règles `FORWARD`, artefacts tous étiquetés
  `marionnet-natbridge:mnbr<pid>` pour un `gc` par pid mort, `ip_forward` restauré seulement
  s'il a été changé. **Prouvé deux fois** (§ 2.1 bis) : `selftest` système (netns invité :
  ICMP + DNS, puis démontage sans résidu) ; et bout en bout avec un vrai Marionnet piloté par
  `--control-socket` (machine trixie + `world_bridge`, `ping -c2 9.9.9.9` → 0 % de perte,
  `nslookup` → réponse), la route par défaut de l'hôte inchangée. Résultat structurant :
  `world_bridge` et `Tap_provider` n'ont eu **aucune** modification à recevoir — l'épisode 3
  n'a donc à écrire en OCaml que la création/destruction du bridge et des règles NAT, plus le
  motif sudoers correspondant. Prochain pas : épisode 3 (câblage OCaml + sudoers + mode dans
  le dialogue).

- **2026-08-16 — épisode 3** : *le POC devient un outil hôte, et l'OCaml l'appelle*.
  **Révision de cadrage assumée** (§ 4.1) : on ne porte PAS la séquence `ip`/`iptables` en
  OCaml — elle est déjà la source de vérité de la règle sudoers, la réécrire aurait créé un
  second exemplaire à tenir en phase pour aucun gain. `git mv` de
  `useful-scripts/marionnet-natbridge-poc.sh` vers **`bin/scripts/marionnet-natbridge.sh`**,
  réécrit sur bashbricks avec un **contrat de sortie JSON** (stdout = un objet, une ligne, sur
  tous les chemins ; stderr = trace humaine ; code d'erreur symbolique) et un **rollback
  transactionnel** (pile d'annulation dépilée en LIFO, `leftovers` rapportés honnêtement,
  `trap ERR/INT/TERM`) ; `down` est le même dépilement appliqué à ce que le système dit
  exister, ce qui le rend correct après un crash. Côté OCaml, **`bin/nat_bridge.ml(i)`** ne
  fait qu'appeler et lire le JSON (`ensure` mémoïsé + `at_exit` gardé par le pid, idiome
  `Tap_provider`), et `world_bridge.ml` résout le nom du bridge **au démarrage du composant**
  (`resolve_bridge_name`) et non plus à l'initialisation — c'était la seule vraie couture,
  puisque `MARIONNET_BRIDGE` est lu trop tôt. Mode par `Global_options.world_bridge_mode`
  (défaut conservateur : `Manual` si `MARIONNET_BRIDGE` est configuré, `Nat` sinon ;
  `MARIONNET_WORLD_BRIDGE_MODE` tranche et tient lieu de sélecteur jusqu'à l'épisode 4).
  Installation : les **quatre** fichiers ensemble dans `share/marionnet/scripts/`
  (`bashbricks/dune` neuf — la bibliothèque n'était jamais installée). Règle sudoers étendue,
  toujours dérivée de `print-privileged-commands`, avec le **tag iptables obligatoire** comme
  garde principale. **Preuves mesurées le 2026-08-16, règle sudoers installée** : `dune build`
  rc 0 ; contrat JSON tenu sur tous les chemins d'erreur (`E_BAD_PID`, `E_BAD_SUBNET`,
  `E_USAGE`) ; **cycle `up`/`status`/`down` réel** — les 6 commandes privilégiées passent en
  `sudo -n` (donc la règle, échappements compris, matche vraiment), le système confirme
  `192.168.101.1/24` sur `mnbr<pid>` et 3 règles taguées, puis après `down` : bridge absent,
  0 règle, `ip_forward` inchangé ; **rollback réel** (`--fail-after forward_in`, sans
  `--dry-run`) — 5 étapes appliquées sur le vrai système, dépilées en LIFO,
  `leftovers:[]`, et vérification système « rien ne survit » ; route par défaut de l'hôte
  intacte tout du long. `visudo -cf` accepte la règle ; `make install-for-testing` place les
  quatre fichiers côte à côte et l'appel **par nom nu** hors du dépôt trouve bashbricks.
  Deux défauts corrigés en cours d'essai : le code d'erreur d'une étape est désormais décidé
  **par l'étape** (`fail_step`) et non supposé au site d'appel — un échec injecté ne se
  déguisait plus en `E_SUDO_DENIED` ; et le **banc d'essai** du `selftest` (veth + netns),
  délibérément hors de la règle sudoers, utilise un `sudo` interactif (`sudo_test_run`) tandis
  que le chemin produit garde `sudo -n` : montrer que le produit n'a besoin d'aucun mot de
  passe est précisément l'objet de l'exercice. **`selftest` PASSED** (invité netns : ICMP
  59,1 ms + DNS, puis démontage sans résidu). **Palier 2 rejoué et vert** : Marionnet réel
  lancé en `MARIONNET_WORLD_BRIDGE_MODE=nat` avec `--control-socket`, maquette `m1 --- w1`
  (trixie / 6.12.95) — **c'est Marionnet qui a créé `mnbr<son pid>`** et y a attaché son propre
  `mtap<pid>-1` ; depuis l'invité UML en `192.168.101.2/24` : `ping -c2 9.9.9.9` → **0 % de
  perte** (59,1 / 55,4 ms) et `nslookup example.org 9.9.9.9` → réponse complète ; route par
  défaut de l'hôte inchangée. Puis `quit` → l'`at_exit` de `Nat_bridge` a tout retiré : plus de
  `mnbr*`, 0 règle taguée, plus de `mtap*`, `ip_forward` intact, seul `docker0` subsiste.
  **Troisième défaut trouvé par ce run et corrigé** : `MARIONNET_WORLD_BRIDGE_MODE` doit être
  déclarée dans la liste blanche de `bin/configuration.ml`, sinon la nommer fait mourir le
  démarrage sur `Invalid_argument("Unexpected variable name")` — un mode inutilisable serait
  passé inaperçu sans essai réel. Au passage, la **valeur par défaut a été confirmée en
  situation** : `/etc/marionnet/marionnet.conf` de ce poste porte `MARIONNET_BRIDGE=br0`, donc
  le mode par défaut y est bien `Manual` — aucune installation existante ne change de
  comportement, et c'est la variable qui tranche. Deux pièges mesurés : les
  métacaractères sudoers `!`/`,`/`:` doivent être échappés sinon `visudo` rejette **tout** le
  fichier ; et `Map_to_json` parse les scalaires, donc un message d'erreur qui *ressemble* à du
  JSON doit passer par `Map_to_json -s`. Dépendance hôte neuve : **`jq`**.

- **2026-08-16 — épisode 4** : *restructuration du chantier — le mode devient un composant*.
  Aucun code fonctionnel. L'objectif final est révisé (§ 1 bis, qui prime désormais sur ce que
  les § 2 à 4 disent du « mode ») : l'utilisateur ne réglera pas un mode sur `world_bridge`, il
  **choisira son équipement** dans le menu planète, qui passe de deux à **trois** entrées —
  *Gateway* / *NAT bridge* / *LAN bridge*. Six décisions arrêtées avec l'auteur : (1) **deux
  natures de composants** distinctes plutôt qu'un attribut caché — le coût (9ᵉ nature : canal de
  contrôle, `.mar`, treeviews, icônes, i18n) est payé pour la seule chose qui compte
  pédagogiquement, deux équipements visiblement différents sur le dessin ; (2) le vocabulaire
  **« LAN bridge »**, qui dit l'effet obtenu, contre « Level 2 » (jargon OSI), « raw » et
  « manual » (qui nomme la contrainte d'hier) ; (3) **`MARIONNET_WORLD_BRIDGE_MODE` disparaît**,
  ainsi que son « défaut conservateur » — un `.mar` existant reste un LAN bridge, donc son
  comportement d'hier, sans qu'aucune variable ne le décide ; (4) **un bridge NAT par
  composant** (deux composants = deux réseaux privés séparés, ce qu'attend l'étudiant qui pose
  deux équipements), donc l'`ensure` mémoïsé de l'épisode 3 devient une table ; (5) le LAN
  bridge devient **automatique lui aussi** — l'option B du § 2.1, promue de « peut-être un
  jour » à composant de plein droit, par un `marionnet-lanbridge.sh` symétrique du script NAT,
  avec **avertissement de coupure hôte** dans le dialogue ; (6) les **privilèges se demandent au
  moment où ils servent** : la règle sudoers se scinde en un socle **(a)** posé par
  l'administrateur à l'installation (taps — sans lui rien ne marche) et deux extensions
  **(b)**/**(c)** que l'utilisateur final active depuis la GUI (`--enable-natbridge`,
  `--enable-lanbridge`, raccourci `--enable-bridges`), dans **trois fichiers séparés** de
  `/etc/sudoers.d/` pour que l'activation run-time n'ait jamais à réécrire le fichier vital.
  L'élévation passe par `sudo` — déjà dépendance dure du projet, donc **aucune hypothèse de
  distribution**, contrairement à `pkexec`/PolicyKit absent des systèmes minimaux et des
  conteneurs. Nouveau découpage en § 4 (ép. 5 sudoers → 6 élévation GUI → 7 dédoublement des
  composants → 8 `marionnet-lanbridge.sh` → 9 i18n), ordonné par dépendance : chaque épisode se
  prouve seul. Prochain pas : épisode 5.

- **2026-08-16 — épisode 5** : *la règle sudoers en trois blocs*. `bin/scripts/marionnet-sudoers.sh`
  n'écrit plus un fichier mais **jusqu'à trois**, un par bloc, dans `/etc/sudoers.d/` :
  `marionnet` (a, taps), `marionnet-natbridge` (b), `marionnet-lanbridge` (c). Un sélecteur
  **unique** vaut pour les quatre sous-commandes — bloc (a) toujours pris, `--enable-natbridge`,
  `--enable-lanbridge` et `--enable-bridges` ajoutent les autres ; `uninstall` inverse les
  défauts (tout par défaut, `--disable-*` pour ne retirer qu'un bloc, et alors (a) est
  délibérément épargné : l'utilisateur renonce à un droit de bridge, il ne désinstalle pas
  Marionnet). Le `Makefile` n'a **rien** à changer : `install "$SUDO_USER"` sans option, c'est
  exactement le nouveau geste d'installation (socle seul) — seul son commentaire dit maintenant
  pourquoi. Le **bloc (c) refuse explicitement de s'installer** (code 3, message nommant
  l'épisode 8) : il est le seul qui nommera la carte de l'hôte, son adresse et sa route par
  défaut — précisément ce que (a) et (b) se gardent de mentionner — et un tel droit se dérive
  commande par commande du script qui les exécute, jamais d'une intention. Deux pièges Bash
  évités en écrivant : sous `set -e`, `$FLAG && BLOCKS+=(x)` est une liste AND qui **échoue**
  quand le drapeau est faux (sortie silencieuse au milieu du parsing) — d'où des `if` partout ;
  et la validation de disponibilité des blocs se fait **avant** toute écriture, sinon
  `--enable-bridges` installerait (b) puis mourrait sur (c), laissant un état que personne n'a
  demandé. Le re-exec privilégié passe `"$@"` tel quel et non une ligne reconstruite : un
  re-exec ne peut donc pas accorder un bloc que l'appelant n'a pas demandé. **Preuves mesurées
  le 2026-08-16** (`bash -n` vert ; cycle complet joué sous `fakeroot` avec
  `MARIONNET_SUDOERS_DIR` pointé sur un répertoire jetable, le poste n'ayant pas de ticket
  `sudo` en session non interactive) : `install` seul écrit **le seul** fichier (a) — et il ne
  contient plus une ligne `mnbr` ; `check --enable-natbridge` répond 1 tant que (b) manque, 0
  ensuite ; `install --enable-natbridge` écrit (b) sans réécrire (a) (« already up to date ») ;
  ré-installation strictement idempotente ; `visudo -cf` accepte les deux fichiers séparément ;
  `uninstall --disable-natbridge` retire (b) et **laisse (a)** ; `uninstall` nu retire les
  trois. Refus contrôlés : `--enable-lanbridge` → rc 3, option inconnue → rc 2, second USER →
  rc 2. **Prouvé ensuite sur le vrai système** (le mot de passe est un geste humain, d'où un
  deuxième temps) : `install --enable-natbridge` a écrit les **deux** fichiers
  `/etc/sudoers.d/marionnet` et `/etc/sudoers.d/marionnet-natbridge` — la scission est donc
  effective là où elle compte — et le **`selftest` de `marionnet-natbridge.sh` est PASSED**
  (bridge `mnbr<pid>` sur `192.168.101.0/24`, invité netns : ICMP 52,4 ms puis DNS,
  démontage complet, `leftovers:[]`, hôte intact). Puis, **ticket `sudo` invalidé**
  (`sudo -k`, sans quoi on ne prouverait rien d'autre que la fraîcheur du ticket) :
  `sudo -n ip link del mnbr9999999` répond « Cannot find device » et
  `sudo -n ip tuntap del dev mtap9999999-1` rend 0 — les deux fichiers matchent **sans mot de
  passe**, séparément ; tandis que `sudo -n ip link del zzz-not-a-marionnet-dev` et
  `sudo -n iptables -A FORWARD -i mnbr1 -j ACCEPT` (une règle **sans notre commentaire**)
  réclament tous deux un mot de passe. La surface n'a donc pas été élargie par la scission :
  ce qui passe est exactement ce que les deux fichiers nomment. Prochain pas : épisode 6
  (élévation depuis la GUI).

- **2026-08-16 — épisode 6** : *l'élévation depuis la GUI*. Marionnet demande désormais
  lui-même les droits du bloc (b), au moment où ils servent. Trois pièces et un correctif de
  l'épisode 5 (détail et *pourquoi* en § 4.2) : **`bin/gui/simple_dialogs.ml`** gagne
  `ask_password` (entrée à visibilité coupée, `Return` = OK, corps sous
  `GMain_actor.apply_extract` puisqu'il est ouvert depuis un thread de tâche) ;
  **`bin/privileges.ml(i)`**, module neuf et minuscule, enchaîne sonde → `sudo -n` (un ticket
  encore valide évite de rien demander) → dialogue → `sudo -S` (3 essais, le mot de passe sur
  le **stdin** et jamais dans `argv`) → re-sonde, d'où un `Nat_bridge.forget_usability` publié
  et un `Tap_provider.sudoers_script` publié aussi (le nom du script reste lu en **un** endroit) ;
  **`bin/world_bridge.ml`** appelle cela avant `Nat_bridge.ensure` et **annonce dans son
  dialogue d'ajout/modification** que le composant demandera un mot de passe à son premier
  démarrage — l'information au moment du geste, pas un échec inexpliqué plus tard ; et
  **`marionnet-sudoers.sh`** reçoit **`--only`**, sans quoi une activation par l'utilisateur
  `Y` réécrivait le fichier (a) de l'administrateur au nom de `Y` (§ 1 bis.3, rectifié).
  **Preuves mesurées le 2026-08-16.** Script seul : `print --only --enable-natbridge` ne rend
  que le bloc (b), `print` nu et `print --enable-natbridge` inchangés, `--only` sans sélection
  → rc 2, `--only` sur `uninstall` → rc 2, `--only --enable-lanbridge` → toujours rc 3 ;
  sous `fakeroot`, `install --only --enable-natbridge` écrit **le seul** fichier (b) et le
  `sha256` de (a) est **identique avant et après**. OCaml : `dune build` rc 0, et le module
  neuf est **réellement compilé** — vérifié par une erreur de type volontaire qui rompt bien le
  build (le piège « dune ne compile pas un module que personne ne référence » ne s'applique
  donc pas ici). Banc réel, Marionnet lancé avec `--control-socket` et deux faux scripts
  (`MARIONNET_NATBRIDGE_SCRIPT` répondant toujours `E_SUDO_DENIED`, `MARIONNET_SUDOERS_SCRIPT`
  traçant ses arguments) : la sonde échoue, `Privileges` prend la main, `sudo -n` échoue (rc 1),
  puis — **run instrumenté, à l'écran** — le dialogue de mot de passe est réellement apparu, a
  été rempli, et le faux script a alors été exécuté **en root** avec exactement
  `install --only --enable-natbridge` : la chaîne dialogue → `sudo -S` → script privilégié est
  donc prouvée de bout en bout. C'est **ce run qui a révélé le défaut de garde** corrigé au § 4.2
  point 3 : la fenêtre n'aurait jamais dû s'ouvrir dans une session pilotée. Après correction,
  le banc rejoué donne exactement ce qu'on veut — **1** demande refusée sans fenêtre (« a
  password was requested in a driven session; NOT asking »), **1** seul dialogue d'erreur
  capturé, **1** réutilisation du verdict mémoïsé au second passage, le composant démarre quand
  même (`state: on`), la session répond encore (`ls`), et ni tap ni bridge résiduel. Les deux
  fichiers de `/etc/sudoers.d/` du poste sont restés **intacts** pendant toute la campagne (le
  banc n'a touché qu'à de faux scripts). **Reste à jouer** (geste humain, avec le **vrai**
  script) : retirer le bloc (b) réel, poser un `world_bridge` en mode `nat` dans une session
  **interactive**, vérifier l'avertissement dans le dialogue d'ajout, taper le mot de passe,
  puis constater `mnbr<pid>` et un `ping` sortant depuis l'invité. Dette : **10 chaînes**
  `s_`/`f_` neuves (8 dans `privileges.ml`, 1 dans `simple_dialogs.ml`, 1 dans
  `world_bridge.ml`) pour l'épisode 9. Prochain pas : épisode 7 (dédoublement des composants).
- **2026-08-16 — épisode 8** : **le bridge LAN devient automatique**, et le bloc (c) du sudoers
  cesse de refuser. `bin/scripts/marionnet-lanbridge.sh` (neuf, patron exact de
  `marionnet-natbridge.sh` : une ligne JSON sur tout chemin de sortie, pile d'undo LIFO,
  validateurs ancrés, `up`/`down`/`status`/`gc`/`selftest`/`print-privileged-commands`,
  `--dry-run`, `--fail-after`) ; `content_lanbridge` de `marionnet-sudoers.sh` **dérivé** de ce
  `print-privileged-commands` (le refus `rc 3` disparaît, et le garde `available_blocks_or_die`
  devient la vérification générale « tout bloc sélectionné doit être productible ») ; 1 ligne
  d'install dans `bin/dune`. **Zéro OCaml**, par la coupe des épisodes 2/3. Les trois décisions
  et leur pourquoi sont en § 4.3 ; les deux dernières ont été **arrachées par les essais**, pas
  déduites :
  1. **`mnlan0`, un par hôte** (§ 1 bis.2 point 4 corrigé) : une carte n'a qu'un master.
  2. **La carte est gravée dans l'alias du bridge** (`marionnet-lanbridge:<pid>:<carte>`). La
     première version la **déduisait** (« le seul port qui n'est pas un `mtap` ») ; le premier
     `selftest` complet l'a tuée en une ligne — l'invité du banc était un port de plus, et le
     script se retrouvait à devoir **choisir** entre deux cartes. On ne devine pas la carte de
     quelqu'un : on la lit. La déduction survit en repli pour un bridge non estampillé.
  3. **L'adresse est posée sur le bridge avant d'être retirée de la carte** : jamais nulle part.
  **Preuves mesurées le 2026-08-16.** `selftest` **PASSED** : trois espaces de noms (hôte
  factice / LAN / invité), le vrai `up` migre l'adresse, la passerelle répond **à travers**
  `mnlan0` (0 % de perte), un invité accroché au bridge par un `mtap<pid>-1` atteint le LAN,
  `down` **refuse** de démonter tant que ce tap appartient à un pid vivant (`kept:true`), puis
  `down --force` déroule `route → enslave → addr_del:0 → addr_add:0 → bridge_up → link` et la
  carte **retrouve** adresse et route par défaut (ping à nouveau vert), sans résidu. Sudoers
  sous `fakeroot` : `visudo -cf` accepte le bloc (c) — l'échappement `\:` de l'alias passe —,
  `install --only --enable-lanbridge` laisse le **sha256 de (a) identique**, `--enable-bridges`
  fonctionne enfin, `uninstall --disable-lanbridge` épargne (a) et (b). **Couverture de la
  règle** : les **15** commandes réellement exécutées, instanciées, sont toutes couvertes par
  une ligne du bloc (c) (correspondance par glob, le modèle du `fnmatch(3)` de sudo) — **0 non
  couverte**. `dune build` rc 0. Deux défauts trouvés par le banc et corrigés : `Array_make X`
  échoue si l'appelant a un `local X` scalaire (`live_users` accumule désormais dans
  `__lb_users`), et la déduction de la carte (point 2). **Découverte du poste** : la machine de
  développement est en **Wi-Fi**, donc `up` y répond `E_WIRELESS` et renvoie vers le NAT bridge
  — le rejeu sur une vraie carte filaire reste à faire ailleurs, le `selftest` en tenant lieu.
  **Reste au chantier** : le câblage OCaml (`Lan_bridge`), l'avertissement de coupure hôte et le
  retrait de `MARIONNET_WORLD_BRIDGE_MODE` partent avec l'épisode 7. Prochain pas : épisode 7
  (dédoublement des composants).

- **2026-08-16 — épisode 7a.1** : *plusieurs bridges NAT pour un seul Marionnet*. L'épisode 7
  se joue en trois temps (§ 4.4) ; celui-ci est le premier et ne touche **aucune ligne
  d'OCaml** : `bin/scripts/marionnet-natbridge.sh` accepte `--instance N` et nomme alors son
  bridge `mnbr<pid>-<n>`, ce qu'exige la décision « un bridge NAT par composant » (§ 1 bis.2
  point 3). L'option est optionnelle et le nom d'hier est le défaut, donc `bin/nat_bridge.ml`
  et tout l'existant sont inchangés. Ajouts : `require_instance`, garde de longueur
  `IFNAMSIZ` dans `require_bridge` (code `E_BAD_INSTANCE`), `pid_of_bridge` /
  `instance_of_bridge` / `bridges_of_pid`, et surtout **`tagged_rules_exist`** — parce que
  `mnbr123` est un **préfixe** de `mnbr123-1` et que la recherche du tag par sous-chaîne
  faisait confondre les règles de deux instances (défaut trouvé en écrivant, pas au banc :
  invisible tant qu'il n'y a qu'une instance). `status` publie le champ `instance` **quand il
  y en a une** (jamais une chaîne vide), `gc` déduit du nom le pid *et* l'instance, et le
  `selftest` monte désormais **deux** bridges, un invité derrière chacun, démonte le premier
  et vérifie que le second survit et sort toujours. **Preuves mesurées** : `bash -n` rc 0 ;
  garde de longueur (16 caractères refusés, 15 acceptés) ; **couverture du bloc (b) du
  sudoers inchangé — 15/15 commandes pour `mnbr<pid>`, `mnbr<pid>-1` et `mnbr<pid>-42`**
  (correspondance `fnmatch`, méthode de l'épisode 8) ; et le **cycle réel sur le système**, en
  `sudo -n` et sans mot de passe : deux bridges simultanés sur deux /24 distincts
  (192.168.101 et .102), `status` les distinguant par leur instance, `down --instance 1`
  laissant le second intact (6 étapes défaites, `rolled_back:true`), `gc` ramassant le second
  après la mort de leur propriétaire, puis **zéro bridge et zéro règle iptables restants** ;
  enfin la non-régression du nom non suffixé (`up`/`status`/`down` identiques à hier). **Reste
  au sous-épisode** : le `selftest` complet (ses invités netns sont hors règle sudoers **par
  choix**, il demande donc un mot de passe — geste humain). Prochain pas : 7a.2
  (`nat_bridge_host.ml(i)`, le mémo devient une table indexée par instance).

- **2026-08-16 — épisode 7a.2** : *l'appelant OCaml prend son nom et sait en tenir plusieurs*
  (§ 4.4). `bin/nat_bridge.ml(i)` → `bin/nat_bridge_host.ml(i)` par `git mv`, ce qui **libère
  le nom `nat_bridge` pour le composant** de 7a.3 ; références mises à jour dans
  `world_bridge.ml`, `privileges.ml(i)`, `global_options.ml(i)` et dans les deux renvois en
  commentaire du script hôte ; `bin/dune` inchangé, aucune chaîne traduite touchée. Côté
  fonction : `up`/`down`/`ensure` prennent un `?instance`, `t` gagne `instance : int option`
  (lu dans le rapport, absent = nom non suffixé), le mémo `t option ref` devient une
  `(int option, t) Hashtbl.t` sous le même mutex, et l'`at_exit` — enregistré une fois,
  toujours gardé par le pid — démonte **toutes** les entrées. **Preuves mesurées** :
  `dune build` rc 0 ; le module est **réellement compilé** (erreur de type volontaire → build
  en échec sur `bin/nat_bridge_host.ml`, retirée, rc 0 de nouveau — le piège « dune ne compile
  pas un module d'exécutable que personne ne référence » est ici vérifié, pas supposé) ; plus
  aucune occurrence de `Nat_bridge` hors `Nat_bridge_host` dans `bin/` ; et un **run réel du
  binaire**, piloté par le canal, avec `MARIONNET_NATBRIDGE_SCRIPT` pointant sur un script
  **simulé** (jetable, hors dépôt) qui journalise son `argv` et rend le JSON du contrat :
  `new` → `add world_bridge w1` → `start w1` a produit exactement `status` (la sonde
  `is_usable`) puis `up --owner-pid <pid de Marionnet>` **sans `--instance`** — la
  non-régression du chemin d'hier — et `quit` a produit `down --owner-pid <même pid>` par
  l'`at_exit`, avec sortie du processus en rc 0 et aucun résidu. Le banc simulé est le bon
  outil ici : il exerce **ce que 7a.2 change** (arguments, table, `at_exit`) sans privilège,
  alors que la partie privilégiée, inchangée, est déjà prouvée aux épisodes 3 et 7a.1.
  **Reste au sous-épisode** : la table à **plusieurs** entrées n'est pas encore exercée au run
  — décision prise avec l'utilisateur, cette preuve appartient à 7a.3, où deux composants
  alloueront deux numéros et deux /24 ; et le rejeu privilégié (`sudo -n`) n'a pas été refait,
  le bloc (b) n'étant plus installé sur ce poste (`sudo -n … status` demande un mot de passe).
  Prochain pas : **7a.3** (`bridge_common.ml`, le composant `nat_bridge.ml`, la 9ᵉ nature, le
  menu planète à 3 entrées, `.mar`, canal, treeviews, icônes).

- **2026-08-16 — épisode 7a.3.a** : *ce que les deux bridges ont en commun*. Nouveau
  `bin/bridge_common.ml` (~290 l.) : `Const`, `Data`, la classe user-level virtuelle `bridge`
  (paramétrée par `~devkind` et `~kind_name`, d'où la racine `.mar`, le `device_type` des
  défauts et le préfixe des icônes) et la classe `bridge_device` (tap par `Tap_provider`, hub
  vde à 2 ports, câble interne, `spawn`/`terminate`/`stop`/`continue`), avec deux points
  d'extension : `~resolve_bridge_name : unit -> string` — le tronc **n'inspecte aucun mode**,
  il reçoit une fonction — et `?after_terminate`, par où le NAT bridge rendra son instance en
  7a.3.b. `bin/world_bridge.ml` **perd 217 lignes pour 44** : il ne garde que ses mots (menus,
  dialogue, aide), sa fonction de résolution (`Manual` → `MARIONNET_BRIDGE`, `Nat` →
  `Privileges` puis `Nat_bridge_host.ensure`) et son `make_simulated_device`. Aucune chaîne
  traduite touchée → **aucune dette i18n** ; `bin/dune` inchangé. Un seul renommage visible :
  `update_world_bridge_with` devient `update_bridge_with` (hérité du tronc, appelé du seul
  `Properties.reaction`). **Preuves mesurées** : `dune build` rc 0, et le module est
  **réellement compilé** (erreur de type volontaire dans `bridge_common.ml` → build en échec
  sur ce fichier, retirée → rc 0). Surtout, **non-régression au run réel, avec privilèges** —
  contrairement à ce que disait la fiche mémoire, les blocs (a) et (b) sont bien installés sur
  ce poste : session pilotée par le canal, `MARIONNET_WORLD_BRIDGE_MODE=nat` et le **vrai**
  `bin/scripts/marionnet-natbridge.sh` ; `new` → `add world_bridge B1` → `start B1` →
  `wait --state=on` a donné, côté hôte, `mnbr<pid>` **créé** et `mtap<pid>-0` **asservi**
  (`master mnbr<pid>`) ; puis `stop`, `save`, `close --save`, `open` ont rendu le composant
  (`ls` → `B1 / world_bridge / off` : round-trip `.mar` intact), et `quit` a tout démonté —
  aucune interface `mnbr`/`mtap` résiduelle, processus sorti. Prochain pas : **7a.3.b**
  (la 9ᵉ nature elle-même).

- **2026-08-16 — épisode 7a.3.b** : *la 9ᵉ nature*. Nouveau **`bin/nat_bridge.ml`** (~400 l.,
  patron des huit composants) : `Make_menus` complet (dont la **souscription** de
  `try_to_add_nat_bridge`, sans quoi un `.mar` ne se relit pas), dialogue et aide avec **ses
  propres mots**, `User_level_nat_bridge.nat_bridge` sur le tronc de 7a.3.a
  (`~devkind:`Nat_bridge`, `~kind_name:"nat_bridge"`) et `Simulation_level_nat_bridge` qui
  fournit au tronc ses deux fonctions. Autour : `` `Nat_bridge `` dans `devkind`
  (`user_level.ml` **et** `.mli` — le devkind n'est qu'un filtre d'égalité, donc aucun `match`
  exhaustif à compléter), la 3ᵉ entrée du menu planète (`gui_toolbar_COMPONENTS.ml`, libellés
  *Gateway* / *NAT bridge* / *LAN bridge*), `known_kinds` + le constructeur du canal
  (`control_server.ml`), les deux treeviews, et **`Nat_bridge_host.release ~instance`** (le
  `down` **et** l'oubli du mémo, annoncé par 7a.2 comme « viendra avec son usage »).
  - **L'allocation des numéros vit dans le composant**, sous un mutex de module :
    `Nat_bridge_host.status` → instances des bridges de **notre** pid → plus petit entier libre
    ≥ 1 → `ensure ~instance` **dans la même section critique** (deux composants démarrés en
    parallèle par le task runner liraient sinon la même liste). Aucun fichier d'état. Le numéro
    est rendu par `?after_terminate`, donc réutilisable dès l'arrêt du composant.
  - **Icônes** : `bin/images/make-bridge-icons.sh` (neuf, rejouable — les chunks de date du PNG
    sont exclus, sinon chaque exécution apparaîtrait comme une modification dans git) dérive
    **deux** jeux badgés, `ico.nat_bridge.*` (« NAT ») et `ico.lan_bridge.*` (« LAN »), des 18
    `ico.world_bridge.*` **laissées intactes comme source**. D'où un `?icon_prefix` optionnel
    dans `Bridge_common` (défaut = `kind_name`) : le LAN bridge reste `world_bridge` dans les
    `.mar` et sur le canal, et ne change que de dessin. Dépannage assumé jusqu'à l'épisode
    d'iconographie (à 32 px le mot est à peine lisible).
  - **Preuves mesurées** : `dune build` rc 0 ; module **réellement compilé** (erreur volontaire
    → échec, retirée → rc 0) ; script d'icônes **idempotent** (`--check` vert au 2ᵉ passage,
    `git diff` vide sur les 18 sources). **Run réel privilégié piloté par le canal** :
    `add nat_bridge N1` + `N2` → `start` des deux → côté hôte **`mnbr<pid>-1` (192.168.101.1)
    et `mnbr<pid>-2` (192.168.102.1)**, chacun avec son propre tap asservi — c'est la preuve au
    run de la table multi-entrées, reportée par 7a.2 ; `stop N1` retire **le premier seul** (le
    second reste `UP`), et un `start N1` récupère le numéro 1 libéré ; `save` / `close --save` /
    `open` rendent les deux composants (`nat_bridge`, `off`, label accentué intact) avec leur
    ligne dans le treeview des défauts ; `quit` démonte tout (`status` du script hôte :
    `bridges:[]`, `leftovers:[]`). Enfin, **bout en bout** : une machine trixie câblée à `N1`,
    adressée en `192.168.101.2/24`, a pingué la passerelle **et 9.9.9.9** à **0 % de perte**.
  - Constats du banc : dans l'arbre source il faut `MARIONNET_NATBRIDGE_SCRIPT` (sans quoi le
    composant démarre « on » **sans** bridge, et seul le journal le dit) ; aucun bridge, LAN ou
    NAT, n'a de ligne dans le treeview `ifconfig` (vérifié sur les deux : le complément de
    `treeview_ifconfig.ml` est de cohérence, pas d'effet observable) ; et `pgrep -f` sur un
    motif contenant le nom du binaire **se matche lui-même** (faux positif « encore vivant »).
  Prochain pas : **7b** (le LAN bridge devient automatique), puis **7c** (retrait du mode).

- **2026-08-17 — épisode 7b** : *le LAN bridge devient automatique* (détail et *pourquoi* :
  § 4.4, « 7b »). Neufs : **`bin/lan_bridge_host.ml(i)`** (appelant du script hôte : `up`,
  `down` qui rend `removed`, `ensure`, `release`, `is_usable` ; un seul bridge par hôte, donc
  un mémo et non une table) et la sous-commande **`check-privileges`** de
  `marionnet-lanbridge.sh` (la seule façon de savoir si le bloc (c) est en place : `status`
  ne traverse aucun `sudo`). Modifiés : `bin/privileges.ml(i)` — la mécanique de l'épisode 6
  devient un `ensure_block` paramétré, d'où **`ensure_lanbridge`** avec ses propres mots (il
  dit qu'il s'agit de reconfigurer l'adressage IPv4 de l'hôte) et son propre verdict mémoïsé ;
  `bin/global_options.ml(i)` — **`explicit_world_bridge_name`**, sur lequel se branchent la
  résolution du bridge **et** `check_bridge_existence_and_warning` ; `etc/marionnet.conf` — la
  ligne `MARIONNET_BRIDGE=br0` **commentée**, sans quoi l'automatique n'aurait jamais tourné.
  Renommé : `bin/world_bridge.ml` → **`bin/lan_bridge.ml`** (`git mv`), avec ses deux
  références (`gui_toolbar_COMPONENTS.ml`, `control_server.ml`) — **identité interne
  inchangée**. Le dialogue d'ajout porte l'avertissement de coupure de l'hôte (deux
  formulations selon que le mot de passe sera demandé ou non) et l'aide est réécrite : elle
  décrivait la préparation manuelle `brctl` d'un administrateur, c'est-à-dire exactement ce que
  l'épisode supprime.
  - **Preuves mesurées** : `dune build` rc 0 ; module **réellement compilé** (erreur volontaire
    → échec, retirée → rc 0) ; sonde `check-privileges` **sur le vrai système** →
    `privileged:false` avec le message de sudo, sans invite, et « Cannot find device » vérifié
    comme discriminant. **Run piloté avec un script hôte simulé** (nommant `docker0`, un bridge
    réel, pour que le tap s'attache pour de bon) : `check-privileges` **une** fois, `up
    --owner-pid <pid de Marionnet>` — jamais `$PPID` — une fois pour deux résolutions, tap
    `mtap<pid>-0` réellement asservi ; `stop` → **`down --owner-pid <pid>`** et tap retiré ;
    `start` de nouveau → un second `up` (mémo bien oublié après un retrait réel) ; `quit` → un
    seul `down`, aucun doublon d'`at_exit`, aucun résidu. **Run avec le vrai script** (le poste
    est en Wi-Fi) : `E_WIRELESS` reçu, renvoi vers le NAT bridge, repli sur le bridge configuré,
    composant démarré quand même, le journal disant tout — plus le chemin `Privileges` complet
    en session pilotée (refus du dialogue, verdict mémorisé, « not asking again »).
    **Surcharge** prouvée au passage : avec `MARIONNET_BRIDGE=br0` hérité de
    `/etc/marionnet/marionnet.conf`, le journal dit « attaching to the configured host bridge »
    et **le script n'est pas appelé du tout**. **Round-trip `.mar`** : label accentué intact,
    `world_bridge` dans `netmodel/network.json` et `states/defects.json`, `help` publiant
    toujours `world_bridge` dans ses `kinds`.
  - Dette assumée : **i18n** (les mots du LAN bridge, l'avertissement de coupure et les textes
    de `ensure_lanbridge` s'ajoutent aux chaînes des épisodes 1, 6 et 7a) → épisode 9.
  Prochain pas : **7c** (retrait de `MARIONNET_WORLD_BRIDGE_MODE`, de
  `Global_options.world_bridge_mode` — **plus aucun lecteur depuis cet épisode** — et du
  contrôle `check_bridge_existence_and_warning` si l'on juge qu'il a fait son temps).

- **2026-08-17 — épisode 7b bis** : *le chemin nominal, enfin joué sur une carte réelle de
  l'hôte* — et le défaut que seule une carte réelle pouvait montrer.
  - **Ce qui a rendu l'essai possible.** Le poste n'a pas de carte filaire (`wlp0s20f3` seule,
    donc `E_WIRELESS` à tous les épisodes précédents). Il a été relié au **partage de connexion
    USB d'un téléphone Android** (`enx022a19680b00`, pilote `rndis_host`, 192.168.95.184/24,
    passerelle 192.168.95.165). Le noyau la voit comme une carte ethernet : la garde
    `refuse_wireless` ne s'applique pas, et **tout ce qui touche l'hôte a donc tourné pour de
    vrai** — création de `mnlan0`, clonage de la MAC, migration de l'adresse *et* de la route
    par défaut, asservissement, puis restauration. Réserve honnête : un lien RNDIS n'est pas un
    câble vers un switch ; l'essai ne dit rien du comportement d'un vrai commutateur, et un
    rejeu sur un LAN filaire reste souhaitable.
  - **Ce qui est prouvé.** (a) `up` réel : `mnlan0` porte l'adresse et la route, la carte est
    `master mnlan0` en `forwarding`, et **l'hôte garde son Internet** (ping passerelle et
    9.9.9.9 à 0 %) ; `status` retrouve l'alias `marionnet-lanbridge:<pid>:enx022a19680b00`.
    (b) `down` : `mnlan0` disparaît, la carte retrouve adresse et route, ping vert.
    (c) **Chaîne OCaml complète** : Marionnet piloté par le canal, un composant *LAN bridge* →
    `Privileges.ensure_lanbridge` (bloc (c) installé, donc aucune fenêtre) → `Lan_bridge_host`
    → script → `mnlan0` avec `enx022a19680b00` **et** `mtap<pid>-0` comme ports.
    (d) **La promesse pédagogique, tenue pour la première fois** : une machine trixie câblée au
    bridge, adressée en `192.168.95.210/24`, résout l'ARP de la passerelle, pingue l'hôte, la
    passerelle et 9.9.9.9 à 0 % ; puis, **`dhcpcd` lancé dans l'invité, un bail réel du serveur
    DHCP du LAN** (192.168.95.170, 3599 s), `/etc/resolv.conf` rempli par lui, et
    `getent hosts deb.debian.org` qui répond. Vraies adresses, vrai DHCP, vrais voisins.
    (e) `quit` → ni `mnlan0` ni tap, `status` : `exists:false`.
  - **Le défaut trouvé, et pourquoi seule une carte réelle pouvait le montrer.** Sur un hôte
    géré par **NetworkManager**, le `down` laissait une **route par défaut surnuméraire de
    métrique 0**. Chronologie relevée à la milliseconde (`ip -ts monitor`) : notre `addr add`
    sur la carte (t), NM qui réapplique sa configuration 0,5 ms plus tard et repose **ses**
    routes `metric 100`, puis notre `route add` nu à t+11 ms — d'où deux routes par défaut, la
    nôtre l'emportant sur celle du système, et sur toutes les autres cartes de la machine. En
    netns (selftest de l'épisode 8) il n'y a ni gestionnaire réseau ni métrique : le défaut y
    est **invisible par construction**. Danger réel : au prochain changement de bail, la route
    de métrique 0, périmée, continue de gagner.
  - **Correctif (script hôte seul, zéro OCaml, zéro modification du sudoers).** La **métrique
    voyage avec la route** : `up` la lit sur la carte (`route_metric_of`) et la pose sur la
    route *et* sur l'adresse du bridge (`ip addr add … metric N`, qui fixe la métrique de la
    route de préfixe dérivée) ; `down` la relit **sur le bridge** — donc toujours aucun fichier
    d'état, l'information se lit sur le système, y compris après un crash. La restauration
    devient de surcroît **conditionnelle** (`addr_present`, `default_route_present`) : ce que le
    gestionnaire a déjà remis n'est pas remis une seconde fois. Repli conservé dans
    `restore_default_route` : si une règle sudoers plus stricte refusait l'argument `metric`,
    perdre la métrique est un défaut d'aspect, laisser l'hôte sans route par défaut serait une
    panne. Mesuré : les formes avec `metric` **sont déjà couvertes** par le bloc (c) tel qu'il
    est installé (un `*` de sudoers matche plusieurs mots, exactement comme pour `brd`), d'où
    aucune réinstallation à demander ; `print-privileged-commands` les publie désormais.
  - **Vérification du correctif** : trace `ip monitor` d'un cycle complet — la route par défaut
    du bridge porte `metric 100`, **aucune route par défaut nue n'est plus créée**, et l'état
    final n'a qu'une seule route par défaut ; rejoué ensuite par la chaîne OCaml (`start`,
    `quit`) avec le même résultat et aucun résidu d'interface.
  - **Limite résiduelle, documentée plutôt que masquée** : il reste une **route de préfixe**
    (`192.168.95.0/24`) en double, sans métrique. La trace montre qu'elle est l'œuvre de
    NetworkManager, qui repose l'adresse **sans** priorité de route (le noyau crée alors une
    route de métrique 0) avant d'ajouter la sienne en `metric 100`. Elle vise le même préfixe,
    par la même carte, avec la même source : aucun effet de routage, et elle meurt avec
    l'adresse. Remède immédiat si elle gêne : `nmcli device reapply <carte>` (vérifié : il
    nettoie sans mot de passe).
  - **Prérequis du jour, pour mémoire** : bloc (c) installé (`marionnet-sudoers.sh install
    --only --enable-lanbridge`, sha256 du bloc (a) inchangé) et `MARIONNET_BRIDGE=` posé dans
    `~/.marionnet/marionnet.conf` pour neutraliser le `br0` que `/etc/marionnet/marionnet.conf`
    porte encore.
  Prochain pas : inchangé — **7c**, puis l'épisode 9 (i18n ×12). Geste humain restant :
  rejouer `marionnet-lanbridge.sh selftest` (harnais netns hors règle sudoers, donc mot de
  passe) pour la non-régression du correctif, et, le jour où un vrai switch est là, refaire
  (a)-(e) sur un LAN filaire.

- **2026-08-17 — retouche des icônes badgées (7a.3.b bis)** : *l'étiquette ne doit pas cacher
  l'état*. Défaut d'usage constaté sur le dessin : le bandeau `NAT`/`LAN` était estampillé en
  bas **à droite** de la partie carrée, c'est-à-dire exactement sur le **petit rond rouge/vert**
  qui dit si le composant est éteint ou allumé — dans **toutes** les tailles, donc un bridge
  posé sur le dessin ne disait plus s'il tournait. Correctif d'une ligne dans
  `bin/images/make-bridge-icons.sh` (`-gravity NorthEast` → `NorthWest`), calage vertical et
  largeur du bandeau (62 % de la largeur) inchangés : posé à gauche il s'arrête vers 0,63·w,
  quand le rond occupe ~0,72·w à ~0,86·w. Le commentaire de `stamp` porte désormais **les deux**
  contraintes, une par axe (à gauche à cause du rond ; sur la partie carrée à cause du marqueur
  `pause` qui déborde vers le bas). Vérifié : script rejoué (36 PNG réécrits, les 18
  `ico.world_bridge.*` sources intactes), `--check` → « up to date » (l'idempotence tient),
  `git status` → exactement 36 PNG + le script, `dune build` rc 0 avec les images propagées
  dans `_build`, et contrôle visuel agrandi des deux jeux sur les 4 tailles ×
  (`on`/`off`/`pause`/palette/dialog) : le rond d'état est dégagé partout, le mot reste
  lisible jusqu'à 32 px. Palliatif toujours assumé en attendant l'épisode d'iconographie.
  Prochain pas : inchangé — **7c**, puis l'épisode 9.

- **2026-08-17 — épisode 7c** : *le mode disparaît, et le garde-fou change de camp*.
  - **Ce qui part.** `Global_options.world_bridge_mode` et sa variable
    `MARIONNET_WORLD_BRIDGE_MODE` (`bin/global_options.ml(i)`, déclaration de
    `bin/configuration.ml`). Née à l'épisode 3 comme sélecteur provisoire — le temps que la
    GUI en ait un — elle n'a plus **aucun lecteur** depuis que le choix est une **nature de
    composant** (épisode 7a.3.b) et que le LAN bridge se construit tout seul (7b). C'est donc
    du code mort qui documente un concept abandonné. Conséquence assumée : un `marionnet.conf`
    qui la nommerait encore fait avorter le démarrage (« Unexpected variable name ») ;
    exposition nulle, la variable est née dans ce chantier et n'a jamais été publiée
    (`etc/marionnet.conf` ne l'a jamais portée, et les deux `marionnet.conf` du poste ont été
    vérifiés avant le build). Au passage, le commentaire « This is temporary: more than one
    bridge will be usable... », posé à côté de `MARIONNET_BRIDGE`, est remplacé par ce que la
    variable veut dire aujourd'hui : une **surcharge**.
  - **Ce qui reste, contre le découpage du § 4.** La table des épisodes prévoyait de supprimer
    aussi `check_bridge_existence_and_warning`. Décision inverse, et voici pourquoi : depuis
    l'épisode 7b ce contrôle est **déjà** un no-op sauf si `MARIONNET_BRIDGE` est explicitement
    configuré. Ce qu'il reste donc à couvrir est le cas exactement inverse de celui qui le
    rendait gênant : quelqu'un a **surchargé** l'automatique en nommant un bridge, et ce bridge
    n'est pas sur la machine — le composant démarrerait et asservirait son tap à rien, **en
    silence**. Ce cas mérite un mot. Deux choses y ont vieilli, et sont corrigées :
    1. **le test** : `brctl showmacs` (un `fork` + une dépendance à `bridge-utils`, paquet qui
       n'est plus installé par défaut sur une Debian/Ubuntu moderne) devient la lecture pure de
       `/sys/class/net/<nom>/bridge`, répertoire qui existe **si et seulement si** l'interface
       est un bridge. L'ancien test répondait « pas de bridge » sur un hôte où le bridge était
       parfaitement là, dès lors que `brctl` manquait — un avertissement mensonger ;
    2. **le message** : il enseignait `sudo brctl addbr …`, c'est-à-dire précisément la
       préparation manuelle que ce chantier existe pour supprimer. Il dit maintenant, **dans
       cet ordre**, que nommer un bridge n'est plus qu'une surcharge et qu'il suffit de
       commenter (ou vider) la ligne pour que Marionnet construise et démonte le sien ; puis,
       pour qui tient à son propre bridge, les commandes `ip link` d'aujourd'hui. Le **titre**
       est laissé mot pour mot : il est déjà traduit ×12, le casser ne rapporterait rien.
  - **Preuves mesurées.** `dune build` rc 0, et **module réellement recompilé** (erreur
    volontaire dans `global_options.ml` → build en échec sur la bonne ligne, erreur retirée →
    rc 0). `grep -rIn WORLD_BRIDGE_MODE` : plus rien hors `docs/` et du pointeur `CLAUDE.md`.
    Prédicat sysfs discriminé en shell : `docker0` (bridge réel) → oui, `wlp0s20f3` (carte
    Wi-Fi, donc interface qui n'est pas un bridge) → non, nom inexistant → non. Puis **deux
    sessions pilotées** ouvrant le même `.mar` (un composant *LAN bridge* enregistré, chemin
    `state.ml` du contrôle) : avec `MARIONNET_BRIDGE=docker0`, ouverture propre et
    `notifications` **vide** ; avec `MARIONNET_BRIDGE=mnbr-nexistepas`, une notification
    `warning` portant le titre inchangé et le **nouveau** corps, ses cinq `%s` substitués (nom
    ×4 + fichier source) — l'arité est donc vérifiée sur pièce, ce qui compte pour l'épisode 9.
    Aucun résidu après `quit`, session graphique intacte.
  - **Deux observations de bord, hors périmètre.** (1) Un chemin de socket de contrôle **trop
    long** (> 108 octets, la limite de `sun_path`) fait démarrer Marionnet **sans canal**, sans
    rien dire sur la sortie standard — rencontré en montant l'essai, résolu en raccourcissant
    le chemin. (2) Quand la surcharge vient de l'**environnement** et non d'un fichier, le
    message renvoie quand même « le fichier `marionnet.conf` » (comportement d'origine de
    `make_understandable_source_of_world_bridge_configuration`, inchangé ici).
  - Dette inchangée : le nouveau corps rejoint les chaînes des épisodes 1, 6, 7a et 7b pour
    l'**épisode 9** (i18n ×12).
  Prochain pas : **épisode 9** (i18n ×12) — l'épisode 7 est complet.
