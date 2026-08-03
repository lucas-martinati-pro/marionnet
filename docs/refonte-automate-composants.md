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

> **CLOS à l'épisode 15** (2026-08-02), en deux temps : la **première** moitié — le compteur de
> rendu qui salissait le projet — a été supprimée à l'épisode 4 (R3, drapeau `project_dirty`) ; la
> **seconde** — l'état de disque COW ajouté au treeview *history* — est tranchée par l'auteur comme
> **légitime**, donc sans correctif. Démarrer une machine crée un état COW qui *est* un contenu
> persistable du `.mar` : demander la sauvegarde est la bonne réponse, et la prémisse de l'audit
> ci-dessous (« aucune donnée persistée n'a changé ») était **fausse** dans ce cas. Un commentaire
> le dit désormais sur place (`state.ml`, `project_already_saved`) pour qu'on ne « corrige » pas ce
> comportement plus tard.

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
>
> **Arbitrage rendu (épisode 15)** : légitime, on ne touche à rien. Ce qui reste « surprenant » ne
> l'est qu'au premier regard — après un démarrer/arrêter, le projet contient réellement quelque
> chose de plus que ce qui a été enregistré. Deux options écartées, et pourquoi : exclure les états
> COW du test des forêts ferait **perdre en silence** un contenu du `.mar` (même refus qu'à
> l'épisode 4 pour les *dotoptions*) ; ne salir que si le disque COW *diffère* réellement
> supposerait de comparer les disques à chaque fermeture, coût sans bénéfice pour l'utilisateur.

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

> **Rectification, épisode 5 : ce n'était NI une divergence des structures, NI une course entre
> threads.** Les deux mécanismes supposés ci-dessus sont infirmés par la mesure (§ « Épisode 5 ») :
> à chaque échec, la forêt interne et le modèle GTK contiennent **exactement les mêmes
> identifiants**, et l'échec se reproduit à l'identique lorsque l'opération est exécutée **par le
> thread GTK lui-même**. La cause du symptôme « le composant ne démarre pas » sur projet sain est
> que **la lecture de la colonne `_id` du modèle rend parfois une valeur qui n'est pas celle
> stockée** (`"@"` là où la lecture suivante donne `"0"`), ce qui faisait déclarer absente une
> ligne parfaitement présente. Le mécanisme n° 1 (`remove_subtree_by_name` avalant l'exception)
> et le mécanisme n° 3 (entrelacement des threads) restent des défauts réels du code, mais ils
> ne sont pas la cause de ce symptôme-ci.

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

> **Fait à l'épisode 7** (`71fca1a`, `cbc6267`, 2026-07-31), en un seul épisode et non
> plusieurs. Une seule pièce du plan ci-dessous est tombée : `device_opt` existe, mais **aucune
> méthode publique ne peut rendre l'état lui-même** — son type mentionnerait `'parent`, que
> `cable.ml` instancie avec son propre type d'objet récursif. Cf. journal § 5.

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
| `simulated_device_state` (getter) | ~~`get_state`~~ → **supprimé** (ép. 7) | son type mentionnerait `'parent` : impossible à exposer sans casser `cable.ml` ; aucun appelant |
| `string_of_simulated_device_state` | `icon_suffix_of_state` | ce n'est pas une conversion fidèle mais **le suffixe de nom de fichier d'icône** (`ico.<kind>.<suffixe>.<taille>.png`) ; la vraie conversion est `automaton_state_as_string` |
| `automaton_state_as_string` | ~~`to_string`~~ → **`state_as_string`** (ép. 7) | sur une classe, `self#to_string` se lirait « chaîne du composant » ; `to_string` est réservé à la fonction du module |
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

### Épisode 5 — 2026-07-30 — B6 : la lecture du modèle GTK, et non la divergence des forêts

**But de l'épisode** : établir la racine de l'échec `id_to_iter: id 0 not found` — élargi au socle
à l'épisode 4 — puis corriger. Méthode : instrumenter jusqu'à ce qu'une mesure, et non un
raisonnement, désigne la cause.

**Les deux hypothèses de l'audit tombent, dans cet ordre.**

| Journal | Mesure | Conséquence |
|---|---|---|
| 52 | `Store ids: [0; 2; 1]. Forest ids: [0; 2; 1]` et pourtant « id 0 not found » | la **divergence store ↔ forêt** est infirmée : les deux structures sont d'accord |
| 53 | `id 0 (length 1) … Found by an immediate retry: true` | ni chaîne piégée ni parcours tronqué : **deux parcours consécutifs se contredisent** |
| 54 | même échec, `Calling thread: 0` (opération déléguée au thread GTK) | la **course entre threads** est infirmée |
| 55 | `Visited BY THE FAILING traversal: [@; 2; 1]` | décisif : le parcours lit **`"@"`** dans la colonne `_id` de la première ligne, là où le parcours suivant lit `"0"` |
| 56 | avec une simple relecture par ligne, m1 démarre ; apparition d'un `CRITICAL … Icon lookup failed` | *heisenbug* ; et le renderer d'icônes montre la **même famille** de défaut sur une autre colonne |

Autrement dit : le socle déclarait absente une ligne parfaitement présente, parce qu'il
**identifiait les lignes en relisant une colonne du widget**. Le symptôme visible pour
l'utilisateur était : le composant ne démarre pas, sans un mot à l'écran.

**Correctif n° 1 — `treeview.ml`, résolution par la forêt interne.** `id_to_iter` ne balaie plus
le modèle GTK en comparant la colonne `_id` de chaque ligne : `id_to_path_indices` calcule les
indices du chemin depuis la **forêt interne** (la source de vérité), puis `store#get_iter` fait le
reste. L'équivalence des deux ordres est établie, pas supposée : `Forest.add_tree_to_forest`
concatène le nouvel arbre **à la fin** des enfants (`forest.ml:331-338`), exactement comme
`store#append`, et `set_complete_forest` remplit le store par un parcours **pré-ordre** — ancêtres
et frères précédents sont donc toujours déjà en place quand un chemin est calculé. Effet
secondaire bienvenu : le widget n'est plus parcouru à **chaque écriture de colonne** (`column#set`
appelait `id_to_iter`), ce qui retire un coût quadratique au chargement d'un projet.

**Correctif n° 2 — `state.ml`, l'échec cesse d'être déclaré « réussi ».**
`make_names_and_thunks` avalait l'exception du thunk (`try … with e -> log`), si bien que le task
runner annonçait ensuite `The task "Startup m1" succeeded.` sur un composant resté éteint.
L'exception est désormais journalisée **puis propagée** (`Printexc.raise_with_backtrace`, après
destruction de la barre de progression, qui reste garantie). Preuve au journal 54 :
`task_runner: WARNING: … raised an exception … THIS MAY BE SERIOUS` a remplacé le « succeeded ».

**Ce qui a été essayé, puis retiré.** La délégation de `add_substate_of` et `remove_device_tree`
à `gMain_actor` (journal 54) : elle n'a pas corrigé l'échec — puisque la course n'était pas la
cause — et elle introduisait précisément le motif de deadlock refusé à l'épisode 1, le task runner
restant bloqué dans `apply` alors qu'il détient deux mutex de composant (cf. B5 et C4). Retirée.
**La violation de la discipline de thread par les treeviews reste entière et non traitée** : elle
est réelle, mais elle demande un traitement d'ensemble, avec une réponse assumée sur les mutex.

**Preuve GUI.**

| Journal | Scénario | Résultat |
|---|---|---|
| 57 | `propre-2machines-1hub`, tout démarrer | **m1 et m2 démarrent** (l'échec cible a disparu) ; H1 échoue encore, pour la cause historique de B6 côté *defects* : `d2` a perdu son enfant `rightward` **sur le disque** (`0/1` direction, `assert` fatal `treeview_defects.ml:302`) — hors périmètre de cet épisode |
| 58 | projet **neuf** : 2 machines + hub + 2 câbles, tout démarrer, tout arrêter, quitter | **0** `id_to_iter`, **0** `Assertion failed`, **0** `CRITICAL`, **0** tâche en échec, fermeture propre |

**Suites ouvertes, explicitement non traitées ici.**

1. **La cause profonde de la lecture non fiable** n'est pas établie : lire une colonne du modèle a
   rendu `"@"` au lieu de `"0"`. Pistes à instruire (dans cet ordre de suspicion) : le
   `Obj.magic gtree_column` des classes de colonnes (`treeview.ml:321-324` et jumeaux), un iter
   périmé, ou lablgtk3 sous OCaml 5. Tant qu'elle n'est pas établie, **toute lecture de colonne
   du widget reste suspecte** — le correctif n° 1 se contente de ne plus en dépendre pour
   identifier une ligne.
2. **`CRITICAL: gtk_tree_cell_data_func … Failure("Icon lookup failed")`** (journal 56) : le
   renderer d'icônes lit lui aussi une valeur qui ne correspond à aucun type connu, et échoue par
   `failwith` au lieu de tolérer l'inconnu. Même famille que le point 1.
3. **Le volet *defects* de B6** : une entrée héritée invalide (`d2` sans `rightward`) suffit à
   empêcher un démarrage, parce que `add_my_defects` conclut de l'existence d'une ligne homonyme
   que l'entrée est **valide** et que `get_cable_data` tranche par `assert`. L'ingrédient qui fait
   perdre la ligne (recherché à l'épisode 2) reste inconnu.
4. **Le retrait de l'instrumentation `B6:`** de l'épisode 2, à faire à la clôture de B6.

### Épisode 6 — 2026-07-30 — B6 : plus aucune identité lue dans le widget, et plus rien de fatal

**But** : traiter trois des quatre suites laissées ouvertes par l'épisode 5 — la dépendance
résiduelle aux lectures du widget, le renderer d'icônes fatal, et le volet *defects* qui empêchait
encore `H1` de démarrer sur `propre-2machines-1hub`.

**Volet 1 — l'identité d'une ligne ne se lit plus jamais dans le modèle GTK.** `iter_to_id`
(`treeview.ml`) était le dernier lecteur de la colonne `_id` du widget, et `path_to_id` en
dépendait. Huit sites en dépendaient à leur tour, dont **deux chemins d'écriture** — la fin d'une
édition (`editable_string_column#on_edit`) et la bascule d'une case (`checkbox_column`) — où un
identifiant faux fait atterrir la saisie **dans une autre ligne**. C'est un mécanisme de perte
silencieuse que l'épisode 2 n'avait pas envisagé : il cherchait un geste utilisateur exotique.
`path_to_id` dérive désormais l'identifiant de la forêt interne (`path_indices_to_id`, le converse
exact de `id_to_path_indices` de l'épisode 5) et **échoue nommément** plutôt que de rendre un
identifiant plausible mais faux. `for_all_rows`, `iter_on_forest` et `iter_on_tree` — le parcours
à itérateurs mutés destructivement, sans appelant depuis l'épisode 5 — sont supprimés.

**Volet 2 — une icône inconnue ne tue plus le rendu.** `icon_cell_data_function` appelait
`lookup_by_string`, dont l'échec est un `failwith`, **depuis un `cell_data_func`** : l'exception
traversait la pile C de Gtk, d'où le `CRITICAL: gtk_tree_cell_data_func` du journal 56. Une
fonction de rendu doit être totale : la valeur inattendue est journalisée et la cellule dessinée
vide (pixbuf transparent explicite — laisser `` `PIXBUF `` non positionné ferait hériter l'icône de
la ligne précédente, le renderer étant réutilisé pour toutes les cellules).

**Volet 3 — le volet *defects*.** La validité d'une entrée était **déduite d'une ligne homonyme**
(`add_my_defects`, `user_level.ml` et `cable.ml`) puis **tranchée par `assert`**
(`get_cable_data`). Un composant héritait donc d'une entrée amputée et échouait au démarrage.
La décision revient maintenant au treeview, seul à connaître la forme attendue :
`ensure_cable_entry` et `ensure_device_entry` créent l'entrée quand il n'y en a pas et
**complètent les lignes manquantes** quand elle est tronquée. **Écart assumé avec le plan**, qui
prévoyait de détruire et recréer une entrée malformée : cela aurait effacé sans le dire les défauts
réglés par l'utilisateur sur les lignes survivantes — le même refus qu'à l'épisode 4 pour les
*dotoptions*. Les `assert` deviennent des échecs nommés ; les doublons sont signalés mais jamais
supprimés (effacer une ligne portant peut-être des réglages n'est pas une décision que ce point du
code peut prendre seul).

**Preuve GUI.**

| Journal | Scénario | Résultat |
|---|---|---|
| 59 | `propre-2machines-1hub`, `-r` (démarrage automatique), tout arrêter, quitter | **`Startup H1` réussit** — jamais obtenu jusqu'ici sur ce projet. `d2` réparé au chargement (`1 missing row(s) added`). **0** `id_to_iter`, **0** `Assertion failed`, **0** `CRITICAL`, **0** exception levée, 12/12 tâches réussies, arrêt et sortie propres, aucun processus résiduel |
| 60 | même projet, gestes d'**édition** des treeviews (valeur éditée, case, menu contextuel), quitter | **0** échec de `path_to_id`, **0** `CRITICAL`, **0** `Assertion failed`. Les éditions aboutissent (`set` précède le callback métier) |

**Trois constats qui débordent de l'épisode.**

1. **Le défaut de lecture du widget est toujours actif — et il est maintenant *mesurable*.** Le
   volet 2 l'a rendu observable au lieu de fatal : six lectures de la colonne `Type` ont rendu
   (journal 60, `cat -v`) `M-??*M-9M-^FZ^@^@port` et `.*,M-9M-^FZ^@ -cable`. Ces valeurs ne sont pas
   aléatoires : ce sont **huit octets de garbage — dont la signature d'une adresse (`M-9 M-^F Z ^@`,
   commune à toutes les occurrences) — suivis de la *fin correcte* de la vraie chaîne**
   (`other-device-port`, `…-cable`). Autrement dit un **décalage d'offset systématique** à la
   lecture, et non une corruption de données ni une course. Cela explique rétrospectivement le
   `"@"` lu à la place de `"0"` (épisode 5). La cause reste dans la couche lablgtk3/Gtk sous
   OCaml 5, non élucidée — mais **toute lecture de colonne du widget est désormais établie comme
   structurellement suspecte**, ce qui valide la stratégie des volets 1 et 2 : ne plus rien
   décider sur une telle lecture, et ne jamais en mourir.
2. **Le `.mar` reste amputé sur le disque.** La réparation opère en mémoire à chaque ouverture ;
   le projet guérit donc à chaque chargement sans jamais guérir sur disque (tant qu'il n'est pas
   sauvegardé). C'est délibéré — on ne réécrit pas le projet de l'utilisateur à son insu.
3. **Bug i18n découvert par le terrain, hors périmètre** : `bin/po/fr.po:2462-2468` traduit un
   `msgid` à **deux** `%s` par un `msgstr` à **un** seul. `Printf.sprintf (f_ "…")`
   (`marionnet.ml:122`) lève donc `Scanf.Scan_failure` et **la question « voulez-vous redémarrer
   maintenant ? » ne s'affiche jamais en français** après l'édition d'un défaut sur un composant en
   marche : la valeur est bien écrite, mais le redémarrage qui l'applique n'est pas proposé
   (6 occurrences au journal 60). Les 11 autres catalogues sont à vérifier de la même façon.

**Reste pour clore B6** : la cause profonde de la lecture décalée (point 1), et le retrait de
l'instrumentation `B6:` de l'épisode 2.

### Épisode 7 — 2026-07-31 — R2, l'état porte le device

**Fait.** Le cœur du chantier, dernier reliquat du plan de conception. Deux commits, pour que le
diff sémantique reste relisible ligne à ligne :

- `71fca1a` — la **fusion** : `val automaton_state` et `val simulated_device` deviennent un seul
  `val state : 'parent Simulated_device.state ref` ;
- `cbc6267` — les **renommages**, purement mécaniques.

**Ce que la fusion rapporte, mesuré et non supposé.** Les huit filtrages de couple deviennent
des filtrages simples et exhaustifs. **Trois** des sept `raise_forbidden_transition` disparaissent
comme **inatteignables** — `destroy_right_now`, `gracefully_shutdown_right_now` et
`poweroff_right_now` couvraient déjà les quatre états, leur fourre-tout ne rattrapait donc qu'une
violation d'invariant désormais non représentable. Les quatre restants (`create`, `startup`,
`suspend`, `resume`) sont des branches **nommées** dont le message porte l'état de départ
(`"suspend_right_now: from DeviceOff"`), au lieu du nom de méthode nu.

**Les `val` quittent les signatures de classe.** `user_level.mli` les déclarait dans quatre
signatures, `machine.mli` dans une : un invariant qu'un héritier externe peut écraser par
affectation n'est pas un invariant. Le retrait était sans risque et sans pari — la signature de
la classe qui les **définit** (`user_level.mli:30-39`) les omettait déjà, n'exposant que
`val mutex`, lequel doit rester (il est utilisé par `cable.ml:795`).

**Deux obstacles de typage, dont un qui a modifié le plan.**

1. *Bénin.* `Simulation_level.device` contraint son paramètre
   (`constraint 'parent = < get_name : string; .. >`, `simulation_level.mli:265`). Le `.ml`
   l'infère, le `.mli` ne l'aurait pas déclarée : il faut la répéter explicitement dans la
   déclaration du type `state`, des deux côtés.
2. *Structurel.* **Aucune méthode publique ne peut avoir un type mentionnant `'parent`.**
   `cable.ml` fait `inherit [cable] User_level.simulated_device ()` : il instancie `'parent`
   avec son **propre** type d'objet, défini récursivement dans un `let rec endpoint … and
   cable = …`. Une méthode de type `'parent Simulated_device.state` y rend l'abréviation `cable`
   insoluble (l'occurrence récursive est monomorphe). `method simulated_device_state` a donc été
   **supprimée** au lieu d'être renommée `get_state` comme le prévoyait la table des renommages.
   Elle n'avait aucun appelant. L'état n'est plus lisible de l'extérieur que par ses projections
   (`icon_suffix_of_state`, `state_as_string`) et les cinq `can_*` — ce qui est le but de R2.
   *Corollaire pour la suite* : exposer l'état au chantier `marionnet-pilotage-par-script`
   demandera une projection **non paramétrée**, pas l'état lui-même.

**Écart avec la table § Renommages.** `automaton_state_as_string` devait devenir `to_string` ;
sur une classe, `self#to_string` se lit « chaîne représentant le composant », pas son état. Elle
est devenue `state_as_string` (son ancien nom citait `automaton_state`, champ disparu), et le nom
court `to_string` est réservé à la fonction du module. `string_of_simulated_device_state` est
devenue `icon_suffix_of_state` comme prévu — c'est le seul renommage qui déborde sur les sept
composants, via leur méthode `dotImg`.

**Aucun `.ml` de composant n'est touché par la fusion.** Les redéfinitions de `machine.ml:715,742`,
`router.ml:1169,1192` et `cable.ml:779,783` **délèguent** au parent, et `cable.ml:888-896`
redéfinit les `can_*` par des constantes : pas une ne lit l'état. *(Ces trois constantes ont été
levées à l'épisode 8 ; le constat ci-dessus décrit l'état du code à l'épisode 7.)*

**Preuve GUI.**

| Journal | Scénario | Résultat |
|---|---|---|
| 61 | `propre-2machines-1hub`, `-r`, puis suspendre `m1`, la reprendre, l'arrêter, « Tout éteindre » (brutal), quitter sans sauvegarder | **15/15 tâches réussies**, **0** `ForbiddenTransition`, **0** `Assertion failed`, **0** `CRITICAL`, aucun processus de simulation résiduel. Les cinq `*_right_now` réécrits ont tous tourné : `create` ×5, `startup` ×5, `suspend` ×1, `resume` ×1, `gracefully_shutdown` ×2, `poweroff` ×3, `destroy` ×18 |

**Le scénario a dû être adapté à la GUI réelle** — le plan supposait des clics droits sur le
dessin. Le dessin est un **PNG graphviz non interactif** : les actions passent par la barre
verticale **gauche** (icône du type de composant → action → choix du composant, donc
action-puis-objet), les actions collectives par la barre horizontale **basse**, et l'extinction
brutale d'un seul composant **n'existe pas** (seul le « Tout éteindre » collectif la déclenche).
La barre verticale **droite** porte les options dot. Consigné dans `bin/gui/CLAUDE.md` pour que
les prochains scénarios de test partent du bon modèle d'interaction.

**Reste au chantier** : la cause profonde de la lecture décalée de 8 octets (épisode 6, point 1),
le retrait de l'instrumentation `B6:` de l'épisode 2, et l'arbitrage B4 (le disque COW ajouté au
treeview *history* au démarrage salit légitimement le projet).

---

### Épisode 8 — 2026-07-31 — B5, un câble ne s'édite plus en marche

Dernier point de conception encore ouvert : **B5**, que l'épisode 7 n'avait pas traité (il a
refondu le *type*, pas les câbles). Les deux écarts de B5 se tiennent, et l'ordre entre eux n'est
pas indifférent.

**Ce que la lecture du code a établi avant d'écrire quoi que ce soit.** Les trois surcharges
`can_startup`, `can_gracefully_shutdown` et `can_poweroff` forcées à `true` (`cable.ml:887-890`,
chacune portant « *To do: try reverting this* ») n'ont **aucun lecteur** : `#startup`,
`#gracefully_shutdown` et `#poweroff` ne sont jamais invoqués sur un câble — la palette n'offre
pas ces actions pour les câbles, `startup_everything`/`shutdown_everything`/`poweroff_everything`
(`state.ml:909-923`) et `marionnet.ml:116` passent par `get_node_by_name`, et le cycle du
processus d'un câble est piloté par le compteur de références (`increment_alive_endpoint_no`
appelle `startup_right_now` **directement**, sans garde). Conséquence : **lever ces trois
constantes, seul, est un no-op observable**. Leur seul rôle réel était de rendre inopérant tout
alignement du `dynlist` — ce que l'audit avait vu (« l'écart est masqué par… »).

**Correctif, en trois gestes, dans le seul `bin/cable.ml`.**

1. Les trois surcharges sont supprimées : les câbles héritent des prédicats **dépendant de
   l'état** (`user_level.ml:417-435`). Un commentaire garde la trace du « To do » levé et de la
   raison pour laquelle la levée est sûre.
2. Le `dynlist` est **scindé**. `Properties.all_names ()` garde la liste brute (tous les câbles du
   type) ; `Properties.dynlist ()` la filtre sur `can_startup`, et c'est elle que `Properties` et
   `Remove` emploient — comme les sept autres composants, qui filtrent sur
   `get_node_names_that_can_startup`. **Le découplage est indispensable** : `Disconnect` et
   `Reconnect` composaient leur propre filtre **sur `Properties.dynlist ()`** (`cable.ml:199,213`)
   ; les laisser tels quels aurait fait disparaître « Débrancher » sur un câble en marche,
   c'est-à-dire exactement le geste que l'utilisateur veut faire. Ils partent désormais de
   `all_names ()`.
3. Le commentaire de `Properties.reaction` est réécrit. Le risque de second
   `Simulation_level.ethernet_cable` sur les mêmes hublets est **fermé par inatteignabilité**, non
   par séquencement : un câble proposé à la modification n'a plus de processus, il n'y a donc plus
   rien à ordonner. Le séquencement reste refusé pour la raison des épisodes 1 et 5 (prendre le
   `Recursive_mutex` depuis le thread GTK, ou différer la re-création après le dialogue). Fenêtre
   résiduelle assumée et documentée : le câble démarre entre l'ouverture du menu et la validation
   du dialogue.

**Effet visible, borné.** Simulation en marche, un câble dont les **deux** extrémités tournent
quitte les menus « Modifier » et « Supprimer » ; il y revient dès qu'on le débranche ou qu'on
éteint un bout. Restent modifiables en toute circonstance : le câble à une seule extrémité
allumée, le câble débranché, et le câble de mauvaise *crossoverness* — ce dernier parce que
`is_correct` lui refuse le démarrage (`user_level.ml:320`), donc il reste `No_device`. Aucun état,
aucune transition, aucun `.mli`, aucun rendu `dot` ne changent : le dessin n'a jamais représenté
qu'une arête entre deux nœuds, et le seul cas « débranché » qu'il connaît (`style=dashed` si
`not is_connected`, `cable.ml:496`) est inchangé.

**Instrumentation permanente, à la demande de l'auteur** (`bin/gui/menu_factory.ml:247`). Un
journal de run disait ce que l'utilisateur **avait fait**, jamais ce qui lui **était proposé** —
or c'est le seul effet observable des prédicats `can_*`. `Make_entry_with_children.item_callback`
journalise donc la liste rendue par `E.dynlist ()` à chaque dépliage de menu. Le point est
**unique** : tous les composants et toutes les actions en bénéficient, sans toucher les huit
fichiers. Log ordinaire (pas de `~force:true`) : visible en `-d`, muet en usage normal ; il est
destiné à **rester**, contrairement à l'instrumentation `B6:` de l'épisode 2.

**Preuve GUI.**

| Journal | Scénario | Résultat |
|---|---|---|
| 62 | `propre-2machines-1hub` : tout démarrer, débrancher `d1`, ouvrir « Modifier » sur `d1` (annulé), rebrancher, re-débrancher, **modifier** `d1` en déplaçant son extrémité gauche de `H1 port1` vers `S1 port1`, tout arrêter, quitter sans sauvegarder | **0** `ForbiddenTransition`, `Assertion`, `CRITICAL`, `id_to_iter` ou exception sur 1228 lignes ; sortie propre, aucun processus résiduel. Mesure directe de B5(c) : le nouveau `d1` est créé (l. 864-869) **avant** que le `destroy d1` de l'ancien ne s'exécute (l. 870-874) — l'ordre incriminé est bien réel — mais le nouveau naît à refcount **2**, donc **aucun second processus n'a pu démarrer** |
| 63 | même projet, avec le log des `dynlist` : déplier « Modifier »/« Supprimer »/« Débrancher » **en marche**, tout arrêter, les redéplier | Preuve écrite et **bidirectionnelle**. En marche (l. 664-668) : `Menu "Modifier": proposing nothing`, `Menu "Supprimer": proposing nothing`, `Menu "Débrancher brutalement": proposing [d1; d2]`. Après arrêt (l. 803-809) : `Modifier` et `Supprimer` proposent de nouveau `[d1; d2]`, `Rebrancher` ne propose `nothing`. **0** erreur, sortie propre |

**Constat révélé par le log, hors périmètre.** À l'arrêt (journal 63, l. 807), « Débrancher
brutalement » propose encore `[d1; d2]` : `can_suspend` d'un câble teste `!connected`
(`cable.ml:892-898`) et **ignore l'état du processus**, si bien qu'on peut « débrancher » un câble
dont les deux nœuds sont éteints. Comportement **préexistant**, inchangé ici, et sans conséquence
persistante (`connected` n'est pas dans le `.mar`) — consigné comme reliquat, pas corrigé : il
demanderait de décider ce que « débranché » signifie sur un réseau à l'arrêt.

**Reste au chantier** : la cause profonde de la lecture décalée de 8 octets (épisode 6, point 1),
le retrait de l'instrumentation `B6:` de l'épisode 2, l'arbitrage B4, et le `can_suspend` des
câbles ci-dessus.

---

### Épisode 9 — 2026-07-31 — le gel à la fermeture d'un projet : le master lock du runtime

Signalement de terrain, hors plan : *Projet → Fermer* fige l'application entière. La fenêtre reste
affichée, les widgets grisés, aucun menu ne répond, et seul le gestionnaire de fenêtres en vient à
bout. L'auteur l'a d'abord relié à l'onglet *Disques* (journal 16), puis, journal 18 à l'appui, à
la **répétition** (la première fermeture passe, la seconde gèle). Ni l'une ni l'autre lecture
n'était la bonne : les deux ne faisaient que rendre la condition réelle plus probable.

**Ce que les journaux établissent, avant toute hypothèse.** Aucune exception, aucune trace
d'erreur sur 939 puis 621 lignes : le processus se tait, il ne meurt pas. Le grisage n'est pas le
bug — c'est le comportement normal du projet fermé (`motherboard_builder.ml:89-93`, `active=false`).
Les deux journaux s'arrêtent sur la **même** signature : le thread de fermeture au message
`B6: [states-forest] Treeview#remove_subtree`, c'est-à-dire entre le log (`treeview.ml:1473`) et
`self#store#remove` (`treeview.ml:1497`) ; le thread principal, lui, au log de
`update_cable_menu_entries_sensitiveness` (`motherboard_builder.ml:121`).

**La mesure, décisive, et contraire à deux des trois hypothèses.** `top -H` sur le processus figé :
**0 % de CPU sur les 27 threads** — interblocage franc, pas de boucle. `wchan` : le thread
principal est en `futex_wait_queue`, pas en `do_poll` — il n'est donc pas bloqué sur la connexion
X, ce qui écartait l'hypothèse « deux threads dans Xlib ». `gdb -p … -ex 'thread apply all bt'`
donne le reste, sans ambiguïté : le thread de fermeture porte la pile complète
`state.ml:340` → `user_level.ml:1603-1605` (`node#destroy`) → `treeview_history.ml:179` →
`treeview.ml:1497` (`store#remove`) → `gtk_tree_store_remove` → `g_signal_emit` → `marshal`
(`ml_gobject.c:205`) → **`st_masterlock_acquire`**.

**Cause racine.** `close_project` s'exécute dans un thread dédié (`state.ml:355-358`) — il le doit,
puisqu'il attend le task runner (`state.ml:344`) — et de là il appelle GTK **directement**,
en violation de l'invariant du projet (« GTK depuis le seul thread principal, sinon `gMain_actor` »).
`gtk_tree_store_remove` émet un signal, car retirer une ligne déplace le curseur et la sélection ;
lablgtk doit alors rappeler du code OCaml et, dans son trampoline `marshal`, réclame le **master
lock du runtime** — que ce thread **détient déjà**, et qui n'est pas réentrant. Le thread s'attend
lui-même indéfiniment, `busy` ne retombe jamais à 0, et tous les autres threads OCaml s'empilent
derrière : thread principal (au retour de son `poll`), threads de `Cortex` (`cortex.ml:411`),
task runner (`message_passing.ml:53`), threads de simulation. D'où un gel **total, silencieux et
sans CPU**. Le caractère erratique s'explique alors seul : il faut qu'un **callback OCaml soit
connecté au signal émis**, donc que la ligne détruite porte la sélection, le curseur, ou une
expansion. Le treeview *history* est celui que l'utilisateur clique — d'où sa surreprésentation ;
les treeviews *defects* et *ifconfig*, jamais cliqués, se laissaient vider sans incident dans les
mêmes journaux.

**Contre-exemple qui valide le correctif avant de l'écrire.** « Remove this document »
(`treeview_documents.ml:314-322`) et `delete_state` (`treeview_history.ml:263`) suppriment la ligne
**sélectionnée**, depuis un callback de menu, donc dans le thread principal — et ces fonctions
marchent au quotidien. Le régime « mutation depuis le thread principal » est donc sain ; seul le
régime « thread secondaire » casse.

**Correctif, dans le seul `bin/treeview.ml` (+31/−4).** Les trois méthodes qui mutent le modèle
GTK — `remove_row`, `remove_subtree`, `clear` — deviennent des enveloppes autour de corps privés
inchangés, et passent par `GMain_actor.apply_extract`. Deux points méritent d'être notés :

1. **`apply_extract`, et non `delegate`.** `delegate` synchrone se réduit à `apply f x |> ignore`
   (`gMain_actor.ml:126`) : il **jette l'`Either`**, donc avale l'exception. L'employer aurait
   ressuscité en silence le « tâche réussie qui a pourtant levé » corrigé à l'épisode 5, et privé
   `remove_subtree_by_name` de l'échec qu'il journalise. `apply_extract` relance dans le thread
   appelant : la sémantique des trois méthodes est **exactement** celle de l'appel direct.
2. **Coût nul sur les chemins normaux.** `apply` applique la fonction sur place quand l'appelant
   est déjà le thread principal (`gMain_actor.ml:82`) : les callbacks de menu ne paient rien, et
   l'imbrication `remove_row` → `clear` est sûre (le corps privé `private_clear` est appelé
   directement).

Vérifié aussi, contre le risque d'interblocage inverse : les deux seuls sites qui attendent le
task runner (`state.ml:344`, `user_level.ml:1613`) sont dans le chemin de fermeture, hors thread
principal — le thread principal n'attend jamais un thread qui délègue.

**Preuve GUI.**

| Journal | Scénario | Résultat |
|---|---|---|
| 19 | reproduction avant correctif, puis capture sur le processus figé | `top -H` : 0 % CPU sur 27 threads ; `gdb` : pile complète ci-dessus, 6 threads en `st_masterlock_acquire` |
| 20 | après correctif : 4 cycles ouvrir/fermer, curseur posé dans l'onglet *Disques* avant chaque fermeture, puis le scénario complet (tout démarrer, tout arrêter, enregistrer sous, fermer) | **4 fermetures explicites → 4 `state#close_project: END. Success.`**, aucun gel. Le 5ᵉ `BEGIN` sans `END` est la fermeture implicite du *quit* : le journal se poursuit jusqu'à `at_exit: killing all orphans` puis `Thread Exiting (main)` — sortie propre |

**Deux anomalies relevées dans le journal 20, non corrigées.** (a) Huit `Icon lookup failed` sur
des valeurs corrompues (`"…hc  -cable"`, `"…hc  vice-port"` : début écrasé, fin de chaîne
correcte) — signature exacte de la lecture décalée de 8 octets de l'épisode 6, préexistante et
toujours non élucidée ; le journal 20 est trois fois plus long et enchaîne quatre cycles, la hausse
du compte n'est donc pas imputable au correctif, le renderer tournant dans le thread principal
avant comme après. (b) Deux `Warning: exception raised in really_refresh_sketch:
Failure(state.ml:123)` = `Option.extract` sur un `root_pathname` devenu `None` : un rafraîchissement
du dessin s'exécute après `unset_filename`, première instruction de `close_project`. Défaut
d'ordonnancement préexistant, **rendu atteignable parce que la fermeture aboutit désormais** ;
l'exception est attrapée et le dessin est vidé juste après.

**Rattachement.** Cet interblocage est le candidat **C5** (« deadlock GTK fermeture projet ») du
rapport `docs/bug-critique-crash-host.md` : il est désormais **caractérisé et corrigé**, et il
n'était pas une cause de crash de l'hôte (le processus se fige, il ne tue rien).

**Risques latents laissés en place**, même violation, autres appels, jamais observés jusqu'ici :
`self#mainwin#sketch#set_file ""` (`state.ml:342`) et `ledgrid_manager#reset`, appelés depuis le
thread de fermeture ; et `Treeview#detach_view_in`, qui utilise `delegate` et avale donc les
exceptions.

**Reste au chantier** : inchangé — la cause profonde de la lecture décalée de 8 octets
(épisode 6, point 1), le retrait de l'instrumentation `B6:` de l'épisode 2, l'arbitrage B4, et le
`can_suspend` des câbles (épisode 8).

---

### Épisode 10 — 2026-08-01 — les frères du gel : audit des appels GTK hors thread principal

L'épisode 9 a corrigé **un** site. La question suivante s'imposait : combien d'autres attendent leur
tour ? Audit sur `bin/`, `bin/gui/` et les couches GTK de `lib/`, puis correction de la seule classe
dont les trois conditions sont réunies.

**Le critère, et sa condition discriminante.** Le gel exige **trois** choses simultanément :
(1) un thread ≠ principal, (2) un appel GTK qui émet un signal **synchronement**, (3) un callback
OCaml **connecté** à ce signal. La condition (2) est celle qui trie, et elle n'est pas intuitive :
`#run ()` d'un dialogue **ne gèle pas** par ce mécanisme, parce que sa boucle imbriquée repasse par
`ml_poll` (`ml_glib.c:319`), lequel **relâche** le master lock avant de dormir ; `store#remove`,
`view#collapse_row` ou `#destroy`, eux, émettent **dans l'appel**, sans jamais rendre le lock. Un
audit qui se contenterait de chercher « du GTK dans un thread » classerait donc mal les deux tiers
des sites.

**Classe A — corrigée ici.** `expand_row`, `expand_everything`, `collapse_everything` et
`collapse_row` (`treeview.ml`) agissent sur la **vue**, dont les signaux `row-expanded` et
`row-collapsed` **sont connectés** (`on_row_expand`/`on_row_collapse`, branchés dans
l'`initializer`). Les trois conditions sont réunies, et les appelants concernés ne sont pas
théoriques :

| Appelant | Thread | Fréquence |
|---|---|---|
| `treeview_history.ml:242` (`add_substate_of`) | **task runner**, via `user_level.ml:1424` ← `machine.ml:672` / `router.ml:1115` ← `create_right_now` (`user_level.ml:204`) | à **chaque** démarrage de machine ou de routeur |
| `treeview.ml:1180` (`add_row` replie la ligne qu'il vient de créer) | idem | toute addition de ligne hors thread principal |
| `treeview_defects.ml:204,240` · `treeview_ifconfig.ml:177` | idem | création d'un composant, chargement de projet |

Ce chemin était **déjà attesté** sans avoir été reconnu comme tel : l'échec `id_to_iter` des
épisodes 4-5 s'est produit exactement dans `add_substate_of → collapse_row`, depuis le task runner.
Ce qui a empêché le gel jusqu'ici est une propriété de Gtk+ : **le signal n'est émis que si l'état
change**. Replier une ligne déjà repliée — le cas courant, et le commentaire de
`treeview_history.ml` le dit — n'émet rien. Il suffit d'un arbre déployé au mauvais moment pour
perdre le processus : même profil erratique que le gel de fermeture avant qu'on ne le comprenne.
Correctif : les 4 méthodes passent par `GMain_actor.apply_extract`, ce qui protège leurs **12**
appelants sans en toucher un seul (vérifié : aucun `view#expand_*`/`view#collapse_*` ne les
contourne).

**Classe B — inventoriée, non corrigée** (décision de l'auteur : audit d'abord). Appels GTK hors
thread principal dont on n'a **pas** établi qu'ils émettent vers un callback connecté : gel non
démontré, mais violation de l'invariant de concurrence et exposition X11 réelle.
`bin/gui/simple_dialogs.ml` n'utilise **aucun** `GMain_actor` — `message`, donc `error`/`warning`/
`info`/`help`, construit le dialogue et enchaîne ses `set_*` dans le thread appelant :

| Site | Thread | Déclencheur |
|---|---|---|
| `simulation_level.ml:1468` (`execute_the_unexpected_death_callback`) | **thread du death monitor** (`death_monitor.ml:188-192`) | mort inattendue d'un processus — survient à n'importe quel instant |
| `user_level.ml:190` | task runner | échec d'une tâche (le *progress bar*, lui, est protégé : il passe par `Progress_bar`) |
| `state.ml:464,518,530,565,824` | threads open/save/close | chargement ou sauvegarde en erreur |
| `gui_menubar_MARIONNET.ml:194,323` | threads d'actions de menu (5 `Thread.create`) | échec d'un « Enregistrer sous », etc. |
| `ledgrid_manager.ml:182-192` (`#misc#hide`, `#destroy`) | close_project / task runner | fermeture de projet, destruction de composant |
| `state.ml:342` (`sketch#set_file ""`) · `gui_bricks.ml:1006` (`set_sensitive`) | close_project / thread `Egg.wait` | déjà relevés à l'épisode 9 |

Si l'on décide de traiter cette classe, le point d'étranglement est étroit : envelopper les
**4 constructeurs** de `simple_dialogs.ml` couvre d'un coup une dizaine de sites d'appel.

**Classe C — les patrons corrects**, qui montrent que la règle était connue et seulement appliquée
par endroits : `progress_bar.ml` (`apply_extract` à la création, `delegate` pour `show`/`destroy`),
`state.ml:807` (`really_refresh_sketch`), `state.ml:852` (`network_change`), et **toutes** les
réactions Cortex de `motherboard_builder.ml` — ce qui compte double, puisque Cortex exécute chaque
réaction dans un thread jeté (`cortex.ml:310-313`).

**Non tranché, faute de mesure** : `store#append`/`store#set` (`treeview.ml:1147,1155,371,503,683`)
déclenchent-ils le `cell_data_func` du renderer d'icônes **synchronement** ? En Gtk+ 3 la
revalidation passe normalement par un *idle*, auquel cas la condition (2) n'est pas remplie. Cela
se vérifie par mesure, pas par lecture — et cela conditionne le classement des méthodes d'ajout.

**Vérification, et ce qu'elle ne couvre pas.** `dune build` rc=0 ; `make rebuild
install-for-testing` rc=0 ; vérifié aussi qu'aucun appel ne contourne les 4 méthodes (les seuls
`view#expand_*`/`view#collapse_*` du dépôt sont leurs corps). Le correctif est **préventif** : son
succès ne se prouve pas par un run vert, puisque le déclencheur — replier, depuis le task runner,
une ligne réellement dépliée — est rare par construction. **Non joué à ce stade** : le rejeu GUI de
non-régression sur les chemins où ces méthodes servent au quotidien (boutons « tout déplier / tout
replier » de chaque treeview, repli automatique à la création des lignes, démarrage d'une machine
avec l'onglet *Disques* déployé). À faire au prochain run.

**Reste au chantier** : inchangé (épisode 8), plus l'arbitrage sur la **classe B** ci-dessus.

---

### Épisode 11 — 2026-08-01 — la classe B, et le verrou qu'il fallait enfermer avec

Arbitrage rendu : la classe B est corrigée. Quatre fichiers, aucun changement de comportement
attendu — `apply_extract` applique sur place quand l'appelant **est** le thread principal, ce qui
est le cas de la grande majorité des sites d'appel existants.

**`bin/gui/simple_dialogs.ml` — les 4 constructeurs.** `message` (donc `error`, `warning`, `info`,
`help`), `recapitulative`, `confirm_dialog` et `ask_text_dialog` enveloppent désormais leur corps.
Un seul point pour `message` couvre les quatre fonctions dérivées, soit une quinzaine de sites
d'appel — dont les trois qui comptent, parce qu'ils se déclenchent **quand quelque chose vient
déjà de mal tourner** : le thread du *death monitor* qui prévient d'une mort inattendue de
processus (`simulation_level.ml:1468`), la tâche du task runner qui a échoué (`user_level.ml:190`),
et les threads open/save/close et d'actions de menu qui rapportent leurs erreurs. `confirm_dialog`
est enveloppé bien qu'il ne fût **pas** un candidat au gel (son `#run ()` repasse par `ml_poll`,
qui relâche le master lock) : sa construction, elle, l'était, et une boucle imbriquée lancée par un
thread secondaire pendant que le thread principal tourne la sienne est une course qu'on préfère ne
pas avoir à réexaminer.

**`bin/gui/ledgrid_manager.ml` — 7 méthodes, verrou compris.** C'est le cas le plus permanent du
programme : le **thread blinker** fait clignoter les LED pendant toute la vie d'une simulation, et
`#reset` est appelé par le thread de fermeture. Le point délicat est le `Mutex` interne : n'envelopper
que les appels de widgets aurait fait qu'un thread **détient ce mutex pendant qu'il attend le thread
principal** — exactement la forme de deadlock refusée à l'épisode 5. L'enrobage englobe donc
`lock` et `unlock` : le mutex n'est plus jamais pris que par le thread principal, il ne peut plus
entrer dans un cycle. `flash` reste **synchrone** délibérément (`apply_extract`, pas
`delegate ~async`) : cela donne au blinker une contre-pression naturelle au lieu d'empiler des
*idle* dans la boucle principale, et les threads OCaml étaient de toute façon déjà sérialisés par
le master lock — rien n'est perdu en parallélisme.

**Deux sites isolés** : `state.ml:342` (`sketch#set_file ""`, dans le thread de fermeture) et le
thread de `gui_bricks.ml` (les deux mises à jour de sensibilité des boutons ; `Egg.wait`, raison
d'être du thread, reste évidemment dehors).

**Trouvé en chemin, signalé, non corrigé.** (a) `make_device_ledgrid` prend le verrou puis appelle
`set_port_connection_state`, qui le **reprend** — `Mutex.lock` n'est pas récursif, donc un
`~connected_ports` non vide s'auto-bloquerait. Cela n'arrive pas aujourd'hui (la liste est toujours
vide à cet endroit) et le corriger suppose de trancher entre mutex récursif et variante interne non
verrouillée : décision séparée, pas un effet de bord de celle-ci. (b) `Treeview#detach_view_in`
utilise `delegate`, qui **jette l'`Either`** : le `raise e` de `private_detach_view_in`
(`treeview.ml:1747`), écrit pour signaler l'échec du *thunk* après restauration du modèle, est donc
**mort** — aucun appelant ne l'a jamais vu. Le correctif est d'une ligne (`apply_extract`), mais il
change la **propagation des erreurs**, pas la discipline de thread : à décider à part.

**Vérification.** `dune build` rc=0 sur chacune des trois étapes (dialogues, ledgrid, sites
isolés), puis `make rebuild install-for-testing` rc=0.

**Rejeu GUI joué le 2026-08-01, journal 22** (1054 lignes) : **0** exception, `CRITICAL`,
`ForbiddenTransition` ou assertion ; LED grid complet et sain — création de `H1` puis `S1`,
connexions de ports, destructions, *blinker* qui reçoit son « please-die » et sort proprement —
avec **0** `failed in set_port_connection_state` (le journal 16 en avait) ; sortie propre. La
mesure qui compte est ailleurs : **toutes** les lignes `ledgrid_manager` portent désormais le
thread **`.0`**, le thread principal, là où le journal 16 les montrait émises par le thread de
fermeture (`[…​.351] Making the port 0 of device 1 disconnected`). C'est la preuve directe que
l'enrobage fait ce qu'il annonce, et l'auteur confirme que le ledgrid se comporte comme avant.
**Reste non exercé** : aucun `Simple_dialogs.error/warning` n'a été déclenché depuis un thread
secondaire dans ce run (les 4 « Dialog result » sont des dialogues de composants, ouverts depuis le
thread principal) — le chemin *death monitor* / tâche en échec attend toujours sa preuve terrain.

---

### Épisode 12 — 2026-08-01 — B5 révisé : un câble s'édite **en marche**

Cet épisode **annule pour partie l'épisode 8**, sur décision de l'auteur : un câble doit pouvoir
être **modifié ou supprimé pendant qu'il « tourne »**.

**Pourquoi l'alignement était une erreur.** L'épisode 8 avait filtré le `dynlist` des câbles sur
`can_startup`, « comme les sept autres composants ». Or un câble n'est pas un composant comme les
autres : dans la réalité, on déplace un câble d'un hub vers un switch **sans éteindre les
machines** — on débranche, on rebranche ailleurs. En interdisant « Modifier » et « Supprimer » sur
un câble en marche, l'épisode 8 a rendu ce geste impossible dans la GUI, alors qu'il est trivial
avec du matériel réel. **Preuve de la régression, journal 22** : quatorze dépliages de « Modifier »
et « Supprimer » sur les câbles, tous `proposing nothing` (l. 685-742), pendant que « Arrêter »
proposait `[H1]` (l. 746) — enregistrés par l'instrumentation permanente des `dynlist` que
l'épisode 8 avait justement ajoutée pour cela.

**La règle générale qui en découle**, désormais inscrite dans `CLAUDE.md` : toute question de
câblage via la GUI se tranche par **ce qui est possible dans la réalité**, dans les limites de la
virtualisation ; la symétrie entre composants n'est pas un argument.

**Ce qui rendait la révision non triviale.** Rendre les deux menus totaux **rouvre B5(c)**, que
l'épisode 8 avait clos « par inatteignabilité » : `Properties.reaction` fait `c#destroy;
Add.reaction r`, or `#destroy` ne fait qu'**enfiler** `destroy_right_now` (`user_level.ml:206-209`)
tandis que le remplaçant est construit **synchroniquement** et démarre aussitôt son processus sur
des hublets encore tenus par l'ancien. Les épisodes 1, 5 et 8 avaient refusé de séquencer pour deux
raisons : prendre le `Recursive_mutex` depuis le thread GTK (deadlock contre un thread du task
runner qui attend ce même thread, cf. C4), ou différer la re-création après le dialogue.

**Le fait qui débloque.** Aucune des deux n'est nécessaire : le task runner est une **file
séquentielle consommée par un unique thread** (`task_runner.ml:66-101`), et `st#network_change`
passe **déjà** par `GMain_actor.delegate` (`state.ml:852-863`), qui sans `~async` **attend** le
thread principal. Il suffit donc d'**enfiler la re-création derrière la destruction** : l'ordre est
imposé par la file, aucun verrou n'est pris depuis le thread GTK, et rien n'est différé après le
dialogue. Le journal le montre littéralement — la destruction est exécutée par le thread `.8` (le
task runner), la re-création par le thread `.0` (GTK) auquel il délègue et qu'il attend.

**Correctif, dans le seul `bin/cable.ml`** (plus un commentaire de `menu_factory.ml`) :

1. `Properties.dynlist` redevient `all_names ()` : les deux menus voient tous les câbles du type,
   quel que soit leur état. `Remove.dynlist` suit ; `Disconnect`/`Reconnect`, qui partaient déjà de
   `all_names ()`, sont inchangés.
2. `Properties.reaction` : `c#destroy` puis
   `Task_runner.the_task_runner#schedule ~name:("re-create the cable "^r.name) (fun () -> Add.reaction r)`.
3. Les trois `can_* = true` supprimées à l'épisode 8 **ne reviennent pas** ; le commentaire qui les
   remplaçait est corrigé, car il n'est plus vrai : pour les câbles, ces prédicats hérités n'ont
   désormais **plus aucun lecteur**.

**Effets assumés.** La re-création devient asynchrone pour **tous** les câbles, arrêtés compris
(bref clignotement dans le dessin et les treeviews) ; un échec de `Add.reaction` est journalisé par
le task runner (« THIS MAY BE SERIOUS ») au lieu de remonter dans le thread GTK, l'ancien câble
ayant déjà disparu ; et modifier un câble en marche **coupe brièvement le lien** — c'est exactement
le geste réel, aucun dialogue d'avertissement n'est ajouté.

**Preuve GUI, journal 24** (`propre-2machines-1hub` + un switch `S1` ajouté, tout démarré).

| Mesure | Ce que le journal montre |
|---|---|
| Les menus voient de nouveau les câbles en marche | `Menu "Modifier": proposing [d1; d2]` et `Menu "Supprimer": proposing [d1; d2]`, l. 886-893, simulation en marche — l'exact inverse du journal 22 |
| L'ordre est imposé (B5(c)) | Trois modifications de `d1` : l. 712-740, 775-822, 853-879. Chaque fois la tâche `destroy d1` est **exécutée jusqu'au bout** (`the on/sleeping device d1. Powering it off first…`, `wirefilter` attendu par `waitpid`, hublets détruits, `destroyed with success`) **avant** que la tâche `re-create the cable d1` ne commence |
| Le cas critique est exercé | À la 2ᵉ modification (l. 781-822) le remplaçant atteint le refcount **3** et **démarre son propre `wirefilter`** (pid 2349506) : le nouveau processus naît bien sur des hublets libérés, jamais en concurrence avec l'ancien |
| Supprimer un câble en marche | l. 889-900 : `d2` supprimé alors qu'il tourne (`destroying the on/sleeping device d2. Powering it off first…`), sans incident — même chemin que l'arrêt d'un nœud |
| Sortie | `destroy_process_before_quitting: END (success)` ; **aucun** processus résiduel du répertoire de run (`/tmp/marionnet-819180832.dir`) ; **0** `ForbiddenTransition`, `Assertion`, `id_to_iter`, ni tâche en échec sur 1727 lignes |

**Constat annexe, à ne pas passer sous silence.** Ce run porte **9** occurrences de
`Treeview.icon_column#lookup: ERROR: icon name lookup failed` (l. 1250-1386), **absentes** des
journaux 22 et 23. Les valeurs lues y sont corrompues d'une façon caractéristique — préfixe binaire
et **fin de chaîne correcte** (`"…b  -cable"`) : c'est la **signature de la lecture décalée de
8 octets** de l'épisode 6, cause profonde connue et toujours non élucidée. Elle se manifeste ici en
mode dégradé bénin (cellule vide dessinée, `append_to_view: WARNING`) précisément parce que
l'épisode 6 a rendu ce renderer total. Rien ne permet d'imputer ces lectures au séquencement
introduit ici — le run 24 enchaîne simplement bien plus de mutations du treeview *defects* (quatre
`remove_subtree` et quatre `add_cable` de câbles) que les runs 22 et 23 — mais rien ne permet non
plus de l'exclure : c'est une raison de plus de traiter ce reliquat.

**Reste au chantier** : la cause profonde de la lecture décalée (épisode 6, point 1, désormais
observée aussi dans ce run), le retrait de l'instrumentation `B6:` de l'épisode 2, et l'arbitrage
B4. Le reliquat `can_suspend` de l'épisode 8 (« on peut débrancher un câble dont les deux nœuds sont
éteints ») **se referme par la règle de projet** : dans la réalité, on débranche parfaitement un
câble d'une machine éteinte — le comportement est légitime, il n'y a rien à corriger.

---

### Épisode 13 — 2026-08-02 — les **ajouts** au modèle Gtk+ rejoignent le thread principal

L'épisode 10 avait corrigé la classe A, l'épisode 11 la classe B ; la **classe C n'était pas une
classe à corriger** — c'est l'inventaire des patrons déjà corrects. Ce qui restait ouvert du volet
« frères du gel » était le point laissé **« non tranché, faute de mesure »** : `store#append` et
`store#set` déclenchent-ils le `cell_data_func` du renderer d'icônes **synchronement** ? De la
réponse dépendait le classement des méthodes d'**ajout**, seules mutations du modèle encore nues
alors que les **suppressions** sont enrobées depuis l'épisode 9.

**Pourquoi la mesure demandée n'aurait pas tranché.** Elle est indécidable dans la direction qui
compte. Si ce callback OCaml était bien invoqué dans l'appel depuis un thread secondaire, le
trampoline `marshal` réclamerait le master lock déjà détenu par ce thread : le processus **gèlerait
avant d'écrire quoi que ce soit** dans le journal. On ne peut instrumenter sans risque que depuis le
thread principal, où une observation positive prouverait le danger mais où une observation négative
ne prouverait rien. Comme l'invariant du projet exige déjà que tout appel GTK parte du thread
principal, et comme `GMain_actor.apply` **applique sur place** quand l'appelant *est* ce thread
(`gMain_actor.ml:82`), l'enrobage ne coûte rien sur les chemins courants : on enrobe au lieu de
mesurer. Aucun `Mutex` dans `treeview.ml` — le piège « détenir un verrou en attendant le thread
principal » de l'épisode 11 ne s'applique pas ici.

**Correctif, `bin/treeview.ml` seul, 5 méthodes, aucun appelant touché** (mêmes patron et
justification qu'à l'épisode 9, dont le long commentaire fait référence) :

| Méthode | Ce qu'elle mute | Ce que l'enrobage couvre |
|---|---|---|
| `add_complete_row_with_no_checking` | `store#append` + `store#set` + n × `column#set` | `add_row` des 4 treeviews ; `private_remove_row`, déjà enrobé, donne une imbrication appliquée sur place |
| `set_complete_forest` | `store#append` + n × `column#set` (et un `self#clear` lui-même enrobé) | `set_forest`, `load`, `set_row`, `set_row_field`, `set_{String,Icon,CheckBox}_field`, `update_String_field` |
| `highlight_row`, `unhighlight_row`, `set_row_highlight_color` | `column#set` → `store#set`, **hors** des deux méthodes ci-dessus | `treeview_history.ml:214,228,281,283`, appelés depuis le **task runner** au démarrage d'une machine ; `treeview_defects.ml:452,455` |

Les deux méthodes basses gardent leur corps intact, renommé `private_…`, et l'ancien nom devient
l'enrobage — le diff est de 39 lignes, dont l'essentiel est du commentaire. `apply_extract`, jamais
`delegate` : la propagation des exceptions reste celle d'avant.

**Vérification.** `dune build` rc=0 ; `make rebuild install-for-testing` rc=0.

**Rejeu GUI joué le 2026-08-02, journal 25** (1386 lignes ; deux cycles ouvrir/fermer), scénario
choisi pour exercer les cinq méthodes **et** solder le rejeu que l'épisode 10 avait laissé non
joué : chargement de projet, « tout déplier / tout replier » dans les 4 onglets, démarrage d'une
machine avec l'onglet *Disques* déployé, ajout d'une machine et d'un câble, édition d'un champ de
*Défauts*, suppression d'un composant en marche, sortie.

| Mesure | Résultat |
|---|---|
| Gel | aucun ; les deux cycles finissent en `destroy_process_before_quitting: END (success)` et les threads sortent proprement |
| `id_to_iter … not found`, `ForbiddenTransition`, assertion, `CRITICAL`, tâche « THIS MAY BE SERIOUS » | **0** de chaque |
| Exceptions | **2**, attendues et identiques : `ColumnConstraintViolated("Loss %")` (l. 910-911) — la saisie hors contrainte dans *Défauts* est refusée par le mécanisme prévu, ce qui atteste au passage que `set_row_field` → `set_complete_forest` fonctionne enrobé |
| `failed to create the hostfs_directory` | 4, **préexistantes** (déjà au journal 24), sans rapport |

**Ce que ce run infirme — et c'est l'apport le plus utile.** On pouvait espérer que sérialiser les
mutations avec le rendu ferait disparaître les `icon_column#lookup: ERROR` de la lecture décalée de
8 octets (épisode 6). **Non** : le journal 25 en porte **25**, toutes dans le thread `.0`, toutes
émises au **rendu** (`append_to_view` → `cell_data_func`), avec exactement la signature connue —
préfixe binaire, suffixe lisible intact (`-cable`, `vice-port`, `port`). Le compte brut n'est pas
comparable à celui du journal 24 (9), le scénario 25 sollicitant bien plus le renderer par ses
dépliages en masse ; ce qui compte est **qualitatif** : les mutations partent désormais toutes du
thread principal et la corruption persiste, donc elle **ne provient pas d'une écriture concurrente
au rendu**. Une famille entière d'hypothèses tombe, et le soupçon se déplace sur la **lecture**
elle-même — `model#get ~column` (`treeview.ml:634`). Deux indices vont dans ce sens : les octets
écrasés sont au **nombre de 8**, et leur poids fort est **constant à l'intérieur d'un run** mais
change d'un run à l'autre (`…5C A3 0D` au 25, `…FC 62` au 24), ce qui est la forme d'une **adresse**
d'un tas mmapé sous ASLR. Piste, pas conclusion : à instruire dans un épisode dédié.

**Reste au chantier** : la cause profonde de la lecture décalée (épisode 6, désormais mieux cernée
ci-dessus), le retrait de l'instrumentation `B6:` de l'épisode 2, l'arbitrage B4, et les deux
défauts signalés à l'épisode 11 (mutex non récursif de `make_device_ledgrid`, `raise e` mort de
`detach_view_in`). Le volet « frères du gel », lui, est **clos** : classes A et B corrigées, classe
C sans objet, méthodes d'ajout enrobées.

### Épisode 14 — 2026-08-02 — le GC mis hors de cause, et le widget n'est plus lu du tout

Point de départ : le suspect resserré par l'épisode 13 sur la **lecture** `model#get ~column`.

**L'hypothèse, formée par lecture du chemin complet.** `bin/treeview.ml` (renderer d'icônes) appelle
`GTree.model#get` ; `gTree.ml:85-95` alloue le `GValue` par `Value.create_empty ()`, soit
(`ml_gobject.c:236`) un bloc custom OCaml de 32 octets — donc logeable dans le *minor heap* — qui
contient le `GValue` **en ligne**, `GValue_val` en rendant un pointeur **intérieur**. Or le wrapper
`ML_1 (g_value_get_mlvariant, GValue_val, ID)` (`ml_gobject.c:395`) se développe
(`wrappers.h:178-179`) en `{ return conv (cname (conv1 (arg1))); }` — **sans `CAMLparam1(arg1)`** :
l'argument n'est pas une racine GC pendant l'appel, alors que le corps alloue
(`tmp = Val_option (DATA.v_pointer, copy_string)`, l. 355). D'où l'hypothèse : une valeur déplacée
ou recyclée par un ramassage survenu au mauvais moment.

