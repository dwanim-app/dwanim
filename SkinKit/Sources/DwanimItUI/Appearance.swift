import Observation
import SwiftUI

// MARK: - AppearanceTheme

/// The token-based colour vocabulary for the redesigned ("Cadence"-derived)
/// default player. A pure value type holding the nine theme tokens from the design
/// handoff — `accent, glow, glow2, bg1, bg2, panel, text, muted, lcd` — as SwiftUI
/// `Color`s, plus the fixed neutrals / hairlines the whole deck shares as static
/// constants.
///
/// ## Why a NEW type (not the existing `DwanimItTheme`)
/// `DwanimItTheme` is the APP-ICON's warm gold vocabulary and MUST stay untouched
/// (`AppIconView` renders the gold Dwennimmen mark from it). This `Appearance` layer
/// is the *player* theme: switching it (via `AppearanceStore`) retints the entire
/// running UI because every redesigned view reads its colours from here, while the
/// icon keeps its own gold gradient. The type is intentionally named
/// `Appearance`/`AppearanceTheme` — NOT "Skin" — to avoid clashing with the app's
/// existing `.wsz` classic-skin concept.
///
/// Every accent-driven surface (active toggles, the visualiser bars, links, the
/// "Add files…" link, the EQ On checkbox, the pop-up chevron chip, the drop overlay)
/// derives from `accent`, so a new theme retints the whole deck.
public struct AppearanceTheme: Identifiable, Equatable, Sendable {

    // MARK: Tokens

    /// The theme's display name (also its identity in the built-in list).
    public let name: String
    /// The accent that drives every active/interactive tint.
    public let accent: Color
    /// The primary desktop glow behind the panel (warm/accent-keyed radial).
    public let glow: Color
    /// The secondary desktop glow behind the panel (cooler radial).
    public let glow2: Color
    /// The top of the desktop backdrop's vertical gradient.
    public let bg1: Color
    /// The bottom of the desktop backdrop's vertical gradient.
    public let bg2: Color
    /// The translucent window/panel fill (has alpha; blurred by the material).
    public let panel: Color
    /// The primary text colour token.
    public let text: Color
    /// The muted/secondary text colour token.
    public let muted: Color
    /// The recessed "LCD" well fill for the visualiser (has alpha).
    public let lcd: Color

    public var id: String { name }

    public init(
        name: String,
        accent: Color,
        glow: Color,
        glow2: Color,
        bg1: Color,
        bg2: Color,
        panel: Color,
        text: Color,
        muted: Color,
        lcd: Color
    ) {
        self.name = name
        self.accent = accent
        self.glow = glow
        self.glow2 = glow2
        self.bg1 = bg1
        self.bg2 = bg2
        self.panel = panel
        self.text = text
        self.muted = muted
        self.lcd = lcd
    }

    // MARK: - Built-ins (exact tokens from the design handoff table)

    /// Graphite — the default theme.
    public static let graphite = AppearanceTheme(
        name: "Graphite",
        accent: Color(hex: 0x3aa8a0),
        glow: Color(rgba: 28, 120, 112, 0.42),
        glow2: Color(rgba: 96, 120, 150, 0.28),
        bg1: Color(hex: 0x12161a),
        bg2: Color(hex: 0x0a0c0d),
        panel: Color(rgba: 30, 31, 33, 0.72),
        text: Color(hex: 0xe8e8ea),
        muted: Color(hex: 0x8b8b90),
        lcd: Color(rgba: 0, 0, 0, 0.24)
    )

    /// Amber Deck — a warm amber alternate.
    public static let amberDeck = AppearanceTheme(
        name: "Amber Deck",
        accent: Color(hex: 0xe0a341),
        glow: Color(rgba: 154, 96, 26, 0.42),
        glow2: Color(rgba: 126, 84, 58, 0.26),
        bg1: Color(hex: 0x1a1613),
        bg2: Color(hex: 0x0c0a08),
        panel: Color(rgba: 39, 33, 29, 0.74),
        text: Color(hex: 0xefe8e0),
        muted: Color(hex: 0x99908a),
        lcd: Color(rgba: 0, 0, 0, 0.26)
    )

    /// Indigo Glass — a cool indigo alternate.
    public static let indigoGlass = AppearanceTheme(
        name: "Indigo Glass",
        accent: Color(hex: 0x8b8bf5),
        glow: Color(rgba: 72, 72, 196, 0.42),
        glow2: Color(rgba: 122, 112, 192, 0.28),
        bg1: Color(hex: 0x14151f),
        bg2: Color(hex: 0x08090f),
        panel: Color(rgba: 31, 32, 44, 0.74),
        text: Color(hex: 0xe9e9f2),
        muted: Color(hex: 0x8f8fa0),
        lcd: Color(rgba: 0, 0, 0, 0.26)
    )

