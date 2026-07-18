# Chantier `bug-critique-crash-host` — crash de l'hôte à la terminaison des composants

> Bug **critique, rare et non reproductible** : l'exécution de Marionnet provoque parfois un
> crash de la machine physique (**reboot spontané**) ou du conteneur Docker (**arrêt net**)
> qui l'héberge. Corrélation observée : la terminaison de composants (shutdown/poweroff d'un
> composant, « terminer tout », fermeture du projet). Ce document est le rapport d'audit
> initial (épisode 0) : causes candidates classées et **vérifiées sur le code**, matrice
> symptôme ↔ cause, checklist de collecte post-mortem, pistes de correctifs.

## 1. Symptômes et contexte

- Crashs **très rares**, jamais reproduits à la demande ; souvent (pas exclusivement) au
  moment d'une terminaison.
- Deux formes observées : le **conteneur Docker s'arrête net** ; la **machine physique
  redémarre spontanément**.
- **Aucune preuve post-mortem** (journaux noyau, `docker inspect`) n'a été collectée à ce
  jour → aucune cause ne peut être *prouvée* ; ce rapport classe des candidates par
  plausibilité et fournit la checklist pour trancher au prochain incident (§ 4).
- Contexte important : l'image Docker qui exécute Marionnet (§ C4) embarque **l'ancienne
  version avec `marionnet-daemon` root**, éliminée du code actuel (chantier
  `marionnet-daemon-elimination`, clos 2026-07-17). Les crashs passés en conteneur ne
  condamnent donc pas nécessairement le code actuel du dépôt.

Audit réalisé le 2026-07-18 : 3 balayages parallèles (sites de kill ; ressources hôte ;
cycle de vie des processus), suivis d'une **vérification manuelle ligne à ligne** de chaque
point retenu ci-dessous.

## 2. Causes candidates (classées)

### C1 — SIGKILL différés vers des PID potentiellement recyclés (code actuel) — VÉRIFIÉ

Le code ne contient **aucun kill de groupe** (pas de PID négatif, pas de `kill 0` ; les PID
proviennent de `Unix.create_process` ou de scans `/proc`, toujours > 0 et gardés par
`match !pid with Some p`). En revanche, **trois sites tuent sur la foi d'un PID capturé
longtemps avant, sans revérifier l'identité du processus** (un PID libéré peut être
réattribué par le noyau à un processus arbitraire) :

1. **`bin/descendants_monitor.ml:31-61`** — un thread accumule toutes les 4 s l'historique
   `(pid, starttime)` des descendants. Sa « garbage collection » (ligne 38) filtre sur
   `is_process_alive pid` (= `kill(pid, 0)`) **sans comparer le `starttime`** pourtant
   stocké : une entrée dont le PID a été recyclé par un processus tiers est crue vivante et
   **reste dans l'ensemble indéfiniment**. À la sortie (`at_exit`,
   `bin/marionnet.ml:435-451`), `kill_process_set` envoie **SIGKILL à tout l'historique**
   sans aucune revérification. Fenêtre de recyclage : **toute la durée de la session**.
2. **`bin/simulation_level.ml:1092-1116`** (`uml_process#gracefully_terminate`) — la liste
   `descendants` est capturée à T+0 (ligne 1100), puis un thread *fire-and-forget* attend
   30 s et, **quoi qu'il se soit passé entre-temps**, envoie SIGKILL à cette liste figée
   (ligne 1113). Le garde `is_process_alive current_pid` (ligne 1109) ne protège que la
   branche `kill_descendants_then_myself` — et souffre lui-même du recyclage : si
   `current_pid` a été réattribué, on tue le nouveau porteur **et sa descendance**. Ce
   chemin est emprunté à **chaque arrêt gracieux** d'une machine/routeur ; enchaîner
   « fermer le projet » puis « ouvrir/relancer » en moins de 30 s expose les nouveaux
   processus aux SIGKILL différés de l'ancien projet.
3. **`lib/STRUCTURES/future.ml:415-430`** (`Control.make`, utilisé par les relais X11 pts,
   `bin/machine.ml:790-808`) — kill par défaut = double SIGKILL sur le PID capturé au fork ;
   seul garde : anti-suicide (`pid = my_pid`). Fenêtre plus courte, patron identique.

Aggravant transverse : **aucun `setsid`/`setpgid` dans `bin/` ni `lib/`** (vérifié) — tous
les processus (UML, vde_switch, xterm…) restent dans le groupe de processus de Marionnet,
sans cloisonnement, et le commentaire de `bin/marionnet.ml:400-404` documente déjà des
SIGTERM parasites remontant par ce couplage.

