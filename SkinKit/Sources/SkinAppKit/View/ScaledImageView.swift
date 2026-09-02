import AppKit
import CoreGraphics
import Foundation
import SkinRender

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

    /// While a shaped-window MANUAL drag is in progress, the grab point in WINDOW
    /// coordinates (recorded at mouse-down). `nil` when no manual drag is active.
    /// Its presence is the gesture latch: `mouseDragged` / `mouseUp` route to the
    /// window move instead of the controller while it is set.
    private var manualDragAnchorInWindow: NSPoint?

    // MARK: Event hooks

    /// Called on mouse-DOWN with the click point in this view's coordinate space
    /// (non-flipped, bottom-left origin, scaled points), the view's height, the
    /// event's `clickCount` (so a window that distinguishes single vs double
    /// click can route on it; windows that don't simply ignore it), and the
    /// modifier keys held (extracted into the plain `ClickModifiers` value here
    /// so controllers stay `NSEvent`-free; the playlist window's cmd-click
    /// multi-select reads it, other windows ignore it).
    public var onMouseDown: ((
        _ viewX: Double, _ viewY: Double, _ viewHeight: Double,
        _ clickCount: Int, _ modifiers: ClickModifiers
    ) -> Void)?

    /// Asked FIRST on a mouse-down, with the same view-space point + height as
    /// `onMouseDown`: return `true` when the press should MOVE THE WINDOW (the
    /// skin's title-bar drag strip) instead of being routed as a click. The view
    /// then hands the gesture to `NSWindow.performDrag(with:)` and forwards
    /// NOTHING — the raw `NSEvent` never leaves the view, so controllers stay
    /// NSEvent-free and unit-testable. The predicate must return `false` for
    /// title-bar BUTTON rects (close / minimize) so buttons win over drag. `nil`
    /// (the default) means the view never drags the window.
    public var shouldDragWindow: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double) -> Bool)?

    /// SHAPED-WINDOW manual drag gate. Asked FIRST on a mouse-down (before
    /// `shouldDragWindow`), with the same view-space point + height: return `true`
    /// when the press should MOVE THE WINDOW by a MANUAL drag — the view records the
    /// grab point and, on each subsequent drag, repositions the window frame,
    /// CLAMPING it to the union of all screens' visible frames (`WindowDragMath`:
    /// top under the menu bar, and a grab strip always left on-screen). The whole
    /// gesture is consumed: no click / slider callback fires, and `mouseDragged` /
    /// `mouseUp` during the drag do not reach the controller. A SHAPED window wires
    /// THIS (so its drag is confined to the title-bar strip and can never start in
    /// a transparent cut-out); an UNSHAPED window leaves it `nil` and keeps its
    /// existing `shouldDragWindow` (`performDrag`) path unchanged. The predicate must
    /// return `false` for title-bar BUTTON rects so buttons win over drag.
    public var shouldManuallyDragWindow: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double) -> Bool)?

    /// Height, in POINTS, of the window's title-bar drag strip. The manual drag
    /// keeps at least this much of the window on-screen at the bottom and sides
    /// (`WindowDragMath.clampedOrigin`), so a shaped window always leaves a grab
    /// handle reachable. The controller sets it from its layout's strip height
    /// times the presentation scale; the default is the canonical 14px strip at 1x.
    public var manualDragGrabStripHeight: Double = 14

    /// SHAPED-WINDOW click-through. When set (a shaped window), a point for which
    /// this returns `false` is OUTSIDE the region silhouette (a transparent
    /// cut-out): `hitTest(_:)` returns `nil` there so the click passes THROUGH
    /// instead of being caught by the window. When `nil` (an unshaped window)
    /// `hitTest` is entirely normal — no regression. Given the view-space point
    /// (bottom-left origin, scaled points) and the view height.
    public var regionContainsPoint: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double) -> Bool)?

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

    /// Optional file-URL DROP hook. When a host (the real app) sets this, the view
    /// registers for `.fileURL` dragging and, on a drop, hands the extracted
    /// `[URL]` to this closure (the app classifies + opens them — a `.wsz` skin, one
    /// or more audio files, or a mix). It is left `nil` by the HARNESS, which never
    /// drops files: registration is keyed off this hook being set (see `didSet`),
    /// so a view with no `onFileDrop` registers for NO dragged types and behaves
    /// EXACTLY as before (no `draggingEntered` / `performDragOperation` is ever
    /// reached because the view advertises no accepted types). This keeps the
    /// harness path byte-identical.
    public var onFileDrop: (([URL]) -> Void)? {
        didSet {
            // Register only when a hook is actually present, and unregister when it
            // is cleared, so the harness (which never sets this) advertises no
            // dragged types and its drag behavior is unchanged.
            if onFileDrop != nil {
                registerForDraggedTypes([.fileURL])
            } else {
                unregisterDraggedTypes()
            }
        }
    }

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

    /// Draws the bitmap into the view's bounds with interpolation OFF. The bitmap
    /// is pre-scaled by an INTEGER nearest-neighbor factor (`PresentationScale
    /// .bitmapScale`), and the bounds are the skin size times the PRESENTATION
    /// scale in points. For an integer presentation scale the two coincide (the
    /// historical 1:1-in-points draw). For the fractional 1.5 on a 2x backing,
    /// bounds(points) x backingScaleFactor == bitmap pixels (275 x 1.5 x 2 ==
    /// 275 x 3), so this draw is a 1:1 device-pixel copy — no resampling, and
    /// `.none` interpolation guarantees no smoothing on any residual mismatch
    /// (e.g. a 1x display, where 3 bitmap pixels cover 1.5 device pixels).
    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
        overlayDraw?(context, bounds)
    }

    // MARK: Events

    /// CLICK-THROUGH: act on the first click even when this window is not key.
    /// NSView defaults to `false`, which made the first press on a background
    /// classic window be swallowed by window activation — e.g. with the EQ window
    /// just opened (and key), the main window's EQ button needed TWO presses to
    /// toggle the window closed (user-reported). The real classic player acts
    /// immediately, and every control here is a safe, single-shot media action.
    open override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// CLICK-THROUGH for a shaped window: a point OUTSIDE the region silhouette (a
    /// transparent cut-out) returns `nil` so the click passes through to whatever is
    /// behind, instead of being caught by this opaque view. Inside the region — and
    /// for an UNSHAPED window (`regionContainsPoint == nil`) — hit-testing is normal,
    /// so there is no regression for the ~90% of skins with no active region.
    ///
    /// `point` arrives in the SUPERVIEW's coordinate system; it is converted into
    /// this view's (bottom-left origin, scaled) space before the region test, then
    /// mapped to skin space by the controller's `regionContainsPoint` closure.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard hit != nil, let regionContainsPoint else { return hit }
        let local = convert(point, from: superview)
        if regionContainsPoint(Double(local.x), Double(local.y), Double(bounds.height)) {
            return hit
        }
        return nil
    }

    public override func mouseDown(with event: NSEvent) {
        // A fresh press ALWAYS starts un-latched. If the `mouseUp` that ends a
        // manual drag is ever lost (AppKit can drop it — e.g. a drag that ends over
        // another app, or a window ordering change mid-gesture), a stale anchor
        // would otherwise turn the NEXT slider / posbar drag into a window move.
        manualDragAnchorInWindow = nil
        let viewPoint = convert(event.locationInWindow, from: nil)
        // Shaped-window MANUAL drag gate (checked FIRST): a press in the title-bar
        // strip records the grab point and turns the gesture into a window move.
        // No controller state is touched, and the drag/up callbacks are suppressed
        // while the latch is set.
        if shouldManuallyDragWindow?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height)) == true {
            manualDragAnchorInWindow = event.locationInWindow
            return
        }
        // Unshaped-window title-bar drag gate: hand the gesture to the AppKit-native
        // `performDrag` (consumes it; no drag/up callbacks follow). Unchanged path.
        if shouldDragWindow?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height)) == true {
            window?.performDrag(with: event)
            return
        }
        let modifiers = ClickModifiers(
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift)
        )
        onMouseDown?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height), event.clickCount, modifiers)
    }

    public override func mouseDragged(with event: NSEvent) {
        // A manual window drag in progress consumes the gesture: reposition the
        // window and forward nothing to the controller.
        if manualDragAnchorInWindow != nil {
            moveWindowDuringManualDrag()
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        onMouseDragged?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height))
    }

    public override func mouseUp(with event: NSEvent) {
        // End a manual window drag without notifying the controller (the lift only
        // ends the move gesture).
        if manualDragAnchorInWindow != nil {
            manualDragAnchorInWindow = nil
            return
        }
        onMouseUp?()
    }

    /// Reposition the window so the recorded grab point stays under the cursor,
    /// clamped by the pure `WindowDragMath` to the UNION of every screen's visible
    /// frame: the top stays under the menu bar and at least the title strip
    /// (`manualDragGrabStripHeight`) stays on-screen at the bottom and sides. The
    /// union (not `window.screen`) is what lets the window cross onto a display
    /// arranged ABOVE — `window.screen` only updates once the frame already
    /// intersects that display. A no-op if the window or anchor is missing; with
    /// no screen attached at all the proposed origin is applied unclamped.
    private func moveWindowDuringManualDrag() {
        guard let window, let anchor = manualDragAnchorInWindow else { return }
        let mouseOnScreen = NSEvent.mouseLocation
        let proposedX = Double(mouseOnScreen.x - anchor.x)
        let proposedY = Double(mouseOnScreen.y - anchor.y)
        guard let allowed = WindowDragMath.union(of: NSScreen.screens.map { screen in
            let frame = screen.visibleFrame
            return WindowDragMath.Rect(
                x: Double(frame.origin.x), y: Double(frame.origin.y),
                width: Double(frame.width), height: Double(frame.height)
            )
        }) else {
            window.setFrameOrigin(NSPoint(x: proposedX, y: proposedY))
            return
        }
        let clamped = WindowDragMath.clampedOrigin(
            proposedX: proposedX,
            proposedY: proposedY,
            windowWidth: Double(window.frame.width),
            windowHeight: Double(window.frame.height),
            allowedArea: allowed,
            grabStripHeight: manualDragGrabStripHeight
        )
        window.setFrameOrigin(NSPoint(x: clamped.x, y: clamped.y))
    }

    public override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        onScroll?(Double(dy))
    }

    // MARK: Drag-and-drop (file URLs)
    //
    // Only reached when `onFileDrop` is set (the view registers for `.fileURL`
    // dragging only then — see `onFileDrop.didSet`). With no hook the view
    // advertises no accepted types, so AppKit never routes a drag here and the
    // harness path is unchanged.

    /// Accept a drag iff it carries file URLs AND a drop hook is wired. Returning
    /// `.copy` shows the green "+" badge and lets `performDragOperation` fire.
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onFileDrop != nil, draggedFileURLs(from: sender) != nil else {
            return []
        }
        return .copy
    }

    /// Extract the dropped `[URL]` from the pasteboard and hand them to the host's
    /// `onFileDrop`. Returns `true` when at least one file URL was forwarded.
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let onFileDrop, let urls = draggedFileURLs(from: sender) else {
            return false
        }
        onFileDrop(urls)
        return true
    }

    /// Read file URLs (and only file URLs) off a dragging pasteboard, or `nil` when
    /// the drag carries none. Restricting to `URLReadingFileURLsOnly` filters out
    /// non-file drags (e.g. a web URL) so only on-disk files are forwarded.
    private func draggedFileURLs(from sender: NSDraggingInfo) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: options
        ) as? [URL], !urls.isEmpty else {
            return nil
        }
        return urls
    }
}
