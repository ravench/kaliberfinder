"""Checks on the Build workflow (.github/workflows/build.yml)."""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / ".github" / "workflows" / "build.yml"


class BuildWorkflowTests(unittest.TestCase):
    def test_unit_tests_write_results_for_the_summary(self):
        text = BUILD.read_text()
        self.assertIn('-resultBundlePath "$RUNNER_TEMP/UnitTests.xcresult"', text)
        self.assertIn("python3 tools/test_summary.py", text)

    def test_mac_job_checks_out_the_golden_masks_from_lfs(self):
        build_job = BUILD.read_text().split("\n  build:\n", 1)[1]
        self.assertIn("lfs: true", build_job.split("\n      - run:", 1)[0])
        self.assertIn("^GOLDEN baseline.json:", build_job)

    def test_golden_masks_are_stored_with_lfs(self):
        out = subprocess.run(["git", "check-attr", "filter", "KaliberfinderTests/Golden/x-20261105-000000/01/vision-instances.png"],
                             cwd=ROOT, capture_output=True, text=True, check=True).stdout
        self.assertTrue(out.strip().endswith(": filter: lfs"), out)


if __name__ == "__main__":
    unittest.main()