**Pouvoir explicatif** : en conteneur, le churn de PID est élevé (UML, xterms, relais) et
l'espace PID partagé avec la chaîne vitale du conteneur (`tini` → `ws_startup.sh` → VNC) :
un SIGKILL sur PID recyclé peut tuer un maillon de cette chaîne → `tini` (PID 1) se termine
→ **le conteneur s'arrête net**. Hors conteneur : peut tuer un processus quelconque de
l'utilisateur (session X…), mais **ne peut pas expliquer un reboot**.

### C2 — Épuisement mémoire hôte (OOM) — VÉRIFIÉ

- **Aucun contrôle de la RAM cumulée** : `mem=` par VM va jusqu'à `memory_max = 1024` Mo
  (`bin/machine.ml:57-61`, « In order to test with selinux ») ; aucune comparaison de la
  somme avec `MemAvailable` (aucune occurrence dans `bin/`), aucun `setrlimit`.
- **Swap invité de 1 Gio par VM** (`bin/simulation_level.ml:1016-1028`, sparse à la
  création) + **fichiers COW** non bornés, écrits dans le répertoire temporaire.
- **Le répertoire temporaire peut être un tmpfs (= RAM) sans aucune vérification de
  capacité** : la cascade `$MARIONNET_TMPDIR → $TMPDIR → /tmp → …`
  (`bin/marionnet.ml:224-274`) ne teste que droits + support sparse, et la liste blanche
  inclut explicitement `tmpfs` (`bin/scripts/can-directory-host-sparse-files.sh:40`,
  assumé dans `etc/marionnet.conf:79-85`). Sur un hôte avec `/tmp` en tmpfs, chaque page
  réellement écrite (COW, swap invité effectivement utilisé) consomme de la RAM hôte.
- Côté conteneur audité : `docker run` **sans limite mémoire** (`Makefile.20-04`) → pas
  d'OOM cgroup dédié ; une surconsommation devient un **OOM global de l'hôte**, dont le
  killer peut faucher n'importe quoi — y compris `tini`/la chaîne du conteneur (le
  conteneur « s'arrête net » avec `OOMKilled=false` dans `docker inspect` !) ou un
  processus critique de l'hôte. (`/tmp` du conteneur est en overlayfs — `OPTION_TMP`
  commentée — donc sur disque ; `/dev/shm` est un tmpfs de 256 Mo.)

**Pouvoir explicatif** : arrêt net du conteneur (via OOM hôte) ; contribution indirecte au
crash machine (thrashing extrême → gel perçu, watchdog) ; un reboot *direct* par OOM
supposerait `vm.panic_on_oom` non standard.

### C3 — Bug du noyau hôte déclenché par UML (ptrace) — hypothèse, non démontrable par le code

UML en mode SKAS fait un usage intensif et atypique de `ptrace` ; la terminaison provoque
des **rafales de SIGKILL sur des arbres entiers de processus ptracés**
(`lib/SHELL/linux.ml:307-342`, retraits parallèles). Un espace utilisateur non privilégié ne
peut pas rebooter une machine : un **reboot spontané** implique un panic noyau ou un
watchdog. C'est la seule candidate qui explique *naturellement* ce symptôme, y compris sur
noyaux 6.1.x — d'autant que le chantier `kernel-rootfs` a déjà mis en évidence des bugs
noyau côté UML (`Bad page map`/`PACKET_MMAP`, flake mprotect/epoll). Seule la collecte § 4
(trace `panic`/`Oops` du boot précédent) peut confirmer/infirmer.

### C4 — Ancien `marionnet-daemon` root, encore déployé dans l'image Docker — VÉRIFIÉ (image)

L'image désignée (`~/WORKING/MARIONUM/MARIOLINE/marioline.next/docker_images/`
`ubuntu-vnc-xfce-g3-marionnet`, `Dockerfile.xfce.20-04` — seule image embarquant Marionnet)
installe Marionnet via `marionnet_from_scratch.20-04.sh`, c'est-à-dire **l'ancienne version
avec le daemon root** :

- init script généré avec `mknod /dev/net/tun` + **`chmod a+rw /dev/net/tun`** et un
  `killall` par **motif de nom** : `ps -u 0 … awk '/marionnet-daemon/' … kill -9`
  (`marionnet_from_scratch.20-04.sh:1240-1245`) ;
