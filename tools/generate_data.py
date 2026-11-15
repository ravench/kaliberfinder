#!/usr/bin/env python3
"""Generates Kaliberfinder/Resources/Cartridges.json from the calibre-data submodule.

    python3 tools/generate_data.py [--preview preview.html]

The catalogue (cartridges.py) and the outline drawing (outline.py) live in the shared
calibre-data repository (github.com/ravench/calibre-data), included at calibre-data/ and
also used by Schiesstagebuch and the calibre poster.

Each entry carries its dimensions in millimetres (for the 1:1 drawing and the
dimension table) and a side-view outline as SVG path data (M/L/Z only), tip at
the top (y = 0), base at the bottom (y = overall length).
"""
import json, os, re, subprocess, sys
from urllib.parse import unquote

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "calibre-data"))
from cartridges import CATALOGUE, BOOKS, BOOK_SOURCE, sources as table_sources, COUNTRIES, DISPLAY_ALIASES, LOOKALIKES, LOOKALIKE_NAMES, COLOUR_CODES, COUNTRY_NAMES as NAMES, is_obsolete, is_rare, origin, is_worldwide, PRIMERS, PRIMER_MM, RIMFIRE, SHOT, LOOSE, BALL, MINIE, PELLET, is_blank  # noqa: E402
from outline import outline, bullet_profile, well_sourced  # noqa: E402,F401  (bullet_profile re-exported for tests)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")
DATA = os.path.join(ROOT, "calibre-data")

# German names of the calibre-data COUNTRIES, the app's localization keys; the English, French and
# Italian names come from calibre-data too (localize.py). Worldwide use is the separate "worldwide"
# flag, not a country (Raven 2026-11-07).
COUNTRY_NAMES = {code: names["de"] for code, names in NAMES.items()}
# Former states and unions without a flag emoji; the app draws these flags itself (DrawnFlag).
DRAWN_FLAGS = {"RUE", "AH", "SU", "CS", "OE", "NATO"}


def country(name):
    """{"code", "name" (German), "flag" (emoji, absent for drawn flags)} of the state or union that
    introduced the calibre (calibre-data ORIGIN), or {} for gauges, balls, pellets, blanks and calibres
    whose origin is still open."""
    o = origin(name)
    return {"country": country_entry(o[0])} if o else {}


def country_entry(code):
    """{"code", "name" (German), "flag" (emoji, absent for drawn flags)} of a calibre-data country code."""
    flag = COUNTRIES[code][1]
    assert code in COUNTRY_NAMES, f"{code}: add its German name to COUNTRY_NAMES"
    assert flag or code in DRAWN_FLAGS, f"{code} has no flag emoji: draw it in DrawnFlag"
    return {"code": code, "name": COUNTRY_NAMES[code], **({"flag": flag} if flag else {})}


def colour_codes(name):
    """What the painted bullet tips, cartridge bases and primer annuli of a calibre's military loads mean
    (calibre-data COLOUR_CODES): the part ("tip", "base" or "annulus"), the colours (a tip's from the tip
    down), the meanings, the loads and the countries, as the calibre page lists them (Raven, 2026-11-11).
    The sources stay in calibre-data."""
    return [{"part": t["part"], "colours": list(t["colours"]), "meaning": list(t["meaning"]),
             **({"description": t["description"]} if t["description"] else {}),
             "countries": [country_entry(c) for c in t["countries"]]} for t in COLOUR_CODES.get(name, [])]


# The parts of a calibre's sources page, in the calibre page's order: calibre-data's table (or "colour_codes",
# the sources of all its [[colour_codes]]). The app titles each part (SourcesView); parts the calibre page
# does not show (the year, the firearms, today's case materials) are left out.
SOURCE_PARTS = ("mm", "shoulder_angle", "case_head", "primer", "bullet", "case", "origin", "colour_codes")
# Web sources named after their publisher rather than their host.
SITE_TITLES = {"bobp.cip-bobp.org": "C.I.P.", "bobp.expert-it.com": "C.I.P.", "saami.org": "SAAMI",
               "commons.wikimedia.org": "Wikimedia Commons", "web.archive.org": "Internet Archive"}


def work(source):
    """(the work a source names, its page or None): a book of books.toml with its page, a web page, or a
    caliper measurement with its date. A work is {"title", "detail"?, "year"?, "url"?}, or {"measured": date}
    for a measurement, which the app titles itself."""
    if m := BOOK_SOURCE.fullmatch(source):
        b = BOOKS[m["id"]]
        return {"title": b["title"], **({"detail": by} if (by := b.get("authors") or b.get("editors")) else {}),
                "year": b["year"]}, m["page"]
    if m := re.fullmatch(r"measured:\S+ (\d{4}-\d\d-\d\d)", source):  # a caliper reading, calibre-data README
        return {"measured": m[1]}, None
    host = re.match(r"https?://([^/]+)", source)
    assert host, f"unknown source {source!r}"
    host = host[1].removeprefix("www.")
    if host == "en.wikipedia.org" and "/wiki/" in source:
        title = "Wikipedia: " + unquote(source.split("/wiki/", 1)[1]).replace("_", " ")
    else:
        title = SITE_TITLES.get(host, host)
    detail = (f"Tab. {t[1].upper()}" if host.startswith("bobp.") and (t := re.search(r"/tab-([ivx]+)/", source))
              else host)
    return {"title": title, **({"detail": detail} if detail != title else {}), "url": source}, None


