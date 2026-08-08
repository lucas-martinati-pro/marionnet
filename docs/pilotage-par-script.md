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
| **Ancrage** | **A** — serveur de contrôle *in-process* (cible) ; **C** — décor pré-fabriqué + option `-r` (raccourci complémentaire ; **révisé ép. 4g** : le décor n'est pas *généré hors ligne* mais produit par A et enregistré par `save-as`, cf. § 6) | A garde la GUI **vivante et observable** pendant le script : c'est précisément ce qui permet de valider une modification risquée. La variante **B** (exécutable *headless* sans GTK) est écartée : `state.ml`, `treeview.ml`, `sketch.ml` et tous les dialogues `where_p4` sont entrelacés avec lablgtk3 ; les découpler serait un refactor massif, sans rapport avec le but |
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
ne tient pas sur une ligne. Plutôt que d'ajouter un mode « corps » au protocole (sentinelle de fin,
donc un **état** dans le lecteur et un cas d'erreur de plus) ou un encodage base64 (illisible, et
un décodeur à écrire), la commande reçoit un **chemin** : `--from=/chemin/fichier`, que le serveur
lit côté hôte. Le lecteur reste un `input_line` **nu**. Légitime ici : un socket unix implique la
même machine, et le répertoire `0700` borne déjà l'accès au canal. Côté client, un heredoc Bash
vers `mktemp` fait le reste. *(Ce mécanisme devait aussi porter le fragment `Xforest` du § 4.8 ;
cette commande est abandonnée depuis l'ép. 4g, `rc-set --from=` en reste le seul usager.)*

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

**Lecture — livrée à l'épisode 5a.** Un verbe par treeview, une seule implémentation :

```
ifconfig  [<nœud>]     # filtre les RACINES par leur colonne Name
defects   [<nœud>]
history   [<nœud>]
documents              # aucun argument positionnel (pas de colonne Name)
```

Réponse : `{"ok":true,"treeview":…,"columns":[…],"count":N,"rows":[{"fields":{…},"children":[…]}]}`.
Les valeurs suivent le type de cellule (`Row_item`) : `String`/`Icon` → chaîne JSON,
`CheckBox` → **booléen** JSON. `count` est le nombre de **racines** rendues. Refus : pas de projet
→ `no_active_project` ; nom absent → `unknown_node`, **avec la liste des racines existantes**.

Trois faits du code — et non une symétrie choisie — dictent cette forme :

1. **Les quatre n'ont pas la même classe mère.** `ifconfig` et `defects` héritent de
   `treeview_with_a_primary_key_Name_column` (un `Name` est unique), `history` de
   `treeview_with_a_Name_column` (un nom désigne **plusieurs** lignes : les états successifs) et
   `documents` du `Treeview.t` nu — il n'a **aucune** colonne `Name`. D'où le filtre optionnel des
   trois premiers et son absence sur le quatrième.
2. **Les hiérarchies sont inégales** : `ifconfig` = nœud → ports ; `defects` = nœud → ports →
   **directions** (3 niveaux) *et* câble → 2 directions (2 niveaux) ; `history` = arbre de COW ;
   `documents` = plat. Une réponse aplatie en table perdrait cela : la forêt est servie **comme
   une forêt**, et le filtre reste sur les racines — un chemin profond promettrait une chose et en
   ferait trois.
3. **Les quatre n'ont pas la même population.** `ifconfig` ne reçoit que les composants
   **adressables** — `add_my_ifconfig` (`user_level.ml:1477`) n'est appelé que par le mixin des
   machines et routeurs (l.1178) —, tandis que `defects` reçoit les 8 natures **plus les câbles**.
   « Autant de racines que de nœuds » est donc faux pour `ifconfig` : c'est « autant que de nœuds
   adressables ».

**Colonnes publiées** (ordre de la GUI : `#add_column` *append*, `treeview.ml:908` — ne jamais
lire `#column_headers`, qui est un `Hashtbl.fold` d'ordre indéterminé) :

| Treeview | Colonnes servies |
|---|---|
| `ifconfig` | `Name`, `_uneditable`, `Type`, `MAC address`, `MTU`, `IPv4 address`, `IPv4 gateway`, `IPv6 address`, `IPv6 gateway` |
| `defects` | `Name`, `_uneditable`, `Type`, `Loss %`, `Duplication %`, `Flipped bits %`, `Minimum delay (ms)`, `Maximum delay (ms)` |
| `history` | `Name`, `Type`, `Activation scenario`, `Timestamp`, `Comment`, `File name`, `Prefixed filesystem` |
| `documents` | `Icon`, `Title`, `Author`, `Type`, `Comment`, `FileName`, `Format` |

Sont exclues les colonnes **réservées** (`_id`, `_highlight`, `_highlight-color`, déclarées
`~reserved:true` dans `Treeview.t`) : elles portent l'identité de ligne et la surbrillance, pas du
contenu. `_uneditable`, elle, est **cachée** en GUI (`~hidden:true`) mais **non réservée** — et
elle est servie, parce qu'elle dit quelles lignes sont éditables : `hidden` est une décision
d'écran, `reserved` une frontière d'implémentation, et un script n'est pas un écran.

**Écriture d'`ifconfig` — livrée à l'épisode 5b.** Constat du banc de l'épisode 5a : **aucun** des
8 projets de `_claude-local/examples/` ne porte d'adresse IPv4 (vérifié au `grep -a` sur
`states/ifconfig`, qui est du `Marshal`). Ce que Marionnet peuple seul, ce sont `MAC address` et
`MTU` ; tout le reste attend qu'on l'écrive.

```
ifconfig-set <nœud> <port> <champ> [<valeur>] [--restart | --no-restart]
```

Un champ à la fois, comme `set` (§ 4.3) : un refus nomme alors le champ qu'il vise. `<champ>` est
le **slug** d'une colonne — minuscules, espaces changés en tirets : `mac-address`, `mtu`,
`ipv4-address`, `ipv4-gateway`, `ipv6-address`, `ipv6-gateway` — dérivé de `#columns` et jamais
listé dans le serveur : une colonne ajoutée à un treeview devient écrivable le jour où elle
devient lisible. Une **valeur absente vide la cellule**, comme un humain qui efface la case.
Réponse : `{"ok":true,"node":…,"port":…,"field":"IPv4 address","old":…,"new":…,"changed":…,`
`"restarted":…}`, la valeur **relue** après écriture et non celle demandée.

Trois faits du code font que cet épisode ne se réduit pas à un *setter* :

1. **`#set_row_field` ne valide rien et ne prévient personne.** La validation vit dans le chemin
   GTK *cell-edited* : le prédicat de **colonne** (adresse mal formée, MTU au-dessus du MAXPACKET
   de vde2) et les contraintes de **ligne**, qu'aucune cellule prise isolément ne peut trancher —
   une valeur posée sur la ligne du device au lieu d'un de ses ports, ou le `port0` d'un routeur
   qui perdrait son adresse de configuration. Le serveur les rejoue **avant** d'écrire ; sans
   cela le canal poserait dans un projet ce qu'un humain n'a pas le droit d'y taper (§ 4.10).
2. **Le verdict devait se séparer de son affichage.** `#check_constraints` ouvre un dialogue
   (`Simple_dialogs.error`) avant de lever : sans gel depuis l'épisode 3c, mais un refus de ce
   canal est une ligne JSON, pas une fenêtre. D'où `#constraints_verdict` (`treeview.ml`) : les
   mêmes contrôles, le rendu laissé à l'appelant — une source de vérité, deux messages, comme
   `check_new_name` à l'épisode 4d-2c.
3. **La question du redémarrage passe du dialogue à la requête.** La GUI demande
   (« vos changements seront appliqués après le redémarrage de X ; redémarrer maintenant ? »,
   `marionnet.ml:143-176`) ; le serveur ne peut pas interroger un humain. Tant que le nœud tourne,
   il refuse par `restart_choice_required` jusqu'à ce que le script dise `--restart` ou
   `--no-restart` — symétrie exacte de `--save`/`--no-save` (§ 4.2). Réseau éteint, aucune option
   n'est requise. `--restart` appelle `#gracefully_restart`, donc `restarted` veut dire *accepté*,
   jamais *fini* (règle 3, § 4.4).

Refus : `no_active_project`, `unknown_node` (avec la liste des composants **adressables** — la
population de ce treeview, § 4.6), `unknown_port` (avec les ports du nœud ; c'est aussi la réponse
quand un script vise la ligne du device), `unknown_field` (avec le vocabulaire écrivable),
`constraint_violated`, `restart_choice_required`. Les colonnes **réservées** restent hors
d'atteinte, y compris `_highlight-color`, qui est pourtant une colonne *éditable*
(`treeview.ml:1825`) : `reserved` est une frontière d'implémentation, en écriture comme en lecture.

Ce qu'écrire change vraiment, et pourquoi cela valait un épisode : `simulation_level.ml:723-742`
lit **ce treeview** à la construction du device et en fait les paramètres de boot
(`ipv4_address_eth0` et consorts, déposés dans le `boot_parameters` du hostfs). Une adresse posée
par le canal avant le démarrage atteint donc l'invité — mesuré par le bloc T11 du banc.

**Écriture de `defects` — livrée à l'épisode 5c.** C'est l'autre moitié de ce qui fait un TP : les
adresses disent qui parle à qui, les *defects* disent à quel prix — pertes, duplications, bruit,
délais. Et c'est le seul treeview dont la GUI applique une écriture à un réseau **en marche**.

```
defects-set <nœud>  <port> <direction> <champ> [<valeur>] [--restart | --no-restart]
defects-set <câble>         <direction> <champ> [<valeur>]
```

Un champ à la fois, comme `ifconfig-set`, et une valeur absente vide la cellule. Réponse :
`{"ok":true,"target":…,"port":…|null,"direction":…,"field":…,"old":…,"new":…,"changed":…,`
`"adjusted":…|null,"warning":…|null,"reconnected":…|"restarted":…}`, la valeur **relue**.

Quatre faits du code — mesurés, aucun n'étant une symétrie avec `ifconfig-set` :

1. **Deux formes sous un seul verbe, et c'est le treeview qui tranche.** L'entrée d'un nœud a un
   niveau par port (nœud → port → direction), celle d'un câble n'en a pas (câble → direction). La
   forme d'une requête ne se déduit donc pas du nombre d'arguments — l'arité déclarée n'est que
   l'enveloppe, de 3 à 5 — mais du **`Type` de la racine visée** (`straight-cable`/`crossover-cable`).
   Un mélange des deux est refusé en `bad_argument`, avec la syntaxe de la forme réelle.
2. **La direction se désigne par son `Type`, jamais par son `Name`.** Sous un nœud les deux
   coïncident (`inward`/`outward`) ; sous un câble, le `Name` d'une direction est
   `to m1 (eth0)` (`cable.ml:623`) — il contient des **espaces**, donc ne peut pas être un argument
   positionnel (§ 4.1), et il **change** quand une extrémité est renommée
   (`#rename_cable_endpoints`). `Treeview_defects#get_cable_data` filtre lui-même par `Type` : le
   canal fait comme le modèle, `leftward`/`rightward`.
3. **L'application est asymétrique, et la GUI l'était déjà.** `after_user_edit_callback` →
   `shutdown_or_restart_relevant_device` (`marionnet.ml:154`) traite un câble et un nœud
   différemment : pour un **câble connecté** il fait `c#suspend; c#resume` **sans rien demander**,
   ce qui détruit et reconstruit le device simulé (`cable.ml:820-847`) dont l'`initializer` relit
   `get_my_defects` et repasse les valeurs à `wirefilter` en ligne de commande
   (`simulation_level.ml:604`) ; pour un **nœud**, il ouvre le dialogue « redémarrer maintenant ? ».
   Le canal reproduit exactement cela : un câble est rebranché d'office (`reconnected`, *accepté*
   jamais *fini* — règle 3, § 4.4) et `--restart`/`--no-restart` y est **refusé** comme sans objet ;
   un nœud en marche exige ce choix (`restart_choice_required`), comme à l'épisode 5b. Le contrat
   § 4.10 se lit ici à l'envers de l'intuition : la restriction ne vient pas de ce qui est risqué,
   mais de ce que la GUI **demande**.
