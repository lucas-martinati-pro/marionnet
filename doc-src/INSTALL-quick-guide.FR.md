# Marionnet — installation rapide

> **Traduction française de `INSTALL-quick-guide.md`.** L'original anglais fait foi : en cas de
> divergence, c'est lui qu'il faut corriger, et cette page à sa suite.

*Copiez, collez. Toutes les explications, toutes les réserves et tout le dépannage sont dans
`INSTALL.FR.md`, dont les numéros de section sont cités ici sous la forme `INSTALL.FR.md § n`.*

## 0. De quoi ai-je besoin ?

| Votre machine | Allez au |
|---|---|
| Debian, Ubuntu et dérivées | § 1 |
| Fedora, famille RHEL (Rocky, AlmaLinux), openSUSE | § 2 |
| tout le reste | § 3 |
| vous comptez modifier Marionnet | § 9 |

Puis le § 4 (images), le § 5 (règle sudoers, **obligatoire**) et le § 6 (lancement), quelle que
soit la méthode prise.

Clef de signature de l'archive, employée par les § 1 et § 2 — comparez-la avec une source qui
n'est pas cette page (`INSTALL.FR.md § 2`) :

```
Marionnet Archive Signing Key <loddo@lipn.univ-paris13.fr>
4A65 3434 0BF9 7733 E74C  9DFC 12E4 6000 225F 0E56
```

## 1. Debian et Ubuntu

### 1.1 Certificats — systèmes minimaux et images de conteneur seulement

```bash
sudo apt update && sudo apt install ca-certificates curl
```

### 1.2 Dépôt et application

```bash
sudo install -d /etc/apt/keyrings
sudo curl -o /etc/apt/keyrings/marionnet.asc \
     https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc
echo 'deb [signed-by=/etc/apt/keyrings/marionnet.asc] https://www.marionnet.org/download/apt/ ./' \
  | sudo tee /etc/apt/sources.list.d/marionnet.list
sudo apt update
sudo apt install marionnet
```

N'ajoutez jamais `-L` à ce `curl` (`INSTALL.FR.md § 2`).

### 1.3 Contrôler la clef

```bash
sudo apt install gnupg
gpg --show-keys /etc/apt/keyrings/marionnet.asc     # doit afficher l'empreinte ci-dessus
```

### 1.4 Paquets de données — seule, l'application ne démarre rien

```bash
sudo apt install marionnet-kernels          # noyau 64 bits : sans lui, aucune image récente (trixie)
sudo apt install marionnet-fs-guignol       # le seul système de fichiers de ROUTEUR : sans lui, pas de routeur
```

**Un routeur exige `marionnet-fs-guignol` ET le noyau 32 bits ci-dessous** : guignol ne tourne
pas sur le 64 bits. Ce noyau porte aussi tout projet `.mar` antérieur à 2026, et il exige une
architecture étrangère :

```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install marionnet-kernels-i386
```

Un système de fichiers dont le noyau supporté n'est pas installé n'est **pas proposé du tout** —
rien n'échoue, il est simplement absent de la liste (`INSTALL.FR.md § 2`).

### 1.5 Si un tarball Marionnet a d'abord été installé ici

```bash
sudo apt install -o Dpkg::Options::=--force-confold marionnet
```

## 2. Fedora, famille RHEL et openSUSE

### 2.1 EPEL — famille RHEL seulement

```bash
sudo dnf install epel-release
```

### 2.2 Clef, dépôt, application

```bash
# 1. la clef — récupérée, REGARDÉE, et alors seulement importée
sudo install -d /etc/pki/rpm-gpg
sudo curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet \
     https://git.launchpad.net/marionnet/plain/marionnet-archive-keyring.asc
gpg --show-keys /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet   # doit afficher l'empreinte du § 2
sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-marionnet

# 2. le dépôt, puis l'application
sudo curl -o /etc/yum.repos.d/marionnet.repo \
     https://www.marionnet.org/download/rpm/marionnet.repo
sudo dnf install marionnet          # zypper install marionnet, sur openSUSE
```

### 2.3 Paquets de données

