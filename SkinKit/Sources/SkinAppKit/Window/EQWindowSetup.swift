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

/// Build and show the EQ window (a plain titled window — the EQ face is a fixed
/// 275x116 rectangle, so no region mask is needed), start the redraw, and return
/// the controller + window. Throws a `RenderError` when the EQ face cannot be
/// composed/scaled into an initial frame. The caller drives the run loop and
/// holds the returned controller.
///
/// `title` is the window's title-bar text (a host-supplied label; NO brand name
/// is invented here).
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
    scale: Int,
    title: String,
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

    let scaled = try scaledImage(image, scale: scale)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    let contentView = ScaledImageView(image: scaled.image, frame: contentRect)
    // Optional file-URL drop hook (nil for the harness — registers nothing).
    contentView.onFileDrop = onFileDrop

    let controller = EQController(
        skin: skin, core: core, view: contentView, scale: scale,
        terminatesAppOnClose: terminatesAppOnClose, onClose: onClose
    )

    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = title
    window.delegate = controller
    // Host handle (harness `liveController` / app `WindowHandle`) is the sole owner;
    // do not let AppKit release the window on close out from under it (ARC
    // double-release footgun on close / re-skin).
    window.isReleasedWhenClosed = false
    window.contentView = contentView
    window.center()
    window.makeKeyAndOrderFront(nil)

    controller.start()

    return EQWindowHandle(controller: controller, window: window)
}
