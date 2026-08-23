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

> **AMORCE CLOSE le 2026-08-23.** L'auteur a tranché d'un coup le périmètre, la table de nommage
> et le sort des anciens noms (D1, D2, D3) ; ces trois-là en rendent trois autres **caduques**
> (D5, D7, D9) et transforment la dernière (D8) en travail d'épisode. Le chemin est énumérable :
> l'exécution passe à `chantier-long`, doc `docs/move-and-rename-useful-scripts-to-bin-scripts.md`.
> **Ce fichier est désormais une archive figée** : il ne se modifie plus.

## Décisions prises

- **D1 + D2 + D3** — *Périmètre, table de nommage, sort des anciens noms* → **tranchés ensemble
  par l'auteur.** Cinq fichiers migrent de `useful-scripts/` vers `bin/scripts/`. Le fichier réel
  prend l'extension `.sh` (la convention de `bin/scripts/`, où les douze fichiers déjà présents
  la portent) et **tous les noms d'usage deviennent des liens symboliques**, placés eux aussi dans
  `bin/scripts/` :

  | Aujourd'hui | Fichier réel | Liens symboliques |
  |---|---|---|
  | `marionnet-cleanup` | `marionnet-cleanup.sh` | `marionnet-cleanup`, `mrn-cleanup` |
  | `mrn-verify` | `marionnet-verify.sh` | `marionnet-verify`, `mrn-verify` |
  | `mrn-check` (+`mrn2sh`) | `marionnet-check.sh` | `marionnet-check`, `mrn-check`, `mrnck`, `mrn2sh` |
  | `marionnet-ctl` (+`mrnctl`) | `marionnet-ctl.sh` | `marionnet-ctl`, `mrnctl`, `mrn-control` |
  | `marionnet-completion.bash` | *(inchangé)* | *(aucun — ce n'est pas une commande)* |

  *Pourquoi c'est la bonne forme :* **aucun nom existant ne disparaît**, donc la migration est
  **non cassante par construction**. Mesuré le jour même, c'est ce qui sauve deux choses qu'un
  renommage sec aurait cassées : (1) `marionnet-cleanup` est **dans les `msgid`** des **12**
  catalogues gettext (`bin/marionnet.ml` nomme la commande dans le message d'avertissement du
  démarrage) — le lien la garde valide, donc **zéro cycle POT, zéro retraduction** ; (2)
  `mrn-check` choisit son mode par `${0##*/}` (`[[ $PROGNAME == mrn2sh ]]`), et `mrn2sh` survit
  comme lien, donc le dispatch est intact. La séparation « implémentation `.sh` / interface par
  liens » est en outre ce qui permettra d'ajouter un nom sans toucher au fichier. (2026-08-23)

- **D6** — *Sort de `marionnet-completion.bash`* → **migre avec les autres, sans renommage, et
  reste non installée.** *Pourquoi :* elle complète des commandes du binaire, donc elle relève de
  `bin/scripts/` par la règle fondatrice ; mais ce n'est pas une commande, et `bin/dune` nomme ses
  fichiers installés **un par un** — ne pas l'y ajouter suffit à la garder hors de
  `$(PREFIX)/bin/`, exactement comme aujourd'hui. Où l'installer reste une tâche du chantier
  `modernisation-installation-marionnet`, pas d'ici. (2026-08-23)

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

## Questions closes sans réponse (rendues caduques par D1-D2-D3)

- **D5** — *`bin/scripts/` à plat ou structuré ?* → **caduque : à plat.** La table de nommage
  suppose les liens à côté de leur cible dans `bin/scripts/`, et une structure déplacerait des
  chemins que `marionnet-sudoers.sh` et `bin/dune` nomment un par un. La question pourra se
  reposer un jour, elle ne bloque plus rien.
- **D7** — *Que faire des archives des chantiers clos ?* → **caduque.** Elles citent des noms qui
  **restent valides** : il n'y a rien à y corriger.
- **D9** — *Les PDF déjà produits ?* → **caduque**, pour la même raison.
- **D8** — *Inventaire exhaustif des sites à mettre à jour* → **n'est plus une question mais le
  travail de chaque épisode** : puisque les noms survivent, seuls cassent les **chemins relatifs
  en dur** (`useful-scripts/<script>`), qui se recensent script par script.
- **D4** — *Mécanique d'installation et traitement des liens par dune* → **résolue en jouant le
  premier épisode** (mesure, pas arbitrage) ; le résultat est consigné dans
  `docs/move-and-rename-useful-scripts-to-bin-scripts.md`.

## Questions ouvertes

*(aucune : l'amorce est close)*

## Pas encore spécifié

*(vide : les trois zones de brouillard ont gradué en étapes — ordre des épisodes, preuve par les
bancs, et répercussion sur `modernisation-installation-marionnet` sont dans le plan d'épisodes de
`docs/move-and-rename-useful-scripts-to-bin-scripts.md`)*

## Hors périmètre

- **Renommer les scripts déjà dans `bin/scripts/`** (invités, portes privilégiées, commandes hôte
  auxiliaires) : ils sont au bon endroit, et les portes privilégiées sont nommées **par chemin**
  dans la règle sudoers — les toucher, c'est un risque de sécurité pour un gain nul.
- **Modifier le comportement** d'un seul de ces scripts : ce chantier déplace et renomme, il ne
  change ni une option, ni une sortie, ni la grammaire du canal.
- **Installer la documentation** (`doc-src/`) : c'est une tâche restante du chantier
  `modernisation-installation-marionnet`, pas d'ici.
