import Compression
import Foundation

/// Assembles raw ZIP archive bytes programmatically so tests never depend on
/// real archive files. This builder is the executable specification for the
/// subset of the ZIP format the reader supports: local file headers, a central
/// directory, and an End-Of-Central-Directory (EOCD) record.
///
/// Only the fields the reader actually consults are populated with meaningful
/// values; everything else is written as zero. The builder is deliberately
/// explicit so the on-disk format is auditable from the test alone.
enum ZipFixtureBuilder {

    // MARK: - Compression methods

    /// Compression method identifiers as defined by the ZIP format.
    enum Method: UInt16 {
        case stored = 0
        case deflate = 8
        /// An arbitrary method the reader does not support (used to exercise
        /// the `isSupported == false` path).
        case unsupported = 99
    }

    // MARK: - Entry description

    /// A single file to place into the synthetic archive.
    struct Entry {
        let path: String
        let payload: Data
        let method: Method
        /// When true, the stored bytes are deliberately damaged so extraction
        /// must fail (truncated for deflate, mutated for stored).
        var corruptStream: Bool = false
        /// When true, the central-directory CRC-32 is deliberately wrong so the
        /// reader's CRC verification must reject the otherwise-valid bytes.
        var wrongCRC: Bool = false
    }

    // MARK: - Signatures

    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let eocdSignature: UInt32 = 0x0605_4b50

    // MARK: - Build

    /// Produces a complete archive for the given entries. When `comment` is
    /// non-empty it is appended after the EOCD record so tests can verify the
    /// backwards scan for the EOCD signature.
    static func build(entries: [Entry], comment: String = "") -> Data {
        var localSection = Data()
        var centralSection = Data()
        var offsets: [Int] = []

        for entry in entries {
            offsets.append(localSection.count)
            localSection.append(localHeader(for: entry))
        }

        for (index, entry) in entries.enumerated() {
            centralSection.append(centralHeader(for: entry, localOffset: offsets[index]))
        }

        var archive = Data()
        archive.append(localSection)
        let centralOffset = archive.count
        archive.append(centralSection)
        archive.append(
            eocd(
                entryCount: entries.count,
                centralSize: centralSection.count,
                centralOffset: centralOffset,
                comment: comment
            )
        )
        return archive
    }

    // MARK: - Local file header

    private static func localHeader(for entry: Entry) -> Data {
        let pathBytes = Data(entry.path.utf8)
        let stored = storedBytes(for: entry)

        var data = Data()
        data.appendLE(localHeaderSignature)
        data.appendLE(UInt16(20))                 // version needed
        data.appendLE(UInt16(0))                  // general purpose flags
        data.appendLE(entry.method.rawValue)      // compression method
        data.appendLE(UInt16(0))                  // mod time
        data.appendLE(UInt16(0))                  // mod date
        data.appendLE(crcValue(for: entry))       // CRC-32
        data.appendLE(UInt32(stored.count))       // compressed size
        data.appendLE(UInt32(entry.payload.count))// uncompressed size
        data.appendLE(UInt16(pathBytes.count))    // file name length
        data.appendLE(UInt16(0))                  // extra field length
        data.append(pathBytes)
        data.append(stored)
        return data
    }

    // MARK: - Central directory header

    private static func centralHeader(for entry: Entry, localOffset: Int) -> Data {
        let pathBytes = Data(entry.path.utf8)
        let stored = storedBytes(for: entry)

        var data = Data()
        data.appendLE(centralHeaderSignature)
        data.appendLE(UInt16(20))                 // version made by
        data.appendLE(UInt16(20))                 // version needed
        data.appendLE(UInt16(0))                  // general purpose flags
        data.appendLE(entry.method.rawValue)      // compression method
        data.appendLE(UInt16(0))                  // mod time
        data.appendLE(UInt16(0))                  // mod date
        data.appendLE(crcValue(for: entry))       // CRC-32
        data.appendLE(UInt32(stored.count))       // compressed size
        data.appendLE(UInt32(entry.payload.count))// uncompressed size
        data.appendLE(UInt16(pathBytes.count))    // file name length
        data.appendLE(UInt16(0))                  // extra field length
        data.appendLE(UInt16(0))                  // file comment length
        data.appendLE(UInt16(0))                  // disk number start
        data.appendLE(UInt16(0))                  // internal attributes
        data.appendLE(UInt32(0))                  // external attributes
        data.appendLE(UInt32(localOffset))        // local header offset
        data.append(pathBytes)
        return data
    }

    // MARK: - End of central directory

    private static func eocd(
        entryCount: Int,
        centralSize: Int,
        centralOffset: Int,
        comment: String
    ) -> Data {
        let commentBytes = Data(comment.utf8)

        var data = Data()
        data.appendLE(eocdSignature)
        data.appendLE(UInt16(0))                  // this disk number
        data.appendLE(UInt16(0))                  // disk with central directory
        data.appendLE(UInt16(entryCount))         // entries on this disk
        data.appendLE(UInt16(entryCount))         // total entries
        data.appendLE(UInt32(centralSize))        // central directory size
        data.appendLE(UInt32(centralOffset))      // central directory offset
        data.appendLE(UInt16(commentBytes.count)) // comment length
        data.append(commentBytes)
        return data
    }

    // MARK: - Payload encoding

    /// The bytes actually written into the file data region, honouring the
    /// requested compression method and any deliberate corruption.
    private static func storedBytes(for entry: Entry) -> Data {
        let encoded: Data
        switch entry.method {
        case .stored, .unsupported:
            encoded = entry.payload
        case .deflate:
            encoded = rawDeflate(entry.payload)
        }

        guard entry.corruptStream else { return encoded }

        switch entry.method {
        case .deflate:
            // Truncate the compressed stream so inflation cannot complete.
            return encoded.prefix(max(1, encoded.count / 2))
        case .stored, .unsupported:
            // Mutate a byte so the CRC of the recovered bytes won't match.
            var mutated = encoded
            if !mutated.isEmpty {
                mutated[mutated.startIndex] = mutated[mutated.startIndex] &+ 1
            }
            return mutated
        }
    }

    private static func crcValue(for entry: Entry) -> UInt32 {
        let real = TestCRC32.checksum(entry.payload)
        return entry.wrongCRC ? real ^ 0xFFFF_FFFF : real
    }

    // MARK: - Raw DEFLATE

    /// Compresses `input` into a raw DEFLATE stream (no zlib/gzip wrapper),
    /// matching what the ZIP format stores for method 8.
    static func rawDeflate(_ input: Data) -> Data {
        if input.isEmpty {
            // An empty raw DEFLATE stream is a single final, empty stored block.
            return Data([0x03, 0x00])
        }
        let capacity = input.count + 64
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        precondition(written > 0, "Fixture deflate encoding failed")
        return output.prefix(written)
    }
}

// MARK: - Little-endian append helpers

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

// MARK: - Independent CRC-32 for fixtures

/// A self-contained CRC-32 used only to stamp fixtures. Kept separate from the
/// production implementation so the test asserts against an independent oracle.
enum TestCRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = UInt32(bitPattern: -Int32(crc & 1))
                crc = (crc >> 1) ^ (0xEDB8_8320 & mask)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
