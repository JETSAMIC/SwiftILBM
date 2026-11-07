import XCTest
@testable import SwiftILBM

/// One test per spec feature added or fixed in the production-readiness
/// audit. Fixtures are built byte-by-byte from Reference/ILBM-Format.md.
final class SpecConformanceTests: XCTestCase {

    private func rgba(_ image: ILBMImage, _ x: Int, _ y: Int = 0) -> [UInt8] {
        let i = (y * image.width + x) * 4
        return Array(image.pixels[i ..< i + 4])
    }

    private let twoColor: [(UInt8, UInt8, UInt8)] = [(0x11, 0x22, 0x33), (0xAA, 0xBB, 0xCC)]

    // MARK: - IFF container

    func testUnknownAndOddLengthChunksAreSkipped() throws {
        let data = Fixture.form("ILBM", [
            Fixture.chunk("ANNO", Array("odd".utf8)),          // 3 bytes + pad
            Fixture.bmhd(width: 2, height: 1, planes: 1),
            Fixture.chunk("DPI ", [0, 72, 0, 72]),
            Fixture.cmap(twoColor),
            Fixture.chunk("BODY", [0b0100_0000, 0]),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.indexedPixels, [0, 1])
        XCTAssertEqual(rgba(image, 1), [0xAA, 0xBB, 0xCC, 0xFF])
    }

    func testChunkSizeBeyondContainerThrows() {
        var bytes = [UInt8](Fixture.indexedImage(compressed: false))
        // Find "BODY" and inflate its size field.
        let range = bytes.indices.first { Array(bytes[$0 ..< $0 + 4]) == Array("BODY".utf8) }!
        bytes.replaceSubrange(range + 4 ..< range + 8, with: Fixture.be32(0xFFFF_FFF0))
        XCTAssertThrowsError(try ILBMImage(data: Data(bytes))) { err in
            XCTAssertEqual(err as? ILBMError, .truncated(stage: "chunk BODY"))
        }
    }

    func testOversizedFORMSizeIsClampedToBuffer() throws {
        var bytes = [UInt8](Fixture.indexedImage(compressed: true))
        bytes.replaceSubrange(4 ..< 8, with: Fixture.be32(0xFFFF_FFFF))
        XCTAssertNoThrow(try ILBMImage(data: Data(bytes)))
    }

    func testLISTWithPROPSuppliesSharedChunks() throws {
        let prop = Fixture.group("PROP", "ILBM", [
            Fixture.bmhd(width: 2, height: 1, planes: 1),
            Fixture.cmap(twoColor),
        ])
        let form = Fixture.group("FORM", "ILBM", [Fixture.chunk("BODY", [0b1000_0000, 0])])
        let list = Data(Fixture.group("LIST", "ILBM", [prop, form]))
        let image = try ILBMImage(data: list)
        XCTAssertEqual(image.indexedPixels, [1, 0])
    }

    func testFORMChunksOverridePROPDefaults() throws {
        let prop = Fixture.group("PROP", "ILBM", [Fixture.cmap([(1, 1, 1), (2, 2, 2)])])
        let form = Fixture.group("FORM", "ILBM", [
            Fixture.bmhd(width: 2, height: 1, planes: 1),
            Fixture.cmap(twoColor),
            Fixture.chunk("BODY", [0b1000_0000, 0]),
        ])
        let image = try ILBMImage(data: Data(Fixture.group("LIST", "ILBM", [prop, form])))
        XCTAssertEqual(rgba(image, 0), [0xAA, 0xBB, 0xCC, 0xFF])
    }

    func testFirstFrameOfANIMAndCATAreFound() throws {
        let ilbm = [UInt8](Fixture.indexedImage(compressed: true))
        let anim = Data(Fixture.group("FORM", "ANIM", [ilbm]))
        let cat = Data(Fixture.group("CAT ", "    ", [Fixture.group("FORM", "8SVX", []), ilbm]))
        XCTAssertEqual(try ILBMImage(data: anim).width, 19)
        XCTAssertEqual(try ILBMImage(data: cat).width, 19)
    }

    func testDataSliceIsHandled() throws {
        let file = Fixture.indexedImage(compressed: true)
        let padded = Data([0xEE, 0xEE]) + file
        XCTAssertEqual(try ILBMImage(data: padded[2...]), try ILBMImage(data: file))
        XCTAssertEqual(try IFFParser.parse(padded[2...]), try IFFParser.parse(file))
    }

    // MARK: - BMHD

    func testBMHDEnumsAndAspect() throws {
        let raw = Data(Fixture.bmhd(width: 17, height: 1, planes: 3, masking: 2, compression: 1,
                                    transparent: 5, xAspect: 10, yAspect: 11).dropFirst(8))
        let bmhd = try BMHDChunk(data: raw)
        XCTAssertEqual(bmhd.maskingMode, .hasTransparentColor)
        XCTAssertEqual(bmhd.compressionMode, .byteRun1)
        XCTAssertEqual(bmhd.bytesPerRow, 4)               // ((17 + 15) / 16) * 2
        XCTAssertEqual(bmhd.pixelAspectRatio ?? 0, 10.0 / 11.0, accuracy: 1e-9)
        XCTAssertEqual(bmhd.pageWidth, 320)
    }

    func testUndefinedMaskingAndCompressionThrow() {
        let body = Fixture.chunk("BODY", [0, 0])
        let badMask = Fixture.form("ILBM", [Fixture.bmhd(width: 2, height: 1, planes: 1, masking: 4),
                                            Fixture.cmap(twoColor), body])
        XCTAssertThrowsError(try ILBMImage(data: badMask)) {
            XCTAssertEqual($0 as? ILBMError, .unsupportedMasking(4))
        }
        let badCompression = Fixture.form("ILBM", [Fixture.bmhd(width: 2, height: 1, planes: 1, compression: 2),
                                                   Fixture.cmap(twoColor), body])
        XCTAssertThrowsError(try ILBMImage(data: badCompression)) {
            XCTAssertEqual($0 as? ILBMError, .unsupportedCompression(2))
        }
    }

    // MARK: - Masking

    func testMaskPlaneIsInterleavedAfterBitplanesAndBecomesAlpha() throws {
        // 3 px, 2 planes + mask. Mask: opaque, transparent, opaque.
        let row = Fixture.planarRow([1, 2, 3], planes: 2, bytesPerRow: 2)
            + Fixture.maskRow([true, false, true], bytesPerRow: 2)
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 3, height: 1, planes: 2, masking: 1),
            Fixture.cmap([(0, 0, 0), (10, 0, 0), (0, 20, 0), (0, 0, 30)]),
            Fixture.chunk("BODY", row),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.indexedPixels, [1, 2, 3])
        XCTAssertEqual(rgba(image, 0), [10, 0, 0, 0xFF])
        XCTAssertEqual(rgba(image, 1), [0, 20, 0, 0])
        XCTAssertEqual(rgba(image, 2), [0, 0, 30, 0xFF])
    }

    func testTransparentColorAndLasso() throws {
        func make(masking: UInt8) -> Data {
            Fixture.form("ILBM", [
                Fixture.bmhd(width: 2, height: 1, planes: 1, masking: masking, transparent: 1),
                Fixture.cmap(twoColor),
                Fixture.chunk("BODY", [0b0100_0000, 0]),
            ])
        }
        let transparent = try ILBMImage(data: make(masking: 2))
        XCTAssertEqual(rgba(transparent, 1), [0xAA, 0xBB, 0xCC, 0])
        XCTAssertEqual(rgba(transparent, 0)[3], 0xFF)
        let lasso = try ILBMImage(data: make(masking: 3))
        XCTAssertEqual(rgba(lasso, 1)[3], 0xFF)
    }

    // MARK: - ByteRun1

    func testByteRun1RunsMayCrossRowBoundaries() throws {
        // 16x2, 1 plane: one replicate packet covering both rows (4 bytes).
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 16, height: 2, planes: 1, compression: 1),
            Fixture.cmap(twoColor),
            Fixture.chunk("BODY", [UInt8(bitPattern: -3), 0xFF]),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.indexedPixels, [UInt8](repeating: 1, count: 32))
    }

    func testByteRun1BombIsRejectedBeforeAllocation() {
        XCTAssertThrowsError(try BODYChunk.byteRun1Decode(Data([0x81, 0x00]), expectedSize: 1 << 30)) {
            XCTAssertEqual($0 as? ILBMError, .malformedRLE)
        }
    }

    // MARK: - CMAP

    func testLeftJustified4BitPaletteIsExpanded() throws {
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 2, height: 1, planes: 1),
            Fixture.cmap([(0x00, 0x00, 0x00), (0xF0, 0x80, 0x10)]),
            Fixture.chunk("BODY", [0b0100_0000, 0]),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.palette[1], CMAPChunk.Color(r: 0xFF, g: 0x88, b: 0x11))
        XCTAssertEqual(rgba(image, 1), [0xFF, 0x88, 0x11, 0xFF])

        let raw = try ILBMImage(data: data, options: .init(expandsLeftJustified4BitPalettes: false))
        XCTAssertEqual(raw.palette[1], CMAPChunk.Color(r: 0xF0, g: 0x80, b: 0x10))
    }

    func testFull8BitPaletteIsNotExpanded() {
        let cmap = CMAPChunk(colors: [.init(r: 0xF0, g: 0x80, b: 0x11)])
        XCTAssertFalse(cmap.isLeftJustified4Bit)
        XCTAssertEqual(cmap.expandingLeftJustified4Bit(), cmap)
        XCTAssertFalse(CMAPChunk(colors: [.init(r: 0, g: 0, b: 0)]).isLeftJustified4Bit)
    }

    // MARK: - CAMG: HAM, EHB

    func testHAM6() throws {
        // codes: load palette 1; modify red 0xF; modify green 0x8; modify blue 0x3
        let codes: [UInt32] = [0b00_0001, 0b10_1111, 0b11_1000, 0b01_0011]
        var palette = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 16)
        palette[0] = (0x10, 0x20, 0x30)
        palette[1] = (0x11, 0x22, 0x33)
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 4, height: 1, planes: 6),
            Fixture.cmap(palette),
            Fixture.camg(0x0800),
            Fixture.chunk("BODY", Fixture.planarRow(codes, planes: 6, bytesPerRow: 2)),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.colorMode, .holdAndModify)
        XCTAssertEqual(image.viewportMode, .ham)
        XCTAssertEqual(rgba(image, 0), [0x11, 0x22, 0x33, 0xFF])
        XCTAssertEqual(rgba(image, 1), [0xFF, 0x22, 0x33, 0xFF])
        XCTAssertEqual(rgba(image, 2), [0xFF, 0x88, 0x33, 0xFF])
        XCTAssertEqual(rgba(image, 3), [0xFF, 0x88, 0x33, 0xFF])
    }

    func testHAM6RowStartsFromBackgroundColor() throws {
        // Row 0 and row 1 each begin with "modify red"; green/blue come from palette[0].
        var palette = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 16)
        palette[0] = (0x12, 0x21, 0x31)   // low nibbles set: no 4-bit expansion
        let row: [UInt32] = [0b10_0101]
        let body = Fixture.planarRow(row, planes: 6, bytesPerRow: 2) + Fixture.planarRow(row, planes: 6, bytesPerRow: 2)
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 1, height: 2, planes: 6),
            Fixture.cmap(palette), Fixture.camg(0x0800), Fixture.chunk("BODY", body),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(rgba(image, 0, 1), [0x55, 0x21, 0x31, 0xFF])
    }

    func testHAM8KeepsLowTwoBits() throws {
        // palette[2] = (0x03, 0x02, 0x01); then modify red with data 0x3F.
        var palette = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 64)
        palette[2] = (0x03, 0x02, 0x01)
        let codes: [UInt32] = [0b00_000010, 0b10_111111, 0b01_000001]
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 3, height: 1, planes: 8),
            Fixture.cmap(palette), Fixture.camg(0x0800),
            Fixture.chunk("BODY", Fixture.planarRow(codes, planes: 8, bytesPerRow: 2)),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(rgba(image, 0), [0x03, 0x02, 0x01, 0xFF])
        XCTAssertEqual(rgba(image, 1), [0xFF, 0x02, 0x01, 0xFF])
        XCTAssertEqual(rgba(image, 2), [0xFF, 0x02, 0x05, 0xFF])   // (1 << 2) | (0x01 & 3)
    }

    func testHAMWithUnsupportedPlaneCountThrows() {
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 1, height: 1, planes: 7),
            Fixture.cmap(twoColor), Fixture.camg(0x0800),
            Fixture.chunk("BODY", [UInt8](repeating: 0, count: 14)),
        ])
        XCTAssertThrowsError(try ILBMImage(data: data)) {
            XCTAssertEqual($0 as? ILBMError, .unsupportedDepth(7))
        }
    }

    func testExtraHalfbriteFromCAMGAndHeuristic() throws {
        var palette = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: 32)
        palette[1] = (0xFE, 0x80, 0x41)
        let body = Fixture.planarRow([1, 33], planes: 6, bytesPerRow: 2)
        for extra in [[Fixture.camg(0x0080)], []] {
            let data = Fixture.form("ILBM", [
                Fixture.bmhd(width: 2, height: 1, planes: 6), Fixture.cmap(palette),
            ] + extra + [Fixture.chunk("BODY", body)])
            let image = try ILBMImage(data: data)
            XCTAssertEqual(image.colorMode, .extraHalfbrite)
            XCTAssertEqual(image.indexedPixels, [1, 33])
            XCTAssertEqual(rgba(image, 0), [0xFE, 0x80, 0x41, 0xFF])
            XCTAssertEqual(rgba(image, 1), [0x7F, 0x40, 0x20, 0xFF])
        }
    }

    func testResolutionFlagsAreExposedButDoNotChangeDecoding() throws {
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 2, height: 1, planes: 1), Fixture.cmap(twoColor),
            Fixture.camg(0x8004), Fixture.chunk("BODY", [0b0100_0000, 0]),
        ])
        let image = try ILBMImage(data: data)
        XCTAssertEqual(image.viewportMode, [.hires, .lace])
        XCTAssertEqual(image.colorMode, .indexed)
    }

    // MARK: - Deep ILBM

    func testTrueColor24And32Planes() throws {
        let px: UInt32 = 0x56_34_12          // planes 0-7 red=0x12, 8-15 green=0x34, 16-23 blue=0x56
        let deep24 = Fixture.form("ILBM", [
            Fixture.bmhd(width: 1, height: 1, planes: 24),
            Fixture.chunk("BODY", Fixture.planarRow([px], planes: 24, bytesPerRow: 2)),
        ])
        let image24 = try ILBMImage(data: deep24)
        XCTAssertEqual(image24.colorMode, .trueColor)
        XCTAssertNil(image24.indexedPixels)
        XCTAssertEqual(rgba(image24, 0), [0x12, 0x34, 0x56, 0xFF])

        let deep32 = Fixture.form("ILBM", [
            Fixture.bmhd(width: 1, height: 1, planes: 32, compression: 1),
            Fixture.chunk("BODY", [UInt8](BODYChunk.byteRun1Encode(
                Data(Fixture.planarRow([0x80_56_34_12], planes: 32, bytesPerRow: 2))))),
        ])
        XCTAssertEqual(rgba(try ILBMImage(data: deep32), 0), [0x12, 0x34, 0x56, 0x80])
    }

    // MARK: - PBM

    func testPBMChunkyRowsArePaddedToEvenWidth() throws {
        // 3x2, rows padded to 4 bytes.
        let raw: [UInt8] = [0, 1, 2, 0xEE, 2, 1, 0, 0xEE]
        for compressed in [false, true] {
            let body = compressed ? [UInt8](BODYChunk.byteRun1Encode(Data(raw))) : raw
            let data = Fixture.form("PBM ", [
                Fixture.bmhd(width: 3, height: 2, planes: 8, compression: compressed ? 1 : 0),
                Fixture.cmap([(9, 0, 0), (0, 9, 0), (0, 0, 9)]),
                Fixture.chunk("BODY", body),
            ])
            let image = try ILBMImage(data: data)
            XCTAssertEqual(image.formType, .pbm)
            XCTAssertEqual(image.indexedPixels, [0, 1, 2, 2, 1, 0])
            XCTAssertEqual(rgba(image, 2, 0), [0, 0, 9, 0xFF])
        }
    }

    func testPBMWithMaskPlaneIsRejected() {
        let data = Fixture.form("PBM ", [
            Fixture.bmhd(width: 2, height: 1, planes: 8, masking: 1),
            Fixture.cmap(twoColor), Fixture.chunk("BODY", [0, 1]),
        ])
        XCTAssertThrowsError(try ILBMImage(data: data)) {
            XCTAssertEqual($0 as? ILBMError, .unsupportedMasking(1))
        }
    }

    // MARK: - CRNG

    func testColorRangesAreParsed() throws {
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 2, height: 1, planes: 1), Fixture.cmap(twoColor),
            Fixture.chunk("CRNG", [0, 0] + Fixture.be16(16384) + Fixture.be16(3) + [4, 9]),
            Fixture.chunk("CRNG", [0, 0]),                     // malformed: ignored
            Fixture.chunk("BODY", [0, 0]),
        ])
        let ranges = try ILBMImage(data: data).colorRanges
        XCTAssertEqual(ranges, [ILBMColorRange(rate: 16384, flags: 3, low: 4, high: 9)])
        XCTAssertTrue(ranges[0].isActive && ranges[0].isReversed)
        XCTAssertEqual(ranges[0].stepsPerSecond, 60, accuracy: 1e-9)
    }

    // MARK: - Size guards

    func testHugeDimensionsAreRejectedBeforeAllocation() {
        let data = Fixture.form("ILBM", [
            Fixture.bmhd(width: 65535, height: 65535, planes: 8, compression: 1),
            Fixture.cmap(twoColor), Fixture.chunk("BODY", [0x81, 0]),
        ])
        XCTAssertThrowsError(try ILBMImage(data: data)) {
            XCTAssertEqual($0 as? ILBMError,
                           .imageTooLarge(width: 65535, height: 65535, limit: ILBMImage.defaultMaximumPixelCount))
        }
    }

    func testBodyTooShortForDeclaredSizeThrows() {
        for compression: UInt8 in [0, 1] {
            let data = Fixture.form("ILBM", [
                Fixture.bmhd(width: 4096, height: 4096, planes: 32, compression: compression),
                Fixture.chunk("BODY", [0x81, 0]),
            ])
            XCTAssertThrowsError(try ILBMImage(data: data))
        }
    }

    func testPixelLimitIsConfigurable() throws {
        let data = Fixture.indexedImage(compressed: true)   // 19 x 3 = 57 px
        XCTAssertThrowsError(try ILBMImage(data: data, options: .init(maximumPixelCount: 56)))
        XCTAssertNoThrow(try ILBMImage(data: data, options: .init(maximumPixelCount: 57)))
    }

    // MARK: - Output

    #if canImport(CoreGraphics)
    func testCGImageUsesStraightAlpha() throws {
        let image = try ILBMImage(data: Fixture.indexedImage(compressed: false))
        let cg = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cg.alphaInfo, .last)
        XCTAssertEqual(cg.width, 19)
    }
    #endif
}
