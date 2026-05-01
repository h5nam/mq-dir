# RALPLAN — mq-dir v1

A macOS file manager inspired by Q-Dir. Quad-pane layout, VS Code-style sidebar tree, embedded media preview, persistent per-folder state. Personal use first, then open-source.

Mode: **SHORT** (default; not `--deliberate`). Greenfield, single developer, well-bounded scope.

---

## 1. RALPLAN-DR Summary

### Principles

- **Native macOS feel beats UI portability.** The whole reason this app exists is that Finder feels broken on macOS. A web-stack file manager that mimics Finder's frustrations is a non-starter.
- **Persistence is a v1 feature, not a v2 nice-to-have.** Per-folder view-mode memory is the headline pain point. If state isn't durable in M1, the product fails its own thesis.
- **Filesystem performance > UI fidelity.** Listing a 50k-file directory must stream, not block. The directory model is the load-bearing component.
- **Solo-dev velocity is a constraint, not a goal.** Pick the stack that lets one person ship M1 in weeks, not the one with the prettiest theoretical architecture.
- **Open-source-friendly from day one.** License + README + CI in M0, before any feature work. No retrofitting.

### Decision Drivers (top 3)

1. **Solo-dev velocity** — one developer, evenings/weekends budget. Stack must minimize boilerplate and maximize stdlib leverage.
2. **Native macOS feel and FS access** — no Electron/web-stack jank, full access to QuickLook, AVKit, NSFileCoordinator, FSEvents, security-scoped bookmarks.
3. **Future contributor pool** — open-source viability. Stack must be approachable enough that macOS-curious devs can contribute without arcane setup.

### Viable Options

#### (A) SwiftUI + AppKit native (Swift 5.10, Xcode 16, macOS 14+)

- **Dev velocity**: High. SwiftUI's `List`, `NavigationSplitView`, `Table` give VS Code-tree and list-view nearly free. Hot reload via `#Preview`.
- **Native feel**: Maximum. Direct access to QuickLook (`QLPreviewPanel`, `QLPreviewView`), AVKit (`AVPlayerView`), `NSImageView`, `NSWorkspace`, `FileManager`, FSEvents.
- **Media preview ease**: Best in class. `QLPreviewView` covers images/video/audio/PDF/text/code in ~20 lines. AVKit handles richer playback. NSImage handles HEIC/RAW.
- **Persistence ease**: Trivial. SwiftData (macOS 14+) or `Codable` + JSON in `Application Support` or `UserDefaults` for small state.
- **Bundle size**: ~5-15 MB. Smallest of the three.
- **Contributor pool**: Smaller than web — but the *intersection* of "macOS users who want a Finder replacement" and "people willing to write Swift" is non-trivial. Comparable open-source apps (Iina, Rectangle, NetNewsWire) prove it works.
- **Ecosystem risk**: Apple-pinned. macOS deprecations happen. Mitigated by targeting macOS 14+ and using stable AppKit APIs where SwiftUI is still rough (e.g. multi-pane focus).

#### (B) Tauri 2.0 (Rust core + WebView UI)

- **Dev velocity**: Medium. Two languages (Rust + TS/JS). Cross-language boundary for every FS call adds friction.
- **Native feel**: Medium. WebView is WKWebView on macOS, decent but you fight it for native scroll/keyboard semantics. Multi-pane focus, drag/drop into the OS, and reveal-in-Finder require IPC dances.
- **Media preview ease**: Web-stack media preview (`<img>`, `<video>`, `<audio>`) covers common cases but loses HEIC, ProRes, MKV, and many RAW formats that `NSImage`/AVKit handle natively. Bridging QuickLook through WKWebView is awkward.
- **Persistence ease**: Easy. SQLite via `tauri-plugin-sql` or JSON to `BaseDirectory::AppLocalData`.
- **Bundle size**: ~10-30 MB.
- **Contributor pool**: Larger (web devs), but contributors must learn two stacks. Many OSS contributors will only touch the frontend.
- **Ecosystem risk**: Tauri 2.0 still maturing. Rust+TS coordination overhead is real for solo dev.

#### (C) Electron (Node + Chromium)

- **Dev velocity**: Highest in pure UI terms. Worst once you hit native FS edges.
- **Native feel**: Worst of the three. Heavy, non-native scrolling, slow cold start. Exactly the "feels weird" experience the user is fleeing from in Finder.
- **Media preview ease**: Same web-stack limits as Tauri. No QuickLook bridge without native modules.
- **Persistence ease**: Easy.
- **Bundle size**: 80-150 MB. User explicitly cares about a "real" macOS app feel — Electron undermines that pitch.
- **Contributor pool**: Largest.
- **Ecosystem risk**: Low (mature) but reputational risk in macOS power-user communities is real. "Yet another Electron Finder" lands flat.

#### (D) Flutter desktop — explicitly rejected

Not mature enough on macOS for a file-manager-grade app (FS APIs, drag/drop, native menus, QuickLook all require platform channels). Eliminated without further analysis.

### Invalidation Rationale (rejected options)

- **Tauri (B)** rejected: bridging QuickLook + AVKit through WKWebView IPC is the worst-case integration path, exactly for the highest-value feature (M3 preview). The web layer adds friction without paying its own way for a single-platform app.
- **Electron (C)** rejected: contradicts Principle #1 (native feel). The user's pain is precisely the kind of UX jank Electron amplifies.
- **Flutter desktop (D)** rejected: insufficient macOS FS/UI maturity; would eat the velocity budget.

### Recommended Option: **(A) SwiftUI + AppKit**

Picked because it (1) is the only stack where QuickLook embeds in ~20 lines and AVKit/NSImage cover the user's media-preview wishlist natively, (2) gives the smallest binary and best cold-launch time, which directly addresses Principle #1, and (3) lets a solo dev hit M1 fastest because SwiftUI's `NavigationSplitView` + `Table` ship 80% of the UI for free.

---

## 2. Product Scope (MVP definition)

### M0 — Skeleton (build week 1)

**Capabilities:**
- Xcode project (`mq-dir.xcodeproj`) checked in, opens cleanly on a fresh clone.
- App shell launches to a window with placeholder sidebar + content.
- README, LICENSE (MIT), `.gitignore`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- GitHub Actions CI: `xcodebuild` + `swift test` on `macos-14` runner.
- Default v1 entitlements file (`mq-dir.entitlements`) ships with **no sandbox-related keys** (Developer ID, non-sandboxed). The `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.bookmarks.app-scope` entitlements are gated behind a `MQDIR_SANDBOXED` build flag (`mq-dir-sandboxed.entitlements`) reserved for a future App Store path; they are **no-ops in the Developer ID v1 build** and are intentionally omitted from the default file to avoid confusing contributors.
- Menu bar wired up in `AppDelegate.swift` covering File / Edit / View / Window / Help with placeholder items pointing at `#selector` stubs (real handlers land in M1+).
- Bundle identifier `com.mqdir.app` registered; `LSApplicationCategoryType = public.app-category.utilities`.
- App icon placeholder (`AppIcon.appiconset`) and `Localizable.strings` scaffolding (en.lproj only at v1).

