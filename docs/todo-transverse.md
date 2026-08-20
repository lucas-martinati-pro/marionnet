# Chantier `marionnet-todo-transverse` — solder la TODOLIST transverse

> **Objectif.** Traiter, une par une et **chacune avec au moins un commit**, les 15 entrées de
> défaut de `docs/TODO.md` : ce qui a été repéré au fil des chantiers, jugé réel, et laissé de
> côté parce qu'il n'appartenait à aucun d'eux. Une entrée est *soldée* quand son symptôme est
> rejoué rouge avant / vert après, et **retirée de `docs/TODO.md` dans le commit qui la clôt**.

Ouvert le 2026-08-20. Reprise : appliquer le skill `chantier-long` (MODE B).

---

## 1. Périmètre

Les **15 entrées de défaut** de `docs/TODO.md`, à la date d'ouverture. Chacune y porte déjà son
constat, ce qu'on veut à la place, et l'obstacle repéré : ce document ne recopie pas cette
analyse, il porte **les décisions de cadrage** (§ 3) et **l'ordre d'exécution** (§ 4).

**Hors périmètre, par décision explicite (2026-08-20)** : l'entrée *« Idée — composer deux
projets (importer un `.mar` dans le projet courant) »*. Ce n'est pas un défaut mais une
fonctionnalité, et le TODO en énumère lui-même quatre obstacles de fond (politique de renommage,
fusion des treeviews persistées à part, répertoires `hostfs/`, remaps d'import à rejouer sur la
seule partie importée). Elle **reste dans `docs/TODO.md`** et méritera son propre chantier.

---

## 2. Ce qui rend ce chantier différent des autres

Il n'a **pas de sujet** : c'est un chantier de *solde*. Ses 15 épisodes ne construisent rien
ensemble et se touchent à peine. La seule chose qui les relie est la discipline :

1. **Un épisode = une entrée = au moins un commit**, portant le retrait de l'entrée du TODO.
2. **La preuve précède l'annonce** : le symptôme exact du TODO, rejoué avant et après.
3. **Aucune extension de périmètre** : si un épisode découvre un défaut voisin, il l'**écrit dans
   `docs/TODO.md`**, il ne le corrige pas en passant. (L'inverse — la campagne qui s'étend —
   est ce qui a fait que ces entrées ne sont pas déjà traitées.)

---

## 3. Décisions de cadrage (grill du 2026-08-20)

### 3.1 Une entrée qu'une mesure bloque livre quand même sa mesure

Deux entrées ne se règlent pas au clavier : le *rapport de fin de session* (« rien n'est
instruit » — il faut mesurer le délai entre le marqueur de disponibilité et l'activation du hook
systemd, sur plusieurs images) et la *durée du timeout mconsole*.

Règle retenue : on mesure d'abord ; si la cause est établie, correctif + commit ; **si la mesure
ne conclut pas, l'épisode livre la mesure** (commit : instrumentation, banc, paragraphe de
journal) et l'entrée du TODO est **réduite à son reliquat** au lieu d'être supprimée. C'est la
forme éprouvée à l'ép. 13 de `modernisation-world-bridge` : le geste impossible ici est *nommé*,
pas escamoté.

### 3.2 Répertoires de run : signaler, ne jamais purger tout seul

Fait mesuré à l'ouverture : le répertoire `/tmp/marionnet-<n>.dir/` est créé par
`project_paths#set_filename_and_create_the_project_working_directory` (`bin/state.ml:142`) et
**détruit** par `reset_and_remove_the_project_working_directory` (`:196`), appelée par
`close_project` — que le chemin *Quitter* invoque bien avant `quit_async`
(`bin/gui/gui_menubar_MARIONNET.ml:435`). **Une sortie propre ne laisse donc rien.** Les 359
répertoires relevés viennent tous de sessions mortes brutalement.

Conséquence : il n'y a rien à corriger « à la sortie », et le seul levier est **au démarrage**.
Décision : Marionnet **signale** les répertoires orphelins et **suggère la commande** —
`useful-scripts/marionnet-cleanup` avec les options pertinentes — sans **jamais** rien retirer de
lui-même. Motif : ce répertoire contient exactement la copie de travail que l'utilisateur n'a pas
enregistrée. Une purge automatique, même vieille de trente jours, efface la seule copie qui
restait.

### 3.3 Noyau par défaut du routeur : la voie (b), pleine

