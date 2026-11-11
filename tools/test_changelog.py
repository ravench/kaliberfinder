"""Unit tests for tools/changelog.py.

    python3 -m unittest discover -s tools -p 'test_changelog.py'
"""
import base64
import json
import os
import subprocess
import tempfile
import types
import unittest

import changelog

ROOT = changelog.ROOT
NOTES = {"de": ["Neu: A", "Neu: B"], "en": ["New: A", "New: B"], "fr": ["Nouveau : A", "Nouveau : B"], "it": ["Nuovo: A", "Nuovo: B"]}


class FakeClient:
    """Answers like the Claude API, and keeps the request."""

    def __init__(self, text, stop_reason="end_turn"):
        self.text, self.stop_reason, self.request = text, stop_reason, None
        self.messages = types.SimpleNamespace(create=self.create)

    def create(self, **kwargs):
        self.request = kwargs
        return types.SimpleNamespace(stop_reason=self.stop_reason, content=[types.SimpleNamespace(type="text", text=self.text)])


def repo(tmp, tag_head=False):
    """A repository with three commits; the first is a TestFlight build."""
    def run(*args):
        subprocess.run(["git", *args], cwd=tmp, check=True, capture_output=True,
                       env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})
    run("init", "-q")
    for i, message in enumerate(["Old change (#1)", "Faster photos (#2)\n\nThe second look is quicker.", "New sheet (#3)"]):
        with open(os.path.join(tmp, f"{i}.txt"), "w") as f:
            f.write(message)
        run("add", ".")
        run("commit", "-q", "-m", message)
        if i == 0:
            run("tag", "testflight/1001")
    if tag_head:
        run("tag", "testflight/1002")


RELEASE_NOTES = """# Release notes

## 0.3.0

### de
- Neu: C

## 0.2.0

### de
- Neu: A
- Neu: B

### en
- New: A
- New: B

### fr
-
"""


