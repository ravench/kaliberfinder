"""Unit tests for tools/app_icon.py and the installed AppIcon asset set.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import json, os, unittest

import app_icon


class AppIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        by_id = {c["id"]: c for c in json.load(open(app_icon.DATA))["cartridges"]}
        cls.cartridges = [by_id[i] for i in app_icon.CARTRIDGES]

    def test_three_different_cartridges(self):
        self.assertEqual(len(set(app_icon.CARTRIDGES)), 3)
        self.assertEqual(len(self.cartridges), 3)

    def test_every_appearance_in_both_looks(self):
        for palettes in (app_icon.MEASURE, app_icon.NAVY):
            self.assertEqual(set(palettes), {"", "-Dark", "-Tinted"})

    def test_default_icon_has_no_ruler(self):
        for p in app_icon.MEASURE.values():
            svg = app_icon.icon(self.cartridges, p)
            self.assertNotIn(p["ruler"], svg)
            self.assertIn("stroke-dasharray", svg)  # the measuring line stays

    def test_light_is_beige_dark_is_navy_tinted_is_black(self):
        bgs = {k: p["bg"] for k, p in app_icon.MEASURE.items()}
        self.assertEqual(bgs, {"": app_icon.BEIGE, "-Dark": app_icon.NAVY_BG, "-Tinted": app_icon.BLACK})

    def test_measuring_line_differs_from_background(self):
        for p in app_icon.MEASURE.values():
            self.assertNotIn(p["measure"], p["bg"])

    def test_no_shadow_under_the_cartridges(self):
        for p in app_icon.MEASURE.values():
            self.assertNotIn("<ellipse", app_icon.icon(self.cartridges, p))

    def test_ruler_is_optional(self):
        p = app_icon.MEASURE[""]
        with_ruler = app_icon.icon(self.cartridges, p, ruler=True)
        without = app_icon.icon(self.cartridges, p, ruler=False)
        self.assertIn(p["ruler"], with_ruler)
        self.assertNotIn(p["ruler"], without)

    def test_measuring_line_only_in_measure_look(self):
        self.assertIn("stroke-dasharray", app_icon.icon(self.cartridges, app_icon.MEASURE[""]))
        self.assertNotIn("stroke-dasharray", app_icon.icon(self.cartridges, app_icon.NAVY[""]))

    def test_drawing_stays_inside_the_icon(self):
        svg = app_icon.icon(self.cartridges, app_icon.MEASURE[""])
        self.assertTrue(svg.startswith("<svg") and svg.endswith("</svg>"))
        widths = sum(c["outline"]["width"] for c in self.cartridges) * app_icon.SCALE
        self.assertLess(widths + 2 * app_icon.GAP + 90, app_icon.S - 200)
        tallest = max(c["outline"]["height"] for c in self.cartridges) * app_icon.SCALE
        self.assertGreater(790 - tallest, 60)

    def test_asset_set_has_light_dark_and_tinted(self):
        contents = json.load(open(os.path.join(app_icon.ASSETS, "Contents.json")))
        looks = {}
        for image in contents["images"]:
            value = next((a["value"] for a in image.get("appearances", []) if a["appearance"] == "luminosity"), "")
            looks[value] = image["filename"]
            self.assertTrue(os.path.exists(os.path.join(app_icon.ASSETS, image["filename"])), image["filename"])
        self.assertEqual(looks, {"": "AppIcon.png", "dark": "AppIcon-Dark.png", "tinted": "AppIcon-Tinted.png"})


if __name__ == "__main__":
    unittest.main()
