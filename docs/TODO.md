# TODO — améliorations repérées, pas encore planifiées

Liste **transverse** : ce qui mérite d'être fait mais n'appartient à aucun chantier en cours, ou
n'y entre que de biais. Ce qui relève d'un chantier reste dans son document (`docs/*.md`, section
« Reste au chantier ») — ici, seulement ce qui serait sinon perdu.

Chaque entrée dit : le **défaut constaté**, ce qu'on **veut à la place**, et ce que
l'implémentation devra affronter (pour que la reprise ne recommence pas l'analyse).

---

## GUI — griser « Enregistrer » / « Enregistrer sous » quand quelque chose tourne

**Constat.** Ces entrées restent actives alors que la sauvegarde est refusée dès que
`st#is_there_something_on_or_sleeping ()` est vrai (`gui_menubar_MARIONNET.ml:160,186,227`). Pour
« Enregistrer sous », l'utilisateur est donc invité à **choisir un nom de fichier**, puis
l'opération est refusée par un dialogue d'erreur (`Msg.error_saving_while_something_up`) : on
l'engage dans une action pour la lui refuser ensuite.

**Voulu.** Que ces entrées soient **insensibles** (grisées) tant que quelque chose est allumé ou
suspendu — l'interdit se lit alors *avant* le geste, comme pour les autres entrées conditionnelles
de la barre de menus. Concerne au moins « Enregistrer », « Enregistrer sous » et « Copier vers »
(les trois sites ci-dessus).

**Ce que l'implémentation devra affronter.** Le mécanisme de sensibilité réactive existe déjà :
piles `sensitive_when_Active` / `_Runnable` / `_NoActive` (`state.ml:260-269`), alimentées par des
réactions `Cortex` dans `motherboard_builder.ml` — il suffirait d'une quatrième pile. Le point dur
est ailleurs : ces réactions se branchent sur des `Cortex` (`project_paths#filename`,
`network#nodes`, `network#cables`), or **l'état allumé/suspendu des composants n'est porté par
aucun `Cortex`** — `is_there_something_on_or_sleeping` interroge la liste des nœuds à chaud. Il
faut donc une **source de notification** aux transitions ; les points naturels sont les
`*_right_now` de `user_level.ml`, où le chantier `marionnet-automate-composants` (épisode 3) a déjà
placé les `Sketch.refresh_sketch ()` explicites de fin de transition.

*Repéré le 2026-08-01, à l'occasion du rejeu GUI du journal 22.*

---

## Modèle — le **label** d'un composant se valide encore trop tard

> Le volet **nom** de cette fiche est **CLOS** : `User_level.check_new_name` valide identifiant et
> unicité en première instruction des cinq chemins destructeurs (chantier
> `marionnet-pilotage-par-script`, ép. **4d-2c**, 2026-08-06 — banc témoin `rename-witness.sh`,
> 4 assertions rouges avant / 6 vertes après). Ne subsiste que le résidu ci-dessous, de même forme.

**Constat.** `update_with` (`user_level.ml`, `node_with_defects` et `node_with_ledgrid_and_defects`)
applique les champs dans l'ordre `set_name` → `set_port_no` → `set_label`. Le `check_label` de
`id_name_label` (`user_level.ml:519`, `526-530`) **peut refuser** un label contenant `<` ou `>` — après,
donc, que le nom et le nombre de ports ont déjà été écrits, le device simulé détruit et (pour les
hubs/switchs/routeurs) le ledgrid défait. Même défaut d'ordre que celui du nom, un cran plus bas.

**Pourquoi ce n'est pas un bug observable aujourd'hui.** Le canal de contrôle écrit le label par
`eval_forest_attribute` (`set label`), qui n'écrit rien avant : un refus y coûte zéro. Le seul
chemin exposé est le dialogue « Properties » de la GUI, dont le champ label n'est pas filtré à la
saisie — nul ne l'a signalé, le caractère `<` étant peu naturel dans un libellé.

**Voulu.** Que `update_with` valide **tous** ses arguments avant d'écrire le premier, comme il le
fait désormais pour le nom. Un `check_label` appelable (aujourd'hui `let` local au corps de
`id_name_label`) rendrait la symétrie évidente ; à défaut, dupliquer son unique test
(`StrExtra.First.matchingp (Str.regexp ".*[><].*")`) comme `check_new_name` duplique le sien.

**Ce que l'implémentation devra affronter.** Rien de structurel : c'est deux lignes au même endroit
que celles de l'ép. 4d-2c. Le coût réel est la **preuve** — comme pour le nom, le chemin fautif
n'est atteignable qu'en désarmant l'appelant, donc par un banc témoin (`rename-witness.sh` en donne
le patron). À faire à l'occasion d'un passage sur `update_with`, pas en campagne dédiée.

