# mq-dir — UI Product Requirements Document
**Version:** 1.0 | **Status:** Draft | **Audience:** UI Designer / Frontend Prototyper

---

## 1. Product Context

mq-dir is a native macOS file manager for power users who find Finder too amnesiac and too cramped. Its headline promise is simple: **the UI you left is the UI you return to** — sort order, scroll position, column widths, and view mode all survive quit, relaunch, and force-quit. The window layout draws from Q-Dir's quad-pane heritage (up to four independent browsing panes in a 2×2 grid) and pairs it with a VS Code-style collapsible folder tree on the left. Each pane is fully independent — its own folder, its own sort, its own history — so side-by-side comparisons and drag-to-move workflows become muscle memory rather than friction. Inline media preview (images with pinch-zoom, video and audio via system QuickLook controls, PDF) lives inside the window without spawning a floating panel. The tone references are Iina (dark, focused, no chrome excess), NetNewsWire (deeply mac-native, respects system appearance, no rounded-corner theatrics), and Things 3 (obsessive polish, every pixel earns its place). The result is not Electron-y, not cross-platform-y, not "macOS but make it web" — it is a first-class AppKit citizen that happens to be built with SwiftUI where SwiftUI earns it.

---

## 2. Design Principles

- **Native macOS first.** System materials (vibrancy, `.underWindowBackground`, `.headerView`), SF Symbols, native traffic-light controls, standard NSWindow chrome. The app looks like it shipped with macOS, not like it was ported to it.
- **State persistence is visible, not invisible.** The fact that mq-dir remembers your state is the headline feature — but the UI should not constantly announce it. State memory is felt as reliability, not shown as a badge. The one exception: on cold launch, the window opens exactly where you left it, which is the moment the promise becomes visceral.
- **Keyboard-first; mouse-friendly.** Every navigable element has a keyboard path. Shortcuts are logical and follow macOS conventions (Cmd for actions, Option for variants, Shift for range). No action is mouse-only.
- **Quiet UI.** No bouncy spring animations, no decorative gradients, no shimmer loaders. Transitions are functional — they communicate state change without entertaining the user. ≤200ms ease-out. Reduced Motion disables all transitions immediately.
- **Focus is explicit and unambiguous.** In a multi-pane layout, keyboard actions must act on exactly one pane. The focused pane shows a 2pt accent-colored border; unfocused panes show nothing. There is never any ambiguity about where a keypress lands.
- **Accessible from launch.** VoiceOver row read-order, full keyboard navigation, WCAG AA contrast, Increase Contrast mode support, Reduce Transparency solid-background fallback — all built in, not bolted on.

---

## 3. Information Architecture

