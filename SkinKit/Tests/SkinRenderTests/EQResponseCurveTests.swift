import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// TDD coverage for `EQResponseCurve` — the PURE helper that maps the ten EQ band
/// gains to a polyline of per-column y positions across `EQWindowLayout.graphFrame`.
/// It is graphics-framework-free and `PlayerCore`-free (raw `[Double]` gains in,
/// `[Int]` window-space y out), the same clean seam the composer uses.
///
/// Conventions mirrored from `EQWindowLayout.thumbTopY`: higher gain ⇒ smaller y
/// (higher on screen). +12 dB pins the curve to the graph's TOP row, -12 dB to its
/// BOTTOM row, 0 dB to the centre. The returned array has exactly
/// `graphFrame.width` entries, one per x column in
/// `[graphFrame.x, graphFrame.x + graphFrame.width)`.
final class EQResponseCurveTests: XCTestCase {

    private let frame = EQWindowLayout.graphFrame

    /// Top / centre / bottom graph rows in WINDOW space, from the layout's frame.
    private var topY: Int { frame.y }
    private var bottomY: Int { frame.y + frame.height - 1 }
    private var centerY: Int { frame.y + (frame.height - 1) / 2 }

    // MARK: - 1. Output shape

    /// The curve has exactly one y per graph column.
    func testReturnsOneYPerGraphColumn() {
        let ys = EQResponseCurve.yPositions(forBandGains: [Double](repeating: 0, count: 10))
        XCTAssertEqual(ys.count, frame.width, "one y per x in [x, x+width)")
    }

    // MARK: - 2. Flat -> centred horizontal line

    /// All bands at 0 dB ⇒ every column sits on the graph centre row (a flat line).
    func testFlatGainsProduceACentredHorizontalLine() {
        let ys = EQResponseCurve.yPositions(forBandGains: [Double](repeating: 0, count: 10))
        for (column, y) in ys.enumerated() {
            XCTAssertEqual(y, centerY, "column \(column) of a flat curve is the centre row")
        }
    }

    // MARK: - 3. Clamp to the graph ends

    /// +12 dB everywhere pins the whole line to the TOP row; -12 dB to the BOTTOM
    /// row. Higher gain ⇒ smaller y.
    func testFullBoostAndFullCutClampToTheGraphEnds() {
        let boosted = EQResponseCurve.yPositions(forBandGains: [Double](repeating: 12, count: 10))
        for y in boosted { XCTAssertEqual(y, topY, "+12 dB pins to the top row") }

        let cut = EQResponseCurve.yPositions(forBandGains: [Double](repeating: -12, count: 10))
        for y in cut { XCTAssertEqual(y, bottomY, "-12 dB pins to the bottom row") }

        // Out-of-range gains clamp to the same ends (never off-graph).
        let over = EQResponseCurve.yPositions(forBandGains: [Double](repeating: 99, count: 10))
        for y in over { XCTAssertEqual(y, topY, "over-boost clamps to the top row") }
        let under = EQResponseCurve.yPositions(forBandGains: [Double](repeating: -99, count: 10))
        for y in under { XCTAssertEqual(y, bottomY, "over-cut clamps to the bottom row") }
    }

    // MARK: - 4. At a band's column, the curve matches that band's gain

    /// The first band maps to the LEFT edge of the graph and the last band to the
    /// RIGHT edge. At those endpoint columns the curve y equals the y that band's
    /// gain maps to (the same +12→top / -12→bottom scaling).
    func testEndpointColumnsMatchTheirBandGains() {
        var bands = [Double](repeating: 0, count: 10)
        bands[0] = 12     // first band: full boost -> top at the left edge
        bands[9] = -12    // last band: full cut -> bottom at the right edge
        let ys = EQResponseCurve.yPositions(forBandGains: bands)

        XCTAssertEqual(ys.first, topY, "left edge column tracks band 0 (+12 -> top)")
        XCTAssertEqual(ys.last, bottomY, "right edge column tracks band 9 (-12 -> bottom)")
    }

    /// Every band's mapped column carries that band's gain-derived y. Uses distinct
    /// gains so the per-band landing is checkable, and asks the helper itself where
    /// each band column lands so the test pins behaviour, not an arithmetic guess.
    func testEachBandColumnMatchesItsGain() {
        let bands: [Double] = [12, 9, 6, 3, 0, -3, -6, -9, -12, 0]
        let ys = EQResponseCurve.yPositions(forBandGains: bands)
        for index in 0..<10 {
            let column = EQResponseCurve.graphColumn(forBandIndex: index)
            XCTAssertEqual(
                ys[column], EQResponseCurve.graphY(forGain: bands[index]),
                "band \(index) column \(column) must equal its gain's graph y")
        }
    }

    // MARK: - 5. Monotonic interpolation between two bands

    /// Between two adjacent bands the curve interpolates MONOTONICALLY. With band 0
    /// at +12 (top) and band 1 at -12 (bottom) and all higher bands at -12, the y
    /// values from band 0's column to band 1's column never DECREASE (they slope
    /// down the screen: top -> bottom, i.e. y strictly non-decreasing).
    func testInterpolationBetweenTwoBandsIsMonotonic() {
        var bands = [Double](repeating: -12, count: 10)
        bands[0] = 12   // top at the left
        // band 1..9 = -12 (bottom)
        let ys = EQResponseCurve.yPositions(forBandGains: bands)

        let c0 = EQResponseCurve.graphColumn(forBandIndex: 0)
        let c1 = EQResponseCurve.graphColumn(forBandIndex: 1)
        XCTAssertLessThan(c0, c1, "band 0 column is left of band 1 column")

        // Walk the span between the two band columns; y must be non-decreasing
        // (sloping from the top row down to the bottom row).
        for column in (c0 + 1)...c1 {
            XCTAssertGreaterThanOrEqual(
                ys[column], ys[column - 1],
                "curve must descend monotonically from band 0 (top) to band 1 (bottom)")
        }
        // And it actually moves (not a flat clamp): the span end is strictly below
        // its start.
        XCTAssertGreaterThan(ys[c1], ys[c0], "the interpolated span spans top -> bottom")
    }

