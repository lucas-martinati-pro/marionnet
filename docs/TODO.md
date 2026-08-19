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

## i18n — en arbre de développement, Marionnet lit le catalogue d'un AUTRE Marionnet

**Constat** (mesuré le 2026-08-10 à l'ép. 8b de `migration-marshal-to-text`, `strace -e openat`).
Le binaire de `_build` ouvre `/usr/share/locale/fr/LC_MESSAGES/marionnet.mo` — le catalogue du
Marionnet **installé sur la machine**, qui peut avoir plusieurs versions de retard — et jamais
celui du dépôt, alors même que la cascade de `bin/gettext.ml` explore le site dune-site
(25 `openat` sous `_build/install/default/share/marionnet/locale`, dont les `.mo` sont des **liens
symboliques** vers `_build/default/i18n/`). Conséquence : on ne peut **pas** vérifier une
traduction sans installer, et pire, on croit la vérifier alors qu'on lit le catalogue d'un autre
binaire — exactement le piège que le chantier i18n clos avait nommé (« preuve du `.mo` réellement
chargé »).

**Voulu.** Qu'un binaire lancé depuis `_build` lise les catalogues du dépôt, pour que
`LC_ALL=fr_FR.UTF-8 ./_build/default/bin/marionnet.exe` montre les traductions **qu'on vient
d'écrire**.

**Ce que l'implémentation devra affronter.** Deux pistes ont été essayées à l'ép. 8b et
**retirées faute d'effet mesuré** : (a) `MARIONNET_LOCALEPREFIX` — la cascade la place pourtant en
deuxième position (`gettext.ml:47-52`), mais la fixer ne change pas le fichier ouvert, ce qui
demande d'abord de vérifier que `Configuration.get_string_variable` lit bien l'environnement pour
cette variable ; (b) `~follow:()` sur le `find` de la cascade, l'hypothèse étant qu'un lien
symbolique n'est pas un `'f'` pour `UnixExtra.find` (qui utilise `lstat` sans `~follow`) — sans
effet non plus. Le diagnostic reste donc **ouvert** : il faudra instrumenter `localeprefix`
(le `Log.printf` de `gettext.ml:59` est écrit **avant** que le journal ne soit prêt, donc perdu —
c'est la première chose à corriger pour voir quoi que ce soit) plutôt que de continuer à deviner.
Le repli final `try_to_infer_localeprefix_searching_marionnet_dot_mo_in_usr` est le suspect
principal : il cherche dans `/usr` et trouve toujours quelque chose sur un poste où Marionnet est
installé.

**Confirmé le 2026-08-15** (clôture de `journalisation-profonde`, ép. 24) : ce défaut a **produit
un faux constat**. Une session française classait « Rapport sur m1 » à côté de « Console of m1 », ce
qui a été consigné comme une incohérence de traduction ; les quatre titres sont pourtant traduits
dans `bin/po/fr.po` **et** dans le catalogue installé du switch courant. C'est
`/usr/share/locale/fr/LC_MESSAGES/marionnet.mo`, **daté du 8 juillet 2023**, qui était lu : il porte
`Report on ` (msgid ancien) et pas `Console of ` / `Terminal of ` (msgid de 2026). Le coût de ce
défaut n'est donc pas seulement « on ne peut pas vérifier une traduction » : c'est **une mesure
fausse qu'on croit vraie**.

---

## Modèle — `wait --ready` ment au second démarrage d'un invité

**Constat** (mesuré le 2026-08-13, `journalisation-profonde` ép. 20, sur **machine et routeur** —
ce n'est pas une propriété du genre). `make_hostfs_content` est appelé dans l'`initializer` de
`uml_process` (`simulation_level.ml:1530`), donc à la **création** du device simulé, lequel
**survit au `poweroff`**. Au démarrage suivant, ni `boot_parameters` ni le marqueur de disponibilité
ne sont réécrits : la garde de fraîcheur compare deux fichiers également périmés et répond
`ready: true` en 50 ms, sur le marqueur du boot **précédent**. Un `exec` qui suit se heurte alors à
un veilleur qui n'est pas encore là.

**Voulu.** Qu'un second démarrage réécrive ce que le premier a déposé — donc que `--ready` réponde
sur le boot **en cours**.

**Ce que l'implémentation devra affronter.** Deux remèdes, tous deux dans `simulation_level.ml` :
rejouer `make_hostfs_content` au `spawn` (c'est ce que son nom laisse attendre), ou effacer le
marqueur au démarrage. Le point dur est que le chemin de démarrage est **commun à tous les
composants** : cela se tranche avec l'automate d'état en tête
(`docs/refonte-automate-composants.md`). En attendant, un banc qui redémarre un invité ne demande
pas `--ready` : il attend que l'invité **réponde** (`exec <c> -- true`). Détail complet :
`docs/journalisation-profonde.md` § 6.

*Reversé ici le 2026-08-15 à la clôture de `journalisation-profonde`.*

---

## Modèle — un `rc-set` sur un **switch** n'est pris en compte qu'au premier démarrage

**Constat** (mesuré le 2026-08-12, `journalisation-profonde` ép. 17). Le contenu du rc est capturé à
la **création du device simulé** (`switch.ml:460-468`, `make_simulated_device`), et ce device
**survit à un `poweroff`** : un `rc-set` ultérieur est accepté (`changed: true`), `rc-get` rend bien
le nouveau contenu, et le démarrage suivant rejoue **l'ancien** — sans que rien ne le signale. Pour
une machine le problème n'existe pas : son rc est un fichier du hostfs, relu à chaque boot. Même
famille que l'entrée précédente : un état capturé à la création d'un device qui survit à
l'extinction.

**Voulu.** Qu'un `rc-set` accepté soit celui qui sera joué au prochain démarrage, ou qu'il soit
refusé en disant pourquoi.

**Ce que l'implémentation devra affronter.** Deux remèdes, tous deux dans `switch.ml` : passer une
**fonction** plutôt qu'une valeur au constructeur du device, ou détruire le device simulé quand le
rc change. Comme ci-dessus, à trancher avec l'automate d'état en tête. En attendant, tout banc ou TP
qui veut deux rc différents utilise **deux switchs**.

*Reversé ici le 2026-08-15 à la clôture de `journalisation-profonde`.*

---

## Invités — le rapport de fin de session n'est pas garanti

**Constat** (mesuré le 2026-08-13, `journalisation-profonde` ép. 21, sur trois machines
`debian-trixie` d'une même session `--exam`) : les trois ont archivé leur console et leur terminal,
**une seule** avait écrit son `report.md`, alors que les trois avaient atteint la fin de leur relais
(journaux `rc_config` identiques). L'hypothèse la plus simple est celle que l'ép. 16 a déjà mesurée
pour le veilleur : une unité systemd **démarrée depuis le relais** n'a son job exécuté qu'**à la fin
du boot**, bien après le marqueur de disponibilité ; une extinction demandée quelques secondes après
ce marqueur manque donc le hook d'arrêt.

**Voulu.** Qu'une machine éteinte proprement laisse son rapport, quel que soit le délai depuis son
démarrage — c'est une **copie à noter** qui manque, pas un journal de confort.

**Ce que l'implémentation devra affronter.** Rien n'est instruit : il faudrait d'abord **mesurer**
le délai réel entre le marqueur et l'activation du hook, sur plusieurs images, avant de choisir
entre attendre, accrocher autrement, ou déclencher le rapport à l'extinction depuis l'hôte. En
attendant, le remède coûte une commande — **demander le rapport avant d'éteindre** — ce que
`doc-src/teacher-guide.md` § 5.5 conseille et que les bancs jouent.

*Reversé ici le 2026-08-15 à la clôture de `journalisation-profonde`.*

---

## Réseau — deux sessions Marionnet simultanées partagent l'adresse hôte de leurs taps

**Constat** (vu le 2026-08-13, `journalisation-profonde` ép. 21, en cherchant pourquoi un boot
n'aboutissait pas). Trois processus `marionnet.exe` tournaient ensemble — deux runs précédents
survivants —, chacun avec ses UML, ses taps `mtap<pid>-*` et **la même** adresse hôte
`172.23.0.254`. Rien n'interdit de lancer deux sessions, et **personne ne le signale** ; l'invité,
lui, ne boote pas jusqu'à son relais.

**Voulu.** Au minimum, que la collision soit **dite** (journal, dialogue) ; au mieux, que l'adresse
d'extrémité des taps soit dérivée du processus, comme l'est déjà le nom du tap.

**Ce que l'implémentation devra affronter.** L'adresse est une constante de configuration héritée
(le contrat réseau du chantier `marionnet-daemon-elimination` la fixe côté `Tap_provider`), donc la
dériver touche à ce qu'un TP écrit dans ses scénarios. Une **détection** est nettement moins
risquée qu'un changement d'adresse. À noter au passage, et déjà connu du dépôt : le verbe qui quitte
**rend la main sans garantir que le processus est parti** — c'est ainsi que trois sessions ont pu
coexister.

*Reversé ici le 2026-08-15 à la clôture de `journalisation-profonde`.*

---

## Canal de contrôle — un `--control-socket` trop long échoue en silence

**Constat** (mesuré le 2026-08-15, `modernisation-world-bridge` ép. 2). Lancé avec
`--control-socket <chemin de 127 caractères>`, Marionnet **démarre normalement, ouvre sa GUI, et ne
crée jamais le socket** : aucun message, aucun refus, rien dans la sortie standard. La cause est la
limite du champ `sun_path` d'une adresse unix — **108 octets**, terminaison comprise —, bien connue
mais invisible ici, le chemin ayant seulement l'air « long » (répertoire de travail temporaire). Le
client, lui, dit correctement `not a unix socket` : c'est le serveur qui se tait.

**Voulu.** Que le serveur **refuse explicitement** un chemin trop long — au démarrage, avant même
de tenter le `bind`, avec un message nommant la limite et la longueur fournie. Une session pilotée
qui ne peut pas être pilotée doit le dire ; c'est d'autant plus vrai qu'un banc de test choisit
rarement ses chemins à la main (répertoires temporaires imbriqués, `XDG_RUNTIME_DIR`, chemins de
projet).

**Ce que l'implémentation devra affronter.** Peu de choses : le contrôle est une comparaison de
longueur au moment où l'option est lue (`bin/control_server.ml`, ouverture du canal), et le mode
d'échec à choisir est le seul vrai arbitrage — refuser de démarrer, ou démarrer en GUI seule après
un avertissement bien visible. La documentation d'usage (`doc-src/scripting/`) gagnerait la même
phrase, puisqu'elle demande un chemin absolu sans dire qu'il est aussi **borné**.

*Reversé ici le 2026-08-15 depuis le chantier `modernisation-world-bridge` (ép. 2), qui l'a
rencontré de biais.*

---

## Canal — `add … --ports=N` ne vérifie **pas** les bornes de la nature

**Constat** (mesuré le 2026-08-18, `modernisation-world-bridge` ép. 10b). `set <n> port_no <N>`
refuse proprement ce qui sort des bornes du composant (« a nat_bridge cannot have more than 16
ports », « … fewer than 6 port(s) here : cables are plugged too high »). `add`, lui, ne vérifie
que `N ≥ 0` (`cmd_add`, `bin/control_server.ml`) et passe la valeur telle quelle au constructeur :
`add machine m0 --ports=0` et `add machine m99 --ports=99` sont **acceptés**, comme
`add nat_bridge N --ports=0`. Deux natures s'en tirent par accident — `switch` et `world_gateway`
meurent sur une assertion de `bin/gui/ledgrid.ml` — ce qui montre bien qu'aucun garde-fou n'est
prévu là.

**Voulu.** Que `add` refuse exactement ce que `set` refuse : les bornes appartiennent à la nature
(`port_no_min` / `port_no_max`, déjà interrogées par le canal pour `set`), et un composant créé
hors bornes est un composant que la GUI n'aurait jamais laissé construire.

**Ce que l'implémentation devra affronter.** Les bornes sont lues sur un **nœud existant**
(`n#port_no_min`, `n#port_no_max`), alors qu'`add` doit décider **avant** de construire :
il faudra soit une table `kind → (min, max)` à côté de `node_maker` (une seconde source de
vérité, ce que ce fichier évite par principe), soit construire puis vérifier puis détruire — le
`rollback` d'`add` existe déjà pour les `--<champ>=<valeur>` refusés, et pourrait servir aussi à
cela, à condition que le constructeur ne meure pas avant (cf. l'entrée suivante).

*Reversé ici le 2026-08-18 depuis le chantier `modernisation-world-bridge` (ép. 10b), qui l'a
rencontré de biais.*

---

## Canal — un constructeur qui échoue laisse quand même son nœud dans le réseau

**Constat** (mesuré le 2026-08-18, `modernisation-world-bridge` ép. 10b). `add switch s0
--ports=0` répond `ok:false` (« creating "s0" failed: … ledgrid.ml, line 320: Assertion
failed ») — et pourtant `s0` **figure ensuite dans `ls`**, puis dans le `.mar` sauvegardé.
Même chose pour `add world_gateway g99 --ports=99`. La raison est que le nœud s'enregistre
auprès du réseau **dans son constructeur**, avant la partie qui lève : quand `node_maker`
rattrape l'exception, le mal est fait, et le `rollback` prévu pour les champs refusés ne
s'applique pas à ce chemin-là.

**Voulu.** Qu'un `add` refusé laisse le réseau **exactement** comme il était — c'est déjà la
promesse écrite pour les options `--<champ>=<valeur>` (« un `add` échoué signifie un réseau
inchangé »), et elle doit valoir aussi quand c'est le constructeur qui échoue.

**Ce que l'implémentation devra affronter.** Le rattrapage ne peut pas se contenter de
`Printexc.to_string` : il doit **chercher** le nœud du nom demandé et le détruire s'il existe
(`st#network#get_node_by_name`, puis `destroy`), en sachant que l'objet est à moitié construit —
c'est justement pourquoi il vaut mieux ne détruire que ce qui est enregistré, sans toucher à ce
que l'exception a laissé en plan. À faire dans la même section critique
(`st#network_change`) que la création.

*Reversé ici le 2026-08-18 depuis le chantier `modernisation-world-bridge` (ép. 10b), qui l'a
rencontré de biais.*

---

## GUI — les **autres** fenêtres de message s'étalent encore sur toute la largeur

**Constat** (mesuré le 2026-08-19, à l'occasion du correctif `34393bb`, qui a plafonné le seul
`title_QUESTION`). Le même défaut Gtk+ 3 subsiste ailleurs : un label sans plafond de largeur
**naturelle** réclame son plus long paragraphe sur une ligne, et le dialogue obéit.
- `dialog_MESSAGE` (`bin/gui/gui_glade3.xml`) : son label `content` a bien `wrap`, mais **aucun**
  `max-width-chars` — **1814 px** relevés sur l'allocation réelle pour un message d'erreur d'un
  seul paragraphe. C'est la forme de **tous** les `Simple_dialogs.error / warning / info / help`.
  Son label `title`, lui, n'a même pas de `wrap` (exactement l'état de `title_QUESTION` avant le
  correctif) : sans conséquence tant que les titres restent courts.
- `bin/gui/simple_dialogs.ml` : les labels en `~line_wrap:true` de `recapitulative` (en-tête,
  préambule, détail d'un dépliant) et de `ask_text_dialog` n'ont pas de plafond non plus. Le
  `~width:640` de la fenêtre de `recapitulative` ne protège de rien : c'est un **minimum**.

**Voulu.** Que tout label de message porte un plafond de largeur naturelle, comme `title_QUESTION`
(72) et les trois labels OCaml de `lan_bridge.ml` / `nat_bridge.ml` / `simple_dialogs.ml`
(`7192aa3`). Un plafond vaut pour les douze langues ; un saut de ligne calculé pour l'une d'elles,
non — c'est l'argument qui a écarté les `\n` posés à la main.

**Ce que l'implémentation devra affronter.** Le correctif se pose à deux endroits selon l'origine
du label : dans le **glade** pour ceux que charge le builder (`wrap` + `max-width-chars` sur
`content` et `title` de `dialog_MESSAGE`), en **OCaml** (`set_max_width_chars`) pour ceux que
construit `GMisc.label`. Aucun `msgid` n'est concerné, donc aucun catalogue. Le point dur est
ailleurs : une partie des messages du dépôt contient **déjà** des `\n` calculés à la main
(`talking.ml`, `state.ml`, `gui_dialog_A_PROPOS.ml`, cf. `7192aa3`) ; un plafond posé par-dessus
coupe une seconde fois et peut produire des lignes irrégulières. Il faudra donc, message par
message, soit retirer la coupure manuelle, soit accepter le résultat — un balayage aveugle est
exclu.

*Reversé ici le 2026-08-19 depuis le correctif de la fenêtre « Quitter » (`34393bb`), qui les a
rencontrés de biais.*

---

## Hygiène — les **fichiers de socket du blinker** s'accumulent dans `/tmp`, un par run

**Constat.** `bin/gui/ledgrid_manager.ml` fabrique au chargement du module un chemin
`/tmp/.marionnet-blinker-server-socket-<n>` (`UnixExtra.temp_file`), sur lequel le thread blinker
se `bind`. Ce fichier n'est retiré que sur le **chemin de sortie propre** : la branche
`please-die` de la boucle et `kill_blinker_thread`. Toute fin anormale — plantage, `SIGKILL`,
gel de l'application — le laisse en place. Relevé le 2026-08-19 : **84 fichiers**, du 4 août au
19 août, plus 2 `/tmp/blinker-killer-client-socket-*` (ceux-là créés par `Filename.temp_file`
dans `kill_blinker_thread`). Rien ne les balaie, ni au démarrage ni ailleurs.

**Voulu.** Qu'un run ne laisse pas de trace après lui, et qu'un run **de plus** ne coûte pas un
fichier de plus dans `/tmp` indéfiniment. Deux gestes possibles, indépendants : retirer le fichier
dès que le `bind` a réussi (une socket unix reste utilisable après `unlink` du chemin **tant que
les deux extrémités le tiennent ouvert** — mais ici le pair, `wirefilter`, résout le chemin à
chaque `sendto` : à vérifier avant de choisir cette voie), ou balayer au démarrage les fichiers du
motif dont **aucun processus vivant** ne tient la socket.

**Ce que l'implémentation devra affronter.** Le nom est calculé à l'initialisation du module,
avant que quoi que ce soit ne soit lancé, et il est passé tel quel à `wirefilter` en `--blink`
(`bin/simulation_level.ml:735-743`) : il ne peut donc pas devenir « anonyme » (socket abstraite)
sans toucher aussi la ligne de commande de `wirefilter`. Un balayage au démarrage, lui, doit
distinguer les fichiers morts des **sockets d'une autre instance de Marionnet tournant en
parallèle** — `/tmp` est partagé, et deux sessions simultanées sont un cas connu du dépôt (voir
l'entrée « deux sessions Marionnet simultanées partagent l'adresse hôte de leurs taps »). Le test
sûr n'est pas la date du fichier mais le fait qu'aucun processus ne le tienne ouvert.

*Repéré le 2026-08-19, en instruisant le gel du blinker (`ledgrid_manager`) : chaque fin brutale
laisse le sien, et le gel en question en est une.*

---

## Hygiène — des `vde_switch` / `wirefilter` **survivent à la session** qui les a lancés

**Constat.** Relevé le 2026-08-19 sur cette machine de développement : **120 processus**
(80 `vde_switch`, 40 `wirefilter`) sans parent Marionnet, tous réadoptés par `systemd --user`,
et répartis en **17 identifiants de session distincts** échelonnés du 13 au 19 août. Marionnet
possède pourtant ce qu'il faut (`at_exit: killing all current descendants` puis `killing all
orphans before exiting`, plus le *descendants monitor*) : ces filets ne jouent que sur une sortie
**qui s'exécute** — un `SIGKILL`, un plantage ou un gel qu'il faut trancher les met tous hors jeu
d'un coup.

**Voulu.** Qu'une session tuée brutalement n'abandonne pas ses processus auxiliaires — ou, à
défaut, qu'une session suivante sache les reconnaître et **proposer** de les balayer. Ils ne
gênent pas une nouvelle session (chaque run a son propre répertoire de travail), mais ils tiennent
des sockets et des descripteurs, et ils s'accumulent sans borne.

**Ce que l'implémentation devra affronter.** Le seul mécanisme qui survive au `SIGKILL` du parent
est côté noyau : `prctl(PR_SET_PDEATHSIG)` posé **par l'enfant, entre `fork` et `exec`**, ou un
`cgroup` par session. Il n'y a pas de contradiction avec le `setsid` de `bin/marionnet.ml:51-58` —
celui-là détache Marionnet du **terminal lançeur**, pas ses enfants de lui : vérifié, les
`vde_switch` orphelins portent encore comme identifiant de session le **PID du Marionnet mort**
qui les a lancés. Mais `PR_SET_PDEATHSIG` ne vaut que pour les enfants **directs** et n'existe pas
dans le `Unix` d'OCaml : il faudrait un stub C sur le chemin de `Simulation_level.process#spawn`.

La voie de moindre risque est donc plutôt la seconde, et elle a un point d'appui : puisque
l'identifiant de session de ces processus **est** le PID du Marionnet qui les a lancés, un
balayage n'a pas à deviner — il regroupe par `sid` et ne retient que les groupes dont le processus
`sid` n'existe plus. Reste à respecter la règle du dépôt (lister les PID, les montrer, ne tuer que
par PID exact, jamais par motif), et à ne **jamais** balayer sans demander : deux sessions
Marionnet simultanées sont un cas connu (voir l'entrée « deux sessions Marionnet simultanées
partagent l'adresse hôte de leurs taps »).

*Repéré le 2026-08-19, en nettoyant après la reproduction du gel du blinker.*
