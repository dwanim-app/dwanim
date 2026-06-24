import Foundation
import XCTest
@testable import SkinKit

/// Tests for the fault-tolerant parser of `region.txt` from the classic `.wsz`
/// skin format: an INI-like file whose `[Normal]` section declares one or more
/// polygons via `NumPoints` (per-polygon vertex counts) and a flat `PointList`
/// of `x,y` pairs. The parser never throws; missing or short data yields a
/// partial or empty result.
final class RegionParserTests: XCTestCase {

    // MARK: - Criterion (a): one polygon, 4 points, correct coords

    func testParsesSinglePolygon() {
        let text = """
        [Normal]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1)
        XCTAssertEqual(region.polygons.first?.points, [
            .init(x: 0, y: 0),
            .init(x: 275, y: 0),
            .init(x: 275, y: 116),
            .init(x: 0, y: 116)
        ])
    }

    // MARK: - Criterion (b): two polygons (NumPoints=4,3) split correctly

    func testSplitsMultiplePolygonsByNumPoints() {
        let text = """
        [Normal]
        NumPoints=4,3
        PointList=0,0,10,0,10,10,0,10, 20,20,30,20,25,30
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 2)
        XCTAssertEqual(region.polygons[0].points, [
            .init(x: 0, y: 0), .init(x: 10, y: 0),
            .init(x: 10, y: 10), .init(x: 0, y: 10)
        ])
        XCTAssertEqual(region.polygons[1].points, [
            .init(x: 20, y: 20), .init(x: 30, y: 20), .init(x: 25, y: 30)
        ])
    }

    // MARK: - Criterion (c): missing [Normal] -> empty polygons

    func testMissingNormalSectionYieldsEmpty() {
        XCTAssertEqual(RegionParser.parse(""), SkinRegion(polygons: []))
        XCTAssertEqual(
            RegionParser.parse("[Equalizer]\nNumPoints=4\nPointList=0,0,1,0,1,1,0,1"),
            SkinRegion(polygons: [])
        )
        // Section present but no keys -> empty.
        XCTAssertEqual(RegionParser.parse("[Normal]"), SkinRegion(polygons: []))
    }

    // MARK: - Criterion (d): PointList shorter than declared -> drop tail

    func testShortPointListDropsIncompletePolygon() {
        // Declares 4 + 4 vertices (16 ints), but only enough for the first
        // polygon plus two stray ints of the second; the incomplete second
        // polygon is dropped.
        let text = """
        [Normal]
        NumPoints=4,4
        PointList=0,0,10,0,10,10,0,10,99,99
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1)
        XCTAssertEqual(region.polygons[0].points, [
            .init(x: 0, y: 0), .init(x: 10, y: 0),
            .init(x: 10, y: 10), .init(x: 0, y: 10)
        ])
    }

    // MARK: - Criterion (e): garbage values skipped gracefully

    func testGarbageValuesAreSkippedGracefully() {
        // Non-numeric NumPoints entry and non-numeric PointList entries.
        let text = """
        [Normal]
        NumPoints=abc,3
        PointList=1,2,foo,4,5,6,7,8
        """

        let region = RegionParser.parse(text)

        // "abc" is dropped from NumPoints, leaving a single count of 3. The
        // non-numeric "foo" is dropped from the flat list, so the surviving
        // ints are 1,2,4,5,6,7,8 -> first 3 vertices: (1,2),(4,5),(6,7).
        XCTAssertEqual(region.polygons.count, 1)
        XCTAssertEqual(region.polygons[0].points, [
            .init(x: 1, y: 2), .init(x: 4, y: 5), .init(x: 6, y: 7)
        ])
    }

    // MARK: - Criterion (f): space-separated `x,y` pairs (dominant real format)

    func testParsesSpaceSeparatedPointPairs() {
        // Each point is `x,y` (comma inside the pair) and points are separated
        // by spaces — the format emitted by the common region.txt tools.
        let text = """
        [Normal]
        NumPoints=4,4,4,4,4
        PointList=1,0 274,0 274,116 1,116 0,1 275,1 275,33 0,33 \
        2,2 273,2 273,114 2,114 3,3 272,3 272,113 3,113 \
        4,4 271,4 271,112 4,112
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 5)
        for polygon in region.polygons {
            XCTAssertEqual(polygon.points.count, 4)
        }
        XCTAssertEqual(region.polygons[0].points, [
            .init(x: 1, y: 0), .init(x: 274, y: 0),
            .init(x: 274, y: 116), .init(x: 1, y: 116)
        ])
    }

    // MARK: - Criterion (g): comma-flat and space-pair forms are equivalent

    func testCommaFlatAndSpaceSeparatedAreEquivalent() {
        let commaFlat = """
        [Normal]
        NumPoints=4
        PointList=1,0,274,0,274,116,1,116
        """
        let spacePairs = """
        [Normal]
        NumPoints=4
        PointList=1,0 274,0 274,116 1,116
        """

        let expected: [SkinRegion.Point] = [
            .init(x: 1, y: 0), .init(x: 274, y: 0),
            .init(x: 274, y: 116), .init(x: 1, y: 116)
        ]

        let flatRegion = RegionParser.parse(commaFlat)
        let pairRegion = RegionParser.parse(spacePairs)

        XCTAssertEqual(flatRegion, pairRegion)
        XCTAssertEqual(flatRegion.polygons.count, 1)
        XCTAssertEqual(flatRegion.polygons.first?.points, expected)
        XCTAssertEqual(pairRegion.polygons.first?.points, expected)
    }

    // MARK: - Criterion (h): absurd NumPoints must not overflow / crash

    func testHugeNumPointsDoesNotCrash() {
        // `Int.max`: the old `count * 2` overflowed and trapped (SIGTRAP) before
        // any bounds check. The polygon can never be filled by the short list, so
        // it is skipped and parsing returns without crashing.
        let intMax = """
        [Normal]
        NumPoints=9223372036854775807
        PointList=0,0,1,1
        """
        let intMaxRegion = RegionParser.parse(intMax)
        XCTAssertTrue(intMaxRegion.polygons.isEmpty)

        // A moderately-huge value (well within Int but far larger than the list)
        // is likewise skipped.
        let huge = """
        [Normal]
        NumPoints=999999999
        PointList=0,0,1,1
        """
        let hugeRegion = RegionParser.parse(huge)
        XCTAssertTrue(hugeRegion.polygons.isEmpty)
    }

    func testNormalPolygonSurvivesAlongsideHugeNumPoints() {
        // An unfillable absurd count is skipped, but a normal polygon declared
        // alongside it still parses. Order: huge first, then a fillable 3-vertex
        // polygon whose six ints follow in the flat list.
        let text = """
        [Normal]
        NumPoints=9223372036854775807,3
        PointList=20,20,30,20,25,30
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1)
        XCTAssertEqual(region.polygons[0].points, [
            .init(x: 20, y: 20), .init(x: 30, y: 20), .init(x: 25, y: 30)
        ])
    }
}
