# Notes for Claude

- Follow [CONTRIBUTING.md](CONTRIBUTING.md): small pull requests, one per group of related
  changes, each with unit tests that CI runs.
- **Pull requests that change the GUI must show screenshots.** The Build workflow
  (`.github/workflows/build.yml`) takes them for you on two macOS runners at once: for pull
  requests that change views, strings or images (`tools/ci_changes.py`), or carry the «screens»
  label, they run the screen tour in `KaliberfinderUITests/PRScreensTests.swift` on the pull
  request (build job) and on its base branch (base-screens job, cached per base), and its screens job
  comments with the screens that look different, before and
  after. After pushing, check that the comment shows your change. If it says «No visible change»
  but your change is visible, the tour does not reach that screen: add a stop for it in the same
  pull request. If your change is visible but touches none of those files (logic, data), add the
  «screens» label before you push, or use «Re-run all jobs» on the Build after adding it.
- While the repo is private without its own Mac (`MAC_RUNNER` unset), CI takes no screens, since
  GitHub bills every Mac minute; the Build says so in a notice. Then don't wait for the comment:
  say in the pull request that it has no screenshots, or attach ones taken on the Mac.
