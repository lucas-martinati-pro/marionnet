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

## Canal — `save` écrit le projet pendant que des composants tournent

**Constat** (mesuré le 2026-08-21). En GUI, « Enregistrer » est refusé tant que quelque chose est
allumé ou suspendu — le message le dit en toutes lettres : *« The project can't be saved right
now. One or more network components are still running. Please stop them before saving. »*
(`bin/gui/talking.ml:94`). Par le canal de contrôle, la même demande **passe** : un switch en
marche, `save` répond `{"ok":true,"saved":true,…}`. `cmd_save` (`bin/control_server.ml:3572`) ne
consulte pas `is_there_something_on_or_sleeping`, alors que `cmd_quit` le fait (en mode examen).
Vaut aussi pour `save-as`, qui partage le même corps.

**Voulu.** Une décision explicite, et la même des deux côtés. Soit le canal refuse comme la GUI
(`ok:false`, code dédié, message nommant les composants encore en marche), soit — si l'on juge
qu'une session pilotée doit pouvoir enregistrer en marche — la GUI cesse d'être seule à
l'interdire et le canal le **dit** dans sa réponse (un avertissement, comme les
`notifications`). Ce qu'on ne veut pas, c'est le silence : aujourd'hui le client ne peut pas
savoir que ce qu'il vient d'écrire n'est pas ce que la GUI aurait écrit.

**Ce que l'implémentation devra affronter.** Le refus GUI est ancien et sa raison n'est écrite
nulle part : avant de la recopier dans le canal, il faut établir **ce que vaut** un `.mar`
enregistré en marche (les fichiers cow des invités sont ouverts en écriture au moment de
l'archivage, et le format `v3` archive aussi les treeviews). C'est cette question-là, pas la
garde, qui coûte. Le geste, lui, est symétrique de `cmd_quit` : un `ask_or_answer` sur le
prédicat, puis un `reply_error` ; la grammaire n'en est pas changée, donc aucun client ne bouge.

*Repéré le 2026-08-21 par l'épisode 14 de `marionnet-todo-transverse`, qui grisait les entrées de
menu correspondantes et a mesuré le voisin sans le corriger (règle du chantier : un défaut voisin
s'écrit, il ne se corrige pas en passant).*

---

## Développement — le glade et les images lus sont ceux du Marionnet **installé**

**Constat** (mesuré le 2026-08-21, ép. 15 de `marionnet-todo-transverse`, en soldant le jumeau
du catalogue). `Initialization.Path.marionnet_home` vaut `Meta.prefix ^ "/share/" ^ Meta.name`
sauf surcharge par `MARIONNET_PREFIX` ; en arbre de développement, `Meta.prefix` désigne le
préfixe d'installation, si bien qu'un binaire de `_build` lit le `gui/gui_glade3.xml` et les
`images/` d'un **autre** Marionnet — celui installé sur la machine, éventuellement vieux de
plusieurs versions. Une modification du glade reste donc invisible au run tant qu'on n'a pas
fait `make install` ; c'est le piège que l'ép. 15 vient de fermer pour le `.mo`, un cran plus
haut. Le banc `driven-sessions/message-window-geometry.sh` s'en protège déjà, mais à la main :
il **fabrique** un préfixe temporaire dont `gui/` et `images/` sont des liens vers le dépôt.

**Voulu.** La même chose que pour le catalogue depuis l'ép. 15 : qu'un binaire lancé depuis
`_build` lise le glade et les images **du dépôt**, sans variable ni installation, et que le
journal dise d'où il les prend.

**Ce que l'implémentation devra affronter.** Le remède du catalogue n'est **pas** transposable
tel quel. `MARIONNET_PREFIX` ne pilote pas que `gui/` et `images/` : `Path.filesystems` et
`Path.kernels` en dérivent aussi (`bin/initialization.ml`), et le préfixe que `dune build`
fabrique (`_build/install/default/share/marionnet/`) contient un `filesystems/` **vide** et
**aucun** `kernels/` — mesuré. Basculer le préfixe entier en arbre de développement priverait
donc Marionnet de ses systèmes invités et de ses noyaux : il faut choisir **par répertoire**
(les données versionnées viennent du dépôt, les données installées de l'hôte), ou bien poser un
candidat de repli plutôt qu'un remplacement. C'est ce tri, pas la détection de `_build`, qui
coûte — cette dernière existe déjà, dans `Gettext.locale_directory_of_the_development_tree`.

*Repéré le 2026-08-21 par l'épisode 15 de `marionnet-todo-transverse`, qui l'a mesuré sans le
corriger (règle du chantier : un défaut voisin s'écrit, il ne se corrige pas en passant).*
