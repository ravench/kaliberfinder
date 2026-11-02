#!/usr/bin/env python3
"""Generates Kaliberfinder/Resources/Cartridges.json from tools/cartridges.py.

    python3 tools/generate_data.py [--preview preview.html]

tools/cartridges.py is a verbatim copy of the Schiesstagebuch catalogue
(github.com/ravench/schiesstagebuch); edit it there and copy it over, so both
apps keep the same data. Extra headstamp spellings for the photo matcher live
in tools/headstamps.py.

Each entry carries its dimensions in millimetres (for the 1:1 drawing and the
dimension table) and a side-view outline as SVG path data (M/L/Z only), tip at
the top (y = 0), base at the bottom (y = overall length).
"""
import json, math, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from cartridges import CATALOGUE, DISPLAY_ALIASES, PRIMERS, PRIMER_DIAMETERS, RIMLESS, RIMMED, BELTED, RIMFIRE, SHOT, BALL, MINIE, PELLET, SPITZER, ROUND, FLAT
from headstamps import HEADSTAMPS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")

N = 14  # samples per curve


def case_profile(s):
    """Right half of the case, bottom to top, as (radius, height)."""
    rim, base, case = s["rim"] / 2, s["base"] / 2, s["case"]
    k = s["kind"]
    if k in (RIMMED, RIMFIRE):
        h = 1.1 if k == RIMFIRE else 1.5
        pts = [(rim, 0), (rim, h), (base, h)]
    else:
        groove = base * 0.82
        pts = [(rim, 0), (rim, 1.3), (groove, 1.3), (groove, 2.6), (base, 3.3)]
        if k == BELTED:
            pts[-1] = (rim, 3.3)
            pts += [(rim, 6.2), (base * 0.985, 6.2)]
    top = s["neck"] / 2
    if s["shoulder"]:
        sh = s["shoulder"] / 2
        run = max(0.8, (sh - top) / math.tan(math.radians(32)))
        sh_at = min(s["sh_at"], case - run - 1.2)
        pts += [(sh, sh_at), (top, sh_at + run), (top, case)]
    else:
        pts += [(top, case)]
    return pts


def bullet_profile(r, y0, top, profile):
    """Right half of the exposed bullet from (r, y0) to the tip at `top`."""
    e = top - y0
    if profile == SPITZER:
        cyl, tip, f = 0.32, 0.05, lambda t: (1 - t ** 1.7) ** 0.8
    elif profile == ROUND:
        cyl, tip, f = 0.22, 0.16, lambda t: math.sqrt(max(0, 1 - t * t))
    else:
        cyl, tip, f = 0.30, 0.55, lambda t: math.sqrt(max(0, 1 - t * t))
    start = y0 + cyl * e
    pts = [(r, y0), (r, start)]
    for i in range(1, N + 1):
        t = i / N
        pts.append((max(r * tip, r * f(t)), start + t * (top - start)))
    if pts[-1][0] > 0.001:
        pts.append((0, top))
    return pts


def mirror(right):
    """Closed polygon from a right half profile (x >= 0)."""
    left = [(-x, y) for x, y in reversed(right) if x > 0.0001]
    return right + left


def to_path(poly, height, half_width):
    d = []
    for i, (x, y) in enumerate(poly):
        d.append(f"{'M' if i == 0 else 'L'}{x + half_width:.2f} {height - y:.2f}")
    return " ".join(d) + " Z"


