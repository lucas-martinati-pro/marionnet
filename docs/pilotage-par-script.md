# Pilotage de Marionnet par script

> Chantier long `marionnet-pilotage-par-script`.
> Reprise : appliquer le skill `chantier-long` (mémoire `marionnet-pilotage-par-script`,
> `git log --grep="marionnet-pilotage-par-script"`).
>
> **État : épisode 0 (conception) — aucun code n'a encore été écrit.**

---

## 1. Problème et but

Marionnet ne s'utilise aujourd'hui qu'à la main, devant la GUI GTK. Conséquence directe : toute
modification risquée du code (refonte de l'automate d'état des composants, changement dans un
composant réseau, migration de noyau ou de rootfs) ne se teste qu'en cliquant. C'est lent, non
reproductible, et surtout **hors de portée d'un agent** — Claude Code peut modifier `bin/`, il ne
peut pas vérifier que la GUI se comporte encore correctement.

Le but est un **canal de pilotage scriptable**, utilisable *identiquement* par un humain et par un
agent, permettant d'ouvrir ou de créer un projet puis d'exercer les mêmes actions qu'un
utilisateur devant l'écran.

Deux usages, également importants :

- **humain** : rejouer un TP, préparer un scénario de démonstration, reproduire un bug ;
- **agent** : après un changement risqué, exécuter un scénario de non-régression et lire un
  verdict machine, plutôt que d'affirmer « ça devrait marcher ».

Ce document est la conception ; il ne décrit pas du code existant.

---

## 2. Décisions actées (et pourquoi)

| Point | Décision | Pourquoi |
|---|---|---|
| **Ancrage** | **A** — serveur de contrôle *in-process* (cible) ; **C** — générateur de `.mar` + option `-r` (raccourci complémentaire) | A garde la GUI **vivante et observable** pendant le script : c'est précisément ce qui permet de valider une modification risquée. La variante **B** (exécutable *headless* sans GTK) est écartée : `state.ml`, `treeview.ml`, `sketch.ml` et tous les dialogues `where_p4` sont entrelacés avec lablgtk3 ; les découpler serait un refactor massif, sans rapport avec le but |
| **Format** | **JSON asymétrique** : requête = une ligne de texte ; réponse = une ligne JSON | l'OCaml **émet** du JSON (quelques `Printf`, **aucune dépendance ajoutée**) et ne **parse** jamais de format structuré. Les dépendances du projet sont `str unix threads inotify lablgtk3 lablgtk3-extras ocamlbricks` : y ajouter `yojson`/`yaml`/`otoml` se paierait aussi dans le `.deb` et le RPM (chantier `modernisation-installation-marionnet`). Côté client, `jq` est présent sur l'hôte et `bashbricks` fournit 14 helpers `Json_*` — alors qu'il n'a **aucun** `Yaml_*`/`Toml_*` et que `yq`/`tomlq` sont absents. Enfin, un réseau est un **graphe** : mauvais terrain pour TOML |
| **Observabilité** | état **Marionnet** seul (`off` / `on` / `sleeping`) + `wait` par scrutation avec délai de garde | l'automate user-level ne connaît que `NoDevice \| DeviceOff \| DeviceOn \| DeviceSleeping` (`user_level.ml:81-88`). `DeviceOn` signifie « le processus UML est lancé », **pas** « l'invité a fini de booter ». Un vrai signal « invité prêt » supposerait de toucher les images (`marionnet-relay`), donc le chantier `marionnet-kernel-rootfs` : hors périmètre. Le script détecte la disponibilité de l'invité par ses propres moyens (§ 4.7) |
| **Périmètre** | noyau **+ les 4 treeviews** (`ifconfig`, `defects`, `history`, `documents`) | c'est là que vit la configuration réelle d'un TP (adresses IP, défauts réseau) ; un pilotage qui ne les couvrirait pas ne remplacerait pas l'utilisateur humain |
| **Audit `network.ml`** | **complet** (1342 lignes), pas seulement le chemin de contrôle | `Network.Socat.dual_inet_of_stream_server` est **déjà en production** dans `bin/x.ml:274-328` et `bin/machine.ml:841` (relais X11), et `Network.stream_client` dans `bin/switch.ml:491-557`. La valeur de l'audit dépasse donc le scriptage |

---

## 3. Architecture A — serveur de contrôle *in-process*

### 3.1 Principe

Un **thread** serveur, dans le processus `marionnet.native`, écoute sur un socket Unix. Chaque
commande reçue est exécutée **sur le thread GTK** par délégation, puis la réponse JSON est
renvoyée au client.

```
 client (Bash/agent)          marionnet.native
 ┌───────────────┐        ┌──────────────────────────────────┐
 │ mrnctl start  │  unix  │ thread serveur                   │
 │   m1          │◄──────►│   (Network.stream_unix_server    │
 └───────────────┘ socket │    ~no_fork:())                  │
                          │        │ GMain_actor.apply       │
                          │        ▼                         │
                          │ thread GTK ──► st#network#…      │
                          └──────────────────────────────────┘
```

### 3.2 Briques réutilisées (rien à inventer)

| Besoin | Brique existante | Où |
|---|---|---|
| serveur Unix multi-clients | `Network.stream_unix_server` | `lib/STRUCTURES/network.mli:251` |
| exécution sur le thread GTK | `GMain_actor.apply` / `apply_extract` / `future` | `bin/gMain_actor.mli:34-52` |
| garde anti-*deadlock* | `GMain_actor.am_I_the_GTK_main_thread` | `bin/gMain_actor.mli:55` |
| état global (projet, réseau, treeviews) | `st` = `new State.globalState ()` | `bin/marionnet.ml:70` |
| ajout d'un composant sans dialogue | `try_to_add_<kind> network (Xforest.tree)` — les **8** composants | `machine.ml:531`, `router.ml:984`, `switch.ml:331`, `hub.ml:252`, `cable.ml:385`, `cloud.ml:230`, `world_gateway.ml:337`, `world_bridge.ml:250` |
| dispatch de ces 8 procédures | registre `subscribe_a_try_to_add_procedure` / `eval_forest_child` | `bin/user_level.ml:1665-1672` |
| déclaration d'option CLI | `Argv.register_*_option` | `bin/initialization.ml:60-66` |

