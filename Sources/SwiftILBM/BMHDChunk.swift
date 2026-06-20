import Foundation

/// Decoded "BMHD" (BitMapHeader) chunk. Always 20 bytes, always present, always
/// the first chunk inside an ILBM FORM. All multi-byte fields are big-endian.
///
/// Layout (per EA IFF 85 / Amiga ROM Kernel):
///   UWORD w, h            // image dimensions in pixels
///   WORD  x, y            // suggested screen position
///   UBYTE nPlanes         // number of bitplanes (1–8 supported here)
///   UBYTE masking         // 0=none, 1=mask plane, 2=transparent color, 3=lasso
///   UBYTE compression     // 0=none, 1=ByteRun1
///   UBYTE pad1            // reserved, should be 0
///   UWORD transparentColor
///   UBYTE xAspect, yAspect
///   WORD  pageWidth, pageHeight
public struct BMHDChunk: Sendable, Equatable {
    public let width: UInt16
    public let height: UInt16
    public let x: Int16
    public let y: Int16
    public let nPlanes: UInt8
    public let masking: UInt8
    public let compression: UInt8
    public let transparentColor: UInt16
    public let xAspect: UInt8
    public let yAspect: UInt8
    public let pageWidth: Int16
    public let pageHeight: Int16

    /// Parse the 20-byte BMHD payload (the chunk body without its 8-byte header).
    public init(data: Data) throws {
        guard data.count >= 20 else { throw ILBMError.truncated(stage: "BMHD") }
        self.width            = IFFParser.beUInt16(data, at: 0)
        self.height           = IFFParser.beUInt16(data, at: 2)
        self.x                = IFFParser.beInt16(data, at: 4)
        self.y                = IFFParser.beInt16(data, at: 6)
        self.nPlanes          = data[data.startIndex + 8]
        self.masking          = data[data.startIndex + 9]
        self.compression      = data[data.startIndex + 10]
        // pad1 at offset 11 — ignored
        self.transparentColor = IFFParser.beUInt16(data, at: 12)
        self.xAspect          = data[data.startIndex + 14]
        self.yAspect          = data[data.startIndex + 15]
        self.pageWidth        = IFFParser.beInt16(data, at: 16)
        self.pageHeight       = IFFParser.beInt16(data, at: 18)
    }

    /// Bytes per bitplane row, rounded up to a 16-bit word boundary as ILBM requires.
    /// (Width 320 → 40 bytes; width 321 → 42 bytes.)
    public var bytesPerRow: Int {
        let words = (Int(width) + 15) / 16
        return words * 2
    }
}
