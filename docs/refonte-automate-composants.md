# Chantier `marionnet-automate-composants` — refonte de l'automate d'état des composants

**Objectif** : faire porter par le **type** l'invariant qui relie l'état d'un composant à son
objet de simulation, aujourd'hui seulement reconstruit dans huit filtrages de couple — puis
corriger les incohérences que cette absence a laissé s'installer entre l'automate,
`Marionnet.st` et les treeviews.

Reprise du chantier : appliquer le skill `chantier-long`.
Historique : `git log --grep="marionnet-automate-composants"`.
Fiche mémoire : `marionnet-automate-composants`.

Le document se lit en trois temps : **§ 1-2** = l'audit fondateur (constats datés, immuables sauf
si le code les périme) ; **§ 3** = la conception retenue ; **§ 5** = le journal d'avancement.

---

## 0. Objet et méthode de l'audit

*Audit mené le 2026-07-29, en lecture seule : aucun code n'a été modifié pour le produire.
Les références `fichier:ligne` valent pour l'arbre au commit `8dcef55`.*

`bin/user_level.ml:79` définit l'automate d'état d'un composant :

```ocaml
type simulated_device_automaton_state =
   NoDevice | DeviceOff | DeviceOn | DeviceSleeping
```

Il est porté par la classe virtuelle `['parent] simulated_device` (`user_level.ml:104-442`),
dont héritent **tous** les composants — nœuds (`node_with_ports_card`, `user_level.ml:635`) comme
câbles (`cable.ml`). Cet état doit rester cohérent avec trois autres vues :

| Vue | Support | Point d'entrée |
|---|---|---|
| processus réels | `simulated_device : 'parent Simulation_level.device option ref` (`user_level.ml:148`), avec son **propre** automate `Off \| On \| Sleeping \| Destroyed` (`simulation_level.ml:1372`) | `d#startup`, `d#suspend`, … (`simulation_level.ml:1412-1451`) |
| état global | `Marionnet.st` = `new State.globalState ()` | `get_nodes_that_can_*` (sensibilité des menus), `project_already_saved`, séquence de quit |
| treeviews | `st#treeview` (ifconfig, defects, history, documents) | `Treeview_history.Startup_functions` (`marionnet.ml:107-118`), `after_user_edit_callback` (`marionnet.ml:132-159`) |

**Périmètre audité** : toutes les méthodes atteignables par une action utilisateur qui modifient
l'état d'un ou plusieurs composants. Elles se répartissent en deux étages :

- **méthodes GUI** — `startup`, `suspend`, `resume`, `gracefully_shutdown`, `gracefully_restart`,
  `poweroff` (`user_level.ml:207-235`), `create`/`destroy_my_simulated_device`
  (`:198-205`). Elles positionnent `next_automaton_state`, puis **enfilent** un thunk dans
  `Task_runner.the_task_runner` ;
- **transitions réelles** — les `*_right_now`, exécutées dans le thread du *task runner*, sous
  `Recursive_mutex`, qui filtrent sur le **couple** `(!automaton_state, !simulated_device)`.