**Non-goals:** No real FS browsing. No persistence. No tests beyond a hello-world unit test.

### M1 — Single-pane MVP (the load-bearing milestone)

**Capabilities:**
- Single pane shows a folder via `NSOpenPanel` + security-scoped bookmark.
- List view (Finder-style table: Name, Date Modified, Size, Kind).
- Sortable columns (click header), resizable columns.
- Persistent per-folder state: path, view mode, sort key, sort direction, scroll offset, column widths. Survives quit/relaunch.
- Open-in-default-app via `NSWorkspace.open(_:)`.
- Reveal-in-Finder via `NSWorkspace.activateFileViewerSelecting`.
- Spacebar → QuickLook panel (`QLPreviewPanel` shared instance) for selected file. **This is the cheap win that covers the user's media-preview ask in M1 with zero custom code.**
- Up/Down arrows navigate selection. Enter opens. Cmd-Up goes to parent.

**Non-goals:**
- No multi-pane.
- No inline embedded preview (spacebar QuickLook is the bridge).
- No sidebar tree.
- No tabs.
- No search, no drag/drop reordering.

### M2 — Multi-pane

**Capabilities:**
- 2-pane horizontal split (`HSplitView`).
- 3-pane and 4-pane (Q-Dir signature: 2x2 grid) via a `PaneLayout` enum.
- Each pane is an independent `PaneViewModel` with its own folder, view mode, sort, scroll, history.
- Per-pane tabs (`TabView`-equivalent on top of each pane).
- Session restore: window count, layout, per-pane state, all tabs.

**Non-goals:** No drag-between-panes file moves yet (deferred to M6 UX polish).

### M3 — Embedded preview

**Capabilities:**
- A pane can switch into "preview mode": split into list (left) + preview (right).
- **Image preview**: `NSImageView` (covers HEIC, PNG, JPEG, GIF, RAW via ImageIO). Magic Trackpad pinch-zoom and two-finger pan with momentum — this is the differentiator over QuickLook and worth the custom code.
- **Video, audio, PDF, text preview**: all routed through inline `QLPreviewView` (the embeddable view, not the floating `QLPreviewPanel`). Saves ~1.5 weeks vs hand-rolled `AVPlayerView` / `PDFView` / `NSTextView` and keeps codec/format coverage on par with macOS itself.
- **Fallback**: `QLPreviewView` again for any other UTI (.docx, .pages, .key, etc.).
- Per-format custom views (`AVPlayerView`, `PDFView`, `NSTextView`) are deferred to v1.x as opt-in upgrades only if `QLPreviewView` falls short for a specific user complaint.

**Non-goals:** No code syntax highlighting (QuickLook gives plain text rendering). No custom video scrubbing UI. No hand-rolled PDF outline / bookmarks panel.

### M4 — Sidebar tree

**Capabilities:**
- VS Code-style collapsible folder tree on the far left of the window.
- Lazy-loaded children (only enumerate when a node expands).
- Click a folder → navigates the *focused* pane (visible focus indicator).
- Drag a folder onto a pane → that pane navigates there.
- Persisted expanded state.

**Non-goals:** No favorites/pinning yet (deferred to M6). No multi-root sidebar (single user-chosen root).

### M5 — Release infrastructure

The original M5 bundled six workstreams (~1.5x the size of any other milestone), so it now splits into release infra (M5) and UX polish (M6). M5 ships first because it makes M1-M4 actually distributable.

**Capabilities:**
- Signed + notarized release build via GitHub Actions (`release.yml`).
- GitHub Releases with `.dmg` (preferred) and `.zip` (fallback). Pinned filename pattern `mq-dir-vX.Y.Z.dmg` for future Homebrew cask automation.
- Maintainer Homebrew tap (`brew tap <user>/mq-dir`) shipping the cask formula directly out of this repo's `Casks/mq-dir.rb`.
- Ad-hoc-signed nightly build workflow (`.github/workflows/nightly.yml`) so contributors without a Developer ID cert can install bleeding-edge builds via `xattr -d com.apple.quarantine` flow.
- Sparkle 2 public key embedded in the v1 binary even though auto-update itself ships in v1.1 — guarantees v1 → v1.1 upgrade path is unblocked.
- Privacy posture: **no telemetry, no crash reporting, no analytics** in v1. Privacy-positive default. Documented in README.

**Non-goals:** No auto-update yet (Sparkle 2 wiring deferred to v1.1, key only). No `homebrew/homebrew-cask` central submission yet (see M6 / post-v1 plan).

### M6 — UX polish

**Capabilities:**
- Keyboard shortcuts: Cmd-T new tab, Cmd-W close tab, Cmd-1/2/3/4 switch pane, Cmd-F search, Cmd-Shift-. toggle hidden files, etc.
- In-pane search (filter current folder by name; recursive search deferred to v1.1).
- Drag/drop file moves between panes (with copy-on-option-key like Finder).
- Sidebar favorites / pinned folders.
- Settings UI: default view mode, font size, hidden files default, pane layout default.
- After 30 days of v1.x stability **and** ≥100 GitHub stars, submit cask to `homebrew/homebrew-cask` central.

**Non-goals:** No iCloud Drive special handling beyond §3.5 ubiquity rendering. No keyboard shortcut customization UI (deferred unless user demand surfaces).

### Out of Scope for v1 (explicit non-goals)

- Cloud sync (Dropbox, Google Drive, S3, FTP, SMB mounts beyond what macOS already mounts).
- Archive previews (zip/tar contents).
- File editing (text or hex). Open-in-default-app is the answer.
- Multi-window saved layouts beyond "last layout."
- Git status overlays.
- Custom file-type icons beyond what `NSWorkspace.shared.icon(forFile:)` returns.
- Plugins / scripting.
- iPadOS/iOS port.
- Localization beyond English (community-driven post-v1).

---

## 3. Architecture Sketch

### Module / layer breakdown

