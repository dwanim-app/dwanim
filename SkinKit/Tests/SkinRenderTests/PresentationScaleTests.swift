import Foundation
import XCTest
@testable import SkinRender

/// Exercises the pure `PresentationScale.bitmapScale(forPresentationScale:)`
/// derivation — the one place the app's fractional points-per-skin-pixel
/// presentation scale becomes the INTEGER nearest-neighbor factor the composed
/// bitmap is rendered at. No graphics framework is touched.
final class PresentationScaleTests: XCTestCase {

    // MARK: - Integer scales map to themselves

    /// An integer presentation scale keeps bitmap == presentation — the
    /// historical behavior the harness's integer `--scale` path relies on for
    /// byte-identical snapshots.
    func testIntegerPresentationScalesMapToThemselves() {
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 1), 1)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 2), 2)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 3), 3)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 16), 16)
    }

    // MARK: - Fractional scales double to the 2x-backing device factor

    /// The app's 1.5 points-per-skin-pixel derives the integer 3 — on a 2x
    /// (Retina) backing, 1.5 points is exactly 3 device pixels, so the 3x bitmap
    /// draws as a 1:1 device-pixel copy.
    func testOnePointFiveDerivesThree() {
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 1.5), 3)
    }

    /// Other half-integer scales follow the same doubling (2.5 -> 5): fractional
    /// point sizes that are whole in 2x device pixels stay integer factors.
    func testOtherHalfIntegerScalesDouble() {
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 0.5), 1)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 2.5), 5)
    }

    // MARK: - Degenerate input yields 1 (never traps)

    /// A non-finite / zero / negative scale yields the sane default 1, matching
    /// the project's finite-guard convention (`Int(NaN.rounded())` would trap).
    func testDegenerateScalesYieldOne() {
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: 0), 1)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: -1.5), 1)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: .nan), 1)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: .infinity), 1)
        XCTAssertEqual(PresentationScale.bitmapScale(forPresentationScale: -.infinity), 1)
    }

    // MARK: - Window-size arithmetic at 1.5 (documentation-as-test)

    /// The classic 275x116 main window at the app's 1.5 presentation scale is a
    /// 412.5 x 174 pt window backed by an 825x348 px (3x) bitmap — and on a 2x
    /// backing, points * backingScale == bitmap pixels exactly (the crispness
    /// invariant the fractional scale relies on).
    func testPointsTimesBackingScaleEqualsBitmapPixelsAtOnePointFive() {
        let scale = 1.5
        let bitmap = PresentationScale.bitmapScale(forPresentationScale: scale)
        let backing = 2.0

        let pointWidth = 275 * scale    // 412.5
        let pointHeight = 116 * scale   // 174.0
        XCTAssertEqual(pointWidth, 412.5, accuracy: 1e-9)
        XCTAssertEqual(pointHeight, 174.0, accuracy: 1e-9)

        XCTAssertEqual(pointWidth * backing, Double(275 * bitmap), accuracy: 1e-9)
        XCTAssertEqual(pointHeight * backing, Double(116 * bitmap), accuracy: 1e-9)
    }
}
