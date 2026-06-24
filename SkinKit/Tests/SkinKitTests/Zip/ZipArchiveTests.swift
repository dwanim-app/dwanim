import Foundation
import XCTest
@testable import SkinKit

/// Tests for the fault-tolerant ZIP reader. Each test maps to one acceptance
/// criterion; archives are assembled in-memory via `ZipFixtureBuilder`.
final class ZipArchiveTests: XCTestCase {

    // MARK: - Criterion 1: stored entries list in order

    func testStoredEntriesAreListedInCentralDirectoryOrder() throws {
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "a.txt", payload: Data("alpha".utf8), method: .stored),
            .init(path: "dir/b.txt", payload: Data("bravo".utf8), method: .stored),
            .init(path: "c.bin", payload: Data([0x00, 0x01, 0x02]), method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(archive.entries.map(\.path), ["a.txt", "dir/b.txt", "c.bin"])
        XCTAssertTrue(archive.entries.allSatisfy(\.isSupported))
    }

    // MARK: - Criterion 2: deflate entries list; extract round-trips

    func testDeflateEntriesAreListedAndExtractRoundTrips() throws {
        let payloadA = Data(repeating: 0x41, count: 1024)
        let payloadB = Data("the quick brown fox".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "big.dat", payload: payloadA, method: .deflate),
            .init(path: "phrase.txt", payload: payloadB, method: .deflate),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(archive.entries.map(\.path), ["big.dat", "phrase.txt"])
        XCTAssertEqual(archive.extract("big.dat"), payloadA)
        XCTAssertEqual(archive.extract("phrase.txt"), payloadB)
    }

    // MARK: - Criterion 3: extract a stored entry returns exact bytes

    func testExtractStoredEntryReturnsExactBytes() throws {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "raw.bin", payload: payload, method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(archive.extract("raw.bin"), payload)
    }

    // MARK: - Criterion 4: extract a deflate entry round-trips a known payload

    func testExtractDeflateEntryRoundTripsKnownPayload() throws {
        // Mixed, compressible-but-not-trivial payload.
        var payload = Data()
        for index in 0..<2000 { payload.append(UInt8(index % 251)) }
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "pattern.dat", payload: payload, method: .deflate),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(archive.extract("pattern.dat"), payload)
    }

    // MARK: - Criterion 5: one bad entry must not break the others

    func testCorruptEntryFailsWhileGoodEntriesStillExtract() throws {
        let good1 = Data("first good".utf8)
        let good2 = Data(repeating: 0x7E, count: 300)
        let bad = Data("this entry is broken".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "good1.txt", payload: good1, method: .stored),
            .init(path: "broken.txt", payload: bad, method: .deflate, corruptStream: true),
            .init(path: "good2.dat", payload: good2, method: .deflate),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        // All entries are still enumerated.
        XCTAssertEqual(archive.entries.map(\.path), ["good1.txt", "broken.txt", "good2.dat"])
        // Good entries extract correctly.
        XCTAssertEqual(archive.extract("good1.txt"), good1)
        XCTAssertEqual(archive.extract("good2.dat"), good2)
        // The corrupt entry returns nil without throwing.
        XCTAssertNil(archive.extract("broken.txt"))
    }

    func testWrongCRCEntryFailsWhileGoodEntriesStillExtract() throws {
        let good = Data("intact payload".utf8)
        let tampered = Data("crc will not match".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "ok.txt", payload: good, method: .stored),
            .init(path: "badcrc.txt", payload: tampered, method: .stored, wrongCRC: true),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertEqual(archive.extract("ok.txt"), good)
        XCTAssertNil(archive.extract("badcrc.txt"))
    }

    // MARK: - Criterion 6: missing path returns nil

    func testExtractNonExistentPathReturnsNil() throws {
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "present.txt", payload: Data("here".utf8), method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        XCTAssertNil(archive.extract("absent.txt"))
    }

    // MARK: - Criterion 7: unsupported method

    func testUnsupportedMethodIsListedButNotExtractable() throws {
        let payload = Data("compressed with an unknown method".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "weird.dat", payload: payload, method: .unsupported),
            .init(path: "normal.txt", payload: Data("fine".utf8), method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))

        let weird = try XCTUnwrap(archive.entries.first { $0.path == "weird.dat" })
        XCTAssertFalse(weird.isSupported)
        XCTAssertNil(archive.extract("weird.dat"))

        let normal = try XCTUnwrap(archive.entries.first { $0.path == "normal.txt" })
        XCTAssertTrue(normal.isSupported)
    }

    // MARK: - Criterion 8: non-zip data throws

    func testNonZipDataThrowsNotAZipArchive() {
        let randomBytes = Data((0..<512).map { _ in UInt8.random(in: 0...255) })
        XCTAssertThrowsError(try ZipArchive(data: randomBytes)) { error in
            XCTAssertEqual(error as? ZipError, .notAZipArchive)
        }
    }

    // MARK: - Criterion 9: EOCD with trailing comment is located

    func testEOCDWithTrailingCommentIsLocated() throws {
        let payload = Data("commented archive".utf8)
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "noted.txt", payload: payload, method: .deflate),
        ]
        let data = ZipFixtureBuilder.build(
            entries: inputs,
            comment: "this is a trailing archive comment with a fake PK marker"
        )
        let archive = try ZipArchive(data: data)

        XCTAssertEqual(archive.entries.map(\.path), ["noted.txt"])
        XCTAssertEqual(archive.extract("noted.txt"), payload)
    }

    // MARK: - Criterion 10: zero-entry archive

    func testZeroEntryArchiveParsesToEmptyEntries() throws {
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: []))
        XCTAssertTrue(archive.entries.isEmpty)
    }

    // MARK: - Extra edge cases

    func testEmptyDataThrowsNotAZipArchive() {
        XCTAssertThrowsError(try ZipArchive(data: Data())) { error in
            XCTAssertEqual(error as? ZipError, .notAZipArchive)
        }
    }

    func testExtractStoredEmptyPayloadReturnsEmptyData() throws {
        let inputs: [ZipFixtureBuilder.Entry] = [
            .init(path: "empty.txt", payload: Data(), method: .stored),
        ]
        let archive = try ZipArchive(data: ZipFixtureBuilder.build(entries: inputs))
        XCTAssertEqual(archive.extract("empty.txt"), Data())
    }
}

// MARK: - Production CRC-32 oracle test

/// Confirms the production CRC-32 agrees with the well-known check value for
/// the ASCII string "123456789" (0xCBF43926).
final class CRC32Tests: XCTestCase {
    func testKnownCheckValue() {
        let crc = CRC32.checksum(Data("123456789".utf8))
        XCTAssertEqual(crc, 0xCBF4_3926)
    }
}
