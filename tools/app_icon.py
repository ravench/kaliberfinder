#!/usr/bin/env python3
"""Draws the app icon (1024 px): two cartridges from the catalogue inside camera
viewfinder brackets, standing on a millimetre ruler.

    python3 tools/app_icon.py
"""
import json, os, re
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")
OUT = os.path.join(ROOT, "Kaliberfinder", "Resources", "Assets.xcassets", "AppIcon.appiconset")
S = 1024
SS = 4  # supersampling
BG, BRASS, COPPER, LINE, WHITE = (24, 38, 64), (227, 193, 111), (184, 115, 51), (40, 30, 20), (236, 240, 245)


def polygons(d):
    out, cur = [], []
    for cmd, x, y in re.findall(r"([MLZ])\s*(?:(-?[\d.]+)\s+(-?[\d.]+))?", d):
        if cmd == "M":
            cur = [(float(x), float(y))]
        elif cmd == "L":
            cur.append((float(x), float(y)))
        else:
            out.append(cur)
    return out


def draw_cartridge(draw, c, left, base, scale):
    o = c["outline"]
    top = base - o["height"] * scale
    for key, colour in (("case", BRASS), ("bullet", COPPER)):
        for poly in polygons(o.get(key, "")):
            pts = [(left + x * scale, top + y * scale) for x, y in poly]
            draw.polygon(pts, fill=colour, outline=LINE, width=int(2.5 * SS))
    return o["width"] * scale


def main():
    cartridges = {c["id"]: c for c in json.load(open(DATA))["cartridges"]}
    img = Image.new("RGB", (S * SS, S * SS), BG)
    d = ImageDraw.Draw(img)
    k = SS
    base = 760 * k
    scale = 7.2 * k  # px per mm
    # ruler
    d.line([(150 * k, base), (874 * k, base)], fill=WHITE, width=5 * k)
    for i in range(0, 101):
        x = 150 * k + i * scale
        if x > 874 * k:
            break
        h = 56 if i % 10 == 0 else (36 if i % 5 == 0 else 20)
        d.line([(x, base), (x, base + h * k)], fill=WHITE, width=(5 if i % 10 == 0 else 3) * k)
    # cartridges
    x = 400 * k
    w = draw_cartridge(d, cartridges[".308 Winchester"], x, base - 3 * k, scale)
    draw_cartridge(d, cartridges["9x19 mm"], x + w + 70 * k, base - 3 * k, scale)
    # viewfinder brackets
    m, L, t = 150 * k, 120 * k, 14 * k
    for cx, cy, sx, sy in ((m, m, 1, 1), (S * k - m, m, -1, 1), (m, 860 * k, 1, -1), (S * k - m, 860 * k, -1, -1)):
        d.line([(cx, cy), (cx + sx * L, cy)], fill=WHITE, width=t)
        d.line([(cx, cy), (cx, cy + sy * L)], fill=WHITE, width=t)
    img = img.resize((S, S), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, "AppIcon.png"))
    json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(OUT, "Contents.json"), "w"), indent=2)


if __name__ == "__main__":
    main()
