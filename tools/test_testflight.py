"""Unit tests for tools/testflight.py.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest

import testflight

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "testflight.py")


class BuildNumberTests(unittest.TestCase):
    def test_offset_added(self):
        self.assertEqual(testflight.build_number(1), testflight.OFFSET + 1)
        self.assertEqual(testflight.build_number("42", offset=0), 42)

    def test_grows_with_each_run(self):
        numbers = [testflight.build_number(n) for n in range(1, 50)]
        self.assertEqual(numbers, sorted(set(numbers)))

    def test_above_hand_uploads(self):
        # project.yml starts at build 1; CI builds must stay above hand uploads.
        self.assertGreater(testflight.build_number(1), 1)

    def test_rejects_bad_run_numbers(self):
        for bad in (0, -3, "abc", ""):
            with self.assertRaises(ValueError):
                testflight.build_number(bad)


class TeamIdTests(unittest.TestCase):
    def test_reads_team(self):
        yml = "settings:\n  base:\n    DEVELOPMENT_TEAM: AB12CD34EF\n    DEVELOPMENT_TEAM: AB12CD34EF\n"
        self.assertEqual(testflight.team_id(yml), "AB12CD34EF")

    def test_quoted_team(self):
        self.assertEqual(testflight.team_id('    DEVELOPMENT_TEAM: "AB12CD34EF"\n'), "AB12CD34EF")

    def test_missing_or_conflicting_team(self):
        with self.assertRaises(ValueError):
            testflight.team_id("name: App\n")
        with self.assertRaises(ValueError):
            testflight.team_id("  DEVELOPMENT_TEAM: AB12CD34EF\n  DEVELOPMENT_TEAM: ZZ12CD34EF\n")

    def test_real_project(self):
        with open(testflight.PROJECT_YML) as f:
            self.assertRegex(testflight.team_id(f.read()), r"^[A-Z0-9]{10}$")


class ExportOptionsTests(unittest.TestCase):
    def test_uploads_to_app_store_connect(self):
        options = testflight.export_options("AB12CD34EF")
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["destination"], "upload")
        self.assertEqual(options["signingStyle"], "automatic")
        self.assertEqual(options["teamID"], "AB12CD34EF")
        self.assertFalse(options["manageAppVersionAndBuildNumber"])

    def test_command_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "ExportOptions.plist")
            subprocess.run([sys.executable, SCRIPT, "export-options", out], check=True)
            with open(out, "rb") as f:
                options = plistlib.load(f)
        with open(testflight.PROJECT_YML) as f:
            self.assertEqual(options["teamID"], testflight.team_id(f.read()))
        self.assertEqual(options["destination"], "upload")
        number = subprocess.run([sys.executable, SCRIPT, "build-number", "7"],
                                check=True, capture_output=True, text=True).stdout
        self.assertEqual(number.strip(), str(testflight.OFFSET + 7))


class WorkflowTests(unittest.TestCase):
    """The workflow and project.yml have to agree, or the upload breaks only on main."""

    @classmethod
    def setUpClass(cls):
        with open(testflight.PROJECT_YML) as f:
            cls.project = f.read()
        workflow = os.path.join(testflight.ROOT, ".github", "workflows", "testflight.yml")
        with open(workflow) as f:
            cls.workflow = f.read()
        cls.name = re.search(r"^name:\s*(\S+)", cls.project, re.MULTILINE).group(1)

    def test_builds_this_app(self):
        self.assertIn(f"-project {self.name}.xcodeproj", self.workflow)
        self.assertIn(f"-scheme {self.name} ", self.workflow)
        self.assertNotIn("APPNAME", self.workflow)

    def test_runs_after_build_on_main(self):
        self.assertIn("workflows: [Build]", self.workflow)
        self.assertIn("branches: [main]", self.workflow)
        self.assertIn("conclusion == 'success'", self.workflow)

    def test_actions_run_on_node_24(self):
        # GitHub retired Node 20 for actions; checkout v5 is the first major on Node 24.
        node24 = {"actions/checkout": 5}
        workflows = os.path.join(testflight.ROOT, ".github", "workflows")
        for name in sorted(os.listdir(workflows)):
            with open(os.path.join(workflows, name)) as f:
                for action, major in re.findall(r"uses:\s*([\w-]+/[\w-]+)@v(\d+)", f.read()):
                    self.assertGreaterEqual(int(major), node24.get(action, 0), f"{name}: {action}@v{major}")

    def test_uses_ci_build_number(self):
        self.assertIn('CURRENT_PROJECT_VERSION="$BUILD_NUMBER"', self.workflow)

    def test_no_export_compliance_prompt(self):
        # Otherwise every build waits in App Store Connect for the encryption question.
        self.assertRegex(self.project, r"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption:\s*NO")


if __name__ == "__main__":
    unittest.main()
