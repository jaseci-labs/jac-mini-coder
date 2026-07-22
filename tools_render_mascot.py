#!/usr/bin/env python3
"""Render the mascot grids from mascot.jac to assets/ (SVG + PNG).

mascot.jac is the single source of truth: the TUI folds each grid into
half-blocks, this script emits the same pixels for the README and for
eyeballing variants. Re-run after editing any NINJA_* grid.

    python3 tools_render_mascot.py
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).parent
SRC = (ROOT / "mascot.jac").read_text()
PAL = {'K': '#4a4a4a', 'O': '#f26b21', 'o': '#f9971e',
       'S': '#f6d7b0', 'W': '#fafafa', 'B': '#111111'}
BG = '#18181b'

def grid(name):
    m = re.search(r'glob ' + name + r': list\[str\] = \[(.*?)\];', SRC, re.S)
    if not m:
        sys.exit("grid not found: " + name)
    return re.findall(r'"([^"]*)"', m.group(1))

def trim(g):
    while g and set(g[-1]) == {'.'}:
        g = g[:-1]
    return g

def svg(g, scale=16, pad=1):
    w, h = len(g[0]) + pad * 2, len(g) + pad * 2
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w*scale}" height="{h*scale}" '
           f'viewBox="0 0 {w} {h}" shape-rendering="crispEdges">']
    for y, row in enumerate(g):
        for x, ch in enumerate(row):
            if ch in PAL:
                out.append(f'<rect x="{x+pad}" y="{y+pad}" width="1" height="1" fill="{PAL[ch]}"/>')
    out.append('</svg>')
    return "\n".join(out)

def png(grids, labels, path, scale=18, gap=3, pad=2):
    from PIL import Image, ImageDraw
    rgb = lambda h: tuple(int(h[i:i+2], 16) for i in (1, 3, 5))
    w = sum(len(g[0]) for g in grids) + gap * (len(grids) - 1) + pad * 2
    h = max(len(g) for g in grids) + pad * 2 + 2
    img = Image.new('RGB', (w * scale, h * scale), rgb(BG))
    d = ImageDraw.Draw(img)
    xo = pad
    for g, lb in zip(grids, labels):
        for y, row in enumerate(g):
            for x, ch in enumerate(row):
                if ch in PAL:
                    d.rectangle([(xo+x)*scale, (y+pad)*scale,
                                 (xo+x+1)*scale-1, (y+pad+1)*scale-1], fill=rgb(PAL[ch]))
        d.text((xo*scale, (len(g)+pad+1)*scale), lb, fill=(160, 160, 165))
        xo += len(g[0]) + gap
    img.save(path)
    return img.size

names = ['NINJA_A', 'NINJA_B', 'NINJA_C', 'NINJA_D']
labels = ['a  ninja + katana (default)', 'b  level throw', 'c  overhead throw',
          'd  original head']
grids = [trim(grid(n)) for n in names]

(ROOT / "assets").mkdir(exist_ok=True)
if "--svg" in sys.argv:
    (ROOT / "assets" / "mascot.svg").write_text(svg(grids[0]))
    print("wrote assets/mascot.svg")
size = png(grids, labels, ROOT / "assets" / "mascot-variants.png")
print("wrote assets/mascot-variants.png", size)
