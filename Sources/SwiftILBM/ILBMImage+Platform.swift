#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

extension ILBMImage {

    /// A `CGImage` of ``pixels``: 8-bit RGBA, sRGB, straight alpha.
    ///
    /// A new image is created on every access. `nil` only if CoreGraphics
    /// cannot create the image.
    public var cgImage: CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    #if canImport(UIKit)
    /// A `UIImage` of the decoded pixels (iOS, iPadOS, tvOS, visionOS,
    /// watchOS), or `nil` if ``cgImage`` is `nil`.
    public var uiImage: UIImage? {
        cgImage.map { UIImage(cgImage: $0) }
    }
    #endif

    #if canImport(AppKit)
    /// An `NSImage` of the decoded pixels (macOS), sized one point per pixel,
    /// or `nil` if ``cgImage`` is `nil`.
    public var nsImage: NSImage? {
        cgImage.map { NSImage(cgImage: $0, size: NSSize(width: width, height: height)) }
    }
    #endif
}
#endif
