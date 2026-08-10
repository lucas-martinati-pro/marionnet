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
| Repli base64 | **paquet opam `base64`** (3.5.2), installé à l'ép. 2 — pas une implémentation maison | décision de l'auteur (2026-08-09), la question ayant été posée précisément parce qu'elle ajoute un **second** paquet au packaging (cf. § 6.6). Une implémentation locale aurait mis ~35 lignes de RFC 4648 à maintenir dans une copie *vendored* |
| Les 6 attributs marshalés *dans* le forest | **hybride** : les désimbriquer, avec un **repli d'encodage** pour tout résidu | le format devient réellement lisible là où ça compte (config Quagga d'un routeur), sans risquer une perte de projet en séance |
| Compat descendante | **nouveaux noms de fichiers en `v3`** | ruse maison déjà éprouvée pour `v1`→`v2` : un vieux binaire ne **trouve** pas les fichiers, donc ne passe jamais d'octets étrangers à `Marshal.from_file` |
| ocamlbricks amont | la divergence de la copie vendored est **assumée** — pas de remontée du patch vers Launchpad | décision de l'auteur (2026-08-09) |
| Conteneur `.mar` | **inchangé** | hors périmètre |

**Correction d'un a priori.** `lib/STRUCTURES/sexpr.mli` d'ocamlbricks n'est **pas** un
sérialiseur : c'est une algèbre de produits typés (GADT `Atom | Cons`), sans `to_string` ni
`of_string`. Rien n'y est réutilisable pour ce chantier.

## 4. Schémas JSON proposés (à figer à l'épisode 2)

> **§ 4.1 figé le 2026-08-09** par l'épisode 2, qui l'a implémenté — tel qu'écrit ici, à trois
> précisions près, consignées au § 8.1. **§ 4.2 et § 4.3 figés le 2026-08-09** par l'épisode 3,
> également tels qu'écrits ici, aux précisions du § 9.3 près. **Les trois schémas sont donc figés.**

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

**Ép. 3 — Le codec des treeviews et des compteurs** *(fait le 2026-08-09)*. Schémas § 4.2 et
§ 4.3, **figés**. Le codec n'a **pas** atterri dans `bin/treeview.ml` comme annoncé ici : la
donnée d'un treeview (`Row_item`, `Row`) a déménagé dans `bin/treeview_row.ml` — sans Gtk+, donc
testable —, les compteurs dans `bin/treeview_counters.ml`, et la plomberie JSON commune aux
**trois** codecs dans `lib/STRUCTURES/json_bricks.ml`. Détail au § 9.
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

**Ép. 5 — Désimbriquer les huit attributs binaires** *(fait le 2026-08-10 ; **six** annoncés ici,
**huit** mesurés à l'ép. 4 — cf. § 10.4 et § 11)*. Aujourd'hui, six attributs sont
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

**Ép. 8 — Compat descendante prouvée et message d'erreur.** Scindé en deux, parce que les deux
moitiés n'ont ni la même nature ni le même périmètre : la première ne produit **aucun code**, la
seconde touche `bin/state.ml` **et** les 12 catalogues.

- **Ép. 8a — la preuve** (§ 13) : prouver au banc qu'un Marionnet `v2` devant un `.mar` `v3` échoue
  **proprement** (il ne trouve pas ses fichiers, et ne passe donc jamais de texte à
  `Marshal.from_file`). Le témoin n'est pas une simulation : c'est un **vrai binaire** construit
  depuis `a4055b1`, piloté par le canal. **Fait le 2026-08-10.**
- **Ép. 8b — le message** (§ 14) : un Marionnet `v3` devant un `.mar` non identifié disait
  « Failed loading the project / Please ensure that the file be well-formed » (`state.ml:625`), ce
  qui est **faux** pour un fichier parfaitement formé mais plus récent. Exception dédiée + deux
  messages **gettext** distincts, donc les 12 catalogues touchés. **Fait le 2026-08-10.**

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
6. **Interaction avec `modernisation-installation-marionnet`** : `yojson` **et `base64`** deviennent
   des dépendances **de build** (`lib/dune`, ép. 2) — pas d'exécution, les bibliothèques OCaml
   étant liées statiquement (vérifié par `ldd`). Elles sont **déjà** dans `OPAM_PACKAGES` du
   `Makefile`, la source de vérité des dépendances (§ 2.4 bis du doc de l'autre chantier), donc
   `make dependencies` les couvre ; reste à les répercuter là où la voie **système** remplace
   opam — `Build-Depends` du `.deb`, `BuildRequires` du RPM, image de build Docker. Équivalents
   Debian vérifiés : `libyojson-ocaml-dev`, `libbase64-ocaml-dev`.

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

## 8. Le codec du forest (ép. 2)

`lib/STRUCTURES/xforest.ml`, à la suite du couple `encode`/`decode` historique — le codec
appartient à la structure qu'il sérialise. Le module gagne au passage l'**interface qui lui
manquait**, `lib/STRUCTURES/xforest.mli` (§ 8.4) ; la surface publique du codec est :

```ocaml
val to_JSON_string : t -> string
val of_JSON_string : string -> (t, string) result
val to_JSON_file   : t -> string -> unit
val of_JSON_file   : string -> (t, string) result
```

`Result` sur les deux lectures, conformément au style visé pour le code neuf ; en interne le
décodage lève une exception privée `Malformed`, rattrapée au bord — l'alternative, un `bind`
monadique traversant listes et arbres, aurait été illisible, et `let*` est **interdit ici** (piège
déjà payé à l'ép. 4d du chantier `marionnet-pilotage-par-script` : `camlp4` ne le connaît pas, et
tout `lib/` passe par `camlp4of`).

**Asymétrie assumée sur les fichiers** : `to_JSON_file` **laisse remonter** une erreur d'E/S — un
projet qui ne peut pas être enregistré doit se signaler bruyamment, comme le fait le chemin
`Marshal` qu'il remplace —, tandis qu'`of_JSON_file` la **retourne** : un fichier absent ou
illisible est un cas ordinaire, que l'appelant traitera avec les échecs de décodage.

### 8.1 Les trois précisions que le § 4.1 ne portait pas

1. **Le repli base64 vaut pour toute chaîne**, pas seulement pour la valeur d'un attribut : un
   **tag** et un **nom** d'attribut y passent aussi. Ils sont des identifiants du code, donc en
   pratique de l'ASCII ; mais un trou là aurait produit un fichier invalide tout autant, pour un
   coût de zéro ligne.
2. **L'enveloppe est vérifiée à la lecture** : `format` doit valoir `marionnet/xforest`, `version`
   doit valoir `3`. Une version future est refusée **en la nommant**
   (`unsupported version 4 (this binary understands 3)`) — c'est très exactement ce qu'un format
   auto-descriptif achète, là où `Marshal.from_file` déréférençait au hasard.
3. **Les trois membres d'un arbre sont requis** (`tag`, `attrs`, `children`). Reconstruire un
   membre absent — lire un `children` manquant comme une forêt vide — réintroduirait l'à-peu-près
   silencieux que ce format est là pour supprimer (§ 6.2).

Deux choix de forme, enfin : la sortie est **indentée** (`pretty_to_string ~std:true`) et terminée
par un saut de ligne. Un projet *diffable* est l'une des raisons d'être du chantier ; `~std:true`
écarte les extensions propres à yojson.

### 8.2 Le fait mesuré qui change la nature du repli base64

Mesure faite avant d'écrire le codec, sur `yojson` 3.0.0 : **yojson écrit les octets non-UTF-8
verbatim et les relit à l'identique**. Autrement dit, un codec *sans* repli aurait un round-trip
parfait — et produirait des fichiers qu'aucun autre outil ne sait lire.

Le repli n'est donc **pas** une protection contre la perte de données, comme le § 4.1 le laissait
entendre : c'est la seule façon d'émettre un texte qui soit du **JSON valide**, ce qui est l'objet
même de la migration. Conséquence directe sur la forme des tests : l'invariant « ce qui entre
ressort » ne suffit pas à les rendre discriminants, il faut lui adjoindre « **le texte produit est
de l'UTF-8 valide** ».

Corollaire sur le validateur : c'est le décodeur de la bibliothèque standard
(`String.get_utf_8_uchar`, `Uchar.utf_decode_is_valid`) qui décide, et non un test maison — il
rejette aussi les **encodages surlongs** (`C0 80`) et les **surrogates** (`ED A0 80`), que les
validateurs écrits à la main laissent passer. Les deux cas sont au banc.

### 8.3 Les tests — dans le dépôt, cette fois

`test/xforest_json.ml`, joué par `dune test` (la stanza `test/dune` devient `tests`, deux
programmes indépendants). **Divergence assumée avec l'ép. 1**, dont le banc est hors dépôt : le
banc de l'ép. 1 exige la GUI, un corpus de `.mar` et plusieurs minutes ; ces tests-ci sont purs et
tiennent en une seconde, exactement comme `test/marionnet.ml` déjà versionné. Un commit d'épisode
de ce chantier ne porte donc plus seulement `docs/`.

53 assertions. D'abord **l'instrument lui-même** : le banc porte son **propre** validateur UTF-8,
écrit à la main, et 15 assertions le mettent à l'épreuve (surlongs, surrogates, séquences
tronquées, au-delà de U+10FFFF). Ce n'est pas de la coquetterie — voir § 8.4, c'est l'interface
qui a révélé le défaut. Puis le codec : forêt vide, tag/nom/valeur vides, UTF-8 accentué avec guillemets et sauts de
ligne, octets bruts en valeur **et** en tag **et** en nom d'attribut, surlong, surrogate, ordre
des attributs **et doublons de clés**, forêt profonde à plusieurs racines, aller-retour par
fichier ; puis les échecs, qui doivent être **rapportés** et non devinés : JSON mal formé, racine
qui n'est pas un objet, format inconnu, version future, membre manquant, `attrs` écrit comme un
objet (l'erreur qu'un humain bien intentionné commettra), paire d'attribut à trois éléments,
base64 invalide, fichier absent.

**Discriminance mesurée**, pas supposée : le repli désarmé (`json_of_string` rendant toujours une
chaîne JSON), **7 assertions tombent** — et, révélateur, **les round-trips passent tous**. C'est
la démonstration du § 8.2 : un banc bâti sur le seul aller-retour aurait certifié un codec cassé.

**Preuve externe**, indépendante de yojson : le fichier produit pour un projet portant à la fois
un nom accentué et un `rc_config` marshalé est relu par le module `json` de `python3` sans erreur, et rend
`[['name', 'café'], ['rc_config', {'b64': 'hJWmvQE='}]]` — c'est-à-dire la lisibilité recherchée,
le blob binaire restant **explicitement** désigné comme tel.

### 8.4 L'interface — et la circularité qu'elle a révélée

`lib/STRUCTURES/xforest.mli` n'existait pas : tout le module était exporté de fait. Il existe
maintenant, et publie exactement ce que le dépôt utilise — les types (transparents : on construit
un nœud comme un couple), la classe `interpreter`, `print_xforest`, `encode`/`decode` et les
quatre fonctions du codec. Restent **privés** les seize noms de l'implémentation : `json_format`,
`json_version`, l'exception `Malformed`, `is_valid_utf_8`, et toutes les fonctions de conversion
vers et depuis `Yojson.Safe.t`. Vérifié plutôt que supposé : `Xforest.is_valid_utf_8`,
`Xforest.json_of_string`, `Xforest.forest_of_json` et `Xforest.json_version` sont désormais
`Unbound value` depuis un appelant.

Le gain d'abstraction se lit dans les signatures : **`yojson` n'y apparaît nulle part**. La
bibliothèque JSON redevient un détail d'implémentation — un appelant ne manipule jamais de valeur
JSON, seulement des chaînes et des `result`.

**Écrire l'interface a mis au jour un défaut du banc de l'ép. 2**, que la relecture n'avait pas vu :
il vérifiait « la sortie est de l'UTF-8 valide » avec `Xforest.is_valid_utf_8`, c'est-à-dire avec
**le prédicat même qui décide du repli**. Circulaire : un prédicat faux aurait rendu le codec *et*
son banc faux **d'un même mouvement**, sans qu'aucune assertion ne bronche. Corrigé en écrivant
dans `test/xforest_json.ml` un validateur **indépendant**, décodant à la main, lui-même éprouvé
par 15 assertions. La discriminance a été **remesurée** après ce remplacement — repli désarmé, les
mêmes 7 assertions tombent —, sans quoi on aurait échangé un banc circulaire contre un banc
laxiste.

Au passage, la question « qu'est-ce qui mérite d'être public ? » a tranché toute seule le sort de
`is_valid_utf_8` : elle n'avait qu'un seul appelant hors du module, le banc — précisément celui
qui n'aurait jamais dû s'en servir.

### 8.5 Ce que l'épisode 2 ne fait PAS

Rien n'est branché. `state.ml`, `user_level.ml` et `sketch.ml` écrivent et lisent toujours du
`Marshal` ; aucun `.mar` produit par ce code n'a changé d'un octet. Le codec est une brique
disponible, éprouvée isolément — le branchement est l'ép. 4, après le codec des treeviews (ép. 3).

## 9. Le codec des treeviews et des compteurs (ép. 3)

Deux schémas de plus, donc **les trois** du § 4 sont écrits ; toujours **rien de branché**. Mais
l'épisode a surtout tranché une question que le § 5 avait posée de travers : *où* le codec vit.

### 9.1 Le codec ne pouvait pas vivre dans `bin/treeview.ml`

Le § 5 annonçait le codec « dans `bin/treeview.ml` ». Impossible d'y tenir la propriété acquise à
l'ép. 2 — **des tests unitaires versionnés, joués par `dune test`** : `treeview.ml` est un widget
Gtk+ de l'**exécutable**, et une stanza `(tests)` ne peut lier que des **bibliothèques**. Le codec
y aurait donc été prouvé par le seul banc de l'ép. 1 (GUI, corpus, plusieurs minutes) — pour un
chemin de chargement qui, précisément, **avale ses erreurs**.

D'où le déplacement : `Row_item` et `Row` — la **donnée** d'un treeview, qui n'a jamais eu besoin
de Gtk+ — vivent dans `bin/treeview_row.ml`, module de la bibliothèque **`marionnet_base`**
(`wrapped false`, sans lablgtk), avec le codec. Les compteurs suivent dans
`bin/treeview_counters.ml`. `treeview.ml` conserve les **noms historiques** :

```ocaml
module Row_item = Treeview_row.Row_item
module Row      = Treeview_row.Row
```

si bien qu'**aucun des 7 fichiers** qui parlent de `Treeview.Row_item` / `Treeview.Row`
(`treeview_{ifconfig,defects,history,documents}.ml`, `router.ml`, `control_server.ml`,
`treeview.ml`) n'a changé d'une ligne. Un alias de module préserve types, sous-modules et
égalités : le foncteur `Row.Make_field_accessors` et les trois `Row_item.*_prj_inj` restent
accessibles par leur ancien chemin.

Pas de `.mli` pour ces deux modules, contrairement à `json_bricks` : la convention du dépôt est
d'en écrire pour les modules « bibliothèque » et l'ép. 2b a montré ce que l'exercice révèle — mais
ici le déplacement de `Row`/`Row_item` est à **iso-code**, et leur doter d'une interface (type de
module `Projection_injection`, trois `*_prj_inj`, le foncteur et ses égalités `with type a = …`)
aurait mêlé à cet épisode un changement d'abstraction qui n'est pas le sien. La discipline qu'on
tenait à préserver — le piège du repli base64 énoncé et testé une fois, hors de portée de ses
appelants — est portée par `json_bricks.mli`, là où elle vit désormais.

