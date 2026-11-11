"""LICENSE.md and the docs agree that the app is closed source: python3 -m unittest tools/test_licence.py"""
import os
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as f:
        return f.read()


class LicenceTest(unittest.TestCase):
    def test_every_bundled_licence_is_listed(self):
        # Code that comes with its own LICENSE file is an exception to "all rights reserved"
        # and has to be named in LICENSE.md.
        files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True,
                               check=True).stdout.split()
        licence = read("LICENSE.md")
        for path in files:
            folder, name = os.path.split(path)
            if folder and os.path.splitext(name)[0].upper() in ("LICENSE", "LICENCE", "COPYING"):
                self.assertIn(f"`{folder}/`", licence, path)

    def test_docs_no_longer_offer_an_open_licence(self):
        self.assertFalse(os.path.exists(os.path.join(ROOT, "CLA.md")))
        for name in ("README.md", "CONTRIBUTING.md", ".github/pull_request_template.md"):
            text = read(name)
            for word in ("PolyForm", "CLA.md", "Contributor License Agreement"):
                self.assertNotIn(word, text, name)


if __name__ == "__main__":
    unittest.main()
