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

**Le catalogue n'est pas seul dans ce cas** (mesuré le 2026-08-21, ép. 13 de
`marionnet-todo-transverse`). Un binaire de `_build` lit aussi le **glade** et les **images** du
Marionnet installé : `Initialization.Path.marionnet_home_gui` dérive de
`Meta.prefix ^ "/share/" ^ Meta.name`, si bien qu'une modification de `bin/gui/gui_glade3.xml`
reste invisible au run tant qu'on n'a pas installé. Deux conséquences pour le diagnostic à
mener ici : (a) sans `make install`, on croit mesurer l'interface du dépôt alors qu'on mesure
celle d'un autre Marionnet — exactement le piège du `.mo`, un cran plus haut ; (b) mais la
variable `MARIONNET_PREFIX`, elle, **fonctionne** — lancer le binaire avec un préfixe fabriqué
(`gui/` et `images/` en liens vers le dépôt) suffit à lui faire lire les sources, ce que le banc
`driven-sessions/message-window-geometry.sh` fait à chaque exécution. Le contraste avec
`MARIONNET_LOCALEPREFIX`, réputée sans effet, est donc **la première piste à instruire** : les
deux variables passent par le même `Configuration.extract_string_variable_or`, et l'une marche.

---

## Modèle — sur un **switch**, tout ce qui n'est pas le rc reste celui du premier démarrage

**Constat** (mesuré le 2026-08-20, `marionnet-todo-transverse` ép. 11, en soldant l'entrée jumelle
sur le rc). `make_simulated_device` (`bin/switch.ml`) lit **trois** réglages à la création du device
simulé : le contenu du rc — devenu une **fonction** à cet épisode —, `activate_fstp` et
`show_vde_terminal`. Les deux derniers sont toujours des **valeurs**, et le device d'un switch
survit à son extinction : ce qu'on change ensuite est accepté par le modèle et jamais joué.

Mesuré sur `activate_fstp`, canal de contrôle, un switch éteint entre les deux démarrages :

```
set s1 activate_fstp true   → {"ok":true,…,"old":"false","new":"true","changed":true}
get s1 activate_fstp        → {"ok":true,…,"activate_fstp":"true"}
switch-info s1 fstp         → "FST DATA VLAN 0000 ROOTSWITCH FSTP IS DISABLED"   ← 2e démarrage
```

Le `vde_switch` **a bien** été relancé (la racine annoncée change d'un démarrage à l'autre) : c'est
sa **ligne de commande**, figée avec le device, qui ne porte pas `-F`. `show_vde_terminal` n'a pas
été mesuré mais partage le même point de capture, et pire : c'est un `initializer` qui ajoute le
processus xterm à la création du device, donc l'activer plus tard ne peut rien produire.

**Voulu.** Qu'un réglage accepté sur un switch éteint soit celui du prochain démarrage — comme le rc
depuis l'ép. 11 —, ou qu'il soit refusé en disant pourquoi.

**Ce que l'implémentation devra affronter.** Le remède du rc (une fonction plutôt qu'une valeur) ne
se transpose pas tel quel : `fstp` est un **argument de la ligne de commande** de `vde_switch`,
construite par `Simulation_level.hub_or_switch`, et l'xterm est un **processus accessoire** ajouté
une fois pour toutes. Il faut donc soit recalculer les arguments dans le `spawn` (le patron du
`slirpvde_process` de `modernisation-world-bridge` ép. 10a bis), soit détruire le device simulé
quand un de ces champs change — ce qui rouvre l'automate d'état (`docs/refonte-automate-composants.md`,
clos). Le dialogue GUI n'est **pas** concerné : il passe par `update_switch_with`, qui détruit le
device.

*Écrit ici le 2026-08-20 par l'ép. 11 de `marionnet-todo-transverse`, qui l'a rencontré sans le
corriger (règle § 2 de `docs/todo-transverse.md`).*

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

## Canal — le verbe `quit` rend la main **avant** que le processus soit parti

**Constat.** `cmd_quit` (`bin/control_server.ml:3562`) renvoie `{"ok":true,"quitting":true}` et
laisse ensuite la boucle principale s'arrêter : quand le client lit la réponse, le processus, ses
composants et ses taps sont **encore là**. Un script qui enchaîne `quit` puis relance une session
en fait donc coexister deux sans le savoir — c'est ainsi que trois `marionnet.exe` ont été trouvés
ensemble le 2026-08-13 (`journalisation-profonde` ép. 21). Un banc s'en sort parce qu'il possède le
pid (`wait "$pid"`) ; un client du canal, non : il n'a que la socket, et la réponse ne porte que
`quitting`.

**Voulu.** Que la fin d'une session soit **observable par le canal seul** : soit la réponse porte le
pid, soit le contrat dit explicitement que la socket disparaît quand le processus est parti — et,
dans les deux cas, que `doc-src/scripting/` l'écrive, puisque c'est ce qu'un script doit attendre
avant d'en lancer une autre.

**Ce que l'implémentation devra affronter.** On ne peut pas répondre *après* être sorti : la réponse
part forcément avant. Le seul point d'accroche est donc ce que le client peut observer ensuite (le
pid, ou la disparition de la socket), pas un « quit synchrone ». Attention aussi au chemin d'examen
de `cmd_quit`, qui refuse déjà de quitter dans certains cas : le contrat neuf doit valoir pour la
réponse `quitting`, pas pour les refus.

*Écrit le 2026-08-20 par l'épisode 9 de `marionnet-todo-transverse` : la remarque vivait dans
l'entrée « deux sessions partagent l'adresse hôte de leurs taps », soldée par cet épisode, et
serait sinon partie avec elle.*

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
