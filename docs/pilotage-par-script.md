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
`unknown_node`, `forbidden_transition`, `unsaved_changes`, `timeout`, `internal`.

**Contenu multi-ligne : par chemin de fichier** (tranché à l'ép. 3a). Un rcfile de scénario (§ 10)
ou un fragment `Xforest` (§ 4.8) ne tient pas sur une ligne. Plutôt que d'ajouter un mode « corps »
au protocole (sentinelle de fin, donc un **état** dans le lecteur et un cas d'erreur de plus) ou un
encodage base64 (illisible, et un décodeur à écrire), la commande reçoit un **chemin** :
`--from=/chemin/fichier`, que le serveur lit côté hôte. Le lecteur reste un `input_line` **nu**, et
le mécanisme couvre rcfile et forest d'un seul geste. Légitime ici : un socket unix implique la
même machine, et le répertoire `0700` borne déjà l'accès au canal. Côté client, un heredoc Bash
vers `mktemp` fait le reste.

**Options et arguments positionnels.** Les jetons commençant par `--` sont des options
(`--clé=valeur`, ou `--clé` seule pour un drapeau), **où qu'ils se trouvent sur la ligne** ; les
autres sont les arguments positionnels.

**Arité déclarée, dernier argument en texte libre** (tranché à l'**ép. 4d**). La commodité de
l'ép. 3a — « tous les jetons non-`--` rejoints par un espace » — ne valait que tant qu'une
commande avait **au plus un** argument positionnel. `connect c1 m1:eth0 s1:port1` et `set m1 label …`
la rendent ambiguë. La convention retenue **n'est pas** une citation à la shell :

| | |
|---|---|
| Chaque commande **déclare** `(min, max, dernier libre ?)` | table `arity_of_command`, `bin/control_server.ml` |
| Surplus de jetons, dernier **libre** | rejoints par un espace dans ce dernier argument |
| Surplus de jetons, commande **stricte** | `bad_argument`, avec la syntaxe de la commande dans le `detail` |
| Manque | `bad_argument`, idem |

Le fondement est une propriété du domaine, pas une préférence : **un nom de composant est un
identifiant** (`check_name` → `StrExtra.Class.identifierp`, `user_level.ml:521`), donc sans
espace ; seuls un **chemin** et une **valeur libre** (un label) en contiennent, et l'un comme
l'autre est toujours en **dernière** position. Une citation shell-like aurait coûté une machine à
états, un code d'erreur de plus, et surtout un **second niveau d'échappement** côté client Bash —
qui a déjà fait le sien — pour un problème que ce canal n'a pas.

```
open /home/jean/mon projet.mar   ->  1 argument : "/home/jean/mon projet.mar"   (dernier libre)
connect c1 m1:eth0 s1:port1      ->  3 arguments                                (strict)
connect c1 m1:eth0 s1:port1 zut  ->  {"ok":false,"error":"bad_argument", …}
ls foo                           ->  {"ok":false,"error":"bad_argument", …}     (0 positionnel)
```

Deux conséquences assumées : `ls foo` était **accepté et ignoré**, il est maintenant refusé —
c'est le comportement attendu d'un instrument, un argument avalé en silence est un bug qui se
cache ; et les espaces **consécutifs** d'un argument libre sont normalisés en un seul, les jetons
étant rejoints plutôt que découpés dans la ligne brute (limite héritée de l'ép. 3a, sans
conséquence connue).

**`--timeout=N`** est accepté par toute commande qui interroge le thread GTK (§ 8).

### 4.2 Projet

| Commande | Correspondance modèle | |
|---|---|---|
| `new <fichier> [--save\|--no-save]` | `st#new_project ~filename` (`state.ml:325`) | **ép. 4d** |
| `open <fichier>` | `st#open_project_async ~filename` (`state.ml:577`) | ép. 3a |
| `save` / `save-as <fichier>` | `st#save_project` (l.813) / `st#save_project_as` (l.820) | **ép. 4d** |
| `close [--save\|--no-save]` | `st#close_project` (l.357) | **ép. 4d** |
| `quit` | `st#quit_async` (l.987) | ép. 3a |
| `status` | `st#active_project`, `st#runnable_project`, `st#project_already_saved` | ép. 3a |

**Le menu n'appelle pas la méthode qui porte son nom** (ancrage : `gui_menubar_MARIONNET.ml:94-105`
et `262-278`). Pour « Nouveau » et « Fermer », il exécute — **dans un `Thread.create`**, donc hors
thread GTK, exactement comme le thread qui sert une commande — la séquence :

```
shutdown_everything ()  →  [save_project]  →  close_project  →  [new_project]
```

Le canal reproduit cette séquence, **la question modale en moins**. Une confirmation
interactive ne s'émule pas honnêtement ; elle s'**exige** : sans `--save` ni `--no-save`, `close`
et `new` sur un projet portant des modifications non enregistrées répondent **`unsaved_changes`**.
Le seul autre choix aurait été de jeter le travail de quelqu'un en silence.

Quatre points de contrat, chacun mesuré :

1. **Appel direct depuis le thread serveur, jamais via `GMain_actor`** : `close_project` et
   `save_project` testent `am_I_the_GTK_main_thread` et s'exécutent **dans le thread appelant**
   quand il n'est pas celui de GTK (`state.ml:357-360`, `813-816`) — même leçon qu'`open`.
2. **Ces commandes sont bloquantes**, et `close` l'est autant que l'arrêt du réseau :
   `shutdown_everything` ne fait qu'**enfiler** (`schedule_parallel`, `state.ml:956-960`), c'est
   `close_project` qui attend le `task_runner` (l.346). Mesuré : `close --no-save` sur un réseau
   en marche rend la main **après** « I have joined "Shut down m1" with success ». Un client a
   besoin d'un délai de lecture généreux — `--timeout`, lui, ne borne que l'aller-retour GTK.
3. **`--save` signifie « sauve *puis* ferme »** : si la sauvegarde échoue, rien n'est fermé et la
   réponse le dit. C'est délibérément **plus strict que le menu**, qui ferme quand même.
   `private_save_project` rattrape ses propres échecs et les signale par un dialogue
   (`state.ml:800-810`) : l'absence d'exception ne prouve rien, le critère est
   `project_already_saved`.
4. **Aucune extension n'est ajoutée** au nom de fichier : le helper du menu
   (`Talking.check_filename_validity_and_add_extension_if_needed`) ouvre des dialogues
   (`talking.ml:119-131`), et un script qui écrit `/tmp/tp.mar` sait ce qu'il veut. Le chemin doit
   être **absolu** (Marionnet a fait `chdir` vers sa propre racine au démarrage).

⚠️ Le champ `saved` de `status` n'a de sens **que si `active` est vrai** : après une fermeture il
conserve la valeur qu'il avait, l'état global n'étant pas réinitialisé (observé, inchangé depuis
toujours).

⚠️ `open` est **asynchrone** (retourne un `Thread.t`) — **tranché à l'ép. 3a, et le nom trompe** :
appelé depuis un thread qui n'est pas `gtk_main`, `open_project_async` exécute le chargement
**dans le thread appelant** (`state.ml:594-596`), sans en créer un autre. Le serveur l'appelle donc
**directement** — surtout pas via `GMain_actor`, qui le ferait basculer sur la branche « je suis
gtk_main » et rendrait la main aussitôt, résultat perdu. La commande est ainsi **bloquante**, ce
qu'un script veut. Restait à ne pas mentir : voir le § 11 (journal de l'ép. 3a), où le premier
critère de succès s'est révélé menteur et a dû être remplacé.

### 4.3 Composants

| Commande | Correspondance modèle | |
|---|---|---|
| `add <kind> <nom> [--ports=<n>] [--<champ>=<valeur>]…` | constructeur `new <Kind>.User_level_<kind>.<kind> ~network ~name …`, sous `st#network_change` | **ép. 4d-2a** |
| `del <nom>` | `#destroy` sous `st#network_change` (patron `Remove.reaction`, ex. `hub.ml:117-119`) | **ép. 4d-2a** |
| `get <nom> [<champ>]` | `#to_tree` (`machine.ml:637`, `cable.ml:715`…) | **ép. 4d-2a** |
| `set <nom> <champ> <valeur>` | `#eval_forest_attribute` (`machine.ml:652-666`) sous `network_change` | **ép. 4d-2a** |
| `set <nom> name\|port_no <valeur>` | `#update_structural_with` (`user_level.ml`) sous `network_change` | **ép. 4d-2b** |
| `rename <ancien> <nouveau>` | idem — même code, autre verbe | **ép. 4d-2b** |
| `ls [--kind=…] [--can=<action>]` | `network#get_node_list` (l.1537) puis les prédicats du modèle, lus par `eligibility_of_node` | ép. 4b |

**Une seule source pour le vocabulaire des champs : `#to_tree`.** C'est ce qu'un `.mar` enregistre ;
c'est donc, sans rien inventer, ce que `get` sert, ce contre quoi `set` valide son champ, et ce que
les options `--<champ>=` d'`add` peuvent viser. Un champ inconnu est **refusé** (`bad_argument`, avec
la liste des champs de ce composant) et non ignoré : `eval_forest_attribute` ignore silencieusement
ce qu'il ne connaît pas (`| _ -> ()`, forward-compatibilité avec les `.mar` futurs), donc une faute
de frappe y disparaîtrait sans trace.

**Deux refus, chacun fondé sur une propriété du modèle :**

1. **Champs marshalés.** `rc_config` (`machine.ml:645`, `switch.ml:455`) et les quatre du routeur
   (`rc_config_unix`, `rc_config_quagga`, `quagga_selected_srvs`, `show_quagga_terminal`) sont écrits
   par `Marshal.to_string` : ce ne sont pas des textes. Les servir mettrait de l'UTF-8 invalide au
   milieu d'une ligne JSON, les accepter reviendrait à demander à un client shell de forger des
   octets marshalés. Ils relèvent de `rc-set`/`rc-get` (§ 10, ép. 4e). Le serveur ne les **énumère
   pas** — une liste vieillirait dès qu'un composant en ajoute un : il les reconnaît à leur en-tête
   (`0x8495A6BD/BE/BF`, les trois nombres magiques de `Marshal`). Ils sont rendus `null` et **nommés**
   dans le champ `omitted` de la réponse, jamais escamotés.
2. **État du composant.** `set` teste `can_modify` et `del` teste `can_destroy` — les prédicats
   descendus dans le modèle à l'ép. 4b — et répondent `forbidden_transition` sinon. Le **§ 4.10 fait
   autorité** ; rappel de son exception : un **câble** s'édite et se supprime **en marche**.

**Les champs structurels — `name` et `port_no` (ép. 4d-2b).** Les écrire n'est pas « écrire un
champ » : renommer un composant renomme aussi ses lignes du treeview **defects**, et pour une
machine ou un routeur ses lignes **ifconfig** et **history** ainsi que son **répertoire hostfs** ;
changer le nombre de ports reconstruit la carte de ports et le sous-arbre defects. Le chemin est
donc celui du modèle, `#update_structural_with ~name ~port_no` (`user_level.ml`) : la **moitié
structurelle** des huit `update_<kind>_with` qu'appellent les dialogues de la GUI, factorisée pour
qu'un appelant qui ignore la nature du composant emprunte exactement la même voie. Elle est
déclarée sur `node_with_ports_card` — la classe qui *est* le type `node` — implémentée une fois
pour `node_with_defects` et `node_with_ledgrid_and_defects`, et surchargée dans `machine.ml` et
`router.ml` pour préfixer `update_virtual_machine_with` (dans **cet** ordre : il renomme en lisant
`self#get_name`, donc avant que le nom ne change). Aucun `Obj.magic` n'a été ajouté, et le serveur
ne connaît toujours pas les natures. Quatre gardes, **toutes lues dans le modèle**, précèdent
l'action :

