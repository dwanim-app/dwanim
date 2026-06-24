import Foundation

/// Standard CRC-32 (the IEEE 802.3 variant used by the ZIP format): reflected
/// input and output, polynomial `0xEDB88320`, initial/final XOR `0xFFFFFFFF`.
enum CRC32 {

    // MARK: - Public

    /// Computes the CRC-32 checksum of `data`.
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                let index = Int((crc ^ UInt32(byte)) & 0xff)
                crc = (crc >> 8) ^ table[index]
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Lookup table

    /// Precomputed remainder table, one entry per possible trailing byte.
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                if value & 1 == 1 {
                    value = (value >> 1) ^ 0xEDB8_8320
                } else {
                    value >>= 1
                }
            }
            return value
        }
    }()
}
