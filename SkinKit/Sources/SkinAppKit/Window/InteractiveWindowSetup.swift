import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The classic main-window construction (one primary concern per file, §12):
// `showInteractiveWindow` builds the view + controller + region window, makes it
// key, and starts the redraw loop, returning the controller + window so the
// caller can hold them for the window's lifetime.
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier so the
// real app target can host the classic main window too. The window-build logic
// that used to live in the harness's `openInteractiveWindow` now lives here; the
// harness keeps only the thin `Never`-returning wrapper that holds the returned
// controller and drives `app.run()`. No logic change beyond returning the
// controller/window rather than running the app inline.

// MARK: - Window construction

/// Result of building the classic main window: the controller (which the caller
/// must hold for the window's lifetime — the run loop owns no strong reference to
/// it) and the window itself.
public struct InteractiveWindowHandle {
    public let controller: InteractiveController
    public let window: NSWindow
}

/// Build and show the classic main skin window, reusing the same opaque-content +
/// window-level region-mask approach as the static window path, start the redraw
/// loop, and return the controller + window. Throws a `RenderError` when an
/// initial frame cannot be composed/scaled. The caller drives the run loop and
/// holds the returned controller.
///
/// `region` is the skin's custom shape (already normalized to `nil` when empty by
/// the caller). `tap` / `format` are the engine's opt-in PCM-tap and
/// format-fact sources. `title` is the titled-fallback window's title-bar text
/// (a host-supplied label; NO brand name is invented here).
@discardableResult
public func showInteractiveWindow(
    skin: Skin,
    core: PlayerCore,
    tap: AudioTapProviding?,
    format: TrackFormatProviding?,
    region: SkinRegion?,
    scale: Int,
    title: String
) throws -> InteractiveWindowHandle {
    // Compose an initial frame just to size the window (the controller will keep
    // it updated).
    guard let base = MainWindowComposer.compose(skin),
          let image = CGImageConversion.makeImage(from: base) else {
        throw RenderError.imageCreationFailed
    }

    let scaled = try scaledImage(image, scale: scale)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    let contentView = ScaledImageView(image: scaled.image, frame: contentRect)

    // Window-level region mask (same as the static window path): the content stays
    // opaque and the shape is carried by a CAShapeLayer mask.
    let maskLayer: CAShapeLayer? = region.flatMap { region in
        RegionMaskLayer.make(
            for: region,
            skinHeight: base.height,
            scale: scale,
            scaledWidth: scaled.width,
            scaledHeight: scaled.height
        )
    }

    // Build the controller first so it can serve as the window delegate: closing
    // the window then routes through `windowWillClose` → `tearDown()` (timer + tap
    // teardown) → clean app termination.
    let controller = InteractiveController(
        skin: skin, core: core, view: contentView, scale: scale, tap: tap, format: format
    )

    // The shared region-window builder applies the same borderless/masked vs
    // titled chrome the static window path uses.
    let window = RegionWindowBuilder.make(
        contentRect: contentRect,
        contentView: contentView,
        maskLayer: maskLayer,
        title: title
    )
    // Both window paths get the delegate: the titled fallback so its close button
    // tears down cleanly, and the borderless region window (no close button) so a
    // programmatic close/terminate is still correct teardown.
    window.delegate = controller
    window.center()
    window.makeKeyAndOrderFront(nil)

    controller.start()

    return InteractiveWindowHandle(controller: controller, window: window)
}
