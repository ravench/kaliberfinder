"""Every workflow job that builds the app checks out the Git LFS files: the images are in LFS."""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parent.parent / ".github" / "workflows"


def jobs(text):
    """The (name, text) of each job in a workflow file."""
    parts = re.split(r"\n  ([\w-]+):\n", "\n" + text.split("\njobs:\n", 1)[1])
    return zip(parts[1::2], parts[2::2])


class WorkflowLfsTests(unittest.TestCase):
    def test_jobs_that_build_the_app_check_out_lfs_files(self):
        building = []
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for name, job in jobs(path.read_text()):
                if "xcodegen generate" not in job:
                    continue
                building.append(f"{path.name} {name}")
                checkout = job.split("uses: actions/checkout@", 1)[1].split("\n      - ", 1)[0]
                self.assertIn("lfs: true", checkout, f"{path.name}, job {name}")
        self.assertGreaterEqual(len(building), 2, building)


if __name__ == "__main__":
    unittest.main()
