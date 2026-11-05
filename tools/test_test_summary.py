"""Run-page test summary (tools/test_summary.py)."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_summary import render

TOOL = Path(__file__).resolve().parent / "test_summary.py"

PASSED = {"result": "Passed", "totalTestCount": 3, "passedTests": 3, "failedTests": 0, "skippedTests": 0,
          "testFailures": []}
FAILED = {"result": "Failed", "totalTestCount": 4, "passedTests": 2, "failedTests": 2, "skippedTests": 0,
          "testFailures": [
              {"testName": "testSum()", "targetName": "AppTests", "failureText": "XCTAssertEqual failed: (\"1\") is not equal to (\"2\")"},
              {"testName": "testPipe()", "targetName": "AppTests", "failureText": "a | b\nsecond line 50%"},
          ]}


class RenderTests(unittest.TestCase):
    def test_counts_per_bundle(self):
        markdown, annotations = render([("Unit tests", PASSED)])
        self.assertIn("| Unit tests | Passed | 3 | 0 | 0 |", markdown)
        self.assertNotIn("Failed tests", markdown)
        self.assertEqual(annotations, [])

    def test_failed_tests_are_listed_and_annotated(self):
        markdown, annotations = render([("Unit tests", FAILED), ("UI tests", PASSED)])
        self.assertIn("| Unit tests | Failed | 2 | 2 | 0 |", markdown)
        self.assertIn("| UI tests | Passed | 3 | 0 | 0 |", markdown)
        self.assertIn("`testSum()`", markdown)
        # Pipes and line breaks would break the table row.
        self.assertIn("a \\| b second line 50%", markdown)
        self.assertEqual(len(annotations), 2)
        self.assertTrue(annotations[0].startswith("::error title=Unit tests: testSum()::XCTAssertEqual failed"))
        self.assertIn("50%25", annotations[1])

    def test_missing_results_say_so(self):
        markdown, _ = render([("UI tests", None)])
        self.assertIn("| UI tests | no results |", markdown)

    def test_command_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "unit.json")
            with open(path, "w") as f:
                json.dump(FAILED, f)
            summary = os.path.join(tmp, "summary.md")
            env = dict(os.environ, GITHUB_STEP_SUMMARY=summary)
            done = subprocess.run([sys.executable, str(TOOL), f"Unit tests={path}",
                                   f"UI tests={os.path.join(tmp, 'missing.json')}"],
                                  capture_output=True, text=True, check=True, env=env)
            with open(summary) as f:
                markdown = f.read()
        self.assertIn("| Unit tests | Failed | 2 | 2 | 0 |", markdown)
        self.assertIn("| UI tests | no results |", markdown)
        self.assertIn("::error title=Unit tests: testSum()::", done.stdout)
        self.assertNotIn("| Unit tests |", done.stdout)


if __name__ == "__main__":
    unittest.main()
