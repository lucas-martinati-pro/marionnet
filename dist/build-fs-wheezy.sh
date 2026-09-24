#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

FS_VERSION="08367"
TARGET_DEB="marionnet-fs-debian-wheezy_${FS_VERSION}_all.deb"

echo "=========================================================="
echo "    Construction du paquet Debian pour Debian Wheezy"
echo "=========================================================="

# Recherche de l'image source Wheezy
SEARCH_PATHS=(
  "/usr/local/share/marionnet/filesystems"
  "/usr/share/marionnet/filesystems"
  "${HOME}/.marionnet/filesystems"
)

SOURCE_DIR=""
for p in "${SEARCH_PATHS[@]}"; do
  if [ -f "$p/machine-debian-wheezy-08367" ]; then
    SOURCE_DIR="$p"
    break
  fi
done

if [ -z "$SOURCE_DIR" ]; then
  echo "[-] ERREUR : Impossible de trouver 'machine-debian-wheezy-08367'." >&2
  echo "    Recherché dans : ${SEARCH_PATHS[*]}" >&2
  exit 1
fi

echo "--> Image source trouvée dans : $SOURCE_DIR"

BUILD_DIR="$(mktemp -d /tmp/marionnet-fs-wheezy-build.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

FS_DEST="$BUILD_DIR/root/usr/share/marionnet/filesystems"
DEBIAN_DEST="$BUILD_DIR/root/DEBIAN"
mkdir -p "$FS_DEST" "$DEBIAN_DEST"

echo "--> Copie des fichiers système..."
cp -p "$SOURCE_DIR/machine-debian-wheezy-08367" "$FS_DEST/"
cp -p "$SOURCE_DIR/machine-debian-wheezy-08367.conf" "$FS_DEST/" 2>/dev/null || true
mkdir -p "$FS_DEST/machine-debian-wheezy-08367_variants"

# Règle impérative UML : préserver le MTIME exact de l'image (1404061349)
MTIME="1404061349"
touch -d "@$MTIME" "$FS_DEST/machine-debian-wheezy-08367"

echo "--> Génération des métadonnées du paquet..."
INSTALLED_SIZE="$(du -sk "$BUILD_DIR/root" | cut -f1)"

cat << EOF > "$DEBIAN_DEST/control"
Package: marionnet-fs-debian-wheezy
Version: $FS_VERSION
Section: net
Priority: optional
Architecture: all
Maintainer: Lucas Martinati <lucasm54800@gmail.com>
Homepage: https://www.marionnet.org
Depends: marionnet, marionnet-kernels-i386
Replaces: marionnet-all-in-one, marionnet
Description: Debian Wheezy guest image for Marionnet virtual network laboratory
 Complete Debian 7 (Wheezy) guest filesystem image for Marionnet.
 Includes networking tools, Apache2, Lighttpd, DNS (bind9), DHCP, Python,
 C/C++ toolchains, text browsers (links, lynx), and X11 graphic support.
 .
 Installed under /usr/share/marionnet/filesystems, where Marionnet looks
 for them.
Installed-Size: $INSTALLED_SIZE
EOF

echo "--> Compression et génération de $TARGET_DEB (XZ multi-threads)..."
XZ_OPT="-T0 -6" dpkg-deb --root-owner-group --build -Zxz "$BUILD_DIR/root" "$TARGET_DEB" >/dev/null

echo "--> Paquet créé avec succès : $SCRIPT_DIR/$TARGET_DEB ($(ls -lh "$TARGET_DEB" | awk '{print $5}'))"
