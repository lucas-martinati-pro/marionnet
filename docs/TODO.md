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

## Défaut — le **LAN bridge** ne dit rien quand son pont n'a pas pu être construit

**Constat.** Le bridge NAT avertit l'utilisateur quand sa résolution de pont échoue
(`bin/nat_bridge.ml`, `Simple_dialogs.warning`, message enrichi à l'ép. 41 de
`modernisation-installation-marionnet`). Le **LAN bridge** n'a **aucun** avertissement de ce
genre : `bin/lan_bridge.ml` ne contient pas un seul `Simple_dialogs.warning`, si bien qu'un
composant dont le pont hôte n'a pas pu être bâti atteint l'état `on` **en silence** — exactement
ce que l'avertissement du NAT bridge existe pour empêcher —, et les machines qui y sont connectées
n'atteignent rien sans que rien ne l'ait dit.

**Ce qu'on veut.** Le pendant de l'avertissement du NAT bridge, avec ses trois propriétés : montré
**une fois** par démarrage (`already_warned`, ré-armé par `after_terminate`), nommant la **cause
mesurée** (le code symbolique de `Lan_bridge_host.error`, pas une devinette) et le geste qui la
répare, et passant par `Simple_dialogs.warning` — sûr depuis un autre thread (GMain_actor) et
transformé en notification dans une session pilotée.

**Obstacles.** (a) Les causes ne sont **pas** celles du NAT bridge : ici la machine peut n'avoir
aucune carte utilisable, ou celle qu'on veut asservir peut porter l'adresse par laquelle
l'utilisateur est connecté — un message qui recopierait la table de `advice_of_error` mentirait ;
(b) le bloc (c) est plus intrusif que le (b) (adresse et route par défaut déplacées), donc le
conseil « accordez la règle » doit renvoyer au § 7 de la page INSTALL, qui dit ce que le bloc fait
à l'hôte, et non seulement à la commande ; (c) le banc
`driven-sessions/nat-bridge-warning-names-its-cause.sh` est directement transposable (fausse
commande hôte par `MARIONNET_LANBRIDGE_SCRIPT`), ce qui rend le défaut mesurable avant d'être
corrigé.

## Défaut — `marionnet-relay.service` retient `multi-user.target` de ~7 s (16,5 s en salle)

**Constat, mesuré deux fois.** Sur la salle MarioNUM (2026-09-02) : `systemd-analyze blame` place
`marionnet-relay.service` en deuxième position avec **16,5 s**, et `critical-chain` montre que
c'est **lui** qui retarde `multi-user.target` (26,7 s). Sur cette machine (2026-09-03, image
publiée `machine-debian-trixie-16341`, 192 Mio) : **7,264 s** avec `--debug`, **6,899 s** sans,
pour un `multi-user.target` à **11,0 s**. Le même défaut, à l'échelle près de la machine.

**Ce que la mesure a déjà éliminé.** (a) *Ce n'est pas la trace* : le relais journalise
**324 lignes** sous `--debug` contre **45** sans, pour la **même durée** (7,26 s contre 6,90 s) —
le coût n'est donc pas dans le `set -x` ni dans l'écriture du journal. (b) *Ce n'est pas un
geste unique qui bloque* : aucun écart de plus de 2 s entre deux lignes tracées consécutives.
(c) *Une part est identifiée* : un **`daemon-reload` de systemd coûte 1,30 s** (« Reloading
finished in 1302 ms »), soit ~19 % du total — le relais écrit des unités et les fait relire.

**Où passent les secondes, mesuré (2026-09-03, épisode 26).** Le relais trace désormais à la
**microseconde** (`PS4` portant `$EPOCHREALTIME`), et l'écart entre deux lignes **est** le coût de
la commande entre elles — le prompt étant imprimé avant l'exécution. Sur un boot trixie, 314
lignes datées couvrant **4,55 s** :

| coût | où | quoi |
|---|---|---|
| **1,633 s** | `marionnet-relay.00-journal:311` | le bloc **non tracé** qui suit (`{ set +x ; }`) : écriture des unités `marionnet-report`/`marionnet-watch`, **`systemctl daemon-reload`** (1,30 s à lui seul) et `systemctl start marionnet-report.service` |
| **~1,02 s** | `marionnet-relay:415-417` | **huit** `systemctl stop getty@tty$i.service`, **un par un** (0,085 à 0,144 s chacun) — **corrigé le 2026-09-03**, voir ci-dessous |
| 0,135 s | `marionnet-relay:134` | `ip netns add marionnet-mgmt` |
| 0,086 s | `marionnet-relay:108` | `mount none /mnt/hostfs -t hostfs` |
| le reste | ~300 lignes | ~5 ms par commande tracée |

