"""The share extension and the app fit together (project.yml, SharedInbox.swift, TestFlight workflow).

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(*path):
    with open(os.path.join(ROOT, *path)) as f:
        return f.read()


def target(project, name):
    """The block of one target in project.yml (until the next target or the schemes)."""
    match = re.search(rf"^  {name}:\n(.*?)(?=^  \w+:\n|^\w)", project, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"target {name} missing")
    return match.group(1)


class ShareExtensionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = read("project.yml")
        cls.app = target(cls.project, "Kaliberfinder")
        cls.share = target(cls.project, "KaliberfinderShare")

    def test_is_a_share_extension_embedded_in_the_app(self):
        self.assertRegex(self.share, r"type:\s*app-extension")
        self.assertIn("com.apple.share-services", self.share)
        self.assertRegex(self.app, r"dependencies:\s*\n(\s*#.*\n)*\s*- target: KaliberfinderShare")

    def test_bundle_id_is_below_the_app(self):
        app_id = re.search(r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", self.app).group(1)
        share_id = re.search(r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", self.share).group(1)
        self.assertEqual(share_id, app_id + ".share")

    def test_same_app_group_everywhere(self):
        swift = re.search(r'appGroup = "([^"]+)"', read("Kaliberfinder", "Services", "SharedInbox.swift")).group(1)
        for block in (self.app, self.share):
            groups = re.findall(r"-\s*(group\.\S+)", block)
            self.assertEqual(groups, [swift])
        self.assertTrue(swift.startswith("group.ch.giotta."))

    def test_url_scheme_matches(self):
        swift = re.search(r'openURL = URL\(string: "([a-z]+)://', read("Kaliberfinder", "Services", "SharedInbox.swift")).group(1)
        self.assertRegex(self.app, rf"CFBundleURLSchemes:\s*\[{swift}\]")

    def test_photo_limit_matches(self):
        swift = int(re.search(r"maxPhotos = (\d+)", read("Kaliberfinder", "Services", "SharedInbox.swift")).group(1))
        plist = int(re.search(r"NSExtensionActivationSupportsImageWithMaxCount:\s*(\d+)", self.share).group(1))
        self.assertEqual(swift, plist)

    def test_versions_match_the_app(self):
        # App Store Connect rejects an upload whose extension version differs from the app's.
        for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION", "DEVELOPMENT_TEAM", "TARGETED_DEVICE_FAMILY"):
            values = {re.search(rf"{key}:\s*(\S+)", block).group(1) for block in (self.app, self.share)}
            self.assertEqual(len(values), 1, key)

    def test_entitlements_follow_the_workflow_naming(self):
        # testflight.yml signs <Name>.appex with <Name>/<Name>.entitlements.
        self.assertIn("path: KaliberfinderShare/KaliberfinderShare.entitlements", self.share)
        self.assertIn("path: Kaliberfinder/Kaliberfinder.entitlements", self.app)
        workflow = read(".github", "workflows", "testflight.yml")
        self.assertIn('PlugIns/*.appex "$APP"', workflow)
        self.assertIn('"$NAME/$NAME.entitlements"', workflow)

    def test_extension_sources_exist(self):
        for path in re.findall(r"^      - (\S+)$", self.share.split("info:")[0], re.MULTILINE):
            self.assertTrue(os.path.exists(os.path.join(ROOT, path)), path)


if __name__ == "__main__":
    unittest.main()
