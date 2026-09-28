#!/bin/bash

# This file is part of Marionnet, a virtual network laboratory
# Copyright (C) 2026  Lucas Martinati
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Marionnet auto-updater:
#   --check    : check for updates against GitHub Releases (exit 0: available, 1: up-to-date, 2: error)
#   --cli      : download and install update interactively in the terminal
#   --gui      : spawn terminal emulator to perform update and wait for keypress
#   --force    : force download and reinstallation even if already at latest version

set -uo pipefail

GITHUB_REPO="${MARIONNET_REPO:-lucas-martinati-pro/marionnet}"
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
CURL_TIMEOUT=8

MODE="cli"
FORCE=false
OVERRIDE_CURRENT=""

function usage {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -c, --check            Check if a new release is available (no changes made)
                         Exit codes: 0 = update available, 1 = up-to-date, 2 = error
  -u, --cli, --update    Update Marionnet in current terminal (default)
  -g, --gui              Launch update inside a terminal window (for GUI invocation)
  -f, --force            Force downloading and reinstalling the latest release
      --current <VER>    Explicitly specify the current version for comparison
  -h, --help             Display this help message and exit
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--check)
      MODE="check"
      shift
      ;;
    -u|--cli|--update)
      MODE="cli"
      shift
      ;;
    -g|--gui)
      MODE="gui"
      shift
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    --current)
      if [ -n "${2:-}" ]; then
        OVERRIDE_CURRENT="$2"
        shift 2
      else
        echo "[-] Error: --current requires a version argument" >&2
        exit 2
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[-] Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Detect current version
detect_current_version() {
  if [ -n "$OVERRIDE_CURRENT" ]; then
    echo "$OVERRIDE_CURRENT"
    return
  fi

  local ver=""
  if command -v marionnet >/dev/null 2>&1; then
    ver=$(marionnet -v 2>/dev/null | awk '{print $NF}' || true)
  fi
  if [ -z "$ver" ] && command -v marionnet.native >/dev/null 2>&1; then
    ver=$(marionnet.native -v 2>/dev/null | awk '{print $NF}' || true)
  fi
  if [ -z "$ver" ]; then
    # Look in repository META if running from source tree
    local script_dir
    script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    local meta_path="$script_dir/../../META"
    if [ -f "$meta_path" ]; then
      ver=$(grep -Po '(?<=version=")[^"]*' "$meta_path" 2>/dev/null || true)
    fi
  fi

  if [ -n "$ver" ]; then
    # Keep only version number if revno is appended (e.g., "1.0.456 revno 42")
    echo "$ver" | awk '{print $1}'
  else
    echo "0.0.0"
  fi
}

compare_versions_gt() {
  local ver_latest="$1"
  local ver_current="$2"

  # Strip leading 'v'
  ver_latest="${ver_latest#v}"
  ver_current="${ver_current#v}"

  if [ "$ver_latest" = "$ver_current" ]; then
    return 1
  fi

  if command -v dpkg >/dev/null 2>&1; then
    if dpkg --compare-versions "$ver_latest" gt "$ver_current" 2>/dev/null; then
      return 0
    else
      return 1
    fi
  fi

  # Fallback to sort -V
  local lowest
  lowest=$(printf '%s\n%s\n' "$ver_current" "$ver_latest" | sort -V | head -n1)
  if [ "$lowest" = "$ver_current" ] && [ "$ver_current" != "$ver_latest" ]; then
    return 0
  fi
  return 1
}

fetch_latest_release() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "[-] Error: curl is required to fetch update information." >&2
    return 2
  fi

  local json
  json=$(curl -fsSL --connect-timeout "$CURL_TIMEOUT" -m 15 "$API_URL" 2>/dev/null) || {
    echo "[-] Network error: unable to contact GitHub releases API ($API_URL)." >&2
    return 2
  }

  if [ -z "$json" ]; then
    echo "[-] Empty response from GitHub releases API." >&2
    return 2
  fi

  echo "$json"
}

# GUI mode handler: spawn terminal emulator
if [ "$MODE" = "gui" ]; then
  THIS_SCRIPT="$(readlink -f "$0")"
  CMD_ARGS="--cli"
  if [ "$FORCE" = true ]; then
    CMD_ARGS="$CMD_ARGS --force"
  fi
  if [ -n "$OVERRIDE_CURRENT" ]; then
    CMD_ARGS="$CMD_ARGS --current $OVERRIDE_CURRENT"
  fi

  INNER_SCRIPT="\"$THIS_SCRIPT\" $CMD_ARGS ; echo '' ; read -p 'Appuyez sur [Entrée] pour fermer cette fenêtre...' _dummy"

  if command -v x-terminal-emulator >/dev/null 2>&1; then
    exec x-terminal-emulator -T "Mise à jour Marionnet" -e bash -c "$INNER_SCRIPT"
  elif command -v xterm >/dev/null 2>&1; then
    exec xterm -T "Mise à jour Marionnet" -geometry 85x24 -e bash -c "$INNER_SCRIPT"
  elif command -v gnome-terminal >/dev/null 2>&1; then
    exec gnome-terminal --title="Mise à jour Marionnet" -- bash -c "$INNER_SCRIPT"
  elif command -v xfce4-terminal >/dev/null 2>&1; then
    exec xfce4-terminal --title="Mise à jour Marionnet" -e "bash -c '$INNER_SCRIPT'"
  elif command -v konsole >/dev/null 2>&1; then
    exec konsole -p tabtitle="Mise à jour Marionnet" -e bash -c "$INNER_SCRIPT"
  else
    echo "[-] Warning: No graphical terminal emulator found. Running in current process." >&2
    MODE="cli"
  fi
