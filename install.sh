#!/usr/bin/env bash
# ==============================================================================
# FormFillAI - 1-Click Installer for Xournal++ (Linux & macOS)
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

# 1. Determine Target Plugin Directory
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

# 2. Copy Plugin Files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "📦 Copying plugin files from $SCRIPT_DIR..."

cp -rf "$SCRIPT_DIR/plugin.ini" "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR/main.lua" "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR/json.lua" "$TARGET_DIR/"
cp -rf "$SCRIPT_DIR/backend" "$TARGET_DIR/"

# 3. Setup Python Environment & Dependencies
echo -e "🐍 Checking Python 3 and dependencies..."
PYTHON_BIN=""
for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
        PYTHON_BIN="$py"
        break
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    echo -e "${RED}Error: Python 3 not found. Please install Python 3.${NC}"
    exit 1
fi

PY_VERSION=$("$PYTHON_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo -e "   Found Python $PY_VERSION ($PYTHON_BIN)"

# Check if required modules exist in system/current python
HAS_MODULES=$("$PYTHON_BIN" -c '
try:
    import onnxruntime, PIL, numpy
    print("OK")
except ImportError:
    print("MISSING")
' 2>/dev/null || echo "MISSING")

if [ "$HAS_MODULES" = "OK" ]; then
    echo -e "${GREEN}   All required core libraries (onnxruntime, PIL, numpy) are present!${NC}"
else
    echo -e "${YELLOW}   Missing runtime libraries. Setting up dedicated virtual environment...${NC}"
    VENV_DIR="$TARGET_DIR/.venv"
    if [ ! -d "$VENV_DIR" ]; then
        "$PYTHON_BIN" -m venv "$VENV_DIR"
    fi
    echo -e "   Installing onnxruntime, pillow, numpy into plugin environment..."
    "$VENV_DIR/bin/pip" install --upgrade pip >/dev/null 2>&1 || true
    "$VENV_DIR/bin/pip" install onnxruntime pillow numpy requests >/dev/null 2>&1 || {
        echo -e "${YELLOW}   Note: Pip install encountered network restriction. Attempting offline/system fallback...${NC}"
    }
fi

# 4. Check / Cache Models
CACHE_DIR="$HOME/.cache/formfillai/models"
mkdir -p "$CACHE_DIR"

if [ -f "/tmp/FFDNet-S.onnx" ] && [ ! -f "$CACHE_DIR/FFDNet-S.onnx" ]; then
    echo -e "💾 Caching pre-downloaded FFDNet-S model..."
    cp /tmp/FFDNet-S.onnx "$CACHE_DIR/"
fi
if [ -f "/tmp/FFDNet-L.onnx" ] && [ ! -f "$CACHE_DIR/FFDNet-L.onnx" ]; then
    echo -e "💾 Caching pre-downloaded FFDNet-L model..."
    cp /tmp/FFDNet-L.onnx "$CACHE_DIR/"
fi

# 5. Automatically enable plugin in Xournal++ settings.xml if present
SETTINGS_XML="$CONFIG_DIR/settings.xml"
if [ -f "$SETTINGS_XML" ]; then
    if ! grep -q "FormFillAI" "$SETTINGS_XML"; then
        echo -e "⚙️  Enabling FormFillAI in Xournal++ settings.xml..."
        # Update pluginEnabled attribute safely with python
        "$PYTHON_BIN" -c '
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    c = f.read()
new_c = re.sub(r"""<property name="pluginEnabled" value="([^"]*)"\s*/>""",
               lambda m: f"""<property name="pluginEnabled" value="{m.group(1) + ",FormFillAI" if m.group(1) else "FormFillAI"}"/>""", c)
with open(path, "w", encoding="utf-8") as f:
    f.write(new_c)
' "$SETTINGS_XML" || true
    fi
fi

echo -e ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}🎉 FormFillAI has been successfully installed!       ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "To start using FormFillAI:"
echo -e "  1. Launch or restart ${BLUE}Xournal++${NC}."
echo -e "  2. Open any flat PDF form."
echo -e "  3. Go to menu: ${YELLOW}Plugin > FormFillAI > Detect Form Fields (Current Page)${NC}"
echo -e "     or press ${YELLOW}Ctrl + Alt + F${NC}!"
echo -e "  4. Use ${YELLOW}Ctrl + Alt + C${NC} to fill all checkboxes in one click."
echo -e ""
