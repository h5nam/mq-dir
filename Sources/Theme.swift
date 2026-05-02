import SwiftUI
import AppKit

// Dark-only theme tokens mirrored from the Claude Design prototype
// (web-prototype/mq-dir.html). The app forces dark appearance via
// `.preferredColorScheme(.dark)` at the App level.

enum Theme {
    enum Color {
        static let windowBg       = SwiftUI.Color(red: 0x1d/255, green: 0x1d/255, blue: 0x1f/255)
        static let paneBg         = SwiftUI.Color(red: 0x1d/255, green: 0x1d/255, blue: 0x1f/255)
        static let toolbarBg      = SwiftUI.Color(red: 0x28/255, green: 0x28/255, blue: 0x2a/255).opacity(0.92)
        static let sidebarBg      = SwiftUI.Color(red: 0x1e/255, green: 0x1e/255, blue: 0x20/255).opacity(0.92)
        static let tabBarBg       = SwiftUI.Color.black.opacity(0.18)
        static let columnHeaderBg = SwiftUI.Color.black.opacity(0.12)
        static let statusBarBg    = SwiftUI.Color(red: 0x1c/255, green: 0x1c/255, blue: 0x1e/255).opacity(0.95)
        static let separator      = SwiftUI.Color.white.opacity(0.08)
        static let separatorFaint = SwiftUI.Color.white.opacity(0.05)
        static let label          = SwiftUI.Color(red: 0xf5/255, green: 0xf5/255, blue: 0xf7/255)
        static let labelSecondary = SwiftUI.Color.white.opacity(0.6)
        static let labelTertiary  = SwiftUI.Color.white.opacity(0.3)
        static let accent         = SwiftUI.Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255)
        static let selection      = SwiftUI.Color(red: 0x0a/255, green: 0x84/255, blue: 0xff/255)
        static let selectionInactive = SwiftUI.Color.white.opacity(0.08)
        static let rowHover       = SwiftUI.Color.white.opacity(0.03)
    }

    enum Metrics {
        static let toolbarHeight: CGFloat       = 38   // compact, Xcode-like
        static let tabBarHeight: CGFloat        = 26
        static let paneHeaderHeight: CGFloat    = 20
        static let columnHeaderHeight: CGFloat  = 22
        static let rowHeight: CGFloat           = 22
        static let statusBarHeight: CGFloat     = 24
        static let sidebarWidth: CGFloat        = 184
        static let focusBorderWidth: CGFloat    = 2
    }

    enum Font {
        static let body          = SwiftUI.Font.system(size: 13)
        static let secondary     = SwiftUI.Font.system(size: 11)
        static let columnHeader  = SwiftUI.Font.system(size: 11, weight: .medium)
        static let sidebarItem   = SwiftUI.Font.system(size: 12)
        static let sidebarHeader = SwiftUI.Font.system(size: 10, weight: .bold)
        static let tab           = SwiftUI.Font.system(size: 11)
        static let breadcrumb    = SwiftUI.Font.system(size: 12)
    }
}
