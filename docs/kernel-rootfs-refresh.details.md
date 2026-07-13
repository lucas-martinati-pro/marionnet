# Détails & constats — chantier `marionnet-kernel-rootfs`

> **Nature de ce fichier.** Trace fine des *constats* et *décisions argumentées* du chantier
> (analyses ponctuelles, tableaux de décision, mesures). Complément de `kernel-rootfs-refresh.md`
> (conception + journal d'épisodes). **Volontairement non résumé dans la mémoire ni le CLAUDE.md** :
> il n'a d'intérêt que si l'on retombe *exactement* sur la même question (p. ex. « ce timer,
> garder ou éliminer ? »). À consulter à la demande, pas à charger en contexte par défaut.

---

## 2026-07-10 — Timers systemd de l'image Trixie : garder ou éliminer ?

**Contexte.** Image `_build.debian-trixie-with-linux-6.12.95.2026-07-10.01h25`. Après le
durcissement « machine nue » de l'épisode 7 (services réseau/serveurs OFF par défaut), il restait
des **timers systemd** activés au boot, non traités par la whitelist de services (qui ne balayait
que `*.target.wants/`, pas `timers.target.wants/`).

**Inventaire réel.** 8 timers activés (`etc/systemd/system/timers.target.wants/`) ;
5 dormants (installés, non activés : `chrony-dnssrv@` [template], `sysstat-{collect,rotate,summary}`,
`systemd-tmpfiles-clean` [cœur systemd]) → aucun traitement requis.

**Fait transversal décisif : les 8 activés ont `Persistent=true`.** Dans une VM éphémère dont
l'horloge démarre « en retard » (ou sans dernier-run enregistré), systemd considère l'échéance
ratée et **rattrape immédiatement au boot**. Conséquence : ces tâches de maintenance « nocturnes »
se déclenchent **en rafale juste après le boot**, quand l'étudiant commence à travailler.

**Grille de décision (Jean).** « Forcer l'étudiant à lancer ça a-t-il une valeur pédagogique
(GARDE), ou est-ce une gêne sans intérêt (ÉLIMINE) ? » — Méthode : **aucun de ces 8 n'est un
service réseau/admin qu'on apprend à administrer** (ceux-là — ssh, bind, dhcp, apache… — sont déjà
OFF-installés, l'étudiant les lance). Ce sont tous de la **maintenance système de fond** → la
question devient « bénéfice réel dans cette VM, ou bruit ? ».

| # | Timer | Rôle réel | Dans une VM UML pédagogique éphémère | Verdict |
|---|-------|-----------|--------------------------------------|---------|
| 1 | **apt-daily** | `apt-get update` + download des paquets | Réseau OFF → échoue ; surtout **verrouille dpkg** au pire moment (l'étudiant fait `apt install` en TP → lock incompréhensible). Anti-reproductibilité. | ÉLIMINE (fort) |
| 2 | **apt-daily-upgrade** | MAJ auto (`apt.systemd.daily install`) | Une image maîtrisée ne doit pas s'auto-mettre à jour (casse la repro). Déjà inerte (pas d'`unattended-upgrades` installé) mais nuisance de principe. | ÉLIMINE (fort) |
| 3 | **dpkg-db-backup** | Backup quotidien de la base dpkg (`/var/backups`) | Sauvegarder la base **dans** une VM jetable n'a aucun sens ; consomme de l'espace sur une image à alléger. | ÉLIMINE |
| 4 | **e2scrub_all** | fsck ext4 *online* via snapshots **LVM** | Image = ext4 simple sur `/dev/ubda`, **pas de LVM** → strictement no-op. Pur bruit. | ÉLIMINE |
| 5 | **fstrim** | TRIM/discard hebdo (SSD) | `/dev/ubd` UML ne propage pas le discard utilement au fichier hôte → no-op en pratique. | ÉLIMINE (faible enjeu) |
| 6 | **lighttpd-maint** | Maintenance de lighttpd | `lighttpd.service` **déjà OFF** (ép. 7) → timer **orphelin** qui tourne dans le vide. Le service web reste installé, l'étudiant l'active (bon comportement) ; le timer doit suivre l'état du service. | ÉLIMINE |
| 7 | **logrotate** | Rotation quotidienne de `/var/log` | Seul avec un argument « hygiène réelle » (VM longue → logs gonflent). Mais VMs Marionnet = courtes, et un `/var/log` qui déborde est un *enseignement*. Inoffensif, à peine utile. | ÉLIMINE (discutable — le plus défendable à garder) |
| 8 | **man-db** | Réindexation quotidienne des pages man | `man` marche sans index frais. `Persistent=true` → se déclenche **à chaque boot** et consomme CPU/IO pendant le travail. | ÉLIMINE |

