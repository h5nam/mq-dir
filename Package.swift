// swift-tools-version:5.10
import PackageDescription

// SwiftPM manifest for the headless `mqdirCore` library only.
// The macOS app proper builds via Xcode (`xcodegen generate && xcodebuild`).
// This manifest exists so contributors can run `swift test` without Xcode
// and so CI can validate library logic on smaller runners.

let package = Package(
    name: "mqdirCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "mqdirCore", targets: ["mqdirCore"]),
    ],
    targets: [
        .target(
            name: "mqdirCore",
            path: "Sources/Core"
        ),
        .testTarget(
            name: "mqdirCoreTests",
            dependencies: ["mqdirCore"],
            path: "Tests/mqdirCoreTests"
        ),
    ]
)
