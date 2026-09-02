import Foundation

// MARK: - WindowDragMath
//
// Pure math for the MANUAL title-bar drag of a shaped classic window. A shaped
// (non-rectangular) window drags ONLY from its title-bar strip — never from a
// transparent cut-out — by recording the grab point and moving the window frame
// as the cursor moves. Because the window is BORDERLESS, AppKit enforces none of
// the usual placement rules, so two are enforced here:
//   • TOP: the window's top edge never goes above the usable screen area (under
//     the menu bar) — macOS would otherwise let a borderless window slide its
//     title strip up under the menu bar, where it can no longer be grabbed;
//   • GRAB HANDLE: at least a title-strip's worth of the window stays on-screen
//     at the bottom and on both sides, so the window can never be dragged
//     somewhere it cannot be grabbed again.
//
// The "screen" is the UNION (bounding box) of every attached display's visible
// frame, gathered by the AppKit view from `NSScreen.screens`. Using the union —
// not `NSWindow.screen` — matters with a display arranged ABOVE the current one:
// `window.screen` only updates once the frame already intersects that display,
// which a single-screen top clamp forbids, so the window could never get there.
//
// Factored out of the AppKit view so the clamp is unit-testable without a window
// or a screen. Everything is in screen points, bottom-left origin.

public enum WindowDragMath {

    // MARK: - Rect

    /// A screen-space rect (bottom-left origin, points). A plain value so the
    /// math stays free of any graphics framework.
    public struct Rect: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var minX: Double { x }
        public var minY: Double { y }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    // MARK: - Union of screens

    /// The bounding box of `rects` (the usable area across every display), or
    /// `nil` when there are none (no screen attached — the caller then does not
    /// clamp at all).
    public static func union(of rects: [Rect]) -> Rect? {
        guard let first = rects.first else { return nil }
        var minX = first.minX, minY = first.minY
        var maxX = first.maxX, maxY = first.maxY
        for rect in rects.dropFirst() {
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Clamp

    /// Clamp a proposed window origin (bottom-left, screen points) so that:
    ///   • the window's TOP (`y + windowHeight`) does not exceed `allowedArea.maxY`;
    ///   • at least `grabStripHeight` of the window's top strip stays ABOVE
    ///     `allowedArea.minY` (bottom clamp);
    ///   • at least `grabStripHeight` of the window's width stays inside
    ///     `[allowedArea.minX, allowedArea.maxX]` (side clamps).
    /// When the area is shorter than the window the TOP rule wins (the menu-bar
    /// rule is the one that must hold). Each axis is clamped independently; a
    /// non-finite input on an axis passes that axis's proposed value through
    /// defensively (never trap), matching the project's finite-guard convention.
    public static func clampedOrigin(
        proposedX: Double,
        proposedY: Double,
        windowWidth: Double,
        windowHeight: Double,
        allowedArea: Rect,
        grabStripHeight: Double
    ) -> (x: Double, y: Double) {
        let x = clampedAxis(
            proposed: proposedX,
            lower: allowedArea.minX + grabStripHeight - windowWidth,
            upper: allowedArea.maxX - grabStripHeight
        )
        let y = clampedAxis(
            proposed: proposedY,
            lower: allowedArea.minY + grabStripHeight - windowHeight,
            upper: allowedArea.maxY - windowHeight
        )
        return (x, y)
    }

    /// `min(max(proposed, lower), upper)` — `upper` wins when the bounds cross —
    /// or `proposed` unchanged when any value is non-finite.
    private static func clampedAxis(proposed: Double, lower: Double, upper: Double) -> Double {
        guard proposed.isFinite, lower.isFinite, upper.isFinite else { return proposed }
        return min(max(proposed, lower), upper)
    }
}
