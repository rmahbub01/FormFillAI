#!/usr/bin/env python3
"""
install.py - Cross-platform 1-click GUI & CLI installer for FormFillAI.
Works across Linux, macOS, and Windows.
"""

from __future__ import annotations
import os
import shutil
import sys
from pathlib import Path
from typing import Optional


def get_xournalpp_plugin_dir() -> Path:
    """Detect the OS-specific Xournal++ plugins directory."""
    if sys.platform == "win32":
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            base = Path(local_app_data) / "xournalpp" / "plugins"
        else:
            base = Path.home() / "AppData" / "Local" / "xournalpp" / "plugins"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "xournalpp" / "plugins"
    else:
        # Linux / BSD (XDG)
        xdg_config = os.environ.get("XDG_CONFIG_HOME")
        if xdg_config:
            base = Path(xdg_config) / "xournalpp" / "plugins"
        else:
            base = Path.home() / ".config" / "xournalpp" / "plugins"

    target = base / "FormFillAI"
    target.mkdir(parents=True, exist_ok=True)
    return target


def get_xournalpp_config_dir() -> Path:
    """Return the parent configuration directory containing settings.xml."""
    plugin_dir = get_xournalpp_plugin_dir()
    # plugin_dir is <config>/xournalpp/plugins/FormFillAI -> parent.parent is <config>/xournalpp
    return plugin_dir.parent.parent


def copy_plugin_files(target_dir: Path, log_cb=print) -> None:
    """Copy all plugin source files into the destination directory."""
    source_dir = Path(__file__).resolve().parent

    files_to_copy = ["plugin.ini", "main.lua", "json.lua"]
    for f in files_to_copy:
        src = source_dir / f
        if src.exists():
            log_cb(f"Copying {f}...")
            shutil.copy2(src, target_dir / f)

    # Copy backend folder
    src_backend = source_dir / "backend"
    dst_backend = target_dir / "backend"
    if src_backend.exists():
        log_cb("Copying backend engine...")
        if dst_backend.exists():
            shutil.rmtree(dst_backend)
        shutil.copytree(src_backend, dst_backend)


def enable_in_settings_xml(log_cb=print) -> None:
    """Ensure FormFillAI is included in the pluginEnabled list in settings.xml."""
    cfg_dir = get_xournalpp_config_dir()
    settings_file = cfg_dir / "settings.xml"

    if not settings_file.exists():
        return

    try:
        content = settings_file.read_text(encoding="utf-8")
        if "FormFillAI" in content:
            log_cb("Plugin is already registered in settings.xml.")
            return

        import re
        def replacer(m):
            val = m.group(1)
            if not val:
                return '<property name="pluginEnabled" value="FormFillAI"/>'
            if "FormFillAI" in val:
                return m.group(0)
            return f'<property name="pluginEnabled" value="{val},FormFillAI"/>'

        new_content, count = re.subn(r'<property name="pluginEnabled" value="([^"]*)"\s*/>', replacer, content)
        if count > 0:
            settings_file.write_text(new_content, encoding="utf-8")
            log_cb("Enabled FormFillAI in settings.xml.")
    except Exception as e:
        log_cb(f"Note: Could not edit settings.xml ({e}), plugin will be enabled via plugin.ini")


def run_cli_install() -> None:
    print("=====================================================")
    print("   FormFillAI - 1-Click Installer for Xournal++     ")
    print("=====================================================")

    target_dir = get_xournalpp_plugin_dir()
    print(f"Target Directory: {target_dir}")

    copy_plugin_files(target_dir)
    enable_in_settings_xml()

    # Pre-copy models from /tmp or cache if available
    cache_dir = Path.home() / ".cache" / "formfillai" / "models"
    cache_dir.mkdir(parents=True, exist_ok=True)
    for model_name in ["FFDNet-S.onnx", "FFDNet-L.onnx", "FFDNet-S.pt"]:
        tmp_model = Path("/tmp") / model_name
        cached_model = cache_dir / model_name
        if tmp_model.exists() and not cached_model.exists():
            print(f"Caching {model_name}...")
            shutil.copy2(tmp_model, cached_model)

    print("\n🎉 FormFillAI has been successfully installed in Xournal++!")
    print("Usage:")
    print("  1. Start Xournal++.")
    print("  2. Open any flat PDF.")
    print("  3. Navigate to Menu: Plugin > FormFillAI > Detect Form Fields (or Ctrl+Alt+F)!")


