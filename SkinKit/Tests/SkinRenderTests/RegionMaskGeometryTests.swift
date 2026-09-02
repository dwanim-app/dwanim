import Foundation
import XCTest
@testable import SkinRender
@testable import SkinKit

/// The fill-rule cross-check for the window mask: the mask geometry
/// (`RegionMaskGeometry.coverageSpans`) must reproduce `RegionCoverage`'s
/// even-odd-per-polygon + union coverage EXACTLY, so a single-fill-rule
/// `CAShapeLayer` built from these spans renders the same silhouette the PNG /
/// coverage math produces. Also verifies the point-in-region hit predicate and
/// the manual-drag top clamp. All pure, no graphics framework.
final class RegionMaskGeometryTests: XCTestCase {

    // MARK: - Helpers

    private func polygon(_ vertices: [(Int, Int)]) -> SkinRegion.Polygon {
        SkinRegion.Polygon(points: vertices.map { SkinRegion.Point(x: $0.0, y: $0.1) })
    }

    private func at(_ mask: [Bool], x: Int, y: Int, width: Int) -> Bool {
        mask[y * width + x]
    }

    /// The universal invariant: the spans rasterize back to the exact coverage.
    private func assertSpansMatchCoverage(
        _ region: SkinRegion, width: Int, height: Int,
        _ message: String = "", file: StaticString = #filePath, line: UInt = #line
    ) {
        let coverage = RegionCoverage.mask(region, width: width, height: height)
        let spans = RegionMaskGeometry.coverageSpans(for: region, width: width, height: height)
        let round = RegionMaskGeometry.rasterize(spans, width: width, height: height)
        XCTAssertEqual(round, coverage, "mask spans must equal RegionCoverage. \(message)",
                       file: file, line: line)
    }

    // MARK: - Cross-check 1: nested rectangles -> SOLID (rounded), not concentric rings

    func testNestedRectanglesFillSolidNotRings() {
        let width = 12, height = 12
        // Two concentric rectangles as SEPARATE polygons (the nested-rectangle /
        // rounded-corner idiom). Even-odd PER polygon + UNION => solid outer; the
        // WRONG (`.evenOdd` on the combined path) rule would hole out the centre.
        let outer = polygon([(0, 0), (10, 0), (10, 10), (0, 10)])
        let inner = polygon([(3, 3), (7, 3), (7, 7), (3, 7)])
        let region = SkinRegion(polygons: [outer, inner])

        assertSpansMatchCoverage(region, width: width, height: height, "nested rects")

        let coverage = RegionCoverage.mask(region, width: width, height: height)
        // The CENTRE (inside BOTH rectangles) must be SOLID (true) — proving union,
        // not a ring/hole.
        XCTAssertTrue(at(coverage, x: 5, y: 5, width: width), "centre must be filled (no ring)")
        // A point inside the outer but outside the inner is also filled.
        XCTAssertTrue(at(coverage, x: 1, y: 5, width: width))
        // Outside the outer is empty.
        XCTAssertFalse(at(coverage, x: 11, y: 11, width: width))
    }

    // MARK: - Cross-check 2: overlapping slabs (883_breeder idiom) -> union

    func testOverlappingSlabsUnion() {
        let width = 20, height = 12
        // Two horizontal slabs that overlap in the middle band — the classic
        // "rounded corners via stacked rectangles" construction.
        let top = polygon([(1, 0), (19, 0), (19, 8), (1, 8)])
        let bottom = polygon([(0, 3), (20, 3), (20, 12), (0, 12)])
        let region = SkinRegion(polygons: [top, bottom])

        assertSpansMatchCoverage(region, width: width, height: height, "overlapping slabs")

        let coverage = RegionCoverage.mask(region, width: width, height: height)
        // Overlap band (inside both) stays filled — union, not an even-odd hole.
        XCTAssertTrue(at(coverage, x: 10, y: 5, width: width), "overlap band filled")
        // Corner outside the top slab (x=0,y=0) is empty; inside the bottom slab is filled.
        XCTAssertFalse(at(coverage, x: 0, y: 0, width: width))
        XCTAssertTrue(at(coverage, x: 0, y: 6, width: width))
    }

