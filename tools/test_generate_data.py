"""Tests for the cartridge data generator: python3 -m unittest discover -s tools -p 'test_*.py'"""
import json, os, re, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
import generate_data  # noqa: E402
from cartridges import CATALOGUE  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def spec(name):
    return next(s for _, items in CATALOGUE for s in items if s["name"] == name)


GP1890 = "7.5x53.5 mm Swiss (Patrone Modell 1890)"  # renamed in calibre-data #154



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

    def test_every_entry_says_whether_it_is_well_sourced(self):
        """calibre-data's outline.well_sourced decides, never the app (Raven, 2026-11-14): the Developer Options
        switch «Unbelegte Kaliber zeigen» hides the others from the user."""
        self.assertTrue(all(isinstance(c["wellSourced"], bool) for c in self.by_name.values()))
        self.assertTrue(self.by_name["9x19 mm"]["wellSourced"])
        self.assertFalse(self.by_name["6x57 mm Mauser"]["wellSourced"], "its measurements are listed as unsourced")
        self.assertFalse(self.by_name[".45-70 Auto"]["wellSourced"], "no extractor groove in [case_head]")

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
        """The German name is the key, the other three languages come from calibre-data too (localize.py);
        translations.py holds none of them twice."""
        from cartridges import COUNTRIES, COUNTRY_NAMES
        from translations import T
        self.assertEqual(set(COUNTRIES), set(generate_data.COUNTRY_NAMES))
        self.assertEqual(generate_data.COUNTRY_NAMES["GB"], "Grossbritannien")
        for code, name in generate_data.COUNTRY_NAMES.items():
            self.assertEqual(set(COUNTRY_NAMES[code]), {"en", "de", "fr", "it", "es"}, code)
            self.assertNotIn(name, T, name)

    def test_a_miniature_primer_carries_its_measured_diameter(self):
        """The Kolibri rounds' primers are smaller than any reloading size (calibre-data #108)."""
        by_name = {c["name"]: c for c in generate_data.build()}
        self.assertEqual(by_name["2.7 mm Kolibri"]["primer"], {"type": "miniature", "diameter": 2.2})
        self.assertEqual(by_name["9x19 mm"]["primer"], {"type": "small-pistol", "diameter": 4.45})

    def test_no_country_means_no_key(self):
        self.assertNotIn("country", self.by_name["12/70"])
        self.assertNotIn("country", self.by_name[".36 Rundkugel (.375)"])
        self.assertEqual(self.by_name[".308 Norma Magnum"]["country"]["code"], "SE")


