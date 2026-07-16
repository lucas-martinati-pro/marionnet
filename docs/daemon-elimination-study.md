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

Épisodes (découpage révisé à l'épisode 1 : la brique et la bascule, que l'étude
fusionnait, sont séparées — la brique se prouve seule, la bascule exige une image
invitée et un run GUI ; un épisode = un critère vérifiable) :

1. ✅ **`tap_provider` + sudoers + preuve** (fait, § 8) : `bin/tap_provider.ml(i)`
   (contrat § 5.2), règle sudoers (`bin/scripts/marionnet-sudoers.sh`) + install,
   driver de preuve `bin/tap_provider_test.ml`. Critère (atteint) : contrat réseau
   prouvé contre le noyau, sans GUI ni image invitée.
2. ✅ **Bascule eth42** (fait, § 9) : `simulation_level.ml` passe de
   `Daemon_client.ask_the_server` à `Tap_provider` ; `purge_orphan_taps` au
   démarrage ; mode dégradé raccroché à `is_usable` (dialogue + commande à
   copier dans un terminal). Critère (partiellement acté, § 9) : machine +
   vieille image, X11 invité OK, taps détruits à l'arrêt ; telnet quagga non
   acté (test perturbé, § 9).
3. ✅ **world_bridge** (fait, § 10) : basculer `world_bridge.ml:395-418` (création sudo) +
   documenter la variante D (taps pré-provisionnés) et la variante groupe
   `marionnet` (salle de TP, § 5.3) dans la doc d'admin. Critère (atteint) : world_bridge
   fonctionnel sur un bridge de test.
4. ✅ **Purge** (fait, § 11) : supprimer les 4 fichiers daemon, le stanza `bin/dune`, le script
   SysV, `MARIONNET_SOCKET_NAME` (etc/marionnet.conf), les références docs
   (`ARCHITECTURE.md` § 6, CLAUDE.md ×2) ; vérifier le devenir de
   `marionnet_common`. Critère : `dune build` rc=0, grep `daemon` résiduel nul
   (hors historique), GUI complète OK sans daemon lancé.
5. *(optionnel, plus tard)* **netns de session** : POC `pupisto.tester` UML-dans-netns,
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

## 8. Épisode 1 — ce qui a été construit, et les écarts à l'étude

Livré : `bin/tap_provider.ml(i)` (les primitives eth42), `bin/scripts/marionnet-sudoers.sh`
(source **unique** du texte de la règle, partagée par `make install-final-as-root` et le
runtime), `bin/tap_provider_test.ml` (driver de preuve), stanzas `bin/dune`.
**Rien ne l'appelle encore** : le daemon reste en place et fonctionnel (bascule = ép. 2).

Écarts assumés vs le § 5.2 / § 6 :

