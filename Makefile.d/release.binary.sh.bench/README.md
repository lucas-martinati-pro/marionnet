# Banc de `Makefile.d/release.binary.sh` — la moitié qui **reçoit**

> Étendu à l'**épisode 10** (les dépendances apt de la machine cible) : voir la dernière
> puce de « Ce qu'il mesure ». **39 cas** au total, dont **10** virent au rouge sur un
> artefact d'avant l'épisode 10 (discriminance mesurée).

L'épisode 9a du chantier `modernisation-installation-marionnet` fabrique le tarball
binaire ; il ne pouvait pas jouer les deux gestes qui en font une **installation**, parce
que les deux sont *root* et modifient l'hôte : l'écriture de
`/etc/marionnet/marionnet.conf` et la pose de la **règle sudoers**. Ce banc les joue,
dans un conteneur jeté ensuite.

## Ce qu'il mesure

- le tarball se déplie **sur une Debian nue** (racine nommée), et `install.sh` s'y présente ;
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

## Ce qu'il ne mesure pas

Aucun invité, aucun tap, aucune GUI : le conteneur n'a pas de serveur X, et rien ici ne
démarre un composant. Le banc s'arrête à ce qu'une machine cible reçoit et à ce que le
binaire fait sans afficher : `--help`, `--paths`.

## Rejeu

```bash
make release-binary                             # produit l'artefact (configuration FINALE)
bash Makefile.d/release.binary.sh.bench/run.sh  # [chemin d'un marionnet_*.tar.xz]
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