Le point important est le dernier bloc : **la création programmatique de composants existe déjà**,
c'est le chemin qu'emprunte le chargement d'un `.mar`. Le serveur de contrôle n'a donc pas à
dupliquer la logique de chaque composant : il fabrique un fragment `Xforest.tree` et le confie au
registre.

### 3.3 Contraintes non négociables

1. **`~no_fork:()` est obligatoire.** Le comportement par défaut de `Network.server` est
   `Unix.fork()` **par connexion** (`network.ml:231`) — dans un processus GTK avec des threads et
   des processus UML enfants, ce serait catastrophique. La variante *thread* existe
   (`thread_forking_loop`, `network.ml:255-267`) et c'est celle qu'il faut. ⚠️ C'est aussi celle
   qui contient le défaut `Thread.exit` du § 7.2.
2. **Aucun appel GTK hors du thread principal.** Toute commande passe par `GMain_actor`. Le
   serveur appelle les **méthodes du modèle** (`st#network#…`, `st#new_project`, …), **jamais** les
   *callbacks* de la GUI : ceux-ci ouvrent des dialogues modaux qui bloqueraient indéfiniment.
3. **Opt-in.** Sans l'option de lancement, aucun socket n'est créé : pas d'option, pas de surface
   d'attaque. Le serveur n'est jamais actif par défaut.

### 3.4 Sécurité du canal

`Network.server` fait un `Unix.chmod socketfile 0o777` **inconditionnel** (`network.ml:202`) : le
socket est *world-writable*. Pour un canal qui exécute des actions arbitraires sur la session, ce
serait une faille locale nette.

Solution retenue, **sans modifier ocamlbricks** : créer le socket via
`socketname_in_a_fresh_made_directory ~perm:0o700` (`network.ml:291-304`), dont le paramètre
`~perm` fixe le mode du **répertoire** parent (`FilenameExtra.temp_dir ~perm`). Un répertoire
`0700` rend le mode du socket lui-même sans effet.

Défense en profondeur retenue :

- socket **Unix uniquement** — jamais `inet`, à aucun moment ;
- répertoire parent `0700`, sous `$XDG_RUNTIME_DIR` si disponible ;
- activation explicite par option de lancement ;
- pas d'exécution de code arbitraire dans le protocole (grammaire fermée, § 4) ;
- le défaut `0o777` reste **signalé** dans le rapport d'audit pour rétro-propagation amont.

### 3.5 Insertion dans le code existant

| Fichier | Modification |
|---|---|
| `bin/control_server.ml` | **nouveau** — serveur, dispatch, encodage JSON |
| `bin/initialization.ml` | déclarer `--control-socket[=PATH]` avec `Argv`, à côté de `option_r` (l.65) |
| `bin/marionnet.ml` | démarrer le thread serveur juste avant `main_loop ()` (l.487), donc après `st` (l.70) et après la construction de la fenêtre |
| `bin/dune` | ajouter le module à la stanza GUI (l.177) |

---

## 4. Grammaire des commandes

C'est le **contrat**, et la source de vérité de l'implémentation. Une commande par ligne ; une
réponse JSON par ligne.

### 4.1 Forme générale

```
-> <verbe> [<argument>…] [--option=valeur]…
<- {"ok":true, …}
<- {"ok":false,"error":"<code>","detail":"<texte>"}
```

Codes d'erreur normalisés : `unknown_command`, `bad_argument`, `no_active_project`,
`unknown_node`, `forbidden_transition`, `timeout`, `internal`.

### 4.2 Projet

| Commande | Correspondance modèle |
|---|---|
| `new <fichier>` | `st#new_project ~filename` (`state.ml:322`) |
| `open <fichier>` | `st#open_project_async ~filename` (`state.ml:577`) |
| `save` / `save-as <fichier>` | `st#save_project` (l.764) / `st#save_project_as` (l.771) |
| `close` | `st#close_project` (l.352) |
| `quit` | `st#quit_async` (l.924) |
| `status` | `st#active_project`, `st#runnable_project`, `st#project_already_saved` |

⚠️ `open` est **asynchrone** (retourne un `Thread.t`). La commande doit soit attendre la fin du
thread, soit renvoyer immédiatement et laisser `wait` faire son office — à trancher à l'épisode 4,
la réponse ne devant jamais mentir sur l'état atteint.

### 4.3 Composants

| Commande | Correspondance |
|---|---|
| `add <kind> <nom> [--ports N] [--…]` | fragment `Xforest.tree` → `network#eval_forest_child` (registre `user_level.ml:1665-1672`) |
| `del <nom>` | méthode de suppression du composant |
| `rename <ancien> <nouveau>` | idem |
| `ls [--kind=…] [--can=startup\|shutdown\|suspend\|resume]` | `network#get_node_names` (l.1823), `get_node_list` (l.1537), `get_node_names_that_can_*` (l.1840-1864) |
| `get <nom> [.champ]` | projection du composant |
| `set <nom> <champ> <valeur>` | idem |

`--can=…` est directement fourni par le modèle : `get_node_names_that_can_startup`,
`…_gracefully_shutdown`, `…_suspend`, `…_resume`. Un script peut donc **interroger les transitions
légales** au lieu de les deviner — c'est le moyen le plus sûr de tester l'automate d'état.

### 4.4 Transitions

