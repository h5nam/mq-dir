# Contributing to mq-dir

Thanks for taking a look. mq-dir is a personal-use-first / open-source-second project. Contributions are welcome but the maintainer reserves the right to keep the scope tight — see the roadmap in [`README.md`](README.md) and the consensus plan in `/.omc/plans/ralplan-mq-dir-v1.md`.

## DCO (Developer Certificate of Origin)

We use **DCO**, not a CLA. Every commit must include a `Signed-off-by:` line:

```bash
git commit -s -m "feat(panes): wire up Cmd+T to open tab in focused pane"
```

That single flag adds the line for you using your `user.name` and `user.email` from git config. By signing off, you're certifying the contents of [the DCO](https://developercertificate.org/) — basically: "I wrote this, or I have the right to submit it under the project's license."

PRs without `Signed-off-by:` on every commit will be asked to amend.

## Branching & PRs

- Branch off `main` with a descriptive name (`feat/multi-pane-tabs`, `fix/scroll-restore`, `docs/contributing`).
- One logical change per PR. Multi-feature PRs get split.
- Title format: `area: short description` (e.g. `panes: persist focus across relaunch`).
- Body: explain the **why**, not the what. Diff already shows the what.

## Building locally

See [`README.md`](README.md). Quickest path:

```bash
Scripts/bootstrap.sh
open mq-dir.xcodeproj
```

Tests only:

```bash
swift test
```

The generated Xcode project builds the app and runs isolated AppKit/Markdown service tests in CI on `macos-14`. These tests do not launch the production app or read your saved workspace.

### First launch with an unsigned local build

Local builds are not signed with a Developer ID certificate (only the maintainer signs official releases). On first launch macOS will refuse to open the app:

```bash
xattr -d com.apple.quarantine /Applications/mq-dir.app
```

Then double-click. Future launches work without intervention.

## Code style

- `.swift-format` configures 4-space indentation and a 120-column line limit. Match the existing style:
  - 4-space indent.
  - `final class` by default.
  - SwiftUI `View` structs end in `View` (`MainWindowView`, `PaneView`).
  - One type per file unless types are tightly coupled (e.g. a small associated enum).
- Run `swift-format lint --recursive Sources Tests` before opening a PR (CI runs it as a soft check, not a build gate).

## Tests

- Unit tests live in `Tests/mqdirCoreTests/` and run via `swift test`.
- App service tests live in `Tests/mqdirAppTests/` and run via `xcodebuild -project mq-dir.xcodeproj -scheme mq-dir -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO test` after `Scripts/generate-project.sh`. Full UI and persistence end-to-end coverage remains planned.
- New persistence schema versions require a `testMigration_vN_to_vN+1_preservesAllFields` test before merge.

## PR review

- Maintainer review. Expect ~3 day turnaround during weekdays.
- Net-new external dependencies need a separate "why this dep" PR description section.
- Touching persistence keys, FSEvents, or focus-management code triggers a §3-of-the-plan re-read by the reviewer.

## Release process

Maintainer-only: run `Scripts/release.sh --dry-run <version>` on clean `main`, then `Scripts/release.sh <version>`. CI checks the exact tag, tests the core and app services, validates bundle metadata, and publishes new assets without overwriting an existing release. Follow the [release guide](docs/releasing.md) for setup and retries. Version/build settings and `Config/Package.resolved` changes must be reviewed together with the generated bundle validation.

## Reporting bugs

Open an issue with:

1. macOS version + chip (Apple Silicon vs Intel).
2. mq-dir version (Help → About).
3. Steps to reproduce.
4. What you expected vs what happened.
5. If a crash: `~/Library/Logs/DiagnosticReports/mq-dir-*.crash`.

## Reporting security issues

**Don't** open a public issue. See [`SECURITY.md`](SECURITY.md).

## Code of Conduct

This project follows the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md). Be kind. Disagreement is fine; condescension is not.
