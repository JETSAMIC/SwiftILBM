import Foundation

/// A decoded IFF ILBM or PBM image.
///
/// Construct one from `Data` or a file `URL`, then read the RGBA8
/// ``pixels``, the palette indices, the header fields, or (on Apple
/// platforms) a `CGImage`.
///
/// ```swift
/// let image = try ILBMImage(url: url)
/// print(image.width, image.height, image.colorMode)
/// let cg = image.cgImage
/// ```
///
/// Decoding is a pure function of the input bytes and is safe to call from
/// any thread.
public struct ILBMImage: Sendable, Equatable {

    // MARK: - Nested types

    /// The IFF `FORM` type the image was read from.
    public enum FormType: String, Sendable, Equatable, CaseIterable {
        /// `FORM ILBM` — interleaved bitplanes (the Amiga standard).
        case ilbm = "ILBM"
        /// `FORM PBM ` — one byte per pixel ("chunky"), written by
        /// Deluxe Paint II Enhanced on the PC.
        case pbm = "PBM "
    }

    /// How pixel values map to colours.
    public enum ColorMode: Sendable, Equatable, CaseIterable {
        /// Each pixel indexes ``ILBMImage/palette``.
        case indexed
        /// Extra-Half-Brite: indices 32...63 are palette entries 0...31 at
        /// half brightness.
        case extraHalfbrite
        /// Hold-And-Modify (HAM6 or HAM8).
        case holdAndModify
        /// 24- or 32-plane direct colour ("deep" ILBM); no palette.
        case trueColor
    }

    /// Decoding limits and behaviour switches.
    public struct Options: Sendable, Equatable {
        /// Largest `width * height` accepted before any pixel memory is
        /// allocated. Defaults to ``ILBMImage/defaultMaximumPixelCount``.
        public var maximumPixelCount: Int
        /// Scale palettes whose components all have a zero low nibble
        /// (4-bit OCS/ECS values stored as `n << 4`) to the full 8-bit range.
        /// Defaults to `true`. See ``CMAPChunk/expandingLeftJustified4Bit()``.
        public var expandsLeftJustified4BitPalettes: Bool

        /// Creates decoding options.
        ///
        /// - Parameters:
        ///   - maximumPixelCount: Pixel-count limit. Defaults to
        ///     ``ILBMImage/defaultMaximumPixelCount``.
        ///   - expandsLeftJustified4BitPalettes: Whether to scale 4-bit
        ///     palettes. Defaults to `true`.
        public init(
            maximumPixelCount: Int = ILBMImage.defaultMaximumPixelCount,
            expandsLeftJustified4BitPalettes: Bool = true
        ) {
            self.maximumPixelCount = maximumPixelCount
            self.expandsLeftJustified4BitPalettes = expandsLeftJustified4BitPalettes
        }

        /// The default options.
        public static let `default` = Options()
    }

    /// Default cap on `width * height`: 64 megapixels (256 MiB of RGBA).
    public static let defaultMaximumPixelCount = 1 << 26

    // MARK: - Public properties

    /// Image width in pixels.
    public let width: Int
    /// Image height in pixels.
    public let height: Int
    /// Bits per pixel: `BMHD.nPlanes` (1–8, 24 or 32).
    public let depth: Int
    /// The `FORM` type the image was read from.
    public let formType: FormType
    /// How pixel values were mapped to colours.
    public let colorMode: ColorMode
    /// The colour map used for decoding (after 4-bit expansion, if enabled).
    /// Empty for true-colour images without a `CMAP`. For EHB images this is
    /// the stored map; the half-bright entries are derived from it.
    public let palette: [CMAPChunk.Color]
    /// The decoded `BMHD` chunk (masking, aspect ratio, page size, …).
    public let header: BMHDChunk
    /// Display-mode flags from the `CAMG` chunk after the specification's
    /// clean-up rules (``ILBMViewportMode/normalized(pageWidth:pageHeight:)``),
    /// or `nil` if the chunk is absent.
    public let viewportMode: ILBMViewportMode?
    /// Colour-cycling ranges from `CRNG` chunks, in file order.
    public let colorRanges: [ILBMColorRange]
    /// One raw pixel value per pixel, row-major: palette indices for indexed,
    /// EHB and PBM images, raw HAM codes for HAM images, and `nil` for
    /// true-colour images.
    public let indexedPixels: [UInt8]?
    /// `width * height * 4` bytes of straight (non-premultiplied) RGBA8,
    /// top row first. Alpha is 0 for transparent-colour pixels
    /// (`masking == 2`), for pixels outside the mask plane (`masking == 1`),
    /// and from the alpha planes of 32-plane images; 255 elsewhere.
    public let pixels: [UInt8]

