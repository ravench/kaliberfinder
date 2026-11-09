"""Release notes for the TestFlight builds (.github/workflows/testflight.yml).

    python3 tools/changelog.py notes Kaliberfinder/Resources/Changelog.json
        The commits since the last TestFlight build (tag testflight/<build>), summarised by the
        Claude API (ANTHROPIC_API_KEY) into short bullet points in the app's four languages and
        written into the bundle: the app shows them the first time a build is opened (Changelog.swift).
    python3 tools/changelog.py what-to-test AuthKey.p8 1042 < Changelog.json
        Puts them into that build's «What to Test» on TestFlight once App Store Connect has
        processed it (ASC_KEY_ID, ASC_ISSUER_ID; waits up to an hour).

A release (a commit tagged v<version>) takes its notes from RELEASE_NOTES.md instead, written by
hand (Raven, 2026-11-09): the section «## <version>» with «### de», «### en», «### fr», «### it»
and their bullets; languages left out fall back to German in the app and are not sent to TestFlight.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = "claude-opus-5-5"
# App Store Connect's names for the app's languages (CFBundleLocalizations in project.yml).
LOCALES = {"de": "de-DE", "en": "en-US", "fr": "fr-FR", "it": "it"}
# With no earlier TestFlight build to compare with, the newest commits.
FIRST_BUILD_COMMITS = 20
ASC = "https://api.appstoreconnect.apple.com/v1"

SYSTEM = """You write the release notes of Kaliberfinder, an iOS app that recognises the calibre of a cartridge from a photo, from its measurements or from a list of calibres, and shows cartridges at their real size.
From the commit messages you are given, write what changed for the people who use the app: short, descriptive bullet points, one per change, the most visible first, at most eight. Merge commits that belong to one change. Leave out what users cannot notice: CI, tests, tooling, research, refactoring, pull request numbers, file and type names. No bullet markers in the text.
The same bullets in German, English, French and Italian. German in Swiss spelling (ss, never ß), as the app writes it."""

SCHEMA = {"type": "object", "additionalProperties": False, "required": list(LOCALES),
          "properties": {lang: {"type": "array", "items": {"type": "string"}} for lang in LOCALES}}


def git(*args, cwd=ROOT):
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout


def previous_build(cwd=ROOT):
    """The tag of the last TestFlight build this commit descends from, None before the first."""
    try:
        return git("describe", "--tags", "--match", "testflight/*", "--abbrev=0", cwd=cwd).strip()
    except subprocess.CalledProcessError:
        return None


def commits(cwd=ROOT):
    """The messages of the commits since the last TestFlight build, newest first, and their range."""
    tag = previous_build(cwd)
    rng = f"{tag}..HEAD" if tag else f"-{FIRST_BUILD_COMMITS}"
    return git("log", "--format=### %s%n%b", rng, cwd=cwd).strip(), rng


def summarise(text, client=None):
    """Bullet points by language for the commit messages `text`, from the Claude API."""
    if client is None:
        import anthropic  # only the TestFlight job installs it
        client = anthropic.Anthropic()
    response = client.messages.create(
        model=MODEL, max_tokens=4096, system=SYSTEM,
        messages=[{"role": "user", "content": "The commit messages, newest first:\n\n" + text}],
        output_config={"format": {"type": "json_schema", "schema": SCHEMA}})
    if response.stop_reason != "end_turn":
        raise ValueError(f"the model stopped with {response.stop_reason}")
    notes = json.loads(next(b.text for b in response.content if b.type == "text"))
    missing = [lang for lang in LOCALES if not notes.get(lang)]
    if missing:
        raise ValueError(f"no bullets in {missing}: {notes}")
    return {lang: [b.strip() for b in notes[lang]] for lang in LOCALES}


def release_version(cwd=ROOT):
    """The version of the release tag (v<version>) on this very commit, None for an ordinary build."""
    tags = git("tag", "--points-at", "HEAD", "--list", "v[0-9]*", cwd=cwd).split()
    return tags[-1][1:] if tags else None


def hand_written(version, text):
    """The bullets by language of the «## version» section of RELEASE_NOTES.md, None when there is none."""
    sections = re.split(r"^## +", text, flags=re.M)
    body = next((s for s in sections if s.split("\n", 1)[0].strip() == version), None)
    if body is None:
        return None
    notes = {}
    for part in re.split(r"^### +", body, flags=re.M)[1:]:
        lang, _, bullets = part.partition("\n")
        lang = lang.strip()
        if lang in LOCALES:
            notes[lang] = [line[2:].strip() for line in bullets.splitlines() if line.startswith("- ") and line[2:].strip()]
    return {lang: b for lang, b in notes.items() if b} or None


