# Étude : élimination de marionnet-daemon

> Rapport d'étude — 2026-07-14. Étude préalable au chantier long éventuel
> « daemon-elimination ». Verdict : **chantier faisable, effort modéré, fortement
> recommandé** (§ 5). Le plan d'amorce (§ 6) est auto-suffisant : une session vierge
> peut ouvrir le chantier à partir de ce seul document (+ skill `chantier-long`).

## 1. Contexte et objectif

`marionnet-daemon` (`bin/marionnet_daemon.ml`, second exécutable du projet,
`marionnet-daemon.native`) est un **service root permanent** sur la machine hôte : il
tourne même quand Marionnet ne s'exécute pas. Cette décision d'architecture date de
2005-2007 : à l'époque, donner à une GUI non privilégiée la capacité de créer des
interfaces tuntap exigeait un intermédiaire root, et le motif « daemon système +
socket » était la solution canonique (avant polkit, avant les user namespaces,
avant systemd).

L'étude répond à trois questions :
1. Que fait **exactement** le daemon (au-delà de « créer des tuntap ») ? — § 2.
2. Peut-il être remplacé par un mécanisme **moins invasif** avec les outils Linux
   de 2026 (namespaces, capabilities, systemd, sudoers…) ? — § 4.
3. Si oui, comment amorcer le chantier ; si non, pourquoi. — § 5, § 6.

## 2. Inventaire exhaustif du daemon

### 2.1 Les ressources gérées : deux types de taps, rien d'autre

Le protocole (`bin/daemon_language.ml`) ne connaît que deux motifs de ressource :

| Motif | Usage | Commandes exécutées (root) |
|---|---|---|
| `AnyTap(uid, ip42)` | tap **eth42** (un par VM) : canal hôte↔invité (X11, relay) | `tunctl -u <uid> -t <tap> && ifconfig <tap> 172.23.0.254 netmask 255.255.255.255 up; route add <ip42> <tap>` (`marionnet_daemon.ml:124-133`) |
| `AnySocketTap(uid, bridge)` | tap **world_bridge** : raccord au bridge admin préexistant | `tunctl -u <uid> -t <tap> && ifconfig <tap> 0.0.0.0 promisc up && brctl addif <bridge> <tap>` (`marionnet_daemon.ml:136-146`) |

Destruction : `ifconfig down` (+ `brctl delif`) + `tunctl -d`, réessayée
obstinément dans un thread (`repeat_obstinately`, `marionnet_daemon.ml:148-193`).

Le mécanisme de « ressources globales » (`marionnet_daemon.ml:318-346`) est **vide**
(« well, none as of now ») : il n'a jamais servi. Il n'y a donc **aucune autre
fonction cachée** : le daemon est exclusivement un créateur/destructeur de taps,
plus la comptabilité ci-dessous.

### 2.2 Comptabilité clients et garbage collection

- Un client = une connexion GUI ; keep-alive `IAmAlive` toutes les 24 s
  (`inter_keepalive_interval = timeout/5`, `daemon_parameters.ml:31`) ; un client
  silencieux > 120 s voit **toutes ses ressources détruites** (`timeout_thread_thunk`,
  `marionnet_daemon.ml:422-442`). C'est le filet de sécurité contre les taps
  orphelins quand la GUI crashe. Nota : `tunctl` crée des taps *persistants* — sans
  ce GC ils survivraient indéfiniment.
- Contrôles d'appartenance : un client ne peut détruire que ses propres taps
  (`ownership`, `uid_consistency`), noms de taps contraints aux préfixes
  `tap`/`wbtap` + suffixe numérique, adresses contraintes au préfixe `172.23.`
  (`marionnet_daemon.ml:487-493`, `daemon_language.ml:203-215`).

### 2.3 Transport et surface d'attaque

- Socket Unix `/tmp/my-marionnet-daemon-socket` (configurable
  `MARIONNET_SOCKET_NAME`, `daemon_parameters.ml:33-35`), messages fixes de 128
  octets, opcodes à 1 caractère.
- La socket est créée en mode **0666** (`Unix.chmod socket_name 438`,
  `marionnet_daemon.ml:579`) : **tout utilisateur local** peut demander à root la
  création de taps et leur raccord au bridge. La validation défensive de
  `daemon_language.ml` (seul endroit du code traitant une entrée non fiable,
  style `Either`) limite les dégâts, mais la surface demeure : c'est un service
  root permanent exposé à tous les comptes locaux.

