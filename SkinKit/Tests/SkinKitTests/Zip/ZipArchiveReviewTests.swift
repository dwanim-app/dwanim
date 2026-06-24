import Foundation
import XCTest
@testable import SkinKit

/// Adversarial completeness review for the fault-tolerant ZIP reader.
///
/// These tests were written by an independent review (QA) pass, NOT by the
/// implementer. They exercise behaviours drawn from real-world `.wsz` archives
/// that the original 14-test suite does not cover. Failures here are EXPECTED
/// and desirable: each failing test documents a concrete gap for the implementer
/// to close. Tests that pass confirm the implementation already handles the
/// case correctly (so the gap is in coverage only, not behaviour).
///
/// No real archive files are used; every fixture is assembled in-memory, reusing
/// `ZipFixtureBuilder` where possible and hand-rolling raw bytes where the
/// builder cannot express the defect (e.g. a corrupt mid-directory record or a
/// bogus local-header offset).
final class ZipArchiveReviewTests: XCTestCase {

    // MARK: - Gap 1: duplicate / case-variant paths in one archive

    /// Real skins ship `cbuttons.bmp` AND `CBUTTONS.bmp` side by side. Both must
    /// be listed, and an exact-path extract of each must return its own bytes.
    func testCaseVariantPathsAreDistinctAndExtractIndependently() throws {
        let lower = Data("lower-case payload".utf8)
        let upper = Data("UPPER-CASE PAYLOAD".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "cbuttons.bmp", payload: lower, method: .stored),
            .init(path: "CBUTTONS.BMP", payload: upper, method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(archive.entries.map(\.path), ["cbuttons.bmp", "CBUTTONS.BMP"])
        XCTAssertEqual(archive.extract("cbuttons.bmp"), lower)
        XCTAssertEqual(archive.extract("CBUTTONS.BMP"), upper)
    }

    /// Two entries that share the EXACT same path. The reader must at least list
    /// both (lossless enumeration) and never crash on extract. We assert both are
    /// enumerated; documents whether the reader silently collapses duplicates.
    func testExactDuplicatePathsAreBothListed() throws {
        let firstBytes = Data("first copy".utf8)
        let secondBytes = Data("second copy, different length".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "dup.txt", payload: firstBytes, method: .stored),
            .init(path: "dup.txt", payload: secondBytes, method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        // Lossless enumeration: both records appear in the listing.
        XCTAssertEqual(archive.entries.filter { $0.path == "dup.txt" }.count, 2)
        // Extract must not crash; it returns one of the two valid payloads.
        let extracted = archive.extract("dup.txt")
        XCTAssertNotNil(extracted)
        XCTAssertTrue(extracted == firstBytes || extracted == secondBytes)
    }

    // MARK: - Gap 2: nested subfolder paths round-trip

    /// Sprites live at e.g. `baseskin/TITLEBAR.BMP`. Listing of nested paths is
    /// already covered; the round-trip extract of a nested deflate entry is not.
    func testNestedSubfolderPathRoundTrips() throws {
        let titlebar = Data(repeating: 0xAB, count: 777)
        let nested = Data("region map".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "baseskin/TITLEBAR.BMP", payload: titlebar, method: .deflate),
            .init(path: "baseskin/sub/region.txt", payload: nested, method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(
            archive.entries.map(\.path),
            ["baseskin/TITLEBAR.BMP", "baseskin/sub/region.txt"]
        )
        XCTAssertEqual(archive.extract("baseskin/TITLEBAR.BMP"), titlebar)
        XCTAssertEqual(archive.extract("baseskin/sub/region.txt"), nested)
    }

    // MARK: - Gap 3: directory entries (path ending in '/', zero size)

    /// A directory entry: path ends in '/', zero compressed/uncompressed size,
    /// stored method. It must be listed sanely and extract must not crash/throw
    /// (returning empty Data or nil are both acceptable).
    func testDirectoryEntryIsListedAndExtractDoesNotCrash() throws {
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "folder/", payload: Data(), method: .stored),
            .init(path: "folder/file.txt", payload: Data("inside".utf8), method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        let dir = try XCTUnwrap(archive.entries.first { $0.path == "folder/" })
        XCTAssertEqual(dir.uncompressedSize, 0)

        // Must not crash or throw. Empty Data or nil are both sane outcomes.
        let extracted = archive.extract("folder/")
        XCTAssertTrue(extracted == nil || extracted == Data())

        // The real file alongside it still extracts.
        XCTAssertEqual(archive.extract("folder/file.txt"), Data("inside".utf8))
    }

    // MARK: - Gap 4: EOCD false-positive robustness

    /// An entry payload that literally CONTAINS the EOCD signature bytes
    /// (PK\x05\x06). The backward scan must skip the false marker embedded in the
    /// file data and locate the real EOCD at the tail.
    func testEmbeddedEOCDSignatureInPayloadDoesNotFoolScanner() throws {
        // Build a payload containing the EOCD signature plus enough trailing
        // bytes that, if mistaken for a real EOCD, the parse would diverge.
        var poison = Data("prefix-".utf8)
        poison.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // "PK\x05\x06"
        poison.append(contentsOf: [UInt8](repeating: 0x00, count: 18)) // fake EOCD body
        poison.append(contentsOf: Data("-suffix".utf8))

        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "trap.bin", payload: poison, method: .stored),
            .init(path: "after.txt", payload: Data("still here".utf8), method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(archive.entries.map(\.path), ["trap.bin", "after.txt"])
        XCTAssertEqual(archive.extract("trap.bin"), poison)
        XCTAssertEqual(archive.extract("after.txt"), Data("still here".utf8))
    }

    // MARK: - Gap 5: corrupt central-directory record isolation (parse level)

    /// One central-directory record in the MIDDLE has a corrupted signature.
    /// Per ADR-2 (one bad entry must never break the others), the records before
    /// AND after it should still be enumerated and extractable. This probes
    /// whether the parser ISOLATES a bad record or ABORTS the whole directory.
    func testCorruptMiddleCentralRecordDoesNotDropLaterEntries() throws {
        let a = Data("entry A".utf8)
        let b = Data("entry B".utf8)
        let c = Data("entry C".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "a.txt", payload: a, method: .stored),
            .init(path: "b.txt", payload: b, method: .stored),
            .init(path: "c.txt", payload: c, method: .stored),
        ]
        var data = ZipFixtureBuilder.build(entries: inputs)

        // Corrupt the SECOND central-directory record's signature. The central
        // directory begins after the three local sections; locate the second
        // central header by scanning for central signatures and damaging the 2nd.
        let centralSig: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        let secondCentralOffset = try XCTUnwrap(
            nthOccurrence(of: centralSig, in: data, n: 2),
            "fixture should contain at least two central-directory records"
        )
        // Flip the signature's third byte so the parser sees a bad record.
        data[data.startIndex + secondCentralOffset + 2] = 0xFF

        let archive = try ZipArchive(data: data)

        // Entry A precedes the damage and must survive.
        XCTAssertEqual(archive.extract("a.txt"), a)
        // ADR-2 requires entry C (AFTER the damaged record) to survive too.
        XCTAssertNotNil(
            archive.entries.first { $0.path == "c.txt" },
            "entry after a corrupt central record was dropped — parser aborts instead of isolating"
        )
        XCTAssertEqual(archive.extract("c.txt"), c)
    }

    /// A central-directory record whose local-header offset is bogus (points
    /// nowhere valid). The record should still be LISTED, its extract should
    /// return nil, and its neighbours must be unaffected. This is parse-level
    /// isolation of a structurally-valid-but-semantically-broken record.
    func testBogusLocalOffsetRecordIsListedExtractNilNeighboursOK() throws {
        let good1 = Data("good one".utf8)
        let victim = Data("victim payload".utf8)
        let good2 = Data("good two".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "g1.txt", payload: good1, method: .stored),
            .init(path: "victim.txt", payload: victim, method: .stored),
            .init(path: "g2.txt", payload: good2, method: .stored),
        ]
        var data = ZipFixtureBuilder.build(entries: inputs)

        // Find the central record for "victim.txt" and overwrite its local-header
        // offset (4 bytes at central-header offset +42) with a wildly OOB value.
        let centralSig: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        let victimCentral = try XCTUnwrap(nthOccurrence(of: centralSig, in: data, n: 2))
        let offsetField = data.startIndex + victimCentral + 42
        // Write 0xFFFFFFF0 little-endian: far past end of archive.
        data[offsetField + 0] = 0xF0
        data[offsetField + 1] = 0xFF
        data[offsetField + 2] = 0xFF
        data[offsetField + 3] = 0xFF

        let archive = try ZipArchive(data: data)

        // All three still listed.
        XCTAssertEqual(archive.entries.map(\.path), ["g1.txt", "victim.txt", "g2.txt"])
        // Bogus offset: extract returns nil, no crash.
        XCTAssertNil(archive.extract("victim.txt"))
        // Neighbours unaffected.
        XCTAssertEqual(archive.extract("g1.txt"), good1)
        XCTAssertEqual(archive.extract("g2.txt"), good2)
    }

    // MARK: - Gap 6: truncated archive degrades gracefully (no crash/trap)

    /// An archive whose tail (central directory + EOCD) has been chopped off.
    /// Construction should throw `.notAZipArchive` rather than crash.
    func testTruncatedArchiveMissingEOCDThrowsGracefully() throws {
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "one.txt", payload: Data("payload one".utf8), method: .stored),
            .init(path: "two.txt", payload: Data("payload two".utf8), method: .deflate),
        ]
        let full = ZipFixtureBuilder.build(entries: inputs)
        // Keep only the first third — well short of the central directory/EOCD.
        let truncated = full.prefix(full.count / 3)