`start`, `stop`, `suspend`, `resume`, `restart`, `poweroff` sur un composant nommé ;
`start-all`, `shutdown-all`, `poweroff-all` sur le réseau entier
(`st#startup_everything`, `#shutdown_everything`, `#poweroff_everything`, `state.ml:888-905`).

Côté composant : `#startup`, `#suspend`, `#resume`, `#gracefully_shutdown`, `#gracefully_restart`,
`#poweroff` (`user_level.ml:207-238`).

### 4.5 Câbles

`connect <câble> <n1>:<port> <n2>:<port>` et `disconnect <câble>` →
`network#add_cable` (l.1805), `#del_cable_by_name` (l.1811),
`#get_cables_involved_by_node_name` (l.1704).

### 4.6 Treeviews

| Commande | Source |
|---|---|
| `ifconfig <nœud> <port> [--ipv4=… \| --mac=… \| …]` | `Treeview_ifconfig.extract ()` (`state.ml:595`) |
| `defects <nœud> <port> [--loss=… \| --delay=… \| …]` | `Treeview_defects.extract ()` (`state.ml:597`) |
| `history …` | `treeview_history` |
| `documents …` | `treeview_documents` |

Les quatre modèles de données restent à spécifier colonne par colonne à l'épisode 5, en lisant
`treeview_ifconfig.ml`, `treeview_defects.ml`, `treeview_history.ml`, `treeview_documents.ml`.
C'est la partie la plus volumineuse du chantier et la plus exposée à la dérive : le contrat doit
être dérivé du code, pas réinventé.

### 4.7 Synchronisation

```
wait <nom> --state=on|off|sleeping --timeout <secondes>
wait-all --state=… --timeout <secondes>
```

Scrutation de l'état user-level, avec délai de garde. Rappel du § 2 : `--state=on` signifie
« processus UML lancé », **pas** « invité prêt ». Pour l'invité, le script procède hors Marionnet :

```bash
hostfs=$(mrnctl get m1 .hostfs)
timeout 120 inotifywait -e close_write "$hostfs"/…
```

Un répertoire hostfs par machine existe déjà et Marionnet le surveille lui-même par inotify
(`bin/machine.ml:867-934`, `simulation_level.ml:868`) — le canal est là, seule la convention de
« prêt » manque, et elle appartient au chantier `marionnet-kernel-rootfs`.

### 4.8 Porte de sortie

```
forest < fragment.xml
```

Applique un fragment `Xforest` au réseau via le registre `eval_forest_child`. Couvre par
construction tout ce qui est représentable dans un `.mar`, sans multiplier les commandes.

⚠️ **Échec silencieux connu** : `try_to_add_machine` se termine par `with _ -> false`
(`machine.ml:545`), et `user_level.ml:1201` documente explicitement qu'un composant mal formé est
« *silently dropped by the try_to_add_\* machinery* ». Une commande `forest` qui répondrait `ok`
sur un fragment rejeté serait pire qu'inutile : la réponse **doit** rendre compte du nombre
d'éléments réellement intégrés.

---

## 5. Client `mrnctl`

Script Bash, sourçant `bashbricks/bashbricks.sh` par chemin relatif (helpers `Json_*`), transport
`socat` ou `nc`. Script **neuf** : le skill `use-bashbricks` s'applique, ainsi que
`set -euo pipefail`.

```bash
mrnctl open /tmp/lab.mar
mrnctl add machine m1 --ports 2
mrnctl connect c1 m1:0 s1:0
mrnctl start m1
mrnctl wait m1 --state=on --timeout 30
state=$(mrnctl ls | jq -r '.nodes[] | select(.id=="m1") | .state')
mrnctl shutdown-all && mrnctl quit
```

Contraintes :

- **délai de garde systématique** côté client (cf. § 8) ;
- code de retour du script aligné sur le champ `ok` de la réponse, pour que
  `mrnctl … && …` soit fiable ;
- mode `--raw` restituant la ligne JSON telle quelle, pour un agent.

---

## 6. Architecture C — générateur de `.mar`

Voie complémentaire, sans aucune modification d'OCaml : produire le `.mar` hors ligne, puis
lancer avec l'option **`-r`/`--run` qui existe déjà** (`bin/initialization.ml:65`, « *immediately
run the specified project* »).

Utile quand « fabriquer un décor de test » suffit. Insuffisant seul : après le lancement, plus
aucune prise (pas de transition ciblée, pas d'attente d'état, pas de terminaison propre scriptée).
D'où l'ordre : **C fabrique le décor, A le pilote**.

---

## 7. Audit préliminaire de `lib/STRUCTURES/network.ml`

### 7.1 Pourquoi, et pourquoi complet

Le serveur de contrôle reposera entièrement sur ce module. Un défaut y serait attribué à tort au
code de Marionnet, ruinant la valeur de l'outil de test. Un précédent existe : c'est déjà dans
`Network.server` qu'a été trouvé le *port-helper* orphelin squattant `:6000` (fd hérités sans
`CLOEXEC`, chantier `marionnet-retro-compat-kernels-images`).

L'audit est **complet** parce que trois de ses familles sont déjà en production :
`stream_client` (`switch.ml`), `Socat.dual_inet_of_stream_server` (`x.ml`, `machine.ml`).

### 7.2 Défauts déjà établis (amorce, épisode 0) — *traités en 7.5*

1. **`network.ml:264` — `Thread.exit ()`** dans `thread_forking_loop`. Sous OCaml ≥ 5.0,
   `Thread.exit` ne termine plus le thread : c'est le piège documenté en mémoire
   `migration-ocaml5`, et il se trouve **exactement** sur le chemin `~no_fork` qu'emprunterait le
   serveur de contrôle. À corriger **avant** de bâtir dessus.
2. **`network.ml:202` — `Unix.chmod socketfile 0o777`** inconditionnel, sans option de mode
   (cf. § 3.4 pour le contournement retenu).

