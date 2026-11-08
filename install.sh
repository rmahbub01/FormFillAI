#!/bin/sh
# ==============================================================================
# FormFillAI - 1-Click Silent Installer for Xournal++ (Linux & macOS)
# Multiplatform: Native RPM/DEB/Arch, Flatpak, Snap, macOS Homebrew/DMG
# Repo: https://github.com/rmahbub01/FormFillAI
#
# Usage (One-Liner):
#   curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/install.sh | bash
# Or with sudo:
#   sudo curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/install.sh | sh
# ==============================================================================

set -e

# Terminal colors (if supported)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    BLUE=''
    YELLOW=''
    NC=''
fi

printf "%b=====================================================%b\n" "$BLUE" "$NC"
printf "%b     FormFillAI - Xournal++ Plugin Installer         %b\n" "$GREEN" "$NC"
printf "%b=====================================================%b\n" "$BLUE" "$NC"

# 1. Resolve real target user and home directory (even under sudo)
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
    [ -z "$REAL_HOME" ] && REAL_HOME="$(eval echo ~"$SUDO_USER")"
else
    REAL_USER="$(id -un 2>/dev/null || whoami)"
    REAL_HOME="${HOME:-/root}"
fi

printf "👤 Target user: %b%s%b (Home: %s)\n" "$YELLOW" "$REAL_USER" "$NC" "$REAL_HOME"

# 2. Locate or download repository source files
CLEANUP_TMP=""
REPO_DIR=""

# Check if script is executed from inside an existing local directory
if [ -f "./plugin.ini" ] && [ -f "./main.lua" ]; then
    REPO_DIR="$(pwd)"
elif [ -n "${BASH_SOURCE[0]}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/plugin.ini" ]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# If piped (e.g. curl ... | sh), download the repo archive from GitHub
if [ -z "$REPO_DIR" ] || [ ! -f "$REPO_DIR/plugin.ini" ]; then
    TMP_DIR="$(mktemp -d /tmp/formfillai_install_XXXXXX)"
    CLEANUP_TMP="$TMP_DIR"
    printf "📥 Fetching latest FormFillAI from GitHub...\n"

    DOWNLOAD_SUCCESS=0
    if command -v curl >/dev/null 2>&1; then
        if curl -LsSf "https://github.com/rmahbub01/FormFillAI/archive/refs/heads/master.tar.gz" 2>/dev/null | tar -xz -C "$TMP_DIR" 2>/dev/null; then
            DOWNLOAD_SUCCESS=1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -qO- "https://github.com/rmahbub01/FormFillAI/archive/refs/heads/master.tar.gz" 2>/dev/null | tar -xz -C "$TMP_DIR" 2>/dev/null; then
            DOWNLOAD_SUCCESS=1
        fi
    fi

    if [ "$DOWNLOAD_SUCCESS" -eq 1 ] && [ -d "$TMP_DIR/FormFillAI-master" ]; then
        REPO_DIR="$TMP_DIR/FormFillAI-master"
    elif command -v git >/dev/null 2>&1; then
        printf "📥 Cloning via git...\n"
        git clone --depth 1 "https://github.com/rmahbub01/FormFillAI.git" "$TMP_DIR/FormFillAI-master" >/dev/null 2>&1
        REPO_DIR="$TMP_DIR/FormFillAI-master"
    else
        printf "❌ Error: Could not download FormFillAI. Please install curl, wget, or git.\n"
        [ -n "$CLEANUP_TMP" ] && rm -rf "$CLEANUP_TMP"
        exit 1
    fi
fi

# 3. Prefer running Python installer if python3 is available
PYTHON_BIN=""
for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
        PYTHON_BIN="$py"
        break
    fi
done

if [ -n "$PYTHON_BIN" ] && [ -f "$REPO_DIR/install.py" ]; then
    # Run silent python installer with environment preserved
    SUDO_USER="$REAL_USER" "$PYTHON_BIN" "$REPO_DIR/install.py" --install "$@"

    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/xournalpp/plugins/FormFillAI" 2>/dev/null || true
        chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.cache/formfillai" 2>/dev/null || true
    fi
    if [ -n "$CLEANUP_TMP" ] && [ -d "$CLEANUP_TMP" ]; then
        rm -rf "$CLEANUP_TMP"
    fi
    exit 0
