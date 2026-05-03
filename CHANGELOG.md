# Changelog

All notable changes to mq-dir are documented here.

The format is based on Keep a Changelog, and this project uses semantic
versioning once public releases begin.

## [Unreleased]

(none)

## [0.1.0-alpha.6] - 2026-05-03

### Fixed

- Icon Dock framing, again: alpha.5's graduated luma fade left a
  translucent grey rim around the squircle that read as a frame against
  the Dock backdrop. Replaced the fade with a sharp luma cutoff at value
  30 — pixels darker than 30 become fully transparent, brighter pixels
  stay fully opaque. Result is a clean squircle silhouette with no grey
  halo while interior glass shading and the four-cell layout stay intact.

## [0.1.0-alpha.5] - 2026-05-02

### Changed

- Repository reorganised into a standard public OSS layout: app sources
  under `Sources/mq-dir/`, headless library under `Sources/mqdirCore/`
  (Package.swift target path updated), entitlements consolidated under
  `Resources/Entitlements/`, brand toolkit moved to `Scripts/brandkit/`,
  and README/social assets to `.github/assets/`. project.yml and
  Package.swift catch up to the new paths.
- README hero image link points to `.github/assets/readme_hero.png` so
  the rendered README on github.com no longer shows a broken image.

### Fixed

- Icon Dock framing: alpha.4 still showed a hard dark outline because the
  AI-baked glass squircle had a near-black rim that the squircle alpha
  mask alone could not dissolve. The refine pass now combines the squircle
  mask with a luminance-driven alpha fade (luma 12 fully transparent, 38+
  fully opaque) so the rim dissolves smoothly while the interior glass
  shading and 4-pane cells stay intact.

## [0.1.0-alpha.4] - 2026-05-02

### Fixed

- App icon no longer renders with a hard black square frame in the Dock.
  The AI-generated `app_icon_master.png` had a small glassmorphism squircle
  floating on a solid black 1024x1024 background, and macOS Dock paints the
  PNG verbatim. Added `Brandkit/refine_app_icon.py` (Pillow-only) which
  detects the design's bounding box, fits it tightly into the canvas, and
  applies an Apple-style rounded-rectangle alpha mask so the corners go
  cleanly transparent. The 10 sized variants under
  `Resources/Assets.xcassets/AppIcon.appiconset/` are regenerated from the
  refined master via the existing `Brandkit/postprocess.py` pipeline.

## [0.1.0-alpha.3] - 2026-05-02

### Fixed

- App icon and localized strings now actually ship inside the `.app`
  bundle. XcodeGen treats the top-level `resources:` key differently than
  `sources:` and silently skipped `Resources/` in alpha.1 and alpha.2, so
  every prior dmg shipped without an `AppIcon.icns` or `Assets.car` —
  hence the generic Dock icon. Moved `Resources/` under `sources:` so
  XcodeGen recurses and registers `Assets.xcassets` and `en.lproj` into
  the proper build phases.

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
