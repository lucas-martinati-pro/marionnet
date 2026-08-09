# Chantier : migration-marshal-to-text

> Chantier long, ouvert le 2026-08-09. Cible : le **format des fichiers d'un projet `.mar`**,
> aujourd'hui huit vidages **`Marshal`** binaires — dont `netmodel/network.xml`, qui n'est pas
> du XML. Objectif : écrire une nouvelle version de projet **`v3` en JSON auto-descriptif**,
> **sans toucher** à la lecture de `v0`/`v1`/`v2`, et fournir une conversion en lot pour les
> projets existants (étudiants, collègues enseignants). Skill de pilotage : `chantier-long`.

## 1. Contexte et objectif

Un `.mar` est un **tar.gz** du répertoire de travail du projet (`state.ml:795` en écriture,
`state.ml:425` en relecture). Le conteneur n'est pas en cause : ce sont les **fichiers qu'il
contient** qui sont des vidages `Marshal`.

Le nom `network.xml` est un vestige, explicitement commenté dans le source :

```ocaml
(** Pseudo XML now! (using xforest instead of ocamlduce) *)
   (user_level.ml:2155)
```

Il y avait un vrai backend XML (**ocamlduce**) ; il a été remplacé par `xforest`, une structure
d'arbre OCaml sérialisée par `Marshal.to_channel` (`lib/MARSHAL/oomarshal.ml:35,41`). Le nom de
fichier n'a pas suivi.

**Le problème n'est pas esthétique.** `Marshal.from_*` est **non typé** : il rend un `'a` que le
compilateur croit sur parole. Si le type sérialisé change — un constructeur ajouté à `Row_item`,
un champ ajouté à un enregistrement — un binaire lisant un projet d'une autre génération ne lève
pas d'erreur : il **déréférence n'importe quoi**. Ce risque est déjà documenté dans le code
lui-même (`state.ml:270-278`), qui explique que `states/ports` a été renommé `states/ifconfig`

> *« in order to prevent seg-faults of old binaries reading a new project »*

Toute la machinerie `project_version` `v0`/`v1`/`v2` (`state.ml:279-296`) n'existe que pour
compenser un format qui **ne se décrit pas lui-même**. Conséquences quotidiennes : un `.mar` ne
se relit pas, ne se compare pas (aucun diff Git utile), ne se fabrique pas par script, et ne
s'audite qu'au `grep -a`.

**Ce que le chantier vise :**

1. une version de projet **`v3`** dont tous les fichiers de données sont du **JSON** ;
2. la lecture de `v0`/`v1`/`v2` **strictement inchangée** — aucun projet existant ne doit devenir
   illisible ;
3. une **conversion en lot** utilisable par un enseignant qui a trente projets d'étudiants ;
4. la garantie qu'un **ancien** Marionnet devant un `.mar` `v3` échoue **proprement**.

**Ce que le chantier ne vise pas** : changer le conteneur `.mar` (il reste un tar.gz), toucher
`Forest_backward_compatibility` (lecture `v0`, intouché), ni bousculer le numéro de version
applicative (`bin/meta.ml`, qui relève de la release).

## 2. Inventaire : les huit fichiers à migrer

L'arborescence d'un projet est documentée en tête de `bin/state.ml:40-67`, les chemins en
`state.ml:191-206`. Règle de nommage `v3` : **radical historique + `.json`**, les deux suffixes
mensongers (`.xml`, `.marshal`) disparaissant.

| # | Fichier `v2` | Schéma OCaml | Fichier `v3` | Écrit par |
|---|---|---|---|---|
| 1 | `netmodel/network.xml` | `Xforest.t` | `netmodel/network.json` | `user_level.ml:2180` |
| 2 | `netmodel/dotoptions.marshal` | `Xforest.t` | `netmodel/dotoptions.json` | `sketch.ml:250` |
| 3 | `states/states-forest` | `(int * Row.t Forest.t)` | `states/states-forest.json` | `treeview.ml:1391` |
| 4 | `states/ifconfig` | idem | `states/ifconfig.json` | idem |
| 5 | `states/defects` | idem | `states/defects.json` | idem |
| 6 | `states/texts` | idem | `states/texts.json` | idem |
| 7 | `states/ifconfig-counters` | `(int * int * Int64.t)` | `states/ifconfig-counters.json` | `treeview_ifconfig.ml:315` |
| 8 | `version` | texte (`"v2"`) | texte (`"v3"`) | `state.ml:786` — **forme inchangée** |

Il n'y a donc que **trois schémas** à concevoir :

- le **forest de nœuds `Xforest`** — `node = tag * (string * string) list`, `forest = node Forest.t`
  (`lib/STRUCTURES/xforest.ml:29-40`) — qui sert **deux** fichiers (network, dotoptions) ;
- le **forest de lignes de treeview** — `Row.t = (field * Row_item.t) list` avec
  `Row_item = String | CheckBox | Icon` (`bin/treeview.ml:42-46,113-117`), accompagné du
  `next_identifier` ;
- le **triplet de compteurs** d'`ifconfig`.

## 3. Décisions actées (2026-08-09)

| Sujet | Décision | Motif |
|---|---|---|
| Format | **JSON** | décision de l'auteur |
| Point d'entrée | `Xforest.to_JSON_string` / `of_JSON_string` / `to_JSON_file` / `of_JSON_file`, dans `lib/STRUCTURES/xforest.ml` | le codec appartient à la structure qu'il sérialise |
| Bibliothèque | **`yojson` 3.0.0**, déjà installée dans le switch `5.4.1` — **pas `ocf`** | `ocf` (1.0.0, également installé) est une couche de *configuration typée* **au-dessus** de yojson, faite pour des options à valeurs par défaut. Le forest est un arbre **dynamique** : `ocf` n'apporterait rien et ajouterait un intermédiaire |
| Les 6 attributs marshalés *dans* le forest | **hybride** : les désimbriquer, avec un **repli d'encodage** pour tout résidu | le format devient réellement lisible là où ça compte (config Quagga d'un routeur), sans risquer une perte de projet en séance |
| Compat descendante | **nouveaux noms de fichiers en `v3`** | ruse maison déjà éprouvée pour `v1`→`v2` : un vieux binaire ne **trouve** pas les fichiers, donc ne passe jamais d'octets étrangers à `Marshal.from_file` |
| ocamlbricks amont | la divergence de la copie vendored est **assumée** — pas de remontée du patch vers Launchpad | décision de l'auteur (2026-08-09) |
| Conteneur `.mar` | **inchangé** | hors périmètre |

**Correction d'un a priori.** `lib/STRUCTURES/sexpr.mli` d'ocamlbricks n'est **pas** un
sérialiseur : c'est une algèbre de produits typés (GADT `Atom | Cons`), sans `to_string` ni
`of_string`. Rien n'y est réutilisable pour ce chantier.

## 4. Schémas JSON proposés (à figer à l'épisode 2)

### 4.1 Le forest de nœuds

```json
{ "format": "marionnet/xforest", "version": 3,
  "roots": [
    { "tag": "network",
      "attrs": [ ["name", "projet1"] ],
      "children": [
        { "tag": "machine",
          "attrs": [ ["name", "m1"], ["memory", "48"] ],
          "children": [] } ] } ] }
