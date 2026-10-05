#!/usr/bin/env bash
set -euo pipefail

# Configuration par défaut (surchargable via argument ou variables d'environnement)
VERSION="${MARIONNET_VERSION:-}"
INSTALL_WHEEZY=true
FORCE_DOWNLOAD=false
BUILD_LOCAL=false
RELEASE_MODE=false
VERBOSE=false

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
  --verbose                Afficher en direct tous les détails de compilation et d’APT
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
      -b|--local|--build|-r|--release|--no-wheezy|--without-wheezy|--force-download|--clean|--re-download|--verbose)
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
    --verbose)
      VERBOSE=true
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

# Présentation uniquement : les commandes gardent leurs arguments et leur statut.
# Aucune couleur dans un fichier/pipe, ni lorsque NO_COLOR est défini.
UI_BOLD="" UI_DIM="" UI_CYAN="" UI_GREEN="" UI_YELLOW="" UI_RED="" UI_RESET=""
if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR+x}" ]; then
  UI_BOLD=$'\033[1m' UI_DIM=$'\033[2m' UI_CYAN=$'\033[36m'
  UI_GREEN=$'\033[32m' UI_YELLOW=$'\033[33m' UI_RED=$'\033[31m' UI_RESET=$'\033[0m'
fi
INSTALL_STARTED=$SECONDS
INSTALL_LOG="$(mktemp "${TMPDIR:-/tmp}/marionnet-install.XXXXXX.log" 2>/dev/null || true)"
if [ -z "$INSTALL_LOG" ]; then
  # Un problème de journal ne doit jamais empêcher une installation.
  VERBOSE=true
fi
CURRENT_STEP="Préparation"
SUMS_FILE=""

ui_line() {
  local color="$1" message="$2"
  printf '%s%s%s\n' "$color" "$message" "$UI_RESET"
  if [ -n "$INSTALL_LOG" ]; then printf '%s\n' "$message" >> "$INSTALL_LOG" || true; fi
}
ui_info() { ui_line "$UI_DIM" "    $*"; }
ui_ok() { ui_line "$UI_GREEN" "    ✓ $*"; }
ui_warn() { ui_line "$UI_YELLOW" "    ! $*"; }
ui_error() { ui_line "$UI_RED" "    ✗ $*" >&2; }
ui_step() {
  CURRENT_STEP="$2"
  printf '\n'
  ui_line "$UI_BOLD$UI_CYAN" "  [$1/9] $2"
}

