import Foundation

/// A single IFF chunk: a four-character identifier and its payload.
public struct IFFChunk: Sendable, Equatable {
    /// Four-character ASCII identifier, for example `"BMHD"`, `"CMAP"` or
    /// `"BODY"`. Non-printable bytes are shown as `"?"`.
    public let id: String
    /// The payload, exactly as long as the chunk header declares (the pad
    /// byte that follows odd-length chunks is not included). Zero-based.
    public let data: Data

    /// Creates a chunk from an identifier and payload.
    public init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

/// A located `FORM` with its own chunks and the `PROP` defaults in scope.
struct IFFForm {
    /// The FORM type, for example `"ILBM"`.
    let type: String
    /// The FORM's own chunks, in file order.
    let chunks: [IFFChunk]
    /// Chunks of the matching `PROP` of each enclosing `LIST`, innermost
    /// `LIST` first.
    let propScopes: [[IFFChunk]]

    /// The FORM's first `BODY`. A `BODY` is never inherited from a `PROP`.
    var body: Data? { chunks.first { $0.id == "BODY" }?.data }

    /// Resolve a property chunk with the ILBM precedence rules: the last
    /// occurrence before `BODY` wins; failing that, an occurrence after
    /// `BODY` (tolerated for lenient reading); failing that, the last
    /// occurrence in the innermost `PROP` that has one.
    func property(_ id: String) -> Data? {
        let bodyIndex = chunks.firstIndex { $0.id == "BODY" } ?? chunks.endIndex
        if let local = chunks[..<bodyIndex].last(where: { $0.id == id }) { return local.data }
        if let late = chunks[bodyIndex...].first(where: { $0.id == id }) { return late.data }
        for scope in propScopes {
            if let inherited = scope.last(where: { $0.id == id }) { return inherited.data }
        }
        return nil
    }

    /// All occurrences of a repeatable property such as `CRNG`: the FORM's
    /// own if it has any, else those of the innermost `PROP` that has any.
    func repeatedProperty(_ id: String) -> [Data] {
        let local = chunks.filter { $0.id == id }.map(\.data)
        if !local.isEmpty { return local }
        for scope in propScopes {
            let inherited = scope.filter { $0.id == id }.map(\.data)
            if !inherited.isEmpty { return inherited }
        }
        return []
    }
}

/// Reader for EA IFF 85 containers.
///
/// An IFF file is a tree of chunks. Every chunk is
///
///     <4-char id> <UInt32 big-endian size> <size bytes> [pad byte if size is odd]
///
/// and the group chunks `FORM`, `LIST` and `CAT ` begin their payload with a
/// 4-character type and then contain further chunks. `IFFParser` locates the
/// first `FORM` of the requested type — at the top level, or nested inside
/// `LIST`, `CAT ` or another `FORM` such as `ANIM` — and returns its chunks.
/// Within a `LIST`, `PROP` chunks of the same type supply defaults; they are
/// appended after the `FORM`'s own chunks (innermost `LIST` first).
public enum IFFParser {

    /// Maximum group-chunk nesting depth that is searched.
    static let maximumNestingDepth = 8

    /// Parse an IFF file and return the chunks of the first `FORM` of type
    /// `expectedType`.
    ///
    /// - Parameters:
    ///   - data: The entire IFF file.
    ///   - expectedType: Four-character `FORM` type to look for. Defaults to
    ///     `"ILBM"`.
    /// - Returns: The `FORM`'s chunks in file order (followed by any `PROP`
    ///   defaults from an enclosing `LIST`).
    /// - Throws: ``ILBMError/truncated(stage:)`` if the file is shorter than a
    ///   group header or a chunk runs past the end of its container, or
    ///   ``ILBMError/invalidSignature`` if no matching `FORM` exists.
    public static func parse(_ data: Data, expectedType: String = "ILBM") throws -> [IFFChunk] {
        let form = try findForm(in: data, types: [expectedType])
        return form.chunks + form.propScopes.flatMap { $0 }
    }

