import Foundation
import XCTest
@testable import SkinKit

/// Independent QA gap-review tests for `SkinArchive`.
///
/// These probe behaviours that real-world classic skin archives exercise but
/// that the original acceptance suite did not cover. Some of these tests are
/// EXPECTED TO FAIL — a failure documents a concrete gap in the current
/// implementation rather than a defect in the test. Each test states, in its
/// comment, whether it is a confirmed-passing guard or a demonstrated gap.
///
/// All fixtures are synthetic (`ZipFixtureBuilder`); no real archive files are
/// used, and no brand names appear.
final class SkinArchiveReviewTests: XCTestCase {

    // MARK: - Gap 1: Windows backslash path separators  [MUST-FIX]

    /// Classic skins were authored on Windows; some archives store nested paths
    /// with a backslash separator (e.g. `baseskin\TITLEBAR.BMP`) instead of `/`.
    /// Basename extraction splits on `/` only, so the backslash form is treated
    /// as a single unsplit component and the file cannot be found by basename.
    ///
    /// EXPECTED TO FAIL against the current implementation — documents the gap.
    func testBackslashSeparatedNestedPathIsFoundByBasename() throws {
        let payload = Data("win-titlebar".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: #"baseskin\TITLEBAR.BMP"#, payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(
            archive.file(named: "titlebar.bmp"),
            payload,
            "Backslash-separated nested paths (Windows-authored archives) must " +
            "be matchable by basename."
        )
    }

    /// A deeper backslash path, mirroring the deeper `/` case already covered.
    /// EXPECTED TO FAIL against the current implementation.
    func testDeepBackslashSeparatedPathIsFoundByBasename() throws {
        let payload = Data("win-region".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: #"a\b\c\region.txt"#, payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "region.txt"), payload)
    }

    /// Mixed separators within a single path (`baseskin\sub/MAIN.BMP`) occur
    /// when an archive is repackaged across platforms. Basename should still be
    /// the trailing component regardless of which separators precede it.
    /// EXPECTED TO FAIL against the current implementation.
    func testMixedSeparatorPathIsFoundByBasename() throws {
        let payload = Data("mixed-sep".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: #"baseskin\sub/MAIN.BMP"#, payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "main.bmp"), payload)
    }

    // MARK: - Gap 2: corruption-aware candidate fallback (ADR-2)  [MUST-FIX]

    /// Two entries share a basename. The deterministically CHOSEN candidate
    /// (uppercase sorts first → `MAIN.BMP`) is corrupt (bad CRC), but the other
    /// same-named entry (`main.bmp`) would extract cleanly. ADR-2's spirit is
    /// "use whatever is readable", so a readable sibling should be returned
    /// rather than `nil`.
    ///
    /// EXPECTED TO FAIL against the current implementation: it picks one path
    /// up front and never falls back to a readable sibling.
    func testCorruptChosenCandidateFallsBackToReadableSibling() throws {
        let good = Data("good-main".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                // Chosen first (uppercase sorts before lowercase) but corrupt.
                .init(path: "MAIN.BMP", payload: Data("damaged".utf8), method: .stored, wrongCRC: true),
                // Readable same-basename sibling.
                .init(path: "main.bmp", payload: good, method: .stored),
            ])
        )

        XCTAssertEqual(
            archive.file(named: "main.bmp"),
            good,
            "When the chosen same-basename candidate is corrupt, a readable " +
            "sibling should still be returned (ADR-2 fault tolerance)."
        )
    }

    /// Same fallback requirement, but the shallower (preferred) candidate is the
    /// corrupt one and a readable copy lives one folder deeper. Depth precedence
    /// chooses the root entry; if it is corrupt, the nested readable copy should
    /// be used rather than returning `nil`.
    ///
    /// EXPECTED TO FAIL against the current implementation.
    func testCorruptShallowCandidateFallsBackToDeeperReadableCopy() throws {
        let good = Data("nested-good".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "cbuttons.bmp", payload: Data("damaged".utf8), method: .stored, wrongCRC: true),
                .init(path: "sub/cbuttons.bmp", payload: good, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "cbuttons.bmp"), good)
    }

    /// Order-independence of the fallback: reversing central-directory order of
    /// the two same-basename entries must not change the result.
    ///
    /// EXPECTED TO FAIL against the current implementation (paired with the
    /// fallback gap above).
    func testFallbackIsIndependentOfCentralDirectoryOrder() throws {
        let good = Data("good-main".utf8)

        let archiveA = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "MAIN.BMP", payload: Data("damaged".utf8), method: .stored, wrongCRC: true),
                .init(path: "main.bmp", payload: good, method: .stored),
            ])
        )
        let archiveB = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "main.bmp", payload: good, method: .stored),
                .init(path: "MAIN.BMP", payload: Data("damaged".utf8), method: .stored, wrongCRC: true),
            ])
        )

        XCTAssertEqual(archiveA.file(named: "main.bmp"), good)
        XCTAssertEqual(archiveB.file(named: "main.bmp"), good)
        XCTAssertEqual(archiveA.file(named: "main.bmp"), archiveB.file(named: "main.bmp"))
    }

    // MARK: - Gap 3: leading "./" and redundant components  [FYI — should pass]

    /// Some packers prefix entries with `./`. With `/`-splitting this yields a
    /// trailing component of `main.bmp`, so the basename match is expected to
    /// already work. This is a regression guard, expected to PASS.
    func testLeadingDotSlashIsMatchedByBasename() throws {
        let payload = Data("dot-slash".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "./main.bmp", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "main.bmp"), payload)
    }

    /// Redundant interior empty components (`baseskin//main.bmp`). Trailing
    /// component is still `main.bmp`. Regression guard, expected to PASS.
    func testRedundantSlashComponentsAreMatchedByBasename() throws {
        let payload = Data("double-slash".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "baseskin//main.bmp", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "main.bmp"), payload)
    }

    // MARK: - Gap 5: query that itself contains a path  [FYI — documents behaviour]

    /// A caller may pass a path-qualified query (`baseskin/main.bmp`). The
    /// query's basename (`main.bmp`) is what gets matched, so this is expected
    /// to PASS and pins the documented behaviour.
    func testPathQualifiedQueryMatchesByItsBasename() throws {
        let payload = Data("qualified-query".utf8)
        let archive = try SkinArchive(
            data: ZipFixtureBuilder.build(entries: [
                .init(path: "baseskin/main.bmp", payload: payload, method: .stored),
            ])
        )

        XCTAssertEqual(archive.file(named: "baseskin/main.bmp"), payload)
        XCTAssertEqual(archive.file(named: "main.bmp"), payload)
    }
}
