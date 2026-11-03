# Kaliberfinder

Small iOS app (SwiftUI, iOS 17+, iPhone) that shows cartridges at **real size**
on the screen, so you can lay a cartridge on the display and see which calibre
it is, after taking a photo of it. In German, English, French and Italian.

## Features

- **Patrone erkennen**: take a photo of a cartridge (or pick one) and get a ranked list of
  likely calibres. The app cuts the cartridge out of the photo (Vision foreground mask; when
  Vision takes the table, a box or the paper as the subject, a colour-based cut-out instead),
  compares its silhouette (length/width ratio and width profile) with every calibre's
  outline. A second, optional photo of the case head is read for the headstamp
  ("WIN 308", "9MM LUGER"); text is only read from that base photo (or from a first photo
  that turns out to show a round end), never from the side photo. Then compare
  the candidates 1:1 by laying the cartridge on the screen. Works best with the
  cartridge on its side on a light, plain background, photographed from above.
  When several cartridges compete in the photo, the app outlines them and you tap the one
  to identify; a cartridge off in a corner is simply ignored.
  Empty cases work too: the app tells a case mouth from a bullet tip by itself (or you pick
  "Patrone" / "Leere Hülse"), compares cases with case outlines, and uses the rim (rimmed or
  rimless) and the neck (bottleneck or straight) to rule out calibres. Matches that are far
  off are not listed.
- **Kaliber**: catalogue of about 100 calibres (rimfire, handgun, rifle incl. GP 90 / GP 11,
  black powder, shotgun, air), with search across names, aliases and headstamp spellings.
  Each calibre shows its dimensions: overall length, case length, rim, base, shoulder,
  neck and bullet diameter, and the primer (Boxer size of commercial brass).
- **1:1**: one or several calibres side by side at real size, standing on a common base
  line next to a millimetre ruler, with the case head seen from below (rim and primer).
  The ruler stays on screen while the cartridges scroll sideways; a 1:1 badge explains why
  the view can't be zoomed.
- **Ohne Foto**: enter measured dimensions (optionally the case shape: straight or bottleneck),
  or pick calibres by name, and compare them 1:1; without a selection the compare button
  shows every calibre that fits within 1 mm.
- **Calibration**: the app knows the display density of every iPhone since the XS and
  takes Display Zoom into account. For unknown models, or to fine-tune, calibrate once
  with a bank card.
- **LiDAR** (Pro iPhones from the 12 Pro): "Patrone fotografieren" opens the app's own camera,
  which guides you to hold the phone flat 20–30 cm above the cartridge and takes the photo
  with the LiDAR distance. From that distance and the camera's focal length the app measures
  the cartridge's length and diameter and ranks calibres by size as well as shape and
  headstamp. The depth is used in memory only and never stored. Other iPhones and photos
  from the library work as before.
- **Einheiten**: metric (mm, the default) or US imperial (inches, three decimals, ruler in
  1/16 in). Data and matching stay in millimetres; only display and input change.

The cartridge data is a copy of the catalogue in
[Schiesstagebuch](https://github.com/ravench/schiesstagebuch). Dimensions are rounded
reference values (CIP/SAAMI), not reloading data.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Kaliberfinder.xcodeproj
```

If you build your own copy, replace `DEVELOPMENT_TEAM` and the bundle id in `project.yml`
with your own, or pick your team under Signing & Capabilities.

Generated files (commit them after a change):

```sh
python3 tools/generate_data.py   # Resources/Cartridges.json from tools/cartridges.py
python3 tools/localize.py        # Resources/Localizable.xcstrings, fails on missing translations
python3 tools/app_icon.py        # app icon, light/dark/tinted (node + Playwright; --no-ruler, --navy)
```

## Tests

Unit tests live in `KaliberfinderTests` and run in CI on every push, together with
SwiftLint 0.59.1 in strict mode and a check that the generated files are up to date.
Run them locally with ⌘U in Xcode, or:

```sh
xcodebuild test -project Kaliberfinder.xcodeproj -scheme Kaliberfinder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
swiftlint lint --strict
```

Every change should come with tests.

## TestFlight

Every push to `main` whose Build workflow passes is archived and uploaded to TestFlight
by `.github/workflows/testflight.yml` (it can also be started by hand under Actions).
The build number is the workflow run number plus 1000 (`tools/testflight.py`); bump
`MARKETING_VERSION` in `project.yml` for a new version.

The upload needs three repository secrets from an App Store Connect API key with the
Admin role (Users and Access, Integrations, Team Keys): `ASC_KEY_ID` (Key ID),
`ASC_ISSUER_ID` (Issuer ID) and `ASC_KEY_P8` (the whole content of the downloaded
`AuthKey_….p8`). Without them the workflow skips the upload. Forks don't get the secrets.

## License

© 2026 Simon Giotta. Source-available under the
[PolyForm Noncommercial License 1.0.0](LICENSE.md): anyone may read, build, modify
and use the app for noncommercial purposes, and pull requests are welcome. Commercial
use, including selling the app or a copy of it in the App Store, is reserved to the
copyright holder.

Contributions require agreeing to the [Contributor License Agreement](CLA.md);
see [CONTRIBUTING.md](CONTRIBUTING.md).
