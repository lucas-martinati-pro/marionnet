# Banc de `Makefile.d/release.deb.sh` + `release.apt.sh` — la moitié qui **reçoit**

> Écrit à l'**épisode 15b** du chantier `modernisation-installation-marionnet`.
> **33 cas**, joués sur les **quatre** boîtes de la feuille de route (Debian 12 et 13,
> Ubuntu 24.04 et 26.04) — **33 verts** sur Debian 13, Ubuntu 24.04 et Ubuntu 26.04, et
> **7 verts** sur Debian 12, où les cas qui installent l'application s'effacent au profit
> du **refus** qu'apt doit énoncer. Un seul fichier : `run.sh`. Pas de `Dockerfile` — et
> c'est le fond de l'affaire, cf. « Pourquoi un troisième banc » ci-dessous.

L'épisode 15a fabrique les quatre paquets et les contrôle **là où ils sont fabriqués** ;
il ne pouvait pas jouer le geste qui en fait une **installation**, parce que ce geste est
`apt install` sur une machine qui n'est pas celle-ci. Ce banc le joue, dans des conteneurs
jetés ensuite.

## Ce qu'il mesure

- **les deux catalogues cohabitent** : `SHA256SUMS` annonce les digests des quatre `.deb`,
  et les index apt (`Packages`, `Packages.gz`, `Release`) n'y sont **pas** — ils sont
  réécrits à chaque publication, un digest enregistré pour eux serait périmé tout seul ;
- `Release` décrit bien le `Packages` posé à côté (taille et digest) — c'est ce qu'apt
  vérifie avant de faire confiance à l'index ;
- **une ligne de `sources.list` suffit** : `deb [trusted=yes] file:///repo ./`, dépôt à
  plat, `apt-get update` l'accepte, et apt voit les **quatre** paquets à la version que
  l'index annonce ;
- `apt install marionnet` sur une boîte **nue** : rc 0, et apt tire **lui-même** les treize
  dépendances d'exécution — les douze commandes appelées par leur nom nu sont là ;
- ce qui est posé : **23 noms** dans `/usr/bin`, **12 fichiers de complétion**, les
  **guides livrés** de l'épisode 14 sous `/usr/share/doc/marionnet`, plus le `copyright` et
  le `changelog.gz` du paquet ;
- la **conffile** `/etc/marionnet/marionnet.conf` : déclarée comme telle (donc jamais
  écrasée en silence), et redirigeant le préfixe compilé vers `/usr` — ce que `--paths`
  confirme depuis le binaire ;
- le `postinst` **nomme** la règle sudoers et n'en accorde aucune (rien dans
  `/etc/sudoers.d/`) ; le `prerm` dit comment la retirer ;
- le binaire **démarre** sur une boîte qu'apt seul a garnie ;
- les paquets de données : le noyau exécutable là où `MARIONNET_KERNELS_PATH` regarde,
  l'image guignol portant **le `mtime` du tarball publié** (`2017-06-09 15:01:16`, mesuré
  des deux côtés) et le routeur toujours un **lien symbolique** ;
- `apt remove` garde la configuration, `apt purge` la retire ;
- l'**architecture étrangère** : sans `dpkg --add-architecture i386`, apt **refuse**
  `marionnet-kernels-i386` en nommant `libc6:i386` ; avec, il l'installe et
  `/lib/ld-linux.so.2` est enfin là ;
- la **rencontre des deux canaux** : la machine où le tarball avait déjà écrit la conf.

## Pourquoi un troisième banc, et pas cinq cas de plus

Le banc du tarball part d'une boîte **portant déjà** `REQUIRED_PACKAGES_RUNTIME`, parce
qu'un humain a dû les installer d'abord (l'épisode 10 a fait en sorte qu'`install.sh` les
**nomme**). Celui-ci part d'une boîte **nue**, parce que toute la promesse du canal `.deb`
est qu'apt résout cette liste lui-même. Fusionner les deux obligerait l'une des deux boîtes
à mentir sur ce qu'elle représente.

D'où l'absence de `Dockerfile` ici : il n'y a **rien à construire**, la boîte *est* l'image
de base. Ce qui est monté, en lecture seule, c'est le **vrai répertoire de release** —
celui où `make release-deb` publie —, index compris.

## Les trois choses que seul ce banc pouvait mesurer

**(a) La forme exacte de la dépendance i386.** `libc6:i386` avait été lu sur la machine de
développement *seulement*. Mesuré ici : sans `dpkg --add-architecture i386`, apt refuse et
**nomme** le paquet ; avec, l'installation passe et l'interpréteur `/lib/ld-linux.so.2`
(écrit **en dur** dans le noyau 32 bits) apparaît. C'est la justification chiffrée du
découpage de l'épisode 13 : un paquet capable de faire activer une architecture étrangère
ne s'impose pas à tout le monde.

