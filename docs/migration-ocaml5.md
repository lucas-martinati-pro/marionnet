# Chantier long — migration OCaml 4.13.1 → 5.4.1

*Slug de chantier (scope des commits, `git log --grep`) : `migration-ocaml5`.*

> **CHANTIER CLOS (2026-07-27).** Périmètre atteint : Marionnet **compile**, **tourne** et
> **s'installe** (profil *testing*) sur le switch opam **5.4.1**, en restant sur camlp4. Le gel
> 4.13.1 est levé, sa justification historique était fausse. Épisodes 0→6 en 2 jours
> (`git log --grep="migration-ocaml5"`). Bilan et suites : § 6, en fin de document.

> **Historique linéaire sur `main`**, comme tous les chantiers de ce dépôt. Conséquence assumée
> de la décision D1 (coupure nette) : entre l'épisode 1 et l'épisode 3, `main` **ne compile pas**
> — ni sur 5.4.1 (3 sites restants, § 4) ni, à partir de l'épisode 2, sur 4.13.1. C'est un état
> transitoire connu, pas une régression : `git log --grep="migration-ocaml5"` donne la position
> exacte dans le chantier. **Depuis l'épisode 3 (2026-07-27), `dune build` est vert sur 5.4.1**
> et cette fenêtre est refermée.

> Doc durable : conception, décisions, inventaire, journal d'avancement.
> État vivant et prochaines étapes : fiche mémoire `migration-ocaml5`.

---

## 1. Pourquoi ce chantier

Le dépôt est gelé sur le switch opam **4.13.1** depuis le port dune, au motif inscrit dans
`CLAUDE.md` : *« Toolchain gelée OCaml 4.13.1 (dernier compatible camlp4) »*.

**Cette prémisse est caduque.** Deux preuves indépendantes :

1. `camlp4` suit OCaml 5 : `opam show -f all-versions camlp4` → `… 5.4  5.5`. La version
   `camlp4.5.4` est disponible et **déjà installée** sur le switch 5.4.1 de la machine de
   développement.
2. Le projet frère **circa** (`~/DEVEL/repos/circa`) compile sa propre copie vendorée
   d'ocamlbricks avec `(preprocess (action (run camlp4of …)))` sur **5.4.1** — commit `6260517`
   « build: passe la base OCaml de 5.3.0 à 5.4.1 ».

Les dépendances GUI ne s'opposent pas non plus : `lablgtk3.3.1.5-1`,
`lablgtk3-sourceview3.3.1.5`, `lablgtk3-extras.3.0.1`, `inotify.2.6`.

Le gel a un coût réel : Merlin/LSP/ocamlformat dégradés, pas de `Domain` ni d'effets, écosystème
opam qui s'éloigne, et un `opam switch` de plus à maintenir sur chaque poste. Le chantier vise
donc à **lever le gel sans quitter camlp4**.

### Choix du 5.4.1 (et pas 5.5.0)

Repris tel quel de circa : rien de 5.5.0 (explicites modulaires, *pacing* du GC) n'est utile ici,
et `camlp4.5.5` y exige `ocamlfind 1.9.9~preview`. On prend la version *bugfix* stable.

### Effet de bord sur le chantier `marionnet-camlp4-ppx`

