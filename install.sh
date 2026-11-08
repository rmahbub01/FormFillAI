#!/usr/bin/env bash
# ==============================================================================
# FormFillAI - 1-Click Installer for Xournal++ (Linux & macOS)
# Multiplatform: Native RPM/DEB/Arch, Flatpak, Snap, macOS Homebrew/DMG
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}     FormFillAI - Xournal++ Plugin Installer         ${NC}"
echo -e "${BLUE}=====================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run silent CLI installer if python3 is available
PYTHON_BIN=""
for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
        PYTHON_BIN="$py"
        break
    fi
done

if [ -n "$PYTHON_BIN" ] && [ -f "$SCRIPT_DIR/install.py" ]; then
    "$PYTHON_BIN" "$SCRIPT_DIR/install.py" --install "$@"
    exit 0
fi

# Fallback bash installation if python is unavailable
OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" = "Darwin" ]; then
    TARGET_DIR="$HOME/Library/Application Support/xournalpp/plugins/FormFillAI"
    CONFIG_DIR="$HOME/Library/Application Support/xournalpp"
else
    TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/xournalpp/plugins/FormFillAI"
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/xournalpp"
fi

echo -e "📂 Target Directory: ${YELLOW}$TARGET_DIR${NC}"
mkdir -p "$TARGET_DIR"

echo -e "📦 Copying plugin files from $SCRIPT_DIR..."
cp -rf "$SCRIPT_DIR/plugin.ini" "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR/main.lua" "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR/json.lua" "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR/config.json" "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR/backend" "$TARGET_DIR/"

# Also copy to Flatpak if present
FLATPAK_DIR="$HOME/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI"
if [ -d "$HOME/.var/app/com.github.xournalpp.xournalpp" ]; then
    echo -e "📦 Copying to Flatpak sandbox: $FLATPAK_DIR..."
    mkdir -p "$FLATPAK_DIR"
    cp -rf "$SCRIPT_DIR/plugin.ini" "$FLATPAK_DIR/"
    cp -rf "$SCRIPT_DIR/main.lua" "$FLATPAK_DIR/"
    cp -rf "$SCRIPT_DIR/json.lua" "$FLATPAK_DIR/"
    cp -rf "$SCRIPT_DIR/config.json" "$FLATPAK_DIR/"
    cp -rf "$SCRIPT_DIR/backend" "$FLATPAK_DIR/"
fi

echo -e "${GREEN}🎉 FormFillAI has been successfully installed in Xournal++!${NC}"
