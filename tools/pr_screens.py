"""Helpers for the PR screens in .github/workflows/build.yml: before/after screenshots on pull requests.

    xcrun simctl list devices available -j | python3 tools/pr_screens.py pick-iphone
    python3 tools/pr_screens.py rename <xcresulttool export dir> <out dir>
    python3 tools/pr_screens.py changes <before dir> <after dir> <out dir>
    python3 tools/pr_screens.py comment <out dir> <image base url> <run url>
"""
import filecmp
import json
import os
import re
import shutil
import sys

MARKER = "<!-- pr-screens -->"
TOUR = "KaliberfinderUITests/PRScreensTests.swift"


def _ios_version(runtime):
    # "com.apple.CoreSimulator.SimRuntime.iOS-26-0" -> (26, 0)
    m = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
    return (int(m.group(1)), int(m.group(2) or 0)) if m else None


def pick_iphone(simctl):
    """UDID of an iPhone on the newest iOS runtime, preferring the plain Pro (the most common size)."""
    best = None
    for runtime, devices in simctl.get("devices", {}).items():
        version = _ios_version(runtime)
        if version is None:
            continue
        for d in devices:
            name = d.get("name", "")
            if not name.startswith("iPhone") or not d.get("isAvailable", True):
                continue
            size = 2 if "Pro" in name and "Max" not in name else 1 if "Max" not in name else 0
            key = (version, size, name)
            if best is None or key > best[0]:
                best = (key, d["udid"])
    if best is None:
        raise ValueError("no iPhone simulator available")
    return best[1]


def screenshot_name(human_name):
    """'portrait-1-Tagebuch_0_1A2B…-….png' -> 'portrait-1-Tagebuch.png'."""
    base, ext = os.path.splitext(human_name)
    base = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", base)
    base = re.sub(r"[^\w.-]+", "_", base).strip("_") or "screenshot"
    return base + (ext or ".png")


def rename(raw_dir, out_dir):
    """Copy the exported attachments to out_dir under their attachment names; returns the names."""
    with open(os.path.join(raw_dir, "manifest.json")) as f:
        manifest = json.load(f)
    os.makedirs(out_dir, exist_ok=True)
    names = []
    for test in manifest:
        for a in test.get("attachments", []):
            name = screenshot_name(a.get("suggestedHumanReadableName") or a["exportedFileName"])
            stem, ext = os.path.splitext(name)
            n = 2
            while name in names:
                name = f"{stem}-{n}{ext}"
                n += 1
            shutil.copyfile(os.path.join(raw_dir, a["exportedFileName"]), os.path.join(out_dir, name))
            names.append(name)
    return sorted(names)


def _pngs(folder):
    return set(n for n in os.listdir(folder) if n.endswith(".png")) if os.path.isdir(folder) else set()


def same(a, b, tolerance=48, max_pixels=20, blur=2):
    """True if two screenshots look the same.

    Identical files are the same. Otherwise, with Pillow, both are blurred a little and a few
    pixels off by a few levels still count as the same: text and toggles rasterised at a
    fractional scroll offset, and the glass bars' blur of what lies under them, differ from run
    to run by up to ~120 levels along every edge, but by under 30 once blurred, while a changed
    word or control stays well over the tolerance. Without Pillow any difference counts.
    """
    if filecmp.cmp(a, b, shallow=False):
        return True
    try:
        from PIL import Image, ImageChops, ImageFilter
    except ImportError:
        return False
    try:
        ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    except OSError:  # not an image Pillow can read
        return False
    if ia.size != ib.size:
        return False
    if blur:
        ia, ib = ia.filter(ImageFilter.GaussianBlur(blur)), ib.filter(ImageFilter.GaussianBlur(blur))
    r, g, bl = ImageChops.difference(ia, ib).split()
    worst = ImageChops.lighter(ImageChops.lighter(r, g), bl)
    return sum(worst.histogram()[tolerance + 1:]) <= max_pixels


def changes(before_dir, after_dir):
    """[(name, status)] for screens that are new, changed or gone, by name.

    Both runs use the same simulator and status bar minutes apart, so an unchanged
    screen gives (almost) the same image.
    """
    before, after = _pngs(before_dir), _pngs(after_dir)
    result = []
    for name in sorted(before | after):
        if name not in before:
            result.append((name, "new"))
        elif name not in after:
            result.append((name, "gone"))
        elif not same(os.path.join(before_dir, name), os.path.join(after_dir, name)):
            result.append((name, "changed"))
    return result


def collect(before_dir, after_dir, out_dir):
    """Copies the changed screens to out_dir/before and out_dir/after and writes out_dir/changes.json."""
    found = changes(before_dir, after_dir)
    for side, folder in (("before", before_dir), ("after", after_dir)):
        os.makedirs(os.path.join(out_dir, side), exist_ok=True)
        for name, _ in found:
            src = os.path.join(folder, name)
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(out_dir, side, name))
    summary = {"changes": found, "total": len(_pngs(after_dir)), "base": len(_pngs(before_dir))}
    with open(os.path.join(out_dir, "changes.json"), "w") as f:
        json.dump(summary, f)
    return summary


def _img(url):
    return f'<img src="{url}" width="250">'


def comment(summary, base_url, run_url):
    """Markdown for the pull request comment; base_url is where out_dir/before and /after are served."""
    found, total = summary["changes"], summary["total"]
    lines = [MARKER, "### Screenshots", ""]
    if summary.get("base", 1) == 0:
        lines += ["The screens of the base branch could not be taken, so every screen is shown as new.", ""]
    if not found:
        lines += [f"No visible change on the {total} screens of the tour.",
                  f"If this pull request changes a screen the tour does not reach, add it to `{TOUR}`."]
    else:
        lines += [f"{len(found)} of {total} screens look different (iPhone, German).", "",
                  "| Screen | Before | After |", "| --- | --- | --- |"]
        for name, status in found:
            before = "—" if status == "new" else _img(f"{base_url}/before/{name}")
            after = "—" if status == "gone" else _img(f"{base_url}/after/{name}")
            label = os.path.splitext(name)[0] + ("" if status == "changed" else f" ({status})")
            lines.append(f"| {label} | {before} | {after} |")
    lines += ["", f"All screens of this run: [workflow artifacts]({run_url})."]
    return "\n".join(lines) + "\n"


def main(argv):
    if argv[1:2] == ["pick-iphone"]:
        print(pick_iphone(json.load(sys.stdin)))
    elif argv[1:2] == ["rename"] and len(argv) == 4:
        for name in rename(argv[2], argv[3]):
            print(name)
    elif argv[1:2] == ["changes"] and len(argv) == 5:
        summary = collect(argv[2], argv[3], argv[4])
        for name, status in summary["changes"]:
            print(f"{status}: {name}")
    elif argv[1:2] == ["comment"] and len(argv) == 5:
        with open(os.path.join(argv[2], "changes.json")) as f:
            sys.stdout.write(comment(json.load(f), argv[3], argv[4]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
