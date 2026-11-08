#!/usr/bin/env bash
# ==============================================================================
# FormFillAI - 1-Click Complete Uninstaller for Xournal++ (Linux & macOS)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================${NC}"
echo -e "${RED}    FormFillAI - 1-Click Complete Uninstaller        ${NC}"
echo -e "${BLUE}=====================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try running python uninstaller if python is available
PYTHON_BIN=""
for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
        PYTHON_BIN="$py"
        break
    fi
done

if [ -n "$PYTHON_BIN" ] && [ -f "$SCRIPT_DIR/install.py" ]; then
    "$PYTHON_BIN" "$SCRIPT_DIR/install.py" --uninstall
    exit 0
fi

# Fallback bash uninstallation if python is unavailable
echo -e "Removing plugin folders..."
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/xournalpp/plugins/FormFillAI"
rm -rf "$HOME/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI"
rm -rf "$HOME/snap/xournalpp/current/.config/xournalpp/plugins/FormFillAI"
rm -rf "$HOME/Library/Application Support/xournalpp/plugins/FormFillAI"

echo -e "Cleaning user cache..."
rm -rf "$HOME/.cache/formfillai"
rm -f /tmp/formfill_*

echo -e "${GREEN}✨ Complete uninstallation finished!${NC}"
