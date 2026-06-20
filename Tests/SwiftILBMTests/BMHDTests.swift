import XCTest
@testable import SwiftILBM

final class BMHDTests: XCTestCase {

    /// Build a canonical BMHD body: 320x200, 5 planes, ByteRun1, NTSC aspect.
    func testDecodesFieldsCorrectly() throws {
        var d = Data()
        // width 320 (0x0140), height 200 (0x00C8)
        d.append(contentsOf: [0x01, 0x40, 0x00, 0xC8])
        // x=0, y=0
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        // nPlanes=5, masking=0, compression=1, pad=0
        d.append(contentsOf: [0x05, 0x00, 0x01, 0x00])
        // transparentColor=0
        d.append(contentsOf: [0x00, 0x00])
        // xAspect=10, yAspect=11 (Amiga NTSC LowRes)
        d.append(contentsOf: [10, 11])
        // pageWidth=320, pageHeight=200
        d.append(contentsOf: [0x01, 0x40, 0x00, 0xC8])

        let bmhd = try BMHDChunk(data: d)
        XCTAssertEqual(bmhd.width, 320)
        XCTAssertEqual(bmhd.height, 200)
        XCTAssertEqual(bmhd.nPlanes, 5)
        XCTAssertEqual(bmhd.masking, 0)
        XCTAssertEqual(bmhd.compression, 1)
        XCTAssertEqual(bmhd.xAspect, 10)
        XCTAssertEqual(bmhd.yAspect, 11)
        XCTAssertEqual(bmhd.pageWidth, 320)
        XCTAssertEqual(bmhd.pageHeight, 200)
        XCTAssertEqual(bmhd.bytesPerRow, 40) // 320 px → 20 words → 40 bytes
    }

    /// Width 321 → ceil(321 / 16) = 21 words = 42 bytes per plane row.
    /// (ILBM pads to 16-bit word boundaries, not 32-bit.)
    func testBytesPerRowRoundsUpToWord() throws {
        var d = Data()
        d.append(contentsOf: [0x01, 0x41, 0x00, 0x01]) // 321 × 1
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        d.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        d.append(contentsOf: [0x00, 0x00, 0, 0])
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        let bmhd = try BMHDChunk(data: d)
        XCTAssertEqual(bmhd.bytesPerRow, 42)
    }

    /// Width 17 → ceil(17 / 16) = 2 words = 4 bytes per plane row (sanity).
    func testBytesPerRowSmall() throws {
        var d = Data()
        d.append(contentsOf: [0x00, 0x11, 0x00, 0x01]) // 17 × 1
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        d.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        d.append(contentsOf: [0x00, 0x00, 0, 0])
        d.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        let bmhd = try BMHDChunk(data: d)
        XCTAssertEqual(bmhd.bytesPerRow, 4)
    }

    func testTruncatedBMHDThrows() {
        let d = Data([0x01, 0x40, 0x00, 0xC8]) // only 4 bytes
        XCTAssertThrowsError(try BMHDChunk(data: d))
    }
}
