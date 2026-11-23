#!/usr/bin/env python3
"""Moves calibre-data to a commit and regenerates everything that depends on it, in one go:

    python3 tools/bump_data.py [commit]    # default: calibre-data's origin/main

the submodule, Resources/Cartridges.json (generate_data.py), the strings (localize.py) and, only
when the catalogue's fields changed, the test fixture's fields: it gains the new ones and loses the
dropped ones, but keeps its frozen values (a bump must not move the test data). Prints the
calibre-data commits brought in, for the pull request.
Commit the result yourself (`git add calibre-data Kaliberfinder KaliberfinderTests`)."""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
import catalogue_fixture  # noqa: E402
from catalogue_fixture import groups_among  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "calibre-data")
CATALOGUE = os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")
FIXTURE = catalogue_fixture.FIXTURE


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
    model gained or lost makes every fixture test fail with «not in Fixtures/catalogue.json»).
    Compared on the fixture's own calibres and their lookalike groups: a field only other calibres
    have is not missing."""
    chosen = {c["id"] for c in fixture["cartridges"]}
    same = [c for c in catalogue["cartridges"] if c["id"] in chosen]
    return (paths(fixture["cartridges"]) == paths(same) and set(fixture) == set(catalogue)
            and paths(fixture.get("lookalikes", [])) == paths(groups_among(catalogue, chosen)))


def merge(frozen, fresh):
    """`frozen` with the fields `fresh` added or dropped (key paths, as `paths` names them), and nothing
    else: a key one calibre lacks and another has is no new field, and every value stays frozen. A new
    field's values come from `fresh`; list items pair up by id, by lookalike group (calibres), by work
    (title and detail) or else by place (also where an id found no partner), and items only `fresh` has
    are not added."""
    new, gone = paths(fresh) - paths(frozen), paths(frozen) - paths(fresh)

    def ident(item, place):
        keys = next((ks for ks in (("id",), ("calibres",), ("title", "detail"))
                     if isinstance(item, dict) and ks[0] in item), None)
        return json.dumps([item.get(k) for k in keys]) if keys else place

    def walk(old, now, prefix):
        if isinstance(old, dict) and isinstance(now, dict):
            kept = {k: walk(v, now[k], prefix + k + ".") if k in now else v
                    for k, v in old.items() if prefix + k not in gone}
            return {**kept, **{k: v for k, v in now.items() if k not in old and prefix + k in new}}
        if isinstance(old, list) and isinstance(now, list):
            inner = prefix.rstrip(".") + "[]." if prefix else ""
            partners = {ident(item, i): item for i, item in enumerate(now)}
            pair = lambda item, i: partners.get(ident(item, i), now[i] if i < len(now) else item)  # noqa: E731
            return [walk(item, pair(item, i), inner) for i, item in enumerate(old)]
        # A value that became an object or a list (or stopped being one) where that brings new fields.
        return now if paths(now, prefix) & new or paths(old, prefix) & gone else old

    return walk(frozen, fresh, "")


def refresh(fixture, catalogue):
    """The fixture with the catalogue's fields and its own values, or None where that is not enough
    (a field only on items the fixture lacks): then it has to be written anew."""
    merged = merge(fixture, catalogue_fixture.build(catalogue))
    return merged if fixture_is_current(merged, catalogue) else None


def git(*args):
    return subprocess.check_output(["git", *args], cwd=DATA, text=True).strip()


def brought_in(old, new, data=DATA):
    """The calibre-data commits from `old` to `new`, for the pull request."""
    if old == new:
        return f"calibre-data already at {new[:7]}"
    if subprocess.run(["git", "merge-base", "--is-ancestor", old, new], cwd=data,
                      capture_output=True).returncode == 0:
        return subprocess.check_output(["git", "log", "--oneline", f"{old}..{new}"], cwd=data, text=True).strip()
    if subprocess.run(["git", "merge-base", "--is-ancestor", new, old], cwd=data,
                      capture_output=True).returncode == 0:
        return f"calibre-data moved back from {old[:7]} to {new[:7]}"
    # A pointer from before the public repository's history (it started over on 2026-11-22).
    return f"calibre-data {old[:7]} -> {new[:7]} (not in one history)"


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
        merged = refresh(fixture, catalogue)
        catalogue_fixture.write(merged or catalogue_fixture.build(catalogue))
        print("The catalogue's fields changed: the test fixture took the new fields and kept its values."
              if merged else "The catalogue's fields changed and the test fixture had to be written anew, "
              "values too: check the tests that read it.")
    print(brought_in(old, new))


if __name__ == "__main__":
    main()
