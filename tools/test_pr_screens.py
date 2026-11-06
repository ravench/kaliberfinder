"""Unit tests for tools/pr_screens.py and the PR screens in the Build workflow.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

import pr_screens

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RT = "com.apple.CoreSimulator.SimRuntime.iOS-"


def write(folder, name, data):
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), "wb") as f:
        f.write(data)


class PickIphoneTests(unittest.TestCase):
    def test_newest_runtime_and_plain_pro(self):
        simctl = {"devices": {
            RT + "18-5": [{"name": "iPhone 16 Pro", "udid": "OLD", "isAvailable": True}],
            RT + "26-0": [
                {"name": "iPad Pro 13-inch (M5)", "udid": "IPAD", "isAvailable": True},
                {"name": "iPhone 17", "udid": "PLAIN", "isAvailable": True},
                {"name": "iPhone 17 Pro Max", "udid": "MAX", "isAvailable": True},
                {"name": "iPhone 17 Pro", "udid": "PRO", "isAvailable": True},
            ],
        }}
        self.assertEqual(pr_screens.pick_iphone(simctl), "PRO")

    def test_skips_unavailable_and_needs_an_iphone(self):
        simctl = {"devices": {RT + "26-0": [
            {"name": "iPhone 17 Pro", "udid": "GONE", "isAvailable": False},
            {"name": "iPhone 17", "udid": "OK", "isAvailable": True},
        ]}}
        self.assertEqual(pr_screens.pick_iphone(simctl), "OK")
        with self.assertRaises(ValueError):
            pr_screens.pick_iphone({"devices": {RT + "26-0": [{"name": "iPad (A16)", "udid": "X"}]}})


class ChangesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.before = os.path.join(self.tmp.name, "before")
        self.after = os.path.join(self.tmp.name, "after")
        write(self.before, "01-Tagebuch.png", b"same")
        write(self.after, "01-Tagebuch.png", b"same")
        write(self.before, "02-Eintrag.png", b"old")
        write(self.after, "02-Eintrag.png", b"new")
        write(self.before, "03-Weg.png", b"x")
        write(self.after, "04-Neu.png", b"y")

    def tearDown(self):
        self.tmp.cleanup()

    def test_only_differing_screens(self):
        self.assertEqual(pr_screens.changes(self.before, self.after),
                         [("02-Eintrag.png", "changed"), ("03-Weg.png", "gone"), ("04-Neu.png", "new")])

    def test_missing_base_shows_everything_as_new(self):
        missing = os.path.join(self.tmp.name, "nothing")
        self.assertEqual([s for _, s in pr_screens.changes(missing, self.after)], ["new"] * 3)

    def test_collect_copies_changed_screens_only(self):
        out = os.path.join(self.tmp.name, "out")
        summary = pr_screens.collect(self.before, self.after, out)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "before"))), ["02-Eintrag.png", "03-Weg.png"])
        self.assertEqual(sorted(os.listdir(os.path.join(out, "after"))), ["02-Eintrag.png", "04-Neu.png"])
        self.assertEqual(summary["total"], 3)
        with open(os.path.join(out, "changes.json")) as f:
            self.assertEqual(json.load(f)["changes"][0], ["02-Eintrag.png", "changed"])

    def test_cli_writes_comment(self):
        out = os.path.join(self.tmp.name, "out")
        script = os.path.join(ROOT, "tools", "pr_screens.py")
        subprocess.run([sys.executable, script, "changes", self.before, self.after, out], check=True, capture_output=True)
        body = subprocess.run([sys.executable, script, "comment", out, "https://img", "https://run"],
                              check=True, capture_output=True, text=True).stdout
        self.assertIn('<img src="https://img/after/02-Eintrag.png"', body)


class RenameTests(unittest.TestCase):
    def test_attachment_names(self):
        self.assertEqual(pr_screens.screenshot_name("01-Start_0_1A2B3C4D-1A2B-1A2B-1A2B-1A2B3C4D5E6F.png"), "01-Start.png")

    def test_rename_from_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            raw, out = os.path.join(tmp, "raw"), os.path.join(tmp, "out")
            write(raw, "a.png", b"1")
            with open(os.path.join(raw, "manifest.json"), "w") as f:
                json.dump([{"attachments": [{"exportedFileName": "a.png",
                                             "suggestedHumanReadableName": "05-Kaliber_0_1A2B3C4D-1A2B-1A2B-1A2B-1A2B3C4D5E6F.png"}]}], f)
            self.assertEqual(pr_screens.rename(raw, out), ["05-Kaliber.png"])


try:
    from PIL import Image
except ImportError:
    Image = None


@unittest.skipUnless(Image, "needs Pillow (installed by the workflow's Compare step)")
class SameTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def png(self, name, changes=(), size=(40, 40)):
        img = Image.new("RGB", size, (240, 240, 245))
        for xy, colour in changes:
            img.putpixel(xy, colour)
        path = os.path.join(self.tmp.name, name)
        img.save(path)
        return path

    def test_faint_noise_is_the_same(self):
        noise = [((x, 3), (250, 245, 250)) for x in range(40)]
        self.assertTrue(pr_screens.same(self.png("a.png"), self.png("b.png", noise)))

    def test_visible_change_differs(self):
        text = [((x, y), (0, 0, 0)) for x in range(10) for y in range(5)]
        self.assertFalse(pr_screens.same(self.png("a.png"), self.png("b.png", text)))

    def test_other_size_differs(self):
        self.assertFalse(pr_screens.same(self.png("a.png"), self.png("b.png", size=(40, 41))))


class CommentTests(unittest.TestCase):
    def test_table_with_before_and_after(self):
        summary = {"changes": [["02-Eintrag.png", "changed"], ["04-Neu.png", "new"], ["03-Weg.png", "gone"]],
                   "total": 9, "base": 9}
        body = pr_screens.comment(summary, "https://raw/x/12", "https://run/1")
        self.assertTrue(body.startswith(pr_screens.MARKER))
        self.assertIn("3 of 9 screens", body)
        self.assertIn('| 02-Eintrag | <img src="https://raw/x/12/before/02-Eintrag.png" width="250"> | '
                      '<img src="https://raw/x/12/after/02-Eintrag.png" width="250"> |', body)
        self.assertIn('| 04-Neu (new) | — | <img src="https://raw/x/12/after/04-Neu.png"', body)
        self.assertIn("| 03-Weg (gone) | <img", body)
        self.assertIn("(https://run/1)", body)

    def test_no_change_points_to_the_tour(self):
        body = pr_screens.comment({"changes": [], "total": 9, "base": 9}, "u", "r")
        self.assertIn("No visible change on the 9 screens", body)
        self.assertIn(pr_screens.TOUR, body)
        self.assertNotIn("<img", body)

    def test_says_when_base_failed(self):
        body = pr_screens.comment({"changes": [["01-Tagebuch.png", "new"]], "total": 1, "base": 0}, "u", "r")
        self.assertIn("base branch could not be taken", body)


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, ".github", "workflows", "build.yml")) as f:
            cls.workflow = f.read()

    def test_runs_on_gui_pull_requests(self):
        self.assertIn("pull_request:", self.workflow)
        self.assertIn("SCREENS_TOUR: ${{ needs.changes.outputs.screens }}", self.workflow)
        self.assertIn("if: env.SCREENS_TOUR == 'true'", self.workflow)
        self.assertRegex(self.workflow, r"runs-on: macos-2[6-9]")

    def test_reuses_the_build_and_its_simulator(self):
        # No second Mac runner: the tour runs on the Build job's build, without compiling it again.
        self.assertFalse(os.path.exists(os.path.join(ROOT, ".github", "workflows", "pr-screens.yml")))
        self.assertNotIn("xcodebuild test ", self.workflow)
        self.assertIn('xcrun simctl boot "$UDID"', self.workflow)
        # The tour scheme is built before the unit test scheme, which must be built last.
        self.assertLess(self.workflow.index("-scheme KaliberfinderScreens"),
                        self.workflow.index("-scheme Kaliberfinder \\"))

    def test_tours_start_without_the_unit_tests_data(self):
        self.assertEqual(self.workflow.count("xcrun simctl uninstall \"$UDID\" ch.giotta.kaliberfinder"), 2)

    def test_tours_head_and_base_with_the_same_tour(self):
        self.assertEqual(self.workflow.count("-only-testing:KaliberfinderUITests/PRScreensTests"), 2)
        self.assertIn("fetch-depth: 2", self.workflow)
        self.assertIn("git checkout -q HEAD^1", self.workflow)
        self.assertIn('cp "$SCREENS/PRScreensTests.swift" KaliberfinderUITests/', self.workflow)
        self.assertIn("status_bar", self.workflow)

    def test_comments_once_per_pull_request(self):
        self.assertIn("pull-requests: write", self.workflow)
        self.assertIn(pr_screens.MARKER, self.workflow)
        self.assertIn("PATCH", self.workflow)

    def test_images_go_to_app_screens_with_a_deploy_key(self):
        # The images stay out of this repo's history: ravench/app-screens holds them.
        comment = self.workflow.split("name: Comment on the pull request")[1]
        self.assertIn("SCREENS_REPO: ravench/app-screens", comment)
        self.assertIn("SCREENS_BRANCH: ${{ github.event.repository.name }}/pr-screens", comment)
        self.assertIn("secrets.SCREENS_DEPLOY_KEY", comment)
        self.assertIn('git remote add origin "git@github.com:${SCREENS_REPO}.git"', comment)
        self.assertIn("https://raw.githubusercontent.com/${SCREENS_REPO}/", comment)
        self.assertNotIn("contents: write", self.workflow)

    def test_tour_exists_and_matches_the_comment_hint(self):
        self.assertTrue(os.path.exists(os.path.join(ROOT, pr_screens.TOUR)))


if __name__ == "__main__":
    unittest.main()
