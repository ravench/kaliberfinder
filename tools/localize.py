#!/usr/bin/env python3
"""Builds Kaliberfinder/Resources/Localizable.xcstrings (source: German; en, fr, it, es).

    python3 tools/localize.py

Fails if a key used in the Swift sources has no translation, so new UI text
can't ship untranslated.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from extract_strings import used_keys
from translations import T, INFO_PLIST
import generate_data  # noqa: E402,F401  (puts calibre-data's cartridges on the path)
from cartridges import COUNTRY_NAMES as NAMES  # noqa: E402  (on the path since generate_data)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Kaliberfinder", "Resources", "Localizable.xcstrings")

# The countries' English, French, Italian and Spanish names are calibre-data's.
T = {**T, **{n["de"]: (n["en"], n["fr"], n["it"], n["es"]) for n in NAMES.values()}}
used = used_keys()
missing = sorted(k for k in used if k not in T)
if missing:
    print("Missing translations:\n  " + "\n  ".join(missing))
    sys.exit(1)

strings = {}
for key in sorted(T):
    en, fr, it, es = T[key]
    strings[key] = {"extractionState": "manual", "localizations": {
        lang: {"stringUnit": {"state": "translated", "value": v}}
        for lang, v in (("en", en), ("fr", fr), ("it", it), ("es", es))}}
json.dump({"sourceLanguage": "de", "strings": strings, "version": "1.0"},
          open(OUT, "w"), ensure_ascii=False, indent=2, sort_keys=True)
# Info.plist texts (German source in project.yml).
info = {key: {"extractionState": "manual", "localizations": {
    lang: {"stringUnit": {"state": "translated", "value": v}}
    for lang, v in zip(("de", "en", "fr", "it", "es"), values)}} for key, values in INFO_PLIST.items()}
json.dump({"sourceLanguage": "de", "strings": info, "version": "1.0"},
          open(os.path.join(os.path.dirname(OUT), "InfoPlist.xcstrings"), "w"), ensure_ascii=False, indent=2, sort_keys=True)
unused = sorted(k for k in T if k not in used)
print(f"{len(strings)} keys written" + (f"; unused: {unused}" if unused else ""))
