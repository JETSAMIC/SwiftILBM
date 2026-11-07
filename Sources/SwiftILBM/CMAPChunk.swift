import Foundation

/// The decoded `CMAP` (colour map) chunk: RGB triplets, one byte per channel.
public struct CMAPChunk: Sendable, Equatable {

    /// One palette entry, 8 bits per channel.
    public struct Color: Sendable, Equatable, Hashable {
        /// Red component, 0...255.
        public let r: UInt8
        /// Green component, 0...255.
        public let g: UInt8
        /// Blue component, 0...255.
        public let b: UInt8

        /// Creates a colour from its components (0...255).
        public init(r: UInt8, g: UInt8, b: UInt8) {
            self.r = r; self.g = g; self.b = b
        }
    }

    /// The entries in index order, exactly as stored in the file.
    public let colors: [Color]

    /// Parse a `CMAP` payload.
    ///
    /// - Parameter data: The chunk body. Each entry is 3 bytes (R, G, B); a
    ///   truncated trailing entry (1–2 leftover bytes) is ignored, matching
    ///   common decoders.
    public init(data: Data) {
        let count = data.count / 3
        var result: [Color] = []
        result.reserveCapacity(count)
        for i in 0 ..< count {
            let base = data.startIndex + i * 3
            result.append(Color(r: data[base], g: data[base + 1], b: data[base + 2]))
        }
        self.colors = result
    }

    /// Creates a colour map from explicit entries.
    public init(colors: [Color]) {
        self.colors = colors
    }

    /// Whether this looks like a 4-bit-per-gun (OCS/ECS) palette stored
    /// left-justified: every component's low nibble is zero and at least one
    /// component is non-zero. Such palettes peak at `0xF0` instead of `0xFF`.
    public var isLeftJustified4Bit: Bool {
        var anyNonZero = false
        for c in colors {
            if (c.r | c.g | c.b) & 0x0F != 0 { return false }
            if (c.r | c.g | c.b) != 0 { anyNonZero = true }
        }
        return anyNonZero
    }

    /// The palette with 4-bit components scaled to the full 8-bit range
    /// (`0xF0` → `0xFF`, by copying the high nibble into the low nibble) if
    /// ``isLeftJustified4Bit``; otherwise `self` unchanged.
    ///
    /// OCS/ECS hardware has 4 bits per gun, and much software of that era
    /// stored a 4-bit value `n` as `n << 4`; scaling to `n * 17` restores
    /// full-range colour (white becomes `0xFF`, not `0xF0`).
    public func expandingLeftJustified4Bit() -> CMAPChunk {
        guard isLeftJustified4Bit else { return self }
        return CMAPChunk(colors: colors.map {
            Color(r: $0.r | ($0.r >> 4), g: $0.g | ($0.g >> 4), b: $0.b | ($0.b >> 4))
        })
    }
}