class ReleaseNotesTests(unittest.TestCase):
    def test_the_version_section_by_language(self):
        self.assertEqual(changelog.hand_written("0.2.0", RELEASE_NOTES), {"de": ["Neu: A", "Neu: B"], "en": ["New: A", "New: B"]})
        self.assertEqual(changelog.hand_written("0.3.0", RELEASE_NOTES), {"de": ["Neu: C"]})
        self.assertIsNone(changelog.hand_written("0.1.0", RELEASE_NOTES))
        self.assertIsNone(changelog.hand_written("0.2.0", "## 0.2.0\n\n### de\n- \n"), "an empty template is no notes")

    def test_a_tagged_release_takes_the_hand_written_notes(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo(tmp)
            self.assertIsNone(changelog.release_version(tmp))
            subprocess.run(["git", "tag", "v0.2.0"], cwd=tmp, check=True)
            self.assertEqual(changelog.release_version(tmp), "0.2.0")
            notes_path = os.path.join(tmp, "RELEASE_NOTES.md")
            with open(notes_path, "w") as f:
                f.write(RELEASE_NOTES)
            out = os.path.join(tmp, "Changelog.json")
            client = FakeClient(json.dumps(NOTES))
            changelog.write_notes(out, tmp, client, release_notes=notes_path)
            self.assertIsNone(client.request, "no call to the Claude API for a release")
            with open(out) as f:
                self.assertEqual(json.load(f), {"notes": {"de": ["Neu: A", "Neu: B"], "en": ["New: A", "New: B"]}})
            # A release without a section still gets the summary.
            subprocess.run(["git", "tag", "-d", "v0.2.0"], cwd=tmp, check=True, capture_output=True)
            subprocess.run(["git", "tag", "v0.9.0"], cwd=tmp, check=True)
            changelog.write_notes(out, tmp, client, release_notes=notes_path)
            self.assertIsNotNone(client.request)

    def test_the_repo_has_the_notes_file_with_the_format(self):
        with open(os.path.join(ROOT, "RELEASE_NOTES.md")) as f:
            text = f.read()
        self.assertIn("### de", text)
        # The first App Store release has its hand-written notes in every language.
        self.assertEqual(sorted(changelog.hand_written("1.0.0", text)), ["de", "en", "fr", "it"])


class CommitsTests(unittest.TestCase):
    def test_since_the_last_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo(tmp)
            text, rng = changelog.commits(tmp)
        self.assertEqual(rng, "testflight/1001..HEAD")
        self.assertIn("### New sheet (#3)", text)
        self.assertIn("The second look is quicker.", text)
        self.assertNotIn("Old change", text)
        self.assertLess(text.index("New sheet"), text.index("Faster photos"), "newest first")

    def test_first_build_takes_the_newest_commits(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo(tmp)
            subprocess.run(["git", "tag", "-d", "testflight/1001"], cwd=tmp, check=True, capture_output=True)
            self.assertIsNone(changelog.previous_build(tmp))
            text, rng = changelog.commits(tmp)
        self.assertEqual(rng, f"-{changelog.FIRST_BUILD_COMMITS}")
        self.assertIn("Old change", text)

    def test_same_commit_again_has_no_notes(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo(tmp, tag_head=True)
            out = os.path.join(tmp, "Changelog.json")
            changelog.write_notes(out, cwd=tmp, client=FakeClient("never asked"))
            with open(out) as f:
                self.assertEqual(json.load(f), {"notes": {}})


class SummariseTests(unittest.TestCase):
    def test_asks_for_all_languages_as_json(self):
        client = FakeClient(json.dumps(NOTES))
        notes = changelog.summarise("### Faster photos (#2)", client)
        self.assertEqual(notes, NOTES)
        request = client.request
        self.assertEqual(request["model"], changelog.MODEL)
        self.assertIn("Faster photos", request["messages"][0]["content"])
        self.assertIn("Swiss spelling", request["system"])
        schema = request["output_config"]["format"]["schema"]
        self.assertEqual(schema["required"], ["de", "en", "fr", "it"])
        self.assertFalse(schema["additionalProperties"])

    def test_missing_language_or_refusal_fails(self):
        with self.assertRaises(ValueError):
            changelog.summarise("x", FakeClient(json.dumps({**NOTES, "it": []})))
        with self.assertRaises(ValueError):
            changelog.summarise("x", FakeClient(json.dumps(NOTES), stop_reason="refusal"))

    def test_writes_one_line_for_the_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo(tmp)
            out = os.path.join(tmp, "Changelog.json")
            changelog.write_notes(out, cwd=tmp, client=FakeClient(json.dumps(NOTES)))
            with open(out) as f:
                text = f.read()
        self.assertNotIn("\n", text)
        self.assertEqual(json.loads(text), {"notes": NOTES})


class TokenTests(unittest.TestCase):
    def test_der_to_raw_strips_and_pads(self):
        der = bytes([0x30, 0x08, 0x02, 0x02, 0x00, 0xff, 0x02, 0x02, 0x01, 0x02])
        raw = changelog.der_to_raw(der)
        self.assertEqual(len(raw), 64)
        self.assertEqual(raw[:32], bytes(31) + b"\xff")
        self.assertEqual(raw[32:], bytes(30) + b"\x01\x02")

    def test_signed_with_the_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            key, pub = os.path.join(tmp, "k.p8"), os.path.join(tmp, "k.pub")
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", key], check=True)
            subprocess.run(["openssl", "ec", "-in", key, "-pubout", "-out", pub], check=True, capture_output=True)
            jwt = changelog.token(key, "KEY1", "issuer-1", now=1_700_000_000)
            header, claims, signature = jwt.split(".")
            decode = lambda part: json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
            self.assertEqual(decode(header), {"alg": "ES256", "kid": "KEY1", "typ": "JWT"})
            self.assertEqual(decode(claims), {"iss": "issuer-1", "iat": 1_700_000_000, "exp": 1_700_001_200, "aud": "appstoreconnect-v1"})
            raw = base64.urlsafe_b64decode(signature + "=" * (-len(signature) % 4))
            self.assertEqual(len(raw), 64)
            # Back to DER, and openssl must accept it for the signed part.
            def integer(b):
                b = b.lstrip(b"\0")
                if b[0] & 0x80:
                    b = b"\0" + b
                return bytes([0x02, len(b)]) + b
            body = integer(raw[:32]) + integer(raw[32:])
            sig = os.path.join(tmp, "sig.der")
            with open(sig, "wb") as f:
                f.write(bytes([0x30, len(body)]) + body)
            check = subprocess.run(["openssl", "dgst", "-sha256", "-verify", pub, "-signature", sig],
                                   input=f"{header}.{claims}".encode(), capture_output=True)
            self.assertEqual(check.returncode, 0, check.stderr)


class WhatToTestTests(unittest.TestCase):
    def test_changes_existing_languages_and_adds_the_others(self):
        existing = [{"id": "L1", "attributes": {"locale": "de-DE", "whatsNew": "old"}}]
        requests = changelog.localization_requests("B1", existing, {**NOTES, "it": []})
        self.assertEqual([(m, p) for m, p, _ in requests],
                         [("PATCH", "/betaBuildLocalizations/L1"), ("POST", "/betaBuildLocalizations"), ("POST", "/betaBuildLocalizations")])
        patch, en, fr = (body["data"] for _, _, body in requests)
        self.assertEqual(patch["id"], "L1")
        self.assertEqual(patch["attributes"]["whatsNew"], "• Neu: A\n• Neu: B")
        self.assertEqual(en["attributes"]["locale"], "en-US")
        self.assertEqual(en["relationships"]["build"]["data"], {"type": "builds", "id": "B1"})
        self.assertEqual(fr["attributes"]["locale"], "fr-FR")

    def test_text_within_the_limit(self):
        self.assertEqual(len(changelog.what_to_test_text(["x" * 5000])), 4000)


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, ".github", "workflows", "testflight.yml")) as f:
            cls.workflow = f.read()
        cls.upload = cls.workflow.split("\n  upload:")[1].split("\n  what-to-test:")[0]

    def test_a_release_tag_uploads_under_its_version(self):
        self.assertIn("tags: ['v[0-9]*']", self.workflow)
        self.assertIn("github.event_name == 'push'", self.workflow)
        self.assertIn("tools/testflight.py version", self.upload)
        self.assertIn('MARKETING_VERSION="$MARKETING_VERSION"', self.upload)

    def test_notes_go_into_the_archive(self):
        # The whole history, for the tag of the last build and the commits since.
        self.assertIn("fetch-depth: 0", self.upload)
        self.assertIn("ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}", self.upload)
        notes = self.upload.index("tools/changelog.py notes Kaliberfinder/Resources/Changelog.json")
        self.assertLess(self.upload.index("xcodegen generate"), notes)
        self.assertLess(notes, self.upload.index("xcodebuild archive"))
        # A build without notes still goes out.
        self.assertIn("::warning::Release notes skipped", self.upload)

    def test_upload_tags_the_build(self):
        self.assertIn("contents: write", self.upload)
        self.assertLess(self.upload.index("Upload to TestFlight"), self.upload.index('git tag "testflight/$BUILD_NUMBER"'))
        self.assertIn('git push origin "refs/tags/testflight/$BUILD_NUMBER"', self.upload)

    def test_what_to_test_waits_on_linux(self):
        job = self.workflow.split("\n  what-to-test:")[1]
        self.assertIn("needs: upload", job)
        self.assertIn("runs-on: ubuntu-latest", job)
        self.assertIn("needs.upload.outputs.notes != ''", job)
        self.assertIn('tools/changelog.py what-to-test "$RUNNER_TEMP/AuthKey.p8" "$BUILD_NUMBER"', job)
        self.assertIn("outputs:\n      notes: ${{ steps.notes.outputs.notes }}", self.upload)

    def test_bundle_placeholder(self):
        # Development builds carry the file CI overwrites, without notes.
        with open(os.path.join(ROOT, "Kaliberfinder", "Resources", "Changelog.json")) as f:
            self.assertEqual(json.load(f), {"notes": {}})


if __name__ == "__main__":
    unittest.main()
