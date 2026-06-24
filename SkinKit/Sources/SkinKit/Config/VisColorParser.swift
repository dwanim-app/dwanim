import Foundation

// MARK: - VisColorParser

/// Fault-tolerant parser for `viscolor.txt`, the visualization palette file of
/// the classic `.wsz` skin format.
///
/// The file is a list of `R,G,B` value lines (0–255 ints), conventionally up to
/// ~24 of them, freely interleaved with blank lines and `//` comments and often
/// carrying a trailing `//` comment or stray junk on a value line. This parser
/// extracts the first three integers from each value line into an `RGBColor`, in
/// document order.
///
/// Tolerance contract — the parser never throws and never crashes:
/// - blank lines and comment-only lines are skipped;
/// - channels may be separated by commas and/or whitespace (space or tab);
/// - any newline (CR, LF, or CRLF) separates lines;
/// - a line with fewer than three parseable integers is skipped;
/// - integers outside `0...255` are clamped into range;
/// - the count is returned as-is (no padding to or truncation at 24) — the
///   loader decides what a short or long palette means.
public enum VisColorParser {

    // MARK: - Parsing

    /// Parses every well-formed `R,G,B` line of `text` into an `RGBColor`.
    public static func parse(_ text: String) -> [RGBColor] {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .compactMap(color(fromLine:))
    }

    // MARK: - Private

    /// Parses a single line into a color, or `nil` if it is blank, a comment,
    /// or does not carry three integers.
    private static func color(fromLine rawLine: Substring) -> RGBColor? {
        let line = stripComment(from: rawLine)
        let channels = line
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .compactMap { Int($0) }
        guard channels.count >= 3 else { return nil }
        return RGBColor(r: clampToByte(channels[0]),
                        g: clampToByte(channels[1]),
                        b: clampToByte(channels[2]))
    }

    /// Drops a trailing `//` comment and surrounding whitespace from a line.
    private static func stripComment(from line: Substring) -> Substring {
        if let range = line.range(of: "//") {
            return line[line.startIndex..<range.lowerBound]
        }
        return line
    }

    /// Clamps an arbitrary integer into the `0...255` byte range.
    private static func clampToByte(_ value: Int) -> UInt8 {
        UInt8(min(255, max(0, value)))
    }
}
