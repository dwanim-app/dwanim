import Foundation
import XCTest
@testable import SkinKit

/// Tests for the fault-tolerant parser of `pledit.txt` from the classic `.wsz`
/// skin format: an INI-like file whose `[Text]` section carries playlist colors
/// (hex) and a font name. The parser never throws; missing keys and missing
/// sections yield `nil` fields.
final class PlaylistEditParserTests: XCTestCase {

    // MARK: - Criterion (a): full [Text] section -> all four colors + font

    func testParsesFullTextSection() {
        let text = """
        [Text]
        Normal=#00FF00
        Current=#FFFFFF
        NormalBG=#000000
        SelectedBG=#0000C6
        Font=Arial
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0, g: 255, b: 0))
        XCTAssertEqual(colors.currentText, RGBColor(r: 255, g: 255, b: 255))
        XCTAssertEqual(colors.normalBackground, RGBColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(colors.selectedBackground, RGBColor(r: 0, g: 0, b: 198))
        XCTAssertEqual(colors.font, "Arial")
    }

    // MARK: - Criterion (b): #RRGGBB and bare RRGGBB both parse

    func testParsesBothHashedAndBareHex() {
        let text = """
        [Text]
        Normal=#1A2B3C
        Current=4D5E6F
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0x1A, g: 0x2B, b: 0x3C))
        XCTAssertEqual(colors.currentText, RGBColor(r: 0x4D, g: 0x5E, b: 0x6F))
    }

    // MARK: - Criterion (c): case-insensitive keys

    func testKeysAreCaseInsensitive() {
        let text = """
        [Text]
        normal=#101010
        CURRENT=#202020
        normalbg=#303030
        selectedBG=#404040
        FONT=Courier
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0x10, g: 0x10, b: 0x10))
        XCTAssertEqual(colors.currentText, RGBColor(r: 0x20, g: 0x20, b: 0x20))
        XCTAssertEqual(colors.normalBackground, RGBColor(r: 0x30, g: 0x30, b: 0x30))
        XCTAssertEqual(colors.selectedBackground, RGBColor(r: 0x40, g: 0x40, b: 0x40))
        XCTAssertEqual(colors.font, "Courier")
    }

    // MARK: - Criterion (d): missing keys -> nil fields

    func testMissingKeysYieldNilFields() {
        let text = """
        [Text]
        Normal=#FF0000
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 255, g: 0, b: 0))
        XCTAssertNil(colors.currentText)
        XCTAssertNil(colors.normalBackground)
        XCTAssertNil(colors.selectedBackground)
        XCTAssertNil(colors.font)
    }

    // MARK: - Criterion (e): missing / empty input -> all nil

    func testEmptyOrSectionlessInputYieldsAllNil() {
        let allNil = PlaylistColors(
            normalText: nil, currentText: nil, normalBackground: nil,
            selectedBackground: nil, font: nil
        )

        XCTAssertEqual(PlaylistEditParser.parse(""), allNil)
        // A file with keys but no [Text] section is ignored.
        XCTAssertEqual(PlaylistEditParser.parse("Normal=#FF0000\nFont=Arial"), allNil)
        // A different section is ignored.
        XCTAssertEqual(PlaylistEditParser.parse("[Other]\nNormal=#FF0000"), allNil)
    }

    // MARK: - Criterion (f): whitespace around '=' tolerated

    func testWhitespaceAroundEqualsTolerated() {
        let text = """
        [Text]
          Normal   =   #ABCDEF
        Font =  Times New Roman
        """

        let colors = PlaylistEditParser.parse(text)

        XCTAssertEqual(colors.normalText, RGBColor(r: 0xAB, g: 0xCD, b: 0xEF))
        XCTAssertEqual(colors.font, "Times New Roman")
    }
}
