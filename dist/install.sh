#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TARGET_USER="${SUDO_USER:-$USER}"

echo "=========================================================="
echo "    Installation de Marionnet 1.0.456 (All-in-One)"
echo "=========================================================="
echo "Utilisateur cible pour les droits réseau : $TARGET_USER"

# 1. Activation de l'architecture i386 (pour les noyaux UML 32-bit et rétrocompatibilité)
echo "--> [1/4] Activation de l'architecture i386..."
sudo dpkg --add-architecture i386 || true

# 2. Nettoyage des éventuels anciens binaires résiduels
echo "--> [2/4] Nettoyage des anciens binaires résiduels..."
if [ -f /usr/local/bin/marionnet ] || [ -f /usr/local/bin/marionnet.native ]; then
  sudo rm -f /usr/local/bin/marionnet*
fi

# 3. Installation du paquet tout-en-un et de toutes ses dépendances
echo "--> [3/4] Installation du paquet tout-en-un et des dépendances..."
sudo apt update
sudo apt install --reinstall -y ./marionnet-all-in-one_1.0.456_amd64.deb

# 4. Configuration des droits réseau (sudoers)
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
echo "Marionnet 1.0.456 est installé et prêt à l'emploi !"
echo "Lancez simplement 'marionnet' dans votre terminal ou via vos applications."
echo "=========================================================="
