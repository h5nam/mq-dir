# Changelog

All notable changes to mq-dir are documented here.

The format is based on Keep a Changelog, and this project uses semantic
versioning once public releases begin.

## [Unreleased]

### Added

- M0 SwiftUI app shell with placeholder sidebar and main window content.
- App metadata, default non-sandboxed entitlements, future sandboxed
  entitlements, app icon asset catalog scaffold, and English localization
  scaffold.
- XcodeGen project source, SwiftPM headless core package, bootstrap script, and
  smoke test.
- MIT license, README, contribution guide, security policy, and code of conduct.
- GitHub Actions CI workflow for SwiftPM tests and generated Xcode app builds.
- Signed/notarized release workflow scaffold for Developer ID distribution.
- Ad-hoc signed nightly workflow scaffold for contributor testing.
- Maintainer-tap Homebrew cask scaffold.
- M1 single-pane folder picker, read-only file list, sorting, open selected,
  parent navigation, hidden-file toggle, and Reveal in Finder wiring.
- M2-lite pane shell ahead of schedule: 1/2/4-pane layout switching, focused
  pane routing, and independent folder state per pane.
- Core file-entry model, directory enumeration service, and XCTest coverage for
  hidden-file filtering and sort behavior.

### Changed

- Use `project.yml` as the source of truth for `mq-dir.xcodeproj` generation
  instead of checking in a generated Xcode project.

### Known gaps

- Repository URLs, maintainer security email, and release signing secrets are
  placeholders until the public GitHub repository and Developer ID account are
  finalized.
- There is no real filesystem browsing yet. M1 owns folder selection, listing,
  sorting, and persistence.

## [0.1.0] - 2026-05-01

### Added

- Initial M0 skeleton.
