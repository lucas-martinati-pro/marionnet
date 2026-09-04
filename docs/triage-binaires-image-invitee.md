# Triage des binaires d'une image invitée — chantier `triage-binaires-image-invitee`

> Chantier **enfant** de `marionnet-kernel-rootfs` (qui possède la fabrication des images).
> Reprise : appliquer le skill `chantier-long` (MODE B).
> Historique : `git log --grep="triage-binaires-image-invitee"`.

## DESTINATION

*(Reformulée à l'épisode 7 — la formulation d'origine est juste en dessous, avec ce qui l'a
fait bouger.)*

**Toute image invitée CONSTRUITE désormais ne contient que des binaires qui fonctionnent** — et
le constat se refait, sur n'importe quelle image, **sans rouvrir de chantier** : sonder, relire
un diff de décisions, appliquer.

Le chantier est terminé quand, tous ensemble : la chaîne tourne de bout en bout sur trixie avec
une **re-sonde verte** ; la **politique** porte un verdict pour *chaque* candidat de
`BINARY_LIST` ; `uml/pupisto.debian.sh` la consomme à la construction ; le **skill** et ce
document existent. Le test qui le prouve tient en une phrase :

> **la prochaine image ne doit pas rouvrir un chantier** — juste
> `make filesystem.probe-image-binaries`, une passe d'agent sur le diff,
> `make filesystem.apply-binary-policy`.

### Le critère de reprise d'une image DÉJÀ publiée (épisode 7)

La formulation d'origine disait *« une image invitée **publiée** ne contient que des binaires qui
fonctionnent »*. Elle promettait donc de reprendre l'existant, et l'épisode 6 a mis le prix de
cette promesse sur la table : reconstruire `machine-debian-trixie-16341` pour ses 47 lanceurs Qt5
morts, c'est recompresser 5,4 Go, republier **sous un nouveau nom** (le nom *est* le `sum`),
réécrire `SHA256SUMS` et redéposer — pour 8301 ko et des binaires (`qmake`, `designer`, `qml*`)
qu'aucun énoncé de TP réseau ne traverse. Décision de l'auteur : **on laisse 16341 en l'état**.

Pour que cette décision ne se re-tranche pas à chaque politique, elle s'écrit comme un critère,
et il porte sur l'**usage**, pas sur la taille :

> **On ne reconstruit pas une image publiée pour des binaires dont l'échec ne bloque aucun geste
> pédagogique. On la reconstruit quand un binaire du périmètre du TP est cassé.**

Conséquences à ne pas perdre de vue :

- l'**étage 3a** (`filesystem.apply-binary-policy.sh`) n'aura donc jamais tourné **jusqu'à
  l'export**. Il est éprouvé en `--dry-run`, en `--print-actions` et en `--measure` — pas au
  bout. Ce n'est pas un outil mort : c'est celui du jour où un défaut, lui, vaudra la reprise.
  Mais la chaîne « verte de bout en bout » que la destination promet sera démontrée par
  **`pupisto`** (étage 3b, à la construction), et la clôture doit le dire ainsi — sans quoi on
  croira avoir prouvé ce qu'on n'a pas prouvé ;
- le critère ne donne **pas** la même réponse pour les deux `fix` restants : `snmpcheck` et
  `snmp-bridge-mib` sont des outils **réseau**, en plein périmètre. La question se repose pour
  eux à l'épisode 8, une fois les noms de paquets confirmés ;
- l'image en ligne et la politique **divergent volontairement** : la politique décrit désormais
  un état *voulu*, pas l'état de 16341. Une re-sonde de 16341 y retrouvera les 47 — ce n'est pas
  une nouveauté, c'est cette décision.

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

### 3.7 L'action de la politique était fausse, et l'invité l'a dit — épisode 4

La politique de l'ép. 3 réparait ses 32 lanceurs `qtchooser` par **une** action collective,
`apt-get -y purge qtchooser`. Elle a été écrite **sans booter**, sur les rapports ; l'épisode 4
est allé la mesurer **dans l'invité**, avant de l'appliquer. Trois faits, aucun supposé.

**1. La purge emporte ce qui marche.** `apt-get -s -y purge qtchooser` répond qu'elle retirerait
**trois** paquets : `qtchooser`, `qtbase5-dev-tools` et `python3-pyqtgraph`. Or
`qtbase5-dev-tools` est précisément ce qui pose les **10 outils réels** de `/usr/lib/qt5/bin`
(`moc`, `rcc`, `uic`, `qlalr`, `qvkgen`, `qdbuscpp2xml`, `qdbusxml2cpp`, `tracegen`,
`syncqt.pl`, `fixqt4headers.pl`) — lus **sans booter**, par `debugfs` sur l'image publiée. Les
lanceurs qui pointent vers eux **fonctionnent** : la sonde les a mesurés à `rc` 0. L'action
réparait donc 32 noms cassés en supprimant **sept qui marchent**, plus une bibliothèque Python
qui n'avait rien demandé. C'est l'inverse du critère du chantier (*« que ça marche »*).

**2. La supposition sur les liens est démentie — dans l'autre sens.** On tablait sur des liens
que `dpkg` ne connaît pas ; `dpkg -L qtchooser` les **possède** tous. Le fait ne sauve pas
l'action pour autant : il dit seulement que le remède devait viser les **liens**, pas le paquet.
D'où l'action retenue, une par ligne : `rm -f /usr/bin/<nom>`. `qtchooser` reste installé, et
tout ce qui se résout encore continue de marcher.

