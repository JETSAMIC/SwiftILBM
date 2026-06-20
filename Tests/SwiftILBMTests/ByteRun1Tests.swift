import XCTest
@testable import SwiftILBM

final class ByteRun1Tests: XCTestCase {

    /// Known PackBits example from Apple's TechNote:
    /// Input:    FE AA 02 80 00 2A FD AA 03 80 00 2A 22 F7 AA
    /// (control bytes interpreted as signed Int8 with replicate/literal rules)
    /// Expected: AA AA AA 80 00 2A AA AA AA AA 80 00 2A 22 AA AA AA AA AA AA AA AA
    func testDecodesKnownAppleExample() throws {
        let input = Data([0xFE, 0xAA, 0x02, 0x80, 0x00, 0x2A,
                          0xFD, 0xAA, 0x03, 0x80, 0x00, 0x2A, 0x22,
                          0xF7, 0xAA])
        let expected: [UInt8] = [
            0xAA, 0xAA, 0xAA,                    // FE AA      → 3 × AA
            0x80, 0x00, 0x2A,                    // 02 80 00 2A→ literal 3
            0xAA, 0xAA, 0xAA, 0xAA,              // FD AA      → 4 × AA
            0x80, 0x00, 0x2A, 0x22,              // 03 ...     → literal 4
            0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA // F7 AA → 10 × AA
        ]
        let decoded = try BODYChunk.byteRun1Decode(input, expectedSize: expected.count)
        XCTAssertEqual(Array(decoded), expected)
    }

    /// Round-trip: encode arbitrary bytes, decode, expect identity.
    func testRoundTripIdentity() throws {
        // Mix replicate-friendly and literal-friendly regions.
        var bytes: [UInt8] = []
        bytes.append(contentsOf: Array(repeating: 0x42, count: 17))
        bytes.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        bytes.append(contentsOf: Array(repeating: 0xFF, count: 200)) // crosses 128-byte run cap
        bytes.append(contentsOf: [0xAA, 0xBB, 0xCC])
        let original = Data(bytes)

        let encoded = BODYChunk.byteRun1Encode(original)
        let decoded = try BODYChunk.byteRun1Decode(encoded, expectedSize: original.count)

        XCTAssertEqual(decoded, original)
    }

    /// -128 control byte is a no-op per Apple spec.
    func testNoOpControlByteIsSkipped() throws {
        // 80 (=-128) noop, then 02 11 22 33 (literal of 3)
        let input = Data([0x80, 0x02, 0x11, 0x22, 0x33])
        let decoded = try BODYChunk.byteRun1Decode(input, expectedSize: 3)
        XCTAssertEqual(Array(decoded), [0x11, 0x22, 0x33])
    }

    func testTruncatedLiteralThrows() {
        // Says "literal 4 bytes" but only 2 follow.
        let input = Data([0x03, 0x11, 0x22])
        XCTAssertThrowsError(try BODYChunk.byteRun1Decode(input, expectedSize: 4)) { err in
            XCTAssertEqual(err as? ILBMError, .malformedRLE)
        }
    }
}
