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
| 2 | **est-ce une application X ?** | `libX11` **atteint transitivement** depuis le fichier (§ 3.5), **plus un saut** à travers le wrapper (cf. § 3.3) | oriente vers 3 ou 4 |
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

### 3.5 Le faux négatif indirect — tranché à l'épisode 2 par une fermeture mesurée

**Le défaut.** `wireshark` était classé non-X : il n'a pas `libX11` en dépendance directe (il
passe par Qt), et le classificateur lit le fichier. Son verdict `OK` (par `--help`) restait
vrai, mais **la grosse application graphique de l'image n'avait jamais été éprouvée à
l'écran** — jugée par une sonde faite pour des outils en ligne de commande. Et il n'était pas
seul : `geany` (GTK) était dans le même cas.

**Les deux issues évidentes étaient fermées**, et le restent : élargir le motif à
`libgtk`/`libQt` serait écrire la liste blanche que ce chantier refuse (§ 3.2) — elle se
périme le jour où une toolkit apparaît — et `ldd` transitif est **mesuré trop lent** (§ 3.3 c).

**Ce qui a été fait à la place** : la fermeture transitive est calculée **dans l'image
elle-même**, avec `libX11` pour **unique graine** — qui n'est pas une liste, mais la
*définition* d'« application X ». Une bibliothèque atteint X si elle mentionne une
bibliothèque qui atteint X ; un binaire est X s'il mentionne une telle bibliothèque. **Qt et
GTK ne sont nommés nulle part : ils sont découverts.** Et le prix que `ldd` ne pouvait pas
payer est payé **une seule fois** : une bibliothèque est lue une fois pour **tout le run**
(mémoïsation), pas une fois par binaire.

**Mesuré avant d'être écrit** (`debugfs` sur l'image publiée, **sans booter**) :
`/usr/bin/wireshark` est un wrapper Marionnet → `wireshark.real`, qui ne mentionne **aucun**
`libX11` mais nomme `libQt6Gui.so.6`, laquelle porte `libX11.so.6` en **`DT_NEEDED`**
(`readelf`, donc une dépendance réelle et pas une chaîne littérale). La chaîne existait ; le
classificateur devait savoir la parcourir.

**Ce que la sur-approximation coûte, et pourquoi elle est du bon côté** : on lit les
*mentions* d'un fichier, ce qui est un sur-ensemble de ses `DT_NEEDED` (une chaîne littérale
compte). Un binaire ainsi classé X à tort n'est qu'éprouvé à l'écran, où il répond aussitôt —
là où l'erreur inverse (le faux négatif) fait passer une application graphique **sans être
jugée du tout**. C'est aussi ce qui capte ce qu'un `ldd` transitif aurait manqué : une
bibliothèque chargée par `dlopen` dont le nom est écrit dans le fichier.

**Le rapport dit sur quoi il a classé.** Une colonne `via` porte ce qui a décidé —
`libX11`, `wireshark.real:libQt6Gui.so.6`, `links2:libX11` — parce qu'une classification qu'un
humain ne peut pas contester n'est pas une mesure.

**Limite du même ordre, elle toujours ouverte** : **`links2` est lancé sans `-g`**, donc en
mode texte, et échoue sur `Epoll ADD(1) on fd 0` — c'est le `</dev/null` de la sonde, pas le
binaire. Un binaire dont le mode par défaut n'est pas graphique n'est pas jugeable par
« survit-il à l'écran ? ».

### 3.6 Le tamis laissait passer les cassés — mesuré à l'épisode 3

La passe de décision ne s'est pas contentée des 177 cas que le rapport lui tendait : elle a
relu **les 1820 `OK`**. Elle y a trouvé **33 binaires qui ne démarrent pas du tout**.

**Pourquoi le verdict les avait manqués** : `OK` accepte `rc` 0 **ou** 1, parce que quantité
d'outils impriment leur usage et sortent avec 1. Or un lanceur `qtchooser` qui ne trouve pas
sa cible sort **aussi** avec 1. Le `rc` ne porte pas la différence entre *« j'ai répondu »* et
*« je n'ai pas démarré »* — le **message**, lui, la porte, et il était déjà dans le rapport.

**Trois familles, et rien d'autre de deviné** (motifs relevés sur le rapport, pas imaginés) :

| famille | n | ce que le message dit |
|---|---|---|
| lanceur `qtchooser` | 32 | `could not exec '/usr/lib/qt5/bin/…'` — l'image porte Qt6, et 32 noms (`qmake`, `designer`, `linguist`, `lrelease`, `qml*`…) sont des liens vers `qtchooser`, dont le `.conf` Qt5 désigne un répertoire absent |
| module Perl absent | 9 | `Can't locate …pm in @INC` |
| bibliothèque absente | 1 | `error while loading shared libraries` |

