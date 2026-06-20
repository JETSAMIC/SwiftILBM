import Foundation

/// Decodes the BODY chunk into raw (uncompressed) planar bytes.
///
/// BODY storage layout for one row of an N-plane ILBM:
///
///     plane0_row[bytesPerRow] plane1_row[bytesPerRow] … planeN-1_row[bytesPerRow]
///
/// repeated for every row. If `BMHD.masking == 1` there is an additional mask
/// plane appended after the N bitplanes on every row; we currently *skip past*
/// those bytes during decoding but don't expose them.
///
/// Compression modes:
///  - 0: uncompressed; payload is exactly height * planesPerRow * bytesPerRow bytes
///       (plus optional mask).
///  - 1: ByteRun1 (Apple PackBits). Per-row decoding is not required — the spec
///       allows runs to cross row boundaries, though most encoders restart per
///       row. We decode the whole stream into one buffer of the expected size.
enum BODYChunk {
    /// Decode the BODY payload into raw planar bytes, ready for planar→chunky
    /// conversion. Mask-plane bytes (if any) are stripped.
    static func decode(_ data: Data, bmhd: BMHDChunk) throws -> Data {
        let bytesPerPlaneRow = bmhd.bytesPerRow
        let planeCount = Int(bmhd.nPlanes)
        let maskPlanes = (bmhd.masking == 1) ? 1 : 0
        let totalPlanesPerRow = planeCount + maskPlanes
        let rawRowBytes = totalPlanesPerRow * bytesPerPlaneRow
        let expectedTotal = rawRowBytes * Int(bmhd.height)

        let raw: Data
        switch bmhd.compression {
        case 0:
            guard data.count >= expectedTotal else {
                throw ILBMError.truncated(stage: "BODY (raw)")
            }
            raw = data.prefix(expectedTotal)
        case 1:
            raw = try byteRun1Decode(data, expectedSize: expectedTotal)
        default:
            throw ILBMError.unsupportedCompression(bmhd.compression)
        }

        // Strip mask plane bytes per row if present.
        guard maskPlanes > 0 else { return raw }

        var stripped = Data(capacity: planeCount * bytesPerPlaneRow * Int(bmhd.height))
        for row in 0 ..< Int(bmhd.height) {
            let rowStart = row * rawRowBytes
            let imageBytes = planeCount * bytesPerPlaneRow
            stripped.append(raw.subdata(in: rowStart ..< rowStart + imageBytes))
            // mask bytes after imageBytes are discarded
        }
        return stripped
    }

    /// Decompress a ByteRun1 (PackBits) stream into exactly `expectedSize` bytes.
    ///
    /// Per Apple's PackBits spec, the control byte `n` is read as a signed Int8:
    ///   -  0...127  → copy the next (n + 1) bytes literally
    ///   -  -1...-127 → repeat the next byte (-n + 1) times
    ///   -  -128      → no-op (skip the control byte)
    ///
    /// We allow the decoded output to *meet or exceed* expectedSize and trim;
    /// real-world encoders sometimes emit a trailing literal that overshoots
    /// by a byte or two.
    static func byteRun1Decode(_ data: Data, expectedSize: Int) throws -> Data {
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

    /// Encode a byte sequence with ByteRun1. Used only by the round-trip test;
    /// not exposed publicly. Implementation favors correctness over compression
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
