#!/usr/bin/env python3
"""
model_manager.py - Downloads, verifies, and resolves paths for FFDNet-S and FFDNet-L models.
"""

from __future__ import annotations
import os
import sys
import time
import urllib.request
from pathlib import Path
from typing import Optional, Tuple

HF_REPOS = {
    ("FFDNet-S", "onnx"): ("jbarrow/FFDNet-S-cpu", "FFDNet-S.onnx"),
    ("FFDNet-S", "pt"):   ("jbarrow/FFDNet-S",     "FFDNet-S.pt"),
    ("FFDNet-L", "onnx"): ("jbarrow/FFDNet-L-cpu", "FFDNet-L.onnx"),
    ("FFDNet-L", "pt"):   ("jbarrow/FFDNet-L",     "FFDNet-L.pt"),
}

EXPECTED_MIN_SIZES = {
    "FFDNet-S.onnx": 30 * 1024 * 1024,
    "FFDNet-S.pt":   15 * 1024 * 1024,
    "FFDNet-L.onnx": 90 * 1024 * 1024,
    "FFDNet-L.pt":   45 * 1024 * 1024,
}


def get_model_cache_dir() -> Path:
    """Return the global model cache directory ~/.cache/formfillai/models."""
    cache_dir = Path.home() / ".cache" / "formfillai" / "models"
    cache_dir.mkdir(parents=True, exist_ok=True)
    return cache_dir


def download_file_with_progress(url: str, dest_path: Path, description: str = "") -> bool:
    """Download a file with console progress feedback."""
    print(f"[FormFillAI] Downloading {description or dest_path.name} from Hugging Face...")
    temp_path = dest_path.with_suffix(dest_path.suffix + ".tmp")
    req = urllib.request.Request(url, headers={"User-Agent": "FormFillAI-Xournalpp/1.0"})

    try:
        with urllib.request.urlopen(req) as resp, open(temp_path, "wb") as out_file:
            total_size = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            block_size = 64 * 1024
            start_time = time.time()

            while True:
                chunk = resp.read(block_size)
                if not chunk:
                    break
                out_file.write(chunk)
                downloaded += len(chunk)

                if total_size > 0:
                    pct = (downloaded / total_size) * 100
                    elapsed = time.time() - start_time
                    speed = (downloaded / (1024 * 1024)) / max(elapsed, 0.001)
                    sys.stdout.write(f"\r[FormFillAI] {dest_path.name}: {pct:5.1f}% ({downloaded / (1024*1024):.1f}/{total_size / (1024*1024):.1f} MB, {speed:.2f} MB/s)")
                    sys.stdout.flush()

            sys.stdout.write("\n")
        temp_path.rename(dest_path)
        print(f"[FormFillAI] Successfully saved {dest_path.name}")
        return True
    except Exception as e:
        if temp_path.exists():
            temp_path.unlink()
        print(f"[FormFillAI] Error downloading from {url}: {e}")
        return False


def resolve_model_path(model_name: str = "FFDNet-S", prefer_onnx: bool = True) -> Tuple[Path, str]:
    """
    Find or download the model file for FFDNet-S or FFDNet-L.
    Returns (model_path, model_type) where model_type is 'onnx' or 'pt'.
    """
    model_name = "FFDNet-L" if "L" in model_name.upper() else "FFDNet-S"
    cache_dir = get_model_cache_dir()

    # Search locations in order
    types = ["onnx", "pt"] if prefer_onnx else ["pt", "onnx"]

    for mtype in types:
        filename = f"{model_name}.{mtype}"
        # Check cache dir
        cached = cache_dir / filename
        if cached.exists() and cached.stat().st_size >= EXPECTED_MIN_SIZES.get(filename, 1024):
            return cached, mtype

        # Check relative models dir next to this file or plugin root
        local_dir = Path(__file__).resolve().parent.parent / "models"
        local_file = local_dir / filename
        if local_file.exists() and local_file.stat().st_size >= EXPECTED_MIN_SIZES.get(filename, 1024):
            return local_file, mtype

    # Not found locally, download default preference (ONNX is preferred for CPU portability)
    chosen_type = "onnx" if prefer_onnx else "pt"
    repo_id, filename = HF_REPOS[(model_name, chosen_type)]
    target_path = cache_dir / filename
    url = f"https://huggingface.co/{repo_id}/resolve/main/{filename}"

    success = download_file_with_progress(url, target_path, f"{model_name} ({chosen_type.upper()})")
    if not success and chosen_type == "pt":
        # Fallback to ONNX
        repo_id, filename = HF_REPOS[(model_name, "onnx")]
        target_path = cache_dir / filename
        url = f"https://huggingface.co/{repo_id}/resolve/main/{filename}"
        success = download_file_with_progress(url, target_path, f"{model_name} (ONNX)")
        chosen_type = "onnx"

    if not success or not target_path.exists():
        raise RuntimeError(f"Could not download or find {model_name} model.")

    return target_path, chosen_type