4. **Le chemin GTK fait trois choses de plus qu'un `#set_row_field`**, et elles ne sont pas
   optionnelles : réaligner la borne sœur quand les deux délais se croisent (poser un minimum
   au-dessus du maximum fait suivre le maximum), rafraîchir la surbrillance de la ligne, et
   avertir qu'un pourcentage de bits retournés dépasse 1 %. Extraites dans
   `Treeview_defects#edit_side_effects` sur la forme de `#constraints_verdict` (épisode 5b) : la
   méthode *fait* les écritures et *rend* ce qu'il y a à rapporter, sans rien afficher — la GUI en
   tire son dialogue, le canal les champs `adjusted` et `warning`. Une source de vérité, deux
   messages ; la GUI n'a pas bougé d'un octet.

**Le slug d'un champ est généralisé** (et les slugs d'`ifconfig` en sortent inchangés, ce que le
banc asserte) : minuscules, tout caractère non alphanumérique devient un tiret, les tirets répétés
sont compressés et le dernier rogné. `Loss %` → `loss`, `Flipped bits %` → `flipped-bits`,
`Minimum delay (ms)` → `minimum-delay-ms`. La règle de l'épisode 5b — « espaces en tirets » —
tenait parce que les en-têtes d'`ifconfig` sont faits de lettres et d'espaces ; ceux de `defects`
ne le sont pas, et un slug portant `%` ou des parenthèses aurait obligé chaque script à le mettre
entre guillemets.

Refus : `no_active_project`, `unknown_target` (avec les racines de **ce** treeview — les 8 natures
**et** les câbles, cf. la note sur les populations ci-dessus), `unknown_port`,
`unknown_direction` (avec celles de la ligne visée), `unknown_field` (avec le vocabulaire
écrivable), `constraint_violated`, `restart_choice_required`, `bad_argument`. Deux couples
mesurés par le banc valent d'être notés, parce qu'aucune validation réécrite dans le serveur ne les
produirait : `loss 100` est accepté quand `duplication 100` est refusé (`is_a_valid_percentage`
contre `is_a_valid_non_100_percentage`), et une écriture visant la ligne d'un port ou d'un device —
et non l'une de ses directions — est refusée par la contrainte de **ligne** du treeview.

#### `history` — par ses actions, pas par ses cellules (épisode 5d)

```
history-start <fichier cow>
history-del   <fichier cow> [--except]
history-set   <fichier cow> <champ> [<valeur>]
```

**L'épisode était mal nommé, et le dire fait partie du livrable.** Le § 9 portait « `history` et
`documents` en **écriture** », par symétrie avec 5b et 5c. Appliqué à la lettre, ce patron ne
livrait presque rien : `history` n'a **qu'une** colonne éditable (`Comment`) et `documents` quatre
— des **métadonnées**, là où `ifconfig` portait les adresses et `defects` les défauts. La valeur
de ce treeview est dans son **menu contextuel**, neuf entrées qu'aucune commande ne couvrait, et
d'abord **« Start in this state »** : démarrer une machine depuis un **état de disque donné** —
le geste par lequel un enseignant place ses étudiants dans une situation préparée.

