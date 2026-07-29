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
  (ifconfig, defects) avec le modèle réseau n'a pas été auditée.
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