    /// The ordered built-in themes (Graphite first / default).
    public static let builtIns: [AppearanceTheme] = [graphite, amberDeck, indigoGlass]

    // MARK: - Fixed neutrals (theme-independent, per the handoff)

    /// `#f2f2f4` — primary row / play-button glyph text.
    public static let primaryText = Color(hex: 0xf2f2f4)
    /// `#d2d2d6` — the window title text.
    public static let titleText = Color(hex: 0xd2d2d6)
    /// `#dcdce0` — the pop-up button's label.
    public static let buttonLabel = Color(hex: 0xdcdce0)
    /// `#c8c8cc` — idle transport side buttons.
    public static let idleTransport = Color(hex: 0xc8c8cc)
    /// `#a0a0a6` — idle Shuffle/Repeat/EQ toggle text.
    public static let idleToggle = Color(hex: 0xa0a0a6)
    /// `#8b8b90` — secondary text (times, header, footer, labels).
    public static let secondary = Color(hex: 0x8b8b90)
    /// `#96969b` — the now-playing artist line.
    public static let nowPlayingArtist = Color(hex: 0x96969b)
    /// `#77777c` — tertiary text (row index, ⌘O hint).
    public static let tertiary = Color(hex: 0x77777c)
    /// `#6f6f74` — the row's `×` remove glyph (idle).
    public static let removeGlyph = Color(hex: 0x6f6f74)
    /// `#b8b8bd` — a row title for a track with no file.
    public static let missingTitle = Color(hex: 0xb8b8bd)
    /// `#ff9a90` — the skin-parse error hint colour.
    public static let error = Color(hex: 0xff9a90)
    /// `#d6d6da` — the seek track's filled portion.
    public static let seekFill = Color(hex: 0xd6d6da)
    /// `#b9b9be` — the volume track's filled portion.
    public static let volumeFill = Color(hex: 0xb9b9be)
    /// `#f4f4f6` — the volume slider knob.
    public static let volumeKnob = Color(hex: 0xf4f4f6)

    // MARK: - EQ slider thumb gradients

    /// The white slider thumb gradient used when the EQ is on.
    public static let eqThumbOn = LinearGradient(
        colors: [Color(hex: 0xfbfbfc), Color(hex: 0xdcdce0)],
        startPoint: .top, endPoint: .bottom
    )
    /// The greyed slider thumb gradient used when the EQ is off.
    public static let eqThumbOff = LinearGradient(
        colors: [Color(hex: 0x9a9a9f), Color(hex: 0x7c7c81)],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: - Hairlines & edges (white overlays)

    /// `rgba(255,255,255,0.09)` — structural hairlines (section rules).
    public static let hairline = Color.white.opacity(0.09)
    /// `rgba(255,255,255,0.05)` — per-row rules.
    public static let rowHairline = Color.white.opacity(0.05)
    /// `rgba(255,255,255,0.16)` — the window's inset edge highlight.
    public static let windowEdge = Color.white.opacity(0.16)
    /// `rgba(255,255,255,0.18)` — button / control inset edges.
    public static let buttonEdge = Color.white.opacity(0.18)

    // MARK: - Common fills (white overlays)

    /// `rgba(255,255,255,0.05)` — row hover fill.
    public static let hoverFill = Color.white.opacity(0.05)
    /// `rgba(255,255,255,0.09)` — selected row / toggle-hover fill.
    public static let selectedFill = Color.white.opacity(0.09)
    /// `rgba(255,255,255,0.14)` — unfilled slider/track rails.
    public static let railFill = Color.white.opacity(0.14)
}

// MARK: - Open-skin file panel contract

/// A completion the App invokes with the picked skin file's TEXT + FILENAME — both
/// `nil` when the user cancelled the panel, or `(nil, filename)` when the file could
/// not be read. `@MainActor` because it drives the `@MainActor` `AppearanceStore`.
public typealias AppearanceFileCompletion = @MainActor (_ text: String?, _ filename: String?) -> Void

/// The App-tier "Open Skin…" action: present a file panel and, on OK, call the
/// completion with the picked file's text + filename (or `nil` on cancel). The App
/// owns the `NSOpenPanel` (so `DwanimItUI` stays AppKit-free); the Appearance popover
/// supplies the completion, which parses + applies the text via the `AppearanceStore`.
public typealias OpenAppearanceFileAction = @MainActor (@escaping AppearanceFileCompletion) -> Void

// MARK: - AppearanceStore

/// The observable holder of the current player theme. Exposes the ordered themes
/// (built-ins, then any user-loaded skins), a `select` that swaps the current theme
/// instantly, and a `load(text:filename:)` that parses a picked skin FILE into a new
/// theme — every view reads `store.current`, so a swap retints the whole deck on the
/// next render, and the popover reads `hint` / `isError` for its status line.
///
/// `@MainActor @Observable` mirrors `PlayerCore` / `PlayerViewModel`: the single
/// writer/reader is the SwiftUI view tree on the main actor, so no locking is
/// needed and property reads during `body` are tracked by Observation.
@MainActor
@Observable
public final class AppearanceStore {

