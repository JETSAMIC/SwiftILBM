import Foundation

/// Amiga display-mode flags from the `CAMG` (Commodore Amiga) chunk.
///
/// `CAMG` holds a 32-bit `ULONG` of viewport mode bits. Only ``ham`` and
/// ``extraHalfbrite`` change how pixels are decoded; the resolution flags
/// describe the original display and are exposed for aspect-ratio handling.
public struct ILBMViewportMode: OptionSet, Sendable, Hashable {
    /// The raw 32-bit `CAMG` value.
    public let rawValue: UInt32

    /// Creates a mode from a raw `CAMG` value.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// `0x0004` — interlaced (doubled vertical resolution).
    public static let lace = ILBMViewportMode(rawValue: 0x0004)
    /// `0x0020` — super-high-resolution (ECS, 1280 pixels).
    public static let superHires = ILBMViewportMode(rawValue: 0x0020)
    /// `0x0080` — Extra-Half-Brite: with 6 planes, indices 32...63 show
    /// colours 0...31 at half brightness.
    public static let extraHalfbrite = ILBMViewportMode(rawValue: 0x0080)
    /// `0x0400` — dual playfield. Not interpreted by SwiftILBM; such images
    /// decode as ordinary indexed images.
    public static let dualPlayfield = ILBMViewportMode(rawValue: 0x0400)
    /// `0x0800` — Hold-And-Modify (HAM6 with 6 planes, HAM8 with 8 planes).
    public static let ham = ILBMViewportMode(rawValue: 0x0800)
    /// `0x8000` — high resolution (640 pixels).
    public static let hires = ILBMViewportMode(rawValue: 0x8000)

    /// Parse a `CAMG` payload.
    ///
    /// - Parameter data: At least 4 bytes (big-endian `ULONG`).
    /// - Throws: ``ILBMError/truncated(stage:)`` if shorter than 4 bytes.
    public init(camg data: Data) throws {
        guard data.count >= 4 else { throw ILBMError.truncated(stage: "CAMG") }
        self.init(rawValue: IFFParser.beUInt32(data, at: 0))
    }
}

/// A colour-cycling range from a `CRNG` chunk (Deluxe Paint).
///
/// SwiftILBM decodes the static image; ranges are exposed so callers can
/// animate the palette themselves.
public struct ILBMColorRange: Sendable, Hashable {
    /// Cycling speed: 16384 means 60 steps per second; 0 means no cycling.
    public let rate: Int16
    /// Raw flags: bit 0 = active, bit 1 = reverse direction.
    public let flags: Int16
    /// First palette index in the range.
    public let low: UInt8
    /// Last palette index in the range (inclusive).
    public let high: UInt8

    /// Whether cycling is enabled for this range (`flags & 1`).
    public var isActive: Bool { flags & 0x1 != 0 }
    /// Whether colours cycle downwards (`flags & 2`).
    public var isReversed: Bool { flags & 0x2 != 0 }
    /// Steps per second (`rate * 60 / 16384`).
    public var stepsPerSecond: Double { Double(rate) * 60.0 / 16384.0 }

    /// Creates a range from explicit values.
    public init(rate: Int16, flags: Int16, low: UInt8, high: UInt8) {
        self.rate = rate
        self.flags = flags
        self.low = low
        self.high = high
    }

    /// Parse a `CRNG` payload (`WORD pad, rate, flags; UBYTE low, high`).
    ///
    /// - Parameter data: The chunk body.
    /// - Returns: `nil` if the payload is shorter than 8 bytes.
    public init?(crng data: Data) {
        guard data.count >= 8 else { return nil }
        self.init(
            rate: IFFParser.beInt16(data, at: 2),
            flags: IFFParser.beInt16(data, at: 4),
            low: data[data.startIndex + 6],
            high: data[data.startIndex + 7]
        )
    }
}