    /// Locate the first `FORM` whose type is in `types`.
    static func findForm(in input: Data, types: Set<String>) throws -> IFFForm {
        let data = input.startIndex == 0 ? input : Data(input)
        guard data.count >= 12 else { throw ILBMError.truncated(stage: "FORM header") }
        let id = fourCC(data, at: 0)
        guard ["FORM", "LIST", "CAT "].contains(id) else { throw ILBMError.invalidSignature }
        // A wrong group size is common in the wild; clamp it to the buffer.
        let end = clampedEnd(start: 8, size: beUInt32(data, at: 4), limit: data.count)
        let found = try search(data, groupID: id, typeOffset: 8, end: end,
                               types: types, props: [], depth: 0)
        guard let found else { throw ILBMError.invalidSignature }
        return found
    }

    /// Search the group chunk whose type field is at `typeOffset` and whose
    /// payload ends at `end`.
    private static func search(
        _ data: Data,
        groupID: String,
        typeOffset: Int,
        end: Int,
        types: Set<String>,
        props: [[IFFChunk]],
        depth: Int
    ) throws -> IFFForm? {
        guard typeOffset + 4 <= end else { return nil }
        let groupType = fourCC(data, at: typeOffset)

        if groupID == "FORM" && types.contains(groupType) {
            var chunks: [IFFChunk] = []
            try walk(data, from: typeOffset + 4, to: end) { id, start, payloadEnd in
                chunks.append(IFFChunk(id: id, data: data.subdata(in: start..<payloadEnd)))
            }
            return IFFForm(type: groupType, chunks: chunks, propScopes: props)
        }

        guard depth < maximumNestingDepth else { return nil }

        var result: IFFForm?
        var inheritedProps = props
        try walk(data, from: typeOffset + 4, to: end) { id, start, payloadEnd in
            guard result == nil else { return }
            switch id {
            case "PROP" where groupID == "LIST" && payloadEnd - start >= 4:
                if types.contains(fourCC(data, at: start)) {
                    var propChunks: [IFFChunk] = []
                    try walk(data, from: start + 4, to: payloadEnd) { pid, ps, pe in
                        propChunks.append(IFFChunk(id: pid, data: data.subdata(in: ps..<pe)))
                    }
                    // This LIST's PROP is more specific than any outer one.
                    inheritedProps = [propChunks] + inheritedProps
                }
            case "FORM", "LIST", "CAT ":
                result = try search(data, groupID: id, typeOffset: start, end: payloadEnd,
                                    types: types, props: inheritedProps, depth: depth + 1)
            default:
                break
            }
        }
        return result
    }

    /// Visit each chunk in `[start, end)`.
    ///
    /// The visitor receives the chunk ID and the absolute payload range.
    /// Iteration is bounded: every step advances by at least 8 bytes.
    private static func walk(
        _ data: Data,
        from start: Int,
        to end: Int,
        _ visit: (String, Int, Int) throws -> Void
    ) throws {
        var cursor = start
        while cursor + 8 <= end {
            let id = fourCC(data, at: cursor)
            let size = beUInt32(data, at: cursor + 4)
            let payloadStart = cursor + 8
            guard UInt64(size) <= UInt64(end - payloadStart) else {
                throw ILBMError.truncated(stage: "chunk \(id)")
            }
            let payloadEnd = payloadStart + Int(size)
            try visit(id, payloadStart, payloadEnd)
            // Odd-sized chunks are followed by a pad byte not counted in size.
            cursor = payloadEnd + Int(size & 1)
        }
    }

    /// `start + size`, clamped to `limit` without overflowing on 32-bit Int.
    private static func clampedEnd(start: Int, size: UInt32, limit: Int) -> Int {
        UInt64(size) >= UInt64(limit - start) ? limit : start + Int(size)
    }

    // MARK: - Byte helpers

    /// Read a 4-character ASCII identifier at `offset` (relative to
    /// `data.startIndex`). Non-printable bytes become `"?"`.
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

    /// Read a big-endian UInt32 at `offset` (relative to `data.startIndex`).
    @inline(__always)
    static func beUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return (UInt32(data[base]) << 24) | (UInt32(data[base + 1]) << 16)
            | (UInt32(data[base + 2]) << 8) | UInt32(data[base + 3])
    }

    /// Read a big-endian UInt16 at `offset` (relative to `data.startIndex`).
    @inline(__always)
    static func beUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return (UInt16(data[base]) << 8) | UInt16(data[base + 1])
    }

    /// Read a big-endian Int16 at `offset` (relative to `data.startIndex`).
    @inline(__always)
    static func beInt16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: beUInt16(data, at: offset))
    }
}