class BlankFlagTests(unittest.TestCase):
    """Blanks are flagged, so the app leaves out the bullet diameter and compares a photo with them whole."""

    def test_the_blanks_are_the_ones_calibre_data_calls_blanks(self):
        cartridges = generate_data.build()
        self.assertTrue(all(isinstance(c["blank"], bool) for c in cartridges))
        # Star-crimped ones, and the ones closed inside the case (9 mm PA Blanc, 8 mm and .315 Blanc): the
        # catalogue's own rule (cartridges.is_blank), not a second one here that knew only the crimp.
        # Sorted, not in catalogue order: where the blanks stand in the catalogue is calibre-data's business.
        # Named as their C.I.P. sheets since calibre-data #168; the old names stay as display aliases.
        self.assertEqual(sorted(c["name"] for c in cartridges if c["blank"]),
                         sorted([".22 SH (5.6/11)", "9 mm PA Blanc", "8 mm Blanc", ".315 Blanc", "9 mm R Blanc",
                                 ".320 Court Blanc", ".45 K Blanc", ".22 Long Blanc", "6 mm Flobert Blanc",
                                 "6.8/11"]))  # the Hilti power-tool load (calibre-data #204)
        self.assertIn("9 mm P.A.K.", next(c for c in cartridges if c["name"] == "9 mm PA Blanc")["displayAliases"])
        # A bullet seated inside the case is still a bullet.
        for name in (".32 S&W Long Wadcutter", "7.62x38 mm R Nagant"):
            self.assertFalse(next(c for c in cartridges if c["name"] == name)["blank"], name)
        for blank in (c for c in cartridges if c["blank"]):
            self.assertNotIn("bullet", blank["outline"])
            self.assertEqual(blank["dimensions"]["caseLength"], blank["dimensions"]["overallLength"])
        # The rule is for cartridges: a shot shell or a loose ball whose measurements coincide is no blank.
        shell = {"kind": generate_data.SHOT, "profile": "flat", "rim": 20.0, "base": 20.0, "neck": 20.0, "bullet": 20.0,
                 "case": 65.0, "oal": 65.0}
        self.assertFalse(generate_data.blank(shell))
        self.assertTrue(generate_data.blank({**shell, "kind": "rimless"}))


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
            tools_job, build_job = f.read().split("  tools:", 1)[1].split("  build:", 1)
        self.assertIn("submodules: true", build_job.split("- run:", 1)[0])
        # A pull request's pointer is main's or newer, so a merge cannot revert a bump (tools/bump_data.py).
        self.assertIn("merge-base --is-ancestor", tools_job)
        # A pointer from before the public repository's history is not compared (2026-11-22).
        self.assertIn('cat-file -e "$main^{commit}"', tools_job)

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
        self.assertLess(max(ys) - min(ys), mouth, "the paper stops before the tip (calibre-data #113 draws it to the 1892 drawing)")

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
            self.assertNotIn("patch", generate_data.outline(spec(name)), name)
        # A copper jacket names no material; the GP 11's silver cupronickel jacket does (calibre-data #115).
        self.assertNotIn("bulletMaterial", generate_data.outline(spec("9x19 mm")))
        self.assertEqual(generate_data.outline(spec("7.5x55 mm Swiss (GP 11)")).get("bulletMaterial"), "cupronickel")


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
        self.assertEqual(by_name["9x19 mm"]["outline"]["currentCaseMaterials"], ["steel", "aluminium"])
        self.assertTrue(set(generate_data.CASE_COLOURS) >= {c["outline"]["caseMaterial"] for c in by_name.values()
                                                             if "caseMaterial" in c["outline"]})


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
        # Named by what the members share (calibre-data #181), no longer after the parent.
        self.assertEqual(win, {"name": "7.62x51 mm", "differs": ["load"],
                               "calibres": [".308 Winchester", "7.62x51 mm NATO"]})

    def test_groups_carry_the_database_s_name(self):
        # The parent's name or the family's (calibre-data lookalikes.toml); the app showed the parent's for
        # every group, so the 7.63x25 mm rounds stood under the obsolete .30 Borchardt (review 2026-11-13).
        by_name = {c["name"]: c for c in generate_data.build()}
        groups = generate_data.lookalikes(set(by_name))
        names = [g["name"] for g in groups]
        self.assertEqual(len(names), len(set(names)), "two groups of one name")
        mauser = next(g for g in groups if "7.63x25 mm Mauser" in g["calibres"])
        self.assertEqual((mauser["name"], mauser["calibres"][0]), ("7.63x25 mm", ".30 Borchardt"))
        self.assertEqual(next(g for g in groups if "8x57 mm IS" in g["calibres"])["name"], "8x57 mm")
        for g in groups:  # a calibre's name names its own group only
            self.assertTrue(g["name"] not in by_name or g["name"] in g["calibres"], g["name"])

    def test_rimfire_and_centrefire_versions_are_grouped_by_ignition(self):
        by_name = {c["name"]: c for c in generate_data.build()}
        groups = generate_data.lookalikes(set(by_name))
        for rimfire, centrefire in [("10.4x38 mm R Vetterli", "10.4x38 mm R Vetterli Centrefire"),
                                    (".44 Henry", ".44 Henry Centrefire"), (".32 Long Rimfire", ".32 Long Centrefire")]:
            self.assertEqual(by_name[rimfire]["kind"], "rimfire")
            self.assertNotIn("primer", by_name[rimfire])
            self.assertEqual(by_name[centrefire]["kind"], "rimmed")
            self.assertIn("primer", by_name[centrefire])
            group = next(g for g in groups if rimfire in g["calibres"])  # the .32s share theirs with other lengths
            self.assertIn("ignition", group["differs"])
            self.assertIn(centrefire, group["calibres"])

    def test_unknown_member_fails_loudly(self):
        with self.assertRaises(AssertionError):
            generate_data.lookalikes({"9x19 mm"})