**Point de non-régression vérifié et non supposé** : déplacer un type de somme d'un module à un
autre ne change **pas** la représentation `Marshal` — l'encodage porte des tags de blocs, jamais
des chemins de modules. Les `.mar` `v0`/`v1`/`v2` existants se relisent donc à l'identique, ce que
le banc de l'ép. 1 confirme (8 projets, cf. journal).

### 9.2 La plomberie JSON était en train d'être écrite trois fois

Le codec de l'ép. 2 portait, mêlée à lui, la partie **dure** du format : le validateur UTF-8 de la
stdlib, le repli base64 et le piège qu'il évite (JSON n'a pas d'échappement d'octet), l'exception
`Malformed`, `kind_of_json`, `member_of`, le contrôle de l'en-tête `format`/`version`, la lecture
et l'écriture de fichier. Les treeviews en avaient besoin ; les compteurs aussi. **Trois
exemplaires du même piège, c'est trois endroits à corriger si l'un est faux** — exactement la
dérive que ce chantier combat.

D'où `lib/STRUCTURES/json_bricks.ml` + `.mli` (neuf) : *la* couche JSON du dépôt. `Xforest` s'y
adosse (l'ép. 2 a été refactoré, ses 4 fonctions publiques inchangées), les deux codecs de `bin/`
aussi. L'énoncé du piège, sa documentation et son test sont **uniques**.

Contrepartie **assumée** : `yojson` apparaît dans cette interface (`Yojson.Safe.t` dans les
signatures de `json_of_string`, `member_of`, `of_text`…). L'invariant de l'ép. 2b reste vrai là où
il avait un sens — `xforest.mli` ne mentionne toujours pas `yojson`, et un appelant du codec ne
manipule jamais de valeur JSON — mais le dépôt a désormais **une** interface qui l'expose, et c'est
celle dont le rôle *est* d'être la couche JSON. Corollaire de build : `yojson` est nommé dans les
`(libraries …)` de `marionnet_base` (`bin/dune`), les sources y construisant des valeurs JSON — il
ne suffit pas de l'hériter d'`ocamlbricks`.

### 9.3 Les deux schémas, et les précisions que le § 4 ne portait pas

Le § 4.2 est implémenté tel quel, avec trois précisions :

1. **Ce qui est enregistré n'est pas la forêt seule** mais le couple `(next_identifier, forest)` —
   le compteur d'identifiants frais voyage avec les lignes qu'il a numérotées. Il est un membre à
   part entière (`"next_identifier": 42`), et son absence est une **erreur**, jamais un `1` deviné.
2. **Les deux membres d'une ligne sont requis** (`fields`, `children`), comme les trois d'un arbre
   à l'ép. 2. Un `children` absent lu comme « pas d'enfants » serait une approximation silencieuse
   — et les enfants d'une ligne, dans `states-forest`, sont les **états de disque** d'une machine.
3. **Un `kind` inconnu est refusé en le nommant.** Se rabattre sur `string` mettrait une valeur du
   mauvais type dans une colonne du widget : c'est la forme même du défaut B6 du chantier
   `marionnet-automate-composants`.

Un champ est une **paire dans un tableau**, jamais un membre d'objet JSON — même raison qu'au
§ 4.1 : une ligne est une liste d'association, dont un objet JSON perdrait l'ordre et les
doublons. Les noms de champs comme les valeurs `string`/`icon` passent par le repli base64
(`{"b64": …}`) : une ligne porte réellement des octets quelconques (un commentaire tapé dans
l'invité, un nom de fichier dans une locale oubliée).

Le § 4.3 est implémenté tel quel, avec une précision qui est un **choix** : `next_ipv6_address_as_int`
voyage en **chaîne, et en chaîne seulement**. Accepter *aussi* un nombre JSON à la lecture rendrait
la relecture dépendante de la forme qu'un producteur a choisie — et un nombre JSON ne peut pas
porter un `Int64` (au-delà de 2^53, tout lecteur qui suit la norme perd les bits de poids faible).
Le champ obsolète `_OBSOLETE_mac_address_as_int` est conservé, tiré au hasard à chaque
enregistrement comme aujourd'hui : ce chantier n'est pas l'endroit pour retirer un champ d'un
fichier que des binaires plus anciens lisent.

### 9.4 Les tests, et la discriminance remesurée

`test/treeview_json.ml` (**74 assertions**), joué par `dune test` avec les deux autres programmes
— **134 assertions, 0 échec**. Même forme qu'à l'ép. 2 : l'**instrument d'abord** (24 assertions
sur le validateur UTF-8), puis les aller-retours (les trois sortes d'item, ligne vide, champs
vides, UTF-8 accentué avec guillemets et sauts de ligne, octets bruts en valeur **et** en nom de
champ **et** en icône, surlong, surrogate, ordre des champs **et doublons**, forêt à trois niveaux
et plusieurs racines, `next_identifier`, aller-retour par fichier), puis **les échecs, un par un**,
dont les messages sont vérifiés : JSON mal formé, racine non-objet, `format` d'un autre fichier du
même `.mar`, version future nommée, `next_identifier` manquant ou écrit en chaîne, `fields` ou
`children` manquant, `fields` écrit comme un objet, champ à trois éléments, `kind` inconnu, `value`
manquante, checkbox non booléenne, base64 invalide, fichier absent. Puis les compteurs : bornes de
l'`Int64` (max, négatif), forme chaîne exigée, entier non analysable, membre manquant, format
croisé, version future, fichier absent.

Le validateur UTF-8 indépendant — celui qui rend ces tests discriminants — est passé dans
`test/utf_8_reference.ml`, **partagé** par les deux programmes de test : une seule référence, et
surtout **jamais** le prédicat qu'utilise le codec (cf. § 8.4, c'est le défaut que l'écriture de
l'interface avait révélé à l'ép. 2).

**Discriminance mesurée deux fois**, pas supposée :

| Désarmement | Ce qui tombe |
|---|---|
| repli base64 neutralisé (`json_of_string` rend toujours une chaîne JSON) | **5** assertions du nouveau banc — *et les 7 de l'ép. 2, inchangées*. **Tous les round-trips passent.** |
| compteur 64 bits accepté aussi comme nombre JSON | **1** assertion (« rejeté quand il est écrit en nombre ») |

**Preuve externe**, indépendante de yojson : les deux fichiers produits (une ligne portant un nom
accentué, une icône, une checkbox et un commentaire binaire ; des compteurs à `Int64.max_int`) sont
décodés en **UTF-8 strict** puis relus par le module `json` de `python3` sans erreur, et rendent
bien `["Comment", {"kind": "string", "value": {"b64": "hJWmvQH/"}}]` et
`"next_ipv6_address_as_int": "9223372036854775807"` — la lisibilité recherchée, le binaire
**explicitement** désigné comme tel.

### 9.5 Ce que l'épisode 3 ne fait PAS

Rien n'est branché, une troisième fois. `treeview.ml` enregistre toujours par
`next_identifier_and_content_forest_marshaler#to_file`, `treeview_ifconfig.ml` par
`counters_marshaler#to_file`, et aucun `.mar` produit n'a changé d'un octet. Le branchement — les
huit chemins de `state.ml`, la détection de version et la bascule `closing_project_version` — est
l'ép. 4, et c'est **là** que se posera la question laissée ouverte : `v3` hérite-t-il de
l'inversion d'ordre des nœuds à chaque cycle (§ 7.5, fait n° 1) ou la corrige-t-on ?

## 10. Le branchement : `v3` écrit et relu (ép. 4)

> **Fait le 2026-08-09.** Depuis cet épisode, **tout `.mar` que Marionnet écrit est du `v3`** :
> huit fichiers de texte, dont sept en JSON. La lecture `v0`/`v1`/`v2` est intacte, ligne pour
> ligne — aucun chemin de lecture n'a été retiré.

### 10.1 Les huit chemins, et le seul endroit où la version se décide

Le branchement lui-même est mécanique et tient en quatre gestes, tous commandés par le **type**
`[ `v0 | `v1 | `v2 | `v3 ]` — c'est lui qui a fait apparaître, à la compilation, les six endroits
qui décident (`state.ml`, `user_level.ml{,i}`, `sketch.ml{,i}`, `treeview.ml`,
`treeview_ifconfig.ml`) :

| Où | Ce qui change |
|---|---|
| `state.ml` (`project_paths`) | deux chemins neufs, `networkFile_json` et `dotoptionsFile_json` ; les anciens **restent**, ils servent à la lecture d'un vieux projet |
| `state.ml` | `opening_project_version` reconnaît `"v3"` ; `closing_project_version` **devient** `` `v3 `` ; l'ouverture choisit le fichier selon la version lue |
| `treeview.ml` | `#json_filename` = radical + `.json` ; `#save` y écrit par `Treeview_row.Json`, `#load` y lit quand le projet est `v3` |
| `treeview_ifconfig.ml` | `#json_counters_filename`, le repli de détection de version, et le choix du fichier `v0`/`v1`/`v2`/`v3` |

Deux détails que le § 2 ne pouvait pas porter :

- **le fichier de compteurs se nomme d'après le radical**, jamais d'après le fichier de forest :
  `states/ifconfig-counters.json`, et non `ifconfig.json-counters`. C'est ce que faisait déjà la
  version `Marshal`, et c'est le nom annoncé au § 2 ;
- **le repli de détection teste le `.json` en tête** (`try_to_understand_in_which_project_version_we_are`).
  Sans cela un `.mar` `v3` dont le fichier `version` est absent ou illisible serait rapporté `v2`
  — deux projets du corpus passent réellement par ce chemin.

### 10.2 Ce que le branchement seul aurait laissé faux : les fichiers `v2` survivants

Un projet ouvert en `v2` conserve ses anciens fichiers dans le **répertoire de travail**, et
l'archive est faite de ce répertoire. Écrire les `.json` à côté d'eux aurait produit un `.mar`
portant **les deux formes**, dont l'une périmée — et la décision « compat descendante par
renommage » (§ 3) serait devenue fausse au moment même où on la mettait en œuvre : un vieux
binaire lit `version` = `"v3"`, ne comprend pas, **tombe sur son propre repli de détection**,
trouve `states/ifconfig` et ouvre sans un mot l'état d'**avant**. Silencieusement faux, ce que
tout ce chantier cherche à supprimer.

D'où, **décision de l'auteur (2026-08-09)** : les fichiers de données `v2` (et `v0`/`v1`) sont
**supprimés du répertoire de travail** juste avant la construction de l'archive
(`project_paths#legacy_data_files`, lu par `save_project`). Ce n'est pas un geste nouveau dans ce
code : `treeview_ifconfig#load` supprime déjà `states/ports` après l'avoir lu.

### 10.3 La question laissée ouverte, tranchée

**L'inversion d'ordre des nœuds est conservée** — décision de l'auteur (2026-08-09). Elle ne vient
pas du format mais du couple `#to_forest` / `from_tree` du modèle, elle est identique en `v2`, et
la corriger ici aurait mélangé un changement de comportement du modèle avec le branchement d'un
format. Le banc, qui mesure sur **deux** cycles, en reste insensible. Le sujet part dans
`docs/TODO.md`, avec son vrai argument : un fichier de projet **diffable** est une des raisons
d'être de ce chantier, et un ordre qui alterne rend tout diff illisible.

### 10.4 Deux faits mesurés, dont un qui corrige le § 5

**Les attributs marshalés dans le forest sont HUIT, pas six.** Le § 5 (ép. 5) en annonce six —
`rc_config` de machine et de switch, quatre champs Quagga du routeur. Le premier `dotoptions.json`
écrit par le binaire en montre **deux de plus** : `shuffler` et `invertedCables`
(`sketch.ml:281,288`, encodés par `Xforest.encode`, c'est-à-dire `Marshal`). Ils sont dans le
**deuxième** fichier, celui que le canal de pilotage ne publie pas — l'angle mort désigné au
§ 7.4. L'ép. 5 devra donc les traiter, ou dire pourquoi il ne le fait pas.

**L'ép. 6 dépend de l'ép. 5, pas de l'ép. 4.** Le serveur de contrôle reconnaît un champ `rc_config`
à l'**en-tête magique de `Marshal`** de sa valeur (`control_server.ml:1438`) : cette valeur reste
marshalée **en mémoire**, seul son transport dans le fichier change (elle y voyage en base64,
n'étant pas de l'UTF-8 valide). Mesuré, pas supposé : `rc-bench.sh` rejoué **bout en bout** — les
sept configurations Quagga posées par le canal, un routeur réellement démarré, `/etc/quagga/zebra.conf`
lu dans l'invité — est **vert sans une ligne touchée au serveur** (102 assertions). C'est la
désimbrication de l'ép. 5 qui rendra l'ép. 6 nécessaire.

### 10.5 La preuve

- **Le banc de l'ép. 1, vert** : `marshal-bench.sh`, **49 assertions, 0 échec** sur les 8 projets
  du corpus. Chacun est ouvert en `v2`, converti par `save-as`, puis **relu quatre fois en `v3`** :
  c'est exactement la fin d'épisode annoncée au § 5 (« ouvrir un `v2` → sauver → rouvrir »), et le
  round-trip sémantique strict par le canal (jusqu'à 72 requêtes par projet) est **identique** à
  celui mesuré avant le branchement.
- **Deux assertions neuves au banc**, parce que le format a changé sous lui : l'inventaire porte
  désormais sur les huit noms `v3`, et une assertion **inverse** exige qu'**aucun** fichier `v2` ne
  subsiste dans l'archive (§ 10.2). L'idempotence octet-à-octet, elle, ne pouvait plus se mesurer
  sur « 4 octets à position fixe » : le champ obsolète est maintenant une ligne de JSON, dont la
  longueur varie avec la valeur tirée au hasard — la comparaison masque **cette ligne, et elle
  seule**, dans les deux fichiers, et exige que tout le reste soit identique (assertion inchangée
  dans son fond, plus forte que « le fichier a changé »).
- **Preuve externe** : les **112 fichiers `.json`** produits par le binaire pendant le banc sont
  relus par le module `json` de `python3` en **UTF-8 strict** — 0 invalide. Un projet de TP réel
  est désormais un texte que n'importe quel outil lit.
- **Les trois bancs du chantier `marionnet-pilotage-par-script` qui inspectent le `.mar`**, rejoués
  et verts : `components-bench.sh` (134), `treeview-bench.sh` (160), `rc-bench.sh` (102, **en mode
  bout en bout**). Ils ont été adaptés aux noms `v3` ; le seul changement de fond est celui décrit
  au § 10.4 (chercher un `rc_config` dans le `.mar` demande maintenant de décoder son base64).
- `dune build` et `dune test` (**134 assertions, 0 échec**) inchangés : les codecs n'ont pas bougé.

### 10.6 Ce que l'épisode 4 ne fait PAS

Il ne **désimbrique** rien : les huit attributs binaires du § 10.4 voyagent en base64, donc
lisibles par un outil mais pas *lisibles par un humain* — c'est l'ép. 5. Il ne touche pas au canal
(ép. 6), ne prouve pas la compat descendante côté **vieux binaire** (ép. 8 ; ici on prouve
seulement que le `.mar` ne lui offre plus de piège), et ne convertit rien en lot. Enfin, le
`try … with _ -> ()` de `load_counters` **reste** un chemin qui avale : il **journalise**
désormais ce qu'il rattrape, ce qui ne remplace pas les tests unitaires de l'ép. 3 — cela les
justifie.

## 11. La désimbrication des huit attributs (ép. 5)

Depuis l'ép. 4 un `.mar` est du texte, mais huit de ses attributs restaient des vidages `Marshal`
*à l'intérieur* du forest, transportés en base64 : lisibles par un outil, illisibles par un
humain. Cet épisode les défait. **Aucun attribut d'un `.mar` écrit par ce binaire n'est plus
marshalé** ; la lecture des huit anciennes clés est **intacte**, et reste écrite en premier dans
chaque `#eval_forest_attribute`.

### 11.1 Les huit attributs, et la forme retenue

| Où | Ancienne clé (`v0`/`v1`/`v2`) | Type OCaml | Clés `v3` |
|---|---|---|---|
| `machine.ml` | `rc_config` | `bool * string` | `rc_config_active`, `rc_config_file` |
| `switch.ml` | `rc_config` | `bool * string` | `rc_config_active`, `rc_config_file` |
| `router.ml` | `rc_config_unix` | `bool * string` | `rc_config_unix_active`, `rc_config_unix_file` |
| `router.ml` | `rc_config_quagga` | `(acronyme * (bool * string)) list` | `quagga_<srv>_active`, `quagga_<srv>_file` |
| `router.ml` | `quagga_selected_srvs` | `acronyme list` | `quagga_<srv>_selected` |
| `router.ml` | `show_quagga_terminal` | `acronyme list` | `quagga_<srv>_terminal` |
| `sketch.ml` | `shuffler` | `int list` | `shuffler_indexes` |
| `sketch.ml` | `invertedCables` | `string list` | `inverted_cable_names` |

**Tout scalaire, à plat** (décision de l'auteur, 2026-08-10). Une clé par donnée atomique, jamais
un JSON encodé dans la chaîne d'un attribut — qui aurait rendu au fichier le double échappement
qu'on venait de lui retirer. Les deux listes de `sketch.ml` restent des listes, séparées par des
espaces : une permutation d'entiers d'un côté, des **noms de câbles** de l'autre, et un nom est un
identifiant (`check_new_name`, `user_level.ml`), donc sans espace — c'est ce fait, et lui seul,
qui rend le séparateur sûr.

**Le routeur est éclaté par service, pas par champ.** Ses quatre champs marshalés sont trois
listes et une liste d'associations, toutes indexées par le même acronyme Quagga ; les rendre
service par service donne au fichier la forme de l'onglet de la GUI — `quagga_zebra_selected`,
`_terminal`, `_active`, `_file` côte à côte — au lieu de quatre listes parallèles qu'il faudrait
recroiser de tête. Corollaire à la lecture : les attributs arrivent **un à la fois**, chacun
mettant à jour *sa* moitié du champ OCaml correspondant, dans n'importe quel ordre.

### 11.2 Pourquoi le contenu d'un rc part dans un fichier, et pas dans l'attribut

Le point n'allait pas de soi, et il **change la forme du `.mar`** : un contenu de rc n'est pas une
valeur, c'est un **script shell** — arbitraire, souvent long, multi-ligne. Le mettre en clair dans
l'attribut aurait troqué une opacité contre une autre : un mur de texte échappé, et surtout un
**blob base64 pour le script entier** dès qu'un seul de ses octets n'est pas de l'UTF-8 (§ 8.2).

Le contenu va donc dans un fichier à lui sous `states/`, nommé `rc_config.XXXXXXXXX`, **exactement
comme les documents de `treeview_documents.ml`** (`states/document-XXXXXXXXX`) — un mécanisme déjà
en place, déjà archivé dans le `.mar`, déjà compris. Le forest ne porte que le **basename**. Ce que
l'enseignant a écrit reste un fichier que n'importe quel éditeur ouvre, que `diff` compare ligne à
ligne et que `grep` trouve, ce qui est le but même du chantier. Un routeur en a jusqu'à huit (le rc
UNIX plus les sept services).

### 11.3 La contrainte qui a dicté la conception : `#to_tree` ne doit pas faire d'I/O

`#to_tree` n'est pas seulement le sérialiseur : c'est aussi **ce que le serveur de contrôle
interroge à chaque `get`** (`control_server.ml:892`, ép. 4d-2a de `pilotage-par-script`). Un
`#to_tree` qui aurait créé le fichier au moment de publier son nom aurait donc fabriqué un fichier
**par requête**. D'où la découpe en trois temps, dans `User_level.Rc_files` :

1. le **basename** est alloué à la construction du composant, sans la moindre I/O ;
2. l'**écriture** a lieu une fois par enregistrement, dans `network#save_rc_files`, que `state.ml`
   appelle **juste avant** de sérialiser le forest — donc les basenames que le forest publie sont
   ceux que cette passe vient d'écrire ;
3. la même passe **balaie les orphelins** : un composant détruit depuis le dernier enregistrement
   laisserait sinon son script dans `states/`, et l'archive est faite du répertoire tel qu'il est.

La **lecture**, elle, se fait bien dans `#eval_forest_attribute` : lire un fichier au moment de
désérialiser n'a aucun des inconvénients d'y écrire.

### 11.4 Ce que le canal gagne, et ce qu'il perd jusqu'à l'ép. 6

Gagné : les **onze booléens** d'un routeur (quatre par service, plus le rc UNIX) et le drapeau
d'une machine ou d'un switch étaient dans `omitted` — ils sont désormais des attributs ordinaires,
donc servis par `get` et écrivables par `set`, sans une ligne ajoutée au serveur.

Perdu, temporairement : `rc-get`/`rc-set` reconnaissent leur champ à l'**en-tête magique de
`Marshal`** (`control_server.ml:1438`). Cette forme n'existe plus — ces deux commandes ne trouvent
donc plus rien, sur les projets neufs comme sur les anciens (le champ est démarshalé *en mémoire*
dès l'ouverture). C'est l'objet de l'**ép. 6**, et c'est assumé : mêler le réaccord du canal au
point de non-régression du format aurait rendu l'épisode illisible.

**Conséquence sur le filet, qui ne va pas de soi.** Le banc de l'ép. 1 mesurait précisément ces
huit champs *par `rc-get`* — le seul chemin qui les voyait (§ 7.2). Ce chemin étant muet, le banc
serait resté **vert en cessant de regarder** exactement là où l'épisode agit : le piège de l'ép. 2,
« un banc vert sur un codec cassé ». D'où deux assertions neuves, **hors canal**, sur les
instantanés extraits :

- **référentielle, dans les deux sens** : tout basename que le forest cite existe dans `states/`,
  et tout `states/rc_config.*` est cité par le forest (donc pas d'orphelin — c'est le balayage
  du § 11.3 qui est mesuré ici) ;
- **de fidélité** : toute ligne non vide d'un script produit vient **du `.mar` d'origine**, où le
  contenu marshalé apparaît en clair (`grep -a`, § 6.4), **ou** des contenus **par défaut** du
  binaire, collectés en début de banc en fabriquant un projet neuf par le canal. Rien ne vient de
  nulle part. Et un compte **nul** est un échec : des fichiers cités mais tous vides, c'est
  exactement ce qu'on verrait si la migration avait perdu le contenu.

**Un fait mesuré, qui corrige le § 7.1.** La seconde assertion a d'abord échoué — 147 lignes sur
174 introuvables dans l'original, sur le projet le plus fourni du corpus. Vérification faite au
`grep -a`, ce `.mar` ne porte **aucune** des clés `rc_config`, `rc_config_quagga` ou
`quagga_selected_srvs` : il est **antérieur à ces champs**. Ce que l'ép. 1 avait pris pour « les
sept configurations Quagga d'un routeur, renseignées » était ce que `rc-get` **affichait** — donc
ce que le *modèle* fabrique par défaut au chargement, et non ce que le projet contient. Le corpus
ne couvre donc **pas** de contenu Quagga saisi par un enseignant ; c'est le projet fabriqué
(`worst-case.sh`) qui pourra le faire, si l'ép. 6 en a besoin.

**Discriminance mesurée** (2026-08-10) : l'écriture des fichiers rc désarmée, les deux assertions
neuves tombent — 14 basenames cités mais absents, contenu perdu — et **les sept autres restent
vertes**, round-trip par le canal et inventaire des huit fichiers compris. C'est le trou qu'elles
bouchent, mesuré plutôt que supposé.

### 11.5 Ce que l'épisode 5 ne fait PAS

Il ne touche **pas** au serveur de contrôle (ép. 6), ne prouve pas la compat descendante côté
vieux binaire (ép. 8), ne convertit rien en lot. Il ne **supprime** aucune lecture : les huit
anciennes clés restent interprétées, et le resteront jusqu'à la clôture (§ 6.3). Enfin, il ne
donne pas aux fichiers rc un nom **parlant** (`rc_config.m1`) : un composant se renomme, le nom du
fichier ne suivrait pas, et l'on retomberait sur le problème que `treeview_documents.ml` avait
déjà tranché en faveur d'un nom opaque.

## 12. Le réaccord du canal de pilotage (ép. 6)

Depuis l'ép. 5 un `.mar` ne contient plus un octet de `Marshal`, mais `rc-get`/`rc-set`
reconnaissaient leur champ à l'**en-tête magique** de `Marshal` : ces deux commandes ne trouvaient
plus rien, et `rc-bench.sh` était rouge à dessein. Cet épisode les remet en marche sur la forme
`v3`. Il ne touche **aucun** fichier de format : le contenu d'une configuration de démarrage
n'a pas changé de place, seul le chemin qui y mène a changé.

### 12.1 La reconnaissance change de nature : des octets aux clés

L'ép. 4e avait posé une règle qui a bien servi : le serveur ne garde **aucune liste de noms de
champs**, « une liste qui pourrirait le jour où un composant en ajoute un » — c'est la *valeur* qui
dit ce qu'elle est, et un vidage `Marshal` commence par l'un des trois nombres magiques d'OCaml.
Cette forme n'existe plus. La règle, elle, survit : ce sont désormais les **clés** qui disent ce
qu'elles sont.

| Ce qui est reconnu | Forme `v2` (jusqu'à l'ép. 5) | Forme `v3` (depuis l'ép. 6) |
|---|---|---|
| une configuration de démarrage | valeur marshalée `(bool * string)` | la paire d'attributs `<radical>_active` + `<radical>_file` |
| une configuration **de service** | valeur marshalée `(clé * (bool * string)) list` | les deux clés ci-dessus **plus** `<radical>_selected` et `<radical>_terminal` |
| les deux réglages d'un service | deux champs `string list`, reconnus **par leur nom** | deux attributs booléens du radical lui-même |

Les radicaux sortent du forest, exactement comme les sept acronymes Quagga sortaient du champ
lui-même à l'ép. 12 de `pilotage-par-script`. La distinction « simple / par service » y gagne même
en franchise : elle reposait sur une différence de **type OCaml** (un couple contre une liste
d'associations), elle repose maintenant sur ce qui la définit vraiment côté GUI — un onglet Quagga
porte une case « sélectionné » et une case « terminal », le rc UNIX n'en porte pas.

**Le seul nom qui reste est un préfixe**, `quagga_`. Le modèle nomme ses clés `quagga_zebra_active`
et consorts, donc le radical est `quagga_zebra` ; mais un script écrit `--field=zebra` depuis
l'ép. 12, et un changement de format de stockage n'est pas une raison de changer un vocabulaire
publié. Le préfixe est donc retiré à la publication — sous garde : un nom court qui serait déjà
celui d'un autre radical est **gardé entier**, une requête ne devant jamais être ambiguë. C'est la
même entorse assumée qu'à l'ép. 12, en plus petite : un préfixe au lieu de deux noms de champs.

### 12.2 Le contenu ne vient plus du forest — et il ne peut pas venir du fichier

C'est le point dur de l'épisode, et il ne se voit pas dans le découpage du § 5. Les *drapeaux*
d'une configuration sont des attributs ordinaires : le serveur les lit dans `#to_tree` et les écrit
par `#eval_forest_attribute`, comme `set`. Le **contenu**, lui, a quitté le forest pour
`states/rc_config.XXXXXXXXX` (§ 11.2). Le lire dans ce fichier serait la solution évidente, et elle
est **fausse** — trois fois :

1. sur un composant qu'on vient d'`add`, le basename est alloué sans I/O et **le fichier n'existe
   pas encore**, alors que le modèle porte déjà le contenu par défaut
   (`Const.initial_content_for_rcfiles`) ;
2. sur un projet ouvert depuis un `.mar` `v0`/`v1`/`v2`, le contenu a été **démarshalé en mémoire**
   au chargement et aucun fichier n'a été écrit ;
3. entre deux enregistrements, le fichier porte l'état du dernier `save`, pas celui du modèle.

Le contenu passe donc par le modèle, par deux méthodes neuves de `User_level.component` :

```
method rc_contents    : (string * string) list                        (* basename -> contenu *)
method set_rc_content : basename:string -> content:string -> bool
```

Ni l'une ni l'autre ne fait d'I/O — la contrainte du § 11.3 vaut ici aussi, le serveur appelant
`#rc_contents` à chaque `rc-get`. **`#save_rc_files` et `#rc_file_basenames` en dérivent** dans la
classe mère, et machine, switch et routeur ne redéfinissent plus qu'`#rc_contents` et
`#set_rc_content`. Ce n'est pas un compte de méthodes : jusqu'ici deux parcours indépendants
donnaient les fichiers **écrits** et les basenames **publiés**, et un routeur les parcourait deux
fois ; ils ne peuvent plus diverger.

`#set_rc_content` rend un **booléen** plutôt que `unit` : un basename que le composant ne reconnaît
pas signifierait que le serveur et le modèle ne sont pas d'accord sur le forest. Le serveur le dit
au client, au lieu de rapporter une écriture qui n'a pas eu lieu.

### 12.3 Ce que l'épisode retire, et la garde qu'il déplace

`bin/control_server.ml` ne contient plus **un seul** `Marshal` ni `Obj` (mesuré au `grep`) : les
quatre prédicats de forme sur `Obj.t`, le marcheur de listes, les trois lecteurs
`*_of_marshalled`, `is_marshalled` et `marshalled_field_names` s'en vont — environ 150 lignes. Avec
eux disparaît la reconstruction de l'**ordre canonique** des deux listes d'appartenance : le modèle
la tient lui-même depuis l'ép. 5, un service à la fois (`update_quagga_membership`, `router.ml`).

Le champ `omitted` **reste** dans les réponses de `get`, `add` et `connect`, désormais toujours
vide (décision de l'auteur, 2026-08-10) : un client qui le lit continue de fonctionner, et c'est là
que se dira le jour où un composant publiera quelque chose que ce canal ne peut pas mettre sur une
ligne JSON.

Une garde, en revanche, n'est pas supprimée mais **déplacée, et pour un motif plus fort qu'avant** :
`set` et `add` refusaient un champ marshalé ; ils refusent maintenant les champs `<radical>_file`.
Écrire un tel champ n'est pas « poser une valeur » — `#eval_forest_attribute` **lit le fichier** que
ce nom désigne (`machine.ml:693`), si bien qu'un `set m1 rc_config_file …` remplacerait le script
par le contenu d'un autre fichier, ou par rien. Le refus nomme la commande qui écrit vraiment.

### 12.4 La preuve, et les trois assertions que la mesure a corrigées

`rc-bench.sh` (le banc de l'ép. 4e du chantier `pilotage-par-script`) est passé de **15 échecs à
0**. Mais il n'est pas redevenu vert tout seul, et ce qu'il a fallu corriger est instructif :

- **deux assertions cherchaient le contenu dans `netmodel/network.json`.** Il n'y est plus depuis
  l'ép. 5 — elles étaient donc *fausses*, pas trop strictes. Les réparer en balayant `states/`
  aurait produit un banc plus faible ; elles **suivent le lien** : le forest cite un basename pour
  ce composant *et pour ce radical*, ce basename existe dans `states/`, et c'est **ce fichier-là**
  qui porte ce que le canal a posé. Deux assertions neuves viennent avec, dont le vrai
  discriminant : **aucune ligne du script ne doit se trouver dans `network.json`** — sans elle, un
  serveur qui aurait continué d'écrire le contenu dans l'attribut passerait le reste sans qu'on le
  voie ; et deux radicaux d'un même routeur (le rc UNIX et `zebra`) doivent pointer **deux fichiers
  distincts** ;
- **une assertion était périmée**, la même qu'à l'ép. 5 dans `components-bench.sh` : elle exigeait
  que `get` *masque* `rc_config` et le **nomme** dans `omitted`. Retournée : `get` publie les deux
  moitiés, `omitted` est vide, et le basename est vérifié **par sa forme** (`rc_config.` suivi de
  chiffres) — une chaîne vide ou un bout de script y échoueraient.

**Un défaut du banc attrapé au passage**, qui vaut d'être noté parce qu'il produit un rapport qui
ment : une fonction qui renseignait une variable globale, appelée dans un `$(…)` ou avant un `|`,
s'exécute dans un **sous-shell** — la variable revenait vide et le message affichait `states/` sans
basename, tandis qu'une comparaison entre deux basenames vides passait pour une différence. Deux
fonctions, l'une rendant le basename, l'autre le contenu.

`marshal-bench.sh`, le filet du chantier, est le second témoin, et pour une raison précise : son
`dump` interroge `rc-get` pour chaque composant puis pour chaque champ que `available` publie. Ce
nombre de requêtes est tombé de **72 à 58** pendant que `rc-get` était muet (§ 11.4) ; il est
**revenu à 72** sur les deux projets qui portent un routeur, sans qu'une ligne du banc ait été
touchée pour cela. Le filet est vert : **65 assertions, 0 échec** sur les 8 projets.

Un dernier fait, qui n'est pas un défaut du code mais mérite d'être su : un `save` demandé sans
`--timeout` est borné à **5 s** côté serveur, et un projet de neuf nœuds les dépasse quand deux
bancs tournent en même temps. Le run fautif l'a fait croire à une régression ; rejoué seul, le
même projet passe. **Ne pas faire tourner deux bancs à la fois** — ils se mesurent l'un l'autre.

### 12.5 Ce que l'épisode 6 ne fait PAS

Il ne retire **aucune** lecture : le modèle interprète toujours les huit anciennes clés marshalées,
et le fera jusqu'à la clôture (§ 6.3). Il ne prouve pas la compatibilité descendante côté vieux
binaire (ép. 8), et ne convertit rien en lot (ép. 7, abandonné à l'ép. 4g). Il ne change pas la
documentation utilisateur `doc-src/scripting/` : elle ne nomme aucun champ interne — le vocabulaire
vient de `rc-get … available`, qui rend exactement la même liste qu'avant.

Il ne filtre pas non plus la **complétion Bash**, qui propose pour `set` toutes les clés que `get`
publie, `rc_config_file` compris — que `set` refuse. Laisser passer est un choix : la complétion de
l'ép. 10 est *dérivée*, et y ajouter une règle sur les noms rétablirait dans le client la
connaissance qu'on tient hors de lui. Le refus du serveur nomme la commande à employer, ce qui
enseigne au lieu d'échouer.

## 13. La compat descendante, mesurée (ép. 8a)

Depuis l'ép. 4, ce document répète (§ 3, § 10.6, § 11.5, § 12.5) qu'un vieux binaire mis devant un
`.mar` `v3` « ne trouve pas ses fichiers, donc ne passe jamais de texte à `Marshal.from_file` ».
C'était un **raisonnement sur le code**, tenu au sujet d'un binaire que personne n'avait relancé —
alors que c'est le pire mode de défaillance du chantier : un enseignant qui ouvre un projet `v3`
avec une installation plus ancienne. L'ép. 8a ne produit **aucun code de production** ; il produit
la mesure.

### 13.1 Le témoin est un vrai binaire, pas une simulation

`a4055b1` (« ép. 3 — les codecs des treeviews ») est le dernier commit qui écrit encore du `v2`
**et** qui ignore la chaîne `"v3"` (vérifié : aucune occurrence de `v3` dans son `state.ml`). Il
porte **déjà** `bin/control_server.ml` : le vieux Marionnet se pilote donc sans un clic humain,
et `mrnctl` lui parle sans adaptation puisqu'il demande son vocabulaire au serveur (`help`).

```
git worktree add _claude-local/v2-witness a4055b1
cd _claude-local/v2-witness && dune build --root .
```

Le `--root .` n'est pas décoratif : sans lui, dune remonte à la racine du dépôt principal et
répond `No rule found for alias _claude-local/v2-witness/default`. La même règle joue en notre
faveur dans l'autre sens — dune ignore tout répertoire dont le nom commence par `_`, si bien que
le worktree, logé sous `_claude-local`, **ne perturbe pas** le `dune build` du dépôt courant
(vérifié). Le banc est `_claude-local/bench/backward-bench.sh` : phase 1, le binaire **courant**
fabrique les `.mar` `v3` (le seul producteur légitime d'un `v3` est Marionnet, ép. 4g) ; phase 2,
le **témoin** les reçoit. Les deux phases ont leur propre journal, `bench_launch` ouvrant `$LOG`
en troncature.

### 13.2 Ce que la mesure a corrigé, dès le premier run

L'assertion statique voulait, dans sa première rédaction, que les fichiers du `.mar` `v2` et ceux
du `.mar` `v3` soient **strictement disjoints** — « un vieux binaire ne peut pas ouvrir ce qu'il ne
nomme pas ». Elle est tombée immédiatement : les deux archives partagent les
`hostfs/<n>/boot_parameters` et `hostfs/<n>/GUESTNAME` (douze fichiers pour un projet de six
machines), qui sont le **canal hôte↔invité** recopié d'un enregistrement à l'autre — du texte que
le chargement ne lit jamais. Exiger la disjonction, c'était exiger autre chose que ce qui protège.

La rédaction retenue énonce le danger lui-même : **parmi les fichiers présents dans les deux
archives, aucun ne doit être un vidage `Marshal` côté `v2`** (test de l'en-tête magique
`0x8495A6BD/BE/BF`). Elle est plus forte que la liste de noms qu'on avait d'abord envisagée — un
nom oublié dans une liste est un trou dans la preuve, et `marshal-bench.sh` en porte déjà une, ce
qui aurait fait une seconde source de vérité.

### 13.3 Ce que le vieux binaire fait vraiment

Mesuré sur deux projets (un TP réel à routeur, le projet fabriqué au canal) — **17 assertions,
0 échec** :

- il **refuse** le `.mar` `v3` : le canal répond `internal`, « loading … did not complete: the
  project is flagged as unsaved right after opening » ;
- **aucun composant** n'est visible après le refus (c'est la liste des noms qui tranche, pas le
  drapeau `active` : un chargement échoué laisse le projet « actif » avec zéro nœud) ;
- il est **toujours vivant** — ni segfault ni terminaison ;
- son journal porte le chemin attendu, `project version cannot be identified`, et **aucune** trace
  de démarshalage raté (`input_value`, `bad object`, `Truncated`, `ill-formed message`) : c'est la
  forme observable de « aucun texte n'a atteint `Marshal` » ;
- le `.mar` est **intact** après le refus.

Le dialogue que l'humain voit, lui, se réduit à un titre : « Échec lors du chargement du projet ».
C'est exactement la matière de l'**ép. 8b** — et le seul endroit où on l'observe, les
`notifications` de `open` (ép. 3c du chantier pilotage) ne publiant pas le corps du dialogue.

### 13.4 Le contrôle négatif : ce que l'ép. 4 avait évité

`ARM_DISCRIMINANCE=1` donne au témoin un `.mar` **hybride** — le `v3` auquel on a **remis** les
fichiers du `v2`, `version` restant à `"v3"` (fusion `cp -rn`, les noms étant disjoints rien n'est
écrasé). C'est le projet qu'on obtenait avant que l'ép. 4 n'ajoute `project_paths#legacy_data_files`.
**Six assertions tombent** (trois par projet), et ce qui les remplace vaut d'être lu : le vieux
binaire **ouvre le projet**, ses neuf nœuds compris, affiche « Projet dans un ancien format » et
**propose de le convertir** — c'est-à-dire de réécrire par-dessus l'état `v2` périmé qu'il vient de
charger. Le danger que l'ép. 4 avait raisonné est donc réel, et il est désormais **mesuré** ; les
trois autres assertions (le binaire est vivant, le fichier est intact, les fichiers communs sont
inoffensifs) restent vertes, ce qui confirme que le désarmement touche ce qu'il prétend toucher.

### 13.5 Ce que l'épisode 8a ne fait PAS

Il ne mesure **qu'un point de l'histoire** : `a4055b1`, c'est-à-dire ce dépôt d'avant le
branchement, et non un Marionnet 1.0 tel qu'il est installé chez quelqu'un. Le chemin de détection
de version est le même (`opening_project_version` + le repli de `treeview_ifconfig`), mais un vrai
1.0 n'a pas de canal : l'échec s'y observerait par le seul dialogue. Il ne touche pas au **message**
montré à l'utilisateur (ép. 8b), ne convertit rien en lot (ép. 7, abandonné), et ne retire aucune
lecture.

## 14. Le message, et le catalogue qu'un arbre de développement ne lit pas (ép. 8b)

### 14.1 Une exception plutôt qu'un `failwith`, parce que la cause doit voyager

Le point de départ est une phrase : devant un `.mar` qu'il ne sait pas identifier, Marionnet
affichait « Failed loading the project » puis « **Please ensure that the file be well-formed** ».
Elle envoie chercher une corruption dans un fichier qui n'en a aucune — un projet écrit par une
version plus récente est parfaitement formé, il est seulement postérieur. C'est le message que
lira l'enseignant resté sur son installation pendant qu'un collègue enregistre en `v3`.

Le chemin fautif tenait en une ligne : `state.ml` levait un `failwith` porteur d'un texte
technique, aussitôt absorbé par le handler **générique** de `synchronous_loading`, qui ne pouvait
donc rien dire de mieux que la phrase passe-partout. D'où une **exception dédiée**,
`State.Unsupported_project_version of string option`, dont l'argument porte la seule chose qui
distingue les deux cas : le **tag brut** du fichier `version`. `Some "v4"` = un tag inconnu, donc
selon toute vraisemblance un projet du futur ; `None` = rien d'identifiable, ni tag lisible ni
repli réussi. La lecture de ce tag est extraite dans `opening_project_version_tag`, sur laquelle
`opening_project_version` s'appuie désormais — une seule lecture, deux méthodes, et la signature
publique de la seconde inchangée (elle n'a aucun appelant hors de `state.ml`).

Le handler gagne **une branche en tête**, le cas générique restant intact :

| Cas | Titre | Corps |
|---|---|---|
| tag inconnu | *Project format not supported* | « écrit par une version plus récente de Marionnet, mettez-le à jour » + `version = v4` |
| aucun tag | *Project format not recognized* | « format non identifiable ; fichier endommagé, ou pas un projet Marionnet » |

### 14.2 Pourquoi les quatre phrases ne prennent aucun argument

Les quatre chaînes neuves sont des `s_`, jamais des `f_` : le nom du fichier et le tag brut sont
concaténés **hors** gettext, dans les `<tt>` du corps. Ce n'est pas une commodité mais une
protection, et elle vient du chantier i18n : une traduction dont l'**arité de format** diffère de
l'original casse à l'exécution, en silence, et `msgfmt -c` ne la voit pas. Zéro `%s` traduit, zéro
possibilité de casse — au prix d'un corps composé, ce que le fichier faisait déjà
(`Printf.sprintf "<tt><small>%s</small></tt>\n\n%s" filename (s_ …)`).

Les 12 catalogues sont passés par le **pipeline officiel** (`make gettext-messages-pot` puis
`gettext-update-po`) et non par une insertion à la main. La mesure a montré que c'était sans
danger : le POT regagne **exactement** les 4 entrées neuves, aucun `msgid` n'est perdu, et une
comparaison entrée par entrée des 12 catalogues (HEAD vs arbre de travail) donne partout
`added=4 changed=0 removed=0`. Les 3 messages non traduits qui subsistent par langue sont ceux du
`world_bridge` (chantier `modernisation-world-bridge`), antérieurs et hors périmètre. `ar.po` et
`zh.po`, hors `LINGUAS`, ne sont pas touchés.

### 14.3 Ce que la mesure a refusé de prouver, et le fait qu'elle a établi à la place

Le banc devait finir par une preuve en deux temps : les mêmes ouvertures en anglais puis en
français, ce qui aurait prouvé d'un même geste le message **et** le chargement effectif d'un `.mo`
(le piège du chantier i18n : un catalogue peut être compilé, installé, et jamais lu). La phase
française a échoué — et c'est elle qui a appris quelque chose.

`strace` sur les seuls `openat` dit que le binaire de `_build` ouvre
`/usr/share/locale/fr/LC_MESSAGES/marionnet.mo`, c'est-à-dire le catalogue du **Marionnet installé
par le système**, vieux de plusieurs versions — et jamais celui du dépôt, bien que la cascade de
`bin/gettext.ml` explore le site dune-site (25 `openat` dans
`_build/install/default/share/marionnet/locale`, dont les catalogues sont des **liens symboliques**
vers `_build/default/i18n/`). Deux correctifs ont été essayés et **retirés faute d'effet mesuré** :
forcer `MARIONNET_LOCALEPREFIX`, et ajouter `~follow:()` au `find` de la cascade (l'hypothèse du
symlink non reconnu par `lstat`). La cause exacte n'est pas établie ; elle sort du périmètre de
l'épisode et part dans `docs/TODO.md`.

Le désarmement du message a d'ailleurs produit la contre-épreuve : avec le `failwith` d'origine
rétabli, le titre affiché est « **Échec lors du chargement du projet** » — du français, sorti du
catalogue système, qui porte l'ancienne chaîne et pas les neuves. Le mécanisme de traduction
fonctionne donc parfaitement : c'est le **catalogue** qui est le mauvais.

Le banc ne fait donc pas semblant. Il prouve ce qui est prouvable sans installer — que les
**12 catalogues compilés rendent les 4 phrases**, en les demandant à `dgettext` par `gettext(1)`,
la fonction même qu'appelle `s_` — puis il **mesure** quel catalogue le binaire ouvre, et ne
conclut sur l'affichage traduit **que** si c'est celui du dépôt. Sur un poste où Marionnet est
installé à jour, la même exécution deviendra une preuve complète, sans toucher au banc.

Au passage, une observation de l'ép. 8a est **démentie** : les `notifications` publient bien le
**corps** du dialogue en plus du titre (`json_of_notification`, `control_server.ml:112-119`).
`backward-bench.sh` demandait `.text`, un champ qui n'existe pas — d'où l'impression que seul le
titre voyageait. Les assertions de l'ép. 8b portent donc sur la phrase entière.

### 14.4 La preuve

`version-bench.sh` (hors dépôt, comme les autres) : **30 assertions, 0 échec**. Douze pour les
catalogues, quatorze pour les deux messages (titre, corps, absence de l'ancienne phrase, présence
ou absence du tag brut, survie du binaire, `.mar` intact), une pour le contrôle négatif permanent
(le même projet non trafiqué s'ouvre **sans aucun dialogue d'erreur**), une pour le catalogue
réellement ouvert, une pour l'intégrité du corpus. Les deux projets mesurés sont fabriqués depuis
un `v3` écrit par le binaire lui-même : `future.mar` porte un tag `"v4"` **et** son
`states/ifconfig.json` renommé — les deux, parce que le repli de détection teste ce fichier en
tête et rouvrirait tranquillement le projet comme un `v3` ; `unknown.mar` n'a plus de fichier
`version` du tout.

**Discriminance mesurée** : `raise (Unsupported_project_version …)` remplacé par le `failwith`
d'origine, `dune build`, banc rejoué → **7 assertions tombent** (les deux titres, les deux corps,
les deux « plus d'invitation à chercher une corruption », le tag brut), toutes les autres restent
vertes. `dune test` : **134 assertions, 0 échec**, inchangé. `backward-bench.sh` (ép. 8a) rejoué :
**17 assertions, 0 échec**.

### 14.5 Ce que l'épisode 8b ne fait PAS

Il ne ferme pas le projet en échec (le comportement mesuré à l'ép. 8a — l'application survit,
aucun composant n'apparaît — est conservé tel quel), ne touche à aucune lecture `v0`/`v1`/`v2`, ne
corrige pas la localisation des catalogues en arbre de développement (→ `docs/TODO.md`), et ne
traduit ni `ar.po` ni `zh.po`, hors `LINGUAS`.

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

### 2026-08-09 — Épisode 2 : le codec du forest

**Premier code de production du chantier**, et rien de branché : `lib/STRUCTURES/xforest.ml`
gagne `to_JSON_string` / `of_JSON_string` / `to_JSON_file` / `of_JSON_file`, `lib/dune` gagne
`yojson` et `base64`, et `test/xforest_json.ml` (38 assertions, `dune test`) les éprouve. Détail
au § 8 ; le § 4.1 est **figé**, à trois précisions près (§ 8.1).

**Une décision revenait à l'auteur** et a été posée avant d'écrire : le repli base64 vient du
**paquet opam `base64`** (3.5.2, installé pour l'occasion) et non d'une implémentation maison. Le
motif de la question n'était pas la difficulté — la RFC 4648 tient en ~35 lignes — mais le fait
qu'un **second** paquet s'ajoute au packaging, donc au chantier
`modernisation-installation-marionnet` ; les deux existent en Debian (`libyojson-ocaml-dev`,
`libbase64-ocaml-dev`, vérifié).

**Ce que la mesure a corrigé dans la conception.** Avant d'écrire une ligne, `yojson` 3.0.0 a été
mis à l'épreuve sur des octets non-UTF-8 : il les écrit **verbatim** et les **relit à
l'identique**. Le repli base64 n'est donc pas ce que le § 4.1 croyait — une protection contre la
perte de données — mais la seule façon d'émettre du **JSON valide**. Ce déplacement n'est pas
cosmétique : il **change la forme du banc**. Un test bâti sur le seul aller-retour aurait été
vert sur un codec cassé ; il fallait lui adjoindre l'invariant « le texte produit est de l'UTF-8
valide ». Vérifié en désarmant le repli : **7 assertions tombent, et tous les round-trips
passent**.

Trois autres choix méritent d'être retenus, tous du même côté : ne rien deviner. Les trois
membres d'un arbre sont **requis** ; une version future est refusée **en la nommant** ; le
validateur UTF-8 est celui de la bibliothèque standard, qui rejette surlongs et surrogates — deux
familles qu'un test maison laisse passer, et qui sont au banc.

Enfin, **les tests de cet épisode sont dans le dépôt**, contrairement au banc de l'ép. 1 : ils
sont purs, tiennent en une seconde et n'ont besoin ni de GUI ni de corpus, exactement comme
`test/marionnet.ml`. `test/dune` passe donc de `test` à `tests`.

Livrables : `lib/STRUCTURES/xforest.ml`, `lib/dune`, `test/xforest_json.ml`, `test/dune`, les § 3,
4, 6 et 8 de ce document.

### 2026-08-09 — Épisode 2 (suite) : l'interface, et la circularité qu'elle a révélée

`lib/STRUCTURES/xforest.mli`, qui n'existait pas : le module publie désormais ce que le dépôt
utilise réellement et **cache** les seize noms de son implémentation — vérifié, pas supposé
(`Xforest.is_valid_utf_8` et trois autres internes sont maintenant `Unbound value`). Effet
d'abstraction notable : **`yojson` n'apparaît dans aucune signature**, la bibliothèque JSON
redevient un détail d'implémentation.

Le vrai gain n'est pas là. Se demander « qu'est-ce qui mérite d'être public ? » a fait apparaître
un défaut du banc que la relecture n'avait pas vu : il vérifiait « la sortie est de l'UTF-8
valide » avec **le prédicat même qui décide du repli**. Un prédicat faux aurait rendu le codec et
son banc faux **d'un même mouvement**, sans qu'aucune assertion ne bronche — exactement le genre
de silence que le § 6.2 traque. Le banc porte maintenant son **propre** validateur, décodant à la
main, éprouvé par 15 assertions (surlongs, surrogates, séquences tronquées, au-delà de U+10FFFF).
Et la discriminance a été **remesurée** après le remplacement — mêmes 7 assertions à terre, repli
désarmé —, faute de quoi on aurait troqué un banc circulaire contre un banc laxiste.

Le banc passe de 38 à 53 assertions. Détail au § 8.4.

Livrables : `lib/STRUCTURES/xforest.mli`, `test/xforest_json.ml`, le § 8.4 de ce document.

### 2026-08-09 — Épisode 3 : les codecs des treeviews et des compteurs

Les deux schémas restants (§ 4.2 et § 4.3) sont **figés et implémentés** ; **rien n'est branché**,
pour la troisième fois. Détail au § 9.

Ce que l'épisode a réellement tranché n'est pas l'écriture des deux codecs — ils ressemblent à
celui de l'ép. 2 — mais **deux questions de structure**, dont l'une contredit ce document.

**1. Le codec ne pouvait pas aller là où le § 5 le plaçait.** `bin/treeview.ml` est un widget Gtk+
de l'**exécutable**, et une stanza `(tests)` de dune ne lie que des **bibliothèques** : le codec y
aurait été privé des tests unitaires versionnés que l'ép. 2 avait justement institués, pour un
chemin de chargement qui **avale ses erreurs** (`load_counters`). D'où le déménagement de `Row` et
`Row_item` — la donnée, qui n'a jamais eu besoin de Gtk+ — dans `bin/treeview_row.ml`
(bibliothèque `marionnet_base`), et des compteurs dans `bin/treeview_counters.ml`. `treeview.ml`
réexpose les deux modules **sous leurs noms historiques** : aucun des 7 fichiers qui les emploient
n'a changé d'une ligne.

**2. La plomberie du format allait être écrite trois fois.** Le validateur UTF-8, le repli base64
et le piège qu'il évite, `Malformed`, `member_of`, le contrôle `format`/`version`, les I/O :
identiques pour les trois codecs. Ils vivent maintenant dans `lib/STRUCTURES/json_bricks.ml{,i}`,
et `Xforest` a été refactoré pour s'y adosser (ses 4 fonctions publiques inchangées, ses 38
assertions toujours vertes). Le prix — `yojson` visible dans **cette** interface — est assumé et
argumenté au § 9.2 : c'est le module dont le rôle *est* d'être la couche JSON.

**Deux mesures, pas deux suppositions.** D'abord la **discriminance**, remesurée comme à l'ép. 2 :
repli base64 désarmé, **5 assertions** du nouveau banc tombent — et **tous les round-trips
passent** ; compteur 64 bits rendu tolérant au nombre JSON, **1 assertion** tombe. Ensuite la
**non-régression du déménagement** : `Marshal` n'encode pas les chemins de modules, donc les `.mar`
existants devaient se relire à l'identique — le **banc de l'ép. 1 rejoué le confirme sur les
8 projets** (41 assertions, 0 échec ; l'ordre des nœuds s'inverse toujours à chaque cycle, comme
mesuré). Enfin, `dune test` : **134 assertions, 0 échec**, dont 74 neuves.

Un déplacement latéral utile au passage : le validateur UTF-8 indépendant est devenu
`test/utf_8_reference.ml`, **partagé** par les deux programmes de test — une référence unique pour
l'invariant qui les rend discriminants, et toujours **pas** le prédicat qu'emploie le codec.

### 2026-08-09 — Épisode 4 : `v3` branché — un projet est désormais du texte

**Tout `.mar` que Marionnet écrit est du `v3`** : sept fichiers JSON plus `version`. La lecture
`v0`/`v1`/`v2` est intacte. Détail au § 10.

Le branchement en lui-même n'a rien appris — le type `[ `v0 | `v1 | `v2 | `v3 ]` a désigné à la
compilation les six endroits qui décident, et les trois codecs de l'ép. 3 s'y sont posés sans une
retouche. **Ce que l'épisode a réellement tranché tient en deux points**, et aucun des deux
n'était dans le § 5.

**1. Écrire le `v3` ne suffisait pas : il fallait EFFACER le `v2`.** Un projet ouvert en `v2` garde
ses anciens fichiers dans le répertoire de travail, dont l'archive est faite. Le `.mar` aurait donc
porté les deux formes, l'ancienne périmée — et un vieux binaire, ne comprenant pas `"v3"`, serait
retombé sur **son propre repli de détection**, aurait trouvé `states/ifconfig` et ouvert l'état
d'avant **sans un mot**. La décision « compat descendante par renommage » (§ 3) aurait été fausse
au moment même de sa mise en œuvre. D'où la suppression des fichiers de données `v2` juste avant
l'archivage (§ 10.2), et une assertion **inverse** au banc : aucun nom `v2` ne doit subsister.

**2. La question laissée ouverte est tranchée : l'inversion d'ordre des nœuds reste** (décision de
l'auteur). Elle vient du modèle, pas du format ; elle est identique en `v2` ; le banc, qui mesure
sur deux cycles, y est insensible. Elle part dans `docs/TODO.md` avec son vrai argument — un
fichier diffable, ce qui est une des raisons de ce chantier.

**Deux faits mesurés, dont un corrige ce document.** Le premier `dotoptions.json` écrit montre
**huit** attributs marshalés dans le forest, et non six : `shuffler` et `invertedCables`
s'ajoutent à la liste du § 5, dans le fichier même que le canal ne publie pas (§ 7.4). Le second :
l'**ép. 6 dépend de l'ép. 5, pas de l'ép. 4** — la valeur d'un `rc_config` reste marshalée en
mémoire, seul son transport change, si bien que `rc-bench.sh` est vert **bout en bout** (routeur
démarré, `/etc/quagga/zebra.conf` lu dans l'invité) sans une ligne touchée au serveur de contrôle.

**La preuve** (§ 10.5) : banc de l'ép. 1 **vert — 49 assertions, 0 échec** sur les 8 projets, dont
la conversion `v2` → `v3` puis quatre relectures ; les **112 fichiers JSON** produits relus en
UTF-8 strict par `python3`, 0 invalide ; les trois bancs du chantier `marionnet-pilotage-par-script`
qui inspectent le `.mar` rejoués et verts (134 + 160 + 102 assertions) ; `dune test` inchangé
(134 assertions).

### 2026-08-10 — Épisode 5 : la désimbrication — plus aucun attribut marshalé

**Aucun attribut d'un `.mar` écrit par ce binaire n'est plus un vidage `Marshal`.** Les huit
derniers (§ 11.1) sont défaits ; la lecture des huit anciennes clés est intacte. Détail au § 11.

**La forme retenue est « tout scalaire, à plat »** (décision de l'auteur) : une clé par donnée
atomique, jamais un JSON encodé dans la chaîne d'un attribut — qui aurait rendu au fichier le
double échappement qu'on venait de lui retirer. Le routeur est éclaté **par service**, ce qui donne
au fichier la forme de l'onglet de la GUI plutôt que quatre listes parallèles à recroiser de tête.

**Le point qui a réellement dicté la conception n'est pas le format, c'est que le contenu d'un rc
est un script.** Le mettre en clair dans l'attribut aurait troqué une opacité contre une autre : un
mur de texte échappé, devenant un **blob base64 pour le script entier** au premier octet non-UTF-8.
Il part donc dans un fichier à lui sous `states/` — `rc_config.XXXXXXXXX`, exactement comme les
documents de `treeview_documents.ml` —, le forest ne portant que le basename. Corollaire non
évident : **`#to_tree` ne peut pas écrire ce fichier**, puisque le serveur de contrôle l'appelle à
chaque `get` et qu'un fichier serait créé par requête. D'où les trois temps du § 11.3 — basename
alloué sans I/O à la construction, écriture une fois par enregistrement dans
`network#save_rc_files`, et **balayage des orphelins** dans la même passe.

**Ce que le canal gagne et perd.** Les onze booléens d'un routeur, plus celui d'une machine ou d'un
switch, étaient dans `omitted` : ils sont désormais servis par `get` et écrits par `set`, sans une
ligne ajoutée au serveur. En revanche `rc-get`/`rc-set`, qui reconnaissent leur champ à l'en-tête
magique de `Marshal`, ne trouvent plus rien — c'est l'**ép. 6**, et c'est assumé.

**Le filet a dû être réparé avant de servir, et c'est l'enseignement de l'épisode.** Le banc
mesurait ces huit champs *par `rc-get`* — le seul chemin qui les voyait. Ce chemin devenu muet, il
serait resté **vert en cessant de regarder** exactement là où l'épisode agit : le nombre de requêtes
du dump est d'ailleurs tombé de 72 à 58 sans qu'aucune assertion bronche. D'où deux assertions
neuves, hors canal (§ 11.4), et **deux corrections que seule la mesure a apportées** :

1. l'assertion de fidélité, écrite comme « toute ligne vient du `.mar` d'origine », a **échoué** —
   147 lignes sur 174. Vérification au `grep -a` : ce projet ne porte **aucune** clé `rc_config*`,
   il est antérieur à ces champs. Ce que l'ép. 1 avait pris pour « les sept configurations Quagga
   renseignées » était ce que `rc-get` *affichait*, c'est-à-dire ce que le **modèle** fabrique par
   défaut au chargement. D'où la collecte des contenus par défaut, en fabriquant un projet neuf par
   le canal (88 lignes distinctes), et une assertion « origine **ou** défaut, jamais nulle part » ;
2. le garde-fou « des fichiers cités mais tous vides = contenu perdu » a **échoué** sur deux autres
   projets, pour la même raison de fond : sans le champ dans l'original, la chaîne vide est la
   bonne réponse. Il est devenu une **implication** — si l'original porte un `rc_config`, la
   migration doit produire du texte.

**La preuve.** Banc de l'ép. 1 **vert : 65 assertions, 0 échec** sur les 8 projets (49 avant
l'épisode, 16 neuves) ; **discriminance mesurée** — écriture des fichiers rc désarmée, les deux
assertions neuves tombent et **les sept autres restent vertes** ; `dune build` et `dune test`
(134 assertions) inchangés. Des trois bancs du chantier `marionnet-pilotage-par-script` qui
inspectent le `.mar` : `treeview-bench.sh` **vert sans retouche**, `components-bench.sh` vert
(**134 assertions**) après **retournement** d'une assertion devenue fausse — elle exigeait que
`get` *masque* `rc_config` dans `omitted`, elle exige maintenant qu'il publie les deux clés en
clair —, et **`rc-bench.sh` rouge (15 assertions), délibérément** : il mesure `rc-get`/`rc-set`,
c'est la dette de l'ép. 6, et le laisser rouge est ce qui la rend visible.

### 2026-08-10 — Épisode 6 : le réaccord du canal, et le banc qui regardait au mauvais endroit

**`rc-get`/`rc-set` parlent de nouveau, sur la forme `v3`.** Ils reconnaissaient leur champ à
l'en-tête magique de `Marshal` ; ils le reconnaissent maintenant à sa **paire de clés**
(`<radical>_active` + `<radical>_file`), un rc **de service** en portant deux de plus
(`_selected`, `_terminal`). Détail au § 12. Pour un client, **rien ne change** : mêmes commandes,
même vocabulaire (`--field=zebra`), même contenu en clair sur une ligne.

**La règle de l'ép. 4e a survécu au changement de format** : le serveur ne tient toujours aucune
liste de noms de champs — les radicaux sortent du forest. La distinction « simple / par service »
y gagne : elle reposait sur une différence de **type OCaml**, elle repose désormais sur la
présence des deux booléens, c'est-à-dire sur ce qui la définit côté GUI. Un seul nom subsiste, le
préfixe `quagga_`, retiré à la publication pour ne pas changer un vocabulaire que des scripts
utilisent déjà — sous garde d'ambiguïté.

**Le point dur n'était pas la reconnaissance, c'était le contenu.** Il a quitté le forest pour
`states/rc_config.XXXXXXXXX`, et le lire dans ce fichier serait **faux trois fois** : sur un
composant qu'on vient d'ajouter le fichier n'existe pas encore, sur un projet ouvert depuis un
`.mar` `v2` il n'a jamais été écrit, et entre deux enregistrements il porte l'état du dernier
`save`. Le contenu passe donc par le modèle — `component#rc_contents` et `#set_rc_content`, sans
I/O — et **`#save_rc_files` / `#rc_file_basenames` en dérivent** : les fichiers écrits et les
basenames publiés ne peuvent plus venir de deux parcours qui divergent. `#set_rc_content` rend un
**booléen** : une écriture perdue ne peut pas passer pour faite.

**Ce que l'épisode retire.** `bin/control_server.ml` ne contient plus **un seul** `Marshal` ni
`Obj` (mesuré au `grep`) : ~150 lignes d'inspection de forme s'en vont, et avec elles la
reconstruction de l'ordre canonique des deux listes d'appartenance — le modèle la tient lui-même
depuis l'ép. 5. Le champ `omitted` **reste**, toujours vide (décision de l'auteur). Une garde est
**déplacée, pas supprimée** : `set`/`add` refusaient un champ marshalé, ils refusent les champs
`<radical>_file` — et le motif est plus fort, puisque `#eval_forest_attribute` **lit le fichier**
que ce nom désigne.

**L'enseignement est encore côté banc, et il prolonge exactement celui de l'ép. 5.** `rc-bench.sh`
n'est pas redevenu vert tout seul : deux de ses assertions cherchaient le contenu dans
`netmodel/network.json`, où il n'est plus depuis l'ép. 5 — elles étaient **fausses**, pas trop
strictes. Les réparer en balayant `states/` aurait donné un banc plus faible ; elles **suivent le
lien** (le forest cite un basename pour ce composant *et* pour ce radical, le fichier existe,
c'est lui qui porte ce que le canal a posé), et deux assertions neuves viennent avec, dont le vrai
discriminant : **aucune ligne du script ne doit se trouver dans `network.json`**. Une troisième
assertion était périmée, la même qu'à l'ép. 5 dans `components-bench` (`get` devait *masquer*
`rc_config` dans `omitted`) : retournée, avec le basename vérifié **par sa forme**. Et un défaut
de banc attrapé au passage, qui produisait un rapport **qui ment** : une fonction renseignant une
variable globale, appelée dans un `$(…)` ou avant un `|`, s'exécute dans un **sous-shell** — le
basename revenait vide, et deux basenames vides passaient pour deux fichiers distincts.

**La preuve.** `rc-bench.sh` **104 assertions, 0 échec**, bout en bout compris — la configuration
ZEBRA posée par le canal se lit dans `/etc/quagga/zebra.conf` de l'invité (réponse en 12 s) et le
service désélectionné voit son `.conf` mis en `.backup`. **Discriminance mesurée** : écriture du
contenu désarmée → **17 assertions tombent** et tout le reste (drapeaux, sélection, terminal,
refus, vocabulaire) reste vert. `dune build` et `dune test` (134 assertions) inchangés ;
`treeview-bench`, `components-bench` (134), `doc-bench` (46, bout en bout invité compris),
`completion-bench` (48) et `check-bench` (32) verts **sans retouche**. Le filet du chantier
(`marshal-bench.sh`) est le second témoin : son `dump` interroge `rc-get` par composant puis par
champ publié, si bien que le nombre de requêtes — tombé de 72 à 58 pendant que la commande était
muette — remonte sans qu'une ligne du banc ait été touchée pour cela.

### 2026-08-10 — Épisode 8a : la compat descendante, mesurée au lieu d'être affirmée

**Aucune ligne de code de production.** Conception et résultats au § 13 ; ce journal ne retient que
ce qui a **changé** par rapport au plan.

Le plan disait « prouver au banc qu'un Marionnet `v2` devant un `.mar` `v3` échoue proprement ».
Deux façons s'offraient : lire le vieux chemin de chargement et conclure, ou **relancer le vieux
binaire**. La seconde a été retenue (décision de l'auteur), et elle était moins chère que prévu :
le commit `a4055b1` porte déjà le canal de contrôle, si bien que le témoin se pilote comme le
binaire courant — aucun clic, aucune capture d'écran, des assertions.

**Ce que la mesure a corrigé.** L'assertion statique était fausse à la première rédaction : elle
exigeait des archives aux noms **disjoints**, ce qui a échoué sur les douze `hostfs/<n>/*` que tout
enregistrement recopie. Reformulée en « aucun fichier commun n'est un vidage `Marshal` », elle dit
enfin le danger — et elle est plus forte que la liste de noms qu'on avait envisagée, laquelle
aurait été une seconde source de vérité en face de celle de `marshal-bench.sh`.

**Ce que le contrôle négatif a rendu visible.** Sur le `.mar` **hybride** (le `v3` avec les fichiers
`v2` remis), le vieux binaire n'échoue pas : il **ouvre** le projet — neuf nœuds — annonce « Projet
dans un ancien format » et **propose de le convertir**, c'est-à-dire d'écrire par-dessus l'état
périmé qu'il vient de charger. Le raisonnement de l'ép. 4 (`legacy_data_files`) tenait donc une
perte de données réelle à distance, et on le sait maintenant par la mesure.

**La preuve.** `backward-bench.sh` : **17 assertions, 0 échec** sur deux projets ; **discriminance
mesurée** — `ARM_DISCRIMINANCE=1` → **6 assertions tombent** (le refus, l'absence de composants et
la ligne de journal, pour chacun des deux projets), les autres restent vertes. `dune build` et
`dune test` (**134 assertions, 0 échec**) inchangés. `marshal-bench.sh` n'a **pas** été rejoué :
rien n'a changé dans `bin/` ni `lib/`.

**Reste à l'ép. 8b** : le message montré à l'utilisateur. Le vieux binaire, lui, dit « Échec lors du
chargement du projet » ; le binaire **courant** devant un `.mar` qu'il ne sait pas identifier dit la
même chose, suivie de « Please ensure that the file be well-formed » — trompeur pour un fichier
parfaitement formé, mais écrit par une version plus récente.

### 2026-08-10 — Épisode 8b : le message, et le catalogue qu'un arbre de développement ne lit pas

**Ce qui a été fait.** `bin/state.ml` : exception dédiée `Unsupported_project_version of string
option`, méthode `opening_project_version_tag` dont `opening_project_version` dérive désormais, et
une branche en tête du handler générique de `synchronous_loading` — deux titres et deux corps
selon que le fichier `version` porte un tag inconnu ou rien du tout. Les 4 chaînes neuves sont
sans format (`s_`, jamais `f_`), le nom du fichier et le tag brut voyageant hors gettext : une
traduction d'arité fausse casserait à l'exécution sans que `msgfmt -c` s'en aperçoive. Les
12 catalogues sont passés par le pipeline officiel (`gettext-messages-pot` + `gettext-update-po`),
mesuré sans danger — POT : 4 `msgid` gagnés, aucun perdu ; catalogues : `added=4 changed=0
removed=0` partout, comparaison entrée par entrée contre HEAD. Restent 3 non-traduits par langue,
ceux du `world_bridge`, antérieurs et hors périmètre.

**Ce que la mesure a appris.** La preuve prévue — rejouer les ouvertures en français — est
**impossible depuis un arbre de développement** : `strace` montre que le binaire de `_build` ouvre
`/usr/share/locale/fr/LC_MESSAGES/marionnet.mo`, le catalogue du Marionnet installé par le
système, et jamais celui du dépôt, bien que la cascade de `bin/gettext.ml` explore le site
dune-site. Deux correctifs essayés (`MARIONNET_LOCALEPREFIX`, `~follow:()` sur le `find`) n'ont
**rien changé à la mesure et ont été retirés** ; la cause n'est pas établie et part dans
`docs/TODO.md`. Le désarmement du message a fourni la contre-épreuve : avec le `failwith`
d'origine, le titre sort **en français** (« Échec lors du chargement du projet ») — le mécanisme
de traduction marche, c'est le catalogue qui est le mauvais. Le banc prouve donc ce qui est
prouvable sans installer (les 12 catalogues compilés rendent les 4 phrases, demandées à
`dgettext`), puis **mesure** le catalogue réellement ouvert et ne conclut sur l'affichage traduit
que s'il vient du dépôt. Enfin, une observation de l'ép. 8a est **démentie** : les `notifications`
publient bien le **corps** en plus du titre — `backward-bench.sh` demandait `.text`, un champ
inexistant.

**La preuve.** `version-bench.sh` : **30 assertions, 0 échec** (12 catalogues, 14 sur les deux
messages, contrôle négatif du projet non trafiqué, catalogue ouvert, corpus intact) ;
**discriminance mesurée** — `failwith` d'origine rétabli → **7 assertions tombent**, les autres
restent vertes. `dune test` **134 assertions, 0 échec** inchangé ; `backward-bench.sh` (ép. 8a)
rejoué : **17 assertions, 0 échec**.

**Reste à l'ép. 9** : tranche « format de projet » de `docs/ARCHITECTURE.md`, note de version pour
les enseignants, puis clôture (MODE C).
