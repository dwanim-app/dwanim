import SwiftUI
import XCTest

@testable import DwanimItUI

// MARK: - AppearanceParserTests

/// Tests for `AppearanceTheme.parse(text:filename:)` — the pure, I/O-free parser that
/// turns a picked skin file's TEXT into a resolved `AppearanceTheme` (or a failure).
/// Every case is in-memory: JSON (three shapes) + the `key: value` line fallback, name
/// resolution, unknown-key rejection, partial-token merge over Graphite, the failure
/// modes, and the hex / rgba colour value forms.
final class AppearanceParserTests: XCTestCase {

    // Convenience: the resolved theme, or fail the test with the parse error. The
    // default filename uses the PREFERRED `.dwtheme` extension; a legacy `.dwskin`
    // regression is exercised explicitly below (`testLegacyDwskinFilenameStillStripsStem`).
    private func parsed(_ text: String, _ filename: String = "Test.dwtheme",
                        file: StaticString = #filePath, line: UInt = #line) throws -> AppearanceTheme {
        switch AppearanceTheme.parse(text: text, filename: filename) {
        case .success(let theme):
            return theme
        case .failure(let error):
            XCTFail("expected success, got \(error)", file: file, line: line)
            throw error
        }
    }

    // MARK: - JSON: top-level tokens

    func testJSONTopLevelAllTokens() throws {
        let text = """
        {
          "name": "Sunset",
          "accent": "#e0a341",
          "glow": "rgba(154,96,26,0.42)",
          "glow2": "rgba(126,84,58,0.26)",
          "bg1": "#1a1613",
          "bg2": "#0c0a08",
          "panel": "rgba(39,33,29,0.74)",
          "text": "#efe8e0",
          "muted": "#99908a",
          "lcd": "rgba(0,0,0,0.26)"
        }
        """
        let theme = try parsed(text)
        XCTAssertEqual(theme.name, "Sunset")
        XCTAssertEqual(theme.accent, Color(hex: 0xe0a341))
        XCTAssertEqual(theme.bg1, Color(hex: 0x1a1613))
        XCTAssertEqual(theme.glow, Color(rgba: 154, 96, 26, 0.42))
        XCTAssertEqual(theme.lcd, Color(rgba: 0, 0, 0, 0.26))
    }

    // MARK: - JSON: { "colors": { … } } shape

    func testJSONColorsShape() throws {
        let text = """
        { "name": "Colored", "colors": { "accent": "#123456", "bg1": "#000000" } }
        """
        let theme = try parsed(text)
        XCTAssertEqual(theme.name, "Colored")
        XCTAssertEqual(theme.accent, Color(hex: 0x123456))
        XCTAssertEqual(theme.bg1, Color(hex: 0x000000))
        // Un-specified tokens keep Graphite.
        XCTAssertEqual(theme.panel, AppearanceTheme.graphite.panel)
    }

    // MARK: - JSON: { "vars": { … } } shape

    func testJSONVarsShape() throws {
        let text = """
        { "vars": { "accent": "#abcdef" } }
        """
        let theme = try parsed(text, "Vars.json")
        XCTAssertEqual(theme.accent, Color(hex: 0xabcdef))
        // No explicit name → filename stem.
        XCTAssertEqual(theme.name, "Vars")
    }

    // MARK: - Line format

    func testLineFormatColonAndEquals() throws {
        let text = """
        name: Line Deck
        accent: #3aa8a0
        bg1 = #12161a
        muted = rgba(139,139,144,1)
        """
        let theme = try parsed(text)
        XCTAssertEqual(theme.name, "Line Deck")
        XCTAssertEqual(theme.accent, Color(hex: 0x3aa8a0))
        XCTAssertEqual(theme.bg1, Color(hex: 0x12161a))
        XCTAssertEqual(theme.muted, Color(rgba: 139, 139, 144, 1))
    }

    func testLineFormatSkipsCommentAndBlankLines() throws {
        let text = """
        # this is a comment with no separator

        accent: #ff0000
        // another comment
        """
        let theme = try parsed(text)
        XCTAssertEqual(theme.accent, Color(hex: 0xff0000))
    }

