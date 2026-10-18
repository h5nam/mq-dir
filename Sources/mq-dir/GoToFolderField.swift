import AppKit
import SwiftUI

/// What the toolbar's Go to Folder field opens with. A new request (new
/// `id`) re-seeds the field even while it is already showing.
struct GoToFolderRequest: Identifiable, Equatable {
    let id = UUID()
    var text: String
    /// Open already flagged — a ⌘V of a copied path that doesn't exist
    /// lands here so the user sees what was pasted and why nothing happened.
    var notFound = false
}

/// The breadcrumb's editing mode: type or paste a path, Return goes there.
///
/// Takes anything `PathInput.resolve` understands — quoted, shell-escaped,
/// `file://`, `~`, relative to the current folder, `:line:column` suffixes
/// — and a file path opens its folder with the file selected. While typing,
/// matching subfolders are listed below: ↑/↓ pick one, Tab completes like a
/// shell, ⌘Return opens the result in a new tab, Esc puts the breadcrumb back.
struct GoToFolderField: View {
    let request: GoToFolderRequest
    /// Folder that relative paths resolve against.
    let base: URL?
    let onGo: (_ resolution: PathInput.Resolution, _ newTab: Bool) -> Void
    /// Esc, or Return on an empty field.
    let onCancel: () -> Void
    /// The user clicked or tabbed somewhere else; that view keeps focus.
    let onFocusLost: () -> Void

    @State private var text: String
    @State private var notFound: Bool
    @State private var completions: [PathInput.Completion] = []
    /// The text `completions` were computed for. They load off the main
    /// actor, so a fast typist can be a keystroke ahead of the list.
    @State private var completionsText: String?
    @State private var highlighted: Int?
    /// False until the user types or presses Tab — the field opens on the
    /// current folder, and listing its siblings would cover the panes for
    /// no reason.
    @State private var edited = false

    init(
        request: GoToFolderRequest,
        base: URL?,
        onGo: @escaping (_ resolution: PathInput.Resolution, _ newTab: Bool) -> Void,
        onCancel: @escaping () -> Void,
        onFocusLost: @escaping () -> Void
    ) {
        self.request = request
        self.base = base
        self.onGo = onGo
        self.onCancel = onCancel
        self.onFocusLost = onFocusLost
        self._text = State(initialValue: request.text)
        self._notFound = State(initialValue: request.notFound)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.forward.circle")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Color.labelTertiary)
            PathTextField(
                text: $text,
                onSubmit: submit,
                onCancel: onCancel,
                onEndEditing: onFocusLost,
                onMove: moveHighlight,
                onComplete: complete
            )
            if notFound {
                Text("Not found")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(.red)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(notFound ? Color.red : Theme.Color.accent, lineWidth: 1)
        )
        .help("Return goes there · Tab completes · ⌘Return opens in a new tab")
        .overlay(alignment: .topLeading) {
            if showsSuggestions {
                suggestionList
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: 26)
            }
        }
        .onChange(of: text) { _, _ in
            edited = true
            notFound = false
            highlighted = nil
        }
        .task(id: text) { await loadCompletions() }
    }

    // MARK: Suggestions

    private var showsSuggestions: Bool {
        edited && completionsText == text && !completions.isEmpty
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(completions.enumerated()), id: \.element.path) { index, completion in
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.labelSecondary)
                    Text(completion.name)
                        .font(Theme.Font.breadcrumb)
                        .foregroundStyle(Theme.Color.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == highlighted ? Theme.Color.selection.opacity(0.35) : .clear)
                )
                .contentShape(Rectangle())
                .onHover { if $0 { highlighted = index } }
                // A tap gesture, not a Button: it leaves the text field as
                // first responder, so the click can't end editing first.
                .onTapGesture { go(to: completion, newTab: NSEvent.modifierFlags.contains(.command)) }
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.Color.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private func loadCompletions() async {
        let text = text
        guard edited || text != request.text else { return }
        let base = base?.path
        let found = await Task.detached(priority: .userInitiated) {
            PathInput.completions(for: text, relativeTo: base)
        }.value
        guard !Task.isCancelled else { return }
        completions = found
        completionsText = text
    }

    // MARK: Keys

    private func submit(newTab: Bool) {
        if showsSuggestions, let highlighted, completions.indices.contains(highlighted) {
            return go(to: completions[highlighted], newTab: newTab)
        }
        switch PathInput.resolve(text, relativeTo: base?.path) {
        case .empty:
            onCancel()
        case .notFound:
            notFound = true
        case let resolution:
            onGo(resolution, newTab)
        }
    }

    private func go(to completion: PathInput.Completion, newTab: Bool) {
        onGo(.folder(URL(fileURLWithPath: completion.path, isDirectory: true)), newTab)
    }

    /// ↑/↓ walk the suggestions; ↑ past the first row returns to the text.
    /// False when no list is showing, so the keys move the caret as usual.
    private func moveHighlight(by delta: Int) -> Bool {
        guard showsSuggestions else { return false }
        if let current = highlighted {
            let next = current + delta
            highlighted = next < 0 ? nil : min(next, completions.count - 1)
        } else if delta > 0 {
            highlighted = 0
        }
        return true
    }

    /// Tab accepts the highlighted row, else extends to the prefix every
    /// match shares (shell-style); when that adds nothing, it highlights the
    /// first match so a second Tab accepts it.
    private func complete() {
        if showsSuggestions, let highlighted, completions.indices.contains(highlighted) {
            text = completions[highlighted].text
            return
        }
        let current = completionsText == text
            ? completions
            : PathInput.completions(for: text, relativeTo: base?.path)
        if let common = PathInput.commonCompletion(current, for: text) {
            text = common
        } else if !current.isEmpty {
            edited = true
            completions = current
            completionsText = text
            highlighted = 0
        }
    }
}