```
┌─ NSWindow ─────────────────────────────────────────────────────────────────┐
│ ● ● ●  [toolbar region — .headerView material]                              │
│  traffic  [ ← ][ → ][ ↑ ] [breadcrumb / path input] [search] [layout ▤]   │
│  lights                                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│ ┌── Sidebar ──┐  ┌── Pane Area ─────────────────────────────────────────┐  │
│ │ FAVORITES   │  │                                                       │  │
│ │  ▸ Desktop  │  │  Pane 1 [tab bar]          Pane 2 [tab bar]          │  │
│ │  ▸ Docs     │  │  ┌─────────────────────┐   ┌──────────────────────┐  │  │
│ │  ▸ Downloads│  │  │ [header: name+count]│   │ [header: name+count] │  │  │
│ │             │  │  │ [file list]          │   │ [file list]          │  │  │
│ │ VOLUMES     │  │  │ ...                  │   │ ...                  │  │  │
│ │  ▸ Macintosh│  │  └─────────────────────┘   └──────────────────────┘  │  │
│ │  ▸ USB Drive│  │                                                       │  │
│ │             │  │  Pane 3 [tab bar]          Pane 4 [tab bar]          │  │
│ │ TAGS        │  │  ┌─────────────────────┐   ┌──────────────────────┐  │  │
│ │  ● Red      │  │  │ [file list]          │   │ [preview pane]       │  │  │
│ │  ● Blue     │  │  │ ...                  │   │ [image / QL / info]  │  │  │
│ │             │  │  └─────────────────────┘   └──────────────────────┘  │  │
│ │ [+ bookmark]│  │                                                       │  │
│ └─────────────┘  └───────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────────────────┤
│ [status bar — 24pt] 3 selected  •  12.4 MB  •  487 GB free                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Regions:**
- **Toolbar** — top, 38pt height, `.headerView` material, not draggable by default (title bar area above is draggable)
- **Sidebar tree** — left, collapsible, `.underWindowBackground` vibrancy, three sections: Favorites / Volumes / Tags
- **Pane area** — center, grows to fill; 1 / 2 / 3 / 4 independent panes arranged by layout enum
- **Preview pane** — right panel inside a pane when that pane is in preview mode (M3+); collapsible
- **Status bar** — bottom, 24pt, optional, shows selection info + disk free

---

## 4. Layout & Wireframes

### M1 — Single-pane window (default, cold launch)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                │
│  ← →  ↑   /Users/hona/Downloads          [🔍]  [⊞ 1]              │
├──────────────────────────────────────────────────────────────────────┤
│  [tab: Downloads ×]  [+]                                             │
├──────────────────────────────────────────────────────────────────────┤
│  Name                    Date Modified      Size       Kind          │
│  ───────────────────────────────────────────────────────────────     │
│  ▼ project-notes.txt     Today 14:22        4 KB       Plain Text    │
│  ▼ screenshot-2026.png   Today 09:11        2.1 MB     PNG Image     │
│  ▼ invoice.pdf           Apr 29 18:45       320 KB     PDF Document  │
│  ▼ archive.zip           Apr 28 10:00       15.3 MB    ZIP Archive   │
│  ▼ video-demo.mov        Apr 27 16:30       234 MB     QuickTime     │
│  ▼ notes-draft.md        Apr 26 11:00       12 KB      Markdown      │
│  ▼ .DS_Store             Apr 24 08:00       6 KB       Document      │
│                                                                      │
│                                                                      │
│                                                                      │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  7 items  •  252 MB  •  487 GB free                                  │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: No sidebar in M1. Single pane fills the content area. Focus border (2pt accent) wraps the pane. Tab bar above file list. Column headers are sortable.

---

### M2 — Two-pane (50/50 horizontal split)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                │
│  ← →  ↑   /Users/hona/Downloads          [🔍]  [⊟ 2]              │
├──────────────────────────────────────────────────────────────────────┤
│                              │                                       │
│  [tab: Downloads ×]  [+]     │  [tab: Documents ×]  [+]             │
├─────────────────────────────┤├──────────────────────────────────────┤
│  Name          Date   Size   ││  Name          Date   Size           │
│  ──────────────────────────  ││  ─────────────────────────           │
│▶ project.txt   Today  4KB    ││  report.docx   Today  44KB           │
│  screenshot.   Today  2.1MB  ││  budget.xlsx   Apr29  102KB          │
│  invoice.pdf   Apr29  320KB  ││  notes.txt     Apr28  8KB            │
│  archive.zip   Apr28  15MB   ││  slides.key    Apr27  4.2MB          │
│  video.mov     Apr27  234MB  ││  contract.pdf  Apr26  890KB          │
│  notes.md      Apr26  12KB   ││  photo.heic    Apr25  3.1MB          │
│                              ││                                      │
│                              ││                                      │
│                              ││                                      │
├─────────────────────────────────────────────────────────────────────┤
│  1 selected  •  4 KB  •  487 GB free                                │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: `▶` row highlight indicates selection in focused pane. Divider is a 1pt separator, drag-resizable. Focused pane (left) has 2pt accent border. Right pane border is system separator color.

---

### M2 — Four-pane (2×2 grid)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                │
│  ← →  ↑   /Users/hona/Downloads          [🔍]  [⊞ 4]              │
├────────────────────────────────┬─────────────────────────────────────┤
│ [tab: Downloads ×][+]          │ [tab: Documents ×][+]               │
├────────────────────────────────┤─────────────────────────────────────┤
│ Name            Size           │ Name            Size                │
│ ─────────────────────────────  │ ────────────────────────            │
│ project.txt     4 KB           │ report.docx     44 KB               │
│ screenshot.png  2.1 MB         │ budget.xlsx     102 KB              │
│ invoice.pdf     320 KB         │ notes.txt       8 KB                │
│ archive.zip     15.3 MB        │ slides.key      4.2 MB              │
│                                │                                     │
├────────────────────────────────┼─────────────────────────────────────┤
│ [tab: Desktop ×][+]            │ [tab: Pictures ×][+]                │
├────────────────────────────────┤─────────────────────────────────────┤
│ Name            Size           │ Name            Size                │
│ ─────────────────────────────  │ ────────────────────────            │
│ readme.txt      1 KB           │ IMG_0423.heic   3.8 MB              │
│ .zshrc          2 KB           │ IMG_0422.heic   4.1 MB              │
│ wallpaper.png   8.4 MB         │ IMG_0421.jpg    2.2 MB              │
│                                │ vacation.mov    812 MB              │
│                                │                                     │
├──────────────────────────────────────────────────────────────────────┤
│  0 selected  •  487 GB free                                          │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: Focused pane (top-left) shows 2pt accent border; others show no border. All four panes are fully independent. Pane dividers are drag-resizable both horizontally and vertically.

---

### M3 — With right-side preview pane

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                │
│  ← →  ↑   /Users/hona/Pictures           [🔍]  [⊡ preview]        │
├────────────────────────────────────────┬─────────────────────────────┤
│ [tab: Pictures ×][+]                   │ PREVIEW                     │
├────────────────────────────────────────┤─────────────────────────────┤
│ Name               Date      Size      │                             │
│ ──────────────────────────────────── │          IMG_0423.heic       │
│ IMG_0423.heic      Today  3.8 MB     ◀│                             │
│ IMG_0422.heic      Today  4.1 MB      │   [image fills area         │
│ IMG_0421.jpg       Apr29  2.2 MB      │    with aspect fit]         │
│ vacation.mov       Apr28  812 MB      │                             │
│ birthday.heic      Apr27  3.2 MB      │   ╔══════════════╗          │
│ scan-doc.pdf       Apr26  2.1 MB      │   ║  [−] 100% [+]║          │
│ meeting-notes.txt  Apr25  8 KB        │   ╚══════════════╝          │
│                                       │                             │
│                                       │ 3.8 MB  •  4032×3024        │
│                                       │ HEIC  •  Today 09:22        │
├──────────────────────────────────────────────────────────────────────┤
│  1 selected  •  3.8 MB  •  487 GB free                              │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: `◀` on selected row indicates preview active. Preview divider is a 1pt separator, drag-resizable. Zoom controls shown only for images. File metadata shown below preview. Preview region collapses to show icon + "No Preview Available" for unsupported types.

---

### M4 — With left sidebar tree expanded

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                │
│  ← →  ↑   /Users/hona/Downloads          [🔍]  [⊟ 2]              │
├───────────────┬──────────────────────────────────────────────────────┤
│ FAVORITES     │ [tab: Downloads ×][+]      [tab: Documents ×][+]    │
│  ▾ Desktop    ├──────────────────────────┬───────────────────────────┤
│  ▾ Documents  │ Name          Size        │ Name          Size        │
│  ▾ Downloads  │ ─────────────────────     │ ─────────────────────     │
│  ▾ Projects   │ project.txt   4 KB        │ report.docx   44 KB       │
│    + bookmark │ screenshot.   2.1 MB      │ budget.xlsx   102 KB      │
│               │ invoice.pdf   320 KB      │ notes.txt     8 KB        │
│ VOLUMES       │ archive.zip   15.3 MB     │ slides.key    4.2 MB      │
│  ▾ Macintosh  │ video.mov     234 MB      │ contract.pdf  890 KB      │
│  ▸ USB Drive  │                           │                           │
│  ▸ iCloud     │                           │                           │
│               │                           │                           │
│ TAGS          │                           │                           │
│  ● Red        │                           │                           │
│  ● Blue       │                           │                           │
│  ● Green      │                           │                           │
├───────────────┴──────────────────────────────────────────────────────┤
│  0 selected  •  487 GB free                                          │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: Sidebar uses `.underWindowBackground` vibrancy. Section headers (FAVORITES, VOLUMES, TAGS) are 11pt bold uppercase `tertiaryLabelColor`. Disclosure triangles are `chevron.right` / `chevron.down` SF Symbols. `▾` = expanded, `▸` = collapsed. Sidebar width is drag-resizable; double-click divider resets to 220pt.

---

### Empty state — no folder selected (cold launch, first time)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                │
│  ← →  ↑                                   [🔍]  [⊞ 1]              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│                                                                      │
│                                                                      │
│                          folder.fill                                 │
│                         ┌──────────┐                                 │
│                         │    📁    │                                 │
│                         └──────────┘                                 │
│                                                                      │
│                       No Folder Open                                 │
│                                                                      │
│              Open a folder to start browsing files.                  │
│                                                                      │
│                     [ Open Folder…   ]                               │
│                                                                      │
│                                                                      │
│              Or drag a folder here from Finder or                    │
│              the sidebar.                                            │
│                                                                      │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: Icon is `folder.fill` SF Symbol at ~48pt, `tertiaryLabelColor`. Headline is 15pt semibold `labelColor`. Body is 13pt `secondaryLabelColor`. Button is the system default button style. Status bar is blank on empty state.

---

### TCC-denied state ("Permission required")

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                │
│  ← →  ↑   /Users/hona/Documents          [🔍]  [⊞ 1]              │
├──────────────────────────────────────────────────────────────────────┤
│  [tab: Documents ×]  [+]                                             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│                                                                      │
│                                                                      │
│                           lock.fill                                  │
│                         ┌──────────┐                                 │
│                         │    🔒    │                                 │
│                         └──────────┘                                 │
│                                                                      │
│                   Permission Required                                │
│                                                                      │
│         mq-dir cannot access the Documents folder.                   │
│         Grant access to browse files here.                           │
│                                                                      │
│              [ Open System Settings… ]                               │
│                                                                      │
│                                                                      │
│                                                                      │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  Permission denied  •  487 GB free                                   │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: Icon is `lock.fill` SF Symbol, `tertiaryLabelColor`. "Open System Settings…" is a default button that deep-links to Privacy & Security > Files and Folders. Path breadcrumb remains visible so user understands which folder is denied. Status bar shows "Permission denied" in `secondaryLabelColor`.

---

### iCloud .icloud placeholder row state

```
┌──────────────────────────────────────────────────────────────────────┐
│  Name                       Date Modified     Size      Kind         │
│  ──────────────────────────────────────────────────────────────      │
│  document-final.pages       Today 14:22       4.2 MB    Pages        │
│  ⬇ report-draft.pages       Apr 29 09:00      —         Pages   ⬇   │
│  spreadsheet.numbers        Apr 28 10:15      2.1 MB    Numbers      │
│  ⬇ video-backup.mov         Apr 27 16:00      —         Movie   ⬇   │
│  photo.heic                 Apr 26 12:30      3.8 MB    HEIC Image   │
│                                                                      │
│   ↑ rows with ⬇ icon are iCloud placeholders not yet downloaded     │
│     Size shows — (unknown until downloaded)                          │
│     Click ⬇ icon or row to trigger download                          │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: iCloud placeholder rows show `arrow.down.circle` SF Symbol in the row's trailing area and prepended to the filename. Text color is `secondaryLabelColor` (dimmed vs normal rows). Size column shows "—" (em dash). Clicking anywhere on the row (or the icon) triggers download. During download, the icon animates to a circular progress indicator. On completion, the row transitions to a normal appearance.