**L'identifiant est le fichier COW, pas le nom.** Dans ce treeview un `Name` désigne autant de
lignes que la machine a d'états ; le fichier COW, lui, est unique deux fois — par construction
(`cow_files.ml:23-35`, tirage aléatoire réessayé tant que le fichier existe) et dans le treeview,
ce dont le modèle lui-même dépend (`get_parent_cow_file_name` y résout par
`unique_complete_row_such_that`). Il ne porte aucun espace, donc il passe en argument positionnel
(§ 4.1), et la lecture le sert **déjà** : la colonne `File name` est `~hidden` mais **non
réservée**, et `#get_row` ne filtre que les réservées (piège « caché ≠ réservé » de l'ép. 5a). Un
script lit `history m1`, y prend l'état voulu, et le repasse tel quel.

Les gardes sont celles de la GUI, jamais des précautions inventées :

| Commande | Garde | Où elle vit en GUI |
|---|---|---|
| `history-start` | `can_startup` du nœud propriétaire | condition de l'entrée de menu (`treeview_history.ml:542-547`), qui interroge `Startup_functions` — rempli de `node#can_startup` (`marionnet.ml:129-141`), le prédicat que `can` publie déjà |
| `history-del` | la machine doit avoir **plus d'un** état | `number_of_states_with_name > 1` (`treeview_history.ml:558-563`) : le dernier état ne se supprime pas |
| `history-set` | `#constraints_verdict` avant d'écrire | patron des ép. 5b/5c ; le vocabulaire écrivable est dérivé de `#columns`, donc `comment` et rien d'autre |

`history-start` répond **`accepted`**, jamais « fait » (règle 3 du § 4.4) : `#startup_in_state`
antidate la ligne visée — ce qui en fait la plus récente, donc celle que la machine prendra —,
démarre, puis restaure l'horodatage sur le `task_runner`. `history-del` rapporte les fichiers
**réellement** disparus, relus avant et après : `--except` supprime tout un sous-arbre, et un
compte calculé de tête serait une supposition.

**Ce qui reste dehors, et pourquoi.** `documents` : ce treeview n'a **aucune** colonne `Name`,
donc aucun identifiant naturel pour une ligne de commande ; « Display » ouvre un visualiseur
externe (sans objet pour un script) et « Import » n'est qu'un dépôt de fichier. Les deux « Export
as machine/router variant » et les quatre suppressions **en masse** de `history` : `--except`
couvre le besoin réel (repartir d'un état), et le reste attendra un besoin, comme le veut la règle
de ce chantier.

Refus : `no_active_project`, `unknown_state` (avec la liste des fichiers COW qui existent),
`unknown_node` (une ligne orpheline, dont le nœud n'est plus dans le réseau), `unknown_field`,
`forbidden_transition`, `constraint_violated`, `bad_argument`.

### 4.7 Synchronisation

```
wait <nom> (--state=on|off|sleeping | --ready) [--timeout=<secondes>]
wait-all --state=… [--timeout=<secondes>]
```

Scrutation de l'état user-level, avec délai de garde. Rappel du § 2 : `--state=on` signifie
« processus UML lancé », **pas** « invité prêt ». Ces deux instants sont réellement distincts et le
banc les mesure : sur une machine trixie, `--state=on` répond en **0,8 s** là où l'invité ne
signale sa disponibilité qu'après **5,1 s** de plus.

Le second instant est ce que dit `--ready` (épisode 4h).

#### Le signal « invité prêt » (`--ready`)

La convention tient en une ligne : **le scénario de démarrage écrit
`/mnt/hostfs/marionnet-guest-ready`**, et `wait <nom> --ready` attend ce fichier. Marionnet ne le
crée pas, ne l'efface pas, et ne touche jamais à l'invité — il regarde le **côté hôte** du
répertoire que l'invité voit en `/mnt/hostfs` (celui que `rc-get` rend dans son champ `hostfs`).

Trois propriétés, et ce sont elles qui rendent la chose sûre :

- **Rien n'est injecté.** `rc-set` repose exactement ce que le script lui a donné (§ 4.11) : le
  marqueur est écrit **par le scénario**, à la main. Extrait de référence, à copier dans son
  scénario — l'écriture doit être **atomique**, sinon la sonde peut lire une ligne tronquée :

  ```bash
  # ce que l'invité exécute en fin de boot (rc-set … --from=<ce fichier>)
  LINE='ready'                      # une ligne libre : verdict, version, numéro d'étape…
  printf '%s\n' "$LINE" > /mnt/hostfs/.marionnet-guest-ready.tmp &&
    mv -f /mnt/hostfs/.marionnet-guest-ready.tmp /mnt/hostfs/marionnet-guest-ready ||
    printf '%s\n' "$LINE" > /mnt/hostfs/marionnet-guest-ready   # repli si rename(2) échoue
  ```

  Côté script, l'attente et la lecture sont un seul aller-retour :

  ```bash
  mrnctl wait m1 --ready --timeout=300   # → {"ok":true,"ready":true,"line":"ready","marker":"…","mtime":…}
  ```

- **Rien n'est mémorisé, et `start` ne gagne aucun effet de bord.** Un marqueur laissé par le
  démarrage *précédent* est ignoré par **datation** : son mtime est comparé à celui de
  `<hostfs>/boot_parameters`, que `uml_process` réécrit depuis son `initializer`, donc à **chaque**
  construction de device, donc à chaque démarrage (`simulation_level.ml:1235`, `1253-1256`,
  `1331-1332`). Un marqueur antérieur au boot courant vaut « pas prêt », et le message d'expiration
  le dit (« left by a previous run »).
- **Le nom n'est pas `marionnet-relay.*`, et ce n'est pas un détail de goût** : le relais invité
  fait `source` de `/mnt/hostfs/{<fs>.,marionnet-}relay*` en fin de boot
  (`marionnet-relay.trixie:486-494`) — un marqueur tombant dans ce glob serait **exécuté** comme du
  bash.

La réponse porte `ready`, la première ligne du marqueur (`line`, `null` si elle est vide ou n'est
pas de l'UTF-8 valide — le *signal* ne dépend jamais de ce que l'invité a écrit), le chemin hôte du
marqueur, son `mtime` et le temps attendu. Les trois attentes se distinguent dans le détail du
timeout : jamais démarré (aucun `boot_parameters`), marqueur absent, marqueur périmé. Un composant
sans hostfs — switch, hub, câble — reçoit un `bad_argument` qui le renvoie à `--state` ; un
composant détruit en cours d'attente, un `unknown_node`.

`wait-all --ready` n'existe **pas** : un script attend ses machines l'une après l'autre pour un
temps total identique (elles bootent en parallèle), et le confort ne justifiait pas la question
« que faire des nœuds sans hostfs ? ».

Ce que la doc affirmait ici avant l'ép. 4h était **faux sur un point** : l'inotify de
`bin/machine.ml` ne surveille pas la racine du hostfs mais son sous-répertoire `.X11-unix`, avec un
filtre `ttyS<n>-pts<n>.(opened|closed)` (relais X11). Il n'y avait donc rien à réutiliser — d'où
l'observation par `stat`, faite dans le thread de session, jamais dans un créneau GTK.

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

### 4.8 La porte de sortie qui n'en était pas une

*Conçue à l'ép. 0, **suspendue** à l'ép. 4d-3 sur un fait de format, **abandonnée** à l'ép. 4g
(2026-08-07). La conception d'origine est conservée en fin de paragraphe, comme trace.*

```
forest < fragment.xml        ← ABANDONNÉ, ne sera pas implémenté
```

L'idée était une **porte de sortie** : plutôt que de multiplier les commandes, appliquer au réseau
un fragment `Xforest` et couvrir d'un coup tout ce qu'un `.mar` sait représenter. Le fait de format
relevé à l'ép. 4d-3 l'a suspendue — `netmodel/network.xml` **n'est pas du XML** malgré son nom :
`Netmodel.Xml.save_network` passe par `Oomarshal.marshaller#to_file` (`user_level.ml:2176-2181`),
c'est-à-dire `Marshal.to_channel` (`lib/MARSHAL/oomarshal.ml:35`,`41`), du **binaire OCaml** ; le
nom du module et le commentaire « Pseudo XML now! (using xforest instead of ocamlduce) » sont un
vestige de l'époque ocamlduce. Un client Bash ne peut donc pas écrire un fragment, et lui en faire
produire un supposerait que l'OCaml **parse** un format structuré, ce que la décision du § 2 exclut.

**Décision de l'ép. 4g : la commande n'existera pas.** Le format n'en est que l'occasion ; les
raisons, elles, tiennent au périmètre — dans l'ordre de leur poids.

1. **Sa couverture est déjà acquise, et par construction — pas par estimation.**
   `network#eval_forest_child` (`user_level.ml:1808-1816`) ne fait qu'une chose : dispatcher chaque
   enfant vers les 8 procédures `try_to_add_<kind>` enregistrées, sous une racine
   `("network",[])` (l.1795). Ce fichier ne porte donc **que des nœuds et des câbles** — les
   treeviews sont persistées à part (`states/ifconfig`, `states/defects`, mesuré ép. 4d-2b). Or
   `add`/`set`/`connect` visent **le même vocabulaire** : `#to_tree` publie les champs,
   `#eval_forest_attribute` les écrit (§ 4.3). Le périmètre de `forest` est **exactement** celui
   des commandes livrées aux ép. 4d-2a → 4d-3, vocabulaire compris, parce que c'est la **même
   source de vérité**. Ce que `forest` ajouterait n'est pas du pouvoir d'expression, c'est le
   **lot** : un aller-retour au lieu de N. Personne ne l'a demandé, et les bancs construisent déjà
   des réseaux entiers commande par commande.
2. **Ce lot serait une régression de diagnostic.** `try_to_add_machine` se termine par
   `with _ -> false` (`machine.ml:545`) et `user_level.ml:1335` documente qu'un composant mal formé
   est « *silently dropped by the try_to_add_\* machinery* ». L'ép. 4d-2a a écarté ce registre au
   profit des **constructeurs** pour cette raison précise ; depuis, `add` refuse **avant** d'écrire
   (ép. 4d-2c, 4f), rapporte ce qu'il réaligne (`adjusted`) et sait défaire. Revenir au registre
   pour gagner un aller-retour, c'est échanger des refus motivés contre des silences.
3. **La seule variante qui apporterait quelque chose sort du contrat.** La voie (a) — le fragment
   est un fichier **produit par Marionnet** et `forest` *compose* deux projets — n'est pas une
   commande de plus, c'est une **fonctionnalité neuve**, absente de la GUI, donc hors du contrat du
   § 4.10. Elle butterait de surcroît sur les collisions de noms, les treeviews que
   `network.xml` ne porte pas, les répertoires `hostfs/`/`states/` à fusionner et les remaps
   d'import. L'idée est gardée dans `docs/TODO.md` ; elle ne relève pas de ce chantier.

La voie (c) — définir une syntaxe textuelle et la parser côté OCaml — reste ce qu'elle était : le
prix en est la décision du § 2, pour un bénéfice nul face à un script qui *est* déjà la description
du réseau.

**Corollaire, tranché dans le même mouvement : l'épisode 7 (voie C, § 6) est absorbé.** Fabriquer
un décor ne demande pas d'écrire un `.mar` hors ligne — cela demande `new` + `add`/`connect`/`set`
+ **`save-as`** (§ 4.2), c'est-à-dire de laisser **Marionnet** écrire le format dont il est le seul
producteur légitime. L'option `-r` garde tout son sens : elle **rejoue** un `.mar` ainsi produit.

**Conception d'origine (trace, sans suite).** La commande recevait un fragment par
`--from=<chemin>` (§ 4.1), le confiait au registre `eval_forest_child`, et sa réponse **devait**
rendre compte du nombre d'éléments réellement intégrés — un `ok` sur un fragment silencieusement
rejeté aurait été pire qu'inutile.

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

## 5. Client `marionnet-ctl` (symlink `mrnctl`)

*Réalisé à l'**ép. 6** (2026-08-08) — `useful-scripts/marionnet-ctl`, versionné. Le nom court de
la conception (`mrnctl`) est gardé en **symlink** : le long se découvre à la complétion
(`marionnet<TAB>`) et suit la convention du seul autre exécutable compagnon installé
(`marionnet-sudoers.sh`), le court reste tapable dans les bancs. `ctl` = *control*, comme dans
`systemctl`/`journalctl` : le **client** en ligne de commande d'un service.*

```bash
export MARIONNET_CONTROL_SOCKET=$XDG_RUNTIME_DIR/mrn.sock
marionnet --control-socket "$MARIONNET_CONTROL_SOCKET" &

mrnctl help                       # le vocabulaire, servi par le serveur lui-même
mrnctl help connect               # la syntaxe d'un verbe
mrnctl new /tmp/lab.mar
mrnctl add machine m1 --ports=2
mrnctl connect c1 m1:eth0 s1:port1
mrnctl start m1
mrnctl wait m1 --state=on --timeout=120
state=$(mrnctl -q '.nodes[] | select(.name=="m1") | .state' ls)
mrnctl shutdown-all && mrnctl quit
```

### 5.1 Il ne connaît aucune grammaire — et c'est le point

Le client **ne sait pas** que `start` prend un composant ni que `connect` en prend trois : il
transmet la ligne et rend la réponse. Le vocabulaire appartient au serveur, qui le **publie** —
commande **`help`** (ép. 6, ~35 l. dans `bin/control_server.ml`), qui rend `arity_of_command` en
JSON : `verb`, `syntax`, `min_args`, `max_args`, `free_tail`, dans l'ordre de la table.

Le motif n'est pas la commodité mais l'**unicité** : un client portant sa propre copie de la
grammaire serait une seconde source de vérité, donc celle qui dérive — c'est exactement ce qui a
fait abandonner `forest` à l'ép. 4g. L'assertion C1 du banc le mesure : la liste servie par `help`
et celle que le dispatch énumère dans le `detail` d'un `unknown_command` sont **identiques**.

Conséquence pratique : une commande ajoutée au serveur est immédiatement utilisable, documentée et
complétable, sans toucher au client.

### 5.2 Ce qu'il apporte, lui

| | |
|---|---|
| **Résolution du socket** | `--socket=PATH`, sinon `$MARIONNET_CONTROL_SOCKET`, sinon une erreur qui dit comment lancer Marionnet. **Aucune découverte automatique** : le serveur n'a pas de chemin par défaut, et deviner en balayant `$XDG_RUNTIME_DIR` serait de la magie |
| **Délai de transport** | `socat -t N -T N` — les **deux**, leçon de l'ép. 4c. Et surtout : une requête portant `--timeout=N` fait attendre le client **N + 10 s**, sans qu'on ait rien à régler. C'est ce que les bancs faisaient à la main en basculant sur `ask_long` |
| **Code de retour** | `0` accepté · `1` refusé (`ok:false`) · `2` faute du client (socket absent, `socat`/`jq` manquant) · `3` pas de réponse. C'est ce qui rend `mrnctl … && …` fiable |
| **Sorties** | par défaut **la ligne JSON telle quelle** ; `--query=<jq>` extrait ; `--pretty` indente. Le refus reste sur **stdout** en JSON *et* s'explique en clair sur **stderr** |
| **Mode lot** | `-f <fichier>` (ou `-`) : une commande par ligne, arrêt au premier refus sauf `--keep-going`. Commentaires `#` en début de ligne ignorés — jamais un `#` rencontré au milieu d'une valeur |

⚠️ **Révision de la conception** : le `--raw` prévu ici « pour un agent » n'existe pas — c'est le
**défaut**. Le brut est le comportement honnête et scriptable ; c'est l'humain qui demande un
confort, avec `--pretty`.

### 5.3 Deux décisions de mise en œuvre, motivées

- **Pas de `bashbricks`**, alors que la règle du dépôt l'impose à tout script neuf : sourcer la
  bibliothèque coûte **~65 ms mesurés par invocation**, quand le travail utile du client est un
  aller-retour de socket et qu'un banc l'appelle des centaines de fois par run. Le seul JSON qu'il
  doit lire est le champ `ok`, que le serveur émet **toujours en premier** (`reply_ok` /
  `reply_error`) : un motif ancré suffit, et il est asserté. Les extractions riches sont déléguées
  à `jq` (`--query`), dépendance **optionnelle** vérifiée au point d'usage.
- **Une connexion par commande**, y compris en mode lot. Le serveur boucle bien sur une session,
  mais apparier les réponses aux requêtes mettrait un **état** dans le client pour un gain nul :
  les bancs ont passé des centaines de commandes ainsi.

### 5.4 `bench-lib.sh` — le préambule des bancs, extrait

Hors dépôt (`_claude-local/bench/`), corollaire direct du client : les huit bancs portaient chacun
~80 lignes identiques (lancement, attente du socket, `ask`, `expect_*`, nettoyage par répertoire
de session, fusible de cardinalité). Un garde-fou recopié à la main finit par diverger — et
celui-là a coûté une session KDE entière le 2026-08-03. Il n'y en a plus qu'une copie ; `ask` y
tient désormais en **une ligne**, puisque c'est `marionnet-ctl` qui parle.

`can-bench.sh` a servi de **témoin** de l'extraction : −100 lignes, et les **16 assertions t0
rigoureusement identiques** à celles du run joué juste avant conversion.

### 5.5 Le guide utilisateur (épisode 8)

`doc-src/scripting/README.md` (+ `examples/`), **versionné**, en **anglais**. Dernière pièce du
chantier : jusqu'ici, tout ce qui existait était interne — *ce* document (conception + journal,
écrit pour nous, en français) et le vocabulaire que le serveur publie lui-même. Il manquait un
mode d'emploi pour l'enseignant qui scripte un TP, ou pour l'agent qui pilote.

Quatre questions étaient ouvertes ; voici comment elles ont été tranchées, et pourquoi.

- **Forme : un Markdown versionné dans `doc-src/scripting/`, pas du texinfo.** `doc-src/` est
  bien le dossier des sources de documentation, mais son unique occupant
  (`documentation.texi`, 2008, Marco Stronati) vise le **développeur**, n'a pas bougé depuis
  2012, et sa chaîne (`texi2dvi`, `makeinfo` → `doc/`) n'est **pas** branchée sur
  `dune install`. Refaire un guide utilisateur dans ce moule aurait coûté une chaîne de build
  pour un gain nul. Le Markdown se lit tel quel dans le dépôt, sur une forge, et reste
  installable le jour où on le décidera.
- **Périmètre : la FORME et les INVARIANTS, jamais la liste des commandes.** C'est la décision
  structurante, et c'est la même qu'à l'ép. 6 pour le client : le serveur est la **source unique**
  de la grammaire (`help` → `arity_of_command`). Une table de commandes recopiée dans un guide
  serait un second exemplaire — juste le jour où on l'écrit, faux ensuite. Le guide dit donc la
  forme du canal (ligne → ligne JSON, codes d'erreur, 4 codes de retour), les **invariants**
  (le contrat de l'automate, `accepted` ≠ fait, le marqueur d'invité, un champ à la fois, le
  *slug* de colonne), et des **recettes** complètes ; pour « quels verbes existent », il renvoie
  à `mrnctl help`. Un § final l'énonce comme règle de maintenance, pas comme un choix de goût.
- **Langue : l'anglais.** Le vocabulaire documenté l'est (`start`, `wait --ready`,
  `ifconfig-set`), la documentation livrée du dépôt l'est, et Marionnet se diffuse au-delà du
  public francophone. Une traduction française reste possible **plus tard et sans risque**,
  précisément parce que le guide ne porte pas la grammaire : elle ne pourrait pas devenir une
  seconde source de vérité. Ce document-ci reste en français : il s'adresse aux développeurs.
- **Anti-dérive : des exemples EXÉCUTABLES, versionnés et joués.** `doc-src/scripting/examples/`
  contient `01-build-a-lab.sh`, `02-run-and-collect.sh`, `scenario-ping.sh` (côté invité) et
  `lab.mrn` (mode lot). Ce ne sont pas des extraits illustratifs : le banc les lance **tels
  quels**. Un exemple qui casse est le signal qu'on attend d'une doc qui a dérivé.

**Les exemples n'utilisent pas `bashbricks`**, contre la règle du dépôt et pour la même raison
qu'à l'ép. 6 : un exemple est fait pour être **copié hors de l'arbre** et modifié ; une dépendance
à la disposition du dépôt serait la première chose à casser, et masquerait derrière des helpers
ce que le lecteur vient voir. Le skill lui-même admet le shell nu quand la tâche est triviale —
ici, ce sont des suites d'appels à `mrnctl`, sans collection ni JSON à manipuler.

**Ce que le banc a corrigé, et qui n'aurait pas été vu à la relecture** (`doc-bench.sh`,
39 assertions, 0 échec) : un **switch numérote ses ports à partir de 1** (`port1`) là où une
machine numérote ses interfaces à partir de 0 (`eth0`) — le guide écrivait `s1:port0` partout ;
le champ d'une écriture est le **slug** (`ipv4-address`), jamais l'en-tête GUI (`"IPv4 address"`),
qui est refusé en `unknown_field` ; la réponse d'une transition est
`{"component","action","accepted":true,"beyond_gui":false}` et non un `"accepted":"start"` ;
`can` rend une **liste** d'actions autorisées, pas un objet de booléens ; la racine d'une réponse
de treeview est `rows`, pas `roots`, et chaque nœud est `{"fields","children"}` ; enfin un
**chemin qui n'est pas un socket** sort en **2** (`not a unix socket`), le **3** étant réservé au
socket qui existe et ne répond pas. Six affirmations fausses écrites de bonne foi, toutes
attrapées par l'exécution.

**Hors périmètre, assumé et motivé : l'installation.** Ni le guide ni `marionnet-ctl` ne sont
ajoutés à `dune install` ici. Les deux forment **un seul** épisode d'installation cohérent (le
client irait dans `$(SHARE_DIR)/scripts`, recopié vers `$(PREFIX)/bin` par le `Makefile` ; le
guide en `(section doc)`), et cet épisode appartient au chantier
`modernisation-installation-marionnet`, pas à celui-ci — c'est exactement la frontière que
l'ép. 6 avait déjà refusé de franchir.

### 5.6 `mrn-check` — vérifier un `.mrn` sans rien envoyer (épisode 9)

`useful-scripts/mrn-check`, **versionné**. Motif : le mode lot **n'a pas de transaction**
(§ 5.2) — envoyer un fichier à l'aveugle, c'est découvrir la faute de la 5ᵉ ligne quand les
quatre premières ont déjà modifié le projet. Le vérificateur lit, contrôle, et n'envoie **rien**.

**Il ne porte pas plus la grammaire que le client** : il la demande au serveur (`marionnet-ctl
help`), et `--grammar=FICHIER` valide **hors ligne** contre un instantané pris par
`marionnet-ctl help > grammar.json`. L'instantané est un **cache**, jamais une source — dit dans
le script, dit dans le guide. C'est la même règle qu'aux ép. 4g et 6, appliquée une troisième fois.

**Ce qu'il contrôle au-delà de l'arité**, et que la grammaire ne peut pas dire : le fichier est
**rejoué contre un modèle construit à partir de lui-même** — nom déjà pris, composant référencé
sans `add`, nom de port, port hors du `--ports=` déclaré, port déjà occupé par un câble antérieur.

**Le modèle n'est cru que quand ce fichier le construit à partir de rien** (drapeau
`authoritative`). `new` ouvre un projet vide, donc on connaît tout ; `open` charge un projet
qu'on ne voit pas, et un fichier sans commande de projet s'appuie sur la session en cours. Dans
ces deux derniers cas les contrôles d'existence sont **désactivés** et une `note` le dit :
inventer des erreurs sur des noms qu'on ne peut pas connaître serait pire que ne rien dire.

