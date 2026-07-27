# Chantier long — migration OCaml 4.13.1 → 5.4.1

*Slug de chantier (scope des commits, `git log --grep`) : `migration-ocaml5`.*

> **Historique linéaire sur `main`**, comme tous les chantiers de ce dépôt. Conséquence assumée
> de la décision D1 (coupure nette) : entre l'épisode 1 et l'épisode 3, `main` **ne compile pas**
> — ni sur 5.4.1 (3 sites restants, § 4) ni, à partir de l'épisode 2, sur 4.13.1. C'est un état
> transitoire connu, pas une régression : `git log --grep="migration-ocaml5"` donne la position
> exacte dans le chantier.

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

Pistes pour l'épisode 2 (à trancher, non tranché) :

1. **Ré-implémenter une table faible itérable** au-dessus de `Ephemeron.K1.t` bruts + un `Hashtbl`
   interne — c'est ce que faisait `Ephemeron.K1.Make` avant 5.0. Sémantique préservée, zéro
   dépendance ; le plus de travail, et il faut assumer explicitement l'*unsoundness* que l'amont a
   voulu supprimer.
2. **Dégrader les tables faibles en tables fortes** (`new_weaktbl = new_hashtbl`, `clean` = no-op).
   Trivial — c'est la sonde qui a donné `rc=0` — mais **change la sémantique mémoire** : ces tables
   sont les *books* globaux de `channel.ml`/`lock_clubs.ml`, conçus pour laisser mourir leurs clés.
   Risque de fuite à évaluer.
3. **Restreindre le type d'objet** : sortir `fold`/`iter`/… du type commun et adapter les 4 sites
   appelants. Honnête, mais touche l'interface publique de `Table` et `Hashset`.
4. **Dépendance externe** fournissant une table faible itérable. À évaluer contre YAGNI.

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
