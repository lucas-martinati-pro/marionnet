#!/usr/bin/env bash
set -euo pipefail

# Configuration par défaut (surchargable via argument ou variables d'environnement)
VERSION="${MARIONNET_VERSION:-}"
INSTALL_WHEEZY=true
FORCE_DOWNLOAD=false
BUILD_LOCAL=false
RELEASE_MODE=false

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] [VERSION]
       $(basename "$0") --tarball [ENGINE-OPTIONS]

Installeur unique de Marionnet, deux moteurs (intacts, chacun avec son banc
et son --help) :
  .deb (défaut) : paquet All-in-One via apt (Ubuntu/Debian x86_64).
  tarball (--tarball) : moteur marionnet-install.sh -- installation sous un
    préfixe local, toutes distributions (--binary, --fetch-only...).

Moteur .deb :
  -b, --local, --build     Construire et installer le paquet à partir des sources locales
  -r, --release            Installer la version officielle publiée sur GitHub Releases
  --no-wheezy              Ne pas installer l'image système Debian Wheezy
  --force-download         Supprimer les paquets de cache locaux et forcer le téléchargement
  -h, --help               Afficher cette aide et quitter

Moteur tarball (arguments passés tels quels, --help du moteur pour le détail) :
  $(basename "$0") --tarball --fetch-only [--choose|--no-choose]  Images et noyaux invités
  $(basename "$0") --tarball --binary --with-deps                 Appli sous un préfixe
  $(basename "$0") --tarball --help                              Aide complète du moteur

Si exécuté dans le dépôt git et qu'un binaire fraîchement compilé existe
(_build/default/bin/marionnet.exe), l'installation locale est automatiquement activée.
EOF
}

# Point d'entrée unique : --tarball route vers le moteur tarball, sans quoi
# c'est le moteur .deb ci-dessous. Les options .deb sont refusées avec
# --tarball (exclusion mutuelle) ; le moteur tarball garde sa grammaire gelée
# (banc marionnet-install.sh.bench, docs livrées, publication standalone).
TARBALL_MODE=false
for arg in "$@"; do
  [ "$arg" = "--tarball" ] && TARBALL_MODE=true
done
if [ "$TARBALL_MODE" = true ]; then
  TARBALL_ARGS=()
  for arg in "$@"; do
    [ "$arg" = "--tarball" ] && continue
    TARBALL_ARGS+=("$arg")
  done
  for arg in "${TARBALL_ARGS[@]}"; do
    case "$arg" in
      -b|--local|--build|-r|--release|--no-wheezy|--without-wheezy|--force-download|--clean|--re-download)
        echo "[-] $arg appartient au moteur .deb, incompatible avec --tarball." >&2
        echo "    Sans --tarball pour le .deb ; avec --tarball, options tarball uniquement." >&2
        exit 2
        ;;
    esac
  done
  ENGINE=""
  if command -v marionnet-install.sh >/dev/null 2>&1; then
    ENGINE="$(command -v marionnet-install.sh)"
  elif [ -f "$REPO_ROOT/bin/scripts/marionnet-install.sh" ]; then
    ENGINE="$REPO_ROOT/bin/scripts/marionnet-install.sh"
  else
    echo "[-] Moteur tarball introuvable (ni marionnet-install.sh installé, ni arbre git)." >&2
    echo "    Sur une machine déjà installée : marionnet-get-images pour les images." >&2
    exit 2
  fi
  exec "$ENGINE" "${TARBALL_ARGS[@]}"
fi

for arg in "$@"; do
  case "$arg" in
    -b|--local|--build)
      BUILD_LOCAL=true
      ;;
    -r|--release)
      RELEASE_MODE=true
      ;;
    --no-wheezy|--without-wheezy)
      INSTALL_WHEEZY=false
      ;;
    --force-download|--clean|--re-download)
      FORCE_DOWNLOAD=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "[-] Option inconnue : $arg" >&2
      usage >&2
      exit 1
      ;;
    *)
      VERSION="$arg"
      ;;
  esac
done

