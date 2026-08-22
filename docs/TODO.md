# TODO — améliorations repérées, pas encore planifiées

Liste **transverse** : ce qui mérite d'être fait mais n'appartient à aucun chantier en cours, ou
n'y entre que de biais. Ce qui relève d'un chantier reste dans son document (`docs/*.md`, section
« Reste au chantier ») — ici, seulement ce qui serait sinon perdu.

Chaque entrée dit : le **défaut constaté**, ce qu'on **veut à la place**, et ce que
l'implémentation devra affronter (pour que la reprise ne recommence pas l'analyse).

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

## Invités — l'échéance de l'hôte est **deux fois plus courte** que celle du hook d'arrêt

**Constat** (mesuré le 2026-08-21 par l'ép. 16 de `marionnet-todo-transverse`, en soldant l'entrée
voisine) : deux échéances encadrent le rapport de fin de session, et elles se contredisent.
Côté invité, l'unité `marionnet-report.service` s'accorde `TimeoutStopSec=60`. Côté hôte,
`gracefully_terminate` (`bin/simulation_level.ml`) crée, **avant** d'envoyer le `cad`, un fil qui
attend **30 s** puis SIGKILL toute la hiérarchie UML. L'enveloppe extérieure vaut donc la **moitié**
de l'enveloppe intérieure : un rapport lent n'est pas coupé par systemd, qui lui laisse 60 s, mais
par l'hôte, qui tue l'invité au milieu de l'écriture. Mesuré ici, hôte au repos : le rapport prend
4 à 8 s par machine (1, 3 puis 6 machines) — donc la marge existe, mais un facteur 4 de charge la
mange, et c'est exactement la condition dans laquelle le défaut voisin avait été observé (trois
processus `marionnet.exe` concurrents, `journalisation-profonde` ép. 21).

