import AppKit
import CoreGraphics
import Foundation

// MARK: - ScaledImageView
//
// The reusable, scaled, NON-flipped content view shared by every interactive
// skin window. It draws a swappable `CGImage` with nearest-neighbor scaling and
// forwards raw view-space mouse / scroll events to its controller via optional
// closures. The view itself carries NO coordinate math: it hands the controller
// the raw point (plus the view height) so the controller can map it to skin
// space via the pure `ControlHitTest`.
//
// This consolidates the three byte-identical "draw a swappable image + forward
// events" views the harness used to carry separately (the main-window
// interactive view, the EQ view, and the playlist view's view-half). Each
// concrete window wires only the closures it needs:
//   * main window:  onMouseDown (clickCount ignored) + onMouseUp
//   * EQ window:     onMouseDown (isDown via the down hook) + onMouseDragged + onMouseUp
//   * playlist:      onMouseDown (single vs double via clickCount) + onScroll + overlayDraw
//
// Coordinate note: this is a default (NON-flipped) `NSView`, so an
// `NSEvent.locationInWindow` converted into this view has origin at the
// BOTTOM-left with y increasing UPWARD. The composed skin image is top-left
// origin (y down). The forwarded view-space point (plus the view height) is
// mapped back to skin space (undo scale + y-flip) by the pure
// `ControlHitTest`, which the controller drives.

open class ScaledImageView: NSView {
    private var image: CGImage

    // MARK: Event hooks

    /// Called on mouse-DOWN with the click point in this view's coordinate space
    /// (non-flipped, bottom-left origin, scaled points), the view's height, and
    /// the event's `clickCount` (so a window that distinguishes single vs double
    /// click can route on it; windows that don't simply ignore it).
    public var onMouseDown: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double, _ clickCount: Int) -> Void)?

    /// Called on each mouse-DRAG with the same view-space point + height. Only the
    /// EQ window wires this (to drag a slider continuously); others leave it nil
    /// so a drag is inert, exactly as before.
    public var onMouseDragged: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double) -> Void)?

    /// Called on mouse-UP. Carries no point — the lift only ends a gesture.
    public var onMouseUp: (() -> Void)?

    /// Called on a wheel scroll with the RAW (fractional) signed `scrollingDeltaY`.
    /// A zero delta is filtered out here (no-op), matching the playlist view's
    /// former guard. Only the playlist window wires this.
    public var onScroll: ((_ rawDeltaY: Double) -> Void)?

    /// Optional overlay drawn AFTER the scaled image, in this view's (bottom-left
    /// origin) context. Used by the playlist window to draw its CoreText track
    /// list on top of the composed frame bitmap. Left nil for windows whose entire
    /// frame is already baked into `image`.
    public var overlayDraw: ((_ context: CGContext, _ bounds: NSRect) -> Void)?

    public init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Image

    /// Swap the displayed image and request a redraw. Same pixel size each tick in
    /// the common case, so the frame is unchanged; a resize swaps in a different
    /// size and updates the frame separately.
    public func update(image: CGImage) {
        self.image = image
        needsDisplay = true
    }

    // MARK: Draw

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
        overlayDraw?(context, bounds)
    }

    // MARK: Events

    public override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        onMouseDown?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height), event.clickCount)
    }

    public override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        onMouseDragged?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height))
    }

    public override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }

    public override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        onScroll?(Double(dy))
    }
}
