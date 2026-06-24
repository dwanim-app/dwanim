import Foundation

/// A read-only view over a ZIP archive held entirely in memory.
///
/// Parsing is driven by the central directory, located via the
/// End-Of-Central-Directory (EOCD) record. Construction fails only when no EOCD
/// can be found; any per-entry defect is surfaced later by `extract(_:)`
/// returning `nil`, so a single damaged entry can never make the rest of the
/// archive unreadable.
public struct ZipArchive: Sendable {

    // MARK: - Stored state

    /// The full archive bytes, retained for lazy extraction.
    let data: Data

    /// Internal central-directory records in stored order. Carries the public
    /// fields plus the offsets/method needed to extract on demand.
    let records: [CentralRecord]

    // MARK: - Public API

    public init(data: Data) throws {
        guard let eocd = ZipArchive.findEOCD(in: data) else {
            throw ZipError.notAZipArchive
        }
        self.data = data
        self.records = ZipArchive.parseCentralDirectory(data: data, eocd: eocd)
    }

    /// The archive's entries in central-directory order.
    public var entries: [ZipEntry] {
        records.map(\.entry)
    }

    /// Extracts and decompresses a single entry by exact path.
    ///
    /// Returns `nil` (and never throws) when the path is absent, the method is
    /// unsupported, the stream is corrupt or truncated, or the decompressed
    /// bytes fail their CRC-32 check.
    public func extract(_ path: String) -> Data? {
        guard let record = records.first(where: { $0.entry.path == path }) else {
            return nil
        }
        guard record.entry.isSupported else { return nil }
        guard let compressed = compressedBytes(for: record) else { return nil }

        let decompressed: Data?
        switch record.method {
        case CompressionMethod.stored:
            decompressed = compressed
        case CompressionMethod.deflate:
            decompressed = ZipArchive.inflate(
                compressed,
                expectedSize: record.entry.uncompressedSize
            )
        default:
            decompressed = nil
        }

        guard let result = decompressed,
              result.count == record.entry.uncompressedSize,
              CRC32.checksum(result) == record.crc
        else {
            return nil
        }
        return result
    }

    // MARK: - File-data slicing

    /// Locates and returns the raw (possibly compressed) file bytes for a
    /// record by reading its local file header. Returns `nil` if any offset or
    /// length falls outside the archive bounds.
    private func compressedBytes(for record: CentralRecord) -> Data? {
        let base = data.startIndex
        let headerStart = base + record.localHeaderOffset

        // Local file header is 30 fixed bytes, then name + extra fields.
        guard reader(at: headerStart, length: 30) != nil else { return nil }
        guard readU32(at: headerStart) == LocalHeader.signature else { return nil }

        let nameLength = Int(readU16(at: headerStart + 26))
        let extraLength = Int(readU16(at: headerStart + 28))
        let dataStart = headerStart + 30 + nameLength + extraLength
        let dataEnd = dataStart + record.compressedSize

        guard dataStart >= base, dataEnd <= data.endIndex, dataStart <= dataEnd else {
            return nil
        }
        return data.subdata(in: dataStart..<dataEnd)
    }

    // MARK: - Bounded byte access

    /// Returns the slice `[offset, offset+length)` if it lies within the data.
    private func reader(at offset: Int, length: Int) -> Data? {
        guard offset >= data.startIndex, offset + length <= data.endIndex else {
            return nil
        }
        return data.subdata(in: offset..<(offset + length))
    }

    private func readU16(at offset: Int) -> UInt16 {
        ByteReader.u16(data, at: offset)
    }

    private func readU32(at offset: Int) -> UInt32 {
        ByteReader.u32(data, at: offset)
    }
}

// MARK: - Compression methods

/// The compression-method identifiers the reader understands.
enum CompressionMethod {
    static let stored: UInt16 = 0
    static let deflate: UInt16 = 8
}

// MARK: - Central directory record

/// Internal companion to `ZipEntry` carrying the data needed for extraction.
struct CentralRecord: Sendable {
    let entry: ZipEntry
    let method: UInt16
    let crc: UInt32
    let compressedSize: Int
    let localHeaderOffset: Int
}

// MARK: - Header layout constants

enum LocalHeader {
    static let signature: UInt32 = 0x0403_4b50
}

enum CentralHeader {
    static let signature: UInt32 = 0x0201_4b50
    /// Fixed size before the variable name/extra/comment fields.
    static let fixedSize = 46
}

enum EOCDLayout {
    static let signature: UInt32 = 0x0605_4b50
    /// Fixed size before the variable trailing comment.
    static let fixedSize = 22
    /// Maximum span the comment can occupy (16-bit length), bounding the scan.
    static let maxCommentSize = 0xFFFF
}
