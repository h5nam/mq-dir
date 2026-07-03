import AppKit
import SwiftUI

extension ColorSchemeOption {
    /// Map the persisted preference onto SwiftUI's `.preferredColorScheme`.
    /// `.system` becomes `nil` so the modifier becomes a no-op and macOS's
    /// own Appearance setting wins.
    var preferred: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    /// Display label for the Settings picker.
    var label: String {
        switch self {
        case .system: "Match System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }
}

/// macOS Settings scene contents. Two sections: Appearance picker
/// + Shortcuts customiser for the 10 actions exposed in
/// `ShortcutAction`. Both write through `WorkspaceManager` so the
/// debounced save path is shared with everything else workspace-
/// scoped (favourites, project list, …).
struct SettingsView: View {
    @ObservedObject var workspace: WorkspaceManager
    @State private var editingAction: ShortcutAction?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(ColorSchemeOption.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Toggle("Normalize Hangul filenames to NFC on drag out", isOn: normalizeHangulBinding)
            } header: {
                Text("Filenames")
            } footer: {
                Text("Korean filenames stored in decomposed (NFD) form look broken — like \u{315E}\u{3157}\u{3134}\u{3131}\u{3161}\u{3139} instead of 한글 — in terminals, Git, zip archives, and Windows transfers. Turn this on to rename them to composed (NFC) form on disk as they drag out of mq-dir. This fixes the name on disk; apps that rebuild names from the drag URL (such as web browsers) may still display NFD.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    shortcutRow(action)
                }
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        workspace.resetAllShortcutOverrides()
                    }
                    .disabled(workspace.workspace.settings.shortcutOverrides.isEmpty)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Click a shortcut to record a new key combination. Conflicts with another customisable shortcut are blocked.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .sheet(item: $editingAction) { action in
            KeyCaptureSheet(
                action: action,
                conflictChecker: { binding in
                    conflictingAction(for: binding, ignoring: action)
                },
                onCommit: { binding in
                    workspace.setShortcutBinding(binding, for: action)
                }
            )
        }
    }

    private var appearanceBinding: Binding<ColorSchemeOption> {
        Binding(
            get: { workspace.workspace.settings.colorScheme },
            set: { workspace.setColorScheme($0) }
        )
    }

    private var normalizeHangulBinding: Binding<Bool> {
        Binding(
            get: { workspace.workspace.settings.normalizeHangulOnDragOut },
            set: { workspace.setNormalizeHangulOnDragOut($0) }
        )
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        let active = workspace.workspace.settings.binding(for: action)
        let isOverridden = workspace.workspace.settings.shortcutOverrides[action] != nil
        return HStack {
            Text(action.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                editingAction = action
            } label: {
                Text(active.displayString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Click to record a new shortcut")
            if isOverridden {
                Button {
                    workspace.setShortcutBinding(nil, for: action)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
    }

    /// Look for an existing customisable action already bound to
    /// `candidate`, ignoring the action currently being edited so
    /// re-saving an unchanged shortcut doesn't flag itself as a
    /// conflict. Only checks the customisable set — collisions with
    /// hardcoded shortcuts (Cut/Copy/Paste, system menus) are not
    /// surfaced because we can't repoint those from this UI.
    private func conflictingAction(
        for candidate: ShortcutBinding,
        ignoring: ShortcutAction
    ) -> ShortcutAction? {
        for action in ShortcutAction.allCases where action != ignoring {
            if workspace.workspace.settings.binding(for: action) == candidate {
                return action
            }
        }
        return nil
    }
}

extension ShortcutAction: Identifiable {
    public var id: String { rawValue }
}

/// Modal that records the next keyDown the user types and either
/// commits it as a binding or surfaces a conflict explanation. The
/// background NSView grabs `keyDown(with:)` directly so we receive
/// the literal modifier flags + keyCode without going through
/// SwiftUI's `.onKeyPress`, which doesn't expose modifier-only
/// captures reliably on macOS 14.
struct KeyCaptureSheet: View {
    let action: ShortcutAction
    let conflictChecker: (ShortcutBinding) -> ShortcutAction?
    let onCommit: (ShortcutBinding) -> Void

    @State private var captured: ShortcutBinding?
    @State private var conflictWith: ShortcutAction?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("New shortcut for \u{201C}\(action.label)\u{201D}")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.10))
                Text(captured?.displayString ?? "Press any key combination")
                    .font(.system(size: 22, design: .monospaced))
                    .foregroundStyle(captured == nil ? .secondary : .primary)
            }
            .frame(height: 80)

            if let conflictWith {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Already used by \u{201C}\(conflictWith.label)\u{201D}")
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 11))
            } else if captured != nil {
                Text("Looks good — click Save to apply.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Modifier-only combinations (e.g. ⌘ alone) cannot be assigned.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    if let captured, conflictWith == nil {
                        onCommit(captured)
                        dismiss()
                    }
                }
                .disabled(captured == nil || conflictWith != nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(KeyCaptureView(
            captured: $captured,
            onBareEscape: { dismiss() }
        ))
        .onChange(of: captured) { _, new in
            guard let new else { conflictWith = nil; return }
            conflictWith = conflictChecker(new)
        }
    }
}

/// SwiftUI bridge that hosts an `NSView` whose only job is to grab
/// `keyDown` events while the capture sheet is open. The view
/// makes itself first responder on appearance so the user can
/// type a key combination immediately without clicking into the
/// sheet first. A bare Esc (no modifiers) routes through
/// `onBareEscape` so the sheet can dismiss instead of binding
/// `⎋` to the action.
private struct KeyCaptureView: NSViewRepresentable {
    @Binding var captured: ShortcutBinding?
    var onBareEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView()
        view.onCapture = { binding in
            DispatchQueue.main.async {
                self.captured = binding
            }
        }
        view.onBareEscape = { DispatchQueue.main.async(execute: onBareEscape) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class KeyCaptureNSView: NSView {
    var onCapture: ((ShortcutBinding) -> Void)?
    var onBareEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Async so the window has finished installing the sheet's
        // responder chain by the time we ask for first-responder
        // status.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        // Bare Esc (no modifiers) is the conventional cancel
        // gesture for a macOS sheet; route it to dismiss instead
        // of letting the user accidentally bind ⎋ to the action.
        // ⎋ with a modifier (e.g. ⌥⎋) still captures normally.
        if event.keyCode == 53 && modifiers.isEmpty {
            onBareEscape?()
            return
        }
        // F1...F12 by hardware keyCode. Reading
        // `charactersIgnoringModifiers` works too (Apple maps them to
        // NSF<N>FunctionKey = 0xF704...0xF70F) but the keyCode table
        // is more obvious and skips the function-row's IR/mute/etc.
        // overlay codes that share the same physical position on
        // some Mac keyboards.
        let fnByKeyCode: [UInt16: Int] = [
            122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6,
            98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12,
        ]

        let key: ShortcutKey
        switch event.keyCode {
        case 51:  key = .delete
        case 36:  key = .return
        case 53:  key = .escape
        case 48:  key = .tab
        case 126: key = .upArrow
        case 125: key = .downArrow
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        default:
            if let fn = fnByKeyCode[event.keyCode] {
                key = .functionKey(fn)
                break
            }
            guard let chars = event.charactersIgnoringModifiers,
                  let first = chars.first
            else { return }
            // Persist as lowercase so a user typing Shift+T and a
            // user typing T into the capture box collapse to the
            // same binding. The macOS menu bar uppercases letter
            // glyphs at render time anyway.
            key = .character(Character(String(first).lowercased()))
        }
        onCapture?(ShortcutBinding(key: key, modifiers: modifiers))
    }
}