À examiner de près (pistes, non confirmées) — **toutes tranchées à l'épisode 1**, cf. § 7.5 :

- `network.ml:77` — `let protect f x : unit = try f x with _ -> ()` : exceptions avalées
  → confirmé, mais **acceptable** dans son emploi (finalisation) ; le problème est ailleurs (N1) ;
- `network.ml:227` et `257` — boucles `while true do … done` non gardées → **confirmé (N3)** ;
- `network.ml:302-303` — l'ordre des `ThreadExtra.at_exit` (`rmdir` enregistré avant `unlink`)
  → **piste écartée** : `threadExtra.ml:80` compose les thunks en **LIFO**
  (`fun () -> nouveau (); précédent ()`), donc `unlink` s'exécute bien avant `rmdir`. Reste un
  autre problème, réel, sur ce même point (N12) ;
- `network.ml:266` — `service_socket` en cas d'échec de création de thread → **confirmé (N11)** ;
- absence de plafond au nombre de connexions simultanées → **confirmé (N10)** ;
- sémantique de `#receive` selon le type de socket → **confirmé (N9)**, et un piège plus grave
  découvert sur le canal *ligne* (N7) ;
- `fix_IPV6_ONLY_if_needed`, `bind`, `accept_in_range_non_intr` : robustesse des cas d'erreur
  → **trois défauts confirmés** (N8 pour le motif de précédence, N5, N13).

### 7.3 Méthode (épisode 1)

Lecture intégrale, section par section, avec une grille fixe : **fuites de descripteurs /
`CLOEXEC`** · **exceptions avalées** · **terminaison des threads et des processus fils** ·
**nettoyage des socketfiles et répertoires** · **permissions** · **sémantique de `receive`** ·
**comportement sous OCaml 5**. Livrable : rapport + correctifs **proposés**, non appliqués.

### 7.4 Destination des correctifs (épisode 2)

Dans `lib/` **vendored**. C'est une pratique déjà établie ici (`3641e96` sur `Weaktbl`,
`01ad4c6`/`bc1fc1d` sur `Future.Control.make`, `4f031db`), assumée comme divergence à
rétro-propager vers l'amont bzr — chantier de rétro-propagation déjà identifié par
`migration-ocaml5` (D4).

### 7.5 Résultats de l'audit (épisode 1, 2026-07-29)

Lecture intégrale des 1342 lignes, complétée par `lib/EXTRA/threadExtra.ml` (terminaison des
threads, `at_exit`) et `lib/EXTRA/filenameExtra.ml` (permissions), puis confrontée aux usages réels
dans `bin/` (`x.ml`, `machine.ml`, `switch.ml`). **17 défauts**, dont **4 bloquants** pour
l'épisode 3. Aucun correctif appliqué : c'est l'épisode 2.

#### 7.5.1 Sur le chemin du futur serveur de contrôle

`stream_unix_server ~no_fork:()` → `unix_server` → `server` → `thread_forking_loop`, canal
`stream_channel` en mode ligne.

