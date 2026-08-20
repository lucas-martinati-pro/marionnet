# Chantier `marionnet-todo-transverse` — solder la TODOLIST transverse

> **Objectif.** Traiter, une par une et **chacune avec au moins un commit**, les entrées de
> défaut de `docs/TODO.md` (15 à l'ouverture, **16** depuis l'épisode 5, cf. § 1) : ce qui a été repéré au fil des chantiers, jugé réel, et laissé de
> côté parce qu'il n'appartenait à aucun d'eux. Une entrée est *soldée* quand son symptôme est
> rejoué rouge avant / vert après, et **retirée de `docs/TODO.md` dans le commit qui la clôt**.

Ouvert le 2026-08-20. Reprise : appliquer le skill `chantier-long` (MODE B).

---

## 1. Périmètre

Les **15 entrées de défaut** de `docs/TODO.md`, à la date d'ouverture. Chacune y porte déjà son
constat, ce qu'on veut à la place, et l'obstacle repéré : ce document ne recopie pas cette
analyse, il porte **les décisions de cadrage** (§ 3) et **l'ordre d'exécution** (§ 4).

**Devenues 16 le 2026-08-20** : l'épisode 5 a mesuré, sans le corriger, le défaut **jumeau** de
celui qu'il soldait (`set … variant <inexistante>` au lieu de `distrib`) et l'a écrit au TODO,
comme l'exige le § 2. Un défaut écrit par ce chantier lui revient : cette 16ᵉ entrée est entrée
dans le périmètre, et comme elle était la moins coûteuse des restantes, elle a pris le rang 7 —
les épisodes non encore joués se décalant d'autant.

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

> **Corrigé à l'épisode 10, par la mesure.** Ce paragraphe annonçait que deux entrées
> (`wait --ready` au second démarrage, `rc-set` sur un switch) avaient **une seule** cause. C'est
> faux, et la moitié qui l'est comptait : une **machine** et un **routeur** *détruisent* leur
> device simulé en s'éteignant (`machine.ml`, `router.ml`, `#poweroff_right_now` →
> `destroy_right_now`, « so that the next time we have to re-create the process command line can
> use a new cow file » — du code de 2013), donc leur hostfs **est** réécrit à chaque démarrage.
> La famille n'a jamais compté qu'un membre : les natures qui n'ont pas de fichier cow à renouveler
> (le switch, et ses voisins), qui gardent bien leur device d'un démarrage à l'autre.
> Le vrai défaut de `wait --ready` était **une course**, pas un état figé : cf. le journal § 5,
> épisode 10.

Ce qui reste vrai : pour les natures **sans** fichier cow, `poweroff` arrête les processus mais
**ne détruit pas** l'objet device simulé, si bien que tout ce qu'un `initializer` calcule n'est
calculé **qu'une fois**.

Décision : **remède local**, nature par nature — pour le rc du switch, une **fonction** plutôt
qu'une valeur au constructeur du device. L'automate d'état n'est **pas** rouvert
(`docs/refonte-automate-composants.md`, clos).

La voie de fond — *le device simulé ne survit pas au `poweroff`* — guérirait la famille entière
pour les huit natures, mais suppose d'établir d'abord ce qui **doit** survivre à l'extinction
(identité, fichier cow, descripteurs de journaux, numéro d'instance, câbles branchés) : c'est
précisément pourquoi l'objet survit aujourd'hui. Ce n'est pas un correctif, c'est un chantier.
**La famille est nommée ici** pour qu'un futur passage sache où regarder — en sachant désormais
qu'elle **exclut** machines et routeurs.

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
*`distrib` inexistante*, *`--control-socket` trop long* — **cinq** depuis l'épisode 7, qui y a
ajouté *`variant` inexistante* (le titre de ce paragraphe, écrit avant la correction ci-dessous,
redevient exact par accident), et **six** depuis l'épisode 11.

> **Corrigé à l'épisode 11**, sur le critère lui-même et non sur son application : la table du § 4
> annonçait un banc **jetable** pour le rc du switch, « parce qu'il faut démarrer quelque chose ».
> Démarrer n'est pas la question — le critère dit *invité* et *privilège*. Un switch n'a ni l'un ni
> l'autre : `vde_switch` est un processus utilisateur ordinaire, et le banc est **versionné**. Six,
> donc, et une leçon : *ce qui décide n'est pas qu'une session tourne, mais ce qu'elle exige de la
> plateforme.*

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

## 4. Les 16 épisodes, par coût croissant

L'ordre est celui du coût, pas de la gravité : les correctifs courts d'abord, les diagnostics
ouverts à la fin. Une dépendance seulement : l'ép. 1 crée `driven-sessions/`. (On en annonçait
deux : l'ép. 4 devait s'appuyer sur le rollback de l'ép. 3 — il ne l'a finalement **pas** fait,
cf. § 5, la vérification tombant *avant* la construction.)

