#!/usr/bin/env python3
"""
gui_checkboxes.py - Dedicated Interactive Checkbox Manager for FormFillAI.
Features:
- Individual checkbox selection: choose which boxes to check, cross, square-fill, or leave empty.
- Visual thumbnail crops of each checkbox and its label from the PDF.
- Instant, non-blocking operation.
- Exports selection to JSON for Xournal++ rendering.
"""

from __future__ import annotations
import argparse
import json
import os
import sys
import tkinter as tk
from tkinter import ttk, messagebox
from pathlib import Path
from typing import Any, Dict, List, Optional

# Ensure backend directory is in sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from config_manager import load_config
from detector import resolve_pdf_path


class CheckboxManagerDialog:
    def __init__(self, root: tk.Tk, data_path: str, out_path: str, pdf_path: Optional[str] = None, page_number: int = 1) -> None:
        self.root = root
        self.data_path = Path(data_path)
        self.out_path = Path(out_path)
        self.pdf_path = pdf_path
        self.page_number = page_number
        self.config = load_config()

        self.root.title(f"FormFillAI - Checkbox Manager (Page {self.page_number})")
        self.root.geometry("780x680")
        self.root.minsize(680, 500)

        # Style setup
        self.style = ttk.Style()
        try:
            self.style.theme_use("clam")
        except Exception:
            pass

        self._load_data()
        self._load_thumbnails()
        self._build_ui()

    def _load_data(self) -> None:
        self.checkboxes: List[Dict[str, Any]] = []
        if self.data_path.exists():
            try:
                with open(self.data_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if "pages" in data and str(self.page_number) in data["pages"]:
                        self.checkboxes = data["pages"][str(self.page_number)].get("checkboxes", [])
                    else:
                        self.checkboxes = data.get("checkboxes", [])
            except Exception as e:
                print(f"[FormFillAI] Failed to read {self.data_path}: {e}")

        # State mapping: [idx] = "none" | "check" | "cross" | "square" | "bullet"
        self.cb_states: Dict[int, str] = {}
        for i, cb in enumerate(self.checkboxes):
            self.cb_states[i] = cb.get("state", "none")

    def _load_thumbnails(self) -> None:
        """Render page and crop small thumbnails around each checkbox with label."""
        self.thumbnails: Dict[int, Any] = {}
        if not self.pdf_path or not self.checkboxes:
            return

        resolved = resolve_pdf_path(self.pdf_path)
        if not resolved or not resolved.exists():
            return

        try:
            import pypdfium2 as pdfium
            from PIL import Image, ImageTk

            pdf = pdfium.PdfDocument(str(resolved))
            page_idx = max(0, min(self.page_number - 1, len(pdf) - 1))
            page = pdf[page_idx]
            w_pts, h_pts = page.get_size()
            # Fast 96 DPI rendering for instant thumbnail generation
            render_scale = 96.0 / 72.0
            bitmap = page.render(scale=render_scale)
            pil_img = bitmap.to_pil().convert("RGB")

            scale_x = pil_img.width / w_pts
            scale_y = pil_img.height / h_pts

            for i, cb in enumerate(self.checkboxes):
                cx = float(cb.get("x", 0))
                cy = float(cb.get("y", 0))
                cw = float(cb.get("width", 12))
                ch = float(cb.get("height", 12))

                # Crop around checkbox + label to the right (~110 pts)
                px1 = int(max(0, (cx - 4) * scale_x))
                py1 = int(max(0, (cy - 4) * scale_y))
                px2 = int(min(pil_img.width, (cx + max(cw + 10, 110)) * scale_x))
                py2 = int(min(pil_img.height, (cy + ch + 5) * scale_y))

                crop = pil_img.crop((px1, py1, px2, py2))
                target_h = 26
                aspect = crop.width / max(1, crop.height)
                target_w = max(40, min(200, int(target_h * aspect)))
                resized = crop.resize((target_w, target_h), Image.Resampling.BILINEAR)
                self.thumbnails[i] = ImageTk.PhotoImage(resized)
        except Exception as e:
            print(f"[FormFillAI] Fast thumbnail rendering fallback: {e}")

    def _build_ui(self) -> None:
        # Header banner
        header = tk.Frame(self.root, bg="#1a365d", padx=16, pady=12)
        header.pack(fill=tk.X)

        title_lbl = tk.Label(
            header,
            text=f"☑️ Checkbox Manager — Page {self.page_number}",
            font=("Sans", 14, "bold"),
            fg="#ffffff",
            bg="#1a365d"
        )
        title_lbl.pack(side=tk.LEFT)

        info_lbl = tk.Label(
            header,
            text=f"{len(self.checkboxes)} Checkboxes Detected",
            font=("Sans", 10),
            fg="#cbd5e1",
            bg="#1a365d"
        )
        info_lbl.pack(side=tk.RIGHT)

        # Control Bar
        ctrl_bar = tk.Frame(self.root, bg="#f8fafc", padx=16, pady=8, bd=1, relief=tk.SOLID)
        ctrl_bar.pack(fill=tk.X)

        lbl_instruct = tk.Label(
            ctrl_bar,
            text="Choose which individual checkboxes to mark (e.g. choose Male vs Female, Married vs Unmarried):",
            font=("Sans", 9, "bold"),
            fg="#334155",
            bg="#f8fafc"
        )
        lbl_instruct.pack(side=tk.LEFT)

        btn_clr_all = tk.Button(
            ctrl_bar,
            text="Clear All",
            font=("Sans", 9),
            bg="#fee2e2",
            fg="#991b1b",
            padx=10,
            pady=2,
            relief=tk.FLAT,
            cursor="hand2",
            command=self._clear_all
        )
        btn_clr_all.pack(side=tk.RIGHT)

        # Scrollable container for checkboxes
        container = ttk.Frame(self.root)
        container.pack(fill=tk.BOTH, expand=True, padx=12, pady=6)

        canvas = tk.Canvas(container, borderwidth=0, highlightthickness=0)
        scrollbar = ttk.Scrollbar(container, orient="vertical", command=canvas.yview)
        scroll_frame = ttk.Frame(canvas)

        scroll_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=scroll_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Mouse wheel support
        canvas.bind_all("<Button-4>", lambda e: canvas.yview_scroll(-1, "units"))
        canvas.bind_all("<Button-5>", lambda e: canvas.yview_scroll(1, "units"))

        self.status_labels: Dict[int, tk.Label] = {}

        if not self.checkboxes:
            lbl_empty = tk.Label(
                scroll_frame,
                text="No checkboxes detected on this page.\nRun 'FormFillAI: Detect Current Page' first.",
                font=("Sans", 11),
                fg="#64748b",
                pady=40
            )
            lbl_empty.pack()

        for i, cb in enumerate(self.checkboxes):
            row_bg = "#f8fafc" if i % 2 == 0 else "#ffffff"
            row = tk.Frame(scroll_frame, bg=row_bg, padx=8, pady=4, bd=1, relief=tk.SOLID)
            row.pack(fill=tk.X, expand=True, pady=2)

            # Checkbox index
            lbl_id = tk.Label(
                row,
                text=f"#{i+1}",
                font=("Sans", 9, "bold"),
                width=4,
                bg=row_bg,
                fg="#475569"
            )
            lbl_id.pack(side=tk.LEFT)

            # Thumbnail image if available
            if i in self.thumbnails:
                lbl_thumb = tk.Label(row, image=self.thumbnails[i], bg=row_bg)
                lbl_thumb.pack(side=tk.LEFT, padx=6)
            else:
                x_pt = round(cb.get("x", 0), 1)
                y_pt = round(cb.get("y", 0), 1)
                lbl_coord = tk.Label(
                    row,
                    text=f"(X: {x_pt}, Y: {y_pt})",
                    font=("Sans", 9),
                    width=14,
                    bg=row_bg,
                    fg="#64748b"
                )
                lbl_coord.pack(side=tk.LEFT, padx=4)

            # Status Badge
            cur_state = self.cb_states.get(i, "none")
            lbl_badge = tk.Label(
                row,
                text=self._get_badge_text(cur_state),
                font=("Sans", 9, "bold"),
                width=10,
                bg=self._get_badge_color(cur_state),
                fg="white",
                padx=6,
                pady=2
            )
            lbl_badge.pack(side=tk.LEFT, padx=8)
            self.status_labels[i] = lbl_badge

            # Action Buttons: Check, Cross, Square, Clear
            btn_box = tk.Frame(row, bg=row_bg)
            btn_box.pack(side=tk.RIGHT)

            btn_check = tk.Button(
                btn_box,
                text="✓ Check",
                font=("Sans", 9),
                bg="#dcfce7",
                fg="#166534",
                relief=tk.FLAT,
                cursor="hand2",
                command=lambda idx=i: self._set_state(idx, "check")
            )
            btn_check.pack(side=tk.LEFT, padx=2)

            btn_cross = tk.Button(
                btn_box,
                text="✗ Cross",
                font=("Sans", 9),
                bg="#fef3c7",
                fg="#92400e",
                relief=tk.FLAT,
                cursor="hand2",
                command=lambda idx=i: self._set_state(idx, "cross")
            )
            btn_cross.pack(side=tk.LEFT, padx=2)

            btn_sq = tk.Button(
                btn_box,
                text="■ Square",
                font=("Sans", 9),
                bg="#dbeafe",
                fg="#1e40af",
                relief=tk.FLAT,
                cursor="hand2",
                command=lambda idx=i: self._set_state(idx, "square")
            )
            btn_sq.pack(side=tk.LEFT, padx=2)

            btn_clr = tk.Button(
                btn_box,
                text="⬜ Clear",
                font=("Sans", 9),
                bg="#f1f5f9",
                fg="#64748b",
                relief=tk.FLAT,
                cursor="hand2",
                command=lambda idx=i: self._set_state(idx, "none")
            )
            btn_clr.pack(side=tk.LEFT, padx=2)

        # Bottom Bar
        bottom = tk.Frame(self.root, bg="#f1f5f9", padx=16, pady=12, bd=1, relief=tk.GROOVE)
        bottom.pack(fill=tk.X, side=tk.BOTTOM)

        btn_apply = tk.Button(
            bottom,
            text="✓ Apply Checkmarks to Document",
            font=("Sans", 11, "bold"),
            bg="#0d9488",
            fg="white",
            activebackground="#0f766e",
            activeforeground="white",
            padx=18,
            pady=6,
            relief=tk.FLAT,
            cursor="hand2",
            command=self._on_apply
        )
        btn_apply.pack(side=tk.LEFT)

        btn_close = tk.Button(
            bottom,
            text="Cancel",
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

    def _get_badge_text(self, state: str) -> str:
        if state == "check":
            return "✓ Checked"
        elif state == "cross":
            return "✗ Crossed"
        elif state == "square":
            return "■ Square"
        elif state == "bullet":
            return "● Bullet"
        return "Empty"

    def _get_badge_color(self, state: str) -> str:
        if state == "check":
            return "#16a34a"
        elif state == "cross":
            return "#d97706"
        elif state in ("square", "bullet"):
            return "#2563eb"
        return "#94a3b8"

    def _set_state(self, idx: int, state: str) -> None:
        self.cb_states[idx] = state
        if idx in self.status_labels:
            self.status_labels[idx].config(
                text=self._get_badge_text(state),
                bg=self._get_badge_color(state)
            )

    def _clear_all(self) -> None:
        for idx in self.cb_states:
            self._set_state(idx, "none")

    def _on_apply(self) -> None:
        applied = {
            "page": self.page_number,
            "action": "apply_checkboxes",
            "checkboxes": []
        }
        for i, cb in enumerate(self.checkboxes):
            st = self.cb_states.get(i, "none")
            applied["checkboxes"].append({
                "x": cb["x"],
                "y": cb["y"],
                "width": cb["width"],
                "height": cb["height"],
                "state": st
            })

        try:
            self.out_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.out_path, "w", encoding="utf-8") as f:
                json.dump(applied, f, indent=2)

            # Auto-trigger Xournal++ to apply checkmarks immediately
            try:
                import subprocess
                subprocess.run(
                    ["xdotool", "search", "--class", "xournalpp", "windowactivate", "--sync", "key", "--clearmodifiers", "ctrl+shift+c"],
                    check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
            except Exception:
                pass

            self.root.destroy()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to save checkboxes: {e}")


def launch_checkbox_manager(data_path: str, out_path: str, pdf_path: Optional[str] = None, page_number: int = 1) -> None:
    root = tk.Tk()
    app = CheckboxManagerDialog(root, data_path, out_path, pdf_path, page_number)
    root.mainloop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FormFillAI Checkbox Manager")
    parser.add_argument("--data", type=str, required=True, help="Input detection JSON")
    parser.add_argument("--out", type=str, required=True, help="Output applied JSON")
    parser.add_argument("--pdf", type=str, default=None, help="Background PDF path for thumbnail crops")
    parser.add_argument("--page", type=int, default=1, help="Page number (1-based)")
    args = parser.parse_args()

    launch_checkbox_manager(args.data, args.out, args.pdf, args.page)
