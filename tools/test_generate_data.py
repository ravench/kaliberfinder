"""Tests for the cartridge data generator: python3 -m unittest discover -s tools -p 'test_*.py'"""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
import generate_data  # noqa: E402
from cartridges import CATALOGUE  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def spec(name):
    return next(s for _, items in CATALOGUE for s in items if s["name"] == name)


GP1890 = "7.5x53.5 mm Swiss (GP 1890)"



class ObsoleteFlagTests(unittest.TestCase):
    """Every entry says whether it is obsolete, so the app can leave those out of matching."""

    def test_every_entry_has_the_flag(self):
        by_name = {c["name"]: c for c in generate_data.build()}
        self.assertTrue(all(isinstance(c["obsolete"], bool) for c in by_name.values()))
        self.assertTrue(by_name[GP1890]["obsolete"])
        self.assertTrue(by_name["10.4x38 mm R Vetterli"]["obsolete"])
        self.assertFalse(by_name["7.5x55 mm Swiss (GP 11)"]["obsolete"])
        self.assertFalse(by_name["5.6 mm GP 90"]["obsolete"])

    def test_gp90_has_the_short_name(self):
        names = {c["name"] for c in generate_data.build()}
        self.assertIn("5.6 mm GP 90", names)
        self.assertNotIn("5.6 mm GP 90 (Swiss)", names)


class RareAndCountryTests(unittest.TestCase):
    """The rare tag and the country come from calibre-data, for the tags on the result rows."""

    def setUp(self):
        self.by_name = {c["name"]: c for c in generate_data.build()}

    def test_every_entry_has_the_rare_flag(self):
        self.assertTrue(all(isinstance(c["rare"], bool) for c in self.by_name.values()))
        self.assertTrue(self.by_name["11x59 mm R Gras"]["rare"])
        self.assertFalse(self.by_name[GP1890]["rare"])
        self.assertFalse(self.by_name["9x19 mm"]["rare"])

    def test_countries_with_flag_emoji(self):
        self.assertEqual(self.by_name["7.5x55 mm Swiss (GP 11)"]["country"],
                         {"code": "CH", "name": "Schweiz", "flag": "🇨🇭"})
        self.assertEqual(self.by_name["9x19 mm"]["country"]["code"], "WW")
        self.assertEqual(self.by_name["9x19 mm"]["country"]["name"], "Weltweit verbreitet")

    def test_former_states_have_no_emoji_and_are_drawn(self):
        self.assertEqual(self.by_name["7.62x54 mm R"]["country"], {"code": "RUE", "name": "Russisches Kaiserreich"})
        self.assertEqual(self.by_name["7.62x39 mm"]["country"]["code"], "SU")
        flagless = {c["country"]["code"] for c in self.by_name.values() if "country" in c and "flag" not in c["country"]}
        self.assertLessEqual(flagless, generate_data.DRAWN_FLAGS)

    def test_drawn_flags_match_the_swift_view(self):
        src = open(os.path.join(ROOT, "Kaliberfinder", "Views", "CalibreTags.swift")).read()
        for code in generate_data.DRAWN_FLAGS:
            self.assertIn(f'case "{code}":', src, code)

    def test_every_catalogue_country_has_a_translated_name(self):
        from cartridges import COUNTRIES
        from translations import T
        self.assertEqual(set(COUNTRIES), set(generate_data.COUNTRY_NAMES))
        for name in generate_data.COUNTRY_NAMES.values():
            self.assertIn(name, T, name)

    def test_no_country_means_no_key(self):
        self.assertNotIn("country", self.by_name[".308 Norma Magnum"])


class BlankFlagTests(unittest.TestCase):
    """Crimped blanks are flagged, so the app can leave out the bullet diameter."""

    def test_only_the_crimped_blank_is_a_blank(self):
        cartridges = generate_data.build()
        self.assertTrue(all(isinstance(c["blank"], bool) for c in cartridges))
        self.assertEqual({c["name"] for c in cartridges if c["blank"]}, {
            ".22 Blank (6.8/11)", ".22 Long Knall", "6 mm Flobert Knall", "9 mm R Knall", ".320 Knall", ".45 Knall"})
        for blank in (c for c in cartridges if c["blank"]):
            self.assertNotIn("bullet", blank["outline"], blank["name"])
            self.assertEqual(blank["dimensions"]["caseLength"], blank["dimensions"]["overallLength"], blank["name"])


