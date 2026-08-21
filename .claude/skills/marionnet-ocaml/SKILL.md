---
name: marionnet-ocaml
description: Travail sur le code OCaml de Marionnet (bin/ et lib/, hors uml/) — outillage d'intelligence de code (ocamllsp via plugin, odoc, sherlodoc, opam), règles d'écriture maison, conventions de documentation odoc, et pièges camlp4 dont l'inapplicabilité d'ocamlformat. Charger avant d'écrire ou de modifier un .ml/.mli, avant de chercher « est-ce que ça existe déjà dans ocamlbricks ? », ou avant de documenter un module.
---

# Code OCaml de Marionnet — outillage et règles

**Périmètre** : `bin/` (cœur applicatif + GUI) et `lib/` (ocamlbricks vendorisé, dont tu es
l'auteur). **Hors périmètre** : `uml/` (Bash, noyaux, rootfs → skill `marionnet-pupisto`) et
`bashbricks/` (→ skill `use-bashbricks`).

## Ne pas réinventer la roue : chercher AVANT d'écrire

Réflexe obligatoire avant d'écrire une fonction utilitaire (chaînes, listes, tableaux, options,
processus, réseau…) : **ocamlbricks l'a probablement déjà**. Trois portées, de la plus proche à
la plus lointaine :

1. **Dans ocamlbricks et le projet — recherche PAR TYPE** (`sherlodoc`, paquet opam) :

   ```bash
   dune build @doc-private                                    # produit les .odocl (474 pages HTML)
   find _build -name '*.odocl' -print0 \
     | xargs -0 sherlodoc index --db=_build/sherlodoc.marshal  # index régénérable
   sherlodoc search --db=_build/sherlodoc.marshal "string -> string list"
   sherlodoc search --db=_build/sherlodoc.marshal "split"      # ou par nom
   ```

   L'index couvre `ocamlbricks`, `marionnet_base`, `marionnet_tap`, `marionnet_sites`. Il vit dans
   `_build/` : jetable, à reconstruire après un `dune clean`.

2. **Dans l'écosystème opam — par nom/synopsis, hors ligne** : `opam search <mot>`, `opam show <p>`.
   L'index local se périme silencieusement (il datait d'un an en 2026-08) : `opam update` d'abord
   si la recherche paraît pauvre.

3. **Dans l'écosystème opam — par type/documentation** : `https://ocaml.org/packages/search?q=…`
   (moteur sherlodoc en ligne, couvre tout opam). À consulter par WebFetch.

**Rappel projet** : Marionnet vendorise ses dépendances. Trouver un paquet opam ≠ l'ajouter —
toute nouvelle dépendance passe par `OPAM_PACKAGES` du `Makefile` et par les canaux de packaging
(chantier `modernisation-installation-marionnet`).

## Intelligence de code : ocamllsp

Le dépôt fournit un plugin local (`.claude-plugin/marketplace.json` → `.claude/plugins/ocaml-lsp`)
qui déclare `ocamllsp` comme serveur de langage pour `.ml`/`.mli` : types, définition, références,
diagnostics — sans lire les fichiers en entier.

- Il utilise l'`ocamllsp` **du PATH**, donc du switch opam courant : celui-ci doit être celui que
  déclare le `Makefile` (`OPAM_SWITCH_TO`). Vérifier par `opam switch show`.
- Il exige des artefacts frais : **`dune build` d'abord**, sinon les types sont périmés ou absents.
- Il fonctionne sur les fichiers **préprocessés camlp4** (dune passe sa commande `(preprocess …)`
  telle quelle au serveur ; cf. `CLAUDE.md` § Build). Restent aveugles : les 7 sources de
  préprocesseurs elles-mêmes.

## Graphe inter-modules : déjà installé ici

Le graphe de dépendances **inter-modules** du dépôt existe : `make module-graph` produit
`_build/module-graph/module-graph.{deps,dot,svg}` (156 nœuds, 975 arêtes, ~30 s), et
`make module-graph-check` le revalide contre l'`ocamldep` de dune. À interroger **avant**
tout refactor non trivial : appelants d'un module, appelés, rayon d'impact transitif.

