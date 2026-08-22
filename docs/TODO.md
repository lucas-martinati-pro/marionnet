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

**Précision mesurée gratuitement le 2026-08-22** (épisode 24, qui journalisait le filet de kill et
a lu ses propres runs) : un invité `debian-trixie` sous **le même `linux-6.12.95`**, mais **de la
session vivante qui l'a démarré**, répond parfaitement — `uml_mconsole succeeded in sending a
'cad' to m1`, où « succeeded » signifie `uml_mconsole` sorti en 0, donc socket présente et servie
(trois runs sur trois). Le constat ci-dessus porte sur un invité **orphelin d'une session morte** :
le diagnostic doit donc commencer par départager les deux situations — socket jamais créée, ou
socket disparue avec la session qui l'a créée — avant de mettre en cause le build du noyau.

*Repéré le 2026-08-22 par l'épisode 20 de `marionnet-todo-transverse`, qui l'a mesuré sans le
corriger (règle du chantier : un défaut voisin s'écrit, il ne se corrige pas en passant).*

