# Rapport final — chantier `marionnet-daemon-elimination` : affichage X11 des invités via eth42

> Rapport de clôture, 2026-07-17. Destiné à un développeur qui n'a pas suivi le chantier :
> explique, en se limitant au strict nécessaire, **qui avait/a le privilège** de créer
> l'interface hôte `eth42` (la tap `mtap*`) et **comment le trafic X11 la traverse**, avant et
> après l'élimination de `marionnet-daemon`. Détail épisode par épisode, décisions et POC :
> `docs/daemon-elimination-study.md` (ce rapport n'en est pas un résumé — il répond à une
> question précise, avec des diagrammes).

## 1. Objet et portée

Une machine ou un routeur virtuel Marionnet est un processus UML qui, en plus de ses
interfaces réseau simulées (hublets vde), reçoit toujours une interface **eth42** reliée à
l'hôte : c'est par elle que passent (a) l'affichage graphique de l'invité (serveur X de l'hôte,
invité→hôte) et (b) les terminaux quagga des routeurs (telnet hôte→invité). Créer cette
interface côté hôte — un tap Linux — exige un privilège que le processus GUI, lancé par un
utilisateur ordinaire, n'a pas nativement. Ce rapport documente **comment ce privilège est
obtenu**, avant et après ce chantier ; le reste de la chaîne (négociation X11, `bin/x.ml`,
telnet quagga) est **inchangé** et n'est décrit ici que pour situer le tap dans le flux complet.

**Hors périmètre** (à ne pas confondre) : le mot « ghost » désigne aussi, **côté invité**, le
choix entre deux mécanismes de redirection réseau — `ghostification="ethghost"` (historique) ou
`"netns"` (relay Debian 13 natif) — piloté par le paramètre `.conf` du filesystem
(`bin/simulation_level.ml:827,1269-1273`). C'est un axe **indépendant**, propriété du chantier
`marionnet-kernel-rootfs` (`docs/kernel-rootfs-refresh.md`), **non touché** par
`marionnet-daemon-elimination`. Ce rapport ne traite que le côté **hôte** : qui crée la tap.

## 2. Le canal eth42, en une phrase

Bidirectionnel, sur le réseau privé `172.23.0.0/16` :

- **invité → hôte (X11)** : l'invité se connecte à `172.23.0.254:600x` (adresse hôte fixe,
  portée par le tap) ; `bin/x.ml` y relaie le trafic vers le serveur X réel de l'utilisateur
  (`/tmp/.X11-unix/X?`) ;
- **hôte → invité (telnet quagga)** : la GUI ouvre `telnet <ip42> <port>` vers l'adresse propre
  de chaque routeur (`172.23.<n>.<m>`, une par VM), routée via le tap par une route
  host-specific.

Ce contrat (adresses, route, nom d'interface `eth42=tuntap,<tap>,<mac>,172.23.0.254` passé à
UML) est **identique avant et après** ce chantier — c'est une contrainte actée dès l'étude
(préserver les vieilles images invitées).

## 3. AVANT — `marionnet-daemon` : un service root permanent

Un second exécutable, `marionnet-daemon.native`, tournait **en permanence** sur l'hôte (lancé au
boot par un script SysV, indépendamment de Marionnet), root, à l'écoute sur une socket Unix
`/tmp/my-marionnet-daemon-socket` en mode **0666** — accessible à *tout compte local*. La GUI lui
parlait un protocole ad hoc (`AnyTap`/`AnySocketTap`, `bin/daemon_language.ml`) ; le daemon
exécutait les commandes privilégiées avec des outils aujourd'hui obsolètes (`tunctl`,
`ifconfig`, `route` — net-tools/uml-utilities) et assurait le ramasse-miettes des taps orphelins
par un keep-alive/timeout (client silencieux > 120 s → ressources détruites).

