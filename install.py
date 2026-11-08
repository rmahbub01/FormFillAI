#!/usr/bin/env python3
"""
install.py - Cross-Platform 1-Click GUI & CLI Installer and Uninstaller for FormFillAI.
Works seamlessly across Linux (RPM, DEB, Arch, Flatpak, Snap), macOS (DMG, Homebrew), and Windows.
"""

from __future__ import annotations
import os
import re
import shutil
import sys
from pathlib import Path
from typing import List, Tuple


def get_user_home() -> Path:
    """Resolve the real target user home directory even under sudo."""
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user and sudo_user != "root":
        try:
            import pwd
            return Path(pwd.getpwnam(sudo_user).pw_dir)
        except Exception:
            pass
    return Path.home()


def fix_ownership(path: Path) -> None:
    """Fix ownership of installed directories to SUDO_USER if running under sudo."""
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user and sudo_user != "root" and hasattr(os, "chown") and hasattr(os, "geteuid"):
        if os.geteuid() == 0:
            try:
                import pwd
                pw = pwd.getpwnam(sudo_user)
                uid, gid = pw.pw_uid, pw.pw_gid
                for root, dirs, files in os.walk(path):
                    os.chown(root, uid, gid)
                    for f in files:
                        os.chown(os.path.join(root, f), uid, gid)
                os.chown(path, uid, gid)
            except Exception:
                pass


def get_detected_targets() -> List[Tuple[str, Path, Path]]:
    """
    Detect all potential Xournal++ plugin directories across platforms and packaging formats.
    Returns list of (label, plugin_dir, config_dir).
    """
    targets: List[Tuple[str, Path, Path]] = []
    home = get_user_home()

    if sys.platform == "win32":
        # Windows Standard & Roaming
        local_app = os.environ.get("LOCALAPPDATA")
        app_data = os.environ.get("APPDATA")
        if local_app:
            p_dir = Path(local_app) / "xournalpp" / "plugins" / "FormFillAI"
            c_dir = Path(local_app) / "xournalpp"
            targets.append(("Windows (Local AppData)", p_dir, c_dir))
        if app_data:
            p_dir = Path(app_data) / "xournalpp" / "plugins" / "FormFillAI"
            c_dir = Path(app_data) / "xournalpp"
            targets.append(("Windows (Roaming AppData)", p_dir, c_dir))
    elif sys.platform == "darwin":
        # macOS Standard
        p_dir = home / "Library" / "Application Support" / "xournalpp" / "plugins" / "FormFillAI"
        c_dir = home / "Library" / "Application Support" / "xournalpp"
        targets.append(("macOS (Application Support)", p_dir, c_dir))
    else:
        # Linux Native (RPM, DEB, Arch, Source)
        xdg_config = os.environ.get("XDG_CONFIG_HOME")
        c_dir = Path(xdg_config) / "xournalpp" if xdg_config else home / ".config" / "xournalpp"
        p_dir = c_dir / "plugins" / "FormFillAI"
        targets.append(("Linux Native (RPM / DEB / Arch)", p_dir, c_dir))

        # Linux Flatpak
        flatpak_c_dir = home / ".var" / "app" / "com.github.xournalpp.xournalpp" / "config" / "xournalpp"
        flatpak_p_dir = flatpak_c_dir / "plugins" / "FormFillAI"
        if flatpak_c_dir.exists() or (home / ".var" / "app" / "com.github.xournalpp.xournalpp").exists():
            targets.append(("Linux Flatpak (Sandbox)", flatpak_p_dir, flatpak_c_dir))

        # Linux Snap
        snap_c_dir = home / "snap" / "xournalpp" / "current" / ".config" / "xournalpp"
        snap_p_dir = snap_c_dir / "plugins" / "FormFillAI"
        if snap_c_dir.exists() or (home / "snap" / "xournalpp").exists():
            targets.append(("Linux Snap (Sandbox)", snap_p_dir, snap_c_dir))

    return targets