- `can_modify` (§ 4.10) → `forbidden_transition` ;
- le nouveau nom doit être un **identifiant** (`StrExtra.Class.identifierp`) et **libre**
  (`network#name_exists`) — les deux tests que fait le dialogue GUI avant d'appeler le modèle
  (`Gui_bricks.Ok_callback.check_name`). Le serveur les garde **pour la qualité du refus** (un
  `bad_argument` motivé plutôt qu'un texte d'exception), non plus pour la sûreté : depuis
  l'épisode 4d-2c, `User_level.check_new_name` les rejoue **dans le modèle**, en première
  instruction des cinq chemins destructeurs (`update_virtual_machine_with`, les deux `set_name`
  redéfinis, les deux `update_with`). Auparavant le chemin de renommage n'était **pas atomique** —
  les lignes et le répertoire étaient renommés *avant* que `set_name` ait l'occasion de refuser le
  nom, et un `rename m1 1m` refusé à mi-chemin laissait la ligne ifconfig de `m1` nommée `1m` ;
- `port_no` doit être un entier compris entre `node#port_no_min` et `node#port_no_max`, mais la
  borne basse réellement appliquée est **`network#port_no_lower_of node`** (`user_level.ml:1836`) —
  celle que le dialogue GUI calcule lui aussi (`hub.ml:91`) : on ne réduit pas le nombre de ports
  en dessous du plus grand port **occupé par un câble**. Le refus dit **laquelle** des trois causes
  s'applique (ports fixes, minimum de la nature, câbles branchés au-dessus).

Une valeur identique à l'actuelle est un **no-op** : `changed:false`, et rien n'est reconstruit
(`update_with` détruit le device simulé au passage — un renommage vers le même nom ne doit pas le
payer). `rename <ancien> <nouveau>` est **le même code** sous un autre verbe, pas une seconde
implémentation à tenir en phase.

⚠️ **Un câble ne se renomme pas** : `set <câble> name` est refusé. Ce n'est pas un trou dans le
contrat mais la réponse de la GUI elle-même — un câble n'y est jamais renommé, il est **détruit et
recréé** (`cable.ml:158-176`, `c#destroy` puis `Add.reaction` réenfilé sur le `task_runner`), ce qui
reconstruit son entrée defects, ses extrémités et ses compteurs de références. Le canal offrira ce
chemin sous la forme `del` + `connect` (§ 4.5) ; renommer un câble en place laisserait son entrée
defects sous l'ancien nom, `cable#set_name` n'étant pas redéfini.

**`add`.** Le `<kind>` est celui de `ls --kind=` et de la racine d'un `.mar` : le canal n'a qu'un
vocabulaire (`machine`, `router`, `switch`, `hub`, `cloud`, `world_bridge`, `world_gateway` ; un
câble se crée par `connect`, § 4.5). Le serveur appelle **le constructeur**, pas le registre
`try_to_add_*` — celui-ci aurait été uniforme, mais il **avale l'erreur** (`with _ -> false`,
`machine.ml:545`) et exige `port_no`, alors que le bon défaut est **local à chaque fichier**
(`Const.port_no_default` : machine 1, hub/switch/routeur/world_gateway 4, cloud 2, world_bridge 1) ;
le constructeur le prend là où il est défini au lieu d'en recopier sept ici. `--ports` sur un
composant à ports fixes (cloud, world_bridge) est **refusé** plutôt qu'avalé.
Les autres `--<champ>=<valeur>` sont appliqués après construction, avec les mêmes refus qu'au-dessus,
et **un échec ne laisse rien** : le composant à peine créé est détruit, de sorte qu'un `add` refusé
signifie un réseau inchangé. La réponse rend les champs **relus** dans le réseau, jamais supposés
(même exigence que l'échec silencieux ci-dessus). `--name=` et `--port_no=` restent **refusés ici**
même depuis l'ép. 4d-2b : dans `add`, le nom est le deuxième argument et le nombre de ports est
`--ports` — deux façons d'écrire la même chose inviteraient à les contredire.

**Le couple (distribution, noyau) — ép. 4f.** Une machine et un routeur portent deux champs qui ne
sont **pas indépendants** : le filesystem (`distrib`) et le noyau qui le démarre (`kernel`). Le
`.conf` du filesystem déclare ce qu'il supporte (`SUPPORTED_KERNELS`, lu par
`Disk.virtual_machine_installations#supported_kernels_of`, `disk.ml:272-330`) et le dialogue GUI
n'offre rien d'autre : le combo des noyaux est un **esclave** de celui des distributions, repeuplé à
chaque changement (`gui_bricks.ml:540-541`). Le modèle, lui, accepte **n'importe quel noyau
installé** (`check_kernel`) — délibérément : un `.mar` peut référencer un noyau qui échappe à
`SUPPORTED_KERNELS`, et durcir le *setter* rendrait ce projet impossible à charger. Trois
conséquences, toutes du même défaut trouvé par le banc de l'ép. 4e :

- **le défaut du constructeur suit désormais la distribution** (`user_level.ml`, classe
  `virtual_machine_with_history_and_ifconfig`) : à défaut de `?kernel`, c'est le **premier noyau
  déclaré par le filesystem** — exactement le choix du dialogue (`gui_bricks.ml:520-522`). Avant,
  c'était le défaut **global** (`kernels#get_default_epithet`, `3.2.64-ghost`), si bien qu'un
  `add machine m1` produisait un couple **non démarrable** : « couple
  (debian-trixie-47362,3.2.64-ghost) unknown! » au journal, puis un UML qui ne boote jamais. La GUI
  et le chargement d'un `.mar` passent toujours `?kernel` explicitement : eux ne changent pas ;
- **`set <n> kernel <k>` refuse, avant d'écrire, un noyau que le filesystem ne déclare pas**
  (`bad_argument`, avec la liste). La garde vit dans le **serveur**, qui possède le message ; le
  modèle n'expose que la **lecture** (`component#supported_kernels_if_any`, `None` pour les natures
  sans filesystem — même patron que `hostfs_directory_if_any`, ép. 4e). C'est la décision de
  l'ép. 4d-3 sur la garde « port libre », pour une raison mesurée cette fois : `check_kernel` durci
  casserait le chargement d'un `.mar` légitime ;
- **`set <n> distrib <d>` est accepté et réaligne le noyau** — la GUI, elle, **verrouille** ce combo
  une fois le composant créé (`gui_bricks.ml:529-531`, avec un « TODO: release this constraint »
  dans le code), mais le modèle n'a pas cette limite ; le canal la lève et paie la cohérence.
  Le réalignement est **rapporté**, jamais silencieux : la réponse de `set` porte un champ
  `adjusted` (`[{field, old, new}]`, vide le reste du temps), comme `del` nomme les câbles emportés.
  L'ajustement s'exécute **dans le même `network_change`** que l'écriture — restaurer un invariant
  que l'écriture vient de rompre fait partie de cette écriture. La valeur y est **relue** et non
  supposée : posé sur wheezy, le premier noyau déclaré (`3.2.64-ghost`) est aussitôt remappé par
  `remap_obsolete_kernel_at_import` en `6.12.95-i386` sur un hôte moderne.