```
                                 HOST
----------------------------------------------------------------------
+--------------------------------------------------------------------+
|                      marionnet-daemon.native                       |
|              (root, ALWAYS running, launched at boot)              |
|                                                                      |
|     AF_UNIX socket /tmp/my-marionnet-daemon-socket, mode 0666      |
|       protocol: AnyTap / AnySocketTap  (daemon_language.ml)        |
|                                                                      |
|                         tunctl -u UID -t T                         |
|                   ifconfig T 172.23.0.254/32 up                    |
|                         route add <ip42> T                         |
+--------------------------------------------------------------------+
                 ^
                 | AF_UNIX request: AnyTap(uid, ip42)
                 |
+--------------------------------------------------------------------+
|             marionnet.native  (GUI, unprivileged user)             |
|        simulation_level.ml -> Daemon_client.ask_the_server         |
+--------------------------------------------------------------------+
                              |
                              v  creates
                tap "tapN"  (persistent, owned by UID)
                ^
                | eth42=tuntap,tapN,MAC,172.23.0.254
+--------------------------------------------------------------------+
|                  UML process  (machine or router)                  |
+--------------------------------------------------------------------+
v  X11 (guest->host)                                  (host->guest)  ^
+--------------------------------+  +--------------------------------+
|            bin/x.ml            |  |         bin/router.ml          |
| (in-process relay, UNCHANGED)  |  |  (quagga terminal, UNCHANGED)  |
|   listens 172.23.0.254:600x    |  |      telnet <ip42> <port>      |
|      -> /tmp/.X11-unix/X?      |  +--------------------------------+
+--------------------------------+
```

Points notables :

- le daemon est l'**unique** point root de toute l'exécution ; aucune autre interface (les
  hublets vde entre composants virtuels, `world_gateway`/slirpvde) n'exige de privilège ;
- UML lui-même s'attache à la tap **sans privilège** (le tap est persistant, `tunctl -u`
  l'a rendu owned par l'utilisateur — c'est déjà le cas avant ce chantier) ; seule la
  **création** de la tap exigeait root ;
- la socket 0666 offrait ces créations de taps, sans distinction, à *tout compte local de la
  machine* — surface d'attaque large pour un service permanent.

## 4. MAINTENANT — `Tap_provider` : pas de service, un privilège ponctuel

Le daemon a été supprimé (épisodes 1-4 du chantier). Le processus GUI crée lui-même la tap, au
moment où il en a besoin, en s'élevant ponctuellement via `sudo -n ip …` (iproute2), autorisé
par une règle sudoers **scopée** (`bin/scripts/marionnet-sudoers.sh`, source unique du texte de
la règle, installée par `make install-final-as-root` ou `marionnet-sudoers.sh install`). Le
contrat réseau posé sur la tap est **exactement le même** — seule la syntaxe des commandes
change (net-tools obsolète → iproute2) :

```
tunctl -u UID -t NAME                                -> ip tuntap add dev NAME mode tap user USER
ifconfig NAME 172.23.0.254 netmask 255.255.255.255 up -> ip addr add 172.23.0.254/32 dev NAME
                                                          ip link set NAME up
route add IP42 NAME                                   -> ip route add IP42/32 dev NAME
ifconfig NAME down && tunctl -d NAME                  -> ip link del NAME
```

```
                                 HOST
----------------------------------------------------------------------
+--------------------------------------------------------------------+
| marionnet.native  (GUI, unprivileged user -- NO permanent service) |
|   simulation_level.ml -> Tap_provider.make_eth42_tap ~uid ~ip42    |
|                                                                      |
|           sudo -n ip tuntap add dev T mode tap user USER           |
|             sudo -n ip addr add 172.23.0.254/32 dev T              |
|                      sudo -n ip link set T up                      |
|                sudo -n ip route add <ip42>/32 dev T                |
|            (sudoers rule scoped to "ip ... mtap*", see             |
|                  bin/scripts/marionnet-sudoers.sh)                 |
+--------------------------------------------------------------------+
                              |
                              v  creates
          tap "mtap<pid>-<seq>"  (persistent, owned by UID)
                ^
                | eth42=tuntap,<tap>,MAC,172.23.0.254
+--------------------------------------------------------------------+
|                  UML process  (machine or router)                  |
+--------------------------------------------------------------------+
v  X11 (guest->host)                                  (host->guest)  ^
+--------------------------------+  +--------------------------------+
|            bin/x.ml            |  |         bin/router.ml          |
| (in-process relay, UNCHANGED)  |  |  (quagga terminal, UNCHANGED)  |
|   listens 172.23.0.254:600x    |  |      telnet <ip42> <port>      |
|      -> /tmp/.X11-unix/X?      |  +--------------------------------+
+--------------------------------+

  GC: purge_orphan_taps() at start-up (dead process -> tap removed)
  + at_exit guarded by owner_pid (episode 6 fix: a forked child of
    bin/x.ml's relay must NOT destroy a tap of the still-live VM)
```