```

**Les attributs sont une liste de paires, pas un objet JSON.** Le type OCaml est
`(string * string) list` : l'ordre y est signifiant et les doublons possibles, ce qu'un objet
JSON perdrait silencieusement. L'argument n'est pas théorique — `#eval_forest_attribute` traite
les attributs **séquentiellement**, et le chantier `marionnet-pilotage-par-script` a montré à son
épisode 4f qu'écrire `distrib` **réaligne** `kernel` : deux ordres ne donnent pas le même
résultat. Un objet JSON serait plus agréable à lire et plus `jq`-able ; il serait faux.

Une **valeur** d'attribut est soit une chaîne JSON, soit un objet d'encodage lorsqu'elle contient
des octets non-UTF-8 :

```json
[ "rc_config", { "b64": "hJWmvQAAA…" } ]
```

⚠️ **Piège JSON à ne jamais oublier.** JSON n'a **pas** d'échappement d'octet brut : sa seule
forme d'échappement (`\uXXXX`) désigne un **point de code**. Écrire l'octet `0x8F` ainsi puis le
relire rend le caractère U+008F, soit **deux** octets en UTF-8 — corruption silencieuse. Le repli
**doit** donc être un encodage explicite (base64), jamais un échappement.

### 4.2 Le forest de lignes de treeview

```json
{ "format": "marionnet/treeview", "version": 3,
  "next_identifier": 42,
  "rows": [
    { "fields": [ ["Name",  {"kind": "string",   "value": "m1"}],
                  ["Type",  {"kind": "icon",     "value": "machine"}],
                  ["Up",    {"kind": "checkbox", "value": true}] ],
      "children": [] } ] }
```

Le discriminant `{"kind": …, "value": …}` est préféré au `{"String": …}` de la forme OCaml : il
reste lisible et interrogeable sans connaître les constructeurs.

### 4.3 Les compteurs d'`ifconfig`

```json
{ "format": "marionnet/ifconfig-counters", "version": 3,
  "obsolete_mac_address_as_int": 12345678,
  "next_ipv4_address_as_int": 1,
  "next_ipv6_address_as_int": "1" }
```