# Détection automatique : si on est dans le dépôt git et qu'un binaire local existe
if [ "$RELEASE_MODE" = false ] && [ "$BUILD_LOCAL" = false ]; then
  if [ -f "$REPO_ROOT/dune-project" ] && [ -f "$REPO_ROOT/_build/default/bin/marionnet.exe" ]; then
    echo "--> Binaire compilé local détecté (_build/default/bin/marionnet.exe)."
    echo "    Mode local activé automatiquement."
    BUILD_LOCAL=true
  fi
fi

# Si le mode local est demandé explicitement mais que le binaire n'est pas encore compilé
if [ "$BUILD_LOCAL" = true ] && [ ! -f "$REPO_ROOT/_build/default/bin/marionnet.exe" ]; then
  echo "--> Binaire non trouvé. Compilation avec dune..."
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    su - "$SUDO_USER" -c "cd '$REPO_ROOT' && if command -v opam >/dev/null 2>&1; then opam exec -- dune build; else dune build; fi"
  elif command -v opam >/dev/null 2>&1; then
    (cd "$REPO_ROOT" && opam exec -- dune build)
  else
    (cd "$REPO_ROOT" && dune build)
  fi
fi

GITHUB_REPO="${MARIONNET_REPO:-lucas-martinati-pro/marionnet}"
BASE_RELEASE_TAG="v1.0.456"
cd "$SCRIPT_DIR"

# Détection de l'outil de téléchargement HTTP (curl ou wget)
if command -v curl >/dev/null 2>&1; then
  HTTP_CLIENT="curl"
elif command -v wget >/dev/null 2>&1; then
  HTTP_CLIENT="wget"
else
  echo "--> Ni curl ni wget trouvé. Installation de curl via apt..."
  sudo apt-get update && sudo apt-get install -y curl
  HTTP_CLIENT="curl"
fi

download_file() {
  local target_file="$1"
  local url="$2"
  local desc="$3"
  local quiet="${4:-false}"

  [ "$quiet" = false ] && echo "--> Téléchargement : $desc..."
  [ "$quiet" = false ] && echo "    Source : $url"

  local ok=false
  if [ "$HTTP_CLIENT" = "curl" ]; then
    if curl -fL --progress-bar "$url" -o "$target_file"; then ok=true; fi
  else
    if wget -q --show-progress -O "$target_file" "$url"; then ok=true; fi
  fi

  if [ "$ok" = false ] || [ ! -s "$target_file" ]; then
    rm -f "$target_file"
    if [ "$quiet" = false ]; then
      echo "[-] ERREUR : Le téléchargement de $(basename "$target_file") a échoué." >&2
    fi
    return 1
  fi
  [ "$quiet" = false ] && echo "    Téléchargement terminé avec succès."
  return 0
}