La voie (a) du TODO — réordonner `SUPPORTED_KERNELS` dans `router-guignol-18474.conf` — est
**écartée** : ce fichier n'est pas versionné (le dépôt ne contient que `machine-{lenny,mandriva,
pinocchio,template}.conf` et `router-pinocchio-09157.conf`), il vit sous `/usr/local/share/…`,
et la prochaine reconstruction d'image l'écrase. Un chantier qui exige un commit par entrée ne
peut pas s'y appuyer.

Voie retenue : **(b) pleine** — la préférence qu'applique `remap_obsolete_kernel_at_import`
devient le facteur commun, appliqué **aussi au constructeur**. « Premier noyau déclaré » devient
« premier noyau déclaré *et* utilisable ici », pour la création comme pour l'import : une seule
source de vérité, donc un défaut qui ne peut pas revenir par l'autre chemin. Le prix, assumé :
cela touche le défaut de **toutes** les natures, d'où une preuve sur toutes les natures.

### 3.4 `--control-socket` : refus de démarrer, généralisé à toute cause

Le TODO ne voit que le chemin trop long ; la lecture du code montre plus large. `Control_server.start`
attrape **déjà** l'échec et le journalise (`Control_server: NOT started: …`,
`bin/control_server.ml:4643,4666`), puis Marionnet **continue en GUI seule** — pour la longueur
comme pour une permission, un répertoire absent ou un socket occupé. Le silence perçu vient de ce
que le journal n'est pas sous les yeux de qui lance un banc.

Décision : quand `--control-socket` est donné et que le canal **ne peut pas** être ouvert, **quelle
qu'en soit la cause**, Marionnet **refuse de démarrer**, avec un message sur **stderr**. Plus un
contrôle de longueur **avant** le `bind`, nommant la limite (107 octets utiles de `sun_path`) et la
longueur fournie. Motif : `--control-socket` **implique le mode script**
(`bin/initialization.ml:92`) — une session pilotée que personne ne peut piloter n'a aucune raison
de tourner, et c'est un banc, pas un humain, qui la lance.

### 3.5 Le device simulé qui survit à l'extinction : remède local, pas refonte

Deux entrées (`wait --ready` au second démarrage, `rc-set` sur un switch) ont **une seule** cause :
`poweroff` arrête les processus mais **ne détruit pas** l'objet device simulé, si bien que tout ce
qu'un `initializer` calcule n'est calculé **qu'une fois**.

Décision : **remède local**, nature par nature — déplacer vers l'allumage ce qui doit être frais
(`make_hostfs_content` dans `spawn` ; une **fonction** plutôt qu'une valeur pour le rc du switch).
L'automate d'état n'est **pas** rouvert (`docs/refonte-automate-composants.md`, clos).

La voie de fond — *le device simulé ne survit pas au `poweroff`* — guérirait la famille entière
pour les huit natures, mais suppose d'établir d'abord ce qui **doit** survivre à l'extinction
(identité, fichier cow, descripteurs de journaux, numéro d'instance, câbles branchés) : c'est
précisément pourquoi l'objet survit aujourd'hui. Ce n'est pas un correctif, c'est un chantier.
**La famille est nommée ici** pour qu'un futur passage sache où regarder.

### 3.6 Preuve : bancs jetables, sauf cinq qui deviennent versionnés

Convention du dépôt jusqu'ici : le banc est **jetable** (scratchpad), sa **sortie** est recopiée
dans le doc du chantier. `git ls-files` ne contient en effet aucun banc — ni `components-bench.sh`,
ni `rename-witness.sh`, ni les `selftest` des chantiers récents.

Elle est **conservée par défaut**, avec une exception motivée par un critère unique :
*le banc est-il déterministe et exécutable partout ?*

| Bancs | Sort |
|---|---|
| Le canal et le modèle suffisent : aucun invité ne boote, aucun privilège | **versionnés** dans `driven-sessions/` |
| Un invité doit booter, ou il faut `sudo`, ou une plateforme absente ici | **jetables**, preuve recopiée dans le journal ci-dessous |

Quatre entrées tombent dans la première colonne : *`add --ports`*, *rollback du constructeur*,
*`distrib` inexistante*, *`--control-socket` trop long*.

> **Corrigé à l'épisode 1** : le *label* y figurait, à tort. Le canal ne peut pas fournir un label
> arbitraire à `update_with` — `update_structural_with` lui passe `self#get_label`, déjà validé, et
> `set <n> label` passe par `eval_forest_attribute`, qui n'atteint pas `update_with`. Seul le
> dialogue *Properties* de la GUI a ce pouvoir. La preuve exige donc un **patch témoin**, donc un
> banc jetable.

