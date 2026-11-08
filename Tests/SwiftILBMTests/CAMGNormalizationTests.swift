import XCTest
@testable import SwiftILBM

/// CAMG clean-up rules, Reference/ILBM-Format.md section 5.5.
final class CAMGNormalizationTests: XCTestCase {

    func testSixteenBitValueLosesNonDisplayBits() {
        // SPRITES | VP_HIDE | EXTENDED_MODE | GENLOCK_AUDIO | GENLOCK_VIDEO | HIRES | LACE | EHB
        let raw = ILBMViewportMode(rawValue: 0x7102 | 0x8000 | 0x0004 | 0x0080)
        XCTAssertFalse(raw.isBogus)
        XCTAssertEqual(raw.normalized(pageWidth: 320, pageHeight: 200).rawValue, 0x8084)
        XCTAssertEqual(ILBMViewportMode.nonDisplayBits.rawValue, 0x7102)
    }

    func testModeIDWithMonitorIsKept() {
        let palHAM = ILBMViewportMode(rawValue: 0x0002_1000 | 0x0800)   // PAL_MONITOR_ID | HAM
        XCTAssertFalse(palHAM.isBogus)
        XCTAssertEqual(palHAM.normalized(pageWidth: 320, pageHeight: 256), palHAM)
    }

    func testBogusValueIsReplacedFromPageSize() {
        let junk = ILBMViewportMode(rawValue: 0x1234_0880)              // junk upper word, no 0x1000
        XCTAssertTrue(junk.isBogus)
        XCTAssertEqual(junk.normalized(pageWidth: 320, pageHeight: 200), [])
        XCTAssertEqual(junk.normalized(pageWidth: 640, pageHeight: 400), [.hires, .lace])
    }

    /// A 6-plane image with a bogus CAMG that claims HAM decodes as plain
    /// 64-colour indexed, not HAM.
    func testBogusHAMCAMGDoesNotSelectHAM() throws {
        let values: [UInt32] = [0x30, 0x05]
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 2, height: 1, planes: 6, pageWidth: 640, pageHeight: 200),
            Fixture.cmap(Fixture.grayscalePalette(64)),
            Fixture.camg(0x00AB_0800),
            Fixture.chunk("BODY", Fixture.planarRow(values, planes: 6, bytesPerRow: 2)),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.colorMode, .indexed)
        XCTAssertEqual(image.viewportMode, [.hires])
        XCTAssertEqual(image.indexedPixels, [0x30, 0x05])
    }

    /// A clean 16-bit HAM value with junk low bits still selects HAM.
    func testLegacyHAMWithJunkBitsStillSelectsHAM() throws {
        let palette: [(UInt8, UInt8, UInt8)] = (0 ..< 16).map { _ in (0, 0, 0) }
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 1, height: 1, planes: 6),
            Fixture.cmap(palette),
            Fixture.camg(0x4800 | 0x0002),                                 // SPRITES | HAM | GENLOCK_VIDEO
            Fixture.chunk("BODY", Fixture.planarRow([0b10_1111], planes: 6, bytesPerRow: 2)),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.colorMode, .holdAndModify)
        XCTAssertEqual(image.viewportMode, [.ham])
        XCTAssertEqual(Array(image.pixels[0 ..< 4]), [0xFF, 0, 0, 0xFF])   // modify red to 15
    }
}
