# Evaluation tool

Runs the app's photo analysis on every shot of the private training data
([ravench/kaliberfinder-training](https://github.com/ravench/kaliberfinder-training)) and reports how
often the right calibre comes first, in automatic mode as the phone starts. Use it to tune the
matching rules against all photos; the build CI only replays the small golden set
(`KaliberfinderTests/GoldenSetTests.swift`), with the same scoring (`KaliberfinderTests/Evaluation.swift`).

It runs on a Mac, because the simulator has no Vision foreground mask. `build.sh` compiles the
app's analysis code (every file in `Kaliberfinder/Services` that needs no UIKit) with the
optimised compiler, so a few hundred shots take a minute or two.

## On your Mac

Clone the training repo next to this one, with [Git LFS](https://git-lfs.com) installed, then:

```
tools/evaluate/build.sh
.build/evaluate/evaluate                         # ../kaliberfinder-training, or $KALIBERFINDER_TRAINING
.build/evaluate/evaluate --json before.json      # before a change
# … change a rule, build again …
.build/evaluate/evaluate --compare before.json   # the scores before and after, and the shots that changed
```

Options: a path to another training repo or a folder of capture packages (for example
`KaliberfinderTests/Golden`), `--holdout` for the held-back packages in `splits.json` instead of the
tuning shots, `--mac-vision`, `--json FILE`, `--compare FILE` and `--report FILE`.

## What each shot goes through

The phone's path as far as the shot allows:

| Shot | Outline from | Report says |
| --- | --- | --- |
| taken with the capture screen, with the phone's Vision mask | that mask, with the photo for the brass colour test | phone |
| taken with the capture screen, the phone's Vision found nothing | the colour cut-out, as on the phone | colour |
| an older photo the phone never analysed | Vision on the Mac, else the colour cut-out | mac |
| a golden shot (mask, no photo) | the mask, with the phone's brass colour test | phone |

`--mac-vision` also runs Vision on the Mac for the second kind, to see what a working Vision would
change there. The Mac's Vision is close to the phone's but not always the same.

## The report

Scores overall, by calibre and part, by kind of shot (cartridge or empty case, with or without a
LiDAR size, where the outline came from), the calibres most often in the phone's first row instead of
the right one, and every shot whose calibre is not in the first row. It holds shot names and numbers
only, never a photo.

The scores are the golden set's: calibre first and in the first five rows of the list as the phone
shows it, the same among all calibres, part (cartridge or empty case) right in automatic mode, and
neck found on calibres with a clear neck. The phone's list is the headline: it hides rare and obsolete
calibres (unless the shot's own calibre is one, as for a user who switched them on) and shows
calibres that look exactly the same from the side, such as GP 90 and .223 Remington, as one row.
«Among all calibres» ranks against every catalogue calibre, each on its own.

## In CI

*Evaluate matching* (`.github/workflows/evaluate.yml`) runs the tool on a macOS runner: start it by
hand from the Actions tab on a branch, for example a tuning pull request's. It compares with `main`
(or the branch you name) and puts the report on the run's page and in its `evaluation` download.
It checks out the training repo with the `TRAINING_DATA_TOKEN` secret, a fine-grained token
that can only read that repo's contents. Without the secret, as on forks, it evaluates the golden set.
Pull requests that change the tool run it too.

Held-back shots are for a last look before merging a tuning change (`--holdout`, or the *holdout*
switch of the job), not for tuning: tuning against them would fit the rules to those photos.