Un point du contrat a dû être **corrigé pendant le chantier** (épisode 6) : `bin/x.ml` sert
chaque connexion X11 avec un **enfant forké** (`process_forking_loop` d'ocamlbricks) ; comme
`at_exit` s'exécute aussi dans les enfants forkés, le handler de nettoyage des taps de
`Tap_provider` s'exécutait *aussi* à la fermeture d'une simple fenêtre graphique invitée, et
détruisait la tap eth42 d'une VM encore vivante. Le daemon n'avait pas ce défaut (il ne
détruisait que sur message explicite). Correctif : le handler `at_exit` de `tap_provider.ml`
est gardé par un `owner_pid` capturé dans le processus principal avant tout fork — il ne fait
rien s'il s'exécute ailleurs.

## 5. Ce qui n'a pas changé

- le contrat réseau exact posé sur la tap (adresse `172.23.0.254/32`, route host-specific,
  syntaxe `eth42=tuntap,<tap>,<mac>,172.23.0.254` passée à UML) ;
- `bin/x.ml` (le relais X11 invité→hôte, ses 5 cas selon la topologie de `$DISPLAY`) : intouché ;
- le telnet quagga hôte→invité (`bin/router.ml`) : intouché ;
- le fait qu'UML s'attache à la tap sans privilège une fois celle-ci créée et owned ;
- le mode dégradé : si le mécanisme privilégié échoue (règle sudoers absente, comme avant
  l'échec de connexion au daemon), la VM démarre **sans** eth42 plutôt que d'échouer totalement.

## 6. Comparaison

| | Avant (`marionnet-daemon`) | Maintenant (`Tap_provider`) |
|---|---|---|
| Service permanent | oui, root, lancé au boot (SysV) | **aucun** |
| Canal de privilège | socket Unix `0666` | règle sudoers scopée (`sudo -n ip …`) |
| Qui peut déclencher une création de tap | **tout compte local** de la machine | l'utilisateur/groupe couvert par la règle sudoers (opt-in admin) |
| Outils privilégiés | `tunctl`, `ifconfig`, `route` (obsolètes) | `ip tuntap/addr/route/link` (iproute2) |
| GC des orphelins | keep-alive 24 s / timeout 120 s (thread daemon) | `purge_orphan_taps` au démarrage (process mort → tap détruite) + `at_exit` gardé par pid |
| Fichiers clés | `bin/{marionnet_daemon,daemon_language,daemon_client,daemon_parameters}.ml`, `useful-scripts/etc_init.d_marionnet-daemon` — **supprimés** | `bin/tap_provider.ml(i)`, `bin/scripts/marionnet-sudoers.sh` |
| Doc admin | — | `docs/admin-taps-and-bridge.md` |

## 7. Ghostification côté invité — hors périmètre (rappel)

Le choix `ethghost`/`netns` (`?ghostification`, `bin/simulation_level.ml:827`) détermine **côté
invité** comment le filesystem redirige son accès réseau vers l'hôte (pertinent surtout pour le
relay Debian 13 natif du chantier `marionnet-kernel-rootfs`). Il ne concerne ni la création de
la tap côté hôte, ni `Tap_provider`, ni le daemon — un invité `ethghost` et un invité `netns`
utilisent la **même** tap `eth42` créée exactement comme décrit ci-dessus. Voir
`docs/kernel-rootfs-refresh.md` pour ce mécanisme.

## 8. Option différée : netns de session (épisode 5)

Une architecture « zéro sudo » a été étudiée (network namespace de session, `unshare -Urn`
autour du processus GUI entier) et prouvée viable par un POC système léger (§12 de
`docs/daemon-elimination-study.md`) : elle éliminerait la règle sudoers pour eth42 (GC parfait
par mort du namespace). Elle a été **délibérément différée** : sa seule motivation est le
« zéro sudo » d'une salle de TP — contexte secondaire, non concrétisé — et elle introduit une
charge permanente (profil AppArmor à maintenir, obligatoire sur Ubuntu ≥ 23.10) ainsi que deux
points durs non résolus (le bridge de `world_bridge` vit dans le namespace racine ; le cas
X-en-TCP de `bin/x.ml` sort du namespace). L'étude reste disponible et à jour si ce besoin se
matérialise un jour.

## 9. État du chantier

**Clos.** L'étape prioritaire (poste personnel, sudo disponible) est livrée, prouvée contre le
noyau et validée par un run GUI complet (X11 invité, destruction des taps). Le daemon
n'existe plus dans le dépôt. L'option netns (§8) reste documentée, non ouverte. Détail complet
épisode par épisode, POC, pièges rencontrés : `docs/daemon-elimination-study.md`.
