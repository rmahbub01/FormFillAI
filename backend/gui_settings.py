#!/usr/bin/env python3
"""
gui_settings.py - Modern Tkinter configuration and manual form tool dialog for FormFillAI.
Features:
- Dynamic discovery of ALL system fonts installed on Linux, macOS, and Windows.
- Dedicated Bangla / Bengali font section (Nikosh, Kalpurush, SolaimanLipi, etc.).
- Live font preview with Bangla and English sample text.
- Instant search filter for 400+ system fonts.
- Checkbox customization (checked, crossed, solid square, bullet, custom symbol).
"""

from __future__ import annotations
import os
import subprocess
import sys
import tkinter as tk
from tkinter import ttk, colorchooser, messagebox
from typing import Any, Dict, List, Set, Tuple

# Add backend directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config_manager import load_config, save_config
from model_manager import resolve_model_path


BANGLA_KEYWORDS = [
    "bangla", "bengali", "kalpurush", "solaiman", "siyam",
    "nikosh", "tiro", "mukti", "lohit", "vrinda", "apona",
    "kohinoor", "ruposhi", "mitra", "ekushey"
]


def get_all_system_fonts() -> Tuple[List[str], List[str]]:
    """
    Dynamically discover all installed system fonts.
    Returns (all_fonts_sorted, bangla_fonts_prioritized).
    """
    fonts: Set[str] = set()

    # 1. Query Fontconfig (fc-list) on Linux / macOS
    try:
        res = subprocess.run(
            ["fc-list", ":", "family"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False
        )
        if res.returncode == 0:
            for line in res.stdout.splitlines():
                for f in line.split(","):
                    f = f.strip()
                    if f and not f.startswith("@"):
                        fonts.add(f)
    except Exception:
        pass

    # 2. Query Tkinter font database
    try:
        import tkinter.font as tkfont
        for f in tkfont.families():
            if f and not f.startswith("@"):
                fonts.add(f)
    except Exception:
        pass

    # Standard fallback fonts
    fallback_defaults = [
        "Nikosh", "Kalpurush", "SolaimanLipi", "Siyam Rupali", "Noto Sans Bengali",
        "Tiro Bangla", "Vrinda", "Sans", "Serif", "Monospace", "Arial", "Liberation Sans"
    ]
    for fb in fallback_defaults:
        fonts.add(fb)

    all_fonts = sorted(fonts, key=lambda s: s.lower())

    # Detect all Bangla fonts
    bangla_set = [f for f in all_fonts if any(k in f.lower() for k in BANGLA_KEYWORDS)]

    # Prioritize popular/standard government Bangla fonts
    priority_order = [
        "Nikosh", "NikoshBAN", "NikoshLight", "Nikosh Modern",
        "Kalpurush", "Kalpurush ANSI",
        "SolaimanLipi",
        "Noto Sans Bengali", "Noto Serif Bengali",
        "Siyam Rupali", "Siyam Rupali ANSI",
        "Tiro Bangla", "Vrinda", "Mukti", "Lohit Bengali"
    ]

    ordered_bangla: List[str] = []
    for prio in priority_order:
        for f in bangla_set:
            if f.lower() == prio.lower() and f not in ordered_bangla:
                ordered_bangla.append(f)
    for f in bangla_set:
        if f not in ordered_bangla:
            ordered_bangla.append(f)

    return all_fonts, ordered_bangla


class FormFillAISettingsDialog:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("FormFillAI - Settings & Bangla Font Tools")

        # Auto-center and constrain dialog to guarantee all buttons are fully visible
        self.root.update_idletasks()
        screen_w = self.root.winfo_screenwidth()
        screen_h = self.root.winfo_screenheight()
        win_w = min(640, max(520, screen_w - 60))
        win_h = min(480, max(400, screen_h - 120))
        pos_x = max(0, (screen_w - win_w) // 2)
        pos_y = max(0, (screen_h - win_h) // 2)
        self.root.geometry(f"{win_w}x{win_h}+{pos_x}+{pos_y}")
        self.root.minsize(520, 380)

        self.config = load_config()

        # Load system fonts
        self.all_fonts, self.bangla_fonts = get_all_system_fonts()

        # Style setup
        self.style = ttk.Style()
        try:
            self.style.theme_use("clam")
        except Exception:
            pass

        self._init_variables()
        self._build_ui()

    def _init_variables(self) -> None:
        self.var_model = tk.StringVar(value=self.config.get("model_name", "FFDNet-S"))
        self.var_confidence = tk.DoubleVar(value=float(self.config.get("confidence", 0.28)))

        # Default font selection: if Nikosh is available, default to it; else Kalpurush, else current config
        current_font = self.config.get("font_family", "")
        if not current_font or current_font == "Sans":
            if "Nikosh" in self.all_fonts:
                current_font = "Nikosh"
            elif "Kalpurush" in self.all_fonts:
                current_font = "Kalpurush"
            elif self.bangla_fonts:
                current_font = self.bangla_fonts[0]
            else:
                current_font = "Sans"

        self.var_font_family = tk.StringVar(value=current_font)
        self.var_font_mode = tk.StringVar(value=self.config.get("font_size_mode", "auto"))
        self.var_font_size = tk.DoubleVar(value=float(self.config.get("font_size", 11.0)))
        self.var_font_color = tk.StringVar(value=self.config.get("font_color_hex", "#000000"))

        self.var_borders = tk.BooleanVar(value=bool(self.config.get("show_field_borders", False)))
        self.var_font_filter = tk.StringVar(value="")

    def _build_ui(self) -> None:
        main_frame = ttk.Frame(self.root, padding=(14, 10, 14, 10))
        main_frame.pack(fill=tk.BOTH, expand=True)

        # 1. Title Banner at Top
        title_frame = ttk.Frame(main_frame)
        title_frame.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))

        lbl_title = tk.Label(
            title_frame,
            text="✨ FormFillAI Settings",
            font=("Sans", 13, "bold"),
            fg="#1a365d"
        )
        lbl_title.pack(anchor=tk.W)

        lbl_sub = tk.Label(
            title_frame,
            text="Configure Bangla fonts, text sizing, and form field AI detection.",
            font=("Sans", 9),
            fg="#4a5568"
        )
        lbl_sub.pack(anchor=tk.W)

        # 2. Bottom Action Bar - Anchored permanently at bottom so buttons NEVER get hidden!
        btn_bar = ttk.Frame(main_frame)
        btn_bar.pack(side=tk.BOTTOM, fill=tk.X, pady=(10, 0))

        btn_save = tk.Button(
            btn_bar,
            text="💾 Save Preferences",
            font=("Sans", 10, "bold"),
            bg="#2b6cb0",
            fg="white",
            activebackground="#2c5282",
            activeforeground="white",
            padx=16,
            pady=6,
            relief=tk.FLAT,
            command=self._on_save
        )
        btn_save.pack(side=tk.RIGHT, padx=(6, 0))

        btn_cancel = tk.Button(
            btn_bar,
            text="Cancel",
            font=("Sans", 10),
            bg="#edf2f7",
            fg="#2d3748",
            padx=12,
            pady=6,
            relief=tk.FLAT,
            command=self.root.destroy
        )
        btn_cancel.pack(side=tk.RIGHT)

        btn_cache = tk.Button(
            btn_bar,
            text="⬇️ Check/Download Models",
            font=("Sans", 9),
            bg="#e2e8f0",
            fg="#4a5568",
            padx=10,
            pady=6,
            relief=tk.FLAT,
            command=self._pre_download_models
        )
        btn_cache.pack(side=tk.LEFT)

        # 3. Notebook for categorized tabs - Fills remaining middle space
        nb = ttk.Notebook(main_frame)
        nb.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        # Tab 1: Bangla & All System Fonts
        tab_font = ttk.Frame(nb, padding=10)
        nb.add(tab_font, text="🇧🇩 Fonts & Bangla Support")
        self._build_font_tab(tab_font)

        # Tab 2: AI Model & Detection
        tab_ai = ttk.Frame(nb, padding=10)
        nb.add(tab_ai, text="🤖 AI Model (FFDNet)")
        self._build_ai_tab(tab_ai)

    def _build_font_tab(self, parent: ttk.Frame) -> None:
        # Quick Bangla Font Picker
        grp_bangla = ttk.LabelFrame(parent, text="🇧🇩 Installed Bangla Fonts (Quick Select)", padding=8)
        grp_bangla.pack(fill=tk.X, pady=(0, 6))

        bangla_sub = ttk.Frame(grp_bangla)
        bangla_sub.pack(fill=tk.X)

        lbl_bangla_desc = tk.Label(
            bangla_sub,
            text=f"Found {len(self.bangla_fonts)} Bangla fonts installed on your machine:",
            font=("Sans", 9)
        )
        lbl_bangla_desc.pack(anchor=tk.W, pady=(0, 4))

        # Popular Bangla font buttons
        btn_row = ttk.Frame(grp_bangla)
        btn_row.pack(fill=tk.X, pady=(0, 2))

        top_bangla = ["Nikosh", "Kalpurush", "SolaimanLipi", "Noto Sans Bengali", "Siyam Rupali"]
        for b_name in top_bangla:
            if b_name in self.all_fonts:
                b_btn = tk.Button(
                    btn_row,
                    text=f"✓ {b_name}",
                    font=("Sans", 9),
                    bg="#ebf8ff",
                    fg="#2b6cb0",
                    activebackground="#bee3f8",
                    relief=tk.RIDGE,
                    padx=6,
                    pady=2,
                    command=lambda name=b_name: self._select_font(name)
                )
                b_btn.pack(side=tk.LEFT, padx=3)

        # Searchable Font List
        grp_all_fonts = ttk.LabelFrame(parent, text="All Installed System Fonts", padding=8)
        grp_all_fonts.pack(fill=tk.BOTH, expand=True, pady=(0, 6))

        search_frame = ttk.Frame(grp_all_fonts)
        search_frame.pack(fill=tk.X, pady=(0, 4))

        tk.Label(search_frame, text="🔍 Search: ", font=("Sans", 9)).pack(side=tk.LEFT)
        ent_search = ttk.Entry(search_frame, textvariable=self.var_font_filter)
        ent_search.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)
        ent_search.bind("<KeyRelease>", self._filter_fonts)

        self.lbl_selected_font = tk.Label(
            search_frame,
            text=f"Selected: {self.var_font_family.get()}",
            font=("Sans", 9, "bold"),
            fg="#2b6cb0"
        )
        self.lbl_selected_font.pack(side=tk.RIGHT, padx=4)

        # Listbox with Scrollbar for all fonts
        list_frame = ttk.Frame(grp_all_fonts)
        list_frame.pack(fill=tk.BOTH, expand=True)

        scrollbar = ttk.Scrollbar(list_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.font_listbox = tk.Listbox(
            list_frame,
            yscrollcommand=scrollbar.set,
            font=("Sans", 10),
            selectmode=tk.SINGLE,
            height=5
        )
        self.font_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.font_listbox.yview)
        self.font_listbox.bind("<<ListboxSelect>>", self._on_font_selected)

        self._populate_font_listbox(self.all_fonts)

        # Font Size & Color Row
        opt_frame = ttk.Frame(parent)
        opt_frame.pack(fill=tk.X)

        # Size
        grp_size = ttk.LabelFrame(opt_frame, text="Font Size Behavior", padding=6)
        grp_size.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 4))

        rb_auto = ttk.Radiobutton(
            grp_size,
            text="Auto-fit to box height (Recommended)",
            variable=self.var_font_mode,
            value="auto"
        )
        rb_auto.pack(anchor=tk.W)

        size_fixed_frame = ttk.Frame(grp_size)
        size_fixed_frame.pack(anchor=tk.W, pady=(2, 0))
        rb_fixed = ttk.Radiobutton(
            size_fixed_frame,
            text="Fixed size: ",
            variable=self.var_font_mode,
            value="fixed"
        )
        rb_fixed.pack(side=tk.LEFT)

        spn_size = ttk.Spinbox(
            size_fixed_frame,
            from_=6,
            to=36,
            increment=0.5,
            textvariable=self.var_font_size,
            width=5
        )
        spn_size.pack(side=tk.LEFT, padx=4)
        tk.Label(size_fixed_frame, text="pt", font=("Sans", 9)).pack(side=tk.LEFT)

        # Color
        grp_color = ttk.LabelFrame(opt_frame, text="Font Color", padding=6)
        grp_color.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(4, 0))

        c_sub = ttk.Frame(grp_color)
        c_sub.pack(fill=tk.X, pady=2)

        self.swatch_font = tk.Label(
            c_sub,
            width=3,
            height=1,
            bg=self.var_font_color.get(),
            relief=tk.SOLID,
            borderwidth=1
        )
        self.swatch_font.pack(side=tk.LEFT, padx=(0, 6))

        btn_pick = ttk.Button(c_sub, text="Color...", command=self._pick_font_color, width=7)
        btn_pick.pack(side=tk.LEFT, padx=(0, 6))

        for col in ["#000000", "#002060", "#8B0000"]:
            b_c = tk.Button(
                c_sub,
                bg=col,
                width=1,
                height=1,
                relief=tk.FLAT,
                command=lambda c=col: self._set_font_color(c)
            )
            b_c.pack(side=tk.LEFT, padx=2)

    def _build_ai_tab(self, parent: ttk.Frame) -> None:
        grp_model = ttk.LabelFrame(parent, text="Form Field Detection Model", padding=10)
        grp_model.pack(fill=tk.X, pady=(0, 8))

        rb1 = ttk.Radiobutton(
            grp_model,
            text="FFDNet-S (Fast & Lightweight ~18MB) — Recommended (Inference < 1.0s)",
            variable=self.var_model,
            value="FFDNet-S"
        )
        rb1.pack(anchor=tk.W, pady=4)

        rb2 = ttk.Radiobutton(
            grp_model,
            text="FFDNet-L (High-Capacity ~48MB) — Maximum accuracy on complex/low-contrast forms",
            variable=self.var_model,
            value="FFDNet-L"
        )
        rb2.pack(anchor=tk.W, pady=4)

        grp_conf = ttk.LabelFrame(parent, text="Confidence Sensitivity", padding=10)
        grp_conf.pack(fill=tk.X)

        val_frame = ttk.Frame(grp_conf)
        val_frame.pack(fill=tk.X)

        self.lbl_conf_val = tk.Label(
            val_frame,
            text=f"{int(self.var_confidence.get() * 100)}%",
            font=("Sans", 10, "bold"),
            fg="#2b6cb0"
        )
        self.lbl_conf_val.pack(side=tk.RIGHT)

        tk.Label(val_frame, text="Minimum confidence threshold:").pack(side=tk.LEFT)

        scale = ttk.Scale(
            grp_conf,
            from_=0.10,
            to=0.90,
            variable=self.var_confidence,
            command=lambda v: self.lbl_conf_val.config(text=f"{int(float(v) * 100)}%")
        )
        scale.pack(fill=tk.X, pady=(6, 0))

    def _populate_font_listbox(self, font_list: List[str]) -> None:
        self.font_listbox.delete(0, tk.END)
        cur = self.var_font_family.get().lower()
        sel_idx = 0
        for i, f in enumerate(font_list):
            self.font_listbox.insert(tk.END, f)
            if f.lower() == cur:
                sel_idx = i

        if font_list:
            self.font_listbox.selection_set(sel_idx)
            self.font_listbox.see(sel_idx)

    def _filter_fonts(self, event=None) -> None:
        q = self.var_font_filter.get().strip().lower()
        if not q:
            self._populate_font_listbox(self.all_fonts)
        else:
            filtered = [f for f in self.all_fonts if q in f.lower()]
            self._populate_font_listbox(filtered)

    def _on_font_selected(self, event) -> None:
        sel = self.font_listbox.curselection()
        if sel:
            font_name = self.font_listbox.get(sel[0])
            self._select_font(font_name)

    def _select_font(self, font_name: str) -> None:
        self.var_font_family.set(font_name)
        if hasattr(self, "lbl_selected_font"):
            self.lbl_selected_font.config(text=f"Selected: {font_name}")

    def _pick_font_color(self) -> None:
        c = colorchooser.askcolor(color=self.var_font_color.get(), title="Select Font Color")
        if c and c[1]:
            self._set_font_color(c[1].upper())

    def _set_font_color(self, hex_val: str) -> None:
        self.var_font_color.set(hex_val)
        self.swatch_font.config(bg=hex_val)

    def _on_save(self) -> None:
        self.config["model_name"] = self.var_model.get()
        self.config["confidence"] = round(float(self.var_confidence.get()), 3)
        self.config["font_family"] = self.var_font_family.get()
        self.config["font_size_mode"] = self.var_font_mode.get()
        self.config["font_size"] = round(float(self.var_font_size.get()), 1)
        self.config["font_color_hex"] = self.var_font_color.get()
        self.config["show_field_borders"] = self.var_borders.get()

        save_config(self.config)
        self.root.destroy()

    def _pre_download_models(self) -> None:
        model = self.var_model.get()
        try:
            path, mtype = resolve_model_path(model, prefer_onnx=True)
            messagebox.showinfo("Model Ready", f"Model {model} ({mtype.upper()}) is cached and ready at:\n{path}")
        except Exception as e:
            messagebox.showerror("Error", f"Could not verify {model}: {e}")


def launch_gui() -> None:
    root = tk.Tk()
    app = FormFillAISettingsDialog(root)
    root.mainloop()


if __name__ == "__main__":
    launch_gui()