    // MARK: - Init

    /// Decode an ILBM or PBM image from the complete file contents.
    ///
    /// The first `FORM ILBM` or `FORM PBM ` is used, whether at the top level
    /// or nested in a `LIST`, `CAT ` or `FORM ANIM`.
    ///
    /// - Parameters:
    ///   - data: The file contents.
    ///   - options: Limits and behaviour switches. Defaults to
    ///     ``Options/default``.
    /// - Throws: An ``ILBMError`` describing the first problem found.
    public init(data: Data, options: Options = .default) throws {
        let form = try IFFParser.findForm(in: data, types: [FormType.ilbm.rawValue, FormType.pbm.rawValue])
        let formType = FormType(rawValue: form.type) ?? .ilbm
        func chunk(_ id: String) -> Data? { form.property(id) }

        guard let bmhdData = chunk("BMHD") else { throw ILBMError.missingBMHD }
        let bmhd = try BMHDChunk(data: bmhdData)

        let width = Int(bmhd.width)
        let height = Int(bmhd.height)
        guard width > 0 && height > 0 else { throw ILBMError.invalidDimensions }
        let area = width.multipliedReportingOverflow(by: height)
        guard !area.overflow, area.partialValue <= options.maximumPixelCount,
              !area.partialValue.multipliedReportingOverflow(by: 4).overflow else {
            throw ILBMError.imageTooLarge(width: width, height: height, limit: options.maximumPixelCount)
        }

        let planes = Int(bmhd.nPlanes)
        guard let masking = bmhd.maskingMode else { throw ILBMError.unsupportedMasking(bmhd.masking) }
        guard bmhd.compressionMode != nil else { throw ILBMError.unsupportedCompression(bmhd.compression) }
        switch formType {
        case .ilbm:
            guard (1...8).contains(planes) || planes == 24 || planes == 32 else {
                throw ILBMError.unsupportedDepth(bmhd.nPlanes)
            }
        case .pbm:
            guard (1...8).contains(planes) else { throw ILBMError.unsupportedDepth(bmhd.nPlanes) }
            guard masking != .hasMask else { throw ILBMError.unsupportedMasking(bmhd.masking) }
        }

        let viewportMode = try chunk("CAMG").map {
            try ILBMViewportMode(camg: $0).normalized(pageWidth: bmhd.pageWidth, pageHeight: bmhd.pageHeight)
        }
        let colorRanges = form.repeatedProperty("CRNG").compactMap { ILBMColorRange(crng: $0) }

        var cmap = chunk("CMAP").map(CMAPChunk.init(data:))
        if options.expandsLeftJustified4BitPalettes {
            cmap = cmap?.expandingLeftJustified4Bit()
        }

        let colorMode = Self.colorMode(formType: formType, planes: planes,
                                       viewportMode: viewportMode, paletteCount: cmap?.colors.count)
        if colorMode == .holdAndModify && planes != 6 && planes != 8 {
            throw ILBMError.unsupportedDepth(bmhd.nPlanes)
        }
        if colorMode != .trueColor && cmap == nil { throw ILBMError.missingCMAP }
        let palette = cmap?.colors ?? []

        guard let bodyData = form.body else { throw ILBMError.missingBODY }

        // Decode the BODY rows.
        let rowStride: Int
        let layout: PlanarToChunky.Layout
        switch formType {
        case .pbm:
            rowStride = (width + 1) & ~1
            layout = .init(width: width, height: height, bytesPerPlaneRow: rowStride, rowStride: rowStride)
        case .ilbm:
            let planeRows = planes + (masking == .hasMask ? 1 : 0)
            rowStride = planeRows * bmhd.bytesPerRow
            layout = .init(width: width, height: height, bytesPerPlaneRow: bmhd.bytesPerRow, rowStride: rowStride)
        }
        let body = try BODYChunk.decode(bodyData, rowBytes: rowStride, height: height,
                                        compression: bmhd.compression)

        // Convert to pixel values and RGBA.
        var indices: [UInt8]?
        var rgba: [UInt8]
        let transparentIndex = masking == .hasTransparentColor ? Int(bmhd.transparentColor) : nil
        switch (formType, colorMode) {
        case (.pbm, _):
            let values = PlanarToChunky.chunkyPixels(body: body, width: width, height: height, rowStride: rowStride)
            indices = values
            rgba = PlanarToChunky.rgbaPixels(indices: values, palette: palette, transparentIndex: transparentIndex)
        case (.ilbm, .trueColor):
            rgba = PlanarToChunky.deepRGBA(planar: body, layout: layout, planes: planes)
        case (.ilbm, .holdAndModify):
            let values = PlanarToChunky.indexedPixels(planar: body, layout: layout, planes: planes)
            indices = values
            rgba = PlanarToChunky.hamRGBA(codes: values, width: width, height: height,
                                          planes: planes, palette: palette)
        case (.ilbm, .extraHalfbrite):
            let values = PlanarToChunky.indexedPixels(planar: body, layout: layout, planes: planes)
            indices = values
            rgba = PlanarToChunky.rgbaPixels(indices: values,
                                             palette: PlanarToChunky.extraHalfbritePalette(palette),
                                             transparentIndex: transparentIndex)
        case (.ilbm, .indexed):
            let values = PlanarToChunky.indexedPixels(planar: body, layout: layout, planes: planes)
            indices = values
            rgba = PlanarToChunky.rgbaPixels(indices: values, palette: palette, transparentIndex: transparentIndex)
        }

        if formType == .ilbm && masking == .hasMask {
            let alpha = PlanarToChunky.maskAlpha(planar: body, layout: layout, maskPlane: planes)
            for (i, a) in alpha.enumerated() where a == 0 { rgba[i * 4 + 3] = 0 }
        }

        self.header        = bmhd
        self.width         = width
        self.height        = height
        self.depth         = planes
        self.formType      = formType
        self.colorMode     = colorMode
        self.palette       = palette
        self.viewportMode  = viewportMode
        self.colorRanges   = colorRanges
        self.indexedPixels = indices
        self.pixels        = rgba
    }

    /// Decode an ILBM or PBM file at `url`.
    ///
    /// - Parameters:
    ///   - url: A file URL.
    ///   - options: Limits and behaviour switches. Defaults to
    ///     ``Options/default``.
    /// - Throws: Any error from reading the file, or an ``ILBMError``.
    public init(url: URL, options: Options = .default) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: data, options: options)
    }

    /// Choose the colour mode from `CAMG` flags, falling back to the
    /// de-facto heuristics for 6-plane files without a `CAMG` chunk
    /// (32 colours → EHB, 16 or fewer → HAM6).
    static func colorMode(formType: FormType, planes: Int,
                          viewportMode: ILBMViewportMode?, paletteCount: Int?) -> ColorMode {
        if formType == .pbm { return .indexed }
        if planes > 8 { return .trueColor }
        if let mode = viewportMode {
            if mode.contains(.ham) { return .holdAndModify }
            if mode.contains(.extraHalfbrite) && planes == 6 { return .extraHalfbrite }
            return .indexed
        }
        if planes == 6, let count = paletteCount {
            if count == 32 { return .extraHalfbrite }
            if count <= 16 { return .holdAndModify }
        }
        return .indexed
    }
}
