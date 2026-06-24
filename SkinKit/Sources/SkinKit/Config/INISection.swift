import Foundation

// MARK: - INISection

/// A minimal, fault-tolerant reader for the INI-like text configs of the classic
/// `.wsz` skin format (`pledit.txt`, `region.txt`).
///
/// It splits the document into `[Header]` sections and, within a section,
/// `Key=Value` pairs. The reader is intentionally forgiving:
/// - section headers and keys are matched case-insensitively;
/// - whitespace around the header brackets, the key, and the `=` is trimmed;
/// - any newline (CR, LF, or CRLF) separates logical lines;
/// - a `;` starts a comment: text from the first `;` to end-of-line is dropped,
///   covering both full-line `; comment` lines and inline `Key=Value ; comment`;
/// - blank lines and lines without an `=` are ignored;
/// - lines before the first section header belong to no section and are dropped;
/// - if a key repeats, the last assignment wins.
///
/// This is a small parsing primitive, not a general INI library — it covers only
/// what the skin configs need.
struct INISection {

    /// Key/value pairs of this section, keyed by **lowercased** key.
    private let values: [String: String]

    // MARK: - Lookup

    /// Returns the raw value for `key` (case-insensitive), or `nil` if absent.
    func value(for key: String) -> String? {
        values[key.lowercased()]
    }

    // MARK: - Parsing

    /// Extracts the section whose header equals `name` (case-insensitive) from
    /// `text`, or `nil` if no such header appears.
    static func named(_ name: String, in text: String) -> INISection? {
        let target = name.lowercased()
        var current: String?
        var pairs: [String: String] = [:]
        var found = false

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = stripComment(from: rawLine)
            if let header = header(of: line) {
                current = header
                if header == target { found = true }
                continue
            }
            guard current == target, let (key, value) = keyValue(of: line) else { continue }
            pairs[key] = value
        }

        return found ? INISection(values: pairs) : nil
    }

    // MARK: - Private

    /// Drops a `;` comment (from the first `;` to end-of-line) and trims
    /// surrounding whitespace, returning the bare content of the line.
    private static func stripComment(from line: Substring) -> String {
        let content = line.prefix { $0 != ";" }
        return content.trimmingCharacters(in: .whitespaces)
    }

    /// Returns the lowercased header name of a `[Header]` line, or `nil`.
    private static func header(of line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]"), line.count >= 2 else { return nil }
        let inner = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return inner.lowercased()
    }

    /// Splits a `Key = Value` line into a lowercased key and trimmed value, or
    /// `nil` if there is no `=`.
    private static func keyValue(of line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }
}
