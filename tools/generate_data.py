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
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "calibre-data"))
from cartridges import CATALOGUE, COUNTRIES, DISPLAY_ALIASES, LOOKALIKES, is_obsolete, is_rare, origin, is_worldwide, PRIMERS, PRIMER_DIAMETERS, RIMFIRE, BALL, MINIE, PELLET, CRIMPED  # noqa: E402
from outline import outline, bullet_profile  # noqa: E402,F401  (bullet_profile re-exported for tests)
from headstamps import HEADSTAMPS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")
DATA = os.path.join(ROOT, "calibre-data")

# German names of the calibre-data COUNTRIES, the app's localization keys (en/fr/it in
# translations.py). Worldwide use is the separate "worldwide" flag, not a country (Raven 2026-11-07).
COUNTRY_NAMES = {
    "CH": "Schweiz", "DE": "Deutschland", "AH": "Österreich-Ungarn", "AT": "Österreich",
    "FR": "Frankreich", "IT": "Italien", "GB": "Grossbritannien", "US": "USA", "SE": "Schweden",
    "DK": "Dänemark", "BE": "Belgien", "ES": "Spanien", "PT": "Portugal", "CZ": "Tschechien",
    "JP": "Japan", "PL": "Polen", "FI": "Finnland", "PH": "Philippinen", "AR": "Argentinien",
    "RUE": "Russisches Kaiserreich", "SU": "Sowjetunion", "CS": "Tschechoslowakei", "CN": "China",
    "NATO": "NATO",
}
# Former states and unions without a flag emoji; the app draws these flags itself (DrawnFlag).
DRAWN_FLAGS = {"RUE", "AH", "SU", "CS", "NATO"}


def country(name):
    """{"code", "name" (German), "flag" (emoji, absent for drawn flags)} of the state or union that
    introduced the calibre (calibre-data ORIGIN), or {} for gauges, balls, pellets, blanks and calibres
    whose origin is still open."""
    o = origin(name)
    if not o:
        return {}
    code, _, flag = o
    assert code in COUNTRY_NAMES, f"{code}: add its German name to COUNTRY_NAMES"
    assert flag or code in DRAWN_FLAGS, f"{code} has no flag emoji: draw it in DrawnFlag"
    return {"country": {"code": code, "name": COUNTRY_NAMES[code], **({"flag": flag} if flag else {})}}


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
                               "rare": is_rare(s["name"]), **country(s["name"]),
                               "worldwide": is_worldwide(s["name"]),
                               "blank": s["profile"] == CRIMPED,
                               "dimensions": dimensions(s), "outline": outline(s),
                               **primer(s)})
    names = {c["name"] for c in cartridges}
    unknown = (set(DISPLAY_ALIASES) | set(HEADSTAMPS)) - names
    assert not unknown, f"aliases for unknown calibres: {unknown}"
    return cartridges


def lookalikes(names):
    """The lookalike groups (calibre-data LOOKALIKES): calibres of their own that look alike, the parent
    first, with what tells them apart ("rim", "bore", "length", "seating", "load", "ignition"). Raven,
    2026-11-08: the app shows every member's group and compares it at 1:1."""
    groups = [{"differs": list(differs), "calibres": list(members)} for differs, members in LOOKALIKES]
    unknown = {n for g in groups for n in g["calibres"]} - set(names)
    assert not unknown, f"lookalikes of unknown calibres: {unknown}"
    return groups


def calibre_data():
    """The calibre-data commit the catalogue is read from and its date, shown in the app's settings."""
    commit, date = subprocess.check_output(["git", "log", "-1", "--format=%H %cI"], cwd=DATA, text=True).split()
    # Newer git writes a UTC offset as "Z", older as "+00:00"; one spelling keeps the JSON the same.
    return {"commit": commit, "date": date.replace("Z", "+00:00")}


# Preview fills of cases that are not brass (CartridgeView uses the same colours).
CASE_COLOURS = {"copper": "#b87333", "steel": "#6b6a55", "nickel": "#c8cbce", "paper": "#f2ede0", "hybrid": "#e3c16f"}


def preview(cartridges, path):
    cells = []
    for c in cartridges:
        o = c["outline"]
        bullet = {"steel": "#a7adb4", "lead": "#8a8c91", "plastic": "#f7f7f5"}.get(o.get("bulletMaterial"), "#b87333")
        case = CASE_COLOURS.get(o.get("caseMaterial"), "#e3c16f")
        parts = "".join(f'<path d="{o[k]}" fill="{col}" stroke="#333" stroke-width="0.25"/>'
                        for k, col in (("case", case), ("head", "#a7adb4" if o.get("headMaterial") == "steel" else "#e3c16f"),
                                       ("bullet", bullet), ("patch", "#f2ede0"),
                                       ("tip", "#cc1a24" if o.get("tipMaterial") == "polymer" else "#8a8c91"))
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
        json.dump({"version": 1, "calibreData": calibre_data(), "cartridges": cartridges,
                   "lookalikes": lookalikes({c["name"] for c in cartridges})}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    if "--preview" in sys.argv:
        preview(cartridges, sys.argv[sys.argv.index("--preview") + 1])
    print(f"{len(cartridges)} cartridges")