| # | Lieu | Gravité | Défaut | Correctif proposé |
|---|---|---|---|---|
| **N1** | `429-430` + `475-480` | **haute** | `stream_channel#shutdown` ferme le **même fd jusqu'à quatre fois** : `Unix.close fd` (l.430), puis `close_in in_channel`, `close_out out_channel`, `Unix.close fd` (l.477-479) — trois `close` de trop, chacun sur un numéro de descripteur **déjà libéré**, donc potentiellement **recyclé par un autre thread**. Pire : `close_out` **flushe avant** de fermer, donc peut écrire dans le descripteur de quelqu'un d'autre. Et si `super#shutdown` lève — `Unix.shutdown` renvoie `ENOTCONN` dès que le pair a fermé en premier, cas **normal** —, le `raise (Closing e)` saute les trois lignes suivantes : les canaux stdlib survivent et leur **finaliseur GC** fera le `close` **plus tard**, sur un fd entre-temps recyclé. C'est le motif C1 de `bug-critique-crash-host` (kill différé vers un PID recyclé), transposé aux descripteurs. | Ne pas dériver de canaux stdlib d'un fd qu'on ferme soi-même : ordonner `flush out_channel` → `Unix.shutdown` (toléré-`ENOTCONN`) → **un seul** `Unix.close`, et supprimer `close_in`/`close_out` ; ou, plus radical, ne créer `in_channel`/`out_channel` qu'à la demande (les méthodes `input_*`/`output_*`). |
| **N2** | `258-266` | **haute** | Sur le chemin `~no_fork`, `service_socket` n'obtient **jamais** `CLOEXEC` — le chemin `fork` le pose (l.239), le chemin thread l'oublie. Or Marionnet `exec` en permanence (xterm, UML, vde, port-helper) : chaque connexion de contrôle laisserait un descripteur vivant dans des enfants de longue durée. Précédent exact dans ce dépôt : le *port-helper* orphelin squattant `:6000` (`marionnet-retro-compat-kernels-images`, ép. 3). | `Unix.accept ~cloexec:true` (cf. 7.5.3) : couvre les deux chemins d'un coup. |
| **N3** | `227`, `257` | **haute** | Les deux boucles `while true` n'ont **aucun** garde : `accepting_function` ne rattrape que `EINTR` et emballe tout le reste en `Accepting e`, qui remonte, sort de la boucle et **tue définitivement** le thread serveur. Un `EMFILE` transitoire (limite de descripteurs) ou un `ECONNABORTED` suffit : le canal de contrôle disparaît en silence, la GUI continue de tourner. | Encapsuler le **corps** de la boucle dans un `try … with` : journaliser, fermer `service_socket` si acquis, temporiser brièvement, continuer ; ne sortir que sur fermeture volontaire du `listen_socket`. |
| **N4** | `264` | moyenne | `Thread.exit ()`. La documentation d'OCaml 5.4 est explicite : « *Raise the `Thread.Exit` exception […] unless the thread function handles the exception itself. […] **catch-all exception handlers will be executed*** ». Or `ThreadExtra.create` passe par `create_non_killable`, dont le `with e ->` (`threadExtra.ml:383`) est précisément un *catch-all* : **chaque connexion terminée normalement** produit un `Terminated by uncaught exception: Thread.Exit`, puis un second `Thread.exit ()` (`threadExtra.ml:386`). Le thread meurt bien — la crainte initiale d'une fuite de threads est donc **infirmée** —, mais le journal devient inexploitable pour diagnostiquer Marionnet, ce qui est exactement ce que cet instrument doit permettre. | Supprimer l'appel : la fonction retourne naturellement, `create_non_killable` exécute déjà `final_actions ()` sur le chemin normal. |
| **N5** | `157-164` | moyenne | `bind` : le gestionnaire d'erreur appelle `inet_addr_and_port_of_sockaddr sockaddr`, qui lève `Invalid_argument` sur un `ADDR_UNIX`. Un `bind` unix qui échoue ne produit donc **ni** l'exception `Binding` annoncée, **ni** le message d'erreur réel, mais un `Invalid_argument "Network.inet_addr_of_sockaddr"` trompeur. Cas le plus courant : socketfile résiduel après un arrêt brutal (`EADDRINUSE`). | Brancher sur le domaine avant de composer le message ; toujours lever `Binding e`. |
| **N6** | `202`, `291`, `675` | moyenne | Permissions. `chmod socketfile 0o777` inconditionnel (l.202) ; `?(perm=0o777)` par défaut pour le répertoire (l.291) ; `dgram_channel` refait `chmod 0o777` dans son `initializer` (l.675). Et le mode n'est pas seulement demandé : `FilenameExtra.temp_dir` (`filenameExtra.ml:77-82`) fait `mkdir perm` **puis** `chmod perm` — « *Yes, we insist* » — ce qui **contourne l'umask** : le répertoire est réellement 0777. **La parade du § 3.4 est confirmée valide** : `~perm:0o700` sur le répertoire rend le `chmod 0o777` du socket inoffensif. | Amont : `?socket_perm` (défaut `0o600`) et défaut de `~perm` ramené à `0o700`. Ici : ne **jamais** appeler `socketname_in_a_fresh_made_directory` sans `~perm:0o700`. |
| **N7** | `546-558` | moyenne | Le canal ligne mélange deux mondes sur **le même fd** : `#receive = ch#input_line` lit par le `in_channel` **bufferisé** de la stdlib, tandis que `#peek` (et le `#receive` du canal sous-jacent) lit par `Unix.recv`. Les octets déjà aspirés dans le tampon stdlib sont **invisibles** à `peek`, et tout `#receive` brut intercalé **perd** des données. La stdlib déconseille elle-même d'utiliser conjointement les deux canaux dérivés d'un même descripteur. | Contrainte pour l'épisode 3 : le serveur n'utilise **que** `input_line`/`output_line` — jamais `#receive`, `#send` ni `#peek`. À documenter dans le `.mli` à l'épisode 2. |
| **N8** | `385-390` | basse | Bug de précédence du `;`, identique à celui de `gracefully_restart` (`marionnet-automate-composants`, R4) : dans `(if c then Log.printf …; Unix.setsockopt_int …)`, le `then` ne porte **que** sur le `Log.printf`. `SO_RCVBUF` est donc réécrit **inconditionnellement** à `max_input_size` — 1514 par défaut —, y compris quand le tampon noyau était plus grand : le module **rétrécit** ce qu'il prétend agrandir, sur *chaque* canal créé. Même motif l.170-172 (`fix_IPV6_ONLY_if_needed`), là sans conséquence. | `begin … end` autour des deux branches, aux deux endroits. |
| **N9** | `486` | basse | `#receive` traite `n = 0` — fermeture **propre** du pair — par `failwith "received 0 bytes (peer terminated?)"`, journalisé puis relevé en `Receiving`. Une déconnexion normale de `mrnctl` produira donc une trace d'erreur. | Ne pas changer la sémantique amont (du code en dépend) ; côté serveur de contrôle, traiter `End_of_file`/`Receiving` comme **fin normale** de session. |
| **N10** | `257` | basse | Aucun plafond de connexions simultanées : un thread par connexion, sans borne. `max_pending_requests` (défaut 5) ne limite que le *backlog* d'`accept`, pas les threads vivants. | Compteur de sessions actives ; au-delà d'un seuil (p. ex. 8), répondre une erreur et fermer. |
| **N11** | `266` | basse | Si `ThreadExtra.create` lève (limite de threads atteinte), `service_socket` n'est **pas** fermé et — combiné à N3 — la boucle meurt : le descripteur fuit **et** le serveur disparaît. | Couvert par le `try … with` de N3, avec fermeture de `service_socket` dans le gestionnaire. |
| **N12** | `302-303`, `279` | info | Le nettoyage du socketfile et de son répertoire repose sur `ThreadExtra.at_exit`, exécuté soit à la fin du thread, soit par `mrproper` branché sur `Pervasives.at_exit` (`threadExtra.ml:140`). Le thread serveur ne se terminant jamais (`while true`), tout dépend d'une sortie **propre** du processus : un `_exit`, un `SIGKILL` ou un crash laisse socket et répertoire derrière — que le prochain démarrage rencontrera via N5. **L'ordre LIFO, lui, est correct** (`threadExtra.ml:80`) : la piste du § 7.2 est écartée. | Côté serveur de contrôle : au démarrage, si le socketfile existe, tenter une connexion ; si elle échoue, `unlink` défensif puis `bind`. |

#### 7.5.2 Hors du chemin du serveur, mais en production dans Marionnet

