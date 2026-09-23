#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================================="
echo "    Installation de Marionnet 1.0.456 (All-in-One)"
echo "=========================================================="

echo "--> Nettoyage des éventuels anciens binaires résiduels dans /usr/local/bin..."
if [ -f /usr/local/bin/marionnet ] || [ -f /usr/local/bin/marionnet.native ]; then
  sudo rm -f /usr/local/bin/marionnet*
fi

echo "--> Installation du paquet tout-en-un et de ses dépendances système..."
sudo apt update
sudo apt install -y ./marionnet-all-in-one_1.0.456_amd64.deb

echo "--> Vérification de l'installation..."
marionnet -v

echo "=========================================================="
echo "Marionnet 1.0.456 est installé et prêt à l'emploi !"
echo "Lancez simplement 'marionnet' dans votre terminal ou via vos applications."
echo "=========================================================="