---

### Loading state — large directory (>500ms to enumerate)

```
┌──────────────────────────────────────────────────────────────────────┐
│  [tab: Build Output ×]  [+]                                          │
├──────────────────────────────────────────────────────────────────────┤
│  Name                    Date Modified      Size       Kind          │
│  ───────────────────────────────────────────────────────────────     │
│  AppDelegate.o           Today 15:44        12 KB      Object        │
│  AppKit.framework        Today 15:44        —          Framework     │
│  AVFoundation.framework  Today 15:44        —          Framework     │
│  BaseTarget.o            Today 15:44        8 KB       Object        │
│  ░░░░░░░░░░░░░░░░        ░░░░░░░░░░░        ░░░░       ░░░░░░░       │
│  ░░░░░░░░░░░             ░░░░░░░░░░░        ░░░░       ░░░░░░░       │
│  ░░░░░░░░░░░░░░░░░░░░    ░░░░░░░░░░░        ░░░░       ░░░░░░░       │
│  ░░░░░░░░                ░░░░░░░░░░░        ░░░░       ░░░░░░░       │
│  ░░░░░░░░░░░░░░░░        ░░░░░░░░░░░        ░░░░       ░░░░░░░       │
│                                                                      │
│              ◌ Loading…   (3,421 items so far)                       │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│  Loading  •  3,421 items so far  •  487 GB free                      │
└──────────────────────────────────────────────────────────────────────┘
```

Notes: Results stream in batches of 500. Already-loaded rows render immediately; skeleton placeholder rows (`░`) fill the visible area below. After 500ms with no completion, a small `NSProgressIndicator` (spinning, indeterminate) appears in the bottom bar with item count. Skeleton rows use `quaternaryLabelColor` as fill color and have no interactivity. Status bar live-updates item count as batches arrive.

---

## 5. Component Inventory

### App Window Chrome

**Purpose:** Standard NSWindow container with traffic lights, draggable title region, and native resize handles.

**Visual:** macOS 14 standard window. Traffic lights (close/minimize/zoom) at top-left. Title bar is transparent; toolbar extends into it. Window background uses system `windowBackgroundColor`.

**States:**
- Default: full chrome, toolbar visible
- Key (focused): traffic lights show colored symbols (red/yellow/green)
- Inactive: traffic lights dim to gray circles
- Full Screen: toolbar collapses to auto-hide; traffic lights hidden
- Split View: standard macOS split view chrome

**Behavior:** Title bar region above toolbar is draggable (move window). Double-clicking title bar zooms window (system default). Resize via all edges and corners.

**Keyboard:** Cmd-M minimizes. Cmd-Ctrl-F toggles full screen. Cmd-W closes the active tab (not the window); if last tab, closes the pane; if last pane, prompts to close window.

---

### Toolbar

**Purpose:** Primary navigation and action strip — back/forward/up, path breadcrumb, search, layout switcher.

**Visual:** 38pt height. `.headerView` NSVisualEffectView material. Horizontally: `[← →]` `[↑]` `[breadcrumb]` `[search icon]` `[layout switcher]`. Spacing 8pt between groups.

**States:**
- Default: all controls at normal opacity
- Back disabled: `←` is `tertiaryLabelColor`; forward disabled similarly
- Searching: breadcrumb hides; search field expands to fill; Esc cancels
- Loading: breadcrumb path segment for current folder shows a tiny inline `NSProgressIndicator`

**Behavior:** Toolbar is not user-customizable in v1 (no View > Customize Toolbar sheet). Back/forward navigate within the focused pane's history. Up navigates to parent directory.

**Keyboard:** Cmd-[ for back, Cmd-] for forward, Cmd-Up for up. Cmd-L focuses path breadcrumb input. Cmd-F focuses search.

---

### Path Breadcrumb

**Purpose:** Displays current folder path as clickable segments; switches to editable text input on Cmd-L.

**Visual:** Segments separated by `›` (chevron.right SF Symbol, 9pt, `tertiaryLabelColor`). Each segment is the folder name in 13pt SF Pro Text. Overflow at left: leading segments clip with a `…` ellipsis, rightmost (current) folder always visible. When in edit mode: text field replaces the breadcrumb display, pre-filled with absolute POSIX path.