D'où un **verdict de plus, `BROKEN`**, lu sur le message et jamais sur le `rc`, et posé **avant**
l'échelle : un binaire qui ne démarre pas ne démarrera pas mieux à la seconde question, si bien
que le repli `--version` ne lui est même plus posé. **Éprouvé sans booter**, en rejouant
`is_broken` sur les deux rapports : **42 reconnus sur 42**, **0 faux positif sur 2060 lignes**.

**Et un second défaut de la même famille** — *juger par autre chose que ce qu'on mesure* :
**26 des cas** arrivaient à la décision avec un **message vide**, parce que la sonde ne gardait
que `stderr` et qu'un bon nombre d'outils écrivent leur usage sur **stdout** avant de sortir
avec un statut non nul. Le rapport tendait donc à l'agent des cas *sans rien à juger*. La sonde
prend désormais `stderr`, **puis stdout à défaut**, en **disant lequel** (`stdout: …`) — un
message pris en silence dans l'autre flux ne décrirait rien. C'est le même argument que la
colonne `via` de l'épisode 2 : *une classification qu'un humain ne peut pas contester n'est pas
une mesure*.

## 4. La politique — le seul fichier que l'agent écrit

`uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.trixie.tsv` — un TSV versionné, **là
où vivent déjà les ressources par distribution** (`package_catalog/*.trixie.*`,
`binary_list.<image>`), parce que c'est `pupisto` qui le lira à la construction (étage 3b).

```
# name    verdict  action                     reason                                    family
qmake     drop     apt-get -y purge qtchooser qtchooser wrapper: execs /usr/lib/qt5/…    qt5-wrapper
snmpcheck fix      apt-get -y install perl-tk network tool, in scope; Tk.pm absent       missing-perl-module
ping      ignore   -                          works: knows neither --help nor --version  no-help-option
```

**Elle ne porte que des exceptions.** `keep` est le défaut, et ne s'écrit pas : **210 lignes**
couvrent un catalogue de **2060** candidats. Écrire une ligne pour chacun des 1820 qui ont
répondu simplement serait la liste blanche que ce chantier refuse (§ 3.2).

**Une ligne par cas examiné, en revanche** — et pas seulement pour les cas actionnables. C'est
ce qui fait que la passe suivante **ne montre que ce qui est nouveau** : sans ces lignes, les
165 cas *« il fonctionne, la sonde ne sait pas le juger »* seraient re-jugés à chaque image, ce
que le gel devait précisément éviter. Le test de la destination — *la prochaine image ne rouvre
pas un chantier* — est à ce prix.

**Une cinquième colonne, `family`.** Elle est à ce fichier ce que `via` est au rapport : elle
dit **sur quoi** le verdict a été lu (`qt5-wrapper`, `no-help-option`, `needs-arguments`,
`no-stderr`, `needs-selinux`…), donc ce qu'un humain doit contester s'il n'est pas d'accord.
Les lignes sont groupées par famille pour cette relecture ; rien dans le format n'en dépend.

**Ce que la première politique contient** (épisode 3, 210 lignes) :

| verdict | n | quoi |
|---|---|---|
| `drop` | 32 | les lanceurs `qtchooser`, tous par la même action (`apt-get -y purge qtchooser`) |
| `fix` | 2 | `snmpcheck` et `snmp-bridge-mib` — outils réseau, donc **dans** le périmètre pédagogique, à qui il manque un module Perl |
| `ignore` | 176 | jugé une fois : le binaire fonctionne (il ne connaît pas `--help`, il réclame ses arguments), ou il est hors d'usage ici (SELinux absent, helper PAM, outil de packaging Debian), ou ce n'est pas un binaire |

Trois de ces `ignore` méritent d'être nommés : **`bin`, `sbin` et `X11` ne sont pas des
binaires** mais des **répertoires** que `BINARY_LIST` a ramassés — un défaut du générateur de
la liste, constaté ici et laissé là où il est.

**Ce que les deux `fix` disent d'eux-mêmes** : leur action **nomme un paquet candidat**
(`perl-tk`, `libsnmp-perl`) que rien n'a encore vérifié dans l'invité, et leur raison le dit.
C'est la re-sonde de l'étage 3 qui le confirmera ou l'infirmera — une action fausse s'y voit.

**L'agent ne fait qu'une chose** : lire le rapport + la politique courante et proposer un
**diff de politique** dont chaque ligne est adossée à une preuve du rapport. Il ne touche ni à
l'image ni aux scripts ; l'humain valide, ça se commite.

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

