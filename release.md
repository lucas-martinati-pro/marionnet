## Marionnet 1.0.457 — Laboratoire Réseau Virtuel (Édition Linux Moderne)

Paquets d'installation autonomes pour Ubuntu (22.04 / 24.04 / 25.04+) et Debian avec support des noyaux Linux récents (Linux >= 5.15) et environnement OCaml modernisé.

---

### 🚀 Nouveautés et Améliorations majeures (v1.0.457)

#### 1. 🌐 Refonte complète du système d'internationalisation (i18n moderne en JSON)
- **Migration des catalogues de traduction** : Remplacement des anciens fichiers binaires `.mo` / `.po` par des fichiers JSON structurés et éditables pour 14 langues (français, anglais, espagnol, allemand, italien, portugais, etc.).
- **Identifiants sémantiques** : Remplacement des textes en anglais brut utilisés comme clés par des identifiants sémantiques normalisés (`hub.tooltip.name`, `router.tooltip.name`, `machine.tooltip.name`, etc.).
- **Mécanisme de secours à double table (Dual-Table Fallback)** : Si une clé de traduction est absente ou partielle dans une langue donnée, l'affichage bascule automatiquement et de manière transparente sur le texte anglais (`en.json`), évitant tout texte manquant ou brisé.
- **Évaluation dynamique à chaud** : Les noms de composants dans les dialogues (`kind_name : unit -> string`) sont désormais évalués dynamiquement pour refléter immédiatement un changement de langue à l'exécution.
- **Nettoyage typographique** : Élimination des balises Pango/HTML superflues des chaînes à traduire pour une meilleure lisibilité.

#### 2. 🛡️ Sécurisation des types OCaml & Refactorisation architecturale
- **Élimination de 11 casts non-typés `Obj.magic`** :
  - Sécurisation complète des actions de suppression (`Remove.reaction`) sur les 8 composants réseau (`hub`, `switch`, `router`, `machine`, `cloud`, `world_gateway`, `nat_bridge`, `lan_bridge`) en s'appuyant directement sur la méthode virtuelle `#destroy` de la classe de base `User_level.node`.
  - Élimination des casts non-sécurisés lors de la création et manipulation des câbles réseau (`cable.ml`).
- **Factorisation du code de cycle de vie (`Make_menus`)** :
  - Création du foncteur centralisé `Lifecycle` dans `Gui_toolbar_COMPONENTS_layouts`, éliminant plus de **350 lignes de code dupliqué** pour les opérations `Remove`, `Startup`, `Stop`, `Suspend` et `Resume`.
- **Harmonisation des stubs `Data.to_string`** :
  - Remplacement de tous les stubs temporaires `"<obj>"` par des implémentations de diagnostic complètes et formatées (`Printf.sprintf`) sur l'ensemble des 9 modules de composants réseau (y compris `bridge_common` et `nat_bridge`).
- **Fiabilisation de la gestion des exceptions** :
  - Ciblage explicite de l'exception `Not_found` dans les méthodes de recherche du réseau (`get_node_by_name`, `get_cable_by_name`, `get_component_by_name`) afin de ne plus masquer silencieusement les erreurs système ou d'allocation mémoire.

#### 3. 🔄 Changement dynamique de distribution invitée (Filesystem VM)
- Possibilité de modifier à chaud la distribution d'une machine virtuelle arrêtée (ex. basculer entre **Guignol** et **Debian Wheezy**) directement depuis la fenêtre de dialogue des propriétés de la machine.
- Dialogue de confirmation préalable avec avertissement clair de perte des modifications locales, et réinitialisation automatique et propre du disque différentiel (COW).

#### 4. ⚡ Système d'auto-mise à jour & Amélioration de l'interface
- Détection et notification automatique de la disponibilité des nouvelles versions de Marionnet.
- Fenêtre d'accueil (Welcome Popup) enrichie d'une option mémorisée « Ne plus afficher au démarrage ».
- Correction visuelle dans l'éditeur de configuration (désactivation du surlignage perturbateur de la ligne courante).

#### 5. 🐧 Standardisation des scripts Unix
- Normalisation des exécutables sous leur nom de commande Unix standard (`marionnet-check`, `marionnet-cleanup`, `marionnet-ctl`, `marionnet-verify`, `marionnet-update`).
- Conservation de liens symboliques pour tous les alias raccourcis usuels (`mrnctl`, `mrn-check`, etc.).

---

### 📦 Installation ultra simple

Clonez le dépôt, puis lancez le script d'installation :

```bash
git clone https://github.com/lucas-martinati-pro/marionnet.git
cd marionnet
./install.sh
```

Le script `install.sh` s'occupe de tout automatiquement :
- Active l'architecture 32-bit (`i386`) si nécessaire.
- Télécharge automatiquement les paquets Debian depuis GitHub Releases s'ils ne sont pas présents localement.
- **Vérifie l'intégrité cryptographique SHA256** des paquets via `SHA256SUMS`.
- Installe toutes les dépendances requises (`vde2`, `graphviz`, `uml-utilities`, `xterm`, `socat`, etc.).
- Configure les règles réseau sudoers pour votre utilisateur.
- Valide immédiatement l'installation (`marionnet version 1.0.457`).
- **Options utiles** :
  - `./install.sh --clean` : Force la suppression des paquets locaux et le retéléchargement propre depuis GitHub Releases.
  - `./install.sh --without-wheezy` : Installation légère sans l'image Debian Wheezy.

---

### 💻 Alternative : Installation manuelle

```bash
# 1. Télécharger les paquets et les sommes de contrôle
wget https://github.com/lucas-martinati-pro/marionnet/releases/download/v1.0.457/SHA256SUMS
wget https://github.com/lucas-martinati-pro/marionnet/releases/download/v1.0.457/marionnet-all-in-one_1.0.457_amd64.deb
wget https://github.com/lucas-martinati-pro/marionnet/releases/download/v1.0.457/marionnet-fs-debian-wheezy_08367_all.deb

# 2. Vérifier l'intégrité SHA256
sha256sum -c SHA256SUMS --ignore-missing

# 3. Activer l'architecture i386 et mettre à jour APT
sudo dpkg --add-architecture i386
sudo apt update

# 4. Installer les paquets et leurs dépendances
sudo apt install -y ./marionnet-all-in-one_1.0.457_amd64.deb ./marionnet-fs-debian-wheezy_08367_all.deb
```