| # | Lieu | Gravité | Défaut | Correctif proposé |
|---|---|---|---|---|
| **N13** | `111-124` | **haute** (sûreté) | `accept_in_range_non_intr` **ignore** le `sockaddr` du pair que `Unix.accept` retourne (l.114, filtré par `_`) et applique le prédicat de plage à `Unix.getsockname service_socket`, c'est-à-dire à **l'adresse locale du serveur**. Le filtrage `~range4`/`~range6` ne filtre donc pas ce qu'il annonce. Aujourd'hui l'effet est masqué côté IPv4 (`x.ml:232` : `range4 = "0.0.0.0/0"`), mais `range6 = "fe80::/64"` (`x.ml:233`) compare une adresse locale à une plage *link-local* : les connexions IPv6 légitimes sont vraisemblablement **rejetées** — vérifiable en pointant `DISPLAY` sur `::1`. Surtout, la restriction laissée en commentaire juste au-dessus (`x.ml:231` : `172.23.0.0/24`) serait **inopérante** si on la rétablissait, alors qu'elle a valeur de garde-fou. | Utiliser le second composant du couple rendu par `Unix.accept` (adresse du **pair**) ; `getpeername` en repli. Un test unitaire du prédicat s'impose. |
| **N14** | `974-999` | moyenne | `crossover_link` : les deux boucles se terminent sur `with _ -> ()`, qui avale **tout** (y compris `Out_of_memory`) sans une ligne de journal ; et les `Thread.join` finaux ne rendront la main que si le `shutdown` croisé débloque effectivement le pair. | Journaliser l'exception terminale ; joindre avec échéance. |
| **N15** | `898-907` | basse | `client` : le `try` englobe `Unix.connect` **et** `client_fun`, si bien qu'une exception du protocole ressort étiquetée `Connecting e`. Sans conséquence tant que `client_fun` provient de `server_fun_of_stream_protocol` (qui rend un `Either` et ne lève pas), mais l'étiquette ment pour tout autre usage. | Restreindre le `try` au `connect`. |
| **N16** | `306-318` | basse | `fresh_socketname` : `Filename.temp_file` puis `Unix.unlink` laisse une fenêtre TOCTOU sur le nom, dans un `/tmp` partagé — aggravée par N6 (socket 0777). | Préférer `socketname_in_a_fresh_made_directory ~perm:0o700`, qui n'a pas ce défaut (le `mkdir` échoue si le nom a été repris). |
| **N17** | `493-506` | info | `#peek` bascule le descripteur en `set_nonblock` puis le rétablit : course avec tout autre lecteur du même fd, et rupture de `input_line` si l'appel tombe au mauvais moment (`EAGAIN`). | Ne pas exposer `peek` sur un canal partagé ; sur le canal ligne, il est de toute façon incohérent (N7). |

#### 7.5.3 Correctif structurant proposé pour l'épisode 2

Les `set_close_on_exec` posés **après** `Unix.socket`/`Unix.accept` (l.192, 239, 901) laissent une
fenêtre de course : un `fork`+`exec` concurrent — Marionnet en déclenche en permanence — peut
survenir entre les deux appels. Depuis OCaml 4.05, `Unix.socket` et `Unix.accept` acceptent
`~cloexec:true`, qui pose l'attribut **atomiquement** :

- `Unix.socket ~cloexec:true` aux lignes 184 (écoute), 682 (dgram unix), 750 (dgram inet), 895 (client) ;
- `Unix.accept ~cloexec:true` aux lignes 106 et 114.

Cela corrige **N2**, supprime la fenêtre de course et rend redondants les trois `set_close_on_exec`
existants (à conserver ou retirer, sans incidence). C'est le prolongement direct du correctif déjà
appliqué à `Network.server` par `marionnet-retro-compat-kernels-images` (ép. 3).

#### 7.5.4 Ordre d'application recommandé (épisode 2)