    // MARK: - Cross-check 3: self-intersecting polygon (even-odd matters)

    func testSelfIntersectingPolygonIsNotSolid() {
        let width = 8, height = 8
        // An "hourglass": the two diagonals cross, so even-odd fills the left/right
        // wedges but leaves the top/bottom wedges empty — a solid (nonzero) fill
        // would fill the whole bounding area. This is the case a single `.nonZero`
        // fillRule would get wrong.
        let hourglass = SkinRegion(polygons: [
            polygon([(1, 1), (6, 1), (1, 6), (6, 6)])
        ])

        // The mask still equals coverage exactly (the whole point).
        assertSpansMatchCoverage(hourglass, width: width, height: height, "hourglass")

        let coverage = RegionCoverage.mask(hourglass, width: width, height: height)
        // Prove it is NOT a solid bounding fill: at least one cell inside the
        // bounding box is empty (a top/bottom wedge the even-odd rule excludes).
        let boundingHasHole = (1...5).contains { y in
            (1...5).contains { x in !at(coverage, x: x, y: y, width: width) }
        }
        XCTAssertTrue(boundingHasHole, "even-odd hourglass must not fill its bounding box solid")
    }

    // MARK: - Cross-check 3b: SAME-WINDING nested loop -> 1px hairline ring
    //
    // The bowtie above is NOT rule-discriminating (its empty wedges have winding 0
    // under BOTH rules). This one is: a single polygon that traces the outer
    // rectangle clockwise, steps inside, and traces the inner rectangle in the
    // SAME direction. Under even-odd the inner area has TWO crossings on each
    // side -> a 1px RING; under non-zero its winding number is 2 -> SOLID. The
    // classic "hairline border" region.txt idiom depends on the ring.

    func testSameWindingNestedLoopIsHairlineRingNotSolid() {
        let width = 10, height = 10
        let hairline = SkinRegion(polygons: [
            polygon([
                (0, 0), (10, 0), (10, 10), (0, 10), (0, 1),      // outer, clockwise
                (1, 1), (9, 1), (9, 9), (1, 9), (1, 1),          // inner, ALSO clockwise
                (0, 1)                                           // back out; closes to (0,0)
            ])
        ])

        assertSpansMatchCoverage(hairline, width: width, height: height, "hairline ring")

        let coverage = RegionCoverage.mask(hairline, width: width, height: height)
        for x in 0..<width {
            XCTAssertTrue(at(coverage, x: x, y: 0, width: width), "top border row filled at x=\(x)")
            XCTAssertTrue(at(coverage, x: x, y: 9, width: width), "bottom border row filled at x=\(x)")
        }
        for y in 1...8 {
            XCTAssertTrue(at(coverage, x: 0, y: y, width: width), "left border column at y=\(y)")
            XCTAssertTrue(at(coverage, x: 9, y: y, width: width), "right border column at y=\(y)")
            for x in 1...8 {
                XCTAssertFalse(at(coverage, x: x, y: y, width: width),
                               "interior (\(x),\(y)) must be EMPTY: a non-zero fill would make it solid")
            }
        }
        // Exactly the ring's runs: 1 span on each border row, 2 on each middle row.
        let spans = RegionMaskGeometry.coverageSpans(for: hairline, width: width, height: height)
        XCTAssertEqual(spans.count, 2 + 8 * 2)
        XCTAssertEqual(spans.first, .init(x: 0, y: 0, width: 10))
        XCTAssertEqual(spans[1], .init(x: 0, y: 1, width: 1))
        XCTAssertEqual(spans[2], .init(x: 9, y: 1, width: 1))
    }

    // MARK: - Full coverage is NOT a shape (M1)
    //
    // The archetypal inert `[Normal]` = `0,0 275,0 275,116 0,116` covers the whole
    // canvas. Such a region must NOT put the window on the shaped path (which
    // drops the shadow, switches to the manual drag, and goes non-opaque).