**Une seule connaissance du modèle est recopiée ici, et c'est un choix borné** : la table
`kind → (préfixe, offset)` des noms de ports (machine `eth0`…, switch/hub/world_gateway
`port1`…, routeur/cloud/world_bridge `port0`…), avec les `fichier:ligne` qui la déclarent. Elle
n'est pas publiée par `help` et c'est elle qui attrape la faute-témoin de l'ép. 8. Un `kind`
absent de la table **désactive** les contrôles de port pour ce composant au lieu de deviner.
Les **nombres de ports par défaut**, eux, ne sont **pas** recopiés : sans `--ports=` explicite,
le contrôle de borne ne s'applique pas — moins de couverture, mais aucune valeur à resynchroniser.

**Pas de `bashbricks`, et cette fois pour une raison vérifiable** : `mrn-check` est destiné à
`$(PREFIX)/bin` à côté de `marionnet-ctl`, et **rien n'installe `bashbricks`** (vérifié :
aucune mention dans `Makefile`, `Makefile.d/`, ni dans une stanza `(install)`). Un `source`
relatif marcherait dans l'arbre des sources et casserait une fois installé. `jq`, en revanche,
est une dépendance **dure** ici — l'outil lit un JSON de grammaire, il n'est pas sur un chemin
chaud, et deux chemins de lecture vaudraient moins qu'un message clair.

**Le discriminant du banc, c'est l'accord avec le serveur** (`check-bench.sh`, K4) : sur un
fichier fautif, la **première ligne** signalée par `mrn-check` doit être **celle où `mrnctl -f`
s'arrête réellement — même ligne, même motif**. Sans cette assertion, le banc ne mesurerait que
la cohérence du vérificateur avec lui-même. Mesuré : ligne 6 des deux côtés, motif
`node "s1" has no port "port0"`, et le témoin (fichier valide) accepté par les deux.

---

## 6. Architecture C — le décor pré-fabriqué (`-r`)

*Intitulée « générateur de `.mar` » jusqu'à l'ép. 4g ; le titre a suivi la révision ci-dessous.*

Voie complémentaire, sans aucune modification d'OCaml : produire le `.mar` hors ligne, puis
lancer avec l'option **`-r`/`--run` qui existe déjà** (`bin/initialization.ml:65`, « *immediately
run the specified project* »).

Utile quand « fabriquer un décor de test » suffit. Insuffisant seul : après le lancement, plus
aucune prise (pas de transition ciblée, pas d'attente d'état, pas de terminaison propre scriptée).
D'où l'ordre : **C fabrique le décor, A le pilote**.

⚠️ **RÉVISÉ à l'ép. 4g (2026-08-07) : « hors ligne » était une impasse, et A l'a rendue inutile.**
Le `.mar` contient du `Marshal` binaire (§ 4.8) : aucun script ne peut l'écrire, et *ce chantier*
n'écrira pas de générateur OCaml pour cela. La bonne nouvelle est qu'il n'y a plus rien à écrire —
le décor se fabrique **par le canal** (`new` + `add`/`connect`/`set`/`rc-set`) et c'est **`save-as`**
(§ 4.2, ép. 4d) qui produit le `.mar`, laissant le format à son seul producteur légitime. La
séquence devient donc : **A fabrique le décor une fois et l'enregistre, `-r` le rejoue** — autant
de fois qu'on veut, sans repasser par la fabrication. L'**ép. 7 est absorbé** par ce constat (§ 9).

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
| **4g** | `forest` (§ 4.8) **re-tranché : abandonné** — sa couverture est acquise par `add`/`set`/`connect` (même source de vérité `#to_tree`/`#eval_forest_attribute`), le lot serait une régression de diagnostic, et la seule variante utile (composer deux projets) sort du contrat § 4.10 ; corollaire : l'ép. 7 est **absorbé** | **fait** (2026-08-07) — décision, aucun code |
| **4f** | Le couple (distrib, noyau) : le constructeur suit la distribution (comme le dialogue), `set … kernel` hors `SUPPORTED_KERNELS` refusé, `set … distrib` réaligne le noyau et le rapporte dans `adjusted` | **fait** (2026-08-07) — 134 assertions (`components-bench.sh`, bloc C11 neuf) + **le bout en bout de `rc-bench.sh` sans aucune pose de noyau à la main** |
| 4e | `rc-set`/`rc-get` (§ 4.11, § 10) : la configuration de démarrage, donc le scripting **dans** les composants | **fait** (2026-08-06) — `rc-bench.sh` |
| **4h** | Signal « invité prêt » (§ 10, point 1) : marqueur `marionnet-guest-ready` écrit par le scénario, `wait <n> --ready`, fraîcheur par datation contre `boot_parameters` | **fait** (2026-08-07) — 29 assertions, `ready-bench.sh` (dont l'anti-périmé, discriminant) |
| **5a** | Les 4 treeviews, **face lecture** : un verbe par treeview, une implémentation, la forêt servie comme une forêt (§ 4.6) | **fait** (2026-08-07) — 47 assertions, `treeview-bench.sh` |
| **5b** | Écriture d'`ifconfig` (adresses, MAC, MTU) — là où le TP se configure : `ifconfig-set`, les contraintes de la GUI rejouées par le serveur (`#constraints_verdict`), et le choix de redémarrage exigé du script | **fait** (2026-08-07) — 80 assertions, `treeview-bench.sh` (T8→T11, dont le bout en bout `boot_parameters`) |
| **5c** | Écriture de `defects` (pertes, délais) : `defects-set`, deux formes sous un verbe, la direction désignée par son `Type`, et l'application **à chaud** pour un câble — mesurée, pas présumée | **fait** (2026-08-07) — 138 assertions, `treeview-bench.sh` (T12→T15, dont la ligne de commande du `wirefilter` recréé) |
| **5d** | ~~`history` et `documents` en écriture~~ → **`history` par ses ACTIONS** : l'intitulé était trompeur (une seule colonne éditable ici, quatre de métadonnées là), la valeur était dans le menu contextuel — `history-start` (démarrer dans un état donné), `history-del`, `history-set … comment`. `documents` **hors périmètre**, motivé (§ 4.6) | **fait** (2026-08-08) — 22 assertions (`treeview-bench.sh`, T16), dont le discriminant de profondeur |
| **6** | Client `marionnet-ctl` (symlink `mrnctl`), **sans grammaire** — plus la commande serveur `help` qui publie `arity_of_command`, et `bench-lib.sh` qui retire le préambule recopié dans les huit bancs | **fait** (2026-08-08) — 36 assertions (`ctl-bench.sh`, C1→C8), et `can-bench.sh` converti rend les **16 mêmes** assertions qu'avant |
| ~~7~~ | ~~Voie C : générateur de `.mar`~~ | **absorbé** (ép. 4g) — le décor se fabrique par le canal et s'enregistre par `save-as` (§ 6) |
| **7** | La garde d'`open` : le faux négatif intermittent (`internal — flagged as unsaved`) était une **course** — `Cortex` lance un thread par commit `on_commit`, donc la réaction des `dotoptions` restaurées pouvait salir le projet *après* l'enregistrement de son état | **fait** (2026-08-08) — correctif = **retirer** les callbacks pendant la restauration (`Sketch.tuning`), 7/10 → 0/10 au banc `open-bench.sh` sous `taskset -c 0` |
| **9** | **`mrn-check`** (§ 5.6) : vérifier un `.mrn` **sans rien envoyer** — le mode lot n'a pas de transaction. Grammaire **demandée au serveur** (`--grammar=` pour l'instantané hors ligne), plus un **modèle rejoué depuis le fichier** (noms, ports, occupation), cru seulement quand le fichier part d'un `new` | **fait** (2026-08-09) — 32 assertions (`check-bench.sh`), **discriminant K4** : même ligne et même motif que l'arrêt réel de `mrnctl -f` |
| **8** | **Documentation utilisateur** (§ 5.5) : `doc-src/scripting/README.md` + `examples/`, en anglais, versionnés — la forme et les invariants du canal, **jamais** la liste des commandes (elle appartient à `help`), et des exemples **exécutables** comme garde anti-dérive | **fait** (2026-08-09) — 39 assertions (`doc-bench.sh`), dont les 4 exemples joués tels quels et le bout en bout invité (`--ready`, journal relu côté hôte) |

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
| hostfs = répertoire **hôte** monté en `/mnt/hostfs` | `simulation_level.ml:868` | ⇒ le journal écrit par l'invité est lisible côté hôte |

*Rectification (ép. 4h)* : ce tableau annonçait un « inotify déjà en place » sur le hostfs
(`machine.ml:867-934`). Il porte en réalité sur le **sous-répertoire `.X11-unix`** et sur les seuls
fichiers `ttyS<n>-pts<n>.(opened|closed)` du relais X11 — rien qui serve à observer un marqueur.

Deux conséquences pour la suite du chantier :

