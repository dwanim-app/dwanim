import XCTest

@testable import DwanimItUI

// MARK: - TrackTimeTests

/// Tests for `TrackTime.format(_:)`, the pure playlist Time-column seam. An
/// unknown length (nil / non-finite / ≤ 0) reads the em dash "—"; a known length
/// reads `m:ss`, or `h:mm:ss` once it reaches an hour. Every case is in-memory
/// (no View), so the formatting is unit-testable in isolation.
final class TrackTimeTests: XCTestCase {

    private let dash = "—"

    func testNilIsDash() {
        XCTAssertEqual(TrackTime.format(nil), dash)
    }

    func testZeroIsDash() {
        XCTAssertEqual(TrackTime.format(0), dash)
    }

    func testNegativeIsDash() {
        XCTAssertEqual(TrackTime.format(-12), dash)
    }

    func testNonFiniteIsDash() {
        XCTAssertEqual(TrackTime.format(.infinity), dash)
        XCTAssertEqual(TrackTime.format(.nan), dash)
    }

    func testSubMinuteZeroPadsSeconds() {
        XCTAssertEqual(TrackTime.format(7), "0:07")
    }

    func testExactMinute() {
        XCTAssertEqual(TrackTime.format(60), "1:00")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(TrackTime.format(187), "3:07")
    }

    func testFractionTruncatesTowardWholeSeconds() {
        XCTAssertEqual(TrackTime.format(187.9), "3:07")
    }

    func testExactHourUsesHMMSS() {
        XCTAssertEqual(TrackTime.format(3600), "1:00:00")
    }

    func testOverAnHourZeroPadsMinutesAndSeconds() {
        XCTAssertEqual(TrackTime.format(3725), "1:02:05")
    }

    func testMultipleHours() {
        // 2h 3m 4s.
        XCTAssertEqual(TrackTime.format(2 * 3600 + 3 * 60 + 4), "2:03:04")
    }
}