class CatalogueOnlyDataTests(unittest.TestCase):
    """calibre-data keeps some data for the catalogue only (fired-by lists). The app reads none of it: the
    same fields as before, and its six categories plus the cannon rounds behind a developer switch."""

    def test_catalogue_only_data_stays_out(self):
        from cartridges import FIRED_BY
        built = generate_data.build()
        self.assertTrue(FIRED_BY)
        self.assertEqual({c["category"] for c in built},
                         {"Randfeuer", "Kurzwaffe", "Langwaffe", "Schwarzpulver", "Flinte", "Luftdruck", "Kanone"})
        self.assertEqual(set().union(*built), {"id", "name", "category", "kind", "aliases", "displayAliases",
                                               "obsolete", "rare", "country", "worldwide", "blank", "wellSourced",
                                               "dimensions", "outline", "primer", "colourCodes", "sources"})

    def test_cannon_rounds_are_partial_entries(self):
        """Raven, 2026-11-13: the cannon category behind «Kanonenkaliber zeigen». A measurement no source gives
        is 0, and such a round gets no drawing, only the box's size; a complete one is drawn as usual."""
        cannon = [c for c in generate_data.build() if c["category"] == "Kanone"]
        self.assertGreaterEqual(len(cannon), 27)
        by_name = {c["name"]: c for c in cannon}
        partial = by_name["57x121 mm R"]
        self.assertEqual((partial["dimensions"]["neck"], partial["dimensions"]["overallLength"]), (0, 0))
        self.assertEqual(set(partial["outline"]), {"width", "height"})
        self.assertEqual(partial["outline"]["height"], partial["dimensions"]["caseLength"])
        vulcan = by_name["20x102 mm"]
        self.assertEqual(vulcan["dimensions"]["overallLength"], 168.0)
        self.assertIn("case", vulcan["outline"])
        self.assertTrue(all("primer" not in c or c["primer"]["diameter"] > 0 for c in cannon))
        # calibre-data #183/#184 completed 15 of them from specimen drawings; the 57 mm rounds are still partial.
        self.assertTrue(vulcan["wellSourced"])
        self.assertFalse(partial["wellSourced"])

    def test_swiss_match_reaches_the_json(self):
        """calibre-data #77: the 6x47 mm SM (Swiss Match) from its C.I.P. sheet, a Swiss rifle round with
        a large rifle primer."""
        sm = next(c for c in generate_data.build() if c["name"] == "6x47 mm SM")
        self.assertEqual((sm["category"], sm["country"]["code"], sm["primer"]["type"]), ("Langwaffe", "CH", "large-rifle"))
        self.assertEqual((sm["dimensions"]["caseLength"], sm["dimensions"]["overallLength"], sm["dimensions"]["bullet"]),
                         (47.0, 66.0, 6.18))
        self.assertIn("swiss match", sm["aliases"])
        groups = generate_data.lookalikes({c["name"] for c in generate_data.build()})
        self.assertIn({"name": "6x47 mm SM", "differs": ["bore"], "calibres": ["6x47 mm SM", "6.5x47 mm Lapua"]}, groups)

    def test_a_belt_wider_than_the_rim_reaches_the_json(self):
        """calibre-data #150: the .378 Weatherby head's belt is wider than its rim, and the drawing as wide
        as the belt. The H&H head's belt is as wide as its rim and has no entry."""
        by_name = {c["name"]: c for c in generate_data.build()}
        d = by_name[".378 Weatherby Magnum"]["dimensions"]
        self.assertEqual(d["belt"], 15.33)
        self.assertGreater(d["belt"], max(d["rim"], d["base"]))
        self.assertEqual(by_name[".378 Weatherby Magnum"]["outline"]["width"], d["belt"])
        self.assertNotIn("belt", by_name[".300 H&H Magnum"]["dimensions"])

    def test_cip_corrections_reach_the_json(self):
        """calibre-data #68: the PRC rounds from their C.I.P. sheets."""
        by_name = {c["name"]: c["dimensions"] for c in generate_data.build()}
        self.assertEqual(by_name["6.5 PRC"]["overallLength"], 75.06)
        self.assertEqual((by_name["7 mm PRC"]["caseLength"], by_name["7 mm PRC"]["overallLength"]), (57.91, 84.84))


SWISS = {"code": "CH", "name": "Schweiz", "flag": "🇨🇭"}