def copy_plugin_files(target_dir: Path, log_cb=print) -> None:
    """Copy all plugin source files into target directory."""
    source_dir = Path(__file__).resolve().parent
    target_dir.mkdir(parents=True, exist_ok=True)

    files_to_copy = ["plugin.ini", "main.lua", "json.lua", "config.json"]
    for f in files_to_copy:
        src = source_dir / f
        if src.exists():
            log_cb(f"Copying {f} to {target_dir.name}...")
            shutil.copy2(src, target_dir / f)

    # Copy backend folder
    src_backend = source_dir / "backend"
    dst_backend = target_dir / "backend"
    if src_backend.exists():
        log_cb("Copying backend engine...")
        if dst_backend.exists():
            shutil.rmtree(dst_backend)
        shutil.copytree(src_backend, dst_backend)


def enable_in_settings_xml(config_dir: Path, log_cb=print) -> None:
    """Ensure FormFillAI is enabled in settings.xml."""
    settings_file = config_dir / "settings.xml"
    if not settings_file.exists():
        return

    try:
        content = settings_file.read_text(encoding="utf-8")
        if "FormFillAI" in content:
            log_cb(f"Plugin already enabled in {config_dir.name}/settings.xml.")
            return

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
            log_cb(f"Enabled FormFillAI in {config_dir.name}/settings.xml.")
    except Exception as e:
        log_cb(f"Note: Could not edit {config_dir.name}/settings.xml ({e})")


def disable_in_settings_xml(config_dir: Path, log_cb=print) -> None:
    """Remove FormFillAI from settings.xml."""
    settings_file = config_dir / "settings.xml"
    if not settings_file.exists():
        return

    try:
        content = settings_file.read_text(encoding="utf-8")
        if "FormFillAI" not in content:
            return

        def remover(m):
            val = m.group(1)
            # Remove FormFillAI with optional leading or trailing comma
            cleaned = re.sub(r'(?:^|,)FormFillAI(?:,|$)', ',', val)
            cleaned = cleaned.strip(',')
            return f'<property name="pluginEnabled" value="{cleaned}"/>'

        new_content, count = re.subn(r'<property name="pluginEnabled" value="([^"]*)"\s*/>', remover, content)
        if count > 0:
            settings_file.write_text(new_content, encoding="utf-8")
            log_cb(f"Removed FormFillAI from {config_dir.name}/settings.xml.")
    except Exception as e:
        log_cb(f"Note: Could not edit {config_dir.name}/settings.xml ({e})")


def run_install_all(log_cb=print) -> None:
    """Perform 1-click installation across all detected platforms/packaging."""
    targets = get_detected_targets()
    source_dir = Path(__file__).resolve().parent

    log_cb("Starting 1-click installation...")

    for label, p_dir, c_dir in targets:
        log_cb(f"Installing for {label}...")
        copy_plugin_files(p_dir, log_cb=log_cb)
        enable_in_settings_xml(c_dir, log_cb=log_cb)

        # Link or create virtualenv if needed
        venv_src = source_dir / ".venv"
        venv_dst = p_dir / ".venv"
        if venv_src.exists() and not venv_dst.exists():
            try:
                if sys.platform != "win32":
                    os.symlink(venv_src, venv_dst)
                else:
                    shutil.copytree(venv_src, venv_dst)
            except Exception:
                pass

        fix_ownership(p_dir)

    # Verify and cache/download AI models silently into user cache (~/.cache/formfillai/models)
    cache_dir = get_user_home() / ".cache" / "formfillai" / "models"
    cache_dir.mkdir(parents=True, exist_ok=True)
    for model_name in ["FFDNet-S.onnx", "FFDNet-L.onnx"]:
        tmp_model = Path("/tmp") / model_name
        cached_model = cache_dir / model_name
        if tmp_model.exists() and not cached_model.exists():
            log_cb(f"Caching {model_name}...")
            shutil.copy2(tmp_model, cached_model)

    try:
        backend_path = source_dir / "backend"
        if str(backend_path) not in sys.path:
            sys.path.insert(0, str(backend_path))
        from model_manager import resolve_model_path
        log_cb("Checking AI model (FFDNet-S)...")
        m_path, m_type = resolve_model_path("FFDNet-S", prefer_onnx=True)
        log_cb(f"AI Model ready: {m_path.name} ({m_type.upper()})")
    except Exception as e:
        log_cb(f"Note on AI model: {e}")

    fix_ownership(get_user_home() / ".cache" / "formfillai")
    log_cb("🎉 1-Click Installation Complete! FormFillAI is ready in Xournal++.")


