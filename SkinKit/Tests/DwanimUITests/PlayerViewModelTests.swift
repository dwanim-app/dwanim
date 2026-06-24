import XCTest
@testable import DwanimUI

// MARK: - PlayerViewModelTests

/// Unit tests for `PlayerViewModel`'s pure logic: progress derivation and the
/// non-finite/negative sanitising the SwiftUI view relies on.
@MainActor
final class PlayerViewModelTests: XCTestCase {

    func testProgressIsZeroWhenDurationUnknown() {
        let model = PlayerViewModel(currentTime: 10, duration: 0)
        XCTAssertEqual(model.progress, 0)
    }

    func testProgressIsTheTimeFraction() {
        let model = PlayerViewModel(currentTime: 30, duration: 120)
        XCTAssertEqual(model.progress, 0.25, accuracy: 1e-9)
    }

    func testProgressClampsPastTheEnd() {
        let model = PlayerViewModel(currentTime: 200, duration: 100)
        XCTAssertEqual(model.progress, 1)
    }

    func testNonFiniteClockSanitisesToZero() {
        let model = PlayerViewModel()
        model.updateClock(currentTime: .nan, duration: .infinity)
        XCTAssertEqual(model.currentTime, 0)
        XCTAssertEqual(model.duration, 0)
        XCTAssertEqual(model.progress, 0)
    }

    func testNegativeTimeSanitisesToZero() {
        let model = PlayerViewModel()
        model.updateClock(currentTime: -5, duration: 100)
        XCTAssertEqual(model.currentTime, 0)
        XCTAssertEqual(model.progress, 0)
    }

    func testUpdateClockReplacesValues() {
        let model = PlayerViewModel(currentTime: 1, duration: 2)
        model.updateClock(currentTime: 50, duration: 100)
        XCTAssertEqual(model.currentTime, 50, accuracy: 1e-9)
        XCTAssertEqual(model.duration, 100, accuracy: 1e-9)
        XCTAssertEqual(model.progress, 0.5, accuracy: 1e-9)
    }
}