Ce chantier-là est justifié par « sortir des 7 extensions camlp4 **pour lever le gel OCaml 4.13.1
et** restaurer Merlin/LSP ». Si la présente migration aboutit, **la première moitié de sa
justification tombe** : camlp4 cesse d'être un verrou de version. Il conserve sa seconde moitié
(Merlin/LSP/ocamlformat, et la dette d'un préprocesseur non maintenu), mais il n'est plus un
préalable à la modernisation. À reformuler — ou à re-prioriser — une fois le présent chantier
conclu. Aucune action ici.

---

## 2. Périmètre et décisions

| # | Décision | Pourquoi |
|---|---|---|
| D1 | **Coupure nette** vers 5.4.1 : on n'entretient pas la double compatibilité 4.13.1/5.4.1 | Un double support via `IFDEF` (les `-D…` de `lib/camlp4of-flags.cfg`) complexifierait durablement 25+ fichiers et doublerait la charge de vérification, pour un filet dont on n'a pas besoin : le travail se fait sur branche, et git garde l'état 4.13.1 |
| D2 | ocamlbricks local : **extraction chirurgicale** des seules adaptations OCaml 5 présentes chez circa | Les copies locales des deux projets ont divergé *indépendamment* : reprendre un fichier circa en bloc importerait ses évolutions fonctionnelles propres (`Future` réécrit sur `Domain`) **et écraserait** les correctifs propres à Marionnet (ex. le `CLOEXEC` de `Network.server`, chantier retro-compat ép. 3) |
| D3 | On **reste sur camlp4** | Objectif borné : changer de compilateur, pas de préprocesseur. Un ppx en même temps rendrait tout échec indiagnosticable |
| D4 | **Rétro-propagation** des correctifs vers `~/DEVEL/repos/ocamlbricks` : dette de **fin** de chantier | Même posture que circa. L'upstream n'est pas à jour ; on consolide d'abord une copie locale qui compile, on remonte ensuite |

### Hors périmètre

- Passage à ppx (chantier `marionnet-camlp4-ppx`).
- Usage effectif de `Domain`/effets (le but est de compiler, pas de paralléliser).
- Ré-vérification du build 4.13.1 (conséquence de D1).

---

## 3. État des lieux mesuré (2026-07-26)

| Élément | Constat |
|---|---|
| `lib/` (ocamlbricks vendored) | **98 `.ml`**, 12 sous-dossiers, **7** extensions camlp4 |
| `bin/` | **55 `.ml`**, lablgtk3 ; jamais confronté à OCaml 5, et circa n'a pas de GUI → **aucun précédent** pour cette moitié |
| Modules ocamlbricks communs avec circa | **30**, dont **8 strictement identiques** |
| Ruptures OCaml 5 visibles au grep | `Pervasives` (supprimé en 5.0) dans `lib/EXTRA/setExtra.ml`, `lib/SHELL/pts.ml`, `lib/EXTRA/threadExtra.ml` (+ occurrences en commentaire) ; **aucun** usage de `Stream`/`Genlex` |
| Stubs C (3) | `CAMLparam`/`Field`/`caml_alloc` classiques, pas de *naked pointers* ; `waitpid-c-wrapper.c` et `does-process-exist-c-wrapper.c` sont **déjà compilés par circa sur 5.4.1** ; seul `gettext-c-wrapper.c` est propre à Marionnet |

### 3.1 Les 30 modules ocamlbricks communs à Marionnet et circa

Colonne « Δ » = nombre de lignes différant entre la copie Marionnet et la copie circa (`.ml`).
Colonne « Verdict » à remplir au fil des épisodes : `=` identique · `OCaml5` adaptation à extraire ·
`circa-only` divergence fonctionnelle de circa, à ignorer · `mixte` à trier ligne à ligne.

| Module Marionnet | Δ vs circa | Verdict |
|---|---:|---|
| `lib/STRUCTURES/bit.ml` | 0 | `=` |
| `lib/STRUCTURES/bitmmasks.ml` | 0 | `=` |
| `lib/STRUCTURES/egg.ml` | 0 | `=` |
| `lib/STRUCTURES/extreme_sharing.ml` | 0 | `=` |
| `lib/BASE/fix.ml` | 0 | `=` |
| `lib/BASE/ocamlbricks_log.ml` | 0 | `=` |
| `lib/STRUCTURES/sowide.ml` | 0 | `=` |
| `lib/STRUCTURES/stateful_modules.ml` | 0 | `=` |
| `lib/EXTRA/strExtra.ml` | 0 | `=` |
| `lib/STRUCTURES/string_queue.ml` | 5 | à trier |
| `lib/EXTRA/filenameExtra.ml` | 7 | à trier |
| `lib/EXTRA/stringExtra.ml` | 9 | à trier |
| `lib/STRUCTURES/hashset.ml` | 16 | à trier |
| `lib/STRUCTURES/memo.ml` | 18 | à trier |
| `lib/STRUCTURES/option.ml` | 35 | à trier |
| `lib/STRUCTURES/bitmasks.ml` | 48 | à trier |
| `lib/STRUCTURES/endpoint.ml` | 49 | à trier |
| `lib/EXTRA/mutexExtra.ml` | 51 | à trier |
| `lib/BASE/log_builder.ml` | 62 | à trier |
| `lib/STRUCTURES/loop.ml` | 62 | à trier |
| `lib/STRUCTURES/arrayTk.ml` | 68 | à trier |
| `lib/EXTRA/pervasivesExtra.ml` | 30 | à trier |
| `lib/EXTRA/listExtra.ml` | 114 | à trier |
| `lib/STRUCTURES/range.ml` | 120 | à trier |
| `lib/STRUCTURES/selections.ml` | 128 | à trier |
| `lib/EXTRA/unixExtra.ml` | 183 | à trier |
| `lib/STRUCTURES/table.ml` | 217 | à trier |
| `lib/BASE/misc.ml` | 312 | à trier |
| `lib/EXTRA/arrayExtra.ml` | 382 | à trier |
| `lib/STRUCTURES/future.ml` | 424 | `circa-only` (réécrit sur `Domain` chez circa) |

**Méthode de tri (D2)** : ne consulter la version circa d'un module **que** lorsque le compilateur
5.4.1 se plaint de la version Marionnet, et n'en extraire que la ligne/expression qui répare
l'erreur. Le compilateur, pas le diff, décide de ce qui est repris.

Les 68 autres `.ml` de `lib/` (CORTEX, WIDGETS, CHANNEL, MARSHAL, SHELL, GETTEXT…) et les 55 de
`bin/` n'ont **aucun** homologue circa : ils seront portés au vu des erreurs.

---

## 4. Inventaire des erreurs du premier build 5.4.1 — épisode 1b

Environnement de la mesure : `ocamlc 5.4.1`, `camlp4of 5.4.1`, `dune 3.23.1`, `lablgtk3 3.1.5`,
`lablgtk3-sourceview3 3.1.5`, `lablgtk3-extras 3.0.1`, `inotify 2.6`, `camlp4 5.4`.
Note : `dune ≥ 3.x` **poursuit** le build après une erreur par défaut (`--stop-on-first-error` est
opt-in), donc chaque passe donne toutes les erreurs *non masquées par une dépendance échouée*.

**Résultat : le portage est presque gratuit.** Cinq points seulement, dont **un seul** demande une
vraie décision de conception.

| Cat. | Constat | Sites | Statut |
|---|---|---|---|
| **A** camlp4 | `Error: Unbound module Stream` en compilant `lib/CAMLP4/include_type_definitions_p4.ml` (2 usages de `Stream`, disparu du Stdlib en 5.0) | 1 | **corrigé** : `-package camlp4,camlp-streams` dans les `(rule)` de `lib/dune` |
| **A** camlp4 | **`where_p4` et `raise_p4` compilent sans rien changer** — le « crux » annoncé n'en est pas un ; les 7 extensions passent | 0 | **non bloquant** |
| **B** Stdlib disparue | **aucune** erreur : les fichiers concernés portent déjà un shim `module Pervasives = Stdlib` en tête (9 fichiers de `lib/`), hérité d'une migration antérieure | 0 | rien à faire |
| **C** sémantique OCaml 5 | **`Ephemeron.S` a perdu `fold`, `iter` et `filter_map_inplace` en 5.0** (l'itération sur des éphémérons est *unsound* avec le GC multicœur) → `lib/STRUCTURES/table.ml` ne compile plus | 1 fichier, 5 méthodes | **BLOQUANT — voir § 4.1** |
| **D** lablgtk3 | **aucune** erreur en passant de 3.1.4 à 3.1.5 ; toute la GUI (`bin/`, 55 `.ml`) compile | 0 | rien à faire |
| **E** stubs C | `enter_blocking_section` / `leave_blocking_section` / `alloc_tuple` : les noms hérités sans préfixe ont disparu des en-têtes OCaml 5 (compilaient en *implicit declaration*, échec au lien) | 3 lignes, 1 fichier | **corrigé** : préfixe `caml_`, alignement à l'identique sur la version circa du stub |
| **F** warnings promus | `warning 34 [unused-type-declaration]` : alias de type d'objet jamais référencé — `bin/simulation_level.mli:265` (`as 'b`), `bin/user_level.mli:159` (`as 'c`) | 2 | trivial : supprimer l'alias |

**Preuve que la liste est exhaustive** : un build avec ces cinq points neutralisés (les deux
correctifs réels + une sonde jetable sur `table.ml` et les deux alias) donne **`rc=0`** —
`lib/` **et** `bin/` compilent intégralement sur 5.4.1. La sonde a été retirée ; l'état réel du
dépôt est `rc=1` avec l'erreur `table.ml` et le premier `warning 34`.

**Conclusion : l'approche « rester sur camlp4 » (D3) est validée.** La catégorie A, qu'on
craignait éliminatoire, se résout par une seule dépendance (`camlp-streams`).

### 4.1 Le seul vrai problème : les tables faibles (`Ephemeron`)

`lib/STRUCTURES/table.ml` construit deux objets de **même type** (`('a,'b) Table.t`, cf.
`table.mli`) : l'un sur `Hashtbl.Make`, l'autre — `new_weaktbl` — sur `Ephemeron.K1.Make`.
Le type d'objet exige `fold`, `iter`, `filter_map_inplace`, `to_list`, `to_assoc_list` ; OCaml 5
ne les fournit plus pour les éphémérons.

**La solution de circa n'est pas transposable.** Circa a mis `assert false` sur ces cinq méthodes
(`lib/ocamlbricks/table.ml` lignes ~190-200) — acceptable chez lui, où les tables faibles ne sont
pas itérées. Ici elles **le sont** :

| Appelant | Méthode disparue |
|---|---|
| `lib/CHANNEL/channel.ml:147` | `wt#to_assoc_list` (table faible créée l. 117) |
| `lib/CHANNEL/channel.ml:320` | `wt#filter_map_inplace` (table faible créée l. 286) |
| `lib/STRUCTURES/hashset.ml:81,88` | `table#fold` — et `Hashset.make ~weak:()` est utilisé par `lib/CHANNEL/lock_clubs.ml:258` |
| `lib/STRUCTURES/hashset.ml:30` | `to_hashtbl`, qui passe par `to_assoc_list` |

Reprendre `assert false` **planterait à l'exécution**. C'est la validation empirique de la
décision D2 : le diff circa se consulte, il ne se copie pas.

Pistes envisagées, **tranchées à l'épisode 2** :

1. **Ré-implémenter une table faible itérable** au-dessus de `Ephemeron.K1.t` bruts + un `Hashtbl`
   interne — c'est ce que faisait `Ephemeron.K1.Make` avant 5.0. Sémantique préservée, zéro
   dépendance ; le plus de travail, et il faut assumer explicitement l'*unsoundness* que l'amont a
   voulu supprimer. → **RETENUE** (§ 5, épisode 2).
2. **Dégrader les tables faibles en tables fortes** (`new_weaktbl = new_hashtbl`, `clean` = no-op).
   Trivial — c'est la sonde qui a donné `rc=0` — mais **change la sémantique mémoire** : ces tables
   sont les *books* globaux de `channel.ml`/`lock_clubs.ml`, conçus pour laisser mourir leurs clés.
   → **REJETÉE** : `Club2UC_book` (`channel.ml:286`) lie `Club.t -> uc` où `uc.cc` **contient les
   clubs** ; en table forte aucun club ne meurt jamais et `get_orphan_ids` devient un no-op. Le
   rejet est empirique et non spéculatif : le test 4 de la preuve de l'épisode 2 (donnée
   référençant sa propre clé) **échoue** si l'on retire `~weak:()`.
3. **Restreindre le type d'objet** : sortir `fold`/`iter`/… du type commun et adapter les 4 sites
   appelants. → **REJETÉE** : les appelants itèrent *réellement* des tables faibles ; restreindre
   le type déplace le problème chez eux au lieu de le traiter, en cassant l'interface publique de
   `Table` et `Hashset`.
4. **Dépendance externe** fournissant une table faible itérable. → **REJETÉE** (YAGNI) : la Stdlib
   5.4.1 suffit, `Ephemeron.K1.make`/`query` et `Weak` restent disponibles.

---

## 5. Journal d'avancement

### Épisode 0 — 2026-07-26 — ouverture du chantier

- Prémisse du gel 4.13.1 **invalidée** (§ 1) : `camlp4.5.4` disponible et installé, précédent circa.
- Décisions D1-D4 arrêtées avec l'auteur (§ 2).
- État des lieux mesuré (§ 3) : 98 + 55 `.ml`, 30 modules communs avec circa dont 8 identiques,
  `Pervasives` dans 3 fichiers, aucun `Stream`/`Genlex`, stubs C sans *naked pointer*.
- Supports durables créés : cette doc, la fiche mémoire `migration-ocaml5`, le pointeur `CLAUDE.md`.

### Épisode 1 — 2026-07-26 — section `dependencies` du Makefile + premier build

**1a. Refonte de la section `dependencies` du `Makefile`** sur le modèle de
`~/DEVEL/repos/circa/Makefile` (lignes 13-121), qui est mieux structurée. Corrigé :

| Défaut | Correctif |
|---|---|
| Cible monolithique | `apt-dependencies` / `opam-switch` / `opam-dependencies`, agrégées par `dependencies` |
| `dpkg -l $(REQUIRED_PACKAGES)` — réussit même quand un paquet manque | boucle `dpkg-query -W -f='$${Status}' … \| grep -q "ok installed"`, `sudo apt install` **seulement** sur les manquants |
| `opam update -y && opam upgrade -y` inconditionnel | retiré du chemin par défaut ; opt-in `make dependencies OPAM_UPDATE=yes` |
| `opam install -y $(OPAM_PACKAGES)` sur la liste entière | **seulement les absents** : repasser un paquet déjà installé le force à sa dernière version (critère `-notuptodate(request)` du solveur) et recompile le switch |
| Paquets non justifiés | un commentaire par paquet |
| `OPAM_SWITCH_TO = 4.13.1` | `= 5.4.1`, avec la justification du choix (§ 1) |
| Outillage mêlé au requis | `OPAM_PACKAGES` (build) vs `OPAM_PACKAGES_DEV` (`utop odoc ocamlformat ocaml-lsp-server`) |

Écarts assumés avec circa : pas de cible `check-cxx` (Marionnet n'a pas de C++), et
`REQUIRED_PACKAGES` révisé — `bzr` retiré (`bin/meta.ml.maker.sh` lit git depuis l'épisode 2 de
`finitions-port-dune`), `liblablgtk3-ocaml-dev` retiré (c'est le lablgtk3 *Debian*, redondant avec
celui d'opam ; ce qu'il faut réellement, ce sont les en-têtes C), `libgtk-3-dev`, `pkg-config`,
`build-essential` et `gettext` ajoutés — ils étaient requis de fait et non déclarés.
L'alias historique `switch:` est conservé.

**1b. Premier build sur 5.4.1** : inventaire complet au § 4. Deux correctifs réels appliqués dans
la foulée, car sans eux dune saute tout l'aval et il n'y a **aucun** inventaire à produire :

- `lib/dune` : `-package camlp4,camlp-streams` dans les 7 `(rule)` de préprocesseurs ;
- `lib/EXTRA/waitpid-c-wrapper.c` : préfixe `caml_` sur les 3 noms hérités (le fichier devient
  **identique** à celui de circa — premier cas d'application de D2).

Une dépendance manquante a aussi été révélée : le paquet opam **`dune-site`** (déclaré dans
`dune-project` et utilisé par `i18n/dune`, mais absent de `OPAM_PACKAGES`). Ajouté au Makefile.

Effet de bord constaté à l'installation : bien que la cible `opam-dependencies` ne passe au
solveur que les paquets **absents**, l'installation de `lablgtk3` & co. a entraîné la montée de
`dune` 3.19 → 3.23.1 et donc la **recompilation du switch entier**. Le garde-fou borne la
*requête*, pas la liberté du solveur sur les dépendances : à savoir, ce n'est pas une régression
du Makefile.

### Épisode 2 — 2026-07-27 — tables faibles itérables (le seul vrai problème)

Piste 1 du § 4.1 retenue, les trois autres rejetées (justifications au § 4.1). **Un seul fichier
modifié : `lib/STRUCTURES/table.ml`** ; `table.mli` reste **inchangé**, donc aucun impact sur les
appelants (`channel.ml`, `hashset.ml`, `tS_memo.ml`, `lock_clubs.ml`).

Un module interne `Weaktbl` (non exporté — `table.mli` ne le mentionne pas, signature explicite
dans le `.ml`) reconstruit ce que `Ephemeron.K1.Make` fournissait avant 5.0, au-dessus des seules
primitives restées disponibles en 5.4.1 : `Ephemeron.K1.make`/`query` et le module `Weak`. Une
liaison est un enregistrement `{ kw : 'k Weak.t (* taille 1 *); mutable eph : ('k,'d) Ephemeron.K1.t }`,
indexé dans un `Hashtbl` interne par le **hash** de sa clé (structure d'`Ephemeron.K1.Make`).

**Les deux mécanismes sont nécessaires, chacun pour sa raison** :

- l'**éphémère**, parce que la donnée ne doit pas maintenir sa propre clé en vie — cas réel de
  `Channel.Club2UC_book`, où la donnée (une conjonction) contient les clubs qui servent de clés :
  une clé faible avec une donnée forte fuirait ;
- le **pointeur faible**, parce que `Ephemeron.K1.query` exige la clé **en argument** et que 5.x
  n'offre aucun moyen d'extraire la clé d'un éphémère : sans source de clés énumérable et non
  rétentive, l'itération est impossible.

Points d'implémentation notables :

- `add` = `Hashtbl.add` (multi-liaisons et ordre « plus récent d'abord » de `find_all` conservés) ;
- `remove` reconstruit le *bucket* au lieu d'appeler `Hashtbl.remove`, qui retirerait la liaison la
  plus récente du **hash** — potentiellement une autre clé (collision) ou une entrée morte ;
- `replace` réinitialise le pointeur faible **et** l'éphémère (la clé stockée devient la nouvelle,
  comme `Hashtbl.replace`) ; `filter_map_inplace` recrée l'éphémère (5.x n'a pas de `set_data`) ;
- **nettoyage automatique amorti** (`clean_at`) : `Ephemeron.K1.Make` nettoyait au redimensionnement.
  Sans cela les entrées mortes s'accumulent là où aucune alarme GC n'appelle `clean` — cas de
  `Hashset.make_physical_compare`, qui insère une entrée par objet comparé ;
- `stats_alive` : seul `num_bindings` est exact (histogramme calculé sur une copie des vivants) ;
  c'est suffisant pour l'usage, qui est du log/debug dans `channel.ml`.

**Sûreté assumée et documentée dans le code** : itérer des structures faibles est *unsound* quand
plusieurs *domains* tournent en parallèle — c'est la raison du retrait amont. Le code n'utilise pas
`Domain` (threads seulement, GTK sur le thread principal) ; un usage multi-domaines imposerait de
revoir ce module.

**Preuve** (`table.ml` ne dépend que de la Stdlib, donc se compile seul) : copie hors dépôt
compilée par `ocamlfind ocamlopt` sur 5.4.1 **contre le vrai `table.mli`**, plus 7 tests exécutés,
tous verts : (1) l'exemple documenté du `.mli` — après `Gc.full_major` + `clean`,
`stats_alive.num_bindings = 0` ; (2) multi-liaisons `add`/`find_all`/`find`/`remove`/`replace`/
`find_or_bind` ; (3) `fold`/`iter`/`filter_map_inplace`/`to_list`/`to_hashtbl` ; (4) **donnée
référençant sa propre clé** → collectée ; (5) collisions de hash → `find_all`/`remove` exacts ;
(6) 1000 clés éphémères → table bornée à 8 liaisons (nettoyage amorti) ; (7) non-régression des
tables fortes. Contre-épreuve : le test (4) **échoue** si la table est rendue forte, ce qui valide
à la fois le test et le rejet de la piste 2.

### Épisode 3 — 2026-07-27 — les 2 `warning 34` et le build vert

Suppression des deux alias de type d'objet jamais référencés (`bin/simulation_level.mli:265`,
`as 'b` ; `bin/user_level.mli:159`, `as 'c`) — catégorie F du § 4.

**`dune clean && dune build` → `rc=0`** sur le switch 5.4.1 (`marionnet.exe` produit). L'état
transitoire « `main` ne compile pas », assumé depuis la coupure nette (§ 4 et D1), est **terminé**.

Reliquat mineur, non bloquant, laissé en l'état : le build émet une alerte
`ocaml_deprecated_auto_include` (une `(rule)` de préprocesseur camlp4 de `lib/dune` utilise `Unix`
sans le déclarer ; le répertoire `unix/` est ajouté automatiquement). Correctif éventuel : ajouter
`unix` au `-package` de la règle concernée.

**Rappel : compiler ≠ fonctionner.** Rien n'est encore vérifié à l'exécution sous le runtime
OCaml 5 (threads, `Unix.fork`, signaux, GTK) — c'est l'objet de l'épisode suivant.

### Épisode 4 — 2026-07-27 — le runtime : Marionnet **tourne** sur 5.4.1

Premier épisode d'exécution. Méthode : zéro code de test neuf (on exploite l'existant), preuves du
moins couplé au plus couplé, puis un scénario GUI réel piloté par l'auteur.

**Preuves obtenues, dans l'ordre :**

| Preuve | Commande | Résultat |
|---|---|---|
| build + tests existants | `dune build`, `dune test` | `rc=0` (le `test/marionnet.ml` vide exécute toutes les initialisations top-level d'`ocamlbricks`) |
| résolution des chemins | `marionnet.exe --paths` | `rc=0` |
| `fork`/`waitpid`/sudo/iproute2 | `tap_provider_test.exe --live` | `rc=0`, **tous les checks** (dont *exit of a forked child* et *orphan collector*) |
| GUI, cycle complet | 2 machines trixie + hub + câbles, `linux-6.12.95` ×2 réellement lancés, arrêt, `quit` | `rc=0`, aucun processus orphelin |
| connectivité entre invités | `ping` de `m1` vers `m2` à travers le hub | **OK** (observé en GUI) |
| X11 dans l'invité + `fork` | `xeyes` dans une machine trixie | **affiché** ; 2 connexions acceptées sur `172.23.0.254:6000`, une par *fork*, « *Protocol completed … Exiting* » |

**Note d'environnement (pas un bug).** En profil *testing*, `Meta.prefix` vaut
`$OPAM_SWITCH_PREFIX` : le changement de switch a déplacé les chemins vers
`~/.opam/5.4.1/share/marionnet`, alors que noyaux et rootfs sont installés sous `/usr/local`. On
lance donc depuis l'arbre de build avec `MARIONNET_PREFIX=/usr/local/share/marionnet`
(variable déclarée dans `bin/configuration.ml`), sans rien modifier. Prérequis hôte annexe : la
règle `/etc/sudoers.d/marionnet` (`bin/scripts/marionnet-sudoers.sh install`), absente de la
machine de test, sans laquelle `Tap_provider` échoue proprement sur `sudo -n`.

#### La régression : `Thread.exit` ne termine plus le thread depuis OCaml 5.0

Symptôme : à la fermeture, le log passait de ~700 à **182 649 lignes**, avec **90 863** paires
alternées « *Exiting the LEDgrid manager blinker thread* » / « *can't understand the message* » —
une boucle à 100 % CPU jusqu'à ce que le thread principal tue ses fils.

Cause racine, dans `bin/gui/ledgrid_manager.ml` (thread *blinker* du gestionnaire de LEDs) :
`thread.mli` de 5.4.1 documente que `Thread.exit ()` est **déprécié** et se contente désormais de
**lever `Thread.Exit`** (« *@before 5.0 A different implementation was used, not based on
raising* »). Or l'appel était placé dans un `try` dont le gestionnaire est un **catch-all
`with _`** : l'exception y était avalée, la boucle `while true` repartait sur un socket **déjà
fermé** juste au-dessus, `recvfrom` échouait dans un autre `try … with _ -> ()`, le buffer
inchangé redonnait le même message — et ainsi de suite.

Correctif (minimal, un seul fichier) : sortie de boucle explicite par un drapeau
(`let finished = ref false in while not !finished do …`), positionné **avant** la fermeture du
socket, à la place de `Thread.exit ()`. Aucune exception ne traverse plus les catch-all.

**Preuve du correctif** — même scénario rejoué en GUI :

| | avant | après |
|---|---|---|
| lignes de log | 182 649 | **691** |
| « can't understand the message » | 90 863 | **0** |
| « Exiting … blinker thread » | 90 863 | **1** |
| sortie de l'application | `rc=0` | `rc=0` |

#### Les trois autres sites de `Thread.exit`, examinés et **laissés en l'état**

- `lib/EXTRA/threadExtra.ml:363` et `:386` — l'appel est en fin de gestionnaire `with e -> …`,
  aucune clause ne peut avaler `Thread.Exit` : elle remonte au *wrapper* de `Thread.create`, qui
  la traite silencieusement. Comportement **inchangé** par rapport à 4.13.1.
- `lib/STRUCTURES/network.ml:264` — fin normale de `server_fun`, dans le `thread_forking_loop` de
  `Network.server`. Sous 5.x, `Thread.Exit` y serait interceptée par le `with e` de
  `ThreadExtra.create`, qui journaliserait un « *Terminated by uncaught exception* » trompeur.
  **Mais cette boucle est du code mort dans Marionnet** : elle n'est atteinte que par
  `~no_fork:()`, or `bin/x.ml:228` fixe `no_fork = None` (« *Yes fork, i.e. create a process for
  each connection* ») et les deux variantes « threads » sont commentées (`x.ml:229`,
  `machine.ml:886`). Le run le confirme : les connexions X11 de `xeyes` sont servies par
  *fork* (« *Process (fork) created for connection #1* »), jamais par un thread. Non modifié :
  corriger un chemin mort, non exercé, serait un changement non vérifiable.

#### Reliquat qualifié, non traité

À la fermeture, deux threads sortent sur `Ocamlbricks.Network.Accepting(_)` (journalisé
« *Terminated by uncaught exception* »). Ce sont les threads `inet4` et `inet6` du service X11
*dual stack* (`0.0.0.0:6000 → /tmp/.X11-unix/X0`, `bin/x.ml`), arrêtés **volontairement** :
`ThreadExtra.set_killable_with_thunk` déclenche un `Unix.shutdown` du socket d'écoute, ce qui fait
échouer l'`accept` en cours et lever `Accepting`. L'alerte est trompeuse, le comportement est
nominal. Rien ne permet de l'attribuer à OCaml 5 sans contre-épreuve sur 4.13.1, laquelle n'est
plus compilable (D1).

---

### Épisode 5 — 2026-07-27 — l'installation : `make install-for-testing` sous 5.4.1

Après l'épisode 4 (le programme **tourne**), le maillon jamais rejoué depuis le changement de switch
était la **chaîne d'installation** : les stanzas `(install)` de `bin/dune` (glade, images, `share/`,
scripts) et de `i18n/dune` (12 catalogues `.mo` dans le site dune-site `locale`), plus les symlinks
kernels/filesystems ajoutés par le `Makefile`.

**Périmètre décidé : le profil `testing` seulement** — `make install-for-testing`, c'est-à-dire
`dune install` **sans** `--prefix` (donc dans `$OPAM_SWITCH_PREFIX = ~/.opam/5.4.1`), sans `sudo`,
réversible par `dune uninstall`. L'installation finale (`make install-final-as-root`, `/usr/local`)
est renvoyée à un épisode ultérieur : elle force d'abord un `make rebuild-for-final` (bascule du
symlink `CONFIGME.choice` + `make clean && make all`) et écrit en root — un pas séparé, à décider par
l'auteur.

#### Preuves obtenues

| Preuve | Commande | Résultat |
|---|---|---|
| build propre | `dune clean && dune build` | `rc=0` (≈ 22 s) |
| tests existants | `dune test` | `rc=0` |
| installation | `make install-for-testing` | `rc=0` ; `which marionnet.native marionnet_telnet.sh` → `~/.opam/5.4.1/bin/` |
| catalogues i18n | `find …/share/marionnet/locale -name marionnet.mo` | **12** (`de el eo es fr it pt pt_BR ro ru sk tr`), en `<lang>/LC_MESSAGES/marionnet.mo` |
| ressources | `ls …/share/marionnet/` | `gui/gui_glade3.xml` (+ `.README`), `share/` (6 fichiers dont `marionnet.conf`, `id_rsa_marionnet`), `images/` (**197** fichiers), `scripts/` (2, exécutables) |
| kernels / filesystems | `ls -l …/share/marionnet/{kernels,filesystems}` | symlinks vers `/usr/local/share/marionnet/…` (3 noyaux + configs, images wheezy/trixie/guignol/lenny…) |
| binaire installé | `marionnet.native --version` | `rc=0` — « marionnet version trunk revno 679 » |
| résolution des chemins | `marionnet.native --paths`, **sans** `MARIONNET_PREFIX`, hors de l'arbre de build | `rc=0`, tout résolu sous `~/.opam/5.4.1/share/marionnet/` |
| i18n bout en bout | `LANG=fr_FR.UTF-8` / `it_IT.UTF-8` / `C` sur un `.mar` inexistant | message d'erreur d'`initialization.ml` en **français**, en **italien**, en **anglais** — `rc=1` (attendu) |
| catalogue réellement chargé | `strace -f -e trace=openat` sur le même lancement | un **seul** `marionnet.mo` ouvert : `~/.opam/5.4.1/share/marionnet/locale/fr/LC_MESSAGES/marionnet.mo` |
| extraction POT (camlp4) | `make gettext-messages-pot` | `rc=0`, 372 `msgid` extraits — la chaîne camlp4 `gettext_extract_pot_p4` fonctionne sur 5.4.1 |

#### La note d'environnement de l'épisode 4 est levée

L'épisode 4 devait lancer avec `MARIONNET_PREFIX=/usr/local/share/marionnet` parce qu'en profil
*testing* `Meta.prefix` vaut `$OPAM_SWITCH_PREFIX` et que `~/.opam/5.4.1/share/marionnet` était
**vide**. `install-for-testing` le peuple : `dune install` y dépose ressources et catalogues, puis le
`Makefile` y crée les symlinks `kernels/` et `filesystems/` vers `/usr/local`. Le lancement sans
`MARIONNET_PREFIX` résout désormais tout, **y compris depuis l'arbre de build**
(`_build/default/bin/marionnet.exe --paths` donne les mêmes chemins) : ce n'est donc pas le binaire
installé qui règle la question, c'est le **préfixe peuplé**.

#### Piège relevé : la preuve i18n « en français » n'est pas discriminante

Afficher du français ne prouve rien à soi seul. Deux catalogues concurrents traînent sur cette
machine — `/usr/local/share/marionnet/locale/fr/…/marionnet.mo` (install finale du 2026-07-19) et
`/usr/share/locale/fr/LC_MESSAGES/marionnet.mo` (2023) — et le dernier recours de `bin/gettext.ml`
(`try_to_infer_localeprefix_searching_marionnet_dot_mo_in_usr`, un `find /usr`) trouve le second :
en masquant temporairement le site dune installé, la sortie **reste** en français. C'est `strace` qui
tranche : site présent, un seul `.mo` est ouvert, celui du site dune. Retenir la méthode — pour
prouver *quel* catalogue sert, tracer les `openat`, ne pas se fier à la langue affichée.

#### Correctif embarqué : l'alerte `ocaml_deprecated_auto_include`

Reliquat qualifié à l'épisode 1, traité ici parce qu'il appartient bien à la migration : depuis
OCaml 5.0 le répertoire `unix` n'est plus dans le chemin de recherche par défaut, et
`lib/CAMLP4/include_as_string_p4.ml` (seul préprocesseur du lot à appeler `Unix.openfile`/`Unix.read`)
était compilé sans le déclarer. Correctif dans `lib/dune` : `unix` ajouté au `-package` des 7 `(rule)`
camlp4 (14 invocations `ocamlfind ocamlc`), suivant la règle d'uniformité déjà en vigueur pour
`camlp-streams`, commentaire du bloc mis à jour. **Preuve** : `dune clean && dune build` — le log
complet passe de l'alerte + `Success.` à `Success.` seul, `rc=0`.

#### Hors périmètre, explicitement

- **`make install-final-as-root`** (`/usr/local`, root) : non joué — décision de l'auteur.
- **RPM** (`RPMS/`, cible `make rpms`) : `rpmbuild` est **absent** de cette machine Kubuntu ; la
  cible reste **non testée** sous 5.4.1, comme elle l'était sous 4.13.1.
- **`bin/po/messages.pot`** : l'extraction ci-dessus le régénère et produit un diff **réel** (le
  texte d'aide `world_bridge` réécrit par le chantier `modernisation-world-bridge` n'y figurait pas).
  Ce diff appartient à ce chantier-là, pas à celui-ci : le fichier versionné a été **restauré**. À
  traiter lors de la prochaine passe i18n.

