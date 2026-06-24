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
/// - polygons declaring a non-positive vertex count are skipped.
// TODO: future increment — also parse the `[Equalizer]` and `[WindowShade]`
//       sections (equalizer window and shade-mode shapes).
public enum RegionParser {

    // MARK: - Parsing

    /// Parses the `[Normal]` section of `text` into a `SkinRegion`.
    public static func parse(_ text: String) -> SkinRegion {
        guard let section = INISection.named("Normal", in: text),
              let counts = section.value(for: "NumPoints").map(ints(from:)),
              let coordinates = section.value(for: "PointList").map(ints(from:))
        else {
            return SkinRegion(polygons: [])
        }
        return SkinRegion(polygons: polygons(counts: counts, coordinates: coordinates))
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
            guard count > 0 else { continue }
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
