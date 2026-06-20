# SwiftILBM

Pure-Swift decoder for **ILBM** (Interleaved Bitmap) images — the IFF-based image
format used on the Commodore Amiga and ubiquitous in the BBS/demo/ANSI-adjacent
art scenes that surrounded it.

No C dependencies, no external Swift packages. Outputs `CGImage` (cross-platform),
`UIImage` on iOS, `NSImage` on macOS.

## Requirements

- Swift 6.0+
- iOS 17+
- macOS 14+

## Installation

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/prestige-exe/SwiftILBM.git", from: "0.1.0")
```

## Usage

```swift
import SwiftILBM

let image = try ILBMImage(url: someURL)
print(image.width, image.height, image.depth)

// CoreGraphics
let cg = image.cgImage

// Platform-specific
#if canImport(UIKit)
let ui = image.uiImage
#elseif canImport(AppKit)
let ns = image.nsImage
#endif
```

## What's supported

- Standard IFF FORM/ILBM parsing (big-endian, padded chunks)
- BMHD, CMAP, BODY chunks
- ByteRun1 (PackBits) decompression
- Uncompressed (raw planar) BODY
- 1–8 bit-depth indexed images (the BBS/Amiga workhorse case)
- Optional transparent-color masking via BMHD.transparentColor

## What's deferred

- **HAM6 / HAM8** (Hold-And-Modify): Amiga-specific 6/8-plane mode where the top
  2 bits of each pixel are control bits that modify R, G, or B from the previous
  pixel. Not decoded in this release.
- **EHB** (Extra-Half-Brite): 6-plane mode where the 6th plane halves the
  intensity of the indexed color. Not decoded in this release.
- **24-bit truecolor ILBM** (nPlanes == 24): rare in the wild but defined by the
  spec. Currently rejected with `ILBMError.unsupportedDepth`.
- **Mask plane** (BMHD.masking == 1): the optional extra plane after the
  bitplanes is currently skipped, not interpreted.
- **SHAM / PCHG** dynamic palette chunks.

## License

MIT — see [LICENSE](LICENSE).
