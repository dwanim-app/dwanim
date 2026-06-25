import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The playlist window's live content view (one primary type per file, §12). It
// draws the scaled frame bitmap + the visible track list, and forwards mouse
// clicks / double-clicks / wheel scrolls to its controller.
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier (no
// logic change) so BOTH the dev harness AND the real app target can host it.

// MARK: - Live content view

/// The playlist window's content view: draws the scaled frame bitmap (nearest
/// neighbor) and the visible track list (CoreText), and forwards mouse clicks +
/// wheel scrolls to the controller. NON-flipped (bottom-left origin); the text
/// drawing flips into this space itself.
///
/// It builds on the shared `SkinAppKit.ScaledImageView`, which already draws the
/// swappable frame bitmap and forwards mouse / scroll events. The UNIQUE playlist
/// behavior is wired through that base's hooks:
///   * the CoreText track-list overlay -> `overlayDraw`
///   * single-vs-double-click routing  -> `onMouseDown` (on `clickCount`)
///   * raw wheel delta                  -> `onScroll`
public final class PlaylistContentView: ScaledImageView {
    private let skin: Skin
    private let scale: Int
    /// The composed-frame UNSCALED dimensions. Mutable so a drag-resize can swap in
    /// a freshly composed frame at the new size and the text layout follows it.
    private var skinWidth: Int
    private var skinHeight: Int

    /// Pulled fresh each redraw so the list reflects the live core.
    public var tracksProvider: () -> [Track] = { [] }
    public var currentIndexProvider: () -> Int? = { nil }
    public var selectedIndexProvider: () -> Int? = { nil }
    public var scrollRowProvider: () -> Int = { 0 }

    public init(frameImage: CGImage, skin: Skin, scale: Int, skinWidth: Int, skinHeight: Int, frame: NSRect) {
        self.skin = skin
        self.scale = scale
        self.skinWidth = skinWidth
        self.skinHeight = skinHeight
        super.init(image: frameImage, frame: frame)

        // Draw the visible track list ON TOP of the composed frame bitmap, in the
        // same (bottom-left origin) context; the text drawing flips into skin
        // space itself.
        overlayDraw = { [weak self] context, _ in
            guard let self else { return }
            drawPlaylistTrackList(
                in: context,
                skin: self.skin,
                tracks: self.tracksProvider(),
                currentIndex: self.currentIndexProvider(),
                selectedIndex: self.selectedIndexProvider(),
                scrollRow: self.scrollRowProvider(),
                skinWidth: self.skinWidth,
                skinHeight: self.skinHeight,
                scale: self.scale
            )
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Wire the mouse routing once the controller has set its click/scroll hooks.
    /// A double click selects on the first down and PLAYS on the second; both
    /// points are forwarded so the controller can map each to a row via the pure
    /// helper. The view carries no coordinate math.
    public func routeClicks(
        onSingleClick: @escaping (Double, Double, Double) -> Void,
        onDoubleClick: @escaping (Double, Double, Double) -> Void
    ) {
        onMouseDown = { x, y, h, clickCount in
            if clickCount >= 2 {
                onDoubleClick(x, y, h)
            } else {
                onSingleClick(x, y, h)
            }
        }
    }

    /// Swap in a freshly composed frame bitmap + its new unscaled dimensions after
    /// a drag-resize, then redraw. The controller composes the new frame (clamped
    /// to the composer minimum) and calls this so the chrome bitmap and the text
    /// layout share the same size — they cannot drift.
    public func updateFrame(image: CGImage, skinWidth: Int, skinHeight: Int) {
        self.skinWidth = skinWidth
        self.skinHeight = skinHeight
        update(image: image)
    }
}
