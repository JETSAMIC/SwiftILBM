# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - Unreleased

Initial public release (proposed).

### Added

- `ILBMImage` decoder for `FORM ILBM` (1–8 plane indexed, HAM6, HAM8,
  Extra-Half-Brite, 24/32-plane true colour) and `FORM PBM ` (Deluxe Paint
  II Enhanced), uncompressed or ByteRun1.
- Images nested in `LIST`, `CAT ` and `FORM ANIM`, with `PROP` defaults.
- Mask-plane and transparent-colour masking as alpha.
- 4-bit left-justified (OCS) palette scaling, on by default.
- `ILBMViewportMode` (CAMG flags) and `ILBMColorRange` (CRNG).
- `ILBMImage.Options` with a `maximumPixelCount` decompression-bomb guard
  (default 64 MP) and `ILBMError.imageTooLarge`.
- `pixels` (straight RGBA8), `formType`, `colorMode`; `cgImage`, `uiImage`,
  `nsImage` on platforms that have them.
- tvOS, watchOS and visionOS support.
- DocC catalog, `Reference/ILBM-Format.md`, CI workflow, Swift Package Index
  configuration, truncation and seeded mutation-fuzz tests.

### Changed

- `indexedPixels` is optional (`nil` for true-colour images).
- `cgImage` uses sRGB and straight alpha.
- Undefined `masking` values throw `ILBMError.unsupportedMasking`.

### Fixed

- Decompression bomb: a tiny ByteRun1 file declaring a large image reserved
  gigabytes before decoding.
- Chunk sizes above `Int32.max` trapped on 32-bit watchOS.
- Sliced `Data` inputs read the wrong bytes.
- HAM and EHB images decoded silently with wrong colours.
- Transparent pixels were tagged premultiplied with non-zero colour.
- A repeated property chunk (e.g. a second `CMAP`) now resolves to the last
  occurrence before `BODY`, as the ILBM specification requires, instead of the
  first; `PROP` scopes nest correctly and `BODY` is never inherited.

### Removed

- `ILBMError.cgImageCreationFailed` (never thrown).
