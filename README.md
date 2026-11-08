# 📝 FormFillAI: AI-Powered Flat PDF Form Field Detection for Xournal++

**FormFillAI** is a high-performance Xournal++ plugin that automatically detects flat (non-interactive/scanned) PDF form fields using small, state-of-the-art vision models (**FFDNet-S** and **FFDNet-L**) and overlays fillable text boxes and interactive checkboxes with a single click or keystroke.

---

## ✨ Features

### 1. 🔤 Exact-Fit Overlay Text Boxes (Non-Movable & Non-Resizable)
- Automatically analyzes the page layout and places overlay text boxes **matching the exact width and height** of every detected input field.
- **Non-movable & non-resizable in text editing mode**: Automatically selects Xournal++'s Text Tool (`Tool_text`) upon detection so clicking inside any box immediately opens inline typing without accidental dragging, shifting, or resizing.
- Isolates form overlays on a dedicated **`FormFillAI` layer**, keeping your personal annotations and document drawings clean.
- Configurable subtle visual guide outlines to instantly see every interactive field on flat scanned documents.

### 2. 🎨 Full Text Box Customization & Complete Font Picker (with Bangla Support)
- **Delete overlays**: Delete individual overlays directly or wipe all detected fields on the current page with `Clear All Form Overlays`.
- **Add manual overlays**: Missed a field? Use `Add Text Field Overlay (at Selection / Center)` to place custom-sized input overlays anywhere.
- **Font & Style Picker**:
  - **Dynamic System Font Discovery**: Enumerate and select from **ALL fonts installed on your machine** (over 400+ system fonts).
  - **Dedicated Bangla Font Support**: Built-in priority access to all installed Bangla/Bengali fonts (**Nikosh**, **Kalpurush**, **SolaimanLipi**, **Siyam Rupali**, **Noto Sans Bengali**, **Tiro Bangla**, **Vrinda**, etc.) with live Bangla text preview.
  - **Auto-fit font size**: Automatically scales text height to ~72% of single-line form field height for a natural, printed look, or set a fixed font size.
  - **Font color**: Choose from presets or use the custom visual color picker.

### 3. ☑️ Versatile Checkbox Auto-Fill & Manual Marking
- **Fill all checkboxes in one click**:
  - **Checked (`✓`)**: Natural, crisp hand-checked vector stroke.
  - **Crossed (`✗`)**: Clean diagonal corner-to-corner cross.
  - **Solid Square (`■`)**: Filled block for shaded questionnaire boxes.
  - **Bullet Dot (`●`)**: Centered circular dot for radio choices.
  - **Custom Shape / Symbol**: User-defined character (e.g. `★`, `✔`, `X`, `Y`, `N`).
- **Manual checkbox addition**: If the AI misses an irregular checkbox, click `Add Checkbox Here (at Selection / Center)` to manually place and register one.
- **Toggle nearest checkbox**: Easily toggle/mark the checkbox closest to your cursor or view center using `Ctrl + Shift + T`.

### 4. 🚀 Ultra-Easy 1-Click Installation
- Built with zero-friction setup:
  - **Linux & macOS**: Run `./install.sh` or `python3 install.py`.
  - **Windows**: Double-click `install.bat` or run `python install.py`.
  - **Graphical Installer**: `python3 install.py` launches a 1-click install window.
- Automatically enables the plugin in Xournal++ without requiring manual configuration.

---

## 🧠 AI Models: FFDNet-S & FFDNet-L

FormFillAI uses the open-source **FFDNet** (Form Field Detection Network) object detection models from the *CommonForms* project:

| Model | Parameters | Weights Size | Optimized Engine | Best For |
|---|---|---|---|---|
| **FFDNet-S** *(Default)* | ~6 Million | ~18 MB | ONNX Runtime / CPU | High speed, low memory, instant CPU response |
| **FFDNet-L** | ~25 Million | ~48 MB | ONNX Runtime / CUDA / CPU | High accuracy on dense, low-contrast, or complex forms |

The plugin natively bundles an **ONNX Runtime engine**—meaning no massive GPU or multi-gigabyte PyTorch downloads are required. It runs in under **0.8 seconds** on standard laptop CPUs.

---

## 📥 Installation

### Method 1: Graphical / 1-Click (Recommended)

Run the Python installer from this folder:

```bash
python3 install.py
```

A friendly installer window will appear. Click **Install FormFillAI Now**, and you're done!

---

### Method 2: Command Line (Linux & macOS)

Open your terminal in the repository directory and run:

```bash
./install.sh
```

---

### Method 3: Windows

Double-click `install.bat` or run:

```cmd
install.bat
```

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action | Description |
|---|---|---|
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd> | **Detect Current Page** | Detects text fields and checkboxes; creates bounded fillable overlays in Pure Black Nikosh font |
| | **Detect Full PDF** | High-speed batch detection across all PDF pages in memory (~2.8s) |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>R</kbd> | **Remove Guide Borders** | Removes all dashed guide borders and unfilled placeholders, leaving 100% naturally typed form |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>X</kbd> | **Add Checkbox Here** | Choose shape (`✓`, `✗`, `■`, `●`, `☐`); drops onto PDF with handles to resize & drag anywhere |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd> | **Settings and Preferences** | Configure 446+ system fonts (Nikosh Bangla default), models, and colors |

---

## 🖥️ Menu Actions (`Plugin > FormFillAI`)

FormFillAI provides a streamlined 5-tool workflow:

1. **FormFillAI: Detect Current Page** (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>D</kbd>): Scans the active page and overlays fillable text boxes matching the exact boundaries (`x, y, width, height`) of detected fields, plus subtle dashed guidelines. Clicking inside any field immediately activates typing with Pure Black Nikosh font.
2. **FormFillAI: Detect Full PDF**: High-speed batch detection across all PDF pages in memory (~2.8s) with zero freezing.
3. **FormFillAI: Remove Guide Borders** (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>R</kbd>): Deletes all dashed guide lines and unfilled placeholders, retaining 100% of user-typed text and checkmarks for a clean, naturally typed form ready for PDF export.
4. **FormFillAI: Add Checkbox Here** (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>X</kbd>): No selection needed beforehand. Prompts you to pick a shape (`✓ Check`, `✗ Cross`, `■ Square`, `● Bullet`, `☐ Box`), immediately drops the shape onto the PDF, and activates selection resize handles so you can resize and reposition it freely.
5. **FormFillAI: Settings and Preferences** (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>S</kbd>): Configure fonts, AI model (FFDNet-S / FFDNet-L), and colors.

---

## 🛠️ Settings Configuration

Open the settings dialog via `Plugin > FormFillAI > Settings and Preferences` or <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>S</kbd>:

1. **AI Model Selection**: Switch seamlessly between `FFDNet-S` and `FFDNet-L`.
2. **Confidence Sensitivity**: Adjust detection threshold slider (default: `28%`).
3. **Font Settings**: Choose font family, auto-fitting vs fixed font size, and text color.
4. **Checkbox Settings**: Choose shape (`✓`, `✗`, `■`, `●`, or custom character), line thickness, and color.
5. **Visual Guidelines**: Toggle subtle field border outlines.

Settings are saved in `~/.config/xournalpp/plugins/FormFillAI/config.json`.

---

## 🧪 Testing & Verification

Run the automated test suite:

```bash
python3 tests/test_detector.py
```

Tests verify:
- Configuration persistence
- Model weight resolution
- FFDNet-S and FFDNet-L object detection
- Typographic coordinate mapping
- Full headless Xournal++ `.xopp` document generation and Cairo rendering

---

## 📜 License

MIT License. Free and open source for all users.
