import Foundation

// MARK: - RegionParser

/// Fault-tolerant parser for `region.txt`, the custom-window-shape file of the
/// classic `.wsz` skin format.
///
/// The file is INI-like. This parser reads the `[Normal]` section's two keys:
/// - `NumPoints` — a comma-separated list of per-polygon vertex counts;
/// - `PointList` — a flat list of `x,y` pairs for all polygons, concatenated in
///   polygon order.
///
/// `PointList` appears in two real-world dialects, both accepted here:
/// - space-separated pairs, where each point is `x,y` and points are separated
///   by whitespace, e.g. `1,0 274,0 274,116 1,116` (the dominant tool output);
/// - a fully comma-flat stream, e.g. `1,0,274,0,274,116,1,116`.
/// Both are handled by extracting every integer in the string regardless of
/// whether commas or whitespace separate them, then pairing the integers
/// sequentially into vertices (ints 0&1 → vertex 0, ints 2&3 → vertex 1, …).
///
/// The flat point stream is sliced back into polygons by walking `NumPoints`:
/// polygon *i* consumes `NumPoints[i]` vertices from the front of the list.
///
/// Tolerance contract — the parser never throws and never crashes:
/// - a missing `[Normal]` section, or a missing `NumPoints`/`PointList`, yields
///   `SkinRegion(polygons: [])`;
/// - non-numeric entries in either list are dropped before slicing;
/// - if the point list runs out mid-polygon, the incomplete trailing polygon is
///   dropped and only the fully-formed polygons are returned;
/// - polygons declaring a non-positive vertex count are skipped;
/// - a polygon whose declared vertex count exceeds what the point list could
///   ever supply is skipped (parsing continues), so an absurd `NumPoints` value
///   can never overflow or crash.
///
/// All FOUR window-shape sections are parsed by `parseAll` — `[Normal]` (main
/// window), `[Equalizer]` (EQ window), `[WindowShade]` and `[EqualizerWS]`
/// (collapsed windowshade shapes). This parser does NOT reuse the shared
/// `INISection` reader (whose duplicate-header / duplicate-key policy is
/// last-wins): `region.txt` requires FIRST-wins for both a repeated section
/// header (12 real skins ship more than one `[Normal]`) and a repeated key, so a
/// dedicated first-wins reader lives here. It also tolerates three comment
/// dialects — `;`, `#`, and `//` — where `INISection` only strips `;`.
public enum RegionParser {

    // MARK: - Parsing

    /// Parses the `[Normal]` section of `text` into a `SkinRegion`.
    ///
    /// Kept as the single-section entry point (its behaviour is pinned by
    /// `RegionParserTests`); it now shares the first-wins, multi-dialect reader
    /// with `parseAll`, so `parse(text) == parseAll(text).normal`.
    public static func parse(_ text: String) -> SkinRegion {
        region(named: "normal", in: sections(in: text))
    }

    /// Parses ALL four window-shape sections into a `SkinRegionSet`. A section
    /// that is absent (or has no usable `NumPoints`/`PointList`) yields an empty
    /// `SkinRegion`. On a duplicate section header, the FIRST occurrence wins.
    public static func parseAll(_ text: String) -> SkinRegionSet {
        let all = sections(in: text)
        return SkinRegionSet(
            normal: region(named: "normal", in: all),
            equalizer: region(named: "equalizer", in: all),
            windowShade: region(named: "windowshade", in: all),
            equalizerWS: region(named: "equalizerws", in: all)
        )
    }

    // MARK: - Private: section reader (first-wins headers + keys)

    /// One parsed `[Header]` block: its lowercased name and its `key -> value`
    /// pairs (keys lowercased, FIRST assignment kept).
    private struct RawSection {
        let name: String
        var values: [String: String]
    }

    /// The `SkinRegion` for the FIRST section named `name` (lowercased) among
    /// `all`, or an empty region when it is absent or lacks a usable
    /// `NumPoints`/`PointList` pair.
    private static func region(named name: String, in all: [RawSection]) -> SkinRegion {
        guard let section = all.first(where: { $0.name == name }),
              let counts = section.values["numpoints"].map(ints(from:)),
              let coordinates = section.values["pointlist"].map(ints(from:))
        else {
            return SkinRegion(polygons: [])
        }
        return SkinRegion(polygons: polygons(counts: counts, coordinates: coordinates))
    }

