# Contributing

Kaliberfinder is closed source ([LICENSE.md](LICENSE.md)). Only people Simon Giotta
invites work on it, under a written agreement with Simon Giotta. These notes are for them.

## Guidelines

- Write UI text in German and add English, French and Italian to
  `tools/translations.py`, then run `python3 tools/localize.py`.
- Cartridge data comes from the shared [calibre-data](https://github.com/ravench/calibre-data)
  repository, a git submodule at `calibre-data/` (run `git submodule update --init` after
  cloning). Fix dimensions there, then `python3 tools/bump_data.py` here: it moves the submodule
  and regenerates the catalogue JSON, the strings and, when the fields changed, the test fixture;
  commit the result. Headstamp spellings for the catalogue search are aliases in calibre-data.
- Every change comes with unit tests; CI runs them and SwiftLint on every push.
- Keep pull requests small and focused, and describe what you changed and how you tested it.
- A pull request that changes the GUI shows screenshots. CI comments with the screens that
  changed, before and after; if your screen is missing, add it to the tour in
  `KaliberfinderUITests/PRScreensTests.swift`.
