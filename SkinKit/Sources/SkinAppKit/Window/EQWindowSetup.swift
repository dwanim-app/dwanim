import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The EQ window construction (one primary concern per file, §12): `showEQWindow`
// builds the view + controller + window, makes it key, and starts the controller,
// returning the controller so the caller can hold it for the window's lifetime.
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier so the
// real app target can host the EQ window too. The window-build logic that used to
// live in the harness's `openEQWindow` now lives here; the harness keeps only the
// thin `Never`-returning wrapper that holds the returned controller and drives
// `app.run()`. No logic change beyond returning the controller rather than
// running the app inline.

// MARK: - Window construction

/// Result of building the EQ window: the controller (which the caller must hold
/// for the window's lifetime — the run loop owns no strong reference to it) and
/// the window itself.
public struct EQWindowHandle {
    public let controller: EQController
    public let window: NSWindow
}

/// Build and show the EQ window (a borderless chromeless window — the EQ face is
/// a fixed 275x116 canvas whose baked title-bar strip is the drag handle and
/// whose baked close glyph is the close affordance; a skin that declares a real
/// `[Equalizer]` region additionally shapes it through the same coverage mask /
/// click-through / manual-drag path as the main window), start the redraw, and
/// return the controller + window. Throws a `RenderError` when the EQ face cannot
/// be composed/scaled into an initial frame. The caller drives the run loop and
/// holds the returned controller.
///
/// `title` is the window's title — invisible on the borderless window but kept
/// for accessibility / Mission Control labels (a host-supplied label; NO brand
/// name is invented here).
///
/// `terminatesAppOnClose` defaults to `true` — the original single-window CLI
/// harness behavior (closing the window quits the process). A larger host (the
/// real app) passes `false` so closing this hosted window only tears it down and
/// fires `onClose` (e.g. to drop the host's retained handle) without quitting the
/// app. In the hosted (`false`) mode the host must NOT install the returned
/// controller as `NSApp.delegate`.
/// `onFileDrop` is an optional file-URL DROP hook wired onto the content view; it
/// defaults to `nil` (the harness path) so the view registers for no dragged types
/// and its behavior is unchanged. The real app passes a closure routing the
/// dropped `[URL]` to its drop handler, so dropping onto the EQ window opens a
/// skin / audio just like the open panels.
///
/// `@MainActor`: it builds the `ScaledImageView` + window + the now-`@MainActor`
/// `EQController`, and reads the `@MainActor` `PlayerCore`. Every caller is already
/// main-actor-isolated, so this is a no-op at runtime and just makes the AppKit
/// construction provable.
@MainActor
@discardableResult
public func showEQWindow(
    skin: Skin,
    core: PlayerCore,
    scale: Double,
    title: String,
    region: SkinRegion? = nil,
    terminatesAppOnClose: Bool = true,
    onClose: (() -> Void)? = nil,
    onFileDrop: (([URL]) -> Void)? = nil
) throws -> EQWindowHandle {
    let eq = core.equalizer
    guard let base = EQWindowComposer.compose(
            skin, enabled: eq.enabled, preamp: eq.preamp, bands: eq.bands
          ),
          let image = CGImageConversion.makeImage(from: base) else {
        throw RenderError.imageCreationFailed
    }

    // Integer nearest-neighbor bitmap + point-sized window: the bitmap renders at
    // the integer factor derived from the presentation scale (1.5 -> 3 on a 2x
    // backing), while the window content rect is skin size * scale in POINTS.
    // See `PresentationScale`.
    let bitmapScale = PresentationScale.bitmapScale(forPresentationScale: scale)
    let scaled = try scaledImage(image, scale: bitmapScale)

    let contentRect = NSRect(
        x: 0, y: 0,
        width: Double(base.width) * scale,
        height: Double(base.height) * scale
    )
    let contentView = ScaledImageView(image: scaled.image, frame: contentRect)
    // Optional file-URL drop hook (nil for the harness — registers nothing).
    contentView.onFileDrop = onFileDrop

    // Region shaping (item 7): a skin that declares a REAL `[Equalizer]` region
    // gets the SAME non-rectangular treatment as the main window — a
    // coverage-derived CAShapeLayer mask, click-through in the cut-outs, no
    // rectangular shadow, and the manual title-bar drag. The pure
    // `RegionMaskGeometry.shape` is the one decision point: it computes the
    // coverage ONCE and answers `nil` for an empty region AND for a full-window
    // rectangle (an inert `[Equalizer] 0,0 275,0 275,116 0,116`), so both the common
    // no-region case and the inert-rectangle case keep the EQ window a plain opaque
    // rectangle with the default shadow — no regression.
    let shape = region
        .flatMap { $0.isEmpty ? nil : $0 }
        .flatMap { RegionMaskGeometry.shape(for: $0, width: base.width, height: base.height) }
    let maskLayer: CAShapeLayer? = shape.map { RegionMaskLayer.make(for: $0, scale: scale) }
    if let shape {
        contentView.regionContainsPoint = { viewX, viewY, viewHeight in
            let point = ControlHitTest.skinPoint(
                viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
            )
            return RegionHitTest.isInside(
                mask: shape.mask, width: shape.width, height: shape.height,
                skinX: point.x, skinY: point.y
            )
        }
    }

    let controller = EQController(
        skin: skin, core: core, view: contentView, scale: scale,
        terminatesAppOnClose: terminatesAppOnClose,
        isShaped: maskLayer != nil, onClose: onClose
    )

    // Chromeless window via the shared region builder: always borderless (the EQ
    // face's own title-bar strip is the drag handle and its baked close glyph the
    // close affordance, wired by `EQController`); a shaped EQ additionally gets the
    // non-opaque + clear-background + layer-mask + no-shadow treatment.
    let window = RegionWindowBuilder.make(
        contentRect: contentRect,
        contentView: contentView,
        maskLayer: maskLayer,
        title: title
    )
    window.delegate = controller
    // Host handle (harness `liveController` / app `WindowHandle`) is the sole owner;
    // do not let AppKit release the window on close out from under it (ARC
    // double-release footgun on close / re-skin).
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)

    controller.start()

    return EQWindowHandle(controller: controller, window: window)
}
