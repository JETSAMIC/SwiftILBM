import XCTest
@testable import SwiftILBM

/// Malformed-input hardening: decoding must throw an ``ILBMError`` or return
/// a consistent image for any input — never trap or hang.
final class RobustnessTests: XCTestCase {

    /// Deterministic SplitMix64 so failures are reproducible.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func fixtures() -> [Data] {
        let ham = Fixture.form("ILBM", [
            Fixture.bmhd(width: 5, height: 2, planes: 6, compression: 1),
            Fixture.cmap(Fixture.grayscalePalette(16)), Fixture.camg(0x0800),
            Fixture.chunk("BODY", [UInt8](BODYChunk.byteRun1Encode(Data(
                Fixture.planarRow([1, 0x2F, 0x38, 0x13, 0x05], planes: 6, bytesPerRow: 2)
                + Fixture.planarRow([0x3F, 0x00, 0x21, 0x12, 0x07], planes: 6, bytesPerRow: 2))))),
        ])
        let masked = Fixture.form("ILBM", [
            Fixture.bmhd(width: 3, height: 1, planes: 2, masking: 1),
            Fixture.cmap(Fixture.grayscalePalette(4)),
            Fixture.chunk("BODY", Fixture.planarRow([1, 2, 3], planes: 2, bytesPerRow: 2)
                          + Fixture.maskRow([true, false, true], bytesPerRow: 2)),
        ])
        let deep = Fixture.form("ILBM", [
            Fixture.bmhd(width: 2, height: 1, planes: 24),
            Fixture.chunk("BODY", Fixture.planarRow([0x123456, 0xABCDEF], planes: 24, bytesPerRow: 2)),
        ])
        let pbm = Fixture.form("PBM ", [
            Fixture.bmhd(width: 3, height: 2, planes: 8, compression: 1),
            Fixture.cmap(Fixture.grayscalePalette(256)),
            Fixture.chunk("BODY", [UInt8](BODYChunk.byteRun1Encode(Data([0, 1, 2, 0, 3, 3, 3, 0])))),
        ])
        let list = Data(Fixture.group("LIST", "ILBM", [
            Fixture.group("PROP", "ILBM", [Fixture.bmhd(width: 2, height: 1, planes: 1),
                                           Fixture.cmap(Fixture.grayscalePalette(2))]),
            Fixture.group("FORM", "ILBM", [Fixture.chunk("BODY", [0x80, 0])]),
        ]))
        return [
            Fixture.indexedImage(compressed: true),
            Fixture.indexedImage(compressed: false),
            ham, masked, deep, pbm, list,
        ]
    }

    private func decodeChecked(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let image = try ILBMImage(data: data)
            XCTAssertEqual(image.pixels.count, image.width * image.height * 4, file: file, line: line)
            if let indices = image.indexedPixels {
                XCTAssertEqual(indices.count, image.width * image.height, file: file, line: line)
            }
        } catch is ILBMError {
            // Expected for malformed input.
        } catch {
            XCTFail("Unexpected non-ILBMError: \(error)", file: file, line: line)
        }
    }

    func testFixturesDecode() throws {
        for fixture in Self.fixtures() {
            XCTAssertNoThrow(try ILBMImage(data: fixture))
        }
    }

    func testTruncationAtEveryOffset() {
        for fixture in Self.fixtures() {
            for length in 0 ..< fixture.count {
                decodeChecked(fixture.prefix(length))
            }
        }
    }

    func testSeededMutationFuzz() {
        var rng = SeededGenerator(state: 0x494C_424D_4655_5A5A)  // "ILBMFUZZ"
        let fixtures = Self.fixtures()
        for _ in 0 ..< 4000 {
            var bytes = [UInt8](fixtures[Int.random(in: 0 ..< fixtures.count, using: &rng)])
            for _ in 0 ..< Int.random(in: 1 ... 8, using: &rng) {
                switch Int.random(in: 0 ..< 4, using: &rng) {
                case 0 where !bytes.isEmpty:
                    bytes[Int.random(in: 0 ..< bytes.count, using: &rng)] = UInt8.random(in: 0 ... 255, using: &rng)
                case 1:
                    // Target BMHD fields and chunk sizes (offsets 4–7, 16–19, 20–39).
                    let offset = [4, 5, 6, 7, 16, 17, 18, 19, 20, 21, 22, 23, 28, 29, 30, 31, 32, 33]
                        .randomElement(using: &rng)!
                    if offset < bytes.count { bytes[offset] = UInt8.random(in: 0 ... 255, using: &rng) }
                case 2 where bytes.count > 1:
                    bytes.removeLast(Int.random(in: 0 ... min(32, bytes.count - 1), using: &rng))
                default:
                    for _ in 0 ..< Int.random(in: 1 ... 16, using: &rng) {
                        bytes.append(UInt8.random(in: 0 ... 255, using: &rng))
                    }
                }
            }
            decodeChecked(Data(bytes))
        }
    }

    func testDeeplyNestedContainersTerminate() {
        var inner = Fixture.group("FORM", "XXXX", [])
        for _ in 0 ..< 64 { inner = Fixture.group("LIST", "ILBM", [inner]) }
        XCTAssertThrowsError(try ILBMImage(data: Data(inner))) {
            XCTAssertEqual($0 as? ILBMError, .invalidSignature)
        }
    }

    func testZeroLengthChunksTerminate() {
        let chunks = [[UInt8]](repeating: Fixture.chunk("ZERO", []), count: 1000)
        XCTAssertThrowsError(try ILBMImage(data: Fixture.form("ILBM", chunks))) {
            XCTAssertEqual($0 as? ILBMError, .missingBMHD)
        }
    }
}