| Étude | Réalisé | Pourquoi |
|---|---|---|
| tap nommé `mtapN` | `mtap<pid>-<seq>` | le pid embarqué rend le GC **exact** : `purge_orphan_taps` ne détruit que les taps d'un pid **mort**, donc jamais ceux d'une autre instance vivante. C'est le remplaçant du keep-alive/timeout du daemon |
| règle sudoers dans `etc/` | script dans `bin/scripts/` | rejoint le mécanisme d'install déjà en place (`marionnet_telnet.sh` : glob dune → `share/` → hard-link dans `$PREFIX/bin/`), donc joignable par nom nu depuis l'OCaml |
| motif sudoers de `pupisto.tester` (`ip addr add * dev …`) | adresse et réseau **littéraux** (`172.23.0.254/32`, `172.23.*`) | resserre le risque « injection par arguments » du § 5.4 ; seul `link set mtap* *` garde un `*` libre (requis par `up`, et par `promisc`/`master` à l'ép. 3) |
| brique **et** bascule dans un épisode | séparées (ép. 1 / ép. 2) | la brique se prouve seule contre le noyau ; la bascule exige une image invitée + un run GUI |

Deux pièges **établis expérimentalement** (2026-07-14), à ne pas re-découvrir :

1. **`sudo -n -l <commande>` ne teste PAS ce qu'on croit.** Il répond « cette commande
   est-elle autorisée par *une* règle », pas « puis-je l'exécuter *sans mot de passe* ».
   Sur un poste ordinaire (`%sudo ALL=(ALL:ALL) ALL`) il répond **oui, règle absente ou
   non**, et sortait exactement la même chose avant et après l'installation — faux positif
   structurel. Le probe retenu : `sudo -n ip tuntap del dev mtapprobe mode tap`, qui est
   un **no-op réussi** (rc=0, aucun device créé) quand la règle est là, et un refus sudo
   sinon. C'est la vraie question, sans effet de bord ni dépendance à la locale.
2. **Le fichier `/etc/sudoers.d/marionnet` est 0440 root:root** (comme tout fichier
   sudoers) : l'utilisateur ne peut pas le lire. Toute vérification par lecture/`diff`
   (la sous-commande `check` du script) est donc réservée à **root** ; le runtime, lui,
   utilise le probe ci-dessus.

Reste à traiter à l'ép. 2 : `ensure_sudoers_rule` hérite des canaux standard, donc `sudo`
ne peut demander le mot de passe **que depuis un terminal** — la GUI devra passer par un
terminal (`Initialization.marionnet_terminal`), `pkexec` ou un askpass, avec le dialogue
explicatif du mode dégradé.

## 9. Épisode 2 — la bascule eth42, et l'état de sa validation

Livré (décisions actées au grill du 2026-07-15) :

- `bin/simulation_level.ml` : la création eth42 appelle
  `Tap_provider.make_eth42_tap ~uid ~ip42` (échec → log + repli `"wrong-tap-name"` :
  la VM démarre sans eth42, contrat dégradé actuel à l'identique) ; les deux
  destructions (`gracefully_terminate`, `terminate`) appellent
  `Tap_provider.destroy_tap`. Piège de code : l'`open Daemon_language` du fichier
  définit son propre constructeur `Error` → les motifs `result` sont qualifiés
  `Stdlib.Ok`/`Stdlib.Error` (sinon warning 42).
- `bin/marionnet.ml` : l'échec de connexion au daemon est rétrogradé en log (plus
  de dialogue au démarrage — le daemon ne sert plus qu'au world_bridge jusqu'à
  l'ép. 3, et `ask_the_server` garde son propre dialogue d'erreur à l'usage) ;
  nouveau bloc au démarrage : `Tap_provider.is_usable` → `purge_orphan_taps`
  (compte loggé), sinon dialogue expliquant la commande
  `marionnet-sudoers.sh install` à lancer dans un terminal (ni pkexec ni terminal
  lancé par la GUI ; `ensure_sudoers_rule` reste sans appelant GUI — YAGNI).
- i18n : les nouvelles chaînes passent par `s_`/`f_` mais le refresh POT/PO des
  12 langues est **différé à l'ép. 4** (purge), qui supprimera de toute façon les
  msgid du daemon — un seul refresh gettext pour tout le chantier.
- `bin/dune` : rien à changer (`marionnet_tap` déjà linkée par `marionnet.native`).

Validation (2026-07-15/16, règle sudoers du poste de l'auteur) : `dune build` et
`dune test` rc=0 ; `grep Daemon_client bin/simulation_level.ml` vide ; run GUI —
**X11 invité OK, taps `mtap<pid>-*` détruits à l'arrêt OK** ; telnet quagga **non
acté** : le test a été perturbé par un problème orthogonal, le couple ancien
`linux-3.2.64-ghost` + debian-wheezy ne boote plus sur un hôte moderne
(6.8.0-134-generic) — `wait_stub_done : failed to wait for SIGTRAP` (logs :
`uml/kernel/linux-3.2.64-ghost.with-debian-wheeze.*.log`). Jugé suffisant par
l'auteur. Ce problème ouvre deux chantiers potentiels à étudier à part :
**retro-compatibilite-kernels-images** (faire rebooter les vieux couples sur hôte
moderne) et **lancement-kernels-images-modernes** (lancer les couples récents,
dont la ligne de commande UML diffère) — recoupe le chantier kernel-rootfs.

## 10. Épisode 3 — la bascule world_bridge

Livré (2026-07-16) :

- `bin/tap_provider.ml(i)` : nouvelle primitive `make_bridge_tap ~uid ~bridge`, calquée
  sur `make_eth42_tap` — contrat du daemon (`AnySocketTap`) à l'identique en iproute2 :
  `tuntap add` + `link set promisc on` + `up` + `link set … master <bridge>` (bridge
  quoté : entrée de config). Rollback en cas d'échec ; le nommage `mtap<pid>-<seq>`
  partagé fait que `destroy_tap` et `purge_orphan_taps` couvrent les bridge taps sans
  code nouveau (`ip link del` détache du bridge implicitement). **Règle sudoers
  inchangée** : le `*` libre de `link set mtap* *` couvrait `promisc`/`master` (prévu
  à l'ép. 1).
- `bin/world_bridge.ml` : `make_world_bridge_tap` → `Tap_provider.make_bridge_tap`
  (échec sudo → log + `None`, repli identique au refus daemon) ; `destroy_world_bridge_tap`
  → `Tap_provider.destroy_tap` (le `try/with` disparaît : destruction best-effort qui ne
  lève pas) ; l'`open Daemon_language` supprimé. `marionnet.ml` intouché (l'init daemon
  vestigial part à l'ép. 4). `bin/dune` : rien à changer.
- `bin/tap_provider_test.ml` : mode `--live-bridge=NAME` (bridge **préexistant** exigé :
  sa création est le geste de l'admin, hors règle scoped) — checks promisc/up/master,
  destruction, bridge intact.
- Doc admin **nouvelle** : `docs/admin-taps-and-bridge.md` (règle sudoers, création du
  bridge `MARIONNET_BRIDGE`, règle de groupe pour salle de TP, variante D documentée
  **non câblée** — décision grill : YAGNI, la GUI ne sait pas découvrir les taps
  pré-provisionnés ; à câbler si le besoin TP se concrétise).

Validation (2026-07-16) : `dune build` et `dune test` rc=0 ; `grep Daemon` sur
`world_bridge.ml` vide ; preuve contre le noyau
(`dune exec bin/tap_provider_test.exe -- --live-bridge=mnbrtest`, bridge de test jetable) :
tap créé promisc/up/master, détruit proprement, bridge intact — 0 FAIL. Pas de run GUI
(décision grill : driver seul, comme critère de l'épisode). **Le daemon n'a plus aucun
client** : la GUI ne lui parle plus (il ne reste que la connexion vestigiale au démarrage,
rétrogradée en log à l'ép. 2, à purger à l'ép. 4).

## 11. Épisode 4 — la purge

Livré (2026-07-16, décisions au grill : périmètre **runtime seul** — les vestiges
`RPMS/marionnet-common.spec`, `doc-src/documentation.texi`,
`useful-scripts/{marionnet_from_scratch,make_marionnet_bytecode_revno}` et
`Makefile.d/{Makefile.local,marionnet.odocl}` ne sont pas touchés, ils sont déjà périmés
pour d'autres raisons) :

- **Supprimés** : `bin/{marionnet_daemon,daemon_language,daemon_client,daemon_parameters}.ml`
  (~1200 lignes), `useful-scripts/etc_init.d_marionnet-daemon` (script SysV), le stanza
  `marionnet-daemon.native` de `bin/dune`, le bloc d'init daemon de `marionnet.ml`,
  `MARIONNET_SOCKET_NAME` (`etc/marionnet.conf` + `bin/share/marionnet.conf` + la liste de
  `configuration.ml`), `marionnet-daemon.native` de `EXECUTABLES` (Makefile).
- **`marionnet_common` → `marionnet_base`** (décision grill : renommage, « common » signifiait
  « commun GUI/daemon ») : réduite à `marionnet_log configuration meta`, requise car
  `tap_provider.ml` (lib `marionnet_tap`) utilise `Marionnet_log` et dune interdit un module
  dans deux stanzas d'un dossier.
- Piège découvert : l'`open Daemon_language` de `simulation_level.ml` fournissait aussi les
  alias `StringExtra`/`UnixExtra`/`Ipv4` (définis en tête de `daemon_language.ml`) — ajoutés
  au bloc d'alias de `simulation_level.ml` (convention du dépôt), qualification
  `Stdlib.Ok/Error` conservée (toujours valide), commentaire devenu faux supprimé.
- **Refresh gettext unique du chantier** (différé depuis l'ép. 2) : POT régénéré
  (358 → **356** msgid : −4 daemon, +2 dialogue sudoers), `msgmerge` sur les 12 langues,
  les 2 nouvelles msgid traduites ×12 par compendium (méthode du chantier i18n ; terminologie
  calibrée sur les anciennes entrées daemon de chaque langue), obsolètes `#~` purgés.
  Vérifs : `msgfmt -c` ×12 silencieux, 12×**356/356** traduits, aucun msgstr préexistant
  modifié, 12 `.mo` reconstruits par dune.
- Docs vivantes : `ARCHITECTURE.md` § 6 réécrit (Tap_provider) + § 2 corrigé (il décrivait
  encore le pré-épisode-5 de finitions), CLAUDE.md racine (table, piège n° 2, chantier),
  `bin/CLAUDE.md`, `bin/CLAUDE-file-overview.md` (section « Privilèges (taps) »).

Validation (2026-07-16) : `dune build` et `dune test` rc=0 ; grep résiduel nul en références
de code (`Daemon_*`, binaire, socket) — ne restent que commentaires historiques (contrat du
daemon documenté dans `tap_provider.ml(i)`, mentions du chantier) et vestiges hors périmètre.
Run GUI de l'auteur (`marionnet.native -d`, sans daemon lancé) : d'abord avec le binaire
installé du 2026-07-15 (état ép. 3), puis — après réinstallation testing — avec le **binaire
post-purge** (révision 642, built 2026-07-16) : démarrage et fermeture propres,
`daemon_client` plus chargé, le bloc « establish connection with daemon » disparu (la
séquence passe des treeviews directement au probe Tap_provider), probe **silencieux =
nominal** (le log de purge n'est émis que si n > 0 orphelin ; règle sudoers en place,
0 orphelin). Critère « GUI complète OK sans daemon » : **acté**.

## 12. Épisode 5 — étude du netns de session (POC léger, 2026-07-16)

L'épisode 5 (§ 6, optionnel) vise le « zéro sudo » : cloisonner le réseau IP de la session
Marionnet dans un **network namespace** où les taps eth42 se créent sans aucun privilège et
meurent avec le ns (GC parfait). Étude préalable + POC système léger (sans UML) demandés avant
toute décision d'implémentation. **Aucun code touché** ; POC = namespaces jetables + un socket
de test, aucun effet persistant.

### 12.1 Résultats du POC (poste de l'auteur, Kubuntu 24.04, kernel 6.8.0-134)

| # | Question | Commande | Résultat | Conséquence |
|---|---|---|---|---|
| 1 | Userns non privilégié utilisable ? | `unshare -Urn true` | **KO** : `write failed /proc/self/uid_map: Operation not permitted` (rc=1) ; idem `bwrap --unshare-user --unshare-net` | La restriction AppArmor Ubuntu (`kernel.apparmor_restrict_unprivileged_userns=1`, § 4.0) est **active** → **un profil AppArmor `userns,` est obligatoire** pour ce poste. Confirme la prévision de l'étude, expérimentalement. |
| 2 | Socket Unix (chemin) traverse le netns ? | serveur `socat UNIX-LISTEN:/tmp/poc.sock` dans le ns racine, client `unshare -n socat UNIX-CONNECT` | **OK** (rc=0, `REACHED-FROM-NETNS`) | hublets vde, X11 local (`/tmp/.X11-unix/X?`), mconsole — tous à **socket-chemin** — **traversent** le cloisonnement réseau. Hypothèse centrale de l'architecture B **validée**. |
| 2b | Socket **abstrait** traverse ? | idem en `ABSTRACT-LISTEN`/`ABSTRACT-CONNECT` | **KO** (`Connection refused`, rc=1) | Les sockets **abstraits** sont scopés au netns → **piège** : tout composant les utilisant casserait. Point de vigilance (les clients X Linux tentent d'abord le socket abstrait `@…/X0` ; le relais de `x.ml` vise le chemin, donc OK, mais à vérifier au câblage). |
| 3 | Contrat `Tap_provider` reproductible **dans** le netns, sans privilège additionnel ? | dans `unshare -Urn` : `ip tuntap add … mode tap` + `ip addr add 172.23.0.254/32` + `ip route add 172.23.0.42 dev …` | **OK** : `ip route get 172.23.0.42` → `dev mtap-poc src 172.23.0.254` | Le contrat réseau du daemon (route host-specific comprise) se reproduit **à l'identique** dans le netns — comme la preuve `--live` de l'ép. 1, mais **sans sudo** (CAP_NET_ADMIN tenu par possession du ns). |

Non testé (jugé non décisif, fait noyau déjà sourcé § 4.0) : `vde_switch -tap` en attache
non privilégiée dans le netns, et le boot UML-dans-netns (relèverait du POC « UML complet »,
option écartée au cadrage).

### 12.2 Architecture recommandée : « GUI entière dans le netns »

L'analyse du code tranche entre les deux architectures que l'étude § 4.1-B laissait ouvertes :

- **Rejetée — « holder + nsenter ciblé »** : envelopper chaque `Unix.create_process` d'un
  `nsenter --user --net`, plus le socat de `x.ml`. Intrusif, fragile.
- **Recommandée — lanceur `unshare -Urn` autour de tout le processus GUI** : deux faits de code
  la rendent quasi gratuite côté runtime :
  1. `bin/simulation_level.ml:101` — **tous** les processus simulés (UML, `vde_switch`,
     `slirpvde`, `telnet` quagga) passent par l'unique `Unix.create_process` de la classe
     `process` : lancés depuis une GUI déjà dans le netns, ils **héritent du netns** sans un
     seul `nsenter`.
  2. `bin/x.ml` — le « socat » des cas 2-5 est un **serveur OCaml in-process**
     (`Network.Socat.dual_inet_of_stream_server`) : dans le netns, il écoute
     `0.0.0.0:600x` **du netns**, où les UML (mêmes netns) se connectent — inchangé.

  Le runtime OCaml est alors **quasi intouché** : l'ép. 5 devient surtout un **lanceur**
  (`unshare -Urn` + profil AppArmor) plus la neutralisation de `purge_orphan_taps`/dialogue
  sudoers (rendus inutiles), et non une réécriture des sites de spawn.

### 12.3 Points durs restants (non résolus par le POC)

1. **world_bridge dans le ns racine.** `bin/world_bridge.ml` fait ouvrir le tap par un
   `vde_switch -tap` (via la classe `process`, donc dans le netns), mais le bridge admin
   `MARIONNET_BRIDGE` vit dans le **ns racine** : un tap créé dans le netns **ne peut pas** y
   être raccordé. Options : (a) garder le **sudo scoped** pour ce seul composant (le « zéro
   sudo » ne vaut alors que pour eth42) ; (b) **variante D** (taps pré-provisionnés par
   l'admin, déjà documentée `docs/admin-taps-and-bridge.md`, non câblée) ; (c) lancer ce seul
   `vde_switch -tap` avec un fd du ns racine conservé. → world_bridge reste **hors** du bénéfice
   netns sauf effort supplémentaire.
2. **X-en-TCP (cas 3/4 de `x.ml`, ssh -X / X distant).** La cible n'est plus un socket local
   mais `host_addr:port` en TCP hors du netns : depuis un netns sans veth/NAT, injoignable.
   Parade : relais dans le ns racine + socket-chemin intermédiaire, **ou** exclusion documentée
   (le cas X-distant perd le graphique invité — dégradation acceptable ?). À trancher.
3. **Profil AppArmor à livrer** (résultat POC #1) : `make install` déposerait
   `/etc/apparmor.d/marionnet` avec `userns,` sur le lanceur, comme Chrome/Discord. Charge de
   maintenance + interaction avec les politiques de sécurité de la salle de TP.

### 12.4 Ce que l'ép. 5 rendrait caduc (bénéfice)

- `purge_orphan_taps` au démarrage (mort du ns = GC parfait, § 5.1) ;
- le dialogue sudoers de démarrage et le probe `Tap_provider.is_usable` (plus de sudo pour
  eth42) ;
- la moitié « eth42 » de la règle sudoers (resterait la partie world_bridge, cf. point dur 1).

### 12.5 Périmètre, effort, critère d'épisode

- **Périmètre** : un lanceur (`unshare -Urn`, wrapper autour de `marionnet.native`), un profil
  AppArmor + son install (Makefile), le traitement de world_bridge (option a/b/c) et du cas
  X-TCP, la neutralisation conditionnelle du chemin sudo eth42. Runtime OCaml **peu** touché.
- **Effort** : moyen (lanceur + AppArmor + 2 points durs), dominé par l'intégration/install et
  la validation UML-dans-netns (non faite ici), pas par le code applicatif.
- **Critère vérifiable** (POC « UML complet » à faire au chantier) : une VM UML bootée **dans**
  le netns, X11 invité OK, telnet quagga OK, **zéro** `mtap*` sur l'hôte après fermeture
  (GC par mort du ns), **sans** règle sudoers eth42 installée.

### 12.6 Recommandation : **DIFFÉRER** (chantier laissé ouvert)

L'ép. 5 est **techniquement viable** — le POC valide ses trois hypothèses porteuses (contrat
tap dans le netns, traversée des sockets-chemin, architecture « GUI dans le netns » quasi
gratuite). Mais :

- son unique **motivation** est le « zéro sudo » de la **salle de TP** — contexte **secondaire**
  au cadrage (§ 3.1), **non concrétisé** à ce jour ;
- il introduit une **charge permanente** (profil AppArmor à maintenir) et **deux points durs**
  (world_bridge, X-TCP) qui, non traités, **dégradent** des fonctions que l'étape 1 assure déjà ;
- l'étape 1 (livrée, ép. 1-4) **satisfait le contexte prioritaire** (poste personnel avec sudo)
  avec une surface **plus étroite** que le daemon supprimé.

→ **Ne pas ouvrir l'ép. 5 maintenant** ; le garder documenté et prêt (ce § 12) pour le jour où
le besoin TP « zéro sudo » se matérialise. Le chantier reste **ouvert** sur cette seule option ;
à défaut, il est mûr pour la **clôture** (MODE C) à la main de l'auteur.

## 13. Épisode 6 — régression : la tap eth42 détruite par un fork

Bug rapporté (2026-07-16, run GUI de l'auteur) : dans une VM trixie, `xeyes` puis
`xeyes & ; kill %2` → le premier `xeyes` gèle, tout le graphique de la VM est mort.
Le log (`marionnet.native -d`) montre l'enfant relais de la connexion X fermée loggant
« Protocol completed … Exiting. » puis « **Tap_provider: the tap mtap…-0 was destroyed** »,
et le `gracefully_terminate` ultérieur échouant (« Cannot find device »).

**Cause racine.** `bin/x.ml` (cas 2-5) sert le X11 invité via le serveur ocamlbricks
`process_forking_loop` (`lib/STRUCTURES/network.ml:226`) : **un enfant forké par connexion**,
terminé par `exit` — qui exécute les handlers `at_exit` **hérités du processus GUI**, dont le
filet de l'ép. 1-2 (`tap_provider.ml`) : `at_exit (fun () -> List.iter destroy_tap …)`.
L'enfant hérite de la table `my_taps` par le fork → `is_mine` passe → la tap de l'hôte est
détruite alors que la VM vit encore. **Toute fermeture de connexion X** (fermer une appli
graphique invitée) suffisait à déclencher le bug. Le daemon n'avait pas ce défaut : il ne
détruisait que sur message explicite, jamais à l'exit d'un enfant de la GUI.

**Correctif** (`bin/tap_provider.ml`) : pid propriétaire capturé au chargement du module
(initialisé dans le processus principal, avant tout fork ; les taps sont créées par des
threads de ce processus, jamais par des forks) ; le handler `at_exit` ne fait rien si
`Unix.getpid () <> owner_pid`. Pas de garde dans `destroy_tap` (appelants explicites tous
dans le processus principal ; une garde là loggerait un refus par tap à chaque exit d'enfant).

**Preuve** (`bin/tap_provider_test.ml`, mode `--live`) : nouveau check « fork + exit d'un
enfant → la tap survit ». Rouge sans le correctif (`[FAIL] the tap survives the exit of a
forked child`, rc=1), vert avec (0 FAIL, 0 `mtap*` résiduel sur l'hôte).

**Piège consigné** : dans ce dépôt, un `at_exit` s'exécute aussi dans les **enfants forkés**
par les serveurs Network d'ocamlbricks (relais X11 de `x.ml`) — tout handler `at_exit` à effet
sur des ressources partagées (hôte) doit être gardé par pid.

## Journal d'avancement

- **2026-07-14 — épisode 0** : étude de faisabilité (inventaire du daemon, vérifications
  kernel/distro, cadrage utilisateur, verdict FAISABLE/recommandé) et officialisation du
  chantier `marionnet-daemon-elimination`. Aucun code touché ; prochain pas = épisode 1
  (`tap_provider` + sudoers + bascule eth42, § 6).
- **2026-07-14 — épisode 1** : la brique de remplacement existe et est **prouvée**.
  `Tap_provider` (sudo -n + iproute2) + règle sudoers scopée + driver de preuve ; découpage
  révisé (§ 6, brique/bascule séparées) ; écarts et 2 pièges consignés (§ 8). Preuve contre
  le noyau (`tap_provider_test --live`, règle installée sur le poste de l'auteur) : tap créé,
  `172.23.0.254/32` porté, `ip route get 172.23.0.42` → `dev mtap<pid>-0 src 172.23.0.254`
  (la route host-specific du daemon, à l'identique), destruction complète, orphelin d'un pid
  mort collecté sans toucher au tap vivant, garde `172.23.` effective. `dune build` rc=0 ;
  **aucun appelant** : daemon et GUI inchangés. Prochain pas = épisode 2 (bascule eth42).
- **2026-07-16 — épisode 2** : la bascule eth42 est faite — la GUI ne demande plus aucun
  tap au daemon (`simulation_level.ml` → `Tap_provider`, purge + dialogue sudoers au
  démarrage de `marionnet.ml`, échec daemon rétrogradé en log). Validation : build/test
  rc=0, X11 invité OK, taps détruits OK ; telnet quagga non acté (test perturbé par
  l'incompatibilité vieux couples kernel/image ↔ hôte moderne, § 9 — deux chantiers
  potentiels consignés). i18n différée à l'ép. 4. Prochain pas = épisode 3 (world_bridge).
- **2026-07-16 — épisode 3** : la bascule world_bridge est faite — **le daemon n'a plus
  aucun client**. `Tap_provider.make_bridge_tap` (contrat `AnySocketTap` à l'identique,
  règle sudoers inchangée), `world_bridge.ml` basculé, mode `--live-bridge` du driver,
  doc admin `docs/admin-taps-and-bridge.md` (groupe TP ; variante D documentée non
  câblée). Preuve contre le noyau : promisc/up/master + destruction, 0 FAIL (§ 10).
  Prochain pas = épisode 4 (purge des 4 fichiers daemon + refresh gettext unique +
  réévaluation de `marionnet_common`).
- **2026-07-16 — épisode 4** : la purge est faite — **le daemon n'existe plus dans le dépôt**
  (périmètre grill : runtime seul, vestiges non touchés). 4 fichiers + stanza dune + script
  SysV + `MARIONNET_SOCKET_NAME` supprimés ; `marionnet_common` → `marionnet_base` (réduite à
  `marionnet_log configuration meta`) ; refresh gettext unique (POT 356 msgid, 12 langues à
  356/356, 2 nouvelles msgid traduites ×12 par compendium) ; docs vivantes à jour
  (ARCHITECTURE § 6 + § 2, CLAUDE.md ×3). Build/test rc=0 ; grep code-résiduel nul (§ 11).
  Reste du chantier : run GUI de l'auteur à acter, puis ép. 5 optionnel (netns) ou clôture.
- **2026-07-16 — épisode 5 (étude)** : étude netns + POC léger (sans UML), **aucun code touché**
  (§ 12). POC sur le poste : (1) userns non privilégié **bloqué** par AppArmor
  (`uid_map: EPERM`) → profil `userns,` obligatoire ; (2) socket Unix-**chemin** **traverse** le
  netns (KO en abstrait) → hublets/X11/mconsole OK ; (3) contrat `Tap_provider` reproduit **dans**
  le netns **sans sudo** (`ip route get` → `src 172.23.0.254`). Analyse code : architecture
  **« GUI entière dans le netns »** recommandée (spawn unique `simulation_level.ml:101` + socat
  in-process de `x.ml` → runtime quasi intouché) ; points durs = world_bridge (bridge en ns
  racine), X-TCP (cas 3/4 `x.ml`), profil AppArmor. **Recommandation : DIFFÉRER** (motivation TP
  « zéro sudo » non concrétisée ; l'étape 1 couvre le contexte prioritaire). Chantier laissé
  ouvert sur cette seule option, sinon mûr pour clôture (MODE C).
- **2026-07-16 — épisode 6** : régression corrigée — la tap eth42 était détruite par les
  **enfants forkés** des relais X11 de `x.ml` (leur `exit` exécutait l'`at_exit` de
  `tap_provider.ml` hérité du fork, table `my_taps` comprise) : fermer une connexion X
  suffisait à tuer le graphique de la VM (§ 13). Correctif : garde `owner_pid` sur le handler
  `at_exit`. Preuve : nouveau check fork-exit du driver `--live`, rouge sans le fix, vert avec
  (0 FAIL) ; build/test rc=0. Reste inchangé : ép. 5 optionnel (netns) ou clôture.
