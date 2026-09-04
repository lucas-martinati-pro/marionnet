# Triage des binaires d'une image invitée — chantier `triage-binaires-image-invitee`

> Chantier **enfant** de `marionnet-kernel-rootfs` (qui possède la fabrication des images).
> Reprise : appliquer le skill `chantier-long` (MODE B).
> Historique : `git log --grep="triage-binaires-image-invitee"`.

## DESTINATION

**Une image invitée publiée ne contient que des binaires qui fonctionnent** — et le constat
se refait, sur n'importe quelle image, **sans rouvrir de chantier** : sonder, relire un diff
de décisions, appliquer.

Le chantier est terminé quand, tous ensemble : la chaîne tourne de bout en bout sur trixie
avec une **re-sonde verte** ; la **politique** porte un verdict pour *chaque* candidat de
`BINARY_LIST` ; `uml/pupisto.debian.sh` la consomme à la construction ; le **skill** et ce
document existent. Le test qui le prouve tient en une phrase :

> **la prochaine image ne doit pas rouvrir un chantier** — juste `make image-probe`, une
> passe d'agent sur le diff, `make image-apply`.

## 1. Le constat d'origine (2026-09-03)

Sur `machine-debian-trixie-16341`, des binaires installés ne fonctionnent pas. Mesuré par
l'auteur, dans un invité :

```
[0 root@m2 ~]$ xlinks2
X Error of failed request:  BadMatch (invalid parameter attributes)
  Major opcode of failed request:  1 (X_CreateWindow)
```

`xeyes` et `wireshark`, eux, marchent. Un binaire qui ne marche pas est installé pour rien —
mais **corriger** et **amaigrir** sont deux objectifs distincts (§ 6).

## 2. Les deux décisions fondatrices

Tranchées par l'auteur à l'ouverture, elles commandent toute la conception :

- **La correction vit aux deux endroits, depuis une source unique.** La *politique* (§ 4) est
  consommée **et** par le respin de l'image publiée **et** par le constructeur. Une décision
  écrite une fois vaut pour l'image d'aujourd'hui et pour celle de demain.
- **Le critère d'acceptation est « que ça marche ».** L'amaigrissement (retirer des *paquets*
  pour gagner de la place) est **hors périmètre** — § 6.

## 3. La conception : trois étages, une politique versionnée

Un script qui **observe**, un agent qui **décide une fois**, un script qui **applique** — et
les verdicts de l'agent sont **gelés dans un fichier**, jamais re-dérivés.

```
   BINARY_LIST (.conf)
        │
        ▼
  [1] sonde ─────────► rapport daté (preuve)        script, 0 token, rejouable
        │                    │
        │                    ▼
        │              [2] passe d'agent (Sonnet, UNE fois)
        │                    │
        │                    ▼
        └──────────►  POLITIQUE versionnée  ◄── relue et validée par l'humain
                             │
                 ┌───────────┴───────────┐
                 ▼                       ▼
        [3a] respin de l'image    [3b] pupisto (construction)
```

**Pourquoi le gel.** Sans lui, chaque passage coûterait des tokens **et pourrait décider
autrement** : l'inverse d'« explicite, scriptable, versionné », et la faute que ce dépôt a
déjà payée plusieurs fois (une seule source de vérité). *L'agent est entre la sonde et la
politique, jamais dans la boucle.*

**Pourquoi pas `/loop`.** Chaque itération paierait un cycle de démarrage complet. Ce qu'on
veut est **un boot, toutes les sondes**.

### 3.1 Ce qui existe déjà et qu'on ne réinvente pas

- `Makefile.d/filesystem.update-published-image.sh` expose **`--in-guest 'CMD'`** (qui passe
  par `exec m1 …` du canal de contrôle, `:279`) et **`--in-guest-script FICHIER`** (déposé
  dans le hostfs via `rc-get m1`, `:302-305`). Il sait déjà booter, jouer, arrêter
  proprement, exporter la variante et publier — avec les six pièges de l'ép. 21 bis de
  `marionnet-kernel-rootfs` déjà codés.
