import Foundation

// MARK: - PlaylistEditParser

/// Fault-tolerant parser for `pledit.txt`, the playlist-window color and font
/// file of the classic `.wsz` skin format.
///
/// The file is INI-like; the colors and font live in a `[Text]` section with
/// keys `Normal`, `Current`, `NormalBG`, `SelectedBG` (hex colors written
/// `#RRGGBB` or bare `RRGGBB`) and `Font` (a free-text font name). Keys are
/// matched case-insensitively and whitespace around `=` is tolerated.
///
/// Tolerance contract — the parser never throws and never crashes:
/// - a missing `[Text]` section yields a value with every field `nil`;
/// - a missing or unparseable key leaves its field `nil`;
/// - other sections are ignored.
public enum PlaylistEditParser {

    // MARK: - Parsing

    /// Parses the `[Text]` section of `text` into a `PlaylistColors`.
    public static func parse(_ text: String) -> PlaylistColors {
        guard let section = INISection.named("Text", in: text) else {
            return empty
        }
        return PlaylistColors(
            normalText: color(section, "Normal"),
            currentText: color(section, "Current"),
            normalBackground: color(section, "NormalBG"),
            selectedBackground: color(section, "SelectedBG"),
            font: section.value(for: "Font").flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Private

    /// The all-`nil` result used when there is no `[Text]` section.
    private static let empty = PlaylistColors(
        normalText: nil, currentText: nil, normalBackground: nil,
        selectedBackground: nil, font: nil
    )

    /// Reads `key` from `section` and parses it as a hex color, or `nil`.
    private static func color(_ section: INISection, _ key: String) -> RGBColor? {
        section.value(for: key).flatMap(hexColor(from:))
    }

    /// Parses an `#RRGGBB` or bare `RRGGBB` hex string into an `RGBColor`.
    ///
    /// Returns `nil` unless the string is exactly six hex digits (after an
    /// optional leading `#`).
    private static func hexColor(from raw: String) -> RGBColor? {
        var digits = Substring(raw)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        return RGBColor(
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }
}