**Le test, et sa réfutation.** Levier choisi : la pression du GC mineur, réglable sans recompiler
(`OCAMLRUNPARAM=s=`), et discriminant **dans les deux sens**. Réglage vérifié effectivement
appliqué (`Gc.get ()` : 4 096 mots contre 33 554 432, défaut 262 144).

| Run | `minor_heap_size` | GC mineurs | Occurrences | Journal |
|---|---|---|---|---|
| témoin (j. 25) | 2 Mo (défaut) | nominaux | 25 | 1386 l. |
| **A** | **32 Ko** (`s=4k`) | ~64× plus fréquents | **21** | 764 l. |
| **B** | **256 Mo** (`s=32M`) | quasi aucun de toute la session | **43** | 1104 l. |

Si le mécanisme exigeait une promotion par GC mineur, le run B — où presque aucun ramassage n'a
lieu, donc où **aucun bloc n'est recyclé** — en aurait montré zéro. Il en montre le double.
**L'hypothèse est réfutée : le mot écrasé ne vient pas du GC d'OCaml.** C'est le pendant de
l'épisode 13, qui avait éliminé la concurrence d'écriture : deux familles tombées, la cause reste
non élucidée.

**Ce que la mesure établit en revanche, et qui corrige la doc.** Les valeurs d'icônes possibles
étant connues (`treeview_defects.ml:507`, `treeview_ifconfig.ml:393`), on peut confronter longueur
lue et longueur réelle :

