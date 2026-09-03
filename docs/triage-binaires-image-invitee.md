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
| 2 | **est-ce une application X ?** | `ldd $(command -v X) \| grep -q libX11` | oriente vers 3 ou 4 |
| 3 | non-X : répond-elle ? | `--help` puis `--version`, sous timeout | rc + `stderr` |
| 4 | X : survit-elle à l'écran ? | lancement avec `DISPLAY`, timeout court, puis mise à mort | vivante ⇒ `OK` ; morte + `stderr` ⇒ `FAIL` |

**À ne pas défaire** : « est-ce une application X ? » est **mesuré par `ldd`**, jamais lu
dans une liste écrite à la main — leçon de l'ép. 39 de
`modernisation-installation-marionnet` (*une liste blanche se périme ; on mesure*). Et la
sonde enregistre **le texte de l'erreur**, pas un booléen : c'est lui qui porte la décision
de l'étage 2.

**Sortie** : un rapport TSV daté et **versionné** (c'est une preuve) —
`binaire · verdict · rc · première ligne de stderr · sonde employée`.

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
