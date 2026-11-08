"""A fresh cartridge matcher: catalogue profiles, silhouette measurement, scoring."""
import json, os, re
import numpy as np
from PIL import Image

BINS = 40
MIN_POINTS = 50

# ---------------------------------------------------------------- catalogue


def parse_paths(d):
    """'M x y L x y … Z' into closed polygons (lists of (x, y))."""
    polys, cur = [], []
    for tok in re.findall(r"[MLZz]|-?\d+\.?\d*", d):
        if tok in "MZz":
            if len(cur) > 1:
                polys.append(cur)
            cur = []
        elif tok == "L":
            pass
        else:
            cur.append(float(tok))
    if len(cur) > 1:
        polys.append(cur)
    return [list(zip(p[0::2], p[1::2])) for p in polys]


def width_at(polys, y):
    lo, hi = np.inf, -np.inf
    for poly in polys:
        n = len(poly)
        for i in range(n):
            (ax, ay), (bx, by) = poly[i], poly[(i + 1) % n]
            if y < min(ay, by) or y > max(ay, by):
                continue
            if ay == by:
                lo, hi = min(lo, ax, bx), max(hi, ax, bx)
            else:
                x = ax + (y - ay) / (by - ay) * (bx - ax)
                lo, hi = min(lo, x), max(hi, x)
    return hi - lo if hi > lo else 0.0


