import Foundation
import XCTest
@testable import SkinKit

/// Adversarial completeness review for `PlaylistEditParser` (`pledit.txt`).
///
/// Written by an independent review (QA) pass, NOT the implementer. Each test
/// probes a behaviour drawn from real-world classic-skin config files that the
/// original suite does not cover. FAILURES HERE ARE EXPECTED and document a
/// concrete gap; PASSES confirm the implementation already handles the case.
///
/// No real skin files are used — every fixture is a synthetic in-test string.
final class PlaylistEditParserReviewTests: XCTestCase {

    // MARK: - Gap 1: line endings

    /// CRLF is the dominant ending of real `pledit.txt`. `INISection` splits on
    /// `\n` only: the header becomes "[Text]\r" (so `hasSuffix("]")` fails and
    /// the section is never found), and every value keeps a trailing `\r`
    /// (so 6-hex-digit colors become 7 chars and fail).
    /// [MUST-FIX] if this fails: CRLF pledit.txt yields all-nil colors.
    func testCRLFSectionAndValuesParse() {
        let text = "[Text]\r\nNormal=#00FF00\r\nFont=Arial\r\n"

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0, g: 255, b: 0),
                       "CRLF: color value should parse")
        XCTAssertEqual(colors.font, "Arial",
                       "CRLF: font value should not keep a trailing \\r")
    }

    /// Old-Mac bare-CR file: collapses to a single line under a `\n` split, so
    /// no `[Text]` header is ever recognized.
    /// [MUST-FIX] if this fails: bare-CR pledit.txt yields all-nil colors.
    func testBareCRSectionAndValuesParse() {
        let text = "[Text]\rNormal=#00FF00\rFont=Arial"

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0, g: 255, b: 0),
                       "bare-CR: color value should parse")
        XCTAssertEqual(colors.font, "Arial",
                       "bare-CR: font value should parse")
    }

    // MARK: - Gap 2: inline / full-line comments inside the section

    /// `INISection` does not strip `;` comments. A trailing `; comment` on the
    /// Font line is folded into the font name verbatim.
    /// [FYI] if this fails: real files rarely put inline comments after pledit
    /// values, but if present the font name is corrupted ("Arial ; main").
    func testInlineSemicolonCommentOnFontValue() {
        let text = """
        [Text]
        Font=Arial ; main playlist font
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.font, "Arial",
                       "[FYI] inline ; comment should be stripped from the font name")
    }

    /// An inline `; comment` after a hex color. Because the value becomes
    /// "#00FF00 ; ..." (>6 hex digits after the #), the color silently fails to
    /// nil rather than corrupting — but the data is still lost.
    /// [FYI] documents that inline-commented color lines are dropped.
    func testInlineSemicolonCommentOnColorValue() {
        let text = """
        [Text]
        Normal=#00FF00 ; normal text color
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0, g: 255, b: 0),
                       "[FYI] inline ; comment should not prevent the color parsing")
    }

    /// A full-line `; comment` between key lines must be ignored, not treated as
    /// a key. (A line with no `=` is already dropped, so this should pass and
    /// confirms full-line comments are harmless.)
    func testFullLineSemicolonCommentIsIgnored() {
        let text = """
        [Text]
        ; this is a comment line
        Normal=#00FF00
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0, g: 255, b: 0),
                       "a full-line ; comment must not disturb following keys")
    }

    // MARK: - Gap 3: hex variants

    /// Lowercase hex must parse (Swift's `isHexDigit` / `UInt32(radix:)` accept
    /// it). Expected PASS — confirms tolerance.
    func testLowercaseHexParses() {
        let colors = PlaylistEditParser.parse("[Text]\nNormal=#abcdef")

        XCTAssertEqual(colors.normalText, RGBColor(r: 0xAB, g: 0xCD, b: 0xEF),
                       "lowercase hex should parse")
    }

    /// A `0x`-prefixed value is 8 chars ("0xRRGGBB" minus...) — not exactly six
    /// hex digits, so it must be rejected to nil WITHOUT crashing. Expected PASS.
    func testStray0xPrefixRejectedNotCrash() {
        let colors = PlaylistEditParser.parse("[Text]\nNormal=0x00FF00")

        XCTAssertNil(colors.normalText,
                     "a 0x-prefixed hex string should be rejected (out of scope), not crash")
    }

    /// A 3-digit shorthand hex (out of scope) must be rejected to nil, not
    /// crash. Expected PASS. [FYI] 3-digit hex is explicitly out of scope.
    func testThreeDigitHexRejectedNotCrash() {
        let colors = PlaylistEditParser.parse("[Text]\nNormal=#0F0")

        XCTAssertNil(colors.normalText,
                     "[FYI] 3-digit shorthand hex is out of scope and should be nil")
    }
}
