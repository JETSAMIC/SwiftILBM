import Foundation

/// Decoded "CMAP" (Color MAP) chunk: an array of RGB triplets, one byte per channel.
///
/// Older Amiga ILBMs only meaningfully used the high nibble of each channel
/// (OCS/ECS hardware was 4 bits per gun), so colors often look like 0x00, 0x10,
/// 0x20, … 0xF0. We do **not** auto-expand those — apps that care can detect
/// "all values & 0x0F == 0" and shift if desired.
public struct CMAPChunk: Sendable, Equatable {
    public struct Color: Sendable, Equatable {
        public let r: UInt8
        public let g: UInt8
        public let b: UInt8
        public init(r: UInt8, g: UInt8, b: UInt8) {
            self.r = r; self.g = g; self.b = b
        }
    }

    public let colors: [Color]

    /// Parse a CMAP payload. Each entry is exactly 3 bytes (R, G, B). A truncated
    /// trailing entry (1–2 leftover bytes) is ignored, matching common decoders.
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
}