**`driven-sessions/`** (nom retenu contre `tests/`, déjà pris par les tests unitaires OCaml sous
`dune test`, et contre `bench`/`trial`, qui disent *benchmark* et *essai clinique* en anglais) :
`driven` est le mot du dépôt pour une session pilotée par le canal
(`bin/gui/gui_menubar_MARIONNET.ml:400`). Son `README.md` porte la règle d'entrée — *un script par
défaut corrigé, rouge avant le correctif, vert après, sans invité qui boote ni privilège* — pour
qu'il ne devienne pas un dépotoir d'exemples.

---

## 4. Les 15 épisodes, par coût croissant

L'ordre est celui du coût, pas de la gravité : les correctifs courts d'abord, les diagnostics
ouverts à la fin. Deux dépendances seulement : l'ép. 1 crée `driven-sessions/`, et l'ép. 4
s'appuie sur le rollback de l'ép. 3.

| N | Entrée de `docs/TODO.md` | Geste | Preuve |
|---|---|---|---|
| 1 | Le **label** se valide trop tard | `check_new_label` avant la première écriture des deux `update_with` (`bin/user_level.ml`), comme `check_new_name` | jetable (**patch témoin**, cf. § 3.6) — **fait** |
| 2 | `--control-socket` trop long échoue en silence | Refus de démarrer généralisé + contrôle de longueur avant le `bind` (§ 3.4) | `driven-sessions/control-socket-refusal.sh` — **fait** (crée le répertoire et son README) |
| 3 | Un constructeur qui échoue laisse son nœud | Le rattrapage d'`add` cherche le nœud du nom demandé et le détruit, dans la même section critique | `driven-sessions/add-rollback-on-constructor-failure.sh` — **fait** |
| 4 | `add … --ports=N` ne vérifie pas les bornes | Construire, vérifier, détruire — en réutilisant le rollback de l'ép. 3 plutôt qu'une seconde table `kind → (min,max)` | `driven-sessions/` |
| 5 | `set … distrib <inexistante>` accepté sans rien changer | `bad_argument` nommant les distributions installées, patron de `supported_kernels_if_any` | `driven-sessions/` |
| 6 | Les répertoires de run ne sont balayés par personne | Signalement au démarrage + suggestion de `marionnet-cleanup` (§ 3.2) | banc jetable |
| 7 | `uml_mconsole … sysrq e` peut rester bloqué | Échéance sur la tentative mconsole, durée **mesurée** sur un invité sain | banc jetable (invité) |
| 8 | Deux sessions partagent l'adresse hôte de leurs taps | **Détection** et message ; l'adresse n'est pas dérivée (contrat réseau de `marionnet-daemon-elimination`) | banc jetable |
| 9 | `wait --ready` ment au second démarrage | `make_hostfs_content` au `spawn`, et le `O_TRUNC` manquant (§ 3.5) | banc jetable (invité) |
| 10 | Un `rc-set` sur un switch n'est pris qu'au premier démarrage | Fonction plutôt que valeur au constructeur du device (§ 3.5) | banc jetable (invité) |
| 11 | Un routeur neuf naît avec un noyau inutilisable | Voie (b) pleine (§ 3.3) | banc jetable, **toutes** les natures |
| 12 | Les autres fenêtres de message s'étalent sur toute la largeur | Plafonds dans le glade et en OCaml, **message par message** (des `\n` manuels préexistent) | run GUI, captures |
| 13 | Griser « Enregistrer » / « Sous » / « Copier vers » | Quatrième pile de sensibilité + source de notification aux transitions | run GUI |
| 14 | En arbre de dev, Marionnet lit le catalogue d'un AUTRE Marionnet | **Instrumenter d'abord** (le `Log.printf` de `gettext.ml:59` est écrit avant que le journal soit prêt, donc perdu) ; fusible § 3.1 | `strace -e openat` |
| 15 | Le rapport de fin de session n'est pas garanti | **Mesurer d'abord** le délai marqueur → hook ; fusible § 3.1 | banc jetable (invités) |

---

## 5. Journal d'avancement

### 2026-08-20 — épisode 0 : ouverture

Chantier officialisé. Périmètre arrêté à 15 entrées (la composition de projets reste au TODO,
§ 1). Six décisions de cadrage prises avant toute édition (§ 3), dont trois reposent sur des faits
**vérifiés dans le code à l'ouverture**, et non sur le TODO seul :