SUMS_FILE=""
cleanup() {
  if [ -n "$SUMS_FILE" ] && [ -f "$SUMS_FILE" ] && [[ "$SUMS_FILE" == /tmp/* ]]; then
    rm -f "$SUMS_FILE"
  fi
}
trap cleanup EXIT

# Fonction de vérification stricte (fail-hard) des sommes de contrôle SHA256
verify_checksum() {
  local file="$1" name line
  name="$(basename "$file")"
  if [ ! -f "$file" ]; then
    return 1
  fi
  [ -s "${SUMS_FILE:-}" ] || { echo "[-] SHA256SUMS indisponible pour vérifier $name" >&2; return 2; }
  line="$(awk -v n="$name" '$2==n {print; exit}' "$SUMS_FILE")"
  [ -n "$line" ] || { echo "[-] $name absent de SHA256SUMS" >&2; return 2; }
  ( cd "$(dirname "$file")" && printf '%s\n' "$line" | sha256sum -c --status - ) \
    || { echo "[-] Checksum SHA256 invalide pour $name" >&2; rm -f "$file"; return 1; }
  echo "    ✓ Checksum SHA256 validé : $name"
  return 0
}

# Résolution de la version et des noms de paquets
if [ "$BUILD_LOCAL" = true ]; then
  # Mode local : dérive depuis le dépôt
  if [ -z "${VERSION:-}" ] && [ -f "$REPO_ROOT/bin/meta.ml.maker.sh" ]; then
    VERSION="$(bash "$REPO_ROOT/bin/meta.ml.maker.sh" --print-version 2>/dev/null || true)"
  fi
  if [ -z "${VERSION:-}" ] && [ -f "$REPO_ROOT/META" ]; then
    VERSION="$(grep -Po '(?<=version=")[^"]*' "$REPO_ROOT/META" 2>/dev/null || true)"
  fi
  if [[ ! $VERSION =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    echo "[-] ERREUR : Version locale invalide ou indéterminée ($VERSION)." >&2
    exit 1
  fi
  DEB_NAME="marionnet-all-in-one_${VERSION}_amd64.deb"
  WHEEZY_DEB="marionnet-fs-debian-wheezy_08367_all.deb"
  DOWNLOAD_BASE_URL=""
else
  # Mode téléchargement depuis GitHub Releases
  if [ -n "${VERSION:-}" ]; then
    # Version demandée explicitement en argument
    DOWNLOAD_BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}"
    SUMS_FILE="$(mktemp /tmp/marionnet-sums.XXXXXX)"
    echo "--> Récupération des sommes de contrôle de la version v${VERSION}..."
    download_file "$SUMS_FILE" "${DOWNLOAD_BASE_URL}/SHA256SUMS" "Sommes de contrôle SHA256 (v$VERSION)" || {
      echo "[-] ERREUR : Impossible de récupérer SHA256SUMS pour la release v${VERSION}." >&2
      exit 1
    }
  else
    # Version automatique : télécharger SHA256SUMS de releases/latest sans appel API
    DOWNLOAD_BASE_URL="https://github.com/${GITHUB_REPO}/releases/latest/download"
    SUMS_FILE="$(mktemp /tmp/marionnet-sums.XXXXXX)"
    echo "--> Récupération des sommes de contrôle de la dernière release..."
    if ! download_file "$SUMS_FILE" "${DOWNLOAD_BASE_URL}/SHA256SUMS" "Sommes de contrôle SHA256 (latest)" true; then
      # Fallback : résolution du tag de redirection HTTP
      if [ "$HTTP_CLIENT" = "curl" ]; then
        url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)"
      else
        url="$(wget --spider -S "https://github.com/${GITHUB_REPO}/releases/latest" 2>&1 | awk '/Location:/{print $2}' | tail -n 1 || true)"
      fi
      TAG="${url##*/}"
      VERSION="${TAG#v}"
      if [[ ! $VERSION =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
        echo "[-] ERREUR : Impossible de déterminer la version de la dernière release." >&2
        exit 1
      fi
      DOWNLOAD_BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}"
      download_file "$SUMS_FILE" "${DOWNLOAD_BASE_URL}/SHA256SUMS" "Sommes de contrôle SHA256 ($TAG)" || {
        echo "[-] ERREUR : SHA256SUMS introuvable pour $TAG." >&2
        exit 1
      }
    fi
  fi

  # Déduction du nom exact du paquet All-in-One depuis SHA256SUMS
  DEB_NAME="$(awk '$2 ~ /^marionnet-all-in-one_.*\.deb$/ {print $2; exit}' "$SUMS_FILE")"
  if [ -z "$DEB_NAME" ]; then
    echo "[-] ERREUR : Aucun paquet marionnet-all-in-one répertorié dans SHA256SUMS." >&2
    exit 1
  fi
  VERSION="$(echo "$DEB_NAME" | sed -nE 's/^marionnet-all-in-one_(.*)_amd64\.deb$/\1/p')"
  # Wheezy épinglé : les releases courantes ne le listent plus, on tombe donc
  # sur le nom invariant par défaut -- voulu, le téléchargement se fait
  # depuis la release de base (voir § 2 ci-dessous).
  WHEEZY_DEB="$(awk '$2 ~ /^marionnet-fs-debian-wheezy_.*\.deb$/ {print $2; exit}' "$SUMS_FILE")"
  if [ -z "$WHEEZY_DEB" ]; then
    WHEEZY_DEB="marionnet-fs-debian-wheezy_08367_all.deb"
  fi
fi

TARGET_USER="${SUDO_USER:-$USER}"

echo "=========================================================="
echo "    Installation de Marionnet $VERSION (All-in-One)"
echo "=========================================================="
echo "Mode : $([ "$BUILD_LOCAL" = true ] && echo "Local (sources du dépôt)" || echo "Release GitHub")"
echo "Utilisateur cible pour les droits réseau : $TARGET_USER"

# 0. Vérification de l'architecture du système hôte
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
  echo "[-] ERREUR : Architecture hôte '$ARCH' non supportée." >&2
  echo "    Marionnet et ses noyaux User-Mode Linux nécessitent une architecture x86_64 (amd64)." >&2
  echo "    Si vous êtes sur Mac Apple Silicon (M1/M2/M3/M4), veuillez exécuter une VM Linux x86_64 émulée." >&2
  exit 1
fi

# 1. Vérification / Construction / Téléchargement du paquet All-in-One
if [ "$FORCE_DOWNLOAD" = true ]; then
  echo "--> Option --force-download : purge des paquets locaux..."
  rm -f "$DEB_NAME" "$WHEEZY_DEB" "$SCRIPT_DIR/SHA256SUMS"
fi

if [ "$BUILD_LOCAL" = true ]; then
  echo "--> Génération du paquet All-in-One avec les sources locales..."
  "$SCRIPT_DIR/build-all-in-one.sh" "$VERSION"
  SUMS_FILE="$SCRIPT_DIR/SHA256SUMS"
elif [ -f "$DEB_NAME" ]; then
  # Détection et purge d'un paquet antérieur au Depends libc6:i386 : sans lui,
  # le noyau linux-6.12.95-i386 embarqué est inexécutable (/lib/ld-linux.so.2
  # manquant) et la première machine meurt avec "died unexpectedly".
  if ! dpkg-deb -f "$DEB_NAME" Depends 2>/dev/null | grep -q "libc6:i386"; then
    echo "--> Ancien paquet local détecté (Depends sans libc6:i386)."
    echo "    Purge automatique et reconstruction/retéléchargement..."
    rm -f "$DEB_NAME"
  # Détection et purge automatique d'un ancien build incompatible lié à GLIBC >= 2.42
  elif dpkg-deb --fsys-tarfile "$DEB_NAME" 2>/dev/null | tar -x -O ./usr/bin/marionnet.native 2>/dev/null | grep -qa "GLIBC_2.4[2-9]"; then
    echo "--> Ancien paquet local détecté (compilé avec GLIBC >= 2.42 incompatible)."
    echo "    Purge automatique et téléchargement du paquet officiel compatible..."
    rm -f "$DEB_NAME"
  elif ! verify_checksum "$DEB_NAME" 2>/dev/null; then
    echo "--> Paquet local $DEB_NAME invalide ou corrompu. Retéléchargement..."
    rm -f "$DEB_NAME"
  fi
fi

if [ ! -f "$DEB_NAME" ]; then
  download_file "$DEB_NAME" "${DOWNLOAD_BASE_URL}/${DEB_NAME}" "Paquet All-in-One Marionnet (v$VERSION)" || {
    echo "[-] ERREUR : Téléchargement de $DEB_NAME impossible depuis $DOWNLOAD_BASE_URL." >&2
    exit 1
  }
  verify_checksum "$DEB_NAME" || {
    echo "[-] ERREUR CRITIQUE : L'intégrité de $DEB_NAME a échoué. Installation annulée." >&2
    exit 1
  }
  if dpkg-deb --fsys-tarfile "$DEB_NAME" 2>/dev/null | tar -x -O ./usr/bin/marionnet.native 2>/dev/null | grep -qa "GLIBC_2.4[2-9]"; then
    echo "[-] ERREUR : Le paquet téléchargé contient un binaire incompatible (GLIBC >= 2.42)." >&2
    echo "    Veuillez patienter pendant la republication du paquet officiel ou utiliser './install.sh 1.0.456'." >&2
    rm -f "$DEB_NAME"
    exit 1
  fi
else
  echo "--> Paquet '$DEB_NAME' vérifié et prêt."
fi

# 2. Wheezy : artefact INVARIANT (08367) épinglé sur la release de base
# (BASE_RELEASE_TAG) et jamais dupliqué dans les releases courantes. On le
# télécharge donc TOUJOURS de là. Vérification en deux temps : la ligne du
# SHA256SUMS courant quand elle existe (releases <= 1.0.459 le listent), sinon
# l'empreinte épinglée -- le fichier ne change jamais, son nom EST sa version.
# Provenance de l'empreinte : SHA256SUMS publiés des releases 1.0.457/458/459
# (fichier identique de 423478976 octets sur les 4 releases) + téléchargement
# local vérifié par `sha256sum -c`.
WHEEZY_PINNED_SHA256="7972fa3cc8a6c9389c29a8173c574781ac14d07783fbaa4b954c98a71d8653fd"
WHEEZY_INSTALLED=false
if [ -f /usr/share/marionnet/filesystems/machine-debian-wheezy-08367 ] || dpkg -s marionnet-fs-debian-wheezy >/dev/null 2>&1; then
  echo "--> Système Debian Wheezy déjà installé dans /usr/share/marionnet/filesystems."
  WHEEZY_INSTALLED=true
fi

verify_wheezy_checksum() {
  local file="$1" name line
  name="$(basename "$file")"
  if [ -s "${SUMS_FILE:-}" ]; then
    line="$(awk -v n="$name" '$2==n {print; exit}' "$SUMS_FILE")"
  fi
  if [ -z "${line:-}" ]; then
    line="$WHEEZY_PINNED_SHA256  $name"
  fi
  ( cd "$(dirname "$file")" && printf '%s\n' "$line" | sha256sum -c --status - ) \
    || { echo "[-] Checksum SHA256 invalide pour $name" >&2; rm -f "$file"; return 1; }
  echo "    ✓ Checksum SHA256 validé : $name"
  return 0
}

if [ "$INSTALL_WHEEZY" = true ] && [ "$WHEEZY_INSTALLED" = false ]; then
  if [ -f "$WHEEZY_DEB" ]; then
    if ! verify_wheezy_checksum "$WHEEZY_DEB" 2>/dev/null; then
      echo "--> Paquet Wheezy local $WHEEZY_DEB corrompu. Retéléchargement..."
      rm -f "$WHEEZY_DEB"
    fi
  fi
  if [ ! -f "$WHEEZY_DEB" ]; then
    echo "--> Téléchargement depuis la release épinglée ($BASE_RELEASE_TAG)..."
    download_file "$WHEEZY_DEB" "https://github.com/${GITHUB_REPO}/releases/download/${BASE_RELEASE_TAG}/${WHEEZY_DEB}" "Distribution Debian Wheezy (Apache2, navigateurs web, etc.)" true || {
      echo "[-] Avertissement : Impossible de récupérer $WHEEZY_DEB. L'installation continuera sans Debian Wheezy." >&2
      INSTALL_WHEEZY=false
    }
    if [ -f "$WHEEZY_DEB" ]; then
      verify_wheezy_checksum "$WHEEZY_DEB" || {
        echo "[-] Avertissement : Le fichier $WHEEZY_DEB ne correspond pas à l'empreinte de contrôle. Ignoré." >&2
        rm -f "$WHEEZY_DEB"
        INSTALL_WHEEZY=false
      }
    fi
  else
    echo "--> Paquet '$WHEEZY_DEB' vérifié et prêt localement."
  fi
fi

# 3. Réparation préventive d'éventuels paquets interrompus ou mal configurés
echo "--> [1/6] Vérification de l'état du gestionnaire de paquets (dpkg)..."
sudo dpkg --configure -a 2>/dev/null || true

# 4. Activation de l'architecture i386 (pour les noyaux UML 32-bit et rétrocompatibilité)
echo "--> [2/6] Activation de l'architecture i386..."
sudo dpkg --add-architecture i386 || true

# 5. Nettoyage des éventuels anciens binaires résiduels
echo "--> [3/6] Nettoyage des anciens binaires résiduels..."
if [ -f /usr/local/bin/marionnet ] || [ -f /usr/local/bin/marionnet.native ]; then
  sudo rm -f /usr/local/bin/marionnet*
fi
# Doublons `.sh` morts depuis 2b2fc87 (les 4 familles vivent sous leur nom nu :
# check, cleanup, ctl, verify) : les installations d'avant les posaient aussi
# sous `*.sh` dans /usr/bin, ce qui doublait la complétion. Hors paquets dpkg
# récents, donc retrait explicite et sans danger.
sudo rm -f /usr/bin/marionnet-check.sh /usr/bin/marionnet-cleanup.sh \
            /usr/bin/marionnet-ctl.sh /usr/bin/marionnet-verify.sh 2>/dev/null || true

# 6. Installation des paquets et de toutes les dépendances
echo "--> [4/6] Installation des paquets et des dépendances système..."
DEBS_TO_INSTALL=( "./$DEB_NAME" )
if [ "$INSTALL_WHEEZY" = true ] && [ -f "$WHEEZY_DEB" ]; then
  echo "    Inclusion de la distribution Debian Wheezy..."
  DEBS_TO_INSTALL+=( "./$WHEEZY_DEB" )
fi

sudo apt update
# Runtime 32-bit du noyau linux-6.12.95-i386 (interpréteur /lib/ld-linux.so.2,
# fourni uniquement par libc6:i386) : installé explicitement car les paquets
# All-in-One publiés avant le Depends libc6:i386 ne le tirent pas, et sans lui
# la première machine meurt avec "died unexpectedly". --clean seul ne suffit pas.
echo "--> [5/6] Installation du runtime 32-bit (libc6:i386)..."
if ! sudo apt install -y libc6:i386; then
  echo "[-] ERREUR : impossible d'installer libc6:i386." >&2
  echo "    Le noyau 32-bit linux-6.12.95-i386 restera inexécutable." >&2
  exit 1
fi
sudo apt install -o Dpkg::Options::="--force-overwrite" --reinstall -y "${DEBS_TO_INSTALL[@]}"

# 7. Configuration des droits réseau (sudoers)
echo "--> [6/6] Configuration des droits réseau (sudoers)..."
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
marionnet -v || true
# Vérification fail-hard : le noyau 32-bit doit être exécutable ICI et
# MAINTENANT, pas à la première machine. On mesure l'interpréteur et ldd,
# jamais un libellé de paquet.
I386_KERNEL=""
if command -v marionnet.native >/dev/null 2>&1; then
  KERNELS_DIR="$(marionnet.native --paths 2>/dev/null | sed -n 's|^kernels[[:space:]]*:[[:space:]]*||p' | head -n 1)"
  [ -n "${KERNELS_DIR:-}" ] && I386_KERNEL="$KERNELS_DIR/linux-6.12.95-i386"
fi
[ -n "$I386_KERNEL" ] || I386_KERNEL="/usr/share/marionnet/kernels/linux-6.12.95-i386"
if [ ! -x "$I386_KERNEL" ]; then
  echo "[-] ERREUR : noyau 32-bit absent ou non exécutable : $I386_KERNEL" >&2
  exit 1
fi
if [ ! -e /lib/ld-linux.so.2 ]; then
  echo "[-] ERREUR : /lib/ld-linux.so.2 manquant (libc6:i386 non installé)." >&2
  echo "    Le noyau $I386_KERNEL ne peut pas s'exécuter." >&2
  exit 1
fi
if ldd "$I386_KERNEL" 2>/dev/null | grep -q "not found"; then
  echo "[-] ERREUR : dépendances 32-bit manquantes pour $I386_KERNEL :" >&2
  ldd "$I386_KERNEL" 2>&1 | grep "not found" >&2 || true
  exit 1
fi
echo "    ✓ Noyau 32-bit exécutable : $I386_KERNEL (ldd OK, /lib/ld-linux.so.2 présent)"
echo "=========================================================="
echo "Marionnet $VERSION est installé et prêt à l'emploi !"
echo "Lancez simplement 'marionnet' dans votre terminal ou via vos applications."
echo "=========================================================="