1. **N2 + N3 + N11** ensemble (une seule réécriture de `thread_forking_loop` et des fonctions
   d'acceptation) — ce sont les trois défauts qui rendent le canal de contrôle non fiable ;
2. **N1** — le plus délicat : il change le cycle de vie des descripteurs pour *tous* les usages
   existants (`switch.ml`, `x.ml`, `machine.ml`), donc à valider par un cycle GUI réel ;
3. **N4, N5, N8** — corrections locales, sans risque ;
4. **N13** — hors chemin, mais c'est un défaut de sûreté : à corriger tant qu'on est dans le fichier ;
5. **N6** (variante amont), **N14**, **N15** — au fil de l'eau ;
6. **N7, N9, N10, N12, N16, N17** — pas de modification de `network.ml` : ce sont des **contraintes
   de conception** pour `bin/control_server.ml`, à honorer à l'épisode 3.

---

## 8. Risques et pièges

| Risque | Nature | Parade |
|---|---|---|
| `GMain_actor.apply` **bloque** le thread serveur si le thread GTK est pris par un dialogue modal | le script se fige sans diagnostic | délai de garde **obligatoire** côté client ; envisager `GMain_actor.future` avec échéance côté serveur |
| Appeler des *callbacks* GUI au lieu des méthodes du modèle | dialogues modaux, blocage certain | règle absolue § 3.3 ; à vérifier à chaque commande ajoutée |
| Échec silencieux de `try_to_add_*` (`with _ -> false`) | le script croit avoir ajouté un composant absent | la réponse rend compte du **nombre réellement intégré** (§ 4.8) |
| `Thread.exit` sous OCaml 5 (`network.ml:264`) | ~~fuite de threads~~ → **infirmé** (§ 7.5, N4) : le thread meurt, mais chaque connexion normale est journalisée comme une erreur | épisodes 1-2 **avant** l'épisode 3 |
| Descripteurs fermés plusieurs fois, ou fermés **plus tard** par le GC (§ 7.5, N1) | fermeture d'un fd recyclé par un autre thread — motif C1 de `bug-critique-crash-host` | correctif N1 à l'épisode 2, validé par un cycle GUI réel |
| `service_socket` sans `CLOEXEC` sur le chemin `~no_fork` (N2) | descripteur de contrôle hérité par les xterm/UML/vde | `~cloexec:true` (§ 7.5.3), épisode 2 |
| Boucle d'acceptation non gardée (N3) | un `EMFILE` transitoire fait **disparaître** le canal de contrôle, GUI toujours vivante | garde + reprise, épisode 2 |
| Mélange `input_line` / `#receive` sur le même canal (N7) | octets perdus, `peek` aveugle | le serveur n'utilise **que** `input_line`/`output_line` |
| Fin de session confondue avec une erreur (N9) | trace d'erreur à chaque `mrnctl` qui se déconnecte | traiter `End_of_file`/`Receiving` comme fin normale |
| Socketfile résiduel après un arrêt brutal (N12), diagnostiqué par une exception trompeuse (N5) | le serveur refuse de démarrer sans dire pourquoi | test de connexion puis `unlink` défensif avant `bind` |
| Les 25 `Obj.magic` aux jointures user/simulation | toute API générique bute dessus | rester sur les méthodes typées ; ne pas ouvrir de chantier `Obj.magic` ici |
| **Dépendance** au chantier `marionnet-automate-composants` (R1 en attente) | la sémantique des états exposés par `ls`/`get` va changer | ne pas figer le vocabulaire d'états avant R1, ou l'assumer comme rupture documentée |
| Exposer un canal de contrôle | surface d'attaque locale | § 3.4 |
| `next_automaton_state` écrit 14× **jamais lu** (audit `marionnet-automate-composants`) | exposer ce champ donnerait une information fausse | n'exposer que `automaton_state` |

---

## 9. Découpage en épisodes

| Ép. | Contenu | État |
|---|---|---|
| **0** | Officialisation + ce document | **fait** (2026-07-29) |
| **1** | Audit complet de `lib/STRUCTURES/network.ml` → rapport + correctifs proposés | **fait** (2026-07-29) — § 7.5, 17 défauts |
| **2** | Application des correctifs retenus (divergence `lib/` vendored), ordre § 7.5.4 | **fait** (2026-07-29) — N2, N3, N11, N4, N5, N8, N13 ; **N1 différé en ép. 2b** |
| 2b | **N1** seul : cycle de vie des descripteurs de `stream_channel#shutdown` — exige une validation par cycle GUI réel | à faire |
| 3 | Squelette `bin/control_server.ml` + option CLI + 4 commandes (`status`, `ls`, `open`, `quit`) + **preuve GUI réelle** | à faire |
| 4 | Noyau complet : projet, composants, transitions, câbles, `wait`, `forest` | à faire |
| 5 | Les 4 treeviews | à faire |
| 6 | Client `mrnctl` + suite de tests scriptés | à faire |
| 7 | Voie C : générateur de `.mar` | à faire |

L'ordre 1 → 2 → 3 n'est pas négociable : bâtir le serveur sur un `network.ml` non audité
reviendrait à fabriquer un instrument de mesure faussé.

---

## 10. Journal d'avancement

### 2026-07-29 — épisode 0 : officialisation et conception

Chantier ouvert. Cinq arbitrages tranchés en interrogatoire préalable (§ 2) : ancrage A+C, JSON
asymétrique, observabilité limitée à l'état Marionnet, périmètre incluant les 4 treeviews, audit
complet de `network.ml`.

Vérifications faites sur le code (aucune supposition) : `GMain_actor` fournit bien le pont
thread → GTK avec garde anti-*deadlock* ; `st` centralise projet et réseau ; **les 8 composants
exposent déjà `try_to_add_<kind>` via un registre**, ce qui rend la création programmatique
quasi gratuite ; l'option `-r` existe déjà ; `~perm` de
`socketname_in_a_fresh_made_directory` porte sur le répertoire, ce qui règle la sécurité du
socket sans toucher ocamlbricks.

Deux défauts de `network.ml` établis dès cet épisode (§ 7.2) : `Thread.exit` l.264 (piège
OCaml 5, sur le chemin exact du futur serveur) et `chmod 0o777` l.202.

Aucun fichier de `bin/` ni de `lib/` modifié.

### 2026-07-29 — épisode 1 : audit de `lib/STRUCTURES/network.ml`

Lecture intégrale des 1342 lignes selon la grille du § 7.3, complétée par `threadExtra.ml`
(terminaison des threads, sémantique réelle d'`at_exit`), `filenameExtra.ml` (permissions
effectives) et les usages en production dans `bin/` (`x.ml`, `machine.ml`, `switch.ml`).
Résultat en § 7.5 : **17 défauts**, dont **4 bloquants** pour l'épisode 3.

Ce que l'audit change par rapport à l'amorce de l'épisode 0 :

- **N4 requalifié** : `Thread.exit` ne fait pas fuir de threads. La doc d'OCaml 5.4 dit qu'un
  *catch-all* rattrape `Thread.Exit`, et `ThreadExtra.create_non_killable` en a précisément un
  (`threadExtra.ml:383`) : le thread meurt, mais **chaque** connexion normale est journalisée
  comme une erreur — inacceptable pour un instrument de diagnostic, sans être fatal.
- **Trois défauts plus graves découverts**, tous invisibles depuis l'extérieur du module :
  N1 (fd fermé jusqu'à quatre fois, ou fermé plus tard par le GC sur un numéro recyclé —
  même motif que C1 de `bug-critique-crash-host`), N2 (`CLOEXEC` absent sur le chemin `~no_fork`,
  exactement le précédent du port-helper `:6000`), N3 (boucle d'acceptation non gardée : le canal
  de contrôle peut disparaître en silence pendant que la GUI tourne).
- **N13, hors périmètre du serveur mais en production** : le filtrage par plage d'adresses teste
  l'adresse **locale** au lieu de celle du pair — la garde `~range4`/`~range6` d'`x.ml` ne garde rien.
- **Une piste de l'épisode 0 écartée** : l'ordre des `ThreadExtra.at_exit` est correct (LIFO,
  `threadExtra.ml:80`). La parade de sécurité du § 3.4 (`~perm:0o700`) est en revanche
  **confirmée**, et même mieux fondée que prévu : `FilenameExtra.temp_dir` force le mode par un
  `chmod` explicite, donc contourne l'umask — dans les deux sens.

Six défauts (N7, N9, N10, N12, N16, N17) ne demandent aucune modification de `network.ml` : ce
sont des **contraintes de conception** pour `bin/control_server.ml`, reportées au § 8.

Aucun fichier de `bin/` ni de `lib/` modifié : les correctifs sont **proposés** (§ 7.5.3 et 7.5.4),
leur application est l'épisode 2.

### 2026-07-29 — épisode 2 : application des correctifs à `lib/STRUCTURES/network.ml`

**Périmètre décidé en ouverture** : tranche 1 (N2 + N3 + N11) + correctifs locaux (N4, N5, N8,
N13). **N1 explicitement exclu** — il change le cycle de vie des descripteurs pour *tous* les
usages existants (`switch.ml`, `x.ml`, `machine.ml`) et exige un cycle GUI réel de validation :
il devient l'**épisode 2b**. Un seul fichier de code touché, `lib/STRUCTURES/network.ml`
(divergence vendored assumée, § 7.4), plus un commentaire dans le `.mli` et la suite de tests.

Ce qui a été appliqué :

- **N2 + correctif structurant § 7.5.3** — `~cloexec:true` posé **à la création** :
  `Unix.accept` (les deux fonctions d'acceptation, ce qui couvre d'un coup le chemin `fork`
  *et* le chemin `~no_fork`) et `Unix.socket` (écoute, dgram unix, dgram inet, client). Les
  trois `set_close_on_exec` posés après coup ont été **retirés** : devenus redondants, ils ne
  laissaient qu'une fenêtre de course. Leur commentaire justificatif (issu de
  `marionnet-retro-compat-kernels-images`, ép. 3) a été reporté sur le nouvel emplacement.
