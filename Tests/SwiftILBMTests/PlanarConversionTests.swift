import XCTest
@testable import SwiftILBM

final class PlanarConversionTests: XCTestCase {

    /// Build a BMHD with the given dimensions and plane count, no compression,
    /// no masking. Useful for synthetic planar inputs.
    private func makeBMHD(width: UInt16, height: UInt16, planes: UInt8) throws -> BMHDChunk {
        var d = Data()
        d.append(contentsOf: [UInt8(width >> 8), UInt8(width & 0xFF)])
        d.append(contentsOf: [UInt8(height >> 8), UInt8(height & 0xFF)])
        d.append(contentsOf: [0, 0, 0, 0])               // x, y
        d.append(contentsOf: [planes, 0, 0, 0])           // nPlanes, masking, compression, pad
        d.append(contentsOf: [0, 0])                      // transparentColor
        d.append(contentsOf: [1, 1])                      // aspect
        d.append(contentsOf: [0, 0, 0, 0])                // pageW, pageH
        return try BMHDChunk(data: d)
    }

    /// Single-plane, 16×1: alternating pixels on/off.
    /// Plane row = 0b10101010 0b10101010 = 0xAA 0xAA.
    /// Expected indices: 1,0,1,0,1,0,1,0, 1,0,1,0,1,0,1,0
    func testSinglePlane16x1Alternating() throws {
        let bmhd = try makeBMHD(width: 16, height: 1, planes: 1)
        XCTAssertEqual(bmhd.bytesPerRow, 2)
        let planar = Data([0xAA, 0xAA])
        let indices = PlanarToChunky.indexedPixels(planar: planar, bmhd: bmhd)
        XCTAssertEqual(indices, [1, 0, 1, 0, 1, 0, 1, 0,
                                  1, 0, 1, 0, 1, 0, 1, 0])
    }

    /// 4-plane, 8×1. Bit at column c of plane p = (p == c % 4) ? 1 : 0.
    /// Plane 0 has bits set at columns 0 and 4 → byte 0b10001000 = 0x88
    /// Plane 1 has bits set at columns 1 and 5 → 0b01000100 = 0x44
    /// Plane 2 has bits set at columns 2 and 6 → 0b00100010 = 0x22
    /// Plane 3 has bits set at columns 3 and 7 → 0b00010001 = 0x11
    /// Expected indices: 1,2,4,8, 1,2,4,8
    func testFourPlane8x1() throws {
        let bmhd = try makeBMHD(width: 8, height: 1, planes: 4)
        XCTAssertEqual(bmhd.bytesPerRow, 2) // word-padded even for w=8
        // Each plane row is 2 bytes (only first significant). Order: plane0, plane1, plane2, plane3.
        let planar = Data([0x88, 0x00,
                           0x44, 0x00,
                           0x22, 0x00,
                           0x11, 0x00])
        let indices = PlanarToChunky.indexedPixels(planar: planar, bmhd: bmhd)
        XCTAssertEqual(indices, [1, 2, 4, 8, 1, 2, 4, 8])
    }

    /// Two-row, two-plane sanity check: ensures row striding by `planes * bytesPerRow`.
    /// 16×2, 2 planes. Row 0 plane 0 = 0xFF 0x00 → first 8 px have plane0 bit set.
    /// Row 0 plane 1 = 0x00 0x00 → none.
    /// Row 1 plane 0 = 0x00 0x00 → none.
    /// Row 1 plane 1 = 0xFF 0x00 → first 8 px have plane1 bit (value 2).
    func testTwoRowStride() throws {
        let bmhd = try makeBMHD(width: 16, height: 2, planes: 2)
        let planar = Data([
            0xFF, 0x00,   // row 0, plane 0
            0x00, 0x00,   // row 0, plane 1
            0x00, 0x00,   // row 1, plane 0
            0xFF, 0x00    // row 1, plane 1
        ])
        let indices = PlanarToChunky.indexedPixels(planar: planar, bmhd: bmhd)
        XCTAssertEqual(indices.count, 32)
        // Row 0: first 8 = 1, next 8 = 0
        XCTAssertEqual(Array(indices[0..<8]),  Array(repeating: UInt8(1), count: 8))
        XCTAssertEqual(Array(indices[8..<16]), Array(repeating: UInt8(0), count: 8))
        // Row 1: first 8 = 2, next 8 = 0
        XCTAssertEqual(Array(indices[16..<24]), Array(repeating: UInt8(2), count: 8))
        XCTAssertEqual(Array(indices[24..<32]), Array(repeating: UInt8(0), count: 8))
    }

    /// Palette lookup turns indices into expected RGBA bytes.
    func testRGBAExpansion() {
        let palette: [CMAPChunk.Color] = [
            .init(r: 0x00, g: 0x00, b: 0x00),
            .init(r: 0xFF, g: 0x00, b: 0x00),
            .init(r: 0x00, g: 0xFF, b: 0x00)
        ]
        let rgba = PlanarToChunky.rgbaPixels(indices: [0, 1, 2], palette: palette)
        XCTAssertEqual(rgba, [
            0x00, 0x00, 0x00, 0xFF,
            0xFF, 0x00, 0x00, 0xFF,
            0x00, 0xFF, 0x00, 0xFF
        ])
    }

    /// Transparent index produces alpha=0.
    func testTransparentIndex() {
        let palette: [CMAPChunk.Color] = [
            .init(r: 0xAB, g: 0xCD, b: 0xEF),
            .init(r: 0x11, g: 0x22, b: 0x33)
        ]
        let rgba = PlanarToChunky.rgbaPixels(indices: [0, 1, 0], palette: palette, transparentIndex: 0)
        XCTAssertEqual(rgba, [
            0xAB, 0xCD, 0xEF, 0x00,
            0x11, 0x22, 0x33, 0xFF,
            0xAB, 0xCD, 0xEF, 0x00
        ])
    }
}