    /// The theme currently applied to the deck.
    public private(set) var current: AppearanceTheme

    /// The ordered built-in themes shown first in the Appearance popover.
    public let builtIns: [AppearanceTheme]

    /// Themes loaded from a user skin file, in load order — listed AFTER the
    /// built-ins in the popover. A same-named reload replaces its earlier entry
    /// (see `load`) rather than duplicating.
    public private(set) var loaded: [AppearanceTheme] = []

    /// Whether the LAST `load` failed. The popover renders `hint` error-red when
    /// true; cleared by any successful `load` or `select`.
    public private(set) var isError = false

    /// The error hint shown while `isError` is true (set by a failed `load`).
    private var errorMessage = ""

    public init(current: AppearanceTheme = .graphite, builtIns: [AppearanceTheme] = AppearanceTheme.builtIns) {
        self.builtIns = builtIns
        self.current = current
    }

    /// The full ordered theme list for the popover: built-ins first, then the loaded
    /// skins, de-duplicated by name (a built-in wins a name tie) so every row keeps a
    /// unique `id` for `ForEach`.
    public var themes: [AppearanceTheme] {
        var seen = Set<String>()
        return (builtIns + loaded).filter { seen.insert($0.name).inserted }
    }

    /// The popover's status line. Normal (muted) — naming the current theme and what a
    /// skin file is — unless the last load failed, in which case it is the error hint.
    public var hint: String {
        isError
            ? errorMessage
            : "Current: \(current.name) — A skin is a .dwskin or .json file of colors."
    }

    /// Swap to the theme named `name` (a built-in OR a loaded skin), instantly. An
    /// unknown name is a guarded no-op (the current theme is kept). Clears any error.
    public func select(name: String) {
        guard let match = themes.first(where: { $0.name == name }) else { return }
        current = match
        isError = false
    }

    /// Swap directly to `theme`, instantly. Clears any error hint.
    public func select(_ theme: AppearanceTheme) {
        current = theme
        isError = false
    }

    /// Load a skin file's TEXT: parse it (JSON or `key: value` lines) and, on success,
    /// append the resolved theme (merged over Graphite) to the loaded list, select it,
    /// and clear the error. A same-named reload REPLACES its earlier entry rather than
    /// duplicating. On failure (empty / no recognised tokens) the current theme is
    /// left untouched and the error hint is set from the filename.
    public func load(text: String, filename: String) {
        switch AppearanceTheme.parse(text: text, filename: filename) {
        case .success(let theme):
            loaded.removeAll { $0.name == theme.name }
            loaded.append(theme)
            current = theme
            isError = false
        case .failure:
            errorMessage = "\"\(filename)\" isn't a readable skin. Needs keys like accent, bg1, panel."
            isError = true
        }
    }
}

// MARK: - Color hex / rgba helpers

extension Color {

    /// A fully-opaque sRGB colour from a `0xRRGGBB` literal.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8) & 0xff) / 255
        let b = Double(hex & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// An sRGB colour from 0–255 channels plus a 0–1 alpha (mirrors CSS `rgba`).
    init(rgba red: Double, _ green: Double, _ blue: Double, _ alpha: Double) {
        self.init(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
    }
}

// MARK: - Time formatting

/// Shared `m:ss` time formatting for the seek labels and the playlist rows, matching
/// the design's `fmt` helper (non-finite / negative reads as `0:00`).
enum CadenceTime {
    /// Format `seconds` as `m:ss`. A non-finite or negative value reads as `0:00`.
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return "\(minutes):" + (secs < 10 ? "0\(secs)" : "\(secs)")
    }
}