| Valeur réelle | Longueur | Valeur lue | Longueur lue |
|---|---|---|---|
| `other-device-port` | 17 | 8 octets + `vice-port` | 17 |
| `machine-port` | 12 | 8 octets + `port` | 12 |
| `straight-cable` | 14 | 8 octets + `-cable` | 14 |
| `rightward` | 9 | 8 octets + `d` | 9 |
| `machine`, `hub`, `switch`, `router` | 3 à 7 | intégralement écrasées | idem |

La longueur est **rigoureusement conservée**. Ce n'est donc **pas un « décalage d'offset »**, comme
l'affirmaient les épisodes 6 et 13 — c'est l'**écrasement in-place du premier mot** d'un bloc par
ailleurs sain. Et la valeur écrite est bien une **adresse** : `0x56A90F……` au run A, `0x5DD0D3……`
au run B, constante à l'intérieur d'un run, variable d'un run à l'autre. Ces plages sont celles du
tas `brk` d'un binaire PIE, et non du tas d'OCaml (mmap, `0x7f……`) — indice, non preuve.

**Le correctif : plus aucune valeur n'est lue dans le widget** (`bin/treeview.ml`). La forêt interne
est la source de vérité depuis les épisodes 5 et 6 pour les *identités* ; l'invariant s'étend
maintenant aux *valeurs*. Le renderer d'icônes dérive l'identifiant du chemin de la ligne
(`path_to_id_opt`, variante **totale** ajoutée à côté du `path_to_id` qui échoue nommément —
un `cell_data_func` ne doit jamais lever, piège de l'épisode 6) puis lit le champ par
`Row.Icon_field.get`. Les trois `method get` de colonne (`string_column`, `checkbox_column`,
`icon_column`) suivent la même voie. **Portée à ne pas surestimer** : ces trois méthodes n'ont
**aucun appelant** dans `bin/` — le chemin réel de lecture est `get_row_field` (`treeview.ml:1424`),
qui lisait déjà la forêt. Le seul site à la fois fautif et exercé était le renderer ; les trois
autres réécritures sont **préventives**, et le run ci-dessous ne les exerce pas.

**Preuve GUI, journal C** (932 l., `s=4k` — les conditions mêmes qui produisaient 21 occurrences au
run A, même projet et même scénario) : **0** `no icon for this row`, **0** `icon_column#lookup`,
**0** `id_to_iter`, **0** assertion, **0** `CRITICAL`, **0** `ForbiddenTransition`, **0** `Failure`,
sortie propre. L'absence du premier motif est une preuve *positive* que chaque lecture a abouti sur
une icône connue : le chemin « cellule vide » est **toujours** journalisé. **Ce que ce run ne prouve
pas**, et il faut le dire : zéro occurrence était acquis **par construction** puisque le widget
n'est plus lu. Ce run atteste la non-régression, pas l'élucidation.

**Reste au chantier** : la cause profonde de l'écrasement — désormais hors d'atteinte des mesures
faites depuis OCaml (deux familles réfutées ; instruire par valgrind ou ASAN serait un épisode à
soi seul, et Marionnet n'y est plus exposé) —, le retrait de l'instrumentation `B6:` de l'épisode 2,
l'arbitrage B4, et les deux défauts signalés à l'épisode 11.

---

### Épisode 15 — 2026-08-02 — les deux défauts de l'épisode 11, et B4 clos par arbitrage

Le plan de conception étant entièrement joué depuis l'épisode 7, cet épisode ne traite que des
**reliquats** : les deux défauts que l'épisode 11 avait délibérément laissés (« chacun demande une
décision propre ») et l'arbitrage B4. Le retrait de l'instrumentation `B6:` reste, par choix de
l'auteur, pour plus tard.

#### 1. Le verrou du gestionnaire de LED grids (`bin/gui/ledgrid_manager.ml`)

Défaut signalé : `make_device_ledgrid` prend le mutex puis appelle `set_port_connection_state`, qui
le **reprend** ; `Mutex.lock` n'étant pas récursif, un `~connected_ports` non vide s'auto-bloquerait.
Inatteignable aujourd'hui (la liste est toujours vide à cet endroit), mais c'est une bombe à
retardement dans une classe dont **le thread du blinker** est un client permanent.

**Un second défaut, trouvé en relisant, et retenu** : les méthodes faisaient `lock; corps; unlock`
**sans protection**. Si le corps lève — et `make_widget` construit des widgets Gtk+ —, le mutex
reste verrouillé **à vie**, après quoi le blinker (`flash`, appelé à chaque datagramme reçu) se
bloque pour de bon. C'est la même famille de gel silencieux que les épisodes 9 à 13, à ceci près
que le verrou en cause est celui de la classe, pas le master lock du runtime.

Correctif, en suivant le patron **déjà présent 7 fois** dans le fichier (`(** This is {e
unlocked}! *)`) plutôt qu'en introduisant un mutex récursif :

- `method private with_lock : 'a. (unit -> 'a) -> 'a` — prend le verrou puis `Fun.protect
  ~finally:(fun () -> self#unlock)`. Les 7 méthodes verrouillantes y passent ;
- `method private set_port_connection_state_unlocked` porte désormais le corps, la méthode publique
  se réduisant à `apply_extract (fun () -> with_lock (fun () -> …)) ()` ;
- `make_device_ledgrid` appelle la variante **unlocked**, puisqu'il détient déjà le verrou.

L'invariant de l'épisode 11 est préservé : l'enrobage `GMain_actor.apply_extract` **englobe** le
verrou, de sorte que le mutex n'est jamais détenu pendant l'attente du thread principal. Le
commentaire de discipline (au-dessus de `reset`) énonce maintenant la forme obligatoire de toute
méthode publique de la classe, au lieu de décrire un défaut non corrigé.

Au passage, un mésnommage qui n'attendait qu'un lecteur pressé : `make_device_ledgrid` liait
`ledgrid_widget, window_widget` au couple rendu par `make_widget`, qui rend `window, device` —
**les deux noms étaient inversés**. Le stockage restait correct (l'ordre attendu par `lookup` est
`(window, device, name, ports)`), donc rien à corriger côté comportement ; les identifiants locaux
sont remis à l'endroit.

#### 2. L'échec d'un treeview cesse d'être avalé (`bin/treeview.ml`, `bin/state.ml`)

Défaut signalé : `Treeview#detach_view_in` déléguait par `GMain_actor.delegate`, qui **jette
l'`Either`** — le `raise e` de `private_detach_view_in` était donc du code mort.

**Ce que la relecture ajoute, et qui a décidé du périmètre** : le corriger seul n'aurait **rien
changé d'observable**. Son unique appelant, `treeview#load`, avale déjà tout dans son propre
`try … with`, et surtout `state.ml` ré-avalait via **trois** `delegate` — `load_treeviews`,
`save_treeviews`, `clear_treeviews`. Le cas grave est `save_treeviews` : un treeview qui échoue à
s'écrire était silencieux, le `.mar` était produit tout de même et le projet **déclaré
sauvegardé**. C'est le motif « tâche réussie qui a pourtant levé » de l'épisode 5, cette fois sur
le chemin le plus coûteux qui soit ; et comme les trois méthodes sont des `List.iter` sur les
quatre treeviews, l'échec du deuxième laissait silencieusement les deux suivants intacts.

Correctif, de l'aval vers l'amont : `detach_view_in` et les trois méthodes de `state.ml` passent à
`apply_extract`, puis les deux appelants sensibles sont gardés.

- **`private_save_project`** : le corps qui suit la création de la barre de progression est
  enveloppé dans `Fun.protect ~finally:(destruction de la barre)` — celle-ci est **modale**, la
  laisser à l'écran rendrait la GUI inutilisable —, et l'échec est rattrapé sur place :
  journalisation, dialogue d'erreur, et surtout **ni `register_state_after_save_or_open` ni
  `END. Success.`**, donc un projet qui reste marqué modifié. Rattraper *ici* et non chez les
  appelants : sur les six appels de `st#save_project`, un seul chemin (`save_project_as`) possède
  un `try`, et lorsque l'appel vient du thread GTK, `save_project` exécute ce corps dans un
  `Thread.create` où une exception échappée tuerait le thread **en silence**.
- **`open_project_async`** : `load_treeviews` est entouré d'un `try … with` qui journalise et
  affiche l'échec, **sans changer le flux** — l'import réseau suit son cours comme avant. Le but
  est la visibilité, pas une réorganisation de l'ouverture.

**Zéro nouvelle chaîne i18n** : l'invariant du projet est que les catalogues soient complets pour
les 12 langues, une chaîne neuve les casserait toutes. Les trois messages réutilisés — `"Save"`,
`"Failed to save the project into the file "`, `"Failed loading the project"` — existent et sont
traduits dans les **14** fichiers `bin/po/*.po` (vérifié avant écriture).

#### 3. B4 : clos par arbitrage, sans correctif

Rappel de l'état : la **première** moitié de B4 — le compteur de rendu qui salissait le projet — a
été supprimée à l'épisode 4 (drapeau `project_dirty`). La **seconde** est apparue en jouant le
scénario : démarrer une machine fait ajouter un état de disque COW au treeview *history*, que le
filet « comparaison des forêts » détecte à juste titre, si bien qu'un simple démarrer/arrêter
suffit à faire poser la question de la sauvegarde.

**Arbitrage rendu par l'auteur : c'est légitime, on ne touche à rien.** Le nouvel état COW *est* un
contenu que le `.mar` stocke ; après un démarrer/arrêter, le projet contient réellement quelque
chose de plus que ce qui a été enregistré. La prémisse de l'audit de l'épisode 0 — « alors
qu'aucune donnée persistée n'a changé » — était **fausse dans ce cas**. Les deux alternatives sont
écartées pour des raisons déjà éprouvées dans ce chantier : exclure les états COW du test des
forêts ferait **perdre en silence** un contenu du `.mar` (même refus qu'à l'épisode 4 pour les
*dotoptions*) ; ne salir que si le disque diffère réellement supposerait de comparer les disques à
chaque fermeture, coût sans bénéfice. Un commentaire sur place (`state.ml`,
`project_already_saved`) dit désormais pourquoi ce comportement ne doit pas être « corrigé ».

#### 4. Preuves

`dune build` rc=0 après chaque volet, `make install-for-testing` rc=0.

**Journal 27** (988 lignes, projet `propre-2machines-1hub`) — ouvrir, enregistrer, démarrer H1,
tout arrêter, fermer, quitter :

| Ce qui est prouvé | Où |
|---|---|
| chargement : `calling load_treeviews` puis **4** treeviews, chacun avec `detach_view_in: about to detach the view` et `successfully loaded` — le `List.iter` va jusqu'au bout | l. 206-262 |
| sauvegarde : `save_project BEGIN` (thread `.61`) → `save_network: end (success)` → **4** `treeview#save` émis depuis `.0` → `tar` listant les 4 fichiers d'états → `state#save_project END. Success.`, puis destruction de la barre par le `finally` | l. 317-347 |
| LED grid : `Making a ledgrid with title H1 (id=3) with 4 ports`, blinker démarré puis **sorti proprement** (`please-die` → `has exited now`) | l. 68-69, 286, 952-957 |
| sortie propre : `at_exit: killing all orphans`, `Thread Exiting (main)` | l. 978-988 |
| 0 `CRITICAL`, 0 `Assertion`, 0 `id_to_iter`, 0 `ForbiddenTransition`, 0 `Failure`, 0 exception, 0 `FAILED` | — |

Sur le volet 1, la preuve est **indirecte mais décisive** : si `with_lock` avait laissé le mutex
pris, le `flash` ou le `destroy` suivant aurait gelé le processus. Il est allé jusqu'au bout.

Les **3 `WARNING` du gestionnaire de LED grids** (id 3, l. 837/842/865) ne sont **pas** une
régression : `ledgrid_manager#reset` détruit le ledgrid de H1 au début de `close_project`, après
quoi `network#reset` redemande de déconnecter ses ports et de le détruire. Comptes de
`failed in set_port_connection_state` par journal : j16 = 2, j20 = 10, j22 = 0, j23 = 0, **j24 = 2,
j25 = 2, j27 = 2** — le motif précède largement cet épisode.

**Ce que ce run ne prouve pas**, et il faut le dire :

- **`clear_treeviews` n'est pas observable** — `Treeview#clear` ne journalise rien ;
- **`close_project` n'atteint pas son `END. Success.`** : le thread `.359` attendait la terminaison
  des hublets de H1 (`Waiting for all currently enqueued tasks…`) lorsque le *quit* est arrivé.
  Ce n'est **pas** un gel — les tâches `destroy H1/m2/m1` se sont exécutées ensuite et la sortie est
  propre — mais ce n'est pas la preuve de fermeture complète du journal 20 ;
- les **chemins d'échec** de save/load n'ont pas été déclenchés : ces gardes restent **préventives**,
  comme celles de l'épisode 10 ;
- **B4 n'a pas été exercé par ce run, par défaut de scénario** : le projet ayant été fermé avant de
  quitter, c'est le menu **Fermer** qui a posé la question — or il la pose **inconditionnellement**
  (`gui_menubar_MARIONNET.ml:257-259`), tandis que seul le **Quitter avec projet actif** consulte
  `project_already_saved` (`:346`). Le `answer = no` du journal ne dit donc rien de B4. D'où le
  rejeu ciblé ci-dessous.

**Journal 28** (578 lignes) — ouvrir, démarrer **m1**, l'arrêter, puis **Quitter directement**. Ce
run n'était pas requis (B4 est clos par arbitrage, aucun code de comportement n'a changé) mais il
donne la chaîne causale complète, et les deux moitiés de B4 s'y lisent en **deux lignes
consécutives** :

