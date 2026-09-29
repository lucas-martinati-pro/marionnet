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

Options:
  -b, --local, --build     Construire et installer le paquet à partir des sources locales
  -r, --release            Installer la version officielle publiée sur GitHub Releases
  --no-wheezy              Ne pas installer l'image système Debian Wheezy
  --force-download         Supprimer les paquets de cache locaux et forcer le téléchargement
  -h, --help               Afficher cette aide et quitter

Si exécuté dans le dépôt git et qu'un binaire fraîchement compilé existe
(_build/default/bin/marionnet.exe), l'installation locale est automatiquement activée.
EOF
}

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

# Résolution dynamique de la version
resolve_version() {
  if [ -n "${VERSION:-}" ]; then
    return 0
  fi
  # 1. Via le script maker du dépôt si présent
  if [ -f "$REPO_ROOT/bin/meta.ml.maker.sh" ]; then
    local v
    v="$(bash "$REPO_ROOT/bin/meta.ml.maker.sh" --print-version 2>/dev/null || true)"
    if [ -n "$v" ] && [ "$v" != "1.0.x" ] && [ "$v" != "trunk" ]; then
      VERSION="$v"
      return 0
    fi
  fi
  # 2. Via META si présent
  if [ -f "$REPO_ROOT/META" ]; then
    local v
    v="$(grep -Po '(?<=version=")[^"]*' "$REPO_ROOT/META" 2>/dev/null || true)"
    if [ -n "$v" ] && [ "$v" != "1.0.x" ] && [ "$v" != "trunk" ]; then
      VERSION="$v"
      return 0
    fi
  fi
  # 3. Via la dernière release GitHub
  local latest_tag
  latest_tag="$(curl -sSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | grep -Po '(?<="tag_name":\s*")[^"]*' || true)"
  if [ -n "$latest_tag" ]; then
    VERSION="${latest_tag#v}"
    return 0
  fi
  # 4. Fallback
  VERSION="1.0.457"
}

resolve_version

DEB_NAME="marionnet-all-in-one_${VERSION}_amd64.deb"
WHEEZY_DEB="marionnet-fs-debian-wheezy_08367_all.deb"
BASE_RELEASE_TAG="v1.0.456"

cd "$SCRIPT_DIR"

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

# Fonction utilitaire de téléchargement avec curl ou wget
download_file() {
  local target_file="$1"
  local url="$2"
  local desc="$3"
  local fail_on_error="${4:-true}"

  echo "--> Téléchargement : $desc..."
  echo "    Source : $url"

  local dl_ok=false
  if command -v curl >/dev/null 2>&1; then
    if curl -fL --progress-bar "$url" -o "$target_file"; then
      dl_ok=true
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -q --show-progress -O "$target_file" "$url"; then
      dl_ok=true
    fi
  else
    echo "    curl ou wget non trouvé. Installation de curl via apt..."
    sudo apt update && sudo apt install -y curl
    if curl -fL --progress-bar "$url" -o "$target_file"; then
      dl_ok=true
    fi
  fi

  if [ "$dl_ok" = false ] || [ ! -s "$target_file" ]; then
    rm -f "$target_file"
    if [ "$fail_on_error" = true ]; then
      echo "[-] ERREUR : Le téléchargement de $target_file a échoué ou le fichier est vide." >&2
      return 1
    else
      return 1
    fi
  fi
  echo "    Téléchargement terminé avec succès."
  return 0
}

# Fonction de vérification des sommes de contrôle SHA256
verify_checksum() {
  local target_file="$1"
  local sha_file="$SCRIPT_DIR/SHA256SUMS"
  local base_name
  base_name="$(basename "$target_file")"

  if [ ! -f "$target_file" ]; then
    return 1
  fi

  # Télécharger SHA256SUMS depuis GitHub Releases si absent
  if [ ! -f "$sha_file" ]; then
    local sha_url="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/SHA256SUMS"
    download_file "$sha_file" "$sha_url" "Sommes de contrôle SHA256" false || true
  fi

  if [ -f "$sha_file" ]; then
    local expected_hash
    expected_hash="$(grep -E "[[:space:]]${base_name}\$" "$sha_file" | awk '{print $1}' || true)"
    if [ -n "$expected_hash" ]; then
      echo "--> Vérification de l'intégrité SHA256 ($base_name)..."
      local actual_hash
      actual_hash="$(sha256sum "$target_file" | awk '{print $1}')"
      if [ "$actual_hash" = "$expected_hash" ]; then
        echo "    ✓ Checksum SHA256 valide : $actual_hash"
        return 0
      else
        echo "[-] ERREUR : L'intégrité de $base_name a échoué (checksum SHA256 invalide) !" >&2
        echo "    Attendu : $expected_hash" >&2
        echo "    Obtenu  : $actual_hash" >&2
        rm -f "$target_file"
        return 1
      fi
    else
      echo "    [i] Note : $base_name non présent dans SHA256SUMS (vérification ignorée)."
    fi
  fi
  return 0
}

# 1. Vérification / Construction / Téléchargement du paquet All-in-One
if [ "$FORCE_DOWNLOAD" = true ]; then
  echo "--> Option --force-download : purge des paquets locaux..."
  rm -f "$DEB_NAME" "$WHEEZY_DEB" "$SCRIPT_DIR/SHA256SUMS"
fi

if [ "$BUILD_LOCAL" = true ]; then
  echo "--> Génération du paquet All-in-One avec les sources locales..."
  "$SCRIPT_DIR/build-all-in-one.sh" "$VERSION"
