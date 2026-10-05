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

# Un fichier partiel (curl interrompu par Ctrl-C, connexion coupée) existe et
# semble valide au premier regard : --info ne lit que l'en-tête, --fsys-tarfile
# traverse TOUTE l'archive et coince les troncations (2802624 attendus, 2486272
# reçus : mesuré). curl reprend (--continue-at) avec réessais, et une couche
# toujours invalide après téléchargement est FATALE -- un AIO partiel est pire
# que pas d'AIO, et le crash dpkg-deb plus loin serait incompréhensible.
deb_ok() { [ -f "$1" ] && dpkg-deb --fsys-tarfile "$1" >/dev/null 2>&1; }
fetch_layer() {  # <deb> : reprend le partiel (-C -), réessaie, puis échoue dur
  local deb="$1"
  echo "--> Téléchargement du composant de base $deb depuis GitHub Releases ($BASE_RELEASE_TAG)..."
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -C - \
    "https://github.com/${GITHUB_REPO}/releases/download/${BASE_RELEASE_TAG}/$deb" -o "$deb" || true
  deb_ok "$deb" || {
    echo "[-] ERREUR : impossible de récupérer un $deb valide après réessais." >&2
    rm -f "$deb"
    exit 1
  }
}
for deb in "$KERNELS_DEB" "$KERNELS_I386_DEB" "$FS_DEB"; do
  deb_ok "$deb" || fetch_layer "$deb"
done
# Wheezy volontairement EXCLU : 403 Mo jamais dépaquetés dans l'AIO (seul son
# hash partait dans SHA256SUMS du temps des uploads par release). Il est
# épinglé sur la release de base et servi par install.sh, pas reconstruit ici.

# 3. Vérification du paquet applicatif marionnet
if ! deb_ok "$APP_DEB"; then
  rm -f "$APP_DEB"
  # Si une version antérieure existe (ex: 1.0.456), on peut s'en servir de base
  BASE_APP_DEB="$(ls marionnet_*_amd64.deb 2>/dev/null | grep -v all-in-one | head -n 1 || true)"
  if [ -n "$BASE_APP_DEB" ] && ! deb_ok "$BASE_APP_DEB"; then
    echo "--> Paquet applicatif local $BASE_APP_DEB corrompu, ignoré." >&2
    rm -f "$BASE_APP_DEB"
    BASE_APP_DEB=""
  fi
  if [ -z "$BASE_APP_DEB" ]; then
    BASE_APP_DEB="marionnet_1.0.456_amd64.deb"
    fetch_layer "$BASE_APP_DEB"
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

# Pas d'extension ni de scripts d'invités sur le PATH : les 4 doublons `.sh`
# (morts depuis 2b2fc87 : check, cleanup, ctl, verify) et les 8 fichiers qui ne
# sont jamais exécutés depuis un PATH -- contenus embarqués par INCLUDE_AS_STRING
# et déposés dans les invités (relay.*, report, watch, terminal-record,
# can-directory-*) ou sourcés depuis le répertoire de complétion (completion).
# Rien ne les appelle par leur chemin installé (vérifié par grep) ; la couche
# applicative de base les ramène, d'où ce retrait explicite après dépaquetage.
for noise in marionnet-check.sh marionnet-cleanup.sh marionnet-ctl.sh marionnet-verify.sh \
             marionnet-relay.00-journal.sh marionnet-relay.05-autologin.sh \
             marionnet-relay.zz-journal.sh marionnet-report.sh marionnet-watch.sh \
             marionnet-terminal-record.sh can-directory-host-sparse-files.sh \
             marionnet-completion.bash; do
  rm -f "$BUILD_DIR/root/usr/bin/$noise"
done

mkdir -p "$BUILD_DIR/root/DEBIAN"

echo "--> Génération des métadonnées du paquet Debian..."
INSTALLED_SIZE="$(du -sk "$BUILD_DIR/root" | cut -f1)"

# Union des Depends des couches, sans doublon, dans l'ordre de première
# apparition (appli, kernels, kernels-i386, fs-guignol) : le découpage est la
# SEULE source de vérité, ce script ne recopie AUCUNE dépendance à la main
# (c'est une liste écrite à la main qui avait perdu libc6:i386). Les tokens qui
# nomment nos propres paquets (ex. `marionnet' dans le Depends de kernels-i386,
# satisfait par le Provides ci-dessous) sont filtrés.
merged_depends() {  # <deb>...
  local deb
  for deb in "$@"; do
    if [ -f "$deb" ]; then
      dpkg-deb -f "$deb" Depends 2>/dev/null || continue
    else
      echo "[-] Avertissement : couche absente, Depends incomplet : $deb" >&2
    fi
  done | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n \+/ /g' \
    | awk -F',' '{
        for (i=1; i<=NF; i++) {
          s=$i; sub(/^ +/, "", s); sub(/ +$/, "", s);
          if (s == "" || s ~ /^marionnet(-|[ (]|$)/) continue;
          if (!seen[s]++) out = (out == "" ? s : out ", " s);
        }
      } END { print out }'
}

echo "--> Calcul du Depends depuis les paquets découpés..."
AIO_DEPENDS="$(merged_depends "$BASE_APP_DEB" "$KERNELS_DEB" "$KERNELS_I386_DEB" "$FS_DEB")"
if [ -z "$AIO_DEPENDS" ]; then
  echo "[-] ERREUR : Depends vide -- aucune couche ne déclare de dépendances." >&2
  exit 1
fi
# Garde verrouillant le bug du noyau i386 inexécutable : son interpréteur
# /lib/ld-linux.so.2 n'est fourni que par libc6:i386 (cf. package_kernels_i386).
if [[ "$AIO_DEPENDS" != *"libc6:i386"* ]]; then
  echo "[-] ERREUR : libc6:i386 absent du Depends calculé ($AIO_DEPENDS)." >&2
  echo "    Le noyau linux-6.12.95-i386 serait inexécutable. Build annulé." >&2
  exit 1
fi
echo "    Depends : $AIO_DEPENDS"

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
Depends: $AIO_DEPENDS
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
