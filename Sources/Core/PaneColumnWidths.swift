import CoreGraphics
import Foundation

/// Per-pane column widths for the file list. Lives in `mqdirCore` so that
/// persisted pane state (which embeds it) is fully testable headless.
struct PaneColumnWidths: Codable, Equatable, Sendable {
    var modified: CGFloat
    var size: CGFloat
    var kind: CGFloat

    init(modified: CGFloat = 132, size: CGFloat = 78, kind: CGFloat = 96) {
        self.modified = modified
        self.size = size
        self.kind = kind
    }

    static let modifiedRange: ClosedRange<CGFloat> = 72...260
    static let sizeRange: ClosedRange<CGFloat> = 56...140
    static let kindRange: ClosedRange<CGFloat> = 56...220
}
