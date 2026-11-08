import XCTest
@testable import SwiftILBM

/// Property-chunk precedence and PROP scoping, Reference/ILBM-Format.md
/// sections 3.1.5 and 3.2.
final class ChunkPrecedenceTests: XCTestCase {

    private let red: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (0xFE, 0, 0)]
    private let green: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (0, 0xFE, 0)]
    private let blue: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (0, 0, 0xFE)]

    /// Pixel 0 is colour 1, pixel 1 is colour 0.
    private let body = Fixture.chunk("BODY", [0b1000_0000, 0])
    private let header = Fixture.bmhd(width: 2, height: 1, planes: 1)

    private func firstPixel(_ data: Data) throws -> [UInt8] {
        Array(try ILBMImage(data: data).pixels[0 ..< 3])
    }

    func testLastPropertyBeforeBODYWins() throws {
        let data = Fixture.form("ILBM", [header, Fixture.cmap(red), Fixture.cmap(green), body])
        XCTAssertEqual(try firstPixel(data), [0, 0xFE, 0])
    }

    func testPropertyAfterBODYIsUsedOnlyWhenNoneComesBefore() throws {
        let lateOnly = Fixture.form("ILBM", [header, body, Fixture.cmap(blue)])
        XCTAssertEqual(try firstPixel(lateOnly), [0, 0, 0xFE])
        let both = Fixture.form("ILBM", [header, Fixture.cmap(red), body, Fixture.cmap(blue)])
        XCTAssertEqual(try firstPixel(both), [0xFE, 0, 0])
    }

    func testInnerLISTPROPOverridesOuterPROP() throws {
        let outerProp = Fixture.group("PROP", "ILBM", [header, Fixture.cmap(red)])
        let innerProp = Fixture.group("PROP", "ILBM", [Fixture.cmap(green)])
        let form = Fixture.group("FORM", "ILBM", [body])
        let inner = Fixture.group("LIST", "ILBM", [innerProp, form])
        let outer = Data(Fixture.group("LIST", "ILBM", [outerProp, inner]))
        // BMHD comes from the outer PROP, CMAP from the inner one.
        XCTAssertEqual(try firstPixel(outer), [0, 0xFE, 0])
    }

    func testLastChunkInPROPWins() throws {
        let prop = Fixture.group("PROP", "ILBM", [header, Fixture.cmap(red), Fixture.cmap(blue)])
        let list = Data(Fixture.group("LIST", "ILBM", [prop, Fixture.group("FORM", "ILBM", [body])]))
        XCTAssertEqual(try firstPixel(list), [0, 0, 0xFE])
    }

    func testBODYIsNotInheritedFromPROP() {
        let prop = Fixture.group("PROP", "ILBM", [header, Fixture.cmap(red), body])
        let list = Data(Fixture.group("LIST", "ILBM", [prop, Fixture.group("FORM", "ILBM", [])]))
        XCTAssertThrowsError(try ILBMImage(data: list)) {
            XCTAssertEqual($0 as? ILBMError, .missingBODY)
        }
    }

    func testFORMColorRangesReplacePROPRanges() throws {
        func crng(low: UInt8) -> [UInt8] {
            Fixture.chunk("CRNG", [0, 0] + Fixture.be16(16384) + Fixture.be16(1) + [low, low + 3])
        }
        let prop = Fixture.group("PROP", "ILBM", [header, Fixture.cmap(red), crng(low: 1), crng(low: 2)])
        let withOwn = Fixture.group("FORM", "ILBM", [crng(low: 8), body])
        let without = Fixture.group("FORM", "ILBM", [body])
        let own = try ILBMImage(data: Data(Fixture.group("LIST", "ILBM", [prop, withOwn])))
        XCTAssertEqual(own.colorRanges.map(\.low), [8])
        let inherited = try ILBMImage(data: Data(Fixture.group("LIST", "ILBM", [prop, without])))
        XCTAssertEqual(inherited.colorRanges.map(\.low), [1, 2])
    }
}