- la sortie propre **retire déjà** le répertoire de run — le tas de `/tmp` vient des morts
  brutales, pas d'une fuite à la sortie (§ 3.2) ;
- `router-guignol-18474.conf` **n'est pas versionné** — la voie (a) du TODO n'est pas
  committable (§ 3.3) ;
- l'échec d'ouverture du canal est **déjà** attrapé et journalisé, et vaut pour **toute** cause,
  pas seulement la longueur du chemin (§ 3.4).

Aucun code modifié à cet épisode.

### 2026-08-20 — épisode 1 : le label validé avant la première écriture

`wellFormedLabel` hissé hors de `id_name_label` (une seule copie du motif `[><]`), `check_new_label`
posé à côté de `check_new_name`, et les **deux** `update_with` (`node_with_defects`,
`node_with_ledgrid_and_defects`) valident désormais leurs deux arguments refusables **avant** de
détruire le device simulé et d'écrire quoi que ce soit.

**Preuve** (banc jetable `label-witness.sh`, patron `rename-witness.sh`). Le canal ne pouvant pas
fournir un label arbitraire à `update_with`, un **patch témoin** d'une ligne fait lire à
`update_structural_with` la variable `MARIONNET_WITNESS_LABEL` — soit exactement le pouvoir qu'a le
dialogue *Properties*. Le banc crée `m1` (1 port), demande `set m1 port_no 6` avec le label
invalide `a<b`, puis **relit** le modèle :

| | réponse du canal | `port_no` relu |
|---|---|---|
| correctif désarmé | `ok:false` — `invalid label` | **6** — écrit malgré le refus |
| correctif en place | `ok:false` — `invalid label a<b` | **1** — inchangé |

Le message y gagne au passage la valeur fautive (`invalid label a<b`), que `check_label` ne disait
pas. `dune build` rc 0 après retrait du témoin ; aucun processus survivant.

**Observé en chemin, non corrigé** (règle § 2) : les trois runs du banc ont laissé leurs trois
`/tmp/marionnet-<n>.dir/`. Le `quit` **du canal** ne passe donc pas par `close_project`, alors que
le *Quitter* de la GUI le fait (§ 3.2). L'épisode 6 devra en tenir compte : une session pilotée
laisse son répertoire de run à *chaque* exécution, ce qui explique une bonne part du tas de 359.

### 2026-08-20 — épisode 2 : le canal qui ne peut pas être servi fait refuser le démarrage

Le TODO ne voyait que le chemin trop long ; le correctif porte, comme prévu au § 3.4, sur **toute**
cause d'échec du canal.

**Le geste, en deux endroits.** La borne est une propriété de l'**argument** : elle se vérifie là
où l'option est lue. `Initialization.check_control_socket_path` (`bin/initialization.ml`) refuse un
chemin relatif ou plus long que **107 octets** (`sun_path` en tient 108, terminaison comprise), et
le refus tombe **avant toute fenêtre** — mesuré : sans `DISPLAY`, le binaire répond quand même. Les
causes qui ne se voient qu'au `bind` (répertoire non inscriptible, socket déjà servi) sont refusées
au même titre par `Control_server.start_if_requested`, qui écrit la raison sur **stderr** en plus
du journal et sort avec le code 1. `start` rend maintenant un `(unit, string) result` au lieu
d'avaler l'échec, et `prepare_socketfile` appelle la même fonction de validation (source unique de
la borne). Le détail d'exception est déballé (`explain_failure`) : `Network.Binding(_)` ne disait
rien à personne, on lit désormais `bind failed: bind: Permission non accordée`.

**Ce qui n'est pas fait, et pourquoi.** Aucune tentative de fermer un projet ouvert avant de
sortir : appelé depuis le thread GTK, `st#close_project` se contente de créer un thread
(`bin/state.ml`), que l'`exit` tuerait avant qu'il nettoie. Le répertoire de run éventuellement
laissé dans ce cas étroit reste l'affaire de l'épisode 6.

**Preuve** — premier banc **versionné** du chantier, `driven-sessions/control-socket-refusal.sh`
(le répertoire et son `README.md` naissent ici, cf. § 3.6). Quatre cas, dont le nominal en garde
anti-faux-positif ; les deux cas syntaxiques ne demandent **ni X ni sudo**.

| Cas | avant le correctif | après |
|---|---|---|
| chemin de 130 octets | démarre, aucun socket, jamais un mot | **exit 1**, stderr nomme la limite 107 et la longueur |
| chemin relatif | démarre | **exit 1**, « an absolute path is required » |
| répertoire non inscriptible | démarre en GUI seule | **exit 1**, « bind failed: … » |
| chemin servable | sert, `quit` → exit 0 | **inchangé** |

