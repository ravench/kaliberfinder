"""Every bundle ID (app, tests, extensions) and iCloud container uses the ch.giotta prefix.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import os
import re
import unittest

PROJECT_YML = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "project.yml")
PREFIX = "ch.giotta"


class BundleIdTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(PROJECT_YML) as f:
            cls.project = f.read()

    def test_prefix_option(self):
        self.assertRegex(self.project, re.compile(rf"^\s*bundleIdPrefix:\s*{re.escape(PREFIX)}\s*$", re.MULTILINE))

    def test_every_bundle_id(self):
        ids = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", self.project)
        self.assertTrue(ids)
        for bundle_id in ids:
            self.assertTrue(bundle_id.startswith(PREFIX + "."), bundle_id)
        self.assertEqual(len(ids), len(set(ids)), "bundle IDs must be unique")

    def test_icloud_containers(self):
        for container in re.findall(r"-\s*(iCloud\.\S+)", self.project):
            self.assertTrue(container.startswith(f"iCloud.{PREFIX}."), container)

    def test_old_prefix_gone(self):
        self.assertNotIn("net.forestraven", self.project)
