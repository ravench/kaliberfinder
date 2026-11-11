"""Tests for tools/store_listing.py and the store texts in store/."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import store_listing as sl  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def loc(locale, id_, **attributes):
    return {"id": id_, "attributes": {"locale": locale, **attributes}}


class StoreTextTests(unittest.TestCase):
    def test_every_language_fits_apples_limits(self):
        for lang in sorted(set(sl.LOCALES.values())):
            with self.subTest(lang=lang):
                self.assertEqual(sl.problems(sl.texts(lang)), [])

    def test_the_apps_four_languages(self):
        self.assertEqual(set(sl.LOCALES.values()), {"de", "en", "fr", "it"})
        self.assertEqual(sorted(os.listdir(sl.STORE)), ["de", "en", "fr", "it"])

    def test_texts_name_no_single_standard_as_the_source(self):
        """Many calibres have no C.I.P. or SAAMI sheet (Raven, 2026-11-11)."""
        for lang in ("de", "en", "fr", "it"):
            self.assertNotIn("SAAMI", sl.texts(lang)["description"])

    def test_problems_catches_long_fields_and_padded_keywords(self):
        listing = {**sl.texts("en"), "subtitle": "x" * 31, "keywords": "a, b"}
        found = sl.problems(listing)
        self.assertIn("subtitle: 31 > 30 characters", found)
        self.assertIn("keywords: empty or space-padded entry", found)


class RequestTests(unittest.TestCase):
    def test_changed_fields_are_patched_and_missing_languages_added(self):
        existing = [loc("de-DE", "L1", description="alt", keywords="k")]
        wanted = {"de-DE": {"description": "neu", "keywords": "k"}, "it": {"description": "nuovo"}}
        out = sl.requests("appStoreVersionLocalizations", "appStoreVersions", "V1", existing, wanted)
        self.assertEqual(out[0], ("PATCH", "/appStoreVersionLocalizations/L1",
                                  {"data": {"type": "appStoreVersionLocalizations", "id": "L1", "attributes": {"description": "neu"}}}))
        method, path, body = out[1]
        self.assertEqual((method, path), ("POST", "/appStoreVersionLocalizations"))
        self.assertEqual(body["data"]["attributes"], {"locale": "it", "description": "nuovo"})
        self.assertEqual(body["data"]["relationships"], {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": "V1"}}})

    def test_nothing_to_do_when_everything_matches(self):
        existing = [loc("fr-FR", "L1", name="Kaliberfinder")]
        self.assertEqual(sl.requests("appInfoLocalizations", "appInfos", "I1", existing, {"fr-FR": {"name": "Kaliberfinder"}}), [])

    def test_app_info_relationship(self):
        out = sl.requests("appInfoLocalizations", "appInfos", "I1", [], {"en-GB": {"name": "Kaliberfinder"}})
        self.assertEqual(out[0][2]["data"]["relationships"], {"appInfo": {"data": {"type": "appInfos", "id": "I1"}}})

    def test_urls_open_the_pages_in_the_listings_language(self):
        listing = sl.texts("fr")
        self.assertEqual(sl.info_attributes("fr", listing)["privacyPolicyUrl"], "https://ravench.github.io/kaliberfinder/privacy.html#fr")
        self.assertEqual(sl.version_attributes("fr", listing)["supportUrl"], "https://ravench.github.io/kaliberfinder/#fr")

    def test_promo_only_writes_just_the_promotional_text(self):
        self.assertEqual(list(sl.version_attributes("de", sl.texts("de"), promo_only=True)), ["promotionalText"])


class PickTests(unittest.TestCase):
    def version(self, id_, state):
        return {"id": id_, "attributes": {"appStoreState": state}}

    def test_texts_go_only_to_a_version_being_prepared(self):
        live = self.version("V1", "READY_FOR_SALE")
        self.assertIsNone(sl.pick_version([live]))
        self.assertEqual(sl.pick_version([live, self.version("V2", "PREPARE_FOR_SUBMISSION")])["id"], "V2")

    def test_promo_only_may_use_the_live_version(self):
        self.assertEqual(sl.pick_version([self.version("V1", "READY_FOR_SALE")], promo_only=True)["id"], "V1")

    def test_the_app_info_that_is_not_live(self):
        infos = [{"id": "I1", "attributes": {"state": "READY_FOR_DISTRIBUTION"}}, {"id": "I2", "attributes": {"state": "PREPARE_FOR_SUBMISSION"}}]
        self.assertEqual(sl.pick_info(infos)["id"], "I2")


class WorkflowTests(unittest.TestCase):
    def test_runs_only_by_hand_and_dry_by_default(self):
        with open(os.path.join(ROOT, ".github/workflows/store-listing.yml")) as f:
            text = f.read()
        self.assertRegex(text, r"on:\n  workflow_dispatch:")
        self.assertNotRegex(text, r"\n  (push|pull_request|schedule):")
        self.assertRegex(text, r"apply:\n(.*\n){2}\s+default: false")

    def test_never_submits_or_attaches_a_build(self):
        with open(os.path.join(ROOT, "tools/store_listing.py")) as f:
            code = f.read()
        self.assertFalse(re.search(r"appStoreVersionSubmissions|reviewSubmissions|/relationships/build", code))


if __name__ == "__main__":
    unittest.main()