| N | Entrée de `docs/TODO.md` | Geste | Preuve |
|---|---|---|---|
| 1 | Le **label** se valide trop tard | `check_new_label` avant la première écriture des deux `update_with` (`bin/user_level.ml`), comme `check_new_name` | jetable (**patch témoin**, cf. § 3.6) — **fait** |
| 2 | `--control-socket` trop long échoue en silence | Refus de démarrer généralisé + contrôle de longueur avant le `bind` (§ 3.4) | `driven-sessions/control-socket-refusal.sh` — **fait** (crée le répertoire et son README) |
| 3 | Un constructeur qui échoue laisse son nœud | Le rattrapage d'`add` cherche le nœud du nom demandé et le détruit, dans la même section critique | `driven-sessions/add-rollback-on-constructor-failure.sh` — **fait** |
| 4 | `add … --ports=N` ne vérifie pas les bornes | Vérifier **avant** de construire, dans `node_maker`, contre les `Const.port_no_{min,max}` que le constructeur reçoit déjà | `driven-sessions/add-ports-bounds.sh` — **fait** |
| 5 | `set … distrib <inexistante>` accepté sans rien changer | `bad_argument` nommant les distributions installées, patron de `supported_kernels_if_any` | `driven-sessions/set-distrib-unknown.sh` — **fait** |
| 6 | Les répertoires de run ne sont balayés par personne | Signalement au démarrage + suggestion de `marionnet-cleanup` (§ 3.2) | banc jetable — **fait** |
| 7 | `set … variant <inexistante>` accepté sans rien changer (entrée neuve, cf. § 1) | `bad_argument` nommant les variantes du filesystem **courant**, et refus du `set distrib` qui ferait perdre la variante portée | `driven-sessions/set-variant-unknown.sh` — **fait** |
| 8 | `uml_mconsole … sysrq e` peut rester bloqué | Échéance sur la tentative mconsole, durée **mesurée** sur un invité sain | banc jetable (invité) — **fait** |
| 9 | Deux sessions partagent l'adresse hôte de leurs taps | **Détection** et message ; l'adresse n'est pas dérivée (contrat réseau de `marionnet-daemon-elimination`) | banc jetable — **fait** |
| 10 | `wait --ready` ment au second démarrage | **Révisé par la mesure** : la cause n'était pas un hostfs figé mais une **course** avec un `start` asynchrone — `--ready` n'accorde plus foi à un marqueur tant que le composant ne tourne pas ; plus le `O_TRUNC` manquant | banc jetable (invité) — **fait** |
| 11 | Un `rc-set` sur un switch n'est pris qu'au premier démarrage | Fonction plutôt que valeur au constructeur du device (§ 3.5) | `driven-sessions/switch-rc-after-poweroff.sh` — **fait** (banc **versionné**, contre l'annonce « jetable » : cf. § 3.6) |
| 12 | Un routeur neuf naît avec un noyau inutilisable | Voie (b) pleine (§ 3.3) | banc jetable, **toutes** les natures |
| 13 | Les autres fenêtres de message s'étalent sur toute la largeur | Plafonds dans le glade et en OCaml, **message par message** (des `\n` manuels préexistent) | run GUI, captures |
| 14 | Griser « Enregistrer » / « Sous » / « Copier vers » | Quatrième pile de sensibilité + source de notification aux transitions | run GUI |
| 15 | En arbre de dev, Marionnet lit le catalogue d'un AUTRE Marionnet | **Instrumenter d'abord** (le `Log.printf` de `gettext.ml:59` est écrit avant que le journal soit prêt, donc perdu) ; fusible § 3.1 | `strace -e openat` |
| 16 | Le rapport de fin de session n'est pas garanti | **Mesurer d'abord** le délai marqueur → hook ; fusible § 3.1 | banc jetable (invités) |

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

---

### 2026-08-20 — épisode 4 : `add … --ports=N` refuse ce que `set … port_no` refuse

**Le défaut.** `cmd_add` (`bin/control_server.ml`) ne vérifiait que `N ≥ 0` puis passait la valeur
au constructeur : `add machine m0 --ports=0`, `add machine m99 --ports=99` et
`add nat_bridge n --ports=0` étaient **acceptés**, alors que `set <n> port_no <N>` refuse les mêmes
valeurs proprement. Deux natures s'en tiraient par accident, en **mourant** sur `assert (ports > 1)`
de `bin/gui/ledgrid.ml:320`.

**Le geste, et pourquoi il n'est pas celui annoncé.** L'ouverture du chantier prévoyait
« construire, vérifier, détruire », pour éviter une seconde table `kind → (min,max)`. Vérification
faite, c'était le mauvais choix, pour trois raisons :

- **il n'y a pas de seconde source de vérité à créer.** `node_maker` est déjà « le seul endroit de
  ce fichier qui connaît les huit natures par leur nom », et il lit déjà
  `<Kind>.Const.port_no_default` dans chaque branche. Or `Const.port_no_min` / `Const.port_no_max`
  sont **exactement** les valeurs que chaque `user_level` passe à `node_with_ports_card`
  (`machine.ml:591`, `hub.ml:309`, `switch.ml:409`, `router.ml:1077`, `world_gateway.ml:384`,
  `cloud.ml:269`, `nat_bridge.ml:769`, `bridge_common.ml:105`), et que `n#port_no_min` — la borne
  que lit `set` — se contente de **renvoyer** (`user_level.ml:984`). Lire la constante ou
  interroger l'objet, c'est lire la même chose ;
- **construire d'abord ne peut pas refuser poliment là où ça compte** : `--ports=0` sur une nature
  à ledgrid tue le constructeur, donc le client recevrait un `Assert_failure` au lieu d'une
  phrase — précisément ce que l'entrée du TODO dénonçait ;
- **rien n'est perdu à vérifier tôt** : un nœud qui n'existe pas encore n'a aucun câble, donc la
  borne basse *effective* de `set` (`network#port_no_lower_of`, `user_level.ml:2152`) vaut
  exactement `port_no_min` à la création. Les deux portes du modèle comparent bien la même chose.

D'où un helper local `with_ports ~min ~max ~default` dans `node_maker` : il refuse hors bornes
(`Error`, donc `Co_bad`, sans que le réseau soit touché) et, sinon, résout le nombre de ports et
rend la fonction de construction. Le message du dépassement **haut** est factorisé avec celui de
`cmd_set` (`too_many_ports ~kind ~max`) : la même phrase, quelle que soit la porte à laquelle le
client frappe. Le message du dépassement **bas** est propre à `add` et commenté : `set` énonce
trois raisons possibles, dont **une seule** peut valoir pour un composant qui n'existe pas encore
(rien n'est câblé, et la seule nature de taille fixe — le cloud — n'accepte pas `--ports` du tout).
Le contrôle syntaxique de l'option (`--ports=abc`, `--ports=-3`) reste en amont, dans `cmd_add`.

**Preuve** — banc versionné `driven-sessions/add-ports-bounds.sh`, onze cas dans une **seule**
session pilotée (donc un `DISPLAY` et `socat`, sinon SKIP 77).

| Cas | avant le correctif | après |
|---|---|---|
| `add machine m0 --ports=0` | `ok:true` — machine à **0 port** | `ok:false`, `m0` absent |
| `add machine m99 --ports=99` | `ok:true` — machine à **99 ports** | `ok:false`, `m99` absent |
| `add hub h3 --ports=3` | `ok:true` | `ok:false`, `h3` absent |
| `add nat_bridge n0 --ports=0` | `ok:true` | `ok:false`, `n0` absent |
| `add machine m1 --ports=1` / `m8 --ports=8` / `router r16 --ports=16` (bornes **incluses**) | `ok:true` | **inchangé** |
| `add cloud c0 --ports=2` | `ok:false` (« fixed number of ports ») | **inchangé** |
| `add machine m8 --ports=99` **et** `set m8 port_no 99` | l'un accepte, l'autre refuse | **la même phrase** des deux côtés |

Rouge/vert mesuré : `passed: 6, failed: 5` sur le binaire d'avant, `passed: 11, failed: 0` après ;
`dune build` rc 0 ; bancs des épisodes 2 et 3 rejoués verts (non-régression).

**Le banc de l'ép. 3 a été complété, et il le fallait** : ses deux cas (`switch --ports=0`,
`world_gateway --ports=99`) étaient les seuls à faire lever un constructeur *via* `add`, et cet
épisode les intercepte désormais **avant** la construction — le rattrapage de l'ép. 3 se serait
retrouvé sans aucune preuve, en silence, tout en restant vert. Un troisième cas l'exerce donc pour
de bon : `add machine m-1`, dont le nom est refusé par `check_name` (`user_level.ml:521`) **après**
que le nœud se soit inscrit au réseau. Mesuré : `ok:false`, et `ls` reste vide. C'est la leçon de
méthode de l'épisode — **un correctif qui déplace une garde en amont peut vider de sa substance le
banc d'un épisode antérieur sans jamais le faire échouer**.