### 2.4 Lancement, install, mode dégradé

- Lancement historique : script SysV `useful-scripts/etc_init.d_marionnet-daemon`
  (`start` = simple `marionnet-daemon.byte &`, `stop` = `killall`).
- Côté GUI : connexion au démarrage (`marionnet.ml:200-201`) ; en cas d'échec,
  **mode dégradé déjà prévu et fonctionnel** (`Daemon_client.disable_daemon_support`,
  warning « Marionnet will work, but some features (graphics on virtual machines
  and host sockets) won't be available »). L'architecture tolère donc déjà
  l'absence du daemon — point favorable à une transition incrémentale.

### 2.5 Les trois sites clients

1. **`bin/simulation_level.ml:874`** (`uml_process`) : demande un `AnyTap` par
   machine/routeur ; le nom obtenu est passé à UML :
   `eth42=tuntap,<tap>,<mac>,172.23.0.254` (`:897`). Destruction dans
   `gracefully_terminate` (`:1141`) et `terminate` (`:1199`).
2. **`bin/world_bridge.ml:395-418`** : demande un `AnySocketTap` sur le bridge
   `MARIONNET_BRIDGE` ; le tap est ensuite ouvert par un
   **`vde_switch … -tap <tap>`** lancé par la GUI (processus *utilisateur*,
   `simulation_level.ml:389`) — le daemon ne fait que créer/raccorder le tap.
3. **`bin/marionnet.ml:200`** : initialisation + thread keep-alive.

### 2.6 Le canal eth42 est bidirectionnel

- Invité→hôte : X11 — l'invité se connecte à `172.23.0.254:600x`, où `bin/x.ml`
  fait écouter un relais socat vers le socket Unix du serveur X
  (`x.ml:250-300`) ; les vieilles images câblent `DISPLAY=172.23.0.254:0`
  (`uml/guest/marionnet-relay:291`).
- **Hôte→invité** : terminaux quagga des routeurs — la GUI ouvre des
  `telnet <ip42> <port zebra/ospfd/…>` (`bin/router.ml:1376`,
  `show_quagga_terminal`) ; d'où la `route add <ip42> <tap>` posée par le daemon.

Toute solution de remplacement doit préserver les **deux** sens (contrainte
utilisateur, § 3).

### 2.7 Hors périmètre daemon (déjà sans privilège)

- `world_gateway` = `slirpvde` (NAT userspace, `simulation_level.ml:490-521`).
- Toutes les autres interfaces des VMs = sockets Unix vde (hublets).
- UML lui-même s'attache au tap eth42 **sans privilège** : le tap est persistant
  et owned par l'utilisateur (`tunctl -u`), et le kernel autorise `TUNSETIFF` sur
  un tap existant owned sans `CAP_NET_ADMIN` (§ 4.0).

Le daemon est donc l'**unique** point root de toute l'architecture d'exécution.

### 2.8 Obsolescence : le daemon est déjà à réécrire

Les commandes invoquées — `tunctl` (uml-utilities), `ifconfig`/`route`
(net-tools), `brctl` (bridge-utils) — sont dépréciées ou absentes par défaut des
distributions récentes au profit d'iproute2 (`ip tuntap`, `ip addr`, `ip route`,
`ip link set … master`). Indépendamment de toute considération d'architecture,
**le code privilégié du daemon doit être réécrit** pour fonctionner sur un hôte
2026. Autant en profiter pour éliminer le daemon lui-même.

## 3. Contraintes retenues (cadrage utilisateur, 2026-07-14)

1. **Poste personnel prioritaire** : l'installateur dispose de sudo ; la salle de
   TP multi-utilisateurs est secondaire (mais documentée, § 5.3).
2. **Bidirectionnalité eth42 à préserver** : X11 invité→hôte **et** telnet
   quagga hôte→invité — élimine les solutions purement NAT (slirp/passt).
3. **Vieilles images invitées à préserver** : le contrat réseau actuel
   (tap dans le ns racine, `172.23.0.254/32`, route host-specific vers `ip42`,
   `DISPLAY=172.23.0.254`) doit être reproduit à l'identique.

## 4. Alternatives évaluées

### 4.0 Faits kernel/distro établis (vérifiés juillet 2026)

- **Créer** un tun/tap exige `CAP_NET_ADMIN` *dans le user namespace propriétaire
  du network namespace* : `tun.c` v6.12, `tun_set_iff` :
  `if (!ns_capable(net->user_ns, CAP_NET_ADMIN)) return -EPERM;`.
