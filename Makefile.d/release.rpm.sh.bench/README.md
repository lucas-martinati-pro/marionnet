# Le banc du canal RPM

Ce que `Makefile.d/release.rpm.sh` **fabrique**, son propre run le dit. Ce banc dit ce qu'une
machine en **fait** — et c'est la seule façon de savoir si le canal tient, parce que la moitié
des invariants ne sont pas observables au moment de l'empaquetage.

```bash
Makefile.d/release.rpm.sh.bench/run.sh                              # fedora:42 (défaut)
Makefile.d/release.rpm.sh.bench/run.sh --distro rockylinux/rockylinux:9
Makefile.d/release.rpm.sh.bench/run.sh --keep                       # garde le conteneur
```

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

## Trois pièges que ce banc a payés

1. **Installer l'application seule est le bon test, pas un échec du banc.** La première version
   installait `marionnet` seul et concluait « refusé pour une raison qui n'est pas la glibc ».
   C'était vrai, et c'était *la* mesure intéressante : le refus nomme `/usr/bin/vde_switch` et
   `/usr/bin/uml_mconsole`. Le cas a été coupé en deux plutôt que corrigé.
2. **Un répertoire de release contient légitimement plusieurs révisions.** Avec r916 *et*
   r917 publiés, `dnf install /rpms/*.rpm` demande deux versions du même paquet et dnf refuse
   (« *conflicting requests* »). Le banc nomme donc les paquets un par un, et choisit la
   **plus récente** (`sort -V`) — ce qui est aussi ce que le cas 10 vérifie côté dépôt.
3. **`bash-completion` n'est pas une dépendance du paquet** — Marionnet marche sans. La boîte ne
   l'a donc pas, et un cas naïf échoue en croyant que la complétion est mal installée. Le banc
   l'installe *dans ce cas-là*, ce qui est justement ce qui prouve que nos douze fichiers sont
   là où le **chargeur** les cherche.

## Résultats mesurés (2026-08-31)

| Boîte | glibc | Résultat |
|---|---|---|
| `fedora:42` | 2.41 | **46 PASS, 0 FAIL** (37 avant l'épisode 18) |
| `rockylinux/rockylinux:9` | 2.34 | **6 PASS, 0 FAIL** — refus attendu, nommant la glibc (le banc s'arrête là : rien ne peut y être installé) |

Pour servir Rocky 9 et openSUSE Leap 15.6 (glibc 2.34 et 2.38), il faudra **construire sur
elles** : un binaire ne tourne que sur une glibc au moins aussi récente que celle de sa machine
de compilation, garantie qui ne vaut que vers l'avant. C'est la conclusion de l'épisode 12,
inchangée.