S'y ajoutent trois producteurs de transitions **hors** action utilisateur directe :
`destroy_because_of_unexpected_death` (mort inopinée d'un processus, `user_level.ml:259`), le
compteur de références des câbles (`cable.ml:792-820`) et les callbacks `mrproper`
(`OoExtra.destroy_methods`, `lib/EXTRA/ooExtra.ml:19-32`) déclenchés par `#destroy`.

Un vestige signale que la question a déjà été posée : `marionnet.ml:213-214` conserve en
commentaire un rafraîchisseur périodique `st#state_coherence ()` dont la méthode n'existe plus
nulle part.

---

## 1. Bugs

### B1 — `gracefully_restart` : la garde ne protège que sa première instruction

`user_level.ml:223-231` :

```ocaml
method gracefully_restart =
  if not self#can_gracefully_shutdown then () else (* continue *)
  self#gracefully_shutdown;
  self#set_next_simulated_device_state (Some DeviceOn);
  self#enqueue_task_with_progress_bar (s_ "Restarting") (fun () -> …)
```

Le `;` ayant une précédence plus faible que `if/then/else`, le corps se lit
`(if … then () else self#gracefully_shutdown); …`. La tâche « Restarting » est donc enfilée
**dans tous les cas** : sur un composant déjà éteint, « redémarrer » le *démarre*.

Le défaut est aujourd'hui **latent** : le seul appelant, `shutdown_or_restart_relevant_device`
(`marionnet.ml:146`), filtre déjà sur `can_gracefully_shutdown` en amont. Mais la garde locale
prouve l'intention, et la protection disparaît au premier autre appelant.

*Correctif* : encadrer la suite par `begin … end` — idiome déjà employé ailleurs dans la base
(`state.ml:328-349`).

### B2 — Cinq chemins laissent `next_automaton_state` figé sur une transition fantôme

`set_next_simulated_device_state` est posé **avant** l'évaluation de la garde `can_*`, laquelle
n'a lieu qu'au moment où le *task runner* dépile le thunk. Or la remise à `None` n'existe que dans
les branches **abouties**. Restent sans remise à zéro :

| Chemin | Ancrage |
|---|---|
| `startup_right_now` sur un `DeviceOn` (« nothing to do ») | `user_level.ml:335-336` |
| `gracefully_shutdown_right_now` sur `NoDevice`/`DeviceOff` | `user_level.ml:383-384` |
| `poweroff_right_now` sur `NoDevice`/`DeviceOff` | `user_level.ml:402-403` |
| refus de démarrer un composant `is_correct = false` (câble de mauvais croisement) | `user_level.ml:339-340` |
| toute levée de `ForbiddenTransition` rattrapée par le `try` du thunk | `user_level.ml:177-188` |

À quoi s'ajoute le cas où la garde `can_*` de la méthode GUI est fausse à l'exécution du thunk :
`startup` (`:209`) etc. n'appellent alors *rien*, et l'état « en transition » persiste.

Sans effet visible aujourd'hui — cf. B3 — mais bloquant dès qu'on lira ce champ.

### B3 — `next_automaton_state` est du code mort

Le champ est **écrit 14 fois** et **jamais lu** : `grep` sur `next_simulated_device_state`
(le getter) ne remonte, hors `user_level.ml`, que des déclarations d'interface
(`user_level.mli:59,220,334,441,600`, `machine.mli:136`). Trois conséquences :

1. L'« icône d'état transitoire » annoncée par le commentaire `user_level.ml:142`
   (« *show our transient simulation state icon* ») **n'a jamais existé** :
   `string_of_simulated_device_state` (`:122`), seule source du suffixe d'icône consommé par les
   huit `dotImg` (`machine.ml:634`, `hub.ml:324`, `switch.ml:416`, `router.ml:1089`,
   `cloud.ml:280`, `world_bridge.ml:302`, `world_gateway.ml:397`), ne lit que `automaton_state`.
2. L'**unique effet** de `set_next_simulated_device_state` est le `Sketch.refresh_sketch ()`
   de sa ligne `:142` — lequel a une portée bien plus large que le dessin (cf. B4).
3. Sa valeur initiale `Some NoDevice` (`:135`) **contredit l'invariant documenté** trois lignes
   plus haut (« *If no transition is occurring then the ref should hold None* ») : tout composant
   fraîchement construit est réputé « en transition ».

### B4 — Le drapeau « projet modifié » est un compteur de rendu

Chaîne complète :

- `Sketch.refresh_sketch` est un *thunk* installé sur `st#refresh_sketch` (`marionnet.ml:74`,
  `sketch.ml:34-38`) ;
- `st#refresh_sketch` incrémente `refresh_sketch_counter` (`state.ml:839-840`) ;
- `project_already_saved` compare ce compteur à la valeur qu'il avait au dernier enregistrement
  (`state.ml:641-647`) ; le test « coûteux » sur les forêts de treeviews n'est atteint que si les
  compteurs sont **égaux**.

Or `Sketch.refresh_sketch ()` est appelé par `set_next_simulated_device_state`
(`user_level.ml:142`, donc à *chaque* transition et à chaque complétion) et par
`connect_right_now`/`disconnect_right_now` des câbles (`cable.ml:742`, `:764`).

**Conséquence** : démarrer, arrêter, suspendre, connecter ou déconnecter un composant marque le
projet comme non sauvegardé, alors qu'aucune donnée persistée n'a changé. Effet utilisateur : sur
un projet fraîchement ouvert, « Démarrer tout » puis « Arrêter tout » suffit à faire apparaître la
question « Voulez-vous sauvegarder le projet avant de quitter ? » (`gui_menubar_MARIONNET.ml:346`)
— et la branche `true, true` de `:359-363` enchaîne alors un `save_project` inutile.

Le compteur conflate deux notions distinctes : *« le dessin doit être re-rendu »* et *« le modèle
persistant a changé »*. Les états des composants relèvent de la première et jamais de la seconde.

> **Seconde cause, découverte à l'épisode 4 en jouant le scénario** (l'audit ne l'avait pas vue, et
> elle invalide en partie la phrase ci-dessus) : **démarrer une machine ajoute un état de disque
> dans le treeview *history*** (`Treeview_history#add_substate_of`, appelé par
> `create_cow_file_name_and_thunk_to_get_the_source`, `user_level.ml:1402`). Le second test de
> `project_already_saved` — la comparaison des forêts de treeviews — le détecte, à juste titre :
> un nouveau fichier COW est référencé, le modèle persistant **a** changé. Preuve (journal 48) :
> `next fresh identifier restored to 2` à l'ouverture, puis au reset
> `[states-forest] removing row 1 ("m2") together with [3:"m2"]` — l'identifiant 3 est né pendant
> la session.
>
> Conséquence : R3 supprime le **faux** positif (le compteur de rendu) mais **le symptôme de B4
> subsiste** dès qu'une machine a démarré, cette fois pour une raison défendable. Décider si un
> nouvel état de disque doit compter comme « projet modifié » est un **arbitrage de l'auteur**, pas
> une suite mécanique de ce chantier. Le symptôme est en revanche bien supprimé pour tous les
> composants sans historique (hubs, switchs, câbles) et pour suspendre/reprendre.

### B5 — Câbles : menus non filtrés sur l'état, et remplacement non séquencé (risque)

Deux écarts cumulés, à traiter ensemble :

- **Filtrage** : les nœuds n'offrent « Modifier »/« Supprimer » que sur les composants arrêtés
  (`dynlist = get_node_names_that_can_startup`, `machine.ml:167`, `hub.ml:84`, `switch.ml:115`,
  `router.ml:490`, `cloud.ml:88`, `world_bridge.ml:93`, `world_gateway.ml:117`). Les câbles, eux,
  listent **tous** leurs exemplaires (`cable.ml:114-116`), y compris connectés et actifs. L'écart
  est masqué par `cable.ml:876-878`, qui force `can_startup`, `can_gracefully_shutdown` et
  `can_poweroff` à `true` — trois surcharges portant chacune le commentaire
  « *To do: try reverting this* ».
- **Séquencement** : `Properties.reaction` (`cable.ml:143-149`) fait `c#destroy; Add.reaction r`.
  Or `#destroy` ne fait qu'**enfiler** la destruction du device simulé
  (`user_level.ml:202-205` → `Task_runner#schedule`), tandis que le nouveau câble est construit
  *immédiatement*, dans le même `st#network_change`. Son `initializer` (`cable.ml:891-894`)
  incrémente aussitôt son compteur de références et peut démarrer un second processus
  `Simulation_level.ethernet_cable` sur les **mêmes hublets** que l'ancien, pas encore détruit.

Le second point est signalé comme **risque non reproduit** : la fenêtre existe par construction,
mais aucun symptôme n'a été observé ni recherché ici. Le commentaire `cable.ml:146-147`
(« *it's important that it's initialized anew, to get the reference counter right* ») montre que
l'ordonnancement avait déjà retenu l'attention de l'auteur.

---

### B6 — Le treeview *defects* diverge du modèle réseau, et l'échec est déclaré « réussi »

**Constaté en exécution réelle** les 2026-07-29 (deux sessions GUI, journaux
`/tmp/marionnet.native.42.log` et `.43.log`), en marge de la fumée du chantier
`marionnet-pilotage-par-script` — d'où le rattachement ici : la pile ne traverse aucun code
réseau, c'est bien une incohérence composant ↔ treeview.

