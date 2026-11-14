"""Tests for the calibre-data bump: python3 -m unittest discover -s tools -p 'test_*.py'"""
import os, sys, unittest

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


if __name__ == "__main__":
    unittest.main()