1. **Le canal « invité prêt » qui manquait au § 4.7 existe déjà.** Un scénario qui touche un fichier
   dans `/mnt/hostfs/` donne au script un signal de disponibilité **sans** toucher aux images —
   c'est-à-dire sans dépendre du chantier `marionnet-kernel-rootfs`. **Fait à l'ép. 4h** : la
   convention est `marionnet-guest-ready`, l'attente est `wait <n> --ready`, et la fraîcheur se
   décide par datation contre `boot_parameters` (§ 4.7).
2. **Ne pas faire passer `rc_config` par un fichier de projet.** Dans le `.mar`, ce champ est
   **marshalé** (`Marshal.to_string`, `machine.ml:644`/`660`, `switch.ml:455`/`464`) : il lui
   fallait une **commande dédiée**, transportant le contenu **en clair** par chemin de fichier
   (§ 4.1). C'est `rc-set`/`rc-get`, livrées à l'ép. 4e (§ 4.11) — et c'est le premier des deux
   arguments qui ont fini par emporter l'abandon de `forest` et l'absorption de la voie C
   (§ 4.8, ép. 4g).

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
`Netmodel.Xml.save_network` écrit par `Oomarshal.marshaller#to_file` (`user_level.ml:2176-2181`),
qui est `Marshal.to_channel` (`lib/MARSHAL/oomarshal.ml:35`). Un client Bash ne peut donc pas
produire de fragment, et lui en faire produire un exigerait que l'OCaml **parse** un format
structuré — ce que la décision du § 2 exclut depuis l'ép. 0. La commande est **suspendue** avec ses
trois voies de sortie écrites au § 4.8, plutôt que bâclée. Détail piquant : l'ép. 4d-2b avait déjà
tiré profit de ce fait, en cherchant les noms au `grep -a` dans un fichier « xml » — sans en tirer
la conséquence sur `forest`. *(Suite : la suspension est devenue un **abandon** à l'ép. 4g, pour une
raison de périmètre et non de format — § 4.8.)*

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

### 2026-08-07 — épisode 4g : la porte de sortie qu'on n'ouvrira pas

Épisode de **décision**, sans une ligne de code : la commande `forest`, suspendue à l'ép. 4d-3 sur
un fait de format, est **abandonnée** — et la voie C (générateur de `.mar`, ép. 7) est **absorbée**
dans le même mouvement.

**Le motif de la suspension n'était pas le vrai motif de l'abandon.** Le `.mar` est du Marshal
binaire : ce fait rendait `forest` inécrivable par un client Bash, mais un fait d'implémentation ne
décide pas d'un périmètre. La question à instruire était : *que resterait-il à `forest` si le
format était textuel ?* La lecture répond **rien**, et la démonstration est structurelle plutôt
qu'estimative : `network#eval_forest_child` (`user_level.ml:1808-1816`) ne dispatche que vers les 8
`try_to_add_<kind>`, sous une racine `("network",[])` (l.1795) — donc **nœuds et câbles, rien
d'autre** ; les treeviews sont ailleurs. Et le vocabulaire des attributs est **le même** des deux
côtés : `#to_tree` publie, `#eval_forest_attribute` écrit, aussi bien pour le chargement d'un `.mar`
que pour `add`/`set`/`connect` depuis l'ép. 4d-2a. Deux chemins qui partagent leur source de vérité
ont, par construction, la même couverture ; la différence se réduit au **lot** (un aller-retour au
lieu de N), que personne n'a demandé.

**Et ce lot serait payé en diagnostic.** Le registre `try_to_add_*` se termine par `with _ -> false`
(`machine.ml:545`), et le modèle documente lui-même qu'un composant mal formé y est *silently
dropped* (`user_level.ml:1335`). L'ép. 4d-2a l'avait écarté pour cette raison, et tout ce que les
épisodes suivants ont construit — refuser **avant** d'écrire (4d-2c, 4f), rapporter ce qu'on
réaligne (`adjusted`), défaire un `add` invalide — vit du côté des constructeurs. `forest` aurait
échangé des refus motivés contre des silences, dans un chantier dont l'instrument doit d'abord ne
pas mentir.

**La seule variante qui apportait quelque chose n'appartient pas à ce chantier.** Composer deux
projets (`forest <projet.mar>`) n'est pas une commande de plus mais une **fonctionnalité neuve**,
absente de la GUI, donc hors du contrat du § 4.10 — et lourde : collisions de noms, treeviews que
`network.xml` ne porte pas, `hostfs/`/`states/` à fusionner, remaps d'import. Elle part dans
`docs/TODO.md`, comme idée, pas comme dette.

**Le corollaire était le vrai gain de l'épisode.** La voie C reposait sur la même impossibilité :
« produire le `.mar` hors ligne » suppose d'écrire du Marshal. Or le besoin — fabriquer un décor —
est servi depuis l'ép. 4d sans qu'on l'ait remarqué : `new` + `add`/`connect`/`set`/`rc-set` +
**`save-as`**, c'est-à-dire laisser Marionnet écrire le format dont il est le seul producteur
légitime, puis `-r` pour le rejouer autant de fois qu'on veut. Un épisode disparaît du § 9 non
parce qu'il est difficile, mais parce qu'il est **déjà fait ailleurs**.

Leçon de méthode, la même qu'à l'ép. 4d-3 d'ailleurs : un découpage écrit à l'ép. 0 se **relit**
après coup, il date d'avant la moitié du code. Sur les quatre lignes qui restaient au § 9, **deux**
s'y sont dissoutes.

### 2026-08-07 — épisode 4h : le signal que seul l'invité peut donner

`--state=on` a toujours voulu dire « le processus UML a été lancé ». Le banc a enfin **mesuré**
l'écart que cette phrase recouvre : 0,8 s pour `--state=on`, 5,1 s de plus avant que l'invité ne se
déclare prêt. Tout l'épisode tient dans ce chiffre — sans lui, un script qui enchaîne sur un
`--state=on` parle à une machine qui n'a pas encore de shell.

**Un épisode où la conception était déjà faite.** Les trois arbitrages avaient été rendus la veille
(l'attente vit dans le canal ; la fraîcheur se décide par datation ; le marqueur est écrit par le
scénario, jamais injecté), et il ne restait qu'à choisir un **nom** et un **format**. Le nom s'est
tranché sur un fait de lecture plutôt que sur le goût : le relais invité fait `source` de
`/mnt/hostfs/{<fs>.,marionnet-}relay*` en fin de boot, si bien qu'un marqueur nommé
`marionnet-relay.ready` — le candidat « par symétrie » — aurait été **exécuté comme du bash**. C'est
`marionnet-guest-ready`. Le format ajoute la **première ligne** du fichier à la réponse : coût
marginal nul, et un scénario peut dire « prêt, mais en échec » sans second aller-retour ; le signal,
lui, ne dépend jamais de ce contenu (ligne vide, binaire ou tronquée → `null`).

**Le code n'a coûté qu'un fichier.** `poll_until` et le patron de `cmd_wait` (épisode 4c) se
réutilisent tels quels ; `hostfs_directory_if_any` existait depuis l'ép. 4e ; le créneau GTK ne sert
qu'à retrouver le composant — donc à répondre `unknown_node` s'il est détruit pendant l'attente
plutôt qu'à faire mine d'expirer — et l'observation elle-même est un `stat`, de l'I/O, faite dans le
thread de session. Le seul type neuf est la sonde à quatre cas, écrite pour que **les trois manières
de ne pas être prêt** (jamais démarré, marqueur absent, marqueur périmé) se distinguent dans le
message d'expiration.

**La doc mentait sur un point, et c'est la conception qui l'a découvert.** Le § 4.7 et le § 10
annonçaient un inotify « déjà en place » sur le hostfs, réutilisable pour ce signal. Il porte en
réalité sur le sous-répertoire `.X11-unix` et sur les seuls fichiers du relais X11 : rien à
réutiliser. Rectifié aux deux endroits ; le `stat` n'est donc pas un choix de facilité mais le seul
mécanisme disponible.

**La preuve, et son assertion discriminante.** 29 assertions vertes (`ready-bench.sh`), dont le bout
en bout : scénario posé par `rc-set --from`, machine démarrée par le canal, marqueur écrit par
l'invité et sa ligne rendue **octet à octet** par la réponse. Mais la mesure de l'épisode est
ailleurs : le banc **date le marqueur 60 s en arrière** (`touch -d`, sous le mtime de
`boot_parameters`) et exige alors un **timeout** — c'est exactement ce qu'aurait laissé un run
précédent, obtenu sans rebooter. Sans la comparaison des mtimes, cette assertion passerait au vert à
tort. Puis le même fichier, re-daté au présent, redevient un signal : le critère est bien la
fraîcheur, et rien d'autre. Le premier run avait une assertion rouge, et c'était le **banc** qui se
trompait de nom de champ (`connected` pour `added`) — troisième fois du chantier qu'un banc corrige
sa propre lecture avant de mesurer le code.

### 2026-08-07 — épisode 5a : les quatre treeviews, et les trois familles qu'ils forment

**Ce que l'épisode livre** : `ifconfig`, `defects`, `history`, `documents` en lecture — un verbe par
treeview, **une seule** implémentation (`cmd_treeview`), la forêt servie comme une forêt. 130 lignes
dans `bin/control_server.ml`, **aucun autre fichier de code touché** : `state.ml:612-618` publiait
déjà les quatre instances et `state.ml:620-631` faisait déjà la coercition `(t :> Treeview.t)` qui
rend l'uniformité gratuite. Aucun `.mli`, donc aucun des trois pièges d'ajout de méthode payés à
l'épisode 4e.

**Le découpage de l'épisode 5 vient d'une lecture, pas d'un calendrier.** Le § 4.6 annonçait un
épisode unique — « la partie la plus volumineuse du chantier ». Le scinder en 5a (lecture des
quatre) puis 5b/5c (écritures) tient à ceci : c'est la lecture qui **décide** si les écritures
seront uniformes ou aiguillées quatre fois, et la trancher sous couvert d'un épisode d'écriture
aurait fait payer un aiguillage peut-être inutile. Réponse obtenue : la lecture est uniforme, et
elle publie le vocabulaire (`columns`) sur lequel les écritures viendront se valider — exactement
le rôle qu'a joué `#to_tree` pour `add`/`set`/`connect`.

**Trois faits ont dicté le contrat, contre trois symétries tentantes** (détail au § 4.6) : les
quatre classes mères ne sont pas les mêmes (un `Name` unique pour `ifconfig`/`defects`, non unique
pour `history`, **absent** pour `documents`) ; les hiérarchies sont inégales (2, 3, arbre, plat) ;
et — trouvaille du **premier run** — les quatre n'ont pas la même **population** : `ifconfig` ne
reçoit que les composants adressables, `defects` reçoit tout, câbles compris. Le banc assertait
« autant de racines que de nœuds » : il mesurait une symétrie qui n'existe pas. C'est le banc qui a
été corrigé, et l'assertion refaite **discriminante** — un switch absent d'`ifconfig` *et* présent
dans `defects`, dans le même run.

**Une décision de vocabulaire, prise sur la différence entre deux attributs de colonne.** `_id`,
`_highlight` et `_highlight-color` sont déclarées `~reserved:true` : elles ne sont pas servies.
`_uneditable` est déclarée `~hidden:true` **sans** `~reserved` — et elle est servie, parce qu'elle
dit quelles lignes sont éditables, ce dont l'épisode 5b aura besoin. `hidden` est une décision
d'écran, `reserved` une frontière d'implémentation : un script n'est pas un écran.

**Lire n'a pas eu besoin du widget, mais a gardé le créneau GTK.** `#get_forest` (`treeview.ml:1241`)
lit une `ref` et une `Hashtbl` OCaml — héritage du chantier clos `marionnet-automate-composants`
(les treeviews ne lisent plus le widget). On passe malgré tout par `ask` : les **écritures**, elles,
traversent `#set_complete_forest`, enveloppé dans `GMain_actor.apply_extract` (l.1267), si bien que
lire dans le même créneau est ce qui fait de la réponse **une photo** et non un mélange de deux.

