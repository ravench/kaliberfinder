"""Mac jobs run on GitHub's Mac, or on the self-hosted Mac in MAC_RUNNER while the repo is private."""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"
MAC = "runs-on: ${{ github.event.repository.private && vars.MAC_RUNNER || 'macos-26' }}"


class MacRunnerTests(unittest.TestCase):
    def test_mac_jobs_use_the_self_hosted_mac_only_while_private(self):
        # On a public repo anyone's pull request could run code on that Mac.
        mac = []
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for line in path.read_text().splitlines():
                if line.strip().startswith("runs-on:") and "ubuntu" not in line:
                    self.assertEqual(line.strip(), MAC, path.name)
                    mac.append(path.name)
        self.assertGreaterEqual(len(mac), 3, mac)

    def test_nothing_is_written_to_the_runners_home(self):
        # A self-hosted Mac keeps its home folder between runs: keys go to RUNNER_TEMP.
        for path in sorted(WORKFLOWS.glob("*.yml")):
            self.assertIsNone(re.search(r"~/|\$HOME\b|\$\{HOME\}", path.read_text()), path.name)


if __name__ == "__main__":
    unittest.main()
