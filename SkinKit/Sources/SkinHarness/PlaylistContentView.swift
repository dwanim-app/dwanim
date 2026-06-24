import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The playlist window's live content view (one primary type per file, §12). It
// draws the scaled frame bitmap + the visible track list, and forwards mouse
// clicks / double-clicks / wheel scrolls to its controller. Split out of
// `PlaylistView.swift`.

// MARK: - Live content view

/// The playlist window's content view: draws the scaled frame bitmap (nearest
/// neighbor) and the visible track list (CoreText), and forwards mouse clicks +
/// wheel scrolls to the controller. NON-flipped (bottom-left origin), like
/// `SkinImageView`; the text drawing flips into this space itself.
final class PlaylistContentView: NSView {
    private var frameImage: CGImage
    private let skin: Skin
    private let scale: Int
    private let skinWidth: Int
    private let skinHeight: Int

    /// Pulled fresh each redraw so the list reflects the live core.
    var tracksProvider: () -> [Track] = { [] }
    var currentIndexProvider: () -> Int? = { nil }
    var selectedIndexProvider: () -> Int? = { nil }
    var scrollRowProvider: () -> Int = { 0 }
    /// Called on a wheel scroll with the RAW (fractional) scroll delta; the
    /// controller accumulates it into a residual and emits whole-row steps so a
    /// trackpad/momentum stream does not over-scroll.
    var onScroll: ((_ rawDeltaY: Double) -> Void)?
    /// Called on a SINGLE click with the click point in this view's coordinate
    /// space (non-flipped, bottom-left origin, scaled points) plus the view height,
    /// so the controller can map it to an interior row. A second click in quick
    /// succession (clickCount == 2) is reported via `onDoubleClick` instead.
    var onSingleClick: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double) -> Void)?
    /// Called on a DOUBLE click with the same view-space point + height.
    var onDoubleClick: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double) -> Void)?

    init(frameImage: CGImage, skin: Skin, scale: Int, skinWidth: Int, skinHeight: Int, frame: NSRect) {
        self.frameImage = frameImage
        self.skin = skin
        self.scale = scale
        self.skinWidth = skinWidth
        self.skinHeight = skinHeight
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(frameImage, in: bounds)

        drawPlaylistTrackList(
            in: context,
            skin: skin,
            tracks: tracksProvider(),
            currentIndex: currentIndexProvider(),
            selectedIndex: selectedIndexProvider(),
            scrollRow: scrollRowProvider(),
            skinWidth: skinWidth,
            skinHeight: skinHeight,
            scale: scale
        )
    }

    override func mouseDown(with event: NSEvent) {
        // Route to single- vs double-click. A double click selects on the first
        // down and PLAYS on the second; we forward both points so the controller
        // can map each to a row via the pure helper. The view carries no
        // coordinate math (mirrors `InteractiveSkinView`).
        let viewPoint = convert(event.locationInWindow, from: nil)
        let x = Double(viewPoint.x)
        let y = Double(viewPoint.y)
        let h = Double(bounds.height)
        if event.clickCount >= 2 {
            onDoubleClick?(x, y, h)
        } else {
            onSingleClick?(x, y, h)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        // Forward the RAW signed delta; the controller accumulates fractional
        // trackpad/momentum deltas into a residual and only emits a whole-row step
        // when it crosses one rowHeight (the scroll-cadence fix). A zero delta is
        // a no-op.
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        onScroll?(Double(dy))
    }
}