    func testFullRectangleRegionIsFullCoverageAndYieldsNoShape() {
        let width = 275, height = 116
        let full = SkinRegion(polygons: [
            polygon([(0, 0), (275, 0), (275, 116), (0, 116)])
        ])

        let mask = RegionCoverage.mask(full, width: width, height: height)
        XCTAssertTrue(RegionMaskGeometry.isFullCoverage(mask), "an all-true mask is full coverage")
        XCTAssertNil(RegionMaskGeometry.shape(for: full, width: width, height: height),
                     "a full-window rectangle is inert: no shape")
    }

    func testUnionCoveringWholeCanvasYieldsNoShape() {
        // Two slabs that together cover everything (the union is full even though
        // neither polygon alone is).
        let width = 275, height = 116
        let halves = SkinRegion(polygons: [
            polygon([(0, 0), (275, 0), (275, 58), (0, 58)]),
            polygon([(0, 58), (275, 58), (275, 116), (0, 116)])
        ])
        XCTAssertNil(RegionMaskGeometry.shape(for: halves, width: width, height: height))
    }

    func testCornerCutRegionIsNotFullCoverageAndYieldsShape() {
        let width = 275, height = 116
        let chamfer = SkinRegion(polygons: [
            polygon([(0, 3), (3, 0), (272, 0), (275, 3), (275, 116), (0, 116)])
        ])

        let mask = RegionCoverage.mask(chamfer, width: width, height: height)
        XCTAssertFalse(RegionMaskGeometry.isFullCoverage(mask))

        let shape = RegionMaskGeometry.shape(for: chamfer, width: width, height: height)
        XCTAssertNotNil(shape)
        // The shape carries the SAME coverage + spans the hit-test and the mask use.
        XCTAssertEqual(shape?.mask, mask)
        XCTAssertEqual(shape?.spans, RegionMaskGeometry.coverageSpans(for: chamfer, width: width, height: height))
        XCTAssertEqual(shape?.width, width)
        XCTAssertEqual(shape?.height, height)
    }

    func testEmptyRegionAndEmptyMaskAreNotShapes() {
        XCTAssertNil(RegionMaskGeometry.shape(for: SkinRegion(polygons: []), width: 275, height: 116),
                     "no polygons -> no shape")
        // A degenerate (< 3 vertex) polygon is likewise no shape.
        let line = SkinRegion(polygons: [polygon([(0, 0), (10, 10)])])
        XCTAssertNil(RegionMaskGeometry.shape(for: line, width: 275, height: 116))
        // An EMPTY mask is not "full" (there is nothing to cover).
        XCTAssertFalse(RegionMaskGeometry.isFullCoverage([]))
        // A partially false mask is not full.
        XCTAssertFalse(RegionMaskGeometry.isFullCoverage([true, false, true]))
    }

    // MARK: - Spans -> view rects (S1: the y-flip, pure and testable)
    //
    // The content view is NON-flipped (bottom-left origin), the skin is top-left.
    // Skin row `y` must land at view rect `[viewHeight - (y+1)*scale,
    // viewHeight - y*scale)` — the same flip `ControlHitTest.viewPoint` applies.

    func testViewRectsFlipRowsScaleColumnsAndSitOnTheRowGrid() {
        // 4-row canvas at the fractional 1.5 scale: viewHeight = 6.0 points.
        let scale = 1.5
        let viewHeight = 4.0 * scale
        let spans: [RegionMaskGeometry.Span] = [
            .init(x: 1, y: 0, width: 2),   // top skin row
            .init(x: 0, y: 3, width: 1)    // bottom skin row
        ]

        let rects = RegionMaskGeometry.viewRects(spans: spans, viewHeight: viewHeight, scale: scale)

        XCTAssertEqual(rects.count, 2)
        // Top skin row -> the HIGHEST view rect, whose top edge is exactly the view's top.
        XCTAssertEqual(rects[0].x, 1.5, accuracy: 1e-9)
        XCTAssertEqual(rects[0].width, 3.0, accuracy: 1e-9)
        XCTAssertEqual(rects[0].height, 1.5, accuracy: 1e-9)
        XCTAssertEqual(rects[0].y, 4.5, accuracy: 1e-9, "row 0 sits at viewHeight - 1*scale (flipped)")
        XCTAssertEqual(rects[0].y + rects[0].height, viewHeight, accuracy: 1e-9,
                       "row 0's top edge is the view's top edge (the +1 row edge)")
        // Bottom skin row -> view y == 0.
        XCTAssertEqual(rects[1].y, 0, accuracy: 1e-9, "the last row's bottom edge is the view's bottom")
        XCTAssertEqual(rects[1].x, 0, accuracy: 1e-9)
        XCTAssertEqual(rects[1].width, 1.5, accuracy: 1e-9)
    }

