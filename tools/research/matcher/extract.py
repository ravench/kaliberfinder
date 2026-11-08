"""Runs Apple Vision on every training shot and stores what a matcher needs:
first-look foreground mask (photo scaled to 1600 px), the picked instance, a second look
at the cartridge cut out of the full-size photo, the crop's RGB, and the LiDAR scale.

    build/venv/bin/python extract.py <training-repo> <out-dir> [package-filter]
"""
import glob, json, os, sys, io
import numpy as np
import objc, Quartz, Vision
from Foundation import NSURL
from PIL import Image

MAX_SIDE = 1600
MAX_SHARE = 0.25      # an instance covering more of the frame is the table or the box
MARGIN = 0.5          # second-look crop margin: half the box's larger side all round

ctx = Quartz.CIContext.contextWithOptions_(None)
gray = Quartz.CGColorSpaceCreateDeviceGray()
rgbspace = Quartz.CGColorSpaceCreateDeviceRGB()


def cg_to_np(cg, channels):
    w, h = Quartz.CGImageGetWidth(cg), Quartz.CGImageGetHeight(cg)
    data = Quartz.CGDataProviderCopyData(Quartz.CGImageGetDataProvider(cg))
    row = Quartz.CGImageGetBytesPerRow(cg)
    bpp = Quartz.CGImageGetBitsPerPixel(cg) // 8
    a = np.frombuffer(bytes(data), dtype=np.uint8)[: h * row].reshape(h, row)[:, : w * bpp].reshape(h, w, bpp)
    return a[:, :, :channels].copy()


def render(ci, w, h, fmt, space, channels):
    cg = ctx.createCGImage_fromRect_format_colorSpace_(ci, Quartz.CGRectMake(0, 0, w, h), fmt, space)
    return cg_to_np(cg, channels)


def load_upright(path, orientation):
    ci = Quartz.CIImage.imageWithContentsOfURL_(NSURL.fileURLWithPath_(path))
    if orientation and orientation != 1:
        ci = ci.imageByApplyingOrientation_(orientation)
    ext = ci.extent()
    # Move the origin to 0,0 (orientation leaves it elsewhere).
    ci = ci.imageByApplyingTransform_(Quartz.CGAffineTransformMakeTranslation(-ext.origin.x, -ext.origin.y))
    return ci, int(ext.size.width), int(ext.size.height)


def scaled(ci, w, h, max_side):
    f = min(1.0, max_side / max(w, h))
    if f < 1:
        ci = ci.imageByApplyingTransform_(Quartz.CGAffineTransformMakeScale(f, f))
    return ci, int(round(w * f)), int(round(h * f)), f


def vision(ci, w, h):
    """Foreground instances: labels (square map), and a function giving a full-res mask for a label set."""
    cg = ctx.createCGImage_fromRect_(ci, Quartz.CGRectMake(0, 0, w, h))
    handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg, None)
    req = Vision.VNGenerateForegroundInstanceMaskRequest.alloc().init()
    ok, err = handler.performRequests_error_([req], None)
    if not ok or not req.results():
        return None
    obs = req.results()[0]
    labels_buf = obs.instanceMask()
    lw, lh = Quartz.CVPixelBufferGetWidth(labels_buf), Quartz.CVPixelBufferGetHeight(labels_buf)
    labels = render(Quartz.CIImage.imageWithCVPixelBuffer_(labels_buf), lw, lh, Quartz.kCIFormatL8, gray, 1)[:, :, 0]
    # CI renders the label map upside down (CI's origin is bottom-left).
    labels = labels[::-1]

    def full_mask(label_list):
        idx = Quartz.NSMutableIndexSet.indexSet()
        for l in label_list:
            idx.addIndex_(int(l))
        buf, err = obs.generateScaledMaskForImageForInstances_fromRequestHandler_error_(idx, handler, None)
        if buf is None:
            return None
        mw, mh = Quartz.CVPixelBufferGetWidth(buf), Quartz.CVPixelBufferGetHeight(buf)
        m = render(Quartz.CIImage.imageWithCVPixelBuffer_(buf), mw, mh, Quartz.kCIFormatL8, gray, 1)[:, :, 0]
        return m[::-1] > 127

    return labels, full_mask


