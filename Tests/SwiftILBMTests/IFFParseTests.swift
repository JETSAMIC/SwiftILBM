import XCTest
@testable import SwiftILBM

final class IFFParseTests: XCTestCase {

    /// Minimal valid ILBM FORM containing two inner chunks: "BMHD" (1 byte payload,
    /// will trigger an odd-length pad byte) and "BODY" (2 byte payload, no pad).
    func testEnumeratesChunksAndHandlesPadding() throws {
        var data = Data()
        // "FORM"
        data.append(contentsOf: [0x46, 0x4F, 0x52, 0x4D])
        // size: subtype(4) + chunk1 header(8) + chunk1 body(1) + pad(1)
        //              + chunk2 header(8) + chunk2 body(2) = 24
        data.append(contentsOf: [0x00, 0x00, 0x00, 24])
        // subtype "ILBM"
        data.append(contentsOf: [0x49, 0x4C, 0x42, 0x4D])
        // chunk 1: "BMHD" len=1 body=0xAA pad=0x00
        data.append(contentsOf: [0x42, 0x4D, 0x48, 0x44])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        data.append(0xAA)
        data.append(0x00) // pad byte
        // chunk 2: "BODY" len=2 body=0x11 0x22
        data.append(contentsOf: [0x42, 0x4F, 0x44, 0x59])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x02])
        data.append(contentsOf: [0x11, 0x22])

        let chunks = try IFFParser.parse(data)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].id, "BMHD")
        XCTAssertEqual(Array(chunks[0].data), [0xAA])
        XCTAssertEqual(chunks[1].id, "BODY")
        XCTAssertEqual(Array(chunks[1].data), [0x11, 0x22])
    }

    func testRejectsNonFORMSignature() {
        var data = Data([0x4C, 0x49, 0x53, 0x54]) // "LIST"
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x04])
        data.append(contentsOf: [0x49, 0x4C, 0x42, 0x4D])
        XCTAssertThrowsError(try IFFParser.parse(data)) { err in
            XCTAssertEqual(err as? ILBMError, .invalidSignature)
        }
    }

    func testRejectsWrongSubtype() {
        var data = Data([0x46, 0x4F, 0x52, 0x4D])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x04])
        data.append(contentsOf: [0x38, 0x53, 0x56, 0x58]) // "8SVX" (audio)
        XCTAssertThrowsError(try IFFParser.parse(data)) { err in
            XCTAssertEqual(err as? ILBMError, .invalidSignature)
        }
    }

    func testTruncatedFormHeader() {
        let data = Data([0x46, 0x4F, 0x52, 0x4D, 0x00, 0x00]) // 6 bytes, need ≥ 12
        XCTAssertThrowsError(try IFFParser.parse(data))
    }
}
