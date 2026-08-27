import Foundation
import SwiftUI

// MARK: - AppearanceParseError

/// Why parsing a picked skin file into an `AppearanceTheme` failed. Both cases map
/// to the SAME user-facing error hint (the file "isn't a readable skin"); they are
/// distinguished only so tests can assert the specific reason.
public enum AppearanceParseError: Error, Equatable, Sendable {
    /// The text had no usable content at all (empty / whitespace only).
    case empty
    /// The text parsed (as JSON or `key: value` lines) but yielded NONE of the nine
    /// recognised colour tokens with a parseable value — so there is nothing to apply.
    case noRecognizedKeys
}

// MARK: - AppearanceTheme.parse

public extension AppearanceTheme {

    /// The nine recognised colour-token keys (lower-cased). `name` is handled
    /// separately (it sets the display name, not a colour), and every other key in
    /// the file is ignored.
    static let tokenKeys: Set<String> = [
        "accent", "glow", "glow2", "bg1", "bg2", "panel", "text", "muted", "lcd"
    ]

    /// Parse a picked skin file's TEXT into a resolved `AppearanceTheme`, deterministic
    /// and I/O-free.
    ///
    /// Accepted forms (tried in order):
    ///   1. JSON with the tokens at the top level — `{ "accent": "#3aa8a0", … }`.
    ///   2. JSON nesting the tokens under `"colors"` — `{ "colors": { … } }`.
    ///   3. JSON nesting the tokens under `"vars"` — `{ "vars": { … } }`.
    ///   4. A plain-text line format — one `key: value` or `key = value` per line.
    /// If the text parses as JSON at all, ONLY the JSON path is used (a valid JSON
    /// object with no recognised keys is a failure, not a fall-through to lines).
    ///
    /// Recognised keys are the nine tokens plus an optional `name`; every other key is
    /// ignored. Colour values may be hex (`#rgb` / `#rrggbb` / `#rrggbbaa`) or
    /// `rgb(…)` / `rgba(…)`. The recognised overrides are MERGED over the Graphite
    /// defaults, so a partial file keeps Graphite's values for the tokens it omits.
    /// The display name is the explicit `name`, else the filename's stem.
    ///
    /// - Returns: `.success` with the resolved theme, or `.failure` when the text is
    ///   empty or yields zero recognised tokens.
    static func parse(text: String, filename: String) -> Result<AppearanceTheme, AppearanceParseError> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.empty)
        }

        // Gather candidate fields: JSON first (any of the three shapes); if the text
        // is not JSON at all, fall back to the `key: value` line format.
        let fields = AppearanceParser.jsonFields(from: text) ?? AppearanceParser.lineFields(from: text)

        // Keep only recognised tokens whose value parses to a colour.
        var overrides: [String: Color] = [:]
        for (key, value) in fields.colors where tokenKeys.contains(key) {
            if let color = Color(appearanceToken: value) {
                overrides[key] = color
            }
        }
        guard !overrides.isEmpty else { return .failure(.noRecognizedKeys) }

        // Name: an explicit non-empty `name`, else the filename stem.
        let explicit = fields.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (explicit?.isEmpty == false) ? explicit! : AppearanceParser.stem(from: filename)

        // Merge the overrides over the Graphite defaults.
        let base = AppearanceTheme.graphite
        let theme = AppearanceTheme(
            name: name,
            accent: overrides["accent"] ?? base.accent,
            glow: overrides["glow"] ?? base.glow,
            glow2: overrides["glow2"] ?? base.glow2,
            bg1: overrides["bg1"] ?? base.bg1,
            bg2: overrides["bg2"] ?? base.bg2,
            panel: overrides["panel"] ?? base.panel,
            text: overrides["text"] ?? base.text,
            muted: overrides["muted"] ?? base.muted,
            lcd: overrides["lcd"] ?? base.lcd
        )
        return .success(theme)
    }
}

// MARK: - AppearanceParser

/// The pure text→fields machinery behind `AppearanceTheme.parse`. All helpers are
/// deterministic and touch no I/O and no AppKit — `DwanimItUI` stays a pure
/// SwiftUI + PlayerCore module (the file panel that supplies the text lives in the
/// App target).
enum AppearanceParser {

    /// The raw, un-typed fields lifted from a file: the optional display `name` and
    /// the candidate colour strings keyed by their LOWER-CASED token name (still to
    /// be filtered to the recognised nine and colour-parsed by `parse`).
    struct RawFields {
        var name: String?
        var colors: [String: String]
    }

    /// Lift fields from JSON, honouring the three accepted shapes: top-level tokens,
    /// `{ "colors": { … } }`, or `{ "vars": { … } }`. Returns `nil` when the text is
    /// not a JSON object at all (so `parse` falls back to the line format); returns an
    /// EMPTY-colour `RawFields` when it IS a JSON object but carries no string values
    /// (a valid-JSON-but-no-tokens file is a failure, never a line-format retry).
    static func jsonFields(from text: String) -> RawFields? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let top = object as? [String: Any] else {
            return nil
        }

        // The token source: prefer a nested "colors" dict, then "vars", else the top
        // level itself.
        let source: [String: Any]
        if let colors = top["colors"] as? [String: Any] {
            source = colors
        } else if let vars = top["vars"] as? [String: Any] {
            source = vars
        } else {
            source = top
        }

