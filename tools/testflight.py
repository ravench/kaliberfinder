"""Helpers for the TestFlight upload workflow (.github/workflows/testflight.yml).

    python3 tools/testflight.py build-number 42          # -> 1042
    python3 tools/testflight.py export-options out.plist # ExportOptions.plist for the upload
    python3 tools/testflight.py export-options out.plist export  # ... that only writes the .ipa
    python3 tools/testflight.py check-entitlements signed.plist App/App.entitlements

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


def export_options(team, destination="upload"):
    """Options for `xcodebuild -exportArchive` that sign for App Store Connect and upload
    (destination "upload") or only write the .ipa (destination "export")."""
    if destination not in ("upload", "export"):
        raise ValueError(destination)
    return {
        "method": "app-store-connect",
        "destination": destination,
        "signingStyle": "automatic",
        "teamID": team,
        "uploadSymbols": True,
        # The workflow sets the build number; Xcode must not change it.
        "manageAppVersionAndBuildNumber": False,
    }


def missing_entitlements(signed, expected):
    """Entitlements from the project that the signed app lacks (values may differ, e.g.
    aps-environment development -> production; list entries such as iCloud containers must stay)."""
    missing = []
    for key, value in expected.items():
        if key not in signed:
            missing.append(key)
        elif isinstance(value, list):
            missing += [f"{key}: {v}" for v in value if v not in signed[key]]
    return missing


def main(argv):
    if len(argv) == 3 and argv[1] == "build-number":
        print(build_number(argv[2]))
    elif len(argv) in (3, 4) and argv[1] == "export-options":
        with open(PROJECT_YML) as f:
            options = export_options(team_id(f.read()), *argv[3:])
        with open(argv[2], "wb") as f:
            plistlib.dump(options, f)
    elif len(argv) == 4 and argv[1] == "check-entitlements":
        with open(argv[2], "rb") as f:
            signed = plistlib.load(f)
        expected = {}
        if os.path.exists(argv[3]):
            with open(argv[3], "rb") as f:
                expected = plistlib.load(f)
        missing = missing_entitlements(signed, expected)
        if missing:
            sys.exit("Signed app lacks entitlements: " + ", ".join(missing))
        print(f"All {len(expected)} entitlements present")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
