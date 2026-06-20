import Foundation

/// Converts ILBM-style interleaved bitplanes into indexed (chunky) pixels and
/// then into a packed RGBA8 buffer using a CMAP palette.
///
/// Bitplane semantics: for a given pixel at column `c`, its color index is built
/// from the bit at column `c` of each plane:
///
///     index = (plane0_bit) | (plane1_bit << 1) | (plane2_bit << 2) | …
///
/// Bits are stored MSB-first within each byte (bit 7 = pixel 0).
enum PlanarToChunky {
    /// Convert the raw planar bitmap (bitplanes already stripped of any mask
    /// plane) into a row-major `[UInt8]` of palette indices, length width*height.
    static func indexedPixels(
        planar: Data,
        bmhd: BMHDChunk
    ) -> [UInt8] {
        let width = Int(bmhd.width)
        let height = Int(bmhd.height)
        let planes = Int(bmhd.nPlanes)
        let bytesPerRow = bmhd.bytesPerRow

        var indices = [UInt8](repeating: 0, count: width * height)

        let base = planar.startIndex

        for row in 0 ..< height {
            // Each row contains `planes` consecutive plane-rows in BODY order.
            let rowStart = base + row * planes * bytesPerRow

            for plane in 0 ..< planes {
                let planeRowStart = rowStart + plane * bytesPerRow
                let planeMask: UInt8 = UInt8(1 << plane)

                for x in 0 ..< width {
                    let byte = planar[planeRowStart + (x >> 3)]
                    let bit = (byte >> (7 - (x & 7))) & 1
                    if bit != 0 {
                        indices[row * width + x] |= planeMask
                    }
                }
            }
        }
        return indices
    }

    /// Convert indexed pixels to a packed RGBA8 buffer using the supplied palette.
    /// If `transparentIndex` is non-nil, pixels matching it get alpha = 0.
    /// Out-of-range indices (palette too small) render as opaque black.
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
                rgba[o + 3] = (transparentIndex == Int(idx)) ? 0 : 0xFF
            } else {
                // Defensive: bad index → opaque black rather than throwing.
                rgba[o + 3] = 0xFF
            }
        }
        return rgba
    }
}