def profile_from_widths(widths, length):
    """Relative widths (tip first) and the aspect from slice widths, as the measurement does."""
    w = np.asarray(widths, float)
    body = np.sort(w)[::-1][BINS // 5]
    if body <= 0:
        return None
    return {"aspect": length / body, "widths": np.minimum(1.3, w / body), "body": body}


class Catalogue:
    def __init__(self, path):
        data = json.load(open(path))["cartridges"]
        self.items = []
        for c in data:
            o = c["outline"]
            d = c["dimensions"]
            polys_case = parse_paths(o.get("case") or "") + parse_paths(o.get("head") or "")
            polys_all = polys_case + parse_paths(o.get("bullet") or "")
            h = o["height"]
            has_case = d["caseLength"] > 0
            entry = {"id": c["id"], "name": c["name"], "kind": c["kind"], "rare": c["rare"], "obsolete": c["obsolete"],
                     "blank": c.get("blank", False), "dims": d, "height": h, "width": o["width"], "has_case": has_case,
                     "sig": (c["kind"], json.dumps(d, sort_keys=True), o["width"], h, o.get("case"), o.get("head"), o.get("bullet"))}
            entry["whole"] = self.expected(polys_all, 0, h)
            entry["case"] = self.expected(polys_case, h - d["caseLength"], h) if has_case else None
            self.items.append(entry)
        # Twins: identical side view.
        groups = {}
        for e in self.items:
            groups.setdefault(e["sig"], []).append(e["id"])
        self.twins = {e["id"]: groups[e["sig"]] for e in self.items}
        self.by_id = {e["id"]: e for e in self.items}

    @staticmethod
    def expected(polys, top, bottom):
        length = bottom - top
        widths = []
        for i in range(BINS):
            widths.append(max(width_at(polys, top + (i + t / 4) / BINS * length) for t in range(5)))
        p = profile_from_widths(widths, length)
        if p:
            p["length_mm"] = length
            p["body_mm"] = p["body"]
        return p


# ---------------------------------------------------------------- measurement


def silhouette(mask):
    ys, xs = np.nonzero(mask)
    return np.stack([xs, ys], 1).astype(float)


def principal(points):
    m = points.mean(0)
    d = points - m
    cov = d.T @ d / len(points)
    w, v = np.linalg.eigh(cov)
    axis = v[:, np.argmax(w)]
    u = d @ axis
    n = np.array([-axis[1], axis[0]])
    vv = d @ n
    return m, axis, u, vv


def slice_widths(u, v, bins=BINS):
    lo, hi = u.min(), u.max()
    length = hi - lo + 1
    idx = np.minimum(bins - 1, ((u - lo) / length * bins).astype(int))
    widths = np.zeros(bins)
    lows = np.full(bins, np.inf)
    highs = np.full(bins, -np.inf)
    np.minimum.at(lows, idx, v)
    np.maximum.at(highs, idx, v)
    filled = highs >= lows
    widths[filled] = highs[filled] - lows[filled] + 1
    centres = np.where(filled, (highs + lows) / 2, 0)
    return widths, length, centres, filled


def mirror_trim(points, u, v, widths, length, centres, filled):
    """Cut each slice back to the shorter side's reach about a straight axis (shadow on one side)."""
    lo = u.min()
    bins = len(widths)
    xs = lo + (np.arange(bins) + 0.5) / bins * length
    f = filled & (widths > 0)
    if f.sum() < 3:
        return points
    # Robust line through slice centres: median slope via least squares on inliers (two passes).
    a, b = np.polyfit(xs[f], centres[f], 1)
    res = np.abs(centres[f] - (a * xs[f] + b))
    tol = max(1.0, 0.03 * np.median(widths[f]))
    inl = res <= max(tol, np.median(res))
    if inl.sum() >= 2:
        a, b = np.polyfit(xs[f][inl], centres[f][inl], 1)
    axis_v = a * u + b
    idx = np.minimum(bins - 1, ((u - lo) / length * bins).astype(int))
    lows = np.full(bins, np.inf); highs = np.full(bins, -np.inf)
    np.minimum.at(lows, idx, v); np.maximum.at(highs, idx, v)
    at = a * (lo + (np.arange(bins) + 0.5) / bins * length) + b
    reach = np.minimum(highs - at, at - lows)
    keep = np.abs(v - axis_v) <= reach[idx] + 0.5
    return points[keep]


def measure(mask, trim=True):
    """Aspect, relative widths (narrow end first), length in pixels, body in pixels; None if too small."""
    pts = silhouette(mask)
    if len(pts) < MIN_POINTS:
        return None
    m, axis, u, v = principal(pts)
    widths, length, centres, filled = slice_widths(u, v)
    if trim:
        pts2 = mirror_trim(pts, u, v, widths, length, centres, filled)
        if len(pts2) >= MIN_POINTS:
            m, axis, u, v = principal(pts2)
            widths, length, centres, filled = slice_widths(u, v)
    p = profile_from_widths(widths, length)
    if p is None:
        return None
    k = max(1, BINS * 15 // 100)
    w = p["widths"]
    if w[:k].sum() > w[-k:].sum():
        w = w[::-1]
    p["widths"] = w
    p["length_px"] = length
    p["body_px"] = p["body"]
    p["end_view"] = p["aspect"] < 1.4
    return p


def features(w):
    """Rim (relative body width at the base end), mouth (median of the first three), flat end."""
    rim = max(w[-1], w[-2])
    mouth = float(np.sort(w[:3])[1])
    flat = w[0] / max(w[1], w[2], 1e-9) >= 0.85 or w[1] / max(w[2], w[3], 1e-9) >= 0.95
    return {"rim": float(rim), "mouth": mouth, "flat": bool(flat)}


def size_mm(meas, scale, image_long_side, f_scale=None):
    """Length and body diameter in mm from the LiDAR distance: outline at half a diameter above the table."""
    if not scale or not meas:
        return None
    f = scale["focalLength"] * (f_scale if f_scale is not None else image_long_side / scale["referenceLongSide"])
    z = scale["tableDistance"]
    wpx = meas["length_px"] / meas["aspect"]
    d = wpx * z / (f + wpx / 2)
    axis = z - d / 2
    L = meas["length_px"] * axis / f
    return {"length": L, "diameter": d, "f": f}


def load_shot(data_dir):
    meta = json.load(open(os.path.join(data_dir, "meta.json")))
    out = {"meta": meta, "first": None, "second": None}
    p1 = os.path.join(data_dir, "first-mask.png")
    # The masks were stored upside down against the JPEGs (Core Image's origin is bottom-left).
    if os.path.exists(p1):
        out["first"] = (np.array(Image.open(p1)) > 127)[::-1]
    p2 = os.path.join(data_dir, "second-mask.png")
    if os.path.exists(p2):
        out["second"] = (np.array(Image.open(p2)) > 127)[::-1]
    return out
