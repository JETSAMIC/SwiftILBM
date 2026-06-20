import Foundation

/// Errors thrown while parsing or decoding an ILBM image.
public enum ILBMError: Error, Equatable, Sendable {
    /// The data is shorter than expected at the indicated stage.
    case truncated(stage: String)
    /// The outer FORM signature is not "FORM" or the subtype is not "ILBM".
    case invalidSignature
    /// No BMHD chunk was found in the FORM.
    case missingBMHD
    /// No BODY chunk was found in the FORM.
    case missingBODY
    /// Compression byte in BMHD is neither 0 (none) nor 1 (ByteRun1).
    case unsupportedCompression(UInt8)
    /// Bit-depth (nPlanes) is outside the supported 1...8 range.
    case unsupportedDepth(UInt8)
    /// CMAP is required for indexed images but was missing.
    case missingCMAP
    /// A ByteRun1 packet underflowed or overflowed the source/destination.
    case malformedRLE
    /// BMHD reports zero width or height.
    case invalidDimensions
    /// CoreGraphics refused to construct a CGImage from the decoded pixels.
    case cgImageCreationFailed
}