def elongation(xs, ys):
    """Long over short axis of a patch, from its pixels' principal axes."""
    if len(xs) < 20:
        return 1.0
    c = np.cov(np.stack([xs, ys]).astype(float))
    w = np.linalg.eigvalsh(c)
    return float(np.sqrt(max(w[1], 1e-9) / max(w[0], 1 / 12)))


def pick(labels):
    """The largest instance that stays inside the frame, is not too big, and is elongated like a
    cartridge (a blob is a shadow or a stone); the largest of the others if none is. None if none."""
    lh, lw = labels.shape
    candidates = []
    for l in np.unique(labels):
        if l == 0:
            continue
        ys, xs = np.nonzero(labels == l)
        n = len(xs)
        inside = xs.min() > 0 and ys.min() > 0 and xs.max() < lw - 1 and ys.max() < lh - 1
        if inside and n <= MAX_SHARE * lw * lh:
            candidates.append((int(l), n, (xs.min(), ys.min(), xs.max(), ys.max()), elongation(xs, ys)))
    if not candidates:
        return None
    long = [c for c in candidates if c[3] >= 1.6]
    best = max(long or candidates, key=lambda c: c[1])
    return best[:3]


def cut(ci, W, H, region):
    """The part `region` (fractions of the upright photo) of `ci`, origin moved to 0,0."""
    x0, y0, x1, y1 = region
    crop = ci.imageByCroppingToRect_(Quartz.CGRectMake(x0 * W, (1 - y1) * H, (x1 - x0) * W, (y1 - y0) * H))
    ext = crop.extent()
    crop = crop.imageByApplyingTransform_(Quartz.CGAffineTransformMakeTranslation(-ext.origin.x, -ext.origin.y))
    return crop, int(ext.size.width), int(ext.size.height)


def salient_box(ci, w, h):
    """The most confident objectness-based salient region, as fractions of the image (top-left origin)."""
    cg = ctx.createCGImage_fromRect_(ci, Quartz.CGRectMake(0, 0, w, h))
    handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg, None)
    req = Vision.VNGenerateObjectnessBasedSaliencyImageRequest.alloc().init()
    ok, err = handler.performRequests_error_([req], None)
    if not ok or not req.results() or not req.results()[0].salientObjects():
        return None
    b = max(req.results()[0].salientObjects(), key=lambda o: o.confidence()).boundingBox()
    return (b.origin.x, 1 - b.origin.y - b.size.height, b.origin.x + b.size.width, 1 - b.origin.y)


def crop_region(box, lw, lh):
    x0, y0, x1, y1 = box
    w, h = (x1 - x0 + 1) / lw, (y1 - y0 + 1) / lh
    m = MARGIN * max(w, h)
    return (max(0, x0 / lw - m), max(0, y0 / lh - m), min(1, (x1 + 1) / lw + m), min(1, (y1 + 1) / lh + m))


