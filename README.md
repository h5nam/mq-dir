# mq-dir

> Quad-pane macOS file manager. Q-Dir heritage, Finder-class polish, opinionated state persistence.

![status: pre-alpha (M1 in progress)](https://img.shields.io/badge/status-pre--alpha%20M1-orange)

> _Screenshots coming after M1 ships._

## Why mq-dir?

- **Finder loses your view-mode-per-folder.** mq-dir remembers — list vs. icon, sort, scroll position, column widths, all per folder, all surviving force-quit.
- **Multi-pane is a lifestyle.** 1, 2, 3, or 4 panes in a 2×2 grid (Q-Dir heritage), each with its own tabs and history.
- **Embedded media preview without Spotlight gymnastics.** Spacebar QuickLook in M1; inline image / video / audio / PDF preview in M3.
- **Persistence that just works.** Sort, scroll, column widths, expanded sidebar nodes — all restored on relaunch. Survives `kill -9`.

## Status: M1 in progress

This is **pre-alpha**. M0 is complete. M1 has started with a folder picker and read-only file list. A lightweight 1/2/4-pane shell is already present so the app opens with the expected Q-Dir shape, but persistence, QuickLook, NSTableView column autosave, and the full M1 acceptance criteria are still in progress.

The full roadmap and architecture decisions live in [`/.omc/plans/ralplan-mq-dir-v1.md`](.omc/plans/ralplan-mq-dir-v1.md).

## Build from source

**Quickstart** (requires macOS 14+ and [Homebrew](https://brew.sh)):

```bash
Scripts/bootstrap.sh
open mq-dir.xcodeproj
```

`bootstrap.sh` installs XcodeGen + the `xcodes` CLI, then generates the Xcode project from `project.yml`.

**Manual:**

```bash
brew install xcodegen
xcodegen generate
open mq-dir.xcodeproj
```

**Tests-only** (no Xcode required, just the Swift toolchain):

```bash
swift test
```

> **Note on the Xcode project.** This repo uses **XcodeGen** (`project.yml` is the source of truth) — the `mq-dir.xcodeproj` directory is generated, not checked in. The original plan called for a checked-in Xcode project; that decision was reversed in the M0 implementation pass because hand-written `project.pbxproj` is unverifiable in environments without the full Xcode IDE. Tracked in `CHANGELOG.md`.

## Privacy

**No telemetry. No crash reporting. No analytics. Ever, in v1.**

mq-dir is local-only. It reads your filesystem to show it back to you and writes its own state to `~/Library/Application Support/com.mqdir.app/`. No network calls. No phone-home. No "anonymous usage stats."

If a v1.x release ever proposes opt-in crash reporting, it will land behind a config toggle defaulting to off, with the source clearly visible. Until then, the network code path simply does not exist.

## License

MIT — see [`LICENSE`](LICENSE).

## Contributing

PRs welcome. Contributions are accepted via [DCO](https://developercertificate.org/) (Developer Certificate of Origin) — every commit needs a `Signed-off-by:` line. **No CLA.** See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full workflow.

## Roadmap

- **M0 — Skeleton.** App shell, OSS docs, CI, signing scaffold.
- **M1 — Single-pane MVP** ← _in progress_. Folder browsing, persistent per-folder state, spacebar QuickLook. The load-bearing milestone.
- **M2 — Multi-pane.** 1/2/3/4-pane layouts, per-pane tabs, session restore.
- **M3 — Embedded preview.** Inline image (NSImageView with pinch-zoom), video / audio / PDF / text via QLPreviewView.
- **M4 — Sidebar tree.** VS Code-style folder tree, lazy-loaded, navigates the focused pane.
- **M5 — Release infra.** Signed + notarized builds via GitHub Actions, maintainer Homebrew tap, ad-hoc nightly builds.
- **M6 — UX polish.** Keyboard shortcuts, in-pane search, drag/drop file moves, sidebar favorites, settings UI.

Out of scope for v1: cloud sync, archive previews, file editing, plugins, iPadOS/iOS port, localization beyond English. Full list in plan §2.
