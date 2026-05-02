import AppKit
import Foundation
import UniformTypeIdentifiers

// Drag/drop pasteboard plumbing for mq-dir.
//
// External drags (mq-dir → Finder/Terminal/etc.) carry a single primary URL
// via the standard `public.file-url` type. Internal drags carry an extra
// `com.mqdir.selection.urls` representation containing the *full* selection,
// so that pane-to-pane drops can move every selected item even though
// SwiftUI's `.draggable` only ships one item at a time.

enum DragDropSupport {
    static let mqdirSelectionTypeIdentifier = "com.mqdir.selection.urls"

    /// Build an NSItemProvider for a row drag. Always exposes the primary URL
    /// as `public.file-url`. If `multiURLs` is non-empty (the row is part of
    /// a multi-selection), also exposes a JSON list under our private type
    /// for in-process drops.
    static func makeItemProvider(primary: URL, multiURLs: [URL]) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerObject(primary as NSURL, visibility: .all)

        if multiURLs.count > 1 {
            let urlStrings = multiURLs.map(\.absoluteString)
            if let data = try? JSONEncoder().encode(urlStrings) {
                provider.registerDataRepresentation(
                    forTypeIdentifier: mqdirSelectionTypeIdentifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(data, nil)
                    return nil
                }
            }
        }
        return provider
    }

    /// Resolve an array of incoming NSItemProviders to file URLs. Prefers our
    /// private multi-selection type when present; otherwise falls back to the
    /// standard `public.file-url`.
    static func resolveURLs(from providers: [NSItemProvider]) async -> [URL] {
        var resolved: [URL] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(mqdirSelectionTypeIdentifier),
               let multi = await loadMultiSelection(from: provider) {
                resolved.append(contentsOf: multi)
                continue
            }
            if let url = await loadFileURL(from: provider) {
                resolved.append(url)
            }
        }

        return resolved
    }

    private static func loadMultiSelection(from provider: NSItemProvider) async -> [URL]? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: mqdirSelectionTypeIdentifier) { data, _ in
                guard let data,
                      let strings = try? JSONDecoder().decode([String].self, from: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: strings.compactMap { URL(string: $0) })
            }
        }
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { obj, _ in
                continuation.resume(returning: obj as? URL)
            }
        }
    }

    /// Type identifiers a drop destination should accept.
    static let acceptedDropTypes: [String] = [
        mqdirSelectionTypeIdentifier,
        UTType.fileURL.identifier,
    ]
}