**Deux symptômes, une même racine.**

| Session | Geste | Exception | Site |
|---|---|---|---|
| 42 | supprimer un hub + ses câbles, ajouter un switch, recâbler, « tout démarrer » | `Not_found` (`List.find`) | `treeview_defects.ml:230` (`get_port_data`), via `simulation_level.ml:710` |
| 43 | créer un câble `d3`, le supprimer aussitôt, « tout démarrer » | `Assertion failed` — `List.length filtered_cable_directions = 1` | `treeview_defects.ml:242` (`get_cable_data`) pour le câble **`d2`**, que l'utilisateur n'avait pas touché |

Autrement dit : la suppression d'un composant abîme l'entrée d'un **autre** composant, et la
lecture ultérieure des défauts échoue au moment où `make_ethernet_cable_process` compose la ligne
de commande du `wirefilter`.

**Mécanismes identifiés dans le code (établis) :**

1. **`Treeview.remove_subtree_by_name` avale toute exception** (`treeview.ml:1714-1718` :
   `try … with _ -> ()`). Sa première instruction utile, `remove_subtree`, commence par
   `id_to_iter row_id` (`:1408`), qui **échoue** dès que le modèle GTK a divergé de la forêt
   interne — et le journal montre cette divergence en cascade
   (`WARNING: unknown column … (Failure("id_to_iter: id 32 not found"))`). Résultat : la
   destruction est **intégralement sautée**, sans un mot. Preuve directe dans le journal 42 :
   `component "d1": destroying my defects.` puis, à la recréation du câble homonyme,
   `The cable d1 has already defects defined...` (`user_level.ml:746`) — donc `add_my_defects`
   trouve encore l'entrée censée être détruite, et **ne la recrée pas**. Le nouveau câble hérite
   de l'entrée du précédent.
2. **L'exception est ensuite avalée par le `task_runner`**, qui journalise
   `Warning (q): "Startup m1" raised an exception (…)` **puis** `The task "Startup m1" succeeded.`
   Le composant reste éteint alors que la tâche est déclarée réussie — même famille que C5, mais
   sur le chemin de **démarrage**, pas de destruction. Symptôme visible pour l'utilisateur :
   recliquer « tout démarrer » suffit, le composant démarre alors normalement (le chemin fautif
   n'est plus emprunté puisque l'objet existe déjà).
3. **Entrelacement thread GTK / task_runner** (journal 42) : la destruction *logique* des defects
   se fait sur le thread GTK (`.0`) tandis que la destruction du device simulé est exécutée en
   tâche de fond (`.8`). L'utilisateur a créé le switch **pendant** que les hublets du hub étaient
   encore en cours de terminaison. Aucun verrou ne protège le treeview de ce chevauchement.

**Non établi, à instrumenter avant tout correctif** : le pas exact par lequel les lignes de
direction du câble `d2` deviennent en nombre ≠ 1 (0 ou 2 ?). L'état sauvegardé
(`abc/states/defects`, extrait du `.mar` postérieur au bug) ne permet pas de trancher : la
sérialisation OCaml **partage les chaînes identiques**, si bien que l'absence de `leftward` /
`rightward` après `d2` dans le dump n'est pas une preuve d'absence de lignes. Le moyen honnête est
de journaliser, dans `get_cable_data`, la longueur réellement trouvée et les noms des enfants,
puis de rejouer le geste minimal de la session 43 (créer un câble, le supprimer, démarrer).

**Direction de correction** (à trancher au moment de R2/R3, pas avant le diagnostic ci-dessus) :

- faire **échouer bruyamment** `remove_subtree_by_name` (journaliser l'exception au lieu de
  `with _ -> ()`) — c'est le seul changement qui rendrait le défaut visible plutôt que latent ;
- ne plus laisser `add_my_defects` conclure de l'existence d'une ligne homonyme que l'entrée est
  **valide** : vérifier aussi sa structure (nombre de ports, deux directions par port) ;
- traiter la question du **thread** : le treeview est manipulé depuis GTK *et* depuis le
  task_runner, sans discipline explicite (à rapprocher de C4).

