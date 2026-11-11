# Kaliberfinder

Small iOS app (SwiftUI, iOS 17+, iPhone and iPad) that shows cartridges at **real size**
on the screen, so you can lay a cartridge on the display and see which calibre
it is, after taking a photo of it. In German, English, French and Italian.

This README uses the app's English names and gives the German ones in
parentheses.

## Features

- **Identify a cartridge** (Patrone erkennen): take a photo of a cartridge (or pick one)
  and get a ranked list of likely calibres. The app cuts the cartridge out of the photo
  (Vision foreground mask and a colour-based cut-out; of their outlines the one that looks
  most like a cartridge wins: symmetric about its axis, solid, with sharp edges, so a shadow
  on one side, wood grain or a tarnished half isn't measured) and compares its silhouette
  (length/width ratio and width profile) with every calibre's outline. Only the side profile
  counts; no text is read from the photo. Then compare the candidates 1:1 by laying the
  cartridge on the screen. Works best with the
  cartridge on its side on a light, plain background, photographed from above. When
  several cartridges compete in the photo, the app outlines them and you tap the one to
  identify; a cartridge off in a corner is simply ignored. The measured cartridge gets a
  green frame that turns with it and shows exactly the silhouette that was measured, and the preview is cropped to the
  detected cartridges. Empty cases work too: the app
  tells a case mouth from a bullet tip by itself (or you pick «Cartridge» / «Empty case»),
  compares cases with case outlines, and uses the rim (rimmed or rimless) and the neck
  (bottleneck or straight) to rule out calibres. Matches that are far off are not listed.
- **Sharing**: share a photo from Photos, Files, Messages or any other app to
  «Kaliberfinder» in the share sheet; the app opens on the matches for it. The share extension only hands the photo over through
  the App Group `group.ch.giotta.kaliberfinder`; the analysis runs in the app.
- **Calibres** (Alle Kaliber): catalogue of about 100 calibres (rimfire, handgun, rifle
  incl. GP 90, GP 11 and GP 1890, black powder, shotgun, air), with search across names,
  aliases and headstamp spellings. Each calibre shows its dimensions: overall length, case
  length, rim, base, shoulder, neck and bullet diameter, and the primer (Boxer size of
  commercial brass).
- **1:1** (Originalgrösse): one or several calibres side by side at real size, standing on
  a common base line next to a millimetre ruler, with the case head seen from below (rim
  and primer). The ruler stays on screen while the cartridges scroll sideways; a 1:1 badge
  explains why the view can't be zoomed.
- **Without a photo** (Ohne Foto): enter measured dimensions (optionally the case shape:
  straight or bottleneck), or pick calibres by name, and compare them 1:1; without a
  selection the compare button shows every calibre that fits within 1 mm.
- **Calibration** (Bildschirm kalibrieren): the app knows the display density of every
  iPhone since the XS and takes Display Zoom into account. For unknown models, or to
  fine-tune, calibrate once with a bank card.
- **LiDAR** (Pro iPhones from the 12 Pro): «Photograph cartridge» opens the app's own
  camera, which guides you to hold the phone flat 20–30 cm above the cartridge and takes
  the photo with the LiDAR distance. From that distance and the camera's focal length the
  app measures the cartridge's length and diameter and ranks calibres by size as well as
  shape. The depth is used in memory only and never stored. Other iPhones
  and photos from the library work as before.
- **Units** (Einheiten): metric (mm, the default) or US imperial (inches, three decimals,
  ruler in 1/16 in). Data and matching stay in millimetres; only display and input change.

The cartridge data comes from the shared [calibre-data](https://github.com/ravench/calibre-data)
repository (a git submodule at `calibre-data/`, also used by Schiesstagebuch), one TOML file per
calibre. Dimensions are rounded reference values (CIP/SAAMI), not reloading data.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Kaliberfinder.xcodeproj
```

If you build your own copy, replace `DEVELOPMENT_TEAM` and the bundle id in `project.yml`
with your own, or pick your team under Signing & Capabilities.

Generated files (commit them after a change; the tools need Python 3.11 or newer):

```sh
python3 tools/generate_data.py   # Resources/Cartridges.json from the calibre-data submodule
python3 tools/localize.py        # Resources/Localizable.xcstrings, fails on missing translations
python3 tools/app_icon.py        # app icon, light/dark/tinted (node + Playwright; --ruler, --navy)
```

## Tests

Unit tests live in `KaliberfinderTests` and run in CI on every push, together with the
tests of the Python tools in `tools/test_*.py`, SwiftLint 0.59.1 in strict mode and a check
that the generated files are up to date.
Run them locally with ⌘U in Xcode, or:

```sh
xcodebuild test -project Kaliberfinder.xcodeproj -scheme Kaliberfinder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
python3 -m unittest discover -s tools -p 'test_*.py'
swiftlint lint --strict
```

Every change should come with tests.

## TestFlight

Every push to `main` whose **Build** workflow passes is archived and uploaded to TestFlight
by `.github/workflows/testflight.yml` (it can also be started by hand under Actions).
Merges less than a minute apart give one upload, from the newest commit on `main`.
The build number is the workflow run number plus 1000 (`tools/testflight.py`). The version is the
newest release tag the commit descends from: to release, write the notes into `RELEASE_NOTES.md`,
tag the commit on `main` (`git tag v0.2.0 && git push origin v0.2.0`), and the tag's push uploads
that build under that version with those notes instead of the Claude-written summary.

The upload needs three repository secrets from an App Store Connect API key with the
Admin role (Users and Access, Integrations, Team Keys): `ASC_KEY_ID` (Key ID),
`ASC_ISSUER_ID` (Issuer ID) and `ASC_KEY_P8` (the whole content of the downloaded
`AuthKey_….p8`). Without them the workflow skips the upload. Forks don't get the secrets.

## App Store screenshots

`KaliberfinderUITests/AppStoreScreensTests.swift` takes the six store screens (matches for a 9 mm
photo, the matches at 1:1, start, the GP 11's page and drawing, entering dimensions) in one language
and writes them as PNG files. It runs by hand, not in CI; once per device and language:

```sh
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100
TEST_RUNNER_SCREENS_LANG=en TEST_RUNNER_SCREENS_DIR="$PWD/screens/iphone-en" \
  xcodebuild test -project Kaliberfinder.xcodeproj -scheme KaliberfinderScreens \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:KaliberfinderUITests/AppStoreScreensTests
```

App Store Connect needs the 6.9" iPhone (1320 × 2868) and the 13" iPad (2064 × 2752).

## CI on your own Mac

The Mac jobs (Build, TestFlight, Evaluate matching) run on GitHub's macOS runner, or on a
self-hosted Mac while the repo is private and the repository variable `MAC_RUNNER` names it.
Register the runner only once the repo is private, and remove it (`./svc.sh uninstall`, then
`./config.sh remove`) before the repo ever goes public again: on a public repo, a pull request
could change its own workflow to run code on that Mac. The Linux jobs stay on GitHub. While the
Mac is off or asleep, or its runner user is logged out, the Mac jobs wait (up to 24 hours)
instead of falling back to GitHub's runner.

1. On the Mac, make a standard macOS user just for the runner: CI erases and restarts its
   iPhone simulator on every run, and a user of its own keeps your simulators, keys and keychain
   out of reach.
2. As an admin, install Xcode 26 with the iOS simulator and open it once. Then run
   `brew install xcodegen git-lfs gh`, `sudo gem install xcpretty`, `sudo DevToolsSecurity -enable`
   and `sudo dseditgroup -o edit -a <runner user> -t user _developer`, so the runner user can run
   tests without a password prompt. As the runner user, run `git lfs install` and add
   `eval "$(/opt/homebrew/bin/brew shellenv)"` to `~/.zprofile`, then open a new Terminal window.
3. Under Settings › Actions › Runners › New self-hosted runner (macOS, ARM64), run the commands it
   shows in that window, then `./svc.sh install && ./svc.sh start`. The runner works while its
   user is logged in: after a restart, log it in once and switch back to your own user. Keep it
   to one runner, which takes the Mac jobs one after another: two would erase each other's
   simulators.
4. Under Settings › Secrets and variables › Actions › Variables, set `MAC_RUNNER` to
   `self-hosted`. Delete the variable to send the Mac jobs back to GitHub's runner.

## Licence

© 2026 Simon Giotta. All rights reserved: Kaliberfinder is closed source, see
[LICENSE.md](LICENSE.md). The calibre catalogue carries its own licence, listed there.
