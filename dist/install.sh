#!/usr/bin/env bash
set -euo pipefail

# Configuration par défaut (surchargable via argument ou variables d'environnement)
VERSION="${1:-${MARIONNET_VERSION:-1.0.456}}"
GITHUB_REPO="${MARIONNET_REPO:-lucas-martinati-pro/marionnet}"
DEB_NAME="marionnet-all-in-one_${VERSION}_amd64.deb"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET_USER="${SUDO_USER:-$USER}"

echo "=========================================================="
echo "    Installation de Marionnet $VERSION (All-in-One)"
echo "=========================================================="
echo "Utilisateur cible pour les droits réseau : $TARGET_USER"

# 0. Vérification de l'architecture du système hôte
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
  echo "[-] ERREUR : Architecture hôte '$ARCH' non supportée." >&2
  echo "    Marionnet et ses noyaux User-Mode Linux nécessitent une architecture x86_64 (amd64)." >&2
  echo "    Si vous êtes sur Mac Apple Silicon (M1/M2/M3/M4), veuillez exécuter une VM Linux x86_64 émulée." >&2
  exit 1
fi

# 1. Vérification / Téléchargement du paquet All-in-One
if [ ! -f "$DEB_NAME" ]; then
  RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${DEB_NAME}"
  echo "--> Paquet '$DEB_NAME' non trouvé localement."
  echo "--> Téléchargement depuis GitHub Releases (v${VERSION})..."
  echo "    Source : $RELEASE_URL"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar "$RELEASE_URL" -o "$DEB_NAME"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$DEB_NAME" "$RELEASE_URL"
  else
    echo "    curl ou wget non trouvé. Installation de curl via apt..."
    sudo apt update && sudo apt install -y curl
    curl -fL --progress-bar "$RELEASE_URL" -o "$DEB_NAME"
  fi

  if [ ! -s "$DEB_NAME" ]; then
    echo "[-] ERREUR : Le téléchargement de $DEB_NAME a échoué ou le fichier est vide." >&2
    echo "    Vérifiez que la release v${VERSION} existe bien sur https://github.com/${GITHUB_REPO}/releases" >&2
    rm -f "$DEB_NAME"
    exit 1
  fi
  echo "    Téléchargement terminé avec succès."
else
  echo "--> Paquet '$DEB_NAME' trouvé localement."
fi

# 2. Activation de l'architecture i386 (pour les noyaux UML 32-bit et rétrocompatibilité)
echo "--> [1/4] Activation de l'architecture i386..."
sudo dpkg --add-architecture i386 || true

# 3. Nettoyage des éventuels anciens binaires résiduels
echo "--> [2/4] Nettoyage des anciens binaires résiduels..."
if [ -f /usr/local/bin/marionnet ] || [ -f /usr/local/bin/marionnet.native ]; then
  sudo rm -f /usr/local/bin/marionnet*
fi

# 4. Installation du paquet tout-en-un et de toutes ses dépendances
echo "--> [3/4] Installation du paquet tout-en-un et des dépendances système..."
sudo apt update
sudo apt install --reinstall -y ./"$DEB_NAME"

# 5. Configuration des droits réseau (sudoers)
echo "--> [4/4] Configuration des droits réseau (sudoers)..."
if ! sudo marionnet-sudoers.sh install "$TARGET_USER" 2>/dev/null; then
  # Fallback compatible avec sudo-rs (Ubuntu 24.10+) et sudo classique
  echo "    Application de la règle sudoers compatible..."
  cat << EOF | sudo tee /etc/sudoers.d/marionnet > /dev/null
# Règle réseau Marionnet pour $TARGET_USER
$TARGET_USER ALL=(root) NOPASSWD: /usr/sbin/ip, /usr/bin/marionnet-tap.sh, /usr/bin/marionnet-tun-device.sh
EOF
  sudo chmod 0440 /etc/sudoers.d/marionnet
fi

echo "=========================================================="
echo "--> Vérification de l'installation :"
marionnet -v
echo "=========================================================="
echo "Marionnet $VERSION est installé et prêt à l'emploi !"
echo "Lancez simplement 'marionnet' dans votre terminal ou via vos applications."
echo "=========================================================="
