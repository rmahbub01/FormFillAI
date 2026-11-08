# 📝 FormFillAI: AI-Powered Flat PDF Form Field Detection for Xournal++

[![GitHub Repository](https://img.shields.io/badge/GitHub-rmahbub01%2FFormFillAI-blue.svg?logo=github)](https://github.com/rmahbub01/FormFillAI)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Xournal++ Plugin](https://img.shields.io/badge/Xournal%2B%2B-Plugin%20v1.0-green.svg)](https://xournalpp.github.io/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Flatpak%20%7C%20Snap%20%7C%20macOS%20%7C%20Windows-blue)](https://github.com/rmahbub01/FormFillAI)

**FormFillAI** is an intelligent, high-performance Xournal++ plugin that automatically detects flat (non-interactive, scanned, or government) PDF form fields using lightweight deep vision models (**FFDNet-S** and **FFDNet-L**) and overlays fillable text inputs and vector checkboxes with a single click or keyboard shortcut.

Native support for **Bangla / Bengali fonts (Nikosh, Kalpurush, SolaimanLipi, etc.)** and standard English typography ensures professional, naturally filled documents without any visual artifacts.

---

## ⚡ Quick Start: 1-Liner Installation & Uninstallation

### 🚀 1-Liner Install (Linux & macOS)

Install FormFillAI silently in one command (automatically detects native package, Flatpak, or Snap, downloads the AI model, and activates the plugin in Xournal++):

```bash
curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/install.sh | bash
```

*Or with `sudo` (installs cleanly into your user account and fixes permissions automatically):*

```bash
sudo curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/install.sh | sh
```

---

### 🗑️ 1-Liner Complete Uninstall (Linux & macOS)

Completely purge FormFillAI from all Xournal++ installations, remove cached model weights, and clean `settings.xml`:

```bash
curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/uninstall.sh | bash
```

*Or with `sudo`:*

```bash
sudo curl -LsSf https://raw.githubusercontent.com/rmahbub01/FormFillAI/master/uninstall.sh | sh
```

---

## ✨ Key Features

### 1. 🔤 Exact-Fit Overlay Text Boxes (Bounded & Pure Natural Look)
- **Zero Artifacts**: Fields are generated with clean text bounds without drawing dashed borders or outlines on the PDF, leaving the final exported document looking naturally typed.
- **Pure Black Ink**: Text is pre-configured with Pure Black (`#000000`) ink to match standard official print and government documents.
- **Dedicated Layer**: Overlays reside on a dedicated **`FormFillAI`** layer, keeping your personal handwritten notes and drawings clean and isolated.
- **Instant Inline Typing**: Activating detection automatically switches Xournal++ to the Text Tool (`Tool_text`). Simply click into any box to begin typing immediately.

### 2. 🇧🇩 First-Class Bangla & System Font Support
- **Bangla Standard**: Defaults to **Nikosh** (Bangladesh Government Standard) and prioritizes **Kalpurush**, **SolaimanLipi**, **Noto Sans Bengali**, and **Siyam Rupali**.
- **440+ System Fonts**: Built-in searchable browser dynamically discovers all fonts installed on your machine (Linux, macOS, and Windows) with real-time keyword filtering.
- **Auto-Fit Sizing**: Font size automatically scales to ~72% of the detected single-line box height for optimal typographic harmony, or switch to a custom fixed point size.

### 3. ☑️ Instant Checkbox & Shape Placement
- **Drop Anywhere**: Select `Add Checkbox Here` (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>X</kbd>) to insert your preferred shape:
  - **Checkmark (`✓`)**: Crisp, official vector tick.
  - **Cross (`✗`)**: Corner-to-corner cross mark.
  - **Solid Square (`■`)**: Filled block for shaded questionnaire boxes.
  - **Bullet Dot (`●`)**: Clean circular dot for radio choices.
  - **Empty Box (`☐`)**: Crisp rectangular border.
- **Immediate Resize & Move Handles**: Placed shapes immediately activate selection handles so you can resize and drag them directly to your desired position.
- **Pure Black Ink**: All checkboxes and shapes are drawn with Pure Black (`0x000000`) ink.

### 4. 🎛️ Clean, Minimal Notifications & Interface
- **Uncluttered Feedback**: Replaces noisy modals with refined, single-sentence alerts (e.g. `FormFillAI: 24 form fields ready to fill.`).
- **Always-Visible Action Buttons**: The Settings dialog is auto-centered and optimized (`640x480`), with **`💾 Save Preferences`**, **`⬇️ Check/Download Models`**, and **`Cancel`** permanently docked at the bottom without any manual window resizing.

---

## 🖥️ Streamlined 4-Tool Menu (`Plugin > FormFillAI`)

| Action | Shortcut | Description |
|---|---|---|
| **Detect Current Page** | <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd> | Scans the active page and creates bounded fillable text overlays matching exact field coordinates. |
| **Detect Full PDF** | — | High-speed batch inference across all pages in memory (~2.8s) with zero freezing. |
| **Add Checkbox Here** | <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>X</kbd> | Opens shape picker (`✓`, `✗`, `■`, `●`, `☐`) and drops the shape with live resize/move handles. |
| **Settings and Preferences** | <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | Configure fonts (Bangla / English), font sizing modes, AI models, and detection sensitivity. |

---

## 🧠 AI Models: FFDNet-S & FFDNet-L

FormFillAI uses the open-source **FFDNet** (Form Field Detection Network) vision models optimized for document forms:

| Model | Parameters | Weights Size | Optimized Engine | Best For |
|---|---|---|---|---|
| **FFDNet-S** *(Default)* | ~6 Million | ~37 MB | ONNX Runtime / CPU | Ultra-fast inference (< 0.8s on laptop CPUs), lightweight |
| **FFDNet-L** | ~25 Million | ~100 MB | ONNX Runtime / CUDA / CPU | Maximum recall on dense, low-contrast, or degraded scans |

The installer automatically caches the default model (`FFDNet-S.onnx`) into `~/.cache/formfillai/models/` during setup, ensuring zero inference delay when opening Xournal++.

---

## 📦 Multiplatform Installation Methods

FormFillAI supports all packaging variants and operating systems:

### 1. Cloned Repository Installation (Linux & macOS)
```bash
git clone https://github.com/rmahbub01/FormFillAI.git
cd FormFillAI
./install.sh
```
*To completely uninstall:*
```bash
./uninstall.sh
```

### 2. Windows Installation (EXE & Portable)
- **Install**: Double-click `install.bat` or run `python install.py`
- **Uninstall**: Double-click `uninstall.bat` or run `python install.py --uninstall`

### 3. Optional Graphical Manager (All Platforms)
Launch the graphical installer / uninstaller window anytime:
```bash
python3 install.py --gui
```

### 4. Supported Environments
- **Linux Native**: DEB (Ubuntu/Debian/Mint), RPM (Fedora/RHEL), Arch Linux, Void, openSUSE (`~/.config/xournalpp/plugins/`).
- **Linux Flatpak Sandbox**: Automatic detection and installation into `~/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/`.
- **Linux Snap Sandbox**: Automatic detection and installation into `~/snap/xournalpp/current/.config/xournalpp/plugins/`.
- **macOS**: Native and Homebrew Xournal++ (`~/Library/Application Support/xournalpp/plugins/`).
- **Windows**: Standard `%LOCALAPPDATA%\xournalpp\plugins\` and Roaming `%APPDATA%\xournalpp\plugins\`.

---

## 🧪 Verification & Unit Tests

Run the automated test suite from the repository:

```bash
python3 -m unittest discover tests
```

Tests verify:
- Configuration loading, persistence, and schema migrations
- FFDNet-S and FFDNet-L model path resolution and caching
- Typographic point-to-pixel coordinate transformations
- Full headless Xournal++ `.xopp` document generation, font overlays, and Cairo image rendering

---

## 📄 License

Distributed under the [MIT License](LICENSE). Free and open-source for personal, educational, and commercial use.