**(b) La rencontre des deux canaux — et c'est ce que cet épisode a appris.** Sur une machine
où le **tarball** avait déjà écrit `/etc/marionnet/marionnet.conf` (préfixe `/usr/local`),
un `apt install` **non interactif échoue** : `DEBIAN_FRONTEND=noninteractive` gouverne
*debconf*, **pas** l'invite de conffile de dpkg, qui demande, ne trouve pas de `stdin` et
laisse le paquet non configuré (« *end of file on stdin at conffile prompt* »). C'est Debian
se comportant exactement comme il le doit — une configuration écrite par un humain n'est
jamais écrasée en silence — et c'est une **conséquence réelle** pour nous, puisque les deux
canaux du chantier se rencontrent chez les utilisateurs qui essaient le tarball d'abord.
Le banc mesure donc **les deux moitiés** : le refus, puis la réponse de l'administrateur
(`-o Dpkg::Options::=--force-confold`), qui termine l'installation, **conserve** le préfixe
choisi et laisse la version du paquet en `.dpkg-dist`. Cela appartient à la **doc INSTALL**,
pas à un drapeau caché dans un `postinst` : un paquet qui répond à cette question à la place
de l'administrateur est un paquet qui jette le préfixe qu'il avait choisi.

**(c) Le refus glibc, dit par apt.** L'épisode 12 ne savait écrire cette contrainte que dans
un **nom de fichier**, et le banc du tarball devait relire ce nom. Ici c'est un champ
`Depends:` — le banc le lit **dans l'index** — et sur Debian 12 apt doit refuser **en
nommant `libc6`**. Comme au banc du tarball, la boîte trop ancienne ne fait pas sauter le
run : seuls les cas qui **installent l'application** s'effacent, remplacés par ce refus.

## Un piège payé ici : une image Docker n'est pas une machine Debian

`debian:*-slim` **et** `ubuntu:*` embarquent une configuration dpkg qui **exclut**
`/usr/share/doc/*` (`path-exclude`, mesuré sur les deux familles ; Ubuntu y jette aussi les
pages de man et les traductions). Laissée en place, la boîte jetait les **26 guides** que
l'épisode 14 venait d'installer — et le banc aurait signalé comme défaut du paquet ce qui
est un **trait de la boîte**. `run.sh` retire donc ce fichier dans chaque conteneur, avant
toute installation.

Le banc du tarball n'a jamais rencontré ce piège : `tar` ne consulte la configuration de
personne. C'est précisément ce qui fait que le canal `.deb` livre **moins** que le tarball
sur une telle image — un point que le futur **canal Docker officiel** devra traiter au lieu
d'en hériter (`/usr/share/marionnet/locale` est heureusement hors de l'exclusion : l'i18n
survit, la documentation non).

## Lancer

```bash
bash Makefile.d/release.deb.sh.bench/run.sh                     # debian:trixie-slim
bash Makefile.d/release.deb.sh.bench/run.sh --distro ubuntu:26.04
bash Makefile.d/release.deb.sh.bench/run.sh --distro all        # les quatre boîtes
bash Makefile.d/release.deb.sh.bench/run.sh /chemin/vers/une/release/
```

Prérequis : `docker`, un **réseau** (apt doit joindre le miroir de la distribution pour
résoudre les treize dépendances — sans lui, le run **SKIP** bruyamment plutôt que de
mesurer un dépôt dont personne ne pourrait installer), et un répertoire de release portant
les quatre `.deb` **et** ses index (`make release-deb`, qui appelle `release.apt.sh` de
lui-même).

Conventions de `driven-sessions/README.md` : 0 = PASS, 77 = SKIP, tout autre = FAIL ; une
ligne `PASS:`/`FAIL:` par cas, un décompte à la fin, et le banc nettoie derrière lui.
`--distro all` rejoue le driver une fois par boîte — un cas rouge nomme donc **une**
distribution — et rend le pire des codes de retour, un SKIP ne masquant jamais un FAIL.

## Discriminance (mesurée, sur un dépôt-témoin)

- **sans les index apt** — l'état d'avant cet épisode : **SKIP 77**. Le banc dit qu'il n'y
  a rien à mesurer ; il ne verdit pas.
- **`Release` décrivant un `Packages` périmé** : **1 rouge**, et c'est le cas *hôte* qui
  l'attrape. Mesuré : apt, lui, **accepte** ce dépôt — `[trusted=yes]` lui fait passer la
  vérification. Autrement dit, tant que le dépôt n'est pas signé, la cohérence de
  `Release` n'est gardée que par nous ; raison de plus pour que `release.apt.sh` les
  écrive **ensemble**, jamais l'un sans l'autre.
- **un index enregistré dans `SHA256SUMS`** : **1 rouge**.
- **l'exclusion `/usr/share/doc/*` laissée en place** : **2 rouges** (les guides de
  l'épisode 14, puis le `copyright`/`changelog.gz`) — et l'i18n, elle, survit
  (12 catalogues sous `/usr/share/marionnet/locale`). C'est la mesure qui a valu le
  paragraphe ci-dessus.
- **sur Debian 12**, les cas d'installation s'effacent et le refus doit **nommer
  `libc6`** ; les cas d'architecture étrangère s'effacent aussi, car
  `marionnet-kernels-i386` dépend de `marionnet` et serait refusé pour la raison de
  l'**autre** paquet (mesuré : une première version du cas passait au vert en nommant le
  `libc6` de l'application).
