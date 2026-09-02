import Foundation
import XCTest
@testable import SkinKit

/// Tests for the multi-section `region.txt` parser (`RegionParser.parseAll`),
/// which reads all four window-shape sections — `[Normal]`, `[Equalizer]`,
/// `[WindowShade]`, `[EqualizerWS]` — into a `SkinRegionSet`. These cover the
/// behaviours the single-section `parse` (kept green by `RegionParserTests`) does
/// not: per-section isolation, first-wins on duplicate headers/keys, the `#` and
/// `//` comment dialects, commented-out sections, and the nested-rectangle idiom.
final class RegionParserSectionsTests: XCTestCase {

    // MARK: - Each of the four sections parses into its own slot

    func testAllFourSectionsParseIndependently() {
        let text = """
        [Normal]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116
        [Equalizer]
        NumPoints=3
        PointList=0,0,10,0,5,10
        [WindowShade]
        NumPoints=4
        PointList=0,0,275,0,275,14,0,14
        [EqualizerWS]
        NumPoints=4
        PointList=1,1,2,1,2,2,1,2
        """

        let set = RegionParser.parseAll(text)

        XCTAssertEqual(set.normal.polygons.count, 1)
        XCTAssertEqual(set.normal.polygons.first?.points.first, .init(x: 0, y: 0))
        XCTAssertEqual(set.equalizer.polygons.count, 1)
        XCTAssertEqual(set.equalizer.polygons.first?.points.count, 3)
        XCTAssertEqual(set.windowShade.polygons.count, 1)
        XCTAssertEqual(set.windowShade.polygons.first?.points, [
            .init(x: 0, y: 0), .init(x: 275, y: 0),
            .init(x: 275, y: 14), .init(x: 0, y: 14)
        ])
        XCTAssertEqual(set.equalizerWS.polygons.count, 1)
    }

    /// A section absent from the file yields an empty (rectangular) region, not a
    /// crash and not a borrow from another section.
    func testAbsentSectionsAreEmpty() {
        let text = """
        [Normal]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116
        """

        let set = RegionParser.parseAll(text)

        XCTAssertFalse(set.normal.isEmpty)
        XCTAssertTrue(set.equalizer.isEmpty)
        XCTAssertTrue(set.windowShade.isEmpty)
        XCTAssertTrue(set.equalizerWS.isEmpty)
    }

    // MARK: - Duplicate section header -> FIRST wins

    func testDuplicateNormalSectionFirstWins() {
        // Two [Normal] sections; the FIRST must win (12 real skins have >1 [Normal]).
        let text = """
        [Normal]
        NumPoints=3
        PointList=0,0,10,0,5,10
        [Normal]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116
        """

        let normal = RegionParser.parse(text)
        let set = RegionParser.parseAll(text)

        // First [Normal] = the triangle (3 points), not the later rectangle.
        XCTAssertEqual(normal.polygons.count, 1)
        XCTAssertEqual(normal.polygons.first?.points.count, 3)
        XCTAssertEqual(set.normal, normal, "parse and parseAll(...).normal must agree")
    }

    // MARK: - Duplicate key within a section -> FIRST wins

    func testDuplicateKeyFirstWins() {
        let text = """
        [Normal]
        NumPoints=3
        NumPoints=4
        PointList=0,0,10,0,5,10
        PointList=9,9,8,8,7,7,6,6
        """

        let normal = RegionParser.parse(text)

        // First NumPoints (3) + first PointList (the triangle) win.
        XCTAssertEqual(normal.polygons.count, 1)
        XCTAssertEqual(normal.polygons.first?.points, [
            .init(x: 0, y: 0), .init(x: 10, y: 0), .init(x: 5, y: 10)
        ])
    }

    // MARK: - Comment dialects (# and //) in addition to ;

    func testHashAndSlashCommentsAreTolerated() {
        let text = """
        # a hash comment line
        [Normal]
        // a slash comment line
        NumPoints=4 // trailing slash comment
        PointList=0,0,275,0,275,116,0,116 # trailing hash comment
        """

        let normal = RegionParser.parse(text)

        XCTAssertEqual(normal.polygons.count, 1)
        XCTAssertEqual(normal.polygons.first?.points, [
            .init(x: 0, y: 0), .init(x: 275, y: 0),
            .init(x: 275, y: 116), .init(x: 0, y: 116)
        ])
    }

    // MARK: - Commented-out section header -> treated as absent

    func testCommentedOutSectionIsAbsent() {
        // The [Equalizer] header is commented out (LadyCroft idiom), so the EQ
        // region is absent -> empty -> rectangular EQ window.
        let text = """
        [Normal]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116

        ;[Equalizer]
        ;NumPoints=4
        ;PointList=0,0,275,0,275,104,0,104
        """

        let set = RegionParser.parseAll(text)

        XCTAssertFalse(set.normal.isEmpty)
        XCTAssertTrue(set.equalizer.isEmpty, "a commented-out [Equalizer] must not shape the EQ window")
    }

