"""Consistency checks on tools/translations.py (English, French, Italian, Spanish)."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from translations import T  # noqa: E402

EN, FR, IT, ES = 0, 1, 2, 3
# The German keys are Swiss Standard German (CONTRIBUTING.md): ss, «», decimal point, Swiss words.
SWISS = [(re.compile(r"ß"), "ss"), (re.compile(r"[„“”]"), "«»"), (re.compile(r"\d,\d"), "decimal point, 10.9")]
GERMANISMS = {r"Webseiten?": "Website", r"oftmals": "oft", r"Los geht['’]s": "Starten", r"Wartung\w*": "Pflege or Service",
              r"Displays?": "Bildschirm"}


def swiss_problems(texts):
    bad = [(text, hint) for text in texts for pattern, hint in SWISS if pattern.search(text)]
    return bad + [(text, swiss) for text in texts for word, swiss in GERMANISMS.items()
                  if re.search(rf"(?<!\w){word}(?!\w)", text, re.I)]


class TranslationTests(unittest.TestCase):
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
        self.assertIn("mesurez avec soin", T["Selten: Ein Treffer ist oft eine ähnliche Patrone, genau nachmessen."][FR])

    def test_case_types_are_short_attributes(self):
        """«Bauart» values read like «Rimmed» / «Belted», not like a noun phrase."""
        for key in ("Mit Rand", "Randlos", "Gürtelhülse", "Randfeuer"):
            for lang in (FR, IT):
                self.assertFalse(re.match(r"(Douille|Bossolo)\b", T[key][lang]), f"{key}: {T[key][lang]}")

    def test_bottleneck_uses_the_overlay_terms(self):
        """The overlay explains «collet et épaulement»; the shape names use the same words."""
        self.assertEqual(T["Flaschenhals"][FR], "À épaulement")
        self.assertEqual(T["mit Flaschenhals"][FR], "à épaulement")
        self.assertEqual(T["Schrot (209)"][FR], "Cartouche à plombs (209)")

    def test_any_fits_both_rows(self):
        """«Beliebig» is the unset choice of Hülsenform (la douille) and Randform (le culot): no gender in French."""
        self.assertEqual(T["Beliebig"][FR], "Peu importe")
        self.assertNotIn("Beliebige Randform", T)

    def test_a_match_is_no_clearance_to_fire(self):
        """Both result screens say under «Mögliche Kaliber» that a match must not decide what is fired (review 2026-11-18)."""
        note = T["Nur zur Bestimmung: Ein Treffer ist keine Freigabe zum Schiessen. Prüfe Bodenstempel und Kaliberangabe der Waffe."]
        for lang, words in ((EN, "safe to fire"), (FR, "n'autorise pas le tir"), (IT, "non autorizza a sparare"),
                            (ES, "no autoriza a disparar")):
            self.assertIn(words, note[lang])
        # «Prüfe Bodenstempel»: in the app's own word for the headstamp, as in the store texts (review 2026-11-20:
        # the Italian said «Controlla il fondello», the case head, instead of its marking).
        for lang in (EN, FR, IT, ES):
            self.assertIn(T["Bodenstempel"][lang].lower(), note[lang].lower(), lang)
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        for view in ("MatchesView.swift", "MeasureView.swift"):
            with open(os.path.join(root, "Kaliberfinder", "Views", view), encoding="utf-8") as f:
                self.assertRegex(f.read(), r'Text\("Mögliche Kaliber"\)\n\s*\} footer: \{\n\s*SafetyNote\(\)', view)

    def test_the_check_of_2026_11_19_stays_fixed(self):
        """What the check of all translations found clearly wrong: cut buttons, calques, a vulgar reading, typography."""
        self.assertEqual(T["Alle passenden 1:1 vergleichen (%lld)"][FR:ES], ("Tout comparer 1:1 (%lld)", "Confronta tutti 1:1 (%lld)"))
        self.assertEqual(T["Geschosse bei leeren Hülsen zeigen"][IT], "Mostra la palla sui bossoli vuoti")
        self.assertEqual(T["Zerfallend"][FR], "Frangible")
        self.assertEqual(T["%1$@: %2$@"][FR], "%1$@ : %2$@", "French sets a space before the colon")
        for key, values in T.items():
            for lang, text in zip(("en", "fr", "it", "es"), values):
                self.assertNotIn(" …", text, f"{lang}, {key!r}: no space before the ellipsis outside German")
                self.assertNotRegex(text, r"un bon %lld|un buon %lld", f"{lang}, {key!r}")
            self.assertNotRegex(values[FR], r"[^\s][:;?!](\s|$)(?<!\d:\d)", f"French, {key!r}: a space before : ; ? !")
        # «Masse» is dimensions in every language, never measurements, cotes or misure.
        for key in ("Kaliber mit identischen Massen gruppieren",
                    "Kaliber, deren Masse in calibre-data nicht gut belegt sind: Teile ihrer Zeichnung sind geschätzt."):
            self.assertEqual([word in text for word, text in zip(("dimensions", "dimensions", "dimensioni"), T[key])], [True] * 3, key)

    def test_the_check_of_2026_11_20_stays_fixed(self):
        """What the review of 2026-11-20 found: iOS's French word for the camera, the colour legend's word order,
        the Italian rim, one word per part, the English seating depth and a capital «Cartridge» mid-line."""
        # French iOS names the camera «appareil photo», in Réglages too, where the access is allowed.
        self.assertIn("l'appareil photo", T["Kein Zugriff auf die Kamera. Erlaube ihn in den Einstellungen."][FR])
        self.assertEqual(T["Kamera"][FR], "Appareil photo")
        # «Pointe et culot en vert», not «Vert pointe et culot».
        legend = T["Grün Spitze und Boden, violett Geschoss, orange Hals und Schulter, hellblau Körper."]
        self.assertEqual(legend[FR:], ("Pointe et culot en vert, projectile en violet, collet et épaulement en orange, corps en bleu clair.",
                                       "Punta e fondello in verde, palla in viola, colletto e spalla in arancione, corpo in azzurro.",
                                       "Punta y culote en verde, bala en violeta, cuello y hombro en naranja, cuerpo en azul claro."))
        # The Italian rim is the «collarino» (earmi.it's C.I.P. columns: «R Spessore del collarino», «R1 Diametro del
        # collarino», «con/senza collarino»), in the app and in the store text, which names the app's fields.
        self.assertEqual(T["Rand"][IT], "Collarino")
        self.assertEqual(T["Randdurchmesser"][IT], "Diametro del collarino")
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        def read(*path):
            with open(os.path.join(root, *path), encoding="utf-8") as f:
                return f.read()
        for key, values in T.items():
            self.assertNotRegex(values[IT], r"(?i)\borl[oi]\b", key)
            self.assertNotRegex(values[IT], r"(?i)proiettil", f"{key}: the bullet is «palla»")
            self.assertNotIn("caméra", values[FR].lower(), key)
            self.assertNotIn("Bodenprägung", key)  # «Bodenstempel», as everywhere else
        self.assertNotRegex(read("store", "it", "description.txt"), r"(?i)\borl[oi]\b")
        # The store text and the release notes, which the app shows too, say what the app says.
        self.assertNotIn("caméra", read("store", "fr", "description.txt").lower())
        french_notes = re.findall(r"### fr\n(.*?)(?=\n### |\n## |\Z)", read("RELEASE_NOTES.md"), re.S)
        self.assertTrue(french_notes)
        for notes in french_notes:
            self.assertNotIn("caméra", notes.lower())
        # The depth, not the act of seating.
        self.assertEqual(T["Setztiefe des Geschosses"], ("seating depth", "profondeur d'enfoncement du projectile",
                                                         "profondità di inserimento della palla", "profundidad de asiento de la bala"))
        # After «Detected:» and «Differ in:» a part starts lower-case like the words that follow it; «Rand» is the
        # drawing's capitalised label, so the rim difference has a key of its own.
        for key in ("Erkannt: Patrone · %@", "Erkannt: leere Hülse · %@"):
            for text in T[key]:
                self.assertRegex(text, r"^[^:]+ ?: [a-zà-ÿ]", key)
        for key in ("Hülsenrand", "Laufdurchmesser", "Länge", "Setztiefe des Geschosses", "Ladung", "Zündung",
                    "mit Flaschenhals", "gerade Hülse", "mit Rand", "ohne Rand"):  # and the features after «Erkannt: … ·»
            for text in T[key]:
                self.assertRegex(text, r"^[a-zà-ÿ]", key)

    def test_the_nose_is_the_ogive(self):
        """«Kopflänge» is the curved part of round and pointed bullets alike (Raven, 2026-11-20); «ogive» means just that."""
        self.assertEqual(T["Kopflänge"], ("Nose length", "Longueur de l'ogive", "Lunghezza dell'ogiva", "Longitud de la ojiva"))
        self.assertNotIn("Spitzenlänge", T)

    def test_the_guidance_speaks_of_the_device(self):
        """«Gerät»: the LiDAR scanner is on iPads too, so no English text says «phone»."""
        for key, values in T.items():
            if "Gerät" in key:
                self.assertIn("device", values[EN], key)
            self.assertNotRegex(values[EN], r"(?i)\bphone\b", key)

    def test_country_names_come_in_their_language(self):
        """calibre-data's country names join the string table in localize.py, not through T."""
        import json
        path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Kaliberfinder", "Resources", "Localizable.xcstrings")
        with open(path, encoding="utf-8") as f:
            names = json.load(f)["strings"]["Schweiz"]["localizations"]
        self.assertEqual({lang: v["stringUnit"]["value"] for lang, v in names.items()},
                         {"en": "Switzerland", "fr": "Suisse", "it": "Svizzera", "es": "Suiza"})

    def test_spanish_takes_its_cartridge_terms_from_municion_org(self):
        """The Spanish names of a cartridge's parts are those of municion.org (AECC), the Spanish source
        calibre-data cites most: its glossary («vaina», «culote», «pistón», «marcaje») and its specimen
        texts (phrase counts there, 2026-11-19: «diámetro de la pestaña» 10, «longitud de la vaina» 51,
        «ángulo del hombro» 18, «vaina abotellada» 22 against «agolletada» 8, «vaina recta» 19 against
        «cilíndrica» 9, «bala esférica» 20 against «redonda» 9)."""
        sourced = {"Hülse": "Vaina", "Boden": "Culote", "Rand": "Pestaña", "Hals": "Cuello", "Schulter": "Hombro",
                   "Geschoss": "Bala", "Gürtel": "Cinturón", "Zündhütchen": "Pistón", "Bodenstempel": "Marcaje del culote",
                   "Randdurchmesser": "Diámetro de la pestaña", "Hülsenlänge": "Longitud de la vaina",
                   "Gesamtlänge": "Longitud total", "Schulterwinkel": "Ángulo del hombro",
                   "Flaschenhals": "Abotellada", "Gerade": "Recta",
                   "Konisch": "Cónica", "Mit Rand": "Con pestaña", "Randlos": "Sin pestaña",
                   "Halbrand": "Con semipestaña", "Zentralfeuer": "Fuego central", "Randfeuer": "Fuego anular",
                   "Stiftfeuer": "De espiga", "Vollmantel": "Blindada", "Teilmantel": "Semiblindada",
                   "Hohlspitz": "Punta hueca", "Mit Papierpflaster": "Calepinada", "Rundkugel": "Bala esférica",
                   "Schrot": "Perdigones", "Keines: Platzpatrone": "Ninguna: cartucho de fogueo",
                   "Schwarzpulver": "Pólvora negra", "Kurzwaffe": "Arma corta", "Langwaffe": "Arma larga",
                   "Standardgeschoss": "Ordinaria", "Panzerbrechend": "Perforante", "Brand": "Incendiaria",
                   "Leuchtspur": "Trazadora", "Reduzierte Ladung": "Carga reducida", "Zerfallend": "Frangible"}
        for key, word in sourced.items():
            self.assertEqual(T[key][ES], word, key)
        # One word per part: no «casquillo» or «proyectil» beside «vaina» and «bala».
        for key, values in T.items():
            self.assertNotRegex(values[ES], r"(?i)casquillo|proyectil|gollete|agolletad", key)

    def test_spanish_addresses_the_reader_as_tu(self):
        """Like the German «du» and the Italian «tu»: no «usted» forms slip into the Spanish texts."""
        for key, values in T.items():
            self.assertNotRegex(values[ES], r"(?i)\b(usted|ustedes|coloque|elija|mida|compruebe|toque)\b", key)
        self.assertIn("mide con cuidado", T["Selten: Ein Treffer ist oft eine ähnliche Patrone, genau nachmessen."][ES])

    def test_spanish_questions_open_with_their_mark(self):
        for key, values in T.items():
            self.assertEqual(values[ES].count("¿"), values[ES].count("?"), key)

    def test_share_extension_texts_pair_up(self):
        self.assertEqual(T["Das Foto konnte nicht übernommen werden."][FR], "Impossible de recevoir la photo.")

    def test_every_translation_is_used(self):
        """A text removed from the app leaves no translation behind (e.g. «Alle Kaliber durchsuchen», 2026-11-14)."""
        from extract_strings import used_keys
        used = used_keys()
        self.assertEqual(sorted(k for k in T if k not in used), [])

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
        # Giotta»; a new year changes it in SettingsView and translations.py).
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

    def test_german_is_swiss(self):
        with open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "RELEASE_NOTES.md"),
                  encoding="utf-8") as f:
            notes = re.findall(r"^### de\n(.*?)(?=^#)", f.read() + "\n#", re.S | re.M)
        self.assertTrue(notes)
        self.assertEqual(swiss_problems(list(T) + notes), [])

    def test_swiss_check_catches_german_spelling(self):
        found = swiss_problems(["Grösse", "Größe", "„Schrot“", "Abstand 1,5 cm", "Öffnet die Webseiten", "Oftmals", "10.9"])
        self.assertEqual([text for text, _ in found], ["Größe", "„Schrot“", "Abstand 1,5 cm", "Öffnet die Webseiten", "Oftmals"])


if __name__ == "__main__":
    unittest.main()
