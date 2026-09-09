import AppKit
import SwiftUI
import XCTest

final class MarkdownImageProviderTests: XCTestCase {
    func testInlineRemoteImageIsRejectedBeforeNetworkAccess() async {
        let provider = PreviewMarkdownInlineImageProvider()
        for address in ["https://127.0.0.1:1/image.png", "http://127.0.0.1:1/image.png", "ftp://127.0.0.1/image.png"] {
            do {
                _ = try await provider.image(with: URL(string: address)!, label: "remote")
                XCTFail("External image should be blocked")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, .resourceUnavailable)
            }
        }
    }

    @MainActor
    func testBlockRemoteImageRendersBlockedMessage() {
        let view = NSHostingView(
            rootView: PreviewMarkdownImageProvider()
                .makeImage(url: URL(string: "https://127.0.0.1:1/image.png")!))
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        view.layoutSubtreeIfNeeded()
        // The blocking provider renders useful content immediately, while the
        // default network provider starts with a zero-sized loading view.
        XCTAssertGreaterThan(view.fittingSize.height, 0)
    }

    func testExplicitRemotePermissionUsesLoaderWhileDefaultDoesNot() async throws {
        let requests = PreviewImageRequests()
        let url = URL(string: "https://mqdir-preview.test/image.png")!
        var provider = PreviewMarkdownInlineImageProvider(remoteImage: { actualURL, label in
            XCTAssertEqual(actualURL, url)
            XCTAssertEqual(label, "allowed")
            requests.record()
            return Image(systemName: "photo")
        })
        do {
            _ = try await provider.image(with: url, label: "blocked")
            XCTFail("Expected the default provider to block the request")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .resourceUnavailable)
        }
        XCTAssertEqual(requests.count, 0)
        provider.allowRemoteImages = true
        _ = try await provider.image(with: url, label: "allowed")
        XCTAssertEqual(requests.count, 1)
    }

    func testLocalInlineImageStillLoads() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        try png.write(to: url)
        _ = try await PreviewMarkdownInlineImageProvider().image(with: url, label: "local")
    }
}

private final class PreviewImageRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func record() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}