- **N3** — les deux `while true` sont remplacés par une boucle `accepting_loop` qui garde le
  **corps** : une panne *transitoire* (`EMFILE`, `ENFILE`, `ENOBUFS`, `ECONNABORTED`, `ENOTCONN`…)
  est journalisée, temporisée 0,1 s, puis la boucle continue ; toute autre erreur termine la
  boucle. **Invariant préservé** : l'arrêt volontaire (thunk `Unix.shutdown listen_socket`) fait
  échouer `accept` avec `EINVAL`, qui reste *terminal* — sans quoi le serveur deviendrait
  immortel. Vérifié dans le journal d'exécution des tests (« *terminated by* » à la sortie).
- **N11**, et au-delà : introduction d'une petite **discipline de propriété** du socket accepté
  (`service_socket_ownership` : `release` idempotent + `transfer`). Elle ferme le descripteur
  quand `Unix.fork` ou `ThreadExtra.create` échoue, et surtout **interdit un second `close`**
  après transfert de propriété au fils ou au thread servant — c'est-à-dire qu'elle évite
  d'introduire, dans le correctif de N11, le motif même que N1 dénonce (fermer un numéro de
  descripteur entre-temps recyclé).
- **N4** — `Thread.exit ()` supprimé : chaque connexion normale n'est plus journalisée comme
  « *Terminated by uncaught exception* ».
- **N5** — le message d'erreur de `bind` est composé selon le **domaine** : un `bind` unix qui
  échoue produit désormais l'erreur réelle (`EADDRINUSE` sur socketfile résiduel, cas N12) au
  lieu d'un `Invalid_argument` trompeur.
- **N8** — `begin … end` aux deux endroits. `SO_RCVBUF` n'est plus **rétréci** à 1514 sur chaque
  canal créé.
- **N13** — le prédicat de plage s'applique enfin au **pair** (adresse rendue par `Unix.accept`,
  `getpeername` en repli) et non à l'adresse locale.
- **N7** — documenté dans `network.mli` (contrainte, pas correctif) : ne jamais mélanger
  `input_*`/`output_*` (bufferisés) et `receive`/`send`/`peek` (`Unix.recv`) sur un même canal.

**Preuve** (`test/marionnet.ml`, jusqu'ici vide, lancé par `dune test`) — 4 tests, `dune build`
et `dune test` verts. Trois d'entre eux ont été **vérifiés discriminants** : rejoués contre le
`network.ml` de `HEAD`, ils échouent (`N4` : *spurious uncaught exception* ; `N13` : connexion
légitime rejetée ; `N2` : 1 socket hérité par l'`exec`) et repassent au vert avec les correctifs.
Le quatrième (N3, saturation de la table de descripteurs pour provoquer `EMFILE`) est **best
effort** et signalé comme tel dans le fichier : il ne peut pas échouer à tort, mais il peut passer
sans avoir exercé le défaut, le timing de l'`accept` n'étant pas contrôlable. Ce qui a bien été
*observé* sur le code corrigé, avec `ulimit -n 256` : cinq « *transient failure, going on* » suivis
de la connexion servie — le comportement attendu de la garde.

**Non fait, et assumé** : aucune fumée GUI n'a été jouée dans cet épisode, alors que les
correctifs touchent par ricochet `x.ml`, `machine.ml` et `switch.ml` (`~cloexec` sur les sockets
dgram et client). À jouer avant l'épisode 3, en même temps que la validation de N1 (ép. 2b).
