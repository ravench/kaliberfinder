#!/usr/bin/env python3
"""App icons: three cartridges side by side (.22 LR, 9x19 mm, 7.5x55 Swiss GP 11),
drawn from the catalogue outlines at the same scale. The default look borrows
from the iOS Measure app: a dotted measuring line with round handles on a beige
(dark mode: navy, tinted: black) background. --navy gives the Schiesstagebuch look instead.

    python3 tools/app_icon.py [--ruler] [--navy] [OUT_DIR]

Writes AppIcon{,-Dark,-Tinted}.svg (1024x1024) to OUT_DIR (default: the asset
catalogue) and renders PNGs next to them with the preinstalled Playwright
Chromium (node). No ruler by default (the measuring line already says "measure");
--ruler adds a cream mm ruler with a red zero mark under the cartridges.
"""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")
ASSETS = os.path.join(ROOT, "Kaliberfinder", "Resources", "Assets.xcassets", "AppIcon.appiconset")
S = 1024
CARTRIDGES = [".22 LR", "9x19 mm", "7.5x55 mm Swiss (GP 11)"]
SCALE = 8.6       # px per mm
GAP = 66          # px between cartridges

BRASS = dict(brass="#E3C16F", brass_hi="#F3DC9C", copper="#C0743A", copper_hi="#DE9A62", line="#3A2A12")
TINT = dict(brass="#C8C8C8", brass_hi="#E6E6E6", copper="#8C8C8C", copper_hi="#A8A8A8", line="#000000")

# Backgrounds: beige in light mode, navy in dark mode, black for tinted (grayscale).
BEIGE = ("#F1E6D2", "#DCC9A8")
NAVY_BG = ("#2B3A55", "#18233A")
BLACK = ("#000000", "#000000")

# Measure-app look: dotted measuring line with round handles (navy on beige, white on navy).
MEASURE = {
    "": dict(BRASS, bg=BEIGE, ruler="#F4F1E8", tick="#141414", zero="#D52B1E", measure="#2B3A55"),
    "-Dark": dict(BRASS, bg=NAVY_BG, ruler="#F4F1E8", tick="#141414", zero="#D52B1E", measure="#FFFFFF"),
    # Tinted: grayscale on black; iOS maps luminance onto the user's tint colour.
    "-Tinted": dict(TINT, bg=BLACK, ruler="#D0D0D0", tick="#000000", zero="#FFFFFF", measure="#FFFFFF"),
}

# Schiesstagebuch look: navy, cream ruler with a red zero mark.
NAVY = {
    "": dict(BRASS, bg=("#2B3A55", "#18233A"), ruler="#F4F1E8", tick="#141414", zero="#D52B1E", shadow="#0B1222"),
    "-Dark": dict(BRASS, bg=("#1E1B1A", "#0B0A0A"), brass="#C9A85A", brass_hi="#DCC07A", copper="#A8622F",
                  copper_hi="#C47E4C", line="#000000", ruler="#D9D5CA", tick="#0D0D0D", zero="#FF5A45",
                  shadow="#000000"),
    "-Tinted": dict(TINT, bg=("#000000", "#000000"), ruler="#D0D0D0", tick="#000000", zero="#FFFFFF",
                    shadow="#000000"),
}


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


def path(polys, left, top):
    return " ".join("M" + " L".join(f"{left + x * SCALE:.1f} {top + y * SCALE:.1f}" for x, y in p) + " Z" for p in polys)


def cartridge(c, left, base, p, uid):
    """Side view standing on `base`, with a soft highlight down the left third (clipped to the outline)."""
    o = c["outline"]
    top = base - o["height"] * SCALE
    w = o["width"] * SCALE
    out = []
    for key, fill, hi in (("case", p["brass"], p["brass_hi"]), ("bullet", p["copper"], p["copper_hi"])):
        if key not in o:
            continue
        d = path(polygons(o[key]), left, top)
        cid = f"c{uid}{key}"
        out.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>'
                   f'<path d="{d}" fill="{fill}"/>'
                   f'<rect x="{left + w * 0.18:.1f}" y="{top:.1f}" width="{w * 0.16:.1f}" height="{o["height"] * SCALE:.1f}" '
                   f'fill="{hi}" opacity="0.8" clip-path="url(#{cid})"/>'
                   f'<path d="{d}" fill="none" stroke="{p["line"]}" stroke-width="3" stroke-linejoin="round"/>')
    return "".join(out), w