**3. Le tamis de l'ép. 3 en avait manqué sept.** Les 32 étaient reconnus sur le message
`could not exec '/usr/lib/qt5/bin/<nom>'`. Sept autres lanceurs — `qdbus`, `qml`,
`qmlimportscanner`, `qmlscene`, `qtdiag`, `qtpaths`, `qtplugininfo` — sont cassés **pour la même
raison** mais `qtchooser` le leur dit **dans une autre phrase** :
`could not find a Qt installation of ''`. Ils étaient dans le rapport, classés `OK` avec `rc` 1,
et la relecture de l'ép. 3 ne les a pas vus. C'est **la même famille de défauts** que celle qui
avait produit `BROKEN` : *juger sur un motif plutôt que sur ce qu'on mesure* — un motif reconnaît
ce qu'il a été écrit pour reconnaître. La leçon n'est pas « écrire un meilleur motif » : c'est
que **la cause se vérifie par un chemin indépendant du message**. Ici la vérification tient en
une comparaison d'ensembles : *les 46 liens que `dpkg -L qtchooser` livre dans `/usr/bin`*,
moins *les 7 dont le contenu réel de `/usr/lib/qt5/bin` porte la cible* (les 3 autres outils de
ce répertoire n'ont pas de lien) = **39 pendants**, contre 32 retenus.

La politique passe donc de 210 à **217 lignes**, et l'action collective disparaît. Note assumée :
retirer un fichier que `dpkg` possède laisse le paquet « modifié » aux yeux de `dpkg -V`. C'est
acceptable pour une image livrée — elle est un artefact, pas un système administré — et ça l'est
d'autant plus que l'alternative propre (purger) est exactement ce qui casse le reste.

### 3.8 L'étage 3a existe, et le canal a corrigé sa traduction — épisode 5

L'épisode 4 avait laissé une action **relue mais jamais jouée**. La jouer demandait ce qui
n'existait pas encore : le **traducteur**, `Makefile.d/filesystem.apply-binary-policy.sh`. Il lit
la politique, en tire un `--in-guest` par ligne dont le verdict est joué, et appelle son frère
`filesystem.update-published-image.sh`. **Il ne décide rien** : chaque commande vient, mot pour
mot, de la colonne `action` d'une ligne du fichier.

**Ce qu'il refuse, plutôt que de le sauter.** Une ligne qui ne dit pas clairement quoi faire —
verdict inconnu, `drop`/`fix` sans action, action portée par une ligne dont le verdict n'en veut
pas, nombre de colonnes autre que 4, raison vide — fait échouer **tout le fichier**, en nommant
son numéro de ligne. Sauter une telle ligne avec un avertissement laisserait une action
**silencieusement non jouée**, ce qui est exactement la famille de défaut que ce chantier a déjà
payée deux fois. Les six refus ont été éprouvés (rc 2 chacun) sur des politiques jetables ; s'y
ajoutent le refus d'une image *router* et celui d'une distribution **sans politique** — la
politique est par distribution (§ 6), et appliquer les verdicts de trixie à une image wheezy
retirerait des noms que personne n'y a jamais sondés.

**Trois profondeurs, et une seule qui produit.** `--dry-run` imprime la ligne de commande et ne
boote rien ; `--measure` relaie le `--no-export` de l'épisode 4 (les commandes jouent, **rien**
n'est exporté) ; sans option, le run écrit une image neuve dans le répertoire de release.

**Le défaut que la mesure a trouvé, et qui n'était pas dans la politique.** Le premier run de
mesure a joué les 39 `rm -f` puis est **mort** sur la première vérification, avec ce message du
canal :

    no option --help here: exec takes only --timeout=<s>. An option meant for the command
    itself must come after a bare --, as in `exec m1 -- ls --all'

`exec` reconnaît une option **où qu'elle se trouve dans la ligne** et refuse celles qu'il ne
connaît pas — c'est délibéré (`bin/control_server.ml`, branche `exec` du dispatch : sans cela
`exec m1 ls --all` lancerait `ls` en avalant le `--all` **en silence**). La conséquence, elle, ne
l'était pas : **`filesystem.update-published-image.sh` construisait `exec m1 $1` sans séparateur**,
si bien qu'une commande `--in-guest` parfaitement ordinaire portant une option longue était
refusée, et le run tué sur une commande que l'invité n'a jamais vue. Le canal dit lui-même le
remède ; il n'y a aucune raison de le faire découvrir à chaque appelant. `run_in_guest` construit
désormais `exec m1 -- $1`. Rien ne change pour les commandes sans option : tout ce qui suit `--`
est rejoint en une *free tail*, celle-là même que le parseur assemblait déjà.

**Ce que l'invité a répondu**, une fois le séparateur en place (un boot, 39 retraits, 5
vérifications, **rien d'exporté**) :

| vérification | réponse mesurée |
|---|---|
| les 39 noms dans `/usr/bin` | **`still-there=0 of 39`** |
| les 7 lanceurs sains (`--help`) | tous **exécutent leur cible** : `Usage: /usr/lib/qt5/bin/moc …`, idem `rcc`, `uic`, `qlalr`, `qvkgen`, `qdbuscpp2xml`, `qdbusxml2cpp` |
| `/usr/lib/qt5/bin` | **10 outils**, intacts — donc `qtbase5-dev-tools` n'a pas bougé |
| entrées `/usr/bin` possédées par `qtchooser` et absentes | **39**, exactement les 39 retirées |

La dernière ligne **referme l'arithmétique de l'épisode 4** : `dpkg -L qtchooser` possède 46
entrées de `/usr/bin`, 39 sont les liens pendants qu'on retire, et les **7** qui restent sont
celles qui résolvent — les sept que la purge collective aurait emportées. Le geste ne touche donc
ni un paquet, ni un lien qui marche.

**Deux précisions d'honnêteté sur cette mesure.** `qvkgen` sort avec `rc` 1 en imprimant son
propre `Usage:` — il a **démarré**, et c'est le **message** qui le dit, jamais le `rc` (leçon de
l'épisode 3, appliquée ici à la lecture d'un résultat favorable). Et la vérification par
`dpkg-query -W -f=…` n'a **rien** rapporté : le `${binary:Package}` de son format est aussi de la
syntaxe bash, que le shell de l'invité a mangée avant `dpkg-query`. Ce n'est pas l'outil qui a
manqué, c'est la vérification qui était mal écrite ; l'inventaire de `/usr/lib/qt5/bin` répond de
toute façon à la même question.

**Rien n'a été appliqué.** L'épisode s'arrête sur la mesure : produire l'image neuve demande le
feu vert de l'auteur.

## 4. La politique — le seul fichier que l'agent écrit

`uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.trixie.tsv` — un TSV versionné, **là
où vivent déjà les ressources par distribution** (`package_catalog/*.trixie.*`,
`binary_list.<image>`), parce que c'est `pupisto` qui le lira à la construction (étage 3b).

```
# --- qt5-wrapper (47)          <- la famille est un EN-TÊTE DE GROUPE, pas une colonne
# name    verdict  action                                     reason
qmake     drop     apt-get -y purge python3-pyqtgraph …       dangling qtchooser wrapper: …
moc       drop     apt-get -y purge python3-pyqtgraph …       working wrapper, package without interest: …
# --- missing-perl-module (11)
snmpcheck fix      apt-get -y install perl-tk  network tool, in scope; Tk.pm absent
# --- no-help-option (…)
ping      ignore   -                     works: knows neither --help nor --version
```

**Un `drop` ne vise pas toujours le binaire** (épisode 6) : quand le paquet qui le porte n'a plus
d'intérêt une fois le binaire parti, l'action est le retrait du **paquet**, et une seule commande
répond alors pour tous les noms qu'il portait — 47 lignes de la famille `qt5-wrapper` pour un
`apt-get purge`. Chaque nom garde néanmoins **sa** ligne (la politique doit nommer tout ce qui
disparaît), et c'est l'applicateur qui joue une fois les actions strictement égales.

**Elle ne porte que des exceptions.** `keep` est le défaut, et ne s'écrit pas : **225 lignes**
couvrent un catalogue de **2060** candidats. Écrire une ligne pour chacun des 1820 qui ont
répondu simplement serait la liste blanche que ce chantier refuse (§ 3.2).

**Une ligne par cas examiné, en revanche** — et pas seulement pour les cas actionnables. C'est
ce qui fait que la passe suivante **ne montre que ce qui est nouveau** : sans ces lignes, les
165 cas *« il fonctionne, la sonde ne sait pas le juger »* seraient re-jugés à chaque image, ce
que le gel devait précisément éviter. Le test de la destination — *la prochaine image ne rouvre
pas un chantier* — est à ce prix.

**La famille est un en-tête de groupe, pas une colonne** (précisé à l'épisode 4 : l'en-tête du
fichier annonçait une 5ᵉ colonne que **pas une ligne ne portait** — les 210 lignes de l'ép. 3
en ont quatre). Elle est à ce fichier ce que `via` est au rapport : elle dit **sur quoi** le
verdict a été lu (`qt5-wrapper`, `no-help-option`, `needs-arguments`, `no-stderr`,
`needs-selinux`…), donc ce qu'un humain doit contester s'il n'est pas d'accord. Elle s'écrit
**une fois par groupe** parce que personne d'autre qu'un lecteur n'en a besoin : le
consommateur, lui, lit quatre champs.

**Ce que la politique contient** (épisode 3, corrigée aux épisodes 4, 6 et 8 — 225 lignes) :

| verdict | n | quoi |
|---|---|---|
| `drop` | 55 | 47 pour la chaîne `qtchooser`, qui part **par paquets nommés** (journal, épisode 6) ; 8 pour les binaires cassés dont le paquet, lui, garde son intérêt — un `rm -f /usr/bin/<nom>` chacun (journal, épisode 8) |
| `fix` | 2 | `snmpcheck` et `snmp-bridge-mib` — outils réseau, donc **dans** le périmètre pédagogique, à qui il manque un module Perl ; leurs paquets sont **vérifiés** depuis l'épisode 8 |
| `ignore` | 168 | jugé une fois : le binaire fonctionne (il ne connaît pas `--help`, il réclame ses arguments), ou il est hors d'usage ici (SELinux absent, helper PAM), ou ce n'est pas un binaire. **Plus aucun `ignore` ne porte sur un binaire qui ne démarre pas** (journal, épisode 8) |

Trois de ces `ignore` méritent d'être nommés : **`bin`, `sbin` et `X11` ne sont pas des
binaires** mais des **répertoires** que `BINARY_LIST` a ramassés — un défaut du générateur de
la liste, constaté ici et laissé là où il est.

**Ce que les deux `fix` disent d'eux-mêmes** : leur action **nomme un paquet**
(`perl-tk`, `libsnmp-perl`). Ce n'était qu'un *candidat* jusqu'à l'épisode 8, qui l'a vérifié
contre le catalogue trixie que l'image transporte elle-même. Ce qui reste à la re-sonde n'est
plus l'existence du paquet mais le seul fait qui compte : met-il le module **là où le script le
cherche** ?

**L'agent ne fait qu'une chose** : lire le rapport + la politique courante et proposer un
**diff de politique** dont chaque ligne est adossée à une preuve du rapport. Il ne touche ni à
l'image ni aux scripts ; l'humain valide, ça se commite.

## 5. L'étage 3 — appliquer, aux deux endroits

- **3a, l'image publiée** : `Makefile.d/filesystem.apply-binary-policy.sh` (épisode 5, § 3.8)
  traduit la politique en `--in-guest` passés à `filesystem.update-published-image.sh` (`fix` →
  sa commande, `drop` → la sienne). Il **refuse le fichier entier**, en nommant la ligne, dès
  qu'une ligne ne dit pas clairement quoi faire, et il **dérive** le nom de la politique de celui
  de l'image plutôt que d'appliquer les verdicts d'une distribution à une autre.
  `--only-verdict` joue une famille de verdicts à la fois, parce qu'un épisode applique et
  re-sonde par tranches.
- **3a bis, mesurer avant d'appliquer** : `filesystem.update-published-image.sh` a gagné à
  l'épisode 4 une option **`--no-export`** — *joue les commandes dans l'invité, n'exporte rien,
  ne publie rien*. Le cow part avec la session, comme celui de la sonde : **une mesure ne
  produit pas d'image**. Sans elle, poser une question à l'invité (« que retire cette purge ? »,
  « qui possède ce lien ? ») obligeait à exporter une variante dans le répertoire de release
  pour l'effacer ensuite. Sous `--no-export`, un statut non nul n'arrête plus le run : c'est
  une **mesure** (`dpkg -S` répond 1 pour un fichier qu'aucun paquet ne possède), et il n'y a
  rien à protéger puisque rien n'est produit.
- **3b, le constructeur** (épisode 7) : `uml/pupisto.debian/pupisto.debian.sh` applique **les
  mêmes jugements** dans son chroot, par la fonction `apply_binary_policy`, appelée **juste avant
  `clean_debian_filesystem`** — de sorte que les orphelins laissés par une purge tombent d'
  eux-mêmes dans l'`apt-get autoremove` et le `deborphan` qui suivent. C'est le côté **bon
  marché** de la correction : ici il n'y a ni image à republier ni invité à piloter, et c'est
  pourquoi 16341 a pu être laissée en l'état.

  **Mais il ne LIT pas la politique.** Le format à quatre colonnes n'a qu'**un seul lecteur**,
  l'étage 3a, qui a gagné pour cela une option **`--print-actions`** : elle contrôle le fichier
  exactement comme avant un run — verdict inconnu, `drop`/`fix` sans action, action sur un
  verdict qui n'en veut pas, colonnes ≠ 4, raison vide — puis imprime sur **stdout** les actions
  dédupliquées, et **rien du tout** si le fichier est refusé (les 5 refus rejoués : `rc` 2, sortie
  vide). Elle se passe d'image quand `--policy` est donné, puisqu'il n'y a alors rien à dériver.
  Un second lecteur du format aurait été libre de diverger du premier ; il n'y en a donc qu'un.
  Ce que `pupisto` reçoit pour trixie : **3 actions pour 49 noms**.

  Trois comportements éprouvés hors invité (la fonction seule, avec un chroot factice) : la
  politique réelle donne ses 3 actions **verbatim** au chroot ; une distribution **sans**
  politique (wheezy, stretch) dit *« nothing to apply »* et rend **0** — n'avoir jamais été triée
  n'est pas une faute ; une politique **refusée** rend **1** et n'applique rien. Une action qui
  échoue arrête la construction (`set -e`) : une image dont la politique n'a pas été appliquée
  jusqu'au bout n'est pas l'image que la politique décrit — et `once` n'enregistre pas une étape
  ratée, donc la construction reprend là où elle s'est arrêtée.

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

> **Livré** : la mécanique à l'épisode 9, le jugement à l'épisode 10 — bilan au § 9.

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
| **La mécanique** | **2 cibles `make`** : `filesystem.probe-image-binaries`, `filesystem.apply-binary-policy` *(nommées à l'ép. 9 ; l'ép. 0 les appelait `image-probe`/`image-apply`)* | Maillons linéaires et sans connaissance propre ⇒ pas de script de regroupement (ép. 26) |
| **Le jugement + le rituel** | **1 skill** : `.claude/skills/marionnet-triage-binaires/` *(livré à l'ép. 10)* | La seule part qu'une cible `make` ne peut pas porter |
| **L'archive** | ce document + la fiche mémoire | Convention des chantiers du dépôt |

**Ce que le skill contient — et ne contient pas.** Il porte (1) la *passe de décision* ;
(2) le *rituel* et les interdits durables : **une sonde ne publie jamais**, **un verdict gelé
ne se re-dérive pas**, **`ldd` répond à « est-ce une application X ? »**, et **republier une
image, c'est la renommer**. Il ne recopie ni la grammaire des scripts ni la politique : il
**renvoie ici**, comme les autres skills du dépôt.

**Écrit à l'épisode 10, 89 lignes.** Il porte les quatre étages en une table (où l'agent *se
tient* : **entre** la sonde et la politique, jamais dans la boucle), la passe de décision en cinq
temps — prendre le rapport **entier**, **relire aussi les `OK`**, poser la question de l'ép. 6 à
**chaque maillon**, écrire **une ligne par cas examiné**, adosser chaque ligne à une preuve —,
puis **onze interdits**, chacun payé par une mesure d'un épisode. Deux ont été ajoutés à ceux que
l'ouverture avait prévus, parce qu'ils sont ce qui coûte le plus cher quand on l'ignore :
*une action se **mesure** dans l'invité avant d'être appliquée* — et, en le vérifiant dans le
`Makefile` au moment de l'écrire, **l'étage 3a sans options écrit une nouvelle image dans le
répertoire de release**, d'où les deux répétitions `--dry-run` puis `--measure` — et *une cause
structurelle se vérifie par la **structure**, jamais par le motif du message*. La formulation de
l'ouverture (« `ldd` répond à… ») a été corrigée en « **`ldd` non : la fermeture transitive vers
`libX11`** » : l'esprit de la règle tient (on **mesure**, on ne lit pas une liste écrite à la
main), l'instrument a changé à l'ép. 2 — un skill qui aurait gardé la lettre aurait enseigné un
instrument que l'ép. 1 a mesuré **faux *et* trop lent** (§ 3.3).

**Ce qu'il ne fait pas** : aucune option n'y est documentée (`--help` du script, § 4 et § 5 de ce
document), et il n'y a **aucun skill coordinateur** — la chaîne reste deux cibles `make` avec une
décision au milieu.

## 8. Réserves établies à l'ouverture

- **`xlinks2` n'est probablement pas « cassé »** : `BadMatch` sur `X_CreateWindow` est la
  signature d'un désaccord **visual/profondeur** avec le relais X — `xeyes` marche parce
  qu'il ne demande rien de particulier. Le remède peut être une option, pas une suppression.
  C'est l'étage 2 qui tranchera, **sur la preuve**.
- **Republier une image, c'est la renommer** : son nom est son `sum`, et le `mtime` du
  *backing file* fait foi (ép. 23). Chaque tour d'application produit une image **neuve**.

## 9. Clôture (2026-09-05) — ce qui est atteint, et ce qui ne l'est pas

Le chantier se clôt à l'**épisode 11**, sur une destination **atteinte pour trois de ses quatre
conditions**, la quatrième étant **déléguée** — pas abandonnée, et surtout pas prouvée en douce.

### 9.1 Atteint

| Condition de la DESTINATION | État | Où c'est |
|---|---|---|
| La **politique** porte un verdict pour *chaque* candidat de `BINARY_LIST` | **fait** (ép. 3→8) | `uml/pupisto.debian/pupisto.debian.sh.files/binary_policy.trixie.tsv` — 225 lignes, 55 `drop`, 2 `fix`, 168 `ignore` |
| `pupisto.debian.sh` la **consomme à la construction** | **fait** (ép. 7) | `apply_binary_policy`, appelée juste avant `clean_debian_filesystem` |
| Le **skill** et ce **document** existent | **fait** (ép. 10) | `.claude/skills/marionnet-triage-binaires/SKILL.md` (89 l.) + ce fichier |
| La chaîne tourne **de bout en bout sur trixie**, re-sonde verte | **délégué** — cf. § 9.2 | à la prochaine image trixie construite (chantier `marionnet-kernel-rootfs`) |

S'y ajoutent, hors condition mais au livrable (ép. 9) : les deux cibles
`filesystem.probe-image-binaries` et `filesystem.apply-binary-policy`, `IMAGE=` seul explicite,
le reste par `OPTIONS=`.

### 9.2 Non prouvé — à dire, pas à masquer

Deux choses n'ont **jamais** tourné pour de vrai, et aucune formulation de clôture ne doit
laisser croire le contraire :

- **L'étage 3a n'aura jamais tourné jusqu'à l'export.** C'est la conséquence assumée du critère
  de reprise de l'épisode 7 (§ DESTINATION) : 16341 reste en l'état. 3a est éprouvé en
  `--dry-run`, `--print-actions` et `--measure` — jamais au bout. Ce n'est pas un outil mort :
  c'est celui du jour où un défaut vaudra la reprise d'une image publiée.
- **L'étage 3b n'a pas de run réel.** `apply_binary_policy` est éprouvé **hors invité** (fonction
  seule + chroot factice : politique réelle → 3 actions **verbatim** ; distribution sans politique
  → *nothing to apply*, rc 0 ; politique refusée → rc 1, rien d'appliqué ; les 5 refus rejoués en
  `--print-actions` → rc 2, sortie vide). C'est une preuve **par construction**, pas une re-sonde.

Le risque résiduel est faible et **bruyant** : sous `set -e`, une action qui échoue **arrête** la
construction, et `once` n'enregistre pas une étape ratée — l'échec ne peut pas passer en silence.

### 9.3 Pourquoi clore maintenant plutôt que veiller

Il ne restait pas un *travail*, mais une *vérification* qui se produira d'elle-même à la
prochaine construction d'image — laquelle appartient au chantier parent, pas à celui-ci. Or la
DESTINATION porte son propre test de réussite : **« la prochaine image ne doit pas rouvrir un
chantier »**. Si constater une image neuve exigeait de rouvrir celui-ci, ce serait la preuve que
le livrable a raté ; il existe précisément pour que ce geste soit `make` + une passe d'agent.
Face à cela, la veille se paie à **chaque session** (fiche mémoire et pointeur `CLAUDE.md` relus)
pour une étape dont la date dépend d'autrui.

La contrepartie, non négociable, est le § 9.4 : la vérification est **écrite chez celui qui
construira l'image**. Une clôture qui l'aurait seulement espérée aurait été un abandon déguisé.

### 9.4 Ce qui est délégué à `marionnet-kernel-rootfs`, et comment le lire

> **À la première image trixie construite avec la politique** : re-sonder l'image neuve
> (`make filesystem.probe-image-binaries IMAGE=…`) et y lire **deux faits**, seuls restes non
> prouvés de la politique :
> 1. les **2 `fix`** (`snmpcheck`, `snmp-bridge-mib`) déposent-ils le module perl **là où le
>    script le cherche** ? Les paquets (`perl-tk` via `Provides: libtk-perl`, `libsnmp-perl`)
>    sont acquis depuis l'ép. 8 ; c'est l'emplacement qui ne l'est pas ;
> 2. les **55 `drop`** sont-ils tous **absents** de la `BINARY_LIST` de l'image produite ?
>
> Un écart n'est **pas** une réouverture de ce chantier : c'est un épisode du chantier qui a
> construit l'image, joué avec le skill `marionnet-triage-binaires`.

### 9.5 Ce qui reste vrai après la clôture

- **La politique décrit un état *voulu*, pas l'état de 16341** : une re-sonde de l'image en ligne
  y retrouvera les 47 lanceurs Qt5 — c'est la décision de l'ép. 7, pas une régression.
- **Le format à 4 colonnes n'a qu'un lecteur**, l'étage 3a (`--print-actions`) ; `pupisto` lui
  *demande* les actions au lieu de reparser. Ajouter un second lecteur, c'est rouvrir le défaut
  que le chantier a passé son temps à refuser.
- **Les interdits** (11, chacun payé par une mesure) vivent dans le skill, pas ici : c'est lui
  qu'on charge avant de juger un rapport ou d'écrire une ligne de politique.
- **HORS PÉRIMÈTRE** (§ 6) est une archive d'arbitrages, **pas** un reste à faire.

## 10. Journal d'avancement

### 2026-09-05 — épisode 11 : la clôture, et la preuve confiée au chantier qui construira l'image

Question de l'auteur : *« on peut clore le chantier temporairement, quitte à le rouvrir, non ? »*
Réponse — **oui sur le fond, non sur la forme**. Il ne restait pas un travail à faire mais une
**vérification** qui se produira d'elle-même à la prochaine construction d'image, laquelle
appartient au chantier parent. « Clore temporairement » n'est pas une opération de la méthode et
décrit mal cela ; la forme juste est une **clôture pleine (MODE C) avec la dernière vérification
déléguée**, écrite chez celui qui la fera.

Ce que l'épisode a écrit, et rien d'autre — **aucun code touché, aucun boot** :

- le **§ 9** de ce document : les trois conditions atteintes, la quatrième déléguée, et surtout
  le **§ 9.2** — *ce qui n'a jamais tourné pour de vrai* (3a jamais allé jusqu'à l'export, 3b sans
  run réel, éprouvé hors invité). Une clôture qui tait son niveau de preuve ment ;
- la **garde déléguée** dans `docs/kernel-rootfs-refresh.md` et dans la fiche mémoire
  `marionnet-kernel-rootfs` : re-sonder la première image trixie construite, y lire **deux
  faits** (les 2 `fix` déposent-ils le module là où le script le cherche ; les 55 `drop` sont-ils
  absents de la `BINARY_LIST`) ;
- la **fiche mémoire** de ce chantier réduite à un renvoi, son entrée de `MEMORY.md` et de
  `CLAUDE.md` passées aux archives.

Le raisonnement qui a tranché, à ne pas re-dérouler : la DESTINATION porte **son propre test de
réussite** — *la prochaine image ne doit pas rouvrir un chantier*. Si constater une image neuve
exigeait de rouvrir celui-ci, ce serait la preuve que le livrable (2 cibles `make` + 1 skill) a
raté. À l'inverse, la veille se paierait à chaque session pour une étape dont la date dépend
d'autrui. Le risque résiduel accepté est nommé : 3b n'a pas de run réel — mais sous `set -e` une
action ratée **arrête** la construction, l'échec ne peut pas passer en silence.


### 2026-09-05 — épisode 10 : le jugement, écrit là où une cible `make` ne peut pas le porter

L'épisode 10 *prévu* — la première image **construite** avec la politique — dépend du chantier
parent `marionnet-kernel-rootfs` : on ne construit pas une image invitée pour ce seul motif. Comme
à l'épisode 9, l'épisode joue donc la part du § 7 qui ne demande **aucune image**, et l'image
neuve glisse à l'épisode 11 (la clôture suivra).

**Livré** : `.claude/skills/marionnet-triage-binaires/SKILL.md` (89 lignes), et son pointeur dans
le `CLAUDE.md` du projet. Le § 7 ci-dessus dit ce qu'il contient et pourquoi ; deux points valent
d'être notés ici, parce qu'ils ont été **trouvés en l'écrivant**, pas recopiés :

- **Une garde que le chantier connaissait sans l'avoir énoncée comme telle** : l'étage 3a
  **sans options écrit une nouvelle image dans le répertoire de release**. Le commentaire de la
  cible `make` le disait déjà (épisode 9) ; le skill en fait un **interdit** au même rang que
  « une sonde ne publie jamais », avec ses deux répétitions (`--dry-run`, puis `--measure`).
  C'est la seule marche de la chaîne qui publie, et c'est celle qu'on atteint par défaut.
- **La lettre du § 7 avait vieilli** : il prescrivait d'enseigner que « `ldd` répond à *est-ce une
  application X ?* », formulation de l'épisode 0 que l'épisode 1 a mesurée **fausse *et* trop
  lente** et que l'épisode 2 a remplacée par une fermeture transitive vers `libX11`. Le skill
  enseigne la **règle** (on mesure, on ne lit pas une liste écrite à la main) et l'**instrument
  actuel**. C'est la même famille de défaut que le chantier traque depuis l'épisode 3 — *juger par
  autre chose que ce qu'on mesure* —, ici sous sa forme documentaire : un livrable de clôture
  écrit d'après un plan d'ouverture, et non d'après l'état mesuré.

**Vérifié en l'écrivant, pas supposé** : les deux cibles existent bien (`Makefile:541,553,775`),
la politique est bien à 225 lignes, les colonnes du rapport sont bien celles que le skill annonce
(`name verdict rc probe via <message>`, en-tête d'un rapport de `docs/probe-reports/`), le défaut
de `--output` est bien `docs/probe-reports/<image>-<date>.tsv`, et `pupisto` dit bien
*nothing to apply* pour une distribution sans politique (`pupisto.debian.sh:1162`). Le harness a
chargé le skill dès son écriture — sa `description` est donc bien celle qui le rendra
découvrable. **Aucun boot, aucune image, rien d'appliqué.**

### 2026-09-05 — épisode 9 : les deux bouts de la chaîne deviennent des cibles

L'épisode qui était prévu ici — *la première image construite avec la politique* — **dépend du
chantier parent** `marionnet-kernel-rootfs` : on ne construit pas une image de plusieurs Go pour
ce seul motif. Il glisse donc, et l'épisode joue la part du § 7 qui ne demande **aucune image** :
la **mécanique**.

Deux cibles ajoutées au `Makefile`, à côté des publieurs de la famille `filesystem.` :

- **`filesystem.probe-image-binaries`** (étage 1, observer) ;
- **`filesystem.apply-binary-policy`** (étage 3a, appliquer à une image **publiée**).

**Trois choix de forme, et leur raison.**

1. **Le nom.** Le § 7 disait `image-probe` / `image-apply`, écrits à l'ép. 0 — avant que les
   scripts existent. Les quatre cibles voisines nomment **exactement leur script**
   (`filesystem.prepare-snapshot-to-publish`, `kernel.prepare-to-publish`,
   `release.sha256sums`) ; garder les noms de l'ép. 0 aurait rompu cette correspondance 1:1 pour
   ces deux-là seulement, et perdu le regroupement par préfixe qu'offre la complétion de `make`.
   Les cibles portent donc le nom de leur script, et le § 7 est corrigé.

2. **`IMAGE=` explicite, tout le reste par `OPTIONS=`.** Une cible pourrait déclarer les 12
   options du script de l'étage 3a. Ce serait un **second endroit où la grammaire est écrite** —
   exactement le défaut que ce chantier refuse ailleurs (un format, **un** lecteur ; § 5). Ce
   qu'une cible peut enseigner et qu'un script ne peut pas, c'est la **syntaxe make** : d'où le
   seul `IMAGE`, avec un message d'usage quand il manque, sur le modèle de
   `kernel.prepare-to-publish KERNEL=…`. Le reste traverse intact, et `--help` reste la source.

3. **Aucune des deux ne prend `--series`**, contrairement aux publieurs voisins : les deux
   scripts dérivent eux-mêmes le répertoire de release (`--print-series` du publieur), et
   `--from` l'écrase. Passer la série ici aurait ajouté un troisième endroit qui la connaît.

**Et pas de troisième cible.** Le § 7 le disait déjà et l'épisode le confirme en le rendant
visible : entre les deux bouts il y a une **décision**, que seul un skill peut porter — un
`make image-triage` obligerait à choisir ce que l'agent décide, ou à mentir sur l'automatisme.
Le commentaire du `Makefile` le dit à l'endroit où quelqu'un chercherait la cible manquante.
Symétriquement, l'étage **3b** (pupisto) ne passe **pas** par la cible : il demande ses actions
au script (`--print-actions`), pour que les quatre colonnes gardent un seul lecteur.

**Preuves prises dans la session** (aucun boot, aucune image écrite) :

| Commande | Attendu | Mesuré |
|---|---|---|
| `make filesystem.probe-image-binaries` (sans `IMAGE`) | usage + refus | `rc 2`, ligne d'usage |
| `make filesystem.apply-binary-policy` (sans `IMAGE`) | usage + refus | `rc 2`, ligne d'usage |
| `make filesystem.apply-binary-policy IMAGE=machine-debian-trixie-16341 OPTIONS=--dry-run` | la politique relue, la ligne de commande imprimée, rien de booté | `rc 0` — `2 fix / 55 drop / 168 ignore`, **11 actions pour 57 noms**, les 57 dans la `BINARY_LIST` |
| `make filesystem.probe-image-binaries IMAGE=… OPTIONS="--only pas-un-binaire"` | `OPTIONS` découpé en deux mots, refus **avant** tout boot | `rc 2`, *not in the BINARY_LIST* |

Ce que ces preuves **ne** montrent pas, et qui reste à l'ép. 10 : un run réel de la sonde par la
cible (il coûte un boot et ~2 h), et l'application jusqu'à l'export — qui, par la décision de
l'ép. 7, n'aura **jamais** lieu depuis l'étage 3a.

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
run complet, à comparer aux **3287 s** de l'épisode 1 — mesure prise à part (§ 10, épisode 3).
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

### 2026-09-04 — épisode 4 : la mesure qui a réfuté l'action, et les sept que le motif n'avait pas vus

**Ce que l'épisode devait faire** : appliquer **un** cas de bout en bout — `qtchooser`, 32 lignes
d'un geste — avec re-sonde discriminante. Il s'est arrêté **avant d'appliquer**, parce que la
mesure préalable a montré que l'action était fausse. C'est exactement ce que la mesure était là
pour faire.

**L'outil qui manquait, et qui tient en dix lignes** : `--no-export` sur
`filesystem.update-published-image.sh` (§ 5). Poser une question à un invité n'est pas le
changer ; le chantier a déjà une garde pour ça — *une sonde ne publie jamais* — et ce script
n'avait aucun moyen de l'honorer : `--no-publish` exporte quand même une variante dans le
répertoire de release. Deuxième point, découvert en s'en servant : `run_in_guest` **tuait** le
run sur un statut non nul, ce qui est juste quand une image est en jeu et faux quand on mesure —
`dpkg -S` répond `1` pour un fichier qu'aucun paquet ne possède, et cette réponse-là est la
donnée. Sous `--no-export`, le statut est **rapporté** et le run continue.

**Ce que l'invité a dit** (un boot, cinq commandes, rien d'exporté) :

| question | réponse mesurée |
|---|---|
| `dpkg -l qtchooser` | `ii 66-2` — installé |
| `dpkg -L qtchooser` | possède `/usr/bin/qtchooser`, **46 liens** dans `/usr/bin`, et les `.conf` |
| `apt-get -s -y purge qtchooser` | retirerait **3 paquets** : `qtchooser`, **`qtbase5-dev-tools`**, **`python3-pyqtgraph`** |
| `ls -l` sur les 32 | tous des liens symboliques vers `qtchooser` |
| `dpkg -S` sur les 32 | tous possédés par `qtchooser` |

Et, **sans booter**, `debugfs` sur l'image publiée : `/usr/lib/qt5/bin` **existe** et porte
**10 binaires réels** — le répertoire que la politique disait *« absent de l'image »*.

**Quatre conséquences**, les trois premières détaillées au § 3.7 :

1. **L'action est remplacée.** `apt-get -y purge qtchooser` aurait emporté `qtbase5-dev-tools`,
   donc `moc`, `rcc`, `uic`, `qlalr`, `qvkgen`, `qdbuscpp2xml`, `qdbusxml2cpp` — **sept lanceurs
   que la sonde a mesurés à `rc` 0**, c'est-à-dire qui marchent — et `python3-pyqtgraph` par
   surcroît. Chaque ligne porte désormais son `rm -f /usr/bin/<nom>` : on retire le **lien
   pendant**, pas le paquet.
2. **Une supposition démentie, dans l'autre sens** : `dpkg -L` **possède** bien les liens (on
   craignait qu'il les ignore). La purge les aurait donc emportés — mais le remède devait viser
   les liens, pas le paquet.
3. **Sept cassés de plus**, invisibles à la relecture de l'ép. 3 parce que `qtchooser` les
   éconduit dans une **autre phrase** (`could not find a Qt installation of ''`) : `qdbus`,
   `qml`, `qmlimportscanner`, `qmlscene`, `qtdiag`, `qtpaths`, `qtplugininfo`. La politique passe
   à **217 lignes** (39 `drop`, 2 `fix`, 176 `ignore`).
4. **Le format que le fichier annonçait n'était pas celui qu'il portait** : l'en-tête décrivait
   **cinq** colonnes, `family` comprise, et **aucune** des 210 lignes n'en avait plus de quatre —
   la famille vivait déjà, et seulement, dans l'en-tête `# --- <famille> (n)` de chaque groupe.
   Écrire mes 39 lignes sur cinq colonnes aurait rendu le fichier illisible à un consommateur
   qui découpe par tabulation. C'est la description qui est corrigée, pas les 178 autres
   lignes : la famille n'a **aucun** consommateur, et une colonne qu'aucun programme ne lit ne
   vaut pas 178 lignes réécrites.

**La leçon, et elle n'est pas « écrire un meilleur motif »** : un motif reconnaît ce qu'il a été
écrit pour reconnaître. Ce qui a trouvé les sept manquants n'est pas une relecture plus
attentive des messages, c'est un **chemin indépendant** vers la même cause — l'ensemble des liens
que le paquet possède, moins l'ensemble des cibles qui existent. Quand un verdict porte sur une
**cause structurelle**, il doit se vérifier par la structure, pas seulement par ce que le binaire
a bien voulu écrire. Encore la famille *juger par autre chose que ce qu'on mesure* — cette fois
en aval, sur la **relecture**, et non sur la sonde.

**Ce qui n'a pas été fait, et pourquoi** : l'application et la re-sonde. L'action de 32 lignes
sur laquelle l'épisode devait s'appuyer n'existe plus ; appliquer maintenant, ce serait appliquer
la version corrigée sans l'avoir relue. L'épisode 5 la joue — et il a désormais **39** noms à
faire disparaître, ce qui rend la re-sonde plus discriminante encore.

### 2026-09-04 — épisode 5 : le traducteur, et le séparateur que le canal réclamait

**Ce que l'épisode devait faire** : appliquer de bout en bout les 39 `drop` que l'épisode 4 avait
relus. Il livre le **traducteur** (l'étage 3a, § 3.8) et la **mesure** qui montre que le geste est
juste — et il s'arrête là : produire l'image neuve est une décision de l'auteur.

**Ce qui est neuf** : `Makefile.d/filesystem.apply-binary-policy.sh`, 7ᵉ de la famille. Il ne
décide rien (chaque commande vient verbatim de la colonne `action`), refuse le fichier entier en
nommant la ligne dès qu'une ligne ne dit pas clairement quoi faire — 6 refus éprouvés, rc 2 —,
dérive le nom de la politique de celui de l'image et **refuse plutôt que de deviner** quand cette
distribution n'en a pas. Trois profondeurs : `--dry-run` (rien ne boote), `--measure` (rien n'est
exporté), le run réel.

**Le défaut trouvé en s'en servant, et qui n'était pas dans la politique** : `exec` reconnaît une
option **où qu'elle soit** dans la ligne et refuse celles qu'il ne connaît pas ; or
`filesystem.update-published-image.sh` construisait `exec m1 $1` **sans le séparateur**. Une
commande `--in-guest` portant une option longue était donc refusée par le canal et tuait le run,
sur une commande que l'invité n'a jamais vue. `run_in_guest` construit désormais `exec m1 -- $1`.
Le canal disait le remède dans son propre message de refus ; c'est l'appelant qui ne l'appliquait
pas.

**Ce que l'invité a répondu** (un boot, 39 retraits, 5 vérifications, rien d'exporté) :
`still-there=0 of 39` ; les **7 lanceurs sains exécutent toujours leur cible** ; `/usr/lib/qt5/bin`
porte toujours ses **10 outils** ; et les entrées de `/usr/bin` possédées par `qtchooser` qui
n'existent plus sont **exactement 39** — 46 − 39 = **7**, l'arithmétique de l'épisode 4, refermée.

**Deux réserves énoncées, pas tues** : `qvkgen` sort `rc` 1 en imprimant son propre `Usage:` — il
a démarré, et c'est le message qui le dit ; et la vérification par `dpkg-query -W -f=…` n'a rien
rapporté, son `${binary:Package}` étant aussi de la syntaxe bash, mangée par le shell de l'invité
avant `dpkg-query` — vérification mal écrite, à laquelle l'inventaire de `/usr/lib/qt5/bin` répond
de toute façon.

### 2026-09-04 — épisode 6 : la question qui décide n'était pas celle qu'on posait

**Ce que l'auteur a corrigé, et qui est une doctrine, pas une ligne.** Les 39 `drop` de la
politique portaient chacun un `rm -f /usr/bin/<nom>` — le correctif de l'épisode 4, qui avait
sauvé sept lanceurs sains d'une purge trop large. La consigne de l'épisode 6 renverse le point de
vue : *ce ne sont pas les binaires qu'il faut supprimer, mais les paquets `.deb` qui les
contiennent, selon la gravité du problème*. Et elle donne la question qui tranche :

> **Le paquet P qui contient le binaire X qui ne fonctionne pas a-t-il quand même un intérêt sans X ?**

La question que le chantier posait jusque-là — *ce binaire marche-t-il ?* — ne mène qu'à un
`rm -f`, c'est-à-dire à une image d'où l'on a effacé la **trace** d'un paquet dont la raison
d'être avait disparu. La bonne question porte sur le **reste**.

**Ce que l'image répond, lue hors ligne (aucun boot).** `debugfs` sur l'image publiée donne
`/var/lib/dpkg/status`, `/var/lib/apt/extended_states` et les 1220 `*.list`. La chaîne qui amène
`qtchooser` dans une image de laboratoire réseau y est écrite, et elle est **linéaire et
exclusive** :

```
binwalk (installé manuellement — voulu)
  `-- python3-binwalk           auto  --Recommends--> python3-pyqtgraph
        `-- python3-pyqtgraph   auto  --Depends-----> qtbase5-dev-tools   (son SEUL détenteur)
              `-- qtbase5-dev-tools auto --Depends--> qtchooser           (son SEUL détenteur)
                    `-- qtchooser   auto             porte les 46 liens
```

Les deux faits « seul détenteur » sont mesurés sur `status` (aucun autre paquet installé ne
dépend de `qtbase5-dev-tools`, aucun autre de `qtchooser`) ; `extended_states` marque les trois
`Auto-Installed`. La question, remontée maillon par maillon : `qtchooser` sans les 39 ne garde que
sept outils de développement Qt5 ; `qtbase5-dev-tools` n'existe que pour `pyqtgraph` ; et
`pyqtgraph` n'est qu'un **Recommends** de binwalk.

**Le fait qui a tranché — et qu'il aurait été facile de supposer dans l'autre sens.** Un
`Recommends` se justifie d'ordinaire par une fonctionnalité optionnelle ; on pouvait donc craindre
que purger `pyqtgraph` coûte à binwalk son tracé d'entropie. La mesure dit le contraire :
**aucun fichier `.py` de `python3-binwalk` ne mentionne `pyqtgraph`**. Le tracé passe par
`matplotlib` (installé), derrière son propre `except ImportError` — lu dans
`binwalk/modules/entropy.py`. Le `Recommends` n'a, dans cette version, **aucun site d'appel**.

**Ce que la politique dit désormais.** La famille `qt5-wrapper` passe de 39 à **47 lignes**, toutes
`drop`, toutes portant la même action :

```
apt-get -y purge python3-pyqtgraph qtbase5-dev-tools qtchooser
```

47 et non 46 : les fichiers de `/usr/bin` possédés par les trois paquets sont **exactement** les
46 liens **plus `qtchooser` lui-même**, et les 47 sont **tous** dans la `BINARY_LIST` de l'image
(mesuré). S'y ajoutent donc les **7 lanceurs qui marchent**, que l'épisode 4 avait protégés : ils
fonctionnent, mais leur paquet n'a plus d'intérêt — ce sont des outils de construction Qt5, et
rien dans cette image ne construit du Qt. Le sélecteur lui-même part enfin, n'ayant plus rien à
sélectionner.

**Les paquets sont nommés, jamais déduits.** L'action ne fait **pas** d'`autoremove` : un
`apt-get autoremove` déciderait à la place de la politique ce qui s'en va. Les trois noms sont
écrits, et ce sont les trois que l'invité retire.

**Une ligne par nom, malgré une seule commande.** La politique doit **nommer tout ce qui
disparaît**, sans quoi une re-sonde n'a aucun moyen de distinguer un retrait voulu d'une surprise.
Mais jouer 47 fois la même commande ferait 46 boots d'inutilité. `filesystem.apply-binary-policy.sh`
**déduplique donc les actions strictement égales** — chaîne pour chaîne, sans fusion, sans
réécriture, sans réordonnancement : il ne décide toujours rien. Le `--dry-run` l'affiche :
`1 action(s) for 47 name(s) (46 line(s) repeat an action already played)`. Les cinq refus du
lecteur de politique (verdict inconnu, `drop`/`fix` sans action, action sur un verdict qui n'en
veut pas, colonnes ≠ 4, raison vide) ont été rejoués : tous à `rc` 2.

**Ce que l'invité a répondu** (un boot, `--measure`, **rien d'exporté**) :

- apt retire **exactement les trois paquets nommés**, 8301 ko libérés, aucun autre ;
- `binwalk` et `python3-binwalk` restent `ii`, `binwalk --help` sort `rc` 0 et
  `python3 -c 'import binwalk'` répond — la crainte du tracé perdu était infondée, comme la
  lecture des sources le laissait attendre ;
- les quatre témoins `qtchooser`, `moc`, `qmake`, `qdbus` sont **absents** ;
- `dpkg -l` ne connaît plus les trois paquets.

Les 43 autres noms ne sont pas vérifiés un par un : ce sont, par construction, les fichiers que
dpkg possédait et qu'il retire. La preuve exhaustive est **gratuite au run réel** — le publieur
reconstruit `BINARY_LIST` en lisant l'image produite, et le diff avant/après nommera les 47.

**Un fait mesuré qu'on ne traite pas ici** : la purge laisse **32 paquets orphelins**
(`pyqt5-dev-tools`, `pyqt6-dev-tools`, `qt6-base-dev-tools`, `python3-pyqt6`, `libqt5opengl5t64`,
`x11proto-dev`…), qu'apt signale « no longer required » sans les retirer. `pyqtgraph` tirait donc
bien plus que la chaîne linéaire ci-dessus. Les retirer serait de l'**amaigrissement**, hors
périmètre (§ 6) ; savoir si l'un d'eux porte un binaire cassé est en revanche une question de ce
chantier — non mesurée, notée telle quelle.

**Rien n'est appliqué.** L'image neuve attend toujours le feu vert de l'auteur.


### 2026-09-04 — épisode 7 : ce qui se capitalise, et ce qu'on renonce à reprendre

**Décision de l'auteur, prise sur le chiffre de l'épisode 6** : *si la conclusion appliquée à la
trixie actuelle est d'enlever un paquet, ça ne vaut pas la peine de régénérer une image — on
laisse 16341 ; en revanche on capitalise autant que possible pour les images à venir.* Le calcul
est sans appel : recompresser 5,4 Go et republier sous un nouveau nom pour 8301 ko de lanceurs Qt5
que nul énoncé n'appelle. S'y ajoute la consigne active du chantier parent — *aucune release avant
la fin de la campagne* : republier une image **est** une publication.

**Ce que l'épisode a écrit plutôt que laissé implicite.** La destination promettait *« une image
**publiée** ne contient que des binaires qui fonctionnent »* : la laisser telle quelle en gardant
16341 en ligne l'aurait rendue fausse, et le critère d'arrêt du chantier invérifiable. Elle porte
désormais sur **toute image construite désormais**, et la reprise de l'existant devient un
critère explicite, écrit sur l'**usage** et non sur la taille — *on ne reconstruit pas une image
publiée pour des binaires dont l'échec ne bloque aucun geste pédagogique*. Sans cette phrase, la
question se re-tranchait à chaque politique.

**Ce que l'épisode a construit : l'étage 3b** (§ 5). `pupisto.debian.sh` applique la politique
dans son chroot, juste avant le nettoyage final, et **sans lire le fichier** : il demande ses
actions à l'unique lecteur du format (`--print-actions`, neuf). C'est l'invariant « une seule
source de vérité » que ce dépôt applique déjà à la grammaire du canal et aux dépendances runtime ;
ici il évite qu'un second lecteur accepte un jour une ligne que le premier refuse.

**Trois conséquences consignées, pour ne pas croire avoir prouvé ce qu'on n'a pas prouvé** :
l'étage 3a n'aura jamais tourné jusqu'à l'export (la chaîne verte de bout en bout sera démontrée
par `pupisto`, pas par le respin) ; les deux `fix` réseau (`snmpcheck`, `snmp-bridge-mib`) ne
tombent **pas** sous le critère de renoncement et se reposeront à l'épisode 8 ; et l'image en
ligne diverge désormais **volontairement** de la politique, ce que l'en-tête du fichier dit
maintenant lui-même — une re-sonde de 16341 y retrouvera les 47, et ce sera cette décision, pas
une régression.

**Aucune image n'a été produite, et aucune ne le sera pour 16341.**

### 2026-09-04 — épisode 8 : le reste de la politique, jugé sans booter

L'épisode solde les quatre questions que les épisodes 4, 6 et 7 avaient laissées écrites, et il
les solde **sans un seul boot** : tout ce qu'il fallait savoir est *dans* l'image, lisible par
`debugfs` — `/var/lib/dpkg/{status,info/*.list}`, `/var/lib/apt/extended_states`, les binaires
eux-mêmes, et jusqu'au **catalogue trixie complet** que l'image transporte encore
(`/var/lib/apt/lists/…_Packages`, 54 Mo).

**(a) Huit `ignore` posés sur des binaires qui ne démarrent pas — ils contredisaient la
destination.** Cinq helpers debhelper (`dh_autotools-dev_restoreconfig`,
`dh_autotools-dev_updateconfig`, `dh_bash-completion`, `dh_installxmlcatalogs`, `dh_numpy3`),
`dtd2vim`, `vimplate`, `dumpmscat`. La question de l'épisode 6 leur est posée telle quelle — *le
paquet qui le contient a-t-il encore un intérêt sans lui ?* — et elle répond, pour les huit,
**l'inverse** de ce qu'elle répondait à `qtchooser` : chaque paquet garde son intérêt, et chacun
est **requis par quelque chose d'installé** (`automake` → `autotools-dev`, `bash` et `curl` →
`bash-completion`, `polkitd` → `xml-core`, `python3-numpy` → `python3-numpy-dev`) ou voulu pour
lui-même (`vim-scripts`, `samba` — un TP réseau veut samba). Donc le paquet reste et le binaire
part : `rm -f` par nom, l'action de l'épisode 4, qui est ici la **bonne** et non un repli.

Les cinq `dh_*` ne sont réparables à aucun prix acceptable : **`debhelper` n'est pas installé**
(lu dans `status`), donc `Debian/Debhelper/Dh_Lib.pm` est absent par construction, et installer
`debhelper` pour faire marcher un outil de packaging dans une image de laboratoire réseau est
exactement l'inverse du critère du chantier. `dtd2vim` et `vimplate` manquent chacun d'un module
CPAN (`SGML/DTD.pm`, `Template.pm`) : un `fix` ajouterait un paquet pour un outil qu'aucun énoncé
n'appelle.

**(c) Une raison était fausse, et c'est la structure qui l'a dit — la règle de l'épisode 4, de
nouveau.** `dumpmscat` portait « private samba library absent ». Elle ne l'est pas :
`libsamba-debug-private-samba.so.0` **est** dans `/usr/lib/x86_64-linux-gnu/samba`, 41 248 octets.
Ce qui manque est un `RUNPATH` — `dumpmscat` en a un, mais la bibliothèque qu'il charge d'abord
(`libmscat-private-samba.so.0`) **n'en a aucun**, et le `RUNPATH` d'un exécutable, contrairement
à un `RPATH`, **n'est pas consulté pour les dépendances transitives**. C'est un défaut de
packaging Debian, que cette politique ne peut pas réparer : le verdict ne change pas, la raison
si.

**Chaque module nommé dans un message a été cherché dans l'image**, pas cru sur parole :
`Dh_Lib.pm`, `SGML/DTD.pm`, `NetSNMP/OID.pm`, `Tk.pm`, `Template.pm` — les cinq sont réellement
absents de tous les répertoires `@INC` que l'image possède. Et `vimplate` livre le piège de
méthode de l'épisode : il charge `Template` par un **`require` dynamique** (il se diagnostique
lui-même, d'où le `rc` 1 que la sonde a lu `OK`), si bien qu'une lecture **statique** de ses
lignes `use` — que cet épisode a d'abord faite — ne voit pas le module manquant. La vérification
doit partir du module **nommé dans le message**, le `use` ne servant qu'à contre-vérifier.

**La question de l'épisode 4, élargie aux 168 `ignore` : reste-t-il un verdict qui repose sur un
motif de message sans vérification structurelle ?** Passe faite sur les 168, en cherchant les
signatures d'un binaire qui **n'a pas démarré** (`error while loading shared libraries`,
`Can't locate`, `Exec format error`, `Traceback`, `ModuleNotFoundError`…). Sept lignes remontent,
et les sept sont des messages **applicatifs** : le binaire a démarré et se plaint de son argument
(`checkgid: group '--help' not found`, `fstab-decode: --help: No such file or directory`…).
**Aucun `ignore` ne porte plus sur un binaire qui ne démarre pas.**

**(b) Les deux `fix` ne nomment plus des candidats.** L'image transporte le catalogue trixie
main complet : `perl-tk` 1:804.036+dfsg1-5 y est, avec `Provides: libtk-perl`, et `libsnmp-perl`
5.9.4 y est comme *SNMP Perl5 support* de net-snmp. Les deux paquets existent — ce qui restait
à prouver depuis l'épisode 3. Ce que la re-sonde dira encore est le seul fait qui compte et
qu'aucun catalogue ne donne : le module atterrit-il **là où le script le cherche** ?

**(d) Une question ouverte à l'épisode 6, close sans rien à faire.** La purge `qt5-wrapper`
laisse des paquets orphelins qu'apt signale et que cette politique ne retire pas (jamais
d'`autoremove`). Recalculés hors ligne depuis `status` + `extended_states` — fermeture depuis les
paquets *manuels*, les trois purgés retirés : **56**, sur-ensemble des 32 noms qu'apt avait
affichés, et le même calcul donne **0** orphelin *avant* la purge, ce qui valide la méthode. Ces
56 portent en tout **sept** entrées de `/usr/bin` : `pylupdate5`, `pylupdate6`, `pyrcc5`,
`pyuic5`, `pyuic6`, `qtpaths6`, `androiddeployqt6`. **Les sept démarrent.** Aucun n'est cassé :
rien à ajouter à la politique, et les retirer serait de l'amaigrissement — hors périmètre (§ 6).

**Ce que le fichier dit maintenant** : 225 lignes, **55 `drop`**, 2 `fix`, **168 `ignore`**. Son
unique lecteur les relit sans broncher — `11 action(s) for 57 name(s)`, `rc` 0 — et refuse
toujours ce qu'il doit refuser (ligne fabriquée `drop` sans action : `rc` 2, sortie vide). Les
huit chemins visés par un `rm -f` existent bien dans l'image (vérifié par `debugfs`) : un `rm -f`
sur un fichier absent serait un succès silencieux, c'est-à-dire une preuve creuse.

**Rien n'est appliqué, et cette fois ce n'est même plus une attente** : c'est la décision de
l'épisode 7. La chaîne verte sera démontrée par la première image que `pupisto` construira avec
cette politique.