**Décision (Jean, 2026-07-10) : désactiver les 8.** Aucun n'est un objet d'apprentissage ; tous
sont no-op, anti-reproductibles/nuisibles, orphelins ou inutiles sur cette cible — et tous se
déclenchent au boot (`Persistent=true`). `logrotate` était le seul cas discutable (réalisme
système) ; tranché ÉLIMINE aussi.

**Implémentation retenue.** Passe symétrique au *pass 1* de
`prevent_non_vital_services_from_starting` (branche systemd) : balayer
`etc/systemd/system/timers.target.wants/` et `rm` les symlinks (équivalent offline-safe de
`systemctl disable`). Whitelist vide. → épisode 8.

---

## 2026-07-10 — Support X11 des VM dans `pupisto.tester.sh` : direction « port série » + AUDIT À FAIRE

**Contexte.** On veut afficher des applis graphiques de la VM (xeyes → wireshark) sur le serveur X
de l'hôte de dev, dans `pupisto.tester.sh`. Correction d'une première analyse erronée : le
mécanisme de Marionnet **ne passe pas par Xephyr** (résidu d'une implémentation abandonnée, à ne
pas récupérer — `class xnest_process` dans `simulation_level.ml`). Le vrai mécanisme (`bin/x.ml`
`fix_X_problems` + `bin/machine.ml` ~761) est une **chaîne de `socat` reliée par une ligne série
UML, sans réseau IP ni sudo** :
```
HÔTE                                     │           INVITÉ
socket X hôte /tmp/.X11-unix/X0 ◄ socat ◄ /dev/pts/N ═╪═ /dev/ttySx ◄ socat ◄ /tmp/.X11-unix/Xd ◄ appli
   (socat ponte le socket Unix →         │ pty hôte    port série  (marionnet-dummy-xserver:
    contourne `-nolisten tcp`)           │ = canal UML  UNIX-LISTEN Xd,fork EXEC dummy-xservice)
```

**Direction stratégique (Jean).** Passer le déport X11 par un **port série** au lieu de l'interface
« ghostifiée » **eth42**. Historiquement eth42 (et donc la ghostification, patches noyau `uml/kernel`
+ outil C `ethghost`) aurait été introduite *précisément* pour déporter le DISPLAY X11. Si le série
suffit, **eth42 et la ghostification deviennent secondaires, voire éliminables** → simplification
majeure du projet (cohérent avec le noyau **vanilla non ghostifié** de Dave, qui boote déjà).

