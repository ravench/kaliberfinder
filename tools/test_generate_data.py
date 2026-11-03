"""Tests for the cartridge data generator: python3 -m unittest discover -s tools -p 'test_*.py'"""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(__file__))
import generate_data  # noqa: E402
from cartridges import CATALOGUE  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def spec(name):
    return next(s for _, items in CATALOGUE for s in items if s["name"] == name)


GP1890 = "7.5x53.5 mm Swiss (GP 1890)"



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
        for name in ("7.5x55 mm Swiss (GP 11)", "9x19 mm", ".22 LR"):
            o = generate_data.outline(spec(name))
            self.assertNotIn("patch", o, name)
            self.assertNotIn("bulletMaterial", o, name)


if __name__ == "__main__":
    unittest.main()
