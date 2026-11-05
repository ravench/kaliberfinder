"""Test results of a run, on the run's page.

Reads the summary of one or more xcresult bundles, as printed by
`xcrun xcresulttool get test-results summary --path X.xcresult`, and writes:
- a Markdown table (passed, failed, skipped per bundle, failed tests by name), appended to the
  file $GITHUB_STEP_SUMMARY names (the run's summary page), or to stdout without it
- one ::error annotation per failed test on stdout, so failures show on the run and the pull request.

    python3 tools/test_summary.py "Unit tests=unit.json" "UI tests=ui.json"

A missing or unreadable file shows as «no results» (the step broke off before testing).
"""
import json
import os
import sys


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _cell(text):
    return " ".join(str(text).split()).replace("|", "\\|")


def render(sections):
    """sections: [(label, summary dict or None)] -> (markdown, annotation lines)."""
    lines = ["### Tests", "", "| | Result | Passed | Failed | Skipped |", "|---|---|---:|---:|---:|"]
    failures, annotations = [], []
    for label, summary in sections:
        if summary is None:
            lines.append(f"| {label} | no results | | | |")
            continue
        lines.append("| {} | {} | {} | {} | {} |".format(
            label, summary.get("result", "?"), summary.get("passedTests", 0),
            summary.get("failedTests", 0), summary.get("skippedTests", 0)))
        for failure in summary.get("testFailures", []):
            name = failure.get("testName", "?")
            target = failure.get("targetName", "")
            text = failure.get("failureText", "")
            failures.append(f"| {label} | {_cell(target)} | `{_cell(name)}` | {_cell(text)} |")
            message = " ".join(text.split()).replace("%", "%25")
            annotations.append(f"::error title={label}: {name}::{message}")
    if failures:
        lines += ["", "#### Failed tests", "", "| | Target | Test | Failure |", "|---|---|---|---|"] + failures
    return "\n".join(lines) + "\n", annotations


def main(argv):
    if len(argv) < 2 or any("=" not in arg for arg in argv[1:]):
        sys.exit(__doc__)
    sections = [(label, load(path)) for label, path in (arg.split("=", 1) for arg in argv[1:])]
    markdown, annotations = render(sections)
    for line in annotations:
        print(line)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(markdown)
    else:
        print(markdown, end="")


if __name__ == "__main__":
    main(sys.argv)