- **S'attacher** à un tap *persistant existant* dont on est owner/group n'exige
  **aucun privilège** (`tun_not_capable` : test owner/group avant `ns_capable`).
  C'est ce qui permet déjà à UML et à `vde_switch -tap` de fonctionner en
  utilisateur. Réf. : [doc kernel TUN/TAP](https://docs.kernel.org/networking/tuntap.html),
  `drivers/net/tun.c` v6.12.
- Dans un **netns créé via un userns non privilégié** (`unshare -Urn`),
  l'utilisateur détient `CAP_NET_ADMIN` sur ce netns : taps, adresses et routes
  s'y créent librement. Mécanisme éprouvé industriellement (podman rootless :
  [slirp4netns](https://github.com/rootless-containers/slirp4netns), pasta).
- **Restriction Ubuntu** : depuis 23.10, et par défaut sur 24.04 LTS, AppArmor
  bloque les userns non privilégiés (`kernel.apparmor_restrict_unprivileged_userns=1`)
  sauf pour les binaires dotés d'un profil contenant `userns,`. Un lanceur
  Marionnet à base d'`unshare -Urn` devrait donc livrer un profil AppArmor
  (comme le font Chrome, Discord…). Réfs :
  [annonce Ubuntu 23.10](https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces),
  [notes de version 24.04](https://documentation.ubuntu.com/release-notes/24.04/).
- **Transports UML** (doc kernel 6.x) : le transport `tuntap` attend une
  interface préexistante persistante owned (le mode actuel) ; les transports
  vector (`raw`, `hybrid`) exigent `CAP_NET_RAW` ou un veth — pas plus simples
  pour notre cas. Réf. :
  [UML HowTo v2](https://www.kernel.org/doc/html/v6.6/virt/uml/user_mode_linux_howto_v2.html).
- **Preuve de concept interne au dépôt** : `uml/pupisto.tester/pupisto.tester.sh`
  (options `-A`/`-X`/`-S`) reproduit déjà tout le travail du daemon — création
  tap + adresse + route, canal X11 ghostifié, ssh hôte→invité — via une règle
  sudoers NOPASSWD *scoped* (`/etc/sudoers.d/marionnet-tester`, commandes `ip`
  limitées au motif `mnt-tap*`) et iproute2. Fonctionne en production de test
  depuis le chantier kernel-rootfs.

### 4.1 Tableau comparatif

| # | Solution | Privilège résiduel | Bidir eth42 | Vieilles images | GC orphelins | Complexité | Verdict |
|---|---|---|---|---|---|---|---|
| A | **sudoers scoped + iproute2** (pattern pupisto.tester `-A`) | règle NOPASSWD étroite, à l'usage | oui | oui (contrat identique) | nettoyage au lancement + à la sortie | **faible** | **retenue (étape 1)** |
| B | **netns de session** (`unshare -Urn`) | **aucun** | oui | oui (contrat identique *dans* le ns) | **automatique** (mort du ns) | moyenne-haute (AppArmor Ubuntu, nsenter, world_bridge à part) | cible étape 2 (optionnelle) |
| C | helper `setcap cap_net_admin` | binaire privilégié à maintenir | oui | oui | idem A | moyenne (file caps fragiles à l'install) | dominée par A |
| D | taps persistants **pré-provisionnés** par l'admin | config admin one-shot, **zéro runtime** | n/a (world_bridge) | oui | n/a (persistants voulus) | faible | **variante world_bridge** |
| E | systemd socket-activation du daemon actuel | daemon root conservé (à la demande) | oui | oui | inchangé | faible | n'atteint pas l'objectif ; repli minimal |
| F | polkit + service D-Bus | service privilégié conservé | oui | oui | à refaire | haute | écartée (E en plus lourd) |
| G | slirp/passt (NAT userspace) | aucun | **non** (hôte→invité impossible sans redirections fragiles) | non (contrat changé) | automatique | moyenne | **écartée** (contrainte 2) |

Détails des solutions retenues :

**A — sudoers scoped.** Le paquet/`make install` dépose
`/etc/sudoers.d/marionnet` autorisant, pour le groupe `marionnet` (ou l'user
installant), exactement : `ip tuntap add dev mtap* mode tap user <u>`,
`ip tuntap del dev mtap* mode tap`, `ip addr add * dev mtap*`,
`ip route add * dev mtap*`, `ip link set mtap* *`, `ip link del mtap*`
(le motif exact est à figer au chantier ; `pupisto.tester.sh:370-380` fournit le
modèle éprouvé). La GUI exécute `sudo -n ip …` là où elle parlait au daemon.
Sécurité : périmètre *plus étroit* que la socket 0666 actuelle (qui offre les
mêmes créations de taps à tous les comptes locaux, sans sudoers du tout).
GC : au lancement, purger les `mtap*` orphelins de l'utilisateur ; à la sortie,
`at_exit` + le nettoyage existant des `terminate`.

**B — netns de session (cible ultérieure).** Un « holder » `unshare -Urn` créé
au lancement ; les UML, les socat de `x.ml` et les telnet quagga y sont lancés
(`nsenter --user --net`) ; les taps eth42 s'y créent sans aucun privilège et
meurent avec le ns (GC parfait). Les sockets Unix (hublets vde, X11, mconsole)
traversent les namespaces — seul le réseau IP est cloisonné. Contraintes qui la
relèguent en étape 2 : profil AppArmor à livrer pour Ubuntu ≥ 23.10 ; le
`vde_switch -tap` du world_bridge doit rester dans le ns racine ; cas X-en-TCP
(ssh -X, cas 3/4 de `x.ml`) à traiter ; validation UML-dans-netns à faire
(facile avec pupisto.tester). Forte synergie avec le chantier kernel-rootfs
(le relay Debian 13 utilise déjà un netns côté invité, `host_display_ip` est
déjà paramétrable).

**D — variante world_bridge.** L'admin qui configure `MARIONNET_BRIDGE` (action
déjà manuelle et documentée) peut, dans le même geste, pré-créer N taps
persistants attachés au bridge, owned par le groupe `marionnet`
(`ip tuntap add … group marionnet` + `ip link set … master <bridge>`) :
`vde_switch -tap` s'y attache ensuite **sans aucun privilège runtime** (§ 4.0).
Élimine même le sudo pour ce composant ; limite : nombre de world_bridges
simultanés borné par N (acceptable : composant rare ; N=4 proposé).

## 5. Verdict et recommandation

### 5.1 Verdict

**Le daemon est éliminable, et son élimination est recommandée.** Aucune de ses
fonctions (§ 2) n'exige un service permanent : la création de taps se délègue à
sudo (A) ou à un namespace (B), le GC des orphelins se fait mieux sans lui
(B : automatique ; A : purge au lancement), et sa disparition supprime l'unique
composant root du projet, sa socket 0666, son script SysV, son protocole ad hoc
(~1200 lignes : `marionnet_daemon.ml`, `daemon_language.ml`, `daemon_client.ml`,
`daemon_parameters.ml`) et la dépendance aux outils morts (tunctl/net-tools/
bridge-utils). Le mode dégradé existant (§ 2.4) garantit une transition sûre.

### 5.2 Architecture cible (étape 1 = solution A + variante D)

- Nouveau module `bin/tap_provider.ml` (~150 lignes) : mêmes deux primitives que
  le daemon (`make_eth42_tap ~uid ~ip42`, `make_bridge_tap ~bridge` +
  destructions), implémentées par `sudo -n ip …`, avec le même contrat réseau
  exact (nom `mtapN`, `172.23.0.254/32`, route host-specific, promisc+master
  pour le bridge). Erreur sudo → même chemin que `disable_daemon_support`
  aujourd'hui (mode dégradé, dialogue explicatif).
- Les 3 sites clients (§ 2.5) basculent de `Daemon_client.ask_the_server` vers
  `Tap_provider`.
- `make install` dépose la règle sudoers (et le README d'admin pour la
  variante D du world_bridge).
- Purge des 4 fichiers daemon, du script SysV, de `MARIONNET_SOCKET_NAME`,
  du stanza daemon de `bin/dune` (et de la lib `marionnet_common` si elle ne
  sert plus qu'à lui — à vérifier au chantier).

### 5.3 Note salle de TP (contexte secondaire)

La règle sudoers par groupe reste **moins** exposée que l'actuelle socket 0666
(qui donne déjà ces créations de taps à *tous* les comptes, sans opt-in admin).
Pour un campus voulant zéro sudo : la variante D couvre le world_bridge, et
l'étape 2 (netns) couvre eth42 — c'est le chemin « TP » naturel, à mentionner
dans la doc d'admin sans bloquer l'étape 1.

### 5.4 Risques principaux

| Risque | Gravité | Mitigation |
|---|---|---|
| Motif sudoers trop large/trop étroit (injection via arguments `*`) | moyenne | reprendre le motif éprouvé de pupisto.tester ; revue sécurité dédiée ; noms de taps générés (jamais saisis) |
| Vieille image qui dépend d'un détail du contrat (netmask /32, ordre route) | faible | reproduire les commandes à l'identique (seule la syntaxe iproute2 change) ; test avec une vieille image au chantier |
| Poste sans sudo installé / politique sudo verrouillée | faible | mode dégradé existant + message explicite ; documenter la variante D |
| Régression GC (taps orphelins après crash GUI) | faible | purge au lancement (idempotente) ; un tap orphelin est inerte et invisible pour l'utilisateur |

## 6. Plan d'amorce du chantier long « daemon-elimination »

Officialisation : skill `chantier-long` — mémoire projet `marionnet-daemon-elimination`,
tag de commits `marionnet-daemon-elimination`, ce document comme doc de chantier
(y ajouter le journal horodaté).

Épisodes proposés :

1. **`tap_provider` + sudoers + bascule eth42** : créer `bin/tap_provider.ml`
   (contrat § 5.2) ; règle sudoers modèle dans `etc/` + install ; basculer
   `simulation_level.ml:874/:1141/:1199`. Critère : lancer une machine + une
   vieille image, X11 invité OK, telnet quagga d'un routeur OK, taps détruits à
   l'arrêt. Témoin : `pupisto.tester.sh -A -X` (contrat identique).
2. **world_bridge** : basculer `world_bridge.ml:395-418` (création sudo) +
   documenter la variante D (taps pré-provisionnés) dans la doc d'admin.
   Critère : world_bridge fonctionnel sur un bridge de test.
3. **Purge** : supprimer les 4 fichiers daemon, le stanza `bin/dune`, le script
   SysV, `MARIONNET_SOCKET_NAME` (etc/marionnet.conf), les références docs
   (`ARCHITECTURE.md` § 6, CLAUDE.md ×2) ; vérifier le devenir de
   `marionnet_common`. Critère : `dune build` rc=0, grep `daemon` résiduel nul
   (hors historique), GUI complète OK sans daemon lancé.
4. *(optionnel, plus tard)* **netns de session** : POC `pupisto.tester` UML-dans-netns,
   puis lanceur + profil AppArmor. Peut n'être ouvert que si le besoin « zéro
   sudo » (TP) se concrétise.

Points de vigilance transverses : messages de commit en anglais (règle dépôt) ;
ne pas toucher `.bzr/` ; les 5 modules communs GUI/daemon de `marionnet_common`
(piège n° 2 du CLAUDE.md) — la purge de l'épisode 3 réévalue cette partition.

## 7. Sources

- [Universal TUN/TAP device driver — doc kernel](https://docs.kernel.org/networking/tuntap.html) ;
  `drivers/net/tun.c` v6.12 (`tun_set_iff`, `tun_not_capable`).
- [UML HowTo v2 — doc kernel 6.x](https://www.kernel.org/doc/html/v6.6/virt/uml/user_mode_linux_howto_v2.html)
  (transports tap/raw/hybrid et leurs privilèges).
- [Ubuntu 23.10 : restricted unprivileged user namespaces](https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces) ;
  [Ubuntu 24.04 LTS release notes](https://documentation.ubuntu.com/release-notes/24.04/)
  (activation par défaut ; profils AppArmor `userns,`).
- [slirp4netns](https://github.com/rootless-containers/slirp4netns) (tap dans un
  netns non privilégié — mécanisme podman rootless).
- Interne : `uml/pupisto.tester/pupisto.tester.sh` (`-A`/`-X`/`-S`, sudoers scoped
  + iproute2) ; `docs/ARCHITECTURE.md` § 6 ; audit `docs/audit-marionnet-20260706.md`.

## Journal d'avancement

- **2026-07-14 — épisode 0** : étude de faisabilité (inventaire du daemon, vérifications
  kernel/distro, cadrage utilisateur, verdict FAISABLE/recommandé) et officialisation du
  chantier `marionnet-daemon-elimination`. Aucun code touché ; prochain pas = épisode 1
  (`tap_provider` + sudoers + bascule eth42, § 6).
