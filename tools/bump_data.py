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
    field's values come from the item's partner in `fresh`: the same calibre (id), lookalike group
    (calibres) or work (title, detail and url), or else the item in the same place. An item without a
    partner takes them from the first item of its fresh list; the second value names those items, to
    be checked. Items only `fresh` has are not added."""
    new, gone = paths(fresh) - paths(frozen), paths(frozen) - paths(fresh)
    borrowed = []

    def ident(item):
        keys = next((ks for ks in (("id",), ("calibres",), ("title", "detail", "url"))
                     if isinstance(item, dict) and ks[0] in item), None)
        return json.dumps([item.get(k) for k in keys]) if keys else None

    def walk(old, now, prefix, where):
        if isinstance(old, dict) and isinstance(now, dict):
            kept = {k: walk(v, now[k], prefix + k + ".", f"{where}.{k}" if where else k) if k in now else v
                    for k, v in old.items() if prefix + k not in gone}
            return {**kept, **{k: v for k, v in now.items() if k not in old and prefix + k in new}}
        if isinstance(old, list) and isinstance(now, list):
            inner = prefix.rstrip(".") + "[]." if prefix else ""
            keys = [ident(item) for item in now]
            partners = {k: item for k, item in zip(keys, now) if k is not None and keys.count(k) == 1}
            merged = []
            for i, item in enumerate(old):
                key = ident(item)
                partner = partners.get(key) if key is not None else now[i] if i < len(now) else None
                own = walk(item, item if partner is None else partner, inner, f"{where}[{i}]")
                if partner is None and now and own != (lent := walk(item, now[0], inner, f"{where}[{i}]")):
                    own = lent
                    borrowed.append(f"{where}[{i}]")
                merged.append(own)
            return merged
        # A value that became an object or a list (or stopped being one): the fresh one where that brings
        # new fields, else the frozen one without the dropped ones.
        if paths(now, prefix) & new:
            return now
        return walk(old, old, prefix, where) if isinstance(old, (dict, list)) else old

    return walk(frozen, fresh, "", ""), borrowed


def refresh(fixture, catalogue):
    """The fixture with the catalogue's fields and its own values (None where that is not enough: a field
    only on items the fixture lacks; then it has to be written anew), and the items whose new fields
    came from another item."""
    merged, borrowed = merge(fixture, catalogue_fixture.build(catalogue))
    return (merged if fixture_is_current(merged, catalogue) else None), borrowed


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
        merged, borrowed = refresh(fixture, catalogue)
        written = merged or catalogue_fixture.build(catalogue)
        if not fixture_is_current(written, catalogue):
            sys.exit("catalogue_fixture.build misses some of the catalogue's fields (a new top-level key?): "
                     "fix it first.")
        catalogue_fixture.write(written)
        if not merged:
            print("The catalogue's fields changed and the test fixture had to be written anew, values too: "
                  "check the tests that read it.")
        else:
            print("The catalogue's fields changed: the test fixture took the new fields and kept its values.")
            if borrowed:
                print("These items had no partner and took their new fields from another item; check them where "
                      "a test reads them: " + ", ".join(borrowed))
    print(brought_in(old, new))


if __name__ == "__main__":
    main()
