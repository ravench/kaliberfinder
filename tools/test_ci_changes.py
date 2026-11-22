"""Which pull requests need the Mac build (tools/ci_changes.py)."""
import subprocess
import sys
import unittest
from pathlib import Path

from ci_changes import NEEDS_MAC, SCREENS, needs_mac, needs_screens

APP_PATHS = ["Kaliberfinder/Views/ContentView.swift", "KaliberfinderTests/MatcherTests.swift",
             "KaliberfinderUITests/PRScreensTests.swift", "KaliberfinderShare/ShareView.swift",
             "calibre-data", "project.yml"]
TOOL = Path(__file__).resolve().parent / "ci_changes.py"


class NeedsMacTests(unittest.TestCase):
    def test_app_code_needs_the_mac(self):
        for path in APP_PATHS:
            with self.subTest(path=path):
                self.assertTrue(needs_mac(["README.md", path]))

    def test_docs_tools_and_other_workflows_skip_the_mac(self):
        self.assertFalse(needs_mac([
            "README.md", "docs/website.md", ".claude/skills/ponytail/SKILL.md",
            ".github/workflows/website.yml", ".github/pull_request_template.md",
            "tools/website.py", "tools/test_website.py", ".swiftlint.yml",
        ]))

    def test_store_texts_skip_the_mac(self):
        self.assertFalse(needs_mac(["store/de/description.txt", "store/es/keywords.txt", "RELEASE_NOTES.md"]))

    def test_the_build_workflow_and_tools_it_runs_need_the_mac(self):
        self.assertIn(".github/workflows/build.yml", NEEDS_MAC)
        for path in NEEDS_MAC:
            self.assertTrue(needs_mac([path]))

    def test_no_files_builds_to_be_safe(self):
        self.assertTrue(needs_mac([]))
        self.assertTrue(needs_mac(["", "\n"]))

    def test_prints_a_github_output_line(self):
        run = lambda text: subprocess.run(
            [sys.executable, str(TOOL)], input=text, capture_output=True, text=True, check=True).stdout
        self.assertEqual(run("README.md\ntools/localize.py\n"), "mac=false\nscreens=false\n")
        self.assertEqual(subprocess.run([sys.executable, str(TOOL), "wip\nscreens"], input="README.md\n",
                                        capture_output=True, text=True, check=True).stdout, "mac=true\nscreens=true\n")
        self.assertEqual(subprocess.run([sys.executable, str(TOOL), ""], input="README.md\n",
                                        capture_output=True, text=True, check=True).stdout, "mac=false\nscreens=false\n")
        self.assertEqual(run(f"README.md\n{APP_PATHS[0]}\n"), "mac=true\nscreens=true\n")
        self.assertEqual(run("KaliberfinderTests/MatcherTests.swift\n"), "mac=true\nscreens=false\n")


class NeedsScreensTests(unittest.TestCase):
    def test_gui_changes_get_the_screens(self):
        for path in ["Kaliberfinder/Views/ContentView.swift", "KaliberfinderUITests/PRScreensTests.swift",
                     "Kaliberfinder/Resources/Localizable.xcstrings", "Kaliberfinder/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json", "tools/pr_screens.py", ".github/workflows/build.yml"]:
            with self.subTest(path=path):
                self.assertTrue(needs_screens(["README.md", path]))

    def test_unit_tests_and_docs_skip_the_screens(self):
        self.assertFalse(needs_screens(["KaliberfinderTests/MatcherTests.swift", "README.md",
                                        "tools/localize.py", ".github/workflows/testflight.yml",
                                        "KaliberfinderUITests/AppStoreScreensTests.swift"]))

    def test_screens_always_come_with_the_mac_job(self):
        # They run in the Mac job, so every path that takes them must also start it.
        for pattern in SCREENS:
            path = pattern.replace("*", "Some.swift")
            with self.subTest(path=path):
                self.assertTrue(needs_mac([path]))

    def test_logic_and_data_bumps_skip_the_screens(self):
        # The tour takes about an hour; these rarely change a screen, and the label asks for it.
        self.assertFalse(needs_screens(["calibre-data", "Kaliberfinder/Resources/Cartridges.json",
                                        "Kaliberfinder/Services/Matcher.swift", "Kaliberfinder/Models/Cartridge.swift",
                                        "project.yml"]))

    def test_the_screens_label_asks_for_them(self):
        self.assertTrue(needs_screens(["KaliberfinderTests/SomeTests.swift"], ["bug", "screens"]))
        self.assertFalse(needs_screens(["KaliberfinderTests/SomeTests.swift"], ["bug", "screenshots"]))

    def test_no_files_takes_the_screens_to_be_safe(self):
        self.assertTrue(needs_screens([]))
