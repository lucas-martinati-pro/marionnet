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

## Défaut — une machine virtuelle démarre **sans le dire** avec un tap fantôme

**Constat.** Quand `Tap_provider.make_eth42_tap` échoue, `bin/simulation_level.ml:1166-1170` passe
au noyau UML le littéral `wrong-tap-name` :

```
eth42=tuntap,wrong-tap-name,42:42:b2:43:ee:27,172.23.0.254
```

La machine démarre, et **rien ne le dit à l'utilisateur** : `report_eth42_tap_failure`
(`bin/simulation_level.ml:1021-1040`) n'ouvre un dialogue que dans **un** cas, la collision
d'adresse avec une autre session ; les autres échecs se contentent d'une ligne de journal. Dans
l'invité, la panne se manifeste alors très loin de sa cause — `xeyes` répond
`Can't open display: :0` — et l'enseignant cherche du côté de X11 (mesuré sur un poste MarioNUM le
2026-09-02, ép. 40 de `modernisation-installation-marionnet` : le conteneur n'avait pas
`/dev/net/tun`).

**Ce qu'on veut.** Que le démarrage d'une machine sans son tap eth42 soit **visible** : soit un
avertissement une fois par session (comme la collision, avec le même garde-fou
`first_collision_report` pour ne pas répéter par machine), soit un refus explicite si l'on juge
qu'une machine sans canal hôte n'a pas de sens.

**Obstacles.** (a) Depuis l'ép. 40, `Tap_provider.unavailability ()` sait **pourquoi** — le message
doit reprendre cette cause plutôt que d'en inventer une ; (b) l'avertissement de démarrage de
`bin/marionnet.ml` couvre déjà le cas « aucun tap possible », donc en ajouter un par machine
serait du bruit : le bon déclencheur est l'échec **inattendu**, c'est-à-dire alors que
`is_usable ()` disait oui ; (c) le mode examen masque certains dialogues, mais celui-ci décrit une
panne de la machine de l'étudiant, comme la collision — même raisonnement, même exception ;
(d) `wrong-tap-name` lui-même mériterait de disparaître au profit d'un argument `eth42` absent, à
condition de vérifier ce que le noyau UML fait d'un `eth42=` manquant.
