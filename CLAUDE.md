# Notes for Claude

- Follow [CONTRIBUTING.md](CONTRIBUTING.md): small pull requests, one per group of related
  changes, each with unit tests that CI runs.
- **Pull requests that change the GUI must show screenshots.** The *PR screens* workflow
  (`.github/workflows/pr-screens.yml`) takes them for you on a macOS runner: it runs the screen
  tour in `KaliberfinderUITests/PRScreensTests.swift` on the pull request and on its base
  branch and comments with the screens that look different, before and after. After pushing,
  check that the comment shows your change. If it says «No visible change» but your change is
  visible, the tour does not reach that screen: add a stop for it in the same pull request.