def run_uninstall_all(log_cb=print) -> None:
    """Perform 1-click complete uninstallation from all platforms/packaging."""
    targets = get_detected_targets()

    log_cb("Starting 1-click complete uninstallation...")

    for label, p_dir, c_dir in targets:
        if p_dir.exists():
            log_cb(f"Removing plugin files from {label} ({p_dir})...")
            try:
                shutil.rmtree(p_dir, ignore_errors=True)
            except Exception as e:
                log_cb(f"Error removing {p_dir}: {e}")

        # Clean settings.xml
        disable_in_settings_xml(c_dir, log_cb=log_cb)

    # Clean user cache
    cache_dir = get_user_home() / ".cache" / "formfillai"
    if cache_dir.exists():
        log_cb(f"Cleaning cache directory ({cache_dir})...")
        try:
            shutil.rmtree(cache_dir, ignore_errors=True)
        except Exception:
            pass

    # Clean temporary runtime files
    temp_dir = Path(os.environ.get("TMPDIR") or os.environ.get("TEMP") or "/tmp")
    for f in temp_dir.glob("formfill_*"):
        try:
            f.unlink()
        except Exception:
            pass

    log_cb("✨ 1-Click Uninstallation Complete! All traces of FormFillAI have been removed.")


def run_cli_install() -> None:
    print("=====================================================")
    print("   FormFillAI - 1-Click Installer for Xournal++     ")
    print("=====================================================")
    run_install_all(log_cb=print)


def run_cli_uninstall() -> None:
    print("=====================================================")
    print("   FormFillAI - 1-Click Complete Uninstaller        ")
    print("=====================================================")
    run_uninstall_all(log_cb=print)


