import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Public entry point. Construct from `Data` or a file `URL`; inspect the
/// header/palette and pull a `CGImage` (or platform-specific image) out.
public struct ILBMImage: Sendable {

    // MARK: - Public properties

    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels.
    public let height: Int
    /// Bit depth (1–8). Number of planes in the source ILBM.
    public let depth: Int
    /// Indexed palette (empty for non-indexed images).
    public let palette: [CMAPChunk.Color]
    /// Decoded BMHD chunk, in case callers want masking / aspect-ratio fields.
    public let header: BMHDChunk

    // Cached RGBA8 buffer + indexed buffer, in row-major order.
    private let rgba: [UInt8]
    public let indexedPixels: [UInt8]

    // MARK: - Init

    /// Load an ILBM image from raw bytes.
    /// - Throws: any `ILBMError` if parsing or decoding fails.
    public init(data: Data) throws {
        let chunks = try IFFParser.parse(data, expectedType: "ILBM")

        guard let bmhdData = chunks.first(where: { $0.id == "BMHD" })?.data else {
            throw ILBMError.missingBMHD
        }
        let bmhd = try BMHDChunk(data: bmhdData)

        guard bmhd.width > 0 && bmhd.height > 0 else { throw ILBMError.invalidDimensions }
        guard bmhd.nPlanes >= 1 && bmhd.nPlanes <= 8 else {
            throw ILBMError.unsupportedDepth(bmhd.nPlanes)
        }

        guard let bodyData = chunks.first(where: { $0.id == "BODY" })?.data else {
            throw ILBMError.missingBODY
        }

        let cmap: CMAPChunk
        if let cmapData = chunks.first(where: { $0.id == "CMAP" })?.data {
            cmap = CMAPChunk(data: cmapData)
        } else {
            // Indexed image without a CMAP is technically legal (greyscale ramp
            // implied) but vanishingly rare. We require one here so output is
            // unambiguous; callers can attach a default palette and retry if
            // they need otherwise.
            throw ILBMError.missingCMAP
        }

        let planar = try BODYChunk.decode(bodyData, bmhd: bmhd)
        let indices = PlanarToChunky.indexedPixels(planar: planar, bmhd: bmhd)

        let transparentIdx: Int? = (bmhd.masking == 2) ? Int(bmhd.transparentColor) : nil
        let rgba = PlanarToChunky.rgbaPixels(
            indices: indices,
            palette: cmap.colors,
            transparentIndex: transparentIdx
        )

        self.header        = bmhd
        self.width         = Int(bmhd.width)
        self.height        = Int(bmhd.height)
        self.depth         = Int(bmhd.nPlanes)
        self.palette       = cmap.colors
        self.indexedPixels = indices
        self.rgba          = rgba
    }

    /// Convenience: load from a file URL.
    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }

    // MARK: - Image accessors

    /// CoreGraphics representation. Always RGBA8 sRGB, premultiplied-last.
    public var cgImage: CGImage? {
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    #if canImport(UIKit)
    /// UIImage representation (iOS / tvOS / visionOS / watchOS).
    public var uiImage: UIImage? {
        guard let cg = cgImage else { return nil }
        return UIImage(cgImage: cg)
    }
    #endif

    #if canImport(AppKit)
    /// NSImage representation (macOS).
    public var nsImage: NSImage? {
        guard let cg = cgImage else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
    #endif
}
