import Foundation

// MARK: - SkinRegion

/// The custom window shape declared by `region.txt` in the classic `.wsz` skin
/// format: a set of polygons that together define the non-rectangular outline of
/// a window.
///
/// Coordinates follow the same convention as the bitmaps: a top-left origin with
/// `x` growing rightward and `y` downward, in whole pixels. One `SkinRegion` is
/// ONE window's shape (one `[Section]` of `region.txt`); `SkinRegionSet` groups
/// the four sections a file can declare.
public struct SkinRegion: Sendable, Equatable {

    // MARK: - Point

    /// A single vertex in window-pixel coordinates.
    public struct Point: Sendable, Equatable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    // MARK: - Polygon

    /// A closed polygon described by its ordered vertices.
    public struct Polygon: Sendable, Equatable {
        public let points: [Point]
        public init(points: [Point]) {
            self.points = points
        }
    }

    /// The polygons forming this window's shape, in declared order.
    public let polygons: [Polygon]

    public init(polygons: [Polygon]) {
        self.polygons = polygons
    }

    /// `true` when no polygon can enclose an area (empty, or every polygon has
    /// fewer than 3 vertices). Such a region declares no usable shape, so the
    /// window stays rectangular. Callers normalize an empty region to `nil`
    /// through this predicate.
    public var isEmpty: Bool {
        !polygons.contains { $0.points.count >= 3 }
    }
}

// MARK: - SkinRegionSet

/// The four window shapes a `region.txt` can declare, one per section:
/// `[Normal]` (main window), `[Equalizer]` (EQ window), `[WindowShade]`
/// (collapsed main window) and `[EqualizerWS]` (collapsed EQ window).
///
/// The `.normal` and `.equalizer` shapes drive real windows and are applied;
/// `.windowShade` / `.equalizerWS` describe the collapsed "windowshade" (roll-up)
/// mode, which is NOT implemented, so they are PARSED AND STORED here for a later
/// increment but never applied. A section absent from the file yields an empty
/// `SkinRegion` (no polygons → rectangular), never `nil`, so callers branch on
/// `SkinRegion.isEmpty` uniformly.
///
/// Coordinate space, top-left origin, unscaled pixels:
/// - `normal` / `equalizer` are on the full window canvas — the sizes are the
///   layouts' (`MainWindowLayout.windowWidth/Height`,
///   `EQWindowLayout.windowWidth/Height`), the single source of those numbers;
/// - `windowShade` / `equalizerWS` are on the collapsed strip, whose height is
///   the classic 14 (NOT 16) — encoded in `windowShadeHeight` for the future
///   windowshade renderer.
public struct SkinRegionSet: Sendable, Equatable {
    /// The `[Normal]` main-window shape.
    public let normal: SkinRegion
    /// The `[Equalizer]` EQ-window shape.
    public let equalizer: SkinRegion
    /// The `[WindowShade]` collapsed-main shape (parsed + stored; not applied).
    public let windowShade: SkinRegion
    /// The `[EqualizerWS]` collapsed-EQ shape (parsed + stored; not applied).
    public let equalizerWS: SkinRegion

    /// The classic collapsed (windowshade) strip height, in unscaled pixels. The
    /// shade mode is 14 tall (not the 16 some references cite); recorded for the
    /// future windowshade renderer that will consume `windowShade`/`equalizerWS`.
    public static let windowShadeHeight = 14

    public init(
        normal: SkinRegion,
        equalizer: SkinRegion,
        windowShade: SkinRegion,
        equalizerWS: SkinRegion
    ) {
        self.normal = normal
        self.equalizer = equalizer
        self.windowShade = windowShade
        self.equalizerWS = equalizerWS
    }
}