def run_gui() -> None:
    try:
        import tkinter as tk
        from tkinter import ttk, messagebox
    except ImportError:
        run_cli_install()
        return

    root = tk.Tk()
    root.title("FormFillAI - 1-Click Installer & Uninstaller")
    root.geometry("580x460")
    root.resizable(False, False)

    frame = ttk.Frame(root, padding=20)
    frame.pack(fill=tk.BOTH, expand=True)

    lbl_title = tk.Label(frame, text="🚀 FormFillAI Manager", font=("Sans", 16, "bold"), fg="#1a365d")
    lbl_title.pack(anchor=tk.W, pady=(0, 2))

    lbl_sub = tk.Label(
        frame,
        text="1-Click Installer & Complete Uninstaller for Xournal++ across all platforms.",
        font=("Sans", 9),
        fg="#4a5568"
    )
    lbl_sub.pack(anchor=tk.W, pady=(0, 14))

    # Detected Platforms & Packaging
    grp_detect = ttk.LabelFrame(frame, text="Detected Xournal++ Installations", padding=10)
    grp_detect.pack(fill=tk.X, pady=(0, 14))

    targets = get_detected_targets()
    for label, p_dir, _ in targets:
        status_txt = "Installed" if p_dir.exists() else "Ready to Install"
        color = "#276749" if p_dir.exists() else "#4a5568"
        row = ttk.Frame(grp_detect)
        row.pack(fill=tk.X, pady=2)
        tk.Label(row, text=f"• {label}:", font=("Sans", 9, "bold")).pack(side=tk.LEFT)
        tk.Label(row, text=f" [{status_txt}]", font=("Sans", 9), fg=color).pack(side=tk.LEFT)
        tk.Label(row, text=f" ({p_dir})", font=("Monospace", 7), fg="#718096").pack(side=tk.RIGHT)

    # Status & Progress
    status_var = tk.StringVar(value="Select an action below.")
    lbl_status = tk.Label(frame, textvariable=status_var, font=("Sans", 9), fg="#2b6cb0")
    lbl_status.pack(anchor=tk.W, pady=(0, 6))

    prog = ttk.Progressbar(frame, mode="indeterminate")
    prog.pack(fill=tk.X, pady=(0, 16))

    def on_install():
        btn_install.config(state=tk.DISABLED)
        btn_uninstall.config(state=tk.DISABLED)
        prog.start(10)
        root.update()

        try:
            run_install_all(log_cb=lambda m: status_var.set(m))
            prog.stop()
            status_var.set("🎉 Installation Complete!")
            messagebox.showinfo(
                "Installed Successfully",
                "FormFillAI is now installed!\n\n"
                "To use it in Xournal++:\n"
                "1. Open Xournal++\n"
                "2. Open any PDF\n"
                "3. Menu: Plugin > FormFillAI > Detect Current Page (Ctrl+Shift+D)"
            )
            root.destroy()
        except Exception as e:
            prog.stop()
            status_var.set(f"Error: {e}")
            messagebox.showerror("Installation Error", str(e))
            btn_install.config(state=tk.NORMAL)
            btn_uninstall.config(state=tk.NORMAL)

    def on_uninstall():
        confirm = messagebox.askyesno(
            "Confirm Complete Uninstallation",
            "Are you sure you want to completely uninstall FormFillAI?\n\n"
            "This will remove all plugin files, clean settings.xml, and clear cache."
        )
        if not confirm:
            return

        btn_install.config(state=tk.DISABLED)
        btn_uninstall.config(state=tk.DISABLED)
        prog.start(10)
        root.update()

        try:
            run_uninstall_all(log_cb=lambda m: status_var.set(m))
            prog.stop()
            status_var.set("✨ Complete Uninstallation Finished!")
            messagebox.showinfo(
                "Uninstalled Successfully",
                "FormFillAI has been completely removed from all Xournal++ installations."
            )
            root.destroy()
        except Exception as e:
            prog.stop()
            status_var.set(f"Error: {e}")
            messagebox.showerror("Uninstallation Error", str(e))
            btn_install.config(state=tk.NORMAL)
            btn_uninstall.config(state=tk.NORMAL)

    # Action Buttons Bar
    btn_frame = ttk.Frame(frame)
    btn_frame.pack(fill=tk.X, pady=(4, 0))

    btn_install = tk.Button(
        btn_frame,
        text="✨ 1-Click Install FormFillAI",
        font=("Sans", 10, "bold"),
        bg="#2b6cb0",
        fg="white",
        activebackground="#2c5282",
        activeforeground="white",
        relief=tk.FLAT,
        padx=14,
        pady=8,
        command=on_install
    )
    btn_install.pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 6))

    btn_uninstall = tk.Button(
        btn_frame,
        text="🗑️ 1-Click Complete Uninstall",
        font=("Sans", 10, "bold"),
        bg="#c53030",
        fg="white",
        activebackground="#9b2c2c",
        activeforeground="white",
        relief=tk.FLAT,
        padx=14,
        pady=8,
        command=on_uninstall
    )
    btn_uninstall.pack(side=tk.RIGHT, expand=True, fill=tk.X, padx=(6, 0))

    root.mainloop()


if __name__ == "__main__":
    if "--gui" in sys.argv:
        run_gui()
    elif "--uninstall" in sys.argv:
        run_cli_uninstall()
    else:
        # Default is silent CLI installation: NO GUI popup!
        run_cli_install()
