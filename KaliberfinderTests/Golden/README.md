# Golden set

A small set of real shots that `GoldenSetTests` replays on every pull request through the
phone's own path: Vision's instance mask → subject picking → outline → neck → LiDAR size →
ranking in automatic mode. It holds **no photos**: each shot is Vision's mask
(`vision-instances.png`, in Git LFS) and a trimmed `shot.json` with the LiDAR scale, the size of
the upright photo the mask covers (`mask.imageWidth`, `mask.imageHeight`) and what the phone
found when the shot was taken. The photos stay in the private training repo
(`ravench/kaliberfinder-training`), which also decides which shots are golden (`splits.json`) and
writes this folder with `tools/export_golden.py`. Don't edit the packages here by hand.

Same layout as a capture package (see `../Captures/README.md`), without photo and depth map.

`baseline.json` holds the scores the set reached: calibre first and in the first five rows of the
list as the phone shows it, the same among all calibres (see `tools/evaluate/README.md`), part
(cartridge or empty case) right in automatic mode, and neck found on calibres with a clear neck,
plus each shot's result. The test fails when a score falls more than 2 points below it, or when
the shots changed. A change that improves matching updates `baseline.json` in the same pull request:
the test prints the new one after the `GOLDEN` lines (CI log, step «Golden set report»).

The masks come from Git LFS: clone with Git LFS installed (`brew install git-lfs && git lfs install`).
