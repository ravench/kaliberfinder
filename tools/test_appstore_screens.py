"""The App Store screenshot tour (KaliberfinderUITests/AppStoreScreensTests.swift) finds buttons by
their text in each language. It runs by hand, not in CI, so a renamed or untranslated text would only
show up halfway through a release: check here that every text it looks up exists in all five."""
import json
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOUR = os.path.join(ROOT, "KaliberfinderUITests", "AppStoreScreensTests.swift")
STRINGS = os.path.join(ROOT, "Kaliberfinder", "Resources", "Localizable.xcstrings")


def looked_up(swift):
    """The German keys the tour translates: t("…") and prefix("…")."""
    return sorted(set(re.findall(r'\b(?:t|prefix)\("([^"]+)"\)', swift)))


class AppStoreScreensTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(TOUR) as f:
            cls.swift = f.read()
        with open(STRINGS) as f:
            cls.strings = json.load(f)["strings"]

    def test_finds_the_lookups(self):
        self.assertEqual(looked_up('t("Treffer") x prefix("Alle (%lld)") t(key)'), ["Alle (%lld)", "Treffer"])

    def test_tour_texts_exist_in_every_language(self):
        keys = looked_up(self.swift)
        self.assertGreaterEqual(len(keys), 5)
        for key in keys:
            self.assertIn(key, self.strings, key)
            localizations = self.strings[key].get("localizations", {})
            for language in ("en", "fr", "it", "es"):
                value = localizations.get(language, {}).get("stringUnit", {}).get("value")
                self.assertTrue(value, f"{key} has no {language} text")

    def test_fields_are_filled_by_name_and_the_matches_asserted(self):
        # Typed by position, the 9 mm's values went into the wrong fields when the form's order changed, and
        # the tour stayed green: the waits it discarded could not fail (review 2026-11-18).
        self.assertIn('"-screenTourLength"', self.swift)
        self.assertIn('"-screenTourBullet"', self.swift)
        self.assertNotIn("element(boundBy:", self.swift)
        self.assertNotIn("_ = app.staticTexts", self.swift)
        self.assertEqual(self.swift.count('XCTAssertTrue(app.staticTexts[t("Mögliche Kaliber")]'), 2)

    def test_languages_match_the_app(self):
        # The tour's locales cover exactly the app's five languages.
        self.assertEqual(sorted(re.findall(r'"(\w\w)": "\w\w_\w\w"', self.swift)), ["de", "en", "es", "fr", "it"])

    def test_stays_out_of_ci(self):
        # Six screens with a 90 s photo analysis: only the PR screens tour runs on CI.
        with open(os.path.join(ROOT, ".github", "workflows", "build.yml")) as f:
            self.assertNotIn("AppStoreScreensTests", f.read())


if __name__ == "__main__":
    unittest.main()