def extract(shot_dir, out_dir):
    shot = json.load(open(os.path.join(shot_dir, "shot.json")))
    photo = os.path.join(shot_dir, shot["photo"])
    ci, W, H = load_upright(photo, shot.get("orientation"))
    small, w, h, f = scaled(ci, W, H, MAX_SIDE)
    meta = {"photo": [W, H], "first": [w, h], "scale": shot.get("scale"), "source": shot.get("source"),
            "phone_mask": bool(shot.get("mask")), "phone_analysis": shot.get("analysis")}
    os.makedirs(out_dir, exist_ok=True)
    rgb = render(small, w, h, Quartz.kCIFormatRGBA8, rgbspace, 3)
    Image.fromarray(rgb).save(os.path.join(out_dir, "first.jpg"), quality=85)
    meta["first"] = [w, h]
    levels = [("whole", (0, 0, 1, 1))]
    for c in (0.6, 0.4, 0.25):
        m = (1 - c) / 2
        levels.append((f"centre{c}", (m, m, 1 - m, 1 - m)))
    sb = salient_box(small, w, h)
    if sb:
        x0, y0, x1, y1 = sb
        mw = 0.5 * max(x1 - x0, y1 - y0)
        levels.append(("salient", (max(0, x0 - mw), max(0, y0 - mw), min(1, x1 + mw), min(1, y1 + mw))))
    found = None
    for level, region in levels:
        part_ci, pw, ph = cut(ci, W, H, region)
        part_s, pw2, ph2, pf = scaled(part_ci, pw, ph, MAX_SIDE)
        v = vision(part_s, pw2, ph2)
        if v is None:
            continue
        labels, full_mask = v
        picked = pick(labels)
        if picked is None:
            continue
        found = (level, region, labels, full_mask, picked, (pw, ph, pw2, ph2))
        break
    meta["first_vision"] = found is not None
    if found is None:
        meta["picked"] = None
        json.dump(meta, open(os.path.join(out_dir, "meta.json"), "w"), indent=1)
        return meta
    level, region, labels, full_mask, picked, (pw, ph, pw2, ph2) = found
    label, n, box = picked
    meta["level"] = level
    meta["level_region"] = list(region)
    meta["level_size"] = [pw, ph, pw2, ph2]
    meta["picked"] = {"label": label, "pixels": int(n), "box_labels": [int(b) for b in box], "label_map": list(labels.shape)}
    m1 = full_mask([label])
    Image.fromarray((m1 * 255).astype(np.uint8)).save(os.path.join(out_dir, "first-mask.png"))
    # Second look: the region around the picked instance, cut from the full-size photo. The box is in
    # the level's crop; map it to the whole photo.
    lx0, ly0, lx1, ly1 = region
    bx0, by0, bx1, by1 = crop_region(box, labels.shape[1], labels.shape[0])
    rx0, ry0 = lx0 + bx0 * (lx1 - lx0), ly0 + by0 * (ly1 - ly0)
    rx1, ry1 = lx0 + bx1 * (lx1 - lx0), ly0 + by1 * (ly1 - ly0)
    meta["region"] = [rx0, ry0, rx1, ry1]
    crop = ci.imageByCroppingToRect_(Quartz.CGRectMake(rx0 * W, (1 - ry1) * H, (rx1 - rx0) * W, (ry1 - ry0) * H))
    ext = crop.extent()
    crop = crop.imageByApplyingTransform_(Quartz.CGAffineTransformMakeTranslation(-ext.origin.x, -ext.origin.y))
    cw, ch = int(ext.size.width), int(ext.size.height)
    crop_s, cw2, ch2, f2 = scaled(crop, cw, ch, MAX_SIDE)
    meta["crop"] = [cw, ch, cw2, ch2]
    rgb2 = render(crop_s, cw2, ch2, Quartz.kCIFormatRGBA8, rgbspace, 3)
    Image.fromarray(rgb2).save(os.path.join(out_dir, "second.jpg"), quality=90)
    v2 = vision(crop_s, cw2, ch2)
    if v2 is not None:
        labels2, full_mask2 = v2
        picked2 = pick(labels2)
        meta["second_picked"] = None if picked2 is None else {"label": picked2[0], "pixels": int(picked2[1])}
        if picked2 is not None:
            m2 = full_mask2([picked2[0]])
            Image.fromarray((m2 * 255).astype(np.uint8)).save(os.path.join(out_dir, "second-mask.png"))
    else:
        meta["second_picked"] = None
    json.dump(meta, open(os.path.join(out_dir, "meta.json"), "w"), indent=1)
    return meta


if __name__ == "__main__":
    root, out = sys.argv[1], sys.argv[2]
    flt = sys.argv[3] if len(sys.argv) > 3 else ""
    shots = sorted(glob.glob(os.path.join(root, "captures", "*", "[0-9]*", "shot.json")))
    done = 0
    for s in shots:
        d = os.path.dirname(s)
        pkg, num = d.split(os.sep)[-2:]
        if flt and flt not in pkg:
            continue
        name = f"{pkg}/{num}"
        try:
            meta = extract(d, os.path.join(out, pkg, num))
            print(name, meta.get("level", "no-vision"),
                  "picked" if meta.get("picked") else "nothing", "second" if meta.get("second_picked") else "-", flush=True)
        except Exception as e:  # keep going, report at the end
            print(name, "ERROR", repr(e), flush=True)
        done += 1
    print("done", done)