> **Élargissement, épisode 4 : ce n'est pas un défaut de `treeview_defects.ml`, mais du socle
> `Treeview`.** Le journal 48 (projet neuf, propre, jamais victime des gestes de la session 43)
> montre le **même** motif sur le treeview *history* :
>
> ```
> Warning (q): "Startup m1" raised an exception (Failure("id_to_iter: id 0 not found"))
>   Treeview.id_to_path (treeview.ml:1498) → Treeview.collapse_row (:1532)
>   → Treeview_history#add_substate_of (treeview_history.ml:234)
> task_runner: The task "Startup m1" succeeded.
> ```
>
> Même divergence entre le modèle GTK et la forêt interne, même tâche déclarée « réussie » après
> avoir levé — et, cette fois, **la machine m1 n'a tout simplement pas démarré**, en silence, sur
> un projet sain. Deux conséquences : le périmètre de B6 est le socle (`treeview.ml`), donc les
> quatre treeviews ; et un scénario de reproduction plus simple que celui cherché à l'épisode 2
> existe peut-être (démarrer deux machines d'un projet fraîchement ouvert).

---

## 2. Incohérences de conception

### C1 — Deux automates parallèles, aux alphabets différents

| | `User_level` | `Simulation_level` |
|---|---|---|
| états | `NoDevice`, `DeviceOff`, `DeviceOn`, `DeviceSleeping` | `Off`, `On`, `Sleeping`, `Destroyed` |
| « pas encore créé » | `NoDevice` | *absent* (l'objet naît en `Off`, `simulation_level.ml:1372`) |
| état terminal | *absent* | `Destroyed` (`:1450`) |
| transition interdite | `raise ForbiddenTransition` (`user_level.ml:93-97`) | `failwith "can't startup a non-off device"` (`:1415`) |

Les deux automates sont synchronisés **à la main**, chaque `*_right_now` de `user_level`
appelant la méthode homonyme de `simulation_level` puis affectant son propre `ref`. Rien
n'empêche une divergence : si `d#startup` lève après avoir muté `state`, le niveau utilisateur ne
sera pas mis à jour.

### C2 — « Arrêté » n'a pas le même sens selon la nature du composant

Machines et routeurs enchaînent un `destroy_right_now` après l'arrêt, afin de repartir d'un
nouveau fichier COW (`machine.ml:715-747`, `router.ml:1169-1196`) : ils finissent en **`NoDevice`**.
Hubs, switchs, clouds et *world\_\** restent en **`DeviceOff`**, hublets vivants.

Deux états distincts recouvrent donc la même notion utilisateur (« éteint »), ce que trahit la
branche d'excuse de `string_of_simulated_device_state` :

```ocaml
| _ -> "off" (* Sometimes the sketch is builded in this state, so... *)
```
(`user_level.ml:126`)

Ce n'est pas un bug — le comportement est délibéré — mais le type ne le dit pas, et le
commentaire montre que le lecteur suivant s'y perd.

### C3 — L'invariant central n'est pas typé

L'invariant réel est :

> `automaton_state = NoDevice` **⟺** `!simulated_device = None`
> et, dans les trois autres états, `!simulated_device = Some d`.

Il n'existe nulle part comme tel : il est **reconstruit** dans huit filtrages du couple
`(!automaton_state, !simulated_device)` (`user_level.ml:244`, `276`, `320`, `347`, `358`, `373`,
`392`, plus les surcharges de `cable.ml`), chacun se terminant par un `| _ ->
raise_forbidden_transition "<nom de méthode>"` fourre-tout — sept sites au total. Ces branches
mélangent deux natures d'erreur : la transition *légitimement* interdite (démarrer un composant
déjà démarré) et l'état *structurellement* impossible (`DeviceOn` avec `None`). Le typeur ne peut
distinguer les deux.

### C4 — Discipline de verrou asymétrique

Toutes les écritures et tous les prédicats `can_*` prennent `Recursive_mutex`
(`user_level.ml:112`), mais les deux lecteurs `simulated_device_state` (`:118`) et
`string_of_simulated_device_state` (`:122`) lisent hors verrou. Sous *systhreads* la lecture d'un
`ref` est atomique : ce n'est **pas** une course de données, seulement une discipline non
uniforme. À noter toutefois que le projet tourne désormais sur OCaml 5.4.1
(cf. `docs/migration-ocaml5.md`) : l'écart deviendrait significatif si un jour un domaine
secondaire lisait ces états.

### C5 — Échecs silencieux sur les chemins de destruction

`network#reset` (`user_level.ml:1587-1593`) et `destroy_process_before_quitting` (`:1611-1617`)
avalent **toute** exception (`try … with _ -> ()`), puis vident la liste des nœuds et des câbles.
Un composant qui échoue à mourir laisse ses processus orphelins et disparaît du modèle sans
laisser de trace — ni log, ni compteur, ni avertissement.

Le même motif se retrouve **hors** de `user_level.ml`, et il n'y est pas théorique :
`Treeview.remove_subtree_by_name` (`treeview.ml:1714-1718`) avale lui aussi toute exception, ce
qui fait passer une destruction entièrement sautée pour une destruction réussie — c'est le
mécanisme n° 1 de **B6**, constaté en exécution. Et sur le chemin symétrique, le `task_runner`
déclare « succeeded » une tâche dont le corps a levé.

À rapprocher du chantier `bug-critique-crash-host` (`docs/bug-critique-crash-host.md`), dont
la cause candidate C1 concerne précisément les terminaisons de composants.

---

## 3. Conception retenue

**Décision du 2026-07-29** : les quatre recommandations sont retenues, **R2 comprise** — c'est
elle qui motive l'ouverture de ce chantier. Ordre d'exécution ci-dessous (rapport bénéfice /
risque décroissant), R2 en dernier parce qu'elle suppose les autres faites : R4 retire les bugs
qui brouilleraient la lecture d'une régression, R1 supprime un champ qu'il serait absurde de
porter dans le nouveau type, R3 découple la persistance du rendu avant qu'on ne déplace les
points de rafraîchissement.

### R4 — Correctifs ponctuels *(à faire en premier : faible risque)*

1. `begin … end` dans `gracefully_restart` (**B1**).
2. Aligner les `dynlist` des câbles sur celles des nœuds, ou documenter l'écart en commentaire ;
   dans les deux cas, ordonner `Properties.reaction` pour que la destruction précède réellement
   la re-création (**B5**).
3. Journaliser au lieu d'avaler dans `network#reset` et `destroy_process_before_quitting`
   (**C5**) — au minimum un `Log.printf` avec `Printexc.to_string`.
4. Supprimer le commentaire mort `marionnet.ml:213-214` (`st#state_coherence`).

Le `Thread.delay 7.` de `gracefully_restart` (`user_level.ml:230`, commenté « *Ugly* ») bloque la
file séquentielle du *task runner* pendant sept secondes. Il n'est pas traité ici : sa suppression
demande de comprendre quelle course il masque, ce qui relève d'un épisode de débogage à part
entière.

### R1 — Supprimer `next_automaton_state`

Retirer le champ (`user_level.ml:135`), les deux méthodes (`:137-142`), les quatorze appels, et
les déclarations correspondantes de `user_level.mli` et `machine.mli`. Remplacer par un
`Sketch.refresh_sketch ()` **explicite en fin de chaque `*_right_now` abouti** : le
rafraîchissement reste nécessaire (les icônes on/off dépendent de `automaton_state`), mais il
devient lisible et cesse d'être un effet de bord d'un champ inutilisé.

**B2** et **B3** disparaissent alors sans correctif dédié. Gain net : une trentaine de lignes en
moins, et un champ d'état de moins à maintenir cohérent.

*Alternative écartée* : câbler enfin le champ pour afficher une icône « en cours de
démarrage/arrêt ». Ce serait une fonctionnalité GUI nouvelle, qui imposerait d'abord de corriger
les cinq fuites de B2 puis de gérer les états transitoires dans les huit `dotImg`. Hors périmètre
d'un travail de mise en cohérence.

### R3 — Séparer rendu et persistance

Introduire dans `State.globalState` un second compteur, distinct de `refresh_sketch_counter` :

- `refresh_sketch_counter` — inchangé, incrémenté par tout ce qui doit re-rendre le dessin
  (y compris les transitions d'état) ;
- `model_revision_counter` — incrémenté **uniquement** par `network_change` (`state.ml:843-851`)
  et par les éditions de treeview ;
- `project_already_saved` (`state.ml:641`) lit le **second**.

Corrige **B4**. Périmètre : `state.ml` seul, plus l'ajout de l'incrément dans `network_change`.

> **Rectifié à l'épisode 4, sur deux points** (la recette ci-dessus est conservée telle qu'elle
> avait été arbitrée, pour que le journal reste lisible) :
>
> 1. **Un second *compteur* est inutile** : personne n'en lirait la valeur, seul compte le test
>    « identique à la valeur du dernier enregistrement ». Un **drapeau booléen** `project_dirty`
>    fait strictement la même chose, et la méthode `set_project_not_already_saved` — qui existe
>    déjà et que les treeviews appellent déjà (`marionnet.ml:101`, `:195`) — en devient le point
>    d'entrée unique, en portant enfin son nom.
> 2. **Les *dotoptions* manquaient à la liste des sources**, et c'était une perte de données :
>    `iconsize`, `rankdir`, `curved_lines`, `nodesep`, `labeldistance`, `shuffler` et `extrasize`
>    sont **persistées** (`dotoptions.marshal`, écrite par `save_project` `state.ml:721`, relue à
>    l'ouverture `:472`). Les incrémenter « uniquement par `network_change` et les treeviews »
>    aurait laissé une modification de la barre d'outils disparaître en silence à la fermeture.

### R2 — Module `User_level.Simulated_device`, avec état porteur du device

**Cœur du chantier.** C'est la proposition de fond ; elle dépasse le cadre d'un correctif et
occupera plusieurs épisodes à elle seule.

```ocaml
module Simulated_device : sig

  (** État de l'automate d'un composant. L'invariant « pas d'état actif sans objet de
      simulation, pas d'objet de simulation sans état actif » est porté par le type. *)
  type 'parent state =
    | No_device
    | Off      of 'parent Simulation_level.device
    | On       of 'parent Simulation_level.device
    | Sleeping of 'parent Simulation_level.device

  val to_string   : 'a state -> string   (* "No_device" | "Off" | … — pour les logs *)
  val icon_suffix : 'a state -> string   (* "off" | "on" | "pause" — pour dotImg *)
  val device_opt  : 'a state -> 'a Simulation_level.device option

end
```

Ce que la fusion apporte :

- l'invariant de **C3** devient indéformable : `DeviceOn` sans device n'est plus *représentable* ;
- les huit filtrages de couple deviennent des filtrages simples et **exhaustifs** — le compilateur
  signale toute branche oubliée ;
- les sept `raise_forbidden_transition` fourre-tout disparaissent ; ne subsistent que les
  transitions réellement interdites, nommées une par une. Pour ces cas, un retour
  `('a, transition_error) result` serait plus fidèle qu'une exception (cf. règle projet
  « `Result` > exceptions pour les erreurs récupérables ») — mais l'appelant est un thunk du
  *task runner* qui rattrape déjà tout : conversion à évaluer, pas à décréter.

**Coût à assumer, à ne pas sous-estimer** : `user_level.mli` et `machine.mli` exposent aujourd'hui
les champs (`val automaton_state`, `val next_automaton_state`, `val simulated_device`) dans
plusieurs signatures de classes — les deux interfaces sont à retoucher, et la recompilation touche
l'ensemble de `bin/`. `machine.ml` et `router.ml` redéfinissent `gracefully_shutdown_right_now` et
`poweroff_right_now`, `cable.ml` redéfinit `suspend_right_now`, `resume_right_now`,
`destroy_because_of_unexpected_death` et les cinq `can_*` : tous doivent suivre.

**Ne pas fusionner au passage avec `Simulation_level.device_state`** (C1) : les deux automates
décrivent des choses différentes (le modèle utilisateur d'un côté, le cycle de vie des processus
de l'autre) et `Destroyed` n'a pas d'équivalent utile côté utilisateur. Une seule mesure suffit :
que le passage de l'un à l'autre soit localisé dans les `*_right_now` — ce qu'il est déjà.

### Renommages (à appliquer avec R2, pas séparément)

| Actuel | Proposé | Motif |
|---|---|---|
| `simulated_device_automaton_state` | `Simulated_device.state` | le préfixe redondant disparaît avec le module |
| `NoDevice`, `DeviceOff`, `DeviceOn`, `DeviceSleeping` | `No_device`, `Off`, `On`, `Sleeping` | idem ; aligne sur `Simulation_level` |
| `simulated_device_state` (getter) | `get_state` | |
| `string_of_simulated_device_state` | `icon_suffix_of_state` | ce n'est pas une conversion fidèle mais **le suffixe de nom de fichier d'icône** (`ico.<kind>.<suffixe>.<taille>.png`) ; la vraie conversion est `automaton_state_as_string` |
| `automaton_state_as_string` | `to_string` | |
| `create_right_now` / `destroy_right_now` / … | inchangés | le suffixe `_right_now` distingue utilement la transition réelle de son enveloppe asynchrone |

---

## 4. Ce que cet audit n'a pas couvert

- **Preuve terrain** : aucun scénario GUI n'a été rejoué. B4 est déductible du source mais mérite
  une vérification manuelle (ouvrir un projet, « Démarrer tout », « Arrêter tout », quitter :
  la question de sauvegarde doit apparaître).
- **`Obj.magic`** : les jointures user/simulation level (`machine.ml:171`, `212`, `240`,
  `cable.ml:120`, …) sont hors périmètre — dette déjà connue et documentée (`CLAUDE.md`).
- **Les treeviews comme source d'état** : seul le chemin `after_user_edit_callback` →
  `shutdown_or_restart_relevant_device` a été suivi. La cohérence *interne* des treeviews
  (ifconfig, defects) avec le modèle réseau n'a pas été auditée. ⚠️ **Ce trou s'est révélé
  habité** : deux plantages reproductibles y ont été constatés en exécution le 2026-07-29, cf.
  **B6** — l'audit de cette cohérence n'est donc plus optionnel.
- **Le `Thread.delay 7.`** de `gracefully_restart` : identifié, non diagnostiqué.

---

## 5. Journal d'avancement

### Épisode 0 — 2026-07-29 — audit et officialisation

**Fait.** Audit complet des chemins qui modifient l'état d'un composant depuis la GUI, en
partant de `simulated_device_automaton_state` (`user_level.ml:79`) et en remontant vers
`Marionnet.st` et les treeviews. Résultat : 5 bugs (B1-B5), 5 incohérences de conception
(C1-C5), 4 recommandations priorisées (§ 3). Aucun code modifié — `dune build` vert avant comme
après, l'épisode est inerte par construction.

**Décidé (ép. 0).** R2 (module `Simulated_device`, état porteur du device) est retenue et devient le
cœur du chantier. Écarté : fusionner l'automate utilisateur avec
`Simulation_level.device_state` (C1) — les deux décrivent des choses différentes, et `Destroyed`
n'a pas d'équivalent utile côté utilisateur. Écarté aussi : câbler `next_automaton_state` pour
afficher une icône transitoire — ce serait une fonctionnalité GUI nouvelle, pas une mise en
cohérence (cf. R1).

**Reste.** R4 → R1 → R3 → R2, dans cet ordre. Aucun n'est entamé.

### Épisode 1 — 2026-07-29 — R4, correctifs ponctuels

**Fait.** Les quatre points de R4, sur trois fichiers, sans toucher une seule signature ni un
seul `.mli` :

1. **B1 corrigé** — `begin … end` dans `gracefully_restart` (`user_level.ml:223-236`), avec un
   commentaire rappelant la précédence du `;` sur `if/then/else`. La garde couvre désormais les
   trois instructions ; le défaut était latent (seul appelant : `marionnet.ml:146`, qui filtre
   déjà en amont).
2. **B5 documenté, non corrigé** (cf. « Décidé » ci-dessous) — deux commentaires dans `cable.ml` :
   sur `Properties.dynlist` (écart de filtrage avec les nœuds, masqué par les trois
   `can_* = true`) et sur `Properties.reaction` (fenêtre de coexistence entre l'ancien câble
   détruit en différé et le nouveau construit tout de suite).
3. **C5 corrigé** — les quatre `try … with _ -> ()` de `network#reset` et
   `destroy_process_before_quitting` (`user_level.ml:1589-1637`) journalisent maintenant le nom du
   composant et `Printexc.to_string`. Comportement inchangé (l'échec reste toléré), traçabilité
   ajoutée — utile au chantier `bug-critique-crash-host`.
4. **Commentaire mort supprimé** — `marionnet.ml:213-214` (`st#state_coherence`, méthode
   inexistante ailleurs dans `bin/`).

Le `Thread.delay 7.` de `gracefully_restart` reste en place, conformément au § 3.

**Décidé.** Ne **pas** modifier le séquencement de `Cable…Properties.reaction` dans cet épisode,
contrairement à la lettre de R4 : les deux corrections envisageables sortent du « faible risque »
qui justifie de faire R4 en premier. Un `c#destroy_right_now` synchrone prendrait le
`Recursive_mutex` depuis le thread GTK alors qu'une tâche du *task runner* peut le détenir en
attendant ce même thread (barre de progression, `refresh_sketch`) — le scénario même que
signalent les logs « *You don't deadlock here … do you?* » (`user_level.ml:260-306`) et C4. Passer
par le *task runner* + `gMain_actor` éviterait le deadlock mais rendrait la re-création asynchrone
après la fermeture du dialogue, soit un changement de comportement visible. Le point est donc
consigné dans le code et rattaché à **R2**, qui révise de toute façon les `can_*` des câbles.

**Preuve.** `dune build` : rc = 0, `marionnet.exe` relié après la dernière édition. Aucun scénario
GUI rejoué : B1 est inatteignable depuis l'IHM actuelle, C5 n'ajoute que des logs, B5 n'a pas
changé de comportement.

**Reste.** R1 → R3 → R2.

### Signalement terrain — 2026-07-29 — B6 (hors épisode)

Deux plantages **constatés en GUI réelle**, rapportés pendant la fumée du chantier
`marionnet-pilotage-par-script` et consignés ici après vérification du périmètre : les piles ne
traversent aucun code réseau (`Network` n'apparaît ni dans `treeview.ml` ni dans
`treeview_defects.ml`), et le journal ne contient aucun `EBADF` ni `Bad file descriptor`. Il
s'agit bien d'incohérences composant ↔ treeview, cf. **B6** au § 1.

Ce signalement n'est pas un épisode : **aucun code n'a été modifié**. Il ajoute une preuve
terrain à un chantier jusqu'ici purement statique, et il remplit un trou que le § 4 déclarait
explicitement non exploré. L'ordre de travail reste **R1 → R3 → R2** ; B6 demande d'abord
l'instrumentation décrite au § 1 (journaliser ce que `get_cable_data` trouve réellement), pas
un correctif à l'aveugle.

Journaux de référence : `/tmp/marionnet.native.42.log` (`Not_found`, ligne 900) et
`/tmp/marionnet.native.43.log` (`Assertion failed`, ligne 569).

### Épisode 2 — 2026-07-30 — B6 : instrumentation et diagnostic partiel

**But de l'épisode** (fixé par le § 1 : instrumenter avant de corriger) : établir par quel pas
les lignes de direction d'un câble deviennent en nombre ≠ 1, et si ce nombre est 0 ou 2.

**Instrumentation posée** — strictement observationnelle : aucun flux de contrôle, aucune valeur
de retour, aucune exception n'est modifiée. Toutes les traces sont préfixées `B6:` et émises en
`~force:true` (donc visibles hors mode debug), à l'exception de la ligne nominale de
`get_cable_data`. Six sites :

| Fichier | Site | Ce que ça montre |
|---|---|---|
| `treeview_defects.ml` | `b6_dump_children` (méthode privée, nouvelle) | tous les enfants d'un parent, via `Row.to_pretty_string` |
| `treeview_defects.ml` | `get_cable_data` | une ligne par appel (`found/total`) + dump si `found ≠ 1` |
| `treeview_defects.ml` | `get_port_data` | dump avant de relancer le **même** `Not_found` |
| `treeview_defects.ml` | `add_cable` | les identifiants des deux enfants créés (les deux `ignore` les masquaient) |
| `treeview.ml` | `remove_subtree`, `remove_row`, `remove_subtree_by_name` | qui est retiré, avec quels descendants ; l'exception que `remove_subtree_by_name` continue d'avaler |
| `treeview.ml` | `load` | la forêt fraîchement chargée et le `next_identifier` restauré |

**Résultats — ce qui est désormais établi.**

1. **C'est 0, pas 2.** Le câble `d2` (row 24) n'a plus qu'un enfant, `leftward` (row 25) ; le
   `rightward` manque et le **parent survit** (journal 44, lignes 596-597).
2. **`remove_subtree_by_name` n'a rien avalé** : aucune trace `SKIPPED`. Le mécanisme n° 1 du
   § 1, quoique réel dans le code, **n'est pas celui qui a agi ici**.
3. **L'état est amputé sur le disque**, pas en mémoire : le dump du chargement montre `abc.mar`
   livrant déjà `d2` avec un unique enfant (journal 45). Tout rejeu ouvrant ce projet ne montre
   donc que l'état hérité — les journaux 44 et 45 ne prouvent rien sur le *pas* fautif.
4. **Le geste supposé minimal ne reproduit pas.** Sur projet **neuf** (journal 46) : `d3` est
   créé (rows 27/28/29), détruit avec ses **deux** enfants, et `d2` conserve les siens du début
   à la fin. L'hypothèse de travail du § 1 (« créer un câble, le supprimer, démarrer ») est
   **infirmée** : il manque un ingrédient.
5. **Le row perdu a bien existé.** Décisif, et obtenu **hors GUI** : le fichier `abc/states/defects`
   d'`abc.mar` est un `Marshal` direct d'un couple `(next_identifier, forêt)`
   (`Oomarshal.marshaller`, `lib/MARSHAL/oomarshal.ml:78-99`), lisible par un programme de trois
   lignes. Il porte **`next_identifier = 30`** alors que le plus grand identifiant présent est
   **25**. La numérotation d'un projet neuf identique (journal 46) étant `m1` 0-3, `m2` 4-7,
   `H1` 8-20, `d1` 21-23, `d2` 24-25-**26**, `d3` 27-29, le compteur prouve que **le row 26 —
   le `rightward` de `d2` — a été alloué**, puis perdu, tandis que `d3` (27-29) a été
   correctement supprimé. Ce n'est donc pas une création manquée.

**Deux défauts découverts en chemin** (hors périmètre de l'épisode, non corrigés) :

- **`Forest.filter` « coupe les mauvais nœuds et **remonte leurs orphelins** »**
  (`lib/STRUCTURES/forest.ml:150`). `Treeview.remove_row` étant bâti dessus, il ne détruit pas un
  sous-arbre : il **promeut** les enfants d'un rang. `remove_subtree` s'en tire parce qu'il
  filtre aussi tous les descendants, mais la primitive publique est un piège.
- **La garde des contraintes de rangée est inversée** : `add_unspecified_columns`
  (`treeview.ml:1046-1059`) exécute `check_constraints` **quand on lui demande de les ignorer**
  (`if ignore_constraints = Some () then …`), et `add_row` ne passe jamais l'argument — donc
  aucune contrainte n'est jamais vérifiée à l'ajout. Corollaire utile ici : `add_row` ne peut pas
  échouer pour cause de contrainte, ce qui écarte le scénario « le second `add_row` a levé ».
- **Le dump de la forêt au chargement était du code mort** : gardé par
  `Global_options.Debug_level.get () >= 3` alors que `Initialization.Debug_level` est produit par
  `of_bool` et plafonne à 1 (`initialization.ml:148-155`). Seuil abaissé à `>= 1` pour cet
  épisode.

**Reste à faire pour clore B6** : trouver l'ingrédient manquant du scénario. Deux candidats,
dans l'ordre de vraisemblance, tous deux compatibles avec le mécanisme n° 3 du § 1 (le treeview
est manipulé depuis le thread GTK *et* depuis le task runner, sans discipline) :

1. **création/suppression de câble pendant que des composants tournent ou terminent** — c'est
   le seul écart connu entre la session 43 et le rejeu 46 ;
2. **sauvegarde/rechargement intercalé** avant la suppression, qui rebâtit la forêt et les iters
   GTK.

Journaux de référence : `/tmp/marionnet.native.44.log` (rejeu sur projet abîmé),
`.45.log` (ouverture seule : dump du chargement), `.46.log` (projet neuf : pas de reproduction).

### Épisode 3 — 2026-07-30 — R1, suppression de `next_automaton_state`

**Fait.** R1 intégralement, sur trois fichiers. Le champ mort disparaît et le rafraîchissement du
dessin, jusqu'ici effet de bord de son *setter*, devient explicite.

1. **Champ et méthodes retirés** — `val next_automaton_state`, `next_simulated_device_state` et
   `set_next_simulated_device_state` (`user_level.ml:131-142`), plus leurs 14 déclarations dans
   `user_level.mli` (4 `val`, 5 couples de méthodes) et 3 dans `machine.mli`. Vérification préalable
   par `grep` sur `bin/` : aucun lecteur hors du *getter* lui-même — **B3** confirmé sur pièces.
2. **Six écritures « transition en cours » supprimées** (`startup`, `suspend`, `resume`,
   `gracefully_shutdown`, `gracefully_restart`, `poweroff`) : elles précédaient une mise en file et
   n'avaient d'autre effet qu'un `refresh_sketch` sur un état inchangé. Ces méthodes se réduisent à
   leur `enqueue_task_with_progress_bar` ; le `begin … end` de B1 (épisode 1) est intact.
3. **Huit écritures « transition finie » remplacées par un `Sketch.refresh_sketch ()` explicite**,
   au même endroit : `create_right_now`, `destroy_because_of_unexpected_death`,
   `destroy_right_now`, `startup_right_now`, `suspend_right_now`, `resume_right_now`,
   `gracefully_shutdown_right_now`, `poweroff_right_now`. Chacun reste dans la branche *aboutie* de
   son `match` — aucun n'est passé du côté d'un `raise_forbidden_transition`.
4. **Deux commentaires devenus faux** (« *don't set the next state* », `create` et
   `destroy_my_simulated_device`) réécrits : ce qui distingue réellement ces deux chemins est
   l'absence de barre de progression.

**B2 et B3 disparaissent** sans correctif dédié, comme prévu au § 3 : il n'y a plus de champ à
laisser figé sur une transition fantôme.

**Effet de bord assumé.** Les six refresh supprimés incrémentaient aussi `refresh_sketch_counter`,
qui sert de drapeau « projet modifié » (**B4**) : démarrer ou arrêter un composant salit désormais
le projet un peu moins souvent. C'est un pas dans le sens de **R3**, qui séparera les deux
compteurs, pas une régression.

**Preuve.** `dune build` : rc = 0 après la dernière édition (les `.mli` font échouer toute
suppression incomplète). `grep -rn "next_automaton_state\|next_simulated_device_state" bin/ lib/` :
aucune occurrence. Bilan : 46 lignes retirées, 10 ajoutées. Aucun scénario GUI rejoué — le nombre de
`refresh_sketch` diminue mais aucun n'est déplacé ni supprimé sur un chemin où l'état change.

**Reste.** R3 → R2. Et, hors ordre imposé, B6 (l'ingrédient manquant du scénario) plus le retrait
de l'instrumentation `B6:` de l'épisode 2.

### Épisode 4 — 2026-07-30 — R3, le rendu du dessin cesse de décider de la sauvegarde

**Fait.** R3 sur deux fichiers, sous la forme rectifiée du § R3 ci-dessus (drapeau, pas compteur).

Le préalable a été un **classement de tous les appelants de `refresh_sketch`** — 14 sites, obtenus
par `grep` puis vérifiés un à un dans le code, parce que la question n'est pas « qui redessine ? »
mais « qui écrit dans le `.mar` ? » :

| Site | Persisté ? | Preuve | Après R3 |
|---|---|---|---|
| `user_level.ml` ×8 (transitions, posées à l'ép. 3) | non | états de simulation | rendu seul |
| `cable.ml:436` (`reversed`) | **non** | absent de `to_tree` / `eval_forest_attribute` (`:703-728`) | rendu seul |
| `cable.ml:756`, `:778` (connect / disconnect) | non | `connected` absent de `to_tree` | rendu seul |
| `motherboard_builder.ml:151-158` (7 *dotoptions*) | **oui** | `dotoptions.marshal` : `state.ml:721` / `:472` | salit le projet |
| `state.ml` `network_change` (21 appelants) | oui | `network.xml` | salit le projet |
| `state.ml` `new_project`, `import_network` | — | cf. invariants ci-dessous | inchangé |

1. **`state.ml`** — `refresh_sketch_counter_value_after_last_save` devient
   `val mutable project_dirty = true` ; `set_project_not_already_saved` l'arme ;
   `register_state_after_save_or_open` le désarme (le *snapshot* des forêts de treeviews est
   conservé tel quel) ; `project_already_saved` teste le drapeau puis, seulement s'il est baissé,
   fait le test coûteux des forêts — qui reste le filet de sécurité. `network_change` arme le
   drapeau à côté de son `refresh_sketch`.
2. **`motherboard_builder.ml:151`** — les 7 `on_commit` des *dotoptions* arment le drapeau en plus
   de redessiner (cf. rectification n° 2 : ces options sont persistées).
3. **`method refresh_sketch_counter` supprimée** : cet accès public au compteur n'existait que pour
   la décision de sauvegarde. Le compteur redevient un canal de rendu **interne**, ce qui retire
   l'invitation à refaire B4.
4. **`private_new_project` arme explicitement le drapeau** (`state.ml:316-319`) : sans cette ligne,
   un projet neuf créé après un projet sauvegardé aurait hérité d'un drapeau baissé, alors que
   l'ancien compteur garantissait « non sauvé » par son incrément. Préservation d'invariant, pas
   ajout de comportement.

**Invariants vérifiés avant édition** (par lecture, pas par supposition) : à l'ouverture, les
*dotoptions* (`:472`) et le réseau (`:533`) sont chargés **avant**
`register_state_after_save_or_open` (`:535`) — un projet fraîchement ouvert reste donc « déjà
sauvé » ; et R3 ne peut régresser sur un chemin qui modifierait le modèle sans redessiner, puisque
ce chemin ne salissait déjà rien.

**Preuve statique.** `dune build` : rc = 0. `grep` : plus aucune référence à l'ancien champ, et
`refresh_sketch_counter` n'est plus lu que par sa propre réaction de rendu. Fraîcheur du binaire
vérifiée sur les chaînes de journal, pas sur un horodatage :
`strings $(which marionnet.native) | grep -c 'the model has been changed'` → 1, et
`… | grep -c 'seems not already saved (x='` → 0. Bilan : 2 fichiers, +30 / −21.

**Preuve GUI (5 rejeux, journaux 47 à 51).** Les trois voies que le correctif touche sont vertes,
la corrélation geste ↔ décision étant lisible au nombre de rafraîchissements du dessin :

| Journal | Geste | « About to refresh the sketch » | Décision |
|---|---|---|---|
| 49 | ouvrir, ne rien faire, quitter | 1 (l'ouverture) | `The project *is* already saved.` — **aucune question** |
| 50 | changer l'*iconsize* / le *rankdir* | 2 (le 2ᵉ juste avant la décision) | `not already saved (the model has been changed)` |
| 51 | renommer un composant | 2 (idem) | `not already saved (the model has been changed)` |

Le journal 50 valide précisément l'écart pris avec la recette d'origine : sans lui, ce réglage
serait perdu sans un mot à la fermeture.

**Ce que le scénario a démenti.** Sur le cycle « Démarrer tout / Arrêter tout » (journaux 47 sur
`abc.mar` et 48 sur un projet neuf), le drapeau reste bien baissé — le journal atteint
`The project *seems* already saved.`, ligne inatteignable avant R3 — **mais la question de
sauvegarde apparaît encore**, via le test des forêts, et pour une raison légitime : le treeview
*history*. Cf. l'encadré ajouté au § B4. **B4 n'est donc corrigé qu'à moitié**, et l'autre moitié
demande un arbitrage, pas du code.

**Reste.** R2 (cœur du chantier). B6, dont le périmètre s'élargit au socle `treeview.ml`
(cf. encadré du § B6), plus le retrait de l'instrumentation `B6:` de l'épisode 2. Et, si l'auteur
le décide, la seconde moitié de B4.
