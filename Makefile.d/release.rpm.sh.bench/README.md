# Le banc du canal RPM

Ce que `Makefile.d/release.rpm.sh` **fabrique**, son propre run le dit. Ce banc dit ce qu'une
machine en **fait** — et c'est la seule façon de savoir si le canal tient, parce que la moitié
des invariants ne sont pas observables au moment de l'empaquetage.

```bash
Makefile.d/release.rpm.sh.bench/run.sh                       # fedora:42 (défaut)
Makefile.d/release.rpm.sh.bench/run.sh --distro all          # les 4 distributions courantes
Makefile.d/release.rpm.sh.bench/run.sh --distro opensuse/leap:16.0
Makefile.d/release.rpm.sh.bench/run.sh --keep                # garde les conteneurs
```

**Deux familles, quatre verbes.** openSUSE n'est pas un Fedora sous un autre nom : il résout les
mêmes dépendances par fichier et par soname avec **zypper**. Tout ce dont les cas ont besoin
passe par `pm_install` / `pm_remove` / `pm_extra_repos` / `unmet_of`, si bien qu'un cas n'a
jamais à savoir sur quelle famille il tourne.

Conventions de `driven-sessions/README.md` : **PASS 0 / SKIP 77 / FAIL** autre chose.

## La boîte est nue, et c'est tout le propos

Il n'y a **pas de `Dockerfile`** ici, contrairement au banc du tarball binaire : un canal de
paquets n'a d'intérêt que si le gestionnaire tire lui-même les dépendances. Une boîte préparée
prouverait que nos fichiers se posent ; elle ne prouverait pas que `dnf` sait les réclamer.

## Ce que seul ce banc peut mesurer