```
mq-dir/
  Sources/
    App/                       # App entry, scene/window plumbing
      mqDirApp.swift           # @main, WindowGroup
      AppDelegate.swift        # NSApplicationDelegate for menu, dock
      RootWindowView.swift     # Top-level layout container
    Services/
      FileSystemService.swift  # Async dir enumeration, FSEvents
      BookmarkStore.swift      # Security-scoped bookmark mgmt
      ThumbnailCache.swift     # NSCache-backed thumbnail provider
    Models/
      FileEntry.swift          # struct: url, name, size, mtime, kind, isDir
      PaneState.swift          # struct: path, viewMode, sortKey, sortDir, scroll, columnWidths
      WindowState.swift        # struct: layout, panes, tabs
      PreviewKind.swift        # enum: image, video, audio, pdf, text, quickLook, none
    ViewModels/
      PaneViewModel.swift      # @Observable; owns directory listing + state
      WindowViewModel.swift    # owns layout + ordered panes
      SidebarTreeViewModel.swift
    Views/
      Pane/
        PaneView.swift         # routes to ListView / GridView / PreviewSplitView
        FileListView.swift     # SwiftUI Table
        FileGridView.swift
        PreviewSplitView.swift # M3
      Sidebar/
        SidebarTreeView.swift  # M4
      Preview/
        ImagePreviewView.swift
        VideoPreviewView.swift
        AudioPreviewView.swift
        PDFPreviewView.swift
        TextPreviewView.swift
        QuickLookPreviewView.swift   # NSViewRepresentable around QLPreviewView
      Layout/
        PaneLayoutView.swift   # 1/2/3/4-pane container
    Persistence/
      PersistenceStore.swift   # Codable JSON, atomic writes, migration
      SchemaVersion.swift
    Keyboard/
      KeyboardCoordinator.swift # NSEvent local monitor for shortcuts
  Tests/
    PersistenceStoreTests.swift
    FileSystemServiceTests.swift
    PaneViewModelTests.swift
  mq-dir.entitlements
  mq-dir.xcodeproj/
```

### List view implementation (resolves the macOS 14 column-width persistence gap)

SwiftUI `Table` exposes column-width persistence via `TableColumnCustomization`, which is **macOS 15+ only**. The plan targets macOS 14 (Sonoma). Two paths:

- **(a)** Bump deployment target to macOS 15 — shrinks user base for ~12 months and forfeits Sonoma installs.
- **(b)** Keep macOS 14 and implement `FileListView` as an `NSViewRepresentable` over `NSTableView` with `autosaveName = "mq-dir.fileList.<paneID>"` and `autosaveTableColumns = true`.

**Decision: (b).** Rationale: preserves the macOS 14 user base and matches the proven OSS pattern (Iina, NetNewsWire wrap NSTableView for the same reason). All other views (sidebar tree, grid, preview wrappers) remain pure SwiftUI. The `NSTableView` wrap is contained to one file (`FileListView.swift`) and is feature-isolated, so the rest of the codebase stays SwiftUI-native. AC #3 column-width persistence is delivered by `NSTableView`'s built-in autosave — not by hand-rolled persistence — making it both reliable and idiomatic.

### Persistence strategy (the user's headline pain point)

**Why this is the load-bearing decision:** the user's core complaint about Finder is that view mode flips and is not remembered per-folder. mq-dir must do the opposite, durably.

- **Storage**: JSON file at `~/Library/Application Support/com.mqdir.app/state.json`. Atomic writes via `Data.write(to:options:.atomic)`.
- **Why JSON over SwiftData**: SwiftData is overkill for ~kilobytes of preference data, and its migration story is fragile. JSON + `Codable` + an explicit `schemaVersion: Int` field is debuggable, diff-able, and 30 lines of code.
- **Key shape (per-folder state)**: keyed by a **stable folder identifier**, never by raw path. We never key on raw path; renames must not orphan state.
  - **Primary identity for any folder outside the app container**: a security-scoped bookmark blob (`URL.bookmarkData(options: .withSecurityScope)`). Bookmarks survive renames *and* moves across volumes, which is exactly what we need.
  - **In-volume fast-path fallback**: `URLResourceKey.documentIdentifierKey` (volume-stable APFS document ID) paired with `URLResourceKey.volumeIdentifierKey` to scope it. Note: `URLResourceKey.fileResourceIdentifierKey` is **session-scoped only** and was explicitly rejected — it cannot be persisted across launches.
  - **Inode-reuse / volume-swap defense**: every resolution validates persisted name + mtime hint against the resolved URL. On mismatch (e.g. APFS reused a document ID after delete-and-create-different-folder, or the volume UUID changed), we treat the entry as a new folder and start fresh — never silently apply stale state.
  - **Path is stored as a hint** for resolution and human debugging, but never the primary key.

```swift
struct PersistedState: Codable {
    var schemaVersion: Int  // start at 1
    var windows: [WindowState]
    var folderPrefs: [FolderID: FolderPrefs]  // FolderID encodes either bookmark digest OR (volumeID, documentID) tuple
}

struct FolderPrefs: Codable {
    var viewMode: ViewMode           // .list, .grid, .preview
    var sortKey: SortKey             // .name, .date, .size, .kind
    var sortAscending: Bool
    var scrollOffset: CGFloat
    var columnWidths: [String: CGFloat]
    var nameHint: String             // for inode-reuse validation
    var mtimeHint: Date              // for inode-reuse validation
    var lastSeen: Date
}
```

- **Eviction**: cap is **50,000 entries** (raised from the original 5,000 — a power user with deep nesting hits 5k easily). Eviction runs **only on app launch, before windows are restored**, and **never removes a `FolderPrefs` whose folder is currently open in any pane or tab**. If the JSON file ever exceeds 5 MB on disk, perform a one-way migration to a GRDB-backed SQLite store (a future schema-version bump that retires JSON for the prefs map; window state stays JSON).
- **Migration**: each schema bump adds a `migrate_v{N}_to_v{N+1}(_:)` function; on load, run all migrations in order. Tests cover each migration with a fixture file.
- **Save cadence**:
  - **Critical state** — sort key, sort direction, view mode, focused pane index, current folder per pane — saved **synchronously on change** (no debounce). This is the user's headline pain point and cannot be lost to a force-quit.
  - **Soft state** — scroll offset, column widths, expanded sidebar nodes — debounced 500ms after change.
  - On `applicationWillTerminate`, `windowWillClose`, **and** `applicationDidResignActive`, all pending soft-state writes are flushed synchronously. AC #8 (force-quit relaunch) depends on this contract.

### Concurrency model

- Directory enumeration is `async` on a background `Task` using `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options:)`.
- For huge directories (>10k entries), stream results in batches of 500 via `AsyncStream<[FileEntry]>` so the UI shows partial results within ~50ms.
- Live updates: a `FileSystemEventMonitor` built on `FSEventStreamCreate` (the high-level CoreServices API), **not** `DispatchSource.makeFileSystemObjectSource`. Per-pane FSEvents stream watches the pane's current folder non-recursively (`kFSEventStreamCreateFlagFileEvents`). The stream is invalidated and recreated on navigation. Events are coalesced with a 100ms debounce; if more than 50 events arrive in the debounce window, the pane re-enumerates the directory wholesale instead of patching incrementally. `DispatchSource` was rejected because it operates on file descriptors, scales poorly across many panes/tabs, and does not surface fine-grained event types — FSEvents is the macOS-native answer for this exact problem.
- Thumbnail generation off the main actor via a single serial queue + `NSCache` keyed by `(fileURL, mtime)`.
- `@MainActor`-isolate all `@Observable` view models; FS work returns to MainActor only at the boundary.

