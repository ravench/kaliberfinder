"""Measures every extracted shot and ranks the catalogue with the fresh scorer.
    build/venv/bin/python run.py <training> <data> [--params p.json] [--json out.json]"""
import glob, json, os, sys
import numpy as np
import kf, mouth, darkside
from PIL import Image

CAT = kf.Catalogue(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'Kaliberfinder', 'Resources', 'Cartridges.json'))

DEFAULT = {
    "w_aspect": 3.0, "w_profile": 2.0, "w_len": 1.0, "w_dia": 1.0, "tol_len": 0.5, "tol_dia": 0.3,
    "w_rim": 0.1, "rim_tol": 0.1, "dia_scale": 1.0, "len_scale_whole": 1.0, "len_scale_case": 1.0,
    "w_caselen": 0.0, "tol_caselen": 1.0, "w_share": 0.0, "tol_share": 0.03, "w_part": 0.0, "part_mid": 0.55, "cap_mouth": 0.3, "end_rise": 1,
}
WHOLE_KINDS = {"shot", "ball", "minie", "pellet"}  # no bullet to seat: always compared whole, like blanks


def shot_measurement(entry):
    """The best look's measurement with its mm size: the second look where it exists and agrees
    with the first look on the size (a second look that picked a shadow or a piece is dropped)."""
    meta = entry["meta"]
    first = first_measurement(entry)
    if entry["second"] is not None and meta.get("crop"):
        m = kf.measure(entry["second"])
        if m and not m["end_view"]:
            m["look"] = "second"
            with_photo(m, entry["second"], os.path.join(entry["dir"], "second.jpg"))
            m["size"] = kf.size_mm(m, meta.get("scale"), None, meta["crop"][2] / meta["crop"][0])
            if first and first.get("size") and m.get("size"):
                ratio = m["size"]["length"] / first["size"]["length"]
                if not 0.7 <= ratio <= 1.4:
                    return first
            return m
    return first


def first_measurement(entry):
    meta = entry["meta"]
    if entry["first"] is not None:
        m = kf.measure(entry["first"])
        if m:
            # The first look's mask is in the level's crop (the whole photo, or a centre crop) at its scale.
            ls = meta.get("level_size")
            f_scale = (ls[2] / ls[0]) if ls else max(meta["first"]) / meta["scale"]["referenceLongSide"] if meta.get("scale") else None
            m["look"] = "first"
            if meta.get("level") == "whole":  # first.jpg is the whole photo: aligned only at this level
                with_photo(m, entry["first"], os.path.join(entry["dir"], "first.jpg"))
            m["size"] = kf.size_mm(m, meta.get("scale"), None, f_scale) if f_scale else None
            return m
    return None


def with_photo(m, mask, jpg):
    """What the photo adds to a mask's measurement: the case mouth, and the dark side given back."""
    m["mouth"] = None
    m["dark"] = 1.0
    if not os.path.exists(jpg):
        return
    rgb = np.array(Image.open(jpg).convert("RGB"))
    if not m["end_view"]:
        m["mouth"] = mouth.find(mask, rgb)
        f = darkside.factor(mask, rgb)
        if f > 1:
            m["dark"] = f
            m["aspect"] = m["aspect"] / f
            m["body_px"] = m["body_px"] * f
            m["end_view"] = m["aspect"] < 1.4


def part_of(m):
    """Automatic mode: a flat end or a neck that runs to the end is an empty case."""
    f = kf.features(m["widths"])
    return "case" if f["flat"] else "whole"


