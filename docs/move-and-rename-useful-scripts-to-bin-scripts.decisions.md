# Amorce du chantier `move-and-rename-useful-scripts-to-bin-scripts`

**Slug (commits, mémoire, grep)** : `move-and-rename-useful-scripts-to-bin-scripts`
**Nature** : phase amont (`chantier-amorce`) — on cherche le **chemin**, on ne déplace rien.

## Le fait fondateur (énoncé par l'auteur, 2026-08-23)

Dans l'esprit initial du projet, les deux répertoires n'ont pas le même rôle :

| Répertoire | Ce qu'il doit contenir |
|---|---|
| `useful-scripts/` | scripts auxiliaires de **gestion / installation du projet** (`marionnet_from_scratch`, dépôt sur le serveur…) et **scripts-guides** pour les développeurs (`HOWTO_*`) |
| `bin/scripts/` | scripts **complémentaires du binaire** `marionnet.native` — ce que le programme dépose, lance, ou ce que l'utilisateur emploie pour piloter Marionnet |

Cette règle n'avait jamais été écrite, et elle n'a donc pas été appliquée : les cinq scripts
produits par les chantiers `pilotage-par-script`, `journalisation-profonde` et
`marionnet-todo-transverse` (`marionnet-ctl`+`mrnctl`, `mrn-check`+`mrn2sh`, `mrn-verify`,
`marionnet-cleanup`, `marionnet-completion.bash`) ont été écrits dans `useful-scripts/` alors
qu'ils appartiennent à `bin/scripts/`. **Ce chantier répare cette incohérence**, et profite du
déplacement pour **renommer** ce qui doit l'être (exemple donné par l'auteur : `mrn-check` doit
devenir `bin/scripts/marionnet-check`, avec deux liens symboliques `mrn2sh` et `mrnck` placés eux
aussi dans `bin/scripts/`).

## Destination

*(proposée le 2026-08-23, **à valider**)*

Le chemin est clair quand on sait, sans plus rien à trancher : **quels** fichiers migrent vers
`bin/scripts/`, sous **quel nom canonique** et avec **quels liens**, ce qu'on fait des **anciens
noms** déjà publiés par la documentation, et par **quelles étapes énumérables** la migration se
joue — installation, documentation livrée, bancs `driven-sessions/`, archives des chantiers clos —
sans qu'un nom appelé quelque part cesse de résoudre.

## Décisions prises

- **D10** — *Quand nettoyer la liste blanche `!useful-scripts/…` du `.gitignore` ?* → **au fil de
  l'eau, pas en une fois à la fin** : les six entrées mortes ont été retirées le jour même.
  *Pourquoi :* une entrée blanche qui nomme un fichier absent ne fait rien de mal
  mécaniquement, mais elle **ment au lecteur** — elle laisse croire que le fichier est encore là
  et versionné, ce qui est exactement l'erreur qu'on vient de payer (le ménage du 2026-08-23 a
  retiré quatre fichiers versionnés en laissant leurs quatre lignes). La règle est donc écrite
  dans le `.gitignore` lui-même, à côté de celle qui existait déjà pour les ajouts : un fichier
  retiré du versionnement sort de la liste blanche. Reste cohérent avec la suite du chantier —
  chaque script migré vers `bin/scripts/` fera sortir sa ligne au moment de sa migration, et non
  dans une passe finale. Vérifié après coup : la liste blanche compte 10 entrées, et
  `git ls-files useful-scripts/` en compte 10, les mêmes. (2026-08-23)

## Questions ouvertes

Le **front** (rien ne les bloque) : **D1**, **D3**, **D5**, **D6**, **D8**.

