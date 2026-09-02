import Foundation
import XCTest
@testable import SkinKit

/// `SkinRegion.isEmpty` — the predicate every "is this window shaped?" decision
/// normalizes through. A polygon needs at least THREE vertices to enclose any
/// area; a region whose polygons all have fewer declares no usable shape.
final class SkinRegionTests: XCTestCase {

    private func polygon(_ vertices: [(Int, Int)]) -> SkinRegion.Polygon {
        SkinRegion.Polygon(points: vertices.map { SkinRegion.Point(x: $0.0, y: $0.1) })
    }

    func testNoPolygonsIsEmpty() {
        XCTAssertTrue(SkinRegion(polygons: []).isEmpty)
    }

    func testPolygonsWithFewerThanThreeVerticesAreEmpty() {
        XCTAssertTrue(SkinRegion(polygons: [polygon([])]).isEmpty, "0 vertices")
        XCTAssertTrue(SkinRegion(polygons: [polygon([(0, 0)])]).isEmpty, "1 vertex")
        XCTAssertTrue(SkinRegion(polygons: [polygon([(0, 0), (10, 10)])]).isEmpty, "2 vertices (a line)")
        XCTAssertTrue(
            SkinRegion(polygons: [polygon([(0, 0)]), polygon([(1, 1), (2, 2)])]).isEmpty,
            "several polygons, none with 3 vertices"
        )
    }

    func testThreeVerticesIsNotEmpty() {
        XCTAssertFalse(SkinRegion(polygons: [polygon([(0, 0), (10, 0), (5, 10)])]).isEmpty,
                       "exactly 3 vertices is the smallest fillable polygon")
    }

    func testOneFillablePolygonAmongDegenerateOnesIsNotEmpty() {
        let region = SkinRegion(polygons: [
            polygon([(0, 0), (1, 1)]),                  // degenerate
            polygon([(0, 0), (10, 0), (10, 10), (0, 10)]), // fillable
            polygon([])                                  // degenerate
        ])
        XCTAssertFalse(region.isEmpty)
    }
}
