# Marionnet — Laboratoire Réseau Virtuel (Édition Linux Moderne)

[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04%20%7C%2025.04+-orange.svg)](https://ubuntu.com)
[![Dernière version](https://img.shields.io/github/v/release/lucas-martinati-pro/marionnet?color=blue&label=version)](https://github.com/lucas-martinati-pro/marionnet/releases/latest)
[![License](https://img.shields.io/badge/license-GPL--2.0-green.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

**Marionnet** est un laboratoire réseau virtuel permettant de définir, configurer et exécuter un réseau informatique complet (machines virtuelles Linux sous User-Mode Linux, routeurs, switchs VDE, concentrateurs, passerelles...) sur une seule machine sans matériel physique dédié.

> [!NOTE]
> **Base amont (Upstream) & Historique du dépôt :**
> Ce dépôt est un fork indépendant du projet officiel **Marionnet** initié par Jean-Vincent Loddo (LIPN — Université Sorbonne Paris Nord / Paris 13). Le dépôt amont originel étant hébergé sur **Launchpad** ([git.launchpad.net/marionnet](https://git.launchpad.net/marionnet)) et non sur GitHub, GitHub n'affiche pas la mention native *« forked from »*.
>
> **Base upstream de référence :**
> - **Dépôt officiel amont :** `https://git.launchpad.net/marionnet` (branche `main`)
> - **Commit amont de base :** [`a4147013b824bcdc1f59f3ae97aa9cafdb757f71`](https://git.launchpad.net/marionnet/commit/?id=a4147013b824bcdc1f59f3ae97aa9cafdb757f71) (*docs: the help no longer sends an administrator to `sudo -l`*, 7 septembre 2026, révision 997 / v1.0.423).

---

## 🚀 Correctifs et améliorations majeures

1. **Élimination définitive de l'erreur `/sbin/getty: Input/output error`** :
   - **Remappage automatique du noyau invité** : Les projets demandant l'ancien noyau `3.2.64-ghost` (incompatible avec les hôtes Linux $\ge$ 5.15 en raison d'un crash du stub SKAS0) sont automatiquement remappés vers le noyau moderne `linux-6.12.95-i386`.
   - **Protection contre le verrouillage en lecture seule d'ext4** : Ajout automatique de `rootflags=errors=continue` sur la ligne de commande UML pour empêcher les images non journalisées (Guignol) de monter en lecture seule suite à un arrêt impromptu.
2. **Paquet Debian « Tout-en-un » (`marionnet-all-in-one`) & Distribution Debian complète** :
   - Plus besoin de compiler, ni d'ajouter de clés GPG externes ou de dépôts APT tiers.
   - Embarque l'application Marionnet, les noyaux UML 64-bit et 32-bit (6.12.95) et le système invité Guignol de base.
   - **Distribution invitée Debian Wheezy complète** (`marionnet-fs-debian-wheezy`) incluse pour les machines : Apache2, Lighttpd, BIND9, ISC-DHCP, Python, compilateurs C/C++, navigateurs en mode texte (`links`, `lynx`), et support X11.
   - Configure automatiquement les droits réseau (sudoers), même sous les versions d'Ubuntu récentes avec `sudo-rs`.
3. **Connexion automatique en root (Autologin immédiat)** :
   - Plus besoin de saisir `root` et `root` à chaque ouverture de terminal de machine ou routeur.
   - Le shell s'ouvre directement sur le prompt `root@nom:~#`.
   - Option activée par défaut, configurable directement dans la fenêtre de création ou de modification de chaque machine et routeur (section *Accès* -> *Connexion auto (root)*).
4. **Système de mise à jour automatique intégré (Auto-Update)** :
   - **Mise à jour en un clic ou en CLI** : Mettez à jour Marionnet d'une simple commande `marionnet -u` (ou `marionnet --update`), ou via l'utilitaire `marionnet-update`.
   - **Vérification en arrière-plan** : À l'ouverture de l'application graphique, une vérification non bloquante contacte GitHub Releases et propose la mise à jour immédiate si une nouvelle version existe.
   - **Menu Aide** : Entrée *« Rechercher des mises à jour... »* accessible à tout moment dans le menu supérieur.
5. **Démarrage instantané & Fenêtre de bienvenue configurable** :
   - **Démarrage instantané** : Suppression du délai bloquant de 2500 ms de la popup de bienvenue. Marionnet s'ouvre désormais immédiatement.
   - **Option au menu** : Case à cocher persistante dans le menu *Options* -> *« Afficher la fenêtre de bienvenue au démarrage »* (mémorisée dans `~/.marionnet/marionnet.conf`).
   - **Fenêtre de bienvenue à la demande** : Consultable à tout moment depuis *Aide* -> *« Bienvenue dans Marionnet »*, dotée d'un bouton Fermer explicite.
   - Options CLI `--welcome` et `--no-welcome`.
6. **Modification des distributions des machines à l'arrêt** :
   - Possibilité de changer la distribution (`Guignol`, `Debian Wheezy`, etc.) ou la variante d'une machine arrêtée sans devoir la détruire et la recréer, avec confirmation de réinitialisation du disque COW.
7. **Nouveau système d'internationalisation moderne (i18n JSON)** :
   - Remplacement de l'ancien système GNU gettext et de ses 14 fichiers `.po` lourds (>3,4 Mo) par des dictionnaires JSON propres et légers (`bin/locales/*.json`).
   - Détection automatique de la langue d'affichage (`fr`, `en`, `de`, `es`, `it`, `pt`, `pt_BR`, `ro`, `ru`, `sk`, `tr`, `el`, `eo`) avec fallback transparent vers l'anglais.
   - Sélection personnalisable via la variable d'environnement `MARIONNET_LANG` ou dans `~/.marionnet/marionnet.conf`.
   - Zéro dépendance C gettext ou `msgfmt` : moteur de traduction OCaml pur ultra rapide basé sur `Yojson`.

---

## 📦 Installation ultra simple (Ubuntu 22.04 / 24.04 / 25.04+)

Clonez le dépôt, puis lancez le script d'installation (depuis la racine ou depuis `dist/`) :

```bash
git clone https://github.com/lucas-martinati-pro/marionnet.git
cd marionnet
./install.sh
```

Le script s'occupe de tout automatiquement :
- Active l'architecture 32-bit `i386` si nécessaire
- Télécharge automatiquement les paquets depuis [GitHub Releases (latest)](https://github.com/lucas-martinati-pro/marionnet/releases/latest)
- **Vérifie l'intégrité (SHA256)** des paquets téléchargés contre toute corruption de transfert via le fichier `SHA256SUMS`
- Installe toutes les dépendances Ubuntu (`vde2`, `graphviz`, `uml-utilities`, `xterm`, `curl`, etc.)
- Configure les droits sudoers pour votre utilisateur
- Valide immédiatement l'installation

#### ⚙️ Options du script `install.sh` :
- `./install.sh` : Installation standard via les paquets pré-compilés GitHub Releases.
- `./install.sh -b` (ou `--build`) : Installe directement le binaire compilé localement dans le dépôt (pratique pour tester des modifications locales sans attendre de release).
- `./install.sh --clean` : Force la suppression des paquets `.deb` locaux en cache et retélécharge les versions officielles propres.
- `./install.sh --without-wheezy` : Installation allégée sans l'image Debian Wheezy (uniquement le système invité minimal Guignol).

---

## 🆙 Mises à jour

Pour mettre à jour Marionnet vers la dernière version :

```bash
marionnet -u
# ou directement :
marionnet --update
```

L'utilitaire télécharge la dernière version depuis GitHub, met à jour le paquet tout-en-un et relance la configuration en conservant vos réglages et vos projets.

### Installation manuelle (alternative via GitHub Releases) :
Les paquets `.deb` pré-compilés et leurs sommes de contrôle SHA256 sont publiés sur [GitHub Releases](https://github.com/lucas-martinati-pro/marionnet/releases/latest) :

```bash
# 1. Télécharger le fichier de sommes de contrôle de la dernière release
wget https://github.com/lucas-martinati-pro/marionnet/releases/latest/download/SHA256SUMS

# Identifier les paquets exacts répertoriés
AIO_DEB="$(awk '$2 ~ /^marionnet-all-in-one_.*\.deb$/ {print $2; exit}' SHA256SUMS)"
WHEEZY_DEB="$(awk '$2 ~ /^marionnet-fs-debian-wheezy_.*\.deb$/ {print $2; exit}' SHA256SUMS)"

# Télécharger les paquets Debian correspondants
wget "https://github.com/lucas-martinati-pro/marionnet/releases/latest/download/${AIO_DEB}"
wget "https://github.com/lucas-martinati-pro/marionnet/releases/latest/download/${WHEEZY_DEB}"

# 2. Vérifier l'intégrité SHA256 des fichiers téléchargés
sha256sum -c SHA256SUMS

# 3. Activer l'architecture i386 et mettre à jour APT
sudo dpkg --add-architecture i386
sudo apt update

# 4. Installer les paquets Debian
sudo apt install -y "./${AIO_DEB}" "./${WHEEZY_DEB}"

# 5. Configurer les droits réseau (sudoers) pour votre utilisateur
sudo marionnet-sudoers.sh install "$USER"
```

---

## 🖥️ Utilisation

Une fois installé, lancez simplement :
```bash
marionnet
```
Vous pouvez charger vos projets réseau (fichiers `.mar`) existants ou en créer de nouveaux. Les machines et routeurs démarreront immédiatement dans leurs terminaux xterm sans aucune erreur d'I/O.

---

## 🔄 Récupérer les futures mises à jour officielles (Upstream)

Ce dépôt est configuré avec deux remotes Git :
- `origin` : votre dépôt GitHub (`lucas-martinati-pro/marionnet`)
- `upstream` : le dépôt officiel du projet (`https://git.launchpad.net/marionnet`)

Pour récupérer les futures évolutions et mises à jour publiées par l'équipe officielle de Marionnet :

```bash
# 1. Récupérer les nouveautés du dépôt officiel
git fetch upstream

# 2. Les fusionner dans votre branche principale
git merge upstream/main

# 3. Pousser les mises à jour sur votre GitHub
git push origin main
```

---

## 📚 Crédits & Liens utiles

- Auteur originel et mainteneur principal : **Jean-Vincent Loddo** (LIPN — Université Sorbonne Paris Nord / Paris 13)
- Site officiel : [www.marionnet.org](https://www.marionnet.org)
- Dépôt officiel amont : [https://git.launchpad.net/marionnet](https://git.launchpad.net/marionnet)
- Suivi des bugs officiel : [https://bugs.launchpad.net/marionnet](https://bugs.launchpad.net/marionnet)
