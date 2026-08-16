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
   composant.
4. **Le LAN bridge devient automatique lui aussi**, par un script hôte symétrique
   **`bin/scripts/marionnet-lanbridge.sh`** : détection de la carte qui porte la route par
   défaut, asservissement au bridge, migration de l'adresse et des routes, rollback
   transactionnel. C'est l'**option B** du § 2.1, promue de « peut-être un jour » à
   composant de plein droit. Son risque ne disparaît pas pour autant : le dialogue
   d'ajout/modification **avertit explicitement d'une coupure possible de l'hôte**, et
   l'asservissement d'une carte Wi-Fi reste impossible (l'AP refuse plusieurs MAC).
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
9. **ép. 8** *(à venir)* — **`bin/scripts/marionnet-lanbridge.sh`** : bridge `mnlan<pid>`,
   détection de la carte de route par défaut, asservissement, migration de l'adresse et des
   routes, rollback transactionnel et `selftest`, sur le patron exact de
   `marionnet-natbridge.sh` (contrat JSON, `--fail-after`, tag de commentaire). Plus
   l'avertissement de coupure hôte, côté GUI.
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
