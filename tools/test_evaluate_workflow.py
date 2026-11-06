"""Checks on the evaluation tool's workflow (.github/workflows/evaluate.yml) and build script."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVALUATE = ROOT / ".github" / "workflows" / "evaluate.yml"
BUILD = ROOT / ".github" / "workflows" / "build.yml"
SERVICES = ROOT / "Kaliberfinder" / "Services"


class EvaluateWorkflowTests(unittest.TestCase):
    def test_it_is_started_by_hand_and_compares_with_main(self):
        text = EVALUATE.read_text()
        self.assertIn("workflow_dispatch:", text)
        self.assertRegex(text, r"compare:\n\s+description: .*\n\s+default: main")
        self.assertIn("--compare", text)

    def test_it_reads_the_training_repo_with_its_own_token_and_lfs(self):
        text = EVALUATE.read_text()
        checkout = text.split("repository: ravench/kaliberfinder-training", 1)[1].split("\n      - ", 1)[0]
        self.assertIn("token: ${{ secrets.KALIBERFINDER_TRAINING_TOKEN }}", checkout)
        self.assertIn("lfs: true", checkout)

    def test_only_the_report_is_uploaded(self):
        # Run downloads of a public repo are open to anyone signed in: never the training photos.
        uploads = re.findall(r"upload-artifact@v\d+[\s\S]*?path: (.+)", EVALUATE.read_text())
        self.assertEqual(uploads, ["${{ env.REPORT }}"])
        self.assertIn('echo "REPORT=$RUNNER_TEMP/evaluation"', EVALUATE.read_text())

    def test_the_build_job_type_checks_the_tool(self):
        build_job = BUILD.read_text().split("\n  build:\n", 1)[1]
        self.assertIn("tools/evaluate/build.sh --typecheck", build_job)

    def test_the_analysis_needs_no_uikit(self):
        # build.sh compiles every Services file without a UIKit import for macOS.
        for name in ["PhotoAnalyzer.swift", "ShapeMatcher.swift", "ColorSegmenter.swift", "Matcher.swift", "TrainingCapture.swift"]:
            self.assertNotRegex((SERVICES / name).read_text(), r"(?m)^import (UIKit|SwiftUI)$", name)


if __name__ == "__main__":
    unittest.main()