`next_ipv6_address_as_int` est un `Int64.t` : il voyage en **chaîne**, JSON n'ayant pas d'entier
64 bits portable. Le champ `_OBSOLETE_mac_address_as_int` est conservé tel quel — il est déjà
écrit « for forward compatibility » (`treeview_ifconfig.ml:313-317`) et ce chantier n'est pas
l'endroit pour le retirer.

## 5. Découpage en épisodes

**Ép. 0 — Officialisation** *(2026-08-09)* : ce document, la fiche mémoire, le pointeur
`CLAUDE.md`. Aucun code.

**Ép. 1 — Le filet AVANT le code : corpus témoin et banc de non-régression.**
Constituer un corpus de `.mar` **réels** : au moins un `v0`, un `v1` et un `v2`, dont un projet
avec **routeur Quagga configuré**, un avec des **defects**, un avec un **history multi-états**.
Écrire un banc de comparaison **sémantique** — jamais octet-à-octet : ouvrir → dumper l'état
**par le canal de pilotage** (`ls`, `get`, `ifconfig`, `defects`, `history`, `rc-get`) → sauver →
rouvrir → re-dumper → comparer.
👉 Point d'appui décisif : le chantier `marionnet-pilotage-par-script` a **déjà construit
l'instrument de mesure** (`useful-scripts/mrnctl`, son épisode 6). Aucun outillage neuf n'est à
écrire, et le banc s'exprime en `.mrn`.
*Prérequis bloquant* : l'auteur doit **désigner** où sont ces `.mar` (aucun scan du disque).

**Ép. 2 — Le codec du forest, dans ocamlbricks.** `to_JSON_string` / `of_JSON_string` /
`to_JSON_file` / `of_JSON_file` dans `lib/STRUCTURES/xforest.ml`, schéma § 4.1 figé ; `yojson`
ajouté aux `(libraries …)` de `lib/dune:47`. Repli base64 pour tout octet non-UTF-8. Tests de
round-trip sur valeurs pathologiques : accents, guillemets, retours à la ligne, octets bruts,
attribut vide, forest vide.
⚠️ `yojson` devient une dépendance de build : intéresse le chantier
`modernisation-installation-marionnet` (paquets `.deb`/RPM, image Docker).

**Ép. 3 — Le codec des treeviews et des compteurs.** Schémas § 4.2 et § 4.3, dans
`bin/treeview.ml` (`Row_item` discriminé, couple `(next_identifier, forest)`,
`treeview.ml:1388-1394`) et `bin/treeview_ifconfig.ml:306-317`.
⚠️ `load_counters` est enrobé d'un `try … with _ -> ()` (`treeview_ifconfig.ml:339-347`) : une
conversion ratée y serait **silencieuse**. Le banc doit vérifier les compteurs **explicitement**,
pas se contenter d'un chargement sans exception.

**Ép. 4 — `v3` dans `state.ml`.** Les huit chemins (`state.ml:191-206`) ;
`opening_project_version` reconnaît `"v3"` (`:279-287`) ; `closing_project_version` devient `v3`
(`:290`) ; écriture `v3` branchée pour les deux forests, les quatre treeviews et les compteurs ;
**lecture `v0`/`v1`/`v2` inchangée**.
⚠️ Point facile à manquer : `try_to_understand_in_which_project_version_we_are`
(`treeview_ifconfig.ml:322-336`) est le **repli** quand le fichier `version` est absent ou
illisible ; il ne connaît que `states/ifconfig` et `states/ports`. Il doit tester **l'existence
des `.json` en tête**, faute de quoi un `.mar` `v3` sans fichier `version` serait rapporté
`None` — « failed to identify ».
*Fin d'épisode* = banc de l'ép. 1 vert sur « ouvrir un `v2` → sauver → rouvrir ».

**Ép. 5 — Désimbriquer les six attributs binaires.** Aujourd'hui, six attributs sont
re-marshalés **à l'intérieur** du forest, parce qu'un attribut `Xforest` est un `string` :
`rc_config` (`machine.ml:654`, `switch.ml:456`) et les quatre champs Quagga du routeur
(`router.ml:1216-1219`). `#to_tree` publiera des clés en clair ; `#eval_forest_attribute` devra
accepter **les deux formes** — ancienne clé marshalée (projets `v0`/`v1`/`v2`) **et** nouvelle
clé en clair. C'est **le** point de non-régression du chantier. Repli base64 pour tout attribut
résiduel non représentable.

**Ép. 6 — Réaccord du canal de pilotage.** Le serveur de contrôle reconnaît ces champs à
l'**en-tête magique de `Marshal`** (`0x8495A6BD/BE/BF`, `control_server.ml:1438`) et les réécrit
(`:1752-1772`). `rc-get` / `rc-set` (§ 4.11 et 4.11.1 de `docs/pilotage-par-script.md`) doivent
parler la forme `v3` **sans perdre** la forme `v2`. Preuve : rejouer `doc-bench.sh` et les bancs
du chantier `marionnet-pilotage-par-script`.

