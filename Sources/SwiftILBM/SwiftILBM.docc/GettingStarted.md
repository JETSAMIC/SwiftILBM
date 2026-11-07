# Getting Started

Decode an ILBM file and display it.

## Overview

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/JETSAMIC/SwiftILBM.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["SwiftILBM"])
]
```

### Decode

``ILBMImage/init(data:options:)`` locates the first `FORM ILBM` or
`FORM PBM `, validates its chunks, decompresses the `BODY` and converts it to
RGBA8.

```swift
import SwiftILBM

do {
    let image = try ILBMImage(data: data)
    print(image.width, image.height, image.depth, image.colorMode)

    // Straight RGBA8, top row first.
    let i = (y * image.width + x) * 4
    let alpha = image.pixels[i + 3]

    // Palette indices (nil for 24/32-plane true colour).
    if let indices = image.indexedPixels {
        print("index:", indices[y * image.width + x])
    }
} catch let error as ILBMError {
    print("Not a usable ILBM file:", error)
}
```

Images larger than ``ILBMImage/defaultMaximumPixelCount`` throw
``ILBMError/imageTooLarge(width:height:limit:)``. Pass an
``ILBMImage/Options`` value to change the limit, or to keep 4-bit palettes
unscaled:

```swift
let options = ILBMImage.Options(maximumPixelCount: 4096 * 4096,
                                expandsLeftJustified4BitPalettes: false)
let image = try ILBMImage(data: data, options: options)
```

### Display

On Apple platforms ``ILBMImage/cgImage`` returns a `CGImage`, and
`uiImage` / `nsImage` wrap it for UIKit and AppKit.

```swift
#if canImport(UIKit)
let view = UIImageView(image: image.uiImage)
#elseif canImport(AppKit)
let view = NSImageView(image: image.nsImage!)
#endif
```

Amiga pixels are rarely square. ``BMHDChunk/pixelAspectRatio`` gives the
intended ratio (for example 10:11 for a 320 × 200 low-resolution screen);
scale the displayed width by it if you want the original proportions.

### Palette animation

Deluxe Paint colour-cycling ranges are available in
``ILBMImage/colorRanges``; SwiftILBM decodes the static image and leaves the
animation to you.
