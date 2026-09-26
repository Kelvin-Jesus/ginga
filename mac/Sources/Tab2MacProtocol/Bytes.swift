import Foundation

/// Big-endian writer for the binary parts of the protocol.
public struct ByteWriter: Sendable {
    public private(set) var data: Data

    public init(capacity: Int = 0) {
        data = Data()
        data.reserveCapacity(capacity)
    }

    public mutating func u8(_ value: UInt8) { data.append(value) }
    public mutating func u16(_ value: UInt16) { append(value.bigEndian) }
    public mutating func u32(_ value: UInt32) { append(value.bigEndian) }
    public mutating func u64(_ value: UInt64) { append(value.bigEndian) }
    public mutating func i16(_ value: Int16) { u16(UInt16(bitPattern: value)) }
    public mutating func bytes(_ value: Data) { data.append(value) }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }
}

/// Bounds-checked big-endian reader. Every read throws `ProtocolError.truncated` instead of trapping.
public struct ByteReader: Sendable {
    private let bytes: [UInt8]
    public private(set) var offset = 0
    private let context: String

    public init(_ data: Data, context: String) {
        bytes = [UInt8](data)
        self.context = context
    }

    public var remaining: Int { bytes.count - offset }
    public var count: Int { bytes.count }

    public mutating func u8() throws(ProtocolError) -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    public mutating func u16() throws(ProtocolError) -> UInt16 {
        UInt16(truncatingIfNeeded: try integer(byteCount: 2))
    }

    public mutating func u32() throws(ProtocolError) -> UInt32 {
        UInt32(truncatingIfNeeded: try integer(byteCount: 4))
    }

    public mutating func u64() throws(ProtocolError) -> UInt64 {
        try integer(byteCount: 8)
    }

    public mutating func i16() throws(ProtocolError) -> Int16 {
        Int16(bitPattern: try u16())
    }

    public mutating func data(count: Int) throws(ProtocolError) -> Data {
        try require(count)
        defer { offset += count }
        return Data(bytes[offset..<offset + count])
    }

    /// Everything that has not been read yet.
    public mutating func rest() -> Data {
        defer { offset = bytes.count }
        return Data(bytes[offset...])
    }

    /// Moves forward to `position` (used to skip fields appended by newer peers).
    public mutating func skip(to position: Int) throws(ProtocolError) {
        guard position >= offset else { throw .malformed("\(context): cannot skip backwards to \(position) from \(offset)") }
        try require(position - offset)
        offset = position
    }

    private mutating func integer(byteCount: Int) throws(ProtocolError) -> UInt64 {
        try require(byteCount)
        var value: UInt64 = 0
        for index in offset..<offset + byteCount {
            value = value << 8 | UInt64(bytes[index])
        }
        offset += byteCount
        return value
    }

    private func require(_ count: Int) throws(ProtocolError) {
        guard count >= 0, remaining >= count else {
            throw .truncated("\(context): need \(count) byte(s) at offset \(offset), have \(remaining)")
        }
    }
}

extension Data {
    /// Lowercase hexadecimal, as used by the golden test vectors.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    public init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
