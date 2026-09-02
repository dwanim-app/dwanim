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

    // MARK: - Window-size arithmetic at 1.0 (the app's native presentation scale)

    /// The app now presents the classic windows at an INTEGER 1.0 points-per-skin-
    /// pixel — the authentic 275x116-pt main window, backed by a 1x (native)
    /// bitmap. This is the crispness fix: unlike the fractional 1.5, an integer
    /// presentation scale yields a WHOLE device-pixel ratio on EVERY backing, so
    /// nearest-neighbor never produces the uneven 2/1/2/1 pixel widths that 1.5
    /// forced on a 1x display.
    func testPointsTimesBackingScaleEqualsBitmapPixelsAtOnePointZero() {
        let scale = 1.0
        let bitmap = PresentationScale.bitmapScale(forPresentationScale: scale)
        XCTAssertEqual(bitmap, 1, "1.0 must derive a native 1x bitmap")

        // Native 1:1 window points.
        let pointWidth = 275 * scale    // 275.0
        let pointHeight = 116 * scale   // 116.0
        XCTAssertEqual(pointWidth, 275.0, accuracy: 1e-9)
        XCTAssertEqual(pointHeight, 116.0, accuracy: 1e-9)

        // On BOTH a 1x and a 2x backing the device-pixel ratio is a WHOLE number
        // (points * backing / bitmap): 1.0 on 1x, 2.0 on 2x — never fractional.
        for backing in [1.0, 2.0] {
            let widthRatio = pointWidth * backing / Double(275 * bitmap)
            let heightRatio = pointHeight * backing / Double(116 * bitmap)
            XCTAssertEqual(widthRatio, backing, accuracy: 1e-9)
            XCTAssertEqual(heightRatio, backing, accuracy: 1e-9)
            XCTAssertEqual(widthRatio, widthRatio.rounded(), accuracy: 1e-9,
                           "device ratio must be integer at backing \(backing)")
        }
    }
}
