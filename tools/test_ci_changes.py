"""Which pull requests need the Mac build (tools/ci_changes.py)."""
import os
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
        run = lambda text, *args: run_tool(text, *args, billed="").stdout
        self.assertEqual(run("README.md\ntools/localize.py\n"), "mac=false\nscreens=false\ntour=false\n")
        self.assertEqual(run("README.md\n", "wip\nscreens"), "mac=true\nscreens=true\ntour=true\n")
        self.assertEqual(run("README.md\n", ""), "mac=false\nscreens=false\ntour=false\n")
        self.assertEqual(run(f"README.md\n{APP_PATHS[0]}\n"), "mac=true\nscreens=true\ntour=true\n")
        self.assertEqual(run("KaliberfinderTests/MatcherTests.swift\n"), "mac=true\nscreens=false\ntour=false\n")


def run_tool(paths, labels="", billed="true"):
    """The tool as the workflow runs it; billed="" leaves BILLED_MAC out."""
    env = {k: v for k, v in os.environ.items() if k != "BILLED_MAC"}
    if billed:
        env["BILLED_MAC"] = billed
    return subprocess.run([sys.executable, str(TOOL), labels], input=paths, env=env,
                          capture_output=True, text=True, check=True)


def changes_job():
    build = (TOOL.parent.parent / ".github" / "workflows" / "build.yml").read_text()
    return build.split("\n  changes:\n", 1)[1].split("\n  tools:\n", 1)[0]


class BilledMacTests(unittest.TestCase):
    """A private repo on GitHub's Macs pays per minute: no screens, not even by label."""

    def test_gui_changes_build_without_screens(self):
        self.assertEqual(run_tool(f"{APP_PATHS[0]}\n").stdout, "mac=true\nscreens=false\ntour=false\n")

    def test_the_label_starts_no_mac_job(self):
        self.assertEqual(run_tool("README.md\n", "screens").stdout, "mac=false\nscreens=false\ntour=false\n")

    def test_a_tour_change_still_compiles_the_tour(self):
        # Nothing else builds the UI tests, so a broken tour would otherwise only show once screens are back.
        self.assertEqual(run_tool("KaliberfinderUITests/PRScreensTests.swift\n").stdout,
                         "mac=true\nscreens=false\ntour=true\n")
        for path in ["project.yml", ".github/workflows/build.yml"]:
            with self.subTest(path=path):
                self.assertEqual(run_tool(f"{path}\n").stdout, "mac=true\nscreens=false\ntour=true\n")

    def test_says_why_the_screens_are_missing(self):
        self.assertIn("::notice::No PR screens", run_tool(f"{APP_PATHS[0]}\n").stderr)
        self.assertEqual(run_tool("KaliberfinderTests/MatcherTests.swift\n").stderr, "")

    def test_public_repo_or_own_mac_keeps_the_screens(self):
        self.assertEqual(run_tool(f"{APP_PATHS[0]}\n", billed="false").stdout, "mac=true\nscreens=true\ntour=true\n")

    def test_the_changes_job_sets_it_for_private_repos_without_their_own_mac(self):
        job = changes_job()
        env = "BILLED_MAC: ${{ github.event.repository.private && vars.MAC_RUNNER == '' }}"
        self.assertIn(env, job)
        self.assertLess(job.index(env), job.index("python3 tools/ci_changes.py"))
        self.assertIn("tour: ${{ steps.check.outputs.tour }}", job)

    def test_only_the_screens_run_the_tour(self):
        build = (TOOL.parent.parent / ".github" / "workflows" / "build.yml").read_text()
        build_job = build.split("\n  build:\n", 1)[1].split("\n  base-screens:\n", 1)[0]
        self.assertIn("if: env.BUILD_TOUR == 'true'", build_job)
        self.assertEqual(build_job.count("steps.build-tour.outcome == 'success'"), 3)
        self.assertEqual(build_job.count("env.SCREENS_TOUR == 'true' && steps.build-tour.outcome == 'success'"), 3)


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