def source_groups(s, works):
    """A calibre's sources for its sources page: [{"parts": [...], "refs": [{"work": index, "pages"?: [...]}]}],
    the parts in SOURCE_PARTS order, parts citing the same works on the same pages merged into one group, a
    book cited on several pages one ref. `works` is the catalogue's list of works, extended in place."""
    name = s["name"]
    shown = {"origin": bool(country(name)), "primer": bool(primer(s)), "colour_codes": bool(COLOUR_CODES.get(name))}
    groups = []
    for part in SOURCE_PARTS:
        if not shown.get(part, True):
            continue
        cited = ([x for t in COLOUR_CODES.get(name, []) for x in t["sources"]] if part == "colour_codes"
                 else table_sources(name, part))
        refs = {}
        for source in cited:
            w, page = work(source)
            key = json.dumps(w, sort_keys=True)
            if key not in works:
                works[key] = len(works)
            pages = refs.setdefault(works[key], [])
            if page and page not in pages:
                pages.append(page)
        refs = [{"work": i, **({"pages": pages} if pages else {})} for i, pages in refs.items()]
        if not refs:
            continue
        same = next((g for g in groups if g["refs"] == refs), None)
        if same:
            same["parts"].append(part)
        else:
            groups.append({"parts": [part], "refs": refs})
    return groups


def dimensions(s):
    """Dimensions as shown in the app. Shoulder only for bottleneck cases, belt only where it is wider than
    the rim (calibre-data's [mm] belt)."""
    d = {"rim": s["rim"], "base": s["base"], "neck": s["neck"], "caseLength": s["case"],
         "overallLength": s["oal"], "bullet": s["bullet"]}
    if s["shoulder"]:
        d["shoulder"] = s["shoulder"]
    if s["belt"]:
        d["belt"] = s["belt"]
    return d


def primer(s):
    """Primer type and diameter (the file's measured one, else the size's nominal one); none for rimfire
    and for balls, Minié bullets and pellets."""
    if s["kind"] in (RIMFIRE, BALL, MINIE, PELLET):
        assert s["name"] not in PRIMERS, f"{s['name']} has no primer"
        return {}
    kind = PRIMERS[s["name"]]  # every centrefire calibre needs one
    return {"primer": {"type": kind, "diameter": PRIMER_MM[s["name"]]}}


def blank(s):
    """No bullet, the case is the whole round: star-crimped, or closed inside the case like the 9 mm P.A.K.
    calibre-data's own rule (is_blank) as its checks apply it, to cartridges only: not to a shot shell or a
    loose projectile, whose measurements can coincide the same way."""
    return (s["kind"] != SHOT and s["kind"] not in LOOSE
            and is_blank(s["profile"], s["rim"], s["base"], s["neck"], s["bullet"], s["case"], s["oal"]))


def build(works=None):
    """The catalogue's entries; `works` (a dict, filled in place) collects the works their sources name."""
    works = {} if works is None else works
    cartridges = []
    for category, items in CATALOGUE:
        for s in items:
            cartridges.append({"id": s["name"], "name": s["name"], "category": category, "kind": s["kind"],
                               "aliases": s["aliases"], "displayAliases": DISPLAY_ALIASES.get(s["name"], []),
                               "obsolete": is_obsolete(s["name"]),
                               "rare": is_rare(s["name"]), **country(s["name"]),
                               "worldwide": is_worldwide(s["name"]),
                               "blank": blank(s),
                               "wellSourced": well_sourced(s),
                               "colourCodes": colour_codes(s["name"]),
                               "sources": source_groups(s, works),
                               "dimensions": dimensions(s), "outline": outline(s),
                               **primer(s)})
    names = {c["name"] for c in cartridges}
    unknown = set(DISPLAY_ALIASES) - names
    assert not unknown, f"aliases for unknown calibres: {unknown}"
    return cartridges


def lookalikes(names):
    """The lookalike groups (calibre-data LOOKALIKES): calibres of their own that look alike, the parent
    first, with what tells them apart ("rim", "bore", "length", "seating", "load", "ignition") and the
    group's name, the parent's or the family's ("7.63x25 mm"). Raven, 2026-11-08: the app shows every
    member's group and compares it at 1:1."""
    groups = [{"name": name, "differs": list(differs), "calibres": list(members)}
              for name, (differs, members) in zip(LOOKALIKE_NAMES, LOOKALIKES, strict=True)]
    unknown = {n for g in groups for n in g["calibres"]} - set(names)
    assert not unknown, f"lookalikes of unknown calibres: {unknown}"
    return groups


def calibre_data():
    """The calibre-data commit the catalogue is read from and its date, shown in the app's settings."""
    commit, date = subprocess.check_output(["git", "log", "-1", "--format=%H %cI"], cwd=DATA, text=True).split()
    # Newer git writes a UTC offset as "Z", older as "+00:00"; one spelling keeps the JSON the same.
    return {"commit": commit, "date": date.replace("Z", "+00:00")}


# Preview fills of cases that are not brass (CartridgeView uses the same colours).
CASE_COLOURS = {"copper": "#b87333", "steel": "#6b6a55", "nickel": "#c8cbce", "aluminium": "#a9adb1", "paper": "#f2ede0", "hybrid": "#e3c16f"}


def preview(cartridges, path):
    cells = []
    for c in cartridges:
        o = c["outline"]
        bullet = {"steel": "#a7adb4", "cupronickel": CASE_COLOURS["nickel"], "lead": "#8a8c91",
                  "plastic": "#f7f7f5"}.get(o.get("bulletMaterial"), "#b87333")
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
    works = {}
    cartridges = build(works)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump({"version": 1, "calibreData": calibre_data(), "cartridges": cartridges,
                   "sources": [json.loads(w) for w in works],
                   "lookalikes": lookalikes({c["name"] for c in cartridges})}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    if "--preview" in sys.argv:
        preview(cartridges, sys.argv[sys.argv.index("--preview") + 1])
    print(f"{len(cartridges)} cartridges")
