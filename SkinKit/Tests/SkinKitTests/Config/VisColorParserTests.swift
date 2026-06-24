import Foundation
import XCTest
@testable import SkinKit

/// Tests for the fault-tolerant parser of `viscolor.txt` from the classic
/// `.wsz` skin format: up to ~24 `R,G,B` value lines, interleaved with blank
/// lines, `//` comments, and trailing junk. The parser never throws and never
/// crashes; it returns every line it could parse, in order.
final class VisColorParserTests: XCTestCase {

    // MARK: - Criterion (a): 24 well-formed lines -> 24 exact colors

    func testParsesTwentyFourWellFormedLines() {
        let lines = (0..<24).map { i in "\(i),\(i + 1),\(i + 2)" }
        let text = lines.joined(separator: "\n")

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors.count, 24)
        for i in 0..<24 {
            XCTAssertEqual(colors[i], RGBColor(r: UInt8(i), g: UInt8(i + 1), b: UInt8(i + 2)))
        }
    }

    // MARK: - Criterion (b): comments / blanks / surrounding whitespace

    func testParsesAroundCommentsBlanksAndWhitespace() {
        let text = """
        // visualization colors
        10,20,30   // background

           40, 50, 60
        // trailing comment-only line

         70,80,90
        """

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors, [
            RGBColor(r: 10, g: 20, b: 30),
            RGBColor(r: 40, g: 50, b: 60),
            RGBColor(r: 70, g: 80, b: 90)
        ])
    }

    // MARK: - Criterion (c): a malformed line is skipped, others survive

    func testSkipsMalformedLinesButKeepsValidOnes() {
        let text = """
        1,2,3
        not,a,color
        4,5
        7,8,9
        """

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors, [
            RGBColor(r: 1, g: 2, b: 3),
            RGBColor(r: 7, g: 8, b: 9)
        ])
    }

    // MARK: - Criterion (d): out-of-range values clamp to 0...255

    func testClampsOutOfRangeChannelsToByteRange() {
        let text = """
        300,128,-5
        256,0,1000
        """

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors, [
            RGBColor(r: 255, g: 128, b: 0),
            RGBColor(r: 255, g: 0, b: 255)
        ])
    }

    // MARK: - Criterion (e): empty input -> []

    func testEmptyInputYieldsNoColors() {
        XCTAssertEqual(VisColorParser.parse(""), [])
        XCTAssertEqual(VisColorParser.parse("   \n\n // just comments\n"), [])
    }
}
