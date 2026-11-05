"""Workflow runs to cancel once a pull request is merged or closed.

Reads runs from `gh api repos/OWNER/REPO/actions/runs?branch=BRANCH --paginate --jq '.workflow_runs[]'`
(one JSON object per line) on stdin and prints the ids of the pull request runs that are still
queued or running, leaving out the given run (the one doing the cancelling).

    ... | python3 tools/ci_runs.py open-pr-runs RUN_ID
"""
import json
import sys


def open_pr_runs(runs, own_id):
    """Ids of pull request runs that have not finished, except own_id."""
    return [run["id"] for run in runs
            if run.get("event") == "pull_request"
            and run.get("status") != "completed"
            and str(run["id"]) != str(own_id)]


def main(argv, stdin=sys.stdin):
    if len(argv) == 3 and argv[1] == "open-pr-runs":
        runs = [json.loads(line) for line in stdin if line.strip()]
        for run_id in open_pr_runs(runs, argv[2]):
            print(run_id)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