def run_gui_install() -> None:
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox
    except ImportError:
        run_cli_install()
        return

    root = tk.Tk()
    root.title("FormFillAI - 1-Click Installer")
    root.geometry("540x400")
    root.resizable(False, False)

    frame = ttk.Frame(root, padding=20)
    frame.pack(fill=tk.BOTH, expand=True)

    lbl_title = tk.Label(frame, text="🚀 FormFillAI for Xournal++", font=("Sans", 16, "bold"), fg="#1a365d")
    lbl_title.pack(anchor=tk.W, pady=(0, 4))

    lbl_sub = tk.Label(
        frame,
        text="Install the AI-powered flat PDF form detector plugin in 1-click.",
        font=("Sans", 10),
        fg="#4a5568"
    )
    lbl_sub.pack(anchor=tk.W, pady=(0, 16))

    target_dir = get_xournalpp_plugin_dir()
    path_lbl = tk.Label(
        frame,
        text=f"Install location:\n{target_dir}",
        font=("Monospace", 8),
        bg="#edf2f7",
        relief=tk.SOLID,
        borderwidth=1,
        justify=tk.LEFT,
        padx=8,
        pady=6
    )
    path_lbl.pack(fill=tk.X, pady=(0, 16))

    status_var = tk.StringVar(value="Ready to install.")
    lbl_status = tk.Label(frame, textvariable=status_var, font=("Sans", 9), fg="#2b6cb0")
    lbl_status.pack(anchor=tk.W, pady=(0, 8))

    prog = ttk.Progressbar(frame, mode="indeterminate")
    prog.pack(fill=tk.X, pady=(0, 20))

    def do_install():
        btn_install.config(state=tk.DISABLED)
        prog.start(10)
        status_var.set("Copying plugin files...")
        root.update()

        try:
            copy_plugin_files(target_dir, log_cb=lambda m: status_var.set(m))
            enable_in_settings_xml(log_cb=lambda m: status_var.set(m))

            cache_dir = Path.home() / ".cache" / "formfillai" / "models"
            cache_dir.mkdir(parents=True, exist_ok=True)
            for model_name in ["FFDNet-S.onnx", "FFDNet-L.onnx"]:
                tmp_model = Path("/tmp") / model_name
                cached_model = cache_dir / model_name
                if tmp_model.exists() and not cached_model.exists():
                    shutil.copy2(tmp_model, cached_model)

            prog.stop()
            status_var.set("🎉 Installation Complete!")
            messagebox.showinfo(
                "Installation Successful",
                "FormFillAI is now installed in Xournal++!\n\n"
                "To use it:\n"
                "1. Open Xournal++\n"
                "2. Look under Menu: Plugin > FormFillAI\n"
                "3. Shortcut: Ctrl+Alt+F to auto-detect form fields!"
            )
            root.destroy()
        except Exception as e:
            prog.stop()
            status_var.set(f"Error: {e}")
            messagebox.showerror("Error", f"Installation failed:\n{e}")
            btn_install.config(state=tk.NORMAL)

    btn_install = tk.Button(
        frame,
        text="✨ Install FormFillAI Now",
        font=("Sans", 11, "bold"),
        bg="#2b6cb0",
        fg="white",
        activebackground="#2c5282",
        activeforeground="white",
        relief=tk.FLAT,
        padx=16,
        pady=8,
        command=do_install
    )
    btn_install.pack(pady=10)

    root.mainloop()


if __name__ == "__main__":
    # Check if graphical display is present
    has_display = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY") or sys.platform == "win32")
    if "--cli" in sys.argv or not has_display:
        run_cli_install()
    else:
        run_gui_install()
