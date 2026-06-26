import Foundation
import XCTest
@testable import PlayerCore

// MARK: - SeekMathTests

/// Unit tests for `SeekMath`, the pure fraction <-> seek-time mapping the
/// default-skin progress bar drives its click/drag seek through. The bar itself
/// (a SwiftUI `DragGesture`) cannot be exercised headlessly, so every guard the
/// gesture relies on is pinned here on the pure core instead.
final class SeekMathTests: XCTestCase {

    private let duration: TimeInterval = 120

    // MARK: - time(forFraction:duration:) — the seek mapping

    func testFractionZeroMapsToStart() {
        XCTAssertEqual(SeekMath.time(forFraction: 0, duration: duration), 0)
    }

    func testFractionOneMapsToDuration() throws {
        XCTAssertEqual(try XCTUnwrap(SeekMath.time(forFraction: 1, duration: duration)), 120, accuracy: 1e-9)
    }

    func testFractionHalfMapsToHalfDuration() throws {
        XCTAssertEqual(try XCTUnwrap(SeekMath.time(forFraction: 0.5, duration: duration)), 60, accuracy: 1e-9)
    }

    func testFractionBelowZeroClampsToStart() {
        XCTAssertEqual(SeekMath.time(forFraction: -0.5, duration: duration), 0)
    }

    func testFractionAboveOneClampsToDuration() throws {
        XCTAssertEqual(try XCTUnwrap(SeekMath.time(forFraction: 1.7, duration: duration)), 120, accuracy: 1e-9)
    }

    func testZeroDurationIsNotSeekable() {
        XCTAssertNil(SeekMath.time(forFraction: 0.5, duration: 0))
    }

    func testNegativeDurationIsNotSeekable() {
        XCTAssertNil(SeekMath.time(forFraction: 0.5, duration: -10))
    }

    func testNaNDurationIsNotSeekable() {
        XCTAssertNil(SeekMath.time(forFraction: 0.5, duration: .nan))
    }

    func testInfiniteDurationIsNotSeekable() {
        XCTAssertNil(SeekMath.time(forFraction: 0.5, duration: .infinity))
    }

    func testNaNFractionNeverLeaksIntoSeek() {
        // A non-finite fraction is treated as 0 (start), never NaN/inf.
        let time = SeekMath.time(forFraction: .nan, duration: duration)
        XCTAssertEqual(time, 0)
    }

    func testSeekTimeIsAlwaysFiniteWithinBounds() {
        for raw in [-1.0, 0.0, 0.33, 0.5, 0.99, 1.0, 2.0, .infinity, -.infinity, .nan] {
            guard let t = SeekMath.time(forFraction: raw, duration: duration) else {
                XCTFail("Seekable duration should always return a time for fraction \(raw)")
                continue
            }
            XCTAssertTrue(t.isFinite, "Seek time must be finite for fraction \(raw)")
            XCTAssertGreaterThanOrEqual(t, 0)
            XCTAssertLessThanOrEqual(t, duration)
        }
    }

    // MARK: - time(forX:width:duration:) — the x/width convenience

    func testXWidthMapsToFractionalTime() throws {
        XCTAssertEqual(try XCTUnwrap(SeekMath.time(forX: 75, width: 300, duration: duration)), 30, accuracy: 1e-9)
    }

    func testXBeyondWidthClampsToDuration() throws {
        XCTAssertEqual(try XCTUnwrap(SeekMath.time(forX: 400, width: 300, duration: duration)), 120, accuracy: 1e-9)
    }

    func testNegativeXClampsToStart() {
        XCTAssertEqual(SeekMath.time(forX: -20, width: 300, duration: duration), 0)
    }

    func testZeroWidthMapsToStart() {
        // A degenerate (un-laid-out) bar width reads as fraction 0, not a divide.
        XCTAssertEqual(SeekMath.time(forX: 50, width: 0, duration: duration), 0)
    }

    func testZeroWidthWithZeroDurationIsNotSeekable() {
        XCTAssertNil(SeekMath.time(forX: 50, width: 0, duration: 0))
    }

    // MARK: - fraction(currentTime:duration:) — the display mapping

    func testDisplayFractionIsTimeOverDuration() {
        XCTAssertEqual(SeekMath.fraction(currentTime: 30, duration: 120), 0.25, accuracy: 1e-9)
    }

    func testDisplayFractionClampsPastTheEnd() {
        XCTAssertEqual(SeekMath.fraction(currentTime: 200, duration: 120), 1)
    }

    func testDisplayFractionClampsBelowZero() {
        XCTAssertEqual(SeekMath.fraction(currentTime: -10, duration: 120), 0)
    }

    func testDisplayFractionZeroDurationIsZero() {
        XCTAssertEqual(SeekMath.fraction(currentTime: 30, duration: 0), 0)
    }

    func testDisplayFractionNaNDurationIsZero() {
        XCTAssertEqual(SeekMath.fraction(currentTime: 30, duration: .nan), 0)
    }

    func testDisplayFractionInfiniteDurationIsZero() {
        XCTAssertEqual(SeekMath.fraction(currentTime: 30, duration: .infinity), 0)
    }

    func testDisplayFractionNaNCurrentTimeIsZero() {
        XCTAssertEqual(SeekMath.fraction(currentTime: .nan, duration: 120), 0)
    }

    func testDisplayFractionIsAlwaysFiniteInUnitRange() {
        for time in [-5.0, 0.0, 60.0, 120.0, 999.0, .infinity, -.infinity, .nan] {
            let f = SeekMath.fraction(currentTime: time, duration: 120)
            XCTAssertTrue(f.isFinite, "Display fraction must be finite for time \(time)")
            XCTAssertGreaterThanOrEqual(f, 0)
            XCTAssertLessThanOrEqual(f, 1)
        }
    }

    // MARK: - round-trip

    func testFractionRoundTripsThroughTime() {
        // Display fraction -> seek time -> display fraction is the identity for
        // an in-range fraction.
        let f0 = 0.4
        guard let t = SeekMath.time(forFraction: f0, duration: 120) else {
            return XCTFail("expected a seekable time")
        }
        XCTAssertEqual(SeekMath.fraction(currentTime: t, duration: 120), f0, accuracy: 1e-9)
    }
}