Dans `add`, la même garde s'applique à `--kernel=`, et `--distrib=` est appliqué **en premier**
quel que soit l'ordre écrit par le client : il conditionne les autres champs, et valider
`--kernel=` contre le filesystem *par défaut* refuserait un couple pourtant valide. Un `--kernel=`
explicite et non supporté est **refusé** (avec le rollback complet d'`add`), jamais corrigé en
douce ; c'est seulement quand le script n'a pas nommé de noyau que le serveur en choisit un.

**`del`.** Supprimer un nœud supprime **les câbles qui y sont branchés** (`del_node_by_name`,
`user_level.ml:1843`) ; la réponse les nomme dans `cables_destroyed`, sans quoi le modèle du réseau
que tient le script divergerait silencieusement du nôtre.

⚠️ **La réponse de `set` porte la valeur relue** (`old`, `new`, `changed`), pas la valeur demandée :
certains setters normalisent (le label est *strippé*, une distribution absente est remappée), et
quelques champs sont **constants par construction** — ceux d'un câble décrivant ses extrémités
(`crossover`, `leftnodename`…) sont acceptés par `eval_forest_attribute` puis ignorés (`cable.ml`,
« these attributes have been already read »). Un client compare `new` à ce qu'il voulait.

⚠️ **Ces commandes passent toutes par `st#network_change`** (`state.ml:892-903`), qui marque le
projet modifié et **redessine le sketch**. Deux conséquences : le coût du créneau GTK croît avec la
taille du réseau (d'où `--timeout` sur un gros projet), et une mutation exige un **projet ouvert**
(`no_active_project` sinon).

`--can=<action>` prend un **nom d'action**, c'est-à-dire un nom de commande du § 4.4 — `set`,
`del`, `start`, `stop`, `suspend`, `resume`, `poweroff`, `restart` — et **non** un nom de prédicat
(`--can=start`, pas `--can=startup`). Un client n'a ainsi qu'un seul vocabulaire à connaître pour
tout le canal. Une action inconnue est **refusée** (`unknown_can`) plutôt que rendue par une liste
vide : dans un script, une faute de frappe doit se diagnostiquer, pas se lire « rien n'est permis ».
Un `--kind=` inconnu, lui, garde son comportement historique (liste vide), l'ensemble des natures
de composants étant ouvert.

`ls` ne liste que les **nœuds** ; la vue qui couvre aussi les câbles est `can` (§ 4.10). Les deux
lisent le **même** enregistrement d'éligibilité : `ls --can=X` est la vue « par action », `can` la
vue « par composant ».

⚠️ **`--can=…` ne suffisait pas à garantir l'équivalence avec la GUI** (constaté à l'ép. 4a) :
`del` et `set` obéissent eux aussi à l'état du composant, mais leur garde vivait **dans la GUI**,
pas dans le modèle. C'est corrigé depuis l'ép. 4b, et le contrat complet — table des états, règle
de refus, exception des câbles, commande `can` — est au **§ 4.10**, qui fait autorité sur ce
paragraphe.

### 4.4 Transitions

`start`, `stop`, `suspend`, `resume`, `restart`, `poweroff` sur un composant nommé ;
`start-all`, `shutdown-all`, `poweroff-all` sur le réseau entier
(`st#startup_everything`, `#shutdown_everything`, `#poweroff_everything`, `state.ml:888-905`).

Côté composant : `#startup`, `#suspend`, `#resume`, `#gracefully_shutdown`, `#gracefully_restart`,
`#poweroff` (`user_level.ml:207-238`).

⚠️ Ces méthodes sont **gardées mais muettes** : appeler `#startup` sur un composant qui ne peut
pas démarrer ne fait rien et ne dit rien. La commande **teste le prédicat avant** et répond
`forbidden_transition` — cf. **§ 4.10**, qui donne la table complète et l'exception des câbles.

⚠️ **`poweroff` et `restart` par composant sont des extensions assumées** (arbitrage de l'auteur,
ép. 4b) : aucun menu par composant ne les offre — `poweroff` n'existe que globalement
(« tout éteindre », `state.ml:962`) et `restart` que par une édition de treeview
(`marionnet.ml:169-175`). L'action existe bel et bien dans l'application, seule sa granularité
diffère, et un script de test a besoin de simuler une coupure brutale sur **une** machine. Elles
sont donc gardées, mais **signalées comme telles** : la réponse de `can` les répète dans un champ
`beyond_gui`, pour qu'un client puisse distinguer ce qu'un humain peut cliquer de ce qu'il ne peut
pas. C'est la seule entorse à l'équivalence du § 4.10, et elle est explicite.

**Contrat des réponses** (implémenté à l'épisode 4c) :

| Cas | Réponse |
|---|---|
| transition acceptée | `{"ok":true,"component":…,"action":…,"accepted":true,"beyond_gui":…}` |
| prédicat faux | `{"ok":false,"error":"forbidden_transition","detail":"\"m1\" cannot start from state \"on\""}` |
| action sans objet pour ce type (`start` sur un câble) | `bad_argument` — un fil ne se démarre pas, ce n'est pas la même chose qu'une transition interdite |
| composant inexistant | `unknown_node` |

Trois règles gouvernent l'implémentation, chacune tirée d'un fait mesuré :
1. **tester le prédicat d'abord** — les méthodes du modèle sont *gardées mais muettes*
   (`user_level.ml:211-237`), donc un `start` illégal serait un no-op silencieux ;
2. **appeler les méthodes de la GUI**, jamais les `…_right_now` : les premières **enfilent** une
   tâche sur le `task_runner` (avec sa barre de progression), les secondes exécuteraient la
   transition dans le thread appelant — ici le thread GTK, gelé pour la durée d'un boot UML ;
3. **d'où `accepted`, jamais « fait »** : au moment de la réponse la tâche est en file, presque
   jamais terminée. C'est `wait` (§ 4.7) qui rejoint la timeline du modèle.

La recherche du composant **et** l'appel ont lieu dans un même créneau du thread GTK (un seul
`ask`), si bien qu'aucun autre callback ne peut s'intercaler entre « c'est permis » et « vas-y ».
Depuis l'épisode 4c cela ne coûte rien : les `can_*` ne prennent plus aucun mutex.

Les trois actions collectives ne sont **pas** une boucle sur la commande par composant :
`startup_everything` enfile ses nœuds *en séquence* quand les deux autres partent *en parallèle*
(`state.ml:951-966`). Elles répondent le nombre de composants que le modèle a sélectionnés —
`count:0` est la façon honnête de dire « rien à faire », et c'est le nombre sur lequel un banc
doit porter.

### 4.5 Câbles

*Livré à l'ép. 4d-3 (2026-08-06).*

```
connect <câble> <nœud>:<port> <nœud>:<port> [--crossover]
```

**Une seule commande neuve, pas deux.** Le `disconnect` annoncé par la conception de l'ép. 0
nommait en réalité deux commandes **déjà livrées** : *débrancher* un câble, c'est
`suspend`/`resume` — le « Disconnect / Reconnect » de la GUI elle-même, § 4.4, ép. 4c — et le
*supprimer*, c'est `del`, livré à l'ép. 4d-2a et mesuré sur un réseau en marche à l'ép. 4b. Un
troisième mot aurait été un synonyme à tenir en cohérence, pas une fonctionnalité.

**Le port se nomme, il ne s'indexe pas.** `eth0`, `port1` : le vocabulaire de la GUI et du `.mar`,
converti par `#ports_card#internal_index_of_user_port_name`, la méthode qu'emploie déjà le
constructeur (`cable.ml:645`). Ce n'est pas une préférence d'ergonomie : un switch numérote ses
ports **à partir de 1** (`user_port_offset:1`, `switch.ml:393`, « perfect mapping with VDE ») là où
une machine part de `eth0` — indexer obligerait le client à recopier cet offset par nature.

**Les gardes, et celle qui manque au modèle.** Le nom (identifiant, libre), l'existence des deux
nœuds, l'existence du port sur son nœud — et surtout : **le port est-il libre ?** Le constructeur
ne le vérifie pas ; il branche là où on lui dit, occupé ou non. En GUI, c'est le **dialogue** qui
tient cette garde, en ne proposant que des extrémités libres
(`network#free_endpoint_list_humanly_speaking`, `user_level.ml:1833`). Sur ce canal, c'est le
serveur. Décision de l'ép. 4d-3 : la garde reste **côté serveur**, la question de la descendre dans
le modèle (comme `check_new_name` à l'ép. 4d-2c) se tranchera **sur mesure du dégât réel**, pas par
symétrie.

**La polarité est rapportée, jamais imposée.** La réponse porte `correct` (`cable#is_correct`,
`cable.ml:674`) : `false` dit que le câble est bien branché mais que sa polarité ne convient pas
aux deux nœuds joints. Le canal ne refuse pas — la GUI ne refuse pas non plus, délibérément
(« allowing users to define 'wrong' connections may be of some pedagogical interest »,
`cable.ml:380`).

**Deux libertés assumées** : une boucle d'un nœud vers **lui-même** sur deux ports distincts est
acceptée (elle l'est en vrai) ; les deux bouts sur **le même** port ne le sont pas. Et un câble se
**branche pendant que le réseau tourne**, comme il s'édite et se supprime en marche (§ 4.10, règle
de projet du `CLAUDE.md`).

**Renommer un câble reste impossible** (ép. 4d-2b) : c'est `del` puis `connect`, le chemin que la
GUI emprunte elle-même (`cable.ml:158-176`). Le refus de `rename` le dit et y renvoie.

Enfin, une mesure faite par le banc de cet épisode et qui ne se devine pas :
**`network#port_no_lower_of` (`user_level.ml:1872`) n'est pas le nombre de ports câblés**, c'est le
plus petit **multiple** de `port_no_min` qui les contienne encore. Un switch dont le port câblé le
plus haut est le 9ᵉ ne peut pas descendre à 9 ports : il descend à **12**.

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
wait <nom> --state=on|off|sleeping [--timeout=<secondes>]
wait-all --state=… [--timeout=<secondes>]
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

Trois décisions d'implémentation (épisode 4c) :

- **`--timeout` change de sens pour ces deux commandes** : il borne l'attente de **l'état**
  (défaut **60 s**), pas l'aller-retour vers le thread GTK. Attendre le boot d'un UML dépasse
  légitimement les 5 s de délai des autres commandes. Le délai GTK de **chaque sondage**, lui,
  reste le délai ordinaire : une interface figée est donc toujours signalée comme telle
  (`error:"timeout"` mentionnant le thread GTK) au lieu d'être masquée par une longue attente.
- **La boucle de scrutation tourne dans le thread de session**, jamais dans le thread GTK : chaque
  tour est un aller-retour court, la GUI garde ses créneaux et les autres sessions restent
  servies. Prix à payer : un client en attente **occupe un des 8 créneaux** pendant toute la durée.
- **`wait-all` porte sur les nœuds**, comme `ls` et comme les boutons de la barre basse : l'état
  d'un câble suit celui de ses extrémités et n'est pas quelque chose qu'un script attend. À
  l'expiration, la réponse porte un champ `pending` listant les retardataires et leur état — de
  quoi diagnostiquer sans second aller-retour.

À l'expiration, `wait` répond `error:"timeout"` en rappelant l'état **réellement** observé en
dernier ; le composant détruit pendant l'attente donne `unknown_node`, pas un faux timeout (la
recherche est refaite à chaque tour).

### 4.8 Porte de sortie

```
forest < fragment.xml
```

Applique un fragment `Xforest` au réseau via le registre `eval_forest_child`. Couvre par
construction tout ce qui est représentable dans un `.mar`, sans multiplier les commandes.

⚠️ **SUSPENDU — le format n'est pas textuel** (constat de l'ép. 4d-3, 2026-08-06). Le fichier
`netmodel/network.xml` d'un `.mar` **n'est pas du XML** malgré son nom : `Netmodel.Xml.save_network`
passe par `Oomarshal.marshaller#to_file` (`user_level.ml:2127`), c'est-à-dire `Marshal.to_channel`
(`lib/MARSHAL/oomarshal.ml:35`,`41`) — du **binaire OCaml**. Le nom du module et le commentaire
« Pseudo XML now! (using xforest instead of ocamlduce) » sont un vestige de l'époque ocamlduce.
Conséquence : un client Bash **ne peut pas** écrire un fragment, et lui en faire produire un
supposerait que l'OCaml **parse** un format structuré — exactement ce que la décision du § 2
exclut. La commande sort donc de l'ép. 4d-3 ; trois voies restent ouvertes, à trancher plus tard :
(a) le fragment est un fichier **produit par Marionnet lui-même** (`.mar` ou sous-arbre), et
`forest` compose des projets existants ; (b) le besoin réel est couvert par `add`/`set`/`connect`,
et `forest` est abandonné (le § 9 en fait déjà une ligne à part) ; (c) une syntaxe textuelle est
définie et parsée côté OCaml, au prix de la décision du § 2. Le reste de ce paragraphe décrit la
conception d'origine et vaut pour (a).

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

**Deux actions restent au-delà de la GUI — tranché à l'ép. 4b : elles sont gardées.** `poweroff` et
`restart` **par composant** n'existent dans aucun menu : le premier n'est offert que globalement
(« tout éteindre », avec confirmation), le second n'est déclenché que par une édition de treeview.
L'auteur a retenu de les **garder** en les marquant comme *extensions assumées* — l'action existe
bel et bien dans l'application, seule sa granularité diffère, et un script de test a besoin de
simuler une coupure brutale sur **une** machine. Le marquage est le champ **`beyond_gui`** de la
réponse (§ 4.4).

**Dette relevée au passage — résolue à l'ép. 4b** : `can_poweroff` (`user_level.ml:431`) n'avait
**aucun lecteur** (`poweroff_everything`, `state.ml:962`, filtre sur `can_gracefully_shutdown`).
Il en a un désormais : c'est lui qui décide de publier `poweroff` dans `can`.

---

**Statut d'implémentation (ép. 4b, 2026-08-04).** Tout ce qui précède est en place :

- `can_modify` / `can_destroy` sont dans la classe de base (`user_level.ml`, même condition que
  `can_startup`), avec leurs accesseurs réseau `get_node{s,_names}_that_can_{modify,destroy}` et
  `get_cable_names_that_can_{modify,destroy}` ;
- ils sont **surchargés à `true`** dans `cable.ml`, et les `dynlist` « Modify »/« Remove » des huit
  composants les lisent — la GUI et le serveur lisent donc la **même** vérité ; au passage
  `Startup.dynlist` cesse d'être un alias de `Properties.dynlist` (chaque menu lit sa garde) ;
- la commande **`can [<nom>]`** et le filtre **`ls --can=<action>`** partagent un enregistrement
  d'éligibilité unique (`control_server.ml`), et l'état publié passe par la projection du § 2
  (`NoDevice`/`DeviceOff` → `off`), jamais par les constructeurs bruts.

Mesuré (banc `can-bench.sh`, deux runs, rapports sous `_claude-local/bench/runs/`) : sur un projet
de 7 nœuds et 6 câbles, réseau **éteint**, chaque nœud offre exactement `set`/`del`/`start` ;
réseau **entièrement démarré**, chaque nœud offre `stop`/`suspend`/`poweroff`/`restart` et
**n'offre ni `set` ni `del`** — le trou de l'ép. 4a est bien fermé — tandis que les six câbles
offrent toujours `set`/`del` **en marche**. La non-régression des menus est vérifiée par
l'équivalence `set` ⟺ `start` sur les nœuds, qui est exactement ce que les `dynlist` listaient
avant.

---