Les trois mêmes noms qu'au § 1.4, nécessaires aux mêmes choses. `marionnet-kernels-i386` n'est
pas installable sur RHEL 10 (le multilib 32 bits n'y existe plus du tout), et avec lui s'en vont
guignol, wheezy et donc le routeur (temporaire : une image de routeur 64 bits est prévue).

## 3. N'importe quelle distribution — le tarball précompilé

```bash
wget https://www.marionnet.org/download/marionnet-install.sh/marionnet-install.sh
bash marionnet-install.sh --binary --with-deps
```

Voir ce qui est publié, et ce qui est refusé et pourquoi, avant d'installer quoi que ce soit :

```bash
bash marionnet-install.sh --binary --fetch-only --list
```

## 4. Images invitées et noyaux UML

```bash
marionnet-get-images
```

**Ne passez jamais `--prefix`** ici après une installation par paquet : les images atterriraient
là où l'application ne regarde pas (`INSTALL.FR.md § 5`).

Salle de TP sans accès à Internet — faites une fois un miroir du répertoire de release, puis :

```bash
marionnet-install.sh --fetch-only --from /srv/marionnet-mirror
```

## 5. Règle sudoers — OBLIGATOIRE, et accordée par aucune méthode

Un compte, ou plusieurs :

```bash
sudo marionnet-sudoers.sh install <user>...
```

Une salle entière, avant que les étudiants aient un login :

```bash
sudo groupadd marionnet                      # si le site n'a pas de groupe à lui
sudo gpasswd -a <login> marionnet            # (ou utilisez le groupe LDAP/AD existant)
sudo marionnet-sudoers.sh install %marionnet
```

Cela accorde le bloc (a) seul — les taps, et la route X11 par laquelle `wireshark` et `xterm`
atteignent votre affichage. Les blocs (b) NAT bridge et (c) LAN bridge se demandent à
l'exécution, avec le mot de passe sudo de l'utilisateur lui-même. **Lisez `INSTALL.FR.md § 7.2`
avant d'accorder (c) : il reconfigure la carte réseau de l'hôte.**

Donner d'avance le NAT bridge, sans que (c) entre jamais en jeu :

```bash
sudo marionnet-sudoers.sh install --enable-natbridge %marionnet
```

Interdire un bloc sur cette machine, pour tout le monde et pour de bon :

```bash
sudo marionnet-sudoers.sh deny --lanbridge     # ou --natbridge, ou --bridges
```

```bash
marionnet-sudoers.sh policy          # rc 0 si autorisé, 3 si interdit ; il dit lequel
```

Tout retirer :

```bash
sudo marionnet-sudoers.sh uninstall
```

## 6. Lancer, et contrôler l'installation

```bash
marionnet                    # ou : marionnet -r lab.mar, marionnet --exam, marionnet --help
```

```bash
marionnet -v                 # version et révision
marionnet --paths            # où cette installation cherche images, noyaux et scripts
```

Marionnet a besoin d'un affichage X, et il en donne l'accès aux invités avec `xhost`.

## 7. Désinstaller

```bash
sudo apt purge marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol
```

```bash
sudo dnf remove marionnet marionnet-kernels marionnet-kernels-i386 marionnet-fs-guignol
```

Tarball : le `README` qu'il contient liste ce qu'il faut supprimer. Dans tous les cas la règle
sudoers reste jusqu'à `sudo marionnet-sudoers.sh uninstall`.

## 8. Ça ne marche pas

| Symptôme | À lire |
|---|---|
| `server down, no route, wrong URL?` alors que le site est debout | `INSTALL.FR.md § 1` — pas de magasin de certificats |
| apt ignore le dépôt, et `apt-get update` sort quand même avec 0 | `INSTALL.FR.md § 9` |
| `Missing key`, `signature verification failed`, `Failed to import OpenPGP keys` | `INSTALL.FR.md § 2`, `§ 3` — récupérez la clef de nouveau, contrôlez l'empreinte |
| le tarball est refusé, en nommant une glibc | `INSTALL.FR.md § 4` — votre distribution est plus ancienne que le plancher de compilation |
| Marionnet démarre, les images invitées n'apparaissent pas | `INSTALL.FR.md § 5`, puis `marionnet --paths` |
| une machine virtuelle refuse de démarrer, ou rien ne s'ouvre depuis un invité | `INSTALL.FR.md § 7` — la règle sudoers |

## 9. Depuis les sources

```bash
git clone https://git.launchpad.net/marionnet && cd marionnet
make dependencies          # paquets apt (build + exécution), switch opam, paquets opam
dune build                 # un clone frais n'a besoin de rien d'autre : préprocesseurs camlp4,
                           # stubs C, version.ml et meta.ml sont tous construits par dune
make install-final-as-root # elle appelle sudo elle-même, pour la seule étape qui l'exige
```
