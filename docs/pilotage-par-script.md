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

### 7.2 Défauts déjà établis (amorce, épisode 0)

1. **`network.ml:264` — `Thread.exit ()`** dans `thread_forking_loop`. Sous OCaml ≥ 5.0,
   `Thread.exit` ne termine plus le thread : c'est le piège documenté en mémoire
   `migration-ocaml5`, et il se trouve **exactement** sur le chemin `~no_fork` qu'emprunterait le
   serveur de contrôle. À corriger **avant** de bâtir dessus.
2. **`network.ml:202` — `Unix.chmod socketfile 0o777`** inconditionnel, sans option de mode
   (cf. § 3.4 pour le contournement retenu).

À examiner de près (pistes, non confirmées) :

- `network.ml:77` — `let protect f x : unit = try f x with _ -> ()` : exceptions avalées ;
- `network.ml:227` et `257` — boucles `while true do … done` non gardées : si la fonction
  d'acceptation lève autre chose qu'`EINTR`, le thread serveur meurt **en silence** ;
- `network.ml:302-303` — l'ordre des `ThreadExtra.at_exit` (`rmdir` enregistré avant `unlink`,
  donc exécuté après si la pile est dépilée en ordre inverse) : à vérifier, sous peine de laisser
  des répertoires ;
- `network.ml:266` — `service_socket` en cas d'échec de création de thread ;
- absence de plafond au nombre de connexions simultanées ;
- sémantique de `#receive` selon le type de socket (le module `Examples` documente lui-même que
  `seqpacket` tronque au-delà de `max_input_size`) ;
- `fix_IPV6_ONLY_if_needed`, `bind`, `accept_in_range_non_intr` : robustesse des cas d'erreur.

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

---

## 8. Risques et pièges

| Risque | Nature | Parade |
|---|---|---|
| `GMain_actor.apply` **bloque** le thread serveur si le thread GTK est pris par un dialogue modal | le script se fige sans diagnostic | délai de garde **obligatoire** côté client ; envisager `GMain_actor.future` avec échéance côté serveur |
| Appeler des *callbacks* GUI au lieu des méthodes du modèle | dialogues modaux, blocage certain | règle absolue § 3.3 ; à vérifier à chaque commande ajoutée |
| Échec silencieux de `try_to_add_*` (`with _ -> false`) | le script croit avoir ajouté un composant absent | la réponse rend compte du **nombre réellement intégré** (§ 4.8) |
| `Thread.exit` sous OCaml 5 (`network.ml:264`) | fuite de threads, connexions non libérées | épisodes 1-2 **avant** l'épisode 3 |
| Les 25 `Obj.magic` aux jointures user/simulation | toute API générique bute dessus | rester sur les méthodes typées ; ne pas ouvrir de chantier `Obj.magic` ici |
| **Dépendance** au chantier `marionnet-automate-composants` (R1 en attente) | la sémantique des états exposés par `ls`/`get` va changer | ne pas figer le vocabulaire d'états avant R1, ou l'assumer comme rupture documentée |
| Exposer un canal de contrôle | surface d'attaque locale | § 3.4 |
| `next_automaton_state` écrit 14× **jamais lu** (audit `marionnet-automate-composants`) | exposer ce champ donnerait une information fausse | n'exposer que `automaton_state` |

---

## 9. Découpage en épisodes

| Ép. | Contenu | État |
|---|---|---|
| **0** | Officialisation + ce document | **fait** (2026-07-29) |
| 1 | Audit complet de `lib/STRUCTURES/network.ml` → rapport + correctifs proposés | à faire |
| 2 | Application des correctifs retenus (divergence `lib/` vendored) | à faire |
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
