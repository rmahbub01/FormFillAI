#!/usr/bin/env python3
"""
detector.py - Form field detection engine using FFDNet-S and FFDNet-L models.
Supports both ONNX Runtime (fast, portable CPU) and Ultralytics YOLO (PyTorch/CUDA).
"""

from __future__ import annotations
import os
import sys
from pathlib import Path

# Ensure backend directory is in sys.path
backend_dir = str(Path(__file__).parent.resolve())
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

import subprocess
import tempfile
import urllib.parse
from dataclasses import dataclass, asdict
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from PIL import Image

from config_manager import load_config
from model_manager import resolve_model_path


CLASS_NAMES = {
    0: "TextBox",
    1: "ChoiceButton",
    2: "Signature"
}


@dataclass
class FormField:
    field_type: str         # "TextBox", "ChoiceButton", "Signature"
    x: float                # Upper-left X in Xournal++ document points
    y: float                # Upper-left Y in Xournal++ document points
    width: float            # Field width in Xournal++ document points
    height: float           # Field height in Xournal++ document points
    confidence: float       # Confidence score (0.0 - 1.0)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "type": str(self.field_type),
            "x": float(round(float(self.x), 2)),
            "y": float(round(float(self.y), 2)),
            "width": float(round(float(self.width), 2)),
            "height": float(round(float(self.height), 2)),
            "confidence": float(round(float(self.confidence), 3)),
        }


def resolve_pdf_path(pdf_path: Optional[str]) -> Optional[Path]:
    """Resolve PDF path handling URL encoding, relative paths, and common directories."""
    if not pdf_path:
        return None

    clean = urllib.parse.unquote(str(pdf_path).strip())
    if clean.startswith("file://"):
        clean = clean[7:]

    p = Path(clean).expanduser()
    if p.exists() and p.is_file():
        return p.resolve()

    # If relative to current directory
    cwd_p = Path.cwd() / clean
    if cwd_p.exists() and cwd_p.is_file():
        return cwd_p.resolve()

    # Search common directories by basename
    fname = Path(clean).name
    common_search_dirs = [
        Path.home() / "Downloads",
        Path.home() / "Documents",
        Path.home() / "Desktop",
        Path("/tmp"),
    ]
    for search_dir in common_search_dirs:
        candidate = search_dir / fname
        if candidate.exists() and candidate.is_file():
            return candidate.resolve()

    return None


