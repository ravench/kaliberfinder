"""Does a pull request need the Mac build, and its PR screens?

Reads the changed file paths (one per line) on stdin and prints `mac=true|false` and
`screens=true|false` for $GITHUB_OUTPUT. Pull requests that change only NO_MAC files skip the Mac
job of the Build workflow: lint and the Linux tools job still check them, and runners for macOS
are scarce. Pull requests that change a SCREENS path also get the PR screens in that job.

    gh api repos/OWNER/REPO/pulls/N/files --paginate --jq '.[].filename' | python3 tools/ci_changes.py
"""
import fnmatch
import sys

# fnmatch's * also matches /, so "tools/*" covers the whole folder.
NO_MAC = ["*.md", ".claude/*", ".github/*", "tools/*", ".gitignore", ".swiftlint.yml"]
# Exception: the Mac job itself and the tool its PR screens run.
NEEDS_MAC = [".github/workflows/build.yml", "tools/pr_screens.py"]
# What can change a screen of the tour (KaliberfinderUITests/PRScreensTests.swift).
SCREENS = ["Kaliberfinder/*", "KaliberfinderUITests/*", "calibre-data", "project.yml",
           "tools/pr_screens.py", ".github/workflows/build.yml"]


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


def needs_screens(paths):
    """True if any path can change a screen. No paths: take the screens to be safe."""
    paths = _clean(paths)
    return not paths or any(fnmatch.fnmatch(p, pattern) for p in paths for pattern in SCREENS)


if __name__ == "__main__":
    paths = sys.stdin.readlines()
    print(f"mac={'true' if needs_mac(paths) else 'false'}")
    print(f"screens={'true' if needs_screens(paths) else 'false'}")