class CalibreDataSubmoduleTests(unittest.TestCase):
    """The catalogue comes from the shared calibre-data submodule (github.com/ravench/calibre-data)."""

    def test_catalogue_comes_from_the_submodule(self):
        import cartridges, outline
        data = os.path.join(ROOT, "calibre-data")
        self.assertTrue(os.path.isfile(os.path.join(data, "cartridges.py")), "run: git submodule update --init")
        self.assertEqual(os.path.dirname(os.path.abspath(cartridges.__file__)), data)
        self.assertIs(generate_data.outline, outline.outline)
        self.assertFalse(os.path.exists(os.path.join(ROOT, "tools", "cartridges.py")), "no second copy of the catalogue")

    def test_ci_checks_out_the_submodule(self):
        with open(os.path.join(ROOT, ".gitmodules")) as f:
            self.assertIn("url = https://github.com/ravench/calibre-data", f.read())
        with open(os.path.join(ROOT, ".github", "workflows", "build.yml")) as f:
            build_job = f.read().split("  build:", 1)[1]
        self.assertIn("submodules: true", build_job.split("- run:", 1)[0])

class PatchedBulletTests(unittest.TestCase):
    """GP 1890: paper-patched lead body with a steel-capped round nose."""

    def test_gp1890_has_paper_band_and_steel_cap(self):
        o = generate_data.outline(spec(GP1890))
        self.assertEqual(o["bulletMaterial"], "steel")
        self.assertIn("patch", o)

    def test_paper_band_starts_at_the_case_mouth(self):
        s = spec(GP1890)
        o = generate_data.outline(s)
        mouth = s["oal"] - s["case"]  # y grows downwards from the tip
        ys = [float(p.split()[1]) for p in o["patch"].replace("Z", "").replace("M", "L").split("L") if p.strip()]
        self.assertAlmostEqual(max(ys), mouth, places=2)
        self.assertLess(max(ys) - min(ys), mouth / 2, "most of the visible bullet is the steel cap")

    def test_profile_steps_in_where_the_paper_ends(self):
        s = spec(GP1890)
        r = s["bullet"] / 2
        pts = generate_data.bullet_profile(r, s["case"], s["oal"], s["profile"])
        self.assertEqual(pts[0][0], r)
        self.assertLess(pts[2][0], r, "steel cap is a paper's thickness narrower")
        self.assertEqual(pts[-1], (0, s["oal"]))
        self.assertTrue(all(b[1] >= a[1] for a, b in zip(pts, pts[1:])), "profile runs from base to tip")

    def test_jacketed_bullets_have_no_patch(self):
        for name in ("7.5x55 mm Swiss (GP 11)", "9x19 mm"):
            o = generate_data.outline(spec(name))
            self.assertNotIn("patch", o, name)
            self.assertNotIn("bulletMaterial", o, name)


class BulletMaterialTests(unittest.TestCase):
    """Original bullets and cases (Raven 2026-11-05): lead, paper-patched lead, soft point tips."""

    def test_lead_paper_and_soft_point(self):
        self.assertEqual(generate_data.outline(spec(".22 LR"))["bulletMaterial"], "lead")
        gras = generate_data.outline(spec("11x59 mm R Gras"))
        self.assertEqual(gras["bulletMaterial"], "lead")
        self.assertIn("patch", gras)
        self.assertIn("tip", generate_data.outline(spec("9.3x62 mm")))
        self.assertNotIn("tip", generate_data.outline(spec("7.62x51 mm NATO")))
        self.assertEqual(generate_data.outline(spec(".17 HMR"))["tipMaterial"], "polymer")
        self.assertEqual(generate_data.outline(spec(".277 SIG Fury"))["headMaterial"], "steel")

    def test_case_materials_reach_the_json(self):
        by_name = {c["name"]: c for c in generate_data.build()}
        self.assertEqual(by_name[".44 Henry"]["outline"]["caseMaterial"], "copper")
        self.assertNotIn("caseMaterial", by_name["9x19 mm"]["outline"])
        self.assertTrue(set(generate_data.CASE_COLOURS) >= {c["outline"]["caseMaterial"] for c in by_name.values()
                                                             if "caseMaterial" in c["outline"]})


if __name__ == "__main__":
    unittest.main()
