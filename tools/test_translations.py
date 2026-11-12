"""Consistency checks on tools/translations.py (English, French, Italian)."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from translations import T  # noqa: E402

EN, FR, IT = 0, 1, 2


class TranslationTests(unittest.TestCase):
    def test_profile_twin_label_matches_the_sentence(self):
        """The detail-view label and the «… von %@» note use the same wording."""
        label, sentence = T["Im Profil nicht unterscheidbar von"], T["Im Profil nicht unterscheidbar von %@"]
        for lang in (EN, FR, IT):
            self.assertEqual(sentence[lang], label[lang] + " %@")

    def test_no_text_claims_all_values_are_cip_or_saami(self):
        """Many calibres have no C.I.P. or SAAMI sheet and come from books (Raven, 2026-11-11)."""
        for key, values in T.items():
            for text in (key, *values):
                self.assertNotIn("CIP/SAAMI", text, key)

    def test_italian_primer_sizes_agree_in_gender(self):
        self.assertEqual(T["Büchse klein"][IT], "Carabina piccola")
        self.assertEqual(T["Pistole klein"][IT], "Pistola piccola")

    def test_french_addresses_the_reader_as_vous(self):
        """The French texts use «vous», so no «tu» forms or tu-imperatives slip in."""
        for key, values in T.items():
            fr = values[FR]
            self.assertFalse(re.search(r"\b(tu|ton|ta|tes|toi)\b", fr, re.IGNORECASE), f"{key!r}: {fr}")
            self.assertNotIn("mesure donc", fr, key)
        self.assertIn("mesurez donc avec soin", T["Selten: wird kaum je gefunden. Ein Treffer ist eher eine ähnliche Patrone, also genau nachmessen."][FR])

    def test_case_types_are_short_attributes(self):
        """«Bauart» values read like «Rimmed» / «Belted», not like a noun phrase."""
        for key in ("Mit Rand", "Randlos", "Gürtelhülse", "Randfeuer"):
            for lang in (FR, IT):
                self.assertFalse(re.match(r"(Douille|Bossolo)\b", T[key][lang]), f"{key}: {T[key][lang]}")

    def test_bottleneck_uses_the_overlay_terms(self):
        """The overlay explains «collet et épaulement»; the shape names use the same words."""
        self.assertEqual(T["Hülse mit Flaschenhals"][FR], "Douille à épaulement")
        self.assertEqual(T["Flaschenhals"][FR], "à épaulement")
        self.assertEqual(T["Schrot (209)"][FR], "Cartouche à plombs (209)")

    def test_share_extension_texts_pair_up(self):
        self.assertEqual(T["Das Foto konnte nicht übernommen werden."][FR], "Impossible de recevoir la photo.")

    def test_no_verbatim_german_in_the_views(self):
        """Every literal shown to the user goes through the string table, the developer screen too."""
        views = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Kaliberfinder", "Views")
        for name in os.listdir(views):
            for i, line in enumerate(open(os.path.join(views, name)), 1):
                literal = re.search(r'Text\(verbatim:\s*"([^"]*)"', line)
                text = re.sub(r"\\\([^)]*\)", "", literal.group(1)) if literal else ""  # interpolations are data
                self.assertFalse(re.search("[A-Za-zÄÖÜäöü]{2}", text), f"{name}:{i}: {line.strip()}")

    def test_no_text_names_an_open_licence(self):
        # Closed source since 2026-11-10: the Settings line is the copyright alone («© 2026 Simon
        # Giotta»; a new year changes it in SettingsView, translations.py and both tests).
        views = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Kaliberfinder", "Views")
        texts = [k for k in T] + [v for values in T.values() for v in values]
        for name in os.listdir(views):
            with open(os.path.join(views, name), encoding="utf-8") as f:
                texts.append(f.read())
        for text in texts:
            for word in ("PolyForm", "Lizenz:", "Licence:"):
                self.assertNotIn(word, text)

    def test_placeholders_survive_translation(self):
        for key, values in T.items():
            for value in values:
                self.assertEqual(value.count("%"), key.count("%"), f"{key!r} -> {value!r}")
                self.assertTrue(value.strip(), key)


if __name__ == "__main__":
    unittest.main()