### 2026-09-04 — épisode 2 : la fermeture transitive, mesurée avant d'être écrite

L'étape était nette (§ 3.5) et elle est **soldée** : le classificateur atteint désormais
`libX11` **transitivement**, avec cette seule graine, en lisant l'image elle-même.

**Mesuré d'abord, et sans booter** (`debugfs`, lecture seule, sur l'image publiée) : la chaîne
`wireshark` → `wireshark.real` (zéro mention de `libX11`) → `libQt6Gui.so.6`, qui porte
`libX11.so.6` en **`DT_NEEDED`** (`readelf` : une dépendance réelle, pas une chaîne littérale).
Sans cette mesure, écrire la fermeture aurait été un pari — elle aurait pu très bien ne rien
relier, Qt cherchant son plugin `xcb` par répertoire et non par nom.

**Ce qui a été écrit** (`Makefile.d/filesystem.probe-image-binaries.sh`) :

- `lib_reaches_x`, **mémoïsée** (`LIB_VERDICT`) et protégée des cycles : une bibliothèque est
  lue **une fois pour tout le run**, ce qui est exactement le prix que `ldd` ne pouvait pas
  payer, lui qui forke le chargeur *par binaire* ;
- la résolution nom → fichier vient d'un **seul** `ldconfig -p` pour le run, avec repli sur les
  répertoires usuels ;
- une colonne **`via`** dans le rapport (6 colonnes désormais), qui dit **sur quoi** le
  classement a été prononcé — une classification qu'un humain ne peut pas contester n'est pas
  une mesure ;
- **`--only A,B,C`**, l'instrument de cet épisode : sans lui, éprouver un témoin coûtait les
  deux heures du catalogue. Il **sélectionne dans `BINARY_LIST`** et **refuse en nommant** un
  nom qui n'y est pas, avant tout boot : un témoin silencieusement écarté est pire qu'un refus.

**La discriminance, sur dix témoins** (`docs/probe-reports/…-2026-09-04-witnesses.tsv`, 35 s,
57 bibliothèques lues) — les deux seules lignes qui changent contre le rapport du 2026-09-03
sont exactement celles que l'épisode visait :

| binaire | avant | après | `via` |
|---|---|---|---|
| `wireshark` | `OK` (help) | **`X_ALIVE`** | `wireshark.real:libQt6Gui.so.6` |
| `geany` | `OK` (help) | **`X_ALIVE`** | `libgeany.so.0` |
| `xeyes`, `xlinks2`, `xmessage` | X | X (inchangé) | `libX11`, `links2:libX11`, `libX11` |
| `ls`, `grep`, `bash`, `python3`, `tar` | non-X | non-X (inchangé) | — |

`geany` n'était pas dans l'énoncé de l'étape : le faux négatif était **plus large** que le seul
cas connu, ce qui est l'argument contre la liste blanche, mesuré.

**Ce que la première forme a coûté, et pourquoi elle a été refaite.** Elle posait **deux
questions au fichier** — « mentionnes-tu `libX11` ? », puis « quelles bibliothèques
mentionnes-tu ? » — donc **deux lectures complètes** de chaque binaire non-X, c'est-à-dire de
presque tout le catalogue. Mesuré dans l'invité : **10,9 s par candidat** (8 → 19 en 120 s),
contre les **1,60 s** de l'épisode 1 (`elapsed=3287s` pour 2059 candidats, ligne `#END` de son
rapport `--x-only`). Le run a été arrêté et la question `libX11` se répond désormais **dans la
liste déjà extraite** : un fichier est lu **une fois**.

**Le coût amorti ne se mesure pas sur un préfixe**, et c'est un piège de mesure de la même
famille que ceux de l'épisode 1 : une bibliothèque est lue **une seule fois pour tout le run**,
donc les premiers candidats paient le remplissage du cache pour tous les autres. Un
`--limit 150` mesure la phase chère et rien d'autre. Le chiffre qui compte est l'`elapsed` d'un
run complet, à comparer aux **3287 s** de l'épisode 1 — mesure prise à part (§ 9, épisode 3).
Et le micro-banc local dit que l'instrument n'y est pour presque rien : `grep -o` + `sort -u`
coûte **1,6×** un `grep -q` sur le même fichier, pas cinq fois.

**Le run complet a tranché les deux questions** —
`docs/probe-reports/machine-debian-trixie-16341-2026-09-04-x2.tsv`, `--x-only`, **2060
candidats** :