**Comment ces prédicats sont lus (règle posée à l'ép. 4c) : LE THREAD GTK NE PREND JAMAIS LE
MUTEX D'UN COMPOSANT.** Les `can_*` lisent `!state` **sans verrou**, et ce n'est pas un
relâchement de discipline mais la suppression d'un interblocage mesuré (journal du 2026-08-04) :
tous leurs lecteurs — les `dynlist` des huit composants, le serveur de contrôle, les dialogues
globaux de `state.ml`, le treeview de `marionnet.ml` — tournent dans le thread GTK, pendant que le
`task_runner` détient ce même mutex et attend, lui, le thread GTK. Le verrou ne protégeait rien :
le corps est une lecture unique d'une case mémoire, et la sérialisation qu'il semblait offrir
était illusoire puisqu'il est relâché avant que l'appelant n'agisse.

**Corollaire pour le script — la réponse de `can` est un indice, pas une promesse.** Entre
l'instant où `can` dit `start` et celui où le `start` est traité, un composant a pu changer d'état
(le `task_runner` travaille en parallèle). C'est précisément pourquoi les commandes de transition
retestent le prédicat **elles-mêmes**, dans le thread GTK, et pourquoi elles répondent
`accepted` : un script qui déduit une action d'un `can` antérieur doit s'attendre à un
`forbidden_transition`, et le traiter comme une information, pas comme un incident.

La règle duale — *ne jamais appeler le thread GTK de façon synchrone en tenant un mutex de
composant* — reste la bonne discipline pour tout code neuf de `user_level.ml` /
`simulation_level.ml`. Mais ce n'est pas elle qui rend l'application sûre ici : le thread GTK ne
prenant plus le mutex, il ne peut plus faire partie d'un cycle, quel que soit ce que le
`task_runner` appelle sous verrou. Même raisonnement qu'à l'épisode 15 de
`docs/refonte-automate-composants.md` (`ledgrid_manager.ml`), appliqué en sens inverse : là le
mutex était devenu **celui du seul thread principal**, ici il devient **celui de tous sauf lui**.

---

### 4.11 La configuration de démarrage

*Livrée à l'ép. 4e (2026-08-06). C'est le premier pas de la direction du § 10 : le scripting
descend **dans** les composants.*

```
rc-get <composant> [<champ>|--field=<champ>]
rc-set <composant> [<contenu d'une ligne>] [--from=<chemin absolu>] [--enable|--disable] [--field=<champ>]
```

Le canal commande l'**infrastructure** ; la « Startup configuration » commande l'**intérieur** des
machines. Le mécanisme était déjà complet — contenu déposé dans `hostfs/marionnet-relay.rcfile`
(`simulation_level.ml:1244-1251`), **sourcé** en fin de `start()` du relais invité
(`marionnet-relay.trixie:486-494`) — seul l'accès programmatique manquait.

**Le serveur marshale, le client écrit du texte.** Dans le forest, le champ est un
`Marshal.to_string (activé, contenu)` (`machine.ml:645`) : c'est pour cela que `get`/`set` le
servent `null` et le **nomment** dans `omitted` depuis l'ép. 4d-2a. Demander à un client bash de
forger des octets marshalés était exclu (décision § 2) ; le contenu voyage donc **en clair** et
c'est le **serveur** qui marshale, à l'aller comme au retour. Cette seule décision est ce qui
dispense ces deux commandes de tout aiguillage par nature : elles écrivent par le même
`#eval_forest_attribute` uniforme que `set`.

**Le champ n'est pas nommé, il est reconnu.** Aucune liste de noms de champs — celle-là même que
`is_marshalled` refuse de tenir « le jour où un composant en ajoute un ». La valeur est
démarshalée en `Obj.t`, ce qui ne suppose **aucun type**, puis sa **forme** est inspectée : bloc de
tag 0, taille 2, un immédiat booléen et une chaîne. `Obj.obj` n'est appliqué qu'**après** — le
contraire exact d'un `Obj.magic`, où le cast est pris sur parole. Conséquence pratique : machine et
switch (`rc_config`) comme routeur (`rc_config_unix`) sont trouvés sans être nommés, tandis que les
trois autres champs marshalés du routeur (`rc_config_quagga`, `quagga_selected_srvs`,
`show_quagga_terminal`) n'ont pas cette forme et restent dans `omitted`. Nommer le champ ne sert
qu'à lever une ambiguïté future : zéro candidat, ou plusieurs, sont deux refus motivés.

**Deux voies pour le contenu, une par usage.** `--from=<chemin absolu>` est la voie du multi-ligne
(§ 4.1) : le fichier est lu **dans le thread serveur**, jamais dans le créneau GTK, et l'absolu est
exigé pour la raison qui vaut déjà pour `open` (Marionnet a fait `chdir` vers sa propre maison).
Le contenu **d'une ligne** s'écrit directement en dernier argument libre — avec la limite du
tokeniseur : un mot commençant par `--` y serait pris pour une option, ce que le serveur **dit** au
lieu de l'avaler (message renvoyant à `--from=`).

**Les gardes**, toutes rendues en `bad_argument` motivé : `--from` et *inline* ensemble ;
`--enable` et `--disable` ensemble ; ni contenu ni drapeau (« rien à faire » plutôt qu'un no-op
muet) ; chemin relatif, fichier absent, non régulier, plus grand qu'**1 Mio** (un scénario n'est pas
une image) ; et surtout **contenu non UTF-8** — la réponse de ce canal est une ligne JSON, un
contenu invalide serait accepté ici et casserait `rc-get` chez le client, très loin de sa cause.

**Poser un contenu l'active**, sauf `--disable` explicite : un scénario qui ne jouerait jamais est
exactement la surprise silencieuse que ce canal existe pour éviter. Un drapeau seul ne touche pas
au contenu. La réponse porte `enabled_before`/`enabled`, `old_bytes`/`bytes` et `changed` — des
**tailles**, pas l'ancien contenu, qui se relit par `rc-get`.

**`can_modify` s'applique** (§ 4.10), et ici la règle est plus qu'une symétrie avec la GUI : le
champ est lu à la **construction du device** (`machine.ml:674-678`), donc un scénario se pose
*avant* `start` et l'écrire sur un composant en marche ne changerait rien d'observable avant le
prochain démarrage. La **lecture**, elle, reste servie en marche.

**Le canal dit où l'invité écrira** : le champ `hostfs` de la réponse porte
`<racine du projet>/hostfs/<nom>` (`user_level.ml:1486`), c'est-à-dire le répertoire **hôte** que
l'invité voit en `/mnt/hostfs`. Il est `null` pour un switch, qui n'en a pas — son rc est un jeu de
commandes **vdeterm** passé à `vde_switch --rcfile` (`simulation_level.ml:398-409`), dont rien ne
revient. Pour l'exposer sans recopier la convention de chemin dans le serveur,
`component#hostfs_directory_if_any` a été ajoutée au modèle (`user_level.ml`, défaut `None`,
redéfinie dans `machine.ml` et `router.ml` — *pas* dans le mixin
`virtual_machine_with_history_and_ifconfig`, où elle aurait été chez elle : ce mixin n'hérite pas
de `component`, et les deux définitions se rencontreraient par héritage multiple, ce qui est le
*warning* 7, une erreur dans ce build).

À noter, mesuré par le banc : un composant créé **par le canal** part d'un rc **vide** et
désactivé. Le modèle commenté que l'humain voit dans le dialogue est le défaut du **dialogue**
(`machine.ml:312`), pas celui du constructeur (`machine.ml:564`). C'est le comportement le plus
prévisible pour un script, mais un humain qui ouvre ensuite le dialogue d'une machine créée par
script y trouvera un champ vide.

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
| **4b** | Implémentation de 4a : `can_destroy`/`can_modify` dans `user_level.ml` (+ surcharge `cable.ml`), `dynlist` GUI qui les lisent, commandes `can` et `ls --can=` ; arbitrage `poweroff`/`restart` par composant | **fait** (2026-08-04) — 8 assertions mesurées sur deux runs |
| 4c | Transitions (`start`/`stop`/`suspend`/`resume`/`restart`/`poweroff` + variantes globales) et `wait` | **fait** (2026-08-04) — le préalable a mangé la première moitié : interblocage GUI/`task_runner` diagnostiqué, capturé et **corrigé** (le thread GTK ne prend plus le mutex d'un composant), puis les 11 commandes, 16 assertions |
| 4d | Arité des arguments (§ 4.1) **et** commandes de projet (§ 4.2) | **fait** (2026-08-05) — 29 assertions, `project-bench.sh` |
| 4d-2a | Composants : `add`, `del`, `get`, `set` **hors champs structurels** (§ 4.3) | **fait** (2026-08-05) — 58 assertions, `components-bench.sh` |
| 4d-2b | Les champs structurels : `rename`, `set … name`, `set … port_no` — `#update_structural_with`, la moitié structurelle des huit `update_<kind>_with` | **fait** (2026-08-06) — 85 assertions, `components-bench.sh` |
| 4d-2c | Le modèle refuse un nom (mal formé **ou** déjà pris) **avant d'écrire** : `check_new_name` en 1ʳᵉ instruction des 5 chemins destructeurs | **fait** (2026-08-06) — banc témoin désarmé, 4 rouges avant / 6 vertes après |
| 4d-3 | Câbles : `connect` (§ 4.5) — `disconnect` s'est révélé un doublon de `suspend`/`del` | **fait** (2026-08-06) — 119 assertions, `components-bench.sh` |
| — | `forest` (§ 4.8) : **suspendu**, le `.mar` est du Marshal binaire et non du XML | à re-trancher |
| **4f** | Le couple (distrib, noyau) : le constructeur suit la distribution (comme le dialogue), `set … kernel` hors `SUPPORTED_KERNELS` refusé, `set … distrib` réaligne le noyau et le rapporte dans `adjusted` | **fait** (2026-08-07) — 134 assertions (`components-bench.sh`, bloc C11 neuf) + **le bout en bout de `rc-bench.sh` sans aucune pose de noyau à la main** |
| 4e | `rc-set`/`rc-get` (§ 4.11, § 10) : la configuration de démarrage, donc le scripting **dans** les composants | **fait** (2026-08-06) — `rc-bench.sh` |
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

### 2026-08-04 — épisode 4b : l'automate descend dans le modèle

**Ce que l'épisode livre.** Les deux prédicats manquants existent (`can_modify`, `can_destroy`,
`user_level.ml`, même condition que `can_startup`), leurs accesseurs réseau aussi, ils sont
surchargés à `true` pour les câbles, les `dynlist` « Modify »/« Remove » des huit composants les
lisent — donc la GUI et le serveur lisent la même vérité — et le canal expose les deux vues de
cette vérité : `can [<nom>]` par composant, `ls --can=<action>` par action. Statut détaillé en fin
de § 4.10.

**Deux arbitrages, tranchés par l'auteur.** (a) `poweroff`/`restart` **par composant** sont
gardés, marqués `beyond_gui` dans la réponse (§ 4.4) : l'action existe dans l'application, seule sa
granularité diffère. (b) `ls --can=` est implémenté dès cet épisode, avec une nomenclature unique —
des **noms de commande** (`start`), jamais des noms de prédicat (`startup`) — et une action inconnue
refusée par `unknown_can` au lieu d'une liste vide, parce qu'une faute de frappe dans un script doit
se diagnostiquer. La dette `can_poweroff` (prédicat sans lecteur) est résolue par la même occasion.

**Le banc a d'abord mesuré du vide — trois fois, pour trois raisons différentes.** Cet épisode a
coûté plus en instrumentation qu'en code, et c'est la partie instructive.

1. *Course perdue contre `-r`* (run du 2026-08-03) : interroger le canal dès l'apparition du
   socket lisait un réseau **vide**, le chargement `-r` n'ayant lieu qu'~1 s après le début de la
   boucle GTK. Le rapport en tirait deux conclusions fausses (« aucun nœud éteint », « le projet ne
   contient aucun câble ») alors que le projet a 7 nœuds et 6 câbles. Correctif : en mode t0, ne
   pas passer `-r` du tout et charger par la commande **`open`**, qui est synchrone — quand elle
   répond, le réseau est là et tout est éteint. Déterministe, sans fenêtre à attraper.