def write_notes(path, cwd=ROOT, client=None, release_notes=os.path.join(ROOT, "RELEASE_NOTES.md")):
    """Changelog.json for the bundle: a release's hand-written notes, else the commits summarised;
    no commits (the same commit again), no notes."""
    version = release_version(cwd)
    notes = None
    if version and os.path.exists(release_notes):
        with open(release_notes) as f:
            notes = hand_written(version, f.read())
    if notes:
        rng = f"release {version}"
    else:
        text, rng = commits(cwd)
        notes = summarise(text, client) if text else {}
    with open(path, "w") as f:
        json.dump({"notes": notes}, f, ensure_ascii=False)  # one line, for $GITHUB_OUTPUT
    print(f"{sum(map(len, notes.values()))} bullets for {rng}")


def der_to_raw(der):
    """An ECDSA signature as a JWT wants it, r and s as 32 bytes each, from openssl's DER."""
    assert der[0] == 0x30, "not a DER sequence"
    parts, i = [], 2
    for _ in range(2):
        assert der[i] == 0x02, "not a DER integer"
        n = der[i + 1]
        parts.append(der[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0"))
        i += 2 + n
    return b"".join(parts)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(key_path, key_id, issuer, now=None):
    """A JWT for the App Store Connect API, signed with the .p8 key, good for 20 minutes."""
    now = int(now or time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claims = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}).encode())
    signed = f"{header}.{claims}"
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path], input=signed.encode(),
                         capture_output=True, check=True).stdout
    return f"{signed}.{b64url(der_to_raw(der))}"


def asc(method, path, token, body=None):
    request = urllib.request.Request(ASC + path, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response) if response.status != 204 else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e}\n{e.read().decode()}")


def what_to_test_text(bullets):
    return "\n".join(f"• {b}" for b in bullets)[:4000]  # App Store Connect's limit


def localization_requests(build_id, existing, notes):
    """The requests that put `notes` into a build's «What to Test»: one per language, changing the
    text App Store Connect already has for it or adding the language. `existing`: the build's
    betaBuildLocalizations."""
    ids = {loc["attributes"]["locale"]: loc["id"] for loc in existing}
    requests = []
    for lang, locale in LOCALES.items():
        if not notes.get(lang):
            continue
        text = what_to_test_text(notes[lang])
        if locale in ids:
            requests.append(("PATCH", f"/betaBuildLocalizations/{ids[locale]}",
                             {"data": {"type": "betaBuildLocalizations", "id": ids[locale], "attributes": {"whatsNew": text}}}))
        else:
            requests.append(("POST", "/betaBuildLocalizations",
                             {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
                                       "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}))
    return requests


def what_to_test(notes, build_number, key_path, key_id, issuer, bundle_id, wait=3600, poll=60):
    """Waits for App Store Connect to process build `build_number` and sets its «What to Test»."""
    def fresh():
        return token(key_path, key_id, issuer)
    apps = asc("GET", f"/apps?filter[bundleId]={bundle_id}", fresh())["data"]
    if not apps:
        sys.exit(f"No app {bundle_id} on App Store Connect")
    deadline = time.time() + wait
    while True:
        builds = asc("GET", f"/builds?filter[app]={apps[0]['id']}&filter[version]={build_number}", fresh())["data"]
        states = [b["attributes"]["processingState"] for b in builds]
        if "VALID" in states:
            build = builds[states.index("VALID")]
            break
        if "FAILED" in states or "INVALID" in states:
            sys.exit(f"Build {build_number} failed processing: {states}")
        if time.time() > deadline:
            sys.exit(f"Build {build_number} not processed within {wait // 60} minutes")
        print(f"Build {build_number}: {states or 'not on App Store Connect yet'}", flush=True)
        time.sleep(poll)
    existing = asc("GET", f"/builds/{build['id']}/betaBuildLocalizations", fresh())["data"]
    for method, path, body in localization_requests(build["id"], existing, notes):
        asc(method, path, fresh(), body)
        print(f"{method} {body['data']['attributes'].get('locale', path)}")


def bundle_id():
    """The app's bundle identifier, from project.yml."""
    with open(os.path.join(ROOT, "project.yml")) as f:
        return re.search(r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", f.read()).group(1)


def main(argv):
    if len(argv) == 3 and argv[1] == "notes":
        write_notes(argv[2])
    elif len(argv) == 4 and argv[1] == "what-to-test":
        notes = json.load(sys.stdin)["notes"]
        what_to_test(notes, argv[3], argv[2], os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], bundle_id())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