def outline(s):
    k = s["kind"]
    width = max(s["rim"], s["base"], s["bullet"])
    hw = width / 2
    H = s["oal"]
    paths = {}
    if k == SHOT:
        r, rim, L = s["base"] / 2, s["rim"] / 2, s["case"]
        head = 0.2 * L
        hull = [(r * 0.98, 1.5), (r * 0.98, L - 2.2), (r * 0.8, L - 0.6), (r * 0.35, L)]
        paths["case"] = to_path(mirror(hull), H, hw)
        paths["head"] = to_path(mirror([(rim, 0), (rim, 1.5), (r, 1.5), (r, head)]), H, hw)
    elif k == BALL:
        r = s["bullet"] / 2
        circ = [(r * math.sin(math.pi * i / (2 * N)), r - r * math.cos(math.pi * i / (2 * N))) for i in range(0, 2 * N + 1)]
        circ[0] = (0.0001, 0)
        paths["bullet"] = to_path(mirror(circ), H, hw)
    elif k == MINIE:
        r, L = s["bullet"] / 2, s["oal"]
        right = [(r * 0.94, 0), (r, 1.0)] + bullet_profile(r, 0.45 * L, L, ROUND)[0:]
        paths["bullet"] = to_path(mirror(right), H, hw)
    elif k == PELLET:
        r, L = s["bullet"] / 2, s["oal"]
        right = [(r, 0), (r * 0.9, 0.18 * L), (r * 0.6, 0.5 * L), (r * 0.62, 0.58 * L), (r, 0.66 * L)]
        right += [(max(0.15 * r, r * math.cos(math.pi / 2 * i / N)), 0.66 * L + 0.34 * L * math.sin(math.pi / 2 * i / N)) for i in range(1, N + 1)]
        right.append((0, L))
        paths["bullet"] = to_path(mirror(right), H, hw)
    else:
        prof = case_profile(s)
        paths["case"] = to_path(mirror(prof), H, hw)
        if s["oal"] > s["case"] + 0.1:
            paths["bullet"] = to_path(mirror(bullet_profile(s["bullet"] / 2, s["case"], s["oal"], s["profile"])), H, hw)
    return {"width": round(width, 2), "height": round(H, 2), **paths}


def dimensions(s):
    """Dimensions as shown in the app. Shoulder only for bottleneck cases."""
    d = {"rim": s["rim"], "base": s["base"], "neck": s["neck"], "caseLength": s["case"],
         "overallLength": s["oal"], "bullet": s["bullet"]}
    if s["shoulder"]:
        d["shoulder"] = s["shoulder"]
    return d


def primer(s):
    """Primer type and diameter; none for rimfire and for balls, Minié bullets and pellets."""
    if s["kind"] in (RIMFIRE, BALL, MINIE, PELLET):
        assert s["name"] not in PRIMERS, f"{s['name']} has no primer"
        return {}
    kind = PRIMERS[s["name"]]  # every centrefire calibre needs one
    return {"primer": {"type": kind, "diameter": PRIMER_DIAMETERS[kind]}}


def build():
    cartridges = []
    for category, items in CATALOGUE:
        for s in items:
            cartridges.append({"id": s["name"], "name": s["name"], "category": category, "kind": s["kind"],
                               "aliases": s["aliases"], "displayAliases": DISPLAY_ALIASES.get(s["name"], []),
                               "headstamps": HEADSTAMPS.get(s["name"], []),
                               "dimensions": dimensions(s), "outline": outline(s),
                               **primer(s)})
    names = {c["name"] for c in cartridges}
    unknown = (set(DISPLAY_ALIASES) | set(HEADSTAMPS)) - names
    assert not unknown, f"aliases for unknown calibres: {unknown}"
    return cartridges


def preview(cartridges, path):
    cells = []
    for c in cartridges:
        o = c["outline"]
        parts = "".join(f'<path d="{o[k]}" fill="{col}" stroke="#333" stroke-width="0.25"/>'
                        for k, col in (("case", "#e3c16f"), ("head", "#e3c16f"), ("bullet", "#b87333")) if k in o)
        cells.append(f'<div class=c><svg width="{o["width"] * 3}" height="{o["height"] * 3}" '
                     f'viewBox="0 0 {o["width"]} {o["height"]}">{parts}</svg><span>{c["name"]}</span></div>')
    open(path, "w").write("<!doctype html><meta charset=utf-8><style>body{font:11px sans-serif}"
                          ".g{display:flex;flex-wrap:wrap;align-items:flex-end;gap:10px}"
                          ".c{display:flex;flex-direction:column;align-items:center;width:90px}</style>"
                          f"<div class=g>{''.join(cells)}</div>")


if __name__ == "__main__":
    cartridges = build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump({"version": 1, "cartridges": cartridges}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    if "--preview" in sys.argv:
        preview(cartridges, sys.argv[sys.argv.index("--preview") + 1])
    print(f"{len(cartridges)} cartridges")
