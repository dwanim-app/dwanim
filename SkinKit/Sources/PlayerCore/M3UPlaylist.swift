import Foundation

// MARK: - M3UPlaylist

/// A PURE `.m3u` playlist reader/writer (`Foundation`-only, no I/O): the host
/// layer reads/writes the file (inside its security scope) and hands the TEXT
/// here, so both directions are unit-testable without touching the disk.
///
/// ## Format choices (documented)
/// - `serialize` writes the standard `#EXTM3U` header, then one ABSOLUTE file
///   path per line (LF line endings, trailing newline). No `#EXTINF` metadata
///   is emitted — the titles are re-derived from the filenames on load, exactly
///   as the open-panel path does.
/// - `parse` is TOLERANT: it accepts CRLF or LF, skips blank lines and `#`
///   comment/directive lines (including `#EXTM3U` / `#EXTINF`), trims
///   surrounding whitespace, and resolves each remaining line to a file URL —
///   either a `file://` URL line or a plain absolute path.
public enum M3UPlaylist {

    /// Parse `.m3u` text into the file URLs it lists, in order. Tolerant of
    /// CRLF, blank lines, and `#`-prefixed comment/directive lines.
    public static func parse(_ text: String) -> [URL] {
        text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line in
                if line.lowercased().hasPrefix("file://") {
                    // A percent-encoded file URL line; drop it if malformed.
                    return URL(string: line).flatMap { $0.isFileURL ? $0 : nil }
                }
                return URL(fileURLWithPath: line)
            }
    }

    /// Serialize `urls` as `.m3u` text: the `#EXTM3U` header, then one absolute
    /// file path per line, with a trailing newline. An empty list yields just
    /// the header line.
    public static func serialize(_ urls: [URL]) -> String {
        (["#EXTM3U"] + urls.map { $0.path }).joined(separator: "\n") + "\n"
    }
}