**(a) Les gettys : FAIT le 2026-09-03, et le gain n'est pas celui qu'on attendait.** Le relais
(`marionnet-relay.trixie`) passe les unités surnuméraires à **une seule** invocation — les deux
listes, `start` et `stop`, sont construites dans un tableau et données à `systemctl` d'un coup.
Mesuré par l'outil de l'épisode 23 (`filesystem.update-published-image.sh`, image publiée
`machine-debian-trixie-16341` respinnée en `machine-debian-trixie-11950`, hors répertoire de
release) :

- au boot, **une** ligne tracée au lieu de huit, et elle coûte **0,577 s** contre les **~1,02 s**
  de l'épisode 26 ;
- A/B **dans le même invité, au même boot** (3 tours) : huit appels **0,761 / 0,811 / 0,808 s**,
  un seul appel **0,485 / 0,516 / 0,486 s**.

Donc **~0,3 s** gagnées, et non ~0,9 : le modèle « un aller-retour au lieu de huit » était faux.
Le prix d'un `systemctl` supplémentaire est ~41 ms, mais **les huit unités coûtent dans la même
transaction** (~0,50 s à elles seules, alors qu'aucun getty ne tourne — `NAutoVTs=0`, seul
`getty@tty0` est actif). **Suite possible, non faite** : ne rien arrêter quand rien n'est chargé
(un `systemctl list-units 'getty@tty*'` d'abord), ce qui viserait les 0,5 s restantes au lieu des
41 ms par appel — à mesurer, car cette interrogation coûte elle aussi un aller-retour.

**Ce qu'on veut encore.** (b) Le `daemon-reload` : les deux unités sont écrites dans `/run/systemd/system`
à **chaque** boot ; les poser dans l'image (`pupisto.debian.sh`) supprimerait le rechargement,
mais déplace du travail vers la fabrication de l'image — et une unité livrée dans l'image ne peut
plus dépendre de ce que le boot courant a lu dans le hostfs (le `TimeoutStopSec` vient de
`report_deadline`).

**Obstacles (inchangés, et c'est pourquoi ce n'est pas un correctif en passant).** (a) le relais
est le point d'entrée de toute la journalisation profonde : ce qu'on en sort doit rester
**avant** les gestes qui en dépendent (le marqueur de disponibilité, le rapport) ; (b) un
`Type=oneshot` sans `--no-block` retient `multi-user.target` **par construction** — changer cela
déplace le problème vers l'ordre des unités au lieu de le supprimer, et c'est un arbitrage, pas
une évidence ; (c) le constat voisin « trixie n'écrit pas `marionnet-guest-ready` »
(`docs/kernel-rootfs-refresh.md`) touche le même fichier et devrait être traité avec celui-ci ;
(d) le `daemon-reload` est peut-être évitable (écrire les unités **avant** le premier boot, dans
l'image), mais cela déplace du travail vers `pupisto.debian.sh` — encore un arbitrage.

---

## Défaut — sur un écran plus court que la palette, les derniers composants sont **hors d'atteinte**

**Constat** (mesuré le 2026-09-04, `ubuntu:24.04` + Xvfb en 1024x600) : la fenêtre principale
s'ouvre à 600 px, la palette n'en montre que **six** icônes sur huit, et les deux dernières
(le nuage, la planète) ne sont accessibles **par aucun geste** — ni flèche de débordement (le
`GtkToolbar` n'en dessine aucune, mesuré), ni molette (la palette ne défile pas, mesuré :
0 pixel de différence entre la capture avant et après dix crans de molette, à l'artefact de
survol près).

**Défaut préexistant** : il n'est pas introduit par l'ajustement de hauteur à l'exécution — le
binaire publié le montre à l'identique dès que la fenêtre est trop courte (mesuré à 583 px :
six icônes, la sixième coupée). L'ajustement le rend simplement **rare** au lieu d'être le cas
nominal : la fenêtre demande désormais exactement ce que la palette exige, donc seul un écran
réellement plus petit que la palette (< ~780 px utiles ici, ~845 sur une machine au thème plus
large) reste concerné.

**Ce qu'on veut à la place** : que la palette **défile** quand elle ne tient pas. Elle est déjà
dans un `GtkScrolledWindow` (`scrolledwindow2`), c'est-à-dire l'endroit exact où cela devrait se
produire.

**Obstacle déjà identifié** : on ne sait pas encore *pourquoi* elle ne défile pas alors que la
barre demande 623 px dans un viewport qui n'en offre que 445. Deux pistes non départagées — les
événements de molette ne parviennent pas au `GtkScrolledWindow` (les items de la palette sont des
`GMenu.menu_bar`, ce qui n'est pas l'usage prévu d'une barre d'outils), ou l'ajustement vertical
du viewport reste à `upper = page_size`. Trancher demande une mesure côté GTK (état de
l'ajustement), pas une lecture de code.

## Chantier à amorcer — **`modernisation-routeur-64bits`** : un routeur qui ne coûte plus une architecture étrangère

**Constat.** Le seul système de fichiers de **routeur** publié est `router-guignol-18474`, un
userland **i386**. Mesuré dans son `.conf` : `SUPPORTED_KERNELS='/3.2.[6-9]/ /-i386$/'`, que
`linux-6.12.95` **ne satisfait pas** — seul `linux-6.12.95-i386` convient. Et le filtre de
`bin/disk.ml:544-547` est **dur** (*« do not propose any filesystems which haven't at least one
compatible installed kernel »*) : sans ce noyau, guignol n'apparaît simplement pas, sans un mot.
Trois conséquences, toutes payées aujourd'hui par l'utilisateur :

1. un routeur coûte **deux** paquets (`marionnet-fs-guignol` **et** `marionnet-kernels-i386`), là
   où une machine récente n'en coûte qu'un ;
2. sur Debian/Ubuntu, il impose `dpkg --add-architecture i386` — activer une architecture
   étrangère sur toutes les machines d'une salle pour obtenir un routeur ;
3. sur **RHEL 10 / AlmaLinux 10 / Rocky 10**, qui ont supprimé tout le multilib 32 bits (mesuré à
   l'ép. 19 de `modernisation-installation-marionnet`), `marionnet-kernels-i386` n'est **pas
   installable** : sur cette famille, **aucun routeur n'est possible**.

**Ce qu'on veut.** Une image de routeur **64 bits**, supportée par `linux-6.12.95`, publiée dans
les mêmes canaux et sous les mêmes conventions que les autres (`router-<distrib>-<sum>`), afin
qu'un routeur ne coûte ni plus ni autre chose qu'une machine. Le noyau i386 redeviendrait alors ce
que la documentation dit qu'il est : la rétro-compatibilité des vieux couples et des `.mar`
antérieurs à 2026.

**Pourquoi *amorcer* et non planifier tout de suite.** Le chemin n'est pas connu — plusieurs
décisions se tiennent l'une l'autre, ce qui est exactement le critère du skill `chantier-amorce`.

**Ce que l'implémentation devra affronter.**

* **Quagga est mort, l'image récente porte FRR.** `bin/router.ml` **écrit la configuration Quagga**
  et code le chemin en dur : `/etc/quagga/%s` (`:395`, avec les `zebra.conf`, `ripd.conf`,
  `ospfd.conf`… et le `password zebra` du gabarit, `:100-140`). Or l'arbre de construction trixie
  contient déjà **`frr`** (`uml/pupisto.debian/_build…/debianroot/usr/share/doc/frr/`), dont la
  disposition diffère (`/etc/frr/`, fichier `daemons`, vtysh intégré). Le fichier porte d'ailleurs
  déjà la trace du défaut : `:1524`, *« Example "/etc/quagga/zebra.conf" => TODO: LEGGERE NEI
  PARAMETRI DELLA MV!! »* — le chemin devrait venir des paramètres de la machine, pas du code.
  C'est **la** décision d'amorce : porter le générateur vers FRR, ou faire dire à l'image où sa
  configuration se pose (et le générateur s'y adapter), ou les deux.
* **La mémoire.** guignol demande 24 Mio (`MEMORY_SUGGESTED_SIZE`), trixie 192. Un TP à huit
  routeurs passerait de ~200 Mio à ~1,5 Gio. Une image de routeur **taillée** (pas une trixie
  complète) est probablement ce qu'il faut, ce qui rouvre le choix de la base — donc du chantier
  `marionnet-kernel-rootfs` (`uml/pupisto.debian/`), avec lequel celui-ci devra se coordonner.
* **La forme publiée.** Un artefact `router-*` est un **lien** vers l'image *machine* d'un autre
  tarball (invariant des ép. 13 et 16 de `modernisation-installation-marionnet`) : la nouvelle
  image devra suivre cette forme, ou la changer sciemment — et le paquet `marionnet-fs-*`
  correspondant devra être découpé en conséquence.
* **La rétro-compatibilité.** Les `.mar` existants nomment `router-guignol-18474` ; le remap
  d'import (`remap_absent_distrib_at_import`, ép. 4 de `marionnet-retro-compat-kernels-images`)
  existe déjà et devra être étendu, sans quoi les TP déjà écrits changeraient de routeur en
  silence.
* **La documentation suit, elle ne précède pas.** Les 4 pages d'installation
  (`doc-src/INSTALL{,.FR}.md`, `doc-src/INSTALL-quick-guide{,.FR}.md`) disent aujourd'hui qu'un
  routeur coûte deux paquets et annoncent cette image comme **prévue** : la clôture du chantier
  devra les corriger, ainsi que le `.html` publié.
