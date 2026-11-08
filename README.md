# SwiftILBM

Pure-Swift decoder for Amiga IFF ILBM and Deluxe Paint PBM images — indexed, HAM, EHB and true colour — hardened for untrusted input.

## Requirements

- Swift 6.0+ / Xcode 16+
- iOS 17+, iPadOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+ (verified on the 27.3 SDKs)
- Foundation only; no third-party dependencies. `cgImage` is available wherever CoreGraphics is, `uiImage` with UIKit (iOS, iPadOS, tvOS, visionOS, watchOS) and `nsImage` with AppKit (macOS).

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/JETSAMIC/SwiftILBM.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["SwiftILBM"])
]
```

In Xcode: **File ▸ Add Package Dependencies…** and enter the URL above.

## Quick start

```swift
import SwiftILBM

let image = try ILBMImage(url: fileURL)                // throws ILBMError
print(image.width, image.height, image.depth, image.colorMode)
let firstPixel = Array(image.pixels[0..<4])            // straight RGBA8

#if canImport(CoreGraphics)
let cg = image.cgImage
#endif
#if canImport(UIKit)
let ui = image.uiImage
#elseif canImport(AppKit)
let ns = image.nsImage
#endif
```

`pixels` is `width * height * 4` bytes, top row first. `indexedPixels` holds palette indices (raw HAM codes for HAM images, `nil` for true colour). `header` exposes every BMHD field, `viewportMode` the CAMG flags and `colorRanges` the CRNG colour-cycling ranges.

### Untrusted input

- Chunk sizes are checked against their container; malformed files throw a typed `ILBMError`, never crash. Covered by truncation-at-every-offset and seeded mutation-fuzz tests.
- `ILBMImage.Options.maximumPixelCount` (default 64 megapixels) is enforced **before** any allocation, and a ByteRun1 BODY that cannot possibly expand to the declared size is rejected up front.

## Spec coverage

| Feature | Status |
|---|---|
| IFF chunks, big-endian sizes, odd-size pad byte, unknown-chunk skipping | Supported |
| `FORM ILBM` | Supported |
| `FORM PBM ` (Deluxe Paint II Enhanced chunky) | Supported (1–8 planes, no mask plane) |
| Nested `LIST` / `CAT ` / `FORM ANIM` (first image), scoped `PROP` defaults | Supported |
| Repeated property chunks (last one before `BODY` wins) | Supported |
| BMHD, incl. `pageWidth/Height`, `xAspect/yAspect` | Supported |
| Masking 0 (none), 1 (mask plane → alpha), 2 (transparent colour → alpha) | Supported |
| Masking 3 (lasso) | Partial — rendered opaque |
| Compression 0 and 1 (ByteRun1, −128 no-op, runs across rows tolerated) | Supported |
| Other compression values (e.g. Atari `VDAT`) | Unsupported |
| CMAP, incl. 4-bit left-justified ("OCS") palette scaling | Supported (on by default; off when BMHD sets `BMHDF_CMAPOK`) |
| 1–8 plane indexed | Supported |
| Palette-only ILBM (`nPlanes` 0, no `BODY`) | Unsupported — rejected, no image |
| CAMG clean-up (16-bit junk bits, bogus values) | Supported |
| CAMG HAM6 / HAM8 | Supported (HAM with other depths rejected) |
| CAMG Extra-Half-Brite | Supported |
| 6-plane files without CAMG (EHB / HAM6 heuristics) | Supported |
| CAMG HIRES / LACE / SUPERHIRES | Exposed; no effect on pixels |
| CAMG dual playfield | Unsupported — decoded as plain indexed |
| 24- and 32-plane true colour ("deep") ILBM | Supported |
| 21-plane NewTek and other deep depths | Unsupported |
| CRNG colour ranges | Parsed and exposed |
| CCRT, DRNG, GRAB, DEST, SPRT | Ignored |
| SHAM / PCHG / CTBL / DYCP dynamic palettes | Unsupported (static CMAP used) |
| ANIM deltas, ACBM / RGBN / RGB8 / DEEP FORMs | Unsupported |
| Encoding | Unsupported (decoder only) |

## Limitations

- Indexed, HAM, EHB and PBM images require a `CMAP` (`ILBMError.missingCMAP`); only true-colour images may omit it.
- Lasso masking is not computed; dual-playfield images are not split into two playfields.
- Pixels are not aspect-corrected; use `header.pixelAspectRatio` if you need the original proportions.

## Documentation

DocC documentation is in `Sources/SwiftILBM/SwiftILBM.docc` (**Product ▸ Build Documentation** in Xcode, or `xcodebuild docbuild -scheme SwiftILBM -destination 'generic/platform=macOS'`). The byte-level format reference used to validate this implementation is [Reference/ILBM-Format.md](Reference/ILBM-Format.md).

## Contributing

Issues and pull requests are welcome; files that SwiftILBM mis-decodes are most useful with the file attached or a hand-built fixture. Run `swift test` before submitting; commit messages follow Conventional Commits (`fix(iff): …`, `docs: …`).

## References

- Jerry Morrison, Electronic Arts — *"EA IFF 85" Standard for Interchange Format Files* (1985) and *"ILBM" IFF Interleaved Bitmap* (1986).
- Commodore-Amiga — *Amiga ROM Kernel Reference Manual: Devices* and *Amiga Hardware Reference Manual*, 3rd ed. (1991).
- *Amiga Developer CD v2.1* IFF form documents (ACBM, ANIM, DEEP, RGBN/RGB8, PCHG and others); full bibliography and errata in [Reference/ILBM-Format.md](Reference/ILBM-Format.md).

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Christian Vozar.