def measuring_line(x, top, bottom, colour):
    """Measure-app style: dotted white line between two round handles."""
    return (f'<line x1="{x:.1f}" y1="{top:.1f}" x2="{x:.1f}" y2="{bottom:.1f}" stroke="{colour}" stroke-width="7" '
            f'stroke-linecap="round" stroke-dasharray="0.1 20"/>'
            f'<circle cx="{x:.1f}" cy="{top:.1f}" r="15" fill="{colour}"/>'
            f'<circle cx="{x:.1f}" cy="{bottom:.1f}" r="15" fill="{colour}"/>')


def icon(cartridges, p, ruler=False):
    widths = [c["outline"]["width"] * SCALE for c in cartridges]
    total = sum(widths) + GAP * (len(cartridges) - 1)
    extra = 90 if "measure" in p else 0   # room for the measuring line on the right
    tallest = max(c["outline"]["height"] for c in cartridges) * SCALE
    base = 790 if ruler else round((S + tallest) / 2)   # without ruler: centred vertically
    x = (S - total - extra) / 2
    centre = x + total / 2
    body = []
    if "shadow" in p:   # contact shadow: only the --navy look has one
        body.append(f'<ellipse cx="{centre:.1f}" cy="{base + 4}" rx="{total / 2 + 60:.0f}" ry="16" fill="{p["shadow"]}" opacity="0.45"/>')
    for i, c in enumerate(cartridges):
        part, w = cartridge(c, x, base, p, i)
        body.append(part)
        x += w + GAP
    if "measure" in p:
        body.append(measuring_line(x - GAP + 70, base - tallest, base, p["measure"]))
    if ruler:
        left, right, top = 150, 874, base + 22
        body.append(f'<rect x="{left}" y="{top}" width="{right - left}" height="96" rx="14" fill="{p["ruler"]}"/>')
        mm = 0
        while left + 24 + mm * SCALE <= right - 20:
            tx = left + 24 + mm * SCALE
            h = 46 if mm % 10 == 0 else (32 if mm % 5 == 0 else 20)
            col = p["zero"] if mm == 0 else p["tick"]
            body.append(f'<rect x="{tx - 2:.1f}" y="{top}" width="{6 if mm % 10 == 0 else 4}" height="{h}" fill="{col}"/>')
            mm += 1
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">'
            f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{p["bg"][0]}"/>'
            f'<stop offset="1" stop-color="{p["bg"][1]}"/></linearGradient></defs>'
            f'<rect width="{S}" height="{S}" fill="url(#bg)"/>{"".join(body)}</svg>')


RENDER = """
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 } });
  for (const svg of process.argv.slice(1)) {
    await page.goto('file://' + svg);
    await page.screenshot({ path: svg.replace(/\\.svg$/, '.png') });
  }
  await browser.close();
})();
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ruler = "--ruler" in sys.argv
    palettes = NAVY if "--navy" in sys.argv else MEASURE
    out = os.path.abspath(args[0]) if args else ASSETS
    os.makedirs(out, exist_ok=True)
    by_id = {c["id"]: c for c in json.load(open(DATA))["cartridges"]}
    cartridges = [by_id[i] for i in CARTRIDGES]
    svgs = []
    for suffix, p in palettes.items():
        path_ = os.path.join(out, f"AppIcon{suffix}.svg")
        with open(path_, "w") as f:
            f.write(icon(cartridges, p, ruler))
        svgs.append(path_)
    subprocess.run(["node", "-e", RENDER, *svgs], check=True)
    if out == ASSETS:
        for s in svgs:
            os.remove(s)  # the asset catalogue only holds the PNGs


if __name__ == "__main__":
    main()
