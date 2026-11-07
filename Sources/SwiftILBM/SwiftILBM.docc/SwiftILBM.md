# ``SwiftILBM``

Decode Amiga IFF ILBM and Deluxe Paint PBM images in pure Swift.

## Overview

SwiftILBM reads the IFF `FORM ILBM` bitmap format used by Deluxe Paint and
virtually every Amiga graphics program, and the chunky `FORM PBM ` variant
written by Deluxe Paint II Enhanced on the PC. It handles 1–8 plane indexed
images, Hold-And-Modify (HAM6 and HAM8), Extra-Half-Brite, 24- and 32-plane
true colour, mask planes and transparent colours, ByteRun1 compression and
4-bit OCS palettes, and finds images nested in `LIST`, `CAT ` and
`FORM ANIM` containers.

The decoder is built for untrusted input: chunk sizes are bounds-checked,
image size is capped before allocation
(``ILBMImage/defaultMaximumPixelCount``), and malformed files throw a typed
``ILBMError``.

```swift
import SwiftILBM

let image = try ILBMImage(url: fileURL)
print(image.width, image.height, image.colorMode)
let rgba: [UInt8] = image.pixels        // width * height * 4 bytes
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``ILBMImage``
- ``ILBMError``

### Chunks

- ``BMHDChunk``
- ``CMAPChunk``
- ``ILBMViewportMode``
- ``ILBMColorRange``

### IFF container

- ``IFFParser``
- ``IFFChunk``
