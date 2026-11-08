#!/usr/bin/env python3
"""
config_manager.py - Manages FormFillAI configuration settings and persistence.
"""

from __future__ import annotations
import json
import os
from pathlib import Path
from typing import Any, Dict

DEFAULT_CONFIG: Dict[str, Any] = {
    "model_name": "FFDNet-S",          # "FFDNet-S" (fast, lightweight) or "FFDNet-L" (high accuracy)
    "engine": "auto",                  # "auto", "onnx", "torch"
    "confidence": 0.28,                # Detection confidence threshold (0.10 - 0.90)
    "device": "auto",                  # "auto", "cpu", "cuda"
    "font_family": "Nikosh",           # Default font family: Nikosh (Bangladesh Govt Standard) or Kalpurush
    "font_size_mode": "auto",          # "auto" (scale to field height) or "fixed"
    "font_size": 11.0,                 # Fixed font size in points if mode == "fixed"
    "font_color": 0x000000,            # Text color (RGB integer for Xournal++)
    "font_color_hex": "#000000",       # Text color hex string for GUI
    "checkbox_style": "check",         # "check" (✓), "cross" (✗), "square" (■), "bullet" (●), "custom"
    "checkbox_stroke_width": 1.6,      # Stroke width for drawn checkboxes
    "checkbox_color": 0x002060,        # Checkbox stroke color (RGB integer)
    "checkbox_color_hex": "#002060",   # Checkbox stroke color hex string
    "checkbox_custom_char": "✓",       # Custom character glyph if style == "custom"
    "auto_fill_checkboxes": False,     # Whether to automatically fill checkboxes on detection
    "show_field_borders": False,       # Do not draw dashed borders (pure fillable text fields)
    "border_color": 0x90B0D0,          # Border guideline color (light slate blue)
    "border_color_hex": "#90B0D0",     # Border guideline color hex
    "border_width": 0.8,               # Border guideline stroke width
}


def get_config_dir() -> Path:
    """Return the configuration directory for FormFillAI."""
    # Check XDG_CONFIG_HOME or fallback to ~/.config/xournalpp/plugins/FormFillAI
    base_dir = os.environ.get("XDG_CONFIG_HOME")
    if base_dir:
        cfg_dir = Path(base_dir) / "xournalpp" / "plugins" / "FormFillAI"
    else:
        cfg_dir = Path.home() / ".config" / "xournalpp" / "plugins" / "FormFillAI"
    cfg_dir.mkdir(parents=True, exist_ok=True)
    return cfg_dir


def get_config_path() -> Path:
    """Return the path to config.json."""
    return get_config_dir() / "config.json"


def load_config() -> Dict[str, Any]:
    """Load configuration from config.json, merging with defaults."""
    cfg_path = get_config_path()
    config = dict(DEFAULT_CONFIG)
    if cfg_path.exists():
        try:
            with open(cfg_path, "r", encoding="utf-8") as f:
                user_cfg = json.load(f)
                if isinstance(user_cfg, dict):
                    config.update(user_cfg)
        except Exception as e:
            print(f"[FormFillAI] Warning: Failed to parse {cfg_path}: {e}")
    return config


def save_config(config: Dict[str, Any]) -> None:
    """Save configuration to config.json."""
    cfg_path = get_config_path()
    try:
        # Normalize hex color integers and strings
        if "font_color_hex" in config:
            h = config["font_color_hex"].lstrip("#")
            try:
                config["font_color"] = int(h, 16)
            except ValueError:
                pass
        if "checkbox_color_hex" in config:
            h = config["checkbox_color_hex"].lstrip("#")
            try:
                config["checkbox_color"] = int(h, 16)
            except ValueError:
                pass
        if "border_color_hex" in config:
            h = config["border_color_hex"].lstrip("#")
            try:
                config["border_color"] = int(h, 16)
            except ValueError:
                pass

        with open(cfg_path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2)
    except Exception as e:
        print(f"[FormFillAI] Error saving config to {cfg_path}: {e}")