| l. | ligne du journal | ce qu'elle établit |
|---|---|---|
| 332 | `B6: Treeview_history#add_substate_of: parent row 0 ("m1"), 0 sibling(s)…, Calling thread: 8` | démarrer m1 ajoute un état au treeview *history*, depuis le **task runner** |
| 335 | `cow file: …/states/50674-47107-32583.cow` | l'état ajouté référence un **fichier COW réel**, que le `.mar` stockerait |
| 508 | `The project *seems* already saved.` | le drapeau `project_dirty` est resté **baissé** — R3 (épisode 4) fait son travail, démarrer/arrêter ne salit rien |
| 509 | `Something has changed in treeviews: the project must be re-saved.` | c'est **le filet des forêts**, et lui seul, qui déclenche la question |
| 510-511 | `--- Dialog result: answer = no` | le dialogue de sauvegarde est bien posé au *quit* |

0 `CRITICAL`, 0 `Assertion`, 0 `id_to_iter`, 0 `ForbiddenTransition`, 0 `Failure`, 0
`raised an exception` ; sortie propre (`at_exit`, `Thread Exiting (main)`) ; aucun `save_project`
puisque la réponse est *non*. La conclusion de l'arbitrage est ainsi visible plutôt que déduite :
ce qui déclenche la question n'est pas un artefact de rendu mais un **contenu persistable** de plus.