**Documentation** : `doc-src/scripting/README.md` gagne la puce des bornes de `--ports`, et son
exemple de constructeur qui échoue (devenu faux) passe de `add switch s0 --ports=0` à
`add machine m-1`. L'entrée est **retirée** de `docs/TODO.md` : 11 défauts restants.

**Observé en chemin, non corrigé** (règle § 2) : rien. Le contrôle syntaxique `--ports` non entier
double désormais partiellement la borne basse (un négatif est refusé par le parseur avant de l'être
par la borne) ; c'est un doublon inoffensif — le message du parseur est plus précis pour
`--ports=abc` — et non un défaut à inscrire.

### 2026-08-20 — épisode 5 : un filesystem non installé est refusé, plus remappé en silence

**Le geste, en deux couches, sur le patron du noyau (ép. 4f de `pilotage-par-script`).** Le modèle
n'apprend rien de neuf : il **publie** seulement ce qu'il savait déjà. `User_level.component` gagne
`installed_distribs_if_any : string list option` (`None` par défaut — « cette nature n'a pas de
filesystem » est une **réponse**, pas un trou), redéfinie dans `machine.ml` et `router.ml` par
`Some vm_installations#filesystems#get_epithet_list` : chacune tient **son** jeu d'installations,
et cette liste est littéralement celle que propose le combo de la GUI (`gui_bricks.ml`,
`distribution_choices`), déjà débarrassée par `disk.ml` des filesystems sans noyau compatible. La
méthode est **en lecture seule**, exactement comme `supported_kernels_if_any`, et pour la même
raison : le modèle **doit** continuer d'accepter une épithète absente, sinon un `.mar` qui en nomme
une devient inouvrable.

Le refus vit donc dans le serveur, qui possède le message : `unknown_distrib`
(`bin/control_server.ml`), jumelle de `unsupported_kernel`, appelée aux **deux** portes qui
écrivent — `cmd_set` et `cmd_add` — chacune passant d'un `if … = "kernel"` à un `match` sur le nom
du champ. Dans `cmd_add`, la garde tombe avant l'écriture, donc le rattrapage de l'ép. 3 rend le
réseau intact. `remap_absent_distrib_at_import` n'est **pas** touchée : son comportement est correct
pour l'import, qui est sa raison d'être — la consigne du TODO est respectée à la lettre.

**Preuve** — banc versionné `driven-sessions/set-distrib-unknown.sh`, six cas dans une seule
session pilotée (donc un `DISPLAY` et `socat`, sinon SKIP 77). Il ne connaît **aucun** chemin
d'installation : la liste des filesystems, il la lit dans le refus lui-même — la garde nomme ce
qu'elle accepterait, ce qui lui évite une seconde source de vérité.

| Cas | avant le correctif | après |
|---|---|---|
| `set m1 distrib pas-une-distrib` | `ok:true`, `changed:false` — rien écrit, rien dit | `ok:false`, la valeur fautive **et** la liste des installés ; `m1` inchangé |
| `add machine m2 --distrib=pas-une-distrib` | `ok:true` — machine créée sur le filesystem par défaut | `ok:false`, `m2` absent du réseau |
| `add router r2 --distrib=pas-une-distrib` | `ok:true` | `ok:false`, `r2` absent (un routeur a **ses** filesystems) |
| `set m1 distrib <son propre filesystem>` | `ok:true` | **inchangé** (anti-faux-positif) |
| `set m1 kernel pas-un-noyau` | `ok:false` | **inchangé** (garde de l'ép. 4f, qui partage les deux sites d'appel) |
| `set m1 distrib <un autre installé>` | *non jouable* : sans refus, le banc n'a pas de liste → SKIP | `ok:true`, relu depuis le modèle (`debian-trixie-47362` → `debian-wheezy-08367`) |

Rouge/vert mesuré : `passed: 2, failed: 3, skipped: 1` sur le binaire d'avant (`git stash` +
`dune build`), `passed: 6, failed: 0, skipped: 0` après restauration ; `dune build` rc 0.

**Documentation** : `doc-src/scripting/README.md` gagne la puce « `distrib` et `kernel` doivent
exister », qui dit aussi ce que la règle **n'est pas** (le chargement d'un `.mar` continue de
remapper). `driven-sessions/README.md` gagne deux lignes : celle de ce banc **et** celle de
`add-ports-bounds.sh`, oubliée à l'épisode 4.

**Observé en chemin, non corrigé** (règle § 2) : `variant` a **exactement** le même défaut, mesuré
au canal — `set m1 variant pas-une-variante` répond `ok:true`/`changed:false` et
`add machine m3 --variant=pas-une-variante` construit une machine sans variante. Écrit dans
`docs/TODO.md` comme entrée neuve, avec les trois obstacles qui l'empêchent d'être une copie de
cette garde (la liste dépend du filesystem **courant**, `""` et `aucune` sont des valeurs
légitimes, et il faut une sixième méthode dans les 5 types de classes de `user_level.mli`).
L'entrée `distrib` est **retirée** de `docs/TODO.md` : 10 défauts restants au périmètre du
chantier, plus le voisin qui vient d'y entrer.

### 2026-08-20 — épisode 6 : les répertoires laissés par les sessions passées se disent

Rien ne balaie les `<tmp>/marionnet-<n>.dir/`. Le geste décidé au § 3.2 est tenu **tel quel** :
Marionnet **dit** combien il y en a et **nomme l'outil**, il n'en retire **aucun**.