cleanup() {
  local status=$?
  if [ -n "$SUMS_FILE" ] && [ -f "$SUMS_FILE" ] && [[ "$SUMS_FILE" == /tmp/* ]]; then
    rm -f "$SUMS_FILE"
  fi
  if [ "$status" -ne 0 ]; then
    printf '\n' >&2
    ui_error "Installation interrompue pendant : $CURRENT_STEP (code $status)."
    if [ -n "$INSTALL_LOG" ]; then ui_error "Journal : $INSTALL_LOG"; fi
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Les lignes ordinaires vont au journal. Les avertissements restent visibles.
# Une sortie sans retour à la ligne est affichée après 200 ms : on conserve les
# barres de téléchargement ET les invites interactives (dpkg, debconf, etc.).
# Ne pas remplacer cette lecture par grep/une capture intégrale : une invite
# pourrait alors rester invisible pendant que la commande attend une réponse.
ui_command_output() {
  local line status partial=false
  local alerts="(^|[[:space:][:punct:]])([Ww][Aa][Rr][Nn][Ii][Nn][Gg]|[Ee][Rr][Rr][Oo][Rr]|[Ee][Rr][Rr][Ee][Uu][Rr]|[Aa][Vv][Ee][Rr][Tt][Ii][Ss][Ss][Ee][Mm][Ee][Nn][Tt]|[Aa][Tt][Tt][Ee][Nn][Tt][Ii][Oo][Nn]|[Nn][Oo][Tt][Ii][Cc][Ee])([[:space:][:punct:]]|$)|^E:|^W:|^debconf:"
  local prompts="\?|\[[YyOoNn]/|[Pp]assword|[Mm]ot de passe|[Cc]onfirm|[Pp]ress.*([Ee]nter|[Rr]eturn)|[Aa]ppuyez"
  while true; do
    line=""
    if IFS= read -r -t 0.2 line; then
      if [ -n "$INSTALL_LOG" ]; then printf '%s\n' "$line" >> "$INSTALL_LOG" || true; fi
      if [ "$VERBOSE" = true ] || [ "$partial" = true ]; then
        printf '%s\n' "$line"
      elif [[ "$line" =~ $prompts ]]; then
        printf '%s\n' "$line"
      elif [[ "$line" =~ $alerts ]]; then
        # Ce rappel générique d’APT apparaît à chaque invocation du CLI.
        if [[ "$line" != *"apt does not have a stable CLI interface"* ]]; then
          printf '    %s! %s%s\n' "$UI_YELLOW" "$line" "$UI_RESET"
        fi
      fi
      partial=false
    else
      status=$?
      if [ -n "$line" ]; then
        if [ -n "$INSTALL_LOG" ]; then printf '%s' "$line" >> "$INSTALL_LOG" || true; fi
        printf '%s' "$line"
        partial=true
      fi
      # read retourne >128 sur délai expiré, 1 sur fin de flux.
      if [ "$status" -le 128 ]; then break; fi
    fi
  done
  if [ "$partial" = true ]; then printf '\n'; fi
  return 0
}

# Appeler seulement des commandes externes ici, pas une fonction métier Bash :
# le contexte conditionnel d’un pipeline modifierait son comportement set -e.
run_task() {
  local title="$1" started=$SECONDS status first_line=1
  shift
  ui_info "$title…"
  if [ -n "$INSTALL_LOG" ]; then
    first_line=$(( $(wc -l < "$INSTALL_LOG") + 1 ))
    printf '\n$ ' >> "$INSTALL_LOG" || true
    printf '%q ' "$@" >> "$INSTALL_LOG" || true
    printf '\n' >> "$INSTALL_LOG" || true
  fi
  # La commande conserve stdin (et sudo son /dev/tty). PIPESTATUS[0] conserve
  # son code exact, y compris lorsque l’appelant ignore volontairement l’échec.
  if "$@" 2>&1 | ui_command_output; then
    status=0
  else
    status=${PIPESTATUS[0]}
  fi
  if [ "$status" -eq 0 ]; then
    ui_ok "$title ($((SECONDS - started)) s)"
  else
    ui_error "$title : échec (code $status)."
    if [ -n "$INSTALL_LOG" ] && [ "$VERBOSE" = false ]; then
      printf '\n    Dernières lignes de la commande :\n' >&2
      sed -n "${first_line},\$p" "$INSTALL_LOG" | tail -n 35 >&2
    fi
  fi
  return "$status"
}

printf '\n'
ui_line "$UI_BOLD$UI_CYAN" "  MARIONNET  /  Installation"
ui_line "$UI_DIM" "  ──────────────────────────────────────────────────"
if [ -n "$INSTALL_LOG" ]; then
  ui_info "Journal détaillé : $INSTALL_LOG"
else
  ui_warn "Journal indisponible ; affichage détaillé activé."
fi
ui_step 1 "Préparation"

# Détection automatique : si on est dans le dépôt git et qu'un binaire local existe
if [ "$RELEASE_MODE" = false ] && [ "$BUILD_LOCAL" = false ]; then
  if [ -f "$REPO_ROOT/dune-project" ] && [ -f "$REPO_ROOT/_build/default/bin/marionnet.exe" ]; then
    ui_info "Sources locales détectées · mode local activé"
    BUILD_LOCAL=true
  fi
fi

# Si le mode local est demandé mais que le binaire est absent ou périmé, on
# (re)construit : dune ne reconstruit que quand on le lui demande, et sans cela
# on empaquetterait en silence l'ancienne version (vécu : binaire 1.0.457
# installé sous une 1.0.459). La version attendue vient de la règle unique
# (meta.ml.maker.sh, repli META) ; la version du binaire de son `-v' headless.
LOCAL_BIN="$REPO_ROOT/_build/default/bin/marionnet.exe"
EXPECTED_VERSION=""
if [ -f "$REPO_ROOT/bin/meta.ml.maker.sh" ]; then
  EXPECTED_VERSION="$(bash "$REPO_ROOT/bin/meta.ml.maker.sh" --print-version 2>/dev/null || true)"
fi
if [ -z "$EXPECTED_VERSION" ] && [ -f "$REPO_ROOT/META" ]; then
  EXPECTED_VERSION="$(grep -Po '(?<=version=")[^"]*' "$REPO_ROOT/META" 2>/dev/null || true)"
fi
LOCAL_VER=""
if [ -f "$LOCAL_BIN" ]; then
  LOCAL_VER="$("$LOCAL_BIN" -v 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1 || true)"
fi
NEED_BUILD=false
if [ ! -f "$LOCAL_BIN" ]; then
  NEED_BUILD=true
elif [ -n "$EXPECTED_VERSION" ] && [ "$LOCAL_VER" != "$EXPECTED_VERSION" ]; then
  NEED_BUILD=true
fi
if [ "$BUILD_LOCAL" = true ] && [ "$NEED_BUILD" = true ]; then
  if [ -f "$LOCAL_BIN" ]; then
    ui_info "Binaire local à actualiser : $LOCAL_VER → $EXPECTED_VERSION"
  else
    ui_info "Première compilation du binaire local"
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    run_task "Compilation OCaml" su - "$SUDO_USER" -c "cd '$REPO_ROOT' && if command -v opam >/dev/null 2>&1; then opam exec -- dune build; else dune build; fi"
  elif command -v opam >/dev/null 2>&1; then
    (cd "$REPO_ROOT" && run_task "Compilation OCaml" opam exec -- dune build)
  else
    (cd "$REPO_ROOT" && run_task "Compilation OCaml" dune build)
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
  ui_info "Installation de l’outil de téléchargement curl"
  run_task "Actualisation des dépôts" sudo apt-get update && run_task "Installation de curl" sudo apt-get install -y curl
  HTTP_CLIENT="curl"
fi

download_file() {
  local target_file="$1"
  local url="$2"
  local desc="$3"
  local quiet="${4:-false}"

  if [ "$VERBOSE" = true ]; then ui_info "Source : $url"; fi

  local ok=false
  if [ "$HTTP_CLIENT" = "curl" ]; then
    # Reprise du partiel + réessais : une connexion coupée laisse sinon un
    # .deb tronqué (vécu : 2486272 o. reçus sur 2802624), détecté plus loin
    # seulement par la vérification d'intégrité.
    if run_task "Téléchargement · $desc" curl -fL --retry 5 --retry-all-errors --retry-delay 5 -C - --progress-bar "$url" -o "$target_file"; then ok=true; fi
  else
    if run_task "Téléchargement · $desc" wget -c --tries=5 -q --show-progress -O "$target_file" "$url"; then ok=true; fi
  fi

  if [ "$ok" = false ] || [ ! -s "$target_file" ]; then
    rm -f "$target_file"
    if [ "$quiet" = false ]; then
      ui_error "Le téléchargement de $(basename "$target_file") a échoué." >&2
    fi
    return 1
  fi
  return 0
}

# Fonction de vérification stricte (fail-hard) des sommes de contrôle SHA256
verify_checksum() {
  local file="$1" name line
  name="$(basename "$file")"
  if [ ! -f "$file" ]; then
    return 1
  fi
  [ -s "${SUMS_FILE:-}" ] || { ui_error "SHA256SUMS indisponible pour vérifier $name" >&2; return 2; }
  line="$(awk -v n="$name" '$2==n {print; exit}' "$SUMS_FILE")"
  [ -n "$line" ] || { ui_error "$name absent de SHA256SUMS" >&2; return 2; }
  ( cd "$(dirname "$file")" && printf '%s\n' "$line" | sha256sum -c --status - ) \
    || { ui_error "Checksum SHA256 invalide pour $name" >&2; rm -f "$file"; return 1; }
  ui_ok "SHA256 validé · $name"
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
    ui_error "Version locale invalide ou indéterminée ($VERSION)." >&2
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
    ui_info "Version demandée : $VERSION"
    download_file "$SUMS_FILE" "${DOWNLOAD_BASE_URL}/SHA256SUMS" "Sommes de contrôle SHA256 (v$VERSION)" || {
      ui_error "Impossible de récupérer SHA256SUMS pour la release v${VERSION}." >&2
      exit 1
    }
  else
    # Version automatique : télécharger SHA256SUMS de releases/latest sans appel API
    DOWNLOAD_BASE_URL="https://github.com/${GITHUB_REPO}/releases/latest/download"
    SUMS_FILE="$(mktemp /tmp/marionnet-sums.XXXXXX)"
    ui_info "Recherche de la dernière version publiée"
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
        ui_error "Impossible de déterminer la version de la dernière release." >&2
        exit 1
      fi
      DOWNLOAD_BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}"
      download_file "$SUMS_FILE" "${DOWNLOAD_BASE_URL}/SHA256SUMS" "Sommes de contrôle SHA256 ($TAG)" || {
        ui_error "SHA256SUMS introuvable pour $TAG." >&2
        exit 1
      }
    fi
  fi

  # Déduction du nom exact du paquet All-in-One depuis SHA256SUMS
  DEB_NAME="$(awk '$2 ~ /^marionnet-all-in-one_.*\.deb$/ {print $2; exit}' "$SUMS_FILE")"
  if [ -z "$DEB_NAME" ]; then
    ui_error "Aucun paquet marionnet-all-in-one répertorié dans SHA256SUMS." >&2
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

ui_info "Version : $VERSION · $([ "$BUILD_LOCAL" = true ] && echo "Sources locales" || echo "Release GitHub")"
ui_info "Utilisateur : $TARGET_USER"

# 0. Vérification de l'architecture du système hôte
ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
  ui_error "Architecture hôte '$ARCH' non supportée." >&2
  ui_info "Marionnet et ses noyaux User-Mode Linux nécessitent une architecture x86_64 (amd64)." >&2
  ui_info "Si vous êtes sur Mac Apple Silicon (M1/M2/M3/M4), veuillez exécuter une VM Linux x86_64 émulée." >&2
  exit 1
fi

# 1. Vérification / Construction / Téléchargement du paquet All-in-One
ui_step 2 "Paquet de l’application"
if [ "$FORCE_DOWNLOAD" = true ]; then
  ui_info "Option --force-download : purge des paquets locaux..."
  rm -f "$DEB_NAME" "$WHEEZY_DEB" "$SCRIPT_DIR/SHA256SUMS"
fi

if [ "$BUILD_LOCAL" = true ]; then
  ui_info "Compilation et assemblage · cette étape peut prendre plusieurs minutes"
  run_task "Construction du paquet local" "$SCRIPT_DIR/build-all-in-one.sh" "$VERSION"
  SUMS_FILE="$SCRIPT_DIR/SHA256SUMS"
elif [ -f "$DEB_NAME" ]; then
  # Détection et purge d'un paquet antérieur au Depends libc6:i386 : sans lui,
  # le noyau linux-6.12.95-i386 embarqué est inexécutable (/lib/ld-linux.so.2
  # manquant) et la première machine meurt avec "died unexpectedly".
  if ! dpkg-deb -f "$DEB_NAME" Depends 2>/dev/null | grep -q "libc6:i386"; then
    ui_info "Ancien paquet local détecté (Depends sans libc6:i386)."
    ui_info "Purge automatique et reconstruction/retéléchargement..."
    rm -f "$DEB_NAME"
  # Détection et purge automatique d'un ancien build incompatible lié à GLIBC >= 2.42
  elif dpkg-deb --fsys-tarfile "$DEB_NAME" 2>/dev/null | tar -x -O ./usr/bin/marionnet.native 2>/dev/null | grep -qa "GLIBC_2.4[2-9]"; then
    ui_info "Ancien paquet local détecté (compilé avec GLIBC >= 2.42 incompatible)."
    ui_info "Purge automatique et téléchargement du paquet officiel compatible..."
    rm -f "$DEB_NAME"
  elif ! verify_checksum "$DEB_NAME" 2>/dev/null; then
    ui_info "Paquet local $DEB_NAME invalide ou corrompu. Retéléchargement..."
    rm -f "$DEB_NAME"
  fi
fi

if [ ! -f "$DEB_NAME" ]; then
  download_file "$DEB_NAME" "${DOWNLOAD_BASE_URL}/${DEB_NAME}" "Paquet All-in-One Marionnet (v$VERSION)" || {
    ui_error "Téléchargement de $DEB_NAME impossible depuis $DOWNLOAD_BASE_URL." >&2
    exit 1
  }
  verify_checksum "$DEB_NAME" || {
    ui_error "ERREUR CRITIQUE : L'intégrité de $DEB_NAME a échoué. Installation annulée." >&2
    exit 1
  }
  if dpkg-deb --fsys-tarfile "$DEB_NAME" 2>/dev/null | tar -x -O ./usr/bin/marionnet.native 2>/dev/null | grep -qa "GLIBC_2.4[2-9]"; then
    ui_error "Le paquet téléchargé contient un binaire incompatible (GLIBC >= 2.42)." >&2
    ui_info "Veuillez patienter pendant la republication du paquet officiel ou utiliser './install.sh 1.0.456'." >&2
    rm -f "$DEB_NAME"
    exit 1
  fi
else
  ui_ok "Paquet prêt · $DEB_NAME"
fi

# 2. Wheezy : artefact INVARIANT (08367) épinglé sur la release de base
# (BASE_RELEASE_TAG) et jamais dupliqué dans les releases courantes. On le
# télécharge donc TOUJOURS de là. Vérification en deux temps : la ligne du
# SHA256SUMS courant quand elle existe (releases <= 1.0.459 le listent), sinon
# l'empreinte épinglée -- le fichier ne change jamais, son nom EST sa version.
# Provenance de l'empreinte : SHA256SUMS publiés des releases 1.0.457/458/459
# (fichier identique de 423478976 octets sur les 4 releases) + téléchargement
# local vérifié par `sha256sum -c`.
ui_step 3 "Images des machines virtuelles"
WHEEZY_PINNED_SHA256="7972fa3cc8a6c9389c29a8173c574781ac14d07783fbaa4b954c98a71d8653fd"
WHEEZY_INSTALLED=false
if [ -f /usr/share/marionnet/filesystems/machine-debian-wheezy-08367 ] || dpkg -s marionnet-fs-debian-wheezy >/dev/null 2>&1; then
  ui_info "Debian Wheezy déjà installé"
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
    || { ui_error "Checksum SHA256 invalide pour $name" >&2; rm -f "$file"; return 1; }
  ui_ok "SHA256 validé · $name"
  return 0
}

if [ "$INSTALL_WHEEZY" = true ] && [ "$WHEEZY_INSTALLED" = false ]; then
  if [ -f "$WHEEZY_DEB" ]; then
    if ! verify_wheezy_checksum "$WHEEZY_DEB" 2>/dev/null; then
      ui_info "Paquet Wheezy local $WHEEZY_DEB corrompu. Retéléchargement..."
      rm -f "$WHEEZY_DEB"
    fi
  fi
  if [ ! -f "$WHEEZY_DEB" ]; then
    ui_info "Debian Wheezy · version épinglée $BASE_RELEASE_TAG"
    download_file "$WHEEZY_DEB" "https://github.com/${GITHUB_REPO}/releases/download/${BASE_RELEASE_TAG}/${WHEEZY_DEB}" "Distribution Debian Wheezy (Apache2, navigateurs web, etc.)" true || {
      ui_warn "Impossible de récupérer $WHEEZY_DEB. L'installation continuera sans Debian Wheezy." >&2
      INSTALL_WHEEZY=false
    }
    if [ -f "$WHEEZY_DEB" ]; then
      verify_wheezy_checksum "$WHEEZY_DEB" || {
        ui_warn "Le fichier $WHEEZY_DEB ne correspond pas à l'empreinte de contrôle. Ignoré." >&2
        rm -f "$WHEEZY_DEB"
        INSTALL_WHEEZY=false
      }
    fi
  else
    ui_ok "Image prête · $WHEEZY_DEB"
  fi
fi

if [ "$INSTALL_WHEEZY" = false ]; then ui_info "Installation sans image Debian Wheezy"; fi

# 3. Réparation préventive d'éventuels paquets interrompus ou mal configurés
ui_step 4 "Préparation du système"
run_task "Vérification du gestionnaire de paquets" sudo dpkg --configure -a 2>/dev/null || true

# 4. Activation de l'architecture i386 (pour les noyaux UML 32-bit et rétrocompatibilité)
run_task "Activation de l’architecture i386" sudo dpkg --add-architecture i386 || true

# 5. Nettoyage des éventuels anciens binaires résiduels
ui_info "Nettoyage des anciens binaires résiduels"
if [ -f /usr/local/bin/marionnet ] || [ -f /usr/local/bin/marionnet.native ]; then
  sudo rm -f /usr/local/bin/marionnet*
fi
# Doublons `.sh` morts depuis 2b2fc87 (les 4 familles vivent sous leur nom nu :
# check, cleanup, ctl, verify) et fichiers jamais exécutés depuis un PATH
# (scripts déposés dans les invités + complétion, voir build-all-in-one.sh) :
# les installations d'avant les posaient dans /usr/bin, ce qui polluait la
# complétion. Retrait explicite et sans danger (rien ne les appelle par là).
sudo rm -f /usr/bin/marionnet-check.sh /usr/bin/marionnet-cleanup.sh \
            /usr/bin/marionnet-ctl.sh /usr/bin/marionnet-verify.sh \
            /usr/bin/marionnet-relay.00-journal.sh \
            /usr/bin/marionnet-relay.05-autologin.sh \
            /usr/bin/marionnet-relay.zz-journal.sh \
            /usr/bin/marionnet-report.sh /usr/bin/marionnet-watch.sh \
            /usr/bin/marionnet-terminal-record.sh \
            /usr/bin/can-directory-host-sparse-files.sh \
            /usr/bin/marionnet-completion.bash 2>/dev/null || true

# 6. Installation des paquets et de toutes les dépendances
ui_step 5 "Actualisation des dépôts"
DEBS_TO_INSTALL=( "./$DEB_NAME" )
if [ "$INSTALL_WHEEZY" = true ] && [ -f "$WHEEZY_DEB" ]; then
  ui_info "Image Debian Wheezy incluse"
  DEBS_TO_INSTALL+=( "./$WHEEZY_DEB" )
fi

run_task "Index des paquets APT" sudo apt update
# Runtime 32-bit du noyau linux-6.12.95-i386 (interpréteur /lib/ld-linux.so.2,
# fourni uniquement par libc6:i386) : installé explicitement car les paquets
# All-in-One publiés avant le Depends libc6:i386 ne le tirent pas, et sans lui
# la première machine meurt avec "died unexpectedly". --clean seul ne suffit pas.
ui_step 6 "Dépendances système"
if ! run_task "Runtime des noyaux 32 bits · libc6:i386" sudo apt install -y libc6:i386; then
  ui_error "impossible d'installer libc6:i386." >&2
  ui_info "Le noyau 32-bit linux-6.12.95-i386 restera inexécutable." >&2
  exit 1
fi
ui_step 7 "Installation de Marionnet"
run_task "Application, noyaux et images" sudo apt install -o Dpkg::Options::="--force-overwrite" --reinstall -y "${DEBS_TO_INSTALL[@]}"

# Un -v réussi ne charge aucun widget et ne détecte pas une ancienne interface.
# En mode local, le fichier installé doit correspondre aux sources empaquetées.
# Signaler les préfixes conservés par dpkg plutôt que modifier une configuration
# personnalisée ou annoncer une application prête alors qu'elle ne démarre pas.
if [ "$BUILD_LOCAL" = true ]; then
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    INSTALLED_PATHS="$(su -s /bin/bash - "$SUDO_USER" -c '/usr/bin/marionnet --paths')"
  else
    INSTALLED_PATHS="$(/usr/bin/marionnet --paths)"
  fi
  GUI_DIR="$(printf '%s\n' "$INSTALLED_PATHS" | sed -n 's|^gui[[:space:]]*:[[:space:]]*||p' | head -n 1)"
  if [ -z "$GUI_DIR" ] || ! cmp -s "$REPO_ROOT/bin/gui/gui_glade3.xml" "$GUI_DIR/gui_glade3.xml"; then
    ui_error "l'interface chargée ne correspond pas au binaire local installé." >&2
    ui_info "Interface configurée : ${GUI_DIR:-introuvable}/gui_glade3.xml" >&2
    ui_info "Interface du paquet : /usr/share/marionnet/gui/gui_glade3.xml" >&2
    ui_info "Vérifiez MARIONNET_PREFIX dans /etc/marionnet/marionnet.conf," >&2
    ui_info "~/.marionnet/marionnet.conf et l'environnement ; conservez vos chemins" >&2
    ui_info "d'images et de noyaux dans MARIONNET_FILESYSTEMS_PATH et MARIONNET_KERNELS_PATH." >&2
    exit 1
  fi
  ui_ok "Interface installée conforme aux sources locales"
fi

# 7. Configuration des droits réseau (sudoers)
ui_step 8 "Configuration réseau"
if ! run_task "Droits réseau · $TARGET_USER" sudo marionnet-sudoers.sh install "$TARGET_USER" 2>/dev/null; then
  # Fallback compatible avec sudo-rs (Ubuntu 24.10+) et sudo classique
  ui_info "Application de la règle sudoers compatible"
  cat << EOF | sudo tee /etc/sudoers.d/marionnet > /dev/null
# Règle réseau Marionnet pour $TARGET_USER
$TARGET_USER ALL=(root) NOPASSWD: /usr/sbin/ip, /usr/bin/marionnet-tap.sh, /usr/bin/marionnet-tun-device.sh
EOF
  sudo chmod 0440 /etc/sudoers.d/marionnet
  ui_ok "Règle réseau compatible appliquée"
fi

ui_step 9 "Vérification de l’installation"
run_task "Version du binaire installé" marionnet -v || true
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
  ui_error "noyau 32-bit absent ou non exécutable : $I386_KERNEL" >&2
  exit 1
fi
if [ ! -e /lib/ld-linux.so.2 ]; then
  ui_error "/lib/ld-linux.so.2 manquant (libc6:i386 non installé)." >&2
  ui_info "Le noyau $I386_KERNEL ne peut pas s'exécuter." >&2
  exit 1
fi
if ldd "$I386_KERNEL" 2>/dev/null | grep -q "not found"; then
  ui_error "dépendances 32-bit manquantes pour $I386_KERNEL :" >&2
  ldd "$I386_KERNEL" 2>&1 | grep "not found" >&2 || true
  exit 1
fi
ui_ok "Noyau 32 bits exécutable · bibliothèques vérifiées"
printf '\n'
ui_line "$UI_BOLD$UI_GREEN" "  ✓ Marionnet $VERSION est prêt ($((SECONDS - INSTALL_STARTED)) s)"
ui_info "Lancer l’application : marionnet"
if [ -n "$INSTALL_LOG" ]; then ui_info "Journal : $INSTALL_LOG"; fi
printf '\n'
