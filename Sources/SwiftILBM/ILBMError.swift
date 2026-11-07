import Foundation

/// Errors thrown while parsing or decoding an ILBM or PBM image.
///
/// Every malformed-input condition the decoder detects maps to one case; no
/// input causes a crash.
public enum ILBMError: Error, Equatable, Sendable {
    /// The data ended before a required structure was complete. `stage`
    /// names the structure: `"FORM header"`, `"BMHD"`, `"CAMG"`,
    /// `"BODY (raw)"`, or `"chunk XXXX"` for a chunk whose declared size runs
    /// past the end of its container.
    case truncated(stage: String)
    /// The data is not an IFF `FORM`, `LIST` or `CAT ` container, or no
    /// `FORM` of the requested type (ILBM or PBM) was found inside it.
    case invalidSignature
    /// No `BMHD` chunk was found in the `FORM`.
    case missingBMHD
    /// No `BODY` chunk was found in the `FORM`.
    case missingBODY
    /// An indexed, EHB, HAM or PBM image has no `CMAP` chunk.
    case missingCMAP
    /// `BMHD.compression` is neither 0 (none) nor 1 (ByteRun1).
    case unsupportedCompression(UInt8)
    /// `BMHD.nPlanes` is not supported: ILBM accepts 1...8, 24 and 32 planes
    /// (HAM requires 6 or 8); PBM accepts 1...8.
    case unsupportedDepth(UInt8)
    /// `BMHD.masking` is not 0...3, or is 1 (mask plane) in a PBM file.
    case unsupportedMasking(UInt8)
    /// The ByteRun1 stream ended before the image was complete, or a literal
    /// packet ran past the end of the BODY.
    case malformedRLE
    /// `BMHD` reports a zero width or height.
    case invalidDimensions
    /// `width * height` exceeds the caller's limit (decompression-bomb guard).
    ///
    /// - Parameters:
    ///   - width: Declared width in pixels.
    ///   - height: Declared height in pixels.
    ///   - limit: The maximum pixel count that was in effect.
    case imageTooLarge(width: Int, height: Int, limit: Int)
}