- Requêtes, pièges et procédure : skill global **`ocaml-code-graph`** — ne pas les redécouvrir ici.
- Complément indispensable : **`make check`** (`dune build @check`) typecheck *tous* les modules,
  ce que `dune build` ne fait pas (clôture atteignable depuis `marionnet.ml` seulement) ; il
  conditionne `make ocaml-index`, donc les *references* exactes d'`ocamllsp` ci-dessus.
- Granularité **module**. Pour « qui appelle cette fonction ? » → `ocamllsp`, pas le graphe.

## ocamlformat : inapplicable ici (fait établi, pas une préférence)

`ocamlformat` **échoue** sur ce dépôt, il ne s'agit pas d'un choix de style :

```
$ ocamlformat --enable-outside-detected-project bin/gettext.ml
ocamlformat: ignoring "bin/gettext.ml" (syntax error)
File "bin/gettext.ml", line 74: IFDEF DOCUMENTATION_OR_DEBUGGING THEN
```

Il analyse avec le parser OCaml standard, qui ne connaît ni `IFDEF … THEN`, ni la syntaxe de
`where_p4`, ni `INCLUDE DEFINITIONS`. Tant que le chantier `camlp4-to-ppx` n'est pas fait,
**ne jamais** proposer un formatage automatique, ni un outil qui en applique un en écrivant
(c'est la raison pour laquelle le serveur MCP `ocaml-mcp` a été écarté : son `fs/write` formate).
Le style se tient à la main, en imitant le fichier voisin.

## Documenter : odoc, lui, fonctionne

Contrairement à ocamlformat, **odoc traverse camlp4** (il consomme les `.cmt`/`.cmti` produits
*après* préprocessing). Vérifié : `dune build @doc-private` → **474 pages HTML**, `exit 0`.

- `dune build @doc` ne rend que la page d'index (aucune bibliothèque n'a de `public_name`) :
  la cible utile ici est **`@doc-private`**.
- Sortie : `_build/default/_doc/_html/index.html`.
- Conventions à appliquer au code neuf ou retouché :
  - commentaire `(** … *)` sur toute **interface publique** — en priorité les `.mli` des modules
    « bibliothèque » de `lib/` ;
  - `@param`, `@return`, `@raise` pour ce qui est visible de l'appelant ;
  - **invariants, préconditions, postconditions** énoncés explicitement (règle OCaml de l'auteur) ;
  - documenter le *contrat*, pas la mécanique : le corps se lit tout seul.

## Règles d'écriture (deltas propres au dépôt)

- **En-tête de tout `.ml`** : bloc GPL puis bloc d'alias `module X = Ocamlbricks.X` — **pas d'`open`**.
- **`Result` plutôt qu'exceptions** pour les erreurs récupérables ; types explicites sur les
  interfaces publiques.
- **`.mli` sélectifs**, comme l'existant : oui pour les modules « bibliothèque », non pour les
  composants et les écrans.
- **`Obj.magic`** (25×, jointures user/simulation level) : dette tolérée, à réduire **à l'occasion**
  quand on touche ces fichiers — pas de campagne dédiée.
- **Piège camlp4 durable** : `let*` (binding operators) n'est **pas** connu de camlp4 — écrire la
  liaison à la main. Même prudence pour toute syntaxe postérieure à 4.02 dans un fichier préprocessé.
- **GTK** : tout appel GUI depuis un autre thread passe par `gMain_actor` ; le thread GTK ne prend
  jamais le mutex d'un composant (cf. `docs/refonte-automate-composants.md`).
- Fichiers **générés, à ne jamais éditer** : `bin/version.ml`, `bin/meta.ml`. Cas particulier
  `bin/gui.ml` : généré **puis modifié à la main** → on l'édite à la main, on ne le régénère jamais.

## Vérifier avant d'annoncer

`dune build` (code de retour 0) pour « ça compile » ; `dune build @doc-private` pour « c'est
documenté ». Un `ocamllsp` qui ne dit rien n'est pas une preuve : c'est peut-être un build périmé.
