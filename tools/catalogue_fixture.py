#!/usr/bin/env python3
"""Writes KaliberfinderTests/Fixtures/catalogue.json: frozen copies of the calibres the unit tests
run on (`Fixture.catalogue`), taken from the generated Kaliberfinder/Resources/Cartridges.json, with
the lookalike groups whose members are all among them. Run it on purpose only, when a test needs a
calibre or a value that moved: a data bump must not change the tests."""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IDS = [
    "9x19 mm", "9x21 mm IMI", "7.65 mm Parabellum", ".30 Super Carry", "9 mm Browning kurz (.380 ACP)",
    ".22 LR", ".17 HMR", ".22 WMR", ".45 ACP", ".32 S&W Long", ".38 Super", "10 mm Auto",
    ".38 Special", ".357 Magnum", ".44 Magnum", ".50 Action Express", ".44 Rundkugel (.454)",
    "7.5x55 mm Swiss (GP 11)", "7.5x53.5 mm Swiss (GP 1890)", "7.5x54.5 mm Swiss (GP 90/23)", "7.5 mm Kadettenpatrone",
    "5.6 mm GP 90", ".223 Remington", "5.56x45 mm NATO", ".308 Winchester", "7.62x51 mm NATO",
    "6 mm Creedmoor", "6.5 mm Creedmoor", ".30-30 Winchester", "8x57 mm IS", "7x57 mm Mauser", "7x57 mm R",
    "7.63x25 mm Mauser", "6.5x54 mm Mannlicher-Schönauer", ".577/450 Martini-Henry",
    "10.4x38 mm R Vetterli", "10.4x38 mm R Vetterli Centrefire", "7.5 mm Swiss Ordnance 1882",
    "7.62x39 mm", "11x59 mm R Gras", ".450 No. 2 Nitro Express", ".36 Rundkugel (.375)", "12/70", "12/76", "12/89",
]


def main():
    with open(os.path.join(ROOT, "Kaliberfinder", "Resources", "Cartridges.json")) as f:
        catalogue = json.load(f)
    by_id = {c["id"]: c for c in catalogue["cartridges"]}
    missing = [i for i in IDS if i not in by_id]
    assert not missing, f"not in the catalogue: {missing}"
    chosen = set(IDS)
    fixture = {"version": catalogue["version"], "calibreData": catalogue["calibreData"],
               "cartridges": [by_id[i] for i in IDS],
               "lookalikes": [g for g in catalogue["lookalikes"] if chosen.issuperset(g["calibres"])]}
    with open(os.path.join(ROOT, "KaliberfinderTests", "Fixtures", "catalogue.json"), "w") as f:
        json.dump(fixture, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"{len(IDS)} calibres, {len(fixture['lookalikes'])} groups")


if __name__ == "__main__":
    main()