def extract_page_as_image(
    pdf_path: Optional[str],
    page_number: int = 1,
    image_path: Optional[str] = None
) -> Tuple[Image.Image, float, float]:
    """
    Load or render the specified page into a PIL Image.
    Returns (pil_image, orig_width_pts, orig_height_pts).
    """
    if image_path and Path(image_path).exists():
        img = Image.open(image_path).convert("RGB")
        return img, float(img.width), float(img.height)

    resolved_pdf = resolve_pdf_path(pdf_path)
    if not resolved_pdf or not resolved_pdf.exists():
        raise FileNotFoundError(f"PDF or image path not found: pdf={pdf_path}, image={image_path}")

    pdf_path_str = str(resolved_pdf)

    # Try pypdfium2 first
    try:
        import pypdfium2 as pdfium
        pdf = pdfium.PdfDocument(pdf_path_str)
        page_idx = max(0, page_number - 1)
        if page_idx >= len(pdf):
            page_idx = len(pdf) - 1
        page = pdf[page_idx]
        w_pts, h_pts = page.get_size()
        # Render at 150 DPI for crisp form detection
        render_scale = 150.0 / 72.0
        bitmap = page.render(scale=render_scale)
        pil_image = bitmap.to_pil().convert("RGB")
        return pil_image, float(w_pts), float(h_pts)
    except ImportError:
        pass

    # Try native pdftoppm (standard on Linux/macOS)
    try:
        with tempfile.TemporaryDirectory() as tmp_dir:
            out_prefix = Path(tmp_dir) / "page"
            cmd = [
                "pdftoppm", "-png", "-r", "150",
                "-f", str(page_number), "-l", str(page_number),
                str(pdf_path_str), str(out_prefix)
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            pngs = list(Path(tmp_dir).glob("page*.png"))
            if pngs:
                img = Image.open(pngs[0]).convert("RGB")
                # pdftoppm rendered at 150 dpi, original point size:
                w_pts = (img.width / 150.0) * 72.0
                h_pts = (img.height / 150.0) * 72.0
                return img, w_pts, h_pts
    except Exception as e:
        print(f"[FormFillAI] pdftoppm extraction fallback failed: {e}")

    # Try pdf2image
    try:
        from pdf2image import convert_from_path
        images = convert_from_path(pdf_path_str, first_page=page_number, last_page=page_number, dpi=150)
        if images:
            img = images[0].convert("RGB")
            w_pts = (img.width / 150.0) * 72.0
            h_pts = (img.height / 150.0) * 72.0
            return img, w_pts, h_pts
    except ImportError:
        pass

    raise RuntimeError("No PDF renderer found. Please install 'pypdfium2' or install 'poppler-utils' (pdftoppm).")


def preprocess_letterbox(
    image: Image.Image,
    target_size: int = 1216
) -> Tuple[np.ndarray, float, float, float]:
    """
    Resize and pad image with reflection/gray fill to square target size.
    Returns (input_tensor, scale, pad_x, pad_y).
    """
    orig_w, orig_h = image.size
    scale = min(target_size / orig_w, target_size / orig_h)
    new_w = int(round(orig_w * scale))
    new_h = int(round(orig_h * scale))

    resized = image.resize((new_w, new_h), Image.Resampling.BILINEAR)

    pad_x = (target_size - new_w) / 2.0
    pad_y = (target_size - new_h) / 2.0

    padded = Image.new("RGB", (target_size, target_size), (114, 114, 114))
    padded.paste(resized, (int(round(pad_x)), int(round(pad_y))))

    arr = np.array(padded, dtype=np.float32) / 255.0
    arr = np.transpose(arr, (2, 0, 1))  # (3, H, W)
    arr = np.expand_dims(arr, 0)        # (1, 3, H, W)

    return arr, scale, pad_x, pad_y


def nms(boxes: List[Tuple[float, int, float, float, float, float]], iou_threshold: float = 0.20) -> List[Tuple[float, int, float, float, float, float]]:
    """Non-maximum suppression."""
    if not boxes:
        return []
    boxes.sort(key=lambda b: b[0], reverse=True)
    kept = []
    for b in boxes:
        conf, cls_id, x1, y1, x2, y2 = b
        overlap = False
        area1 = max(0.0, x2 - x1) * max(0.0, y2 - y1)
        for k in kept:
            k_conf, k_cls, kx1, ky1, kx2, ky2 = k
            ix1, iy1 = max(x1, kx1), max(y1, ky1)
            ix2, iy2 = min(x2, kx2), min(y2, ky2)
            iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
            inter = iw * ih
            area2 = max(0.0, kx2 - kx1) * max(0.0, ky2 - ky1)
            union = area1 + area2 - inter
            iou = inter / union if union > 0 else 0
            if iou > iou_threshold:
                overlap = True
                break
        if not overlap:
            kept.append(b)
    return kept


class FormFieldDetector:
    def __init__(self, model_name: str = "FFDNet-S", confidence: float = 0.28, engine: str = "auto") -> None:
        self.model_name = "FFDNet-L" if "L" in model_name.upper() else "FFDNet-S"
        self.confidence = confidence
        self.engine = engine
        self._session = None
        self._yolo = None
        self._load_model()

    def _load_model(self) -> None:
        prefer_onnx = (self.engine in ("onnx", "auto"))
        model_path, model_type = resolve_model_path(self.model_name, prefer_onnx=prefer_onnx)

        if model_type == "onnx" or (prefer_onnx and model_path.suffix == ".onnx"):
            import onnxruntime as ort
            providers = ["CPUExecutionProvider"]
            if ort.get_device() == "GPU" and "CUDAExecutionProvider" in ort.get_available_providers():
                providers.insert(0, "CUDAExecutionProvider")
            self._session = ort.InferenceSession(str(model_path), providers=providers)
            self.model_type = "onnx"
        else:
            from ultralytics import YOLO
            self._yolo = YOLO(str(model_path), task="detect")
            self.model_type = "yolo"

    def detect(
        self,
        pdf_path: Optional[str] = None,
        page_number: int = 1,
        image_path: Optional[str] = None,
        target_page_width: Optional[float] = None,
        target_page_height: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Run detection on the requested page and return mapped form fields.
        """
        pil_image, doc_w, doc_h = extract_page_as_image(pdf_path, page_number, image_path)

        # If user passed custom page dimensions from Xournal++:
        if target_page_width and target_page_width > 0:
            doc_w = target_page_width
        if target_page_height and target_page_height > 0:
            doc_h = target_page_height

        orig_w, orig_h = pil_image.size

        if self.model_type == "onnx":
            target_size = 1216
            tensor, scale, pad_x, pad_y = preprocess_letterbox(pil_image, target_size=target_size)
            outputs = self._session.run(["output0"], {"images": tensor})[0]
            out = outputs[0]  # shape: (7, num_anchors) e.g. (7, 30324)

            cx = out[0]
            cy = out[1]
            w = out[2]
            h = out[3]
            scores = out[4:7]

            classes = np.argmax(scores, axis=0)
            confs = np.max(scores, axis=0)

            mask = confs >= self.confidence
            candidates = []
            for i in np.where(mask)[0]:
                cf = float(confs[i])
                c = int(classes[i])
                bx1 = (cx[i] - w[i] / 2.0 - pad_x) / scale
                by1 = (cy[i] - h[i] / 2.0 - pad_y) / scale
                bx2 = (cx[i] + w[i] / 2.0 - pad_x) / scale
                by2 = (cy[i] + h[i] / 2.0 - pad_y) / scale

                # Clamp to original image bounds
                bx1 = max(0.0, min(float(orig_w), bx1))
                by1 = max(0.0, min(float(orig_h), by1))
                bx2 = max(0.0, min(float(orig_w), bx2))
                by2 = max(0.0, min(float(orig_h), by2))

                if bx2 > bx1 and by2 > by1:
                    candidates.append((cf, c, bx1, by1, bx2, by2))

            filtered = nms(candidates, iou_threshold=0.20)
        else:
            # YOLO / Ultralytics execution
            results = self._yolo.predict(pil_image, conf=self.confidence, imgsz=1600, verbose=False)
            filtered = []
            if results and results[0].boxes:
                for box in results[0].boxes.cpu().numpy():
                    cf = float(box.conf.item())
                    c = int(box.cls.item())
                    x1, y1, x2, y2 = box.xyxy[0]
                    filtered.append((cf, c, float(x1), float(y1), float(x2), float(y2)))
            filtered = nms(filtered, iou_threshold=0.20)

        # Map pixel boxes to document points (pts)
        fields: List[FormField] = []
        for cf, c, x1, y1, x2, y2 in filtered:
            field_type = CLASS_NAMES.get(c, "TextBox")
            pt_x = (x1 / orig_w) * doc_w
            pt_y = (y1 / orig_h) * doc_h
            pt_w = ((x2 - x1) / orig_w) * doc_w
            pt_h = ((y2 - y1) / orig_h) * doc_h

            # Filter tiny noise boxes (< 6 pts)
            if pt_w < 6.0 or pt_h < 6.0:
                continue

            fields.append(FormField(
                field_type=field_type,
                x=pt_x,
                y=pt_y,
                width=pt_w,
                height=pt_h,
                confidence=cf
            ))

        # Natural reading order sort: top-to-bottom, left-to-right with row grouping tolerance
        # Rows within 12 points vertically are considered the same row
        fields.sort(key=lambda f: (round(f.y / 12.0) * 12.0, f.x))

        text_boxes = [f.to_dict() for f in fields if f.field_type == "TextBox"]
        checkboxes = [f.to_dict() for f in fields if f.field_type == "ChoiceButton"]
        signatures = [f.to_dict() for f in fields if f.field_type == "Signature"]

        return {
            "success": True,
            "model": str(self.model_name),
            "model_type": str(self.model_type),
            "page": int(page_number),
            "page_width": float(round(float(doc_w), 2)),
            "page_height": float(round(float(doc_h), 2)),
            "counts": {
                "total": int(len(fields)),
                "text_boxes": int(len(text_boxes)),
                "checkboxes": int(len(checkboxes)),
                "signatures": int(len(signatures)),
            },
            "text_boxes": text_boxes,
            "checkboxes": checkboxes,
            "signatures": signatures,
        }
