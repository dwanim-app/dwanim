import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender
import SpectrumKit

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
/// format-fact sources. `title` is the window's title — invisible on the
/// borderless window but kept for accessibility / Mission Control labels (a
/// host-supplied label; NO brand name is invented here).
///
/// `terminatesAppOnClose` defaults to `true` — the original single-window CLI
/// harness behavior (closing the window quits the process). A larger host (the
/// real app) passes `false` so closing this hosted window only tears it down and
/// fires `onClose` (e.g. to drop the host's retained handle) without quitting the
/// app. In the hosted (`false`) mode the host must NOT install the returned
/// controller as `NSApp.delegate`.
///
/// `externalFeed` is an optional host-owned, already-fed `SpectrumFeed`. When
/// non-`nil` (the app, which runs ONE engine tap shared across every spectrum
/// consumer) the controller's redraw loop is timer-only and installs NO tap — it
/// reads this shared feed. When `nil` (the harness) the controller installs its
/// own tap on `tap` exactly as before (unchanged single-window behavior).
/// `onFileDrop` is an optional file-URL DROP hook wired onto the content view. It
/// defaults to `nil` (the harness path), which leaves the view registered for NO
/// dragged types so its drag behavior is unchanged. The real app passes a closure
/// that routes the dropped `[URL]` to its drop handler (so dropping onto this
/// classic main window opens a skin / audio just like the open panels).
///
/// `@MainActor`: it builds the `ScaledImageView` + region window + the now-
/// `@MainActor` `InteractiveController`, and reads the `@MainActor` `PlayerCore`.
/// Every caller (the harness modes, the app's `ClassicSkinPresenter`) is already
/// main-actor-isolated, so this is a no-op at runtime — it just proves the AppKit
/// construction runs on the main actor.
@MainActor
@discardableResult
public func showInteractiveWindow(
    skin: Skin,
    core: PlayerCore,
    tap: AudioTapProviding?,
    format: TrackFormatProviding?,
    region: SkinRegion?,
    scale: Double,
    title: String,
    externalFeed: SpectrumFeed? = nil,
    terminatesAppOnClose: Bool = true,
    onClose: (() -> Void)? = nil,
    onFileDrop: (([URL]) -> Void)? = nil,
    onToggleEQ: (() -> Void)? = nil,
    onTogglePlaylist: (() -> Void)? = nil,
    onEject: (() -> Void)? = nil,
    onMinimize: (() -> Void)? = nil,
    isEQWindowOpen: @escaping () -> Bool = { false },
    isPlaylistWindowOpen: @escaping () -> Bool = { false }
) throws -> InteractiveWindowHandle {
    // Compose an initial frame just to size the window (the controller will keep
    // it updated).
    guard let base = MainWindowComposer.compose(skin),
          let image = CGImageConversion.makeImage(from: base) else {
        throw RenderError.imageCreationFailed
    }

    // The bitmap is upscaled by an INTEGER nearest-neighbor factor (crisp pixel
    // art needs whole-pixel duplication), while the WINDOW is sized in POINTS at
    // the presentation scale. For an integer scale the two coincide (the
    // historical behavior); for a fractional scale (1.5) the bitmap renders at
    // the 2x-backing device factor (3x) and the 1.5x-points bounds place it
    // 1:1 in device pixels. See `PresentationScale`.
    let bitmapScale = PresentationScale.bitmapScale(forPresentationScale: scale)
    let scaled = try scaledImage(image, scale: bitmapScale)

    let pointWidth = Double(base.width) * scale
    let pointHeight = Double(base.height) * scale
    let contentRect = NSRect(x: 0, y: 0, width: pointWidth, height: pointHeight)
    let contentView = ScaledImageView(image: scaled.image, frame: contentRect)
    // Wire the optional file-URL drop hook. Setting it registers the view for
    // `.fileURL` dragging; leaving it `nil` (harness) registers nothing.
    contentView.onFileDrop = onFileDrop

    // ONE decision point for "is this window shaped?": the pure
    // `RegionMaskGeometry.shape` computes the region COVERAGE once (even-odd per
    // polygon, unioned — the `--png` silhouette) and answers `nil` for an empty
    // region AND for a full-window rectangle (the inert `[Normal]` most region.txt
    // files carry). Such a skin gets the plain opaque window with the default
    // shadow and the native drag, exactly as if region.txt were absent. The shape's
    // `spans` drive the CAShapeLayer mask (built in the view's POINT space) and its
    // `mask` drives the click-through hit test, so "what you can click" is exactly
    // "what you can see" — from a single computation.
    let shape = region.flatMap {
        RegionMaskGeometry.shape(for: $0, width: base.width, height: base.height)
    }
    let maskLayer: CAShapeLayer? = shape.map { RegionMaskLayer.make(for: $0, scale: scale) }

    // Shaped window: click-through in the transparent cut-outs. The view's
    // `hitTest` returns nil for a view point OUTSIDE the region silhouette; the
    // closure maps the view point to skin space (the same flip used everywhere) and
    // looks the pure `RegionHitTest` up in the precomputed coverage. Left unset for
    // an unshaped window, so its hit-testing is entirely normal.
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

    // The shared region-window builder: ALWAYS a borderless (chromeless) window —
    // the skin art is the chrome — plus the region mask treatment when the skin
    // declares a shape. Built BEFORE the controller so the controller's default
    // minimize / close actions can target THIS window — the borderless window has
    // no OS window buttons, so the in-window minimize / close sprites are the
    // window's own affordances.
    let window = RegionWindowBuilder.make(
        contentRect: contentRect,
        contentView: contentView,
        maskLayer: maskLayer,
        title: title
    )

    // Default minimize action: miniaturize this window. A host may inject its own
    // `onMinimize`; otherwise the classic minimize button still works (it
    // miniaturizes the window directly). Captured weakly so the closure never keeps
    // the window alive beyond its owner's hold.
    let minimizeAction: () -> Void = onMinimize ?? { [weak window] in window?.miniaturize(nil) }

    // Close action for the skin's title-bar close button: a plain programmatic
    // `window.close()`, which routes through `windowWillClose` → `tearDown()` →
    // `onClose` — the SAME funnel as any other close of this window, so a host's
    // close-time policy (e.g. the app's close-quits-with-guards behavior) is
    // reached, never bypassed. Weak for the same ownership reason as minimize.
    let closeAction: () -> Void = { [weak window] in window?.close() }

    // Build the controller so it can serve as the window delegate: closing the
    // window then routes through `windowWillClose` → `tearDown()` (timer + tap
    // teardown) → clean app termination.
    let controller = InteractiveController(
        skin: skin, core: core, view: contentView, scale: scale, tap: tap, format: format,
        externalFeed: externalFeed,
        terminatesAppOnClose: terminatesAppOnClose,
        // Shaped windows use the manual title-bar drag; unshaped keep performDrag.
        isShaped: maskLayer != nil,
        onClose: onClose,
        onToggleEQ: onToggleEQ,
        onTogglePlaylist: onTogglePlaylist,
        onEject: onEject,
        onMinimize: minimizeAction,
        onCloseWindow: closeAction,
        isEQWindowOpen: isEQWindowOpen,
        isPlaylistWindowOpen: isPlaylistWindowOpen
    )

    // The controller is the window delegate: any close of this borderless window
    // (the skin close button's `window.close()`, a programmatic close, terminate)
    // routes through `windowWillClose` for correct teardown.
    window.delegate = controller
    // The caller owns the window for its lifetime (the harness via `liveController`,
    // the app via its `WindowHandle`). Defaulting `isReleasedWhenClosed` to `true`
    // would have AppKit release the window on close while the host handle still
    // holds it — an ARC double-release footgun on close / re-skin. Make the host
    // handle the sole owner.
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)

    controller.start()

    return InteractiveWindowHandle(controller: controller, window: window)
}