    /// Splits `text` into its ordered `[Header]` sections. Within each section the
    /// FIRST assignment of a key wins; a duplicate section header keeps BOTH blocks
    /// in order (the caller's `first(where:)` then selects the first by name, so the
    /// first `[Normal]` wins). Lines before any header belong to no section and are
    /// dropped. Comments (`;`, `#`, `//`) are stripped before header/key detection,
    /// so a fully-commented header line is not a header. Any newline (LF, CR, CRLF)
    /// separates lines.
    private static func sections(in text: String) -> [RawSection] {
        var result: [RawSection] = []
        var current: RawSection?

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = stripComment(from: rawLine)
            if let name = header(of: line) {
                if let current { result.append(current) }
                current = RawSection(name: name, values: [:])
                continue
            }
            guard current != nil, let (key, value) = keyValue(of: line) else { continue }
            // First-wins: only record a key the section has not seen yet.
            if current!.values[key] == nil {
                current!.values[key] = value
            }
        }
        if let current { result.append(current) }
        return result
    }

    /// Drops a comment (from the first `;`, `#`, or `//` to end-of-line) and trims
    /// surrounding whitespace, returning the bare content of the line. Region
    /// values are numeric, so none of the three markers can ever be part of real
    /// `NumPoints`/`PointList` data.
    private static func stripComment(from line: Substring) -> String {
        var content = Substring(line)
        // `;` and `#` full/inline comments.
        if let semi = content.firstIndex(of: ";") { content = content[..<semi] }
        if let hash = content.firstIndex(of: "#") { content = content[..<hash] }
        // `//` comment: cut at the first "//".
        if let slash = content.range(of: "//") { content = content[..<slash.lowerBound] }
        return content.trimmingCharacters(in: .whitespaces)
    }

    /// Returns the lowercased header name of a `[Header]` line, or `nil`.
    private static func header(of line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]"), line.count >= 2 else { return nil }
        return line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Splits a `Key = Value` line into a lowercased key and trimmed value, or
    /// `nil` if there is no `=` or the key is empty.
    private static func keyValue(of line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    // MARK: - Private

    /// Extracts every integer from `list`, treating both commas and whitespace
    /// as separators so that comma-flat (`1,2,3,4`), space-separated `x,y` pairs
    /// (`1,2 3,4`), and mixed/extra-whitespace forms all parse identically.
    /// Each non-empty token is parsed as an `Int` (negative signs supported);
    /// blank or non-numeric tokens are dropped.
    private static func ints(from list: String) -> [Int] {
        list
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .compactMap { Int($0) }
    }

    /// Slices the flat `coordinates` (x, y, x, y, …) into polygons according to
    /// `counts`, dropping any trailing polygon that the coordinates can't fully
    /// supply.
    private static func polygons(counts: [Int], coordinates: [Int]) -> [SkinRegion.Polygon] {
        var result: [SkinRegion.Polygon] = []
        var cursor = 0
        for count in counts {
            // Bound `count` BEFORE multiplying: a `NumPoints` value parsed from an
            // untrusted file can be as large as `Int.max`, so `count * 2` would
            // overflow and trap. The total vertex budget is `coordinates.count / 2`,
            // so any `count` larger than that can never be filled — skip it (and
            // keep parsing the rest), matching the existing "drop unfillable" rule.
            guard count > 0, count <= coordinates.count / 2 else { continue }
            let needed = count * 2
            guard cursor + needed <= coordinates.count else { break }
            let slice = coordinates[cursor ..< cursor + needed]
            result.append(SkinRegion.Polygon(points: points(from: Array(slice))))
            cursor += needed
        }
        return result
    }

    /// Pairs a flat `[x, y, x, y, …]` slice into vertices. The slice length is
    /// guaranteed even by the caller.
    private static func points(from flat: [Int]) -> [SkinRegion.Point] {
        stride(from: 0, to: flat.count, by: 2).map { i in
            SkinRegion.Point(x: flat[i], y: flat[i + 1])
        }
    }
}