fi

# Fetch and parse release details
CURRENT_VER=$(detect_current_version)
RELEASE_INFO=$(fetch_latest_release) || exit 2

TAG_NAME=""
HTML_URL=""
DEB_URL=""

if command -v jq >/dev/null 2>&1; then
  TAG_NAME=$(echo "$RELEASE_INFO" | jq -r '.tag_name // empty')
  HTML_URL=$(echo "$RELEASE_INFO" | jq -r '.html_url // empty')
  DEB_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[] | select(.name | test("marionnet-all-in-one.*amd64\\.deb$")) | .browser_download_url' 2>/dev/null | head -n1 || true)
  if [ -z "$DEB_URL" ]; then
    DEB_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[] | select(.name | test("marionnet.*amd64\\.deb$")) | .browser_download_url' 2>/dev/null | head -n1 || true)
  fi
fi

# Fallback parsing with grep if jq not present or failed
if [ -z "$TAG_NAME" ]; then
  TAG_NAME=$(echo "$RELEASE_INFO" | grep -Po '(?<="tag_name": ")[^"]*' | head -n1 || true)
fi
if [ -z "$HTML_URL" ]; then
  HTML_URL=$(echo "$RELEASE_INFO" | grep -Po '(?<="html_url": ")[^"]*' | head -n1 || true)
fi
if [ -z "$DEB_URL" ]; then
  DEB_URL=$(echo "$RELEASE_INFO" | grep -Po '(?<="browser_download_url": ")[^"]*marionnet-all-in-one[^"]*amd64\.deb' | head -n1 || true)
fi

LATEST_VER="${TAG_NAME#v}"

if [ -z "$LATEST_VER" ]; then
  echo "[-] Error: unable to parse latest version tag from GitHub release." >&2
  exit 2
fi

# 1. Mode: Check
if [ "$MODE" = "check" ]; then
  if compare_versions_gt "$LATEST_VER" "$CURRENT_VER"; then
    echo "UPDATE_AVAILABLE $LATEST_VER $CURRENT_VER $HTML_URL"
    exit 0
  else
    echo "UP_TO_DATE $CURRENT_VER"
    exit 1
  fi
fi

# 2. Mode: CLI Update
echo "=========================================================="
echo "         Gestionnaire de mise à jour Marionnet"
echo "=========================================================="
echo "Version actuelle : $CURRENT_VER"
echo "Dernière version : $LATEST_VER ($TAG_NAME)"

UPDATE_NEEDED=false
if compare_versions_gt "$LATEST_VER" "$CURRENT_VER"; then
  UPDATE_NEEDED=true
fi

if [ "$UPDATE_NEEDED" = false ] && [ "$FORCE" = false ]; then
  echo "----------------------------------------------------------"
  echo "[+] Marionnet est déjà à jour (version $CURRENT_VER)."
  echo "    Pour forcer la réinstallation, relancez avec --force."
  echo "=========================================================="
  exit 0
fi

if [ "$FORCE" = true ] && [ "$UPDATE_NEEDED" = false ]; then
  echo "--> Option --force activée : réinstallation de la version $LATEST_VER..."
else
  echo "--> Nouvelle version disponible : $LATEST_VER !"
fi

if [ -z "$DEB_URL" ]; then
  DEB_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG_NAME}/marionnet-all-in-one_${LATEST_VER}_amd64.deb"
fi

TEMP_DEB=$(mktemp /tmp/marionnet-update.XXXXXX.deb)
cleanup() {
  rm -f "$TEMP_DEB"
}
trap cleanup EXIT

echo "--> Téléchargement du paquet All-in-One..."
echo "    URL : $DEB_URL"
curl -fL --progress-bar "$DEB_URL" -o "$TEMP_DEB" || {
  echo "[-] Erreur : le téléchargement du paquet Debian a échoué." >&2
  exit 1
}

# Verify file size (> 1MB)
FILE_SIZE=$(wc -c < "$TEMP_DEB" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1000000 ]; then
  echo "[-] Erreur : le fichier téléchargé semble corrompu ou incomplet ($FILE_SIZE octets)." >&2
  exit 1
fi

echo "--> Installation du paquet Debian..."
sudo apt update || true
sudo apt install -o Dpkg::Options::="--force-overwrite" --reinstall -y "$TEMP_DEB" || {
  echo "[-] Erreur : l'installation du paquet via apt a échoué." >&2
  exit 1
}

TARGET_USER="${SUDO_USER:-$USER}"
echo "--> Actualisation des droits réseau (sudoers) pour $TARGET_USER..."
if command -v marionnet-sudoers.sh >/dev/null 2>&1; then
  sudo marionnet-sudoers.sh install "$TARGET_USER" 2>/dev/null || true
fi

echo "=========================================================="
echo "[+] Marionnet a été mis à jour avec succès vers la version $LATEST_VER !"
echo "=========================================================="
echo "Vous pouvez relancer Marionnet pour profiter des nouveautés."
echo "=========================================================="
exit 0