    // MARK: - Name handling

    func testNameFallsBackToFilenameStem() throws {
        let theme = try parsed("accent: #ffffff", "My Cool Theme.dwtheme")
        XCTAssertEqual(theme.name, "My Cool Theme")
    }

    /// Backward-compat regression: a LEGACY `.dwskin` file still derives its display
    /// name from the filename stem (the extension is stripped the same way `.dwtheme`
    /// is). The theme file was renamed `.dwskin` → `.dwtheme`, but the owner's existing
    /// `.dwskin` files must keep loading — no parse logic keys on the extension.
    func testLegacyDwskinFilenameStillStripsStem() throws {
        let theme = try parsed("accent: #ffffff", "Legacy Deck.dwskin")
        XCTAssertEqual(theme.name, "Legacy Deck")
        XCTAssertEqual(theme.accent, Color(hex: 0xffffff))
    }

    func testExplicitNameWinsOverFilename() throws {
        let theme = try parsed("name = Chosen\naccent = #ffffff", "ignored.json")
        XCTAssertEqual(theme.name, "Chosen")
    }

    func testJSONNameKeyIsCaseInsensitive() throws {
        // A capitalised `"Name"` key still sets the display name (matching the
        // case-insensitive token-key handling), rather than being dropped.
        let theme = try parsed(##"{ "Name": "Capitalized", "accent": "#ffffff" }"##, "ignored.json")
        XCTAssertEqual(theme.name, "Capitalized")
    }

    func testJSONNameKeyUppercaseIsCaseInsensitive() throws {
        let theme = try parsed(##"{ "NAME": "Shouty", "accent": "#ffffff" }"##, "ignored.json")
        XCTAssertEqual(theme.name, "Shouty")
    }

    func testBlankExplicitNameFallsBackToFilename() throws {
        let theme = try parsed("name:   \naccent: #ffffff", "Fallback.dwtheme")
        XCTAssertEqual(theme.name, "Fallback")
    }

    // MARK: - Unknown keys ignored

    func testUnknownKeysAreIgnored() throws {
        let text = """
        { "accent": "#3aa8a0", "border": "#111111", "spacing": "8", "shadow": "#222" }
        """
        let theme = try parsed(text)
        XCTAssertEqual(theme.accent, Color(hex: 0x3aa8a0))
        // The unknown keys do not disturb the other tokens (still Graphite).
        XCTAssertEqual(theme.bg1, AppearanceTheme.graphite.bg1)
        XCTAssertEqual(theme.text, AppearanceTheme.graphite.text)
    }

    // MARK: - Partial tokens merge over Graphite

    func testPartialTokensMergeOverGraphite() throws {
        let theme = try parsed("accent: #ff8800")
        XCTAssertEqual(theme.accent, Color(hex: 0xff8800))
        // Every OTHER token is inherited from Graphite unchanged.
        let g = AppearanceTheme.graphite
        XCTAssertEqual(theme.glow, g.glow)
        XCTAssertEqual(theme.glow2, g.glow2)
        XCTAssertEqual(theme.bg1, g.bg1)
        XCTAssertEqual(theme.bg2, g.bg2)
        XCTAssertEqual(theme.panel, g.panel)
        XCTAssertEqual(theme.text, g.text)
        XCTAssertEqual(theme.muted, g.muted)
        XCTAssertEqual(theme.lcd, g.lcd)
    }

    func testMalformedColorValueForOneTokenIsSkippedButOthersApply() throws {
        // `bg1` has a garbage value → dropped; `accent` still applies.
        let theme = try parsed("accent: #00ff00\nbg1: not-a-color")
        XCTAssertEqual(theme.accent, Color(hex: 0x00ff00))
        XCTAssertEqual(theme.bg1, AppearanceTheme.graphite.bg1)
    }

    // MARK: - Failure modes

    func testEmptyTextFails() {
        assertFailure(AppearanceTheme.parse(text: "   \n\t  ", filename: "Blank.json"), .empty)
    }

    func testZeroRecognizedKeysFails() {
        assertFailure(AppearanceTheme.parse(text: ##"{ "foo": "bar", "baz": "#fff" }"##, filename: "Nope.json"),
                      .noRecognizedKeys)
    }

    func testValidJSONButNoTokensDoesNotFallBackToLines() {
        // Valid JSON object → the JSON path is authoritative; no line-format retry.
        assertFailure(AppearanceTheme.parse(text: #"{ "unrelated": "value" }"#, filename: "X.json"),
                      .noRecognizedKeys)
    }

    func testMalformedInputWithNoTokensFails() {
        // Not JSON, and no recognisable `key: value` token lines.
        assertFailure(AppearanceTheme.parse(text: "just some prose\nwith no colors at all", filename: "Prose.txt"),
                      .noRecognizedKeys)
    }

    func testRecognizedKeyWithOnlyMalformedValueFails() {
        // The one recognised key has an unparseable value → nothing to apply.
        assertFailure(AppearanceTheme.parse(text: "accent: banana", filename: "Bad.dwtheme"),
                      .noRecognizedKeys)
    }

    // MARK: - Colour value forms (Color(appearanceToken:))

    func testHexSixDigits() {
        XCTAssertEqual(Color(appearanceToken: "#3aa8a0"), Color(rgba: 58, 168, 160, 1))
    }

    func testHexThreeDigitsExpands() {
        // #0f8 → 00 ff 88.
        XCTAssertEqual(Color(appearanceToken: "#0f8"), Color(rgba: 0, 255, 136, 1))
    }

    func testHexEightDigitsCarriesAlpha() {
        // #3aa8a080 → rgb 58,168,160 with alpha 128/255.
        XCTAssertEqual(Color(appearanceToken: "#3aa8a080"), Color(rgba: 58, 168, 160, 128.0 / 255.0))
    }

    func testRGBAFourComponents() {
        XCTAssertEqual(Color(appearanceToken: "rgba(28, 120, 112, 0.42)"), Color(rgba: 28, 120, 112, 0.42))
    }

    func testRGBThreeComponentsDefaultsAlphaToOne() {
        XCTAssertEqual(Color(appearanceToken: "rgb(10, 20, 30)"), Color(rgba: 10, 20, 30, 1))
    }

    func testUppercaseHexParses() {
        XCTAssertEqual(Color(appearanceToken: "#E0A341"), Color(hex: 0xe0a341))
    }

    func testRGBOutOfRangeChannelsAreClamped() {
        // r < 0 clamps to 0, g > 255 clamps to 255 — a sane in-gamut colour.
        XCTAssertEqual(Color(appearanceToken: "rgb(-5, 999, 0)"), Color(rgba: 0, 255, 0, 1))
    }

    func testRGBAOutOfRangeAlphaIsClamped() {
        // Alpha above 1 clamps to 1; below 0 clamps to 0.
        XCTAssertEqual(Color(appearanceToken: "rgba(10, 20, 30, 5)"), Color(rgba: 10, 20, 30, 1))
        XCTAssertEqual(Color(appearanceToken: "rgba(10, 20, 30, -2)"), Color(rgba: 10, 20, 30, 0))
    }

    func testMalformedColorValuesReturnNil() {
        XCTAssertNil(Color(appearanceToken: "banana"))
        XCTAssertNil(Color(appearanceToken: "#gggggg"))         // non-hex digits
        XCTAssertNil(Color(appearanceToken: "#12345"))          // 5 digits — invalid arity
        XCTAssertNil(Color(appearanceToken: "rgba(1,2)"))       // too few components
        XCTAssertNil(Color(appearanceToken: "rgba(1,2,x,1)"))   // non-numeric component
        XCTAssertNil(Color(appearanceToken: ""))
    }

    // MARK: - Helper

    private func assertFailure(_ result: Result<AppearanceTheme, AppearanceParseError>,
                               _ expected: AppearanceParseError,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success(let theme):
            XCTFail("expected failure \(expected), got success (\(theme.name))", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }
}