2. *Démarrage bloqué* (même run) : le projet de test contenait deux `world_gateway`, dont le
   démarrage réclame un tap privilégié ; le `task_runner` étant séquentiel, **rien** d'autre n'a
   démarré et l'assertion centrale n'a jamais été mesurée. Correctif : un projet sans
   `world_gateway` ni `world_bridge`.
3. *Faux positif franc* (première reprise, 2026-08-04 10:55) : la réponse `can` de t1 est arrivée
   **vide** (client coupé avant la réponse), et le banc a proclamé « toutes les assertions
   tiennent » — `jq` comparait des listes vides à des listes vides. Un banc qui ne mesure rien doit
   s'arrêter, pas féliciter : toute réponse est désormais passée par `require_ok` (non vide **et**
   `ok:true`), A3 exige au moins un nœud `on`, A7 exige deux vues non vides.

**Une limite du canal, mesurée au passage.** Pendant la rafale de démarrages d'un projet, le canal
devient **muet** : ni `--timeout=25` côté serveur ni `-T30` côté client n'obtiennent de réponse,
alors que le même canal répondait 2 s plus tôt et répond de nouveau la rafale passée (le thread de
la session concernée n'est jamais journalisé comme terminé). Ce n'est pas un défaut de l'épisode
4b — les prédicats, eux, répondent juste — mais c'est une contrainte réelle pour un client :
**réessayer**, plutôt que faire confiance à un délai. Le banc attend maintenant un réseau
*stabilisé* (au moins un nœud `on`, plus aucun `off`) au lieu de dormir cinq secondes.

**Et un garde-fou qui protégeait du cas normal.** Le fusible de cardinalité du nettoyage (« au-delà
de 60 processus, le filtre est forcément faux ») s'est déclenché sur un projet de 5 machines, qui
en fait **76** : le banc a donc refusé de nettoyer et laissé 76 processus UML orphelins, exactement
ce que le fusible était censé éviter. Plafond porté à 200 ; la garde qui compte reste la **forme**
du motif (`/tmp/marionnet-<N>.dir`), pas son cardinal.

**Preuve.** `dune build` et `dune test` verts. Banc `can-bench.sh`, deux runs sur un projet de
7 nœuds et 6 câbles (`_claude-local/bench/runs/20260804-11*`) :

- **t0**, réseau chargé et éteint, aucun UML : les 7 nœuds offrent exactement `set`/`del`/`start` ;
  les 6 câbles offrent `set`/`del` et n'exposent aucune action de nœud ; `ls --can=X` coïncide avec
  `can` pour les 8 actions ; `ls --can=teleport` → `unknown_can` ; `can <inconnu>` →
  `unknown_node` ; aucun état brut publié.
- **t1**, réseau entièrement démarré (5 s) : les 7 nœuds offrent `stop`/`suspend`/`poweroff`/
  `restart` et **aucun** n'offre `set` ni `del` — le trou de l'ép. 4a est fermé — avec
  `beyond_gui = [poweroff, restart]` ; les 6 câbles restent `set`/`del` **en marche** ; `set` ⟺
  `start` sur tous les nœuds, donc les menus listent ce qu'ils listaient avant ; la vue à plat
  `can m1` est identique à l'entrée correspondante de la vue globale.

### 2026-08-04 — épisode 4c (1/2) : le canal muet n'était pas muet, l'application était gelée

**Ce que l'épisode devait livrer**, et qui reste à faire : les commandes de transition (`start`,
`stop`, `suspend`, `resume`, `restart`, `poweroff`, leurs variantes globales) et `wait`. Elles
n'ont pas été écrites : le préalable qu'on croyait mineur — « le canal devient muet pendant la
rafale de démarrages », noté en marge de l'épisode 4b — s'est révélé être un **interblocage
franc de l'application entière**, qu'il aurait été absurde d'habiller de commandes nouvelles.

**Reproduction déterministe** (banc `mute-diag.sh`, hors dépôt) : Marionnet lancé avec `-r` sur
un projet de 7 nœuds, un client qui sonde le canal toutes les 0,5 s.

| Sonde | Résultat |
|---|---|
| `status` seul | **187 réponses, aucun trou** ; les 38 tâches du `task_runner` s'exécutent, le réseau démarre entièrement |
| `status` et `can` en alternance | **gel définitif** à +4,3 s : 30 non-réponses sur 37, le `task_runner` s'arrête et ne redémarre jamais, la GUI ne répond plus, et une requête patiente (`can --timeout=25`, client `-T60`) n'obtient **rien** en 60 s |

La différence entre les deux lignes est le seul fait qui compte : `status` ne lit que l'état
global, tandis que `can` interroge les prédicats de **chaque composant** — lesquels prennent le
mutex du composant (`user_level.ml:135`).

