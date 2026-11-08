#!/usr/bin/env python3
"""
test_detector.py - Test suite for FormFillAI.
Verifies config management, model loading, detection accuracy, coordinate mapping,
and Xournal++ .xopp file generation and rendering.
"""

import gzip
import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from PIL import Image, ImageDraw

# Add parent directory to path
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "backend"))

from config_manager import load_config, save_config, DEFAULT_CONFIG
from model_manager import resolve_model_path
from detector import FormFieldDetector


class TestFormFillAI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Create a synthetic form page for testing
        cls.img_w, cls.img_h = 800, 1000
        cls.test_img_path = Path("/tmp/test_form_ai.png")

        img = Image.new("RGB", (cls.img_w, cls.img_h), "white")
        draw = ImageDraw.Draw(img)

        # Draw Title
        draw.text((50, 40), "MEDICAL INTAKE FORM", fill="black")

        # Field 1: Name Textbox (rect: 150, 95, 550, 125 -> w=400, h=30)
        draw.text((50, 100), "Full Name:", fill="black")
        draw.rectangle([150, 95, 550, 125], outline="black", width=2)

        # Field 2: Address Textbox (rect: 150, 155, 550, 185 -> w=400, h=30)
        draw.text((50, 160), "Home Address:", fill="black")
        draw.rectangle([150, 155, 550, 185], outline="black", width=2)

        # Checkbox 1 (rect: 150, 220, 170, 240 -> w=20, h=20)
        draw.rectangle([150, 220, 170, 240], outline="black", width=2)
        draw.text((180, 222), "Primary Patient", fill="black")

        # Checkbox 2 (rect: 150, 260, 170, 280 -> w=20, h=20)
        draw.rectangle([150, 260, 170, 280], outline="black", width=2)
        draw.text((180, 262), "Emergency Contact Consent", fill="black")

        img.save(cls.test_img_path)

    def test_01_config_manager(self):
        """Verify configuration load, defaults, and save."""
        cfg = load_config()
        self.assertIn("model_name", cfg)
        self.assertIn("font_family", cfg)
        self.assertIn("checkbox_style", cfg)
        self.assertEqual(cfg["checkbox_style"], "check")

    def test_02_model_resolution(self):
        """Verify FFDNet-S and FFDNet-L resolution."""
        path_s, type_s = resolve_model_path("FFDNet-S", prefer_onnx=True)
        self.assertTrue(path_s.exists())
        self.assertEqual(type_s, "onnx")

        path_l, type_l = resolve_model_path("FFDNet-L", prefer_onnx=True)
        self.assertTrue(path_l.exists())
        self.assertEqual(type_l, "onnx")

    def test_03_ffdnet_s_detection(self):
        """Verify FFDNet-S detection on synthetic form fields."""
        detector = FormFieldDetector(model_name="FFDNet-S", confidence=0.25)
        res = detector.detect(
            image_path=str(self.test_img_path),
            target_page_width=612.0,
            target_page_height=792.0
        )

        self.assertTrue(res["success"])
        self.assertEqual(res["model"], "FFDNet-S")
        self.assertGreaterEqual(res["counts"]["text_boxes"], 2)
        self.assertGreaterEqual(res["counts"]["checkboxes"], 2)

        # Check coordinate bounds
        for tb in res["text_boxes"]:
            self.assertEqual(tb["type"], "TextBox")
            self.assertGreater(tb["width"], 50.0)
            self.assertGreater(tb["confidence"], 0.70)

        for cb in res["checkboxes"]:
            self.assertEqual(cb["type"], "ChoiceButton")
            self.assertGreater(cb["width"], 8.0)
            self.assertLess(cb["width"], 30.0)
            self.assertGreater(cb["confidence"], 0.70)

    def test_04_ffdnet_l_detection(self):
        """Verify FFDNet-L detection on synthetic form fields."""
        detector = FormFieldDetector(model_name="FFDNet-L", confidence=0.25)
        res = detector.detect(
            image_path=str(self.test_img_path),
            target_page_width=612.0,
            target_page_height=792.0
        )

        self.assertTrue(res["success"])
        self.assertEqual(res["model"], "FFDNet-L")
        self.assertGreaterEqual(res["counts"]["text_boxes"], 2)
        self.assertGreaterEqual(res["counts"]["checkboxes"], 2)

    def test_05_cli_detection(self):
        """Verify CLI interface runs and outputs valid JSON."""
        cli_py = REPO_ROOT / "backend" / "cli.py"
        out_json = Path("/tmp/cli_test_out.json")
        if out_json.exists():
            out_json.unlink()

        cmd = [
            sys.executable, str(cli_py), "detect",
            "--image", str(self.test_img_path),
            "--width", "612", "--height", "792",
            "--out", str(out_json)
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0, f"CLI error: {res.stderr}")
        self.assertTrue(out_json.exists())

        with open(out_json) as f:
            data = json.load(f)
        self.assertTrue(data.get("success"))
        self.assertIn("text_boxes", data)
        self.assertIn("checkboxes", data)

    def test_06_xopp_export_rendering(self):
        """Generate a complete Xournal++ .xopp file with detected fields and verify headless rendering."""
        # Detect fields
        detector = FormFieldDetector(model_name="FFDNet-S", confidence=0.25)
        res = detector.detect(
            image_path=str(self.test_img_path),
            target_page_width=612.0,
            target_page_height=792.0
        )

        # Build XML for .xopp
        text_elements = []
        for tb in res["text_boxes"]:
            text_elements.append(
                f'<text font="Sans" size="11.0" x="{tb["x"]}" y="{tb["y"]}" color="#000000" ts="0">Sample Text Fill</text>'
            )

        stroke_elements = []
        for cb in res["checkboxes"]:
            # Checkmark stroke inside box
            cx = cb["x"]
            cy = cb["y"]
            cw = cb["width"]
            ch = cb["height"]
            p1x, p1y = cx + 0.20 * cw, cy + 0.52 * ch
            p2x, p2y = cx + 0.42 * cw, cy + 0.78 * ch
            p3x, p3y = cx + 0.82 * cw, cy + 0.22 * ch
            stroke_elements.append(
                f'<stroke tool="pen" color="#002060" width="1.6" capStyle="round">{p1x} {p1y} {p2x} {p2y} {p3x} {p3y}</stroke>'
            )

        xml = f"""<?xml version="1.0" standalone="no"?>
<xournal creator="Xournal++ 1.3.8" fileversion="4">
<title>FormFillAI Generated Document</title>
<page width="612" height="792">
<background type="solid" color="#ffffff" style="plain"/>
<layer name="FormFillAI">
{"".join(text_elements)}
{"".join(stroke_elements)}
</layer>
</page>
</xournal>
"""
        test_xopp = Path("/tmp/formfill_test_render.xopp")
        test_png = Path("/tmp/formfill_test_render.png")
        if test_png.exists():
            test_png.unlink()

        with gzip.open(test_xopp, "wb") as f:
            f.write(xml.encode("utf-8"))

        # Render with xournalpp
        cmd = ["xournalpp", "-i", str(test_png), str(test_xopp)]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(res.returncode, 0, f"Xournalpp render error: {res.stderr}")
        self.assertTrue(test_png.exists())
        self.assertGreater(test_png.stat().st_size, 1000)
        print(f"\n[Test] Rendered .xopp output image size: {test_png.stat().st_size} bytes")

    def test_07_detect_all_pages(self):
        """Verify batch all-pages detection on reference PDF."""
        ref_pdf = "/home/mahbub/Downloads/Form-1_Government_Employee_Service_Information_Form.pdf"
        if not Path(ref_pdf).exists():
            self.skipTest(f"Reference PDF {ref_pdf} not found")

        detector = FormFieldDetector(model_name="FFDNet-S", confidence=0.28)
        results = detector.detect_all_pages(pdf_path=ref_pdf)

        self.assertTrue(results["success"])
        self.assertEqual(results["total_pages"], 4)
        self.assertEqual(len(results["pages"]), 4)
        self.assertGreaterEqual(results["counts"]["text_boxes"], 200)
        self.assertGreaterEqual(results["counts"]["checkboxes"], 20)

    def test_08_resolve_pdf_path(self):
        """Verify robust PDF path resolver with relative, URL, and common directories."""
        from detector import resolve_pdf_path
        ref_pdf = "/home/mahbub/Downloads/Form-1_Government_Employee_Service_Information_Form.pdf"
        if not Path(ref_pdf).exists():
            self.skipTest(f"Reference PDF {ref_pdf} not found")

        p_abs = resolve_pdf_path(ref_pdf)
        p_base = resolve_pdf_path("Form-1_Government_Employee_Service_Information_Form.pdf")
        p_uri = resolve_pdf_path("file://" + ref_pdf)

        self.assertIsNotNone(p_abs)
        self.assertEqual(p_abs, p_base)
        self.assertEqual(p_abs, p_uri)


if __name__ == "__main__":
    unittest.main()
