"""Tests for the website builder (tools/website.py) and its texts (tools/website_content.py)."""
import re
import struct
import tempfile
import zlib
import unittest
from html.parser import HTMLParser
from pathlib import Path
from unittest import mock

import website as app_site

content = app_site.content

def tiny_png():
    """A valid 1x1 PNG, so the tests need no Git LFS checkout of the real icon."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff")) + chunk(b"IEND", b""))


TEST_CONTACT = {"email": "test@example.org", "address": ["Test Person", "Teststrasse 1", "8000 Zürich"],
                "uid": "CHE-000.000.000"}


class LinkCollector(HTMLParser):
    VOID = {"meta", "link", "img", "br", "input", "hr"}

    def __init__(self):
        super().__init__()
        self.links, self.stack, self.errors = [], [], []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for key in ("href", "src"):
            if key in attrs:
                self.links.append(attrs[key])
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1] != tag:
            self.errors.append(f"unexpected </{tag}>, open: {self.stack[-3:]}")
        else:
            self.stack.pop()


class SiteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.icon = Path(cls.tmp.name) / "icon.png"
        cls.icon.write_bytes(tiny_png())
        with mock.patch.dict(content.CONTACT, TEST_CONTACT), mock.patch.object(content, "ICON", cls.icon):
            cls.out = app_site.build(Path(cls.tmp.name) / "site")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def pages(self):
        for lang in app_site.LANGS:
            for page in app_site.PAGES:
                yield lang, page, self.out / app_site.page_path(lang, page)

    def test_every_page_exists_in_every_language(self):
        for lang, page, path in self.pages():
            self.assertTrue(path.is_file(), f"{lang}/{page} missing")
        self.assertTrue((self.out / "index.html").is_file())
        self.assertTrue((self.out / "en" / "privacy.html").is_file())

    def test_cname_and_icon(self):
        self.assertEqual((self.out / "CNAME").read_text().strip(), content.DOMAIN)
        self.assertTrue(content.DOMAIN.endswith(".apps.giotta.ch"))
        self.assertEqual((self.out / "icon.png").read_bytes(), tiny_png())
        self.assertTrue((app_site.ROOT / content.ICON).is_file(), content.ICON)

    def test_build_refuses_an_lfs_pointer_as_icon(self):
        pointer = Path(self.tmp.name) / "pointer.png"
        pointer.write_text("version https://git-lfs.github.com/spec/v1\noid sha256:0\nsize 1\n")
        with mock.patch.dict(content.CONTACT, TEST_CONTACT), mock.patch.object(content, "ICON", pointer):
            with self.assertRaises(SystemExit):
                app_site.build(Path(self.tmp.name) / "pointer-site")

    def test_html_is_well_formed_and_links_resolve(self):
        for lang, page, path in self.pages():
            parser = LinkCollector()
            parser.feed(path.read_text(encoding="utf-8"))
            self.assertEqual(parser.errors, [], f"{lang}/{page}")
            self.assertEqual(parser.stack, [], f"{lang}/{page} leaves tags open")
            for link in parser.links:
                if re.match(r"^(https?:|mailto:)", link):
                    continue
                self.assertTrue((path.parent / link).resolve().is_file(), f"{lang}/{page}: broken link {link}")

    def test_page_language_and_switcher(self):
        for lang, page, path in self.pages():
            text = path.read_text(encoding="utf-8")
            self.assertIn(f'<html lang="{lang}">', text)
            for other in app_site.LANGS:
                self.assertIn(f'hreflang="{other}"', text)

    def test_contact_details_on_privacy_support_and_imprint(self):
        for lang, page, path in self.pages():
            if page == "index":
                continue
            text = path.read_text(encoding="utf-8")
            self.assertIn("mailto:test@example.org", text, f"{lang}/{page}")
            if page in ("privacy", "imprint"):
                self.assertIn("Teststrasse 1", text, f"{lang}/{page}")
        for lang in app_site.LANGS:
            self.assertIn("CHE-000.000.000", (self.out / app_site.page_path(lang, "imprint")).read_text(encoding="utf-8"))

    def test_no_third_party_requests_or_scripts(self):
        for lang, page, path in self.pages():
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("<script", text)
            for match in re.finditer(r'(?:src|rel="stylesheet" href)="(https?://[^"]+)"', text):
                self.fail(f"{lang}/{page} loads {match.group(1)}")

    def test_texts_complete_in_every_language(self):
        def shape(value):
            if isinstance(value, dict):
                return {k: shape(v) for k, v in value.items()}
            if isinstance(value, (list, tuple)):
                return [shape(v) for v in value]
            return "text"

        reference = shape(content.APP["de"])
        for lang in app_site.LANGS:
            self.assertEqual(shape(content.APP[lang]), reference, f"APP[{lang}] differs in structure from de")
            self.assertEqual(set(app_site.COMMON[lang]), set(app_site.COMMON["de"]), lang)
            self.assertIn(lang, content.UPDATED)

    def test_build_refuses_missing_contact(self):
        with mock.patch.dict(content.CONTACT, {"email": "", "address": []}), \
                mock.patch.object(content, "ICON", self.icon):
            with self.assertRaises(SystemExit):
                app_site.build(Path(self.tmp.name) / "refused")

    def test_store_link_or_coming_soon(self):
        text = (self.out / "index.html").read_text(encoding="utf-8")
        if content.STORE_URL:
            self.assertIn(content.STORE_URL, text)
        else:
            self.assertIn(app_site.COMMON["de"]["soon"], text)


if __name__ == "__main__":
    unittest.main()
