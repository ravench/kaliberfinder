"""Mac jobs run on GitHub's Mac, or on the self-hosted Mac in MAC_RUNNER while the repo is private."""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"
MAC = "runs-on: ${{ github.event.repository.private && vars.MAC_RUNNER || 'macos-26' }}"


def workflow(name):
    return (WORKFLOWS / name).read_text()


def xcodebuild_builds(text):
    """Each xcodebuild call that builds or tests, with its continuation lines."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.search(r"xcodebuild (build-for-testing|test-without-building|test|archive|build)\b", line):
            command = [line]
            while command[-1].rstrip().endswith("\\"):
                i += 1
                command.append(lines[i])
            yield "\n".join(command)


class MacRunnerTests(unittest.TestCase):
    def test_mac_jobs_use_the_self_hosted_mac_only_while_private(self):
        # The repo's own workflows never send a public repo's jobs to that Mac (README).
        mac = []
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for line in path.read_text().splitlines():
                if line.strip().startswith("runs-on:") and "ubuntu" not in line:
                    self.assertEqual(line.strip(), MAC, path.name)
                    mac.append(path.name)
        self.assertGreaterEqual(len(mac), 3, mac)

    def test_nothing_is_left_in_the_runners_home(self):
        # A self-hosted Mac keeps its home folder between runs: keys go to RUNNER_TEMP.
        for path in sorted(WORKFLOWS.glob("*.yml")):
            self.assertIsNone(re.search(r"~/|\$HOME\b|\$\{HOME\}", path.read_text()), path.name)
        self.assertIn("UserKnownHostsFile='$HOSTS'", workflow("build.yml"))
        # xcodebuild's distribution logs, which the failure step lists, go there too.
        testflight = workflow("testflight.yml")
        self.assertLess(testflight.index('echo "TMPDIR=$RUNNER_TEMP" >> "$GITHUB_ENV"'),
                        testflight.index("xcodebuild archive"))

    def test_a_mac_that_keeps_its_state_starts_clean(self):
        build = workflow("build.yml")
        # Shut down first: erase fails on a simulator a crashed run left booted.
        self.assertLess(build.index('xcrun simctl shutdown "$UDID"'), build.index('xcrun simctl erase "$UDID"'))
        self.assertLess(build.index('xcrun simctl erase "$UDID"'), build.index('xcrun simctl boot "$UDID"'))
        last_step = build.rsplit("\n      - ", 1)[1]
        self.assertIn("if: always()", last_step)
        self.assertIn('xcrun simctl shutdown "$UDID"', last_step)
        evaluate = workflow("evaluate.yml")
        self.assertLess(evaluate.index("git worktree prune"), evaluate.index("git worktree add"))
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for line in path.read_text().splitlines():
                if "brew install xcodegen" in line:
                    self.assertIn("command -v xcodegen >/dev/null ||", line, path.name)

    def test_builds_go_to_runner_temp(self):
        # Xcode's default DerivedData is in the home folder, where a self-hosted Mac would keep it.
        builds = 0
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for command in xcodebuild_builds(path.read_text()):
                builds += 1
                self.assertIn("-derivedDataPath", command, f"{path.name}: {command.splitlines()[0].strip()}")
        self.assertGreaterEqual(builds, 5)


if __name__ == "__main__":
    unittest.main()