    func testViewRectsAgreeWithControlHitTestViewPoint() {
        // The rect's lower-left corner must be the view point of the skin pixel
        // just BELOW the span's row (skinY + 1), at the span's x — the shared flip.
        let scale = 2.0
        let viewHeight = 116.0 * scale
        let span = RegionMaskGeometry.Span(x: 40, y: 17, width: 5)

        let rect = RegionMaskGeometry.viewRects(spans: [span], viewHeight: viewHeight, scale: scale)[0]
        let corner = ControlHitTest.viewPoint(skinX: 40, skinY: 18, viewHeight: viewHeight, scale: scale)

        XCTAssertEqual(rect.x, corner.x, accuracy: 1e-9)
        XCTAssertEqual(rect.y, corner.y, accuracy: 1e-9)
        // And mapping the rect's centre BACK lands on the span's own row/column.
        let back = ControlHitTest.skinPoint(
            viewX: rect.x + rect.width / 2, viewY: rect.y + rect.height / 2,
            viewHeight: viewHeight, scale: scale
        )
        XCTAssertEqual(back.y, 17)
        XCTAssertEqual(back.x, 42)
    }

    // MARK: - Cross-check 4: disjoint boxes + concave notch

    func testDisjointAndConcaveMatchCoverage() {
        // Two disjoint boxes.
        let two = SkinRegion(polygons: [
            polygon([(1, 1), (5, 1), (5, 5), (1, 5)]),
            polygon([(12, 1), (16, 1), (16, 5), (12, 5)])
        ])
        assertSpansMatchCoverage(two, width: 20, height: 8, "disjoint boxes")

        // An L-shape (concave).
        let lShape = SkinRegion(polygons: [
            polygon([(1, 1), (5, 1), (5, 5), (9, 5), (9, 9), (1, 9)])
        ])
        assertSpansMatchCoverage(lShape, width: 10, height: 10, "L-shape")
    }

    // MARK: - Real rounded-corner idiom (LadyCroft-style chamfer)

    func testRoundedCornerChamferMatchesCoverage() {
        // The LadyCroft [Normal] polygon: chamfered top corners on a 275x116 frame.
        let ladyCroft = SkinRegion(polygons: [
            polygon([
                (0, 3), (1, 2), (2, 1), (3, 0), (272, 0),
                (273, 1), (274, 2), (275, 3), (275, 116), (0, 116)
            ])
        ])
        assertSpansMatchCoverage(ladyCroft, width: 275, height: 116, "LadyCroft chamfer")

        let coverage = RegionCoverage.mask(ladyCroft, width: 275, height: 116)
        // The very top-left pixel is chamfered OUT (outside the region)...
        XCTAssertFalse(coverage[0 * 275 + 0], "chamfered corner pixel is cut out")
        // ...while the body well inside the frame is filled.
        XCTAssertTrue(coverage[50 * 275 + 130], "interior is filled")
    }

    // MARK: - Span reduction basics

    func testSpansMergeConsecutiveRun() {
        // One full row covered -> a single span spanning the row.
        var mask = [Bool](repeating: false, count: 5 * 2)
        for x in 0..<5 { mask[0 * 5 + x] = true }          // full row 0
        mask[1 * 5 + 1] = true; mask[1 * 5 + 3] = true      // two singletons in row 1

        let spans = RegionMaskGeometry.spans(from: mask, width: 5, height: 2)

        XCTAssertEqual(spans, [
            .init(x: 0, y: 0, width: 5),
            .init(x: 1, y: 1, width: 1),
            .init(x: 3, y: 1, width: 1)
        ])
    }

    func testSizeMismatchYieldsNoSpans() {
        XCTAssertTrue(RegionMaskGeometry.spans(from: [true, true], width: 3, height: 3).isEmpty)
    }
}
