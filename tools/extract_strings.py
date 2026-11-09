#!/usr/bin/env python3
"""Lists the localization keys used in the Swift sources (German source strings).

Interpolations become %lld (integers) or %@ (strings), matching how Swift builds
keys for LocalizedStringKey and String(localized:). Used by tools/localize.py.
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Kaliberfinder")
LIT = r'"((?:[^"\\]|\\.|\\\((?:[^()]|\([^()]*\))*\))*)"'
CONTEXTS = [
    r'\b(?:Text|Button|Label|Section|TextField|Picker|Toggle|LabeledContent|Stepper|Menu|ContentUnavailableView|NavigationLink)\(\s*' + LIT,
    r'\.(?:navigationTitle|alert|confirmationDialog|accessibilityLabel)\(\s*' + LIT,
    r'\b(?:prompt|title):\s*' + LIT,  # title: the camera choices (CameraChoice)
    r'\bString\(localized:\s*' + LIT,
    LIT + r'\.loc\b',
    r'\b(?:pickerRow|tile|metric|row|field|measured|choice)\(\s*' + LIT,
    r'\bBreakdownChart\(title:\s*' + LIT,
    r'\bcase \.\w+:\s*' + LIT,          # enum titles (titleKey) and error texts
    r'\bcase \w+ = ' + LIT,             # CartridgeCatalog.Category raw values
    r'\bcase "[a-z0-9-]+":\s*' + LIT,  # titles for catalogue kinds and primers
    r'\[' + LIT + r'(?:,\s*' + LIT + r')+\]\s*\n?\s*\.map\(\\\.loc\)',
]
STRINGY = ("formatted", "name", "Name", "Developer", "title", "Description", "joined", ".loc", "text", "Text", "mm(", "format(")


def key_for(literal):
    def repl(m):
        expr = m.group(1)
        return "%@" if any(t in expr for t in STRINGY) else "%lld"
    return re.sub(r'\\\(((?:[^()]|\([^()]*\))*)\)', repl, literal).replace('\\"', '"')


def keys():
    found = {}
    for dirpath, _, files in os.walk(ROOT):
        for f in files:
            if not f.endswith(".swift"):
                continue
            src = open(os.path.join(dirpath, f)).read()
            for pat in CONTEXTS:
                for m in re.finditer(pat, src):
                    for g in m.groups():
                        if g and re.search(r'[A-Za-zÄÖÜäöü]{2}', g):
                            found.setdefault(key_for(g), f)
    # SF Symbol names and other non-UI literals that the patterns can catch.
    junk = re.compile(r'^[a-z0-9_.]+$|^(pt/mm)')
    return {k: v for k, v in found.items() if not junk.match(k)}


if __name__ == "__main__":
    for k, f in sorted(keys().items()):
        print(f"{f}\t{k}")
