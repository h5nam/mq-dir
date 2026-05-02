# Changelog

All notable changes to mq-dir are documented here.

The format is based on Keep a Changelog, and this project uses semantic
versioning once public releases begin.

## [Unreleased]

(none)

## [0.1.0-alpha.2] - 2026-05-02

### Added

- Window and per-pane state persistence across launches and force-quit.
  Layout (1/2/4-pane), focused pane, sort key/order, hidden-files toggle,
  column widths, and selection are all restored on relaunch. Per-pane folder
  is stored as a security-scoped bookmark for sandbox-readiness.
- VS Code-style sidebar tree (Favorites, Locations, Tags) with one-click
  navigation routed to the focused pane.
- Theme tokens centralised in `Theme.swift`, file-icon style scaffolding,
  and drag-and-drop helper.
- App icon assets and Brandkit source files.
- Public landing page deployed at <https://mqdir.com>.

### Fixed

- `FileEntry.id` is now URL-typed instead of a path string, avoiding
  duplicate-row collisions on case-insensitive APFS volumes.

### Known issues (tracked for next alpha)

- Drag captures selection at view-build time; rapid click + drag from a
  different row may ship a stale selection.
- `acceptDrop` surfaces per-item move failures only via stderr; no per-pane
  error UI yet.
- Permission-denied directories (e.g., `~/Library`) clear entries instead of
  preserving the previous folder.
- Cross-pane reload on `.mqdirFileSystemChanged` is a sledgehammer; reloads
  all panes regardless of which folder changed.

## [0.1.0-alpha] - 2026-05-01

### Added

- M0 SwiftUI app shell with placeholder sidebar and main window content.
- App metadata, default non-sandboxed entitlements, future sandboxed
  entitlements, app icon asset catalog scaffold, and English localization
  scaffold.
- XcodeGen project source, SwiftPM headless core package, bootstrap script,
  and smoke test.
- MIT license, README, contribution guide, security policy, and code of
  conduct.
- GitHub Actions CI workflow for SwiftPM tests and generated Xcode app
  builds.
- Signed/notarized release workflow scaffold for Developer ID distribution.
- Ad-hoc signed nightly workflow scaffold for contributor testing.
- Maintainer-tap Homebrew cask scaffold.
- M1 single-pane folder picker, read-only file list, sorting, open
  selected, parent navigation, hidden-file toggle, and Reveal in Finder
  wiring.
- M2-lite pane shell ahead of schedule: 1/2/4-pane layout switching,
  focused pane routing, and independent folder state per pane.
- Core file-entry model, directory enumeration service, and XCTest coverage
  for hidden-file filtering and sort behavior.

### Changed

- Use `project.yml` as the source of truth for `mq-dir.xcodeproj`
  generation instead of checking in a generated Xcode project.