### Preview architecture

- **MVP (M1)**: spacebar opens shared `QLPreviewPanel` — zero custom code, covers everything macOS knows how to preview. This buys M1 the user's media-preview wishlist for free.
- **M3 in-pane preview**: `PreviewKind` is decided by UTI lookup (`UTType` from `URL.contentType`). Routes to a specific `*PreviewView` for the rich path; falls back to `QuickLookPreviewView` (a `NSViewRepresentable` wrapping `QLPreviewView`) for unknown types.
- **No global preview state**: each pane owns its own preview. Cleaner mental model, no cross-pane bleed.

### Multi-pane data flow

- `WindowViewModel` owns `panes: [PaneViewModel]` and `focusedPaneIndex: Int`.
- Each `PaneViewModel` is fully self-contained: its own current folder, listing, selection, scroll, history.
- Sidebar tree (M4) emits navigation intents to `WindowViewModel`, which forwards to `panes[focusedPaneIndex]`. Selection is *never* shared across panes.
- Drag/drop between panes (M6) is a `NSItemProvider` exchange at the view layer; no shared model state needed.

### Focus contract (single source of truth)

Multi-pane focus is the riskiest UI bet in the plan; SwiftUI's responder-chain behavior across many custom panes is historically flaky. To eliminate ambiguity:

- **Focus is owned by `WindowViewModel.focusedPaneIndex`**, an explicit `Int`. SwiftUI's `@FocusState` is **not** used for cross-pane focus.
- Each pane reads `focusedPaneIndex` from the model and styles itself with a **2px accent-colored border** when it is the focused pane. Unfocused panes show no border.
- Click anywhere inside a pane (`.onTapGesture` at the pane root) sets `focusedPaneIndex` to that pane's index.
- **Sidebar navigation always targets the focused pane** — never opens a new pane, never replaces a non-focused pane.
- **Cmd-T opens a new tab in the focused pane.** Cmd-W closes the focused pane's active tab.
- **Cmd-1 / Cmd-2 / Cmd-3 / Cmd-4 set `focusedPaneIndex` directly**, regardless of mouse position.
- **Tab cycles** focus forward (Shift-Tab cycles backward) via `KeyboardCoordinator`'s `NSEvent` local monitor — `focusedPaneIndex = (focusedPaneIndex + 1) % panes.count`.
- **Spacebar QuickLook scopes to the focused pane's selection** — never to whatever AppKit thinks the first responder is.

This contract is enforced by `WindowViewModel` and verified by `WindowViewModelTests.testFocusContract*`. It gives us deterministic focus regardless of SwiftUI's internal state.

### 3.5 TCC and ubiquity handling

macOS guards `~/Documents`, `~/Desktop`, `~/Downloads`, iCloud Drive, removable volumes, and network volumes via TCC (Transparency, Consent, Control). When TCC denies access, `FileManager.default.contentsOfDirectory(at:)` **silently returns an empty array** — no error, no exception. A naive implementation would render a denied folder as "empty," misleading the user. mq-dir must handle this explicitly.

**Required Info.plist usage descriptions** (added in M0, surfaced on first access):

- `NSDesktopFolderUsageDescription` — "mq-dir needs access to your Desktop folder to list and preview files."
- `NSDocumentsFolderUsageDescription` — "mq-dir needs access to your Documents folder to list and preview files."
- `NSDownloadsFolderUsageDescription` — "mq-dir needs access to your Downloads folder to list and preview files."
- `NSRemovableVolumesUsageDescription` — "mq-dir needs access to removable volumes (USB drives, SD cards) to browse them."
- `NSNetworkVolumesUsageDescription` — "mq-dir needs access to network volumes to browse SMB / AFP / NFS shares."

**TCC denial detection**: after `contentsOfDirectory` returns an empty array, probe `URLResourceKey.isDirectoryKey` on the parent. If the directory is in a TCC-protected zone and we got zero entries, render a dedicated **"Permission required"** affordance in place of an empty list with a "Grant Access" button that re-triggers the TCC prompt or deep-links to System Settings → Privacy & Security → Files and Folders. Distinguish this state from a genuinely empty directory.

**iCloud `.icloud` placeholders**: files not yet downloaded from iCloud Drive appear as zero-byte `*.icloud` stubs. mq-dir queries `URLUbiquitousItemDownloadingStatusKey` per entry:
- `.notDownloaded` → render row with cloud-with-arrow glyph and a "Download" affordance.
- `.downloaded` / `.current` → render normally.
- On user click of the download affordance, call `FileManager.default.startDownloadingUbiquitousItem(at:)` and reflect progress via `URLUbiquitousItemDownloadingStatusKey` polling at 500ms cadence until `.current`.

This avoids the "why is this 0 bytes" confusion that plagues other Finder alternatives.

---

## 4. Repo & Tooling

### Repo layout (top-level)

```
mq-dir/
  Sources/                  # all Swift source (see arch sketch)
  Tests/                    # XCTest targets
  Resources/                # asset catalogs, icons
  Scripts/
    bootstrap.sh            # one-shot dev setup
    build-release.sh        # signed build for distribution
    notarize.sh
  .github/
    workflows/
      ci.yml                # build + test on every PR
      release.yml           # tag-triggered notarized build
  mq-dir.xcodeproj/         # checked in
  mq-dir.entitlements
  README.md
  LICENSE                   # MIT
  CONTRIBUTING.md
  CODE_OF_CONDUCT.md
  CHANGELOG.md
  .gitignore
  .swift-version
```

### License: **MIT**

- MIT chosen over Apache-2.0 and GPL-3.0 because:
  - **MIT** is the dominant license in the macOS OSS app ecosystem (Iina, Rectangle, AltTab, Stats are MIT or BSD-2). Lowest contributor friction.
  - **Apache-2.0** adds patent-grant boilerplate that's overkill for a single-platform user-facing app and adds a NOTICE-file maintenance burden.
  - **GPL-3.0** is hostile to App Store distribution (which is an option to keep open) and discourages contributions from devs who also work on commercial macOS apps. The user explicitly said "open-source" not "copyleft."

### Build tooling: **Xcode project (checked in), no XcodeGen, no Tuist**

- For a single-target macOS app, an Xcode project is ~50 lines of `project.pbxproj` churn per file added — manageable.
- XcodeGen/Tuist add a non-trivial setup step for first-time contributors. Justified at 5+ targets, not at 1.
- SwiftPM is used for dependency declarations only (we expect zero or one dependency at v1 — possibly none).
- `.swift-version` pins Swift 5.10. Deployment target: macOS 14 (Sonoma) — gives us `@Observable`, `NavigationSplitView`, modern SwiftUI `Table`.

### CI: GitHub Actions