*Volet « nom » repéré le 2026-08-06 (ép. 4d-2b), corrigé le même jour (ép. 4d-2c) ; résidu
« label » repéré à cette occasion.*

## Canal — `set <n> distrib <épithète inexistante>` est accepté **sans rien changer**

**Constat.** `set m1 distrib pas-une-distrib` répond `ok:true` avec `changed:false` : le champ passe
par `#eval_forest_attribute ("distrib", …)`, qui appelle `remap_absent_distrib_at_import`
(`machine.ml:660`, `router.ml:1228`). Cette méthode existe pour le **chargement d'un `.mar`** — un
projet peut nommer un filesystem qui n'est pas installé ici, et le remplacer en silence (avec un
avertissement d'import) vaut mieux que refuser d'ouvrir le projet. Employée sur un `set` explicite,
elle transforme une faute de frappe en no-op poli.

**Pourquoi ce n'est pas grave aujourd'hui.** La réponse porte `changed:false` et la valeur **relue**
(§ 4.3) : un script qui compare `new` à ce qu'il demandait le voit. Mais il doit y penser, alors que
partout ailleurs le canal **refuse** ce qu'il ne peut pas faire (champ inconnu, noyau hors
`SUPPORTED_KERNELS` depuis l'ép. 4f, nom non identifiant…).

**Voulu.** Un `bad_argument` nommant les distributions installées, comme la garde du noyau nomme les
noyaux supportés. C'est la même exigence, sur le champ voisin.

**Ce que l'implémentation devra affronter.** Le modèle ne publie pas la liste des filesystems
installés : `vm_installations#filesystems#get_epithet_list` n'est accessible qu'aux classes qui
tiennent `vm_installations`. Il faudrait une méthode de lecture de plus sur `component` (patron de
`supported_kernels_if_any`, ép. 4f) — donc les trois pièges connus du `.mli` — pour un défaut dont
personne n'a encore souffert. À faire au prochain passage sur ces gardes, pas avant. **Ne pas**
toucher `remap_absent_distrib_at_import` : son comportement est correct pour l'import, qui est sa
raison d'être.

*Repéré le 2026-08-07 par le banc de l'ép. 4f (`components-bench.sh`, bloc C11), qui avait lui-même
confondu un répertoire `…_variants` avec une épithète — l'erreur du banc a révélé celle du canal.*

## Idée — **composer** deux projets (importer un `.mar` dans le projet courant)

**Constat.** Il n'existe aucun moyen, ni en GUI ni ailleurs, de verser le contenu d'un projet dans
un autre : ouvrir un `.mar` **remplace** le projet courant. Un enseignant qui a préparé un « bloc
LAN » et un « bloc routage » ne peut pas les réunir autrement qu'en recréant les composants à la
main dans l'un des deux.

**Voulu.** Un import additif : les nœuds et câbles du projet importé s'ajoutent à ceux du projet
courant, avec leurs configurations (treeviews comprises), sous un préfixe ou un plan de renommage
explicite en cas de collision.

**Ce que l'implémentation devra affronter.** C'est plus qu'une commande — et c'est pourquoi ce
n'est **pas** un épisode du chantier `pilotage-par-script`, qui l'a examiné et écarté (§ 4.8,
ép. 4g) : le contrat de ce canal est « les mêmes possibilités et limites que la GUI », or la GUI ne
compose pas. Les obstacles réels, dans l'ordre : (a) les **collisions de noms** (`name_exists`
n'offre qu'un refus, il faut une politique de renommage, or renommer touche ifconfig, defects,
history et le répertoire `hostfs/`) ; (b) `netmodel/network.xml` ne porte **que** nœuds et câbles —
les treeviews sont persistées à part (`states/…`) et devraient être fusionnées ligne à ligne ;
(c) les répertoires `hostfs/<nom>/` et les états de disque à recopier ; (d) les remaps d'import
(`remap_obsolete_kernel_at_import`, `remap_absent_distrib_at_import`) à rejouer sur la partie
importée seulement. Une fois cela fait, l'exposer au canal serait trivial (une commande de plus).

*Idée issue de la voie (a) de `forest`, écartée le 2026-08-07 (ép. 4g de `pilotage-par-script`) :
gardée ici parce qu'elle a une valeur pédagogique propre, indépendante du scripting.*


---

## Modèle — un **routeur créé aujourd'hui naît avec un noyau inutilisable**