| Cas | Ce qu'il établit |
|---|---|
| **1** | La boîte ne fournit **ni** `vde_switch` **ni** `uml_mconsole`, et cette distribution n'a **pas** de `vde2` — le constat qui oblige le canal à empaqueter les deux lui-même |
| **2** | L'application **seule** est **refusée**, et le refus **nomme les deux fichiers manquants**. C'est l'invariant 5 (dépendances par fichier) rendu visible : dnf n'installe pas un Marionnet incapable de démarrer un composant. Et les **douze autres** dépendances, elles, se résolvent depuis les dépôts de la distribution — elles ne sont pas dans le message |
| **2 bis** | Les cinq paquets ensemble s'installent — ou, sur une boîte plus ancienne, le refus **nomme la glibc**. C'est l'épisode 12 transposé : la contrainte n'est plus dans un *nom de fichier*, elle est une métadonnée que dnf sait refuser |
| **3** | `glibc.i686` est tiré **par dérivation** (rpm lit les deux classes d'ELF du paquet de noyaux), là où le canal Debian devait écrire `libc6:i386` à la main — et `libgtksourceview` est réclamé **par son soname**, donc sans traduction |
| **5** | **Aucune** règle sudoers n'a été accordée : le `%post` la *nomme* seulement |
| **6** | L'image invitée porte le **même `mtime`** que le tarball publié — ce qu'UML vérifie contre le `.conf` d'un backing file |
| **7** | Les 26 guides sont **dans** le paquet mais **absents** de cette boîte : rpm marque tout seul comme documentation ce qui vit sous `%{_docdir}`, et toute image RPM pose `tsflags=nodocs`. Une fois cette exclusion retirée, ils s'installent |
| **8** | Le binaire **tourne**, et `bash-completion` **arme** notre fonction pour `mrnctl` (le chargeur, pas seulement le fichier posé) |
| **9** | Une configuration **modifiée** par l'administrateur survit à la désinstallation |
| **10** | Le **dépôt** (`repodata/`, épisode 18), dans un conteneur **neuf** : `dnf install marionnet` **par son nom** tire `vde2` et `uml-utilities` **du même répertoire** — sans le dépôt, il faudrait que l'utilisateur sache qu'ils existent et pourquoi. Les deux paquets de données restent dehors (`Suggests:`, comme `apt install marionnet`) mais sont **visibles**, et s'installent sur demande. Enfin, plusieurs révisions publiées : dnf choisit **la plus récente**. `repodata/` n'est **pas** dans `SHA256SUMS` |

## Cinq pièges que ce banc a payés

1. **Installer l'application seule est le bon test, pas un échec du banc.** La première version
   installait `marionnet` seul et concluait « refusé pour une raison qui n'est pas la glibc ».
   C'était vrai, et c'était *la* mesure intéressante : le refus nomme `/usr/bin/vde_switch` et
   `/usr/bin/uml_mconsole`. Le cas a été coupé en deux plutôt que corrigé.
2. **Un répertoire de release contient légitimement plusieurs révisions.** Avec r916 *et*
   r917 publiés, `dnf install /rpms/*.rpm` demande deux versions du même paquet et dnf refuse
   (« *conflicting requests* »). Le banc nomme donc les paquets un par un, et choisit la
   **plus récente** (`sort -V`) — ce qui est aussi ce que le cas 10 vérifie côté dépôt.
3. **Un PASS mensonger, le pire des défauts de banc.** La première version classait « refus
   nommant la glibc » **tout** message contenant le mot ; sur Rocky 10 elle affichait donc un
   PASS alors que les vraies causes étaient `xrandr`, `gtksourceview3` et
   `filesystem(unmerged-sbin-symlinks)`. Un refus se classe désormais par le **symbole exact**
   (`unmet_of`), jamais par un mot trouvé quelque part.
4. **`zypper` sort avec le code 0 après avoir annulé.** Il imprime le problème, propose des
   solutions, choisit « cancel » en mode non interactif — et rend 0. L'état se lit dans
   `rpm -q`, jamais dans le statut de sortie.
5. **`bash-completion` n'est pas une dépendance du paquet** — Marionnet marche sans. La boîte ne
   l'a donc pas, et un cas naïf échoue en croyant que la complétion est mal installée. Le banc
   l'installe *dans ce cas-là*, ce qui est justement ce qui prouve que nos douze fichiers sont
   là où le **chargeur** les cherche.

## Résultats mesurés (2026-08-31, après l'épisode 19)

| Boîte | glibc | Résultat |
|---|---|---|
| `rockylinux/rockylinux:10` | 2.39 | **47 PASS, 0 FAIL** |
| `almalinux:10` | 2.39 | **45 PASS, 0 FAIL** |
| `fedora:42` | 2.41 | **46 PASS, 0 FAIL** |
| `opensuse/leap:16.0` | 2.40 | **46 PASS, 0 FAIL** — la boîte `zypper` |
| `rockylinux/rockylinux:9` | 2.34 | **6 PASS, 0 FAIL** — refus attendu, classé par le **symbole exact** |

Soit **184 cas verts**. Les versions **précédentes** (Rocky 9, Leap 15.6) demanderaient une image
de build à glibc plus ancienne : un binaire ne tourne que sur une glibc au moins aussi récente
que celle de sa machine de compilation, garantie qui ne vaut que vers l'avant (épisode 12). Ce
n'est plus un préalable, c'est un choix de portée.

## Le répertoire de release peut être le serveur (épisode 27)

Point **(6)** de la feuille de route :

```bash
bash Makefile.d/release.rpm.sh.bench/run.sh -o https://www.marionnet.org/download/rpm
bash Makefile.d/release.rpm.sh.bench/run.sh --distro all -o https://www.marionnet.org/download/rpm
```

Ici, **contrairement au banc `.deb`, les paquets sont bel et bien téléchargés** : neuf cas sur
dix installent un **fichier nommé** (`dnf install /rpms/<nom>.rpm`), qui est le geste de qui a
récupéré un paquet à la main — et c'est ce geste que ce banc a été écrit pour mesurer. Le cas
**10** (le dépôt) est celui qui ne le fait pas : `dnf` y est pointé sur le serveur
(`baseurl=https://…`, rien de monté) et rapatrie lui-même.

Le tri est **piloté par le catalogue** et par rien d'autre (invariant de l'ép. 8, vu du côté
consommateur) : les `*.rpm`, plus **deux** tarballs qui achètent chacun un cas qu'aucun autre
ne joue — celui de l'application, que l'ép. 20c compare **octet par octet** au binaire
installé, et celui de l'image invitée, dont le `mtime` est ce qu'UML vérifie. Les noyaux et les
grosses images ne sont **pas** rapatriés : aucun cas ne les lit.

Un cas de plus, joué avant les autres : les paquets servis correspondent aux digests de leur
**propre** `SHA256SUMS`. Le téléchargement **survit à la boucle `--distro all`**
(`MRN_BENCH_CACHE`) : quatre boîtes mesurent **une** release.