    // MARK: - Nested-rectangle (rounded-corner) idiom parses all slabs

    func testNestedRectangleSlabsAllParse() {
        // The classic "rounded corners via stacked slabs" idiom (883_breeder):
        // five overlapping rectangles that union to a rounded rectangle.
        let text = """
        [Normal]
        NumPoints=4,4,4,4,4
        PointList=1,0 274,0 274,116 1,116 0,1 275,1 275,33 0,33 0,34 275,34 275,79 0,79 0,80 275,80 275,113 0,113 0,114 275,114 275,116 0,116
        """

        let normal = RegionParser.parse(text)

        XCTAssertEqual(normal.polygons.count, 5, "all five nested-rectangle slabs parse")
        for poly in normal.polygons {
            XCTAssertEqual(poly.points.count, 4)
        }
    }

    // MARK: - CRLF across sections

    func testCRLFAcrossSections() {
        let text = "[Normal]\r\nNumPoints=4\r\nPointList=0,0,275,0,275,116,0,116\r\n"
            + "[Equalizer]\r\nNumPoints=3\r\nPointList=0,0,10,0,5,10\r\n"

        let set = RegionParser.parseAll(text)

        XCTAssertEqual(set.normal.polygons.count, 1)
        XCTAssertEqual(set.equalizer.polygons.count, 1)
    }

    // MARK: - Keys BEFORE any header belong to no section (dropped)

    func testKeysBeforeAnyHeaderAreDroppedAndDoNotLeakIntoTheFirstSection() {
        // A triangle declared BEFORE [Normal], then a rectangle inside it. The
        // pre-header keys must be dropped: if they leaked into the first section,
        // first-wins would keep the TRIANGLE and shadow the real rectangle.
        let text = """
        NumPoints=3
        PointList=0,0,10,0,5,10
        [Normal]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116
        """

        let normal = RegionParser.parse(text)

        XCTAssertEqual(normal.polygons.count, 1)
        XCTAssertEqual(normal.polygons.first?.points.count, 4, "the in-section rectangle wins")
    }

    func testKeysBeforeAnyHeaderAloneYieldNoShape() {
        let text = """
        NumPoints=3
        PointList=0,0,10,0,5,10
        [Normal]
        """

        XCTAssertTrue(RegionParser.parse(text).isEmpty, "pre-header keys never populate [Normal]")
        XCTAssertTrue(RegionParser.parseAll(text).normal.isEmpty)
    }

    // MARK: - Section headers are case-insensitive and tolerate inner padding

    func testHeaderMatchingIsCaseInsensitive() {
        let text = """
        [NORMAL]
        NumPoints=3
        PointList=0,0,10,0,5,10
        [equalizer]
        NumPoints=4
        PointList=0,0,275,0,275,116,0,116
        [WindowShade]
        NumPoints=4
        PointList=0,0,275,0,275,14,0,14
        [EQUALIZERws]
        NumPoints=4
        PointList=1,1,2,1,2,2,1,2
        """

        let set = RegionParser.parseAll(text)

        XCTAssertEqual(set.normal.polygons.first?.points.count, 3, "[NORMAL] is [Normal]")
        XCTAssertEqual(set.equalizer.polygons.first?.points.count, 4, "[equalizer] is [Equalizer]")
        XCTAssertEqual(set.windowShade.polygons.count, 1)
        XCTAssertEqual(set.equalizerWS.polygons.count, 1, "[EQUALIZERws] is [EqualizerWS]")
        XCTAssertEqual(RegionParser.parse(text), set.normal)
    }

    func testHeaderToleratesInnerWhitespace() {
        let text = """
        [ normal ]
        NumPoints=3
        PointList=0,0,10,0,5,10
        """

        let normal = RegionParser.parse(text)

        XCTAssertEqual(normal.polygons.count, 1)
        XCTAssertEqual(normal.polygons.first?.points.count, 3)
    }

    // MARK: - NumPoints / PointList count mismatch (stop when points run out)

    func testNumPointsMismatchStopsWhenPointsRunOut() {
        // NumPoints declares 4+4 vertices (16 ints) but only 10 ints are supplied:
        // the first polygon fills, the second runs out and is dropped.
        let text = """
        [Equalizer]
        NumPoints=4,4
        PointList=0,0,10,0,10,10,0,10,99,99
        """

        let set = RegionParser.parseAll(text)

        XCTAssertEqual(set.equalizer.polygons.count, 1)
        XCTAssertEqual(set.equalizer.polygons.first?.points.count, 4)
    }
}