    /// A midpoint between two equal-magnitude opposite bands lands near the centre
    /// row: band 0 = +12 (top), band 1 = -12 (bottom) ⇒ the column halfway between
    /// their graph columns is within a pixel of the centre.
    func testMidpointBetweenOppositeBandsIsNearCentre() {
        var bands = [Double](repeating: 0, count: 10)
        bands[0] = 12
        bands[1] = -12
        let ys = EQResponseCurve.yPositions(forBandGains: bands)
        let c0 = EQResponseCurve.graphColumn(forBandIndex: 0)
        let c1 = EQResponseCurve.graphColumn(forBandIndex: 1)
        let mid = (c0 + c1) / 2
        XCTAssertLessThanOrEqual(
            abs(ys[mid] - centerY), 1,
            "the midpoint of a +12 -> -12 ramp is within a pixel of the graph centre")
    }

    // MARK: - 6. Bounds safety

    /// Every returned y stays inside the graph rows [topY, bottomY], even for
    /// extreme / non-finite gains — nothing the compositor plots can land off-graph.
    func testAllYsStayInsideTheGraphRowsForExtremeAndNonFiniteGains() {
        let bands: [Double] = [100, -100, .nan, .infinity, -.infinity, 12, -12, 0, 6, -6]
        let ys = EQResponseCurve.yPositions(forBandGains: bands)
        XCTAssertEqual(ys.count, frame.width)
        for (column, y) in ys.enumerated() {
            XCTAssertGreaterThanOrEqual(y, topY, "column \(column) y >= top row")
            XCTAssertLessThanOrEqual(y, bottomY, "column \(column) y <= bottom row")
        }
    }

    /// A NaN band is sanitised to flat (centre), matching `thumbTopY`'s NaN policy,
    /// so a single bad gain neither traps nor throws the curve off-graph.
    func testNaNBandSanitisesToCentre() {
        var bands = [Double](repeating: 0, count: 10)
        bands[5] = .nan
        let ys = EQResponseCurve.yPositions(forBandGains: bands)
        let c5 = EQResponseCurve.graphColumn(forBandIndex: 5)
        XCTAssertEqual(ys[c5], centerY, "a NaN band falls back to the centre row")
    }

    // MARK: - 7. Off-length band arrays tolerated

    /// Fewer than ten bands does not trap: the missing high bands are treated as
    /// flat (0 dB) so the curve still spans the whole graph width.
    func testShortBandArrayIsToleratedAndStillSpansTheGraph() {
        let ys = EQResponseCurve.yPositions(forBandGains: [12, 12, 12])
        XCTAssertEqual(ys.count, frame.width, "still one y per column with a short array")
        for (column, y) in ys.enumerated() {
            XCTAssertGreaterThanOrEqual(y, topY, "column \(column) in range")
            XCTAssertLessThanOrEqual(y, bottomY, "column \(column) in range")
        }
        // The first band column still tracks band 0 (+12 -> top).
        XCTAssertEqual(ys[EQResponseCurve.graphColumn(forBandIndex: 0)], topY)
    }

    /// More than ten bands ignores the extras (only the first ten shape the curve).
    func testLongBandArrayIgnoresExtras() {
        let ys = EQResponseCurve.yPositions(forBandGains: [Double](repeating: 0, count: 25))
        XCTAssertEqual(ys.count, frame.width)
        for y in ys { XCTAssertEqual(y, centerY, "extra bands beyond ten are ignored") }
    }

    /// An empty band array is tolerated (treated as all-flat): a centred line.
    func testEmptyBandArrayIsTreatedAsFlat() {
        let ys = EQResponseCurve.yPositions(forBandGains: [])
        XCTAssertEqual(ys.count, frame.width)
        for y in ys { XCTAssertEqual(y, centerY) }
    }

    // MARK: - 8. graphColumn / graphY building blocks

    /// `graphColumn` maps band 0 to the graph's left column and band 9 to its right
    /// column, monotonically increasing in between.
    func testGraphColumnSpansLeftToRightMonotonically() {
        XCTAssertEqual(EQResponseCurve.graphColumn(forBandIndex: 0), 0, "band 0 -> left column")
        XCTAssertEqual(
            EQResponseCurve.graphColumn(forBandIndex: 9), frame.width - 1,
            "band 9 -> right column")
        var previous = -1
        for index in 0..<10 {
            let column = EQResponseCurve.graphColumn(forBandIndex: index)
            XCTAssertGreaterThan(column, previous, "band columns strictly increase")
            previous = column
        }
    }

    /// `graphY` mirrors the slider convention: +12 -> top, -12 -> bottom, 0 ->
    /// centre, clamped, NaN -> centre.
    func testGraphYMapsGainToRowWithClampAndNaNPolicy() {
        XCTAssertEqual(EQResponseCurve.graphY(forGain: 12), topY)
        XCTAssertEqual(EQResponseCurve.graphY(forGain: -12), bottomY)
        XCTAssertEqual(EQResponseCurve.graphY(forGain: 0), centerY)
        XCTAssertEqual(EQResponseCurve.graphY(forGain: 999), topY, "over-boost clamps to top")
        XCTAssertEqual(EQResponseCurve.graphY(forGain: -999), bottomY, "over-cut clamps to bottom")
        XCTAssertEqual(EQResponseCurve.graphY(forGain: .nan), centerY, "NaN -> centre")
    }
}
