import Foundation

// MARK: - Central directory parsing

extension ZipArchive {

    /// The pieces of the EOCD record the parser needs.
    struct EOCD {
        let entryCount: Int
        let centralDirectoryOffset: Int
    }

    /// Scans backwards from the end of `data` for the EOCD signature, tolerating
    /// a trailing archive comment. Returns `nil` if no plausible record exists.
    static func findEOCD(in data: Data) -> EOCD? {
        let base = data.startIndex
        let count = data.count
        guard count >= EOCDLayout.fixedSize else { return nil }

        // The signature can sit at most `maxCommentSize` bytes before the end.
        let earliest = max(base, data.endIndex - EOCDLayout.fixedSize - EOCDLayout.maxCommentSize)
        var index = data.endIndex - EOCDLayout.fixedSize

        while index >= earliest {
            if ByteReader.u32(data, at: index) == EOCDLayout.signature {
                let entryCount = Int(ByteReader.u16(data, at: index + 10))
                let cdOffset = Int(ByteReader.u32(data, at: index + 16))
                // Reject records whose central directory points outside the data.
                if cdOffset >= 0, base + cdOffset <= data.endIndex {
                    return EOCD(entryCount: entryCount, centralDirectoryOffset: cdOffset)
                }
            }
            index -= 1
        }
        return nil
    }

    /// Walks the central directory, producing one record per entry.
    ///
    /// Per-entry fault tolerance (ADR-2): a single malformed record must never
    /// hide the records that follow it. When a record fails any structural check
    /// the parser resynchronizes by scanning forward for the next central-record
    /// signature and resumes from there, rather than abandoning the rest of the
    /// directory. Parsing stops cleanly only when no further signature remains
    /// (e.g. a genuinely truncated tail).
    static func parseCentralDirectory(data: Data, eocd: EOCD) -> [CentralRecord] {
        var records: [CentralRecord] = []
        records.reserveCapacity(eocd.entryCount)

        let base = data.startIndex
        var cursor = base + eocd.centralDirectoryOffset

        // The advertised count is the expected number of records, but a damaged
        // directory may force extra resync hops. Cap total iterations so the loop
        // can never spin forever on adversarial input.
        var iterationsRemaining = eocd.entryCount * 2 + 1

        while records.count < eocd.entryCount, iterationsRemaining > 0 {
            iterationsRemaining -= 1

            guard let record = parseRecord(data: data, at: cursor) else {
                // Malformed record: resynchronize on the next central signature
                // strictly after the current cursor, or stop if none remains.
                guard let next = nextCentralSignature(in: data, after: cursor) else {
                    break
                }
                cursor = next
                continue
            }

            records.append(record.record)
            cursor = record.nextCursor
        }
        return records
    }

    /// A parsed record paired with the cursor position of the record that
    /// should follow it.
    private struct ParsedRecord {
        let record: CentralRecord
        let nextCursor: Int
    }

    /// Attempts to parse one central-directory record at `cursor`. Returns `nil`
    /// if the fixed header, signature, or name bounds fail their checks.
    private static func parseRecord(data: Data, at cursor: Int) -> ParsedRecord? {
        guard cursor >= data.startIndex,
              cursor + CentralHeader.fixedSize <= data.endIndex else { return nil }
        guard ByteReader.u32(data, at: cursor) == CentralHeader.signature else { return nil }

        let method = ByteReader.u16(data, at: cursor + 10)
        let crc = ByteReader.u32(data, at: cursor + 16)
        let compressedSize = Int(ByteReader.u32(data, at: cursor + 20))
        let uncompressedSize = Int(ByteReader.u32(data, at: cursor + 24))
        let nameLength = Int(ByteReader.u16(data, at: cursor + 28))
        let extraLength = Int(ByteReader.u16(data, at: cursor + 30))
        let commentLength = Int(ByteReader.u16(data, at: cursor + 32))
        let localOffset = Int(ByteReader.u32(data, at: cursor + 42))

        let nameStart = cursor + CentralHeader.fixedSize
        let nameEnd = nameStart + nameLength
        guard nameEnd <= data.endIndex else { return nil }

        let path = String(decoding: data.subdata(in: nameStart..<nameEnd), as: UTF8.self)
        let isSupported = method == CompressionMethod.stored || method == CompressionMethod.deflate

        let entry = ZipEntry(
            path: path,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            isSupported: isSupported
        )
        let record = CentralRecord(
            entry: entry,
            method: method,
            crc: crc,
            compressedSize: compressedSize,
            localHeaderOffset: localOffset
        )
        return ParsedRecord(record: record, nextCursor: nameEnd + extraLength + commentLength)
    }

    /// Scans forward for the next central-record signature strictly after
    /// `cursor`, bounded by `data.endIndex`. Returns the signature's offset, or
    /// `nil` if none remains.
    private static func nextCentralSignature(in data: Data, after cursor: Int) -> Int? {
        // Begin one byte past the current position so the cursor always advances,
        // and clamp into range so a bogus cursor cannot start the scan OOB.
        let lower = max(data.startIndex, cursor + 1)
        var probe = lower
        // A signature is 4 bytes, so the last position worth testing is endIndex-4.
        let last = data.endIndex - 4
        while probe <= last {
            if ByteReader.u32(data, at: probe) == CentralHeader.signature {
                return probe
            }
            probe += 1
        }
        return nil
    }
}