class Tables:
    """The catalogue as arrays, for one comparison per part: aspects, widths, rims, lengths, diameters."""
    def __init__(self, cat):
        self.ids = [e["id"] for e in cat.items]
        n = len(cat.items)
        self.whole_only = np.array([e["blank"] or e["kind"] in WHOLE_KINDS or not e["has_case"] for e in cat.items])
        self.caselen = np.array([e["dims"]["caseLength"] for e in cat.items], float)
        self.overall = np.array([e["dims"]["overallLength"] for e in cat.items], float)
        # Calibres whose colours can show a case mouth: a case with a bullet in front of it.
        self.has_mouth = np.array([e["has_case"] and not e["blank"] and e["kind"] not in WHOLE_KINDS for e in cat.items])
        # How high each end stands above the axis of a lying cartridge, in body widths: a bullet tip lies on
        # the axis (0), a case mouth or a crimp half its width up, the head half the rim up.
        def front(e, key):
            x = e[key]
            if x is None: return np.nan
            tip = float(np.median(x["widths"][:3]))
            return 0.0 if (key == "whole" and e["has_case"] and not e["blank"] and e["kind"] not in WHOLE_KINDS) else tip / 2
        self.front_whole = np.array([front(e, "whole") for e in cat.items])
        self.front_case = np.array([front(e, "case") for e in cat.items])
        self.back_whole = np.array([kf.features(e["whole"]["widths"])["rim"] / 2 if e["whole"] else np.nan for e in cat.items])
        self.back_case = np.array([kf.features(e["case"]["widths"])["rim"] / 2 if e["case"] else np.nan for e in cat.items])
        def table(key, lkey):
            aspect = np.full(n, np.nan); widths = np.full((n, kf.BINS), np.nan); rim = np.full(n, np.nan)
            length = np.full(n, np.nan); dia = np.full(n, np.nan)
            for i, e in enumerate(cat.items):
                x = e[key]
                if x is None: continue
                aspect[i] = x["aspect"]; widths[i] = x["widths"]; rim[i] = kf.features(x["widths"])["rim"]
                length[i] = e["dims"][lkey]; dia[i] = e["dims"]["base"]
            return aspect, widths, rim, length, dia
        self.whole = table("whole", "overallLength")
        self.case = table("case", "caseLength")

TABLES = None


def distance(m, exp, P, size, exp_len, exp_dia, part):
    if exp is None:
        return None
    a = abs(np.log(m["aspect"] / exp["aspect"]))
    best = None
    for w in (m["widths"], m["widths"][::-1]) if part == "case" else (m["widths"],):
        prof = np.mean(np.abs(w - exp["widths"]))
        fe, fx = kf.features(w), kf.features(exp["widths"])
        rim = 0 if abs(fe["rim"] - fx["rim"]) <= P["rim_tol"] else P["w_rim"]
        d = P["w_aspect"] * a + P["w_profile"] * prof + rim
        if best is None or d < best:
            best = d
    if size:
        L = size["length"] * (P["len_scale_case"] if part == "case" else P["len_scale_whole"])
        D = size["diameter"] * P["dia_scale"]
        best += P["w_len"] * max(0, abs(L - exp_len) - P["tol_len"]) / 10 + P["w_dia"] * max(0, abs(D - exp_dia) - P["tol_dia"]) / 10
    return best


def vector_distance(m, P, part, aspect, widths, rim, length, dia, both_ways):
    a = np.abs(np.log(m["aspect"] / aspect))
    rim_m = kf.features(m["widths"])["rim"]
    best = None
    ways = (m["widths"], m["widths"][::-1]) if both_ways else (m["widths"],)
    for w in ways:
        prof = np.nanmean(np.abs(w[None, :] - widths), axis=1)
        rim_pen = np.where(np.abs(kf.features(w)["rim"] - rim) <= P["rim_tol"], 0.0, P["w_rim"])
        d = P["w_aspect"] * a + P["w_profile"] * prof + rim_pen
        best = d if best is None else np.minimum(best, d)
    size = m.get("size")
    if size:
        L = size["length"] * (P["len_scale_case"] if part == "case" else P["len_scale_whole"])
        D = size["diameter"] * P["dia_scale"]
        best = best + P["w_len"] * np.maximum(0, np.abs(L - length) - P["tol_len"]) / 10 + P["w_dia"] * np.maximum(0, np.abs(D - dia) - P["tol_dia"]) / 10
    return best


