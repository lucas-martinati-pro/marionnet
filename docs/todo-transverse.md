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

**Deuxième tournée, décidée le 2026-08-21.** Les 16 sont soldées ; mais les épisodes ont écrit
**7 entrées neuves** dans `docs/TODO.md`, chacune un défaut voisin **mesuré** et volontairement
non corrigé en passant (règle § 2.3) : ép. 7 (un `set` explicite dépose un avertissement
d'import), ép. 8 (les `~/.uml/<umid>/` que personne ne balaie), ép. 9 (`quit` rend la main avant
que le processus soit parti), ép. 11 (sur un switch, `activate_fstp` et `show_vde_terminal`
restent ceux du premier démarrage), ép. 14 (`save` écrit le projet pendant que des composants
tournent), ép. 15 (le glade et les images lus sont ceux du Marionnet installé), ép. 16 (les deux
échéances qui encadrent le rapport se contredisent). Elles **entrent dans le périmètre**, mêmes
règles, sous les numéros 17 et suivants (§ 4 bis) — même motif qu'au rang 7 : un défaut écrit par
ce chantier lui revient. Le risque de ré-alimentation est assumé et **borné par la mesure** : les
entrées neuves d'une tournée sont plus périphériques que celles de la précédente, et le chantier
se clôt quand une tournée n'en produit plus qui vaille un épisode.

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

> **Fusible jamais employé, et c'est le résultat qui compte.** L'ép. 8 a mesuré le délai mconsole
> (moins de 10 ms sur un invité sain) et l'ép. 16 le délai marqueur → hook : les deux ont
> **conclu**, donc les deux ont livré un correctif et non un reliquat. Ce que le fusible a vraiment
> servi à faire est plus discret — autoriser à **ouvrir** ces deux épisodes sans savoir s'ils
> aboutiraient, au lieu de les repousser encore. Leçon de l'ép. 16 : une entrée « non instruite »
> peut l'être **pour une raison fausse**. Sa prémisse (« les journaux `rc_config` se terminent à
> l'identique, donc le relais est allé au bout ») ne prouvait rien du tout, ce journal s'arrêtant
> précisément avant le code en cause.

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