**Cause, capturée et non déduite.** `gdb` ne pouvait pas s'attacher au processus
(`ptrace_scope=1`, et le `sudoers` de Marionnet n'ouvre que des règles `ip`) : le banc
`deadlock-capture.sh` lance donc Marionnet **sous** gdb et déclenche l'arrêt à distance par
`SIGUSR2` (`handle SIGUSR2 stop nopass`). Deux captures concordantes :

- **thread GTK** : `main_loop` → idle → `GMain_actor` → `control_server.ml:354` (`can`) →
  `eligibility_of_node` (`control_server.ml:279`) → `MutexExtra` → `caml_ml_condition_wait`.
  Il **attend un mutex de composant**.
- **thread `task_runner`** : `task_runner.ml:87` → `state.ml:926` (le thunk de
  `make_names_and_thunks`) → `user_level.ml:942` (`startup_right_now`) → `with_mutex` →
  `GMain_actor.apply_extract` (`gMain_actor.ml:112`) → `Milner`/`Channel` →
  `caml_ml_condition_wait`. Il **attend le thread GTK, un mutex à la main**.

Chacun attend ce que l'autre tient. Le site de l'appel synchrone est le gestionnaire de LED :
`show_device_ledgrid` (`bin/gui/ledgrid_manager.ml:184`) est un `GMain_actor.apply_extract`, et
il est appelé en fin de démarrage d'un nœud (`user_level.ml:944`).

**Ce n'est pas un défaut du canal de contrôle.** Les prédicats en cause alimentent aussi les
`dynlist` des menus par composant (« Modify », « Remove », « Startup ») : **dérouler un menu
pendant qu'un composant démarre emprunte exactement le même chemin depuis le thread GTK**. Le
canal n'a fait que rendre reproductible, et scriptable, un gel que la GUI peut produire seule.
À rapprocher de `docs/bug-critique-crash-host.md` (C5 : ce qui ressemblait à un crash hôte était
un gel d'application) et de `docs/refonte-automate-composants.md` (discipline des appels Gtk+).

**Deux correctifs tentés, tous deux annulés** — ils visaient `Sketch.refresh_sketch`, qui est
appelé sous le même mutex (8 sites de `user_level.ml`) et paraissait le coupable naturel :
(a) `really_refresh_sketch` en `delegate ~async:()` (`state.ml`) ; (b) le thunk global
`Refresh_sketch_thunk` posté en asynchrone (`marionnet.ml:97`). **Aucun effet** sur le gel, mesuré
deux fois. L'explication tient dans le journal : la ligne qui suit `Sketch.refresh_sketch` dans
`startup_right_now` (« The device H1 was started up ») **est bien écrite** — le refresh passe donc,
et le blocage est postérieur. Les deux modifications ont été retirées de l'arbre : une hypothèse
infirmée ne se garde pas « au cas où ».

**Reste à trancher (prochaine session).** Rendre non bloquant l'appel du gestionnaire de LED sur
le chemin des transitions (`show_device_ledgrid`/`hide_device_ledgrid` en `delegate ~async:()`),
ou tenir la règle plus générale — *aucun appel synchrone au thread GTK tant qu'un mutex de
composant est détenu* — ce qui demande d'inventorier le chemin de démarrage complet. Le premier
est une ligne et se prouve avec le banc existant ; le second est la vraie règle. La décision
appartient à l'auteur, parce qu'elle touche le cœur applicatif, pas le canal.

### 2026-08-04 — épisode 4c (2/2) : le thread GTK n'attend plus après un composant

**L'arbitrage.** Des deux correctifs soumis à l'auteur, aucun n'a été retenu tel quel : c'est leur
**duale** qui l'a été. Un cycle a deux arêtes, et les deux options proposées coupaient la même —
celle de l'écrivain (le porteur du mutex n'attend plus le thread GTK). La règle retenue coupe
l'autre : **le thread GTK ne prend jamais le mutex d'un composant**. Les sept `can_*` de
`user_level.ml` et les deux de `cable.ml` lisent désormais l'état **sans verrou**.

Quatre raisons, toutes vérifiées dans le source avant d'éditer quoi que ce soit :

1. **le correctif d'une ligne était insuffisant** — `Sketch.refresh_sketch` est appelé sous le
   *même* mutex à huit endroits et mène au même thread GTK. Que le journal montre qu'il « passe »
   ne prouve pas qu'il est sûr : il prouve qu'il a gagné la course cette fois-là. Corriger le seul
   gestionnaire de LED laissait une seconde porte ouverte sur le même cycle ;
2. **la règle générale n'était pas bornable** — l'inventaire descend dans `simulation_level.ml` et
   dans tout ce que `d#startup` appelle ; périmètre non fini, et aucune garantie qu'un ajout futur
   ne le rouvre. C'est une discipline, pas une propriété ;
3. **la duale est bornable et vérifiable par `grep`** — les lecteurs de ces prédicats depuis le
   thread GTK s'énumèrent : les `dynlist` des huit composants, `control_server.ml`, `state.ml`,
   `marionnet.ml` ;
4. **le verrou ne protégeait rien** — chaque prédicat est une lecture unique de `!state` suivie
   d'un filtrage de constructeur ; aucun invariant composé, et la sérialisation apparente est
   illusoire, le mutex étant relâché avant que l'appelant n'agisse. On payait un risque de gel pour
   une garantie inexistante.

La règle générale n'est pas abandonnée pour autant : elle est **écrite** au § 4.10 comme discipline
du code neuf. Elle n'est simplement plus ce qui rend l'application sûre.

**Mesure.** Banc `mute-diag.sh` **inchangé**, donc directement comparable :

| Run | `status` | `can` | Sonde patiente |
|---|---|---|---|
| référence (avant, `4c-mute-3`) | 4 réponses / 15 muettes | 3 / 15 | **aucune réponse en 60 s** — gel définitif à +4,3 s |
| après (`4c-mute-6-nolock`) | **153 / 0** | **153 / 0** | non déclenchée (aucun trou) |

Et le run mesure bien quelque chose, contrairement à ceux de l'épisode 4b : les 13 composants
démarrent pendant l'observation (13 lignes « was started up »), la sonde `can` passant de
`state:"off"` au premier tour à `state:"on"` au dernier, threads montés à 109. Les deux correctifs
`refresh_sketch` de la session précédente avaient, eux, reproduit le gel **à l'identique**
(+4,3 s, 7/30) — la mesure les a bien infirmés.

**Les commandes.** `start`, `stop`, `suspend`, `resume`, `restart`, `poweroff` par composant ;
`start-all`, `shutdown-all`, `poweroff-all` ; `wait` et `wait-all` (§ 4.4 et § 4.7 pour le
contrat). Rien d'inattendu dans l'écriture — les trois règles étaient tranchées en conception — sauf
un point de nomenclature : **`start` sur un câble répond `bad_argument`, non
`forbidden_transition`**. Un fil ne se démarre pas ; son processus suit un compteur de références.
Dire « interdit » laisserait croire qu'un autre état le permettrait.

**Preuve** : banc `transitions-bench.sh` (nouveau, hors dépôt), 16 assertions, réseau chargé par
`open` puis **entièrement piloté par le canal** — aucune course contre `-r`. Toutes vertes :
`start` accepté puis `wait --state=on` rendant la main en 0,8 s avec `can` confirmant ; second
`start` refusé par `forbidden_transition` ; suspend/resume aller-retour ; `poweroff` accepté avec
`beyond_gui:true` ; `start-all` (count 7) puis `wait-all --state=on` en **10,1 s**, `shutdown-all`
(count 7) puis `wait-all --state=off` en **5,3 s**.

**Deux enseignements de mesure**, tous deux payés par un run faux :

- **le client coupait avant la réponse, et cela ressemblait à un mutisme du serveur.** Le premier
  run a rendu `wait-all` VIDE deux fois. La cause n'est pas dans Marionnet mais dans `socat -t3` :
  `-T` borne l'inactivité totale, mais **`-t` borne l'attente après EOF** — et il y a EOF dès que
  le `printf` a écrit la requête. Le client fermait donc 3 s après avoir demandé, quoi que dise
  `-T`. Toute réponse plus lente était lue comme vide, et le banc accusait le serveur d'un silence
  qui était le sien. Les gardes de l'épisode 4b (`expect_ok` refuse une réponse vide) ont fait
  exactement leur travail : échec franc, pas félicitation à vide ;
- **les câbles restent `on` un instant après que tous les nœuds sont `off`** : leur processus suit
  un compteur de références décrémenté par la destruction des extrémités, elle-même asynchrone.
  Ce n'est pas une anomalie, et cela confirme le choix de ne faire porter `wait-all` que sur les
  nœuds (§ 4.7).

Le préalable de l'épisode est donc levé et son livrable rendu : un script peut piloter les
transitions et se synchroniser dessus, sans jamais confondre « accepté » et « fait ».

### 2026-08-05 — épisode 4d : l'arité des arguments, et les commandes de projet

**Le préalable annoncé, tranché sur une propriété du domaine.** La tokenisation était le dernier
obstacle avant les commandes à plusieurs arguments. Les trois conventions envisageables ont été
soumises à l'auteur ; c'est **l'arité déclarée avec dernier argument en texte libre** qui a été
retenue (§ 4.1), et l'argument décisif n'est pas d'ergonomie mais de domaine : **un nom de
composant est un identifiant** (`check_name` → `StrExtra.Class.identifierp`, `user_level.ml:521`),
donc sans espace. Seuls un chemin et une valeur libre en contiennent, et tous deux sont toujours
en dernière position. Une citation à la shell aurait acheté une machine à états, un code d'erreur
supplémentaire et un **second niveau d'échappement** côté client Bash, pour couvrir un cas qui
n'existe pas.

Effet de bord retenu comme un gain : `ls foo` était **accepté et ignoré**, il répond désormais
`bad_argument` — un argument avalé en silence est un bug qui se cache. Le `detail` porte la
syntaxe de la commande, si bien qu'un refus enseigne l'usage.

**Ce que le code a appris en chemin** : `camlp4` préprocesse `bin/` et **ne connaît pas les
*binding operators*** de OCaml 4.08 — `let ( let* ) = Result.bind` échoue en *« Parse error: ")"
or "module" expected »*. Le chaînage des étapes passe donc par un `( >>= )` classique, ce qui ne
change rien à la lisibilité et rappelle où l'on écrit.

**Les commandes de projet, ou pourquoi une méthode ne suffit pas.** `new`, `save`, `save-as` et
`close` (§ 4.2) n'appellent pas la méthode homonyme de `state.ml` : le menu, lui, exécute une
**séquence** — `shutdown_everything` → *[save]* → `close_project` → *[new_project]* — dans un
`Thread.create`, c'est-à-dire hors thread GTK, exactement comme le thread qui sert une commande.
Le canal reproduit cette séquence. Deux décisions y répondent à des questions qu'un humain
tranchait par un clic :

- la question modale « voulez-vous enregistrer ? » devient `--save` / `--no-save`, et **son
  absence est une erreur** (`unsaved_changes`) quand le projet est modifié. Émuler la
  confirmation aurait signifié choisir à la place du script ;
- `--save` signifie « sauve **puis** ferme » : si la sauvegarde échoue, **rien n'est fermé**.
  C'est plus strict que le menu, qui ferme quand même — et fondé, `private_save_project`
  rattrapant ses propres échecs pour les afficher dans un dialogue (`state.ml:800-810`) : le
  critère de succès est `project_already_saved`, jamais l'absence d'exception. Même leçon qu'à
  l'épisode 3a.

**Preuve** : banc `project-bench.sh` (nouveau, hors dépôt), **29 assertions, toutes vertes**, en
un seul mode — Marionnet lancé sans `-r`, tout par le canal. Notamment : les 8 refus d'arité avec
leur syntaxe ; `new` puis `status` rendant `saved:false` (un projet neuf n'a jamais été
enregistré, `set_project_not_already_saved`) ; `close` refusé par `unsaved_changes` puis accepté
après `save` ; **`save-as` vers un chemin contenant un espace**, rendu intact par le serveur et
écrit sur le disque — la preuve directe du « dernier argument libre » ; et le vrai cas d'usage,
`open` (7 nœuds) → `start m1` → `wait --state=on` → `close --no-save`, où le journal montre
`close_project: END` **après** « I have joined "Shut down m1" with success ». Aucun processus
orphelin, répertoire de session supprimé.

**Un mensonge d'instrumentation corrigé en cours de route** : le premier run a laissé quatre
lignes « closing the current project » dans le journal pour **deux** fermetures réelles — la
trace était écrite à l'entrée de la commande, avant même de savoir si elle serait refusée. Elle
est descendue au seul endroit où la fermeture commence vraiment. C'est la règle de N4 : un
instrument de diagnostic ne peut pas mentir, fût-ce par avance.

**Observation gardée pour les clients** : le champ `saved` de `status` n'a de sens que si
`active` est vrai — après une fermeture il conserve sa valeur d'avant, l'état global n'étant pas
réinitialisé. Comportement historique, non touché.

### 2026-08-05 — épisode 4d-2a : construire un réseau, et s'arrêter à la bonne frontière

Jusqu'ici un script pouvait **piloter** un réseau, pas en **construire** un : il fallait partir
d'un `.mar` dessiné à la main. `add`, `del`, `get` et `set` (§ 4.3) referment ce trou — sauf sur
deux champs, et c'est le cœur de l'épisode.

**Trois propriétés du modèle rendent ces commandes uniformes sur les huit natures**, si bien que
presque rien, dans le serveur, ne sait ce qu'est une machine : `#to_tree` publie les attributs
tels qu'un `.mar` les enregistre ; `#eval_forest_attribute` est le setter indexé par nom
d'attribut ; le constructeur s'**enregistre lui-même** dans le réseau (`network#add_node`,
`user_level.ml:854`) et crée son entrée ifconfig (l.1092). `add` est donc l'`Add.reaction` de la
GUI (`machine.ml:146-161`) sans le dialogue, et `del` son `Remove.reaction`.

**Où l'épisode s'arrête, et pourquoi.** `name` et `port_no` ne sont pas des champs comme les
autres : le chemin de la GUI passe par `update_<kind>_with` → `update_virtual_machine_with`, qui
**renomme les entrées ifconfig et history, renomme le répertoire hostfs et met à jour le nombre de
ports du treeview** (`user_level.ml:1418-1425`). Les écrire par `eval_forest_attribute` n'appellerait
que `set_name`/`set_port_no` : le composant porterait le nouveau nom, ses lignes de treeview
l'ancien, et personne ne s'en apercevrait avant le démarrage suivant. Le canal les **refuse** en
disant pourquoi, et le vrai chemin — avec `rename` — devient l'ép. 4d-2b. Un découpage tiré du
code, pas du calendrier.

**Le constructeur plutôt que le registre.** Passer par `try_to_add_*`/`eval_forest_child`
(`user_level.ml:1714`) aurait été tentant : uniforme, déjà écrit, et c'est le chemin du chargement
d'un `.mar`. Deux faits l'ont écarté. Il **avale l'erreur** (`with _ -> false`, `machine.ml:545`) —
un nom refusé, un attribut mal formé, tout revient en un `false` nu. Et il exige `port_no`, alors
que le bon défaut est **local à chaque fichier** (`Const.port_no_default` : machine 1,
hub/switch/routeur/world_gateway 4, cloud 2, world_bridge 1) : le serveur aurait dû en recopier
sept, et les voir vieillir. Sept appels de constructeur les prennent là où ils sont définis.

**Les valeurs marshalées se reconnaissent, elles ne s'énumèrent pas.** `rc_config` est écrit par
`Marshal.to_string` dans l'arbre (`machine.ml:645`) : le servir mettrait de l'UTF-8 invalide au
milieu d'une ligne JSON. Plutôt qu'une liste de noms de champs — qui aurait vieilli au premier
composant ajouté — le serveur les reconnaît à l'en-tête de `Marshal` (`0x8495A6BD/BE/BF`). Le run
l'a immédiatement validé : sur un routeur, **quatre** champs sont ainsi masqués et nommés dans
`omitted` (`rc_config_unix`, `rc_config_quagga`, `quagga_selected_srvs`, `show_quagga_terminal`)
alors qu'aucun n'avait été prévu à l'écriture du code.

**Un piège de concurrence, évité par construction puis par mesure.** Tout se joue dans **un seul**
`ask`, dont le thunk appelle `st#network_change` : recherche, garde et action tiennent dans le même
créneau GTK. C'est correct parce que `GMain_actor.delegate` sans `~async` **est** `apply`
(`gMain_actor.ml:126`), et qu'`apply` exécute directement quand l'appelant est déjà le thread GTK
(l.82). Mais la même lecture révèle un second fait, moins agréable : `apply` **capture**
l'exception de son thunk (`EitherExtra.protect`) et `delegate` la **jette**. Une action qui échoue
au fond de `network_change` ressemblerait donc à un succès. D'où la référence `failure` que chaque
commande porte : l'exception est rattrapée là où elle se produit, et le message du modèle est
rendu au client (`Failure("int_of_string")`, `Failure("Setting component 1m: invalid name")`…).

**Un `add` refusé laisse le réseau intact.** Les options `--<champ>=<valeur>` sont appliquées après
construction ; si l'une est refusée — champ inconnu, structurel, marshalé, ou valeur que le modèle
rejette — le composant à peine créé est **détruit**. L'alternative aurait été un composant à moitié
configuré que le script n'a pas demandé.

**Preuve** : banc `components-bench.sh` (nouveau, hors dépôt), **58 assertions, toutes vertes au
premier run**, en un seul mode (sans `-r`, tout par le canal). Notamment : les 7 natures créées
dans un projet **neuf** puis relues par `ls` ; les cinq refus d'`add` (nom pris, nom non
identifiant, nature inconnue, `--ports` sur un cloud, `cable`) suivis d'un `ls` qui compte
toujours 7 ; `set m1 label salle de TP 42` — le dernier argument libre, ici sur une valeur et non
plus sur un chemin ; les trois rollbacks (`--gruyere=1`, `--memory=beaucoup`, `--name=m5`) laissant
le réseau à 7 nœuds ; et, **réseau réellement en marche**, `set`/`del` refusés sur une machine `on`
(`forbidden_transition`) pendant qu'un **câble** s'édite sans broncher — l'exception du § 4.10,
mesurée. Enfin `del` sur un nœud câblé rend `cables_destroyed: ["d2","d5"]`, et les deux câbles ont
bien disparu du réseau. `dune build` et `dune test` verts (7 tests, 0 échec), aucun orphelin.