def rank(m, P, part=None):
    global TABLES
    if TABLES is None:
        TABLES = Tables(CAT)
    part = part or part_of(m)
    T = TABLES
    d_whole = vector_distance(m, P, "case" if part == "case" else "whole", *T.whole, both_ways=(part == "case"))
    if part == "whole" and m.get("mouth") is not None:
        share = 1 - m["mouth"]
        pen = P["w_share"] * np.maximum(0, np.abs(share - T.caselen / T.overall) - P["tol_share"])
        if m.get("size"):
            case_mm = m["size"]["length"] * P["len_scale_whole"] * share
            pen = pen + P["w_caselen"] * np.maximum(0, np.abs(case_mm - T.caselen) - P["tol_caselen"]) / 10
        d_whole = d_whole + np.where(T.has_mouth, pen, 0)
    if part == "case":
        d_case = vector_distance(m, P, "case", *T.case, both_ways=True)
        d = np.where(T.whole_only | np.isnan(d_case), d_whole, d_case)
    else:
        d = d_whole
    order = np.argsort(d)
    scored = [(float(d[i]), T.ids[i]) for i in order if np.isfinite(d[i])]
    return scored, part


def rows_for(scored, calibre, switches):
    """Row of `calibre` in the phone's list with twins merged and rare/obsolete hidden per `switches`."""
    me = CAT.by_id.get(calibre)
    show_obs = switches != "off" or (me and me["obsolete"])
    show_rare = switches == "all" or (me and me["rare"])
    rows, seen = [], set()
    for d, cid in scored:
        e = CAT.by_id[cid]
        if (e["rare"] and not show_rare) or (e["obsolete"] and not show_obs):
            continue
        key = e["sig"]
        if key in seen:
            continue
        seen.add(key)
        rows.append(CAT.twins[cid])
    for i, group in enumerate(rows):
        if calibre in group:
            return i + 1
    return None


def evaluate(shots, P, verbose=False):
    res = []
    for name, calibre, part_true, m in shots:
        if m is None:
            res.append((name, calibre, None, None, None, None))
            continue
        scored, part = rank(m, P)
        row = rows_for(scored, calibre, "off")
        row_all = rows_for(scored, calibre, "all")
        first = scored[0][1] if scored else None
        res.append((name, calibre, row, row_all, part == part_true, first))
    n = len(res)
    top1 = sum(1 for r in res if r[2] == 1) / n
    top5 = sum(1 for r in res if r[2] is not None and r[2] <= 5) / n
    top1_all = sum(1 for r in res if r[3] == 1) / n
    return top1, top5, top1_all, res


def load_all(training, data):
    shots = []
    for meta_path in sorted(glob.glob(os.path.join(data, "*", "[0-9]*", "meta.json"))):
        d = os.path.dirname(meta_path)
        pkg, num = d.split(os.sep)[-2:]
        package = json.load(open(os.path.join(training, "captures", pkg, "package.json")))
        entry = kf.load_shot(d)
        entry["dir"] = d
        m = shot_measurement(entry)
        shots.append((f"{pkg}/{num}", package["calibre"], "case" if package["part"] == "emptyCase" else "whole", m))
    return shots


if __name__ == "__main__":
    training, data = sys.argv[1], sys.argv[2]
    P = dict(DEFAULT)
    if "--params" in sys.argv:
        P.update(json.load(open(sys.argv[sys.argv.index("--params") + 1])))
    shots = load_all(training, data)
    measured = [s for s in shots if s[3] is not None]
    print(f"{len(shots)} shots, {len(measured)} measured")
    top1, top5, top1_all, res = evaluate(measured, P)
    print(f"measured shots: first {100*top1:.1f} %, top 5 {100*top5:.1f} %, first with all on {100*top1_all:.1f} %")
    top1n, top5n, _, _ = evaluate(shots, P)
    print(f"all shots: first {100*top1n:.1f} %, top 5 {100*top5n:.1f} %")
    by = {}
    for name, cal, row, row_all, part_ok, first in res:
        by.setdefault(cal, []).append((row, part_ok, first))
    for cal, rs in sorted(by.items()):
        n = len(rs)
        print(f"  {cal:32s} {n:3d}  first {100*sum(1 for r in rs if r[0]==1)/n:5.1f} %  top5 {100*sum(1 for r in rs if r[0] and r[0]<=5)/n:5.1f} %  part {100*sum(1 for r in rs if r[1])/n:5.1f} %")
    if "--json" in sys.argv:
        json.dump({"params": P, "results": res}, open(sys.argv[sys.argv.index("--json") + 1], "w"), indent=1)
