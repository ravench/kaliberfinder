"""Cancelling runs of closed pull requests, and not re-running old main builds."""
import io
import json
import re
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from ci_runs import main, open_pr_runs

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"


def run(run_id, status="in_progress", event="pull_request"):
    return {"id": run_id, "status": status, "event": event}


class OpenPullRequestRunsTests(unittest.TestCase):
    def test_queued_and_running_pull_request_runs_are_cancelled(self):
        runs = [run(1, "queued"), run(2, "in_progress"), run(3, "waiting"), run(4, "completed")]
        self.assertEqual(open_pr_runs(runs, 99), [1, 2, 3])

    def test_own_run_and_other_events_are_left_alone(self):
        runs = [run(5), run(6, event="push"), run(7, event="workflow_run"), run(8)]
        self.assertEqual(open_pr_runs(runs, "8"), [5])

    def test_reads_one_run_per_line_and_prints_ids(self):
        stdin = io.StringIO("\n".join(json.dumps(r) for r in [run(10), run(11, "completed"), run(12)]) + "\n\n")
        out = io.StringIO()
        with redirect_stdout(out):
            main(["ci_runs.py", "open-pr-runs", "12"], stdin)
        self.assertEqual(out.getvalue(), "10\n")


class WorkflowTests(unittest.TestCase):
    def test_closing_a_pull_request_cancels_its_runs(self):
        text = (WORKFLOWS / "cancel-closed-pr-runs.yml").read_text()
        self.assertIn("types: [closed]", text)
        self.assertIn("tools/ci_runs.py open-pr-runs", text)
        self.assertRegex(text, r"actions: write")

    def test_testflight_retry_only_reruns_the_newest_main_commit(self):
        # It re-ran Build for an old main commit after main had moved on (2026-11-05).
        text = (WORKFLOWS / "testflight.yml").read_text()
        retry = re.search(r"^  retry:.*?(?=^  \w)", text, re.M | re.S).group(0)
        self.assertIn("commits/main", retry)
        self.assertLess(retry.index("commits/main"), retry.index("gh run rerun"))


if __name__ == "__main__":
    unittest.main()
