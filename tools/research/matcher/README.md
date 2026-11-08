# A matcher from scratch (research, 2026-11-08)

Raven asked for one night of tuning: start the photo matching from scratch, see what the best
reachable result is, and only then compare with the app's algorithm, on all of the training data
(222 shots in 23 packages of [ravench/kaliberfinder-training](https://github.com/ravench/kaliberfinder-training)).
This folder is that experiment, in Python, so it can iterate in seconds. Nothing here ships in
the app; what proved out is listed under *Worth porting*.

## Result

Scores are the phone's list with the «Erkennung» switches off, twins in one row, as
`KaliberfinderTests/Evaluation.swift` counts them, over all 222 shots.

| | Calibre first | In the top 5 |
| --- | ---: | ---: |
| App on main (`tools/evaluate`, 2026-11-08) | 68.9 % | 82.4 % |
| This matcher, weights fitted on all shots | 83.8 % | 91.9 % |
| This matcher, leave-one-package-out | 73.9 % | 91.4 % |

Shot by shot: 138 both get first, 48 only this matcher, 15 only the app, 21 neither. The app's
15 are mostly empty cases and blanks whose part this matcher reads the other way, and two 9 mm
shots whose shaded side it does not restore. The 21 neither gets are 14 library photos without
LiDAR (nine GP 11 cases, four 9 mm), where only the shape is known, and a few bad cut-outs.

## What the pipeline does

1. **Segmentation** (`extract.py`): Apple Vision from Python (PyObjC) on the Mac. On the whole
   photo Vision finds the cartridge in 96 of 222 shots, the same failure rate the phone sees. A
   cascade of centre crops (60 %, 40 %, 25 % of the photo) and a crop around the most salient
   object lifts that to 219 of 222. Then a second look on the cartridge cut from the full-size
   photo, as the app does. The LiDAR depth map does not show the cartridge (it sits at the
   table's depth), so depth cannot segment. Vision degrades after many images in one process:
   run one process per package.
2. **Measurement** (`kf.py`): principal axis, 40 slice widths, mirror trim, rim and mouth
   features; size in mm from the LiDAR distance with the half-diameter axis correction. Lengths
   come out 3.4 % long (the ends rise above the axis), diameters 0.3 % short.
3. **Photo cues**: the case mouth from the colours along the axis (`mouth.py`, a two-segment split
   of (g−b)/s and (r−g)/s), and the dark side given back where the mask stops in the shadow
   (`darkside.py`: asymmetry about the axis through the tip, dark just outside the edge).
4. **Scoring** (`run.py`, `fast.py`): aspect, profile and rim terms against every catalogue
   outline, LiDAR length and diameter with a per-calibre end rise (a bullet tip lies on the axis,
   a case mouth half its width above it, the head half the rim), a soft part decision (both the
   whole and the empty-case comparison, penalised by the end's width), and the case mouth as a
   capped penalty. Weights are fitted by coordinate search with random restarts; the leave-one-
   package-out figure trains without each package and tests on it.

## Worth porting to the app

- The centre-crop cascade before falling back to the colour cut-out: it turns most of the
  phone's «Vision found nothing» shots into Vision masks.
- A per-calibre end rise (the app has one; this one also rises the mouth of empty cases).
- The soft part decision instead of the flat-end rule: .45 ACP and GP 90 cases stop landing on
  9 mm pistol calibres.
- A cap on the case-mouth penalty, since real cartridges differ from the catalogue (Raven's GP 11
  has a long silver bullet, the Vetterli a copper case with a brass band).

## Running it

```
python3 -m venv build/venv && build/venv/bin/pip install numpy scipy pillow pyobjc-framework-Vision pyobjc-framework-Quartz
cd tools/research/matcher
for p in ../../../../kaliberfinder-training/captures/*/; do ../../../build/venv/bin/python extract.py ../../../../kaliberfinder-training data "$(basename "$p")"; done
../../../build/venv/bin/python -W ignore fast.py ../../../../kaliberfinder-training data --rounds 4 --restarts --out params.json
```

`params.json` holds the weights the numbers above were reached with.