**Reste au chantier** : le retrait de l'instrumentation `B6:` de l'épisode 2 (11 sites), et la cause
profonde de l'écrasement — hors d'atteinte des mesures faites depuis OCaml, et sans objet depuis
l'épisode 14 puisque Marionnet ne lit plus aucune valeur dans le widget.

---

### Épisode 16 — 2026-08-03 — le retrait de l'instrumentation `B6:`, et la clôture

Dernier reliquat du chantier. L'instrumentation posée à l'épisode 2 pour traquer la divergence du
treeview *defects* est devenue **du bruit d'exploitation** : la plupart de ses lignes sont en
`~force:true`, donc visibles hors mode debug, alors que le défaut qu'elles traquaient est corrigé
depuis les épisodes 5, 6 et 14. Le retrait est **sélectif**, sur décision de l'auteur : ce qui a une
valeur au-delà du diagnostic reste, débarrassé du jeton.

#### 1. Ce qui a été mesuré avant d'éditer

`grep 'B6:' bin/` donnait **11 lignes de log** (`treeview_defects.ml` ×6, `treeview.ml` ×4,
`treeview_history.ml` ×1), et la relecture en a trouvé un **douzième site** que le `grep` ne voyait
pas : `treeview.ml`, `remove_subtree_by_name`, dont le commentaire s'annonce « instrumentation »
alors que son log — une destruction silencieusement sautée — n'a jamais porté le préfixe et n'a rien
de temporaire.

