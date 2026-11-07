import Foundation

/// Converts decoded BODY rows into chunky pixel values and RGBA8.
///
/// Bitplane semantics: the value of the pixel at column `c` is built from the
/// bit at column `c` of each plane, plane 0 being the least significant bit:
///
///     value = plane0_bit | (plane1_bit << 1) | (plane2_bit << 2) | …
///
/// Bits are stored MSB-first within each byte (bit 7 = leftmost pixel).
enum PlanarToChunky {

    /// Geometry of a decoded BODY buffer.
    struct Layout {
        let width: Int
        let height: Int
        /// Bytes in one plane row (`BMHD.bytesPerRow`).
        let bytesPerPlaneRow: Int
        /// Bytes in one full row: every plane plus any mask plane.
        let rowStride: Int
    }

    /// Convenience used by tests: planar data without a mask plane.
    static func indexedPixels(planar: Data, bmhd: BMHDChunk) -> [UInt8] {
        let layout = Layout(
            width: Int(bmhd.width),
            height: Int(bmhd.height),
            bytesPerPlaneRow: bmhd.bytesPerRow,
            rowStride: Int(bmhd.nPlanes) * bmhd.bytesPerRow
        )
        return indexedPixels(planar: Array(planar), layout: layout, planes: min(Int(bmhd.nPlanes), 8))
    }

    /// Combine up to 8 planes into one byte per pixel, row-major.
    static func indexedPixels(planar: [UInt8], layout: Layout, planes: Int) -> [UInt8] {
        var indices = [UInt8](repeating: 0, count: layout.width * layout.height)
        guard planar.count >= layout.rowStride * layout.height else { return indices }
        planar.withUnsafeBufferPointer { src in
            indices.withUnsafeMutableBufferPointer { dst in
                for row in 0 ..< layout.height {
                    let rowStart = row * layout.rowStride
                    let outRow = row * layout.width
                    for plane in 0 ..< planes {
                        let planeStart = rowStart + plane * layout.bytesPerPlaneRow
                        let planeBit = UInt8(1) << UInt8(plane)
                        for x in 0 ..< layout.width where (src[planeStart + (x >> 3)] >> (7 - (x & 7))) & 1 != 0 {
                            dst[outRow + x] |= planeBit
                        }
                    }
                }
            }
        }
        return indices
    }

    /// Read the mask plane (stored after `planes` image planes on every row)
    /// as one alpha byte per pixel: 0xFF where the mask bit is set, else 0.
    static func maskAlpha(planar: [UInt8], layout: Layout, maskPlane: Int) -> [UInt8] {
        var alpha = [UInt8](repeating: 0xFF, count: layout.width * layout.height)
        guard planar.count >= layout.rowStride * layout.height else { return alpha }
        for row in 0 ..< layout.height {
            let planeStart = row * layout.rowStride + maskPlane * layout.bytesPerPlaneRow
            for x in 0 ..< layout.width where (planar[planeStart + (x >> 3)] >> (7 - (x & 7))) & 1 == 0 {
                alpha[row * layout.width + x] = 0
            }
        }
        return alpha
    }