**Constat.** `add router r1` (canal) ou l'ajout d'un routeur par la GUI donne au composant le
noyau **`3.2.64-ghost`**, dont Marionnet lui-même dit, au chargement d'un projet, qu'il est
« unusable on this host » (série 3.2, stub SKAS0 cassé par les hôtes ≥ 6.x). Le routeur n'est donc
pas bootable tant qu'on ne l'a pas **enregistré puis rouvert** : c'est la relecture qui déclenche
le remap `3.2.64-ghost` → `6.12.95-i386`. Le même défaut frappe tout `.mar` antérieur à l'attribut
`kernel` du routeur : son nœud n'en porte pas, le constructeur applique donc le même défaut, et le
projet demande **deux** cycles d'ouverture/enregistrement pour converger.

**Cause.** Deux règles justes se contredisent. (1) Le défaut de noyau suit le *filesystem* : c'est
le **premier noyau déclaré** par son `.conf` (`user_level.ml:1151-1163`, règle posée à l'ép. 4f de
`marionnet-pilotage-par-script` pour éviter les couples inbootables). (2) Le filesystem du routeur
déclare `SUPPORTED_KERNELS='/3.2.[6-9]/ /-i386$/'`
(`/usr/local/share/marionnet/filesystems/router-guignol-18474.conf`, ligne écrite à l'ép. 2 de
`marionnet-retro-compat-kernels-images`) — le **premier** motif est donc la série 3.2. Le remap
d'import, lui, **préfère** un `-i386` (`user_level.ml:remap_obsolete_kernel_at_import`), mais il
n'est branché que sur `eval_forest_attribute` : jamais sur la création.

**Voulu.** Qu'un routeur neuf soit bootable **sans** cycle enregistrement/relecture.

**Ce que l'implémentation devra affronter.** Deux voies, et le choix n'est pas anodin.
(a) *Réordonner* le `.conf` (`'/-i386$/ /3.2.[6-9]/'`) : une ligne, mais le fichier est **installé**
(hors dépôt sur cette machine) et le même ordre gouverne la liste proposée par les dialogues.
(b) Faire appliquer au **constructeur** la même préférence que le remap (facteur commun entre
`user_level.ml:1151-1163` et `remap_obsolete_kernel_at_import`) : plus juste, mais cela change le
défaut de **toutes** les natures, donc à valider contre `components-bench.sh`.

*Repéré le 2026-08-09 par le banc de l'ép. 1 de `migration-marshal-to-text`, qui a d'abord signalé
une adaptation « résiduelle » à la deuxième ouverture d'un projet déjà normalisé, puis l'a
reproduite sur un projet **neuf** fabriqué par le canal.*

---

## Modèle — l'**ordre des nœuds s'inverse** à chaque cycle enregistrement/relecture

**Constat.** Enregistrer un projet, le rouvrir, l'enregistrer à nouveau : la liste des nœuds
revient à l'endroit, puis à l'envers, puis à l'endroit — une alternance de **période 2**, mesurée
sur les 8 projets du corpus de `migration-marshal-to-text` (§ 7.5, fait n° 1, et rapportée à
chaque exécution de son banc). Les quatre treeviews, eux, ne bougent pas. Le comportement est
antérieur au chantier : il est identique en `v2` et en `v3`.

**Voulu.** Qu'un projet inchangé se réécrive **à l'identique**. L'argument a pris du poids depuis
que le fichier est du texte (ép. 4 de `migration-marshal-to-text`) : un `netmodel/network.json`
est désormais **diffable**, ce qui était une des raisons d'être de la migration — et un ordre qui
alterne rend chaque diff illisible, donc inutilisable pour un enseignant qui versionnerait ses
sujets de TP.

**Ce que l'implémentation devra affronter.** L'inversion ne vient pas du format mais du couple
`network#to_forest` / `from_tree` (`user_level.ml`) : la lecture reconstruit la liste en tête, si
bien que l'écriture suivante la publie retournée. Corriger d'un côté seulement **déplacerait**
l'alternance sans la supprimer. Deux conséquences à vérifier avant de toucher : (a) le banc
`marshal-bench.sh` mesure exprès sur **deux** cycles (A vs C) et resterait vert — il faudrait donc
lui ajouter l'assertion « A == B » pour prouver la correction ; (b) l'ordre de la liste est celui
que le canal publie (`ls`) et celui que la GUI dessine, donc la correction est **visible par
l'utilisateur** et ne doit pas être glissée dans un épisode qui parle d'autre chose.

*Décision explicite de l'auteur le 2026-08-09 (ép. 4 de `migration-marshal-to-text`) : `v3` hérite
du comportement, la correction sort du chantier — c'est un changement de comportement du modèle,
pas du format.*
