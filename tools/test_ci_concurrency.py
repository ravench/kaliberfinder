"""Every workflow that runs on pull requests cancels its superseded runs.

Mac runners are scarce: without a concurrency group, each push to a pull request queues a new
run while the runs for its older commits keep their place in the queue.
"""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"


def top_level(text, key):
    """The block of a top-level key, up to the next top-level key."""
    match = re.search(rf"^{key}:.*?(?=^\S|\Z)", text, re.M | re.S)
    return match.group(0) if match else ""


class CIConcurrencyTests(unittest.TestCase):
    def test_pull_request_workflows_cancel_superseded_runs(self):
        files = sorted(WORKFLOWS.glob("*.yml"))
        self.assertTrue(files)
        for path in files:
            text = path.read_text()
            if not re.search(r"^  pull_request:", top_level(text, "on"), re.M):
                continue
            with self.subTest(workflow=path.name):
                block = top_level(text, "concurrency")
                self.assertIn("github.event.pull_request.number", block)
                self.assertRegex(block, r"cancel-in-progress: (true|\$\{\{ github\.event_name == 'pull_request' \}\})")

    def test_main_builds_are_not_cancelled_while_running(self):
        # TestFlight uploads from a finished main build; a newer merge only replaces a waiting run.
        for path in sorted(WORKFLOWS.glob("*.yml")):
            text = path.read_text()
            if re.search(r"^  push:", top_level(text, "on"), re.M):
                with self.subTest(workflow=path.name):
                    self.assertNotIn("cancel-in-progress: true", top_level(text, "concurrency"))


if __name__ == "__main__":
    unittest.main()
