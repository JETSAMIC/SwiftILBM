import Foundation

/// Amiga display-mode flags from the `CAMG` (Commodore Amiga) chunk.
///
/// `CAMG` holds a 32-bit `ULONG`: a 16-bit `ViewPort` mode in files from
/// before AmigaOS 2.0, or a display-database mode ID (monitor ID in the upper
/// word) after it. Only ``ham`` and ``extraHalfbrite`` change how pixels are
/// decoded; the resolution flags describe the original display and are
/// exposed for aspect-ratio handling.
public struct ILBMViewportMode: OptionSet, Sendable, Hashable {
    /// The raw 32-bit `CAMG` value.
    public let rawValue: UInt32

    /// Creates a mode from a raw `CAMG` value.
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// `0x0002` — genlock video. No effect on pixels; removed by
    /// ``normalized(pageWidth:pageHeight:)`` from 16-bit values.
    public static let genlockVideo = ILBMViewportMode(rawValue: 0x0002)
    /// `0x0004` — interlaced (doubled vertical resolution).
    public static let lace = ILBMViewportMode(rawValue: 0x0004)
    /// `0x0020` — super-high-resolution (ECS, 1280 pixels).
    public static let superHires = ILBMViewportMode(rawValue: 0x0020)
    /// `0x0040` — playfield 2 has priority (dual playfield only).
    public static let playfield2Priority = ILBMViewportMode(rawValue: 0x0040)
    /// `0x0080` — Extra-Half-Brite: with 6 planes, indices 32...63 show
    /// colours 0...31 at half brightness.
    public static let extraHalfbrite = ILBMViewportMode(rawValue: 0x0080)
    /// `0x0100` — genlock audio. No effect on pixels; removed by
    /// ``normalized(pageWidth:pageHeight:)`` from 16-bit values.
    public static let genlockAudio = ILBMViewportMode(rawValue: 0x0100)
    /// `0x0400` — dual playfield. Not interpreted by SwiftILBM; such images
    /// decode as ordinary indexed images.
    public static let dualPlayfield = ILBMViewportMode(rawValue: 0x0400)
    /// `0x0800` — Hold-And-Modify (HAM6 with 6 planes, HAM8 with 8 planes).
    public static let ham = ILBMViewportMode(rawValue: 0x0800)
    /// `0x1000` — extended mode. In a 16-bit value it carries no display
    /// meaning; in an AmigaOS 2.0+ mode ID it is part of every monitor ID.
    public static let extendedMode = ILBMViewportMode(rawValue: 0x1000)
    /// `0x2000` — viewport hidden. No effect on pixels.
    public static let viewportHidden = ILBMViewportMode(rawValue: 0x2000)
    /// `0x4000` — sprites. No effect on pixels.
    public static let sprites = ILBMViewportMode(rawValue: 0x4000)
    /// `0x8000` — high resolution (640 pixels).
    public static let hires = ILBMViewportMode(rawValue: 0x8000)

    /// The bits that are not display modes in a pre-2.0 16-bit value:
    /// ``extendedMode``, ``sprites``, ``viewportHidden``, ``genlockAudio``
    /// and ``genlockVideo`` (`0x7102`).
    public static let nonDisplayBits: ILBMViewportMode = [
        .extendedMode, .sprites, .viewportHidden, .genlockAudio, .genlockVideo,
    ]

    /// Whether this is a corrupt value of the kind some brush writers
    /// produced: junk in the upper 16 bits without ``extendedMode`` set.
    /// Every genuine AmigaOS 2.0+ mode ID with a non-zero upper word has
    /// bit `0x1000` set.
    public var isBogus: Bool {
        rawValue & 0xFFFF_0000 != 0 && rawValue & ILBMViewportMode.extendedMode.rawValue == 0
    }

    /// The mode a reader should use, after the clean-up rules Commodore added
    /// to the ILBM specification in 1988.
    ///
    /// - A 16-bit value (upper word zero) has ``nonDisplayBits`` removed.
    /// - A bogus value (see ``isBogus``) is discarded and replaced by
    ///   ``hires`` if `pageWidth >= 640` and ``lace`` if `pageHeight >= 400`;
    ///   in particular it never selects HAM or Extra-Half-Brite.
    /// - A 32-bit AmigaOS 2.0+ mode ID is returned unchanged.
    ///
    /// - Parameters:
    ///   - pageWidth: `BMHD.pageWidth`, in pixels.
    ///   - pageHeight: `BMHD.pageHeight`, in pixels.
    /// - Returns: The cleaned-up mode.
    public func normalized(pageWidth: Int16, pageHeight: Int16) -> ILBMViewportMode {
        if rawValue & 0xFFFF_0000 == 0 {
            return subtracting(ILBMViewportMode.nonDisplayBits)
        }
        if isBogus {
            var mode: ILBMViewportMode = []
            if pageWidth >= 640 { mode.insert(.hires) }
            if pageHeight >= 400 { mode.insert(.lace) }
            return mode
        }
        return self
    }

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