    /// Decode a 24- or 32-plane "deep" ILBM. Planes 0–7 are red (plane 0 =
    /// LSB), 8–15 green, 16–23 blue and, with 32 planes, 24–31 alpha.
    static func deepRGBA(planar: [UInt8], layout: Layout, planes: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: layout.width * layout.height * 4)
        guard planar.count >= layout.rowStride * layout.height else { return rgba }
        for row in 0 ..< layout.height {
            let rowStart = row * layout.rowStride
            let outRow = row * layout.width * 4
            for plane in 0 ..< planes {
                let planeStart = rowStart + plane * layout.bytesPerPlaneRow
                let channel = plane >> 3
                let bit = UInt8(1) << UInt8(plane & 7)
                for x in 0 ..< layout.width where (planar[planeStart + (x >> 3)] >> (7 - (x & 7))) & 1 != 0 {
                    rgba[outRow + x * 4 + channel] |= bit
                }
            }
            if planes < 32 {
                for x in 0 ..< layout.width { rgba[outRow + x * 4 + 3] = 0xFF }
            }
        }
        return rgba
    }

    /// Read a PBM ("chunky") BODY: one byte per pixel, rows padded to an
    /// even length.
    static func chunkyPixels(body: [UInt8], width: Int, height: Int, rowStride: Int) -> [UInt8] {
        var indices = [UInt8](repeating: 0, count: width * height)
        guard body.count >= rowStride * height else { return indices }
        for row in 0 ..< height {
            let src = row * rowStride
            for x in 0 ..< width { indices[row * width + x] = body[src + x] }
        }
        return indices
    }

    /// Convert indexed pixels to RGBA8 using `palette`.
    ///
    /// Pixels equal to `transparentIndex` get alpha 0 (colour is kept; alpha
    /// is straight, not premultiplied). Out-of-range indices render as
    /// opaque black.
    static func rgbaPixels(
        indices: [UInt8],
        palette: [CMAPChunk.Color],
        transparentIndex: Int? = nil
    ) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: indices.count * 4)
        for (i, idx) in indices.enumerated() {
            let o = i * 4
            if Int(idx) < palette.count {
                let c = palette[Int(idx)]
                rgba[o]     = c.r
                rgba[o + 1] = c.g
                rgba[o + 2] = c.b
            }
            rgba[o + 3] = (transparentIndex == Int(idx)) ? 0 : 0xFF
        }
        return rgba
    }

    /// Decode Hold-And-Modify pixels.
    ///
    /// The top two bits of each value select the operation and the remaining
    /// `planes - 2` bits are data: `00` loads palette entry `data`, `01`
    /// modifies blue, `10` red, `11` green, holding the other two components
    /// from the pixel to the left. Every row starts from palette entry 0
    /// (the border colour). HAM6 replaces the whole 4-bit component
    /// (`data * 17`); HAM8 replaces the upper 6 bits and keeps the lower 2,
    /// as AGA hardware does.
    static func hamRGBA(codes: [UInt8], width: Int, height: Int, planes: Int, palette: [CMAPChunk.Color]) -> [UInt8] {
        let dataBits = planes - 2
        let dataMask = UInt8((1 << dataBits) - 1)
        let background = palette.first ?? CMAPChunk.Color(r: 0, g: 0, b: 0)
        var rgba = [UInt8](repeating: 0xFF, count: width * height * 4)

        @inline(__always) func modify(_ old: UInt8, _ data: UInt8) -> UInt8 {
            planes == 6 ? data &* 17 : (data << 2) | (old & 0x03)
        }

        for row in 0 ..< height {
            var r = background.r, g = background.g, b = background.b
            for x in 0 ..< width {
                let i = row * width + x
                let code = codes[i]
                let data = code & dataMask
                switch code >> UInt8(dataBits) {
                case 0:
                    if Int(data) < palette.count {
                        let c = palette[Int(data)]
                        r = c.r; g = c.g; b = c.b
                    } else {
                        r = 0; g = 0; b = 0
                    }
                case 1: b = modify(b, data)
                case 2: r = modify(r, data)
                default: g = modify(g, data)
                }
                rgba[i * 4] = r
                rgba[i * 4 + 1] = g
                rgba[i * 4 + 2] = b
            }
        }
        return rgba
    }

    /// The 64-entry Extra-Half-Brite palette: entries 0–31 from `palette`
    /// (missing entries black) and entries 32–63 the same colours with each
    /// component halved, as the hardware displays them.
    static func extraHalfbritePalette(_ palette: [CMAPChunk.Color]) -> [CMAPChunk.Color] {
        let black = CMAPChunk.Color(r: 0, g: 0, b: 0)
        let base = (0 ..< 32).map { $0 < palette.count ? palette[$0] : black }
        return base + base.map { CMAPChunk.Color(r: $0.r >> 1, g: $0.g >> 1, b: $0.b >> 1) }
    }
}
