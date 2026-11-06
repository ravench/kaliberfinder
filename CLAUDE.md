# Notes for Claude

- Follow [CONTRIBUTING.md](CONTRIBUTING.md): small pull requests, one per group of related
  changes, each with unit tests that CI runs.
- **Pull requests that change the GUI must show screenshots.** The *PR screens* steps at
  the end of the Build job (`.github/workflows/build.yml`) take them for you on its macOS runner:
  for pull requests that touch the GUI (`tools/ci_changes.py`) they run the screen
  tour in `KaliberfinderUITests/PRScreensTests.swift` on the pull request and on its base
  branch and comment with the screens that look different, before and after. After pushing,
  check that the comment shows your change. If it says «No visible change» but your change is
  visible, the tour does not reach that screen: add a stop for it in the same pull request.