        XCTAssertThrowsError(try ZipArchive(data: Data(truncated))) { error in
            XCTAssertEqual(error as? ZipError, .notAZipArchive)
        }
    }

    /// EOCD is intact but the central-directory body is truncated mid-record.
    /// The reader must not crash: it should yield whatever parsed cleanly and
    /// extract surviving entries; missing/cut entries simply extract to nil.
    func testTruncatedCentralDirectoryDoesNotCrash() throws {
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "alpha.txt", payload: Data("alpha".utf8), method: .stored),
            .init(path: "bravo.txt", payload: Data("bravo".utf8), method: .stored),
        ]
        let full = ZipFixtureBuilder.build(entries: inputs)

        // Locate the EOCD (last 22 bytes, no comment) and the central-dir offset
        // it advertises; then remove ~12 bytes from the middle of the central
        // directory while keeping the EOCD so the scan still finds it. To stay
        // robust we instead drop bytes just before the EOCD record.
        let eocdSize = 22
        let cdEnd = full.count - eocdSize
        // Remove a chunk near the end of the central directory body.
        let cutStart = max(0, cdEnd - 10)
        var damaged = Data()
        damaged.append(full.prefix(cutStart))
        damaged.append(full.suffix(eocdSize)) // re-attach EOCD

        // Whatever happens, opening + extracting must not trap.
        if let archive = try? ZipArchive(data: damaged) {
            _ = archive.entries
            _ = archive.extract("alpha.txt")
            _ = archive.extract("bravo.txt")
        }
        // Reaching here without a crash is the assertion.
        XCTAssertTrue(true)
    }

    // MARK: - Gap 7: stored entry whose declared size disagrees with data

    /// A stored entry whose central-directory uncompressed size is LARGER than
    /// the bytes actually present. The size/CRC guard in extract must reject it
    /// (return nil) rather than returning truncated/garbage bytes.
    func testStoredEntryWithOverstatedSizeReturnsNil() throws {
        let payload = Data("twelve bytes".utf8) // 12 bytes
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "size.txt", payload: payload, method: .stored),
        ]
        var data = ZipFixtureBuilder.build(entries: inputs)

        // Overstate the uncompressed size in the central-directory record so it
        // disagrees with the stored bytes. Central uncompressed-size lives at
        // central-header offset +24 (4 bytes, LE).
        let centralSig: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        let central = try XCTUnwrap(nthOccurrence(of: centralSig, in: data, n: 1))
        let sizeField = data.startIndex + central + 24
        let overstated: UInt32 = 9999
        data[sizeField + 0] = UInt8(overstated & 0xFF)
        data[sizeField + 1] = UInt8((overstated >> 8) & 0xFF)
        data[sizeField + 2] = UInt8((overstated >> 16) & 0xFF)
        data[sizeField + 3] = UInt8((overstated >> 24) & 0xFF)

        let archive = try ZipArchive(data: data)
        // Declared 9999 bytes but only 12 present and CRC is for 12 bytes:
        // extract must return nil, never partial/garbage bytes.
        XCTAssertNil(archive.extract("size.txt"))
    }

    // MARK: - Helpers

    /// Returns the byte offset (relative to data.startIndex) of the `n`-th
    /// (1-based) occurrence of `needle` in `haystack`, or nil if not found.
    private func nthOccurrence(of needle: [UInt8], in haystack: Data, n: Int) -> Int? {
        guard n >= 1, !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let bytes = [UInt8](haystack)
        var found = 0
        var i = 0
        let last = bytes.count - needle.count
        while i <= last {
            if Array(bytes[i..<(i + needle.count)]) == needle {
                found += 1
                if found == n { return i }
                i += needle.count
            } else {
                i += 1
            }
        }
        return nil
    }
}
