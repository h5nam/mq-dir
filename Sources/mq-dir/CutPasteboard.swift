import AppKit

/// Completes only the clipboard transaction that started this move.
@MainActor
enum CutPasteboard {
    static let markerType = NSPasteboard.PasteboardType("com.mqdir.cut.urls")

    static func complete(_ pasteboard: NSPasteboard, changeCount: Int, remainingURLs: [URL]) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        if !remainingURLs.isEmpty {
            pasteboard.writeObjects(remainingURLs.map { $0 as NSURL })
            pasteboard.setData(Data(), forType: markerType)
        }
    }
}