class ColourCodeTests(unittest.TestCase):
    """The tip and base colour codes of calibre-data reach the JSON, for the calibre page (Raven, 2026-11-11)."""

    def setUp(self):
        self.by_name = {c["name"]: c for c in generate_data.build()}

    def test_codes_with_their_colours_meanings_loads_and_countries(self):
        nato = self.by_name["7.62x51 mm NATO"]["colourCodes"]
        self.assertEqual([(t["part"], t["colours"]) for t in nato],
                         [("tip", ["black"]), ("tip", ["orange"]), ("tip", ["purple"]),
                          ("annulus", ["purple"]), ("annulus", ["red"]), ("annulus", ["yellow"])])
        self.assertEqual(nato[-1]["meaning"], ["proof"])
        self.assertEqual(nato[0]["part"], "tip")
        self.assertEqual(nato[0]["meaning"], ["armour-piercing"])
        self.assertEqual(nato[0]["description"], "M61 and M993")
        self.assertEqual(nato[0]["countries"], [{"code": "US", "name": "USA", "flag": "🇺🇸"}])
        self.assertNotIn("sources", nato[0])
        bmg = self.by_name[".50 BMG"]["colourCodes"]
        self.assertIn(["red", "silver"], [t["colours"] for t in bmg], "from the tip down")

    def test_every_entry_has_the_list_and_most_are_empty(self):
        self.assertTrue(all(isinstance(c["colourCodes"], list) for c in self.by_name.values()))
        self.assertEqual(self.by_name["9x19 mm"]["colourCodes"], [])
        gp11 = self.by_name["7.5x55 mm Swiss (GP 11)"]["colourCodes"]
        # In the app's other languages where calibre-data translates the description (Raven, 2026-11-18); a bare
        # designation has none, and the key is left out.
        self.assertEqual(gp11[1]["descriptions"], {"de": "Leuchtspur, ältere Kennzeichnung: ganzer Boden lackiert",
                                                   "fr": "Traçant, ancien marquage : tout le culot laqué",
                                                   "it": "Tracciante, vecchia marcatura: tutto il fondello laccato",
                                                   "es": "Trazadora, marca antigua: todo el culote lacado"})
        self.assertTrue(all(sorted(c["descriptions"]) == ["de", "es", "fr", "it"] for c in gp11))
        self.assertNotIn("descriptions", next(c for c in self.by_name[".50 BMG"]["colourCodes"] if c.get("description") == "M2"))
        self.assertEqual([{k: v for k, v in c.items() if k != "descriptions"} for c in gp11],
                         [{"part": "tip", "colours": ["red"], "meaning": ["tracer"],
                           "description": "Tracer M.1911 (Leuchtspurpatrone)", "countries": [SWISS]},
                          {"part": "base", "colours": ["red"], "meaning": ["tracer"],
                           "description": "Tracer, the older marking: the whole base lacquered", "countries": [SWISS]},
                          {"part": "base", "colours": ["purple"], "meaning": ["armour-piercing"],
                           "description": "Armour-piercing, no longer in service (1980)", "countries": [SWISS]}])

    def test_a_former_state_is_drawn(self):
        soviet = next(t for t in self.by_name["7.62x54 mm R"]["colourCodes"] if any(c["code"] == "SU" for c in t["countries"]))
        self.assertEqual([c for c in soviet["countries"] if c["code"] == "SU"], [{"code": "SU", "name": "Sowjetunion"}])