### 2026-08-06 — épisode 4d-2b : renommer sans laisser d'orphelin

L'épisode 4d-2a s'était arrêté devant `name` et `port_no` en disant pourquoi : les écrire par
`eval_forest_attribute` aurait laissé des lignes de treeview sous l'ancien nom. Cet épisode ouvre
les deux champs — `set … name`, `set … port_no`, `rename` — et le contrat de `set` redevient sans
exception sur les sept natures de nœuds : **tout champ publié par `#to_tree` s'écrit**.

**Le chemin existait déjà, fragmenté.** Les huit `update_<kind>_with` que les dialogues appellent
ne font qu'assembler des briques du modèle et y ajouter leurs champs propres. Le serveur n'avait
besoin que de la partie commune, d'où `#update_structural_with ~name ~port_no` : déclarée sur
`node_with_ports_card` (la classe qui **est** le type `node`, `class type virtual node =
node_with_ports_card` — la seule place d'où `get_node_by_name` la voit), implémentée une fois pour
`node_with_defects` et une fois pour `node_with_ledgrid_and_defects`, surchargée dans `machine.ml`
et `router.ml` pour préfixer `update_virtual_machine_with`. Cinq fichiers du modèle, une vingtaine
de lignes, **aucun `Obj.magic` ajouté** — l'alternative (dispatcher les huit natures dans le
serveur et rappeler chaque `update_<kind>_with` avec tous ses champs relus) en aurait demandé huit,
et aurait obligé à relire puis réécrire des champs **marshalés** pour ne changer qu'un nom.

**Le banc a trouvé un défaut d'atomicité, et c'est le meilleur moment de l'épisode.** Une seule
assertion a échoué au premier run : `set m1 port_no 4`, en fin de bloc, avec un message venu du
treeview — *« unique_row_id_such_that: there were 0 results instead of 1 »*. Un diagnostic isolé
(projet neuf, aucune autre commande) a montré que `set … port_no` sur une machine fonctionne
parfaitement : le coupable n'était pas la commande mais **le refus qui la précédait**. `rename m1
1m` avait été refusé — mais **trop tard** : `update_virtual_machine_with` renomme les lignes
ifconfig et history et le répertoire hostfs **avant** que `set_name` n'ait l'occasion de rejeter le
nom (`check_name`). Le composant s'appelait toujours `m1`, sa ligne ifconfig s'appelait `1m`.
Autrement dit, le code censé empêcher les orphelins en fabriquait un.

La lecture de la GUI a donné la réponse : elle ne s'appuie pas davantage sur le modèle pour cela.
`Gui_bricks.Ok_callback.check_name` teste **l'identifiant puis l'unicité** *avant* d'appeler
`update_<kind>_with`. Le serveur fait donc exactement les deux mêmes tests, avant d'agir. Leçon
générale pour la suite du chantier : « les mêmes possibilités et limites que la GUI » (§ 4.10) ne
concerne pas que les prédicats d'état — cela inclut les **gardes d'entrée de ses dialogues**, qui
ne sont pas dans le modèle. Le modèle, lui, reste non atomique sur ce chemin : c'est une fragilité
inscrite dans `docs/TODO.md`, pas un bug observable (aucun appelant ne l'atteint sans garde).

**Un câble ne se renomme pas, et ce n'est pas une exception arbitraire.** En cherchant comment le
faire, on trouve que la GUI ne le fait pas non plus : `Properties.reaction` d'un câble **détruit**
le câble et en **recrée** un (`cable.ml:158-176`), l'enfilant derrière la destruction sur le
`task_runner`. Renommer en place aurait laissé son entrée defects sous l'ancien nom
(`cable#set_name` n'est pas redéfini, contrairement à celui des nœuds). Le canal refuse donc, en
renvoyant à `del` + `connect` (§ 4.5, ép. 4d-3).

**Preuve** : `components-bench.sh` étendu (blocs C7 neuf, C8 et C9 renumérotés), **85 assertions,
toutes vertes**, en un seul mode (sans `-r`). La preuve du renommage n'est délibérément **pas** le
canal — il pourrait mentir de bout en bout — mais le **`.mar` enregistré** : après `set m1 name
machinerenommee` puis `save`, le nouveau nom est dans `states/ifconfig`, `states/defects` et
`netmodel/network.xml`, le répertoire `hostfs/machinerenommee` existe, `hostfs/m1` a disparu, et
un `grep -a` sur `states/` et `netmodel/` ne trouve **plus une seule occurrence** de l'ancien nom
(le motif inclut le préfixe de longueur de `Marshal`, ces fichiers étant binaires). Le reste : le
no-op (`changed:false`, aucun rebuild), les refus (nom pris, non identifiant, nœud démarré →
`forbidden_transition`, câble → `bad_argument`), les bornes de `port_no` (minimum de la nature,
maximum, ports fixes, non entier) et l'assertion discriminante décrite plus haut. `dune build` et
`dune test` verts (7 tests, 0 échec), aucun processus orphelin.