**States:**
- Default: segments, read-only, `labelColor`
- Hover on segment: segment background fills with `quaternaryLabelColor` (subtle hover)
- Edit mode (Cmd-L): text field with system focus ring, cursor at end
- Error (typed path doesn't exist): text field border turns `systemRed`, error tooltip on Tab/Return
- Loading: rightmost segment shows inline spinner (12pt `NSProgressIndicator`)

**Behavior:** Click any segment to navigate focused pane to that folder. Cmd-L / click on trailing empty area activates edit mode. Return confirms; Esc cancels (restores previous display). Tab autocompletes path segments (like Terminal's Tab completion).

**Keyboard:** Cmd-L enter edit, Return confirm, Esc cancel, Tab autocomplete.

---

### Sidebar Tree

**Purpose:** Persistent left-panel folder tree — Favorites, Volumes, Tags — for one-click navigation to any pane.

**Visual:** 220pt default width (resizable). `.underWindowBackground` NSVisualEffectView material. Section headers: 11pt SF Pro Text bold uppercase, `tertiaryLabelColor`, 8pt top padding. Items: 24pt row height, `sidebar.left` icon area 16pt, 13pt SF Pro Text. Disclosure triangles: `chevron.right` / `chevron.down`, 10pt, `tertiaryLabelColor`. Indentation: 16pt per level.

**Sections:**
1. FAVORITES — user-curated folders. Draggable to reorder. Each item has a system file icon from `NSWorkspace`.
2. VOLUMES — mounted volumes from `FileManager.mountedVolumeURLs`. Eject button on hover for removable volumes.
3. TAGS — macOS Finder tags from `NSMetadataQuery`. Color dot (12pt) + tag name.

**States:**
- Default: item shows icon + name
- Hover: `quaternaryLabelColor` row background, eject icon appears (volumes only)
- Selected / navigated: `systemAccentColor` tint on icon, `labelColor` text, full-width highlight at `quaternaryLabelColor` (not full accent — sidebar items are navigation targets, not selection objects)
- Drag (favorites): item lifts with 1pt shadow; drop indicator line between items
- Drag target (folder being hovered): `systemAccentColor` border 1pt around the item
- Collapsed sidebar: completely hidden; 0pt width; divider handle appears at window left edge on hover

**Behavior:** Single click navigates focused pane. Cmd-click opens the folder in a new tab in the focused pane. Drag a folder from Finder onto the FAVORITES section to add a bookmark. Drag to reorder within FAVORITES. "+" button at section header adds current folder as favorite. Collapse: click the sidebar toggle button in toolbar, or drag divider to 0pt.

**Keyboard:** Sidebar focus via Cmd-Option-S (toggle). Arrow keys navigate items. Return navigates focused pane to selected item. Delete removes from Favorites (with undo).

---

### Pane Container

**Purpose:** Individual browsing unit — one folder, one view, its own tabs and history.

**Visual:** Fills its grid cell. Contains a tab bar at top, then a column-header row, then the file list. Focused pane: 2pt `systemAccentColor` border on all four sides. Unfocused pane: no border. Header strip (beneath tab bar): 13pt SF Pro Text, folder name in `labelColor`, entry count in `secondaryLabelColor`, e.g. "Downloads  —  7 items".

**States:**
- Focused: 2pt `systemAccentColor` border
- Unfocused: no border (border area is transparent / background blends to normal)
- Loading: spinner in header strip
- Empty: empty folder placeholder inside content area
- Error (TCC / unmounted): error placeholder inside content area
- Drag target (file being dragged in from another pane): `systemAccentColor` border brightens + subtle `quaternaryLabelColor` fill over content area

**Behavior:** Click anywhere in pane to focus it. Focused pane receives keyboard input.

**Keyboard:** Cmd-1/2/3/4 focus panes by index. Tab cycles focus forward. Shift-Tab cycles backward.

---

### File List Row

**Purpose:** Single file entry — icon, name, size, date modified, kind.

**Visual:** 22pt row height. Leading: 16pt system file icon (`NSWorkspace.shared.icon(forFile:)`). Then name (SF Pro Text 13pt regular, `labelColor`). Trailing columns: Size (13pt, `secondaryLabelColor`, right-aligned), Date Modified (13pt, `secondaryLabelColor`), Kind (13pt, `secondaryLabelColor`). Hidden files: entire row at 60% opacity. Symlinks: name in `secondaryLabelColor` with `→` alias badge.

**States:**
- Default: standard background (`windowBackgroundColor`)
- Hover: `quaternaryLabelColor` background
- Selected (focused pane): `systemAccentColor` background, all text `white` / `labelColor` on light backgrounds
- Selected (unfocused pane): `quaternaryLabelColor` background, text colors unchanged
- Drag source: row shows at 70% opacity while drag is in progress elsewhere
- iCloud (not downloaded): row at 70% opacity, `⬇` icon trailing, size shows "—"
- Renamed (in-place edit): name column switches to editable text field in-place

**Behavior:** Single click selects. Double click opens (default app for files; navigates for folders). Return opens selected item. Cmd-click adds to selection. Shift-click range-selects. Right-click shows context menu. Rubber band drag (click-drag on empty area) creates a selection rectangle.

**Keyboard:** Up/Down arrows move selection. Enter opens. Cmd-Up navigates to parent. Space triggers QuickLook on focused pane's selection. F2 or Return on already-selected item enters rename mode. Cmd-A selects all. Cmd-Shift-. toggles hidden files.

---

### Sort Header

**Purpose:** Column header that acts as a sort control.

**Visual:** 22pt height. SF Pro Text 11pt medium, `secondaryLabelColor`. Active sort column: `labelColor` + `chevron.up` or `chevron.down` SF Symbol (10pt) to the right of the label. Column headers: Name | Date Modified | Size | Kind. Drag handle at right edge of each column for resizing (appears as a 1pt separator on hover).

**States:**
- Default: 11pt secondary label, no chevron
- Active ascending: chevron.up visible, `labelColor`
- Active descending: chevron.down visible, `labelColor`
- Hover: background `quaternaryLabelColor`
- Resize hover: right edge shows 3pt-wide drag handle in `separatorColor`
- Drag: cursor changes to `resizeLeftRight`

**Behavior:** Click column header to sort by that column ascending; click again to reverse. Drag right edge of column header to resize. Column widths persist per folder (see parent plan).

**Keyboard:** Tab between column headers when sort header area is focused.

---

### Selection

**Purpose:** Single and multi-item selection within a pane.

**Visual:** Selected rows show `systemAccentColor` fill when pane is focused; `quaternaryLabelColor` fill when pane is unfocused. Rubber band (drag-select) shows a semi-transparent `systemAccentColor` rectangle with 1pt border.

**States:**
- No selection: all rows default
- Single selection: one row highlighted
- Multi selection (contiguous): range highlighted
- Multi selection (discontiguous): multiple rows highlighted
- Rubber band: selection rectangle drawn over rows

**Behavior:** Click: single select. Cmd-Click: toggle item in selection. Shift-Click: extend range. Drag on empty area: rubber band. Cmd-A: select all. Click on empty area: deselect all.

**Keyboard:** Arrow keys move single selection. Shift-Arrow extends range. Cmd-A selects all. Escape deselects all.

---

### Context Menu

**Purpose:** Right-click contextual actions for selected files.

**Visual:** System NSMenu appearance (native context menu). Items in 13pt SF Pro Text. Destructive items (Move to Trash) in `systemRed`. Menu sections separated by NSMenuItem separators.

**Items:**
1. Open (default app)
2. Open With > [submenu with app list]
3. --- separator ---
4. Move to Trash
5. --- separator ---
6. Get Info
7. Quick Look (same as spacebar)
8. --- separator ---
9. Copy
10. Paste (enabled when clipboard has files)
11. Duplicate
12. --- separator ---
13. Rename…
14. Compress (creates .zip)
15. --- separator ---
16. Reveal in Finder (Cmd-Shift-R)
17. Copy as Pathname
18. --- separator ---
19. Tags > [system tag picker]

**Behavior:** Right-click on any row. If item clicked is outside current selection, replaces selection with that item. If inside multi-selection, menu acts on the full selection. "Move to Trash" has no confirmation; undo available via Cmd-Z (standard macOS undo).

**Keyboard:** Cmd-Delete moves to Trash. Cmd-C copies. Cmd-V pastes. Cmd-D duplicates.

---

### Status Bar

**Purpose:** Bottom bar summarizing selection state and disk info.

**Visual:** 24pt height. `windowBackgroundColor` background (no vibrancy). Left-aligned text: "N items" or "N selected  •  X MB" when selection exists. Right-aligned: "X GB free". All text 11pt SF Pro Text regular, `secondaryLabelColor`. 1pt `separatorColor` top border.

**States:**
- No selection: "N items  •  X GB free"
- With selection: "N selected  •  total size  •  X GB free"
- Loading: "Loading…  •  N items so far  •  X GB free"
- Permission denied: "Permission denied  •  X GB free"
- Empty folder: "0 items  •  X GB free"

**Behavior:** Read-only. Updates live as selection changes. "N items" counts visible entries (hidden files excluded unless show-hidden is on).

**Keyboard:** None (informational only).

---

### Preview Pane

**Purpose:** Inline file preview inside the pane, shown when a single file is selected and preview mode is active.

**Visual:** Right split of the pane; default 40% of pane width. Contains:
- Image: `NSImageView` with aspect-fit scaling. Zoom controls: `minus` / `plus` SF Symbols + percentage label, pinned to bottom of preview area.
- Video/Audio/PDF/Other: `QLPreviewView` fills the preview area. System QuickLook chrome (play/pause, scrubber) renders natively.
- No selection / multiple selection: centered `eye.slash` SF Symbol + "Select one item to preview" message in `secondaryLabelColor`.
- Unsupported type: centered `questionmark.square.dashed` SF Symbol + "No Preview Available" + "Open in Default App" button.

**States:**
- Collapsed: preview divider is at right edge; only file list visible; a `sidebar.right` icon on the toolbar edge to expand
- Expanded - empty: placeholder message
- Expanded - image: image with zoom controls
- Expanded - video: QLPreviewView with player controls
- Expanded - loading: spinner while QuickLook loads
- Expanded - error: "No Preview Available" placeholder

**Behavior:** Click file in list to update preview (no double-click needed). Pinch gesture (trackpad) zooms image. Two-finger pan pans image. Double-click-to-zoom resets zoom to fit. Drag preview divider to resize. Double-click divider resets to 40% default.

**Keyboard:** Cmd-Option-P toggles preview mode. +/- zooms image. Cmd-0 resets image zoom to fit.

---

### Tab Bar (per pane)

**Purpose:** Multiple folder tabs within a single pane, similar to browser tabs.

**Visual:** 28pt height above file list. Flat tab style (no chunky borders). Each tab: folder icon (12pt `NSWorkspace` icon), folder name (13pt SF Pro Text), close button (`xmark` SF Symbol, appears on hover of the specific tab, or when tab is active). Active tab: `labelColor` text. Inactive tabs: `secondaryLabelColor` text. "+" button at right edge of tab bar adds a new tab.

**States:**
- Single tab: tab still visible (always show tab bar)
- Multiple tabs: all visible; overflow: tabs compress to minimum (icon only) before scrolling
- Active: text `labelColor`, slightly lighter background
- Inactive: text `secondaryLabelColor`, no background differentiation
- Hover: close button (`xmark`) appears at 10pt
- Drag: tab lifts slightly, can drag to reorder within pane or drag to a different pane's tab bar

**Behavior:** Cmd-T opens new tab in focused pane (inherits current folder). Cmd-W closes active tab; if last tab, does not close the pane (pane shows empty state). Click tab to switch. Drag to reorder tabs. Drag a tab to another pane's tab bar to move it there.

**Keyboard:** Cmd-T new tab. Cmd-W close active tab. Cmd-Shift-[ previous tab. Cmd-Shift-] next tab.

---

### Layout Switcher

**Purpose:** Toolbar control to switch between 1, 2, 3, and 4 pane layouts.

**Visual:** NSSegmentedControl in the toolbar with 4 segments. Each segment uses an SF Symbol:
1. `square` — single pane
2. `square.split.2x1` — two panes horizontal
3. `square.split.1x2` — two panes vertical (three-pane is a 1+2 arrangement)
4. `square.split.2x2` — four panes (2×2 grid)

Active segment is selected/highlighted. 32pt total control width.

**States:**
- Segment default: unselected, `secondaryLabelColor` icon
- Segment selected: system accent tint
- Segment hover: `quaternaryLabelColor` background
- Disabled: n/a (all layouts always available)

**Behavior:** Click segment to switch layout. Switching from 1→2 splits current pane (right pane opens at same folder). Switching from 4→1 keeps focused pane, discards others (after a confirmation if other panes have unsaved tab states). Pane layout per window is persisted.

**Keyboard:** Cmd-Option-1/2/3/4 for layout switch.

---

### Permission Required Affordance

**Purpose:** Full-pane placeholder shown when TCC denies folder access.

**Visual:** Centered vertically and horizontally in the pane. `lock.fill` SF Symbol at 48pt, `tertiaryLabelColor`. Headline: "Permission Required", 15pt semibold `labelColor`. Body: "mq-dir cannot access [folder name]. Grant access to browse files here.", 13pt `secondaryLabelColor`, max-width 280pt, center-aligned. "Open System Settings…" button (system default button style) 8pt below body.

**States:**
- Default: as above
- Button hover: standard button hover state

**Behavior:** "Open System Settings…" calls `NSWorkspace.shared.open` with deep link URL `x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders`. After user grants access and returns to mq-dir, pane auto-retries enumeration (triggered by `NSApplicationDidBecomeActiveNotification`).

**Keyboard:** Tab focuses "Open System Settings…" button. Return activates it.

---

### Download Affordance (.icloud placeholder)

**Purpose:** Inline row affordance to trigger iCloud download for not-yet-downloaded files.

**Visual:** `arrow.down.circle` SF Symbol (14pt, `systemAccentColor`) appears at the leading-right of the row, after the file name. During download: symbol animates to circular progress indicator (12pt `NSProgressIndicator` circular style). On completion: affordance disappears, row transitions to normal appearance.

**States:**
- Not downloaded: `arrow.down.circle` icon visible, row text at 70% opacity
- Downloading (0–99%): `NSProgressIndicator` circular, row text at 70% opacity
- Downloaded: icon gone, row fully opaque, normal appearance

**Behavior:** Click the download icon (or click anywhere on the row) to trigger download. No confirmation. Download runs in background; user can continue browsing. Multiple concurrent downloads supported.

**Keyboard:** Return on a selected placeholder row triggers download (rather than "open").

---

### Empty Folder Placeholder

**Purpose:** Indicates a directory with zero entries (genuinely empty, not denied).

**Visual:** Centered in pane content area. `folder.fill` SF Symbol at 36pt, `tertiaryLabelColor`. Text: "Empty Folder", 13pt `secondaryLabelColor`. No action button.

**States:**
- Default: icon + text, no interaction

**Behavior:** Read-only. If FSEvents fires while placeholder is shown (e.g. a file is created in the folder externally), the pane re-enumerates and updates within 100ms debounce.

**Keyboard:** None.

---

### Loading Spinner

**Purpose:** Signals that directory enumeration is in progress and results are streaming.

**Visual:** Appears in the status bar after 500ms of enumeration without completion — a 16pt `NSProgressIndicator` (spinning indeterminate) followed by "Loading…  N items so far". Skeleton placeholder rows (solid `quaternaryLabelColor` fills with no text) fill visible empty rows below the streamed results.

**States:**
- Not triggered (<500ms): no spinner, no skeleton
- Triggered (>500ms): spinner + status text + skeleton rows
- Streaming: real rows appear above skeleton rows as batches arrive; skeleton count decreases
- Complete: spinner and skeletons disappear in a single no-animation swap

**Behavior:** Purely informational. Does not block interaction with already-loaded rows. User can click, sort, and even navigate away while loading is in progress (navigation cancels the current enumeration task).

**Keyboard:** None.

---

### Toast (non-blocking error notification)

**Purpose:** Ephemeral non-blocking notification for recoverable errors (e.g., permission denied on a single subfolder during enumeration).

**Visual:** 340pt wide, 44pt tall, bottom-center of the window above the status bar, 12pt inset. `controlBackgroundColor` fill, 6pt corner radius, 1pt `separatorColor` border, subtle shadow. Left icon: `exclamationmark.triangle.fill` (14pt, `systemYellowColor`). Text: 13pt SF Pro Text regular `labelColor`. Right: "Dismiss" link in `systemAccentColor`. Auto-dismisses after 5 seconds.

**States:**
- Appearing: 150ms ease-out slide up from status bar + fade in
- Visible: static
- Dismissing (auto or click): 150ms fade out
- Stacked (multiple errors): toasts queue; second appears only after first dismisses

**Behavior:** "Dismiss" click or 5s timeout hides the toast. If Reduce Motion is on, toast appears/disappears instantly (no slide/fade).

**Keyboard:** Esc dismisses focused toast. Toasts do not steal keyboard focus.

---

## 6. Interaction Specs

### 1. Switching from 1-pane to 4-pane layout

1. User clicks `square.split.2x2` segment in layout switcher (or presses Cmd-Option-4).
2. Current pane (Pane 1) snaps to top-left quadrant. Three new pane containers appear — top-right (Pane 2), bottom-left (Pane 3), bottom-right (Pane 4).
3. New panes open at the same folder as Pane 1 (not empty state). Each new pane gets a single tab with that folder.
4. Animation: none (instant snap). No spring, no morph. The layout grid redraws synchronously.
5. Focus remains on Pane 1 (2pt border visible immediately at its new smaller size).
6. Layout is persisted immediately: saved as the window's `paneLayout` in critical state (synchronous write).
7. Per-window memory: if the user had previously used 4-pane on this window, panes 2–4 restore to their last folders (if available in persistence); otherwise they open at the same folder as Pane 1.

### 2. Opening a tab in a specific pane

1. User presses Cmd-T while Pane 2 is focused (2pt border visible on Pane 2).
2. A new tab appears in Pane 2's tab bar, immediately to the right of the active tab.
3. The new tab inherits the active tab's current folder (not root, not home — the same folder the user is in).
4. The new tab becomes active: tab bar highlights new tab, file list for that folder renders within 100ms.
5. Animation: new tab slides in from right in Pane 2's tab bar (150ms ease-out). File list fades in (100ms).
6. Cmd-W closes active tab. If only one tab remains, the tab bar stays visible (single-tab mode), and the tab cannot be closed (close button disabled at one tab).

### 3. Dragging a file from Pane A to Pane B

1. User clicks and begins dragging on a file row in Pane A (focused, 2pt border).
2. After ~4pt drag threshold: drag session starts. The dragged row(s) become a ghost image (native NSImage drag pasteboard representation) at 70% opacity, offset 8pt from cursor.
3. Source row(s) in Pane A dim to 50% opacity (remain in place — not removed yet).
4. As cursor enters Pane B: Pane B shows a 2pt `systemAccentColor` drop indicator border (distinct from focus border — slightly pulsed/brighter). A horizontal insertion line appears between rows at the drop position.
5. Modifier keys:
   - No modifier: **move** (files removed from source folder, added to target)
   - Option held: **copy** (badge appears on ghost: `plus` circle). Source rows stay at full opacity.
   - Cmd held: **create alias**. (Badge: `arrow.turn.down.right` circle.)
6. Drop: files are moved/copied/aliased. Pane A and Pane B both refresh via FSEvents (within 100ms debounce).
7. If the drop fails (permission error): toast notification: "Cannot move [filename] — permission denied."
8. Undo: Cmd-Z undoes the move/copy (implemented via `NSUndoManager`).

### 4. Spacebar QuickLook

1. User selects one or more files in the focused pane.
2. User presses Spacebar.
3. Focused pane identity is read from `WindowViewModel.focusedPaneIndex` (not AppKit first-responder — the model is authoritative).
4. Visual feedback: selected row(s) briefly flash `systemAccentColor` at 30% opacity (1 frame highlight — ~16ms), communicating which pane's selection is being previewed.
5. `QLPreviewPanel.shared().makeKeyAndOrderFront(nil)` is called with the focused pane's selected URLs.
6. Subsequent arrow key presses while QuickLook is open navigate through the focused pane's file list (not keyboard focus trapping in the panel).
7. Second Spacebar press or Esc dismisses QuickLook.
8. Under VoiceOver: Spacebar still triggers QuickLook (does not get intercepted). VoiceOver announces "Quick Look open."

### 5. Resizing a column

1. User hovers over the right edge of a column header.
2. Cursor changes to `resizeLeftRight` (←|→).
3. A 3pt drag handle appears as a highlighted region at the column boundary.
4. User click-drags to resize. Column width updates live as the drag moves (not deferred to drop).
5. Minimum column width: 40pt (enforced by drag clamping).
6. Snap-to-content: double-click the right edge of the column header to snap to the widest visible entry's text width + 8pt padding.
7. Column widths are persisted with a 500ms debounce (soft state) after drag ends.

### 6. Resizing sidebar / pane divider

1. User hovers over the divider between sidebar and pane area (or between panes).
2. Cursor changes to `resizeLeftRight` (or `resizeUpDown` for horizontal pane dividers).
3. Drag handle highlights: 4pt-wide region centered on the 1pt separator, `separatorColor` tint.
4. User drags to resize. Both panels resize live.
5. Sidebar minimum width: 160pt. Maximum: 360pt. Pane minimum: 240pt.
6. Double-click the sidebar/pane divider resets to 50/50 split (for panes) or 220pt (for sidebar).
7. Dragging sidebar divider to 0pt collapses the sidebar (equivalent to the sidebar toggle button). A subtle 200ms ease-out collapse animation plays (unless Reduce Motion is on — instant collapse).

### 7. Reveal in Finder (Cmd-Shift-R)

1. User selects a file row and presses Cmd-Shift-R (or chooses "Reveal in Finder" from context menu).
2. The selected row in mq-dir briefly flashes with a `systemAccentColor` tint (150ms fade in + out) — a "pulse" that says "yes, this one."
3. `NSWorkspace.shared.activateFileViewerSelecting([url])` is called.
4. Finder activates and scrolls to the file, selecting it.
5. mq-dir window does not lose focus until Finder takes it (system-standard behavior).

### 8. Switching view mode (list / icon / column / gallery)

1. View mode switcher (a secondary toolbar control, M2+) shows four segments: `list.bullet`, `square.grid.2x2`, `rectangle.split.3x1`, `rectangle.grid.1x2`.
2. User clicks a segment.
3. File list area re-renders in the new mode. No animation (instant swap).
4. View mode is saved to the current folder's `FolderPrefs` as critical state (immediate synchronous write).
5. Navigating to a different folder loads that folder's persisted view mode automatically.
6. List view is available from M1. Icon, column, gallery views are M2+.

### 9. TCC denial flow

1. User navigates to `~/Documents` (first time, TCC not yet granted).
2. macOS may show a TCC prompt ("mq-dir wants to access your Documents folder" → allow/deny). If allowed: enumerate normally.
3. If denied (or silently denied — `contentsOfDirectory` returns `[]` in a TCC-protected zone): pane shows **Permission Required** affordance.
4. User clicks "Open System Settings…": `x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders` deep link opens System Settings.
5. User toggles mq-dir on in the Files and Folders list.
6. User returns to mq-dir: `NSApplicationDidBecomeActiveNotification` fires.
7. mq-dir re-runs enumeration for any pane currently showing the Permission Required affordance.
8. If now granted: folder lists normally. Permission Required affordance replaced by file list (no animation — instant).
9. If still denied: affordance remains.

---

## 7. Visual Design Tokens

### Colors (semantic, NSColor names)

| Token | Light Mode | Dark Mode |
|---|---|---|
| `background.window` | `NSColor.windowBackgroundColor` | `NSColor.windowBackgroundColor` |
| `background.sidebar` | `.underWindowBackground` vibrancy | `.underWindowBackground` vibrancy |
| `background.pane.focused` | `NSColor.windowBackgroundColor` | `NSColor.windowBackgroundColor` |
| `background.pane.unfocused` | `NSColor.windowBackgroundColor` | `NSColor.windowBackgroundColor` |
| `background.row.hover` | `NSColor.quaternaryLabelColor` | `NSColor.quaternaryLabelColor` |
| `background.row.selected.focused` | `NSColor.controlAccentColor` | `NSColor.controlAccentColor` |
| `background.row.selected.unfocused` | `NSColor.quaternaryLabelColor` | `NSColor.quaternaryLabelColor` |
| `text.primary` | `NSColor.labelColor` | `NSColor.labelColor` |
| `text.secondary` | `NSColor.secondaryLabelColor` | `NSColor.secondaryLabelColor` |
| `text.tertiary` | `NSColor.tertiaryLabelColor` | `NSColor.tertiaryLabelColor` |
| `separator` | `NSColor.separatorColor` | `NSColor.separatorColor` |
| `accent` | `NSColor.controlAccentColor` | `NSColor.controlAccentColor` |
| `border.focus` | `NSColor.controlAccentColor` | `NSColor.controlAccentColor` |
| `icon.tint` | `NSColor.controlAccentColor` | `NSColor.controlAccentColor` |
| `destructive` | `NSColor.systemRed` | `NSColor.systemRed` |

Notes: All colors use system dynamic values — no hardcoded hex. The app inherits the user's chosen system accent color. No custom brand color override in v1. Vibrancy materials are disabled when "Reduce Transparency" is on (system handles this automatically via `NSVisualEffectView`).

### Typography

| Role | Font | Size | Weight | Color |
|---|---|---|---|---|
| App body / file list | SF Pro Text | 13pt | Regular | `labelColor` |
| File name (list) | SF Pro Text | 13pt | Regular | `labelColor` |
| File metadata (size, date, kind) | SF Pro Text | 13pt | Regular | `secondaryLabelColor` |
| Sidebar section headers | SF Pro Text | 11pt | Bold | `tertiaryLabelColor` |
| Sidebar item labels | SF Pro Text | 13pt | Regular | `labelColor` |
| Tab labels | SF Pro Text | 13pt | Regular | `labelColor` / `secondaryLabelColor` |
| Column headers | SF Pro Text | 11pt | Medium | `secondaryLabelColor` |
| Path breadcrumb | SF Pro Text | 13pt | Regular | `labelColor` |
| Status bar | SF Pro Text | 11pt | Regular | `secondaryLabelColor` |
| Empty/error headlines | SF Pro Text | 15pt | Semibold | `labelColor` |
| Empty/error body | SF Pro Text | 13pt | Regular | `secondaryLabelColor` |
| Toast text | SF Pro Text | 13pt | Regular | `labelColor` |

Note: All typography is SF Pro Text (the body-text variant) — not SF Pro Display, not SF Mono, not any external web font. This matches native macOS system UI exactly.

### Spacing

| Element | Value |
|---|---|
| File list row height | 22pt |
| Row horizontal padding | 8pt |
| Leading icon width | 16pt |
| Icon-to-label gap | 6pt |
| Toolbar height | 38pt |
| Status bar height | 24pt |
| Sidebar item height | 24pt |
| Sidebar section header top padding | 8pt |
| Tab bar height | 28pt |
| Column header height | 22pt |
| Pane focus border thickness | 2pt |
| Divider / separator thickness | 1pt |
| Preview divider thickness | 1pt |
| Sidebar default width | 220pt |
| Preview pane default width | 40% of pane width |
| Pane minimum width | 240pt |
| Sidebar minimum width | 160pt |
| Toast width | 340pt |
| Toast height | 44pt |
| Toast bottom inset | 12pt |

### Iconography (SF Symbols)

| Context | Symbol name |
|---|---|
| Back navigation | `chevron.left` |
| Forward navigation | `chevron.right` |
| Up (parent folder) | `chevron.up` |
| Disclosure triangle (collapsed) | `chevron.right` |
| Disclosure triangle (expanded) | `chevron.down` |
| Search | `magnifyingglass` |
| Single pane layout | `square` |
| Two-pane horizontal | `square.split.2x1` |
| Two-pane vertical | `square.split.1x2` |
| Four-pane grid | `square.split.2x2` |
| Preview toggle | `sidebar.right` |
| Sidebar toggle | `sidebar.left` |
| List view mode | `list.bullet` |
| Icon view mode | `square.grid.2x2` |
| Column view mode | `rectangle.split.3x1` |
| Gallery view mode | `rectangle.grid.1x2` |
| Sort ascending | `chevron.up` |
| Sort descending | `chevron.down` |
| New tab | `plus` |
| Close tab | `xmark` |
| iCloud not downloaded | `arrow.down.circle` |
| iCloud downloading | `arrow.down.circle.fill` (with progress) |
| TCC permission denied | `lock.fill` |
| Empty folder | `folder.fill` |
| Empty pane (no folder) | `folder` |
| No preview available | `questionmark.square.dashed` |
| Preview hidden (no selection) | `eye.slash` |
| Error / warning toast | `exclamationmark.triangle.fill` |
| Move to Trash (context menu) | `trash` |
| Get Info (context menu) | `info.circle` |
| Reveal in Finder | `magnifyingglass.circle` |
| Copy pathname | `doc.on.clipboard` |
| Eject volume | `eject` |
| Tag (colored) | `circle.fill` (tinted per tag color) |
| Add bookmark | `plus.circle` |
| Alias badge | `arrow.turn.down.right` |
| Copy drag badge | `plus` (in a circle badge) |
| Zoom in (preview) | `plus.magnifyingglass` |
| Zoom out (preview) | `minus.magnifyingglass` |
| Zoom reset (preview) | `arrow.up.left.and.arrow.down.right` |

File icons: all via `NSWorkspace.shared.icon(forFile:)` — system-rendered, no custom icons.

### Materials

| Surface | NSVisualEffectView Material |
|---|---|
| Sidebar | `.underWindowBackground` |
| Toolbar | `.headerView` |
| Window content area | Standard `NSWindow` background (no vibrancy) |
| Context menu | System-managed (NSMenu) |
| Toast | `NSColor.controlBackgroundColor` (solid; no vibrancy for readability) |

When "Reduce Transparency" is on: `NSVisualEffectView` materials automatically fall back to opaque equivalents (system-handled). No custom override needed.

### Motion

| Transition | Duration | Easing | Reduce Motion |
|---|---|---|---|
| Tab open | 150ms | ease-out | instant |
| Tab close | 150ms | ease-out | instant |
| Sidebar collapse | 200ms | ease-out | instant |
| Sidebar expand | 200ms | ease-out | instant |
| Toast appear | 150ms | ease-out (slide up + fade) | instant (no slide) |
| Toast dismiss | 150ms | ease-out (fade only) | instant |
| iCloud row resolved | 100ms | cross-dissolve | instant |
| Pane focus border | instant | — | instant |
| Layout switch (1→4 pane) | instant | — | instant |
| Drag ghost appear | instant | — | instant |
| Row selection | instant | — | instant |
| Skeleton → real rows | instant swap | — | instant |

Rule: **never bounce, never spring, never exceed 200ms.** Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — when true, all durations become 0ms.

---

## 8. Keyboard Reference

### Navigation

| Shortcut | Action |
|---|---|
| Cmd-[ | Back (previous folder in pane history) |
| Cmd-] | Forward (next folder in pane history) |
| Cmd-Up | Navigate to parent folder |
| Return | Open selected item (navigate into folder; open file in default app) |
| Double-click | Same as Return |
| Cmd-L | Focus path breadcrumb input |
| Cmd-F | Focus search field |
| Esc (in search) | Cancel search, restore file list |
| Up / Down arrows | Move file list selection |
| Shift-Up / Shift-Down | Extend selection |
| Cmd-A | Select all items |
| Esc (in list) | Deselect all |

### View

| Shortcut | Action |
|---|---|
| Cmd-1 (view mode) | List view |
| Cmd-2 | Icon grid view (M2+) |
| Cmd-3 | Column view (M2+) |
| Cmd-4 | Gallery view (M2+) |
| Cmd-Shift-. | Toggle hidden files |
| Cmd-Option-P | Toggle preview pane |
| Cmd-Option-S | Toggle sidebar |
| Space | QuickLook selection in focused pane |

### File

| Shortcut | Action |
|---|---|
| Cmd-Delete | Move to Trash |
| Cmd-C | Copy |
| Cmd-V | Paste |
| Cmd-D | Duplicate |
| F2 | Rename (enter rename mode on selected row) |
| Cmd-I | Get Info |
| Cmd-Shift-R | Reveal in Finder |
| Enter (on iCloud placeholder) | Trigger iCloud download |

### Pane

| Shortcut | Action |
|---|---|
| Cmd-1 | Focus Pane 1 |
| Cmd-2 | Focus Pane 2 |
| Cmd-3 | Focus Pane 3 |
| Cmd-4 | Focus Pane 4 |
| Tab | Cycle focus to next pane |
| Shift-Tab | Cycle focus to previous pane |
| Cmd-Option-1 | Switch to 1-pane layout |
| Cmd-Option-2 | Switch to 2-pane layout |
| Cmd-Option-3 | Switch to 3-pane layout |
| Cmd-Option-4 | Switch to 4-pane layout |

### Tab

| Shortcut | Action |
|---|---|
| Cmd-T | New tab in focused pane |
| Cmd-W | Close active tab in focused pane |
| Cmd-Shift-[ | Select previous tab |
| Cmd-Shift-] | Select next tab |

### Window

| Shortcut | Action |
|---|---|
| Cmd-N | New window |
| Cmd-M | Minimize window |
| Cmd-Ctrl-F | Toggle full screen |
| Cmd-Q | Quit |

### Help

| Shortcut | Action |
|---|---|
| Cmd-? | Open Help (placeholder for v1) |
| Cmd-Shift-/ | Same as Cmd-? |

---

## 9. Accessibility Specs

### VoiceOver

- **File list row read order:** `<file name>, <kind>, <size>, modified <date>`. Example: "report.pdf, PDF Document, 320 kilobytes, modified April 29, 2026." No icon description unless icon conveys unique information.
- **Column headers:** announced with sort direction. Example: "Date Modified, sorted descending, column header."
- **Pane focus:** when focus changes between panes, VoiceOver announces: "Pane 2, Downloads, 7 items."
- **Sidebar items:** "Desktop, Favorites." (Section header reads as a group header, not interactive.)
- **Tabs:** "Downloads tab, selected." "Documents tab." Tab bar role: `NSAccessibilityTabGroup`.
- **iCloud row:** "report-draft.pages, Pages document, not downloaded. Press Return to download."
- **TCC placeholder:** "Permission required. mq-dir cannot access the Documents folder. Open System Settings button."
- **Toast:** announced via `NSAccessibility.post(element:notification:)` with `NSAccessibilityAnnouncement` when toast appears.
- **Spacebar under VoiceOver:** VoiceOver intercepts Space for "read current item" — mq-dir must handle this by routing through the menu item action (`Quick Look`) so VoiceOver's Space intercept does not conflict. Alternatively: provide a `Cmd-Y` Quick Look shortcut that VoiceOver does not intercept.

### Keyboard Navigation

- Every interactive element is Tab-navigable.
- No mouse-only actions.
- Focus indicators always visible (never hidden on non-keyboard interaction in macOS).
- Focus moves predictably: toolbar → sidebar → pane area → status bar. Shift-Tab reverses.

### Contrast & Color

- All text meets WCAG AA minimum: 4.5:1 for body text (13pt), 3:1 for large text (18pt+).
- File list uses `labelColor` / `secondaryLabelColor` — system colors guaranteed to meet contrast at all system appearance settings.
- Accent color is decorative only (focus border, selection background) — never the only way to convey meaning.
- iCloud placeholder conveyed by both icon AND text dimming (not icon alone).
- TCC denial conveyed by icon + headline + body text (not color alone).

### Reduce Transparency

- All `NSVisualEffectView` surfaces automatically fall back to opaque equivalents.
- Sidebar: `windowBackgroundColor` instead of `.underWindowBackground` vibrancy.
- Toolbar: `headerBackgroundColor` solid instead of `.headerView` material.

### Increase Contrast

- Focus border widens from 2pt to 3pt.
- `separatorColor` lines become 1.5pt.
- Selected row background: full `controlAccentColor` (no change needed; already opaque).
- System handles most of this automatically via `NSHighContrastColor` variants.

### Reduce Motion

- All `duration > 0` transitions set to `duration = 0`.
- Check: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- Listen for `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` to react at runtime.

---

## 10. Empty / Error / Edge States

| Trigger | UI Shown | Recovery Action |
|---|---|---|
| No folder open (cold launch, first time) | Empty pane with `folder` icon, "No Folder Open" headline, "Open Folder…" button, drag-here hint | Click "Open Folder…" or drag a folder onto the pane |
| TCC permission denied | `lock.fill` icon, "Permission Required" headline, body text, "Open System Settings…" button | Click button → grant in System Settings → return (app auto-retries) |
| Folder doesn't exist (unmounted volume or deleted path) | `questionmark.folder` icon, "Folder Not Found" headline, "The folder at [path] is no longer available.", "Open Different Folder…" button | Click "Open Different Folder…" to pick a new path; or reconnect the volume |
| Folder is empty | `folder.fill` icon, "Empty Folder" text (no button) | User action: add files, or navigate away |
| Loading slow directory (>500ms) | Skeleton rows in visible area, `NSProgressIndicator` in status bar, "Loading… N items so far" | Wait; or navigate away to cancel |
| File deleted while viewing (FSEvents fires) | Row disappears from list with no animation (instant); if that row was selected, selection moves to nearest row; toast: "1 item removed (externally)" | Undo not possible for external deletions; informational only |
| Cannot preview file (codec gap / QL failure) | Preview area shows `questionmark.square.dashed` icon, "No Preview Available", "Open in Default App" button | Click "Open in Default App" → `NSWorkspace.open` |
| iCloud file not downloaded | Placeholder row with `arrow.down.circle` icon, dimmed text, "—" size | Click row or icon to trigger download |
| Network volume timeout | `network.slash` icon (or `antenna.radiowaves.left.and.right.slash`), "Network Volume Unavailable" headline, "The volume [name] is not responding.", "Reconnect" (retries enumeration) and "Eject" buttons | Click "Reconnect" to retry; click "Eject" to unmount |
| Force-quit recovery (re-launch) | Window opens exactly where it was left: same folder(s), same pane layout, same sort, same scroll position, same tab(s). No "Recovered from crash" UI. The state just works. | No recovery action needed; this is the headline promise |

---

## 11. Out of Scope for this PRD

This document covers **UI only**. The following topics are intentionally omitted and live in the parent plan (`ralplan-mq-dir-v1.md`):

- FSEvents stream implementation, debounce strategy, batch sizes
- SQLite vs JSON persistence internals, `Codable` schema, migration functions
- `URLResourceKey` values (`documentIdentifierKey`, `volumeIdentifierKey`, `fileResourceIdentifierKey`)
- Security-scoped bookmark management (`BookmarkStore`)
- `NSTableView` autosave column widths implementation detail
- `QLPreviewPanel` vs `QLPreviewView` API distinction
- Concurrency model (`AsyncStream`, `@MainActor`, thumbnail cache)
- TCC Info.plist usage description keys
- `URLUbiquitousItemDownloadingStatusKey` polling implementation
- Build tooling (Xcode project, CI/CD, notarization)
- Distribution (Homebrew tap, GitHub Releases, Sparkle 2 key embedding)
- Milestone schedule (M0–M6), acceptance criteria, test suites
- Architecture module breakdown and file structure

---

## 12. Open Questions for the Designer

1. **Toolbar density: compact or spacious?**
   The current spec sets toolbar height at 38pt (standard macOS). A denser 32pt toolbar would feel more "pro tool" (like Xcode's toolbar). A more spacious 44pt would feel more approachable. Which direction aligns with the power-user intent?

2. **Show "Kind" column in list view by default?**
   Most users will rarely sort or filter by Kind. Hiding it by default (but showing it in a "Customize Columns" popover) gives more horizontal room to Name and Date. Or show it but make it the narrowest column. What's the default?

3. **System accent color vs fixed brand color for pane focus border?**
   Using `systemAccentColor` means the focus border matches the user's macOS accent (blue, orange, purple, etc.). Using a fixed brand color (a dark amber, a steel blue, a forest green) would give the app a consistent identity regardless of user settings. The native-macOS principle points toward system accent. Is there a case for a fixed identity color?

4. **Sidebar position: always left, or user-movable?**
   The spec fixes the sidebar on the left (matching Finder, VS Code, NetNewsWire). Some power users (especially ultra-wide monitor users) prefer right-side sidebars. Should sidebar position be a setting, or is left-always the right call for v1?

5. **Tab style: flat/Safari-style vs compact/dense?**
   Safari tabs are generously spaced and clearly legible. Xcode tabs are dense and favor horizontal density. For a file manager used all day with many tabs open, dense tabs (icon-only in overflow) may be preferable. What tab density feels right: Safari-style comfortable or Xcode-style dense?

6. **Four-pane at small window sizes?**
   At 1024pt wide, a 4-pane grid gives each pane only 512pt (minus sidebar). At 240pt minimum per pane that barely works. Should 4-pane be blocked below a minimum window width (e.g., auto-collapse to 2-pane if window is narrower than 960pt)? Or always allow 4-pane and let the user deal with cramped panes?