**La preuve** : `treeview-bench.sh` (neuf), **47 assertions vertes, 0 échec**, 0 orphelin ;
`dune build` et `dune test --force` verts. Le bloc discriminant n'est pas la lecture d'un projet
chargé — qui prouverait seulement qu'on sait lire un fichier — mais la suite `set … port_no 5`,
`rename`, `del` **par le canal** : les trois changent immédiatement ce que rend `ifconfig`, ce qui
distingue « lire le treeview » de « lire une copie du treeview ». Deuxième constat du banc, inscrit
au § 4.6 : **aucun** des huit projets d'exemple ne porte d'adresse IPv4 — Marionnet ne peuple seul
que `MAC address` et `MTU`. Asserter des adresses aurait mesuré le contenu des exemples, pas le
canal ; le banc asserte donc les cellules que Marionnet écrit, et **consigne** le zéro pour ce qui
attend l'épisode 5b.

### 2026-08-07 — épisode 5b : écrire une cellule, et la question que le canal ne peut pas poser

**Ce que l'épisode livre** : `ifconfig-set <nœud> <port> <champ> [<valeur>]`, un champ à la fois,
avec `--restart`/`--no-restart` exigés dès que la cible tourne (§ 4.6). C'est l'épisode qui rend le
treeview d'adresses **utile** : jusqu'ici un script savait fabriquer une topologie mais pas la
configuration réseau qui en fait un TP — et aucun projet d'exemple n'en portait.

**Ce n'était pas un *setter*, et c'est la lecture du code qui l'a dit.** `#set_row_field`
(`treeview.ml`) ne valide rien et ne déclenche aucun callback : tout vit dans le chemin GTK
*cell-edited*. Deux étages de validation y sont perdus si on l'appelle nu — le prédicat de
**colonne** (adresse mal formée, MTU au-dessus du MAXPACKET de vde2) et surtout les contraintes de
**ligne**, qui ne sont déductibles d'aucune cellule prise isolément : une valeur posée sur la ligne
du device plutôt que sur un de ses ports, ou le `port0` d'un routeur qui perdrait son adresse de
configuration. Écrire sans les rejouer aurait mis dans un projet ce qu'un humain n'a pas le droit
d'y taper, contre le § 4.10.

