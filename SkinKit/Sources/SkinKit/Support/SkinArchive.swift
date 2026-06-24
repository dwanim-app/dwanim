import Foundation

/// A canonical lookup over a classic skin archive.
///
/// Real-world archives are inconsistent: filenames vary in case (`MAIN.BMP`,
/// `Main.bmp`) and sprites are frequently nested in a subfolder
/// (`baseskin/TITLEBAR.BMP`). `SkinArchive` wraps a `ZipArchive` and resolves a
/// file by its canonical *basename* — the last path component, matched
/// case-insensitively across nested folders — so callers can simply ask for
/// `"main.bmp"` or `"viscolor.txt"` without knowing the archive's layout.
///
/// Construction throws only what `ZipArchive` throws (no usable archive).
/// All per-entry faults are inherited from `ZipArchive.extract(_:)`, which
/// returns `nil` rather than throwing, so lookups never throw.
public struct SkinArchive: Sendable {

    // MARK: - Stored state

    /// The wrapped reader; the sole source of bytes and entry paths.
    private let archive: ZipArchive

    // MARK: - Public API

    public init(data: Data) throws {
        self.archive = try ZipArchive(data: data)
    }

    /// All entry paths, exactly as stored, in central-directory order. Provided
    /// for inspection; lookups go through `file(named:)`.
    public var entryPaths: [String] {
        archive.entries.map(\.path)
    }

    /// Resolves a file by its canonical name (a basename like `"main.bmp"`).
    ///
    /// The last path component of each entry is compared against `name`
    /// case-insensitively, and the `name` query is likewise matched
    /// case-insensitively. Nested folders are searched. Directory entries (paths
    /// ending in `/`) are never matched.
    ///
    /// When several entries match, the choice is deterministic:
    ///   1. prefer the shallowest path (fewest `/` separators — root beats
    ///      nested);
    ///   2. break ties by lexicographic order of the full stored path
    ///      (Swift `String` `<`, i.e. Unicode scalar order, so uppercase sorts
    ///      before lowercase).
    ///
    /// Returns the decompressed bytes, or `nil` if no entry matches or the
    /// matched entry is corrupt/unsupported. Never throws.
    public func file(named name: String) -> Data? {
        // Try every basename match in precedence order; the top candidate wins
        // when readable, but a corrupt entry falls back to the next-best
        // readable sibling (ADR-2 fault tolerance). The order is derived from
        // the paths themselves, so it is independent of central-directory order.
        for path in candidatePaths(for: name) {
            if let bytes = archive.extract(path) { return bytes }
        }
        return nil
    }

    // MARK: - Matching

    /// All stored paths whose basename matches `name`, ordered by the documented
    /// depth-then-lexicographic precedence. Empty when nothing matches.
    private func candidatePaths(for name: String) -> [String] {
        let target = SkinArchive.basename(of: name).lowercased()
        guard !target.isEmpty else { return [] }

        return entryPaths
            .filter { path in
                !SkinArchive.isDirectoryPath(path)
                    && SkinArchive.basename(of: path).lowercased() == target
            }
            .sorted(by: SkinArchive.precedes)
    }

    /// Orders two matching paths: shallower first, then lexicographically.
    private static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        let leftDepth = depth(of: lhs)
        let rightDepth = depth(of: rhs)
        if leftDepth != rightDepth { return leftDepth < rightDepth }
        return lhs < rhs
    }

    // MARK: - Path helpers

    /// Both separators we honour: forward slash (archive-canonical) and
    /// backslash (Windows-authored archives sometimes store this form).
    private static let separators: Set<Character> = ["/", "\\"]

    /// The last path component of `path`, treating both `/` and `\` as
    /// separators. For a query basename without separators this returns the
    /// input unchanged.
    private static func basename(of path: String) -> String {
        String(path.split(whereSeparator: separators.contains).last ?? "")
    }

    /// The number of separators (`/` or `\`) in a path — its nesting depth.
    private static func depth(of path: String) -> Int {
        path.reduce(0) { separators.contains($1) ? $0 + 1 : $0 }
    }

    /// Whether `path` denotes a directory entry (ends in a separator) rather
    /// than a file, honouring both `/` and `\`.
    private static func isDirectoryPath(_ path: String) -> Bool {
        guard let last = path.last else { return false }
        return separators.contains(last)
    }
}
