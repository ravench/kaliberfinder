"""Where the bullet meets the case, from the colours along the cartridge's axis: copper, lead or
plated bullets differ in hue from the brass case. Returns the mouth as a fraction of the length
from the narrow end (tip), or None."""
import numpy as np
import kf

STEPS = 100
BAND = 0.5          # middle share of the width sampled across
NEAREST = 0.06      # the mouth lies at least this far from the tip …
FARTHEST = 0.7      # … and no farther than this
WINDOW = 0.05       # colours compared over this much of the length on each side
MIN_STEP = 0.025    # least change of the colour feature at the mouth
MIN_CHANGE = 0.03   # least change between the whole bullet and the case behind the mouth


def colour_feature(rgb):
    """(green − blue) / sum: copper about 0.0–0.05, brass 0.1–0.2, lead and nickel near 0.0, as one number;
    and (red − green) / sum as a second, which separates copper (high) from brass (lower)."""
    r, g, b = [rgb[..., i].astype(float) for i in range(3)]
    s = r + g + b + 1
    return np.stack([(g - b) / s, (r - g) / s], -1)


def profile_along(mask, rgb):
    """Median colour feature per step along the axis (tip first), over the middle band of each slice."""
    pts = kf.silhouette(mask)
    if len(pts) < kf.MIN_POINTS:
        return None
    m, axis, u, v = kf.principal(pts)
    widths, length, centres, filled = kf.slice_widths(u, v)
    k = max(1, kf.BINS * 15 // 100)
    tip_first = widths[:k].sum() <= widths[-k:].sum()
    feat = colour_feature(rgb)
    lo, hi = u.min(), u.max()
    out = np.full((STEPS, 2), np.nan)
    xs = pts[:, 0].astype(int); ys = pts[:, 1].astype(int)
    step = np.minimum(STEPS - 1, ((u - lo) / (hi - lo + 1e-9) * STEPS).astype(int))
    for i in range(STEPS):
        sel = step == i
        if sel.sum() < 4:
            continue
        vv = v[sel]
        c = (vv.max() + vv.min()) / 2
        half = (vv.max() - vv.min()) / 2
        band = np.abs(vv - c) <= BAND * half
        if band.sum() < 3:
            continue
        px = feat[ys[sel][band], xs[sel][band]]
        bright = rgb[ys[sel][band], xs[sel][band]].astype(int).sum(1)
        ok = (bright > 90) & (bright < 740)
        if ok.sum() < 3:
            continue
        out[i] = np.median(px[ok], axis=0)
    if not tip_first:
        out = out[::-1]
    return out


def find(mask, rgb, nearest=NEAREST, farthest=FARTHEST):
    """The split of the colour profile into bullet and case that leaves the least colour variance on
    either side; None when the two sides differ too little (an empty case, a lead ball, a grey photo)."""
    prof = profile_along(mask, rgb)
    if prof is None:
        return None
    ok = ~np.isnan(prof).any(1)
    idx = np.arange(STEPS)
    lo, hi = int(nearest * STEPS), int(farthest * STEPS)
    best = None
    for i in range(lo, hi):
        front = prof[(idx < i) & ok & (idx >= 2)]   # the first steps hold the tip's shadow and glare
        back = prof[(idx >= i) & ok & (idx < int(0.85 * STEPS))]  # the last hold the head's rim
        if len(front) < 3 or len(back) < 3:
            continue
        cost = front.var(0).sum() * len(front) + back.var(0).sum() * len(back)
        if best is None or cost < best[1]:
            best = (i, cost, front.mean(0), back.mean(0))
    if best is None:
        return None
    i, cost, a, b = best
    change = float(np.hypot(*(b - a)))
    if change < MIN_CHANGE:
        return None
    return (i + 0.5) / STEPS
