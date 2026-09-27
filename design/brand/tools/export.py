"""Renders the brand SVGs to design/brand/png/ and builds mac/Resources/AppIcon.icns.

    python3 -m venv /tmp/v && /tmp/v/bin/pip install resvg_py
    /tmp/v/bin/python design/brand/tools/export.py

resvg, not ImageMagick: ImageMagick's built-in SVG renderer drops nested transforms.
"""
import shutil
import subprocess
import tempfile
from pathlib import Path

import resvg_py

brand = Path(__file__).resolve().parents[1]
png = brand / "png"
png.mkdir(exist_ok=True)

def render(svg, out, width, height=None):
    data = resvg_py.svg_to_bytes(svg_path=str(brand / svg), width=width, height=height)
    Path(out).write_bytes(bytes(data))

# App icon (mark A) and site favicons
for size in (1024, 512, 256, 180, 32):
    render("ginga-app-icon.svg", png / f"ginga-app-icon-{size}.png", size)
# Marks and wordmark for the site
for name in ("ginga-orbit", "ginga-orbit-dark", "ginga-monogram", "ginga-monogram-dark"):
    render(f"{name}.svg", png / f"{name}-512.png", 512)
for name in ("ginga-wordmark", "ginga-wordmark-dark"):
    render(f"{name}.svg", png / f"{name}-1200.png", 1200)

# macOS .icns (iconutil ships with macOS)
with tempfile.TemporaryDirectory() as tmp:
    iconset = Path(tmp) / "AppIcon.iconset"
    iconset.mkdir()
    for points in (16, 32, 128, 256, 512):
        render("ginga-app-icon.svg", iconset / f"icon_{points}x{points}.png", points)
        render("ginga-app-icon.svg", iconset / f"icon_{points}x{points}@2x.png", points * 2)
    icns = brand.parents[1] / "mac" / "Resources" / "AppIcon.icns"
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
    print("wrote", icns)
print("wrote", png)
