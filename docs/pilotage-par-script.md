# Pilotage de Marionnet par script

> Chantier long `marionnet-pilotage-par-script`.
> Reprise : appliquer le skill `chantier-long` (mémoire `marionnet-pilotage-par-script`,
> `git log --grep="marionnet-pilotage-par-script"`).
>
> **État : épisodes 0 à 2c faits.** La conception (§ 1-6) reste à l'état de projet : aucune ligne
> de `bin/` n'est encore écrite. Ce qui existe est l'assainissement préalable de
> `lib/STRUCTURES/network.ml` (§ 7.5, ép. 2 et 2b), sa suite de tests `test/marionnet.ml`, et sa
> validation en GUI réelle (ép. 2c). Prochaine étape : épisode 3.

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
- **aucun descripteur du canal n'est hérité par les processus exec'és** — `~cloexec` à la
  création du socket d'écoute (N2), à l'`accept` et au `dup` des canaux stdlib (N1) : sans quoi
  un `vde_switch` ou un noyau invité pourrait parler au canal de contrôle de son propre hôte.
  **Prouvé en session réelle à l'ép. 3b**, témoin à l'appui (§ 11) ;
- le défaut `0o777` reste **signalé** dans le rapport d'audit pour rétro-propagation amont.

### 3.5 Insertion dans le code existant

| Fichier | Modification |
|---|---|
| `bin/control_server.ml` | **nouveau** — serveur, dispatch, encodage JSON |
| `bin/initialization.ml` | déclarer `--control-socket PATH` avec `Argv`, à côté de `option_r` (l.65) |
| `bin/marionnet.ml` | neutraliser `SIGPIPE` (N18) ; démarrer le thread serveur juste avant `main_loop ()`, donc après `st` et après la construction de la fenêtre |
| ~~`bin/dune`~~ | **rien à faire** (rectifié à l'ép. 3a) : la stanza GUI est `(modules (:standard \ …))` (`bin/dune:163`), elle prend le nouveau module automatiquement |

⚠️ Rectifié à l'ép. 3a : `--control-socket[=PATH]`, avec valeur **optionnelle**, n'est pas
réalisable — `Argv` n'offre que des options *sans* argument (`register_unit_option`) ou à argument
**obligatoire** (`register_string_option`, `lib/BASE/argv.mli:26`). La valeur est donc obligatoire,
ce qui a un avantage : le client connaît le chemin sans avoir à découvrir un nom auto-généré.
Contrepartie : le `~perm:0o700` du § 3.4 ne s'applique qu'au nom auto-généré, donc c'est le serveur
qui doit vérifier le répertoire parent d'un chemin imposé (créé en `0700` s'il manque, refus s'il
est accessible en écriture à autrui).

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

**Contenu multi-ligne : par chemin de fichier** (tranché à l'ép. 3a). Un rcfile de scénario (§ 10)
ou un fragment `Xforest` (§ 4.8) ne tient pas sur une ligne. Plutôt que d'ajouter un mode « corps »
au protocole (sentinelle de fin, donc un **état** dans le lecteur et un cas d'erreur de plus) ou un
encodage base64 (illisible, et un décodeur à écrire), la commande reçoit un **chemin** :
`--from=/chemin/fichier`, que le serveur lit côté hôte. Le lecteur reste un `input_line` **nu**, et
le mécanisme couvre rcfile et forest d'un seul geste. Légitime ici : un socket unix implique la
même machine, et le répertoire `0700` borne déjà l'accès au canal. Côté client, un heredoc Bash
vers `mktemp` fait le reste.

**Options et argument positionnel** (ép. 3a) : les jetons commençant par `--` sont des options
(`--clé=valeur`, ou `--clé` seule pour un drapeau) ; **tous les autres jetons sont rejoints par un
espace** pour former l'unique argument positionnel — de sorte qu'un chemin contenant des espaces
n'a pas besoin d'être protégé. Cette commodité ne vaut que tant qu'une commande a **au plus un**
argument positionnel : les commandes de l'ép. 4 (`connect`, `ifconfig`…) exigeront une vraie
tokenisation, et sans doute une convention de citation.

**`--timeout=N`** est accepté par toute commande qui interroge le thread GTK (§ 8).

### 4.2 Projet

| Commande | Correspondance modèle |
|---|---|
| `new <fichier>` | `st#new_project ~filename` (`state.ml:322`) |
| `open <fichier>` | `st#open_project_async ~filename` (`state.ml:577`) |
| `save` / `save-as <fichier>` | `st#save_project` (l.764) / `st#save_project_as` (l.771) |
| `close` | `st#close_project` (l.352) |
| `quit` | `st#quit_async` (l.924) |
| `status` | `st#active_project`, `st#runnable_project`, `st#project_already_saved` |

⚠️ `open` est **asynchrone** (retourne un `Thread.t`) — **tranché à l'ép. 3a, et le nom trompe** :
appelé depuis un thread qui n'est pas `gtk_main`, `open_project_async` exécute le chargement
**dans le thread appelant** (`state.ml:594-596`), sans en créer un autre. Le serveur l'appelle donc
**directement** — surtout pas via `GMain_actor`, qui le ferait basculer sur la branche « je suis
gtk_main » et rendrait la main aussitôt, résultat perdu. La commande est ainsi **bloquante**, ce
qu'un script veut. Restait à ne pas mentir : voir le § 11 (journal de l'ép. 3a), où le premier
critère de succès s'est révélé menteur et a dû être remplacé.

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

⚠️ **`--can=…` ne suffit pas à garantir l'équivalence avec la GUI** (constaté à l'ép. 4a) :
`del` et `set` obéissent eux aussi à l'état du composant, mais leur garde vit **dans la GUI**, pas
dans le modèle. Le contrat complet — table des états, règle de refus, exception des câbles,
commande `can` — est au **§ 4.10**, qui fait autorité sur ce paragraphe.

### 4.4 Transitions

`start`, `stop`, `suspend`, `resume`, `restart`, `poweroff` sur un composant nommé ;
`start-all`, `shutdown-all`, `poweroff-all` sur le réseau entier
(`st#startup_everything`, `#shutdown_everything`, `#poweroff_everything`, `state.ml:888-905`).

Côté composant : `#startup`, `#suspend`, `#resume`, `#gracefully_shutdown`, `#gracefully_restart`,
`#poweroff` (`user_level.ml:207-238`).

⚠️ Ces méthodes sont **gardées mais muettes** : appeler `#startup` sur un composant qui ne peut
pas démarrer ne fait rien et ne dit rien. La commande **teste le prédicat avant** et répond
`forbidden_transition` — cf. **§ 4.10**, qui donne la table complète, l'exception des câbles, et
le statut particulier de `poweroff` et `restart` (aucun menu par composant ne les offre).

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

### 4.9 Les fenêtres qui s'ouvrent toutes seules

*Conception de l'épisode 3c (2026-08-03).*