Rouge/vert mesuré en rejouant le banc sur le binaire d'avant (`git stash`) : `passed: 1, failed: 3`
— le seul PASS étant le cas nominal, qui montre que le banc n'est pas rouge par construction.
Après restauration : `passed: 4, failed: 0, skipped: 0`, `dune build` rc 0.

**Documentation** : `doc-src/scripting/README.md` gagne la phrase manquante (chemin absolu **et**
borné à 107 octets, refus de démarrer avec la raison sur stderr) et une ligne dans la table
« When it does not work ». L'entrée est **retirée** de `docs/TODO.md` : 13 défauts restants.

### 2026-08-20 — épisode 3 : un `add` refusé par son constructeur ne laisse plus rien

**Le geste, en un seul endroit.** Un nœud s'enregistre auprès du réseau **dans son initializer**
(`network#add_node (self :> node)`, `bin/user_level.ml:1138` et `:1231`), juste avant la suite qui
peut lever — pour un `switch` ou un `world_gateway`, `add_my_ledgrid` et son assertion. Le
rattrapage de `cmd_add` (`bin/control_server.ml`) se contentait de rapporter l'exception : le nœud
à moitié construit restait. Il **cherche désormais le nœud du nom demandé et le détruit**, dans la
**même** section critique `st#network_change` que la création — donc avant que le sketch ne soit
rafraîchi et avant que quiconque puisse lire le réseau.

Trois précisions que l'implémentation a imposées :

- **`destroy` plutôt que `del_node_by_name`** : `destroy` (`OoExtra.destroy_methods`) rejoue les
  callbacks enregistrés **jusqu'au point de levée**, dans l'ordre LIFO — exactement ce que l'objet
  a eu le temps de faire (son inscription au réseau, sa ligne de défauts), et rien de plus. Retirer
  le nœud de la liste aurait laissé le reste.
- **`List.find_opt` plutôt que `get_node_by_name`** : ce dernier **lève** quand le nom est absent
  (`failwith`, `bin/user_level.ml:2071`), ce qui aurait remplacé une exception par une autre. C'est
  aussi le patron déjà employé vingt lignes plus bas dans `cmd_add`.
- **`try … with _ -> ()` autour du `destroy`** : un callback peut à son tour lire un champ que
  l'exception a laissé non posé. L'échec du nettoyage ne doit pas masquer l'échec initial, qui est
  ce que le client doit lire.

**Preuve** — banc versionné `driven-sessions/add-rollback-on-constructor-failure.sh`, quatre cas
joués dans une **seule** session pilotée (donc un `DISPLAY` et `socat`, sinon SKIP 77).

| Cas | avant le correctif | après |
|---|---|---|
| `add switch s0 --ports=0` | `ok:false` — et `s0` **figure dans `ls`** | `ok:false`, `s0` **absent** |
| `add world_gateway g99 --ports=99` | `ok:false` — et `g99` figure dans `ls` | `ok:false`, `g99` absent |
| `add switch s0` juste après le refus | `ok:false` — « the name "s0" is already used » | `ok:true`, `s0` reconstruit |
| `add hub h1 --ports=8` (anti-faux-positif) | `ok:true` | **inchangé** |

Rouge/vert mesuré : `passed: 1, failed: 3` sur le binaire d'avant, `passed: 4, failed: 0` après ;
`dune build` rc 0 ; le banc de l'épisode 2 rejoué **4 PASS** (non-régression) ; aucun répertoire de
run laissé (le banc retire **ceux qu'il a créés**, jamais un glob entier).

Le troisième cas est le plus fort des quatre : il ne dit pas seulement que `ls` ne montre plus le
nœud, mais que le **nom est libre** — c'est-à-dire que le réseau est bien celui d'avant, et qu'un
script peut réessayer sous le même nom.

**Documentation** : `doc-src/scripting/README.md` gagne la puce qui manquait — un `add` refusé, pour
**quelque** raison que ce soit, laisse le réseau tel quel et le nom libre. L'entrée est **retirée**
de `docs/TODO.md` : 12 défauts restants.

**Observé en chemin, non corrigé** (règle § 2) : l'entrée de l'épisode 4 (`add … --ports=N` ne
vérifie pas les bornes) devient franchement plus simple, puisque « construire, vérifier, détruire »
peut maintenant s'appuyer sur un rattrapage qui détruit vraiment. Rien d'autre n'a été touché.