- **D1** `arbitrage` — **Périmètre exact du déplacement.** Les cinq évidents sont
  `marionnet-cleanup`, `marionnet-ctl` (+`mrnctl`), `mrn-check` (+`mrn2sh`), `mrn-verify`,
  `marionnet-completion.bash`. Restent à trancher les cas de bord : `make_marionnet_bytecode_revno`
  (outil de développement — reste ?), `marionnet_from_scratch` (installeur mort, gardé comme pièce
  à conviction de l'autopsie — reste), `marionnet_from_scratch.install_on_site` et
  `uninstall_marionnet.sh` (gestion/installation — restent ?), les `HOWTO_*` et
  `make_a_release_from_trunk.sh` (scripts-guides — restent). Question : la règle fondatrice
  suffit-elle à classer chaque fichier, ou faut-il une troisième catégorie ?

- **D2** `arbitrage` — **Table de nommage canonique.** L'exemple donné fixe un motif possible :
  nom canonique `marionnet-<verbe>`, alias courts en liens. Faut-il l'appliquer systématiquement
  (`mrn-check` → `marionnet-check` + `mrnck` + `mrn2sh` ; `mrn-verify` → `marionnet-verify` +
  `mrnv` ? ; `marionnet-ctl` → `marionnet-control` + `mrnctl` ? ou `marionnet-ctl` est-il déjà
  canonique ?), ou seulement là où le nom court est aujourd'hui le nom principal ?
  *(bloquée par D1)*

- **D3** `arbitrage` — **Sort des anciens noms.** `mrnctl`, `mrn-check`, `mrn2sh`, `mrn-verify`
  sont des **noms publics** : la documentation livrée les appelle par leur nom nu et des PDF ont
  été produits. Rupture nette (la série `1.0.x` n'est pas encore publiée, personne n'a encore
  installé ces commandes) ou liens de compatibilité conservés ? Une rupture nette est cohérente
  avec « rien n'est encore diffusé » ; des liens de compatibilité coûtent deux inodes et une ligne
  de doc.

- **D4** `recherche` — **Mécanique d'installation après déplacement.** `bin/dune` installe déjà
  `scripts/*` par `glob_files` en section `share`, exactement là où `useful-scripts/dune` pose les
  six exécutables (`share/marionnet/scripts/`, que le `Makefile` mirroir dans `$(PREFIX)/bin/`).
  Le déplacement est donc *a priori* **neutre à l'installation** — à vérifier : que devient
  `useful-scripts/dune` (supprimé ?), et surtout **comment dune traite les liens symboliques**
  (aujourd'hui il les installe en **copies**, ce qui marche parce que les scripts lisent
  `${0##*/}`, mais il faudra le revérifier avec des liens neufs). *(bloquée par D2)*

- **D5** `arbitrage` — **Frontière interne de `bin/scripts/`.** Le répertoire mêle déjà trois
  familles : scripts **déposés dans les invités** (`marionnet-relay.*`, `marionnet-report.sh`,
  `marionnet-watch.sh`, `marionnet-terminal-record.sh`), **portes privilégiées** root:root nommées
  par `marionnet-sudoers.sh` (`marionnet-dnsmasq.sh`, `marionnet-ipv6.sh`, les deux bridges), et
  **commandes hôte auxiliaires**. Les clients utilisateur en formeraient une quatrième. On les
  verse à plat, ou on introduit une structure (`guest/`, `host/`, `cli/`) ? ⚠️ Une structure
  déplacerait des chemins que `marionnet-sudoers.sh` et `bin/dune` nomment un par un.

- **D6** `arbitrage` — **Sort de `marionnet-completion.bash`.** Ce n'est pas une commande : elle
  n'a rien à faire dans `$(PREFIX)/bin/`, et le chantier `modernisation-installation-marionnet`
  la porte déjà comme tâche restante (« pas une commande, appartient à un répertoire de
  complétion »). Migre-t-elle avec les autres, va-t-elle ailleurs (`etc/`,
  `share/bash-completion/completions/`), et son installation est-elle du ressort de **ce**
  chantier ou de celui de l'installation ?

- **D7** `arbitrage` — **Que fait-on des archives de chantiers clos ?** `docs/pilotage-par-script.md`,
  `docs/journalisation-profonde.md` et `docs/todo-transverse.md` nomment abondamment les anciens
  chemins et les anciens noms. Ce sont des **archives figées** (le skill `chantier-long` les
  déclare non réécrites). On les laisse telles quelles (elles décrivent un état passé, ce qui est
  leur rôle), ou on y appose une note de renvoi ? *(bloquée par D3)*

- **D8** `recherche` — **Inventaire exhaustif des sites à mettre à jour.** Première mesure
  (2026-08-23, `grep` par zone, nombre de **fichiers** citant chaque nom) :

  | Nom | `doc-src/` | `bin/` | `docs/` | `driven-sessions/` | `.claude/` | `useful-scripts/` |
  |---|---|---|---|---|---|---|
  | `mrnctl` | 21 | 2 | 5 | 0 | 0 | 4 |
  | `mrn-verify` | 12 | 1 | 2 | 0 | 1 | 3 |
  | `mrn-check` | 7 | 2 | 3 | 0 | 1 | 5 |
  | `marionnet-ctl` | 6 | 1 | 2 | 0 | 1 | 6 |
  | `mrn2sh` | 4 | 2 | 3 | 0 | 0 | 3 |
  | `marionnet-cleanup` | 0 | 15 | 2 | 3 | 0 | 2 |

  Reste à établir précisément : les **chemins relatifs en dur** (les 7 exemples de
  `doc-src/scripting/examples/` pointent `useful-scripts/mrnctl` via `$MRNCTL`), les deux bancs
  `driven-sessions/` qui construisent `$HERE/useful-scripts/marionnet-cleanup`, le skill
  `.claude/skills/marionnet-lab-design`, et le **code OCaml** (`bin/marionnet.ml` nomme
  `marionnet-cleanup` **à l'écran** et le **lance** ; `MARIONNET_CLEANUP_SCRIPT` le surcharge).

- **D9** `arbitrage` — **Les PDF déjà produits.** `doc-src/teacher-guide.pdf` et
  `teacher-guide.FR.pdf` (non versionnés) citent les noms actuels. On les régénère dans ce
  chantier, ou est-ce hors périmètre ? *(bloquée par D3)*

## Pas encore spécifié

- L'**ordre des épisodes** de la future exécution (un script à la fois ? tout d'un coup avec
  `git mv` et une passe de `sed` ?) — dépend de D1/D2/D3.
- Comment **prouver** la migration : quels bancs `driven-sessions/` ajouter ou adapter pour qu'un
  nom cassé se voie, plutôt que d'être découvert par un utilisateur.
- Ce que la migration change pour le chantier **`modernisation-installation-marionnet`**
  (son § 2.4 ter et `useful-scripts/dune` sont écrits autour des chemins actuels) — il faudra le
  lui répercuter, reste à savoir sous quelle forme.

## Hors périmètre

- **Renommer les scripts déjà dans `bin/scripts/`** (invités, portes privilégiées, commandes hôte
  auxiliaires) : ils sont au bon endroit, et les portes privilégiées sont nommées **par chemin**
  dans la règle sudoers — les toucher, c'est un risque de sécurité pour un gain nul.
- **Modifier le comportement** d'un seul de ces scripts : ce chantier déplace et renomme, il ne
  change ni une option, ni une sortie, ni la grammaire du canal.
- **Installer la documentation** (`doc-src/`) : c'est une tâche restante du chantier
  `modernisation-installation-marionnet`, pas d'ici.