`.github/workflows/ci.yml`:
- Trigger: push to `main`, all PRs.
- Runner: pinned with the comment `runs-on: macos-14` (Xcode 15.4 default; install Xcode 16 via the `xcodes` action). When `macos-14` is deprecated by GitHub, upgrade to `macos-15` and re-verify Xcode 16 default-availability before merging the bump. Free for public repos.
- Steps: install Xcode 16 via `xcodes`, select it (`sudo xcode-select -s`), then `xcodebuild -scheme mq-dir -destination 'platform=macOS' build test`.
- `Scripts/bootstrap.sh` (one-shot dev setup) installs Xcode 16 via the `xcodes` CLI if not already present, and is the same code path CI uses.
- Optional: `swift-format lint --recursive Sources Tests` as a soft check.

`.github/workflows/release.yml`:
- Trigger: tag matching `v*`.
- Steps: build release archive, codesign with developer ID stored as encrypted secret (`MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`), notarize via `xcrun notarytool submit`, staple, package as `.dmg` (using `create-dmg`), upload to GitHub Releases.

### Code signing for OSS

- A Developer ID Application certificate ($99/yr Apple Developer membership) is required for notarization.
- Document the DIY path in `CONTRIBUTING.md`: contributors who want to run a locally-built unsigned build use `xattr -d com.apple.quarantine /Applications/mq-dir.app` after first launch.
- The user (as maintainer) signs all official releases. No CI access to the cert is given to outside contributors.
- Store cert + secrets in GitHub Actions secrets. Rotate annually.

### Contribution model

- **Contributions accepted via DCO** (Developer Certificate of Origin) — every commit must include a `Signed-off-by:` line. **No CLA**. The DCO bar is low enough not to scare casual contributors but high enough to give the project clean provenance if downstream redistribution gets complicated.
- `CONTRIBUTING.md` documents the DCO workflow (`git commit -s`), the `xattr -d com.apple.quarantine` first-launch instruction for unsigned local builds, branch/PR conventions, and how to run the test suite.
- `SECURITY.md` lists a maintainer email for vulnerability reports and a 90-day disclosure window.

### Distribution

- **Primary**: GitHub Releases. Notarized `.dmg` (preferred) and `.zip` (fallback). Filename pattern is **pinned** as `mq-dir-vX.Y.Z.dmg` so a future Homebrew bot / livecheck can resolve URLs deterministically.
- **Initial Homebrew distribution**: ship via a **maintainer tap** (`brew tap <user>/mq-dir`), which is just this repo with a `Casks/mq-dir.rb` file. Zero approval barrier, instant updates.
- **`homebrew/homebrew-cask` central submission**: deferred until **30 days of v1.x stability *and* ≥100 GitHub stars**. The central cask repo's review bar is real; submitting prematurely wastes reviewer time and gets the cask kicked back. Tracked as an M6 deliverable.
- **Nightly builds**: ad-hoc-signed (no Developer ID) via `.github/workflows/nightly.yml` for contributors who want bleeding-edge bits without paying $99/yr. Documented in CONTRIBUTING.md alongside the `xattr -d com.apple.quarantine` first-launch instruction.

```ruby
cask "mq-dir" do
  version "1.0.0"
  sha256 "..."
  url "https://github.com/<user>/mq-dir/releases/download/v#{version}/mq-dir-v#{version}.dmg"
  name "mq-dir"
  desc "Quad-pane macOS file manager with embedded preview"
  homepage "https://github.com/<user>/mq-dir"
  app "mq-dir.app"
  zap trash: ["~/Library/Application Support/com.mqdir.app"]
end
```

- App Store: deferred. Possible later, but sandboxing for arbitrary FS access is ugly. v1 ships outside the App Store.

### Privacy posture

**No telemetry, no crash reporting, no analytics in v1.** Privacy-positive default. README states this prominently. Future opt-in crash reporting (e.g. Sentry self-hosted, or PLCrashReporter with manual user-triggered upload) is a v1.1+ discussion, not a v1 feature.

---

## 5. Risks & Mitigations

### R1 — Sandboxing / arbitrary FS access (HIGH likelihood, HIGH impact)

The user wants to browse anywhere on disk. macOS sandboxing forces security-scoped bookmarks for any folder outside the app's container.

- **Mitigation**: ship **non-sandboxed** for v1. Distribute via Developer ID + notarization, not the App Store. This gives full FS access via `FileManager` directly.
- **If we later target App Store**: switch to sandboxed mode and use security-scoped bookmarks (`URL.bookmarkData(options: .withSecurityScope)`, `startAccessingSecurityScopedResource()`, paired `stop`). `BookmarkStore` is designed to handle this from day one — it's a no-op in non-sandboxed mode and active in sandboxed mode. This means the App Store path is preserved as a pivot without rework.
- **Documentation**: README explicitly states "non-sandboxed" with the rationale, so security-conscious users understand.

### R2 — Solo-dev burnout / scope creep (HIGH likelihood, MEDIUM impact)

Most macOS open-source apps die between M2 and M5. Scope creep is the killer.

