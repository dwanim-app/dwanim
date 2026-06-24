import Foundation
import XCTest
@testable import SkinKit

/// Adversarial completeness review for `VisColorParser` (`viscolor.txt`).
///
/// Written by an independent review (QA) pass, NOT the implementer. Each test
/// probes a behaviour drawn from real-world classic-skin config files that the
/// original suite does not cover. FAILURES HERE ARE EXPECTED and document a
/// concrete gap; PASSES confirm the implementation already handles the case.
///
/// No real skin files are used — every fixture is a synthetic in-test string.
final class VisColorParserReviewTests: XCTestCase {

    // MARK: - Gap 1: line endings (classic files are old Windows / old Mac)

    /// CRLF (`\r\n`) is the dominant line ending of real classic config files.
    /// The parser splits on `\n` only, so each line keeps a trailing `\r`.
    /// `.whitespaces` does NOT include `\r`, so the final channel ("3\r")
    /// fails `Int(_)` and the whole RGB line is dropped.
    /// [MUST-FIX] if this fails: CRLF palettes parse as empty.
    func testCRLFLineEndingsStillParse() {
        let text = "10,20,30\r\n40,50,60\r\n70,80,90\r\n"

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors, [
            RGBColor(r: 10, g: 20, b: 30),
            RGBColor(r: 40, g: 50, b: 60),
            RGBColor(r: 70, g: 80, b: 90)
        ], "CRLF lines should parse identically to LF lines")
    }

    /// Old-Mac files use a bare `\r` as the line separator. Splitting on `\n`
    /// only collapses the whole file into a single line.
    /// [MUST-FIX] if this fails: bare-CR palettes collapse to one (mostly
    /// unparseable) line.
    func testBareCRLineEndingsStillParse() {
        let text = "10,20,30\r40,50,60\r70,80,90"

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors, [
            RGBColor(r: 10, g: 20, b: 30),
            RGBColor(r: 40, g: 50, b: 60),
            RGBColor(r: 70, g: 80, b: 90)
        ], "bare-CR lines should parse as three separate colors")
    }

    // MARK: - Gap 5: alternative channel separators

    /// Some authoring tools emit tab-separated channels. The parser splits on
    /// `,` only, so a tab-separated line is a single token that fails `Int(_)`.
    /// [FYI] if this fails: comma is the documented/standard separator; tabs are
    /// nonstandard. Documents tolerance only.
    func testTabSeparatedChannels() {
        let text = "10\t20\t30"

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors, [RGBColor(r: 10, g: 20, b: 30)],
                       "[FYI] tab-separated channels are not parsed")
    }

    /// Space-separated channels (another nonstandard variant).
    /// [FYI] documents tolerance only — comma is the standard separator.
    func testSpaceSeparatedChannels() {
        let text = "10 20 30"

        let colors = VisColorParser.parse(text)

        XCTAssertEqual(colors, [RGBColor(r: 10, g: 20, b: 30)],
                       "[FYI] space-separated channels are not parsed")
    }

    // MARK: - Gap 5 (cont.): negative clamp + comment immediately after values

    /// Negative channel values must clamp to 0. (Existing suite covers -5 mixed
    /// with valid channels; this isolates an all-negative line.)
    func testNegativeChannelsClampToZero() {
        let colors = VisColorParser.parse("-1,-99,-255")

        XCTAssertEqual(colors, [RGBColor(r: 0, g: 0, b: 0)],
                       "negative channels should clamp to 0")
    }

    /// A `//` comment with NO space before it, directly after the value.
    /// Should strip cleanly because `stripComment` runs before integer parsing.
    func testCommentImmediatelyAfterValuesNoSpace() {
        let colors = VisColorParser.parse("255,0,0//red")

        XCTAssertEqual(colors, [RGBColor(r: 255, g: 0, b: 0)],
                       "a // comment glued to the values should be stripped")
    }
}
