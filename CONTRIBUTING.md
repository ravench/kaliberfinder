# Contributing

Thanks for helping with Kaliberfinder! Pull requests are welcome: bug fixes,
features, translations or better cartridge data.

## Licence in short

- The code is **source-available** under the
  [PolyForm Noncommercial License 1.0.0](LICENSE.md). You may read, build, change
  and use it for yourself, your club or any other noncommercial purpose, and share
  your changes under the same terms.
- **Commercial use is not allowed**, including selling the app or a copy of it in
  the App Store, or making money from it in other ways. Only the project owner may
  publish the app commercially.

## Contributor License Agreement

Before your first pull request can be merged, you need to agree to the
[Contributor License Agreement](CLA.md). You keep the copyright in your work, but
grant the project owner the right to use it in any way, including in a paid App
Store release.

To agree, tick the CLA checkbox in the pull request description.

## Guidelines

- Write UI text in German and add English, French and Italian to
  `tools/translations.py`, then run `python3 tools/localize.py`.
- Cartridge data comes from the shared [calibre-data](https://github.com/ravench/calibre-data)
  repository, a git submodule at `calibre-data/` (run `git submodule update --init` after
  cloning). Fix dimensions there, then bump the submodule here; headstamp spellings for the
  catalogue search go into `tools/headstamps.py`. Then run `python3 tools/generate_data.py` and commit the generated JSON.
- Every change comes with unit tests; CI runs them and SwiftLint on every push.
- Keep pull requests small and focused, and describe what you changed and how you tested it.
