# Chantier : modernisation-world-bridge

> Chantier long, ouvert le 2026-07-18. Cible : le composant **`world_bridge`**
> (`bin/world_bridge.ml`, dernier bouton de la palette gauche, icône planète), qui
> raccorde le réseau virtuel au **vrai réseau L2 de l'hôte**. Deux axes : (1) éliminer
> sa **barrière de mise en œuvre** (config hôte manuelle hors GUI), sur le modèle du
> chantier `daemon-elimination` ; (2) un **travail GUI** rendant le composant
> compréhensible pour enseignants et étudiants. Skill de pilotage : `chantier-long`.

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

### 2.3 Conventions établies par le POC (à reprendre telles quelles en OCaml)

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
- *(épisodes ultérieurs, après l'axe A)* : sélecteur de **mode** dans le dialogue (NAT auto /
  L2 réel / bridge manuel) ; libellé de palette plus parlant ; éventuel regroupement visuel
  des deux composants « accès au monde ».

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
4. **ép. 3** *(à venir)* — *câblage OCaml* : création/destruction du bridge NAT et de ses
   règles depuis Marionnet (le module naturel est `tap_provider.ml`, qui tient déjà la
   discipline sudo + `owner_pid` + GC), extension du motif de `bin/scripts/marionnet-sudoers.sh`
   (§ 2.1 bis), et **choix du mode** dans le dialogue de `world_bridge` (NAT auto / bridge
   manuel), avec la sémantique NAT annoncée en clair. L'attachement du tap n'est pas à écrire :
   il fonctionne déjà.
5. **ép. 4+** *(à venir)* — option B (L2 réel automatique, garde-fous et rollback) en mode
   expert ; puis **refresh i18n consolidé ×12**, qui soldera aussi la dette des trois chaînes
   de l'épisode 1 (§ 5).

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
