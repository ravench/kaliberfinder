"""The crash reports testers sent from TestFlight (.github/workflows/crashes.yml).

    python3 tools/crashes.py AuthKey.p8 crashes/
        Lists them, newest first (ASC_KEY_ID, ASC_ISSUER_ID), and writes each crash log into crashes/.
"""
import json
import os
import re
import sys
import urllib.request

import changelog

# Not the tester's e-mail: the run's log is public.
FIELDS = "createdDate,comment,deviceModel,osVersion,appPlatform,locale,buildBundleId,build"


def submissions(app_id, token):
    """The newest crash submissions of the app, with the build each came from."""
    return changelog.asc("GET", f"/apps/{app_id}/betaFeedbackCrashSubmissions?sort=-createdDate&limit=50"
                         f"&fields[betaFeedbackCrashSubmissions]={FIELDS}&include=build&fields[builds]=version", token)


def lines(response):
    """One line per submission: when, build, device, system, the tester's comment."""
    builds = {b["id"]: b["attributes"].get("version", "?") for b in response.get("included", [])}
    out = []
    for s in response["data"]:
        a = s["attributes"]
        build = builds.get(((s.get("relationships") or {}).get("build") or {}).get("data", {}).get("id"), "?")
        out.append(f"{a.get('createdDate', '?')}  build {build}  {a.get('deviceModel', '?')}  "
                   f"{a.get('appPlatform', '')} {a.get('osVersion', '?')}  {a.get('comment') or ''}".rstrip())
    return out


def crash_log(submission_id, token):
    """The crash log's text; the API hands out a short-lived download link."""
    data = changelog.asc("GET", f"/betaFeedbackCrashSubmissions/{submission_id}/crashLog", token)["data"]
    url = data.get("attributes", {}).get("url")
    if not url:
        return json.dumps(data, indent=1)  # not the expected shape: keep what came
    with urllib.request.urlopen(url) as response:
        return response.read().decode(errors="replace")


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    key_path, out = argv[1], argv[2]
    key_id, issuer = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]
    apps = changelog.asc("GET", f"/apps?filter[bundleId]={changelog.bundle_id()}", changelog.token(key_path, key_id, issuer))["data"]
    if not apps:
        sys.exit("No app on App Store Connect")
    response = submissions(apps[0]["id"], changelog.token(key_path, key_id, issuer))
    os.makedirs(out, exist_ok=True)
    for submission, line in zip(response["data"], lines(response)):
        print(line, flush=True)
        name = re.sub(r"[^0-9A-Za-z]", "-", submission["attributes"].get("createdDate", "")) + "-" + submission["id"][:8] + ".crash"
        with open(os.path.join(out, name), "w") as f:
            f.write(crash_log(submission["id"], changelog.token(key_path, key_id, issuer)))
    print(f"{len(response['data'])} crash reports")


if __name__ == "__main__":
    main(sys.argv)
