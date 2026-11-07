import XCTest
import SwiftILBM

/// Compiles and runs the README "Quick start" snippet against the public API
/// (non-`@testable` import) so the documentation cannot drift.
final class ReadmeTests: XCTestCase {

    func testQuickStartSnippet() throws {
        // 2x1, 1 plane, uncompressed: pixel 0 = index 1, pixel 1 = index 0.
        var file = Data("FORM".utf8) + Data([0, 0, 0, 56]) + Data("ILBM".utf8)
        file += Data("BMHD".utf8) + Data([0, 0, 0, 20])
        file += Data([0, 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 10, 11, 1, 64, 0, 200])
        file += Data("CMAP".utf8) + Data([0, 0, 0, 6]) + Data([0, 0, 0, 255, 255, 255])
        file += Data("BODY".utf8) + Data([0, 0, 0, 2]) + Data([0x80, 0x00])
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftilbm-readme-\(UUID().uuidString).iff")
        try file.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // --- README snippet begins ---
        let image = try ILBMImage(url: fileURL)                // throws ILBMError
        print(image.width, image.height, image.depth, image.colorMode)
        let firstPixel = Array(image.pixels[0..<4])            // straight RGBA8

        #if canImport(CoreGraphics)
        let cg = image.cgImage
        XCTAssertNotNil(cg)
        #endif
        #if canImport(UIKit)
        let ui = image.uiImage
        XCTAssertNotNil(ui)
        #elseif canImport(AppKit)
        let ns = image.nsImage
        XCTAssertNotNil(ns)
        #endif
        // --- README snippet ends ---

        XCTAssertEqual(firstPixel, [255, 255, 255, 255])
        XCTAssertEqual(image.indexedPixels, [1, 0])
    }
}
