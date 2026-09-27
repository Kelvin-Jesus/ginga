"""Regenerates design/brand/ginga-wordmark*.svg: "ginga" in Unbounded ExtraBold (SIL OFL 1.1),
outlined to paths, with the dot of the i replaced by the tilted tablet.

    python3 -m venv /tmp/v && /tmp/v/bin/pip install fonttools
    curl -L -o /tmp/Unbounded.ttf "https://github.com/google/fonts/raw/main/ofl/unbounded/Unbounded%5Bwght%5D.ttf"
    /tmp/v/bin/python design/brand/tools/wordmark.py /tmp/Unbounded.ttf
"""
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

TEXT = ["g", "dotlessi", "n", "g", "a"]
TRACKING = 24             # +0.024 em: at ExtraBold, anything tighter makes g and ı touch
DOT = dict(w=300, h=212, rx=52, cy=770, angle=-12)  # font units
PAD = 40

font = instantiateVariableFont(TTFont(sys.argv[1]), {"wght": 800})
glyphs, hmtx = font.getGlyphSet(), font["hmtx"]

paths, x, dot_cx = [], 0, None
for name in TEXT:
    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.0f}")
    glyphs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))  # flip y: SVG grows down
    paths.append(pen.getCommands())
    advance = hmtx[name][0]
    if name == "dotlessi":
        dot_cx = x + advance / 2
    x += advance + TRACKING

width = x - TRACKING
top, bottom = -1000, 260  # above the dot, below the descender of g
view = f"{-PAD} {top - PAD} {width + 2 * PAD:.0f} {bottom - top + 2 * PAD}"

def svg(ink, accent):
    d = DOT
    rect = (f'<rect x="{dot_cx - d["w"] / 2:.1f}" y="{-d["cy"] - d["h"] / 2:.1f}" width="{d["w"]}" '
            f'height="{d["h"]}" rx="{d["rx"]}" fill="{accent}" '
            f'transform="rotate({d["angle"]} {dot_cx:.1f} {-d["cy"]})"/>')
    body = "".join(f'<path d="{p}"/>' for p in paths)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" role="img" aria-label="Ginga">'
            f'<g fill="{ink}">{body}</g>{rect}</svg>\n')

out = Path(__file__).resolve().parents[1]
(out / "ginga-wordmark.svg").write_text(svg("#141830", "#2E47F5"))
(out / "ginga-wordmark-dark.svg").write_text(svg("#FFFFFF", "#6F82FF"))
print("wrote", out / "ginga-wordmark.svg", out / "ginga-wordmark-dark.svg")
