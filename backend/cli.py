#!/usr/bin/env python3
"""
cli.py - Command-line interface for FormFillAI.
Invoked by the Xournal++ Lua plugin or run standalone.
"""

from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

# Add backend directory to path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from config_manager import load_config, save_config, get_config_path
from detector import FormFieldDetector
from model_manager import resolve_model_path


def main() -> None:
    parser = argparse.ArgumentParser(description="FormFillAI Backend Engine")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Subcommand: detect
    p_detect = subparsers.add_parser("detect", help="Detect form fields on a PDF page or image")
    p_detect.add_argument("--pdf", type=str, default=None, help="Path to input PDF file")
    p_detect.add_argument("--page", type=int, default=1, help="Page number (1-based)")
    p_detect.add_argument("--all-pages", action="store_true", help="Detect form fields across all pages of the PDF")
    p_detect.add_argument("--image", type=str, default=None, help="Path to image file (optional fallback)")
    p_detect.add_argument("--width", type=float, default=None, help="Target document width in points")
    p_detect.add_argument("--height", type=float, default=None, help="Target document height in points")
    p_detect.add_argument("--model", type=str, default=None, help="Override model (FFDNet-S or FFDNet-L)")
    p_detect.add_argument("--conf", type=float, default=None, help="Override confidence threshold")
    p_detect.add_argument("--out", type=str, default=None, help="Path to save JSON output")

    # Subcommand: settings
    subparsers.add_parser("settings", help="Open visual settings and tools dialog")

    # Subcommand: assistant
    p_ast = subparsers.add_parser("assistant", help="Open FormFillAI Assistant & Checkbox Manager")
    p_ast.add_argument("--data", type=str, required=True, help="Path to detection JSON")
    p_ast.add_argument("--out", type=str, required=True, help="Path to applied JSON output")
    p_ast.add_argument("--page", type=int, default=1, help="Page number (1-based)")

    # Subcommand: download
    p_dl = subparsers.add_parser("download", help="Pre-download AI models")
    p_dl.add_argument("--model", type=str, default="all", choices=["all", "FFDNet-S", "FFDNet-L"], help="Model to download")

    # Subcommand: config
    subparsers.add_parser("config", help="Print current configuration JSON")

    args = parser.parse_args()
    config = load_config()

    if args.command == "detect":
        model_name = args.model or config.get("model_name", "FFDNet-S")
        confidence = args.conf if args.conf is not None else float(config.get("confidence", 0.28))
        engine = config.get("engine", "auto")

        try:
            detector = FormFieldDetector(model_name=model_name, confidence=confidence, engine=engine)
            if args.all_pages and args.pdf:
                results = detector.detect_all_pages(pdf_path=args.pdf)
            else:
                results = detector.detect(
                    pdf_path=args.pdf,
                    page_number=args.page,
                    image_path=args.image,
                    target_page_width=args.width,
                    target_page_height=args.height
                )

            # Inject active configuration so Lua can immediately apply font & checkbox styling
            results["config"] = config

            json_str = json.dumps(results, indent=2)
            if args.out:
                out_path = Path(args.out)
                out_path.parent.mkdir(parents=True, exist_ok=True)
                with open(out_path, "w", encoding="utf-8") as f:
                    f.write(json_str)
                print(f"[FormFillAI] Results written to {args.out}")
            else:
                print(json_str)
        except Exception as e:
            err_data = {
                "success": False,
                "error": str(e),
                "model": model_name,
                "page": args.page,
            }
            err_str = json.dumps(err_data, indent=2)
            if args.out:
                with open(args.out, "w", encoding="utf-8") as f:
                    f.write(err_str)
            print(err_str, file=sys.stderr)
            sys.exit(1)

    elif args.command == "settings":
        from gui_settings import launch_gui
        launch_gui()

    elif args.command == "assistant":
        from gui_assistant import launch_assistant
        launch_assistant(args.data, args.out, args.page)

    elif args.command == "download":
        models = ["FFDNet-S", "FFDNet-L"] if args.model == "all" else [args.model]
        for m in models:
            print(f"Downloading {m}...")
            p, t = resolve_model_path(m, prefer_onnx=True)
            print(f"Ready: {p} ({t})")

    elif args.command == "config":
        print(json.dumps(config, indent=2))


if __name__ == "__main__":
    main()
