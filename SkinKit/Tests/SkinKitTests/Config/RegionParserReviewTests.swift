import Foundation
import XCTest
@testable import SkinKit

/// Adversarial completeness review for `RegionParser` (`region.txt`).
///
/// Written by an independent review (QA) pass, NOT the implementer. Each test
/// probes a behaviour drawn from real-world classic-skin config files that the
/// original suite does not cover. FAILURES HERE ARE EXPECTED and document a
/// concrete gap; PASSES confirm the implementation already handles the case.
///
/// No real skin files are used — every fixture is a synthetic in-test string.
final class RegionParserReviewTests: XCTestCase {

    // MARK: - Gap 1: line endings

    /// CRLF is the dominant ending of real `region.txt`. `INISection` splits on
    /// `\n` only, so "[Normal]\r" fails `hasSuffix("]")` and the section is
    /// never found.
    /// [MUST-FIX] if this fails: CRLF region.txt yields no polygons (window
    /// gets no custom shape).
    func testCRLFLineEndingsParse() {
        let text = "[Normal]\r\nNumPoints=4\r\nPointList=0,0,10,0,10,10,0,10\r\n"

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1, "CRLF region should yield one polygon")
        XCTAssertEqual(region.polygons.first?.points, [
            .init(x: 0, y: 0), .init(x: 10, y: 0),
            .init(x: 10, y: 10), .init(x: 0, y: 10)
        ], "CRLF region coordinates should parse")
    }

    /// Old-Mac bare-CR file collapses to one line under a `\n` split.
    /// [MUST-FIX] if this fails: bare-CR region.txt yields no polygons.
    func testBareCRLineEndingsParse() {
        let text = "[Normal]\rNumPoints=4\rPointList=0,0,10,0,10,10,0,10"

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1, "bare-CR region should yield one polygon")
    }

    // MARK: - Gap 2: inline comment on a key value

    /// An inline `; comment` after `NumPoints`. `INISection` does not strip it,
    /// so the value becomes "4 ; foo"; the comma split then yields "4 ; foo"
    /// which fails `Int(_)`, dropping the count -> no polygons.
    /// [FYI] inline comments in region.txt are rare; documents tolerance only.
    func testInlineCommentOnNumPoints() {
        let text = """
        [Normal]
        NumPoints=4 ; one rectangle
        PointList=0,0,10,0,10,10,0,10
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1,
                       "[FYI] inline ; comment after NumPoints should not drop the polygon")
    }

    // MARK: - Gap 4: count / list mismatches

    /// PointList has MORE coordinates than NumPoints declares. The extra trailing
    /// coordinates must be ignored cleanly (cursor stops after the declared
    /// vertices). Expected PASS.
    func testExtraPointsBeyondDeclaredAreIgnored() {
        let text = """
        [Normal]
        NumPoints=4
        PointList=0,0,10,0,10,10,0,10,99,99,88,88
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1)
        XCTAssertEqual(region.polygons.first?.points.count, 4,
                       "extra trailing coordinates beyond NumPoints should be ignored")
        XCTAssertEqual(region.polygons.first?.points, [
            .init(x: 0, y: 0), .init(x: 10, y: 0),
            .init(x: 10, y: 10), .init(x: 0, y: 10)
        ])
    }

    /// NumPoints present but PointList key entirely missing -> empty region, no
    /// crash. Expected PASS (the `.map` on a nil value short-circuits the guard).
    func testNumPointsPresentButPointListMissing() {
        let text = """
        [Normal]
        NumPoints=4
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region, SkinRegion(polygons: []),
                       "missing PointList should yield an empty region without crashing")
    }

    /// PointList present but NumPoints key missing -> empty region, no crash.
    func testPointListPresentButNumPointsMissing() {
        let text = """
        [Normal]
        PointList=0,0,10,0,10,10,0,10
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region, SkinRegion(polygons: []),
                       "missing NumPoints should yield an empty region without crashing")
    }

    /// Odd number of coordinates in PointList: a dangling x with no y. Because
    /// the parser consumes `count*2` ints per polygon, a polygon whose final y
    /// is missing should drop that polygon rather than crash on an out-of-bounds
    /// pair access. Expected PASS — this guards against an index crash.
    func testOddCoordinateCountDoesNotCrash() {
        // Declares 2 vertices (needs 4 ints) but supplies only 3.
        let text = """
        [Normal]
        NumPoints=2
        PointList=0,0,10
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region, SkinRegion(polygons: []),
                       "an odd/short coordinate list should drop the polygon, not crash")
    }

    /// A two-polygon file where the SECOND polygon has an odd dangling
    /// coordinate. The first polygon must survive; the incomplete second is
    /// dropped without crashing.
    func testDanglingCoordinateInSecondPolygonKeepsFirst() {
        // Polygon 1 needs 4 ints (2 verts); polygon 2 declares 2 verts (needs 4)
        // but only 3 ints remain after polygon 1.
        let text = """
        [Normal]
        NumPoints=2,2
        PointList=0,0,10,10,20,20,30
        """

        let region = RegionParser.parse(text)

        XCTAssertEqual(region.polygons.count, 1,
                       "first polygon should survive a dangling coordinate in the second")
        XCTAssertEqual(region.polygons.first?.points, [
            .init(x: 0, y: 0), .init(x: 10, y: 10)
        ])
    }
}
