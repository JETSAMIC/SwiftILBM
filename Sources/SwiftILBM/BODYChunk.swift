import Foundation

/// Decodes the `BODY` chunk into uncompressed row data.
///
/// ILBM BODY layout, repeated for every row:
///
///     plane 0 row | plane 1 row | … | plane N-1 row | [mask row if masking == 1]
///
/// where each plane row is ``BMHDChunk/bytesPerRow`` bytes. PBM BODY rows are
/// one byte per pixel, padded to an even length.
///
/// Compression 1 is ByteRun1. The specification has encoders restart the
/// run-length coder for every plane row, but this decoder treats the BODY as
/// one continuous stream, so it also accepts files whose runs cross row
/// boundaries; for conforming files the output is identical.
enum BODYChunk {

    /// Decode `height` rows of `rowBytes` bytes each.
    ///
    /// - Parameters:
    ///   - data: The BODY payload.
    ///   - rowBytes: Uncompressed bytes per row (all planes plus any mask).
    ///   - height: Number of rows.
    ///   - compression: `BMHD.compression`.
    /// - Returns: Exactly `rowBytes * height` bytes.
    /// - Throws: ``ILBMError/unsupportedCompression(_:)``,
    ///   ``ILBMError/truncated(stage:)`` for a short uncompressed body,
    ///   ``ILBMError/malformedRLE`` for a bad or short ByteRun1 stream, or
    ///   ``ILBMError/invalidDimensions`` if the size overflows `Int`.
    static func decode(_ data: Data, rowBytes: Int, height: Int, compression: UInt8) throws -> [UInt8] {
        let product = rowBytes.multipliedReportingOverflow(by: height)
        guard rowBytes > 0, height > 0, !product.overflow else { throw ILBMError.invalidDimensions }
        let expectedTotal = product.partialValue

        switch compression {
        case 0:
            guard data.count >= expectedTotal else {
                throw ILBMError.truncated(stage: "BODY (raw)")
            }
            return Array(data.prefix(expectedTotal))
        case 1:
            return Array(try byteRun1Decode(data, expectedSize: expectedTotal))
        default:
            throw ILBMError.unsupportedCompression(compression)
        }
    }

    /// Decompress a ByteRun1 (PackBits) stream into exactly `expectedSize` bytes.
    ///
    /// The control byte `n` is read as a signed Int8:
    ///   -  0...127  → copy the next (n + 1) bytes literally
    ///   -  -1...-127 → repeat the next byte (-n + 1) times
    ///   -  -128      → no-op (skip the control byte)
    ///
    /// Output that overshoots `expectedSize` (a trailing packet written past
    /// the last row by some encoders) is trimmed.
    static func byteRun1Decode(_ data: Data, expectedSize: Int) throws -> Data {
        // Decompression-bomb guard: two input bytes expand to at most 128
        // output bytes, so reject impossible sizes before allocating.
        let maxExpansion = (data.count / 2).multipliedReportingOverflow(by: 128)
        if !maxExpansion.overflow && maxExpansion.partialValue < expectedSize {
            throw ILBMError.malformedRLE
        }
        var out = Data(capacity: expectedSize)
        var i = data.startIndex
        let end = data.endIndex

        while out.count < expectedSize && i < end {
            let control = Int8(bitPattern: data[i])
            i += 1
            if control >= 0 {
                let runLength = Int(control) + 1
                guard i + runLength <= end else { throw ILBMError.malformedRLE }
                out.append(data.subdata(in: i ..< i + runLength))
                i += runLength
            } else if control != -128 {
                let runLength = Int(-Int(control)) + 1
                guard i < end else { throw ILBMError.malformedRLE }
                let byte = data[i]
                i += 1
                out.append(contentsOf: repeatElement(byte, count: runLength))
            }
            // control == -128 → no-op
        }

        guard out.count >= expectedSize else { throw ILBMError.malformedRLE }
        if out.count > expectedSize {
            out = out.prefix(expectedSize)
        }
        return out
    }

    /// Encode a byte sequence with ByteRun1. Used by tests only; not public. Implementation favors correctness over compression
    /// ratio: emits literal runs and replicate runs greedily up to 128 bytes each.
    static func byteRun1Encode(_ data: Data) -> Data {
        var out = Data()
        var i = data.startIndex
        let end = data.endIndex

        while i < end {
            // Look ahead for a run of identical bytes.
            let runByte = data[i]
            var runEnd = i + 1
            while runEnd < end && data[runEnd] == runByte && (runEnd - i) < 128 {
                runEnd += 1
            }
            let runLen = runEnd - i
            if runLen >= 3 {
                // Worth encoding as a replicate run.
                let control = Int8(-(runLen - 1))
                out.append(UInt8(bitPattern: control))
                out.append(runByte)
                i = runEnd
            } else {
                // Literal run up to 128 bytes, stopping if a 3+ replicate run appears.
                var litEnd = i + 1
                while litEnd < end && (litEnd - i) < 128 {
                    // Peek for upcoming replicate run that would be cheaper.
                    if litEnd + 2 < end &&
                       data[litEnd] == data[litEnd + 1] &&
                       data[litEnd + 1] == data[litEnd + 2] {
                        break
                    }
                    litEnd += 1
                }
                let litLen = litEnd - i
                let control = Int8(litLen - 1)
                out.append(UInt8(bitPattern: control))
                out.append(data.subdata(in: i ..< litEnd))
                i = litEnd
            }
        }
        return out
    }
}
