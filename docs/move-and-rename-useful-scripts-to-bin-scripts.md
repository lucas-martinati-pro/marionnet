# Chantier : remettre les scripts complémentaires du binaire dans `bin/scripts/`

**Slug (commits, mémoire, grep)** : `move-and-rename-useful-scripts-to-bin-scripts`
**Amorce (archive figée)** : `docs/move-and-rename-useful-scripts-to-bin-scripts.decisions.md`
**Nature** : chantier long d'exécution, un script par épisode.

## Destination

Les cinq fichiers complémentaires du binaire ont quitté `useful-scripts/` pour `bin/scripts/`,
chacun sous la forme d'un fichier `.sh` réel entouré de ses liens symboliques ; `useful-scripts/`
ne contient plus que ce pour quoi il a été fait (gestion/installation du projet, guides
développeurs) ; **aucun nom d'usage n'a disparu**, et rien de ce qui les appelle — le binaire, les
catalogues gettext, la documentation livrée, les bancs — n'a cessé de fonctionner.

## 1. La règle fondatrice (énoncée par l'auteur le 2026-08-23)

| Répertoire | Ce qu'il doit contenir |
|---|---|
| `useful-scripts/` | scripts de **gestion / installation du projet** et **scripts-guides** pour développeurs |
| `bin/scripts/` | scripts **complémentaires du binaire** `marionnet.native` |

Elle n'avait jamais été écrite : c'est pourquoi les cinq scripts produits par
`pilotage-par-script`, `journalisation-profonde` et `marionnet-todo-transverse` ont atterri du
mauvais côté. Ce chantier répare cela — et rien d'autre.

## 2. La forme retenue : implémentation `.sh`, interface par liens