elif [ -f "$DEB_NAME" ]; then
  # Détection et purge automatique d'un ancien build incompatible lié à GLIBC 2.42
  if dpkg-deb --fsys-tarfile "$DEB_NAME" 2>/dev/null | tar -x -O ./usr/bin/marionnet.native 2>/dev/null | grep -qa "GLIBC_2.42"; then
    echo "--> Ancien paquet local détecté (compilé avec GLIBC 2.42 incompatible)."
    echo "    Purge automatique et téléchargement du paquet officiel compatible..."
    rm -f "$DEB_NAME"
  elif ! verify_checksum "$DEB_NAME"; then
    echo "--> Paquet local $DEB_NAME invalide ou corrompu. Retéléchargement..."
    rm -f "$DEB_NAME"
  fi
fi

if [ ! -f "$DEB_NAME" ]; then
  RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${DEB_NAME}"
  download_file "$DEB_NAME" "$RELEASE_URL" "Paquet All-in-One Marionnet (v$VERSION)" || {
    echo "    Vérifiez que la release v${VERSION} existe bien sur https://github.com/${GITHUB_REPO}/releases" >&2
    exit 1
  }
  verify_checksum "$DEB_NAME" || {
    echo "[-] ERREUR : Le paquet téléchargé est corrompu." >&2
    exit 1
  }
else
  echo "--> Paquet '$DEB_NAME' prêt."
fi

# 2. Vérification / Téléchargement de la distribution Debian Wheezy
WHEEZY_INSTALLED=false
if [ -f /usr/share/marionnet/filesystems/machine-debian-wheezy-08367 ] || dpkg -s marionnet-fs-debian-wheezy >/dev/null 2>&1; then
  echo "--> Système Debian Wheezy déjà installé dans /usr/share/marionnet/filesystems."
  WHEEZY_INSTALLED=true
fi

if [ "$INSTALL_WHEEZY" = true ] && [ "$WHEEZY_INSTALLED" = false ]; then
  if [ -f "$WHEEZY_DEB" ]; then
    if ! verify_checksum "$WHEEZY_DEB"; then
      echo "--> Paquet Wheezy local $WHEEZY_DEB corrompu. Retéléchargement..."
      rm -f "$WHEEZY_DEB"
    fi
  fi
  if [ ! -f "$WHEEZY_DEB" ]; then
    WHEEZY_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${WHEEZY_DEB}"
    if ! download_file "$WHEEZY_DEB" "$WHEEZY_URL" "Distribution Debian Wheezy (Apache2, navigateurs web, etc.)" false; then
      WHEEZY_FALLBACK="https://github.com/${GITHUB_REPO}/releases/download/${BASE_RELEASE_TAG}/${WHEEZY_DEB}"
      echo "--> Téléchargement depuis la release de base ($BASE_RELEASE_TAG)..."
      download_file "$WHEEZY_DEB" "$WHEEZY_FALLBACK" "Distribution Debian Wheezy (fallback)" false || {
        echo "[-] Avertissement : Impossible de récupérer $WHEEZY_DEB. L'installation continuera sans Debian Wheezy." >&2
        INSTALL_WHEEZY=false
      }
    fi
    if [ -f "$WHEEZY_DEB" ]; then
      verify_checksum "$WHEEZY_DEB" || {
        echo "[-] Avertissement : Le fichier $WHEEZY_DEB téléchargé est invalide. Ignoré." >&2
        rm -f "$WHEEZY_DEB"
        INSTALL_WHEEZY=false
      }
    fi
  else
    echo "--> Paquet '$WHEEZY_DEB' vérifié et prêt localement."
  fi
fi

# 3. Réparation préventive d'éventuels paquets interrompus ou mal configurés
echo "--> [1/5] Vérification de l'état du gestionnaire de paquets (dpkg)..."
sudo dpkg --configure -a 2>/dev/null || true

# 4. Activation de l'architecture i386 (pour les noyaux UML 32-bit et rétrocompatibilité)
echo "--> [2/5] Activation de l'architecture i386..."
sudo dpkg --add-architecture i386 || true

# 5. Nettoyage des éventuels anciens binaires résiduels
echo "--> [3/5] Nettoyage des anciens binaires résiduels..."
if [ -f /usr/local/bin/marionnet ] || [ -f /usr/local/bin/marionnet.native ]; then
  sudo rm -f /usr/local/bin/marionnet*
fi

# 6. Installation des paquets et de toutes les dépendances
echo "--> [4/5] Installation des paquets et des dépendances système..."
DEBS_TO_INSTALL=( "./$DEB_NAME" )
if [ "$INSTALL_WHEEZY" = true ] && [ -f "$WHEEZY_DEB" ]; then
  echo "    Inclusion de la distribution Debian Wheezy..."
  DEBS_TO_INSTALL+=( "./$WHEEZY_DEB" )
fi

sudo apt update
sudo apt install -o Dpkg::Options::="--force-overwrite" --reinstall -y "${DEBS_TO_INSTALL[@]}"

# 7. Configuration des droits réseau (sudoers)
echo "--> [5/5] Configuration des droits réseau (sudoers)..."
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
echo "=========================================================="
echo "Marionnet $VERSION est installé et prêt à l'emploi !"
echo "Lancez simplement 'marionnet' dans votre terminal ou via vos applications."
echo "=========================================================="