#### 2. Les huit lignes retirées

| Site | Ce que c'était | Pourquoi il part |
|---|---|---|
| `treeview.ml`, `load` | compteur d'identifiants restauré, `~force` | sonde pure : distinguer « ligne jamais créée » de « ligne créée puis perdue » n'intéressait que le diagnostic |
| `treeview_defects.ml`, `complete_direction_rows` | « la ligne "%s" manquante a été créée », `~force` | **redondant** : `report_repair`, juste en dessous, journalise déjà en permanent « entrée incomplète … *N* ligne(s) ajoutée(s) » |
| `treeview_defects.ml`, `add_cable` | identifiants des deux lignes de direction créées, `~force` | ne servait qu'à corréler les traces de l'épisode 2 ; les deux `ignore` d'origine sont restaurés |
| `treeview_defects.ml`, `b6_dump_children` | la méthode **entière** | dump verbeux d'anomalie, explicitement marqué « à retirer une fois B6 corrigé » |
| `treeview_defects.ml`, `get_port_data` | l'appel du dump **et son `try … with Not_found → … raise Not_found`** | le `try` n'existait que pour le dump — son propre commentaire le disait ; l'expression redevient nue |
| `treeview_defects.ml`, `get_cable_data` | l'appel du dump | idem |
| `treeview_defects.ml`, `get_cable_data` | ligne concise `%d/%d matching child row(s)` | l'anomalie est déjà dite, **nommément**, par le `failwith` de l'épisode 6 trois lignes plus bas |
| `treeview_history.ml`, `add_substate_of` | parent, frères, **thread appelant**, `~force` | a servi de preuve à B4 (journal 28), désormais clos ; et le thread figure déjà dans le préfixe de *chaque* ligne de journal |