| Aujourd'hui (`useful-scripts/`) | Fichier réel (`bin/scripts/`) | Liens symboliques (même répertoire) |
|---|---|---|
| `marionnet-cleanup` | `marionnet-cleanup.sh` | `marionnet-cleanup`, `mrn-cleanup` |
| `mrn-verify` | `marionnet-verify.sh` | `marionnet-verify`, `mrn-verify` |
| `mrn-check` (+`mrn2sh`) | `marionnet-check.sh` | `marionnet-check`, `mrn-check`, `mrnck`, `mrn2sh` |
| `marionnet-ctl` (+`mrnctl`) | `marionnet-ctl.sh` | `marionnet-ctl`, `mrnctl`, `mrn-control` |
| `marionnet-completion.bash` | `marionnet-completion.bash` | *(aucun : ce n'est pas une commande)* |

**Ce que cette forme achète, mesuré avant de choisir** — la migration est **non cassante par
construction**, parce qu'aucun nom existant ne disparaît :

1. **L'i18n ne bouge pas.** `marionnet-cleanup` figure **dans les `msgid`** des **12** catalogues
   (`bin/marionnet.ml` nomme la commande dans l'avertissement de démarrage sur les répertoires de
   session, et l'exécute depuis deux boutons). Un renommage sec aurait imposé un cycle POT et
   douze retraductions ; le lien rend l'opération invisible pour gettext.
2. **Le dispatch par `$0` est intact.** `mrn-check` choisit son mode par `${0##*/}`
   (`[[ $PROGNAME == mrn2sh ]]`) ; `mrn2sh` survit comme lien.
3. **La documentation livrée reste vraie.** Les 21 fichiers de `doc-src/` qui citent `mrnctl`, les
   12 qui citent `mrn-verify`, le skill `marionnet-lab-design` : tous nomment des commandes qui
   existent encore.

Corollaire — **ce qui casse réellement**, et qui constitue donc le travail de chaque épisode :
les **chemins relatifs en dur** vers `useful-scripts/<script>` (les 7 exemples de
`doc-src/scripting/examples/`, deux bancs de `driven-sessions/`), et les **déclarations de build**
(`bin/dune`, `useful-scripts/dune`, la liste blanche du `.gitignore`).

## 3. Invariants à tenir à chaque épisode

- **`git mv`**, jamais copier-supprimer : l'historique d'un script de 24 à 36 Ko doit suivre.
- **Le lien est versionné en tant que lien** (`git ls-files -s` → mode `120000`), comme le sont
  déjà `mrnctl` et `mrn2sh`.
- **`bin/dune` nomme ses fichiers installés un par un** : un fichier non ajouté n'est pas
  installé (c'est ainsi que `marionnet-completion.bash` reste hors de `$(PREFIX)/bin/`).
- **La destination d'installation ne change pas** : `useful-scripts/dune` posait déjà ses fichiers
  dans `share/marionnet/scripts/`, exactement où `bin/dune` pose les siens, et le `Makefile` les
  mirroir dans `$(PREFIX)/bin/`. La migration doit rester **neutre à l'installation**.
- **La liste blanche du `.gitignore` se vide au fil de l'eau** (décision D10 de l'amorce) : la
  ligne `!useful-scripts/<script>` part avec le script.
- **Preuve par épisode** : le banc `driven-sessions/` concerné rejoué, ou à défaut l'appel direct
  du script par chacun de ses noms.

## 4. Plan d'épisodes

| # | Script | Ce qui le rend particulier |
|---|---|---|
| 1 | `marionnet-cleanup` | couplé au **code OCaml** (nommé à l'écran, lancé par deux boutons) et à 2 bancs ; **zéro** citation dans `doc-src/`. C'est aussi lui qui **résout D4** (comment dune traite un lien symbolique) |
| 2 | `mrn-verify` | 12 fichiers de `doc-src/`, le skill `marionnet-lab-design` |
| 3 | `mrn-check` | le **dispatch par `$0`** (`mrn2sh`), 4 liens au lieu de 2 |
| 4 | `marionnet-ctl` | le plus cité (21 fichiers via `mrnctl`) et les **7 exemples** qui construisent `useful-scripts/mrnctl` en dur |
| 5 | `marionnet-completion.bash` | dépend des quatre précédents : elle déclare les noms qu'elle complète (`complete -F … marionnet-ctl mrnctl`), donc elle vient en dernier |
| 6 | *(finition)* | répercussion sur `modernisation-installation-marionnet` (§ 2.4 ter et la disparition de `useful-scripts/dune`), puis clôture |

## 5. Hors périmètre (repris de l'amorce, toujours valides)

- **Renommer les scripts déjà dans `bin/scripts/`** : ils sont au bon endroit, et les portes
  privilégiées y sont nommées **par chemin** dans la règle sudoers — un risque pour un gain nul.
- **Modifier le comportement** d'un script : ce chantier déplace et renomme, il ne change ni une
  option, ni une sortie, ni la grammaire du canal.
- **Installer `doc-src/`** ou décider où va la complétion bash : tâches du chantier
  `modernisation-installation-marionnet`.

## Journal d'avancement

- **2026-08-23 — bascule amorce → exécution.** L'auteur a tranché d'un coup D1 (périmètre),
  D2 (table de nommage) et D3 (sort des anciens noms), ce qui a rendu **caduques** D5 (structure
  interne de `bin/scripts/`), D7 (archives des chantiers clos) et D9 (PDF livrés) — tous trois ne
  se posaient que si un nom disparaissait — et a transformé D8 (inventaire) en travail d'épisode.
  L'amorce est close, `…decisions.md` devient une archive figée.

- **2026-08-23 — épisode 1 : `marionnet-cleanup`.** `git mv` vers
  `bin/scripts/marionnet-cleanup.sh`, plus les liens `marionnet-cleanup` et `mrn-cleanup`
  (versionnés en mode `120000`). Déclarations suivies : `bin/dune` gagne les trois noms,
  `useful-scripts/dune` perd le sien, la liste blanche du `.gitignore` aussi (D10). Renvois
  corrigés là où ils désignaient un chemin devenu faux : `bin/marionnet.ml`,
  `bin/control_server.ml`, `etc/marionnet.conf` — qui est **livré à l'utilisateur** et nomme
  désormais la **commande installée** plutôt qu'un chemin de sources —, `CLAUDE.md` (piège 6) et
  les deux bancs. Les archives de chantiers clos (`docs/todo-transverse.md`…) sont laissées
  telles quelles : elles nomment `marionnet-cleanup`, qui existe toujours.

  **D4 résolu par la mesure** : `dune install --prefix` **déréférence** les liens — les trois noms
  arrivent en trois **copies** de 31 244 octets, sans bit exécutable (que le mirroring du
  `Makefile` ajoute). Ce n'est pas une régression (`useful-scripts/dune` faisait déjà cela) et
  c'est sans effet fonctionnel, les scripts lisant `${0##*/}` et jamais l'inode ; mais c'est un
  fait à connaître pour les canaux d'empaquetage, qui préféreront sans doute de vrais liens.

  **Preuve** : `dune build` rc 0 ; `dune build @install` rc 0 avec les trois noms dans
  `share/marionnet/scripts/` ; les trois noms exécutables et équivalents depuis l'arbre source ;
  et les **deux bancs rejoués** — `uml-dirs-reported.sh` **9 PASS / 0 FAIL**,
  `run-directories-recover-and-purge.sh` **15 PASS / 0 FAIL**.

- **2026-08-23 — épisode 2 : `mrn-verify`.** `git mv` vers
  `bin/scripts/marionnet-verify.sh`, plus les liens `marionnet-verify` et `mrn-verify`
  (mode `120000`). Déclarations suivies : `bin/dune` gagne les trois noms,
  `useful-scripts/dune` perd le sien, la liste blanche du `.gitignore` aussi (D10). Un seul
  renvoi corrigé ailleurs : le commentaire des dépendances du `Makefile`, qui nommait
  `useful-scripts/mrn-check and mrn-verify` — il nomme désormais les deux vérificateurs
  **sans chemin**, énoncé qui restera vrai après l'épisode 3.

  **L'inventaire a démenti le plan** : le § 4 annonçait « 12 fichiers de `doc-src/` », mais
  aucun d'eux — pas plus que le skill `marionnet-lab-design` — ne construit un chemin vers
  `useful-scripts/` : les trois scripts d'exemple prennent le **nom nu** comme défaut
  (`MRN_VERIFY="${MRN_VERIFY:-mrn-verify}"` dans `06-assert-a-lab.sh`, `play.sh`,
  `grade.sh`) et les `.mrv` livrés le citent en commentaire d'en-tête. Aucun banc de
  `driven-sessions/` ne l'appelle non plus. Cet épisode n'a donc rien eu à corriger dans la
  documentation livrée — ce qui est exactement ce que la forme « fichier `.sh` + liens »
  achète, et ce que le § 4 sur-estimait en comptant les **citations** au lieu des **chemins**.

  **Preuve** : `dune build` rc 0 ; `dune build @install` rc 0 avec les trois noms dans
  `share/marionnet/scripts/` ; les trois noms exécutables depuis l'arbre source, `--help`
  identique modulo `$PROGNAME` (48 lignes chacun), et le contrôle hors-ligne d'un `.mrv`
  livré (`doc-src/scripting/examples/lab.mrv`, `--grammar=` sur un instantané de grammaire)
  rendant **le même verdict** par les trois noms — « 7 assertion(s), well formed », rc 0.

- **2026-08-23 — épisode 3 : `mrn-check`.** `git mv` vers `bin/scripts/marionnet-check.sh`, plus
  les **quatre** liens `marionnet-check`, `mrn-check`, `mrnck`, `mrn2sh` (mode `120000`).
  `useful-scripts/mrn2sh` était déjà un lien, mais vers `mrn-check` : il a été `git rm` et refait à
  destination plutôt que déplacé — un lien vers un lien, dont la cible relative allait disparaître,
  aurait été fragile pour rien. Déclarations suivies : `bin/dune` gagne les cinq noms,
  `useful-scripts/dune` en perd deux, la liste blanche du `.gitignore` aussi (D10).

  **`mrnck` est un nom neuf** (table D2) : il n'a demandé **aucune ligne de code**, le dispatch ne
  testant que `[[ $PROGNAME == mrn2sh ]]` — tout autre nom retombe sur le mode normal. Son revers
  est qu'il n'est encore annoncé nulle part : l'usage n'a **pas** été touché (le § 5 met « changer
  une sortie » hors périmètre), c'est la complétion de l'**épisode 5** qui déclarera les noms.

  **Un renvoi de l'épisode 1 rattrapé au passage** : l'en-tête de `useful-scripts/dune` justifiait
  encore l'installation par « Marionnet nomme **l'un d'eux** à l'écran et le lance depuis un
  bouton » — or ce script-là (`marionnet-cleanup`) avait quitté le répertoire à l'épisode 1. Le
  motif est conservé (c'est bien lui qui a tranché la question de l'installation) mais énoncé au
  passé, et le paragraphe dit désormais que la stanza **rétrécit** à mesure que les scripts
  complémentaires du binaire s'en vont.

  **Preuve, plus forte que celle des deux premiers épisodes** : `dune build` rc 0 ;
  `dune build @install` rc 0 avec les **cinq** noms dans `share/marionnet/scripts/` ; `--help`
  identique par les cinq noms (aux trois mentions littérales de `mrn2sh` près, que seul le mode
  `--to-bash` doit voir) ; le contrôle hors ligne de `doc-src/scripting/examples/lab.mrn`
  (`--grammar=` sur un instantané) rendant **le même verdict** — « 9 request(s), no error », rc 0 —
  par `marionnet-check.sh`, `marionnet-check`, `mrn-check` et `mrnck`, tandis que `mrn2sh` sort du
  **bash** sur le même fichier ; et surtout les **deux bancs de l'épisode 9 de
  `pilotage-par-script` rejoués** contre un vrai serveur : **32 assertions / 0 échec** chacun,
  dont le discriminant « le vérificateur et le serveur s'arrêtent à la même ligne, pour le même
  motif ».

  **Leçon de méthode** : ces deux bancs vivent dans `_claude-local/`, **gitignoré** — ils portaient
  donc des chemins durs `useful-scripts/…` que l'inventaire des épisodes précédents, mené sur le
  versionné, n'avait pas vus ; l'un d'eux (`useful-scripts/mrn-verify`) était cassé **depuis
  l'épisode 2**. Le relevé des chemins doit couvrir l'arbre de travail, pas seulement l'index.

- **2026-08-23 — épisode 4 : `marionnet-ctl`.** `git mv` vers `bin/scripts/marionnet-ctl.sh`, plus
  les **trois** liens `marionnet-ctl`, `mrnctl`, `mrn-control` (mode `120000`).
  `useful-scripts/mrnctl` était un lien relatif vers `marionnet-ctl` : `git rm` puis refait à
  destination, comme `mrn2sh` à l'épisode 3. `mrn-control` est un nom neuf (table D2) et n'a coûté
  **aucune ligne de code** — ce client ne dispatche pas sur `$0`, il ne s'en sert que pour son
  `Usage:` — mais, comme `mrnck`, il n'est encore annoncé nulle part : c'est la complétion de
  l'épisode 5 qui déclarera les noms.

  **`useful-scripts/dune` a disparu, avec un épisode d'avance sur le § 4.** Sa stanza `install`
  n'installait plus que ce client : l'épisode la vidait, et une stanza vide est une déclaration qui
  ment. Ce que son en-tête portait encore de vivant — *pourquoi* la complétion bash n'est installée
  nulle part — est passé dans le commentaire de la liste blanche du `.gitignore`, à côté de la
  seule entrée qui reste ; le fond de la question appartient de toute façon à
  `modernisation-installation-marionnet` (§ 2.4 ter). Il ne reste donc **plus aucune déclaration de
  build** dans `useful-scripts/`, et rien n'y est installé — ce qui est cohérent avec la règle
  fondatrice : ce répertoire gère le **projet**, il n'accompagne pas le **binaire**.

  **L'inventaire a de nouveau corrigé le plan** : le § 4 annonçait « les 7 exemples qui construisent
  `useful-scripts/mrnctl` en dur ». Il y en a **six** (`01`–`05`, `07`) ; le septième (`06`) ne
  nomme pas le chemin du client mais dit « the ones in `useful-scripts/` » — vrai jusqu'à
  l'épisode 2, faux depuis. Corrigés avec eux : les trois renvois de
  `doc-src/scripting/examples/README.md` (dont le `MRNCTL=../../../useful-scripts/mrnctl` de son
  mode d'emploi), la ligne de `doc-src/scripting/README.md` — qui, documentation **livrée**, nomme
  désormais la **commande** et ne donne le chemin des sources qu'entre parenthèses —, le
  commentaire `socat` du `Makefile` (nom nu, précédent de l'épisode 2) et
  `bin/CLAUDE-file-overview.md`.

  **Deux renvois d'épisodes précédents rattrapés** : `bin/marionnet.ml` justifiait encore
  l'installation de `marionnet-cleanup` par « `useful-scripts/dune` puts it among the scripts »
  (faux depuis l'épisode 1, et le fichier disparaît ici) ; et `CLAUDE.md` annonçait « 7 versionnés »
  dans `useful-scripts/` alors qu'il en restait 6 — le chiffre a été retiré plutôt que corrigé,
  puisqu'il vieillit à chaque épisode.

  **Bancs locaux** : la leçon de l'épisode 3 a été appliquée d'emblée — les six chemins durs de
  `_claude-local/bench/` (`bench-lib.sh`, `check-bench.sh`, `doc-bench.sh`, `mrn2sh-bench.sh`,
  `completion-bench.sh` ×2) ont été suivis, **et** les deux `useful-scripts/mrn-verify` de
  `verify-bench.sh` et `exec-bench.sh`, cassés depuis l'épisode 2 et oubliés par l'épisode 3.

  **Preuve** : `dune build` rc 0 ; `dune build @install` rc 0 avec les **quatre** noms dans
  `share/marionnet/scripts/` ; `--help` identique par les quatre noms (29 lignes, `diff` vide après
  normalisation du `PROGNAME`) ; et **trois bancs rejoués contre un vrai serveur** —
  `ctl-bench.sh` **36 assertions / 0 échec**, `doc-bench.sh` (qui joue les exemples livrés)
  **66 / 0**, `completion-bench.sh` **60 assertions, 3 échecs**. Ces trois échecs sont **antérieurs
  et étrangers** à cet épisode : le banc attend **7** natures de composants là où le serveur en
  publie **8** depuis la 9ᵉ nature `nat_bridge` (chantier `modernisation-world-bridge`, ép. 7a.3.b,
  2026-08-18). Le banc étant celui de l'épisode 5, sa remise à jour se fera là.

- **2026-08-23 — épisode 5 : `marionnet-completion.bash`.** `git mv` vers
  `bin/scripts/marionnet-completion.bash`, **sans aucun lien** : ce n'est pas une commande, on ne
  l'appelle pas, on la source (D6). Déclarations suivies : la liste blanche du `.gitignore` perd sa
  dernière entrée de ce chantier (D10 — il n'y reste que `make_marionnet_bytecode_revno` et
  `marionnet_from_scratch`), et **`bin/dune` ne la nomme pas** — c'est le mécanisme même qui la
  garde hors de `$(PREFIX)/bin/`. Mais une absence ne se lit pas : le motif qui vivait dans le
  commentaire du `.gitignore` a **déménagé dans `bin/dune`**, à la place exacte où on chercherait
  la ligne manquante, avec sa raison (sa place est un répertoire de complétion) et son renvoi
  (`modernisation-installation-marionnet`, § 2.4 ter).

  **Le déplacement répare un défaut que l'épisode 4 avait créé.** `_mrn_ctl_program` cherche le
  client dans trois endroits : `$MARIONNET_CTL`, puis **`$here/marionnet-ctl`** où `$here` est le
  répertoire du fichier de complétion, puis le `PATH`. La deuxième branche — celle qui fait marcher
  la complétion depuis un arbre de sources, sans rien installer — était **morte depuis que le lien
  a quitté `useful-scripts/`** ; elle redevient vraie ici, sans une ligne de code, parce que le
  fichier a rejoint les clients. Mesuré : `_mrn_ctl_program` répond `bin/scripts/marionnet-ctl`.

  **Les noms déclarés ont été remis à niveau** — la dette que l'épisode 3 avait explicitement
  renvoyée ici. Les trois lignes `complete -F` ne connaissaient que 5 noms sur 12 : `mrnck` et
  `mrn-control`, créés aux épisodes 3 et 4, **n'étaient annoncés nulle part**, et les noms
  `marionnet-*` non plus. Elles nomment désormais **les 12** — les trois fichiers `.sh` réels
  compris, qui sont invocables. Ce n'est pas un changement de comportement (hors périmètre) : les
  fonctions de complétion, elles, n'ont pas bougé d'une ligne. `marionnet-cleanup`/`mrn-cleanup`
  restent hors sujet : ils n'ont pas de fonction de complétion.

  **Inventaire** : aucune correction dans la documentation livrée. `doc-src/scripting/README.md` et
  l'en-tête du fichier disent `. /path/to/marionnet-completion.bash` — générique, donc toujours
  vrai (l'en-tête a néanmoins été mis au niveau des noms desservis). Les archives de chantiers clos
  (`docs/pilotage-par-script.md` § 5.7) ne se corrigent pas ; le doc de
  `modernisation-installation-marionnet` cite le chemin, mais c'est la matière de l'**épisode 6**.

  **Preuve** : `dune build` rc 0 ; `dune install --prefix` rc 0 avec les **14** noms des épisodes
  1-4 dans `share/marionnet/scripts/` et **`marionnet-completion.bash` absente**, comme voulu ;
  `complete -p` sur les 12 noms après avoir sourcé le fichier ; le repli `$here` résolu ; et
  **deux bancs rejoués contre un vrai serveur** — `completion-bench.sh` **60 assertions / 0 échec**
  (les 3 échecs de l'épisode 4 éteints : le banc attendait 7 natures là où le serveur en publie 8
  depuis `nat_bridge`) et `verify-bench.sh` **84 / 0**.

  **Un banc a failli mentir.** `verify-bench.sh` vérifiait le branchement de la complétion par un
  `grep` **littéral** — `complete -F _mrn_verify_completion mrn-verify` — que l'ajout d'un nom
  **avant** `mrn-verify` sur la ligne aurait fait échouer, alors que le branchement, lui, est
  intact. Motif rendu robuste (`grep -qE … (^| )mrn-verify( |$)`). Leçon générale : un banc qui
  cherche une **ligne entière** mesure sa mise en page autant que son sens.
