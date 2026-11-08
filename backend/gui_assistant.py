#!/usr/bin/env python3
"""
gui_assistant.py - Interactive Form & Checkbox Assistant for FormFillAI.
Allows users to:
1. Select and mark individual preferred checkboxes (Checked ✓, Crossed ✗, Square ■, Bullet ●).
2. Fill text fields in Bengali (Nikosh) or English.
3. Remove or toggle guide borders before saving/exporting to PDF.
"""

from __future__ import annotations
import argparse
import json
import os
import sys
import tkinter as tk
from tkinter import ttk, messagebox
from pathlib import Path
from typing import Any, Dict, List

# Ensure backend directory is in sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from config_manager import load_config


class FormAssistantDialog:
    def __init__(self, root: tk.Tk, data_path: str, out_path: str, page_number: int = 1) -> None:
        self.root = root
        self.data_path = Path(data_path)
        self.out_path = Path(out_path)
        self.page_number = page_number
        self.config = load_config()

        self.root.title(f"FormFillAI - Form & Checkbox Assistant (Page {self.page_number})")
        self.root.geometry("740x720")
        self.root.minsize(680, 560)

        # Style setup
        self.style = ttk.Style()
        try:
            self.style.theme_use("clam")
        except Exception:
            pass

        self._load_data()
        self._build_ui()

    def _load_data(self) -> None:
        self.data: Dict[str, Any] = {}
        if self.data_path.exists():
            try:
                with open(self.data_path, "r", encoding="utf-8") as f:
                    self.data = json.load(f)
            except Exception as e:
                print(f"[FormFillAI] Failed to read {self.data_path}: {e}")

        # If data is multi-page format, get current page data
        if "pages" in self.data and str(self.page_number) in self.data["pages"]:
            page_data = self.data["pages"][str(self.page_number)]
            self.text_boxes = page_data.get("text_boxes", [])
            self.checkboxes = page_data.get("checkboxes", [])
        else:
            self.text_boxes = self.data.get("text_boxes", [])
            self.checkboxes = self.data.get("checkboxes", [])

        # State for checkboxes: [cb_idx] = "none" | "check" | "cross" | "square" | "bullet"
        self.cb_states: Dict[int, str] = {}
        for i, cb in enumerate(self.checkboxes):
            self.cb_states[i] = cb.get("state", "none")

        # State for text entries: [tb_idx] = tk.StringVar
        self.tb_vars: Dict[int, tk.StringVar] = {}
        for i, tb in enumerate(self.text_boxes):
            existing_text = tb.get("user_text", "")
            self.tb_vars[i] = tk.StringVar(value=existing_text)

    def _build_ui(self) -> None:
        # Header banner
        header = tk.Frame(self.root, bg="#1a365d", padx=16, pady=12)
        header.pack(fill=tk.X)

        title_lbl = tk.Label(
            header,
            text=f"📋 FormFillAI Assistant — Page {self.page_number}",
            font=("Sans", 14, "bold"),
            fg="#ffffff",
            bg="#1a365d"
        )
        title_lbl.pack(side=tk.LEFT)

        font_name = self.config.get("font_family", "Nikosh")
        info_lbl = tk.Label(
            header,
            text=f"Active Font: {font_name} | {len(self.checkboxes)} Checkboxes | {len(self.text_boxes)} Text Fields",
            font=("Sans", 10),
            fg="#cbd5e1",
            bg="#1a365d"
        )
        info_lbl.pack(side=tk.RIGHT)

        # Notebook tabs: Checkboxes, Text Fields, Options
        notebook = ttk.Notebook(self.root)
        notebook.pack(fill=tk.BOTH, expand=True, padx=12, pady=8)

        tab_cb = ttk.Frame(notebook, padding=8)
        tab_tb = ttk.Frame(notebook, padding=8)

        notebook.add(tab_cb, text=f" ☑️ Checkbox Selector ({len(self.checkboxes)}) ")
        notebook.add(tab_tb, text=f" 📝 Text Field Inputs ({len(self.text_boxes)}) ")

        self._build_checkboxes_tab(tab_cb)
        self._build_textboxes_tab(tab_tb)

        # Bottom Action Bar
        bottom_bar = tk.Frame(self.root, bg="#f1f5f9", padx=16, pady=12, bd=1, relief=tk.GROOVE)
        bottom_bar.pack(fill=tk.X, side=tk.BOTTOM)

        btn_apply = tk.Button(
            bottom_bar,
            text="✓ Apply to Document (Update Xournal++)",
            font=("Sans", 11, "bold"),
            bg="#0d9488",
            fg="white",
            activebackground="#0f766e",
            activeforeground="white",
            padx=16,
            pady=6,
            relief=tk.FLAT,
            cursor="hand2",
            command=self._on_apply
        )
        btn_apply.pack(side=tk.LEFT)

        btn_remove_guides = tk.Button(
            bottom_bar,
            text="🧹 Clean Borders (For PDF Export)",
            font=("Sans", 10),
            bg="#e2e8f0",
            fg="#1e293b",
            padx=12,
            pady=6,
            relief=tk.FLAT,
            cursor="hand2",
            command=self._on_remove_guides
        )
        btn_remove_guides.pack(side=tk.LEFT, padx=10)

        btn_close = tk.Button(
            bottom_bar,
            text="Close",
            font=("Sans", 10),
            bg="#e2e8f0",
            fg="#475569",
            padx=12,
            pady=6,
            relief=tk.FLAT,
            cursor="hand2",
            command=self.root.destroy
        )
        btn_close.pack(side=tk.RIGHT)

    def _build_checkboxes_tab(self, parent: ttk.Frame) -> None:
        top_ctrl = tk.Frame(parent, pady=4)
        top_ctrl.pack(fill=tk.X)

        lbl = tk.Label(
            top_ctrl,
            text="Select your preferred boxes below (e.g. choose Male OR Female, Married OR Unmarried):",
            font=("Sans", 9, "bold"),
            fg="#334155"
        )
        lbl.pack(side=tk.LEFT)

        btn_clr_all = tk.Button(
            top_ctrl,
            text="Clear All Checkboxes",
            font=("Sans", 9),
            bg="#fee2e2",
            fg="#991b1b",
            padx=8,
            pady=2,
            relief=tk.FLAT,
            command=self._clear_all_checkboxes
        )
        btn_clr_all.pack(side=tk.RIGHT)

        # Scrollable container for checkboxes
        canvas = tk.Canvas(parent, borderwidth=0, highlightthickness=0)
        scrollbar = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
        scroll_frame = ttk.Frame(canvas)

        scroll_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=scroll_frame, anchor="nw")
        canvas.configure(xscrollcommand=None, yscrollcommand=scrollbar.set)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, pady=6)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y, pady=6)

        # Mouse wheel support
        def _on_mousewheel(event):
            canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        canvas.bind_all("<Button-4>", lambda e: canvas.yview_scroll(-1, "units"))
        canvas.bind_all("<Button-5>", lambda e: canvas.yview_scroll(1, "units"))

        self.cb_status_labels: Dict[int, tk.Label] = {}
        self.cb_btn_widgets: Dict[int, Dict[str, tk.Button]] = {}

        for i, cb in enumerate(self.checkboxes):
            row_frame = tk.Frame(scroll_frame, bg="#f8fafc" if i % 2 == 0 else "#ffffff", padx=8, pady=4, bd=1, relief=tk.SOLID)
            row_frame.pack(fill=tk.X, expand=True, pady=2)

            # Label showing index and coordinate
            x_pt = round(cb.get("x", 0), 1)
            y_pt = round(cb.get("y", 0), 1)
            lbl_info = tk.Label(
                row_frame,
                text=f"Checkbox #{i+1} (X: {x_pt}, Y: {y_pt}):",
                font=("Sans", 9, "bold"),
                width=24,
                anchor=tk.W,
                bg=row_frame["bg"],
                fg="#1e293b"
            )
            lbl_info.pack(side=tk.LEFT)

            # Current state badge
            cur_state = self.cb_states.get(i, "none")
            state_text = self._get_state_badge_text(cur_state)
            lbl_badge = tk.Label(
                row_frame,
                text=state_text,
                font=("Sans", 9, "bold"),
                width=10,
                bg=self._get_state_color(cur_state),
                fg="white",
                padx=4,
                pady=2
            )
            lbl_badge.pack(side=tk.LEFT, padx=6)
            self.cb_status_labels[i] = lbl_badge

            # Action buttons for this specific box
            btn_box_frame = tk.Frame(row_frame, bg=row_frame["bg"])
            btn_box_frame.pack(side=tk.RIGHT)

            btn_check = tk.Button(
                btn_box_frame,
                text="✓ Check",
                font=("Sans", 9),
                bg="#dcfce7",
                fg="#166534",
                relief=tk.FLAT,
                cursor="hand2",
                command=lambda idx=i: self._set_cb_state(idx, "check")
            )
            btn_check.pack(side=tk.LEFT, padx=2)

            btn_cross = tk.Button(
                btn_box_frame,
                text="✗ Cross",
                font=("Sans", 9),
                bg="#fef3c7",
                fg="#92400e",
                relief=tk.FLAT,
                cursor="hand2",
                command=lambda idx=i: self._set_cb_state(idx, "cross")
            )
            btn_cross.pack(side=tk.LEFT, padx=2)

            btn_clear = tk.Button(
                btn_box_frame,
                text="⬜ Clear",
                font=("Sans", 9),
                bg="#f1f5f9",
                fg="#64748b",
                relief=tk.FLAT,
                cursor="hand2",
                command=lambda idx=i: self._set_cb_state(idx, "none")
            )
            btn_clear.pack(side=tk.LEFT, padx=2)

    def _get_state_badge_text(self, state: str) -> str:
        if state == "check":
            return "✓ Checked"
        elif state == "cross":
            return "✗ Crossed"
        elif state == "square":
            return "■ Square"
        elif state == "bullet":
            return "● Bullet"
        return "Empty"

    def _get_state_color(self, state: str) -> str:
        if state == "check":
            return "#16a34a"
        elif state == "cross":
            return "#d97706"
        elif state in ("square", "bullet"):
            return "#2563eb"
        return "#94a3b8"

    def _set_cb_state(self, idx: int, state: str) -> None:
        self.cb_states[idx] = state
        if idx in self.cb_status_labels:
            lbl = self.cb_status_labels[idx]
            lbl.config(
                text=self._get_state_badge_text(state),
                bg=self._get_state_color(state)
            )

    def _clear_all_checkboxes(self) -> None:
        for idx in self.cb_states:
            self._set_cb_state(idx, "none")

    def _build_textboxes_tab(self, parent: ttk.Frame) -> None:
        top_ctrl = tk.Frame(parent, pady=4)
        top_ctrl.pack(fill=tk.X)

        font_name = self.config.get("font_family", "Nikosh")
        lbl = tk.Label(
            top_ctrl,
            text=f"Enter text for detected fields (Bangla / English supported with {font_name} font):",
            font=("Sans", 9, "bold"),
            fg="#334155"
        )
        lbl.pack(side=tk.LEFT)

        btn_clr_all = tk.Button(
            top_ctrl,
            text="Clear All Entries",
            font=("Sans", 9),
            bg="#fee2e2",
            fg="#991b1b",
            padx=8,
            pady=2,
            relief=tk.FLAT,
            command=self._clear_all_textboxes
        )
        btn_clr_all.pack(side=tk.RIGHT)

        # Scrollable container for text fields
        canvas = tk.Canvas(parent, borderwidth=0, highlightthickness=0)
        scrollbar = ttk.Scrollbar(parent, orient="vertical", command=canvas.yview)
        scroll_frame = ttk.Frame(canvas)

        scroll_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=scroll_frame, anchor="nw")
        canvas.configure(xscrollcommand=None, yscrollcommand=scrollbar.set)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, pady=6)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y, pady=6)

        for i, tb in enumerate(self.text_boxes):
            row_frame = tk.Frame(scroll_frame, bg="#f8fafc" if i % 2 == 0 else "#ffffff", padx=8, pady=4)
            row_frame.pack(fill=tk.X, expand=True, pady=2)

            x_pt = round(tb.get("x", 0), 1)
            y_pt = round(tb.get("y", 0), 1)
            w_pt = round(tb.get("width", 0), 1)

            lbl_info = tk.Label(
                row_frame,
                text=f"Field #{i+1} (Y: {y_pt}):",
                font=("Sans", 9, "bold"),
                width=16,
                anchor=tk.W,
                bg=row_frame["bg"],
                fg="#1e293b"
            )
            lbl_info.pack(side=tk.LEFT)

            var = self.tb_vars[i]
            entry = tk.Entry(
                row_frame,
                textvariable=var,
                font=(font_name, 11),
                width=42,
                relief=tk.SOLID,
                bd=1
            )
            entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6)

            btn_clr = tk.Button(
                row_frame,
                text="✕",
                font=("Sans", 8),
                bg="#f1f5f9",
                fg="#94a3b8",
                relief=tk.FLAT,
                command=lambda v=var: v.set("")
            )
            btn_clr.pack(side=tk.RIGHT)

    def _clear_all_textboxes(self) -> None:
        for var in self.tb_vars.values():
            var.set("")

    def _on_apply(self) -> None:
        # Build applied data structure
        applied_data = {
            "page": self.page_number,
            "action": "apply_fills",
            "remove_guides": False,
            "checkboxes": [],
            "text_boxes": []
        }

        # Checkboxes with applied states
        for i, cb in enumerate(self.checkboxes):
            st = self.cb_states.get(i, "none")
            applied_data["checkboxes"].append({
                "x": cb["x"],
                "y": cb["y"],
                "width": cb["width"],
                "height": cb["height"],
                "state": st
            })

        # Text boxes with entered values
        for i, tb in enumerate(self.text_boxes):
            val = self.tb_vars[i].get().strip()
            if val:
                applied_data["text_boxes"].append({
                    "x": tb["x"],
                    "y": tb["y"],
                    "width": tb["width"],
                    "height": tb["height"],
                    "text": val
                })

        try:
            self.out_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.out_path, "w", encoding="utf-8") as f:
                json.dump(applied_data, f, indent=2, ensure_ascii=False)
            messagebox.showinfo(
                "Fills Applied",
                f"Successfully saved applied fills for Page {self.page_number}!\n\n"
                f"• Checkboxes marked: {sum(1 for s in self.cb_states.values() if s != 'none')}\n"
                f"• Text fields filled: {len(applied_data['text_boxes'])}\n\n"
                "In Xournal++, select Menu > FormFillAI > 'Apply Fills from Assistant' (or press Ctrl+Shift+A) to render onto canvas."
            )
            self.root.destroy()
        except Exception as e:
            messagebox.showerror("Error", f"Could not save applied data: {e}")

    def _on_remove_guides(self) -> None:
        applied_data = {
            "page": self.page_number,
            "action": "remove_guides",
            "remove_guides": True
        }
        try:
            self.out_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.out_path, "w", encoding="utf-8") as f:
                json.dump(applied_data, f, indent=2)
            messagebox.showinfo(
                "Guide Borders Cleaned",
                "Guide borders flagged for removal.\n\n"
                "In Xournal++, select Menu > FormFillAI > 'Remove Guide Borders' to clean the document for saving/printing."
            )
            self.root.destroy()
        except Exception as e:
            messagebox.showerror("Error", f"Could not save action: {e}")


def launch_assistant(data_path: str, out_path: str, page_number: int = 1) -> None:
    root = tk.Tk()
    app = FormAssistantDialog(root, data_path, out_path, page_number)
    root.mainloop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FormFillAI Assistant")
    parser.add_argument("--data", type=str, required=True, help="Input detection JSON")
    parser.add_argument("--out", type=str, required=True, help="Output applied JSON")
    parser.add_argument("--page", type=int, default=1, help="Page number (1-based)")
    args = parser.parse_args()

    launch_assistant(args.data, args.out, args.page)