**Voulu.** Que les deux échéances soient ordonnées dans le bon sens : l'invité doit renoncer
**avant** que l'hôte ne tire, pour qu'un rapport lent soit *tronqué proprement par systemd*
(et le reste de l'extinction joué) plutôt que perdu avec l'invité.

**Ce que l'implémentation devra affronter.** Le choix n'est pas neutre : abaisser
`TimeoutStopSec` sous les 30 s de l'hôte coupe un rapport lent mais laisse l'extinction se finir ;
relever les 30 s de l'hôte retarde l'extinction de **tout** invité gelé, or ce fil est précisément
le filet qui rattrape un invité qui ignore le `cad`. Il faudrait donc mesurer le rapport sous
charge réelle avant de choisir un couple, et non ajuster une constante au jugé.

*Écrit ici le 2026-08-21 par l'ép. 16 de `marionnet-todo-transverse`, qui l'a rencontré sans le
corriger (règle § 2 de `docs/todo-transverse.md`).*

---

## Canal et GUI — `--save` enregistre **pendant** que l'extinction descend

**Constat** (mesuré le 2026-08-22). Depuis l'épisode 19, `save` et `save-as` refusent d'écrire le
projet tant que quelque chose tourne. `close --save`, lui, accepte — mesuré sur la même session,
un switch en marche :

```
save         -> {"ok":false,"error":"components_running","detail":"… (s1) …"}
close --save -> {"ok":true,"closed":true,"saved":true}
```

Ce n'est pas une exception assumée mais une **course**, lue dans le code : `leave_current_project`
(`bin/control_server.ml`, corps commun de `close`, `new` et `open`) appelle `st#shutdown_everything ()`,
qui ne fait que **planifier** les extinctions (`do_something_with_every_node_in_parallel` →
`Task_runner#schedule_parallel`, `bin/state.ml:1079,1144`), puis enchaîne `st#save_project`
**tout de suite** : le `tar` part donc pendant que les invités descendent, ce qui est exactement
la situation que le refus de l'épisode 19 écarte. Seul `close_project`, plus loin, attend le
*task runner*. Le menu GUI joue la **même** séquence (« éteindre, enregistrer si oui, fermer »,
`bin/gui/gui_menubar_MARIONNET.ml`), donc le défaut n'est pas propre au canal.

**Voulu.** Que `--save` sauve un réseau **arrêté** : attendre que les extinctions planifiées
soient terminées avant d'appeler `save_project`. Pour un switch la fenêtre est courte, pour un
invité UML elle dure ce que dure un arrêt propre — des dizaines de secondes pendant lesquelles
le cow est encore écrit.

**Ce que l'implémentation devra affronter.** Le point d'attente existe déjà
(`Task_runner#wait_for_all_currently_scheduled_tasks`, que `close_project` utilise), mais
l'insérer entre l'extinction et l'enregistrement change la **durée** de `close --save` sans
changer sa réponse : un client qui pilotait avec un `--timeout` court verra un `timeout` là où
il voyait un succès (l'échéance ne borne que les allers-retours vers le fil GTK, pas la commande
— § 15 de `doc-src/scripting/README.md`). Et comme le menu partage la séquence, corriger le seul
canal recréerait l'asymétrie GUI/canal que l'épisode 19 vient de fermer : les deux se corrigent
ensemble, ou aucun.

*Repéré le 2026-08-22 par l'épisode 19 de `marionnet-todo-transverse`, qui alignait `save` sur la
GUI et a mesuré le voisin sans le corriger (règle du chantier : un défaut voisin s'écrit, il ne se
corrige pas en passant).*

---

## Invités — un invité vivant sous `linux-6.12.95` n'a **aucune** socket mconsole

**Constat** (mesuré le 2026-08-22, en soldant l'entrée « les répertoires mconsole de `~/.uml/`
ne sont balayés par personne »). Un UML `linux-6.12.95` démarré la veille (`umid=m1`, vivant
depuis 13 h, orphelin d'une session morte) n'a **ni** `~/.uml/m1/` **ni** `/tmp/uml/m1/` :

```
$ timeout 2 uml_mconsole m1 version
Warning: couldn't stat file: /home/jean/.uml/m1/mconsole - No such file or directory
Warning: couldn't stat file: /tmp/uml/m1/mconsole - No such file or directory
Sending command to '' : Invalid argument           # rc=1, immédiat
```

Ce n'est ni un `uml_dir=` détourné (sa ligne de commande n'en porte aucun), ni un `HOME` exotique
(son environnement dit `HOME=/home/jean`), ni un noyau sans la fonction (`strings` sur le noyau :
`CONFIG_MCONSOLE=y`, `mconsole_register_dev`, `mconsole (version %d) initialized on %s`). Aucune
socket unix liée ne nomme `mconsole` dans `/proc/net/unix`. Les huit répertoires `~/.uml/<umid>/`
résiduels de cet hôte datent tous des noyaux **précédents** (11 au 14 août).

**Conséquence.** Sur ce noyau, tout le chemin `gracefully_terminate_with_mconsole`
(`bin/simulation_level.ml`, l'échéance de l'épisode 8) échoue **d'emblée** : l'extinction propre
d'un invité — `cad`, `halt`, `sysrq e` — ne peut atteindre personne, et l'arrêt retombe
systématiquement sur le kill. C'est exactement ce que l'épisode 8 croyait réserver au noyau gelé.

**Voulu.** Que l'extinction propre par mconsole marche sur le noyau courant, ou — si UML 6.12 a
changé de convention — que Marionnet lui dise explicitement où poser sa socket (`uml_dir=` sur la
ligne de commande du noyau, qui a l'avantage de rendre le chemin **connu** au lieu de dépendre de
`$HOME`).

**Ce que l'implémentation devra affronter.** La cause reste à établir, et elle se mesure sur un
**boot neuf** : le noyau écrit `mconsole (version N) initialized on <chemin>` sur sa console au
démarrage, et le journal profond de l'invité (chantier `journalisation-profonde`) le capte. Deux
hypothèses à départager — `mconsole_init` échoue à créer le répertoire (droits, `$HOME` non vu par
le noyau au moment de l'initcall), ou le noyau de `marionnet-kernel-rootfs` a perdu l'option au
build. Tant que ce n'est pas tranché, ne pas « corriger » l'échéance de l'épisode 8 : elle fait ce
qu'on lui demande, c'est sa cible qui manque.

*Repéré le 2026-08-22 par l'épisode 20 de `marionnet-todo-transverse`, qui l'a mesuré sans le
corriger (règle du chantier : un défaut voisin s'écrit, il ne se corrige pas en passant).*

---

## Développement — le fichier de configuration « failsafe » est cherché là où **rien** n'est installé

**Constat** (mesuré le 2026-08-22, ép. 22 de `marionnet-todo-transverse`, en soldant le voisin du
glade). `bin/configuration.ml:25` cherche la copie de secours de `marionnet.conf` dans
`<prefix>/share/marionnet/marionnet.conf`, et `:26` dans `<prefix>/etc/marionnet/marionnet.conf`.
**Aucun des deux n'existe**, ni ici ni ailleurs : dune installe ce fichier un cran plus bas,
dans `<prefix>/share/marionnet/**share**/marionnet.conf` (vérifié sur l'installation courante,
où les deux chemins cherchés sont absents et le troisième présent). La liste de priorité
croissante se réduit donc en pratique à `/etc/marionnet/marionnet.conf` puis
`~/.marionnet/marionnet.conf` — la valeur livrée avec le logiciel n'est jamais lue.

**Voulu.** Que la copie livrée soit lue là où elle est réellement installée, et — comme pour le
glade depuis l'ép. 22 — que ce soit **celle du dépôt** (`etc/marionnet.conf`, versionnée) quand le
binaire tourne depuis `_build`.

**Ce que l'implémentation devra affronter.** Le remède de l'ép. 22 n'est **pas** réutilisable tel
quel : `Configuration` est évalué **avant** `Initialization.Path` — c'est même `Configuration` qui
sert à lire `MARIONNET_PREFIX` —, donc il ne peut pas passer par `Path.versioned_data_home`. Il
peut en revanche appeler directement `Development_tree.share_directory` (`bin/development_tree.ml`,
sans dépendance sur `Configuration`), ce pour quoi ce module a été isolé. Reste à trancher si l'on
corrige le chemin cherché ou le chemin installé (`bin/dune`) : changer l'installation déplacerait
un fichier que les paquets `.deb`/RPM et le `Makefile` connaissent peut-être par son emplacement.

*Repéré le 2026-08-22 par l'épisode 22 de `marionnet-todo-transverse`, qui l'a mesuré sans le
corriger (règle du chantier : un défaut voisin s'écrit, il ne se corrige pas en passant).*