**Ép. 7 — Conversion en lot.** `useful-scripts/mar2v3` : convertir *N* projets sans ouvrir la GUI
à la main. S'appuie sur le canal (`--control-socket`, `open` → `save` → `quit`) plutôt que sur un
binaire de conversion séparé — **aucune logique de format dupliquée**, donc rien qui puisse
diverger du chemin réellement emprunté par l'application.

**Ép. 8 — Compat descendante prouvée et message d'erreur.** Prouver au banc qu'un Marionnet `v2`
devant un `.mar` `v3` échoue **proprement** (il ne trouve pas ses fichiers, et ne passe donc
jamais de texte à `Marshal.from_file`) ; et qu'un Marionnet `v3` devant un `.mar` non identifié
dit quelque chose d'utile — chaîne **gettext**, donc les 12 catalogues sont touchés.

**Ép. 9 — Documentation et clôture.** Tranche « format de projet » de `docs/ARCHITECTURE.md`,
note de version destinée aux enseignants, puis clôture (MODE C du skill `chantier-long`).
*(Rien à retirer de `docs/TODO.md` : vérifié le 2026-08-09, le sujet n'y avait jamais été
consigné — il est né directement comme chantier.)*

## 6. Points de vigilance transverses

1. **L'ordre des attributs est signifiant** (cf. § 4.1). Toute représentation qui le perd — objet
   JSON, table de hachage — est fausse, même si elle « marche » sur les projets d'exemple.
2. **Le silence est l'ennemi.** Deux chemins avalent déjà les erreurs : `load_counters`
   (`try … with _ -> ()`) et `#eval_forest_attribute`, qui **ignore silencieusement** un attribut
   inconnu. Une migration incomplète peut donc produire un projet qui s'ouvre sans erreur *et*
   qui a perdu des données. Le banc de l'ép. 1 est la seule protection réelle.
3. **Ne pas confondre lecture et écriture.** Le chantier n'ajoute **que** de l'écriture `v3` ; il
   ne retire aucun chemin de lecture. La lecture `v0` (`Forest_backward_compatibility`) reste
   intouchée jusqu'à la clôture.
4. **`grep -a` reste l'outil d'audit** tant que des `v2` circulent : les chaînes OCaml
   apparaissent en clair dans le binaire, précédées de leur octet de longueur — piège connu,
   inclure ce préfixe dans le motif, sinon `c1` matche aussi `c1bis`.
5. **Interaction avec `marionnet-pilotage-par-script`** : ce chantier fournit l'instrument de
   mesure (ép. 1) et subit un contrecoup (ép. 6). Le chantier est clôturable mais pas clos ; si
   sa clôture intervient avant l'ép. 6, la dette passe ici.
6. **Interaction avec `modernisation-installation-marionnet`** : `yojson` devient une dépendance
   de build à déclarer dans les paquets.

## Journal d'avancement

### 2026-08-09 — Épisode 0 : officialisation

Chantier ouvert. Le sujet est venu d'une question de compréhension (« qu'est-ce que ce `Marshal`
dans les `.mar` ? ») qui a fait remonter un risque réel : le format ne se décrit pas lui-même, et
le code documente déjà des segfaults évités de justesse.

Trois décisions ont été prises avant toute conception : **JSON** (via `yojson`, déjà présent dans
le switch `5.4.1`, plutôt qu'`ocf` qui est une couche de configuration au-dessus) ; traitement
**hybride** des six attributs marshalés (désimbriquer + repli d'encodage) ; compat descendante par
**renommage des fichiers** en `v3`, reprenant la ruse déjà employée pour `v1`→`v2`. La divergence
de la copie vendored d'ocamlbricks est assumée : pas de remontée vers l'amont Launchpad.

Une conception préalable a été corrigée par la lecture du code : `Sexpr` d'ocamlbricks n'est pas
un sérialiseur, et l'inventaire compte **huit** fichiers et non sept — `states/ifconfig-counters`
a son propre schéma (`treeview_ifconfig.ml:315`), qu'on aurait manqué en raisonnant sur les seuls
treeviews.

Le découpage retenu place le **banc de non-régression avant la première ligne de code de
production** (ép. 1), et il s'appuie sur un instrument qui existe déjà : le canal de pilotage.
Sans ce filet, aucun des épisodes suivants ne serait vérifiable autrement qu'à l'œil.

Livrables : ce document, la fiche mémoire `migration-marshal-to-text`, le pointeur dans
`CLAUDE.md`. Aucun code touché.
