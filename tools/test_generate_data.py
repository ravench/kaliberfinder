"""Tests for the cartridge data generator: python3 -m unittest discover -s tools -p 'test_*.py'"""
import os, re, sys, unittest

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
        # Raven 2026-11-07: worldwide rounds keep the state that introduced them
        self.assertEqual(self.by_name["9x19 mm"]["country"], {"code": "DE", "name": "Deutschland", "flag": "🇩🇪"})
        self.assertEqual(self.by_name[".338 Lapua Magnum"]["country"]["name"], "Finnland")

    def test_worldwide_is_a_separate_flag(self):
        self.assertTrue(all(isinstance(c["worldwide"], bool) for c in self.by_name.values()))
        self.assertTrue(self.by_name["9x19 mm"]["worldwide"])  # German and worldwide
        self.assertTrue(self.by_name["12/70"]["worldwide"])  # a gauge: worldwide without a country
        self.assertFalse(self.by_name["7.62x39 mm"]["worldwide"])
        self.assertFalse(self.by_name[GP1890]["worldwide"])
        self.assertNotIn("WW", generate_data.COUNTRY_NAMES)

    def test_former_states_have_no_emoji_and_are_drawn(self):
        self.assertEqual(self.by_name["7.62x54 mm R"]["country"], {"code": "RUE", "name": "Russisches Kaiserreich"})
        self.assertEqual(self.by_name["7.62x39 mm"]["country"]["code"], "SU")
        flagless = {c["country"]["code"] for c in self.by_name.values() if "country" in c and "flag" not in c["country"]}
        self.assertLessEqual(flagless, generate_data.DRAWN_FLAGS)
        # calibre-data #51 (2026-11-08): unions are origins too, and the flag tilts to the main adopter
        self.assertEqual(self.by_name["5.56x45 mm NATO"]["country"], {"code": "NATO", "name": "NATO"})
        self.assertEqual(self.by_name["7.65x53 mm Argentine"]["country"],
                         {"code": "AR", "name": "Argentinien", "flag": "🇦🇷"})
        self.assertEqual(self.by_name["9x21 mm IMI"]["country"]["name"], "Italien")
        self.assertNotIn("IL", generate_data.COUNTRY_NAMES)

    def test_drawn_flags_match_the_swift_view(self):
        src = open(os.path.join(ROOT, "Kaliberfinder", "Views", "CalibreTags.swift")).read()
        codes = re.search(r"static let codes: Set<String> = \[(.*)\]", src).group(1)
        for code in generate_data.DRAWN_FLAGS:
            self.assertIn(f'case "{code}":', src, code)
            self.assertIn(f'"{code}"', codes, code)  # DrawnFlag.codes must list it too

    def test_every_catalogue_country_has_a_translated_name(self):
        from cartridges import COUNTRIES
        from translations import T
        self.assertEqual(set(COUNTRIES), set(generate_data.COUNTRY_NAMES))
        for name in generate_data.COUNTRY_NAMES.values():
            self.assertIn(name, T, name)

    def test_no_country_means_no_key(self):
        self.assertNotIn("country", self.by_name["12/70"])
        self.assertNotIn("country", self.by_name[".36 Rundkugel (.375)"])
        self.assertEqual(self.by_name[".308 Norma Magnum"]["country"]["code"], "SE")