**Limite assumée** : la borne dynamique `network#port_no_lower_of` est **appliquée** (c'est
l'expression même du dialogue GUI) mais **non discriminée** par le banc — l'exercer demande un
câble branché sur un port d'indice supérieur au minimum de la nature, donc `connect`. Assertion à
ajouter à l'ép. 4d-3.

### 2026-08-06 — épisode 4d-2c : le modèle refuse avant d'écrire

Épisode court, ouvert par une question : la fragilité que l'épisode précédent avait **constatée**
puis **contournée** chez l'appelant méritait-elle d'être corrigée avant de continuer ? La relecture
a répondu oui, mais pas pour les raisons qu'en donnait la fiche `docs/TODO.md`.

**Ce n'était pas un site, mais trois — et le plus accessible manquait à la fiche.** Elle décrivait
`update_virtual_machine_with` (machine et routeur). Mais `node_with_defects#set_name` et
`node_with_ledgrid_and_defects#set_name` renomment la ligne **defects** *avant* de déléguer à
`id_name_label#set_name`, seul porteur de `check_name` : le défaut touchait donc **les sept
natures de nœuds**, par `set_name` seul, sans passer par aucun `update_*_with`. Et `update_with`
appelle `destroy_my_simulated_device` en première instruction, laquelle **enfile une tâche** sur le
`task_runner` (`user_level.ml:206-209`) qu'aucun refus ultérieur ne pourrait rappeler.

**Le trou le plus grave n'était pas le nom mal formé mais l'homonyme.** `network#name_exists` n'est
lu que par `add_node` et `add_cable` ; un renommage ne passe ni par l'un ni par l'autre. Le modèle
**acceptait** donc de renommer un nœud sur le nom d'un autre, et le canal — qui adresse les
composants par nom — n'aurait plus jamais su lequel des deux il désignait. Rien dans la fiche ne le
disait ; c'est la relecture de `add_node` qui l'a montré.

**Correctif** : une fonction libre `check_new_name ~network ~old_name` (`user_level.ml`), qui rejoue
les deux tests du dialogue GUI et lève si le nom est mal formé **ou** déjà pris, appelée en
**première instruction** des cinq chemins destructeurs. Trois rangées de `user_level.mli` gagnent
`name_exists : string -> bool`. Rien ne change chez les appelants : la GUI garde son
`Ok_callback.check_name` (elle doit rendre `None` pour reboucler et afficher un message localisé,
pas attraper une exception) et le serveur garde ses deux tests (ils produisent un `bad_argument`
motivé). **Ce correctif est un filet, pas une source unique de vérité** — et c'est assumé : ce
qu'il achète, c'est qu'un troisième appelant échoue **bruyamment et sans dégât** au lieu de
corrompre en silence.

**Preuve — un banc témoin, parce que le chemin est devenu inatteignable.** Les deux appelants
pré-valident : aucun banc « normal » ne peut plus mesurer quoi que ce soit. La méthode est celle
des épisodes 3a (témoin `SIGPIPE`) et 3b (témoin `~cloexec`) : `rename-witness.sh` tourne avec les
deux tests de `set_structural` **désarmés** (`if false && …`), et regarde le modèle laissé seul.
Résultat, sur le **`.mar` enregistré** et non sur le canal :

| | avant le correctif | après |
|---|---|---|
| `rename alphatemoin 1betatemoin` (mal formé) | refusé, mais `1betatemoin` écrit dans `states/ifconfig`, `states/defects`, `states/states-forest` **et** répertoire `hostfs/1betatemoin` créé | refusé, **aucune trace** nulle part |
| `rename gammatemoin alphatemoin` (déjà pris) | **accepté** → 2 × `alphatemoin`, plus aucun `gammatemoin`, hostfs fusionné | refusé, les deux composants et leurs deux `hostfs/` intacts |

**4 assertions rouges sur 6** avant, **6/6** après : le banc est discriminant. Puis
`control_server.ml` restauré (`git checkout`), rebuild, et l'ensemble rejoué :
`components-bench.sh` **85 assertions vertes**, `dune build` et `dune test` verts (7 tests),
aucun processus orphelin.

**Reste hors périmètre**, et inscrit comme tel dans `docs/TODO.md` : `update_with` applique le nom
**avant** `set_label`, dont le `check_label` peut encore refuser un label contenant `<` ou `>` —
même forme de défaut, un cran plus bas, atteignable par le dialogue « Properties » de la GUI mais
pas par le canal (qui écrit le label par `eval_forest_attribute`, sans écriture préalable).

### 2026-08-06 — épisode 4d-3 : le câble, et la borne qui n'était pas celle qu'on croyait

**L'épisode a d'abord rétréci.** Le § 9 lui donnait trois livrables — `connect`, `disconnect`,
`forest` — et la lecture en a retiré deux **avant** d'écrire une ligne.

`disconnect` nommait deux commandes déjà livrées : en GUI, « Disconnect / Reconnect » **débranche
et rebranche** (c'est `suspend`/`resume`, ép. 4c), et **supprimer** un câble, c'est `del`
(ép. 4d-2a, mesuré en marche à l'ép. 4b). Le mot venait de la conception de l'ép. 0, écrite avant
que ces commandes n'existent ; le garder aurait créé un synonyme à tenir en cohérence.

`forest`, lui, s'est heurté à un fait de format : **`netmodel/network.xml` n'est pas du XML**. Le
nom, et le commentaire « Pseudo XML now! (using xforest instead of ocamlduce) », sont un vestige ;
`Netmodel.Xml.save_network` écrit par `Oomarshal.marshaller#to_file` (`user_level.ml:2127`), qui est
`Marshal.to_channel` (`lib/MARSHAL/oomarshal.ml:35`). Un client Bash ne peut donc pas produire de
fragment, et lui en faire produire un exigerait que l'OCaml **parse** un format structuré — ce que
la décision du § 2 exclut depuis l'ép. 0. La commande est **suspendue** avec ses trois voies de
sortie écrites au § 4.8, plutôt que bâclée. Détail piquant : l'ép. 4d-2b avait déjà tiré profit de
ce fait, en cherchant les noms au `grep -a` dans un fichier « xml » — sans en tirer la conséquence
sur `forest`.

**Reste `connect`, et une garde que le modèle n'a pas.** Le constructeur de câble résout
`<nœud>:<port>` puis s'enregistre lui-même (`cable.ml:645`,`666`) : il branche là où on lui dit,
que le port soit libre ou non. En GUI, c'est le **dialogue** qui l'empêche, en ne proposant que des
extrémités libres. Décision de l'épisode, prise avec l'auteur : la garde vit **côté serveur**, et
la question de la descendre dans le modèle — comme `check_new_name` à l'ép. 4d-2c — se tranchera
**sur mesure du dégât réel**, pas par symétrie. Trois autres choix, tous lus dans la GUI : le port
se **nomme** (`eth0`, `port1`) parce qu'un switch numérote à partir de 1 et une machine à partir de
0 ; la polarité est **rapportée** (`correct`) et jamais imposée, la GUI laissant elle-même
construire un câble « faux » à dessein ; et une **boucle** d'un nœud vers lui-même sur deux ports
distincts est acceptée, les deux bouts sur le même port ne l'étant pas.

**Le moment de mesure : l'assertion discriminante a échoué, et c'est le banc qui avait tort.**
L'ép. 4d-2b laissait une dette explicite — exercer `network#port_no_lower_of`, ce qui demandait un
câble. Le banc l'a écrite en croyant la borne égale au **port câblé le plus haut** : câble sur
`s1:port9`, donc `set s1 port_no 9` attendu accepté. Refusé, avec « fewer than 12 ». Lecture du
modèle (`user_level.ml:1872`) : la borne est le plus petit **multiple** de `port_no_min` qui
contienne encore ce port — un switch se dimensionne par multiples de 4, donc **12**. Le code n'avait
pas tort ; c'est notre description qui l'était, dans le commentaire du type `structural` **et** dans
le message d'erreur rendu au client (« cables are plugged into ports above 4 », ce qui laissait
croire que 8 aurait suffi). Les deux ont été corrigés. Et l'assertion a été refaite **discriminante
par construction**, en ne dépendant plus d'aucune arithmétique devinée : *la même commande, la même
valeur, avant et après `del c4`* — `set s1 port_no 8` refusé tant que le câble occupe `port9`,
accepté une fois le câble retiré. Seul le câblage change entre les deux.

**Preuve** : `components-bench.sh` étendu (bloc C8 neuf, C9/C10 renumérotés),
**119 assertions vertes**, dont la persistance vérifiée sur le **`.mar` enregistré** — `c1bis`
présent dans `netmodel/network.xml`, et le câble détruit `c1` absent, motif préfixé de son octet
de longueur Marshal pour ne pas matcher `c1bis`. Les deux dettes de l'ép. 4d-2b sont soldées : la
borne dynamique ci-dessus, et le « renommage » d'un câble qui est un `del` + `connect` (le canal le
refuse en y renvoyant, comme la GUI le fait en interne). Un câble est enfin **branché pendant que
le réseau tourne**, sur deux composants créés eux aussi en marche — la règle de projet, mesurée et
non plus seulement écrite. `dune build` et `dune test --force` verts (0 échec), aucun processus
orphelin.

### 2026-08-06 — épisode 4e : la configuration de démarrage, et le journal que l'invité renvoie

**Ce que l'épisode livre.** `rc-get` et `rc-set` (§ 4.11) : le canal sait désormais poser un
**scénario bash** sur une machine, un switch ou un routeur, le relire, l'activer, le désactiver —
et dire **où** l'invité écrira ce qu'il a à dire. C'est le premier pas concret de la direction du
§ 10 : le scripting ne s'arrête plus aux gestes de la GUI, il descend **dans** les composants.

**La décision qui a dispensé de tout aiguillage par nature.** Le champ est marshalé dans le forest
— c'est pour cela que `get`/`set` le servent `null` depuis l'ép. 4d-2a. Plutôt que d'ajouter huit
appels `#set_rc_config` typés, le contenu voyage **en clair** et c'est le **serveur** qui marshale,
puis écrit par le même `#eval_forest_attribute` uniforme que `set`. Les deux commandes ne savent
donc rien d'une machine, d'un switch ni d'un routeur.

**Et celle qui a dispensé d'une liste de noms.** Le fichier refusait déjà d'énumérer les champs
marshalés (« a list that would rot the day a component adds one ») ; la même règle valait ici. La
valeur est démarshalée en `Obj.t` — ce qui ne suppose **aucun** type — et c'est sa **forme** qui la
désigne : bloc de tag 0, taille 2, un immédiat booléen, une chaîne. `Obj.obj` n'est appliqué
qu'après. Ce n'est pas un `Obj.magic` de plus dans la dette du dépôt : là le cast est pris sur
parole, ici il est **vérifié avant**. Effet mesuré : `rc_config` (machine, switch) et
`rc_config_unix` (routeur) sont trouvés sans être nommés, tandis que `rc_config_quagga`,
`quagga_selected_srvs` et `show_quagga_terminal` — marshalés mais d'une autre forme — restent dans
`omitted`, et le disent quand on les demande.

**Le modèle a gagné une méthode, à un endroit qui n'était pas le sien.**
`component#hostfs_directory_if_any` (défaut `None`) donne au serveur le répertoire hôte que
l'invité voit en `/mnt/hostfs`, sans recopier la convention de chemin de `user_level.ml:1486`. Sa
place naturelle était le mixin `virtual_machine_with_history_and_ifconfig` — celui qui porte
`get_hostfs_directory`. Le compilateur l'a refusée : ce mixin **n'hérite pas** de `component`, donc
les deux définitions se rencontrent par héritage multiple dans `machine.ml` et `router.ml`, ce qui
est le *warning* 7 (`method-override`), erreur dans ce build. Deux `method!` explicites, dans les
deux fichiers concernés, coûtent moins qu'un warning désactivé — et se lisent mieux. Piège voisin,
déjà payé à l'ép. 4d-2b : ajouter une méthode à `component` oblige à compléter **quatre** classes
de `user_level.mli` plus `machine.mli`, sans quoi « The public method … cannot be hidden ».

**Le banc a trouvé autre chose que ce qu'il cherchait.** Deux constats, aucun des deux prévu :

1. Un composant créé **par le canal** part d'un rc **vide**. Le modèle commenté que l'humain voit
   est le défaut du **dialogue** (`machine.ml:312`), pas celui du constructeur (`machine.ml:564`,
   `?(rc_config=(false,""))`). L'assertion qui attendait un contenu non vide était donc fausse, et
   c'est elle qui a été corrigée — la deuxième fois en trois épisodes que le banc se trompe avant
   le code.
2. Surtout : **`add machine` crée une machine qui ne démarre pas.** Le constructeur prend le noyau
   par défaut *global* (`3.2.64-ghost`) alors que le dialogue GUI ne propose que ceux déclarés par
   le `.conf` de la distribution (trixie : `SUPPORTED_KERNELS='/6.12.95$/'`). Le journal le dit
   franchement — « couple (debian-trixie-47362,3.2.64-ghost) unknown! » — et l'invité ne boote
   pas. C'est exactement la famille de défauts de l'ép. 4d-2b : *« les mêmes limites que la GUI »
   inclut les gardes d'entrée des dialogues*, qui ne vivent pas dans le modèle. Défaut d'`add`,
   pas de cet épisode : inscrit au § 9, et contourné dans le banc par un `set m1 kernel 6.12.95`
   commenté à l'endroit où il se lit.

**Preuve** : `rc-bench.sh` (neuf), **59 assertions vertes, 0 échec**, dont la persistance sur le
**`.mar` enregistré** (le scénario retrouvé au `grep -a` dans `netmodel/network.xml`) et le refus
sur un composant **en marche** mesuré sur un switch réellement démarré. Et surtout le bloc R8, la
preuve qui compte pour le § 10 : scénario posé par le canal, machine démarrée par le canal, et
**le journal écrit par l'invité lu côté hôte au chemin rendu par `hostfs`**, 10 s après le
démarrage — `hôte vu par l'invité : m1`, suivi de son `ip -brief addr`. Aucun clic, aucune image
modifiée. `dune build` et `dune test --force` verts (0 échec), aucun processus orphelin.

### 2026-08-07 — épisode 4f : le noyau que la distribution déclare

Épisode entièrement dicté par une trouvaille du banc précédent : **une machine créée par le canal
ne démarrait pas**. Le correctif de fond tient en cinq lignes du modèle — à défaut de `?kernel`, le
constructeur prend le **premier noyau déclaré par le filesystem** au lieu du défaut *global*,
c'est-à-dire exactement ce que fait le dialogue GUI (`gui_bricks.ml:520-522`) — mais la lecture qui
y menait a montré que le défaut avait **trois faces**, pas une : le constructeur, `set … kernel`
(qui acceptait n'importe quel noyau installé) et `set … distrib` (qui laissait le noyau derrière
lui). C'est la même famille que l'ép. 4d-2b, et sa leçon se confirme une troisième fois : *« les
mêmes limites que la GUI » inclut les gardes d'entrée des dialogues*, qui ne vivent pas dans le
modèle.

**Deux arbitrages, dans deux directions opposées, et c'est délibéré.**

1. **La garde reste dans le serveur**, le modèle n'exposant que la lecture
   (`component#supported_kernels_if_any`, patron de `hostfs_directory_if_any`). L'ép. 4d-2c avait
   fait l'inverse pour le nom (`check_new_name` **dans** le modèle) ; ici, durcir `check_kernel`
   aurait un coût mesurable : `remap_obsolete_kernel_at_import` **garde** un noyau installé et
   moderne même s'il échappe à `SUPPORTED_KERNELS` (`user_level.ml:1378`), donc un `.mar` existant
   dans ce cas deviendrait **non chargeable**. Le patron de l'ép. 4d-3 (« sur mesure du dégât
   réel, pas par symétrie ») s'applique tel quel.
2. **`set … distrib` est autorisé alors que la GUI l'interdit.** Son combo est verrouillé une fois
   le composant créé (`gui_bricks.ml:529-531`) — mais le code porte à cet endroit un
   « TODO: release this constraint », et le modèle, lui, sait le faire. Le canal le fait donc, et
   **paie la cohérence** : le noyau est réaligné dans le **même** `network_change` et le
   changement est **rapporté** dans un champ `adjusted`, jamais silencieux. Le principe est celui
   de `cables_destroyed` (§ 4.3) : un script dont le modèle du réseau diverge sans le savoir est
   pire qu'un refus.

**Un détail d'implémentation qui n'en est pas un : l'ordre des options d'`add`.** Le serveur trie
`--distrib=` en tête quel que soit l'ordre écrit par le client, parce que la distribution
conditionne la validité du noyau ; sans ce tri, `add machine m --kernel=6.12.95-i386
--distrib=debian-wheezy-08367` serait refusé au motif d'un filesystem qui n'est même pas celui
demandé. Le banc mesure les deux ordres.

**Preuve, en deux temps, et le second est le vrai.** D'abord `components-bench.sh`, bloc **C11**
neuf : **134 assertions vertes** (119 + 15), dont le refus d'un noyau hors liste, le réalignement
rapporté, la **preuve croisée** (l'ancien noyau devient refusé sous la nouvelle distribution) et le
rollback d'un `--kernel=` invalide. Les épithètes y sont **découvertes sur le disque**, jamais
codées — et un premier jet a d'ailleurs pris les répertoires `…_variants` pour des distributions,
ce qui a fait mesurer des `set distrib <nom inexistant>` : **acceptés en silence** (`ok:true`,
`changed:false`), un mensonge doux consigné dans `docs/TODO.md` plutôt que corrigé ici.

Ensuite la mesure qui compte : `rc-bench.sh` a **perdu** son `set m1 kernel 6.12.95`, cette ligne
que l'ép. 4e avait dû écrire pour contourner le défaut. Sans elle, **R8 reste vert** — scénario
posé, machine démarrée, journal de l'invité lu côté hôte après 22 s, 59 assertions, 0 échec.
Et le **témoin** dit l'inverse avec la même netteté : le correctif mis de côté (`git stash` du seul
`bin/`, les bancs étant hors dépôt), rebuild, rejeu — `add` choisit `3.2.64-ghost`, **aucun journal
après 90 s**, 2 échecs. `dune build` et `dune test --force` verts, 0 processus orphelin.
