#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

# 1. Détermination dynamique de la version cible (depuis bin/meta.ml.maker.sh ou META)
if [ -n "${1:-}" ]; then
  VERSION="$1"
elif [ -f "$REPO_ROOT/bin/meta.ml.maker.sh" ]; then
  VERSION="$(bash "$REPO_ROOT/bin/meta.ml.maker.sh" --print-version 2>/dev/null || true)"
fi
if [ -z "${VERSION:-}" ] && [ -f "$REPO_ROOT/META" ]; then
  VERSION="$(grep -Po '(?<=version=")[^"]*' "$REPO_ROOT/META" 2>/dev/null || true)"
fi
if [[ ! $VERSION =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "[-] ERREUR : Version invalide ou impossible à déterminer ($VERSION)." >&2
  exit 1
fi

KERNEL_VER="6.12.95"
FS_VER="18474"
GITHUB_REPO="${MARIONNET_REPO:-lucas-martinati-pro/marionnet}"
BASE_RELEASE_TAG="v1.0.456"

echo "=========================================================="
echo "    Génération du paquet All-in-One pour Marionnet $VERSION"
echo "=========================================================="

# 2. Vérification / Récupération des paquets de base (noyaux et images système)
KERNELS_DEB="marionnet-kernels_${KERNEL_VER}_amd64.deb"
KERNELS_I386_DEB="marionnet-kernels-i386_${KERNEL_VER}_amd64.deb"
FS_DEB="marionnet-fs-guignol_${FS_VER}_all.deb"
WHEEZY_DEB="marionnet-fs-debian-wheezy_08367_all.deb"
APP_DEB="marionnet_${VERSION}_amd64.deb"
AIO_DEB="marionnet-all-in-one_${VERSION}_amd64.deb"

for deb in "$KERNELS_DEB" "$KERNELS_I386_DEB" "$FS_DEB" "$WHEEZY_DEB"; do
  if [ ! -f "$deb" ]; then
    echo "--> Téléchargement du composant de base $deb depuis GitHub Releases ($BASE_RELEASE_TAG)..."
    curl -fsSL "https://github.com/${GITHUB_REPO}/releases/download/${BASE_RELEASE_TAG}/$deb" -o "$deb" || {
      echo "[-] Avertissement : impossible de récupérer $deb depuis les releases." >&2
    }
  fi
done

# 3. Vérification du paquet applicatif marionnet
if [ ! -f "$APP_DEB" ]; then
  # Si une version antérieure existe (ex: 1.0.456), on peut s'en servir de base
  BASE_APP_DEB="$(ls marionnet_*_amd64.deb 2>/dev/null | grep -v all-in-one | head -n 1 || true)"
  if [ -z "$BASE_APP_DEB" ]; then
    echo "--> Téléchargement du paquet application de référence..."
    curl -fsSL "https://github.com/${GITHUB_REPO}/releases/download/${BASE_RELEASE_TAG}/marionnet_1.0.456_amd64.deb" -o "marionnet_1.0.456_amd64.deb"
    BASE_APP_DEB="marionnet_1.0.456_amd64.deb"
  fi
else
  BASE_APP_DEB="$APP_DEB"
fi

BUILD_DIR="$(mktemp -d /tmp/marionnet-aio-build.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "--> Décompression des couches dans l'arborescence cible..."
mkdir -p "$BUILD_DIR/root"
dpkg-deb -x "$BASE_APP_DEB" "$BUILD_DIR/root"
dpkg-deb -x "$KERNELS_DEB" "$BUILD_DIR/root"
dpkg-deb -x "$KERNELS_I386_DEB" "$BUILD_DIR/root"
dpkg-deb -x "$FS_DEB" "$BUILD_DIR/root"

# Si un binaire local fraîchement compilé existe, on l'utilise pour garantir la fraîcheur
if [ -f "$REPO_ROOT/_build/default/bin/marionnet.exe" ]; then
  echo "--> Intégration du binaire local compilé (_build/default/bin/marionnet.exe)..."
  cp "$REPO_ROOT/_build/default/bin/marionnet.exe" "$BUILD_DIR/root/usr/bin/marionnet.native"
  chmod 755 "$BUILD_DIR/root/usr/bin/marionnet.native"
  ln -sf marionnet.native "$BUILD_DIR/root/usr/bin/marionnet"
fi

# Copie des scripts récents depuis bin/scripts si existants
if [ -d "$REPO_ROOT/bin/scripts" ]; then
  for script in "$REPO_ROOT"/bin/scripts/*; do
    if [ -f "$script" ]; then
      base="$(basename "$script")"
      cp -a "$script" "$BUILD_DIR/root/usr/bin/" 2>/dev/null || true
    fi
  done
fi

mkdir -p "$BUILD_DIR/root/DEBIAN"

echo "--> Génération des métadonnées du paquet Debian..."
INSTALLED_SIZE="$(du -sk "$BUILD_DIR/root" | cut -f1)"

# Le noyau i386 embarqué est un ELF dont l'interpréteur /lib/ld-linux.so.2
# n'est fourni que par libc6:i386 (pas libc6-i386) : sans ce Depends, apt
# n'installe pas le runtime, l'exec du noyau échoue et la première machine
# meurt avec "died unexpectedly". Cf. package_kernels_i386 (release.deb.sh).
cat << EOF > "$BUILD_DIR/root/DEBIAN/control"
Package: marionnet-all-in-one
Version: $VERSION
Section: net
Priority: optional
Architecture: amd64
Maintainer: Lucas Martinati <lucasm54800@gmail.com>
Homepage: https://www.marionnet.org
Provides: marionnet (= $VERSION), marionnet-kernels (= $KERNEL_VER), marionnet-kernels-i386 (= $KERNEL_VER), marionnet-fs-guignol (= $FS_VER)
Replaces: marionnet, marionnet-kernels, marionnet-kernels-i386, marionnet-fs-guignol
Conflicts: marionnet (<< $VERSION)
Depends: libc6 (>= 2.35), libc6:i386, libcairo2, libfontconfig1, libfreetype6, libgdk-pixbuf-2.0-0, libglib2.0-0t64 | libglib2.0-0, libgtk-3-0t64 | libgtk-3-0, libgtksourceview-3.0-1, libpango-1.0-0, libpangocairo-1.0-0, vde2, graphviz, uml-utilities, xterm, iproute2, sudo, x11-xserver-utils, xauth, jq, socat, dnsmasq-base, xz-utils, curl
Description: Complete standalone distribution of Marionnet (Virtual Network Laboratory)
 Marionnet lets a student define, configure and run a complete computer network
 -- machines, routers, switches, hubs, cables, gateways -- on a single host, with
 no physical setup at all. The virtual machines are real Linux systems running as
 User-Mode Linux processes, wired together by vde switches, so what is learned
 here is what happens on real equipment.
 .
 This all-in-one package includes Marionnet v$VERSION, 64-bit & 32-bit UML kernels ($KERNEL_VER),
 and the Guignol guest system image, ready to use immediately without extra repository setup.
Installed-Size: $INSTALLED_SIZE
EOF

cat << 'EOF' > "$BUILD_DIR/root/DEBIAN/postinst"
#!/bin/sh
set -e
case "$1" in
  configure)
    [ -x /usr/bin/marionnet-setup-check.sh ] && /usr/bin/marionnet-setup-check.sh --package-manager apt || true
    [ -x /usr/bin/marionnet-tun-check.sh ] && /usr/bin/marionnet-tun-check.sh || true
    ;;
esac
exit 0
EOF
chmod 755 "$BUILD_DIR/root/DEBIAN/postinst"

cat << 'EOF' > "$BUILD_DIR/root/DEBIAN/prerm"
#!/bin/sh
set -e
case "$1" in
  remove|upgrade|deconfigure)
    if [ -x /usr/bin/marionnet-cleanup ]; then
      /usr/bin/marionnet-cleanup || true
    elif [ -x /usr/bin/marionnet-cleanup.sh ]; then
      /usr/bin/marionnet-cleanup.sh || true
    fi
    ;;
esac
exit 0
EOF
chmod 755 "$BUILD_DIR/root/DEBIAN/prerm"

cat << 'EOF' > "$BUILD_DIR/root/DEBIAN/conffiles"
/etc/marionnet/marionnet.conf
EOF

echo "--> Construction du paquet $AIO_DEB..."
dpkg-deb --root-owner-group --build -Zxz "$BUILD_DIR/root" "$AIO_DEB" >/dev/null

echo "--> Paquet créé avec succès : $SCRIPT_DIR/$AIO_DEB ($(ls -lh "$AIO_DEB" | awk '{print $5}'))"

# 4. Vérification de compatibilité de la GLIBC
if dpkg-deb --fsys-tarfile "$AIO_DEB" 2>/dev/null | tar -x -O ./usr/bin/marionnet.native 2>/dev/null | grep -qa "GLIBC_2.4[2-9]"; then
  echo "[-] ATTENTION CRITIQUE : Le binaire inclus dans $AIO_DEB est lié à GLIBC >= 2.42 !" >&2
  echo "    Ce paquet sera INCOMPATIBLE avec Ubuntu 22.04 LTS, Ubuntu 24.04 LTS et Debian 12." >&2
  echo "    Les versions de production officielles doivent être générées via GitHub Actions (ubuntu-22.04/24.04)." >&2
fi

# 5. Génération automatique du fichier de sommes de contrôle SHA256SUMS
echo "--> Génération des sommes de contrôle SHA256 (SHA256SUMS)..."
sha256sum "$AIO_DEB" > "$SCRIPT_DIR/SHA256SUMS"
if [ -f "$SCRIPT_DIR/$WHEEZY_DEB" ]; then
  sha256sum "$WHEEZY_DEB" >> "$SCRIPT_DIR/SHA256SUMS"
fi
echo "--> Fichier SHA256SUMS généré dans : $SCRIPT_DIR/SHA256SUMS"
