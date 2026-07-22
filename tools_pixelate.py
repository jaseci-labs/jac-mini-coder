#!/usr/bin/env python3
"""Pixelate an image (or a PDF page) into a mascot grid for mascot.jac.

Prints a `glob NAME: list[str]` block ready to paste, and optionally a preview
PNG. The terminal folds two pixel rows into one row of half-blocks, so --height
is PIXEL rows: a 9-row banner needs --height 18.

    python3 tools_pixelate.py sticker.png --width 52 --height 30 --name NINJA_E
    python3 tools_pixelate.py art.pdf --crop 324,175,2330,1310 --preview out.png

Pipeline, in order — each step exists because the naive version failed:
  flood-fill  the outside white goes transparent while interior whites (eye
              highlights, logo negative space) survive
  HSV roles   skin and jaseci orange share a hue and differ only in saturation
              (~0.30 vs ~0.86); a nearest-RGB snap turns the whole face orange
  majority    per cell, not an average: averaging blends the zeroed background
              into every edge pixel and smears the palette
  denoise     lone pixels dropped; fine details shatter into confetti
  relief      line art on white separates via dark outlines on a light ground.
              On a dark terminal that collapses to one blob, so the interior of
              a dark region is lit and its boundary kept charcoal.
"""
import argparse, colorsys, re, subprocess, sys, tempfile
from collections import Counter, deque
from pathlib import Path

PALETTE = {
    'K': (0x4a, 0x4a, 0x4a),   # outline / dark boundary
    'G': (0x6b, 0x6b, 0x73),   # lit interior of a dark region (relief)
    'O': (0xf2, 0x6b, 0x21),   # jaseci orange
    'o': (0xf9, 0x97, 0x1e),   # highlight orange
    'S': (0xf6, 0xd7, 0xb0),   # skin
    'W': (0xfa, 0xfa, 0xfa),   # eye white / emblem
    'B': (0x11, 0x11, 0x11),   # pupil
}

def load(path, dpi):
    from PIL import Image
    p = Path(path)
    if p.suffix.lower() == '.pdf':
        out = Path(tempfile.mkdtemp()) / 'page'
        subprocess.run(['pdftoppm', '-r', str(dpi), '-png', '-singlefile',
                        str(p), str(out)], check=True)
        return Image.open(str(out) + '.png').convert('RGB')
    if p.suffix.lower() == '.svg':
        return _svg(p.read_text())
    return Image.open(p).convert('RGB')

def _svg(text):
    from PIL import Image, ImageDraw
    m = re.search(r'viewBox="0 0 (\d+) (\d+)"', text)
    rects = re.findall(r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" '
                       r'fill="(#[0-9a-fA-F]{6})"', text)
    if not (m and rects):
        sys.exit("only the flat <rect> SVG form is supported; export a PNG")
    img = Image.new('RGB', (int(m.group(1)), int(m.group(2))), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for x, y, w, h, f in rects:
        d.rectangle([int(x), int(y), int(x)+int(w)-1, int(y)+int(h)-1], fill=f)
    return img

def cut_background(img):
    rgba = img.convert('RGBA'); px = rgba.load(); W, H = rgba.size
    lit = lambda p: p[0] > 225 and p[1] > 215 and p[2] > 215
    seen = [[False]*W for _ in range(H)]; q = deque()
    for x in range(W):
        for y in (0, H-1):
            if lit(px[x, y]): q.append((x, y)); seen[y][x] = True
    for y in range(H):
        for x in (0, W-1):
            if lit(px[x, y]): q.append((x, y)); seen[y][x] = True
    while q:
        x, y = q.popleft(); px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx, ny = x+dx, y+dy
            if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and lit(px[nx, ny]):
                seen[ny][nx] = True; q.append((nx, ny))
    return rgba

def role(p):
    r, g, b, a = p
    if a < 128: return '.'
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    if v < 0.42: return 'K'
    if s < 0.12: return 'W' if v > 0.80 else 'K'
    if 0.02 <= h <= 0.13:
        if s < 0.50: return 'S'
        return 'o' if v > 0.93 and s < 0.75 else 'O'
    return 'K'

def to_grid(rgba, w, h, bg_cut):
    px = rgba.load(); W, H = rgba.size
    cw, ch = W/w, H/h; rows = []
    for gy in range(h):
        row = ''
        for gx in range(w):
            c = Counter()
            x0, x1 = int(gx*cw), max(int(gx*cw)+1, int((gx+1)*cw))
            y0, y1 = int(gy*ch), max(int(gy*ch)+1, int((gy+1)*ch))
            sx, sy = max(1, (x1-x0)//14), max(1, (y1-y0)//14)
            for yy in range(y0, y1, sy):
                for xx in range(x0, x1, sx):
                    c[role(px[xx, yy])] += 1
            tot = sum(c.values()); blank = c.get('.', 0)
            if tot == 0 or blank/tot >= bg_cut:
                row += '.'
            else:
                del c['.']; row += c.most_common(1)[0][0]
        rows.append(row)
    return rows

def denoise(g):
    h, w = len(g), len(g[0]); out = [list(r) for r in g]
    for y in range(h):
        for x in range(w):
            if g[y][x] == '.': continue
            if not any(0 <= x+dx < w and 0 <= y+dy < h and g[y+dy][x+dx] != '.'
                       for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))):
                out[y][x] = '.'
    return [''.join(r) for r in out]

def relief(g):
    h, w = len(g), len(g[0]); out = [list(r) for r in g]
    for y in range(h):
        for x in range(w):
            if g[y][x] != 'K': continue
            edge = any(not (0 <= x+dx < w and 0 <= y+dy < h) or g[y+dy][x+dx] != 'K'
                       for dx, dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)))
            if not edge: out[y][x] = 'G'
    return [''.join(r) for r in out]

def preview(g, path, scale=18):
    from PIL import Image, ImageDraw
    img = Image.new('RGB', (len(g[0])*scale, len(g)*scale), (24, 24, 27))
    d = ImageDraw.Draw(img)
    for y, row in enumerate(g):
        for x, ch in enumerate(row):
            if ch in PALETTE:
                d.rectangle([x*scale, y*scale, (x+1)*scale-1, (y+1)*scale-1],
                            fill=PALETTE[ch])
    img.save(path)

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('image')
    ap.add_argument('--width', type=int, default=52)
    ap.add_argument('--height', type=int, default=30, help='PIXEL rows (half the terminal rows)')
    ap.add_argument('--name', default='NINJA_E')
    ap.add_argument('--crop', help='x0,y0,x1,y1 in source pixels')
    ap.add_argument('--dpi', type=int, default=1200, help='PDF rasterisation dpi')
    ap.add_argument('--bg-cut', type=float, default=0.55)
    ap.add_argument('--preview')
    ap.add_argument('--no-relief', action='store_true')
    a = ap.parse_args()

    img = load(a.image, a.dpi)
    if a.crop:
        img = img.crop(tuple(int(v) for v in a.crop.split(',')))
    g = denoise(to_grid(cut_background(img), a.width, a.height, a.bg_cut))
    if not a.no_relief:
        g = relief(g)
    if a.preview:
        preview(g, a.preview); print(f'preview -> {a.preview}', file=sys.stderr)
    print(f'glob {a.name}: list[str] = [')
    print(',\n'.join(f'    "{r}"' for r in g))
    print('];')

if __name__ == '__main__':
    main()
