"""Gives back the dark side of a cartridge that the foreground mask leaves out.

A brass case mirrors the room; along the side that faces something dark it is nearly black and
the mask often stops in the middle of that strip. Two signs together tell a cut side: the mask's
edge on that side lies inside a dark area of the photo (no step from metal to table just outside
it, and darker than the table further out), and measured from the axis through the tip, that side
reaches clearly less far than the other. The lit side's reach is then taken for both sides.

Returns the factor to widen the measured width by (>= 1), or 1.0 when no side looks cut."""
import numpy as np
import kf

TIP_WIDTH_UP_TO = 0.5     # the tip end's last slices are at most this share of the body width
BODY = (0.10, 0.45)       # the body, as shares of the length from the head
ASYMMETRY_FROM = 0.085    # (lit − cut) / (lit + cut)
STEP_BELOW = 0.10         # log brightness ratio inside/outside the edge: below this, no edge in the photo
TABLE_SHARE = 0.5         # outside counts as table from this share of the table's brightness
TABLE_FROM, TABLE_TO = 0.3, 0.45   # where the table is, in body widths beyond the edge


def brightness(rgb, x, y):
    h, w = rgb.shape[:2]
    xi, yi = int(round(x)), int(round(y))
    if 0 <= xi < w and 0 <= yi < h:
        return rgb[yi, xi].astype(float).sum() / 765
    return None


def factor(mask, rgb, slices=120):
    pts = kf.silhouette(mask)
    if len(pts) < kf.MIN_POINTS:
        return 1.0
    m, axis, u, v = kf.principal(pts)
    n = np.array([-axis[1], axis[0]])
    lo, hi = u.min(), u.max()
    length = hi - lo + 1
    count = min(slices, int(length))
    if count < 24:
        return 1.0
    idx = np.minimum(count - 1, ((u - lo) / length * count).astype(int))
    low = np.full(count, np.inf); high = np.full(count, -np.inf)
    np.minimum.at(low, idx, v - 0.5); np.maximum.at(high, idx, v + 0.5)
    widths = np.where(high >= low, high - low, 0)
    # The tip at the high end of u.
    eighth = max(1, count // 8)
    if widths[:eighth][widths[:eighth] > 0].mean() < widths[-eighth:][widths[-eighth:] > 0].mean():
        u, v, axis, n = -u, -v, -axis, -n
        lo, hi = u.min(), u.max()
        idx = np.minimum(count - 1, ((u - lo) / length * count).astype(int))
        low = np.full(count, np.inf); high = np.full(count, -np.inf)
        np.minimum.at(low, idx, v - 0.5); np.maximum.at(high, idx, v + 0.5)
        widths = np.where(high >= low, high - low, 0)
    body = [i for i in range(count) if BODY[0] <= (i + 0.5) / count <= BODY[1] and widths[i] > 0]
    if len(body) < 5:
        return 1.0
    body_width = float(np.median(widths[body]))
    tip_width = float(np.mean([w for w in widths[-4:-1] if w > 0] or [body_width])) / body_width
    if tip_width > TIP_WIDTH_UP_TO or body_width < 12:
        return 1.0
    # The axis: through the middle of the points near the tip, with the body edges' mean slope.
    tip_zone = max(1.0, 0.02 * length)
    near_tip = v[u >= hi - tip_zone]
    if len(near_tip) == 0:
        return 1.0
    centres = np.array([lo + (i + 0.5) / count * length for i in body])
    slope = (np.polyfit(centres, high[body], 1)[0] + np.polyfit(centres, low[body], 1)[0]) / 2
    axis_v_tip = float(np.mean(near_tip))
    def axis_at(uu):
        return axis_v_tip + slope * (uu - hi)
    reach_high = float(np.median([high[i] - axis_at(lo + (i + 0.5) / count * length) for i in body]))
    reach_low = float(np.median([axis_at(lo + (i + 0.5) / count * length) - low[i] for i in body]))
    cut = 1 if reach_high < reach_low else -1
    lit, short = max(reach_high, reach_low), min(reach_high, reach_low)
    if short <= 0 or (lit - short) / (lit + short) < ASYMMETRY_FROM:
        return 1.0
    # The photo at the cut side's edge: dark just outside, no step, table further out.
    steps, darks = [], []
    far0, far1 = int(TABLE_FROM * body_width), max(int(TABLE_FROM * body_width), int(TABLE_TO * body_width))
    for i in body:
        uu = lo + (i + 0.5) / count * length
        edge = high[i] if cut > 0 else low[i]
        def at(offset):
            vv = edge + cut * offset
            p = m + uu * axis + vv * n
            return brightness(rgb, p[0], p[1])
        inside = [b for b in (at(-o) for o in range(2, 6)) if b is not None]
        outside = [b for b in (at(o) for o in range(1, 5)) if b is not None]
        table = [b for b in (at(o) for o in range(far0, far1 + 1)) if b is not None]
        if not inside or not outside or not table or np.median(table) <= 0:
            continue
        steps.append(np.log((np.mean(inside) + 0.02) / (np.mean(outside) + 0.02)))
        darks.append(np.mean(outside) / np.median(table))
    if not steps or np.median(steps) >= STEP_BELOW or np.median(darks) >= TABLE_SHARE:
        return 1.0
    return float(2 * lit / (lit + short))