> **Sans objet depuis l'épisode 12**, et pour une raison qui vaut mieux que la voie (b) : le
> défaut était déjà soldé, **à la racine**, par `79c25dd` (2026-08-13, hors chantier, prérequis
> de l'épisode 20 de `journalisation-profonde`). Ce que le constructeur, le dialogue GUI et le
> canal prennent tous les trois est la **tête** de `supported_kernels_of` ; cette liste vient de
> `kernels#get_epithet_list`, désormais ordonnée du noyau le plus récent au plus ancien
> (`?ordering`, `bin/disk.ml`) et non plus lexicographiquement. La tête est donc utilisable, sans
> qu'aucun site d'appel ait eu à changer. La voie (b) aurait ajouté une **seconde** garde, en aval,
> à une propriété déjà tenue en amont : l'épisode 12 ne l'écrit pas, il **verrouille** la propriété
> par un banc (§ 5). Ce qui reste vrai du paragraphe ci-dessus : la voie (a) est écartée, et pour
> le même motif.

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
redevient exact par accident), et **six** depuis l'épisode 11 — **sept** depuis l'épisode 12,
dont le banc ne fait que créer, enregistrer et relire.

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
| 12 | Un routeur neuf naît avec un noyau inutilisable | **Rien à corriger** : `79c25dd` (hors chantier) l'a soldé à la racine, l'entrée n'avait pas été retirée (§ 3.3, encadré) | `driven-sessions/default-kernel-needs-no-remap.sh` — **fait** (banc **versionné**, contre l'annonce « jetable » : cf. § 3.6) |
| 13 | Les autres fenêtres de message s'étalent sur toute la largeur | **Constat retourné par la mesure** : elles ne s'étalent pas, elles se **rétrécissent** en colonne et s'allongent sans fin (`set_resizable true` + Gtk+ 3). Plafond dans le glade, zone défilante bornée, `set_resizable` retiré ; aucun `\n` manuel à toucher (mesuré sur les 12 catalogues) | `driven-sessions/message-window-geometry.sh` — **fait** (banc **versionné**, contre l'annonce « run GUI, captures ») |
| 14 | Griser « Enregistrer » / « Sous » / « Copier vers » | Quatrième pile `sensitive_when_Saveable` ; la source de notification aux transitions **existait déjà** (`refresh_sketch_counter`), `user_level.ml` n'est pas touché | `driven-sessions/save-entries-greyed-while-running.sh` — **fait** (banc **versionné**, contre l'annonce « run GUI ») |
| 15 | En arbre de dev, Marionnet lit le catalogue d'un AUTRE Marionnet | Instrumenter d'abord (fait : diagnostic **différé**, le journal n'existe pas encore quand la cascade décide), puis deux causes **mesurées** : `Sites.locale` est **vide** hors installation, et les `.mo` d'un site dune sont des **liens** que `find ~kind:'f'` rejette. Candidat « arbre de dev » + `~follow:()` | `driven-sessions/gettext-catalogue-in-dev-tree.sh` — **fait** (banc **versionné**, contre l'annonce « `strace -e openat` » jetable) |
| 16 | Le rapport de fin de session n'est pas garanti | **Instruit par la mesure, et la cause n'est pas celle qu'on suspectait** : l'unité systemd n'est pas mise en file, elle est armée par le **mauvais relais** — la `zz-journal` est sourcée **après** le `rcfile` de l'utilisateur, qui est ce qui écrit le marqueur de `wait --ready`. Le hook déménage dans le prologue `00-journal` | banc jetable (invité) — **fait** (fusible § 3.1 non employé : la mesure a conclu) |

---

## 4 bis. La deuxième tournée : 7 entrées, par coût croissant

Écrites par les épisodes de la première (§ 1). L'ordre reste celui du coût ; les deux dernières
sont des **diagnostics**, pas des correctifs (l'une demande une mesure sous charge réelle,
l'autre un tri de préfixe).

| N | Entrée de `docs/TODO.md` (épisode qui l'a écrite) | Geste | Preuve |
|---|---|---|---|
| 17 | Un `set` explicite dépose un avertissement d'import hors de tout import (ép. 7) | Deux moitiés : la branche `aucune` du routeur, **et** un avertissement qui n'est enregistré que pendant un import (drapeau porté par le **fil** qui importe, posé par l'unique porte de désérialisation) | `driven-sessions/import-warning-outside-import.sh` — **fait** (banc **versionné**) |
| 18 | Le verbe `quit` rend la main avant que le processus soit parti (ép. 9) | Le **pid**, publié par `quit` **et** par `status` : le seul signal qui dise vrai aussi bien après une sortie propre qu'après une mort brutale — plus la section de `doc-src/scripting/` qui l'écrit | `driven-sessions/quit-is-observable.sh` — **fait** (banc **versionné**) |
| 19 | `save` écrit le projet pendant que des composants tournent (ép. 14) | Ce que **vaut** un `.mar` enregistré en marche, tranché d'abord (le cow d'un invité est archivé en plein vol) ; puis le geste, symétrique de `cmd_quit` : un `ask_or_answer` + `reply_error ~code:"components_running"` | `driven-sessions/save-refused-while-running.sh` — **fait** (banc **versionné**) |
| 20 | Les répertoires mconsole de `~/.uml/` ne sont balayés par personne (ép. 8) | `marionnet-cleanup` sait les **repérer** et les proposer, jamais purger tout seul (§ 3.2) ; le tri vivant/mort par `uml_mconsole … version`, sous l'échéance de l'ép. 8 | — |
| 21 | Sur un switch, `activate_fstp` et `show_vde_terminal` restent ceux du premier démarrage (ép. 11) | Recalculer les arguments dans le `spawn` (patron du `slirpvde_process`) ; l'xterm est un `initializer`, donc un cas à part | — |
| 22 | Le glade et les images lus sont ceux du Marionnet installé (ép. 15) | Choisir **par répertoire** (données versionnées ↔ données installées), pas basculer `MARIONNET_PREFIX` entier : `filesystems/` et `kernels/` en dérivent aussi | — |
| 23 | Les deux échéances qui encadrent le rapport se contredisent (ép. 16) | Mesurer le rapport **sous charge réelle** avant de choisir un couple ; ni l'abaissement ni le relèvement n'est neutre | — |

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

---

### 2026-08-20 — épisode 12 : le noyau d'un composant neuf n'a plus rien à remapper

**L'entrée était déjà soldée — par un commit hors chantier, qui ne l'avait pas retirée.** Premier
geste de l'épisode, avant toute ligne de code : rejouer le symptôme. Il n'existe plus. `add router
r1` sur le binaire courant donne **`6.12.95-i386`**, non `3.2.64-ghost`, et la liste que le canal
publie dans son refus (`set r1 kernel pas-un-noyau`) est ordonnée `6.12.95-i386, 3.2.64-ghost` :
la tête de `supported_kernels_of` est utilisable.

La cause de la guérison est **`79c25dd`** (2026-08-13, *fix(disk): the default kernel is now the
most recent installed*), écrit comme prérequis de l'épisode 20 de `journalisation-profonde` :
`kernels#get_epithet_list` reçoit un `?ordering` (`compare_epithets_by_decreasing_version`), donc
la liste des noyaux n'est plus lexicographique. Elle l'était — parmi
`{3.2.64-ghost, 6.12.95, 6.12.95-i386}`, la tête était la série 2014 — et *tous* les défauts sont
alimentés par cette tête : le dialogue GUI, `User_level`, `Control_server`. Aucun site d'appel n'a
eu à changer.

Ce commit répare donc **à la racine** ce que l'entrée du TODO proposait de réparer en aval, par sa
voie (b) : faire appliquer au constructeur la préférence de `remap_obsolete_kernel_at_import`. Le
§ 3.3 est corrigé en conséquence ci-dessus : **la voie (b) n'a plus d'objet**, et l'écrire
aujourd'hui serait une seconde garde redondante avec l'ordre de la liste — la source unique, elle,
étant *en amont* (l'ordre) et non *en aval* (une préférence recopiée dans deux méthodes).

**Ce que l'épisode livre alors : la preuve, et son verrou.** Une entrée ne se retire pas sur la
foi d'un `git log` ; ce qui la retire, ici, est un banc qui **échoue sur le code d'avant**.

**Le banc dit la propriété sans connaître la règle.** `driven-sessions/default-kernel-needs-no-remap.sh`
ne compare aucune version, n'a aucune préférence pour `-i386`, ne lit aucun `SUPPORTED_KERNELS`.
Il interroge Marionnet **deux fois** et compare : ce que le constructeur a choisi, et ce que
`remap_obsolete_kernel_at_import` en fait au chargement suivant — la méthode dont c'est
précisément le métier de remplacer un noyau que cet hôte ne peut pas faire tourner. Le désaccord,
s'il existe, est **dit par Marionnet lui-même**, dans les `notifications` que porte la réponse à
`open` : `router "r1": kernel "3.2.64-ghost" → "6.12.95-i386"`. La propriété prouvée est donc un
**point fixe** : *créer, enregistrer, rouvrir ne change rien*.

Trois cas, dont deux couvrent les deux moitiés de l'entrée du TODO :

| Cas | avant (patch témoin) | après |
|---|---|---|
| 1. 6 composants créés ici (routeur et machine par défaut, puis un de chaque nature par filesystem installé) gardent leur noyau après enregistrement + relecture, sans un seul ajustement | **FAIL** | PASS |
| 2. un `.mar` **sans attribut `kernel`** (projets antérieurs à l'attribut du routeur) converge en **un seul** cycle enregistrement/relecture | **FAIL** | PASS |
| 3. contre-épreuve : un `.mar` qui nomme vraiment `3.2.64-ghost` est **toujours** réparé, et le dit | PASS | PASS |

soit **1 PASS / 2 FAIL** avant, **3 PASS / 0 FAIL** après. Le « code d'avant » est ici un **patch
témoin** — la ligne `~ordering:compare_epithets_by_decreasing_version` retirée de `bin/disk.ml`,
`dune build`, banc, puis `git checkout` — c'est-à-dire exactement le code d'avant `79c25dd`.

**Le cas 2 a failli être un faux vert, et c'est instructif.** Écrit d'abord comme le cas 1 (« le
chargement ne rapporte aucun ajustement »), il passait **même sous le patch témoin** : sans
attribut `kernel`, il n'y a rien à remapper, donc jamais rien à rapporter, quel que soit le noyau
que le constructeur pose. Ce que l'entrée du TODO décrivait n'est pas un ajustement muet mais
**deux cycles pour converger** — le banc joue donc le **second** cycle : ce que le constructeur a
choisi est maintenant écrit comme attribut, et cette fois le chargeur parle. Leçon à ranger
à côté de celle de l'épisode 4 : *un cas qui ne peut pas échouer ne prouve rien, et cela ne se voit
pas en le lisant vert*.

**Banc versionné** (§ 3.6) : ni invité ni privilège — on crée, on enregistre, on relit ; rien ne
démarre. Il réécrit ses `.mar` avec `jq` (SKIP sans lui) plutôt que d'embarquer un vieux fichier
binaire : ce qui compte est l'**absence** de l'attribut, que le lecteur `v3` traite comme les
formats antérieurs. Deux pièges de bash s'y sont montrés : `add <kind> probe-distribs` est refusé
par `check_name` (un tiret n'est pas un identifiant), et `local i=0` suivi de `i+=1` **concatène**
(`0`, `01`, `011`) — `local -i` est nécessaire.

**Non-régression** : `dune build` rc 0, `dune test` vert, les **6** bancs versionnés antérieurs
rejoués, aucun processus survivant, aucun répertoire de run laissé. Aucune ligne d'OCaml touchée,
donc aucune chaîne i18n.

L'entrée « Modèle — un **routeur créé aujourd'hui naît avec un noyau inutilisable** » est
**retirée** de `docs/TODO.md` : **4 défauts restants** au périmètre du chantier, plus les
**quatre** voisins entrés par les épisodes 7, 8, 9 et 11.

### 2026-08-21 — épisode 13 : la fenêtre d'un message cesse d'être une colonne sans fin

**L'entrée du TODO se trompait de sens, et la mesure l'a retournée.** Elle annonçait des fenêtres
qui « s'étalent sur toute la largeur » et citait 1 814 px pour le label `content` de
`dialog_MESSAGE`. Mesuré sur l'application réelle (serveur X, `xwininfo`), un avertissement d'un
seul paragraphe donnait **398 × 512** : pas une bannière, une **colonne étroite** — et le même
message allongé (~2 500 caractères) donnait **398 × 2 672**, c'est-à-dire un bouton *Fermer* hors
de tout écran de salle de TP. C'est le défaut décrit par le commentaire de `recapitulative`
(« un seul label qui grandit sans borne et pas de barre de défilement »), mais pour la forme
générique de **tous** les `Simple_dialogs.error / warning / info / help`.

**Pourquoi, exactement.** Le glade marque `dialog_MESSAGE` `visible`, donc le builder la **mappe
vide**, et `Simple_dialogs.message` remplit les labels **ensuite**. Or Gtk+ 3 ne fait grandir une
fenêtre déjà mappée jusqu'à sa **taille naturelle** que si elle n'est **pas** redimensionnable ;
redimensionnable, elle n'en honore que le **minimum** — et le minimum d'un label enveloppant est
la largeur de son **plus long mot**. Le `set_resizable true` posé au portage lablgtk3
(`6cb0289`, 2022) figeait donc chaque message à cette largeur-là. Le chiffre de 1 814 px du TODO
n'était pas faux : il avait été relevé **sans** cet appel, donc en régime naturel.

**Corollaire mesuré, contre-intuitif :** sur cette fenêtre, `max-width-chars` **ne fait rien**
(350 × 568 avant, 350 × 568 après) — il ne plafonne que la largeur *naturelle*, qui n'est pas
celle que Gtk+ utilise ici. Cela n'infirme en rien `34393bb` : `dialog_QUESTION`, elle, n'est
jamais rendue redimensionnable, donc elle est dimensionnée au naturel et `max-width-chars` y est
le bon levier. **Le levier dépend du régime de dimensionnement de la fenêtre, pas du label.**

**Le correctif tient en trois pièces, et les trois sont nécessaires** (chacune mesurée seule) :

1. `bin/gui/simple_dialogs.ml` : `set_resizable true` **retiré** (la fenêtre repasse au régime
   naturel, comme `dialog_QUESTION`). Rien n'est tronqué en échange, grâce à la pièce 3.
2. `bin/gui/gui_glade3.xml` : `max-width-chars` = 72 sur `content` (et `wrap` + le même plafond
   sur `title`, qui n'avait ni l'un ni l'autre — l'état exact de `title_QUESTION` avant
   `34393bb`).
3. Une `GtkScrolledWindow` (+ `GtkViewport`, l'idiome déjà employé dans ce fichier) autour de
   `content` : `hscrollbar-policy` `never`, `propagate-natural-height` et
   `max-content-height` 400 — un message court garde sa hauteur, seul un long est borné et
   défile. **`propagate-natural-width` n'est pas décoratif** : sans lui la largeur naturelle du
   label ne remonte pas et la fenêtre retombe à ~200 px (mesuré).

Valeur 400 : la fenêtre la plus haute mesure alors 532 px, décorations comprises, donc tient sur
un portable **1366 × 768** — l'écran de référence retenu, et non les 3840 × 2160 de la machine de
développement, où le défaut ne se voit pas.

**Deux autres fenêtres, construites en OCaml, avaient le même défaut sous l'autre régime.**
`ask_text_dialog` et `recapitulative` ne sont pas redimensionnables (ou le sont mais sont
montrées une fois **construites**), donc elles sont dimensionnées au **naturel** : c'est le défaut
de `7192aa3`, et le remède est bien `set_max_width_chars`. Mesuré sur une réplique structurelle
de `recapitulative` : **3 840 px** de large (tout l'écran) sans plafond, **877** avec. Le
`~width:640` de sa fenêtre ne protégeait de rien, c'est un **minimum**. Quatre labels plafonnés
au total (en-tête, préambule et détail de dépliant de `recapitulative`, consigne de
`ask_text_dialog`).

**Les `\n` posés à la main : le « point dur » annoncé n'existe pas.** Audit des 429 `msgid` du
POT puis des **12 catalogues** : 36 `msgid` portent un `\n`, 24 ont au moins une ligne de plus de
72 caractères — mais ce sont des **séparateurs de paragraphe**, pas des coupures calculées ; un
plafond les enveloppe, il ne les recoupe pas. Les seuls candidats à une coupure manuelle sont des
**listes à puces** (2 traductions sur 12 pour un seul `msgid`), dont toutes les lignes font moins
de 72 caractères : le plafond ne les touche pas. Le **tableau préformaté** de l'aide du routeur
(`zebra\t\t2601/tcp…`) est intact pour la même raison (30 caractères par ligne au plus).
**Aucun `msgid` retouché, donc aucun catalogue : `git diff bin/po/` est vide.**

**Preuve — rouge/vert sur l'application réelle**, pas sur une réplique :

| cas | avant | après |
|---|---|---|
| message d'un paragraphe (~400 car.) | 398 × 512 | **888 × 302** |
| message long (~2 500 car.) | 398 × **2 672** | **888 × 532** |

**Banc versionné** : `driven-sessions/message-window-geometry.sh`, **1 PASS / 3 FAIL** sur le code
d'avant, **4 PASS / 0 FAIL** après. Il ne réplique rien : il lance la **vraie** GUI et lit la
géométrie de la **vraie** fenêtre au serveur X, **sans un seul clic** — l'avertissement de
démarrage de l'épisode 6 **nomme** le répertoire temporaire, donc la **profondeur** de ce
répertoire choisit la longueur du message (27 caractères de chemin pour le cas court, 2 070 pour
le cas long). Il n'exige ni invité ni privilège, seulement un **affichage** : sans `DISPLAY`,
`xdotool` ou `xwininfo`, il se **saute** (77). Il précise ainsi le critère du § 3.6 une fois de
plus : *X est une plateforme, pas un privilège*.

**Piège durable découvert en chemin, écrit au TODO** (entrée i18n, qui est l'épisode 15 de ce
chantier) : un binaire de `_build` ne lit pas que le catalogue d'un autre Marionnet — il lit
aussi son **glade** et ses **images**, `Initialization.Path.marionnet_home_gui` dérivant de
`Meta.prefix`. Sans installation, on croit mesurer l'interface du dépôt et on en mesure une
autre. Mais `MARIONNET_PREFIX`, elle, **fonctionne** : un préfixe fabriqué (`gui/` et `images/`
en liens vers le dépôt) suffit, et c'est ce que fait le banc à chaque exécution. Le contraste
avec `MARIONNET_LOCALEPREFIX`, réputée sans effet alors que les deux passent par le même
`Configuration.extract_string_variable_or`, est la première piste que l'épisode 15 devra tirer.

**Non-régression** : `xmllint --noout` rc 0, `dune build` rc 0 (la copie de `_build` porte bien
les propriétés), `dune test` vert, les **7** bancs versionnés antérieurs rejoués verts, aucun
processus survivant. `bin/gui.ml` **n'est pas touché** : la classe générée lie ses widgets **par
identifiant** (`builder#get_object "content"`), pas par position, donc un niveau d'imbrication de
plus ne la casse pas — vérifié avant d'écrire, ce fichier étant interdit de régénération.

L'entrée « GUI — les **autres** fenêtres de message s'étalent encore sur toute la largeur » est
**retirée** de `docs/TODO.md` : **3 défauts restants** au périmètre du chantier (les épisodes 14,
15 et 16), plus les **quatre** voisins entrés par les épisodes 7, 8, 9 et 11.

---

### 2026-08-21 — épisode 14 : les entrées qui écrivent le projet sont grisées quand quelque chose tourne

**Le point dur annoncé par le TODO n'existait plus.** L'entrée disait : *« ces réactions se
branchent sur des `Cortex`, or l'état allumé/suspendu des composants n'est porté par aucun
`Cortex` », d'où le besoin d'une source de notification aux transitions, à placer dans les
`*_right_now` de `user_level.ml`.* Elle existe : `refresh_sketch_counter` (`bin/state.ml`) **est**
un `Cortex`, que `st#refresh_sketch` déplace, et **toutes** les transitions appellent déjà
`Sketch.refresh_sketch ()` — `create`, `destroy`, `startup`, `suspend`, `resume`,
`gracefully_shutdown`, `poweroff`, plus `destroy_because_of_unexpected_death`. L'épisode n'a donc
**pas touché `user_level.ml`** : il s'est abonné à un compteur qui était là depuis le début, en
l'exposant (`method refresh_sketch_counter`) avec le commentaire disant *pourquoi* il devient
public.

**Le correctif, trois fichiers.** Une quatrième pile `sensitive_when_Saveable` (`bin/state.ml`) à
côté des trois existantes, et la condition écrite **une seule fois**
(`method is_project_saveable = active_project && not (is_there_something_on_or_sleeping ())`) —
c'est mot pour mot ce que les trois callbacks testaient à la main. Dans
`bin/motherboard_builder.ml`, une fonction `update_save_entries_sensitiveness` appelée par
**deux** réactions, car deux choses indépendantes invalident la condition : le projet
(`on_commit` du groupe `filename` × `nodes`) et les transitions (le compteur ci-dessus). Enfin
`bin/gui/gui_menubar_MARIONNET.ml` : « Enregistrer », « Enregistrer sous » et « Copier vers »
quittent `sensitive_when_Active` pour la nouvelle pile ; « Fermer » et « Exporter » y restent.

**Deux précautions.** (1) La condition est calculée **avant** de déléguer au thread GTK : seule
l'application aux widgets appartient au thread principal. Mesuré en chemin : les prédicats
`can_gracefully_shutdown` / `can_resume` lisent `!state` **sans mutex** (`bin/user_level.ml:486`
et `509`), donc l'appeler à chaque rafraîchissement ne peut geler personne — c'était la seule
crainte sérieuse, le compteur bougeant aussi à chaque changement de modèle. (2) Les gardes
d'exécution (`Msg.error_saving_while_something_up`) sont **conservées** : la sensibilité d'un
widget ne protège que le menu.

**La preuve : `driven-sessions/save-entries-greyed-while-running.sh`**, versionné (un switch
n'exige ni invité ni privilège), **1 PASS / 3 FAIL** sur le code d'avant, **4 PASS / 0 FAIL**
après. Il lit la réaction elle-même dans le journal de l'application (`--debug`) : la condition
calculée **et le nombre de widgets** auxquels elle est appliquée — ce nombre est la moitié de la
preuve, il dit que les trois entrées sont dans la pile et qu'aucune quatrième n'y a été traînée.
Un cas est joué **avant** toute création de projet : rien ne doit y devenir sensible.

**Ce que le banc ne lit pas : le pixel.** Le plan prévoyait de lire l'état `SENSITIVE` réel des
trois items dans l'arbre d'accessibilité (AT-SPI). Mesuré le 2026-08-21, sur cette machine et
après avoir installé le pont manquant : **une application lablgtk3 pilotée par `GtkThread.main`
ne s'enregistre jamais sur le bus AT-SPI**, là où un programme GTK3 ordinaire (`zenity`) y
apparaît en quelques secondes. Une sonde au niveau du widget se serait donc sautée partout ; le
cas a été retiré plutôt que gardé en SKIP perpétuel. Le grisé à l'écran reste un geste de l'œil.

**Défaut voisin mesuré, écrit au TODO, non corrigé** (règle du § 2) : par le canal de contrôle,
`save` **écrit** le projet pendant qu'un switch tourne (`{"ok":true,"saved":true,…}`), là où la
GUI refuse en toutes lettres. `cmd_save` ne consulte pas le prédicat, à la différence de
`cmd_quit`. La question de fond — que vaut un `.mar` enregistré en marche ? — n'est pas
tranchable en passant, d'où l'entrée neuve *« Canal — `save` écrit le projet pendant que des
composants tournent »*.

**Non-régression** : `dune build` rc 0, `dune test` vert, les **8** bancs versionnés antérieurs
rejoués verts (45 cas, 0 échec), aucun `msgid` touché (donc aucun catalogue, l'invariant
« catalogues complets » n'est pas concerné).

L'entrée « GUI — griser « Enregistrer » / « Enregistrer sous » quand quelque chose tourne » est
**retirée** de `docs/TODO.md` : **2 défauts restants** au périmètre du chantier (les épisodes 15
et 16), plus les **cinq** voisins entrés par les épisodes 7, 8, 9, 11 et 14.

---

### 2026-08-21 — épisode 15 : un binaire de `_build` lit les catalogues du dépôt

**Le diagnostic était impossible, littéralement.** L'entrée du TODO le disait sans en tirer la
conséquence : le `Log.printf` de `gettext.ml:59` est *« écrit avant que le journal soit prêt,
donc perdu »*. Ce n'est pas une malchance de mise en page, c'est structurel — `bin/marionnet_log.ml`
donne au journal le niveau **constant 0** jusqu'à ce que `bin/initialization.ml` y branche
`Debug_level.get`, et la cascade du catalogue s'exécute à l'**initialisation du module**, donc
avant. Aucun `--debug` ne pouvait montrer quoi que ce soit. Le premier geste de l'épisode est
donc un **diagnostic différé** : `gettext.ml` accumule ce qu'il décide, `Gettext.log_diagnosis ()`
l'imprime, et `initialization.ml` l'appelle juste après avoir posé le niveau réel. Ce
renversement est le seul moyen d'avoir une mesure plutôt qu'une hypothèse.

**Deux causes, mesurées, dont aucune n'était celle qu'on croyait.** Les deux pistes de l'ép. 8b
de `migration-marshal-to-text` avaient été retirées « faute d'effet » ; elles étaient justes
toutes les deux, mais seules et sans instrument elles ne pouvaient rien montrer.

1. **`Sites.locale` est vide en arbre de développement.** `_build/default/i18n/Locations.ml`
   passe à `Dune_site` un `%%DUNE_PLACEHOLDER:…%%` que **seul `dune install` réécrit** ; le
   placeholder est intact dans `_build/default/bin/marionnet.exe` (`strings`), et la trace
   `strace` ne montre **aucun** répertoire sondé au titre du site. Le premier candidat de la
   cascade ne peut donc rien donner tant qu'on n'a pas installé.
2. **Les `.mo` d'un site dune sont des liens symboliques.**
   `_build/install/default/share/marionnet/locale/fr/LC_MESSAGES/marionnet.mo` pointe vers
   `_build/default/i18n/fr.mo`, et `UnixExtra.find ~kind:'f'` fait un `lstat` quand `~follow`
   est absent (`lib/EXTRA/unixExtra.ml:411`) : un lien n'est alors **pas** un fichier régulier.
   Mesuré directement dans la trace : `newfstatat(…marionnet.mo, {st_mode=S_IFLNK}, AT_SYMLINK_NOFOLLOW)`
   — le fichier est vu, reconnu comme lien, et rejeté. C'est **exactement** pourquoi
   `MARIONNET_LOCALEPREFIX` semblait sans effet : la variable était lue, le répertoire parcouru,
   le catalogue trouvé… et écarté.

Le repli `try_to_infer_localeprefix_searching_marionnet_dot_mo_in_usr` ramassait ensuite le
`.mo` de `/usr` — daté du 8 juillet 2023 sur cette machine — en silence.

**Le correctif, deux fichiers et quatre gestes.** (a) `~follow:()` sur la recherche de la
cascade, **pas** sur celle du repli (qui balaye tout `/usr`, où suivre les liens revient à le
parcourir plusieurs fois) ; (b) un candidat *arbre de développement*, dérivé de
`Sys.executable_name` : un exécutable en `<racine>/_build/default/bin/` désigne
`<racine>/_build/install/default/share/marionnet/locale`, que `dune build` fabrique de toute
façon — la forme est reconnue explicitement, et un binaire installé ne la rencontre jamais ;
(c) l'ordre des candidats devient site, **variable**, arbre de dev, `Meta.localeprefix` : une
surcharge explicite l'emporte sur une inférence ; (d) le repli `/usr` est **gardé** (décision de
l'utilisateur) mais cesse d'être muet — il dit désormais, en toutes lettres, que le catalogue
retenu appartient à un **autre** Marionnet.

**La preuve.** `driven-sessions/gettext-catalogue-in-dev-tree.sh`, versionné (ni invité ni
privilège), **0 PASS / 3 FAIL** sur le code d'avant, **3 PASS / 0 FAIL** après. Il ne lit pas ce
que le code croit mais ce que le noyau fait : le `marionnet.mo` réellement ouvert, extrait des
`openat` de l'application. Ses trois cas sont les trois propriétés voulues — le catalogue du
dépôt en run nu, la variable honorée **lien compris**, et la décision visible dans le journal.
S'y ajoute une preuve jetable, celle que l'entrée du TODO réclamait mot pour mot : `msgstr
"Avertissement"` remplacé par un marqueur dans `bin/po/fr.po`, `dune build`, et le titre de la
fenêtre d'avertissement lu au serveur X — `PREUVE-EPISODE-15`, **sans `make install`**.
`bin/po/fr.po` a été restauré aussitôt (`git diff` vide).

**Trois pièges durables.**

1. **Un `.mli` de trois `val` protège plus qu'il ne coûte.** `bin/gettext.mli` existe et
   n'exportait que `s_`, `f_` et `localeprefix` : les valeurs internes ajoutées ici
   (`diagnosis_lines`, la cascade, la détection de `_build`) restent invisibles aux **dizaines**
   de modules qui font `open Gettext`. Sans lui, chacune aurait été un nom de plus dans leur
   portée.
2. **`strace` détache au lieu de tuer.** Une première version du banc signalait le PID de
   `strace` : sur `SIGTERM`, strace se **détache** et laisse l'application vivre — six fenêtres
   ont survécu au banc. Le banc lit donc les PID **dans la trace** (strace préfixe chaque ligne
   du PID appelant) et les vérifie un à un dans `/proc` (identité exacte, jamais un motif) avant
   de signaler.
3. **Un fusible de cardinalité se calibre sur une mesure, pas sur une intuition.** Le premier
   seuil (20 PID) s'est déclenché sur le cas **nominal** — une session ordinaire en trace 45 —,
   donc le banc ne tuait plus rien tout en affichant PASS : pire que pas de fusible. Seuil porté
   à 500, la vraie garde étant le contrôle d'identité.

**Un défaut voisin, écrit et non corrigé** (règle du chantier) : `Path.marionnet_home` fait lire
au binaire de `_build` le **glade** et les **images** du Marionnet installé. Le remède n'est pas
transposable tel quel — `MARIONNET_PREFIX` pilote aussi `filesystems/` et `kernels/`, absents ou
vides dans le préfixe que fabrique `dune build` (mesuré) — d'où une entrée neuve dans
`docs/TODO.md` plutôt qu'une correction en passant.

### 2026-08-21 — épisode 16 : le hook d'arrêt est armé avant que l'invité se dise prêt

**La cause n'était pas celle que l'entrée supposait, et la preuve sur laquelle elle s'appuyait
n'en était pas une.** Le TODO tenait pour acquis que « les trois avaient atteint la fin de leur
relais (journaux `rc_config` identiques) », et en déduisait une unité systemd *mise en file
jusqu'à la fin du boot*. Mesuré ici : `rc_config.log` s'arrête à
`marionnet-relay.zz-journal:42`, c'est-à-dire au moment où l'épilogue **referme la capture** — soit
environ deux cents lignes **avant** le code qui installait le hook. Trois journaux identiques ne
disaient donc rien du tout de l'armement du hook. La prémisse est nulle, et l'hypothèse qu'elle
portait aussi : sur `debian-trixie`, `marionnet-report.service` est active **13 s** après le
`start`, en même seconde que `marionnet-watch.service` — aucune file d'attente, aucun retard de job.

**La vraie cause est un ordre de sourçage, et elle se lit dans le nom des fichiers.** Le relais de
l'invité source `/mnt/hostfs/marionnet-relay*` par ordre alphabétique :

    marionnet-relay.00-journal   ← le prologue
    marionnet-relay.rcfile       ← la configuration de démarrage de l'utilisateur
    marionnet-relay.zz-journal   ← l'épilogue, qui armait le hook

Or le **marqueur de disponibilité** — celui que `wait --ready` attend — est écrit par le `rcfile`,
donc **avant** l'épilogue. Un banc (ou un enseignant) qui fait ce que tout le dépôt recommande,
`wait --ready` puis extinction, court après l'armement de son propre hook. Le défaut ne se voit pas
avec une configuration triviale (l'écart tombe sous la seconde) : il se voit dès qu'elle **travaille
encore** après avoir écrit le marqueur, ce que fait n'importe quel scénario de TP.

**Rouge, puis vert, sur le même cas.** Configuration de démarrage
`: > /mnt/hostfs/marionnet-guest-ready ; sleep 40`, un `stop` (extinction *gracieuse*) envoyé dès la
réponse de `wait --ready` :

| | `wait --ready` | hook au moment du `stop` | `report.md` |
|---|---|---|---|
| avant | 8,6 s | pas armé | **absent** |
| après | 11,6 s | armé | **présent**, 10 658 o, terminé (`_end of the report:_`) |

**Le correctif tient en un déménagement.** Le bloc *SHUTDOWN HOOK* passe de
`bin/scripts/marionnet-relay.zz-journal.sh` à `bin/scripts/marionnet-relay.00-journal.sh` (fin du
prologue) ; l'épilogue garde à sa place une section qui ne dit plus que **où** le hook est parti et
pourquoi. Rien d'autre ne change : ni l'unité, ni ses dépendances, ni la branche SysV. Trois points
tenus délibérément :

- le `systemctl start` reste **bloquant** — c'est ce que le déménagement achète : quand la ligne
  rend la main, l'unité *est* active, donc armée. Le `--no-block` dont le veilleur a besoin
  remettrait une petite course à la place de la grande ;
- `After=network.target` est **gardé** : systemd arrête dans l'ordre inverse du démarrage, donc
  c'est cette ligne qui maintient le réseau debout pendant que le rapport est pris. Elle n'est pas
  là pour le démarrage ;
- le veilleur (`marionnet-watch.service`), lui, **ne bouge pas** : il ne doit pas démarrer avant que
  l'épilogue ait refermé la capture (son propre commentaire l'explique), et rien ne juge un invité
  prêt sur lui.

**Effet de bord favorable, et non recherché** : l'armement du hook se produit désormais **pendant**
que la trace est ouverte, donc `rc_config.log` en porte la marque (`__mrn_journal_hook=…`,
`[[ -r /mnt/hostfs/marionnet-report ]]`) avant que le bloc ne se taise. Le geste que l'épisode 21
croyait pouvoir lire dans ce journal y est enfin.

**Non-régression, mesurée.** Cas ordinaire à 1, 3 et 6 machines `debian-trixie` : rapport présent et
complet pour chacune (10,2 à 10,5 ko), avant comme après. Sur `debian-wheezy-08367` (SysV, noyau
`6.12.95-i386`) : le boot aboutit, la trace montre le bloc atteint à `00-journal:269`, et
`report.md` reste **absent** — c'est la *limite connue* déjà documentée (l'extinction passe par
`uml_mconsole cad`, auquel l'`inittab` de ces images répond par `/sbin/halt`, ce qui court-circuite
`/etc/rc0.d`), inchangée par le déménagement.

**Banc jetable**, conformément au § 3.6 (un invité doit booter) : les quatre scripts de mesure sont
restés au scratchpad ; leurs sorties sont ci-dessus. Le binaire porte bien les scripts modifiés
(`preprocessor_deps` de `bin/dune`, piège 7 du `CLAUDE.md` — vérifié par `strings` sur
`marionnet.exe`).

**Un défaut voisin, écrit et non corrigé** (règle du chantier) : les deux échéances qui encadrent le
rapport se contredisent — `TimeoutStopSec=60` dans l'unité de l'invité, contre les **30 s** du fil
que `gracefully_terminate` (`bin/simulation_level.ml`) arme *avant* d'envoyer le `cad` et qui SIGKILL
toute la hiérarchie UML. L'enveloppe extérieure vaut la moitié de l'intérieure : un rapport lent est
perdu avec son invité au lieu d'être tronqué proprement. Mesuré ici, hôte au repos : 4 à 8 s par
machine — la marge existe, mais un facteur 4 de charge la mange, et c'est exactement la condition de
l'épisode 21. Entrée neuve dans `docs/TODO.md` plutôt qu'une constante ajustée au jugé.

---

### 2026-08-21 — épisode 17 : un avertissement d'import ne naît que d'un import

**Le premier de la deuxième tournée** (§ 4 bis), et le premier épisode à solder une entrée que
le chantier avait lui-même écrite au TODO — celle de l'ép. 7.

**Le symptôme, rejoué rouge.** `set r1 variant aucune` sur un **routeur** répond `ok:true`,
retire bien la variante… et journalise
`import remapping: router "r1" : variante "aucune" supprimée`. Ce n'est pas qu'une ligne de
journal : l'avertissement est **empilé** dans `network#add_import_warning`, et la liste est lue
par `state#open_project_async` **à la fin du prochain chargement**. Mesuré, dans la même
session, sur un projet qui n'avait strictement rien à adapter :

```
open victim.mar → "notifications":[{"kind":"recap",
                    "title":"1 ajustement(s) automatique(s) appliqué(s)",
                    "items":[{"summary":"router \"r1\" : variante \"aucune\" supprimée", …}]}]
```

Le dialogue « Projet adapté au chargement » présente donc, comme une adaptation de *ce*
projet-là, une conséquence d'une écriture explicite faite **avant** lui, sur un **autre** projet.

**Deux moitiés, prouvées séparément.** L'ordre de la preuve n'est pas cosmétique : appliquée
seule, chaque moitié laisse l'autre symptôme rouge, ce qui interdit qu'une seule d'entre elles
suffise à faire passer le banc.

| | banc, cas 1 (le journal) | banc, cas 3 (le récapitulatif) |
|---|---|---|
| avant | **FAIL** (`import remapping:`) | **FAIL** (`"kind":"recap"` sur un projet vierge) |
| moitié 2 seule | **FAIL** (`remapping outside any import (NOT recorded)`) | PASS |
| les deux | PASS | PASS |

- **Moitié 1 — `bin/router.ml`.** Une branche `("variant", "aucune") -> self#set_variant None`,
  celle que `bin/machine.ml` a depuis `v0`. Sans elle le mot tombait dans
  `remap_absent_variant_at_import`, qui faisait ce pour quoi il existe : retirer la variante *et*
  signaler une adaptation. `aucune` n'est pas une variante manquante, c'est **le mot qui retire
  une variante** — le seul qui traverse le canal (la chaîne vide n'y survit pas, ép. 7).
- **Moitié 2 — `bin/user_level.ml`, la plus importante** (la première ne règle que le symptôme
  mesuré ; les trois `remap_*_at_import` gardaient la même porte). Un avertissement n'est
  **enregistré que pendant un import** : `network` porte `importing_thread`, posé par
  `with_import_in_progress`, que `Netmodel.Xml.load_network` enveloppe autour de son
  `net#from_tree` — **l'unique** porte de désérialisation du réseau (`state#import_network` est
  son seul appelant). Hors de là, `add_import_warning` n'enregistre rien.

**Pourquoi un fil et non un booléen.** Le canal de contrôle écrit depuis **son** fil pendant que
la GUI charge un projet dans le sien : un booléen global compterait ces écritures-là comme
faisant partie de l'import — exactement le défaut qu'on ferme, à l'envers. Le drapeau retient
donc `Thread.id (Thread.self ())`, et `Fun.protect` le retire quoi qu'il arrive.

**Ce qui reste visible.** Un remap hors import est toujours journalisé, mais **jamais sous le
même nom** : `remapping outside any import (NOT recorded)`. Sans quoi la moitié 2 aurait rendu
le défaut *invisible* au lieu de le corriger. Le commentaire de `user_level.ml` qui affirmait
« Called ONLY from the deserialization code » est corrigé : il énonçait une contre-vérité depuis
l'ouverture du canal de contrôle.

**Le banc, versionné** — `driven-sessions/import-warning-outside-import.sh`, 5 cas, ni invité ni
privilège (aucun composant n'est démarré) :

1. `set r1 variant aucune` (routeur) : accepté, **aucune** ligne de remap (des deux
   formulations) ;
2. le même geste sur une **machine**, témoin : n'a jamais rien écrit ;
3. `open victim.mar` (rien à adapter) : **aucun** `"kind":"recap"` ;
4. anti-faux-positif décisif — `open remapped.mar`, fabriqué par le banc en réécrivant
   `[ "kernel", "3.2.64-ghost" ]` dans le `network.json` de l'archive : le récapitulatif est
   **toujours** montré, et la ligne **toujours** journalisée. Sans ce cas, « plus jamais de
   récapitulatif » passerait le banc ;
5. rouvrir le projet vierge juste après : silencieux de nouveau (la liste ne survit pas à son
   propre affichage).

Deux détails du banc valent d'être notés : il lit le récapitulatif **par le canal**, dans le
champ `notifications` de la réponse d'`open` (`Simple_dialogs.recapitulative` passe par
`capture_and_dismiss`, genre `Recap`), donc sans un `xdotool` ni un clic ; et son `socat` porte
`-t 60 -T 90`, sans quoi la réponse d'un `open` — qui charge un projet entier — serait perdue
(piège de l'ép. 10).

**Ce que la mesure a appris, et qu'il faut écrire.** Après la moitié 1, **plus aucun chemin
atteignable** ne déclenche un `remap_*_at_import` hors import : les trois gardes du canal
(kernel ép. 4f de `pilotage-par-script`, distrib ép. 5, variant ép. 7) couvrent exactement les
trois remaps, et la GUI n'y passe pas. La moitié 2 est donc une garantie **structurelle** — elle
ne se prouve que par l'étape intermédiaire du tableau ci-dessus, où elle est appliquée seule.
C'est la mesure qui l'a établi, pas un pari : le banc ne peut pas exercer la moitié 2 sur le code
final.

**Vérifications.** `dune build` rc 0 ; `make check` (`dune build @check`, obligatoire ici :
`user_level.ml` est en amont de tout) rc 0 ; banc 5 PASS / 0 FAIL. Zéro chaîne i18n neuve : tout
ceci est du journal, et les `msgid` des remaps ne bougent pas. Le `.mli` de `user_level` suit
(la ligne `network:< … >` du constructeur de `virtual_machine_with_history_and_ifconfig` liste
les méthodes attendues : y ajouter `import_in_progress` fait partie du correctif).

**Aucun défaut voisin écrit** à cet épisode.

### 2026-08-21 — épisode 18 : la fin d'une session s'observe par le canal seul

**Le symptôme, rejoué rouge.** `quit` répond `{"ok":true,"quitting":true}` et le processus est
**encore là** quand le client lit cette ligne — mesuré : il lui survit de **559 ms**, ses
composants et ses taps avec lui. Un banc s'en sort parce qu'il possède le pid ; un client du
canal n'a qu'une socket, donc il enchaîne sur la session suivante et les deux coexistent sans
que personne le sache.

**Ce qui ne pouvait pas être le geste.** Un `quit` synchrone : la réponse part forcément avant
la sortie (`st#quit_async` ne fait que *planifier* l'arrêt sur le `Task_runner`). Le seul point
d'accroche est donc ce que le client peut **observer ensuite** — d'où le choix, tranché avant
d'écrire, entre le **pid** et la **disparition de la socket**.

**La mesure a démenti la prémisse, et le choix a tenu quand même.** On croyait le fichier socket
survivant au processus ; il ne l'est pas : ocamlbricks l'`unlink` depuis le thread serveur
(`ThreadExtra.at_exit`, `lib/STRUCTURES/network.ml:386`). La socket **est** donc un signal — mais
seulement de la sortie *propre*. Une session tuée brutalement laisse son fichier derrière elle
(cas 6 du banc, `kill -9`) : l'**absence** du fichier prouve une fin, sa **présence** ne prouve
rien. Le pid, lui, dit vrai des deux côtés. C'est ce que la doc écrit, au lieu de laisser
chacun le découvrir.

**Le geste.** `("pid", jint (Unix.getpid ()))` dans la réponse de `cmd_quit` — et le même dans
`cmd_status`, pour deux raisons : un client arme sa surveillance **avant** de quitter, et un
`quit` **refusé** (mode examen) ne porte par construction ni `quitting` ni `pid`, le contrat
neuf valant pour la seule réponse `quitting`, comme l'exigeait l'entrée. Trois lignes d'OCaml,
zéro chaîne i18n (le canal n'est pas traduit), plus une section de `doc-src/scripting/` au § 6
« `accepted` is not `done` » — le chapitre qui porte déjà la même leçon pour `--state` et
`--ready`.

**Rouge/vert** (banc **versionné** `driven-sessions/quit-is-observable.sh`, ni invité ni
privilège — aucun composant n'est démarré) : **5 PASS / 2 FAIL** avant, **7 PASS** après. Les
deux cas rouges sont exactement les deux affirmations du correctif (`status` et `quit` publient
le pid de la session, comparé à celui que le banc a réellement lancé) ; les cinq autres
mesurent le contrat autour et passent des deux côtés — c'est leur rôle.

**Quatre pièges mesurés en chemin, tous du côté de la mesure.**

1. **`socat` ne peut pas mesurer ce cas** : il rend la main quand la **connexion** se ferme,
   c'est-à-dire quand le processus meurt — un banc écrit avec l'`ask()` des dix autres aurait
   trouvé le processus toujours mort, pour une raison sans rapport avec ce qu'il mesure. D'où un
   **coprocess** pour la seule requête `quit`. (`mrnctl`, lui, s'en tire : son `| head -1` ferme
   le tuyau dès la première ligne, donc il rend la main **avant** la mort — c'est bien le
   comportement que la doc décrit.)
2. **SIGTERM ne tue pas Marionnet**, et c'est **délibéré** (`bin/marionnet.ml` : un `halt` dans
   un invité en envoie un, via la connexion X rompue d'un programme graphique). Le premier run
   du banc est resté bloqué sur `kill "$pid"; wait "$pid"` jusqu'à son propre fusible, en
   laissant une session vivante. Ce qu'un banc lance se termine donc **par le canal** (`quit`)
   ou **par SIGKILL** — noté dans `driven-sessions/README.md`.
3. **`kill -0` réussit sur un zombie** : un enfant sorti mais non récolté reste dans la table
   des processus. Le banc, qui a lancé la session lui-même, doit lire l'état dans
   `/proc/<pid>/stat` ; un client du canal, qui n'est pas le parent, ne rencontre jamais ce cas
   — la doc le dit à qui lance Marionnet depuis son propre script.
4. **`EPOCHREALTIME` suit la locale** : sous `fr_FR` son séparateur est une **virgule**, et
   `${EPOCHREALTIME/./}` laisse alors une chaîne qu'aucun contexte arithmétique ne lit.

**Vérifications.** `dune build` rc 0, `make check` (`dune build @check`) rc 0, banc 7 PASS / 0
FAIL, les **11 bancs versionnés** antérieurs rejoués, aucun processus survivant, aucun
répertoire de run laissé.

**Aucun défaut voisin écrit** à cet épisode : les deux surprises rencontrées sont un
comportement d'ocamlbricks (correct) et une neutralisation de signal voulue et commentée depuis
longtemps.


### 2026-08-22 — épisode 19 : `save` refuse ce que la GUI refuse

**Ce qu'il fallait trancher avant d'écrire une ligne** — l'entrée le disait elle-même : « c'est
cette question-là, pas la garde, qui coûte ». Ce que **vaut** un `.mar` enregistré en marche se
lit dans `private_save_project` (`bin/state.ml`) : l'archive est un `tar` du répertoire de
travail, et la seule exclusion qui touche aux disques est `get_files_may_not_be_saved`
(`bin/treeview_history.ml`) — dont le nom trompe, ce sont les **anciens** snapshots, jamais le
cow courant. Le cow d'un invité en marche est donc archivé **pendant que son noyau écrit
dedans** : le disque restitué vaut celui d'un débranchement. Le refus que la GUI oppose depuis
toujours (`Msg.error_saving_while_something_up`, `bin/gui/talking.ml`) est fondé, et sa raison
n'était écrite nulle part — elle l'est maintenant, dans le commentaire de la garde.

**Décision** (utilisateur, avant l'implémentation) : le canal **refuse**, comme la GUI. Des deux
voies que l'entrée laissait ouvertes, celle-ci ne change pas la grammaire — aucun client ne
bouge — et surtout elle ne demande pas à un script de savoir ce que même la GUI ne l'autorise pas
à faire.

**Le geste**, une seule addition dans `cmd_save` (`bin/control_server.ml`), donc valable pour
`save` **et** `save-as`, qui partagent le corps :

```
ask_ (fun () -> List.filter_map
        (fun n -> if n#can_gracefully_shutdown || n#can_resume then Some n#get_name else None)
        (st#network#get_node_list))
```

La **liste des noms est le prédicat** — vide si et seulement si
`is_there_something_on_or_sleeping` est faux, puisqu'elle parcourt les mêmes nœuds avec le même
test (`bin/state.ml`) — donc pas de seconde source de vérité à faire diverger, et le refus
**nomme** les composants (`components_running`, détail : `… (s1) …`). Placé **avant** tout appel
à `save_project`/`save_project_as` : ce dernier **renomme** le projet avant de sauver, et un
refus tardif aurait laissé la session portant le nom d'un fichier jamais écrit. Zéro chaîne
i18n : le message part sur le canal, pas à l'écran.

**Rouge/vert** (banc **versionné** `driven-sessions/save-refused-while-running.sh` — un switch,
ni invité ni privilège) : **2 PASS / 2 FAIL** avant, **4 PASS** après. Les deux cas rouges sont
les deux moitiés du symptôme du TODO (`save` puis `save-as` avec `s1` en marche) ; les deux
autres sont la non-régression, jouée **avant et après** — une garde qui refuserait toujours
passerait les deux premiers et rendrait `save` inutilisable. Le banc lit la réponse du canal
seule : le code, les noms qu'elle porte, et pour `save-as` les deux choses qu'un refus doit
laisser intactes — aucun fichier créé, et le projet portant toujours son propre nom (relu par
`status`).

**Défaut voisin, mesuré et écrit au TODO** (règle § 2.3). Le refus neuf rend visible une
asymétrie qui existait déjà : sur la même session, un switch en marche,

```
save         -> {"ok":false,"error":"components_running",…}
close --save -> {"ok":true,"closed":true,"saved":true}
```

`leave_current_project` (corps commun de `close`, `new` et `open`) appelle `shutdown_everything ()`,
qui ne fait que **planifier** les extinctions (`Task_runner#schedule_parallel`), puis enchaîne
`save_project` tout de suite : le `tar` part **pendant** que les invités descendent. Le menu GUI
joue la même séquence, donc les deux se corrigent ensemble ou pas du tout — c'est ce que dit la
nouvelle entrée de `docs/TODO.md`, qui remplace celle que cet épisode solde.

**Vérifications.** `dune build` rc 0, `make check` (`dune build @check`) rc 0, banc **4 PASS /
0 FAIL**, et les **14 bancs versionnés** rejoués en séquence — tous rc 0, aucun FAIL, aucun SKIP.
Aucun processus survivant et aucun répertoire de run laissé par les runs de cet épisode (les
seuls UML relevés sur la machine dataient de treize heures, d'une session antérieure sans
rapport). Les deux scripts livrés qui enregistrent après un démarrage
(`doc-src/scripting/examples/05-exam-session.sh`, `doc-src/labs/session-7/play.sh`) le font déjà
l'un après un `stop` suivi de `wait --state=off`, l'autre **avant** son `start-all` : rien à y
corriger, et les recettes du § 7 et du § 13 du README enregistrent un réseau jamais démarré.