---

## 6. Bilan et clôture (2026-07-27)

### Ce que le chantier a livré

En deux jours et sept épisodes, sur `main` en historique linéaire :

| | Preuve | Épisode |
|---|---|---|
| **Compile** | `dune clean && dune build` `rc=0` sur 5.4.1 | 1→3 |
| **Tourne** | `dune test`, `tap_provider_test --live`, cycle GUI réel (2 machines trixie + hub, ping, `xeyes`) | 4 |
| **S'installe** | `make install-for-testing` `rc=0`, 12 catalogues `.mo`, `--paths` sans `MARIONNET_PREFIX` | 5 |

**Trois modifications de code au total** — c'est la mesure honnête de l'effort réel :
`lib/STRUCTURES/table.ml` (module interne `Weaktbl`, ép. 2), deux alias de type inutilisés
(ép. 3), `bin/gui/ledgrid_manager.ml` (`Thread.exit`, ép. 4) ; plus deux correctifs de build
(`lib/dune`, `lib/EXTRA/waitpid-c-wrapper.c`, ép. 1 et 5).

Le chantier avait été ouvert (ép. 0) en démontrant que sa propre justification officielle était
fausse : le gel n'était pas imposé par camlp4 (`camlp4.5.4` existe, le projet frère `circa` le
prouvait). Cette inversion de prémisse est ce qui a rendu le reste presque gratuit.

