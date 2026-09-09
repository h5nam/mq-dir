import Foundation

/// Window-level layout describing how the pane grid is divided.
///
/// Lives in `mqdirCore` so that persisted window state (which references it)
/// is self-contained and can be fully exercised by `swift test`.
enum PaneLayout: Int, CaseIterable, Identifiable, Codable, Sendable {
    case one = 1
    case twoH = 2
    case twoV = 3
    case four = 4
    case three = 5

    var id: Int { rawValue }

    var paneCount: Int {
        switch self {
        case .one:  1
        case .twoH: 2
        case .twoV: 2
        case .four: 4
        case .three: 3
        }
    }

    var symbol: String {
        switch self {
        case .one:  "square"
        case .twoH: "rectangle.split.2x1"
        case .twoV: "rectangle.split.1x2"
        case .four: "square.grid.2x2"
        case .three: "rectangle.split.3x1"
        }
    }

    var help: String {
        switch self {
        case .one:  "Single pane"
        case .twoH: "Two panes — side by side"
        case .twoV: "Two panes — stacked"
        case .four: "Four panes — 2×2 grid"
        case .three: "Three panes — source and two destinations"
        }
    }
}