- `cmd_exec` (`bin/control_server.ml:3290`) porte déjà un **`command_timeout`**.
- Les invités ont **`DISPLAY=172.23.0.254:<n>.<screen>`** et un cookie xauth
  (`bin/x.ml:212-250`).

### 3.2 L'étage 1 — la sonde

`Makefile.d/filesystem.probe-image-binaries.sh`, même famille et même forme d'options
(`--image`, `--from`) que ses frères. **Elle ne publie RIEN** : elle travaille dans un COW
jetable qu'elle détruit. Le nom d'une image *est* son `sum` (ép. 23) — sonder ne doit
produire aucune image.

L'échelle de sonde est **déterministe : aucun jugement, que des mesures**.

| # | Question | Mesure | Verdict |
|---|---|---|---|
| 1 | le binaire est-il là ? | `command -v` | absent ⇒ `MISSING` |
| 2 | **est-ce une application X ?** | `grep -a libX11` sur le fichier, **puis un saut** à travers le wrapper (cf. § 3.3) | oriente vers 3 ou 4 |
| 3 | non-X : répond-elle ? | `--help` puis, en repli, `--version`, sous timeout | rc + `stderr` |
| 4 | X : survit-elle à l'écran ? | lancement avec `DISPLAY`, timeout court | vivante ⇒ `X_ALIVE` ; morte + `stderr` ⇒ `X_DIED` |

**À ne pas défaire** : « est-ce une application X ? » se **mesure**, jamais ne se lit dans une
liste écrite à la main — leçon de l'ép. 39 de `modernisation-installation-marionnet` (*une
liste blanche se périme ; on mesure*). Le § 3.3 dit **pourquoi la mesure n'est pas `ldd`** :
l'esprit de la règle tient, l'instrument a changé. Et la sonde enregistre **le texte de
l'erreur**, pas un booléen : c'est lui qui porte la décision de l'étage 2.

### 3.3 Ce que l'épisode 1 a mesuré, et qui a redessiné l'étage 1

Quatre mesures, prises sur `machine-debian-trixie-16341`, chacune contredisant quelque chose
que l'épisode 0 supposait. Elles sont la raison d'être de la forme actuelle du script.

**(a) Le crux : `exec` ne donne pas de `DISPLAY`, et il n'en a pas besoin.** L'environnement
d'un `exec m1 …` est **nu** — `PATH`, et pas même `HOME` : le guetteur tourne sous une unité
systemd sans `Environment=` (`bin/scripts/marionnet-relay.zz-journal.sh`). Mais le relais a
écrit `export DISPLAY=:0` et `export XAUTHORITY=/etc/X11/Xauthority` dans `/etc/profile`
(`uml/guest/marionnet-relay`), qu'un shell non interactif ne lit pas. Un `. /etc/profile` en
tête suffit donc, et `xdpyinfo` répond ensuite. **Conséquence** : le dépôt par
`--in-guest-script` n'est **pas** nécessaire pour l'écran — il l'est pour le volume (c).

**(b) Le symptôme fondateur ne se reproduit pas sur cette plateforme.** `xlinks2` ne rend
**aucun** `BadMatch` ici, ni sans terminal ni sous `script` : il vit jusqu'au `timeout`. Le
serveur X de cette machine (X.Org 21.1.11) annonce sept profondeurs ; celui de la salle,
non. La réserve du § 8 est donc **confirmée par la mesure** : ce que le chantier a pris pour
un défaut de l'image est un désaccord avec le **relais X de l'hôte**, ce que le § 6 déclare
hors périmètre. **Conséquence de conception, à ne pas défaire** : *un verdict X n'est pas une
propriété de l'image seule*, mais du couple (image, serveur X) — d'où l'en-tête du rapport,
qui **enregistre le serveur** contre lequel il a été pris. Deux rapports qui divergent ne sont
pas nécessairement deux images qui divergent.