- **le coût amorti** : `elapsed=5095s` contre les **3287 s** de l'épisode 1, soit **2,47 s par
  candidat contre 1,60** — **+55 %**, et non le facteur cinq que le préfixe laissait craindre.
  **497 bibliothèques** lues, chacune une seule fois, pour 2060 candidats : c'est exactement ce
  que la mémoïsation achète. Un passage reste de l'ordre de l'heure et demie ;
- **ce que la fermeture trouve** : **16 binaires** basculent *plain* → X, et **aucun** X de
  l'épisode 1 n'est perdu (X passe de 73 à 89). Ce sont `wireshark` sous ses **trois** noms (le
  lien, le wrapper, le `.real`), `geany`, `mtr`, `broadwayd`, `gtk-launch`,
  `gtk-builder-tool`, `gtk-encode-symbolic-svg`, `gtk-query-settings`, `hydra`,
  `hydra-wizard`, `dpl4hydra`, `listres`, `xmore`, `bmtoa` — GTK, Qt, Xaw et Xmu, **aucune de
  ces bibliothèques n'étant nommée nulle part dans le code**.

**Et ce que ça coûte à l'étage 2, mesuré**. Huit de ces seize sortent en `X_DIED` — mais leur
`stderr` les nomme pour ce qu'ils sont : `gtk-launch: missing application name`,
`bmtoa: unable to read bitmap from f…`. Ce sont des **outils en ligne de commande liés à une
toolkit**, que la sonde X éprouve sans leur donner ce qu'ils attendent. La sur-approximation
n'est donc pas gratuite : elle fait passer quelques cas de plus devant l'agent. C'est le côté
où il faut se tromper — un faux positif se lit et se classe `ignore` **une fois**, là où le
faux négatif laissait une application graphique sortir **sans aucun jugement**.

### 2026-09-04 — épisode 3 : la première politique, et ce que le tamis laissait passer

**Livrable** : `uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.trixie.tsv`, **210
lignes** de jugement gelé (§ 4) — et deux correctifs de la sonde que cette passe a rendus
obligatoires (§ 3.6).

**Aucun boot.** La décision s'est prise sur les deux rapports déjà versionnés, **fusionnés** :
celui du 09-03 (2060 candidats, ancien classificateur) et le `x2` du 09-04 (`--x-only`, 92
lignes, fermeture transitive), **le second faisant autorité sur ce qu'il a jugé** et le premier
sur le reste. La fusion est exacte parce que la fermeture est un **sur-ensemble** de l'ancien
classificateur : re-payer 1 h 25 de sonde n'aurait rien appris. Après fusion, les cas à juger
sont **177** et non 186 — la fermeture en avait reclassé 16.

**Ce que la passe a trouvé, et que personne n'avait demandé.** Elle a relu les 1820 `OK`, et y
a trouvé **33 binaires qui ne démarrent pas** (§ 3.6) : 32 lanceurs `qtchooser` vers un
`/usr/lib/qt5/bin` absent — `qmake`, `designer`, `linguist`, `lrelease`, `assistant`, tous les
`qml*` — plus `vimplate`. Le verdict `OK` les couvrait parce qu'il accepte `rc` 1, que le
lanceur cassé rend lui aussi. **Le `rc` ne portait pas la différence ; le message, oui, et il
était déjà dans le rapport.** D'où `BROKEN`, lu sur le message, posé avant l'échelle.

**Preuve, prise sans invité** : `is_broken` rejoué sur les deux rapports reconnaît **42
messages sur 42** et fait **0 faux positif sur 2060 lignes** ; `message` rend bien `stderr`,
puis `stdout: …` à défaut, puis rien. C'est la vérification que cet épisode pouvait produire —
la sonde corrigée ne sera exercée en vrai qu'au prochain passage.

**Deux questions de conception tranchées** (elles étaient au brouillard depuis l'ép. 0) :

- **où vit la politique** — dans `pupisto.debian.sh.files/`, avec les autres ressources par
  distribution, parce que c'est `pupisto` qui la lira ;
- **ce que la politique garde** — **une ligne par cas examiné**, `ignore` compris. Sans elles,
  les 165 cas *« il fonctionne, la sonde ne sait pas le juger »* seraient re-jugés à chaque
  image ; avec elles, la passe suivante ne montre **que ce qui est nouveau**. C'est le test de
  la destination, et il valait ses 165 lignes.

**Ce qui reste actionnable** est petit et c'est bon signe : **32 `drop`** par une seule action
(`apt-get -y purge qtchooser`), **2 `fix`** (`snmpcheck`, `snmp-bridge-mib` — outils réseau,
donc dans le périmètre), **176 `ignore`**. L'épisode 4 appliquera **un** cas de bout en bout ;
`qtchooser` est le candidat naturel — 32 binaires réparés d'un geste, et une re-sonde
discriminante immédiate.
