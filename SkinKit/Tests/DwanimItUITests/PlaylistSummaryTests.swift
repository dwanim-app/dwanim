import XCTest

@testable import DwanimItUI

// MARK: - PlaylistSummaryTests

/// Tests for `PlaylistSummary.text(songCount:totalSeconds:)`, the pure footer-copy
/// seam that fixes the "1 songs, 1 minutes" grammar bug (E2). English pluralization:
/// exactly `1` is singular ("1 song" / "1 minute"), everything else (including `0`)
/// is plural. Minutes are the design's `round(totalSeconds / 60)` with NO hour
/// rollover — the handoff footer format is literally "N songs, M minutes", so a
/// two-hour library reads "120 minutes", not "2 hours". Every case is in-memory
/// (no View), so the copy is unit-testable in isolation.
final class PlaylistSummaryTests: XCTestCase {

    // MARK: Singular (the E2 bug)

    func testOneSongOneMinuteIsSingular() {
        // The exact bug: one 60-second track used to read "1 songs, 1 minutes".
        XCTAssertEqual(PlaylistSummary.text(songCount: 1, totalSeconds: 60), "1 song, 1 minute")
    }

    func testOneSongPluralMinutes() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 1, totalSeconds: 180), "1 song, 3 minutes")
    }

    func testPluralSongsOneMinute() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 2, totalSeconds: 60), "2 songs, 1 minute")
    }

    // MARK: Zero (plural in English)

    func testZeroSongsZeroMinutes() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 0, totalSeconds: 0), "0 songs, 0 minutes")
    }

    // MARK: N songs / M minutes

    func testManySongsManyMinutes() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 3, totalSeconds: 300), "3 songs, 5 minutes")
    }

    func testMinutesRoundToNearest() {
        // 150 s → 2.5 min → rounds to 3 (round-half-away-from-zero, matching the
        // prototype's Math.round).
        XCTAssertEqual(PlaylistSummary.text(songCount: 4, totalSeconds: 150), "4 songs, 3 minutes")
    }

    // MARK: No hour rollover — minutes only, as the handoff specifies

    func testLargeLibraryStaysInMinutes() {
        // Two hours of audio is "120 minutes", not "2 hours" — the footer format is
        // minutes-only by design.
        XCTAssertEqual(PlaylistSummary.text(songCount: 40, totalSeconds: 7200), "40 songs, 120 minutes")
    }

    func testSixtyOneMinutesStaysMinutes() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 12, totalSeconds: 3660), "12 songs, 61 minutes")
    }

    // MARK: Guards

    func testNegativeTotalClampsToZeroMinutes() {
        // A stray negative duration must not produce "-1 minutes".
        XCTAssertEqual(PlaylistSummary.text(songCount: 1, totalSeconds: -30), "1 song, 0 minutes")
    }

    func testSubMinuteRoundsDownToZero() {
        // 20 s → 0.33 min → rounds to 0 → plural "0 minutes".
        XCTAssertEqual(PlaylistSummary.text(songCount: 1, totalSeconds: 20), "1 song, 0 minutes")
    }
}