#### 3. Les trois lignes gardées, et pourquoi

Elles perdent le préfixe `B6:` et le vocabulaire « instrumentation », mais restent : chacune dit
quelque chose qu'aucun autre log ne dit.

- **`treeview.ml`, `load`** — dump de la forêt telle qu'elle sort du fichier. Déjà gardé par
  `Debug_level >= 1` (coût nul hors `-d`), c'est le seul moyen de distinguer une forêt **déjà abîmée
  sur disque** d'une forêt abîmée en session. Le commentaire perd l'anecdote de la garde morte
  (`>= 3`, inatteignable) et garde le fait.
- **`treeview.ml`, `remove_row`** — la victime et le nombre d'orphelins **remontés d'un niveau**.
  C'est la trace sur place du piège durable `Forest.filter` (`forest.ml:150`) : cette méthode
  **n'est pas** une suppression de sous-arbre. Passe sans `~force:true`.
- **`treeview.ml`, `remove_subtree`** — symétrique (victime + descendants), même traitement, pour
  que les deux méthodes jumelles se lisent de la même façon dans un journal.

Le douzième site (`remove_subtree_by_name`) garde son log tel quel : une destruction sautée en
silence est *le premier mécanisme de B6*, elle doit laisser une trace. Seul son commentaire est
réécrit pour ne plus se présenter comme provisoire.

