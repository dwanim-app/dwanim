import XCTest

@testable import DwanimItUI

// MARK: - TrackTitleTests

/// Tests for `TrackTitle.split(_:)`, the single pure `"Artist - Title"` seam shared
/// by the default face's now-playing line and the playlist rows. The split is on the
/// FIRST `" - "`; both halves non-empty → `(title, artist)`, else `(whole, nil)`.
/// Every case is in-memory (no View), so the split is unit-testable in isolation.
final class TrackTitleTests: XCTestCase {

    func testBasicSplitOnFirstDash() {
        let parts = TrackTitle.split("Daft Punk - Aerodynamic")
        XCTAssertEqual(parts.title, "Aerodynamic")
        XCTAssertEqual(parts.artist, "Daft Punk")
    }

    func testNoDashIsWholeTitleNoArtist() {
        let parts = TrackTitle.split("Aerodynamic")
        XCTAssertEqual(parts.title, "Aerodynamic")
        XCTAssertNil(parts.artist)
    }

    func testLeadingDashEmptyArtistFallsBackToWhole() {
        // The artist half is empty → the whole string is the title, no artist.
        let parts = TrackTitle.split(" - Aerodynamic")
        XCTAssertEqual(parts.title, " - Aerodynamic")
        XCTAssertNil(parts.artist)
    }

    func testTrailingDashEmptyTitleFallsBackToWhole() {
        // The title half is empty → the whole string is the title, no artist.
        let parts = TrackTitle.split("Daft Punk - ")
        XCTAssertEqual(parts.title, "Daft Punk - ")
        XCTAssertNil(parts.artist)
    }

    func testMultipleDashesSplitOnFirstOnly() {
        // Only the FIRST " - " separates; later ones stay in the title half.
        let parts = TrackTitle.split("A - B - C")
        XCTAssertEqual(parts.artist, "A")
        XCTAssertEqual(parts.title, "B - C")
    }

    func testEmptyStringIsWholeTitleNoArtist() {
        let parts = TrackTitle.split("")
        XCTAssertEqual(parts.title, "")
        XCTAssertNil(parts.artist)
    }
}
