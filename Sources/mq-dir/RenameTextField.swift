import SwiftUI
import AppKit

/// Finder-grade inline rename field, shared by both the list-mode
/// (`BrowserPaneView.FileEntryRow`) and tree-mode (`TreeFileListView.TreeRow`)
/// rows. Wraps an `NSTextField` directly instead of SwiftUI's `TextField`
/// because the rename interaction needs three behaviours SwiftUI's control
/// can't express cleanly:
///
/// 1. **Stem selection on begin** — Finder selects only the filename stem
///    ("report final" of "report final.pdf") when you start editing, leaving
///    the extension untouched. That requires reaching into the field editor's
///    `selectedRange`, which `TextField` doesn't expose.
/// 2. **Deterministic key routing** — Return commits, Esc cancels, Tab commits
///    (and optionally advances), arrows drive the caret and must NEVER leak to
///    the file list. `control(_:textView:doCommandBy:)` gives exact control;
///    `.onSubmit` / `.onExitCommand` race the pane's own key handlers.
/// 3. **Commit on focus loss** — clicking another row, the pane background,
///    another pane, or resigning key all commit the draft (Finder behaviour),
///    surfaced via `controlTextDidEndEditing`.
struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    /// Drives the stem-vs-whole-name selection split: directories (and
    /// dotfiles / extension-less names) select the whole name; files with a
    /// real extension select just the stem.
    let isDirectory: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void
    /// Tab / Shift-Tab. `forward == true` for Tab, `false` for Shift-Tab.
    /// The caller commits then optionally advances to the next/previous row.
    let onTab: (_ forward: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false      // SwiftUI chrome paints the surface
        field.focusRingType = .none        // accent ring is the focus cue
        field.font = NSFont.systemFont(ofSize: 13)   // matches Theme.Font.body
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping  // show long names fully while editing
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.allowsEditingTextAttributes = false
        field.maximumNumberOfLines = 1
        // Hug nothing — fill the available width the SwiftUI frame hands us.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Keep the AppKit value in sync with an external draft mutation (e.g.
        // a watcher-driven reload that preserves rename mode) WITHOUT clobbering
        // the user's in-progress typing: only overwrite when they genuinely
        // differ, and never while the field owns the field editor mid-edit.
        if field.stringValue != text, context.coordinator.editingText != text {
            field.stringValue = text
        }
        // One-shot deterministic first-responder + stem selection. We can't do
        // this in makeNSView (the view isn't in a window yet, so there's no
        // window to become first responder of). A single layout pass later the
        // field is mounted; `viewDidMoveToWindow` would be the AppKit-native
        // hook, but NSViewRepresentable owns the view's lifecycle and doesn't
        // forward it, so we drive focus from updateNSView guarded by a one-shot
        // flag. A single deferred hop is required: at the first updateNSView the
        // field is in the view tree but the window hasn't finished installing
        // the field editor for it, so `makeFirstResponder` succeeds but the
        // field editor's selectedRange isn't honoured until the next runloop
        // turn. One hop — not a retry loop — is enough and deterministic.
        if !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeFirstResponder(field)
                context.coordinator.selectStem(in: field)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: RenameTextField
        /// One-shot guard so focus + stem selection happen exactly once per
        /// mounted field, not on every updateNSView.
        var didFocus = false
        /// Set when WE initiate teardown via cancel, so the resulting
        /// `controlTextDidEndEditing` doesn't double-fire a commit after Esc.
        private var isCancelling = false
        /// Set when WE commit (Return / Tab), so the trailing end-editing
        /// notification doesn't fire a second commit.
        private var isCommitting = false
        /// Last text we observed in the field editor — lets updateNSView tell a
        /// live edit apart from an external draft change.
        var editingText: String

        init(_ parent: RenameTextField) {
            self.parent = parent
            self.editingText = parent.text
        }

        /// Select only the filename stem the way Finder does: the last "." with
        /// a non-empty extension on a non-directory splits stem from extension;
        /// directories, dotfiles (".gitignore"), and extension-less names select
        /// the whole string.
        func selectStem(in field: NSTextField) {
            guard let editor = field.currentEditor() else { return }
            let name = field.stringValue
            let stemLength = Self.stemSelectionLength(of: name, isDirectory: parent.isDirectory)
            editor.selectedRange = NSRange(location: 0, length: stemLength)
        }

        /// Number of leading characters Finder would pre-select for `name`.
        /// Whole name unless there's a real extension (a "." that is neither
        /// leading nor trailing) on a file. Uses NSString length so the
        /// `NSRange` we hand the field editor is in the same UTF-16 units.
        nonisolated static func stemSelectionLength(of name: String, isDirectory: Bool) -> Int {
            let ns = name as NSString
            guard !isDirectory else { return ns.length }
            let dotRange = ns.range(of: ".", options: .backwards)
            // No dot, leading dot (dotfile), or trailing dot → whole name.
            guard dotRange.location != NSNotFound,
                  dotRange.location > 0,
                  dotRange.location < ns.length - 1
            else { return ns.length }
            return dotRange.location
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            editingText = field.stringValue
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                commit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                cancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                isCommitting = true
                parent.text = textView.string
                parent.onTab(true)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                isCommitting = true
                parent.text = textView.string
                parent.onTab(false)
                return true
            case #selector(NSResponder.moveUp(_:)),
                 #selector(NSResponder.moveDown(_:)):
                // Let the field editor move the caret to start/end. Returning
                // false keeps the default behaviour and — critically — the
                // event never reaches the file list's onKeyPress handlers
                // because the NSTextField is first responder.
                return false
            default:
                return false
            }
        }

        /// Commit on focus loss: clicking another row, the pane background,
        /// switching panes, or the window resigning key all land here as an
        /// end-editing notification. Skip when WE already committed (Return /
        /// Tab) or are cancelling (Esc) so commit fires exactly once.
        func controlTextDidEndEditing(_ notification: Notification) {
            guard !isCommitting, !isCancelling else { return }
            if let field = notification.object as? NSTextField {
                parent.text = field.stringValue
            }
            parent.onCommit()
        }

        private func commit() {
            guard !isCommitting else { return }
            isCommitting = true
            parent.onCommit()
        }

        private func cancel() {
            guard !isCancelling else { return }
            isCancelling = true
            parent.onCancel()
        }
    }
}

/// SwiftUI chrome that wraps `RenameTextField` so the editing surface is
/// unmistakable and the two row views don't duplicate it: an opaque
/// `textBackgroundColor` rounded rect, a 2pt accent ring, and a soft outer
/// glow that reads on both light and dark.
struct RenameFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.Color.accent, lineWidth: 2)
            )
            .shadow(color: Theme.Color.accent.opacity(0.35), radius: 3)
    }
}

extension View {
    /// Apply the shared rename editing chrome (opaque surface + accent ring +
    /// glow) around a `RenameTextField`.
    func renameFieldChrome() -> some View {
        modifier(RenameFieldChrome())
    }
}
