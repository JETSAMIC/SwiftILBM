import Foundation
@testable import SwiftILBM

/// Hand-built IFF fixtures derived from the field layouts in
/// Reference/ILBM-Format.md. Kept in code so every byte is reviewable.
enum Fixture {

    static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    static func be16(_ v: UInt16) -> [UInt8] {
        [UInt8(v >> 8), UInt8(v & 0xFF)]
    }

    /// `<id> <size> <body> [pad]`.
    static func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] {
        var out = Array(id.utf8) + be32(UInt32(body.count)) + body
        if body.count & 1 == 1 { out.append(0) }
        return out
    }

    /// A group chunk (`FORM`, `LIST`, `CAT `, `PROP`) of `type` holding `children`.
    static func group(_ id: String, _ type: String, _ children: [[UInt8]]) -> [UInt8] {
        chunk(id, Array(type.utf8) + children.flatMap { $0 })
    }

    static func form(_ type: String = "ILBM", _ chunks: [[UInt8]]) -> Data {
        Data(group("FORM", type, chunks))
    }

    static func bmhd(
        width: UInt16, height: UInt16, planes: UInt8,
        masking: UInt8 = 0, compression: UInt8 = 0, transparent: UInt16 = 0,
        xAspect: UInt8 = 10, yAspect: UInt8 = 11,
        pageWidth: UInt16 = 320, pageHeight: UInt16 = 200, flags: UInt8 = 0
    ) -> [UInt8] {
        chunk("BMHD", be16(width) + be16(height) + [0, 0, 0, 0]
              + [planes, masking, compression, flags] + be16(transparent)
              + [xAspect, yAspect] + be16(pageWidth) + be16(pageHeight))
    }

    static func cmap(_ colors: [(UInt8, UInt8, UInt8)]) -> [UInt8] {
        chunk("CMAP", colors.flatMap { [$0.0, $0.1, $0.2] })
    }

    static func camg(_ mode: UInt32) -> [UInt8] {
        chunk("CAMG", be32(mode))
    }

    /// One image row in ILBM order: `planes` plane rows of `bytesPerRow`
    /// bytes, built from per-pixel values (plane p holds bit p).
    static func planarRow(_ values: [UInt32], planes: Int, bytesPerRow: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: planes * bytesPerRow)
        for (x, v) in values.enumerated() {
            for p in 0 ..< planes where (v >> UInt32(p)) & 1 != 0 {
                out[p * bytesPerRow + x / 8] |= UInt8(0x80) >> UInt8(x % 8)
            }
        }
        return out
    }

    /// One mask-plane row: bit set (opaque) where `opaque[x]`.
    static func maskRow(_ opaque: [Bool], bytesPerRow: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytesPerRow)
        for (x, on) in opaque.enumerated() where on { out[x / 8] |= UInt8(0x80) >> UInt8(x % 8) }
        return out
    }

    static func grayscalePalette(_ count: Int) -> [(UInt8, UInt8, UInt8)] {
        (0 ..< count).map { i in let v = UInt8(truncatingIfNeeded: i * 255 / max(count - 1, 1)); return (v, v, v) }
    }

    /// A small valid indexed image, optionally compressed.
    static func indexedImage(width: Int = 19, height: Int = 3, planes: Int = 4, compressed: Bool) -> Data {
        let bpr = ((width + 15) / 16) * 2
        var body: [UInt8] = []
        for y in 0 ..< height {
            body += planarRow((0 ..< width).map { UInt32($0 * 3 + y) % UInt32(1 << planes) },
                              planes: planes, bytesPerRow: bpr)
        }
        if compressed { body = Array(BODYChunk.byteRun1Encode(Data(body))) }
        return form("ILBM", [
            bmhd(width: UInt16(width), height: UInt16(height), planes: UInt8(planes), compression: compressed ? 1 : 0),
            cmap(grayscalePalette(1 << planes)),
            chunk("BODY", body),
        ])
    }
}