**(c) `ldd` est faux *et* trop lent.** Faux : `/usr/bin/xlinks2` est un `#!/bin/sh` qui fait
`exec links2 -g "$@"` — `ldd` n'y voit aucun `libX11`, qui est porté par `links2` ; et
**417 des 2057 candidats ne sont pas des ELF**. Le binaire même pour lequel le chantier a été
ouvert était donc classé *non-X* par le classificateur de l'épisode 0. Trop lent : `ldd` forke
le chargeur dynamique par binaire et **n'a pas fini le catalogue en 300 s**. D'où la mesure
actuelle : `grep -a libX11` **sur le fichier** (une lecture, pas un `exec`), plus **un seul
saut** à travers le wrapper — un script est une application X quand ce qu'il lance en est
une. Un saut et pas un point fixe : c'est ce que le cas mesuré demande, au-delà on écrit un
analyseur de shell.

**(d) Le canal ne peut pas porter la boucle.** Un aller-retour `exec` coûte ~1 s ; 2061 en
feraient ~35 min d'attente pour une boucle que l'invité joue en une fraction de seconde. D'où
**un seul script**, déposé dans le hostfs et lancé en arrière-plan, et **un rapport que l'hôte
regarde grandir** dans le répertoire partagé. Ce qui donne le quatrième invariant : le rapport
est écrit **ligne à ligne**, si bien qu'un binaire qui tue l'invité (`reboot`, `halt`) est
**nommé par la dernière ligne écrite** au lieu d'être deviné après avoir tout perdu.

**Et ce qui rend la sonde sûre** n'est pas une liste de binaires dangereux — elle se périmerait
— mais le fait qu'elle travaille **dans un COW jetable** : un `--help` qui se révèle être un
`mkfs` écrit dans une image que personne ne garde.

