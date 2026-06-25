import AppKit
import CoreGraphics
import Foundation

// The EQ window's live content view (one primary type per file, §12). It draws
// the scaled, composed EQ-face bitmap (nearest neighbor) and forwards mouse-down
// AND mouse-drag (and mouse-up, for explicit gesture lifecycle) to its
// controller. Split out of `EQMode.swift` — no logic change.

// MARK: - Live EQ content view

/// A content view that draws a `CGImage` with nearest-neighbor scaling (like the
/// main-window interactive view) but forwards mouse-down AND mouse-drag to a
/// controller so a slider can be dragged continuously.
///
/// Coordinate note: this is a default (NON-flipped) `NSView`, origin bottom-left,
/// y increasing UPWARD. The composed EQ image is top-left origin (y down). The
/// view forwards the raw view-space point (plus its own height); mapping it back
/// to skin space (undo scale + y-flip) is the pure `ControlHitTest.skinPoint(...)`
/// the controller drives — the view carries no coordinate math.
final class EQSkinView: NSView {
    private var image: CGImage

    /// Called on mouse-down AND on each mouse-drag, with the point in this view's
    /// coordinate space (non-flipped, bottom-left origin, scaled points) plus the
    /// view's height, so the controller can map it to skin space.
    var onMousePoint: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double, _ isDown: Bool) -> Void)?

    /// Called on mouse-UP so the controller can end the gesture (clear the latched
    /// dragging slider). Carries no point — the lift only ends the drag.
    var onMouseUp: (() -> Void)?

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Swap the displayed image and request a redraw. Same pixel size each tick.
    func update(image: CGImage) {
        self.image = image
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        forward(event, isDown: true)
    }

    override func mouseDragged(with event: NSEvent) {
        forward(event, isDown: false)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }

    private func forward(_ event: NSEvent, isDown: Bool) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        onMousePoint?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height), isDown)
    }
}
