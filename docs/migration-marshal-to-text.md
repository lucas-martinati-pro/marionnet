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

**Ép. 1 — Le filet AVANT le code : corpus témoin et banc de non-régression** *(fait le
2026-08-09)*. Corpus de `.mar` **réels** désigné par l'auteur, banc de comparaison **sémantique**
— jamais octet-à-octet sur l'archive : ouvrir → dumper l'état **par le canal de pilotage** →
sauver → rouvrir → re-dumper → comparer. Point d'appui décisif : le chantier
`marionnet-pilotage-par-script` avait **déjà construit l'instrument de mesure**
(`useful-scripts/mrnctl`, son épisode 6). **Livré et vert** ; détail au § 7.

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

## 7. Le filet : corpus témoin et banc de non-régression (ép. 1)

### 7.1 Le corpus

Huit projets, dans `_claude-local/examples/` (hors dépôt, comme les bancs). Les neuf chemins
désignés par l'auteur s'y trouvaient **déjà** ; deux d'entre eux sont md5-identiques — le même
projet rangé dans deux répertoires de séance —, d'où **sept** projets distincts, plus un huitième
fabriqué (§ 7.3).

| projet | fichier `version` | ce qu'il apporte au filet |
|---|---|---|
| `m1m2m3-dhcpd-conf` | `v2` | le plus gros (649 Ko) |
| `projet-marionnet` | `v2` | 9 nœuds, `rc_config` de machine |
| `projet-marionnet-seance-7` | `v2` | 9 nœuds |
| `tp6c` | `v2` | 10 nœuds, `rc_config` de machine **et** de switch |
| `tp9` | `v2` | adressage IPv6 |
| `tp` | *absent* → pré-`v2` | `world_gateway` |
| `projet-marionnet-pour-seance-06` | *absent* → pré-`v2` | **routeur dont les 7 configurations Quagga sont renseignées et sélectionnées** (440 à 936 octets chacune) ; `cloud` ; defects non nuls |
| `worst-case` | `v2` (fabriqué) | cf. § 7.3 |

Aucun `v0` étiqueté. Les deux projets sans fichier `version` portent `states/ports` : ils sont donc
identifiés par le repli `try_to_understand_in_which_project_version_we_are` — précisément le
chemin que l'ép. 4 devra amender.

Le point le plus utile est que le corpus réel couvre **déjà** le morceau le plus délicat de la
migration : les six attributs re-marshalés *dans* le forest (ép. 5) sont tous représentés, les
sept configurations Quagga d'un routeur y compris. Il n'y avait rien à fabriquer de ce côté.

### 7.2 Le banc — `_claude-local/bench/marshal-bench.sh`

Il prouve **un** invariant : *ce que le canal de pilotage dit d'un projet ne change pas au travers
d'un cycle sauvegarde → relecture*. Il est vrai en `v2` aujourd'hui et devra l'être en `v3`. Il ne
compare jamais les octets de l'archive : le format a vocation à changer.