**Sortie** : un rapport TSV daté et **versionné** (c'est une preuve) —
`binaire · verdict · rc · sonde employée · première ligne de stderr`, précédé des
**conditions de la mesure** (image, `sum`, nombre de candidats, délais, **serveur X**).

### 3.4 Le premier rapport, et ce qu'il a corrigé dans la sonde

`docs/probe-reports/machine-debian-trixie-16341-2026-09-03.tsv` — **2060 candidats, un seul
boot** :

| verdict | n | ce que ça veut dire |
|---|---|---|
| `OK` | 1834 | a répondu à `--help` (ou, en repli, à `--version`) avec 0 ou 1 |
| `ERR` | 142 | a répondu autre chose |
| `X_ALIVE` | 40 | application X toujours vivante au bout du délai : elle a ouvert sa fenêtre |
| `X_DIED` | 33 | application X partie avant le délai |
| `TIMEOUT` | 8 | n'a pas rendu la main à `--help` |
| `MISSING` | 3 | annoncée par `BINARY_LIST`, absente du `PATH` |

**Ce que ces chiffres valident** : l'étage 2 ne voit que **186 cas sur 2060** (9 %) — la
décision fondatrice « l'agent ne voit que les échecs, jamais le catalogue » est chiffrée, et
ce ratio ne dépend pas du nombre d'entrées.

**Ce qu'un passage coûte** : ~3,7 s par candidat, soit **environ deux heures** pour le
catalogue, dans un seul boot. Et ce coût est celui de la **classification**, pas des sondes —
mesuré : un run `--x-only`, qui n'exécute que 73 binaires, avance à la même vitesse, parce
qu'il classe quand même les 2060. L'option sert donc à **ne pas exécuter** deux mille
binaires, pas à aller plus vite.

**Ce qu'ils ont corrigé, une fois lus** — deux défauts de la sonde, tous deux du genre *juger
par autre chose que ce qu'on mesure*, la famille que ce dépôt collectionne :

1. **`X_DIED` avec `rc` 0 n'est pas une mort.** **Quinze** des trente-trois étaient `xdpyinfo`,
   `xlsfonts`, `xauth`, `appres`, `xvinfo`, `setxkbmap`, `xclip`, `see`, `open`… — des outils X
   **en ligne de commande** qui ont fait leur travail et sont partis avec 0. Le verdict aurait
   donné quinze échecs imaginaires à juger. Trois issues désormais, et non deux : `X_ALIVE`
   (le délai), `X_OK` (**rc 0**), `X_DIED` (le reste).
2. **Le garde-fou de progression comptait les lignes écrites.** Sous `--x-only`, la sonde
   n'écrit rien pour les deux mille candidats qu'elle saute : l'hôte a lu ce silence comme un
   blocage et **a arrêté une sonde qui marchait**, après six lignes sur soixante-treize. Le
   guest compte donc les **candidats** (`probe-progress`), et c'est ce compteur que l'hôte
   surveille.

**Ce qu'ils ont prouvé, aussi** : `tgz` a écrit une archive nommée `--help.tgz`, et
`unix_chkpwd`, `unix_update`, `pwhistory_helper` répondent *« This binary is not designed for
running in this way »*. Une sonde `--help` **fait agir** certains binaires. La garde n'est pas
une liste de dangereux — elle se périmerait — c'est le **COW jetable**.

### 3.5 Une limite mesurée, laissée ouverte : le faux négatif indirect

**`wireshark` est classé non-X** : il n'a pas `libX11` en dépendance directe (il passe par Qt),
et le classificateur lit le fichier. Son verdict `OK` (par `--help`) reste vrai, mais il n'a
pas été éprouvé **à l'écran** — or c'est la grosse application graphique de l'image.

Les deux issues évidentes sont fermées : élargir le motif à `libgtk`/`libQt` serait écrire la
liste blanche que ce chantier refuse (§ 3.2), et `ldd` transitif est **mesuré trop lent**
(§ 3.3 c). La question est nette, elle est donc une **prochaine étape**, pas une improvisation.

Deuxième limite du même ordre : **`links2` est lancé sans `-g`**, donc en mode texte, et
échoue sur `Epoll ADD(1) on fd 0` — c'est le `</dev/null` de la sonde, pas le binaire. Un
binaire dont le mode par défaut n'est pas graphique n'est pas jugeable par « survit-il à
l'écran ? ».

## 4. La politique — le seul fichier que l'agent écrit

Un TSV versionné, à côté des ressources de la distribution. Quatre verdicts, et c'est tout :

```
# binaire       verdict  action                          raison
xlinks2         drop     apt-get -y purge links2         BadMatch X_CreateWindow, non corrigeable (ép. N)
marionnet-relay ignore   -                               interne à Marionnet, pas destiné à l'utilisateur
wireshark       keep     -                               sondé OK le 2026-09-03
<autre>         fix      <commande jouée dans l'invité>  <pourquoi>
```

`ignore` porte le **discernement** de l'énoncé d'origine (« `marionnet-relay` n'a aucun
intérêt pour l'utilisateur ») — écrit **une fois, avec sa raison**, au lieu d'être re-jugé à
chaque passage.

**L'agent (Sonnet) ne fait qu'une chose** : lire le rapport + la politique courante et
proposer un **diff de politique** dont chaque ligne est adossée à une preuve du rapport. Il
ne touche ni à l'image ni aux scripts ; l'humain valide, ça se commite.

## 5. L'étage 3 — appliquer, aux deux endroits

- **3a, l'image publiée** : la politique se traduit mécaniquement en `--in-guest` passés à
  `filesystem.update-published-image.sh` (`fix` → sa commande, `drop` → son `apt-get purge`).
- **3b, le constructeur** : `uml/pupisto.debian.sh` lit **le même fichier** à la construction.

## 6. HORS PÉRIMÈTRE (écarté consciemment, avec le pourquoi)

- **L'amaigrissement de l'image.** Supprimer un *binaire* ne libère presque rien : ce qui
  pèse, c'est le paquet et ses bibliothèques, souvent partagées. Viser la place, c'est viser
  des *paquets*, avec un risque de casse tout autre. Décision de l'auteur : *« que ça
  marche » d'abord* ; l'amaigrissement sera un **autre chantier**, s'il est voulu.
- **Corriger le relais X lui-même.** Si un binaire échoue parce que le relais n'offre pas le
  *visual* demandé, la question devient celle du relais (`bin/x.ml`), pas celle de l'image.
  Ce chantier le **constatera et le nommera** ; il ne le réparera pas.
- **Les autres images** (wheezy, guignol). La mécanique sera générique, mais la politique est
  **par distribution** : trixie d'abord, les autres seulement si l'auteur le demande.

## 7. Le livrable, une fois le chantier clos

> Question posée à l'ouverture : *« un skill qui coordonne tous les helpers ? »* —
> **oui à un skill, non à « qui coordonne »**.

L'ép. 26 de `modernisation-installation-marionnet` a **refusé** un script de regroupement
pour la chaîne de release : *la chaîne est linéaire, chaque maillon est déjà une cible, elle
n'a aucune connaissance propre — un script n'ajouterait qu'un endroit où l'ordre peut
diverger.* Le même raisonnement vaut ici, **sauf sur un point** : notre chaîne a **une
décision au milieu**. Le livrable se sépare donc exactement là où la chaîne se sépare :

| Ce qui reste | Forme | Pourquoi cette forme |
|---|---|---|
| **La politique** | TSV versionné | *Le plus précieux* : le jugement accumulé, sans quoi il serait re-dérivé (ou re-payé en tokens) à chaque image |
| **La mécanique** | **2 cibles `make`** : `image-probe`, `image-apply` | Maillons linéaires et sans connaissance propre ⇒ pas de script de regroupement (ép. 26) |
| **Le jugement + le rituel** | **1 skill** | La seule part qu'une cible `make` ne peut pas porter |
| **L'archive** | ce document + la fiche mémoire | Convention des chantiers du dépôt |

**Ce que le skill contient — et ne contient pas.** Il porte (1) la *passe de décision* ;
(2) le *rituel* et les interdits durables : **une sonde ne publie jamais**, **un verdict gelé
ne se re-dérive pas**, **`ldd` répond à « est-ce une application X ? »**, et **republier une
image, c'est la renommer**. Il ne recopie ni la grammaire des scripts ni la politique : il
**renvoie ici**, comme les autres skills du dépôt.

## 8. Réserves établies à l'ouverture

- **`xlinks2` n'est probablement pas « cassé »** : `BadMatch` sur `X_CreateWindow` est la
  signature d'un désaccord **visual/profondeur** avec le relais X — `xeyes` marche parce
  qu'il ne demande rien de particulier. Le remède peut être une option, pas une suppression.
  C'est l'étage 2 qui tranchera, **sur la preuve**.
- **Republier une image, c'est la renommer** : son nom est son `sum`, et le `mtime` du
  *backing file* fait foi (ép. 23). Chaque tour d'application produit une image **neuve**.

## 9. Journal d'avancement

### 2026-09-03 — épisode 0 : la stratégie, et ce que le chantier laissera derrière lui

Ouverture. Aucun boot, aucun script : le livrable est une **conception** et un **format**.
Acquis de l'épisode :

- les **deux décisions fondatrices** (§ 2), tranchées par l'auteur ;
- la **conception à trois étages** (§ 3) et, avec elle, le refus argumenté de deux fausses
  bonnes idées : le *jugement dans la boucle* (un agent qui re-décide à chaque passage) et
  **`/loop`** (un boot par itération) ;
- l'**échelle de sonde déterministe** (§ 3.2), dont le point dur : *est-ce une application
  X ?* se **mesure** (`ldd`), ne se liste pas ;
- le **format de la politique** (§ 4) et ses quatre verdicts ;
- le **hors périmètre** (§ 6), consigné pendant qu'il est frais ;
- le **livrable de clôture** (§ 7) : `make` pour la mécanique, un **skill** pour le jugement
  et le rituel — pas un skill coordinateur.

**Vérifié avant de concevoir** (et non supposé) : les deux modes d'exécution dans l'invité
du script de pilotage, le `command_timeout` déjà présent dans `cmd_exec`, et la forme du
`DISPLAY` des invités (§ 3.1).

**Prérequis pour l'épisode 1** : le chemin du **répertoire de release** (l'option `--from`),
sans lequel `BINARY_LIST` n'est pas lisible et l'ampleur pas chiffrable.

**Le crux de l'épisode 1**, à mesurer avant d'écrire la sonde : `exec m1 …` donne-t-il un
`DISPLAY` utilisable dans l'invité ? Si non, la sonde des applications X doit passer par
`--in-guest-script` (hostfs) en posant `DISPLAY` elle-même.

### 2026-09-03/04 — épisode 1 : la sonde, et quatre suppositions démenties par la mesure

Le crux a été mesuré **avant** d'écrire une ligne (§ 3.3 a) : `exec` livre un environnement nu,
mais `/etc/profile` porte le `DISPLAY` que le relais y a écrit, et un `.` suffit.

Livrable : **`Makefile.d/filesystem.probe-image-binaries.sh`**, sixième de la famille et,
comme ses cinq frères, sans rien de sourcé. Il boote l'image dans un COW jetable, dépose une
sonde dans le hostfs, la lance en arrière-plan et **regarde le rapport grandir** ; il
n'exporte aucune variante et **ne publie rien**.

Premier rapport réel : `docs/probe-reports/machine-debian-trixie-16341-2026-09-03.tsv`,
**2060 candidats en un seul boot** (§ 3.4).

Ce que l'épisode a **démenti** de la conception d'ouverture, chaque fois par une mesure :

1. le classificateur `ldd` était **faux** (`xlinks2`, le binaire du constat d'origine, est un
   `#!/bin/sh` — donc classé *non-X* ; et 417 des 2057 candidats ne sont pas des ELF) **et
   trop lent** (catalogue non fini en 300 s) ;
2. la boucle ne peut pas passer par le canal (~1 s l'aller-retour, ~35 min de pure attente) ;
3. **le symptôme fondateur ne se reproduit pas ici** — `xlinks2` est `X_ALIVE` sur cette
   plateforme. La réserve du § 8 est confirmée : c'est le serveur X de l'hôte, ce que le § 6
   met hors périmètre. D'où l'invariant neuf : *un verdict X est une propriété du couple
   (image, serveur X)*, et le rapport enregistre le serveur ;
4. deux défauts de la sonde elle-même, trouvés **en lisant son propre rapport** : `X_DIED`
   avec `rc` 0 (quinze morts imaginaires) et un garde-fou qui comptait les lignes écrites au
   lieu des candidats traités (il a arrêté une sonde qui marchait).

**La preuve des deux correctifs**, prise en rejouant `--x-only` —
`docs/probe-reports/machine-debian-trixie-16341-2026-09-04-x.tsv` : **15 bascules
`X_DIED` → `X_OK`** (les seules lignes qui changent entre les deux rapports), et un run qui
traverse **2059 candidats** là où le précédent s'arrêtait à **6**. Le rapport X final :
`X_ALIVE` 40, `X_DIED` 18, `X_OK` 15, `MISSING` 3.

**Reste ouvert, et nettement formulé** (§ 3.5) : le faux négatif du classificateur sur les
applications qui lient X **indirectement** (`wireshark` via Qt), les deux issues évidentes
étant fermées — une liste se périme, `ldd` transitif est trop lent.
