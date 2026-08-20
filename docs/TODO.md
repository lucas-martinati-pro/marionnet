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

## Hygiène — les répertoires mconsole de `~/.uml/` ne sont balayés par personne

**Constat** (mesuré le 2026-08-20, en soldant l'entrée « un `uml_mconsole … sysrq e` peut
rester bloqué »). Chaque invité fait créer par son noyau UML un répertoire `~/.uml/<umid>/`
(socket `mconsole` et compagnie), et ce répertoire **survit à la session** : onze traînaient
ici, dont des `probe-*` du 11 août et des noms de projets fermés depuis. Rien ne les enlève —
ni Marionnet à la sortie, ni `useful-scripts/marionnet-cleanup`, qui ne connaît que
`/tmp/marionnet-*.dir` (vérifié : le mot `.uml` n'y figure pas). Ils ne coûtent presque rien
(quelques kio), mais ils s'accumulent indéfiniment et, surtout, **ils portent le nom de la
machine** : un `~/.uml/m1/` résiduel est
exactement ce qu'un `uml_mconsole m1` d'une session suivante trouvera — refusé aussitôt
(« Connection refused », mesuré : ~10 ms), donc sans conséquence fonctionnelle, mais trompeur
pour qui lit le journal.

**Voulu.** Le même traitement que les répertoires de run (entrée soldée à l'épisode 6 du
chantier `marionnet-todo-transverse`) : `marionnet-cleanup` sait les **repérer** et les proposer
au retrait, Marionnet ne purge jamais tout seul.

**Ce que l'implémentation devra affronter.** Trancher le vivant du mort demande la même prudence
qu'ailleurs : le répertoire appartient à un UML **peut-être encore en marche** (une autre session
de l'utilisateur). Le socket lui-même donne la réponse sans `/proc` : un `uml_mconsole <umid>
version` refusé en quelques millisecondes signe un noyau mort — mais un noyau **gelé** ne répond
pas du tout, d'où l'échéance posée à l'épisode 8 sur toute tentative mconsole.

*Repéré le 2026-08-20, en soldant l'entrée « un `uml_mconsole … sysrq e` peut rester bloqué ».*

---

## Modèle — un `set` explicite peut déposer un **avertissement d'import** hors de tout import

**Constat** (mesuré le 2026-08-20). `set r1 variant aucune` sur un **routeur** répond `ok:true` et
retire bien la variante, mais dépose au passage un avertissement d'import — journal :
`import remapping: router "r1": variant "aucune" removed (…)`. La cause est une asymétrie :
`bin/machine.ml:710` traite `("variant", "aucune")` par une branche dédiée (rétro-compatibilité
des vieux `.mar`), `bin/router.ml:1373` n'a que la branche `""`, si bien que le mot passe par
`remap_absent_variant_at_import`, dont c'est la raison d'être… **à l'import**. Or ces
avertissements ne sont pas jetés : ils s'empilent dans `network#add_import_warning` et sont lus
par `get_and_reset_import_warnings` (`bin/state.ml:581,606`) **à la fin du prochain chargement de
projet**, qui les présentera comme venant de ce chargement-là.

**Voulu.** Qu'un avertissement d'import ne naisse que d'un import. Deux moitiés, la seconde plus
importante : (1) le routeur reconnaît `aucune` comme la machine le fait ; (2) plus généralement,
un `remap_*_at_import` appelé hors chargement ne devrait pas alimenter la liste récapitulative —
ou celle-ci devrait être vidée à l'**ouverture** d'un chargement, et non seulement à sa fin.

**Ce que l'implémentation devra affronter.** Le remap est appelé depuis `eval_forest_attribute`,
qui est le **même chemin** pour l'import d'un `.mar` et pour une écriture du canal : les
distinguer demande soit un drapeau porté par le chargement, soit de sortir du remap la
reconnaissance des valeurs « pas de variante ». La première moitié (une branche dans `router.ml`)
est un correctif d'une ligne, mais elle ne règle que le symptôme mesuré ici : les autres
`remap_*_at_import` gardent la même porte.

*Repéré le 2026-08-20 par l'épisode 7 de `marionnet-todo-transverse`, qui soldait le défaut du
`variant` inexistant et a mesuré le voisin sans le corriger (règle du chantier : un défaut voisin
s'écrit, il ne se corrige pas en passant).*