### Hors périmètre, assumé

- **`make install-final-as-root`** (root, `/usr/local`) : **non joué**, sur décision explicite de
  l'auteur. La recette n'a rien de spécifique à OCaml 5 (elle enveloppe `dune install --prefix`,
  déjà exercé en profil *testing*), mais ce n'est pas une preuve — si un jour elle échoue, ce
  document ne prétend pas le contraire.
- **RPM** (`RPMS/Makefile`) : `rpmbuild` est absent de la machine de développement ; non testé sous
  5.4.1, comme il ne l'était pas sous 4.13.1.
- **`bin/po/messages.pot`** : en retard sur les chaînes de `modernisation-world-bridge` ; relève de
  la prochaine passe i18n, pas de ce chantier (constaté à l'ép. 5).

### Ce qui reste à rendre à l'upstream — décision D4 réévaluée

D4 prévoyait de rétro-propager les correctifs vers `~/DEVEL/repos/ocamlbricks` « en fin de
chantier ». Vérification faite à la clôture, **cette étape n'appartient pas à ce chantier** :
l'upstream est en **bzr**, **sans dune** (build ocamlbuild/Makefile historique), et n'est pas porté
sur OCaml 5. Rien n'y serait *prouvable* sans le porter d'abord — ce qui est un chantier en soi.

Matériau relevé, pour qui l'ouvrira :

| Correctif | Transposable ? |
|---|---|
| `EXTRA/waitpid-c-wrapper.c` | **oui, tel quel** — 21 lignes de diff : `enter/leave_blocking_section` → `caml_enter/leave_blocking_section`, `alloc_tuple` → `caml_alloc_tuple` |
| `STRUCTURES/table.ml`, module `Weaktbl` | **oui, mais à isoler** — les deux copies divergent de ~399 lignes depuis 2023 ; ne reprendre que le module interne, jamais le fichier en bloc (D2) |
| `lib/dune` (`-package …,unix`) | **non** — l'upstream n'a pas de dune ; l'équivalent y serait un flag ocamlbuild/`_tags` |

Prérequis d'un tel chantier : porter l'upstream (98 modules, ocamlbuild + camlp4) sur 5.4.1, la
copie Marionnet servant alors de référence de ce qui casse et de comment le réparer.

### Effet sur les autres chantiers

`camlp4 → ppx` perd sa justification principale : il n'y a plus de gel de toolchain à lever, il ne
reste que la dégradation **Merlin/LSP/ocamlformat** sur les fichiers préprocessés. À re-prioriser
en conséquence — cf. `docs/camlp4-to-ppx.md`.
