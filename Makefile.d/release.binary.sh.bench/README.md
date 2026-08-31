# Banc de `Makefile.d/release.binary.sh` — la moitié qui **reçoit**

> Étendu à l'**épisode 10** (les dépendances apt de la machine cible), à l'**épisode
> 11a** (la complétion bash), puis à l'**épisode 12** — la **boîte est un paramètre**, et
> les cas sont joués sur les **quatre** distributions de la feuille de route.
> Puis à l'**épisode 14** — la **documentation livrée** (`doc-src/`) est enfin installée.
> **48 cas** au total, dont **10** virent au rouge sur un artefact d'avant l'épisode 10,
> **3** sur un artefact d'avant l'épisode 11a et **5** sur un artefact d'avant l'épisode 14
> (discriminance mesurée).

L'épisode 9a du chantier `modernisation-installation-marionnet` fabrique le tarball
binaire ; il ne pouvait pas jouer les deux gestes qui en font une **installation**, parce
que les deux sont *root* et modifient l'hôte : l'écriture de
`/etc/marionnet/marionnet.conf` et la pose de la **règle sudoers**. Ce banc les joue,
dans un conteneur jeté ensuite.

## Ce qu'il mesure

- le tarball se déplie **sur une boîte nue** (racine nommée), et `install.sh` s'y présente ;
- les trois refus d'`install.sh` : hors d'un tarball déplié, sans root, et sans savoir
  **à qui** accorder la règle (`SUDO_USER`/`USER` absents) ;
- l'installation nominale : 23 noms dans `<prefix>/bin`, tous `root:root`, les scripts
  compagnons sous leur **nom nu** ;
- la configuration : écrite, nommant le préfixe, **laissée intacte** au second passage,
  réécrite sous `--force`, absente sous `--no-config` ;
- la **règle sudoers** : un fichier à elle dans `/etc/sudoers.d/`, acceptée par `visudo -c`,
  accordée à l'utilisateur que `sudo` a nommé, **bloc (a) seul** (ni NAT ni LAN bridge :
  ceux-là, l'utilisateur final les demande depuis la GUI), retirée par
  `marionnet-sudoers.sh uninstall`, non posée sous `--no-sudoers` ;
- que **`REQUIRED_PACKAGES_RUNTIME` suffit** à faire démarrer le binaire : le conteneur ne
  porte que cette liste, lue par `make print-required-packages-runtime` (jamais recopiée) ;
- la **documentation livrée** (épisode 14) : ses **26** fichiers sous
  `<prefix>/share/doc/marionnet/`, **l'arborescence conservée** (les guides se citent par
  chemin relatif), les **14** scripts d'exemple **exécutables** — le bit que `dune` ne sait
  pas porter, mesuré : il installe tout hors `bin/` en 0644 — et les documents, eux, qui ne
  le sont pas ; aucun renvoi résiduel vers `doc-src/…`, c'est-à-dire vers la racine d'un
  clone que la machine cible n'a pas ; le tout `root:root`. Les trois cas qui *cherchent*
  quelque chose sont **gardés sur l'existence du répertoire** : un `grep` sur rien ne trouve
  rien, et serait passé au vert sur l'arbre même qu'il doit condamner (leçon de l'épisode 12) ;
- un **préfixe inhabituel** (`/opt/marionnet`) : la configuration le suit, l'avertissement
  « pas dans le PATH » est émis, et `--paths` reloge tout **sauf** `binaries` — le piège
  durable de l'épisode 9a, inscrit ici pour que le corriger soit une décision et non une
  surprise ;
- côté hôte, avant tout conteneur : que `SHA256SUMS` annonce le digest **de ce
  tarball-ci** — défaut mesuré à l'épisode 9b, republier sous le même nom laissait le
  digest précédent ;
- **ce que l'installation dit des dépendances apt** (épisode 10), sur une machine
  **dénudée** — une `debian:trixie-slim` sans aucun paquet du runtime, celle où arrive
  quelqu'un qui a juste téléchargé le tarball : `REQUIRED-PACKAGES-RUNTIME` voyage dans le
  tarball et **est** la liste du `Makefile` ; ce qui manque est **nommé** (avec la commande
  `apt` toute prête) sans rien installer, l'application est posée quand même (`rc 0` : un
  paquet absent n'est pas un échec d'installation), l'étape sudoers **s'efface** faute de
  `visudo` en disant comment la rejouer, et le binaire **ne démarre pas** là — la
  contre-preuve du cas « la liste suffit ». Puis les trois états : `--no-deps` ne regarde
  même pas, `--with-deps` sans réseau échoue en avertissant (toujours `rc 0`), et
  `--with-deps` avec réseau installe, fait démarrer le binaire et pose la règle sudoers
  dans la foulée (seul cas de ce banc qui ait besoin de l'extérieur : sauté à voix haute
  s'il n'y a pas de réseau).
- la **complétion bash** des clients du canal (épisode 11a) : les **12 noms** sont posés
  dans `<prefix>/share/bash-completion/completions/`, `root:root` comme le reste, et
  **sourcer l'un d'eux arme réellement `complete` pour ce nom-là**. Ce dernier cas est
  celui qui compte : `bash-completion` charge **à la demande**, en cherchant un fichier
  *portant le nom de la commande tapée*, donc une installation sous un seul nom
  compléterait `marionnet-ctl` et laisserait `mrnctl`, `mrn2sh`, `mrn-verify`… muets.
