import Foundation

/// A single IFF sub-chunk: a 4-character ID and its raw payload bytes.
public struct IFFChunk: Sendable {
    public let id: String        // 4-char ASCII (e.g. "BMHD", "CMAP", "BODY")
    public let data: Data        // payload, exact length per chunk header (no padding)
}

/// Generic IFF reader. The Amiga EA IFF 85 format wraps everything in a top-level
/// FORM chunk:
///
///     "FORM" <u32 BE size> "<TYPE>" <chunks…>
///
/// Each inner chunk is:
///
///     <4-char id> <u32 BE size> <bytes…> [pad to even]
///
/// `IFFParser` validates the outer FORM, checks the subtype matches `expectedType`
/// (e.g. "ILBM"), and returns the inner chunks in document order.
public enum IFFParser {
    /// Parse a FORM container and return its chunks.
    /// - Parameters:
    ///   - data: Raw bytes of the entire IFF file.
    ///   - expectedType: 4-char subtype to enforce (default "ILBM").
    /// - Throws: `ILBMError.invalidSignature`, `ILBMError.truncated`.
    public static func parse(_ data: Data, expectedType: String = "ILBM") throws -> [IFFChunk] {
        guard data.count >= 12 else { throw ILBMError.truncated(stage: "FORM header") }

        let formID = fourCC(data, at: 0)
        let formSize = beUInt32(data, at: 4)
        let subtype = fourCC(data, at: 8)

        guard formID == "FORM" else { throw ILBMError.invalidSignature }
        guard subtype == expectedType else { throw ILBMError.invalidSignature }

        // The 4-byte subtype counts toward formSize. Inner chunks therefore live
        // in data[12 ..< 8 + formSize], capped by the actual buffer length.
        let declaredEnd = 8 + Int(formSize)
        let end = min(declaredEnd, data.count)
        var cursor = 12

        var chunks: [IFFChunk] = []
        while cursor + 8 <= end {
            let id = fourCC(data, at: cursor)
            let size = Int(beUInt32(data, at: cursor + 4))
            let payloadStart = cursor + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= end else {
                throw ILBMError.truncated(stage: "chunk \(id)")
            }
            let payload = data.subdata(in: payloadStart ..< payloadEnd)
            chunks.append(IFFChunk(id: id, data: payload))
            // Chunks are padded to even byte boundary; pad byte is not counted in size.
            cursor = payloadEnd + (size & 1)
        }
        return chunks
    }

    // MARK: - Byte helpers

    /// Read a 4-character ASCII identifier from `data` at `offset`.
    /// Non-ASCII bytes are replaced with "?" so the result is always 4 chars.
    @inline(__always)
    static func fourCC(_ data: Data, at offset: Int) -> String {
        var s = ""
        s.reserveCapacity(4)
        for i in 0 ..< 4 {
            let b = data[data.startIndex + offset + i]
            if b >= 0x20 && b < 0x7F {
                s.append(Character(UnicodeScalar(b)))
            } else {
                s.append("?")
            }
        }
        return s
    }

    /// Read a big-endian UInt32 from `data` at `offset`.
    @inline(__always)
    static func beUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        let b0 = UInt32(data[base])
        let b1 = UInt32(data[base + 1])
        let b2 = UInt32(data[base + 2])
        let b3 = UInt32(data[base + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    /// Read a big-endian UInt16 from `data` at `offset`.
    @inline(__always)
    static func beUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        let b0 = UInt16(data[base])
        let b1 = UInt16(data[base + 1])
        return (b0 << 8) | b1
    }

    /// Read a big-endian Int16 from `data` at `offset`.
    @inline(__always)
    static func beInt16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: beUInt16(data, at: offset))
    }
}
