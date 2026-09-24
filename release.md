## Marionnet 1.0.456 — Laboratoire Réseau Virtuel (Édition Linux Moderne)

Paquets d'installation autonomes pour Ubuntu (22.04 / 24.04 / 25.04+) et Debian avec support des noyaux Linux récents (Linux >= 5.15).

---

### 🚀 Nouveautés et Correctifs majeurs (v1.0.456)

1. **Élimination définitive de l'erreur `/sbin/getty: Input/output error`** :
   - **Remappage automatique du noyau invité** : Les projets demandant l'ancien noyau `3.2.64-ghost` (incompatible avec les hôtes Linux récents en raison du crash du stub SKAS0) sont automatiquement remappés vers le noyau moderne `linux-6.12.95-i386`.
   - **Protection contre le verrouillage en lecture seule d'ext4** : Ajout automatique de `rootflags=errors=continue` sur la ligne de commande UML pour empêcher les images non journalisées (Guignol) de monter en lecture seule suite à un arrêt impromptu.

2. **Paquet Debian « Tout-en-un » (`marionnet-all-in-one`) & Distribution Debian complète** :
   - Plus besoin de compiler, ni d'ajouter de clés GPG externes ou de dépôts APT tiers.
   - Embarque l'application Marionnet 1.0.456, les noyaux UML 64-bit et 32-bit (6.12.95) et le système invité Guignol de base.
   - **Distribution Debian Wheezy complète** (`marionnet-fs-debian-wheezy`) : intègre désormais Apache2, Lighttpd, BIND9, ISC-DHCP, Python, compilateurs C/C++, navigateurs web (`links`, `lynx`), outils de diagnostic et support graphique X11.
   - Configuration automatique des droits réseau (sudoers), compatible avec `sudo` classique et `sudo-rs` (Ubuntu 24.10+).

3. **Connexion automatique en root (Autologin immédiat)** :
   - Plus besoin de saisir `root` et `root` à chaque ouverture de terminal de machine ou routeur.
   - Le shell s'ouvre directement sur le prompt `root@nom:~#`.
   - Option activée par défaut, configurable directement dans la fenêtre de création ou de modification de chaque machine et routeur (*Accès* -> *Connexion auto (root)*).

4. **Optimisation des performances et réactivité de l'interface** :
   - Exécution de Graphviz `dot` déportée en tâche d'arrière-plan avec temporisation (debounce) pour éviter tout gel de l'interface GTK lors de l'édition de topologie.
   - Écran de démarrage (splash screen) avec fermeture automatique au bout de 2,5 secondes.
   - Fermeture propre et parallélisée de la topologie réseau lors de la fermeture de l'application.

---

### 📦 Installation ultra simple

Clonez le dépôt, puis lancez le script d'installation :

```bash
git clone https://github.com/lucas-martinati-pro/marionnet.git
cd marionnet/dist
./install.sh
```

Le script `install.sh` s'occupe de tout automatiquement :
- Active l'architecture 32-bit (`i386`) si nécessaire.
- Télécharge automatiquement le paquet Debian tout-en-un et la distribution invitée **Debian Wheezy** depuis GitHub Releases s'ils ne sont pas présents localement.
- Installe toutes les dépendances requises (`vde2`, `graphviz`, `uml-utilities`, `xterm`, `socat`, etc.).
- Configure les règles réseau sudoers pour votre utilisateur.
- Valide immédiatement l'installation (`marionnet version 1.0.456`).

*(Note : pour une installation légère sans l'image Debian Wheezy, passez l'option `./install.sh --without-wheezy`)*.

---

### 💻 Alternative : Installation manuelle

```bash
# 1. Télécharger les paquets
wget https://github.com/lucas-martinati-pro/marionnet/releases/download/v1.0.456/marionnet-all-in-one_1.0.456_amd64.deb
wget https://github.com/lucas-martinati-pro/marionnet/releases/download/v1.0.456/marionnet-fs-debian-wheezy_08367_all.deb

# 2. Activer l'architecture i386 et mettre à jour APT
sudo dpkg --add-architecture i386
sudo apt update

# 3. Installer les paquets et leurs dépendances
sudo apt install -y ./marionnet-all-in-one_1.0.456_amd64.deb ./marionnet-fs-debian-wheezy_08367_all.deb
```