class BlankFlagTests(unittest.TestCase):
    """Crimped blanks are flagged, so the app can leave out the bullet diameter."""

    def test_only_the_crimped_blank_is_a_blank(self):
        cartridges = generate_data.build()
        self.assertTrue(all(isinstance(c["blank"], bool) for c in cartridges))
        # The flat-capped 8 mm and .315 Knall are drawn like shot shells, not as crimped blanks.
        self.assertEqual([c["name"] for c in cartridges if c["blank"]],
                         [".22 Blank (6.8/11)", "9 mm R Knall", ".320 Knall", ".45 Knall",
                          ".22 Long Knall", "6 mm Flobert Knall"])
        for blank in (c for c in cartridges if c["blank"]):
            self.assertNotIn("bullet", blank["outline"])
            self.assertEqual(blank["dimensions"]["caseLength"], blank["dimensions"]["overallLength"])


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

    def test_catalogue_names_the_commit_it_was_read_from(self):
        """Settings show the calibre-data commit of the app's catalogue (CartridgeCatalog.source)."""
        import json, subprocess
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=generate_data.DATA, text=True).strip()
        with open(generate_data.OUT) as f:
            stored = json.load(f)["calibreData"]
        self.assertEqual(stored["commit"], head, "run: python3 tools/generate_data.py")
        # The committer date with its offset, which the app decodes as ISO 8601.
        self.assertRegex(stored["date"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$",
                         "a numeric offset, never Z, whichever git version wrote it")

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


class BBTests(unittest.TestCase):
    """Steel and airsoft BBs: loose balls drawn in steel or plastic (calibre-data #47)."""

    def test_bbs_are_balls_with_their_material(self):
        by_name = {c["name"]: c for c in generate_data.build()}
        for name, material in (("4.4 mm Stahl-BB (.177 BB)", "steel"), ("6 mm Airsoft-BB", "plastic"),
                               ("8 mm Airsoft-BB", "plastic")):
            self.assertEqual(by_name[name]["kind"], "ball", name)
            self.assertEqual(by_name[name]["category"], "Luftdruck", name)
            self.assertEqual(by_name[name]["outline"]["bulletMaterial"], material, name)
        self.assertNotIn("bulletMaterial", by_name[".44 Rundkugel (.454)"]["outline"])


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
        self.assertEqual(by_name[".45-70 Government"]["outline"]["currentCaseMaterials"], ["brass"])
        self.assertEqual(by_name["9x19 mm"]["outline"]["currentCaseMaterials"], ["steel"])
        self.assertTrue(set(generate_data.CASE_COLOURS) >= {c["outline"]["caseMaterial"] for c in by_name.values()
                                                             if "caseMaterial" in c["outline"]})


if __name__ == "__main__":
    unittest.main()


class LookalikeTests(unittest.TestCase):
    """The lookalike groups go into the JSON so the app can show a calibre's group."""

    def test_groups_name_known_calibres_once(self):
        names = {c["name"] for c in generate_data.build()}
        groups = generate_data.lookalikes(names)
        self.assertGreaterEqual(len(groups), 20)
        members = [n for g in groups for n in g["calibres"]]
        self.assertEqual(len(members), len(set(members)), "a calibre in two groups")
        self.assertTrue(all(len(g["calibres"]) >= 2 and g["differs"] for g in groups))
        win = next(g for g in groups if ".308 Winchester" in g["calibres"])
        self.assertEqual(win, {"differs": ["load"], "calibres": [".308 Winchester", "7.62x51 mm NATO"]})

    def test_rimfire_and_centrefire_versions_are_grouped_by_ignition(self):
        by_name = {c["name"]: c for c in generate_data.build()}
        groups = generate_data.lookalikes(set(by_name))
        for rimfire, centrefire in [("10.4x38 mm R Vetterli", "10.4x38 mm R Vetterli Centrefire"),
                                    (".44 Henry", ".44 Henry Centrefire"), (".32 Long Rimfire", ".32 Long Centrefire")]:
            self.assertEqual(by_name[rimfire]["kind"], "rimfire")
            self.assertNotIn("primer", by_name[rimfire])
            self.assertEqual(by_name[centrefire]["kind"], "rimmed")
            self.assertIn("primer", by_name[centrefire])
            self.assertIn({"differs": ["ignition"], "calibres": [rimfire, centrefire]}, groups)

    def test_unknown_member_fails_loudly(self):
        with self.assertRaises(AssertionError):
            generate_data.lookalikes({"9x19 mm"})


class CatalogueOnlyDataTests(unittest.TestCase):
    """calibre-data keeps some data for the catalogue only (tip colour codes; later also fired-by lists and
    cannon rounds). The app reads none of it: the same six categories and fields as before."""

    def test_catalogue_only_data_stays_out(self):
        from cartridges import FIRED_BY
        built = generate_data.build()
        self.assertTrue(FIRED_BY)
        self.assertEqual({c["category"] for c in built},
                         {"Randfeuer", "Kurzwaffe", "Langwaffe", "Schwarzpulver", "Flinte", "Luftdruck"})
        self.assertEqual(set().union(*built), {"id", "name", "category", "kind", "aliases", "displayAliases",
                                               "headstamps", "obsolete", "rare", "country", "worldwide", "blank",
                                               "dimensions", "outline", "primer", "tipColours"})

    def test_swiss_match_reaches_the_json(self):
        """calibre-data #77: the 6x47 mm SM (Swiss Match) from its C.I.P. sheet, a Swiss rifle round with
        a large rifle primer."""
        sm = next(c for c in generate_data.build() if c["name"] == "6x47 mm SM")
        self.assertEqual((sm["category"], sm["country"]["code"], sm["primer"]["type"]), ("Langwaffe", "CH", "large-rifle"))
        self.assertEqual((sm["dimensions"]["caseLength"], sm["dimensions"]["overallLength"], sm["dimensions"]["bullet"]),
                         (47.0, 66.0, 6.18))
        self.assertIn("swiss match", sm["aliases"])
        groups = generate_data.lookalikes({c["name"] for c in generate_data.build()})
        self.assertIn({"differs": ["bore"], "calibres": ["6x47 mm SM", "6.5x47 mm Lapua"]}, groups)

    def test_cip_corrections_reach_the_json(self):
        """calibre-data #68: the PRC rounds from their C.I.P. sheets."""
        by_name = {c["name"]: c["dimensions"] for c in generate_data.build()}
        self.assertEqual(by_name["6.5 PRC"]["overallLength"], 75.06)
        self.assertEqual((by_name["7 mm PRC"]["caseLength"], by_name["7 mm PRC"]["overallLength"]), (57.91, 84.84))


class TipColourTests(unittest.TestCase):
    """The tip colour codes of calibre-data reach the JSON, for the calibre page (Raven, 2026-11-11)."""

    def setUp(self):
        self.by_name = {c["name"]: c for c in generate_data.build()}

    def test_codes_with_their_colours_meanings_loads_and_countries(self):
        nato = self.by_name["7.62x51 mm NATO"]["tipColours"]
        self.assertEqual([t["colours"] for t in nato], [["black"], ["orange"], ["purple"]])
        self.assertEqual(nato[0]["meaning"], ["armour-piercing"])
        self.assertEqual(nato[0]["description"], "M61 and M993")
        self.assertEqual(nato[0]["countries"], [{"code": "US", "name": "USA", "flag": "🇺🇸"}])
        self.assertNotIn("sources", nato[0])
        bmg = self.by_name[".50 BMG"]["tipColours"]
        self.assertIn(["red", "silver"], [t["colours"] for t in bmg], "from the tip down")

    def test_every_entry_has_the_list_and_most_are_empty(self):
        self.assertTrue(all(isinstance(c["tipColours"], list) for c in self.by_name.values()))
        self.assertEqual(self.by_name["9x19 mm"]["tipColours"], [])
        self.assertEqual(self.by_name["7.5x55 mm Swiss (GP 11)"]["tipColours"],
                         [{"colours": ["red"], "meaning": ["tracer"], "description": "Tracer M.1911 (Leuchtspurpatrone)",
                           "countries": [{"code": "CH", "name": "Schweiz", "flag": "🇨🇭"}]}])

    def test_a_former_state_is_drawn(self):
        soviet = next(t for t in self.by_name["7.62x54 mm R"]["tipColours"] if any(c["code"] == "SU" for c in t["countries"]))
        self.assertEqual([c for c in soviet["countries"] if c["code"] == "SU"], [{"code": "SU", "name": "Sowjetunion"}])
