import XCTest
@testable import SwiftILBM

/// End-to-end synthesis: builds a minimal but spec-correct ILBM in memory,
/// feeds it through ILBMImage, and inspects the decoded CGImage. This catches
/// integration regressions that unit tests on the individual chunks would miss.
final class EndToEndTests: XCTestCase {

    /// 2×1, 1-plane, uncompressed ILBM with palette [black, white].
    /// Single plane row = 0b10000000 0x00 → pixels: white(1), black(0)
    func testUncompressedTwoPixelImage() throws {
        let bmhd: [UInt8] = [
            0x00, 0x02,                     // width = 2
            0x00, 0x01,                     // height = 1
            0x00, 0x00, 0x00, 0x00,         // x, y
            0x01,                           // nPlanes = 1
            0x00,                           // masking = 0
            0x00,                           // compression = 0 (none)
            0x00,                           // pad
            0x00, 0x00,                     // transparentColor
            0x01, 0x01,                     // aspect
            0x00, 0x02, 0x00, 0x01          // pageW, pageH
        ]
        let cmap: [UInt8] = [
            0x00, 0x00, 0x00,               // index 0 = black
            0xFF, 0xFF, 0xFF                // index 1 = white
        ]
        // 2 pixels but bytesPerRow = 2 (word-padded), so 2 bytes per plane per row.
        let body: [UInt8] = [0b10000000, 0x00]

        let data = makeFORM(chunks: [
            ("BMHD", bmhd),
            ("CMAP", cmap),
            ("BODY", body)
        ])

        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(image.depth, 1)
        XCTAssertEqual(image.palette.count, 2)
        XCTAssertEqual(image.indexedPixels, [1, 0])
        XCTAssertNotNil(image.cgImage)
        XCTAssertEqual(image.cgImage?.width, 2)
        XCTAssertEqual(image.cgImage?.height, 1)
    }

    /// Same image but BODY is ByteRun1-compressed. Verifies the BMHD.compression=1
    /// path is wired through to PackBits decoding end-to-end.
    func testByteRun1CompressedImage() throws {
        let bmhd: [UInt8] = [
            0x00, 0x02, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x01, 0x00,         // compression = 1
            0x00, 0x00,
            0x01, 0x01,
            0x00, 0x02, 0x00, 0x01
        ]
        let cmap: [UInt8] = [0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF]
        let bodyRaw = Data([0b10000000, 0x00])
        let bodyEncoded = BODYChunk.byteRun1Encode(bodyRaw)

        let data = makeFORM(chunks: [
            ("BMHD", bmhd),
            ("CMAP", cmap),
            ("BODY", Array(bodyEncoded))
        ])

        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.indexedPixels, [1, 0])
    }

    func testMissingBMHDThrows() {
        let data = makeFORM(chunks: [("BODY", [0x00])])
        XCTAssertThrowsError(try ILBMImage(data: data)) { err in
            XCTAssertEqual(err as? ILBMError, .missingBMHD)
        }
    }

    func testMissingBODYThrows() {
        let bmhd: [UInt8] = [
            0x00, 0x02, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
            0x00, 0x00,
            0x01, 0x01,
            0x00, 0x02, 0x00, 0x01
        ]
        let cmap: [UInt8] = [0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF]
        let data = makeFORM(chunks: [("BMHD", bmhd), ("CMAP", cmap)])
        XCTAssertThrowsError(try ILBMImage(data: data)) { err in
            XCTAssertEqual(err as? ILBMError, .missingBODY)
        }
    }

    func testUnsupportedDepthThrows() {
        // nPlanes = 12 is rejected. (This test used nPlanes = 24, which the
        // ILBM spec defines as 24-bit true colour and is now supported.)
        let bmhd: [UInt8] = [
            0x00, 0x02, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            12, 0x00, 0x00, 0x00,
            0x00, 0x00,
            0x01, 0x01,
            0x00, 0x02, 0x00, 0x01
        ]
        let body: [UInt8] = Array(repeating: 0, count: 48)
        let data = makeFORM(chunks: [("BMHD", bmhd), ("BODY", body)])
        XCTAssertThrowsError(try ILBMImage(data: data)) { err in
            XCTAssertEqual(err as? ILBMError, .unsupportedDepth(12))
        }
    }

    // MARK: - Helpers

    /// Assemble a FORM/ILBM wrapping the given (id, bytes) chunks. Adds the
    /// per-chunk 8-byte header, pads each chunk body to even length, and writes
    /// the outer FORM size correctly.
    private func makeFORM(chunks: [(String, [UInt8])]) -> Data {
        var inner = Data()
        // subtype "ILBM"
        inner.append(contentsOf: [0x49, 0x4C, 0x42, 0x4D])
        for (id, body) in chunks {
            inner.append(contentsOf: id.utf8)
            let sz = UInt32(body.count)
            inner.append(contentsOf: [
                UInt8((sz >> 24) & 0xFF),
                UInt8((sz >> 16) & 0xFF),
                UInt8((sz >> 8)  & 0xFF),
                UInt8(sz & 0xFF)
            ])
            inner.append(contentsOf: body)
            if body.count & 1 == 1 { inner.append(0x00) }
        }
        var out = Data()
        out.append(contentsOf: [0x46, 0x4F, 0x52, 0x4D])
        let sz = UInt32(inner.count)
        out.append(contentsOf: [
            UInt8((sz >> 24) & 0xFF),
            UInt8((sz >> 16) & 0xFF),
            UInt8((sz >> 8)  & 0xFF),
            UInt8(sz & 0xFF)
        ])
        out.append(inner)
        return out
    }
}
