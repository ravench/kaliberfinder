"""Tests for the calibre-data bump: python3 -m unittest discover -s tools -p 'test_*.py'"""
import os, subprocess, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(__file__))
import bump_data  # noqa: E402


class FixtureFieldsTests(unittest.TestCase):
    """The frozen test fixture is regenerated only when the catalogue's fields change, nested ones too."""

    def test_same_fields_keep_the_fixture(self):
        catalogue = {"version": 1, "cartridges": [{"id": "a", "primer": {"type": "x"}}, {"id": "b", "outline": {"tip": "M0 0"}}]}
        fixture = {"version": 1, "cartridges": [{"id": "a", "primer": {"type": "x"}}]}
        self.assertTrue(bump_data.fixture_is_current(fixture, catalogue), "b's tip is no field a lacks")
        self.assertEqual(bump_data.paths(fixture["cartridges"]), {"id", "primer", "primer.type"})

    def test_a_new_or_renamed_field_regenerates_it(self):
        fixture = {"version": 1, "cartridges": [{"id": "a", "tipColours": [{"colours": ["red"]}]}]}
        renamed = {"version": 1, "cartridges": [{"id": "a", "colourCodes": [{"colours": ["red"]}]}]}
        nested = {"version": 1, "cartridges": [{"id": "a", "tipColours": [{"colours": ["red"], "part": "tip"}]}]}
        self.assertFalse(bump_data.fixture_is_current(fixture, renamed))
        self.assertFalse(bump_data.fixture_is_current(fixture, nested), "colourCodes[].part is a new path")
        self.assertFalse(bump_data.fixture_is_current(fixture, {"version": 1, "lookalikes": [], "cartridges": fixture["cartridges"]}))

    def test_a_new_field_of_the_groups_regenerates_it(self):
        # The app's LookalikeGroup gained `name` (2026-11-14): a fixture without it decodes to no calibres at all.
        cartridges = [{"id": "a"}, {"id": "b"}, {"id": "c"}]
        fixture = {"version": 1, "cartridges": cartridges[:2], "lookalikes": [{"differs": ["load"], "calibres": ["a", "b"]}]}
        named = {"name": "a", "differs": ["load"], "calibres": ["a", "b"]}
        other = {"name": "c", "differs": ["rim"], "calibres": ["b", "c"], "note": "not among the fixture's calibres"}
        self.assertFalse(bump_data.fixture_is_current(fixture, {"version": 1, "cartridges": cartridges, "lookalikes": [named, other]}))
        fixture["lookalikes"] = [named]
        self.assertTrue(bump_data.fixture_is_current(fixture, {"version": 1, "cartridges": cartridges, "lookalikes": [named, other]}))


class MergeTests(unittest.TestCase):
    """When the fields change, the fixture takes the new ones and drops the old ones but keeps its values:
    a bump that regenerated it whole moved every frozen value (7 failing tests on main)."""

    def test_new_and_dropped_fields_but_frozen_values(self):
        frozen = {"cartridges": [{"id": "a", "dimensions": {"rim": 1.0}, "old": 1},
                                 {"id": "b", "dimensions": {"rim": 2.0}, "old": 2}]}
        fresh = {"cartridges": [{"id": "b", "dimensions": {"rim": 2.2, "neck": 0.6}},
                                {"id": "a", "dimensions": {"rim": 1.1, "neck": 0.5}, "tip": "M0 0"}]}
        self.assertEqual(bump_data.merge(frozen, fresh),
                         {"cartridges": [{"id": "a", "dimensions": {"rim": 1.0, "neck": 0.5}, "tip": "M0 0"},
                                         {"id": "b", "dimensions": {"rim": 2.0, "neck": 0.6}}]})

    def test_an_optional_key_is_no_new_field(self):
        frozen = {"refs": [{"work": 0}, {"work": 1, "pages": "5"}], "outline": {"width": 9}}
        fresh = {"refs": [{"work": 0, "pages": "9"}, {"work": 1}], "outline": {"width": 9.5}}
        self.assertEqual(bump_data.merge(frozen, fresh), frozen)

    def test_works_and_groups_find_their_own_partner(self):
        frozen = {"sources": [{"title": "A", "detail": "1"}, {"title": "B", "detail": "2"}],
                  "lookalikes": [{"calibres": ["a", "b"]}, {"calibres": ["c", "d"]}]}
        fresh = {"sources": [{"title": "B", "detail": "2", "year": 2002}, {"title": "A", "detail": "1", "year": 2001}],
                 "lookalikes": [{"calibres": ["c", "d"], "name": "c"}, {"calibres": ["a", "b"], "name": "a"}]}
        merged = bump_data.merge(frozen, fresh)
        self.assertEqual([w["year"] for w in merged["sources"]], [2001, 2002])
        self.assertEqual([g["name"] for g in merged["lookalikes"]], ["a", "c"])

    def test_refresh_writes_anew_only_where_merging_cannot_bring_a_field(self):
        catalogue = {"version": 1, "calibreData": {"commit": "new"}, "sources": [], "lookalikes": [],
                     "cartridges": [{"id": "a", "colourCodes": [], "rim": 1.1, "neck": 0.5}, {"id": "z"}]}
        fixture = {"version": 1, "calibreData": {"commit": "old"}, "cartridges": [{"id": "a", "colourCodes": [], "rim": 1.0}],
                   "sources": [], "lookalikes": []}
        ids = bump_data.catalogue_fixture.IDS
        bump_data.catalogue_fixture.IDS = ["a"]
        try:
            refreshed = bump_data.refresh(fixture, catalogue)
            self.assertEqual(refreshed["cartridges"], [{"id": "a", "colourCodes": [], "rim": 1.0, "neck": 0.5}])
            self.assertEqual(refreshed["calibreData"], {"commit": "old"})
            # A field that only a colour code the frozen calibre lacks would bring: the fixture is written anew.
            catalogue["cartridges"][0]["colourCodes"] = [{"colours": ["red"]}]
            self.assertIsNone(bump_data.refresh(fixture, catalogue))
        finally:
            bump_data.catalogue_fixture.IDS = ids


class BroughtInTests(unittest.TestCase):
    def test_lists_commits_or_says_the_histories_differ(self):
        with tempfile.TemporaryDirectory() as data:
            def git(*args):
                return subprocess.check_output(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                                               cwd=data, text=True).strip()
            git("init", "-q")
            git("commit", "-q", "--allow-empty", "-m", "first")
            old = git("rev-parse", "HEAD")
            git("commit", "-q", "--allow-empty", "-m", "second")
            new = git("rev-parse", "HEAD")
            git("checkout", "-q", "--orphan", "public")
            git("commit", "-q", "--allow-empty", "-m", "Calibre data")
            public = git("rev-parse", "HEAD")
            self.assertEqual(bump_data.brought_in(old, old, data), f"calibre-data already at {old[:7]}")
            self.assertTrue(bump_data.brought_in(old, new, data).endswith("second"))
            self.assertEqual(bump_data.brought_in(new, old, data),
                             f"calibre-data moved back from {new[:7]} to {old[:7]}")
            # The public repository started over: the old pointer is not in its history.
            self.assertEqual(bump_data.brought_in(old, public, data),
                             f"calibre-data {old[:7]} -> {public[:7]} (not in one history)")


if __name__ == "__main__":
    unittest.main()