/// `NSTextField` for the Go to Folder field, wrapped directly for the same
/// reason as `RenameTextField`: Return, Esc, Tab and ↑/↓ must route
/// deterministically through `control(_:textView:doCommandBy:)` instead of
/// racing the file list's key handlers or SwiftUI's focus system.
private struct PathTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: (_ newTab: Bool) -> Void
    let onCancel: () -> Void
    let onEndEditing: () -> Void
    /// ↑ (-1) / ↓ (+1). Returns false to leave the key to the field editor.
    let onMove: (_ delta: Int) -> Bool
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = "Type or paste a path"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 12)   // matches Theme.Font.breadcrumb
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.allowsEditingTextAttributes = false
        field.maximumNumberOfLines = 1
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // An outside change (Tab completion) replaces the text and parks the
        // caret at the end. Written through the field editor: setting
        // `stringValue` mid-edit would end editing and drop focus.
        if text != coordinator.editorText {
            coordinator.editorText = text
            if let editor = field.currentEditor() {
                editor.string = text
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            } else {
                field.stringValue = text
            }
        }
        // One-shot focus with everything selected, so a paste or the first
        // keystroke replaces the current path. Deferred one runloop turn for
        // the same reason as `RenameTextField`: the field isn't in a window
        // on the first update.
        if !coordinator.didFocus {
            coordinator.didFocus = true
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PathTextField
        var didFocus = false
        /// Last text seen in the field editor — tells `updateNSView` a live
        /// edit apart from an outside change.
        var editorText: String

        init(_ parent: PathTextField) {
            self.parent = parent
            self.editorText = parent.text
        }

        func controlTextDidChange(_ notification: Notification) {
            // Read the field editor rather than `stringValue`, which would
            // commit an in-progress Hangul composition.
            guard let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView else { return }
            editorText = editor.string
            parent.text = editor.string
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(Self.commandIsDown)
                return true
            // ⌘↩ has no key binding, so the field editor reports it as `noop:`.
            case Selector(("noop:")) where Self.isCommandReturn(NSApp.currentEvent):
                parent.onSubmit(true)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMove(1)
            case #selector(NSResponder.insertTab(_:)):
                parent.onComplete()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                return true
            default:
                return false
            }
        }

        /// Focus moved elsewhere — another pane, the sidebar, a tab. Put
        /// the breadcrumb back, like a browser's address bar.
        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }

        private static var commandIsDown: Bool {
            NSApp.currentEvent?.modifierFlags.contains(.command) == true
        }

        private static func isCommandReturn(_ event: NSEvent?) -> Bool {
            guard let event, event.type == .keyDown, event.modifierFlags.contains(.command) else { return false }
            return event.keyCode == 36 || event.keyCode == 76   // Return, keypad Enter
        }
    }
}
