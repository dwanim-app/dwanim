import Foundation

// MARK: - SkinRegion

/// The custom window shape declared by `region.txt` in the classic `.wsz` skin
/// format: a set of polygons that together define the non-rectangular outline of
/// a window.
///
/// Coordinates follow the same convention as the bitmaps: a top-left origin with
/// `x` growing rightward and `y` downward, in whole pixels. This type currently
/// models only the main window's `Normal` shape.
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

    /// The polygons forming the main window's `Normal` shape, in declared order.
    public let polygons: [Polygon]

    public init(polygons: [Polygon]) {
        self.polygons = polygons
    }
}
