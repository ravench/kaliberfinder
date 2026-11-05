"""Checks on the Build workflow (.github/workflows/build.yml)."""
import unittest
from pathlib import Path

BUILD = Path(__file__).resolve().parent.parent / ".github" / "workflows" / "build.yml"


class BuildWorkflowTests(unittest.TestCase):
    def test_unit_tests_write_results_for_the_summary(self):
        text = BUILD.read_text()
        self.assertIn('-resultBundlePath "$RUNNER_TEMP/UnitTests.xcresult"', text)
        self.assertIn("python3 tools/test_summary.py", text)


if __name__ == "__main__":
    unittest.main()