**Le geste, en un seul endroit.** `bin/marionnet.ml`, juste après le bloc qui arrête le répertoire
temporaire — donc en connaissant le répertoire **réellement retenu** (`MARIONNET_TMPDIR`,
`TMPDIR`, `/tmp`, `/var/tmp`, …), jamais `/tmp` en dur. Le compte porte sur les entrées de nom
`marionnet-*.dir` qui **nous appartiennent** (`st_uid`, `/tmp` est partagé). Journal toujours,
dialogue sauf en **mode examen** (un élève n'a pas de ménage à faire) et sauf si l'avertissement
est éteint — 4ᵉ drapeau `MARIONNET_DISABLE_WARNING_ORPHAN_RUN_DIRECTORIES`, patron exact de
`temporary_working_directory_automatically_set` (déclaré aussi dans `bin/configuration.ml`, sans
quoi la variable n'existe pas, et documenté dans `etc/marionnet.conf`).

**Ce que le message ne dit pas, et pourquoi.** Il ne prétend **pas** que ces répertoires sont
morts. Décider lequel est encore servi demande de lire `/proc` — ce que
`useful-scripts/marionnet-cleanup` fait déjà, correctement ; le refaire en OCaml serait une
seconde source de vérité au service d'un message dont le seul but est de **passer la main à ce
script**. Le message dit donc le nombre, le répertoire, le fait que certains peuvent appartenir à
un Marionnet en cours, et la commande. Pas de taille non plus : un `du` sur 359 répertoires au
démarrage se paierait à chaque lancement, et le script l'affiche, lui.

**Preuve** — banc **jetable** (`rundirs-notice.sh`) : le signal tombe **après**
`GtkMain.Main.init`, il exige donc un `DISPLAY` (piège de l'ép. 2), ce qui l'exclut de
`driven-sessions/` (§ 3.6). Chaque cas est une session pilotée complète, lue par la commande
`notifications` du canal — `Simple_dialogs.warning` passe par `capture_and_dismiss`, qui notifie
le script et referme la fenêtre tout seul.

| Cas | avant le correctif | après |
|---|---|---|
| répertoire temporaire vide | rien | rien |
| 3 répertoires (+ 1 nom mal formé, + 1 fichier homonyme) | **rien** | notification `warning`, compte **3**, répertoire et outil nommés |
| les 3 répertoires après coup | intacts | **intacts** (Marionnet n'en retire aucun) |
| `MARIONNET_DISABLE_WARNING_ORPHAN_RUN_DIRECTORIES=true` | rien | rien (journal seul) |
| répertoire d'un autre uid | *non jouable sans privilège* | SKIP, jamais maquillé |

Rouge/vert mesuré : `passed=3 failed=1 skipped=1` sur le binaire d'avant (`git stash` +
`dune build`), `passed=4 failed=0 skipped=1` après restauration. Les trois cas qui passent des
deux côtés sont les gardes anti-faux-positif : sans correctif ils passent **à vide**, c'est leur
rôle.

**i18n : les 2 chaînes neuves traduites ici même** (décision prise en cours d'épisode). L'ép. 9b de
`modernisation-world-bridge` venait de rétablir l'invariant « on ne supporte que des catalogues
complets » (423/423 aux 12) ; un dialogue neuf non traduit l'aurait cassé le jour même. Refresh POT
(`make gettext-update-po`) → exactement **2 trous** par catalogue, puis versement par
**`msgmerge --compendium`** (aucune édition à la main des 12 fichiers), essai à blanc d'abord :
le diff ne touche **que** les 2 entrées. Résultat **425 traduits, 0 trou** aux 12, `msgfmt -c`
propre. Gardes rejouées : audit d'arité sur les **12 catalogues entiers** (5 100 entrées, 0 écart,
regex excluant `%%` et le drapeau espace — cf. les 7 faux positifs de l'ép. 9b), parse **Pango réel**
des 24 traductions (48 parses : le corps tel quel et le titre enveloppé de `<b>…</b>` comme le fait
`simple_dialogs.ml`), et interrogation des **`.mo` compilés** par clé exacte, les 12 répondent.
Contrainte de fond respectée : OCaml n'a **pas** d'arguments positionnels dans `Printf`, donc
l'ordre `%s` (le répertoire) puis `%d` (le compte) est le **même** dans les 12 traductions ; une
langue dont l'ordre naturel diffère se **reformule**, elle ne se réordonne pas.

Un mot sur ce libellé, qui a été **refait** en cours d'épisode : la première rédaction disait
`%d run directories are lying in %s`, ce qui donne « 1 run directories » dès qu'il n'y a **qu'un**
répertoire — le cas le plus courant, celui du crash unique. Marionnet n'utilise pas `ngettext`
(et l'introduire imposerait les formes plurielles aux 12 catalogues) : le compte est donc passé
**en fin de phrase, après un deux-points**, où aucun nom ne s'accorde avec lui. Les 12 traductions
ont été refaites sur ce libellé (POT rejoué, compendiums réécrits) plutôt que gardées avec la
faute — un `msgid` faux coûte les mêmes 12 traductions le jour où on le corrige.

**Ce que la preuve ne peut pas montrer ici** : le texte **français à l'écran**. Mesuré au
`strace -e openat` : un binaire de `_build` ouvre `/usr/share/locale/fr/LC_MESSAGES/marionnet.mo`
et jamais le catalogue du dépôt — c'est l'entrée i18n de `docs/TODO.md`, épisode **15** de ce
chantier même (numéroté 14 quand ces lignes ont été écrites : l'épisode 7 a décalé les rangs). La preuve des traductions est donc celle de l'ép. 9b : le `.mo` compilé, interrogé
par clé exacte.

**Ce qui n'est pas fait, et pourquoi.** (a) Le `quit` **du canal** continue de laisser son
répertoire. Le lui faire nettoyer contredirait la politique de cet épisode : le *Quitter* de la GUI
ne le retire qu'**après** avoir proposé d'enregistrer, ce que le canal ne fait pas — il détruirait
donc la copie non enregistrée au lieu de la signaler. (b) `useful-scripts/marionnet-cleanup`
**n'est installé par aucune cible** (vérifié : aucune occurrence dans `Makefile*`), d'où le message
qui le nomme par son emplacement dans les sources. Le défaut d'installation est **écrit** au
chantier `modernisation-installation-marionnet` (§ 2.4 ter, qui liste déjà les outils non
installés), pas corrigé ici.

L'entrée « Hygiène — les répertoires de run » est **retirée** de `docs/TODO.md` : 9 défauts
restants au périmètre du chantier, plus le voisin `variant` entré à l'ép. 5.

### 2026-08-20 — épisode 7 : une variante inexistante est refusée, plus avalée

Le défaut **jumeau** de l’épisode 5, un attribut plus loin, et écrit au TODO par lui : `set m1
variant pas-une-variante` répondait `ok:true / changed:false`, et `add machine m3
--variant=pas-une-variante` construisait une machine dont le champ `variant` valait `""`. Même
cause : `eval_forest_attribute ("variant", x)` passe par `remap_absent_variant_at_import`
(`bin/user_level.ml`), écrite pour le **chargement d'un `.mar`** — une variante disparue avec son
filesystem ne doit pas rendre le projet inouvrable, le composant retombe sur le filesystem vierge.
Sur une écriture explicite, c'est une faute de frappe transformée en no-op poli.

**Le geste, patron de l'ép. 5.** Le modèle publie, le serveur refuse : une méthode de lecture
`variants_of_distrib_if_any` sur `component` (`None` par défaut), redéfinie dans `machine.ml` et
`router.ml`, et déclarée dans les 5 types de classes de `user_level.mli` plus `machine.mli`. Elle
prend **une épithète de filesystem en argument**, et non « le courant », parce que les deux gardes
du serveur n'ont pas besoin du même : `unknown_variant` interroge le filesystem **courant**,
`variant_lost_by_distrib_change` le filesystem **cible**. Elle est gardée : `#variants_of` est un
`String_map.find` (`bin/disk.ml`) qui **lève** sur une épithète non installée.

**La décision prise en cours d'épisode** (question posée avant d'écrire une ligne) : le cas croisé
— un `set distrib` ultérieur rend inexistante la variante déjà posée — est **refusé**, plutôt que
de laisser tomber la variante en silence, ce qui serait exactement le défaut soldé ici, un attribut
plus loin. La GUI n'a jamais à répondre à cette question (elle verrouille les deux combos une fois
le device créé) ; le canal, si. L'ordre des commandes devient donc contraignant, et le message dit
comment en sortir.

**Un fait mesuré qui a changé le message.** `""` n'est **pas** transmissible par le canal : une
requête est découpée sur les espaces et les jetons vides sont jetés (`parse_request`), et `set m1
variant` échoue sur l'arité de `set`. Le seul mot qui retire une variante est donc `aucune`
(`bin/machine.ml`, branche de rétro-compatibilité) — les messages le nomment, au lieu de la chaîne
vide qu'ils désignaient d'abord.

**Preuve** — banc **versionné** `driven-sessions/set-variant-unknown.sh`, cinquième du répertoire,
et le premier à jouer **deux sessions** : une variante doit *exister* pour prouver le cas nominal
et la garde croisée, or la liste des filesystems installés n'est connue qu'une fois une session
lancée. Le banc pilote donc le binaire avec `HOME` **détourné dans son propre répertoire
temporaire** et y fabrique une variante entre les deux sessions (un fichier vide sous
`$HOME/.marionnet/filesystems/machine-<épithète>_variants/` : `read_epithet_list` prend tout
non-répertoire, et le répertoire utilisateur est bien dans la liste de recherche). Effet de bord
recherché : les variantes de l'hôte deviennent **invisibles** au run, donc le banc est
déterministe, et rien n'est écrit hors du temporaire.

| | correctif désarmé | correctif en place |
|---|---|---|
| `set m1 variant pas-une-variante` | `ok:true`, `changed:false` | `ok:false`, variante inchangée |
| `add machine m2 --variant=…` | `ok:true`, m2 construite | `ok:false`, m2 absente du réseau |
| `add router r2 --variant=…` | `ok:true`, r2 construite | `ok:false`, r2 absente |
| `set m1 distrib <autre>` en portant une variante | `ok:true`, variante perdue | `ok:false`, puis accepté après `variant aucune` |

Mesure rouge/vert : **4 FAIL / 4 PASS** sur le code d'avant (`git stash` du seul `bin/`, rebuild),
**9 PASS / 0 FAIL / 0 SKIP** après. Non-régression : les 4 bancs versionnés antérieurs rejoués
verts (11 + 5 + 4 + 6 PASS), la branche `distrib` du serveur ayant dû être réécrite pour porter
deux refus. `dune build` rc 0. Aucun processus survivant, aucun `/tmp/marionnet-<n>.dir/` laissé
par les runs (vérifié : le plus récent des 20 restants date de six heures avant la séance).

**Observé en chemin, non corrigé** (règle § 2), et **mesuré** plutôt que déduit : `set r1 variant
aucune` sur un **routeur** dépose un avertissement d'import (`import remapping: router "r1":
variant "aucune" removed`), là où une machine n'en dépose aucun — `bin/router.ml` n'a pas la
branche `("variant", "aucune")` de `bin/machine.ml`. Ces avertissements ne sont pas jetés : ils
s'empilent et sont lus **à la fin du prochain chargement de projet**, qui les présentera comme
siens. Entrée neuve dans `docs/TODO.md` (« un `set` explicite peut déposer un avertissement
d'import hors de tout import »), qui vaut au-delà de ce seul mot : `eval_forest_attribute` est le
même chemin pour l'import et pour le canal.

L'entrée « Canal — `set <n> variant <épithète inexistante>` » est **retirée** de `docs/TODO.md` :
9 défauts restants au périmètre du chantier, plus le voisin entré ici.

---

### 2026-08-20 — épisode 8 : une tentative mconsole a une échéance, et le dit

**Le défaut.** `bin/simulation_level.ml`, méthode `gracefully_terminate_with_mconsole` : un seul
site, qui lance `uml_mconsole <umid> <commande>` par `/bin/sh` **sans échéance**. Un invité qui
n'a plus de noyau pour répondre laisse `uml_mconsole` attendre pour toujours — cinq d'entre eux,
échelonnés sur plusieurs jours, avaient été relevés à l'ouverture du chantier.

**Ce que la mesure a corrigé du constat.** Le TODO disait « un noyau **mort ou gelé** ». Les deux
cas ne se ressemblent pas :

| situation de l'invité | réponse de `uml_mconsole` |
|---|---|
| sain, `version` (inoffensif) | OK en **3 ms** (100 relevés, max 7 ms) |
| sain, `cad` | OK en **3 ms**, et la machine s'éteint pour de bon |
| sain, `halt` | OK en **4 ms**, processus disparu dans la foulée |
| sain, `sysrq e` / `sysrq i` | OK en **9 ms** / 3 ms — mais le noyau 6.12.95 répond `sysrq: This sysrq operation is disabled.` |
| boot précoce (socket pas encore créé) | échec en **5 ms** (`No such file`) |
| processus **mort**, socket résiduel | échec en **10 ms** (`Connection refused`) |
| noyau **gelé** (`SIGSTOP`) | **aucune réponse** — mesuré 30 s, puis 44 s sur le banc, sans fin |

Autrement dit : ce n'est pas la commande destructrice qui tue le noyau avant sa réponse (l'idée la
plus naturelle, mesurée fausse : `halt` répond *puis* la machine meurt), et ce n'est pas non plus
un socket résiduel (refusé aussitôt). **Seul le noyau gelé bloque**, et il bloque *tout*, y
compris un `version`.

**Le geste.** `timeout <t> uml_mconsole …` (coreutils) et, pour `t`, **2 s** : deux cents fois le
pire cas mesuré sur un invité sain, donc hors d'état de transformer un arrêt propre lent en kill
brutal ; et le pire cas de `gracefully_terminate` (5 `cad` puis 3 `halt`, soit `8·t + 11` s) reste
**sous les 30 s** du fil de garde que cette méthode démarre elle-même. La branche d'échec **dit
désormais laquelle** : `no answer after 2 s` (code 124 de `timeout`) au lieu d'un « failed » qui
confondait « a répondu non » et « attend encore » — c'était précisément ce que le code ne savait
pas.

**Plus grave que ce que l'entrée disait.** Le TODO ne parlait que de processus qui s'accumulent.
Mesuré : sur un invité gelé, `poweroff` (chemin `terminate`) restait bloqué à sa **première**
tentative (`sysrq e`), donc n'atteignait jamais son `kill` — l'invité gelé n'était **jamais tué**.
Contrairement à `gracefully_terminate`, `terminate` n'a pas de fil de garde à 30 s. Le correctif
règle les deux d'un coup.

**Preuve** — banc **jetable** (il faut un invité qui boote, donc hors des critères de
`driven-sessions/`) : session pilotée par le canal, machine démarrée, noyau **gelé** par
`kill -STOP` sur le pid du processus UML, puis `poweroff` par le canal.

| | correctif désarmé | correctif en place |
|---|---|---|
| `uml_mconsole` survivants 15 s après | **2** (le `/bin/sh` et son `uml_mconsole`) | 0 |
| processus UML gelé | **toujours vivant** | tué |
| journal | rien sur l'attente | 3 lignes `no answer after 2 s` |

Mesure rouge/vert : **0 PASS / 3 FAIL** sur le code d'avant (`git stash` du seul `bin/`, rebuild),
**3 PASS / 0 FAIL** après. Non-régression : les 5 bancs versionnés rejoués verts (11 + 5 + 4 + 6 +
9 PASS). `dune build` rc 0. Aucun processus ni répertoire de run laissé par les runs de mesure
(vérifié par pid exact).

**Vérifié, donc non écrit au TODO** : l'autre site du dépôt qui lance `uml_mconsole`
(`bin/serial.ml`, `config <con>` pour retrouver un `/dev/pts`) a le même défaut *en théorie*, mais
`grep` ne lui trouve **aucun appelant** — module mort. Rien à corriger, et une entrée de TODO
l'aurait présenté comme un bug actif.

**Observé en chemin, non corrigé** (règle § 2) : les répertoires `~/.uml/<umid>/` créés par les
noyaux UML **survivent à la session** et ne sont balayés par personne — onze traînaient ici, dont
des `probe-*` du 11 août ; `useful-scripts/marionnet-cleanup` ne connaît que
`/tmp/marionnet-*.dir`. C'est le jumeau, côté `$HOME`, de l'entrée soldée à l'épisode 6. Entrée
neuve dans `docs/TODO.md`.

L'entrée « Invités — un `uml_mconsole … sysrq e` peut rester bloqué **pour toujours** » est
**retirée** de `docs/TODO.md` : 8 défauts restants au périmètre du chantier, plus les deux voisins
entrés par les épisodes 7 et 8.

### 2026-08-20 — épisode 9 : deux sessions simultanées se disent

**Le défaut, dans son mécanisme.** L'entrée disait « rien ne le signale ». La lecture du code dit
*pourquoi* le second invité ne boote pas : `bin/simulation_level.ml:1067` dérive l'adresse `ip42`
d'un **identifiant de device**, compteur **par processus**, si bien que la première machine de
chaque session réclame la **même** `172.23.0.x` ; `Tap_provider.make_eth42_tap` finit par
`ip route add <ip42>/32 dev <tap>`, la seconde session reçoit un `File exists`, et le message
partait au **journal seul** avant que la machine démarre avec `"wrong-tap-name"` — c'est-à-dire
sans réseau, sans un mot à l'écran.

**Le geste, en trois endroits.**

1. `bin/tap_provider.ml(i)` — la détection. Les primitives d'inspection (`existing_taps`,
   `process_is_alive`, et le pid extrait du nom `mtap<pid>-<seq>`) **remontent** avant la section
   de création, où elles servent maintenant deux fois : `other_live_sessions ()` (les processus
   vivants **autres que nous** possédant des taps, avec leur compte) et
   `colliding_session_of_address` (qui détient déjà la route de cette adresse). La section de
   ramasse-miettes ne garde que `purge_orphan_taps`, son seul client historique.
2. `bin/marionnet.ml` — le signal au démarrage : journal `~force:true` toujours, dialogue sauf si
   l'avertissement est éteint.
3. `bin/simulation_level.ml` — le signal **au moment où la collision frappe** : journal forcé
   nommant l'adresse, le tap et le pid de l'autre session, et **un** dialogue, au premier échec
   seulement (`first_collision_report`, sous mutex : plusieurs machines échouent en parallèle et
   un dialogue par machine serait insupportable). Décision de l'utilisateur, prise avant d'écrire
   une ligne : l'autre session a pu démarrer **après** nous, donc le message du démarrage ne
   suffit pas.

**Ce que l'épisode ne fait pas, et pourquoi.** (a) L'adresse **n'est pas dérivée** du processus (le
« au mieux » de l'entrée) : c'est le contrat réseau hérité de `marionnet-daemon-elimination`, celui
qu'un TP écrit dans ses scénarios — non-objectif assumé, pas un reliquat. (b) Une machine dont le
tap échoue **continue de démarrer**, contre la doctrine « refuser plutôt qu'avaler » des épisodes
2-7 : sur un hôte où la règle sudoers n'est pas installée, refuser rendrait Marionnet inutilisable
d'un coup. Elle démarre, et elle le **dit**.

**Piège durable : ne pas mettre un diagnostic derrière une sonde de privilège.** Le bloc du
démarrage est délibérément **hors** du garde `Tap_provider.is_usable ()` qui l'entoure : lister les
interfaces (`ip -o link show`) ne coûte **aucun** privilège, alors que la purge des taps orphelins,
elle, en exige un. Conditionner le diagnostic au privilège aurait reproduit exactement ce qui a
rendu ce défaut invisible — et aurait rendu le banc injouable sur toute machine sans la règle.

**Preuve — deux étages.**

*Sans privilège, rejouable partout* (`bin/tap_provider_test.exe`, déjà branché sur `dune test`) :
la décision est prouvée sur des noms d'interface **fabriqués**, le processus étranger vivant étant
notre propre parent et le mort un fils déjà moissonné (`dead_pid`, qui existait). 7 vérifications :
liste vide, une session étrangère comptée une fois avec ses 2 taps au milieu de noms mal formés,
les taps d'un mort ignorés, les nôtres ignorés, et la lecture du `dev` d'une ligne de route.

*Banc jetable* (il exige un `DISPLAY` **et** la règle sudoers : hors `driven-sessions/` par le
§ 3.6). Il n'a besoin d'**aucun mot de passe** — fabriquer les taps d'une session étrangère est
précisément ce que la règle scopée autorise (`ip tuntap add dev mtap* mode tap user <moi>`) :

| cas | avant le correctif | après |
|---|---|---|
| 2 taps d'un pid **vivant** + 1 d'un pid **mort** | rien | notification `warning`, **1** session, pid nommé, le mort non compté |
| `MARIONNET_DISABLE_WARNING_OTHER_MARIONNET_SESSIONS=true` | rien | rien (journal seul) |
| le même drapeau, côté journal | **rien** | la ligne y est quand même |
| **collision réelle** : la route de `172.23.0.42` tenue par la session étrangère | tap refusé, raison brute | refusé, collision **nommée** (5 vérifications, `--live-collision`) |
| aucun tap étranger | rien | rien |

Rouge/vert mesuré : **2 PASS / 3 FAIL** sur le binaire d'avant (`git stash` + `dune build`),
**5 PASS / 0 FAIL** après restauration. Les deux cas qui passent des deux côtés sont les gardes
anti-faux-positif. Un faux vert a été corrigé en cours de route, et mérite d'être noté : le pilote
qui ne connaît pas `--live-collision` **retombe sur son essai à blanc et sort 0** — un banc ne peut
donc pas conclure sur le seul code de retour d'un binaire dont il teste une option neuve ; il lit
maintenant la vérification elle-même.

**La collision réelle, prouvée sans invité.** `--live-collision=<adresse>` est le mode neuf du
pilote : le banc fabrique le tap **et la route** de la session étrangère (les trois commandes sont
dans la règle sudoers), puis le pilote vérifie que la collision est reconnue, que le pid est celui
d'un autre vivant, qu'**aucun** tap n'est créé, que le tap étranger est intact et que la tentative
ratée n'a rien laissé. Reste hors de portée ici : le **dialogue** de collision à l'écran, qui exige
deux Marionnet avec des invités qui bootent.

**i18n : les 3 chaînes neuves traduites ici même** (invariant « on ne supporte que des catalogues
complets »). Refresh POT → exactement **3 trous** par catalogue : un titre, partagé par les deux
dialogues, et les deux corps. Versement par `msgmerge --compendium` (aucune édition à la main),
essai à blanc d'abord : le diff ne touche que ces 3 entrées, 12 à 15 lignes par catalogue. Les 12
passent à **428 traduits, 0 trou**. Le compte est en fin de phrase après un deux-points (leçon de
l'épisode 6 : pas de `ngettext` ici, donc jamais « 1 sessions ») et le vocabulaire suit l'habitude
de chaque catalogue (*session* → `Sitzung`, `сеанс`, `relácia`, `sesio`… ; *tap* → `Taps`,
`tap-uri`, `tapy`, selon ce qu'ils écrivaient déjà). Gardes rejouées : arité sur les **12
catalogues entiers** (5 136 entrées, 0 écart), parse **Pango réel** des traductions neuves (72
parses : le corps nu et le titre enveloppé de `<b>…</b>`), `msgfmt -c` propre, et les `.mo`
**compilés** interrogés par clé exacte (36 réponses, 0 manquante). Le nom de machine interpolé dans
le message de collision passe par `Glib.Markup.escape_text` (piège de l'ép. 9a de
`modernisation-world-bridge`).

**Un drapeau pour les deux dialogues** : `MARIONNET_DISABLE_WARNING_OTHER_MARIONNET_SESSIONS`
(`bin/initialization.ml`, déclaré dans `bin/configuration.ml`, documenté dans `etc/marionnet.conf`)
— ils disent la même chose à deux moments, et qui sait pourquoi deux sessions coexistent ne veut ni
l'un ni l'autre. Ni l'un ni l'autre n'est caché en **mode examen**, à la différence de l'avis de
ménage de l'épisode 6 : ce n'est pas un conseil d'entretien, c'est l'explication d'une panne de la
machine de l'élève — même posture que l'avertissement « A process died unexpectedly » qui vit deux
cents lignes plus bas dans le même fichier.

**Observé en chemin, non corrigé** (règle § 2) : la remarque de fin d'entrée — le verbe `quit` du
canal **rend la main avant que le processus soit parti** — serait partie avec l'entrée soldée. Elle
devient une **entrée neuve** de `docs/TODO.md` (`cmd_quit` répond `quitting:true` puis laisse la
boucle s'arrêter ; un banc s'en sort par `wait "$pid"`, un client du canal n'a que la socket).

L'entrée « Réseau — deux sessions Marionnet simultanées partagent l'adresse hôte de leurs taps »
est **retirée** de `docs/TODO.md` : 7 défauts restants au périmètre du chantier, plus les trois
voisins entrés par les épisodes 7, 8 et 9.

---

### 2026-08-20 — épisode 10 : `wait --ready` ne parle plus que d'un invité qui tourne

**Ce que l'entrée annonçait, et ce que la mesure a trouvé.** L'entrée (reversée à la clôture de
`journalisation-profonde`, ép. 20) disait : `make_hostfs_content` est appelé dans l'`initializer`
de `uml_process`, donc à la **création** du device simulé, lequel **survit au `poweroff`** ; ni
`boot_parameters` ni le marqueur ne sont réécrits au démarrage suivant, donc la garde de fraîcheur
compare deux fichiers également périmés. Le banc l'a démenti sur son premier cas : `boot_parameters`
**est** réécrit au second démarrage (mesuré : `…285,21` → `…301,26`). La raison tient en huit lignes
de 2013 — `machine#poweroff_right_now` et `router#poweroff_right_now` appellent `destroy_right_now`
*« so that the next time we have to re-create the process command line can use a new cow file »*.
Une machine et un routeur **détruisent** donc leur device simulé en s'éteignant ; le device qui
survit est celui des natures sans fichier cow (le switch — d'où l'entrée jumelle, qui reste
entière). Le § 3.5, qui donnait aux deux entrées « une seule cause », est corrigé en tête.

**Le défaut, lui, est réel — c'est une course.** `start` **répond avant que le démarrage soit
fait** : `cmd_transition` rend `accepted:true` et la tâche part sur le `Task_runner`. Entre cette
réponse et la reconstruction du hostfs, le répertoire porte encore le **couple entier** du boot
précédent — marqueur *et* `boot_parameters` —, la comparaison de fraîcheur tient, et `--ready`
répond `ready:true`. Mesuré, sur une session pilotée à la main :

```
start m1          → {"ok":true,"action":"start","accepted":true}
wait m1 --ready   → {"ok":true,"ready":true,"mtime":1787254504.941,"waited":0.050}   ← marqueur du boot PRÉCÉDENT
wait m1 --state=on --timeout=1 → {"ok":false,"error":"timeout","detail":"\"m1\" was still \"off\""}
```

La fenêtre se referme dès que le `Task_runner` prend la tâche : le défaut est donc **intermittent**,
ce qui explique qu'un banc puisse le manquer — celui-ci l'a manqué deux fois sur trois.

**Le correctif : la garde n'est plus une seule condition mais deux, et la seconde ne dépend
d'aucune horloge.** `wait --ready` n'accorde foi à un marqueur que si le composant est **`on`**,
et seulement alors compare les dates. C'est exact par construction et non par chance :
`startup_right_now` (`user_level.ml`) écrit `boot_parameters` — via `create_right_now` — **avant**
de poser l'état `On`, donc « on » implique déjà « le `boot_parameters` du boot en cours ».
`find_hostfs` rend désormais le couple *(hostfs, état)* en **un seul** coup d'œil dans le créneau
Gtk+ : demander deux fois rouvrirait la fenêtre que la paire ferme. Un `Rp_not_running` neuf
distingue en outre les deux façons de ne pas tourner — jamais démarré (pas de `boot_parameters`)
ou arrêté depuis —, parce qu'elles appellent deux gestes différents côté appelant.

**Le second défaut, trouvé au même endroit : `boot_parameters` s'ouvrait sans `O_TRUNC`.** Le
chemin est **réutilisé** d'un démarrage à l'autre (le hostfs appartient au composant, pas au boot)
et le contenu n'est pas de longueur fixe — le nom du tap et l'adresse IPv6 d'eth42 changent avec
l'allocation. Une seconde écriture plus courte laissait donc la queue de la première, que l'invité
`source` en entier. Prouvé en déposant 430 octets de garniture dans le fichier entre deux
démarrages : **830 octets** conservés avant, **396** après.

*Banc jetable* (il faut un invité qui boote : § 3.6). Rouge/vert mesuré sur le binaire d'avant
(`git stash` + `dune build`) : **5 PASS / 2 FAIL**, puis **7 PASS / 0 FAIL** après restauration.
Les deux cas qui échouaient sont les deux défauts ci-dessus ; le cas de la course est marqué
**opportuniste** dans le banc, parce qu'il ne peut pas être rendu déterministe (deux tentatives
d'élargir la fenêtre — une seconde machine mise en file d'attente devant — ne l'ont pas ouverte).
Non-régression : `dune test` vert, et les **5 bancs versionnés** rejoués (11, 5, 4, 6, 9 — 35
vérifications, 0 échec).

**La doc utilisateur portait la mise en garde à cinq endroits**, tous devenus faux :
`doc-src/scripting/README.md` (§ `--ready`), `doc-src/teacher-guide.md` (deux fois : les pièges et
la table), son jumeau français, `doc-src/lab-design-skill.md` (§ 2.3, où la précision manquait) et
le commentaire de `doc-src/labs/session-7/grade.sh`. Le contournement (`exec <c> -- true`) reste
**valide** et le TP le garde — il prouve en plus que l'`exec` dont la clé se sert fonctionne — mais
il cesse d'être **obligatoire**. Aucune chaîne i18n : les refus du canal ne sont pas traduits.

L'entrée « Modèle — `wait --ready` ment au second démarrage » est **retirée** de `docs/TODO.md`, et
la phrase de l'entrée jumelle qui s'y adossait (« même famille que l'entrée précédente ») est
corrigée sur place : 6 défauts restants au périmètre du chantier, plus les trois voisins entrés par
les épisodes 7, 8 et 9.

### 2026-08-20 — épisode 11 : le rc d'un switch est lu à chaque démarrage, non figé au premier

**Le geste, en trois lignes utiles.** `make_simulated_device` (`bin/switch.ml`) ne calcule plus le
contenu du rc, il passe la **fonction** qui le lira (`~get_rcfile_content`, § 3.5) ; la classe du
niveau simulation reçoit un thunk au lieu d'une valeur ; et `spawn_internal_cables` l'appelle **une
fois par `spawn`**, en tête, parce que la même réponse sert deux fois — la branche
(`show_vde_terminal || rcfile_content <> None`) et l'envoi. Deux évaluations auraient rouvert, en
petit, le défaut qu'on ferme : un switch dont le rc vient d'être activé aurait pris la branche
« sans rc » puis tenté d'envoyer. Rien d'autre ne bouge : ni le `.mar`, ni `rc_contents`, ni le
dialogue GUI — qui n'a jamais eu le défaut, `update_switch_with` détruisant le device.

**Preuve — banc versionné `driven-sessions/switch-rc-after-poweroff.sh`**, et non jetable : le
critère du § 3.6 parle d'**invité** et de **privilège**, pas de « démarrer quelque chose ». Trois
cas, rejoués sur le binaire d'avant (`git stash` sur `bin/switch.ml` + `dune build`) puis après :

| Cas | avant | après |
|---|---|---|
| 1er démarrage : le rc donné est joué (anti-faux-positif) | PASS | PASS |
| 2ᵉ démarrage après `rc-set` : le **nouveau** rc, et plus l'ancien | **FAIL** | PASS |
| rc **activé** après un démarrage sans rc (bascule de branche) | **FAIL** | PASS |

soit **1 PASS / 2 FAIL** avant, **3 PASS / 0 FAIL** après. Ce que le banc lit n'est pas le modèle
— qui n'a jamais menti — mais le journal `log <switch> rc_config`, c'est-à-dire ce que Marionnet a
**réellement dit** à `vde_switch` : `> vlan/create 5` / `1000 Success` au premier démarrage,
`vlan/create 7` au second. Le rc partant dans un thread après l'allocation des ports, le banc
**attend** son apparition au lieu de lire une fois.

**Le piège de l'épisode 10 s'est représenté, intact.** Le premier run est revenu avec trois échecs
et des réponses **vides** : `socat` ferme la connexion une demi-seconde après avoir envoyé, et un
`wait --state=on` est plus lent que cela. Aucun message, aucun code d'erreur — juste du vide, qu'un
banc naïf lit comme un refus. `-t`/`-T` sont donc dans `ask`, avec le commentaire qui dit pourquoi.
Ce piège est le premier du chantier à **frapper deux fois** : il est désormais dans un fichier
versionné, pas seulement dans ce journal.

**Le défaut voisin, mesuré et écrit, non corrigé** (règle § 2). Le même
`make_simulated_device` lit **deux autres** réglages en valeur : `activate_fstp` et
`show_vde_terminal`. Mesuré sur le premier — `set s1 activate_fstp true` répond `changed:true`,
`get` relit `true`, et le démarrage suivant affiche toujours `FSTP IS DISABLED` — avec la preuve
que `vde_switch` **a** été relancé (la racine annoncée change) : c'est sa ligne de commande qui est
figée. Le remède du rc **ne s'y transpose pas** (`fstp` est un argument de ligne de commande,
l'xterm un processus accessoire ajouté par un `initializer`), d'où une entrée neuve dans
`docs/TODO.md` plutôt qu'une rallonge ici.

**Non-régression** : `dune build` rc 0, `dune test` vert, et les **5** bancs versionnés antérieurs
rejoués (4, 5, 11, 6, 9 — 35 vérifications, 0 échec), plus les 3 du banc neuf. Aucun processus
survivant (`marionnet.exe`, `vde_switch`), aucun répertoire de run laissé par le banc. Aucune
chaîne i18n : rien de visible n'a changé.

L'entrée « Modèle — un `rc-set` sur un **switch** n'est pris en compte qu'au premier démarrage »
est **retirée** de `docs/TODO.md` : **5 défauts restants** au périmètre du chantier, plus les
**quatre** voisins entrés par les épisodes 7, 8, 9 et 11.