Marionnet ouvre des fenêtres **que personne n'a demandées** : l'écran de bienvenue au démarrage,
un avertissement quand un projet est dans un ancien format, le récapitulatif des adaptations
appliquées au chargement (images et noyaux remappés — cf. `docs/retro-compatibilite-kernels-images.md`),
une erreur quand un chargement échoue, une alerte quand un processus meurt. En session pilotée
personne n'est là pour les fermer : elles s'accumulent, et surtout **ce qu'elles disent est perdu
pour le script**. L'épisode 3a l'avait déjà rencontré sans le traiter — un `open` en échec rapporte
sa cause dans un dialogue non modal et nulle part ailleurs.

La réponse n'est donc pas « les fermer » mais **capturer, puis fermer**.

**Armement.** Le mode est impliqué par `--control-socket` (une session pilotée n'a personne devant
l'écran) et se désarme par `--keep-dialogs` ; `--dialog-timeout=MS` règle le délai avant
auto-fermeture (défaut 2000 ms — non nul **exprès** : la session doit rester *observable*, un humain
ou une capture d'écran voit encore ce qui s'est passé).

**Capture.** `bin/script_mode.ml` tient un tampon **borné** (200, éviction FIFO) de messages
horodatés et numérotés (`seq` monotone). Deux points d'insertion suffisent, et couvrent la
cinquantaine de sites d'appel :

| Point | Fichier | Ce qui est capturé |
|---|---|---|
| `message` (constructeur unique de `help`/`error`/`warning`/`info`) | `bin/gui/simple_dialogs.ml` | titre + corps, avec le `kind` |
| `recapitulative` | `bin/gui/simple_dialogs.ml` | la liste **structurée** `(résumé, détail, sévérité)`, item par item |

Le splash n'avait même pas besoin de code : `Splash.show_splash ?timeout` savait déjà se fermer
seul (`bin/splash.ml:112`), le paramètre n'avait jamais servi.

**Restitution.** Deux voies, et la première est la plus utile :

- le champ `notifications` de la réponse d'`open` — les adaptations d'un vieux projet appartiennent
  à la commande qui les a provoquées, pas à un second aller-retour ; il est présent **aussi sur les
  réponses d'erreur** (`reply_error_with`), puisque c'est là que la cause se trouve ;
- la commande `notifications [--since=N] [--clear]`, qui rend `enabled`, `count`, `last_seq` et la
  liste. Elle ne touche **pas** le thread GTK et n'a pas de délai de garde : quand la GUI est bloquée
  derrière un modal et que toute autre commande expire, celle-ci répond encore — et dit ce qu'est
  ce modal.

**Questions (dialogues bloquants).** `Simple_dialogs.confirm_dialog` et `Talking.EDialog.ask_question`
partagent le même widget, la même boucle `#run ()` et le même refus de se laisser fermer. Ils
reçoivent un `?script_answer` : la réponse à rendre **sans afficher la fenêtre**. Deux garde-fous
tiennent la sémantique :

1. **pas de politique globale « oui à tout »** — la valeur est fixée site par site (aujourd'hui :
   `true` pour « tout arrêter » / « tout éteindre », `"no"` pour « sauvegarder avant de quitter ? » ;
   l'omettre vaut *annuler*, c'est-à-dire ne rien faire) ;
2. **la neutralisation est limitée au thread qui sert la commande** (`Script_mode.in_command`), pas
   au mode script. Un compteur global n'aurait pas suffi : `open` charge le projet dans le thread
   serveur et prend plusieurs secondes, pendant lesquelles un clic **humain** sur « tout éteindre »
   aurait perdu sa confirmation. Un callback déclenché par un clic tourne dans le thread GTK, jamais
   enregistré : les deux cas ne peuvent pas être confondus.

Atteindre cette branche signale d'ailleurs qu'un *callback* GUI a été appelé depuis le serveur, ce
que le § 3.3 interdit : elle journalise bruyamment. À ce jour aucune commande n'y mène.

### 4.10 L'automate d'état, contrat du script

*Conception de l'épisode 4a (2026-08-03), ancres vérifiées le jour même.*

**Exigence.** Un script doit avoir **les mêmes possibilités et les mêmes limites** qu'un humain
devant la GUI : si un composant est suspendu, il peut être réveillé, pas démarré ; s'il tourne, il
ne peut pas être supprimé. Cette exigence n'est pas une politesse d'API — c'est ce qui rend le
canal utilisable comme **instrument de test** : un script qui pourrait faire ce que la GUI
interdit ne testerait pas Marionnet, il testerait une autre application.

**L'automate existe déjà**, et il est explicite : quatre états
(`No_device | Off | On | Sleeping`) et cinq prédicats gardés par `Recursive_mutex`
(`user_level.ml:417-450`), exposés par nature de composant via `get_node_names_that_can_*`
(`user_level.ml:1838-1868`). Rien à inventer : le chantier `marionnet-automate-composants`
(16 épisodes, clos le 2026-08-03, `docs/refonte-automate-composants.md`) l'a audité et refondu.
Ce qui manquait, c'est **d'en publier la table** et de constater qu'elle a un trou.

| Action | Commande | Garde — source de vérité | États autorisés | Dans la GUI ? |
|---|---|---|---|---|
| démarrer | `start` | `can_startup` (`user_level.ml:417`) | `No_device`, `Off` | oui — menu *Startup* |
| arrêter | `stop` | `can_gracefully_shutdown` (`:424`) | `On`, `Sleeping` | oui — menu *Stop* |
| suspendre | `suspend` | `can_suspend` (`:438`) | `On` **seulement** | oui — menu *Suspend* |
| réveiller | `resume` | `can_resume` (`:445`) | `Sleeping` **seulement** | oui — menu *Resume* |
| modifier | `set` | **`can_modify` — à créer** (aujourd'hui : `Properties.dynlist`) | `No_device`, `Off` | oui — menu *Properties* |
| supprimer | `del` | **`can_destroy` — à créer** (aujourd'hui : `Remove.dynlist`) | `No_device`, `Off` | oui — menu *Remove* |
| éteindre brutalement | `poweroff` | `can_poweroff` (`:431`) — **sans lecteur** | `On`, `Sleeping` | **non par composant** — seulement « tout éteindre » (`state.ml:962`, filtré par `can_gracefully_shutdown`) |
| redémarrer | `restart` | `can_gracefully_shutdown` (`marionnet.ml:169`) | `On`, `Sleeping` | **non par menu** — seulement via une édition de treeview, après confirmation (`marionnet.ml:173-175`) |

**Le trou : la règle de suppression n'est pas dans le modèle, elle est dans la GUI.** Sur les sept
composants-nœuds, sans exception, `Properties.dynlist () = get_node_names_that_can_startup` et
`Remove.dynlist = Properties.dynlist` (`machine.ml:167`/`229`, `hub.ml:84`/`106`,
`switch.ml:115`/`149`, `router.ml:490`/`555`, `cloud.ml:88`/`108`, `world_gateway.ml:117`/`158`,
`world_bridge.ml:93`/`113`) : le menu ne propose « Modifier »/« Supprimer » que pour ce qui peut
démarrer, c'est-à-dire ce qui est éteint. Mais `#destroy` n'est gardé par **aucun** prédicat —
`can_destroy` n'existe pas. Un serveur qui appelle les méthodes du modèle (§ 3.3) **contournerait
donc la règle** et détruirait un composant en marche, avec ses processus vivants.

**Décision (ép. 4a) : la garde descend dans le modèle.** `can_destroy` et `can_modify` sont
ajoutés à la classe de base de `user_level.ml`, avec la même condition que `can_startup` par
défaut, et **surchargés à `true` dans `cable.ml`** ; les `dynlist` de la GUI les lisent au lieu de
`can_startup`, et le serveur lit les mêmes. Source unique de vérité : c'est la seule forme qui
garantit l'équivalence demandée. Deux prédicats plutôt qu'un, bien qu'ils coïncident aujourd'hui :
ils recouvrent deux notions qui peuvent diverger — le câble en est déjà la preuve — et le coût
marginal est nul. *(Implémentation : épisode 4b.)*

**Les câbles ne suivent pas la règle des nœuds**, et c'est délibéré :

| | Câble |
|---|---|
| modifier / supprimer | `Properties.dynlist = all_names` (`cable.ml:127`), `Remove.dynlist = Properties.dynlist` (`:181`) → **toujours permis, en marche compris** |
| suspendre / réveiller | `can_suspend = connected`, `can_resume = not connected` (`cable.ml:906-912`) — sémantique propre : « débranché » plutôt que « endormi » |
| redémarrer | `suspend` puis `resume` (`marionnet.ml:160-164`), pas `gracefully_restart` |
| démarrer / arrêter | **inapplicable** : le processus d'un câble est piloté par un compteur de références, jamais par l'utilisateur ; `can_startup` n'a plus aucun lecteur pour un câble depuis l'ép. 12 (`cable.ml:897-903`) |

C'est la règle de projet « le câblage suit la réalité » (`CLAUDE.md`) : on débranche et rebranche
un câble pendant que les machines tournent, donc Marionnet doit le permettre. Un serveur qui
appliquerait aux câbles la règle des nœuds serait plus restrictif que la GUI — aussi faux que
l'inverse.

**Trois règles pour le serveur**, qui découlent de ce qui précède :

1. **Tester `can_*` avant, et refuser explicitement.** Les méthodes de transition du modèle sont
   gardées mais **muettes** : `user_level.ml:212-237` fait `if self#can_startup then
   self#startup_right_now`, sans `else`. Un `start` sur un composant déjà démarré est donc un
   **no-op silencieux**, et un serveur qui se fierait au retour répondrait `ok` alors que rien
   n'a eu lieu. Toute commande d'action teste le prédicat **avant**, et répond
   `forbidden_transition` en indiquant l'état courant et les actions légales. Même motif que
   l'échec silencieux de `try_to_add_*` (§ 4.8) et que le C5 de l'audit de l'automate.
2. **Ne jamais exposer l'état brut.** `No_device` et `Off` se projettent tous deux sur `off`
   (§ 2 : `off`/`on`/`sleeping`). La différence est un détail d'implémentation — machines et
   routeurs enchaînent un `destroy` après l'arrêt pour repartir d'un fichier COW neuf et finissent
   en `No_device`, les autres restent en `Off` (C2 de l'audit). Un script qui verrait deux états
   là où l'utilisateur en voit un serait conduit à écrire des conditions fausses.
3. **Publier l'éligibilité plutôt que la faire deviner** — commande `can` ci-dessous.

**Commande `can [<nom>]`** — l'équivalent scriptable du menu contextuel, vue « par composant »
(là où `ls --can=…` du § 4.3 est la vue « par action ») :

```
-> can m1
<- {"ok":true,"name":"m1","kind":"machine","state":"sleeping","can":["resume","stop"]}
-> can
<- {"ok":true,"components":[{"name":"m1","state":"sleeping","can":["resume","stop"]}, …]}
```

Le script n'a ainsi **aucune table à réimplémenter** : il demande ce qui est permis maintenant.
C'est aussi le moyen le plus direct de tester l'automate lui-même — comparer `can` avant et après
chaque transition est un oracle qui ne dépend d'aucune connaissance externe.

**Deux actions restent au-delà de la GUI, à trancher à l'ép. 4b.** `poweroff` et `restart`
**par composant** n'existent dans aucun menu : le premier n'est offert que globalement
(« tout éteindre », avec confirmation), le second n'est déclenché que par une édition de treeview.
Le § 4.4 les prévoit pourtant tous deux. Recommandation : les **garder**, mais les marquer dans la
grammaire comme *extensions assumées* — l'action existe bel et bien dans l'application, seule sa
granularité diffère, et un script de test a besoin de simuler une coupure brutale sur **une**
machine. L'alternative (équivalence stricte, donc suppression des deux commandes) reste ouverte et
appartient à l'auteur.

**Dette relevée au passage** : `can_poweroff` (`user_level.ml:431`) n'a **aucun lecteur** —
`poweroff_everything` (`state.ml:962`) filtre sur `can_gracefully_shutdown`. Les deux prédicats
ont la même définition (`On | Sleeping`), donc pas de bug ; mais c'est un prédicat mort de plus,
du même genre que `can_startup` sur les câbles. À traiter avec l'ép. 4b, pas avant.

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
| **N1** | `429-430` + `475-480` | **haute** | `stream_channel#shutdown` ferme le **même fd jusqu'à quatre fois** : `Unix.close fd` (l.430), puis `close_in in_channel`, `close_out out_channel`, `Unix.close fd` (l.477-479) — trois `close` de trop, chacun sur un numéro de descripteur **déjà libéré**, donc potentiellement **recyclé par un autre thread**. Pire : `close_out` **flushe avant** de fermer, donc peut écrire dans le descripteur de quelqu'un d'autre. Et si `super#shutdown` lève — `Unix.shutdown` renvoie `ENOTCONN` dès que le pair a fermé en premier, cas **normal** —, le `raise (Closing e)` saute les trois lignes suivantes : les canaux stdlib survivent et leur **finaliseur GC** fera le `close` **plus tard**, sur un fd entre-temps recyclé. C'est le motif C1 de `bug-critique-crash-host` (kill différé vers un PID recyclé), transposé aux descripteurs. **Rectification de l'ép. 2b** : la clause « *finaliseur GC* » de ce diagnostic est **fausse** — mesuré sur OCaml 5.4.1, le GC d'un canal non fermé **ne ferme pas** son descripteur, il ne libère que la structure (les octets encore en tampon sont perdus, rien de plus). Le défaut réel se réduit donc — mais s'y réduit entièrement — au **quadruple `close`**, dont un avec écriture. Comme pour N4, une moitié de l'audit tombe à l'épreuve. | **Corrigé à l'ép. 2b** : chaque canal stdlib reçoit **sa propre copie** du socket (`Unix.dup ~cloexec:true`), allouée **à la demande** ; `#shutdown` devient idempotent, ferme les copies effectivement créées (`flush` d'abord, avant tout `SHUTDOWN_SEND`) puis délègue au parent l'**unique** `Unix.close` du socket. |
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
| **N18** | hors `network.ml` — `bin/marionnet.ml` | **haute** | **`SIGPIPE` n'est jamais neutralisé.** Aucun `Sys.set_signal Sys.sigpipe Signal_ignore` nulle part dans `bin/` ni dans `lib/` (`sysExtra.ml` ne fait que **nommer** les signaux). Or l'action par défaut de `SIGPIPE` est de **tuer le processus** : toute écriture sur un socket dont le pair vient de fermer — `output_line` (qui `flush` à chaque appel), `#send`, le `flush` de fermeture — peut donc terminer Marionnet **sans trace**, sans exception à journaliser. Ce n'est pas une conjecture : le programme de tests de l'ép. 2b s'est fait tuer de cette façon (`exit 141`) dès qu'il a enchaîné des connexions. Un serveur de contrôle dont le client raccroche entre deux lignes serait exactement dans ce cas. | **Découvert à l'ép. 2b**, corrigé à l'ép. 3 : neutraliser le signal **dans `bin/marionnet.ml`**, pas dans `lib/` (un effet global n'a pas à être posé par une bibliothèque vendored). `EPIPE` devient alors une exception ordinaire, capturée par les `tutor*` du canal. Déjà appliqué dans `test/marionnet.ml`, où il rend la suite déterministe. |

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
| **2b** | **N1** seul : cycle de vie des descripteurs de `stream_channel#shutdown` | **fait** (2026-07-29) — code + 2 tests ; fumée GUI reportée en 2c |
| **2c** | Fumée GUI : exercer réellement le chemin `input_line`/`output_line` corrigé | **fait** (2026-08-03) — 4 critères sur 5 satisfaits, protocole de l'ép. 2b rectifié |
| **3a** | Squelette `bin/control_server.ml` + option CLI + 4 commandes (`status`, `ls`, `open`, `quit`) + **N18** + preuve **scriptée** | **fait** (2026-08-03) |
| **3b** | Preuve en session réelle : critère **C5** (aucun fd de contrôle dans `/proc/<pid xterm>/fd`, xterm vivant), non couvert par l'ép. 2c | **fait** (2026-08-03) — 0 fd sur 395 processus, témoin à 351 fds |
| **3c** | Fenêtres auto-ouvertes : capture + auto-fermeture, commande `notifications`, `?script_answer` (§ 4.9) | **fait** (2026-08-03) |
| **4a** | L'automate comme **contrat du script** (§ 4.10) : table états × actions, règle de refus, exception des câbles, commande `can` ; décision `can_destroy`/`can_modify` dans le modèle | **fait** (2026-08-03) — conception, aucun code |
| 4b | Implémentation de 4a : `can_destroy`/`can_modify` dans `user_level.ml` (+ surcharge `cable.ml`), `dynlist` GUI qui les lisent, commande `can` ; arbitrage `poweroff`/`restart` par composant | à faire |
| 4c | Noyau complet : projet, composants, transitions, câbles, `wait`, `forest`, `rc-set`/`rc-get` | à faire |
| 5 | Les 4 treeviews | à faire |
| 6 | Client `mrnctl` + suite de tests scriptés | à faire |
| 7 | Voie C : générateur de `.mar` | à faire |

L'ordre 1 → 2 → 3 n'est pas négociable : bâtir le serveur sur un `network.ml` non audité
reviendrait à fabriquer un instrument de mesure faussé.

---

## 10. Perspective : le scripting descend dans les composants

*Direction fixée par l'auteur le 2026-08-03, ancrages vérifiés le jour même.*

Piloter Marionnet ne s'arrête pas aux gestes que la GUI propose. La fonctionnalité **« Startup
configuration »** — déjà offerte par les machines, les switchs et les routeurs — permet de faire
**jouer un scénario au démarrage** : une machine peut exécuter sa part d'un TP, écrire un
**journal d'exécution** récupérable côté hôte, se **synchroniser approximativement** avec les
autres (`sleep`), et jusqu'à **décider sa propre terminaison** (`halt`) au lieu de subir un arrêt
piloté depuis l'extérieur. C'est le complément naturel du canal de contrôle : celui-ci commande
*l'infrastructure*, la configuration de démarrage commande *l'intérieur des machines*.

**Corollaire assumé** : les composants qui n'ont pas cette fonctionnalité (hub, câble, cloud,
`world_*`) pourront être **augmentés** pour l'obtenir. Élargir la surface scriptable est un
objectif du chantier, pas une dérive de périmètre.

Le mécanisme **existe déjà de bout en bout** ; seul l'accès programmatique manque :

| Maillon | Où | Nature |
|---|---|---|
| `rc_config : bool * string` = (activé, contenu) | `machine.ml:613-615`, `switch.ml:410-412` | état user-level, déjà persistant |
| 8 variantes pour le routeur (unix + 7 protocoles quagga) | `router.ml:63-250`, `349-389` | idem |
| lu à la **construction du device** | `machine.ml:674-678` | ⇒ prend effet au **prochain démarrage**, jamais à chaud |
| déposé dans `hostfs/marionnet-relay.rcfile` | `simulation_level.ml:1244-1251` | côté hôte |
| **sourcé** en fin de `start()` du relais invité | `marionnet-relay.trixie:486-494` | `for i in /mnt/hostfs/{$virtualfs_name.,marionnet-}relay*; do source "$i"; done` — donc du **bash invité arbitraire**, en fin de boot |
| hostfs = répertoire **hôte** monté en `/mnt/hostfs` | inotify déjà en place, `machine.ml:867-934` | ⇒ le journal écrit par l'invité est lisible côté hôte |

Deux conséquences pour la suite du chantier :

1. **Le canal « invité prêt » qui manquait au § 4.7 existe déjà.** Un scénario qui touche un fichier
   dans `/mnt/hostfs/` donne au script un signal de disponibilité **sans** toucher aux images —
   c'est-à-dire sans dépendre du chantier `marionnet-kernel-rootfs`. Seule la *convention* reste à
   fixer.
2. **Ne pas faire passer `rc_config` par `forest`.** Dans le `.mar`, ce champ est **marshalé**
   (`Marshal.to_string`, `machine.ml:644`/`660`, `switch.ml:455`/`464`) : la commande `forest`
   (§ 4.8) et le générateur `.mar` (voie C) sont de mauvais véhicules. Il faut une **commande
   dédiée** qui transporte le contenu **en clair**, par chemin de fichier (§ 4.1) :
   `rc-set <nœud> --from=<fichier> [--enable|--disable]`, et son pendant `rc-get`.

---

## 11. Journal d'avancement

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

### 2026-07-29 — épisode 2b : N1, un propriétaire par descripteur

Un seul fichier de code touché (`lib/STRUCTURES/network.ml`, classes
`stream_or_seqpacket_bidirectional_channel` et `stream_channel`), plus deux tests.

**Ce qui a été corrigé.** Le nœud de N1 est qu'`in_channel` et `out_channel` étaient dérivés du
**même** descripteur que celui possédé par l'objet : trois propriétaires pour un seul numéro,
donc deux `close` de trop — sur un numéro déjà libéré, et l'un d'eux (`close_out`) **écrit**
dedans avant de fermer. Correctif : chaque canal stdlib reçoit **sa propre copie**
(`Unix.dup ~cloexec:true`), et `#shutdown` :

1. est **idempotent** (drapeau `closed` porté par la classe parente) — indispensable, car quatre
   sites appellent `try ch#shutdown … with _ -> ()`, parfois deux fois sur le même canal ;
2. `flush` puis ferme les copies **effectivement créées**, *avant* le `Unix.shutdown` (un `flush`
   postérieur à un `SHUTDOWN_SEND` échouerait) ;
3. délègue au parent l'**unique** `Unix.close` du socket.

**Copies allouées à la demande** (`lazy`), et c'est une correction de trajectoire dictée par la
mesure, pas une élégance : la première version dupliquait le descripteur **à la construction** du
canal, ce qui a fait **échouer le test N3** (`EMFILE` transitoire) — sous pénurie de descripteurs,
la connexion était acceptée puis abandonnée faute de deux numéros libres pour les copies,
c'est-à-dire exactement la disparition du service que la garde de l'ép. 2 vise à empêcher. Avec
l'allocation paresseuse, un protocole qui n'utilise que `#send`/`#receive` — le cas de `x.ml` et
`machine.ml` — ne consomme **aucun** descripteur supplémentaire ; seul un protocole en mode ligne
(`switch.ml`, et le futur serveur de contrôle) en demande deux.

**Deux moitiés de l'audit rectifiées.** (a) Le GC **ne ferme pas** le descripteur d'un canal
finalisé (mesuré sur OCaml 5.4.1) : la clause « fermeture différée par le GC sur un numéro
recyclé » de N1 est fausse, comme l'avait été la crainte de fuite de threads de N4. Ce qui reste
de N1 — le quadruple `close`, dont un avec écriture — suffisait amplement. (b) Le défaut **N18**
(`SIGPIPE` jamais neutralisé, § 7.5.2) a été découvert *par accident* pendant cet épisode : le
programme de tests s'est fait tuer (`exit 141`) en enchaînant des connexions. À corriger dans
`bin/marionnet.ml` à l'épisode 3.

**Preuve.** `dune build` et `dune test` verts, 7 vérifications, 6 exécutions consécutives sans
échec. Le test N1 est **discriminant** : rejoué contre le `network.ml` de `HEAD`, il échoue
(« *the second shutdown closed a descriptor belonging to someone else* ») et repasse au vert avec
le correctif. Il est construit sur un `socketpair`, sans serveur ni thread : une **première**
version passait par un vrai échange client/serveur et s'est révélée *flaky*, le thread servant du
même processus reprenant parfois le numéro libéré avant le témoin (observé : numéro libéré 11,
plus petit numéro disponible pour le témoin 12). Le second test N1 (30 connexions successives)
n'est pas discriminant : il garde le correctif lui-même contre une fuite des copies, puisqu'un
canal possède désormais jusqu'à trois descripteurs.

**Fumée GUI — jouée le 2026-07-29, partiellement concluante.** Deux sessions
(`/tmp/marionnet.native.42.log` et `.43.log`, `marionnet.native -d`). Acquis : le relais X11 a
exercé un `stream_channel` complet en conditions réelles (`Accepted connection #1 on
172.23.0.254:6000`, `crossover_link`, `#receive`, `Protocol completed`, processus sorti proprement,
`xeyes` fonctionnel), les deux boucles d'acceptation se terminent sur `terminated by:
Accepting(_)` — comportement voulu de la garde N3 — et **aucun** `EBADF`, `Bad file descriptor` ni
`Closing` inattendu n'apparaît dans les deux journaux. **Non couvert** : `grep -c "port/print"`
donne **0** dans les deux sessions, donc le chemin `input_line`/`output_line` de `switch.ml` — le
seul qui alloue réellement les copies `dup` de cet épisode — n'a jamais été atteint, un défaut
**extérieur à ce chantier** empêchant le switch de finir son démarrage (treeview *defects*
divergent : cf. **B6** de `docs/refonte-automate-composants.md`, signalé le même jour). À rejouer
sur un **projet neuf** (switch + 2 machines), le projet de test ayant son treeview déjà corrompu.

Protocole, à rejouer intégralement avant l'épisode 3 :

1. `dune build` puis lancer `./_build/default/bin/marionnet.native --debug 2>&1 | tee /tmp/smoke-ep2b.log` ;
2. noter `ls /proc/$(pgrep -f marionnet.native)/fd | wc -l` juste après le démarrage ;
3. créer un switch et une machine, les relier, **démarrer** : `switch.ml:478-557` sonde le
   `vde_switch` en boucle via un `stream_channel` en mode ligne — donc un `#shutdown` par
   sondage, c'est le chemin corrigé, exercé des dizaines de fois par minute ;
4. ouvrir la console (xterm) puis un client X dans l'invité (`xeyes`) — chemin `x.ml` /
   `machine.ml` (`Socat.*_of_stream_server`), impacté par les `~cloexec` de l'ép. 2 ;
5. après ~2 min de simulation, reprendre le compte de descripteurs : il doit être **stable** ;
   vérifier aussi qu'aucun socket de Marionnet n'apparaît dans `/proc/<pid xterm>/fd` ;
6. arrêter les composants, fermer le projet, quitter. Le journal ne doit contenir ni `EBADF`,
   ni `Bad file descriptor`, ni exception `Closing` inattendue.

⚠️ Ce protocole est **erroné sur trois points** ; voir l'épisode 2c pour la version corrigée.

### 2026-08-03 — épisode 2c : la fumée GUI, et le protocole qui ne mesurait rien

Aucune ligne de code touchée : cet épisode ne produit que de la **preuve**, et une rectification
du protocole.

**Le protocole de l'ép. 2b ne pouvait pas conclure.** Sa dette (« le chemin `input_line`/
`output_line` n'a jamais été atteint ») avait été imputée à un défaut extérieur — B6 de
`marionnet-automate-composants`, qui empêchait le switch de finir son démarrage. Attribution
**au mieux incomplète** : la lecture de `bin/switch.ml` montre trois erreurs propres au protocole.

1. **Le sondage est conditionnel** (`switch.ml:588`) :
   `match show_vde_terminal || (rcfile_content <> None) with | false -> super#spawn_internal_cables`.
   Un switch ordinaire n'ouvre **jamais** de canal ligne. Le geste GUI décisif — absent du
   protocole — est de cocher **« Show VDE terminal »** dans le dialogue du switch
   (`switch.ml:249,263`).
2. **Le critère d'observation était intestable.** `grep -c "port/print"` ne peut rien donner :
   `ask_vde_switch_for_current_active_ports` et `wait_vde_switch_until_ports_will_be_allocated`
   (`switch.ml:487-499`) **ne journalisent pas** la commande envoyée. La chaîne `port/print`
   n'apparaît que dans deux fonctions marquées *currently unused*. Le « 0 » relevé à l'ép. 2b ne
   prouvait donc rien — ni dans un sens ni dans l'autre.
3. **La fréquence annoncée était fausse.** « Un `#shutdown` par sondage, des dizaines de fois par
   minute » : non. Le chemin n'est emprunté qu'à `spawn_internal_cables`, c'est-à-dire **au
   démarrage du switch**, une fois plus une fois par câble interne. Pour accumuler des cycles, il
   faut **cycler stop/start** — ce que le protocole ne demandait pas.

Accessoirement, le binaire est `_build/default/bin/marionnet.exe` (`public_name` = `marionnet.native`),
et non `_build/default/bin/marionnet.native`.

**Critères de succès, fixés avant la mesure** (et non déduits après coup) : C1 le canal ligne est
ouvert et lu ; C2 les cycles par câble interne tournent ; C3 aucune fermeture fautive ; C4 aucune
fuite de descripteurs ; C5 aucun socket hérité par un `exec`.

**Session jouée** : `marionnet.exe -d`, projet neuf, switch S1 **avec « Show VDE terminal »**,
machines m1 et m2 câblées, démarrage complet, deux cycles stop/start de S1, console xterm sur m1
avec client X dans l'invité, ~9 minutes, puis extinction et sortie propre. Compte de descripteurs
et de threads échantillonné toutes les 15 s.

| Critère | Mesure | Verdict |
|---|---|---|
| C1 — canal ligne exercé | `has currently … active ports` : **3** (démarrage + 2 redémarrages) | satisfait |
| C2 — cycles par câble interne | `has now … allocated ports` : **12** (4 câbles × 3 démarrages) | satisfait |
| C3 — fermeture fautive | `EBADF` / `Bad file descriptor` / `Closing` : **0** | satisfait |
| C4 — fuite de descripteurs | **20-21 fd, stables**, pendant que les threads passaient de 16 à **71** | satisfait |
| C5 — `CLOEXEC` en GUI | **non relevé** : le xterm était éteint avant la vérification | non couvert |

C4 est le résultat le plus parlant : le nombre de descripteurs n'a pas bougé d'une unité alors que
le processus montait à 71 threads et que douze cycles de canal ligne — donc jusqu'à trois
descripteurs par canal, ouverts puis rendus — s'étaient succédé. C'est exactement ce que le
correctif N1 promettait, et ce que `dune test` ne pouvait pas prouver à cette échelle.

C5 reste adossé au seul test unitaire N2 (« *no socket is inherited by an exec'ed child* »,
discriminant) : à relever pendant la session GUI de l'épisode 3, tant que le xterm est vivant.

**Deux constats de terrain, en prime.**

- **N4 confirmé hors banc de test** : **zéro** `Thread.Exit`, zéro *uncaught exception* dans
  1293 lignes de journal. Les deux boucles d'acceptation du relais X11 se terminent sur
  `Accepting(_)` à l'extinction — comportement voulu de la garde N3 — et aucune n'a eu à
  journaliser de *transient failure* (rien d'anormal : la charge ne provoquait pas d'`EMFILE`).
- **N9 observé en conditions réelles** : `Network.stream_channel#receive: Failure("received 0 bytes
  (peer terminated?)")`, deux fois, à la fermeture **normale** du relais X11, juste avant
  `crossover_link: joined both threads`. La fin de session propre est bien journalisée comme une
  erreur ; le serveur de contrôle devra traiter ce cas comme une terminaison ordinaire (§ 7.5, N9).

**Conclusion.** La dette de l'épisode 2b est levée : les correctifs de `network.ml` tiennent en
GUI réelle, sur le chemin qu'ils modifient. L'épisode 3 peut commencer — l'instrument de mesure
est validé.

---

### 2026-08-03 — épisode 3a : le canal de contrôle existe, et il ne ment plus

Premières lignes de `bin/` du chantier. Trois fichiers : `bin/control_server.ml` (nouveau),
`bin/initialization.ml` (+1 option), `bin/marionnet.ml` (SIGPIPE + démarrage du thread).
`bin/dune` n'a **pas** été touché — cf. la rectification du § 3.5.

**Trois questions de conception ont été tranchées avant d'écrire**, chacune parce qu'elle
changeait l'ossature et non le détail : le transport d'un contenu **multi-ligne** (→ chemin de
fichier, § 4.1), la sémantique d'**`open`** (→ synchrone, § 4.2), et la protection contre un
**thread GTK bloqué** (→ échéance côté serveur). Cette dernière mérite d'être justifiée : la GUI
reste vivante *et* un humain peut être devant l'écran ; un menu déroulé suffit à figer la boucle
GTK. Sans échéance côté serveur, le client raccroche après *son* délai (§ 8), le thread serveur
reste pendu (**N10**), puis écrit dans un socket fermé (**N18**) — les trois défauts de l'audit se
tiennent, et il fallait les traiter ensemble. D'où `GMain_actor.future` + `Future.taste`, défaut
5 s, `--timeout=N` par commande.

**Le premier critère de succès d'`open` était menteur, et la mesure l'a montré.** La version
initiale concluait au succès si le projet actif portait le nom demandé. Or l'ouverture d'un fichier
texte quelconque a répondu `{"ok":true,…,"nodes":0}` : Marionnet **positionne le nom de fichier
même quand le chargement échoue** (l'exception est ravalée en dialogue non modal,
`state.ml:537-547`, `567-580`). Le critère retenu s'appuie sur `project_already_saved`, que
`register_state_after_save_or_open` (`state.ml:551`) ne met à vrai **que** sur le chemin de succès —
mesuré dans les deux sens : `true` après `tp.mar`, `false` après le fichier mal formé. Un projet
légitimement vide répond toujours `ok` avec `nodes:0`, puisqu'il passe par cette même ligne.

**N18 est corrigé, et la preuve est discriminante.** Neutraliser `SIGPIPE` n'est utile que si son
absence tue : la même série de 40 clients qui raccrochent sans lire leur réponse a été jouée deux
fois. Avec `Sys.Signal_default` (témoin), Marionnet meurt **à la 3ᵉ itération** — « Relais brisé
(pipe) », aucune trace dans le journal, exactement le motif annoncé. Avec `Sys.Signal_ignore`, il
survit aux 40 et continue de servir. Le signal est posé dans `bin/marionnet.ml` : une disposition
globale appartient au programme, pas à une bibliothèque vendored.

**Mesures de la session finale** (mode `--debug`, 23 connexions servies) : **0** `Thread.Exit`,
**0** *uncaught exception*, **0** `EBADF`, **0** `Closing`. Le plafond de sessions (**N10**, 8)
refuse la 9ᵉ connexion et rend le jeton dès qu'une session se termine. Le socket est nettoyé à la
sortie propre (**N12**), et son répertoire parent est bien `drwx------` alors que le socket lui-même
reste `srwxrwxrwx` : la parade du § 3.4 fait exactement ce qu'elle annonce.

**Deux limites assumées, à traiter plus tard.** (a) Une session refusée pour cause de plafond reçoit
sa réponse JSON puis voit sa connexion coupée sans `shutdown` ordonné (`Connection reset by peer`
côté `socat`) — le client est servi, mais la fermeture pourrait être plus propre. (b) Une fin de
session normale laisse une ligne `stream_channel#input_line: End_of_file` dans le journal *debug* :
c'est `network.ml` qui journalise avant de lever (**N9**), et le corriger supposerait de toucher
`lib/` vendored pour un simple bruit de trace.

**Reste à l'épisode 3b** : le critère **C5** (aucun descripteur du canal de contrôle dans
`/proc/<pid xterm>/fd`, xterm **vivant**), qui suppose une session GUI interactive avec des
composants démarrés.

---

### 2026-08-03 — épisode 3c : les fenêtres n'attendent plus un humain

**Le point aveugle.** La conception ne parlait des dialogues que comme d'un *risque à éviter*
(§ 3.3 « jamais de *callback* GUI », § 8 « `apply` bloque si le thread GTK est pris par un modal »).
L'épisode 3a n'avait posé qu'une **échéance côté serveur** : elle protège le serveur d'un blocage,
elle ne ferme rien. Le mot « splash » n'apparaissait nulle part. Or Marionnet ouvre des fenêtres de
lui-même, et en session pilotée elles restent — avec leur contenu.

**Ce que l'inventaire a corrigé dans la représentation qu'on s'en faisait.** Trois constats, tous
vérifiés dans le code avant d'écrire une ligne :

1. **Aucune confirmation n'est atteignable par le script**, contrairement à ce qu'on pouvait
   craindre. Les deux appelants de `confirm_dialog` sont les boutons « tout arrêter » / « tout
   éteindre » (`gui_window_MARIONNET.ml:158,167`), et `ask_question` sert le patron
   `Menu_factory.Make_entry` : tous partent d'un geste humain. Mieux, `st#quit_async ()`
   (`state.ml:987`) planifie l'arrêt **sans rien demander** — la commande `quit` était déjà propre.
   Le traitement des questions est donc un **filet instrumenté**, pas une fonctionnalité.
2. `yes_no_or_cancel` (`gui_bricks.ml:421`) n'a **aucun appelant** : code mort, non instrumenté.
3. Les dialogues de composants (`gui_dialog_toolkit.ml:70`, `talking.ml:294,460`) sont **hors
   périmètre** : les toucher dégraderait l'usage interactif sans rien apporter au script.

**Un cycle de dépendances a dicté la forme du module.** `script_mode.ml` ne lit pas la ligne de
commande, alors que c'est le plus naturel : `initialization.ml` dépend de `user_level.ml`, qui
dépend de `simple_dialogs.ml`, qui utilise `script_mode.ml`. La lecture des options aurait bouclé.
D'où `Script_mode.configure`, appelé par `marionnet.ml` — la racine — **avant** que quoi que ce soit
puisse afficher une fenêtre (le sondage du *tap provider* ouvre déjà un avertissement).

**Le garde-fou des questions a été resserré en cours de route.** La première version conditionnait
l'auto-réponse à un compteur global « une commande est en vol ». C'était faux : `open` charge le
projet **dans le thread serveur** et dure plusieurs secondes, pendant lesquelles un clic humain sur
« tout éteindre » aurait perdu sa confirmation. Le marqueur retient donc le **thread** qui sert la
commande ; un *callback* déclenché par un clic tourne dans le thread GTK, jamais enregistré.

**Mesures (2026-08-03).** Deux témoins, un banc scripté, une contrainte de terrain rencontrée en
chemin : `sun_path` est limité à 108 octets et le chemin du bac à sable de session le dépasse
(`ENAMETOOLONG`) — le socket de test vit dans `$XDG_RUNTIME_DIR`, qui est court **et** déjà `0700`
(la garde de l'épisode 3a refuse un répertoire parent accessible en écriture au groupe).

| Épreuve | Mode armé | Témoin `--keep-dialogs` |
|---|---|---|
| `open tp.mar` (projet mandriva de 2010) | `ok`, 7 nœuds, **2 notifications** dont le récapitulatif et ses **6 ajustements** détaillés (images `mandriva20100215` → `debian-wheezy-08367`, noyaux `2.6.18-ghost` → `6.12.95-i386`) | `notifications: []` |
| `open /etc/hostname` (fichier mal formé) | `ok:false` **et la cause capturée** : « Échec lors du chargement du projet… vérifier que le fichier est bien formé » | `notifications: []` |
| `notifications --since=0` | `enabled:true`, `count:3`, `last_seq:3` | `enabled:false`, `count:0` |
| splash (session laissée au repos) | affiché **et fermé** | affiché, **jamais fermé** |
| fenêtres X après chargement | **2** (fenêtre technique + fenêtre principale) | **5** : + « Project adapted at loading », + « Avertissement », + « Bienvenue dans Marionnet » |

Une session ordinaire (sans `--control-socket`) a été rejouée pour la non-régression : `Script_mode`
reste désarmé, le splash s'affiche et attend son clic, comme toujours.

**Un enseignement de mesure, à ne pas perdre.** L'auto-fermeture dépend d'un `GMain.Timeout`, donc
d'une boucle GTK qui a un créneau. Quand le script enchaîne les commandes sans répit, la boucle est
saturée par les `apply_extract` du chargement et les fenêtres restent visibles **plus longtemps que
le délai annoncé** — elles partent dès que le thread principal respire. C'est ce qui a fait échouer
la première mesure du splash, dans une session où `open` monopolisait la boucle du début à la fin.
Un script qui veut un écran propre doit donc laisser un temps mort, ou ne pas s'en soucier : la
capture, elle, est synchrone et n'attend rien.

**Reste à l'épisode 3b** : le critère **C5**, inchangé.

---

### 2026-08-03 — épisode 3b : le descripteur qui ne fuit pas

**Le motif de l'ajournement était devenu faux.** Les épisodes 2c puis 3a ont repoussé C5 en le
disant tributaire d'« une session GUI interactive avec des composants démarrés ». Or l'option
`-r`/`--run` existe depuis toujours (`bin/initialization.ml:64`) et déclenche
`st#startup_everything ()` (`bin/marionnet.ml:431`) : la session pilotée démarre tout seule.
Mieux, l'ordre du code rend le volet le plus délicat — l'héritage du socket **de session**, et
pas seulement de l'écoute — **déterministe plutôt qu'aléatoire** : le serveur est démarré en
`bin/marionnet.ml:519`, soit après le chargement du projet et **avant** `main_loop ()` (l.521),
tandis que `startup_everything` n'est armé que par un `GMain.Timeout ~ms:1000`. Un client qui se
connecte dès l'apparition du socket est donc connecté **avant** le premier `exec` de composant.
Aucun clic humain, aucune course à gagner.

**Le banc** (`_claude-local/bench/c5-bench.sh`, hors dépôt) : lance Marionnet `--debug
--control-socket … -r tp.mar`, connecte un client persistant dès que le socket paraît, attend
qu'un xterm **vivant** existe, relève par `ss -xap` les inodes du canal, puis balaie
`/proc/<pid>/fd` de **tous** les processus lisibles — pas seulement les descendants, parce qu'un
enfant peut avoir été `setsid`é ou réattaché à `init`.

**La mesure porte sur un canal complet, et `ss` le prouve** : au moment du balayage, l'écoute
(inode `8771841`) est tenue par le fd 19, et le socket de service (inode `8771842`) par **trois**
fds de Marionnet — 18, 20 et 23, c'est-à-dire l'accepté plus les deux `Unix.dup` des canaux
stdlib introduits à l'ép. 2b. Les trois familles de descripteurs étaient donc bien présentes,
et pas seulement celle qu'on visait.

| Épreuve | Armé (code du dépôt) | Témoin (`~cloexec` retiré) |
|---|---|---|
| descripteurs du canal hors Marionnet | **0** sur **395** processus inspectés | **351** sur **88** processus |
| répartition | — | 30 `vde_switch`, 28 `wirefilter`, 21 noyaux `linux-6.12.95-i386`, 3 `xterm`, 3 `port-helper`, 2 `slirpvde` |
| xterm vivant à la mesure | oui (pid relevé, 6 s après le lancement) | oui — et il tient `19 → socket:[…040]` (écoute) plus `20,22,23 → socket:[…041]` (session ×3) |
| canal encore servi en fin de mesure | oui (`status` → 7 nœuds) | oui |

**Le témoin est ce qui donne son sens au « 0 ».** Il consiste à retirer `~cloexec:true` des cinq
emplacements du chemin serveur — création de l'écoute (`network.ml:218`), les deux `accept`
(l.112, l.129), les deux `dup` (l.578-579) — puis à rejouer le **même** banc, avant de restaurer
(`git checkout`, `dune build` et `dune test` verts, `git diff` vide sur `lib/`). Sans lui, un
verdict à zéro n'aurait rien prouvé d'autre que la capacité du script à ne rien trouver — c'est
la leçon de l'ép. 2c, où le protocole publié mesurait un critère intestable.

**Ce que le témoin apprend au-delà du pass/fail.** La fuite n'aurait pas été marginale : pour un
projet de 7 nœuds, **chaque** processus exec'é en hérite, y compris les 21 noyaux invités. Un
noyau UML tenant le socket de contrôle de son propre hôte, c'est la frontière hôte/invité percée
par un descripteur — et un orphelin gardant l'écoute, c'est le motif exact du port-helper qui
squattait `:6000` (`bin/marionnet.ml:475-500`).

**Un enseignement de terrain, payé comptant.** Les enfants **survivent** à la mort de Marionnet :
la première version du banc est sortie en silence (un `((waited++))` valant 0 sous `set -e`) après
avoir tué le père, et a laissé **13** `vde_switch`/`wirefilter`/`slirpvde` orphelins. C'est
précisément le scénario que N2 prévient, observé par accident. Corollaire pour tout banc futur :
nettoyer par **répertoire de session** (`/tmp/marionnet-<N>.dir`, propre au run) et jamais par
`pkill -f marionnet`, qui se tue lui-même. Le banc corrigé sort désormais 0 orphelin et 0 fenêtre.

**Aucune ligne de code applicatif n'a été touchée** : l'épisode est une mesure, et son résultat
est que le correctif N2 (ép. 2) et le cycle de vie des descripteurs de l'ép. 2b tiennent en
session réelle. C5 est le dernier critère de sûreté de l'ép. 3 ; l'épisode 3 est clos.

---

### 2026-08-03 — épisode 4a : l'automate, contrat du script

**L'exigence, posée par l'auteur avant que l'ép. 4 ne commence** : un script doit avoir *les mêmes
possibilités et les mêmes limites* qu'un humain devant la GUI — un composant suspendu se réveille
mais ne se démarre pas, un composant en marche ne se supprime pas. La question posée était :
est-ce déjà prévu, et faut-il un chantier dédié à définir explicitement cet automate ?

**Réponse mesurée sur le code : à moitié prévu, et le trou n'est pas là où on l'attendait.**
Les transitions d'exécution étaient couvertes (§ 4.3, `ls --can=…`) et l'automate est explicite
depuis longtemps — quatre états, cinq prédicats (`user_level.ml:417-450`). Mais **`del` et `set`
échappaient entièrement au raisonnement** : leur garde n'existe que dans la GUI, où
`Remove.dynlist = Properties.dynlist = get_node_names_that_can_startup`, uniformément sur les sept
composants-nœuds. Aucun `can_destroy` dans le modèle. Le serveur, qui n'appelle que le modèle
(§ 3.3), aurait donc détruit des composants en marche — et l'aurait fait *en croyant respecter
l'automate*, puisque le § 4.3 laissait entendre que `--can=…` suffisait.

**Trois autres constats, chacun capable de fausser une commande.** (a) Les méthodes de transition
sont gardées mais **muettes** (`user_level.ml:212-237`) : un `start` illégal est un no-op
silencieux, et un serveur qui se fierait au retour répondrait `ok` sans rien avoir fait — le motif
d'échec silencieux qui court dans tout ce chantier. (b) Le menu **par composant** n'offre que six
entrées (*Properties*, *Remove*, *Startup*, *Stop*, *Suspend*, *Resume* — la signature même du
foncteur de disposition, `gui_toolbar_COMPONENTS_layouts.ml:118-127`) : ni `poweroff`, offert
seulement globalement
(`state.ml:962`), ni `restart`, déclenché uniquement par une édition de treeview après
confirmation (`marionnet.ml:169-175`). Le § 4.4 prévoyait pourtant les deux comme commandes de
composant : ce sont des **extensions** au-delà de la GUI, et il fallait le dire plutôt que le
laisser passer. (c) `can_poweroff` n'a **aucun lecteur** — dette relevée, pas traitée.

**Ce que la GUI sait et que le modèle ignore, le modèle doit l'apprendre.** Décision actée avec
l'auteur : `can_destroy` et `can_modify` descendent dans `user_level.ml`, surchargés à `true` pour
les câbles, et la GUI comme le serveur lisent ces prédicats — source unique de vérité. L'option
« recopier la règle dans le serveur » a été écartée : deux vérités divergent toujours, et c'est
précisément ce dont on sortait.

**Les câbles sont l'exception qui valide la démarche.** Leur `Properties.dynlist` est `all_names`
(`cable.ml:127`) : un câble se modifie et se supprime **en marche**, conformément à la règle de
projet « le câblage suit la réalité » et à l'ép. 12 du chantier de l'automate. Un serveur qui
aurait généralisé la règle des nœuds « par symétrie » aurait été *plus restrictif* que la GUI —
la même erreur, en miroir, que celle commise à l'ép. 8 de ce chantier-là.

**Pas de nouveau chantier.** L'automate a déjà été audité et refondu de bout en bout
(`marionnet-automate-composants`, 16 épisodes, clos ; C1 à C5 y sont écrits). Ce qui manquait
n'était pas de le *définir* mais d'en **publier la table** à l'usage du script et de combler un
trou précis. D'où le § 4.10, et un ép. 4 découpé : 4a (ce document), 4b (les prédicats et la
commande `can`), 4c (le noyau des commandes).

**Aucune ligne de code touchée.** La preuve attendue d'un épisode de conception n'est pas une
exécution mais l'exactitude de ses ancres : chaque garde de la table du § 4.10 a été relue dans
le source le jour même, y compris les sept couples `Properties`/`Remove` un par un.
