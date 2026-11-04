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


class EntitlementTests(unittest.TestCase):
    EXPECTED = {"aps-environment": "development",
                "com.apple.developer.icloud-container-identifiers": ["iCloud.ch.giotta.schiesstagebuch"],
                "com.apple.developer.icloud-services": ["CloudKit"]}

    def test_distribution_signature_passes(self):
        signed = dict(self.EXPECTED, **{"aps-environment": "production", "application-identifier": "PD9YC6KM5T.x"})
        self.assertEqual(testflight.missing_entitlements(signed, self.EXPECTED), [])

    def test_lost_entitlements_reported(self):
        signed = {"com.apple.developer.icloud-container-identifiers": [], "application-identifier": "x"}
        self.assertEqual(testflight.missing_entitlements(signed, self.EXPECTED),
                         ["aps-environment", "com.apple.developer.icloud-container-identifiers: iCloud.ch.giotta.schiesstagebuch",
                          "com.apple.developer.icloud-services"])

    def test_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            signed, expected = os.path.join(tmp, "s.plist"), os.path.join(tmp, "e.plist")
            with open(expected, "wb") as f:
                plistlib.dump(self.EXPECTED, f)
            with open(signed, "wb") as f:
                plistlib.dump({}, f)
            bad = subprocess.run([sys.executable, SCRIPT, "check-entitlements", signed, expected], capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("icloud-services", bad.stderr)
            with open(signed, "wb") as f:
                plistlib.dump(self.EXPECTED, f)
            ok = subprocess.run([sys.executable, SCRIPT, "check-entitlements", signed, expected], capture_output=True, text=True)
            self.assertEqual(ok.returncode, 0, ok.stderr)
            # Apps without an entitlements file (no capabilities) pass.
            ok = subprocess.run([sys.executable, SCRIPT, "check-entitlements", signed, os.path.join(tmp, "none")], capture_output=True, text=True)
            self.assertEqual(ok.returncode, 0, ok.stderr)


class ExportDestinationTests(unittest.TestCase):
    def test_local_export(self):
        self.assertEqual(testflight.export_options("AB12CD34EF", "export")["destination"], "export")
        self.assertEqual(testflight.export_options("AB12CD34EF")["destination"], "upload")
        with self.assertRaises(ValueError):
            testflight.export_options("AB12CD34EF", "somewhere")


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

    def test_merges_within_a_minute_upload_once(self):
        # Each run waits a minute in a group that cancels the older wait; only the newest commit uploads.
        wait = self.workflow.split("\n  wait:")[1].split("\n  upload:")[0]
        self.assertIn("group: testflight-wait", wait)
        self.assertIn("cancel-in-progress: true", wait)
        self.assertIn("sleep 60", wait)
        self.assertIn("commits/main", wait)
        upload = self.workflow.split("\n  upload:")[1]
        self.assertIn("needs: wait", upload)
        self.assertIn("needs.wait.outputs.latest == 'true'", upload)
        # A started upload is never cancelled.
        self.assertRegex(upload, r"group: testflight\n\s+cancel-in-progress: false")
        self.assertNotRegex(self.workflow, r"^concurrency:", "workflow-level concurrency would hold the wait")

    def test_build_rerun_when_no_runner_picked_it_up(self):
        # Queued macOS jobs can fail without ever starting (2026-11-04): Build is re-run instead
        # of silently skipping the upload, but only for that failure and only twice.
        retry = self.workflow.split("\n  retry:")[1].split("\n  wait:")[0]
        self.assertIn("workflow_run.conclusion == 'failure'", retry)
        self.assertIn("workflow_run.event == 'push'", retry)
        self.assertIn("run_attempt < 3", retry)
        self.assertIn("actions: write", retry)
        self.assertIn("not acquired by Runner", retry)
        self.assertIn('gh run rerun "$RUN" --failed', retry)
        self.assertIn("runs-on: ubuntu-latest", retry)

    def test_actions_run_on_node_24(self):
        # GitHub retired Node 20 for actions; checkout v5 is the first major on Node 24.
        node24 = {"actions/checkout": 5}
        workflows = os.path.join(testflight.ROOT, ".github", "workflows")
        for name in sorted(os.listdir(workflows)):
            with open(os.path.join(workflows, name)) as f:
                for action, major in re.findall(r"uses:\s*([\w-]+/[\w-]+)@v(\d+)", f.read()):
                    self.assertGreaterEqual(int(major), node24.get(action, 0), f"{name}: {action}@v{major}")

    def test_build_pushes_only_on_main(self):
        # One Mac run per commit: branches build via their pull request; main's
        # push build is what triggers the TestFlight upload.
        with open(os.path.join(testflight.ROOT, ".github", "workflows", "build.yml")) as f:
            build = f.read()
        self.assertRegex(build, r"push:\n\s+branches: \[main\]")
        self.assertIn("pull_request:", build)

    def test_archive_creates_no_certificates(self):
        # Automatic signing in the archive made each fresh runner create an Apple Development
        # certificate until Apple's per-team limit (2026-11-03). Only the export signs, in the cloud.
        # Ad hoc signing ("-") is refused for the iOS SDK, so the archive is unsigned.
        archive = self.workflow.split("xcodebuild archive")[1].split("- name:")[0]
        self.assertIn("CODE_SIGNING_ALLOWED=NO", archive)
        self.assertNotIn("allowProvisioningUpdates", archive)
        # ...but the export only keeps entitlements the archived app is signed with.
        self.assertIn('codesign --force --sign - --entitlements "$ENTITLEMENTS"', archive)

    def test_entitlements_checked_before_upload(self):
        check = self.workflow.index("check-entitlements")
        upload = self.workflow.index("ExportOptions.plist\"", self.workflow.index("- name: Upload to TestFlight"))
        self.assertLess(check, upload)
        self.assertIn('export-options "$RUNNER_TEMP/ExportLocal.plist" export', self.workflow)

    def test_archive_errors_shown(self):
        # xcpretty hides signing errors; the raw log is kept and printed when the archive fails.
        self.assertIn('| tee "$RUNNER_TEMP/archive.log" | xcpretty', self.workflow)
        shown = self.workflow.split("Show the archive errors")[1].split("- name:")[0]
        self.assertIn("if: failure()", shown)
        self.assertIn("archive.log", shown)

    def test_uses_ci_build_number(self):
        self.assertIn('CURRENT_PROJECT_VERSION="$BUILD_NUMBER"', self.workflow)

    def test_builds_with_ios_26_sdk(self):
        # App Store Connect rejects builds made with an SDK older than iOS 26 (Xcode 26).
        for name in ("build.yml", "testflight.yml"):
            with open(os.path.join(testflight.ROOT, ".github", "workflows", name)) as f:
                runners = re.findall(r"runs-on:\s*macos-(\d+)", f.read())
            self.assertTrue(runners, name)
            for version in runners:
                self.assertGreaterEqual(int(version), 26, name)

    def test_ipad_supports_all_orientations(self):
        # iPad multitasking needs all four orientations, or the upload is rejected.
        family = re.search(r"TARGETED_DEVICE_FAMILY:\s*\"?([\d,]+)", self.project).group(1)
        if "2" not in family.split(","):
            self.skipTest("iPhone only")
        ipad = re.search(r"INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad:\s*\"?([^\"\n]+)", self.project)
        self.assertIsNotNone(ipad)
        self.assertEqual(set(ipad.group(1).split()), {
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"})

    def test_no_export_compliance_prompt(self):
        # Otherwise every build waits in App Store Connect for the encryption question.
        self.assertRegex(self.project, r"INFOPLIST_KEY_ITSAppUsesNonExemptEncryption:\s*NO")


if __name__ == "__main__":
    unittest.main()
