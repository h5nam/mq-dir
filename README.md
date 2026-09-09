# mq-dir

> Free, open-source macOS file manager for AI multi-taskers. Up to four independent panes per project, each remembering its folder, sort, and scroll position across launches — with zero telemetry, ever.

[![release](https://img.shields.io/github/v/release/h5nam/mq-dir?label=release&color=blue)](https://github.com/h5nam/mq-dir/releases)
[![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](#requirements)
[![swift](https://img.shields.io/badge/swift-5.10-orange)](https://swift.org)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

🌐 [mqdir.com](https://mqdir.com) · 📓 [Releases](https://github.com/h5nam/mq-dir/releases) · 🛠 [Contributing](CONTRIBUTING.md) · 🌏 [한국어](README.ko.md)

![mq-dir hero](.github/assets/readme_hero.png)

## Why

A modern coding session is half source, half artifacts: generated images, recorded demos, PDFs, screenshots from QA, exported transcripts, downloaded models, design specs. None of it lives where your code does — and Finder wasn't built for that volume or for the way agents now produce work in parallel.

mq-dir gives you up to four independent panes side by side. One per project, one per agent, one for the artifact dump. Each pane keeps its own folder, sort, scroll position, and column widths — and remembers them across launches and force-quits.

## Features

- 🟦 **1 / 2H / 2V / 4-pane layouts** — focused-pane routing, independent folder per pane.
- ↹ **Per-pane tabs** — Safari-style strip with X/+, ⌘T / ⌘W / ⌘⇧T / ⌘1…⌘9 / ⌘⇧[ / ⌘⇧], drag-to-reorder, drag a tab onto Favorites to bookmark its folder, right-click Close Other / Close to Right / Duplicate, last-tab safety placeholder.
- 🌳 **VS Code-style tree view** — per-tab toggle, lazy child loading, separate chevron hit target (clicking a folder name selects without expanding), Shift / Cmd multi-select, file drag-out to external apps. New tabs via **⌘+double-click** or **⌘+Enter** on a folder (same as list view).
- ⌨️ **Keyboard nav + Finder-parity right-click** — ↑/↓ step through rows (hold to repeat, Shift to extend the selection); Return opens, ⌘+Return opens in a new tab. **⌘C / ⌘X / ⌘V** copy / cut / paste with Windows Explorer-style move semantics — a ⌘X-marked selection moves on ⌘V at the destination instead of copying (something Finder doesn't ship). Row context menu covers Open With ▸ (LaunchServices candidates + Other…), Get Info, Reveal in Finder, Copy / Copy Path, Duplicate, Rename, **Normalize Filename to NFC** (rewrites Hangul filenames stored as decomposed NFD on disk to the precomposed NFC form Windows / Slack / Discord / Gmail / web uploaders expect — multi-select supported, no-op on already-NFC names), and Move to Trash. Multi-selection right-clicks act on the whole selection. Restoring keyboard focus after a rename is handled correctly in both list and tree view.
- ⚙️ **Settings → Shortcuts** — 17 actions re-bindable from Preferences (⌘,), including F1…F12. Reset-to-default per row.
- 👀 **Per-tab preview pane** — toggle in the pane header (or ⌘⇧P). PDFs render through PDFKit with continuous scroll + paging; everything else routes through Quick Look for images, code, video, audio, office docs (DOCX/PPTX/XLSX). MarkdownUI handles `.md` with full GFM (tables, code blocks, lists). Folder/multi/empty selections get custom summaries. Zip archives preview in-pane (listing + single-entry decode). Multi-page navigation for non-PDF documents and formats macOS Quick Look has no generator for (HWP, etc.) is best done with ⎵ to summon the floating Quick Look panel, or ⇧↩ to open in the system default app (e.g. Hancom Office Viewer for HWP).
- 🏷️ **Finder tag display** — per-tag colour swatches (red / orange / yellow / green / blue / purple / grey) read straight from macOS metadata, including multi-tag rows. Sidebar Tags section lists every tag in the current folder. Read-only — applying or editing tags happens in Finder.
- 📂 **Custom folder icons** — folders with a Finder-assigned custom icon (Get Info → drag image) render that icon in the row, not the system default.
- ⭐ **User-editable Favorites sidebar** — drag folders in (or drag a tab in to bookmark its folder), right-click Remove or Rename, drag to reorder, ⌘⇧D adds the focused pane's folder. Real Finder folder icons, stale-path styling.
- 📁 **Projects (workspaces)** — named snapshots of (layout + pane tabs + focus). + button creates one, click switches, right-click Rename / Delete, drag to reorder. Switching auto-saves the outgoing project.
- 💾 **State persistence** — every pane / tab / favorite / project survives relaunch, force-quit, and even schema upgrades (legacy `state.json` shapes auto-migrate).
- 🔎 **Per-pane recursive search** — debounced, case-insensitive substring match across the current folder's subtree. ⌘F.
- 🔄 **In-app auto-update** — Sparkle 2 polls the appcast every 24 h; when a new release is out, the sidebar grows an "Update Available" button that runs the standard install/relaunch flow.
- 💬 **In-app Send Feedback** — sidebar footer → send a short note with optional screenshots straight to the maintainer (no email client involved).
- 🔗 **Selectable coding app integrations** — choose cmux, Orca, Paseo, Claude Code Desktop, or Codex Desktop in the sidebar, then Sync to list local workspace folders. Click to open a folder; ⌘-click opens a new tab. The selection survives relaunch. See [setup and support boundaries](docs/integrations.md).
- 🎨 **Native macOS look** — SwiftUI + AppKit, system theme tokens, hand-finished app icon.

**Roadmap**

- 3-pane layout option.
- More archive formats in-pane (tar / 7z / rar).
- Open to ideas — file an issue or use the in-app Send Feedback.

## Status

**v0.1.2 — latest stable cut.** Each tagged build is Developer ID-signed and Apple-notarized. The feature set above has been daily-driven by the maintainer and a small early-adopter group; expect occasional rough edges around ergonomics. Per-release detail lives on the [Releases page](https://github.com/h5nam/mq-dir/releases).

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel
- For building: Xcode 15+, [Homebrew](https://brew.sh)

## Install

### From the signed DMG (recommended)

Grab the latest `.dmg` from [Releases](https://github.com/h5nam/mq-dir/releases) and drag `mq-dir.app` into `/Applications`. Notarized + stapled, so Gatekeeper opens it without a right-click trick. The running app then auto-updates via Sparkle on its 24-hour cadence (or whenever you click the sidebar's "Update Available" button).

### Via Homebrew

```bash
brew install --cask h5nam/mq-dir/mq-dir
```

`brew` tap-installs the formula on first use — no separate `brew tap` needed. Subsequent updates are `brew upgrade --cask mq-dir`. The cask points at the same signed DMG as above; the tap repo ([`h5nam/homebrew-mq-dir`](https://github.com/h5nam/homebrew-mq-dir)) is refreshed automatically by the release workflow.

### From source

```bash
git clone https://github.com/h5nam/mq-dir.git
cd mq-dir
Scripts/bootstrap.sh   # installs XcodeGen and the xcodes CLI
open mq-dir.xcodeproj
```

`bootstrap.sh` generates `mq-dir.xcodeproj` from `project.yml` (XcodeGen is the source of truth — the `.xcodeproj` is not checked in).

**Tests-only** (no Xcode required, just the Swift toolchain):

```bash
swift test
```

## Privacy

External images in Markdown previews are blocked by default. Choosing **Load external images** sends requests to the image servers for that document. Opening another document resets this permission. Local images display without image-server requests.

**We never call home. No telemetry, no crash reporting, no analytics. Ever, in v1.**

mq-dir is local-only by default. Outbound network traffic is limited to the following paths, each auditable in the source:

1. **Markdown external images** — only after choosing to load external images for the previewed document.
2. **Sparkle update check** — once every 24 hours, fetches `https://h5nam.github.io/mq-dir/appcast.xml`. Public file, no identifying info attached to the request.
3. **Send Feedback** — only when *you* press the button in the sidebar footer, posts your message + optional screenshots to the maintainer's Discord webhook. Nothing leaves the machine if you never use it.

No background analytics, no usage pings, no crash reporting upload. Local state lives in `~/Library/Application Support/com.mqdir.app/`.

If a v1.x release ever proposes opt-in crash reporting, it will land behind a config toggle defaulting to off, with the source clearly visible.

## Out of scope for v1

Cloud sync, file editing, plugins, iPadOS/iOS port, localization beyond English. Archive *editing* (we preview zip in-pane; tar / 7z / rar previews are on the roadmap, not write support).

## Contributing

PRs welcome. Contributions are accepted via [DCO](https://developercertificate.org/) — every commit needs a `Signed-off-by:` line. **No CLA.** See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the workflow, [`SECURITY.md`](SECURITY.md) for vulnerability disclosure, and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Releasing (maintainers only)

```bash
Scripts/release.sh --dry-run 0.3.0
Scripts/release.sh 0.3.0
```

Run from a clean `main`. The script bumps version/build and pushes the commit and tag atomically. CI tests that exact tag and validates the bundle before signing, notarizing and publishing. Published assets are never overwritten; reruns verify the existing files and resume appcast/cask updates.

See the [release guide](docs/releasing.md) for credentials, dependency locking and recovery. Generate the app project with `Scripts/generate-project.sh` to apply the tracked dependency lock.

## License

MIT — see [`LICENSE`](LICENSE).

## Acknowledgments

mq-dir's quad-pane layout is inspired by **[Q-Dir](https://www.q-dir.com/)** by SoftwareOK / Nenad Hrg, a long-running Windows file manager that made the case for multi-pane file management. mq-dir is an independent, clean-room implementation in Swift for macOS — **not affiliated with, endorsed by, or derived from Q-Dir's source code**.