        var colors: [String: String] = [:]
        for (key, value) in source {
            let lower = key.lowercased()
            guard lower != "name" else { continue }
            // Only string values are colour candidates; arrays / numbers / nested
            // objects are ignored (they cannot be a hex / rgba colour string).
            if let string = value as? String {
                colors[lower] = string
            }
        }

        // `name` may sit at the top level (a sibling of the tokens / "colors") or,
        // leniently, inside the chosen source dict.
        let name = (top["name"] as? String) ?? (source["name"] as? String)
        return RawFields(name: name, colors: colors)
    }

    /// Lift fields from the plain-text line format: one `key: value` or `key = value`
    /// per line, split on the FIRST `:` or `=` (so an rgba value's commas / a hex
    /// value's `#` stay in the value). Blank lines and lines without a separator are
    /// skipped, so `#`- or `//`-style comment lines fall away on their own.
    static func lineFields(from text: String) -> RawFields {
        var colors: [String: String] = [:]
        var name: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  let sep = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else { continue }
            let key = line[line.startIndex..<sep].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if key == "name" {
                name = value
            } else {
                colors[key] = value
            }
        }
        return RawFields(name: name, colors: colors)
    }

    /// The filename's stem (its last path component with the extension dropped) — the
    /// display-name fallback when the file carries no explicit `name`.
    static func stem(from filename: String) -> String {
        let last = (filename as NSString).lastPathComponent
        let dropped = (last as NSString).deletingPathExtension
        return dropped.isEmpty ? last : dropped
    }
}

// MARK: - Colour token parsing

extension Color {

    /// Parse a CSS-ish colour token — `#rgb` / `#rrggbb` / `#rrggbbaa`, or
    /// `rgb(r,g,b)` / `rgba(r,g,b,a)` — reusing the module's `Color(hex:)` /
    /// `Color(rgba:)` channel model. `nil` when the string is not a recognised
    /// colour form (so the token is dropped rather than applied wrong).
    init?(appearanceToken raw: String) {
        let string = raw.trimmingCharacters(in: .whitespaces)
        guard !string.isEmpty else { return nil }

        let channels: (r: Double, g: Double, b: Double, a: Double)?
        if string.hasPrefix("#") {
            channels = AppearanceColorParsing.hexChannels(String(string.dropFirst()))
        } else {
            channels = AppearanceColorParsing.rgbaChannels(string)
        }
        guard let c = channels else { return nil }
        self.init(rgba: c.r, c.g, c.b, c.a)
    }
}

/// Pure hex / rgba string → channel decoding for `Color(appearanceToken:)`. Channels
/// are returned as 0–255 red/green/blue plus a 0–1 alpha (the shape `Color(rgba:)`
/// consumes). Any malformed digit / arity yields `nil`.
enum AppearanceColorParsing {

    /// Decode a hex body (the part AFTER `#`): 3 (`rgb`), 6 (`rrggbb`), or 8
    /// (`rrggbbaa`) hex digits. `nil` for any other length or a non-hex digit.
    static func hexChannels(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        let chars = Array(hex)
        switch chars.count {
        case 3:
            guard let r = nibble(chars[0]), let g = nibble(chars[1]), let b = nibble(chars[2]) else { return nil }
            // Each nibble is doubled (`f` → `ff` = 255) so #rgb expands to #rrggbb.
            return (Double(r * 17), Double(g * 17), Double(b * 17), 1)
        case 6:
            guard let r = byte(chars, 0), let g = byte(chars, 2), let b = byte(chars, 4) else { return nil }
            return (r, g, b, 1)
        case 8:
            guard let r = byte(chars, 0), let g = byte(chars, 2), let b = byte(chars, 4), let a = byte(chars, 6) else { return nil }
            return (r, g, b, a / 255)
        default:
            return nil
        }
    }

    /// Decode `rgb(r,g,b)` or `rgba(r,g,b,a)` — r/g/b are 0–255, a is 0–1 (defaulting
    /// to 1 for the 3-component `rgb(…)`). `nil` for a wrong component count or a
    /// non-numeric component. The `rgb`/`rgba` prefix and casing are not required
    /// here (the caller gates on `#`); any `name(a,b,c[,d])` numeric tuple decodes.
    static func rgbaChannels(_ string: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard let open = string.firstIndex(of: "("),
              let close = string.lastIndex(of: ")"),
              open < close else { return nil }
        let inner = string[string.index(after: open)..<close]
        let parts = inner.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        guard let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) else { return nil }
        if parts.count == 4 {
            guard let a = Double(parts[3]) else { return nil }
            return (r, g, b, a)
        }
        return (r, g, b, 1)
    }

    /// One hex digit (0–15), or `nil` if not a hex digit.
    private static func nibble(_ character: Character) -> Int? {
        Int(String(character), radix: 16)
    }

    /// The byte at `index` (two hex digits), or `nil` if out of range / not hex.
    private static func byte(_ chars: [Character], _ index: Int) -> Double? {
        guard index + 1 < chars.count else { return nil }
        return UInt8(String(chars[index...index + 1]), radix: 16).map(Double.init)
    }
}
