"""Does a pull request need the Mac build, and its PR screens?

Reads the changed file paths (one per line) on stdin and prints `mac=true|false` and
`screens=true|false` for $GITHUB_OUTPUT. Pull requests that change only NO_MAC files skip the Mac
job of the Build workflow: lint and the Linux tools job still check them, and runners for macOS
are scarce. Pull requests that change a SCREENS path, or carry the «screens» label, also get the
PR screens in that job; they take about an hour, so data bumps and logic changes skip them.

    gh api repos/OWNER/REPO/pulls/N/files --paginate --jq '.[].filename' | python3 tools/ci_changes.py [LABELS]

LABELS: the pull request's label names, one per line.

With BILLED_MAC=true in the environment (a private repo without its own Mac, where GitHub bills
every Mac minute) the screens never run: they cost two Mac jobs of up to an hour each.
"""
import fnmatch
import os
import sys

# fnmatch's * also matches /, so "tools/*" covers the whole folder.
# store/: the App Store texts, which only tools/store_listing.py reads (its tests run in the Linux tools job).
NO_MAC = ["*.md", ".claude/*", ".github/*", "tools/*", "store/*", ".gitignore", ".swiftlint.yml"]
# Exception: the Mac job itself and the tool its PR screens run.
NEEDS_MAC = [".github/workflows/build.yml", "tools/pr_screens.py"]
# What changes how a screen looks: views, images, strings, the tour
# (KaliberfinderUITests/PRScreensTests.swift) and the tool that compares its screens. Logic, data
# bumps and unit tests can change a screen too, but rarely: a pull request whose screen changes
# without these files gets the «screens» label (SCREENS_LABEL).
SCREENS = ["Kaliberfinder/Views/*", "Kaliberfinder/App/*", "Kaliberfinder/Resources/Assets.xcassets/*",
           "Kaliberfinder/Resources/*.xcstrings", "KaliberfinderUITests/PRScreensTests.swift", "tools/pr_screens.py",
           ".github/workflows/build.yml"]
SCREENS_LABEL = "screens"


def _clean(paths):
    return [p.strip() for p in paths if p.strip()]


def needs_mac(paths):
    """True unless every path is one the Mac job does not check. No paths: build to be safe."""
    paths = _clean(paths)
    if not paths:
        return True
    for path in paths:
        if path in NEEDS_MAC or not any(fnmatch.fnmatch(path, pattern) for pattern in NO_MAC):
            return True
    return False


def needs_screens(paths, labels=()):
    """True if any path changes how a screen looks, or the «screens» label asks for them.
    No paths: take the screens to be safe."""
    paths = _clean(paths)
    return (SCREENS_LABEL in _clean(labels) or not paths
            or any(fnmatch.fnmatch(p, pattern) for p in paths for pattern in SCREENS))


if __name__ == "__main__":
    paths = sys.stdin.readlines()
    labels = sys.argv[1].splitlines() if len(sys.argv) > 1 else []
    screens = os.environ.get("BILLED_MAC") != "true" and needs_screens(paths, labels)
    # The PR screens run in the Mac job, so the label starts it too.
    print(f"mac={'true' if screens or needs_mac(paths) else 'false'}")
    print(f"screens={'true' if screens else 'false'}")
