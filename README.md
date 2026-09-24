# Marionnet 1.0.456 — Laboratoire Réseau Virtuel (Édition Linux Moderne)

[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04%20%7C%2025.04+-orange.svg)](https://ubuntu.com)
[![Version](https://img.shields.io/badge/version-1.0.456-blue.svg)](https://github.com/lucas-martinati-pro/marionnet)
[![License](https://img.shields.io/badge/license-GPL--2.0-green.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

**Marionnet** est un laboratoire réseau virtuel permettant de définir, configurer et exécuter un réseau informatique complet (machines virtuelles Linux sous User-Mode Linux, routeurs, switchs VDE, concentrateurs, passerelles...) sur une seule machine sans matériel physique dédié.

Ce dépôt est un fork maintenu de [Marionnet (Launchpad)](https://git.launchpad.net/marionnet), spécialement corrigé pour fonctionner nativement et sans plantage sur les distributions Linux et noyaux récents.

---

## 🚀 Correctifs majeurs inclus (v1.0.456)

1. **Élimination définitive de l'erreur `/sbin/getty: Input/output error`** :
   - **Remappage automatique du noyau invité** : Les projets demandant l'ancien noyau `3.2.64-ghost` (incompatible avec les hôtes Linux $\ge$ 5.15 en raison d'un crash du stub SKAS0) sont automatiquement remappés vers le noyau moderne `linux-6.12.95-i386`.
   - **Protection contre le verrouillage en lecture seule d'ext4** : Ajout automatique de `rootflags=errors=continue` sur la ligne de commande UML pour empêcher les images non journalisées (Guignol) de monter en lecture seule suite à un arrêt impromptu.
2. **Paquet Debian « Tout-en-un » (`marionnet-all-in-one`)** :
   - Plus besoin de compiler, ni d'ajouter de clés GPG externes ou de dépôts APT tiers.
   - Embarque l'application, les noyaux UML 64-bit et 32-bit (6.12.95) et le système invité Guignol de base.
   - Configure automatiquement les droits réseau (sudoers), même sous les versions d'Ubuntu récentes avec `sudo-rs`.
3. **Connexion automatique en root (Autologin immédiat)** :
   - Plus besoin de saisir `root` et `root` à chaque ouverture de terminal de machine ou routeur.
   - Le shell s'ouvre directement sur le prompt `root@nom:~#`.
   - Option activée par défaut, configurable directement dans la fenêtre de création ou de modification de chaque machine et routeur (section *Accès* -> *Connexion auto (root)*).

---


## 📦 Installation ultra simple (Ubuntu 22.04 / 24.04 / 25.04+)

Clonez le dépôt (ou téléchargez le dossier `dist/`), puis lancez le script d'installation :

```bash
git clone https://github.com/lucas-martinati-pro/marionnet.git
cd marionnet/dist
./install.sh
```

Le script s'occupe de tout automatiquement :
- Active l'architecture 32-bit `i386` si nécessaire
- Installe le paquet tout-en-un ainsi que toutes les dépendances Ubuntu (`vde2`, `graphviz`, `uml-utilities`, `xterm`, etc.)
- Configure les droits sudoers pour votre utilisateur
- Valide l'installation (`marionnet version 1.0.456`)

### Installation manuelle (alternative) :
```bash
# Téléchargement direct du paquet All-in-One depuis les Releases GitHub
wget https://github.com/lucas-martinati-pro/marionnet/releases/download/v1.0.456/marionnet-all-in-one_1.0.456_amd64.deb

sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y ./marionnet-all-in-one_1.0.456_amd64.deb
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