- et, depuis l'**épisode 12**, que `bash-completion` **trouve** ce fichier tout seul :
  une boîte à part, avec réseau, portant le seul paquet `bash-completion` (qui n'est pas une
  dépendance de Marionnet et n'a rien à faire dans l'image cliente), où le chargeur à la
  demande arme `mrnctl` sans qu'on ait rien sourcé. Ce cas vérifie le **nom de la fonction**
  armée (`_marionnet_ctl_completion`) et non le simple succès de `complete -p` : le chargeur
  de `bash-completion` retombe sur `complete -o default -F _minimal` pour une commande qu'il
  ne connaît pas, si bien que la première version du cas passait sur une boîte où **rien**
  n'avait été installé (mesuré). Ce qu'il valide au fond, c'est le choix `share_root` de
  l'épisode 11a : `/usr/local/share` est bien dans le `XDG_DATA_DIRS` par défaut des quatre.

## Les quatre boîtes (épisode 12)

`--distro <référence d'image>` choisit la machine cible ; `--distro all` rejoue le banc sur
les quatre, en n'annonçant qu'un code de sortie (le pire des quatre, un SKIP ne masquant
jamais un FAIL). Le défaut reste `debian:trixie-slim`, donc un run sans argument veut dire
ce qu'il a toujours voulu dire. Les images et les conteneurs sont **suffixés** par la boîte :
deux distributions ne se prennent jamais l'une pour l'autre.

Ce que la boîte change vraiment, et que ce banc mesure :

| Boîte | glibc | Résultat |
|---|---|---|
| `debian:bookworm-slim` (12) | 2.36 | **44 verts, 4 sautés** |
| `debian:trixie-slim` (13) | 2.41 | 48 verts |
| `ubuntu:24.04` | 2.39 | 48 verts |
| `ubuntu:26.04` | 2.43 | 48 verts |

**Debian 12 est le cas intéressant.** L'artefact fabriqué ici est lié à la glibc de la
machine de compilation (2.39) : sur une boîte plus ancienne, il **ne peut pas démarrer** —
c'est la garantie de versionnement de symboles de la glibc, qui ne vaut que dans un sens.
Le banc lit donc, comme `marionnet-install.sh` le fait, l'arch et la glibc **dans le nom du
tarball**, et :

- il ne saute **pas** le run : poser les fichiers, la configuration, la règle sudoers, la
  complétion et le nommage des dépendances apt se mesurent tout aussi bien là — ce sont
  justement les choses qui changent d'une distribution à l'autre ;
- seuls les **quatre cas qui démarrent le binaire** s'effacent, et **un cas neuf prend leur
  place** : le refus doit **nommer la glibc**. C'est ce qui fait du critère lu dans le nom
  un fait mesuré plutôt qu'une décoration ;
- une **architecture** étrangère, elle, fait sauter tout le run : il n'y aurait rien à
  mesurer.

Conséquence à ne pas perdre : **pour servir Debian 12, il faudra construire sur Debian 12.**
Une matrice de compilation est un autre épisode ; ce banc dit seulement, et sans se mentir,
que l'artefact courant n'est pas pour cette boîte-là.

## Ce qu'il ne mesure pas

Aucun invité, aucun tap, aucune GUI : le conteneur n'a pas de serveur X, et rien ici ne
démarre un composant. Le banc s'arrête à ce qu'une machine cible reçoit et à ce que le
binaire fait sans afficher : `--help`, `--paths`.

## Rejeu

```bash
make release-binary                             # produit l'artefact (configuration FINALE)
bash Makefile.d/release.binary.sh.bench/run.sh  # [--distro IMAGE|all] [marionnet_*.tar.xz]
bash Makefile.d/release.binary.sh.bench/run.sh --distro all
```

Sans argument, le banc prend le plus récent `marionnet_*.tar.xz` publié sous
`website-repo/download/marionnet-install.sh/*/`. Conventions de
`driven-sessions/README.md` : **0** = PASS, **77** = SKIP (docker absent, ou aucun
tarball), autre = FAIL ; une ligne par cas, un décompte, et le banc retire ses conteneurs.

## Deux trous que ce banc a trouvés (2026-08-30)

1. **`xz-utils`** manquait à `REQUIRED_PACKAGES_RUNTIME` : sur une `debian:trixie-slim`,
   le `tar xf` que le README du tarball prescrit meurt sur `xz: Cannot exec`.
2. **`libgtksourceview-3.0-1`** manquait pour la même raison de fond : tant qu'installer
   voulait dire *compiler*, les bibliothèques GTK arrivaient comme dépendances de
   `REQUIRED_PACKAGES_BUILD` ; une machine qui ne fait qu'**exécuter** n'a pas ce paquet
   de build, et le binaire mourait sur `libgtksourceview-3.0.so.1`.

Les deux sont désormais dans la liste du `Makefile`, avec leur justification.