else
    # 4. Fallback Pure Shell Installer (when python is missing)
    OS_TYPE="$(uname -s)"
    if [ "$OS_TYPE" = "Darwin" ]; then
        TARGET_DIR="$REAL_HOME/Library/Application Support/xournalpp/plugins/FormFillAI"
        CONFIG_DIR="$REAL_HOME/Library/Application Support/xournalpp"
    else
        TARGET_DIR="${XDG_CONFIG_HOME:-$REAL_HOME/.config}/xournalpp/plugins/FormFillAI"
        CONFIG_DIR="${XDG_CONFIG_HOME:-$REAL_HOME/.config}/xournalpp"
    fi

    printf "📂 Target Directory: %b%s%b\n" "$YELLOW" "$TARGET_DIR" "$NC"
    mkdir -p "$TARGET_DIR"

    printf "📦 Copying plugin files...\n"
    cp -rf "$REPO_DIR/plugin.ini" "$TARGET_DIR/"
    cp -rf "$REPO_DIR/main.lua" "$TARGET_DIR/"
    cp -rf "$REPO_DIR/json.lua" "$TARGET_DIR/"
    cp -rf "$REPO_DIR/config.json" "$TARGET_DIR/"
    cp -rf "$REPO_DIR/backend" "$TARGET_DIR/"

    # Also install to Flatpak sandbox if directory exists
    FLATPAK_DIR="$REAL_HOME/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI"
    if [ -d "$REAL_HOME/.var/app/com.github.xournalpp.xournalpp" ]; then
        printf "📦 Copying to Flatpak sandbox: %s...\n" "$FLATPAK_DIR"
        mkdir -p "$FLATPAK_DIR"
        cp -rf "$REPO_DIR/plugin.ini" "$FLATPAK_DIR/"
        cp -rf "$REPO_DIR/main.lua" "$FLATPAK_DIR/"
        cp -rf "$REPO_DIR/json.lua" "$FLATPAK_DIR/"
        cp -rf "$REPO_DIR/config.json" "$FLATPAK_DIR/"
        cp -rf "$REPO_DIR/backend" "$FLATPAK_DIR/"
    fi

    # Also install to Snap sandbox if directory exists
    SNAP_DIR="$REAL_HOME/snap/xournalpp/current/.config/xournalpp/plugins/FormFillAI"
    if [ -d "$REAL_HOME/snap/xournalpp" ]; then
        printf "📦 Copying to Snap sandbox: %s...\n" "$SNAP_DIR"
        mkdir -p "$SNAP_DIR"
        cp -rf "$REPO_DIR/plugin.ini" "$SNAP_DIR/"
        cp -rf "$REPO_DIR/main.lua" "$SNAP_DIR/"
        cp -rf "$REPO_DIR/json.lua" "$SNAP_DIR/"
        cp -rf "$REPO_DIR/config.json" "$SNAP_DIR/"
        cp -rf "$REPO_DIR/backend" "$SNAP_DIR/"
    fi

    # Enable in settings.xml
    SETTINGS_XML="$CONFIG_DIR/settings.xml"
    if [ -f "$SETTINGS_XML" ]; then
        if ! grep -q "pluginEnabled.*name=[\"']FormFillAI[\"']" "$SETTINGS_XML"; then
            sed -i '/<\/settings>/i \  <pluginEnabled name="FormFillAI" enabled="true"\/>' "$SETTINGS_XML" 2>/dev/null || true
        fi
    fi
fi

# 5. Fix ownership if run under sudo
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/xournalpp/plugins/FormFillAI" 2>/dev/null || true
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.cache/formfillai" 2>/dev/null || true
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI" 2>/dev/null || true
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/snap/xournalpp/current/.config/xournalpp/plugins/FormFillAI" 2>/dev/null || true
fi

# 6. Cleanup temporary download directory
if [ -n "$CLEANUP_TMP" ] && [ -d "$CLEANUP_TMP" ]; then
    rm -rf "$CLEANUP_TMP"
fi

printf "%b🎉 1-Click Installation Complete! FormFillAI is ready in Xournal++.%b\n" "$GREEN" "$NC"
