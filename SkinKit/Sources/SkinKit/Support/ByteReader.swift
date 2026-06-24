import Foundation

/// Bounds-checked little-endian integer reads from a `Data` buffer. Out-of-range
/// reads return zero rather than trapping, so malformed archives degrade into
/// failed extractions instead of crashes.
enum ByteReader {

    // MARK: - Little-endian reads

    static func u16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= data.startIndex, offset + 2 <= data.endIndex else { return 0 }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return b0 | (b1 << 8)
    }

    static func u32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= data.startIndex, offset + 4 <= data.endIndex else { return 0 }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
