import Foundation
import XCTest
@testable import SkinKit

/// Tests for `SkinArchive`, the canonical sprite/config lookup layer over
/// `ZipArchive`. Each test maps to one acceptance criterion; archives are
/// assembled in-memory via `ZipFixtureBuilder` — never from real skin files.
///
/// Documented same-depth collision tie-break: when two entries match at the
/// same depth, the one whose full stored path sorts first lexicographically
/// (Swift `String` `<`) wins. For criterion 7 (`cbuttons.bmp` + `CBUTTONS.BMP`
/// both at root), `"CBUTTONS.BMP"` sorts before `"cbuttons.bmp"` because
/// uppercase letters precede lowercase in Unicode scalar order, so the
/// uppercase entry is expected.
final class SkinArchiveTests: XCTestCase {

    // MARK: - Criterion 1: exact root match

    func testExactRootMatchReturnsBytes() throws {
        let payload = Data("root-main".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "main.bmp", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "main.bmp"), payload)
    }

    // MARK: - Criterion 2: case-insensitive entry name

    func testCaseInsensitiveEntryNameIsFound() throws {
        let upper = Data("UPPER".utf8)
        let mixed = Data("MIXED".utf8)

        let upperArchive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "MAIN.BMP", payload: upper, method: .stored),
            ])
        )
        XCTAssertEqual(upperArchive.file(named: "main.bmp"), upper)

        let mixedArchive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "Main.bmp", payload: mixed, method: .stored),
            ])
        )
        XCTAssertEqual(mixedArchive.file(named: "main.bmp"), mixed)
    }

    // MARK: - Criterion 3: case-insensitive query

    func testCaseInsensitiveQueryIsFound() throws {
        let payload = Data("query-case".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "main.bmp", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "MAIN.BMP"), payload)
    }

    // MARK: - Criterion 4: recursive match, one level deep

    func testRecursiveMatchOneLevelDeep() throws {
        let payload = Data("nested-titlebar".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "baseskin/TITLEBAR.BMP", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "titlebar.bmp"), payload)
    }

    // MARK: - Criterion 5: recursive match, deeper

    func testRecursiveMatchDeeper() throws {
        let payload = Data("deep-region".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "a/b/c/region.txt", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "region.txt"), payload)
    }

    // MARK: - Criterion 6: depth precedence (shallowest wins)

    func testShallowestPathWinsOverNested() throws {
        let root = Data("root-cbuttons".utf8)
        let nested = Data("nested-cbuttons".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "sub/cbuttons.bmp", payload: nested, method: .stored),
                .init(path: "cbuttons.bmp", payload: root, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "cbuttons.bmp"), root)
    }

    // MARK: - Criterion 7: same-depth collision is deterministic

    func testSameDepthCollisionIsDeterministic() throws {
        let lower = Data("lower".utf8)
        let upper = Data("upper".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "cbuttons.bmp", payload: lower, method: .stored),
                .init(path: "CBUTTONS.BMP", payload: upper, method: .stored),
            ])
        )

        // "CBUTTONS.BMP" sorts before "cbuttons.bmp" lexicographically, so the
        // uppercase entry is the documented, stable winner.
        let first = archive.file(named: "cbuttons.bmp")
        XCTAssertEqual(first, upper)
        // Stability: repeated calls return the identical choice.
        XCTAssertEqual(archive.file(named: "cbuttons.bmp"), first)
        XCTAssertEqual(archive.file(named: "cbuttons.bmp"), first)
    }

    // MARK: - Criterion 8: absent name → nil

    func testAbsentNameReturnsNil() throws {
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "main.bmp", payload: Data("present".utf8), method: .stored),
            ])
        )

        XCTAssertNil(archive.file(named: "missing.bmp"))
    }

    // MARK: - Criterion 9: corrupt matched entry → nil; sibling still works

    func testCorruptMatchReturnsNilWhileSiblingSucceeds() throws {
        let goodPayload = Data("good".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(
                    path: "cbuttons.bmp",
                    payload: Data("damaged".utf8),
                    method: .stored,
                    wrongCRC: true
                ),
                .init(path: "main.bmp", payload: goodPayload, method: .stored),
            ])
        )

        XCTAssertNil(archive.file(named: "cbuttons.bmp"))
        XCTAssertEqual(archive.file(named: "main.bmp"), goodPayload)
    }

    // MARK: - Criterion 10: text config found by the same mechanism

    func testTextConfigIsFound() throws {
        let payload = Data("0,0,0\n255,255,255\n".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "skin/VISCOLOR.TXT", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "viscolor.txt"), payload)
    }

    // MARK: - Criterion 11: directory entries are never returned

    func testDirectoryEntryIsNotReturnedAsFile() throws {
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "folder/", payload: Data(), method: .stored),
            ])
        )

        XCTAssertNil(archive.file(named: "folder"))
        XCTAssertNil(archive.file(named: "folder/"))
    }

    // MARK: - Passthrough: entryPaths mirrors stored order exactly

    func testEntryPathsPassThroughInStoredOrder() throws {
        let paths = ["main.bmp", "baseskin/TITLEBAR.BMP", "a/b/c/region.txt"]
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: paths.map {
                .init(path: $0, payload: Data($0.utf8), method: .stored)
            })
        )

        XCTAssertEqual(archive.entryPaths, paths)
    }
}