- **Mitigation**: M1 is shippable on its own (folder browsing + spacebar QuickLook ≈ a usable Finder replacement for the user's stated workflow). After M1, treat each milestone as independently releasable (v0.2, v0.3, ...). Never block a release on a future milestone.
- **Hard rule**: any feature not in this plan is `v2` until M6 ships. Track in `CHANGELOG.md` "Future" section.
- **Pace**: target ~1 milestone/month evenings-and-weekends. M1 in 3-4 weeks. v1.0 in ~5-6 months elapsed.
- **Tripwires** (objective scope-cut triggers, not vibes-based):
  - **If M2 has not shipped within 8 weeks of M1 release**, M3 scope **auto-cuts to images-only** inline preview (NSImageView). Video, audio, PDF, and text all route through `QLPreviewView` with zero custom view code. Buys back ~1.5 weeks.
  - **If the open-PR review backlog exceeds 10 PRs for >2 consecutive weeks**, all maintainer-side feature work pauses until the backlog drops below 5. Reviewing other people's contributions is the highest-leverage use of solo-maintainer time.
  - **If any single milestone slips by >50% of its budgeted duration**, write a `docs/post-mortem-MX.md` before starting the next milestone. No exceptions.

### R3 — AVKit codec coverage limits (MEDIUM likelihood, MEDIUM impact)

AVKit handles H.264, HEVC, ProRes, common audio. It does **not** play MKV containers, VP9 in many configs, or some legacy codecs. Power users will notice.

- **Mitigation**: when `AVURLAsset.isPlayable` returns false, fall back to `QuickLookPreviewView`, which itself falls back to a "Open in default app" button. The app never claims to play everything.
- **Document** in README: "Native preview supports the codecs macOS supports natively. For MKV/VP9, install IINA or VLC and use 'Open with...'."

### R4 — FSEvents stream churn on huge directories (MEDIUM likelihood, LOW impact)

A folder being actively written to (e.g. `~/Downloads` during a download, or a build output directory) can fire hundreds of FSEvents callbacks per second.

- **Mitigation**: each pane's `FSEventStream` (created via `FSEventStreamCreate`, see §3 Concurrency model) routes its callback through a 100ms coalescing debounce. If more than 50 events arrive within a debounce window, the pane drops the incremental patch path and re-enumerates the directory wholesale via `FileManager.default.contentsOfDirectory(at:)`. The stream is invalidated and recreated on every pane navigation, so we never accumulate stale watchers.

### R5 — SwiftUI multi-pane focus management (MEDIUM likelihood, MEDIUM impact)

SwiftUI's `@FocusState` across multiple custom panes is historically rough. Q-Dir's value depends on sane focus.

- **Mitigation**: model focus explicitly in `WindowViewModel.focusedPaneIndex` rather than relying on SwiftUI's responder chain alone (see §3 Focus contract for the full specification). Each pane reads the model and styles its border accordingly. Click-to-focus is a `.onTapGesture` at the pane level. Tab-to-cycle is an `NSEvent` local monitor in `KeyboardCoordinator` translating to `focusedPaneIndex = (focusedPaneIndex + 1) % panes.count`. This gives us deterministic focus regardless of SwiftUI's internal state.

### R6 — TCC permission denials silently return empty arrays (HIGH likelihood, HIGH impact)

macOS TCC denies access to `~/Documents`, `~/Desktop`, `~/Downloads`, iCloud Drive, removable volumes, and network volumes by default. `FileManager.contentsOfDirectory(at:)` returns an empty array on denial — no thrown error, no log. A user opening their `~/Documents` would see an empty list and conclude the app is broken.

- **Mitigation**: declare all required usage descriptions in Info.plist (see §3.5). Detect the denial state by checking whether we're in a TCC-protected zone and got zero entries from a directory that should not be empty (probe via `FileManager.attributesOfItem(atPath:)` link count or sibling `.DS_Store` presence as a heuristic).
- Render a dedicated **"Permission required"** UI affordance with a "Grant Access" button that re-triggers the prompt or deep-links to System Settings → Privacy & Security → Files and Folders.
- **Tests**: `testTCCDenialRendersPermissionUI` simulates denial via `tccutil reset SystemPolicyAllFiles <bundle-id>` in a sandboxed test environment and asserts the permission affordance renders.

### R7 — iCloud `.icloud` placeholder files render as zero-byte stubs (MEDIUM likelihood, MEDIUM impact)

Files not yet downloaded from iCloud Drive appear as zero-byte `*.icloud` stubs. Showing them as empty files is misleading and frustrating.

- **Mitigation**: per §3.5, query `URLUbiquitousItemDownloadingStatusKey` for every entry. Render `.notDownloaded` rows with a cloud-with-arrow glyph and a "Download" affordance that triggers `FileManager.default.startDownloadingUbiquitousItem(at:)` and polls status at 500ms cadence until `.current`.
- **Tests**: `testICloudPlaceholderRendersDownloadAffordance` uses a fixture URL marked with the `.notDownloaded` ubiquity status (mocked at the resource-values layer) and asserts the row renders with the download affordance.

---

## 6. Acceptance Criteria (M1, hand-runnable)

1. **Cold launch and pick a folder**: launch app → click "Open Folder" → pick `~/Downloads` → folder lists within 1s on a 5000-file directory.
2. **List view + sort**: click "Date Modified" header → list sorts descending. Click again → ascending. Column widths drag-resizable.
3. **Persistence (the load-bearing test)**: in `~/Downloads`, sort by Date Modified descending, scroll halfway down, resize Name column to 320px, drag Size column to 80px. Quit (Cmd-Q). Relaunch. Re-open `~/Downloads`. **Same sort, same scroll, same column widths.** *Implementation note*: column-width persistence is delivered by `NSTableView.autosaveTableColumns = true` with `autosaveName = "mq-dir.fileList.<paneID>"` (see §3 List view implementation), not by hand-rolled persistence. Sort and scroll come from `PersistenceStore`. AC fails if column widths reset to defaults after relaunch.
4. **Per-folder isolation**: in `~/Documents`, set Name ascending, scroll to top. Switch back to `~/Downloads` via Cmd-Up + double-click — `~/Downloads` still shows Date Modified descending at the half-scroll position. Each folder remembers its own state independently.
5. **Spacebar QuickLook for media**: select an image → spacebar → QuickLook opens with the image. Select a `.mov` → spacebar → QuickLook plays it. Select a `.mp3` → spacebar → QuickLook plays audio. Select a `.pdf` → spacebar → QuickLook renders it.
6. **Open-in-default and Reveal-in-Finder**: Enter on a `.txt` opens TextEdit (or default). **Cmd-Shift-R** reveals the selected file in Finder. (Cmd-R is reserved for Reload, matching macOS convention; the original plan's Cmd-R was a typo.)
7. **Scroll budget**: scrolling a 50,000-entry directory is smooth. Concretely: Instruments Time Profiler shows **no main-thread block >100ms** over a 5-second continuous scroll, and **frame rate ≥ 58fps** measured via `os_signpost` interval timing. Test machine: **M1 Mac mini base (8GB) on macOS 14.5**, scrolling a 50,000-entry temp directory generated by `Tests/Fixtures/genFiles.sh` (script lives in repo, generates flat directory of empty files with varied names/extensions).
8. **No state loss on restart**: kill the app via Activity Monitor (force quit, `kill -9`). Relaunch. Same window position, same folder, same view state, same sort, same focused pane. (This explicitly tests the "Finder keeps closing" complaint.) **This AC must pass with the synchronous-critical-state save policy from §3** — debounced soft state may legitimately be lost on `kill -9`, but critical state (sort, view mode, focused pane, current folder) must survive.
9. **VoiceOver accessibility**: with VoiceOver enabled (Cmd-F5), the file list is fully navigable. Each row reads `<file name>, <kind>, <size>, modified <date>` in that order. Column headers are accessible and announce sort direction. **Spacebar still triggers QuickLook under VoiceOver** (does not get intercepted by the screen reader). Arrow-key navigation announces the newly-focused row.

---

## 7. Verification Plan

### Manual smoke test checklist (M1 ship-gate)

Run all 9 acceptance criteria above on a fresh user (delete `~/Library/Application Support/com.mqdir.app/` and re-test). Anything that fails blocks ship.

**Before each fresh-user run, also execute** `tccutil reset SystemPolicyAllFiles <bundle-id>` (or use a fresh macOS user account in a VM). This guarantees the run actually exercises first-launch TCC prompts rather than re-using previously granted permissions, which is the #1 silent-failure path for AC #1 / R6.

### Automated tests

- **`PersistenceStoreTests`** (XCTest, required):
  - `testRoundTripPreservesAllFields` — encode + decode `PersistedState` with non-default values for every field; assert equality.
  - `testAtomicWriteSurvivesCrashSimulation` — spawn a child process that writes 100x to the persistence file in a loop while the parent issues `kill -9` at random offsets. Repeat for **10 such kill-cycles**; after each cycle assert the on-disk file is **always parseable as either valid `schemaVersion = 1` JSON or absent** (never partially written, never garbage). Replaces the original `Process.exit` approach, which under-tests the atomic write contract.
  - `testMigration_v1_isStable` — load fixture `state-v1.json`, assert no migration runs, no data loss.
  - `testMigration_v1_to_v2_preservesAllFields` — placeholder test for the next schema bump; loads `state-v1.json`, runs `migrate_v1_to_v2`, asserts every field round-trips into the v2 shape with no loss. Skipped (`XCTSkipUnless schemaVersion >= 2`) until v2 lands, but the test scaffold is in v1 to make migration mandatory rather than optional.
  - `testEvictionAtCapacity` — insert 50,001 entries, assert oldest by `lastSeen` is dropped, **assert that any FolderPrefs marked as currently-open is never evicted** even if it is the oldest.
- **`FileSystemServiceTests`**:
  - `testEnumerateLargeDir` — generate 10k temp files in a temp dir, assert enumeration completes and yields all entries.
  - `testStreamingPartialResults` — assert first batch arrives within 100ms.
  - `testTCCDenialRendersPermissionUI` — simulate TCC denial (test harness mocks `contentsOfDirectory` returning `[]` in a known-protected zone) and assert the `PaneViewModel` exposes a `.permissionRequired` state which the view layer renders as the "Grant Access" affordance.
  - `testICloudPlaceholderRendersDownloadAffordance` — fixture URL is mocked at the resource-values layer to return `URLUbiquitousItemDownloadingStatusKey = .notDownloaded`. Assert the corresponding row exposes `needsDownload = true` and triggers `startDownloadingUbiquitousItem` on user action.
- **`PaneViewModelTests`**:
  - `testNavigateUpdatesPersistedState` — navigate, assert `PersistenceStore` writes within debounce window.
- **`WindowViewModelTests`**:
  - `testFocusContract_ClickSetsFocus` — click event on a non-focused pane sets `focusedPaneIndex`.
  - `testFocusContract_CmdNumberSetsFocus` — Cmd-1/2/3/4 sets focus regardless of mouse.
  - `testFocusContract_TabCycles` — Tab advances `focusedPaneIndex` modulo pane count.
  - `testFocusContract_SidebarTargetsFocusedPane` — sidebar nav routes to focused pane only.

### Snapshot tests

- Optional. Add `pointfreeco/swift-snapshot-testing` only if `FileListView` rendering becomes a regression magnet. Skip in v1.

### Cold-launch performance budget

- Target: **<1s from `applicationDidFinishLaunching` to first usable folder list** on **M1 Mac mini base (8GB), macOS 14.5+, no other apps in foreground**, listing `~/Downloads` with 1000 files. Pinning the test machine matters — a Mac Studio will hit <500ms trivially and mask regressions that would bite Sonoma users on older Apple Silicon.
- Measure: log timestamps with `os_signpost`. Add a debug-build assertion that fails if cold-launch list-render exceeds 1500ms.
- Stretch: <500ms on the same baseline machine.

### Pre-release gates (M5 release infra)

- All 9 acceptance criteria pass on a clean macOS 14 install (test in a VM).
- `xcodebuild test` green in CI.
- `xcrun notarytool` returns "Accepted."
- Stapled `.dmg` opens cleanly on a Gatekeeper-strict machine.
- README quickstart works copy-paste.
- Maintainer Homebrew tap `brew install --cask <user>/mq-dir/mq-dir` works end-to-end.

---

## 8. ADR

**Decision.** Build mq-dir as a native macOS app in SwiftUI + AppKit, Swift 5.10, deployment target macOS 14 (Sonoma). License MIT, contributions via DCO. Distribute as a notarized `.dmg` via GitHub Releases and a maintainer Homebrew tap. Persistent state stored as Codable JSON in Application Support, keyed primarily by security-scoped bookmark digests with `documentIdentifierKey + volumeIdentifierKey` as the in-volume fast-path fallback (never by raw path; `fileResourceIdentifierKey` rejected as session-scoped). `FileListView` is implemented as `NSViewRepresentable` over `NSTableView` with `autosaveTableColumns = true` to deliver column-width persistence on macOS 14. Live updates via `FSEventStreamCreate`. **No telemetry, no analytics in v1.** M1 single-pane folder browser ships as v0.2; quad-pane (M2), embedded preview (M3), sidebar tree (M4), release infra (M5), and UX polish (M6) ship as subsequent point releases.

**Drivers.** (1) Solo-dev velocity — SwiftUI's `NavigationSplitView` collapses ~70% of the UI work, the NSTableView wrap is contained to one file, and QuickLook gives free media preview in M1 *and* covers video/audio/PDF/text in M3 (per the simplification away from hand-rolled AVPlayerView/PDFView/NSTextView). (2) Native macOS feel — the user's pain is Finder jank, so any non-native stack is dead on arrival. (3) Future contributor pool — MIT + DCO + checked-in `xcodeproj` + GitHub Actions matches the OSS macOS app norm (Iina, Rectangle, AltTab) and minimizes onboarding friction.

**Alternatives considered.** Tauri (Rust core + WebView UI) — rejected because bridging QuickLook/AVKit through WKWebView IPC undermines the highest-value feature. Electron — rejected because it embodies the very UI jank the user is trying to escape. Flutter desktop — rejected as immature for FS-heavy macOS apps. Bumping the deployment target to macOS 15 to use `TableColumnCustomization` — rejected; the NSTableView wrap costs one file and preserves the macOS 14 user base.

**Why chosen.** SwiftUI + AppKit is the only option where the headline features (per-folder persistence, embedded media preview, multi-pane native focus) are 1-2 days of work each rather than 1-2 weeks. A solo developer ships M1 in weeks, not quarters. The macOS power-user audience treats native apps as a quality signal, raising adoption probability.

**Consequences.**
- **Positive**: smallest binary, fastest cold launch, full access to QuickLook/AVKit/FSEvents, alignment with macOS OSS norms, App Store path preserved as a future pivot via `MQDIR_SANDBOXED` build flag, privacy-positive default (no telemetry), Sparkle 2 public key embedded in v1 keeps the v1.1 auto-update path unblocked.
- **Negative**: macOS-only forever (we're explicitly not portable); contributor pool narrower than a web stack; tied to Apple's SwiftUI release cadence and bug churn (`@Observable`, `Table`, focus); annual $99 Developer ID dependency; sandboxing/security-scoped bookmark complexity if we ever pursue App Store; **TCC prompts surface on first folder access and require Info.plist usage strings** for Desktop / Documents / Downloads / RemovableVolumes / NetworkVolumes (see §3.5); **iCloud `.icloud` placeholders need explicit ubiquity handling** to avoid zero-byte confusion (see §3.5); **`NSTableView` wrap (or a future macOS 15 minimum bump) is required for column-width persistence** on the chosen macOS 14 baseline.

**Follow-ups (deferred open questions).**

- v1.1: auto-update via Sparkle 2 (public key embedded in v1, wiring lands in v1.1).
- v1.1: full-text recursive search (likely Spotlight `NSMetadataQuery` rather than custom indexer).
- v1.2: archive previews (zip/tar) — evaluate `libarchive` Swift wrapper.
- v1.2: optional sandboxed App Store build path via `MQDIR_SANDBOXED` flag.
- v2: cloud mounts (S3/SMB) — out of scope; prefer to defer indefinitely unless a contributor champions it.
- v2: opt-in crash reporting (PLCrashReporter manual upload, or self-hosted Sentry) — not v1.
- TBD: keyboard shortcut customization UI (M6 ships fixed shortcuts; user demand may force a settings panel earlier).
- TBD: dark/light theming — SwiftUI handles automatically; flag if Q-Dir-style colored panes are wanted, which would need explicit theming.
- TBD: when JSON prefs file crosses 5 MB, migrate the prefs map to GRDB-backed SQLite (window state stays JSON).

---

## Revision Notes (iter 1)

This iteration applied the Architect's 4 BLOCKERS + Critic's 25 file-anchored deltas. Where deltas conflicted with the original text, deltas won.

**Applied verbatim** (text or technical contract used as written):
- Delta #1 (key shape: documentIdentifierKey + volumeIdentifierKey, bookmark primary, fileResourceIdentifierKey rejected, never key on raw path) — §3 Persistence.
- Delta #2 (NSViewRepresentable wrap of NSTableView with autosaveName + autosaveTableColumns) — §3 List view implementation subsection.
- Delta #3 (FSEventStreamCreate, non-recursive per-pane, invalidate-on-navigation, R4 prose match) — §3 Concurrency, §5 R4.
- Delta #4 (synchronous critical state, debounced soft state, flush on three lifecycle events) — §3 Save cadence.
- Delta #5 (cap 50,000, never evict open folders, eviction at launch only, 5MB → SQLite migration) — §3 Eviction.
- Delta #6 + BLOCKER 3 (TCC + iCloud subsection with all 5 Info.plist usage descriptions) — new §3.5.
- Delta #7 (R6 TCC, R7 iCloud) — §5 added in full.
- Delta #8 (R2 tripwires: M2-8wk, PR-backlog-10, milestone-50% slip post-mortem) — §5 R2.
- Delta #10 (AC #3 NSTableView.autosaveTableColumns implementation note).
- Delta #11 (Cmd-R → Cmd-Shift-R for Reveal in Finder).
- Delta #12 (AC #7: Instruments, ≥58fps, M1 Mac mini base, genFiles.sh).
- Delta #13 (AC #8 explicitly references §3 critical-state save policy).
- Delta #14 (manual smoke test prefixed with `tccutil reset SystemPolicyAllFiles`).
- Delta #15 (testAtomicWrite: 100x writes × 10 kill cycles, parseable-or-absent invariant).
- Delta #16 (cold-launch budget pinned to M1 Mac mini base, macOS 14.5+, no foreground apps).
- Delta #17 (added testMigration_v1_to_v2_preservesAllFields, testTCCDenialRendersPermissionUI, testICloudPlaceholderRendersDownloadAffordance).
- Delta #18 (CI pinned `runs-on: macos-14`, xcodes action, bootstrap.sh installs Xcode 16).
- Delta #19 (DCO contributions, no CLA, SECURITY.md with maintainer email, xattr first-launch instruction).
- Delta #20 (maintainer tap first; central homebrew/homebrew-cask after 30d + 100 stars; pinned `mq-dir-vX.Y.Z.dmg`; nightly.yml ad-hoc-signed).
- Delta #21 (M5 = release infra, M6 = UX polish; M0-M4 numbering preserved).
- Delta #22 (M0: menu bar in AppDelegate, bundle id, LSApplicationCategoryType utilities, AppIcon placeholder, en.lproj scaffolding).
- Delta #23 (ADR Consequences/Negative now lists TCC, iCloud, NSTableView-wrap explicitly).
- Delta #24 (no telemetry/analytics in v1, Sparkle 2 public key embedded in v1).
- Delta #25 (AC #9 VoiceOver row-read order, headers accessible, spacebar still triggers QuickLook).
- BLOCKER directives: focus contract subsection added in §3 (focus owned by `WindowViewModel.focusedPaneIndex`, 2px accent border, Cmd-T/Cmd-W/Cmd-1-4/Tab semantics, spacebar-scopes-to-focused-pane). Default v1 entitlements file ships sandbox-related keys gated behind `MQDIR_SANDBOXED` build flag rather than in the default file. M3 simplified to NSImageView for images only; video/audio/PDF/text route through inline `QLPreviewView`.

**Merged** (delta intent kept; surrounding plan adjusted for consistency):
- M2 / M4 non-goals updated to reference M6 instead of M5 (delta #21 ripple). Both edits made because moving the original M5 contents into M6 invalidated forward-references.
- §5 R5 (focus management) now cross-references the new §3 Focus contract subsection rather than restating it, to avoid duplication.
- §7 manual smoke test count updated from 8 to 9 to match the new AC #9.
- ADR Decision/Drivers/Consequences/Follow-ups rewritten end-to-end to integrate every applied delta (FSEvents, NSTableView wrap, DCO, no-telemetry, M5/M6 split, TCC/iCloud, security-scoped bookmark primacy).

**Judgment calls** (called out for the next reviewer):
- For the in-volume fast-path fallback I encoded `FolderID` as either a "bookmark digest" *or* a `(volumeID, documentID)` tuple at the type level. Critic delta #1 specified the constituent fields but not the encoding; this is the simplest way that supports both paths in one Codable map without sentinel values. Open to a different encoding in iter 2.
- Delta #5 said "If JSON file exceeds 5MB, migrate one-way to GRDB-backed SQLite." I scoped the migration to the prefs map only (window state stays JSON) because window state is small and benefits from human-readability for debugging. Flagged in ADR Follow-ups.
- Delta #21 listed M6 deliverables including "After 30 days of v1.x stability and ≥100 stars, submit cask to homebrew/homebrew-cask." This was also delta #20's distribution rule. I rendered it in both places (M6 capabilities + §4 Distribution) because they answer different reader questions; flagging the redundancy in case iter 2 wants to dedupe.
- I did **not** widen the file scope to a separate "open questions" file — the plan's own ADR Follow-ups + this Revision Notes section serve that role for the consensus loop. If iter 2 wants `.omc/plans/open-questions.md`, easy to extract.