#### 4. Un renommage et une note

`b6_treeview_nickname` → **`treeview_nickname`**. Cette méthode survit au chantier — deux messages
d'échec **permanents** l'utilisent (`id_to_iter`, `path_to_id`), en plus des deux logs gardés — son
nom ne devait plus porter le jeton d'un diagnostic clos. Sans risque : `bin/treeview.mli` n'existe
pas (les `.mli` de `bin/` sont sélectifs) et aucun fichier hors `treeview.ml` ne la nommait.

Restent une vingtaine de commentaires « B6 (épisode *N*) » dans `treeview.ml`, `treeview_defects.ml`,
`cable.ml`, `user_level.ml` et `state.ml` : ils documentent des **choix durables** (lire la forêt et
non le widget ; un `cell_data_func` qui ne lève jamais ; un `failwith` nommé plutôt qu'un `assert`)
et n'ont aucune raison de disparaître avec la sonde. Plutôt que de les réécrire un par un, **une**
note d'en-tête a été ajoutée dans `bin/treeview.ml` : ce qu'est B6, et où le lire — ce document.

#### 5. Vérifications

- `dune build` → **rc=0** ;
- `grep -rn 'B6:' bin/` → **0 résultat** ; `grep -rn 'b6_' bin/` → **0 résultat** ;
- `make install-for-testing` → **rc=0** ;
- diff : **3 fichiers**, +49 / −123.

#### 6. Preuve GUI (journal de l'épisode 16, 560 lignes, lancé avec `-d`)

Scénario : ouvrir `propre-2machines-1hub`, démarrer **m1**, l'arrêter, **supprimer le câble d1**,
quitter.

| Ce qu'on vérifie | Mesure |
|---|---|
| plus aucune trace de la sonde | **0** ligne `B6:` |
| dump de forêt gardé (sous `-d`) | **4** `Treeview.treeview#load: freshly loaded forest of …` — un par treeview (*ifconfig*, *states-forest*, *defects*, *texts*) |
| `remove_subtree` gardé, et le renommage | `[defects] Treeview#remove_subtree: removing row 21 ("d1") together with [22:"to H1 (port1)"; 23:"to m2 (eth0)"]` — le préfixe `[defects]` est rendu par `treeview_nickname`, donc le renommage tient sur un chemin réellement exercé |
| le cycle du composant | `Gracefully shutting down the device m1 (from state: DeviceOn)` puis destruction complète (hublets, tap `mtap2772806-0`) |
| la suppression du câble | `component "d1": destroying my defects.` → le `remove_subtree` ci-dessus → `The task "destroy d1" succeeded.` |
| erreurs | **0** `CRITICAL`, **0** `Assertion`, **0** `id_to_iter`, **0** `ForbiddenTransition`, **0** `Failure`, **0** `raised an exception` |
| tâches | **9** `succeeded`, **0** `THIS MAY BE SERIOUS` |
| sortie | `at_exit` (descendants puis orphelins), boucles d'acceptation terminées, `Thread Exiting (main): nothing to do` |

**Ce que ce run ne prouve pas**, et il faut le dire :

- **`remove_row` n'a pas été exercé** — la suppression d'un câble passe par `remove_subtree` ; le
  log gardé sur `remove_row` (les orphelins **remontés** par `Forest.filter`) reste donc non
  observé, comme il l'était avant cet épisode ;
- `remove_subtree_by_name` n'a pas eu à journaliser de `destruction SKIPPED` — c'est un chemin
  d'échec, son silence est une bonne nouvelle, pas une mesure ;
- les **2** `component "m1"/"m2": failed to create the hostfs_directory` sont **préexistants** :
  le motif est présent aux journaux 24, 25 et 27, bien avant cet épisode.

Un retrait de logs ne peut pas *causer* de régression ; ce rejeu vaut comme non-régression du
chemin *defects* (celui que la sonde surveillait) et comme preuve que les trois lignes gardées
sortent bien, au bon moment, sous leur nouvelle forme.

---

## 6. Conclusion du chantier (2026-08-03)

**Le chantier est clos.** Ce qu'il laisse :

- **L'invariant est porté par le type.** `automaton_state` et `simulated_device` sont fusionnés en
  un unique `val state : 'parent Simulated_device.state ref` (épisode 7) : les huit filtrages de
  couple sont devenus simples et exhaustifs, et trois des sept `raise_forbidden_transition` ont
  disparu comme **inatteignables**. C'était l'objectif annoncé au § 3.
- **Les cinq bugs de l'audit sont soldés** : B1 et B2/B3 corrigés (ép. 1 et 3), B5 corrigé puis
  **révisé** par la règle de projet « le câblage suit la réalité » (ép. 8 puis 12 — un câble
  s'édite et se supprime en marche), B6 corrigé sur le socle (ép. 5, 6, 14), B4 **clos par
  arbitrage** comme légitime (ép. 15).
- **Un acquis qui déborde largement le périmètre initial** : la discipline des appels Gtk+ hors du
  thread principal. Partie d'un gel signalé sur le terrain (ép. 9), elle a produit un critère de
  tri à trois conditions, la correction des classes A et B (ép. 10, 11), l'enrobage des ajouts au
  modèle (ép. 13) et deux règles de méthode — `apply_extract` plutôt que `delegate` (qui avale
  l'exception), et englober le verrou quand on enrobe une méthode qui prend un mutex. Ces règles
  sont résumées dans `docs/ARCHITECTURE.md` § 5 ; le détail et les preuves restent ici.
- **Un défaut clos par C5** de `docs/bug-critique-crash-host.md` : ce qui passait pour un crash
  hôte était un gel d'application, mesuré et corrigé (ép. 9).

**Hors périmètre, assumé** : la **cause profonde** de l'écrasement du premier mot d'une valeur lue
dans le modèle Gtk+. Deux familles d'hypothèses ont été **réfutées par la mesure** — l'écriture
concurrente au rendu (ép. 13) et le GC d'OCaml (ép. 14, où un minor heap de 256 Mo donne *plus*
d'occurrences qu'un de 32 Ko, l'inverse de ce qu'exigerait une promotion). L'instruire demanderait
valgrind ou ASAN, c'est-à-dire un épisode à soi seul, **sans bénéfice pour le produit** : depuis
l'épisode 14, Marionnet ne lit plus aucune valeur dans le widget et n'y est donc plus exposé. Si
le sujet devait être rouvert, la caractérisation exacte est au § PIÈGES de l'épisode 14.

Ce document reste comme **archive**. La fiche mémoire `marionnet-automate-composants` est réduite
aux seuls pièges qui servent hors du chantier ; le pointeur de `CLAUDE.md` a été déplacé en
« Chantiers clos ». Historique complet : `git log --grep="marionnet-automate-composants"`.