**Le verdict s'est séparé de son affichage, pas de sa source.** `#check_constraints` ouvre un
dialogue avant de lever — sans gel depuis l'épisode 3c, mais un refus de ce canal est une ligne
JSON, pas une fenêtre. Plutôt que réécrire les contrôles dans le serveur (la tentation, et la
faute : deux validations divergent le jour où l'une des deux évolue), on a extrait
`#constraints_verdict`, qui rend le verdict sans rien afficher ; `#check_constraints` est devenu
son appelant et la GUI n'a pas bougé d'un octet. Même forme qu'`User_level.check_new_name` à
l'épisode 4d-2c : une source de vérité, deux messages.

**Ce que la GUI met dans un dialogue, le canal le met dans la requête.** Éditer l'ifconfig d'une
machine allumée est **permis** en GUI — vérifié plutôt que supposé (`marionnet.ml:143-176`) — et
déclenche une question modale : « redémarrer maintenant ? ». Le serveur ne peut pas interroger un
humain ; il interroge le script. Tant que le nœud tourne, l'écriture est refusée par
`restart_choice_required` jusqu'à ce que `--restart` ou `--no-restart` tranche, exactement comme
`--save`/`--no-save` à l'épisode 4d. Rien n'est deviné pour le client, rien ne se fait dans son dos.

**Le premier run du banc a trouvé deux défauts, et aucun n'était dans le contrat.** (a) Le canal
offrait `_highlight-color` comme champ écrivable : cette colonne **est** éditable
(`treeview.ml:1825`) et seulement **réservée** — le filtre `is_reserved` de la face lecture n'avait
pas été repris côté écriture. (b) Le nom d'une contrainte de ligne, rendu par `%S`, sortait en
`La premi\195\168re…` : `%S` échappe tout octet ≥ 0x7f, alors que ces noms passent par gettext et
sont donc **traduits**. Corrigé en `%s` entre guillemets, `json_escape` laissant l'UTF-8 passer. La
leçon vaut au-delà : un message destiné à un script ne doit pas traverser `%S` s'il peut être
traduit — et un banc ne doit pas asserter un libellé traduit (l'assertion cherche `rout`, qui
couvre « router » et « routeur »).

**La preuve** : `treeview-bench.sh` étendu (blocs T8 à T11), **80 assertions vertes, 0 échec**,
0 orphelin ; `dune build` et `dune test --force` verts. Le bloc discriminant est **T9** : vider
l'IPv4 du `port0` d'un routeur est refusé alors que la même écriture passe sur `port1` et sur une
machine — un couple qu'aucune validation réécrite dans le serveur ne produirait, puisqu'il vient
d'une contrainte de *ligne* du treeview. Et **T11** ferme la boucle sur ce qui compte vraiment :
`simulation_level.ml:723-742` lit ce treeview à la construction du device, si bien que l'adresse
posée par le canal se retrouve dans le `boot_parameters` du hostfs — mesuré, machine réellement
démarrée.

### 2026-08-07 — épisode 5c : le defect qui s'applique sans rien éteindre

**Ce que l'épisode livre** : `defects-set`, sous deux formes qu'un seul verbe porte —
`<nœud> <port> <direction> <champ>` et `<câble> <direction> <champ>` (§ 4.6). Avec les adresses de
l'épisode 5b, un script sait désormais poser tout ce qui fait la matière d'un TP : qui parle à qui,
et à quel prix.

**La question de l'épisode n'était pas « comment écrire » mais « quand cela s'applique », et elle
se tranchait par lecture, pas par symétrie.** La fiche de reprise disait de mesurer plutôt que de
présumer, et de ne pas reconduire le `--restart`/`--no-restart` de l'épisode 5b par ressemblance
entre treeviews. Bien lui en a pris : `shutdown_or_restart_relevant_device` (`marionnet.ml:154`)
traite les deux natures différemment. Pour un **câble connecté**, la GUI fait `c#suspend; c#resume`
**sans ouvrir le moindre dialogue** — et ce couple n'est pas cosmétique : il détruit le device
simulé et le reconstruit (`cable.ml:820-847`), si bien que l'`initializer` du nouveau
(`cable.ml:981`) relit les defects du treeview et les passe à `wirefilter` sur sa ligne de commande.
Un defect de câble s'applique donc **à chaud**, par recréation du process, sans que rien ne
s'éteigne. Pour un **nœud**, en revanche, c'est le dialogue de l'épisode 5b. Le canal reproduit les
deux : il rebranche le câble d'office et **refuse** `--restart` comme sans objet, il exige le choix
sur un nœud en marche. Généralisation à garder : dans ce chantier, ce n'est pas le risque qui
décide d'une restriction, c'est ce que la GUI **demande** à l'humain.

**Trois choses que `#set_row_field` ne fait pas, et qui ne sont pas optionnelles.** Le chemin GTK
*cell-edited* réaligne la borne sœur quand les deux délais se croisent, rafraîchit la surbrillance,
et avertit au-delà de 1 % de bits retournés. Les écrire une seconde fois dans le serveur, c'était
se garantir deux comportements divergents au premier changement de l'un des deux ; elles sont donc
passées dans `Treeview_defects#edit_side_effects`, qui *fait* les écritures et *rend* ce qu'il y a
à rapporter, sans rien afficher — même forme que `#constraints_verdict` (épisode 5b) et que
`User_level.check_new_name` (épisode 4d-2c). La GUI en tire son dialogue, le canal les champs
`adjusted` et `warning`, et elle n'a pas changé d'un octet. Effet de bord heureux du passage :
vider une cellule de délai levait une exception dans le callback, que `on_edit` rattrape en
journalisant — donc `run_after_update_callback` n'était **pas** appelé, et l'effacement d'un délai
ne redémarrait rien ni ne marquait le projet modifié. Une cellule vide vaut désormais zéro, comme
`is_defective` la lisait déjà.

**Le nom d'une direction de câble n'est pas utilisable, son type l'est.** Sous un nœud, `Name` et
`Type` coïncident (`inward`/`outward`) ; sous un câble, le `Name` d'une direction est
`to m1 (eth0)` — avec des espaces, donc impassable en argument positionnel (§ 4.1), et réécrit
quand une extrémité est renommée. Le modèle lui-même filtre par `Type` (`get_cable_data`) : le
canal fait pareil. C'est aussi ce qui a fixé la forme de la commande — ce n'est pas le nombre
d'arguments qui dit à quoi on s'adresse, c'est le `Type` de la racine visée.

**La preuve, et les trois runs qu'il a fallu.** `treeview-bench.sh` étendu (T12→T15), **138
assertions vertes, 0 échec**, 0 orphelin ; `dune build` et `dune test --force` verts. Les deux
premiers runs ont trouvé trois erreurs, **toutes dans le banc** : (a) `defects-set m1 outward loss 5`
n'est pas une requête à trois arguments mais à quatre, donc un port nommé `outward` — le refus
qu'elle produit est juste, il énumère les ports ; (b) un câble est `connected` **par défaut**
(`cable.ml:743`), réseau éteint compris, donc `reconnected` vaut `true` même quand rien ne tourne :
ce champ dit que le débranchement/rebranchement a été **demandé**, pas que du trafic passait ;
(c) surtout, le banc croyait mesurer un câble en marche alors qu'il avait relié deux switchs par un
câble **droit** — « incorrect », donc jamais démarré (`user_level.ml:345`), pendant que neuf
`wirefilter` (ceux des câbles internes des switchs) donnaient l'illusion du contraire. Corrigé en
`--crossover`, avec l'assertion de polarité **et** un `wait c2 --state=on` : c'est exactement la
leçon (c) de l'épisode 4b — une assertion d'ensemble doit d'abord exiger que ce qu'elle prétend
mesurer existe. Quatrième correction, celle-là utile bien au-delà du bloc : il y a **un répertoire
de session par projet**, et ce banc en ouvre quatre ; le `head -1` hérité ne connaissait que le
premier, si bien que le nettoyage laissait filer les orphelins des trois autres.

**Le bloc discriminant est T15**, et il ne coûte aucun invité : deux switchs et un câble croisé
suffisent à faire tourner un `wirefilter`. Une seconde après le `defects-set`, la perte de 37 %
figure dans la **ligne de commande** du process recréé, où elle était absente avant — mesuré sur
`/proc/<pid>/cmdline`, sans qu'aucun composant n'ait été éteint. C'est la différence entre dire
qu'un defect s'applique à chaud et le montrer.

### 2026-08-08 — épisode 6 : un client qui ne sait rien, et un serveur qui se raconte

**Le canal avait tout, sauf quelqu'un à qui parler.** Trente-six verbes côté serveur, huit bancs
qui les exercent — et, pour dialoguer, la même ligne `printf … | socat -t30 -T30 - UNIX-CONNECT:…
| head -1` recopiée huit fois. L'épisode livre `useful-scripts/marionnet-ctl` (symlink `mrnctl`),
**versionné** parce que c'est un livrable d'utilisateur : piloter un TP par script, pas seulement
mesurer un chantier.

**La décision structurante est une abstention : le client ne connaît aucune grammaire.** Il ignore
que `start` prend un composant et que `connect` en prend trois ; il transmet la ligne, rend la
réponse, et c'est tout. Ce qui aurait pu être une facilité — une fonction Bash par verbe, avec son
aide — aurait recréé une **seconde source de vérité**, celle qui dérive au premier épisode suivant.
C'est le raisonnement qui avait fait abandonner `forest` (ép. 4g), appliqué ici à l'autre bout du
canal. À la place, le serveur se raconte : commande **`help`**, ~35 lignes, qui rend
`arity_of_command` en JSON — verbe, syntaxe, arité, queue libre — dans l'ordre de la table.

**L'assertion qui garde cette propriété (C1) compare deux chemins de code.** La liste servie par
`help` et celle que le dispatch énumère dans le `detail` d'un `unknown_command` doivent être
**identiques** : si `help` recopiait la grammaire au lieu de la lire, cette assertion tomberait la
première. Sa jumelle C2 joue les 35 verbes (tous sauf `quit`) sur un réseau vide et exige
qu'aucun ne réponde `unknown_command` — un verbe publié mais non branché serait une aide qui ment.
Au passage, la factorisation d'`unknown_command_reply` fait que les deux chemins **ne peuvent
plus** diverger.

**Ce que le client apporte de son côté**, puisqu'il n'apporte pas de grammaire : la résolution du
socket (option, puis `$MARIONNET_CONTROL_SOCKET`, puis une erreur qui enseigne — jamais une
découverte automatique) ; quatre codes de retour distincts, chacun provoqué au banc (`0` accepté,
`1` refusé, `2` faute du client, `3` pas de réponse) ; la sortie brute par défaut, `--query` et
`--pretty` en options — ce qui **révise** le `--raw` de la conception, écrit à l'envers ; un mode
lot. Et un gain qu'on n'avait pas prévu : le délai de transport se **cale tout seul** sur le
`--timeout=N` de la requête (N + 10 s), là où les bancs devaient penser à basculer sur `ask_long`.
C8 le mesure en exigeant qu'un `wait --timeout=45` voué à l'échec rende bien un `timeout` **du
serveur**, et non le silence d'un transport coupé trop tôt.

**Une règle du dépôt a été écartée, avec mesure à l'appui.** Tout script Bash neuf doit employer
`bashbricks` ; celui-ci ne le source pas. Sourcer la bibliothèque coûte **~65 ms par invocation**
— pour un client dont le travail utile est un aller-retour de socket, et qu'un banc appelle des
centaines de fois. Le seul JSON qu'il doit lire est le champ `ok`, que `reply_ok`/`reply_error`
placent **toujours en tête** ; un motif ancré suffit, et il est asserté. Le reste est délégué à
`jq`, dépendance **optionnelle** vérifiée au point d'usage.

**Corollaire immédiat : `bench-lib.sh`.** Le préambule des huit bancs — lancement, attente du
socket, `ask`, `expect_*`, nettoyage par répertoire de session, fusible de cardinalité — n'existe
plus qu'en un exemplaire. `ask` y tient en une ligne. `can-bench.sh` a servi de témoin de
l'extraction : cent lignes de moins, et les **seize assertions t0 rigoureusement identiques** à
celles du run joué juste avant conversion (comparaison ligne à ligne, pas « toutes vertes des deux
côtés »). Les sept autres bancs n'ont pas été touchés : ils sont verts, et leur valeur est d'avoir
déjà mesuré.

**Trois erreurs, toutes dans le banc, toutes instructives.** (a) `.commands | length == .count` est
un filtre `jq` faux — après le pipe, `.count` est cherché dans le tableau ; il faut parenthéser.
(b) `ls` **sans projet actif répond `ok:true`** avec une liste vide : ce sont les treeviews (§ 4.6)
qui refusent, pas l'inventaire — le banc voulait provoquer un refus et provoquait un succès. (c) Le
socket du « pair muet », placé sous le répertoire du run, dépassait les **108 octets** de
`sun_path` : `socat` échouait en silence et le client répondait « pas un socket » (code 2) au lieu
du 3 attendu. Le piège de `sun_path`, connu depuis l'ép. 3c pour le socket de Marionnet, vaut pour
**tout** socket auxiliaire d'un banc.

**Un défaut du serveur, découvert par accident et laissé ouvert.** En enchaînant les runs, `open`
d'un vieux projet (`tp9.mar`, six adaptations automatiques) a répondu deux fois sur quatre
`internal` — « the project is flagged as unsaved right after opening » — alors que le chargement
s'était bien passé. Ce n'est **ni le client ni la bibliothèque** : neuf runs isolés, trois avec le
transport `socat` d'origine et six avec `marionnet-ctl`, sont tous verts, et les trois runs de banc
suivants aussi. La garde de `cmd_open` lit `st#project_already_saved` immédiatement après le
chargement, alors que des réacteurs `Cortex.on_commit_append` (`motherboard_builder.ml:153`, sur
les `dotoptions` — persistantes, donc « salissantes ») marquent le projet modifié **de façon
asynchrone**. La garde mesure donc un état instable, et rend un faux négatif sous charge. Consigné
dans `docs/TODO.md` : ce n'est pas un défaut du canal, et le corriger demande de décider *quand* un
projet fraîchement ouvert est propre — une question d'application, pas de protocole.

**Preuve** : `ctl-bench.sh`, **36 assertions vertes, 0 échec**, 0 orphelin ; `can-bench.sh`
converti, 16 assertions identiques au témoin ; `dune build` et `dune test --force` verts.

### 2026-08-08 — épisode 5d : l'épisode que son titre cachait

**Le titre disait « `history` et `documents` en écriture ».** Il avait été écrit à l'épisode 5,
par symétrie avec `ifconfig-set` et `defects-set`, et il portait depuis la mention « si un besoin
apparaît ». Vérification faite avant de coder quoi que ce soit, le patron « écrire une cellule »
ne livrait presque rien ici : `history` n'a **qu'une** colonne éditable — `Comment` — et
`documents` quatre, toutes de métadonnées. Le YAGNI était donc **juste pour l'intitulé**, et c'est
ce qui l'a fait survivre six épisodes.

**Ce que l'intitulé cachait, c'est le menu contextuel.** `treeview_history.ml` en compte neuf
entrées, dont aucune n'avait d'équivalent au canal, et l'une d'elles vaut l'épisode à elle seule :
**« Start in this state »**, qui démarre une machine depuis un **état de disque donné**. C'est le
geste par lequel un enseignant place ses étudiants dans une situation préparée — et c'était le
dernier vrai manque au regard du contrat du § 4.10, « le script a les mêmes possibilités et les
mêmes limites que la GUI ». L'épisode livre donc `history` **par ses actions** :
`history-start`, `history-del [--except]`, et `history-set … comment` pour ne pas laisser un trou
là où la lecture, elle, sert la colonne.

**L'identifiant s'est imposé de lui-même : le fichier COW.** Dans ce treeview un `Name` désigne
autant de lignes que la machine a d'états — c'était déjà écrit au § 4.6 depuis l'ép. 5a, et cela
interdisait le patron `<nœud> <port> …` des deux épisodes précédents. Le fichier COW, lui, est
unique deux fois (par construction, `cow_files.ml:23-35` ; et dans le treeview, ce dont le modèle
dépend déjà dans `get_parent_cow_file_name`), il ne porte aucun espace, et **la lecture le servait
déjà** : `File name` est une colonne `~hidden` mais **non réservée**, et `#get_row` ne filtre que
les réservées. Autrement dit, l'épisode 5a avait publié l'identifiant six épisodes avant qu'on
sache à quoi il servirait. Aucun changement côté lecture n'a été nécessaire.

**Les trois gardes sont celles de la GUI, et cela se vérifie ligne à ligne.** « Start in this
state » n'est proposé que si `can_startup name` (l. 542-547), via un registre que
`marionnet.ml:129-141` remplit avec `node#can_startup` — le prédicat que `can` publie depuis
l'ép. 4b : le canal lit donc la même vérité, sans passer par le registre. Les deux suppressions
sont conditionnées à `number_of_states_with_name > 1` (l. 558-563) : une machine garde toujours un
état. Et l'écriture du commentaire rejoue `#constraints_verdict` avant d'écrire, comme aux ép. 5b
et 5c — même là où le treeview déclare peu de contraintes, parce qu'une colonne qui en gagnerait
une demain ne doit pas trouver un écrivain qui la contourne.

**Le discriminant du banc ne mesure pas un démarrage, il mesure un CHOIX.** Chaque démarrage crée
un état, enfant du plus récent (`user_level.ml:1558` → `add_state_for_device` →
`add_substate_of`). Après un aller-retour, la racine A a donc un enfant B. Si l'on redémarre
normalement, le nouvel état pend sous **B** ; si `history-start A` a réellement sélectionné A, il
pend sous **A**. C'est une différence de *profondeur*, observable dans la forêt que `history`
sert déjà, et qu'aucune écriture du serveur ne produirait sans passer par `#startup_in_state`.
Mesuré : un enfant de la racine avant, deux après. La preuve tangible l'accompagne — l'UML tourne
bien sur ce nouvel enfant, lu dans `/proc/<pid>/cmdline` avec le même garde-fou de session qu'en
T15.

**Un écart au plan, assumé.** Le plan prévoyait de *factoriser* la résolution « fichier COW → ligne »
depuis `get_parent_cow_file_name`. En lisant l'unique appelant de cette méthode
(`user_level.ml:1567`, le choix du COW source à la construction d'un device), il est apparu que la
factorisation changerait sa sémantique : ce qui **levait** sur une ligne introuvable rendrait
désormais `None`, donc un `get_variant_realpath` silencieux au lieu d'une erreur. Économiser
quatre lignes au prix d'un changement de comportement sur un chemin de production est un mauvais
échange : la méthode neuve, `row_id_of_cow_file_name_if_any`, vit **à côté**, écrite sur
`row_ids_such_that` plutôt que sur `unique_complete_row_such_that` — laquelle lève aussi bien pour
« aucune ligne » que pour « plusieurs », alors que le canal doit distinguer « cet état n'existe
pas » d'une incohérence interne.

**Correction au passage, dans le client de l'ép. 6** : le résumé d'erreur affiché sur `stderr`
rendait les échappements JSON tels quels (`no state \"pas-un-cow.cow\"`). « En clair » veut dire
en clair : les `\"` et `\\` sont désormais défaits avant impression.

**Preuve** : `treeview-bench.sh` étendu (T16), **160 assertions vertes, 0 échec** (138 + 22),
0 orphelin ; `dune build` et `dune test --force` verts. Le bloc T16 est passé au premier run.

### 2026-08-08 — épisode 7 : la course que le journal montrait à l'envers

**Le seul défaut connu du chantier restait la garde d'`open`** (fiche de `docs/TODO.md`, ouverte à
l'ép. 6) : ouvrir par le canal un vieux projet répondait *parfois* `internal` — « the project is
flagged as unsaved right after opening » — alors que le chargement avait réussi. Deux échecs sur
quatre runs enchaînés, zéro sur neuf runs isolés : c'est le profil d'une **course**, et la fiche
prévenait qu'un correctif exigeait d'abord un banc qui la **reproduise**.

**Reproduire d'abord : `open-bench.sh`, et deux leviers.** Le premier est l'**alternance de deux
projets**. Un `Cortex.set` ne commite que s'il **change** la valeur (`cortex.ml:281`) : rouvrir dix
fois le même projet ne rejoue donc aucune réaction — mesuré au run de sanité, 2 réactions pour 5
ouvertures. Le régime fautif est celui des bancs de ce chantier, qui ouvrent plusieurs projets par
run. Le second est l'**épinglage sur un seul CPU** (`taskset -c 0`, option `PIN_CPU` du banc) :
avec un seul processeur, le thread de réaction ne s'exécute plus en parallèle du thread de
chargement mais **derrière** lui. Le symptôme passe alors de « parfois » à **7 sur 10**.

**La cause, établie par des piles d'appel, pas par déduction.** Une instrumentation temporaire de
`state#set_project_not_already_saved` (`Printexc.get_callstack`) a montré que, pendant un
chargement, **toutes** les marques « projet modifié » viennent du même endroit :
`motherboard_builder.ml`, la réaction branchée sur les sept options persistantes du sketch, appelée
depuis un thread créé par `cortex.ml:312`. Cortex lance en effet **un thread par commit** pour
exécuter ses callbacks `on_commit`, hors section critique : le chargement restaure les
`dotoptions`, donc commite, donc réagit — et cette réaction peut atterrir *après*
`register_state_after_save_or_open` (`state.ml:551`), qui venait de déclarer le projet propre.

**Leçon durable, payée au passage : l'ordre des lignes du journal ne prouve rien.** La première
version du banc assertait « aucune réaction *postérieure* à la ligne de registration ». Elle
mesurait 2 réactions tardives là où le symptôme frappait 9 fois : incohérence. `Log.printf` prend
un **mutex global** avant d'écrire (`log_builder.ml:132-136`), si bien qu'un thread ayant déjà muté
peut attendre ce mutex pendant qu'un autre mute et écrit — les lignes s'inversent. Une assertion
fondée sur cet ordre mesure l'ordonnancement du **logger**, pas celui du code. Le banc mesure donc
la **cause**, qui est déterministe : pendant une ouverture, une réaction `dotoptions` ne doit plus
exister **du tout**.

**Le correctif retire les callbacks, il ne lève pas un drapeau.** Un drapeau lu par la réaction
serait consulté au moment où le thread s'exécute, c'est-à-dire précisément à l'instant
imprévisible dont on veut se débarrasser. Ce qui supprime la course, c'est de retirer les
callbacks : leur présence est testée par le thread qui commite, sous les mutex
(`cortex.ml:301-307`) — **sans callback, aucun thread n'est créé**. Le mécanisme vit dans la classe
qui possède les cortex (`Sketch.tuning`) et non dans `motherboard_builder`, qui se contente
désormais de **déclarer** sa réaction (`set_persistence_reaction`) au lieu de l'attacher option par
option ; `state#open_project_async` enveloppe la restauration dans
`with_persistence_reaction_suspended`. C'est le jumeau exact de `disable_gui_callbacks`, qui
protège déjà `set_toolbar_widgets` des callbacks GTK : même idée, pour des réactions au lieu de
widgets.

**Ce que cela change de visible** : un projet fraîchement ouvert est « non modifié » de façon
**systématique**, adaptations automatiques comprises. Ce n'est pas une décision nouvelle, c'est
l'intention déjà écrite en `state.ml:551` — que la réaction contredisait au hasard. La garde
d'`open`, elle, n'a **pas** été touchée : `saved` reste ce qui distingue un chargement raté (ouvrir
un fichier texte répond `active:true, nodes:0`), et la piste (a) de la fiche, qui proposait de ne
plus le tester, aurait échangé une intermittence contre un silence.

**Un déclencheur écarté par un témoin désarmé.** Pour vérifier que la suspension est bien
*temporaire*, le banc a d'abord essayé de provoquer un commit par la commande `new` (elle appelle
`dotoptions#reset_defaults`, `state.ml:316`). Zéro réaction. Plutôt que d'en conclure que la
réinstallation était cassée, un run avec la suspension **neutralisée** a tranché : zéro réaction
là aussi. Les deux commits d'une ouverture sont un aller-retour, si bien qu'après le chargement les
options sont déjà revenues à leurs valeurs par défaut. L'assertion mesure donc la suspension
elle-même, que la classe journalise : par ouverture, **une** suspension et **une** réinstallation.

**Piège de fichier** : `raise` explicite est impossible dans `sketch.ml` sans alias `Log` — la
mesure `raise_p4`, appliquée à tout `bin/`, réécrit `raise` en une version qui journalise, d'où un
« Unbound module Log » sans localisation (`File "_none_"`). D'où `Fun.protect ~finally` pour rendre
la réaction quoi qu'il arrive, et l'alias ajouté ensuite pour les deux lignes de journal.

**Preuve** : `open-bench.sh` (neuf, 4 assertions O0…O3), à conditions identiques (K=10, `PIN_CPU=0`,
alternance `tp9.mar`/`tp.mar`) — **avant** : 20 réactions `dotoptions` (10 ouvertures sur 10),
symptôme **7/10**, 3 ouvertures correctes sur 10 ; **après** : **0** réaction, symptôme **0/10**,
10/10 correctes, et 10 suspensions pour 11 installations. Le même banc sans épinglage : 4/4 vertes.
Non-régression : `dune build` et `dune test --force` verts (0 échec), `project-bench.sh` 29/29,
`can-bench.sh t0` 16/16, `treeview-bench.sh` (`E2E=0`) 128/128, 0 échec partout.

**Ce qui reste avant de clore le chantier** : la **documentation utilisateur** du scripting (guides
formels, avec exemples) — décision prise à cet épisode de ne pas clore tant qu'elle n'est pas
tranchée. Le canal, lui, n'a plus de défaut connu ouvert.

---

### 2026-08-09 — épisode 8 : un guide qui ne recopie pas la grammaire

**Livrable** : `doc-src/scripting/README.md` (+ `examples/`, 4 fichiers), versionné, en anglais.
Détail des décisions et de leurs motifs en **§ 5.5** ; on ne les répète pas ici.

**La question posée était « quelle forme, quel périmètre, quelle langue, comment éviter la
dérive » — et c'est la quatrième qui a commandé les trois autres.** Depuis l'ép. 6, le serveur
est la source unique de la grammaire : il la publie par `help`, et le client n'en connaît rien.
Un guide qui aurait recopié la table des verbes aurait rétabli exactement ce que l'ép. 6 avait
supprimé — un second exemplaire, donc celui qui dérive. Le périmètre s'en déduit : le guide dit
la **forme** du canal et les **invariants** (contrat de l'automate, `accepted` ≠ fait, marqueur
d'invité, un champ à la fois, slug de colonne), puis des recettes complètes ; pour « quels
verbes existent », il renvoie à `mrnctl help`. La langue s'en déduit aussi : un document qui ne
porte pas la grammaire peut être traduit plus tard sans créer de seconde vérité, donc on a écrit
d'abord dans la langue du dépôt et du vocabulaire documenté.

**La forme retenue est du Markdown, pas du texinfo.** `doc-src/` est le dossier des sources de
documentation, mais son unique occupant vise le développeur, date de 2008 et n'a pas bougé depuis
2012 ; sa chaîne (`texi2dvi`/`makeinfo` → `doc/`) n'est pas branchée sur `dune install`. On
n'allait pas remonter une chaîne de build pour un document que le dépôt et la forge rendent déjà
lisible tel quel — et qui reste installable le jour où on le décidera.

**L'anti-dérive n'est pas une intention, c'est un banc.** Les exemples sont des scripts
exécutables versionnés (`01-build-a-lab.sh`, `02-run-and-collect.sh`, `scenario-ping.sh` côté
invité, `lab.mrn` en mode lot), et `doc-bench.sh` les lance **tels quels** contre une session
réelle. Le premier run l'a immédiatement justifié : **six affirmations fausses**, toutes écrites
de bonne foi après lecture du source, toutes attrapées à l'exécution — le `port0` d'un switch qui
numérote à partir de `port1` ; l'en-tête GUI `"IPv4 address"` là où l'écriture veut le slug
`ipv4-address` (refusé en `unknown_field`) ; un `"accepted":"start"` inventé là où la réponse est
`{"component","action","accepted":true,"beyond_gui":false}` ; un `can` supposé rendre un objet de
booléens quand il rend une **liste** d'actions autorisées ; une racine `roots` là où le treeview
sert `rows` de `{"fields","children"}` ; et un chemin non-socket annoncé en code 3 quand le client
sort en **2**, le 3 étant réservé au socket qui existe et ne répond pas. Relire ne les aurait pas
trouvées : c'est le mode de défaillance propre à la documentation d'API, et la seule parade est
de l'exécuter.

**Preuve** : `doc-bench.sh`, **39 assertions, 0 échec**, `dune build` vert. Y compris le bout en
bout invité — `rc-set` d'un scénario, `start`, `wait --ready` qui rend `ready` comme première
ligne du marqueur, et les **11 lignes** que l'invité a écrites dans `/mnt/hostfs/lab.log`, relues
côté hôte par le chemin que `rc-get` publie. Les 4 codes de retour du client sont provoqués
séparément, dont le « socket muet » par un `socat` qui écoute et n'a rien à dire.

**Écart au périmètre, assumé** : ni le guide ni `marionnet-ctl` ne sont ajoutés à `dune install`.
Les deux forment un seul épisode d'installation cohérent, qui appartient au chantier
`modernisation-installation-marionnet` — la frontière que l'ép. 6 avait déjà refusé de franchir.

**État du chantier** : le § 9 est soldé, aucun défaut connu n'est ouvert, et la condition posée à
la clôture est levée. Le chantier peut être clos (MODE C) sur décision de l'auteur.

---

### 2026-08-09 — épisode 9 : un vérificateur qui ne connaît toujours pas la grammaire

**Livrable** : `useful-scripts/mrn-check`, versionné, + § 12 du guide utilisateur. Décisions et
motifs en **§ 5.6** ; on ne les répète pas ici.

**Le besoin vient d'une propriété qu'on avait documentée sans en tirer les conséquences** : le
mode lot **n'a pas de transaction** (§ 5.2). Un `.mrn` envoyé à l'aveugle fait découvrir la faute
de sa 5ᵉ ligne quand les quatre premières ont déjà modifié le projet — et l'ép. 8 venait d'en
donner l'exemple parfait, un `s1:port0` sur un switch qui numérote à partir de `port1`. Le
vérificateur lit le fichier et n'envoie rien.

**Trois questions ont été posées avant d'écrire, et les trois réponses tiennent en une règle.**
La grammaire n'est **pas** écrite dans le vérificateur : il la demande au serveur, exactement
comme le client de l'ép. 6, et `--grammar=FICHIER` permet de valider hors ligne contre un
instantané explicitement désigné comme **cache**. C'est la troisième application de la règle
d'unicité (ép. 4g pour `forest`, ép. 6 pour le client) : deux copies d'une grammaire, c'est une
copie qui dérive. Corollaire de forme : un **script autonome** plutôt qu'un `-n` sur
`marionnet-ctl`, pour ne pas donner au client la compréhension de ce qu'il transmet — c'est
précisément ce qu'il n'a pas.

**Le contrôle utile n'est pourtant pas dans la grammaire.** L'arité attrape un verbe mal tapé ;
elle ne dira jamais qu'un câble se branche sur un port qui n'existe pas. D'où le second étage :
le fichier est **rejoué contre un modèle construit à partir de lui-même** — noms déclarés et
encore libres, composant référencé sans `add`, nom de port, borne du `--ports=`, port déjà pris.
Avec une limite explicite, qui est ce qui empêche l'outil de mentir : **le modèle n'est cru que
quand le fichier le construit à partir de rien**. Après un `open`, ou sans commande de projet, on
ne voit pas le décor : les contrôles d'existence s'éteignent et une `note` le dit. Un linter qui
invente des erreurs se fait désactiver la semaine suivante.

**Une seule connaissance du modèle est recopiée, et elle est bornée** : la table
`kind → (préfixe, offset)` des noms de ports, avec les `fichier:ligne` qui la déclarent. Elle
n'est pas publiée par `help`, et c'est elle qui attrape la faute-témoin. Les **nombres de ports
par défaut**, eux, ne sont pas recopiés : sans `--ports=` explicite, la borne n'est pas
contrôlée. Moins de couverture contre zéro valeur à resynchroniser — le même arbitrage qu'ailleurs
dans ce chantier.

**Pas de `bashbricks`, pour une raison vérifiable cette fois** : `mrn-check` est destiné à
`$(PREFIX)/bin` et rien n'installe `bashbricks` (aucune mention dans `Makefile`, `Makefile.d/`,
ni dans une stanza `(install)`) — un `source` relatif marcherait dans l'arbre des sources et
casserait une fois installé. `jq` est en revanche une dépendance **dure** ici : l'outil lit un
JSON de grammaire, il n'est pas sur un chemin chaud, et deux chemins de lecture vaudraient moins
qu'un message clair.

**Preuve** : `check-bench.sh`, **32 assertions, 0 échec**. Le discriminant est **K4** — sur un
fichier fautif, la première ligne signalée par `mrn-check` doit être **celle où `mrnctl -f`
s'arrête réellement** : mesuré ligne 6 des deux côtés, même motif
(`node "s1" has no port "port0"`), avec le témoin (fichier valide) accepté par les deux. Sans
cette assertion, le banc n'aurait mesuré que la cohérence du vérificateur avec lui-même. Le reste
couvre le mode hors ligne **Marionnet arrêté**, sept classes d'erreur une par fichier, et les
trois codes de retour.

**Deux défauts trouvés au premier run**, tous deux dans le vérificateur : `-` (lire l'entrée
standard) était rejeté comme option inconnue, et le message d'échec « le serveur n'a rien publié »
n'enseignait pas l'option hors ligne. Corrigés, run suivant vert.
