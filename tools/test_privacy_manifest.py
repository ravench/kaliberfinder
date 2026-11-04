"""The app's privacy manifest matches what the code does (Kaliberfinder/Resources/PrivacyInfo.xcprivacy).

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import os
import plistlib
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "Kaliberfinder", "Resources", "PrivacyInfo.xcprivacy")
SOURCES = ["Kaliberfinder", "KaliberfinderShare"]

# Required-reason APIs Apple lists, with a pattern that finds their use in Swift.
REQUIRED_REASON_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage",
    "NSPrivacyAccessedAPICategoryFileTimestamp": r"creationDate|modificationDate|ContentModificationDate|\bstat\(",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time",
    "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|systemFreeSize|statfs",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}
NETWORK = r"URLSession|URLRequest|NWConnection|WKWebView|SFSafariViewController|openURL\(URL\(string: \"http"


def swift_sources():
    for folder in SOURCES:
        for base, _, files in os.walk(os.path.join(ROOT, folder)):
            for name in files:
                if name.endswith(".swift"):
                    with open(os.path.join(base, name)) as f:
                        yield name, f.read()


class PrivacyManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(MANIFEST, "rb") as f:
            cls.manifest = plistlib.load(f)
        cls.code = "\n".join(text for _, text in swift_sources())

    def declared(self):
        return {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
                for entry in self.manifest["NSPrivacyAccessedAPITypes"]}

    def test_no_tracking_and_nothing_collected(self):
        self.assertIs(self.manifest["NSPrivacyTracking"], False)
        self.assertEqual(self.manifest["NSPrivacyTrackingDomains"], [])
        self.assertEqual(self.manifest["NSPrivacyCollectedDataTypes"], [])

    def test_app_makes_no_network_calls(self):
        # "Data Not Collected" on the App Store label relies on this.
        self.assertIsNone(re.search(NETWORK, self.code))

    def test_every_used_required_reason_api_is_declared(self):
        declared = self.declared()
        for api, pattern in REQUIRED_REASON_APIS.items():
            if re.search(pattern, self.code):
                self.assertIn(api, declared, f"{api} used in code but not in PrivacyInfo.xcprivacy")
                self.assertTrue(declared[api], f"{api} declared without a reason")

    def test_user_defaults_reason_is_app_only(self):
        # CA92.1: read/write only by the app itself (no App Group suite).
        self.assertEqual(self.declared()["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        self.assertNotIn("UserDefaults(suiteName", self.code)

    def test_declares_nothing_unused(self):
        for api in self.declared():
            self.assertRegex(self.code, REQUIRED_REASON_APIS[api], f"{api} declared but not used")

    def test_is_bundled_with_the_app(self):
        # project.yml takes all of Kaliberfinder/ as sources, so Resources/ files are copied into the app.
        with open(os.path.join(ROOT, "project.yml")) as f:
            self.assertRegex(f.read(), r"sources: \[Kaliberfinder\]")


if __name__ == "__main__":
    unittest.main()