class SourcesTests(unittest.TestCase):
    """Each calibre's sources page (Raven, 2026-11-15): the works its values come from, grouped by the parts of
    the calibre page they back, with pages and links."""

    @classmethod
    def setUpClass(cls):
        cls.works = {}
        cls.by_name = {c["name"]: c for c in generate_data.build(cls.works)}
        cls.list = [json.loads(w) for w in cls.works]

    def page(self, name):
        return [(g["parts"], [(self.list[r["work"]].get("title"), r.get("pages")) for r in g["refs"]])
                for g in self.by_name[name]["sources"]]

    def test_gp11_groups_follow_the_calibre_page(self):
        self.assertEqual(self.page("7.5x55 mm Swiss (GP 11)"), [
            (["mm"], [("Cartridges of the World", ["573"]), ("C.I.P.", None),
                      ("Hornady Handbook of Cartridge Reloading", ["469"])]),
            (["shoulder_angle", "case_head"], [("C.I.P.", None)]),
            (["primer"], [("Wikipedia: 7.5×55mm Swiss", None)]),
            (["bullet"], [("Cartridges of the World", ["545"]), ("Swiss Magazine Loading Rifles 1869 to 1958", ["50"])]),
            # C.I.P. backs the origin too, the sheet's country, since calibre-data #190.
            (["origin"], [("Wikipedia: 7.5×55mm Swiss", None), ("Ammo Encyclopedia", ["513"]), ("C.I.P.", None)]),
            (["colour_codes"], [("Military Small Arms Ammunition of the World, 1945-1980", ["76", "77", "86"])]),
        ])

    def test_a_nose_length_has_its_own_sources(self):
        # The GP 90's nose comes from the AECC drawing of the 5.56x45 mm (calibre-data #197), its [mm] from C.I.P./SAAMI.
        nose = [g for g in self.by_name["5.6 mm GP 90"]["sources"] if "nose" in g["parts"]]
        self.assertEqual([(g["parts"], [self.list[r["work"]]["url"] for r in g["refs"]]) for g in nose],
                         [(["nose"], ["https://municion.org/producto/556-x-45-otan/"])])
        self.assertFalse(any("nose" in g["parts"] for g in self.by_name[".308 Winchester"]["sources"]), "no nose, no row")

    def test_a_book_is_one_work_with_its_year_and_author(self):
        cotw = next(w for w in self.list if w.get("title") == "Cartridges of the World" and w["year"] == 2026)
        self.assertEqual(cotw, {"title": "Cartridges of the World", "detail": "W. Todd Woodard, Corey Graff", "year": 2026})
        self.assertEqual(len([w for w in self.list if w == cotw]), 1, "pages stay on the refs")

    def test_shops_and_load_data_are_named_but_not_linked(self):
        # «Quellen» does not send its reader to a page that sells cartridges, brass or reamers, or to load data
        # (Raven, 2026-11-18): the source is still named, as text.
        self.assertEqual(generate_data.UNLINKED_HOSTS, {"ammo-one1.com", "starlinebrass.com", "pacifictoolandgauge.com",
                                                        "xxlreloading.com", "hodgdonreloading.com", "loaddata.com"})
        for host in generate_data.UNLINKED_HOSTS:
            for prefix in ("", "www."):
                self.assertEqual(generate_data.work(f"https://{prefix}{host}/product/x-brass/")[0], {"title": host, "detail": "x-brass"})
        unlinked = [w for w in self.list if w.get("title") in generate_data.UNLINKED_HOSTS]
        self.assertGreaterEqual(len(unlinked), 20)
        self.assertEqual({w["title"] for w in unlinked}, generate_data.UNLINKED_HOSTS, "a host no calibre cites any more: drop it")
        linked = [w["url"] for w in self.list if "url" in w]
        self.assertFalse([u for u in linked if any(host in u for host in generate_data.UNLINKED_HOSTS)])
        self.assertGreater(len(linked), 1000)

    def test_web_sources_link_and_name_the_publisher(self):
        cip, page = generate_data.work("https://bobp.cip-bobp.org/uploads/tdcc/tab-i/tabical-en-page46.pdf")
        self.assertEqual(cip, {"title": "C.I.P.", "detail": "Tab. I · tabical-en-page46",
                               "url": "https://bobp.cip-bobp.org/uploads/tdcc/tab-i/tabical-en-page46.pdf"})
        self.assertIsNone(page)
        self.assertEqual(generate_data.work("https://www.example.com/x")[0],
                         {"title": "example.com", "detail": "x", "url": "https://www.example.com/x"})
        self.assertEqual(generate_data.work("https://municion.org/producto/22-long-rifle/")[0]["detail"], "22-long-rifle",
                         "two pages of one site differ")
        self.assertEqual(generate_data.work("https://en.wikipedia.org/wiki/.22_Long_Rifle")[0]["title"], "Wikipedia: .22 Long Rifle")

    def test_a_caliper_measurement_carries_its_date(self):
        self.assertEqual(generate_data.work("measured:raven 2026-11-08"), ({"measured": "2026-11-08"}, None))

    def test_parts_the_page_does_not_show_are_left_out(self):
        parts = {p for c in self.by_name.values() for g in c["sources"] for p in g["parts"]}
        self.assertLessEqual(parts, set(generate_data.SOURCE_PARTS))
        self.assertNotIn("introduced", parts)
        rimfire = self.by_name[".22 LR"]
        self.assertFalse(any("primer" in g["parts"] for g in rimfire["sources"]), "no primer row, no primer sources")

    def test_own_sources_of_flat_mouth_and_crimp(self):
        # calibre-data #204/#205: values read off a drawing or Raven's photos are credited apart from the [mm] sheets.
        def parts(name):
            return {p for g in self.by_name[name]["sources"] for p in g["parts"]}
        self.assertIn("flat", parts(".45 Colt"))
        self.assertLessEqual({"mouth", "crimp_length"}, parts("6.8/11"))
        self.assertNotIn("crimp_length", parts(".22 LR"))

    def test_almost_every_calibre_cites_its_measurements(self):
        missing = [n for n, c in self.by_name.items() if not any("mm" in g["parts"] for g in c["sources"])]
        self.assertLessEqual(len(missing), 5, missing)

    def test_every_ref_points_at_a_work(self):
        refs = [r["work"] for c in self.by_name.values() for g in c["sources"] for r in g["refs"]]
        self.assertEqual(set(refs), set(range(len(self.list))))


if __name__ == "__main__":
    unittest.main()
