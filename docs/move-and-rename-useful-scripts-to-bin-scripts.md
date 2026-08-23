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
