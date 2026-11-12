#!/usr/bin/env python3
"""Moves calibre-data to a commit and regenerates everything that depends on it, in one go:

    python3 tools/bump_data.py [commit]    # default: calibre-data's origin/main

the submodule, Resources/Cartridges.json (generate_data.py), the strings (localize.py) and, only
when the catalogue's fields changed, the test fixture (catalogue_fixture.py: a bump must not move
the frozen test data otherwise). Prints the calibre-data commits brought in, for the pull request.
Commit the result yourself (`git add calibre-data Kaliberfinder KaliberfinderTests`)."""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "calibre-data")
CATALOGUE = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")
FIXTURE = os.path.join(ROOT, "KaliberfinderTests", "Fixtures", "catalogue.json")


def paths(value, prefix=""):
    """Every key path in a JSON value: {"a": {"b": 1}, "c": [{"d": 2}]} is {"a", "a.b", "c", "c[].d"}."""
    found = set()
    if isinstance(value, dict):
        for key, inner in value.items():
            found.add(prefix + key)
            found |= paths(inner, prefix + key + ".")
    elif isinstance(value, list):
        for item in value:
            found |= paths(item, prefix.rstrip(".") + "[]." if prefix else "")
    return found


def fixture_is_current(fixture, catalogue):
    """Whether the frozen fixture still has the catalogue's fields, nested ones too (a key the app's
    model gained or lost makes every fixture test fail with «not in Fixtures/catalogue.json»)."""
    return paths(fixture["cartridges"]) == paths(catalogue["cartridges"]) and set(fixture) == set(catalogue)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=DATA, text=True).strip()


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
    git("fetch", "-q", "origin")
    old = git("rev-parse", "HEAD")
    git("checkout", "-q", target)
    new = git("rev-parse", "HEAD")
    for tool in ("generate_data.py", "localize.py"):
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", tool)], check=True)
    with open(CATALOGUE) as f:
        catalogue = json.load(f)
    with open(FIXTURE) as f:
        fixture = json.load(f)
    if not fixture_is_current(fixture, catalogue):
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "catalogue_fixture.py")], check=True)
        print("The catalogue's fields changed: the test fixture is regenerated too. Check the tests that read it.")
    print(git("log", "--oneline", f"{old}..{new}") if old != new else f"calibre-data already at {new[:7]}")


if __name__ == "__main__":
    main()
