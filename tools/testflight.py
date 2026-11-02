"""Helpers for the TestFlight upload workflow (.github/workflows/testflight.yml).

    python3 tools/testflight.py build-number 42          # -> 1042
    python3 tools/testflight.py export-options out.plist # ExportOptions.plist for the upload

Build numbers come from the workflow's run number plus an offset, so every upload
is higher than the last one and higher than builds uploaded by hand from Xcode.
"""
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_YML = os.path.join(ROOT, "project.yml")

# Room for builds uploaded by hand from Xcode before CI took over.
OFFSET = 1000


def build_number(run_number, offset=OFFSET):
    """CFBundleVersion for a workflow run: a positive integer that grows with each run."""
    run = int(run_number)
    if run < 1:
        raise ValueError(f"run number must be positive, got {run_number!r}")
    return run + offset


def team_id(project_yml):
    """The DEVELOPMENT_TEAM in project.yml (all targets must use the same one)."""
    teams = set(re.findall(r"^\s*DEVELOPMENT_TEAM:\s*[\"']?([A-Z0-9]{10})[\"']?\s*$",
                           project_yml, re.MULTILINE))
    if len(teams) != 1:
        raise ValueError(f"expected exactly one DEVELOPMENT_TEAM in project.yml, found {sorted(teams)}")
    return teams.pop()


def export_options(team):
    """Options for `xcodebuild -exportArchive` that sign for and upload to App Store Connect."""
    return {
        "method": "app-store-connect",
        "destination": "upload",
        "signingStyle": "automatic",
        "teamID": team,
        "uploadSymbols": True,
        # The workflow sets the build number; Xcode must not change it.
        "manageAppVersionAndBuildNumber": False,
    }


def main(argv):
    if len(argv) == 3 and argv[1] == "build-number":
        print(build_number(argv[2]))
    elif len(argv) == 3 and argv[1] == "export-options":
        with open(PROJECT_YML) as f:
            options = export_options(team_id(f.read()))
        with open(argv[2], "wb") as f:
            plistlib.dump(options, f)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
