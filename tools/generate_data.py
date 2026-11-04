#!/usr/bin/env python3
"""Generates Kaliberfinder/Resources/Cartridges.json from the calibre-data submodule.

    python3 tools/generate_data.py [--preview preview.html]

The catalogue (cartridges.py) and the outline drawing (outline.py) live in the shared
calibre-data repository (github.com/ravench/calibre-data), included at calibre-data/ and
also used by Schiesstagebuch and the calibre poster. Extra headstamp spellings for the
catalogue search live in tools/headstamps.py.

Each entry carries its dimensions in millimetres (for the 1:1 drawing and the
dimension table) and a side-view outline as SVG path data (M/L/Z only), tip at
the top (y = 0), base at the bottom (y = overall length).
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "calibre-data"))
from cartridges import CATALOGUE, DISPLAY_ALIASES, is_obsolete, PRIMERS, PRIMER_DIAMETERS, RIMFIRE, BALL, MINIE, PELLET  # noqa: E402
from outline import outline, bullet_profile  # noqa: E402,F401  (bullet_profile re-exported for tests)
from headstamps import HEADSTAMPS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")

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
                               "headstamps": HEADSTAMPS.get(s["name"], []), "obsolete": is_obsolete(s["name"]),
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
        bullet = "#a7adb4" if o.get("bulletMaterial") == "steel" else "#b87333"
        parts = "".join(f'<path d="{o[k]}" fill="{col}" stroke="#333" stroke-width="0.25"/>'
                        for k, col in (("case", "#e3c16f"), ("head", "#e3c16f"), ("bullet", bullet), ("patch", "#f2ede0"))
                        if k in o)
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