**AUDIT SÉRIEUX À FAIRE (noté ici, PAS maintenant)** — la conclusion « eth42/ghost éliminables »
est une *conclusion d'audit*, pas une prémisse. Deux hypothèses à prouver dans le code :
- **C1 — « eth42/ip42 ne sert QU'à X11 ».** Auditer tous les usages de `eth42`/`ip42` dans `bin/`
  (notamment : par quel canal `marionnet-relay` parle-t-il à l'hôte ? La config passe déjà par
  **hostfs**, pas eth42 — bon signe — mais `ip42`/`host_ipv4_address_eth42`/`…_ipv6_…` sont injectés
  dans l'invité : pour qui, à part le vieux chemin X TCP `172.23.0.254:0` ?). Si un autre service
  dépend d'eth42, l'éliminer casse plus que X11.
- **C2 — « la ghostification n'existe que pour cacher eth42 ».** Auditer `uml/kernel` + `ethghost` :
  s'applique-t-elle *uniquement* à eth42, ou à *toutes* les interfaces des liens simulés (autre
  raison d'être) ? Dans ce dernier cas elle ne disparaît pas avec eth42.

**Contrainte de conception CONFIRMÉE (challenge C3, validé avec Jean 2026-07-10).** Un **seul** canal
série ne multiplexe PAS plusieurs connexions X : le protocole X11 est un flux binaire à état *par
connexion*. Avec un `ssl4`↔`/dev/ttyS4` unique + `socat …,fork`, deux connexions simultanées
(`xeyes & xeyes`, `xeyes & wireshark`) forkent deux socat ouvrant le **même** device série → octets
**entrelacés** sur un flux unique sans trame → le serveur X voit un flux corrompu → **les deux
meurent** (corruption mutuelle, pas simple contention). Séquentiel (une appli fermée avant la
suivante) : OK. Différence structurelle avec eth42 : eth42 = **une** interface IP portant N
connexions TCP multiplexées nativement ; un pts série = **une** connexion à la fois. D'où : pour
2+ applis graphiques, il faut un **pool de `sslN`** ou l'**allocation dynamique par connexion** —
ce que fait déjà Marionnet (`dummy-xservice` prend un `/dev/ttySx` libre par connexion ; `machine.ml`
tient une liste de `pts_relays`, un pts hôte par connexion). L'endpoint exclusif est donc *par
connexion X*, pas *par VM*.

**Risque à valider empiriquement.** Débit du canal série UML pour X11 (host-fd ≈ mémoire, a priori
suffisant, mais **wireshark = vrai test de charge**). Jamais mené « jusqu'au bout » côté OCaml selon
Jean → possiblement jamais éprouvé en charge.

**Plan incrémental retenu.** (1) Jalon 1 = **1 connexion / 1 pts fixe** (`ssl4`), côté invité manuel,
sur xeyes puis wireshark seul → preuve de débit + faisabilité. (2) Audit C1+C2 **avant** toute
conclusion sur l'élimination d'eth42/ghost. (3) Si 1+2 passent : concevoir le **multi-connexion**
(pool `sslN` ou dynamique à la Marionnet), condition pour que série *remplace* eth42. Ensuite
seulement : aligner le code OCaml de Marionnet (`x.ml`/`machine.ml`, à auditer/corriger — jamais
fini) sur le comportement du tester, éventuellement en factorisant un script Bash appelé par les deux.

### 2026-07-10 (suite) — jalon 1 statique INVALIDÉ ; bascule sur le schéma dynamique

Le mode `-X` mono-connexion « pré-câblé » (`pupisto.tester.sh` : `socat PTY,link=$XPTY
UNIX-CONNECT:$HOST_X_SOCKET` + `ssl4=tty:$pts`) a été implémenté et testé au boot réel. **Échec, cause
racine établie et testée :**
- **Le serveur X ferme toute connexion qui reçoit des octets non conformes au handshake X11.**
  Test isolé : `socat PTY … UNIX-CONNECT:X0` vit tant que rien ne circule (~0,6 s), mais dès qu'on
  écrit des octets parasites dans l'esclave du pty → le serveur X **ferme** → `socat` meurt (`DIED`).
- Or le jalon connecte le pty au serveur X **en permanence dès le boot**. Dès que la ligne série
  véhicule le moindre octet non-X (ouverture/init UML, avant que `xeyes` ne parle), X ferme →
  `socat` hôte meurt → `/dev/pts/N` disparaît → UML perd la ligne → `/dev/ttyS4` inutilisable côté
  invité. Symptômes observés cohérents : socat hôte absent + `/dev/pts/10` disparu **pendant** que
  le tester/UML tournent ; `dmesg` invité sans « Serial line 4 assigned » ; `/dev/ttyS4` non créé
  par UML (mknod manuel requis — le node ainsi créé est « mort », sans backing UML).

**Conséquence structurelle** : le **pré-câblage statique « pty→X au boot » ne peut pas marcher** ; la
connexion à X doit être **déclenchée à la demande**. C'est exactement pourquoi Marionnet ne lance le
relais hôte (`pts_of_stream_server`) **qu'au signal `.opened`** (un vrai client X est connecté) :
jamais de fenêtre « idle/bruit » sur la connexion X. Donc **même pour UNE connexion**, une
« connexion paresseuse » est nécessaire — le schéma purement statique est mort-né.

**Décision (Jean, 2026-07-10) : direction 1 — basculer sur le schéma DYNAMIQUE** (finir/porter le
mécanisme Marionnet dans le tester) : hostfs partagé comme canal de contrôle ; côté invité
`marionnet-dummy-xserver`/`-xservice` (socat UNIX-LISTEN Xd,fork ; par connexion : ttyS libre →
ouverture → pts alloué lu dans `dmesg` → signal `ttySN-ptsM.opened`/`.closed`) ; côté hôte un
watcher (inotify) qui lance/tue un `socat /dev/pts/M ↔ socket X` par événement. Points restés
**non validés** et à lever pendant l'implémentation : (i) `ssl4=tty:` fonctionne-t-il côté UML
(non conclu) — avec le dynamique on utilise plutôt le défaut `CONFIG_SSL_CHAN=pts` ; (ii) `dummy-
xserver`/`-xservice` sont-ils présents dans l'image trixie, ou à fournir via hostfs ; (iii)
`inotifywait` dispo côté hôte. Le débit série (wireshark) reste à mesurer une fois la chaîne montée.

### 2026-07-10 (suite) — PoC manuel du lazy-connect : acquis et point de blocage

PoC live (Jean côté invité, Claude côté hôte), boot **sans** `-X` (défaut `CONFIG_SSL_CHAN=pts`).
Résultats **testés** :
- **Ligne série UML fonctionnelle sans `ssl4=tty:`** : ouvrir `/dev/ttyS4` (après `mknod -m 666
  /dev/ttyS4 c 4 68` — UML ne matérialise pas le node) déclenche `dmesg: Serial line 4 assigned
  device /dev/pts/M`. Le major 4 / minor 64+N est le bon. Donc `ssl4=tty:` est **inutile** : le
  défaut pts suffit, l'invité `mknod` le node et l'ouverture alloue le pts hôte.
- **Lazy-connect validé** : connecter le relais hôte `socat /dev/pts/M UNIX-CONNECT:X` **à la
  demande** (pas au boot) évite la mort prématurée du socat (cause racine du jalon statique).
- **Transport invité→hôte OK** : `printf 'ABCDEFGH' > /dev/ttyS4` (invité) arrive **binaire intact**
  sur `/dev/pts/M` (hôte). (Piège de mesure : `cat | xxd` bufferise les octets partiels — n'affiche
  qu'à 16 octets ou EOF ; tuer le lecteur pour flusher.)
- **Transport hôte→invité KO en bash naïf** : `printf > /dev/pts/M` (O_WRONLY) **et** `exec 8<>`
  (O_RDWR) n'atteignent **jamais** `/dev/ttyS4` côté invité (avec ou sans `\n`, discipline raw).
  → c'est ce qui bloque `xeyes` : le client envoie son handshake (qui arrive), mais ne reçoit
  jamais la réponse du serveur X.

**Cause racine identifiée via l'oracle `lib/SHELL/pts.ml`** (la classe `stream_channel`, ce
qu'utilise `Network.Socat.pts_of_stream_server`, qui marche en prod) : le côté hôte ouvre le pts
avec **DEUX fd séparés** — `O_RDONLY|O_NONBLOCK` (lecture) et `O_WRONLY|O_NONBLOCK|`**`O_NOCTTY`**
(écriture) — et un **termios raw complet** (`c_icanon=false, c_echo=false, c_opost=false,
c_isig=false, c_vmin=1`). Le **`O_NOCTTY` sur l'écriture** est très probablement décisif : une
ouverture bash sans `O_NOCTTY` fait de l'esclave le terminal contrôlant du process écrivain, et
l'écriture **ne se propage pas au maître** (UML) → sens hôte→invité muet. Cohérent avec
l'asymétrie observée.

**Conséquence pour l'implémentation** : le helper hôte ne peut pas être un `printf`/`echo` naïf ;
il faut reproduire l'ouverture de `pts.ml` (fd WRONLY **avec O_NOCTTY** + termios raw). À vérifier :
si `socat …/dev/pts/M,raw,echo=0` pose le même souci (socat ouvre en O_RDWR sans forcément
O_NOCTTY), il faudra les bonnes options socat (`,o-noctty`/`rawer`) **ou** un petit outil dédié
(ou réutiliser directement le `pts_of_stream_server` OCaml). **Reste non mesuré** : le débit série
sous charge (wireshark), une fois le sens hôte→invité rétabli.

## 2026-07-10 — Outil de test autonome : option `-A/--auto-network-by-eth42`

Prérequis (décidé par Jean) au « finissage » du X11 : une option du tester donnant à Claude un
**accès SSH sans mot de passe** à la VM lancée, pour tester en autonomie. Bâtie dans
`uml/pupisto.tester/pupisto.tester.sh`. Points clés :

- **Unicité par instance (« K unique »)** : `net_free_octet` balaye `1..254`, prend le premier octet
  `K` dont ni `172.23.K.254/` ni l'interface `mnt-tapK` n'existent → dérive **tap `mnt-tapK`**, hôte
  `172.23.K.254/24`, guest `172.23.K.1`, `umid`/`hostname` = `tester-K`. Permet **plusieurs images en
  parallèle** sans collision (tap **et** mconsole/umid **et** sous-réseau — `$RANDOM` sur le seul tap
  aurait laissé collisionner umid/IP).
- **Sudo maîtrisé** : le tester s'auto-provisionne une règle `/etc/sudoers.d/marionnet-tester` en
  **NOPASSWD** scopée `mnt-tap*` (create/del/addr/link), demandée **une fois** (mot de passe la
  première fois, pour Jean) puis silencieuse. `visudo -cf` valide la syntaxe avant install.
- **Clé propre** : `ensure_ssh_key` génère un ed25519 `tester_key` (gitignoré), poussé dans l'invité
  via un patch `marionnet-relay-ssh` sourcé depuis le hostfs (installe la clé + `systemctl start ssh`).
- **Cleanup** : `net_tap_down` (démonte le tap) + `rm` COW/hostfs à la sortie (trap `cleanup`).
- **Piège d'observation** : le motif d'auto-journalisation (`tee`) fait que le message `READY:` du
  script atterrit dans le **journal mktemp**, pas dans une redirection `>` de la sortie (celle-ci ne
  reçoit que la console kernel `con0=fd:1`). Pour l'usage autonome : **poller le SSH directement**,
  ne pas guetter `READY` dans la redirection.

Validé bout-en-bout (K=1) : boot systemd → `marionnet-relay`+`ssh` → SSH `root@172.23.1.1` OK
(`Linux tester-1 6.12.95`), eth42 `172.23.1.1/16`, seul échec `run-rpc_pipefs.mount` (inoffensif).

## 2026-07-10 — PIVOT : X11-série **suspendu** → approche C (eth42 conservé + ghostification NETNS)

Après discussion (Jean) : on **abandonne** le transport X11 par port série au profit de l'**approche
C**. Raisonnement :

- X11 est un **protocole réseau** → le porter sur eth42 (lien réseau) le **multiplexe nativement** :
  les **deux murs** du schéma série disparaissent — le multiplexage N-connexions (1 ligne série =
  1 connexion, corruption sinon) **et** le transport hôte→guest bloqué (oracle `pts.ml` ci-dessus).
- La raison d'abandonner la ghostification **patch** était le **noyau vanilla** (objectif Dave). Or
  `CONFIG_NET_NS=y` en 6.12 → on peut **ghostifier eth42 par netns**, donc atteindre l'objectif
  vanilla **sans** patch **et** garder eth42.
- **Masquage pédagogique**, pas anti-root (tranché par Jean) : netns **ne résiste pas** à un root
  guest (`nsenter -t <pid> -n`, `ip netns exec`). Accepté : le but est de **désencombrer `ip a`**
  pour la clarté des TP, pas de résister à un étudiant adversarial. (Le patch noyau, lui, filtrait le
  device même pour le root — garantie plus forte, mais coût de maintenance et incompat vanilla.)
- Idée **connexe** (Jean) : faire tourner Marionnet dans une **sandbox namespaces hôte**. Vrai gain =
  **rootless via user namespaces** (retirer le rôle privilégié de `marionnet_daemon.ml` : taps/veth
  sans sudo ; le réseau inter-équipements VDE est **déjà** userspace). **Chantier séparé**, découplé
  de X11 ; un netns seul ne confine que le bruit **réseau**, pas process/fichiers (faudrait mount+pid+
  user ns). Non ouvert pour l'instant.

### Test décisif du mécanisme de C (le seul risque technique dur) — **RÉUSSI**

Question : les NIC virtuels UML sont-ils **déplaçables entre netns** (pas `NETNS_LOCAL`) ? Sans quoi
C est mort. Testé dans `tester-1` (lancée par `-A`), procédure **réversible** (trap de restauration,
log dans `/mnt/hostfs` lu depuis l'hôte car déplacer eth42 coupe le SSH, lancement `setsid` détaché) :

1. `ip netns add mgmt` ; `ip link set eth42 netns mgmt` → **`MOVE_RC=0`** (eth42 = netdev
   `platform / uml-netdev.42`, **pas** `NETNS_LOCAL`).
2. Vue du **netns racine** après déplacement : **`lo` seul, eth42 absent** → ghostification obtenue
   côté login étudiant.
3. eth42 dans `mgmt` : reconfig `172.23.1.1/16` + up + **`ping 172.23.1.254` = 0.13 ms, 0% perte** →
   canal pleinement fonctionnel **depuis le netns caché**.
4. Restauration (trap) : eth42 rendu au netns racine, SSH revenu (vérifié).

Terrain confirmé dans l'image Trixie : `ip`/`unshare`/`nsenter` présents, netns créable en root guest,
`CONFIG_NAMESPACES=y`+`CONFIG_NET_NS=y`, `/mnt/hostfs` monté rw.

### Reste à faire pour C (non fait)

- **Audit C1 — FAIT (2026-07-10)** : `eth42`/`ip42` sert **essentiellement au déport X11**, rien
  d'autre de matériel. `simulation_level.ml:1250/1258` `xhost +/-$ip42` (autorise le serveur X hôte
  pour l'IP guest) ; `:873` `Make(AnyTap(uid,ip42))` + `:896` `eth42=tuntap,…,172.23.0.254` (tap créé
  par le daemon, hôte `.0.254`) ; `:1229-1237` `boot_parameters` = `ip42`+`host_ipv4/ipv6_address_eth42`
  (la guest apprend l'adresse de son display ; `ip42` « for compatibility with old VM ») ; méthode
  `ip_address_eth42` exposée (machine/router/simulation). **Aucun** transfert fichiers/presse-papier
  trouvé. Cohérent avec `x.ml` (socat → socket Unix pour contourner `-nolisten tcp`). ⇒ **eth42 = canal
  réseau du X11** : C le garde tel quel, le cache par netns.
- **Audit C2 — FAIT (2026-07-10)** : la ghostification **patch** (`doc/README.Ghostification`) rend
  une interface **invisible à tout process user, ROOT compris** — ioctl `-ENODEV`, absente `/proc/net`,
  **netlink/iproute2 aveugle**, **hooks Netfilter sautés**, routes cachées mais suivies. Appliquée par
  le userland `ethghost -g <dev>` (ioctl custom `SIOCGIFGHOSTIFY`) adossé à `net/core/dev.c` **+ beaucoup
  de fichiers `net/`**, **par version de noyau** (→ c'est CE qui bloque vanilla 6.12). Limites avouées :
  max 9 ghosts, **fuites `/sys` + certains `/proc`**, ifindex non contigus.
  **netns = équivalent standard bien plus léger** : couvre les **mêmes surfaces** (ioctl/netlink/proc/
  netfilter) pour le netns étudiant, **sans fuite** (séparation réelle vs « sauter les hooks »), **0
  patch**. Seul écart = **pas anti-root** (`nsenter`) — abandonné volontairement (masquage pédagogique).
  **Remplacement concret** : `ethghost -g eth42` → `ip link set eth42 netns mgmt` (dans `marionnet-relay`).
  Le **patch noyau ET l'outil C `ethghost` disparaissent**. ⇒ intuition Jean confirmée.
- **Plumbing d'init guest** : netns `mgmt` anonyme (pas de `/run/netns/` nommé), y déplacer eth42 +
  y lancer `marionnet-relay`+pont X11, laisser `eth0..eth7`+login au netns racine. Ordre : déplacer
  eth42 **avant** tout login. Vérifier la survie du déplacement quand eth42 porte déjà une conf.
- **Pont X11 hôte↔guest sur eth42** : essayer d'abord le plus simple (`ssh -X`/`-Y`) ; sinon proxy
  socat côté hôte + contournement `-nolisten tcp` (schéma `x.ml` sans le patch). Mesurer wireshark.
- **Alignement OCaml** : `bin/x.ml`, `bin/machine.ml`, `bin/simulation_level.ml`.

### 2026-07-10 — PoC C implémenté dans `pupisto.tester.sh` (mode `-X` réécrit)

Le mode `-X/--display` (ex-série cassé) est **entièrement réécrit sur l'architecture C**. Chaîne :

```
GUEST racine : xeyes → DISPLAY=:0 → /tmp/.X11-unix/X0  (socket pathname, cross-netns)
                         │  socat (netns mgmt) UNIX-LISTEN:X0,fork → TCP host:6000 via eth42
GUEST mgmt   : eth42 ghostifié (déplacé dans le netns) ───────────┘
HOST         : socat TCP-LISTEN:172.23.K.254:6000,fork → UNIX-CONNECT:/tmp/.X11-unix/X<Djean>
               + xhost +local:  (autorise le client local socat ; révoqué à la sortie)
```

Implémentation (host, dans le script) : réutilise le plumbing tap « K unique » de `-A`
(`net_free_octet`, `net_tap_up`, sudoers `mnt-tap*`) ; lance le socat-pont hôte + `xhost +local:` ;
`make_x11_hostfs` écrit `boot_parameters` (`ip42`, `host_display_ip`) + le patch **`marionnet-relay-x11`**
sourcé par le relay. `cleanup` : tap down + kill socat + `xhost -local:` + rm hostfs. Console en **xterm**
(l'étudiant tape `export DISPLAY=:0 ; xeyes`). Le socat invité est lancé via **`systemd-run --unit=
marionnet-x11-relay`** pour **survivre** à la sortie du service `marionnet-relay` (sinon tué avec son
cgroup). netns **nommé** `marionnet-mgmt` (persiste après le relay ; visible dans `ip netns list` — leak
assumé, masquage pédagogique).

**Volet invité VALIDÉ en autonomie** (rejoué dans `tester-1` réelle, sans écran) : vue racine = `lo`
seul (**eth42 ghostifié**), eth42 présent+UP dans `mgmt`, unité `marionnet-x11-relay` **`active`**, socket
`/tmp/.X11-unix/X0` créé, listener `ss` lié dans le netns mgmt. Restauration + retour SSH OK.

**Reste à valider (écran Jean)** : `./pupisto.tester.sh -X` → xterm, login root/root, `export DISPLAY=:0 ;
xeyes` → fenêtre sur l'écran hôte ; `ip a` sans eth42 ; puis `xeyes & wireshark` (multiplexage natif).
Point d'incertitude unique = **auth X** (`xhost +local:` doit autoriser le client Unix du socat ; sinon
`xhost +`). Débit wireshark à observer. `bash -n` OK, mode `-X` autonome-testé côté invité.

### 2026-07-10 — Résultat visuel : C ✅, mais wireshark crash = bug noyau UML (orthogonal)

- **`xeyes` s'affiche sur l'écran hôte** (Jean) ⇒ **architecture C VALIDÉE bout-en-bout** : transport X11
  par netns+eth42 fonctionnel, eth42 ghostifié. `xhost +local:` a suffi (pas besoin de `xhost +`).
- **`wireshark` crash** (au 1er lancement la VM entière tombait ; avec `QT_X11_NO_MITSHM=1` seul dumpcap
  segfault, la VM survit). Signature console (Jean) :
  `BUG: Bad page map in process dumpcap  … file:PACKET fault:0x0 mmap:sock_mmap` (répété sur des pages
  `0x408f9000…`, index croissants) puis `BUG: Bad rss-counter state … MM_ANONPAGES val:-20` → `Segmentation
  fault`. ⇒ le fault est sur le **mmap d'une socket `AF_PACKET`** = le ring `PACKET_MMAP`/TPACKET de libpcap.
- **Écarté par tests** : (a) architecture C/display (xeyes OK) ; (b) MIT-SHM (`QT_X11_NO_MITSHM=1` ne
  l'empêche pas) ; (c) epoll/mprotect `ENOSYS` (les deux marchent : `epoll.poll(0)`→`[]`, `mprotect`→`ret 0`) ;
  (d) mémoire (même crash à `-m 2G`) ; (e) **dumpcap CLI seul** — repro tenté en **5 configs headless sous
  `-A`** (`dumpcap -i eth42 -w f` 98k paquets ; `-i eth42 -w -` pipe 155k ; `-i any` ; `-i lo`) → **0 crash,
  VM survit**.
- **Conclusion** : bug **mémoire du noyau UML 6.12.95** sur le ring AF_PACKET mmap, **non déterministe**,
  déclenché par le pattern mémoire **concurrent** Qt(wireshark)+dumpcap (pas par la capture seule). **Même
  famille** que le flake noyau déjà suivi (`mprotect Error 38`, `epoll EPERM`). ⇒ **chantier noyau**, pas C.
  **Bloque la capture live wireshark** (comme le kernel bloque vwifi). Stopgap : capture **offline**
  (`tcpdump -w f.pcap` puis `wireshark f.pcap` — pas d'AF_PACKET dans le GUI).
- **Hygiène opérationnelle** : incident — un nettoyage `ip link del mnt-tap*` **en masse** a supprimé la
  tap d'une session `-X` VIVANTE de Jean (irréversible à chaud : UML garde un fd périmé). Règle : ne
  supprimer une tap qu'après avoir vérifié qu'aucun UML `linux` ne la référence (motif `pgrep` qui
  n'auto-matche pas la ligne de commande courante).

## 2026-07-10 — Étendre la ghostification : cacher aussi le socat X11 et le service ssh ?

Question de Jean, une fois l'archi C en place (eth42 caché dans le netns `marionnet-mgmt`) :
peut-on **cacher (1) le processus** `socat UNIX-LISTEN:/tmp/.X11-unix/X0,fork,mode=0777
TCP:172.23.K.254:6000` et **(2) le service `ssh.service`** (pour forcer les étudiants à le lancer) ?

**Code vérifié** : le socat est lancé par `systemd-run --collect --unit=marionnet-x11-relay
ip netns exec marionnet-mgmt socat …` (`pupisto.tester.sh` ~445) → il tourne dans le **netns mgmt**
(pour joindre `172.23.K.254` via eth42) mais dans le **PID namespace racine**. `ssh.service` est une
unité native (openssh-server) tirée par `multi-user.target.wants`.

### (2) ssh — DÉJÀ obtenu par « machine nue », rien à coder

`prevent_non_vital_services_from_starting` (`pupisto.debian.sh` ~888) applique une **whitelist stricte**
`KEEP_ENABLED="marionnet-relay"`. `ssh.service` n'y est pas → **retiré par PASS 1** (balayage des
`*.target.wants`). Conséquences :
- **OFF au boot** ✓ ; **`systemctl start ssh` fonctionne** (le `start` est indépendant de l'activation
  `wants`/`enable`). C'est exactement « forcer l'étudiant à le lancer ».
- Ne PAS rendre l'unité *invisible* de `systemctl` : anti-pédagogique — l'étudiant doit pouvoir
  `status`/`start`/`enable` l'unité pour **apprendre systemd**. « Désactivé au boot » ≠ « caché ».
- **À vérifier au boot-test** : qu'aucun **`ssh.socket`** (activation à la connexion) ne subsiste dans
  un `*.target.wants` — le balayage multi-target devrait aussi le retirer, à confirmer.
- Le `-A` du tester relance sshd dans son **COW jetable** → n'affecte pas l'image livrée.

### (1) socat — possible mais ASYMÉTRIQUE et coûteux : reco = accepter la visibilité

Point dur : le masquage réseau par netns marche grâce à une **asymétrie de vue que les processus
n'ont pas**.
- `ip a` ne liste **que** les interfaces du netns courant ; l'étudiant est dans le netns racine qui ne
  voit pas `mgmt` → masquage « gratuit ».
- Les **PID namespaces sont l'inverse** : un PID ns enfant est **visible du parent**. L'étudiant est
  root dans le PID ns racine → il voit tout processus, y compris ceux d'un PID ns enfant (avec un PID
  racine). **Mettre le socat dans un PID ns ne le cache donc pas** ; le kernel l'expose toujours dans le
  `/proc` racine.
- Reproduire l'asymétrie exige de **confiner l'étudiant** (shell de login dans un PID+mount ns restreint,
  `/proc` re-monté) et de lancer le socat **hors** de ce ns. C'est l'**inverse** de « cacher dans un ns
  annexe » (= « enfermer l'étudiant »), un changement d'archi lourd + **friction pédagogique** (altère
  `ps`/`top`/`/proc`/`mount`, donc les TP système). Rejoint l'**idée n°1 (rootless/user-ns)** de Jean,
  appliquée dans la guest → **chantier séparé**.

Options réalistes :

| Option | Cache du root étudiant ? | Coût |
|---|---|---|
| **Accepter la visibilité** (reco) | non | nul ; gêne péda faible (un `socat` dans `ps` ≠ interface parasite d'un TP réseau) |
| `hidepid=2` sur `/proc` | non si étudiant root (cas typique) | faible mais **inefficace** vs root |
| Renommer/déguiser (`comm`) | cosmétique (args révèlent) | faible / trompeur |
| Confiner l'étudiant (PID+mount ns) | **oui** | lourd + casse des TP système |

**Décision** : le besoin du netns était de ne pas polluer `ip a` en **TP réseau** — ce qu'un processus
socat ne fait pas. On **n'essaie pas** de cacher le socat du root ; le confinement de l'étudiant est un
vrai chantier (idée n°1), à traiter séparément s'il devient un objectif.