Par projet, sur une **copie** (les originaux sont irremplaçables — leur empreinte est relevée
avant et revérifiée après, c'est une assertion, pas une promesse) :

| phase | séquence | rôle |
|---|---|---|
| 0 | `open` → dump jeté → `save` → `close`, **itéré jusqu'au point fixe** | absorber les adaptations d'un vieux projet ; instantané `S0` |
| A | `open` → **dump A** → `save` → `close` | |
| B | `open` → **dump B** → `save` → `close` | parité opposée ; instantané `S2` |
| C | `open` → **dump C** → `close` | retour à la parité de A |

Quatre verdicts : **A == C** (strict, ordre compris) ; **A ≡ B** (au jeu de lignes près, pour
qu'un seul cycle ne perde aucun contenu) ; **les 8 fichiers** présents et non vides dans le `.mar`
sauvé ; **S0 == S2 octet à octet** sur les fichiers extraits.

Le dump interroge, dans l'ordre : `status`, `ls`, puis pour chaque composant — nœuds dans l'ordre
de `ls`, câbles lus dans le treeview `defects`, seul à les recevoir — `can`, `get`, `rc-get` et
`rc-get --field=<f>` pour chaque champ que la réponse déclare `available`, enfin les quatre
treeviews. `rc-get` est le **seul** chemin qui voit les six attributs marshalés : `get` les laisse
dans `omitted` (`control_server.ml:1425-1427`).

Un seul masquage, justifié : `/tmp/marionnet-<n>.dir`, puisqu'un répertoire de session est créé
par ouverture. **Contrôle de discriminance** : `ARM_DISCRIMINANCE=1` altère un label sans
l'enregistrer ; le banc échoue alors en nommant `get m1` dans son diff.

### 7.3 Le projet fabriqué — `_claude-local/bench/worst-case.sh`

Il ne refabrique **pas** ce que le corpus couvre déjà. Il ajoute ce qui manquait : la nature
`world_bridge`, des defects sur un **câble** (`leftward`/`rightward` — les sept n'en ont que sur
des ports de nœuds), un câble croisé, et du **texte adverse** partout où le canal peut en poser
(accents, guillemets typographiques et ASCII, contre-obliques, `%s`, accolades, tiret cadratin).
Il est écrit en shell et non en `.mrn` parce que deux valeurs ne sont connues qu'à l'exécution :
le nom des ports et le **fichier COW** qui identifie une ligne d'historique.

### 7.4 Ce que le filet ne couvre PAS (à ne pas croire couvert)

1. **`netmodel/dotoptions.marshal`** n'est publié par **aucune** commande du canal : la géométrie
   du sketch échappe au dump. Elle n'est tenue que par les assertions d'inventaire et d'idempotence
   octet-à-octet — lesquelles disparaîtront si l'ép. 4 change le format des deux côtés.
2. **`states/texts`** (treeview `documents`) est **vide dans tout le corpus**, et aucun verbe du
   canal ne l'alimente (ép. 5d du chantier pilotage : `documents` hors périmètre). Ce fichier
   migrera donc **sans témoin**.
3. **L'historique reste à un état par machine** : en créer plusieurs demande de démarrer un invité
   réel. Manque structurellement mineur — `states/states-forest` a le même type (`Row.t Forest.t`)
   que `defects`, dont la profondeur 3 est couverte.
4. **Les octets non-UTF-8 sont inatteignables par le canal** : `rc_content_is_servable`
   (`control_server.ml:1652`) les refuse, le canal répondant en JSON. **Le repli base64 du § 4.1
   ne peut donc pas être éprouvé par ce banc** — il faudra un `.mar` fabriqué à la main, ou la GUI.

### 7.5 Trois faits mesurés, qui dictent la forme du banc

1. **L'ordre des nœuds s'inverse à chaque cycle.** `netmodel/network.xml` alterne entre deux
   empreintes, de période 2, sur les huit projets ; les quatre treeviews, eux, ne bougent pas. Un
   banc qui comparerait **un** cycle échouerait donc toujours, sur du `v2` intact. D'où la mesure
   sur **deux** cycles, qui reste intégralement sensible à l'ordre — au lieu de trier, ce qui
   aurait aveuglé le filet sur une vraie réorganisation. *Conséquence pour l'ép. 4 : `v3` héritera
   de cette oscillation si rien n'est fait ; la corriger est possible mais ce serait un changement
   de comportement, à décider explicitement.*
2. **Enregistrer aussitôt après l'ouverture n'écrit pas la même chose** qu'enregistrer un peu plus
   tard : `dotoptions.marshal` part alors avec `gui_callbacks_disable = "true"`, c'est-à-dire
   l'état **transitoire** de la restauration (`Sketch.tuning`, ép. 7 du chantier pilotage), la
   réaction de persistance n'ayant pas encore été rétablie. Chaque phase du banc rejoue donc
   exactement la même séquence, dump compris.
3. **`states/ifconfig-counters` change à chaque enregistrement, sur 4 octets et 4 seulement** :
   `_OBSOLETE_mac_address_as_int` (`treeview_ifconfig.ml:313-317`) est tiré au hasard. Le banc
   n'exige donc pas l'égalité du fichier mais que **seuls ces 4 octets** diffèrent — plus fort,
   puisque cela prouve que les deux compteurs vivants (IPv4, `Int64` IPv6) ont survécu au cycle.
   Le fichier fait 39 octets : en-tête `Marshal` (20), `0xb0` bloc de 3 champs, `0x02` CODE_INT32,
   les 4 octets de l'entier, `0x41` (petit entier 1), puis l'`Int64` custom `_j`.

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

### 2026-08-09 — Épisode 1 : le filet, avant le code

**Aucune ligne de code de production.** Le corpus est constitué, le banc est écrit, et il est vert
— 41 assertions, 0 échec sur 8 projets (`_claude-local/bench/runs/20260809-215517-1-marshal/`).
Conception détaillée au § 7 ; ce journal ne retient que ce qui a **changé** par rapport au plan.

**Le prérequis bloquant est tombé sans travail.** Les neuf chemins désignés par l'auteur étaient
déjà tous dans `_claude-local/examples/` — deux étant md5-identiques, cela fait sept projets
distincts. Mieux : le corpus réel couvre **déjà** le morceau le plus délicat de la migration, les
sept configurations Quagga d'un routeur, renseignées et sélectionnées. Le projet à fabriquer s'est
donc réduit à ce qui manquait vraiment (`world_bridge`, defects de **câble**, câble croisé, texte
adverse) au lieu du décor complet que l'ép. 0 imaginait.

**Le banc a d'abord échoué sur du `v2` intact, trois fois, et c'est ce qui l'a fait.** Chaque échec
a été instrumenté plutôt que contourné, et chacun a livré un fait durable (§ 7.5) :

1. comparer **un** cycle est impossible — l'ordre des nœuds s'inverse à chaque enregistrement
   (période 2). La réponse n'a pas été de **trier** les composants, ce qui aurait aveuglé le filet
   sur une vraie réorganisation, mais de mesurer **deux** cycles, en gardant l'ordre dans la
   comparaison ;
2. `dotoptions.marshal` bougeait entre deux enregistrements. En cause : enregistrer aussitôt après
   l'ouverture fige `gui_callbacks_disable = "true"`, l'état **transitoire** de la restauration.
   Chaque phase du banc rejoue donc la même séquence — dump compris, même quand il est jeté ;
3. `states/ifconfig-counters` change à **chaque** enregistrement, sur 4 octets : un champ déclaré
   obsolète, tiré au hasard. L'assertion n'a pas été retirée mais **resserrée** — seuls ces 4
   octets ont le droit de bouger, ce qui prouve la survie des deux compteurs vivants.

**Un quatrième échec n'était pas un artefact de mesure mais un vrai défaut**, hors périmètre :
un routeur naît avec le noyau `3.2.64-ghost`, que Marionnet lui-même juge inutilisable sur cet
hôte. Le banc l'a d'abord vu comme une adaptation « résiduelle » à la deuxième ouverture d'un
projet déjà normalisé, puis l'a **reproduit sur un projet neuf** fabriqué par le canal — ce qui a
écarté l'hypothèse « vieux fichier » et désigné le constructeur. Analyse et deux voies de
correction dans `docs/TODO.md`. Le banc, lui, itère sa normalisation **jusqu'au point fixe** et
rapporte le nombre de passes : le défaut reste visible au lieu d'être noyé dans un « on ouvre deux
fois ».

**Ce que le filet ne tiendra pas** est écrit noir sur blanc au § 7.4, parce qu'un filet dont on
croit à tort qu'il couvre tout est pire que pas de filet : `dotoptions.marshal` n'est publié par
aucune commande du canal, `states/texts` est vide dans tout le corpus et inalimentable, et le
**repli base64 du § 4.1 ne peut pas être éprouvé ici** — le canal refuse le non-UTF-8. L'ép. 2
devra donc porter ses propres tests de round-trip sur octets bruts.

Enfin, la discriminance a été vérifiée plutôt que supposée : `ARM_DISCRIMINANCE=1` altère un label
sans l'enregistrer, et le banc échoue en nommant `get m1` dans son diff.

Livrables : `_claude-local/bench/marshal-bench.sh`, `_claude-local/bench/worst-case.sh` et
`_claude-local/examples/worst-case.mar` (tous hors dépôt, comme les huit bancs du chantier
`marionnet-pilotage-par-script` — décision de l'auteur) ; côté versionné, le § 7 de ce document,
son journal, l'entrée de `docs/TODO.md` et le pointeur de `CLAUDE.md`.