- conteneur lancé avec **`--cap-add=ALL`** (`Makefile.20-04:155`), sans user-namespace →
  root du conteneur quasi omnipotent (CAP_SYS_ADMIN…), PID 1 = `sudo → tini -s`
  (`ws_entrypoint.sh:101`).

Ce vecteur (opérations réseau root arbitraires, kills root par pattern) a **disparu du code
actuel** (remplacé par `Tap_provider`, sudo scoped) mais était présent partout où les crashs
ont été observés jusqu'ici. Conséquence méthodologique : **reconstruire l'image sur le
Marionnet post-daemon-elimination avant de tirer des statistiques** sur le code actuel.

### C5 — (annexe : gel de l'appli, pas crash hôte) mutation GTK hors thread principal à la fermeture

`state.ml:352-355` (`close_project` appelé depuis le thread GTK) détache un thread qui finit
par muter des `GtkTreeStore` **hors thread GTK et sans délégation `gMain_actor`**
(`user_level.ml:1592` → `treeview_history.ml:161-182` `remove_device_tree` →
`treeview.ml:1407-1427` `remove_subtree`), en violation de la discipline documentée
(`docs/ARCHITECTURE.md` § Concurrence). C'est l'explication la plus plausible du « rare
deadlock » de 2023 (commit `0a68ad6`, logs `HERE0..HERE6` ajoutés précisément dans
`remove_device_tree`, jamais suivi d'un correctif structurel). À corriger dans ce chantier,
mais ce défaut gèle Marionnet — il ne peut pas crasher l'hôte.

## 3. Matrice symptôme ↔ cause

| Symptôme | C1 kill/PID recyclé | C2 OOM | C3 bug noyau (UML) | C4 daemon root (image) |
|---|---|---|---|---|
| Conteneur s'arrête net | **++** (chaîne tini tuée) | **++** (OOM hôte tue tini, `OOMKilled=false`) | – | + (kill -9 root par pattern) |
| Reboot machine physique | – | + (indirect : thrashing/watchdog) | **++** (panic) | + (root, indirect) |
| Corrélation « à la terminaison » | **++** (at_exit, thread 30 s) | + (pic I/O/CPU aux arrêts groupés) | **++** (rafales SIGKILL sur ptracés) | + |

Lecture : aucun candidat unique ne couvre les deux symptômes ; l'hypothèse de travail est
**C1/C2 pour le conteneur, C3 pour le reboot physique**, avec C4 comme facteur confondant
historique.

## 4. Checklist de collecte au prochain crash (à exécuter AVANT toute analyse)

**Machine physique, après le reboot :**
```bash
journalctl -b -1 -k | grep -iE 'panic|oops|BUG:|watchdog|Out of memory|oom' | tail -50
journalctl -b -1 -e            # dernières lignes du boot précédent (gel progressif ?)
ls /sys/fs/pstore/             # traces de panic persistées, si pstore actif
```
Si `journalctl -b -1` est vide (logs non persistés) : activer `Storage=persistent` dans
`journald.conf` — sans cela, un reboot ne laissera jamais de preuve.

**Conteneur Docker :**
```bash
docker inspect <c> --format '{{.State.ExitCode}} {{.State.OOMKilled}} {{.State.FinishedAt}}'
docker logs --tail 100 <c>
journalctl -k --since '<FinishedAt> - 5 min' | grep -iE 'oom|killed process'   # sur l'HÔTE
```
NB : `ExitCode` 137 + `OOMKilled=false` = quelqu'un (OOM hôte ou kill erratique) a tué la
chaîne PID 1 — signature compatible C1/C2.

**Dans les deux cas :** noter le projet ouvert (nombre de VM, `mem=` de chacune), l'action
en cours (terminer tout ? fermeture ?), `df -h` du répertoire temporaire de Marionnet et
`free -h` en régime de croisière, et récupérer `~/.marionnet/marionnet.log`.

## 5. Pistes de correctifs (épisodes futurs, ordre suggéré)

1. **C1 — identité des processus** — **FAIT (épisode 1)** : introduire dans `lib/SHELL/linux.ml` un
   `is_same_process ~pid ~starttime` (relire `/proc/<pid>/stat`) et l'exiger **avant tout
   kill différé** ; corriger la GC de `descendants_monitor.ml` (vivant **et** même
   `starttime`, sinon retirer l'entrée) ; faire de même dans `kill_process_set`.
2. **C1 — thread 30 s** — **FAIT (épisode 1)** : à l'échéance, revérifier l'identité
   (pid, starttime) de `current_pid` et de chaque descendant capturé à T+0 avant tout
   SIGKILL — une terminaison gracieuse réussie ne laisse plus rien à tuer. Reste un TOCTOU
   résiduel (microsecondes) entre le test et le kill, irréductible sans `pidfd_send_signal`
   (stub C). Le site 3 (`future.ml` `Control.make`) est **FAIT (épisode 2)** : `starttime`
   capturé à la création du contrôle, identité revérifiée avant chacun des deux SIGKILL du
   kill par défaut (lecteur `/proc` local à `future.ml` : le cycle de modules
   Linux → Forest → Future interdit d'y réutiliser `Linux.Process.is_same_process`).
3. **C1 — cloisonnement** : étudier `setsid` au spawn (groupe de processus par composant),
   ce qui rendrait les kills bornables au groupe ; mesurer l'impact (xterm, mconsole, relais).
4. **C2 — garde-fous ressources** : au démarrage d'une VM, comparer la somme des `mem=`
   (+ marge) à `MemAvailable` et avertir ; détecter un répertoire temporaire tmpfs et
   avertir/refuser selon la capacité (`df`).
5. **C4 — image Docker** : reconstruire l'image sur le Marionnet actuel (sans daemon),
   remplacer `--cap-add=ALL` par le minimum (`NET_ADMIN`), envisager une limite mémoire
   explicite (`-m`) pour transformer un OOM hôte diffus en OOM cgroup diagnosticable.
6. **C5 — GTK** : déléguer via `gMain_actor` les mutations treeview atteintes depuis le
   thread de `close_project`.

Chaque correctif devra être suivi d'une période d'observation (le bug étant rare, seule
l'absence prolongée de récidive + la checklist § 4 valident).

## Journal d'avancement

- **2026-07-18 — épisode 0** : officialisation du chantier. Audit initial : 3 balayages
  parallèles (sites kill, ressources hôte, cycle de vie), vérification manuelle de chaque
  point retenu, audit de l'image Docker `ubuntu-vnc-xfce-g3-marionnet` (20-04). Livrables :
  ce rapport (causes C1-C5, matrice, checklist, pistes). Aucun correctif appliqué.
- **2026-07-18 — épisode 1** : correctif C1 « identité des processus » (pistes § 5.1-2).
  Nouveau prédicat `Linux.Process.is_same_process ~pid ~starttime` (`lib/SHELL/linux.ml` +
  `.mli`), exigé avant tout SIGKILL différé : GC et `kill_process_set` de
  `bin/descendants_monitor.ml` (une entrée au PID recyclé est retirée au lieu de rester
  tuable indéfiniment) ; thread 30 s de `uml_process#gracefully_terminate`
  (`bin/simulation_level.ml` : capture de couples (pid, starttime) à T+0, identité
  revérifiée à l'échéance pour la racine et chaque descendant). Vérifié : `dune build` rc 0 ;
  test comportemental du prédicat (vivant→true, starttime falsifié→false, tué+récolté→false).
  Hors périmètre (épisodes futurs) : `future.ml` `Control.make`, setsid, C2/C4/C5 ;
  le bug étant rare, seule l'absence prolongée de récidive validera (piège § 5 in fine).
- **2026-07-18 — épisode 2** : correctif C1 sur le site 3, dernier kill différé sans garde
  (`lib/STRUCTURES/future.ml` `Control.make`, kill par défaut du relais X11 pts —
  `network.ml:1109` `pts_of_stream_server_FORK`, consommé par `machine.ml#stop_pts_relays`).
  `starttime` capturé à la création (PID tout juste forké par l'appelant), identité
  revérifiée avant chacun des deux SIGKILL ; processus illisible à la création → aucun kill
  aveugle. Contrainte découverte : cycle de modules Linux → Forest → Future ⇒ lecteur
  local `proc_starttime` (champ 22 de `/proc/<pid>/stat`, parsing après le dernier `)`)
  au lieu de `Linux.Process.is_same_process`. Vérifié : `dune build` rc 0 ; test
  comportemental sous `strace -e trace=kill` — cible vivante bien tuée (2× SIGKILL),
  **aucun** SIGKILL émis vers un PID mort avant ou après la création du contrôle.
  Les trois sites C1 identifiés à l'épisode 0 sont désormais tous gardés.
