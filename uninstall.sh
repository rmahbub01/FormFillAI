#!/bin/sh
# ==============================================================================
# FormFillAI - 1-Click Complete Uninstaller for Xournal++ (Linux & macOS)
# Multiplatform: Native RPM/DEB/Arch, Flatpak, Snap, macOS Homebrew/DMG
# Repo: https://github.com/rmahbub01/FormFillAI
#
# Usage (One-Liner):
#   curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/uninstall.sh | bash
# Or with sudo:
#   sudo curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/uninstall.sh | sh
# ==============================================================================

set -e

# Terminal colors (if supported)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    BLUE=''
    YELLOW=''
    NC=''
fi

printf "%b=====================================================%b\n" "$BLUE" "$NC"
printf "%b    FormFillAI - 1-Click Complete Uninstaller        %b\n" "$RED" "$NC"
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

printf "👤 Removing for user: %b%s%b (Home: %s)\n" "$YELLOW" "$REAL_USER" "$NC" "$REAL_HOME"

# 2. Try running local python uninstaller if available
PYTHON_BIN=""
for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
        PYTHON_BIN="$py"
        break
    fi
done

INSTALL_PY=""
if [ -f "./install.py" ]; then
    INSTALL_PY="./install.py"
elif [ -n "${BASH_SOURCE[0]}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/install.py" ]; then
    INSTALL_PY="$(dirname "${BASH_SOURCE[0]}")/install.py"
fi

if [ -n "$PYTHON_BIN" ] && [ -n "$INSTALL_PY" ] && [ -f "$INSTALL_PY" ]; then
    SUDO_USER="$REAL_USER" "$PYTHON_BIN" "$INSTALL_PY" --uninstall
    exit 0
else
    # 3. Direct Shell Uninstaller (works 100% standalone, perfect for curl | sh)
    printf "🗑️ Removing plugin directories...\n"
    rm -rf "${XDG_CONFIG_HOME:-$REAL_HOME/.config}/xournalpp/plugins/FormFillAI"
    rm -rf "$REAL_HOME/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/FormFillAI"
    rm -rf "$REAL_HOME/snap/xournalpp/current/.config/xournalpp/plugins/FormFillAI"
    rm -rf "$REAL_HOME/Library/Application Support/xournalpp/plugins/FormFillAI"

    printf "🧹 Cleaning cache and temporary files...\n"
    rm -rf "$REAL_HOME/.cache/formfillai"
    rm -f /tmp/formfill_*

    printf "⚙️ Cleaning xournalpp/settings.xml...\n"
    for s_xml in \
        "${XDG_CONFIG_HOME:-$REAL_HOME/.config}/xournalpp/settings.xml" \
        "$REAL_HOME/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/settings.xml" \
        "$REAL_HOME/snap/xournalpp/current/.config/xournalpp/settings.xml" \
        "$REAL_HOME/Library/Application Support/xournalpp/settings.xml"; do
        if [ -f "$s_xml" ]; then
            if [ -n "$PYTHON_BIN" ]; then
                "$PYTHON_BIN" -c "
import re, sys
p = sys.argv[1]
try:
    with open(p, 'r', encoding='utf-8') as f:
        c = f.read()
    c2 = re.sub(r'\s*<pluginEnabled\s+name=[\"\']FormFillAI[\"\'][^>]*/>', '', c)
    if c2 != c:
        with open(p, 'w', encoding='utf-8') as f:
            f.write(c2)
except Exception:
    pass
" "$s_xml" 2>/dev/null || true
            else
                sed -i '/pluginEnabled.*name=[\"'"'"']FormFillAI[\"'"'"']/d' "$s_xml" 2>/dev/null || true
            fi
        fi
    done
fi

printf "%b✨ 1-Click Uninstallation Complete! All traces of FormFillAI have been removed.%b\n" "$GREEN" "$NC"
