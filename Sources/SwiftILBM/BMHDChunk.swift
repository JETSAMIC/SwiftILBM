import Foundation

/// The decoded `BMHD` (BitMapHeader) chunk. All multi-byte fields are
/// big-endian.
///
/// Layout (EA "ILBM" IFF Interleaved Bitmap, 1986):
///
///     UWORD w, h              image size in pixels
///     WORD  x, y              suggested position
///     UBYTE nPlanes           number of bitplanes
///     UBYTE masking           0 none, 1 mask plane, 2 transparent colour, 3 lasso
///     UBYTE compression       0 none, 1 ByteRun1
///     UBYTE flags             pad1 in the 1986 spec; bit 7 = BMHDF_CMAPOK
///     UWORD transparentColor
///     UBYTE xAspect, yAspect  pixel aspect ratio
///     WORD  pageWidth, pageHeight  source page size in pixels
public struct BMHDChunk: Sendable, Equatable {

    /// The `masking` field values defined by the ILBM specification.
    public enum Masking: UInt8, Sendable, Equatable, CaseIterable {
        /// `0` — opaque image.
        case none = 0
        /// `1` — a mask bitplane follows the image planes on every row; a set
        /// bit marks an opaque pixel.
        case hasMask = 1
        /// `2` — pixels equal to ``BMHDChunk/transparentColor`` are transparent.
        case hasTransparentColor = 2
        /// `3` — lasso: the image should be lassoed by the reader. No mask data
        /// is stored; SwiftILBM renders the image opaque.
        case lasso = 3
    }

    /// The `compression` field values defined by the ILBM specification.
    public enum Compression: UInt8, Sendable, Equatable, CaseIterable {
        /// `0` — uncompressed rows.
        case none = 0
        /// `1` — ByteRun1 (PackBits-style) run-length encoding.
        case byteRun1 = 1
    }

    /// Image width in pixels.
    public let width: UInt16
    /// Image height in pixels.
    public let height: UInt16
    /// Suggested horizontal position on the page, in pixels.
    public let x: Int16
    /// Suggested vertical position on the page, in pixels.
    public let y: Int16
    /// Number of bitplanes (bits per pixel), excluding any mask plane.
    public let nPlanes: UInt8
    /// Raw masking technique; see ``maskingMode``.
    public let masking: UInt8
    /// Raw compression method; see ``compressionMode``.
    public let compression: UInt8
    /// The byte at offset 11: `pad1` in the 1986 specification, later named
    /// `flags`. Only bit 7 (``hasFullRangeCMAP``) is defined.
    public let flags: UInt8
    /// Palette index treated as transparent when ``masking`` is 2.
    public let transparentColor: UInt16
    /// Horizontal component of the pixel aspect ratio (0 if unknown).
    public let xAspect: UInt8
    /// Vertical component of the pixel aspect ratio (0 if unknown).
    public let yAspect: UInt8
    /// Width of the source page (screen) in pixels.
    public let pageWidth: Int16
    /// Height of the source page (screen) in pixels.
    public let pageHeight: Int16

    /// Parse a `BMHD` payload (the chunk body without its 8-byte header).
    ///
    /// - Parameter data: At least 20 bytes; extra bytes are ignored.
    /// - Throws: ``ILBMError/truncated(stage:)`` if fewer than 20 bytes.
    public init(data: Data) throws {
        guard data.count >= 20 else { throw ILBMError.truncated(stage: "BMHD") }
        let base = data.startIndex
        self.width            = IFFParser.beUInt16(data, at: 0)
        self.height           = IFFParser.beUInt16(data, at: 2)
        self.x                = IFFParser.beInt16(data, at: 4)
        self.y                = IFFParser.beInt16(data, at: 6)
        self.nPlanes          = data[base + 8]
        self.masking          = data[base + 9]
        self.compression      = data[base + 10]
        self.flags            = data[base + 11]
        self.transparentColor = IFFParser.beUInt16(data, at: 12)
        self.xAspect          = data[base + 14]
        self.yAspect          = data[base + 15]
        self.pageWidth        = IFFParser.beInt16(data, at: 16)
        self.pageHeight       = IFFParser.beInt16(data, at: 18)
    }

    /// Whether `BMHDF_CMAPOK` (``flags`` bit 7) is set: the writer declares
    /// that the `CMAP` holds genuine 8-bit values, so a reader must not apply
    /// the 4-bit left-justified palette heuristic.
    public var hasFullRangeCMAP: Bool { flags & 0x80 != 0 }

    /// ``masking`` as an enum, or `nil` for an undefined value.
    public var maskingMode: Masking? { Masking(rawValue: masking) }

    /// ``compression`` as an enum, or `nil` for an undefined value.
    public var compressionMode: Compression? { Compression(rawValue: compression) }

    /// Bytes per bitplane row in an ILBM BODY: the width rounded up to a
    /// 16-bit word, `((width + 15) / 16) * 2`. (Width 320 → 40; 321 → 42.)
    public var bytesPerRow: Int {
        ((Int(width) + 15) / 16) * 2
    }

    /// Pixel aspect ratio (`xAspect / yAspect`), or `nil` when either field
    /// is zero. A value below 1 means pixels are taller than they are wide.
    public var pixelAspectRatio: Double? {
        guard xAspect > 0, yAspect > 0 else { return nil }
        return Double(xAspect) / Double(yAspect)
    }
}
