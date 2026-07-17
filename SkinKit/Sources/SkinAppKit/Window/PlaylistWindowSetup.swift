import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The playlist window's default geometry + the `showPlaylistWindow` construction
// that builds the view/controller/window (per §12: one primary concern per file).
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier so the
// real app target can host the playlist window too. The window-build logic that
// used to live in the harness's `openPlaylistWindow` now lives here; the harness
// keeps only the thin `Never`-returning wrapper that holds the returned controller
// and drives `app.run()`. No logic change beyond returning the controller/window
// rather than running the app inline.

// MARK: - Default window geometry

/// Default unscaled playlist-window size (skin pixels). Kept in a plain,
/// non-actor-isolated namespace so the headless snapshot path can read it too
/// (the controller is `@MainActor`; these constants are not UI state). Wide
/// enough for a readable title column and tall enough for ~14 rows.
public enum PlaylistWindowGeometry {
    public static let defaultWidth = 275
    public static let defaultHeight = 232
}

// MARK: - Window construction

/// Result of building the playlist window: the controller (which the caller must
/// hold for the window's lifetime — the run loop owns no strong reference to it)
/// and the window itself.
@MainActor
public struct PlaylistWindowHandle {
    public let controller: PlaylistWindowController
    public let window: NSWindow
}

/// Build and show the playlist window (a resizable borderless chromeless window
/// — the skin's own title bar is the drag handle and its baked close glyph the
/// close affordance), wire the controller + view, and return the controller +
/// window. Throws a `RenderError` when the playlist frame cannot be
/// composed/scaled. The caller drives the run loop and holds the returned
/// controller.
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
/// dropped `[URL]` to its drop handler, so dropping onto the playlist window opens
/// a skin / audio (a multi-file audio drop becomes the queue) just like the panels.
@MainActor
@discardableResult
public func showPlaylistWindow(
    skin: Skin,
    core: PlayerCore,
    scale: Double,
    title: String,
    terminatesAppOnClose: Bool = true,
    onClose: (() -> Void)? = nil,
    onFileDrop: (([URL]) -> Void)? = nil
) throws -> PlaylistWindowHandle {
    let width = PlaylistWindowGeometry.defaultWidth
    let height = PlaylistWindowGeometry.defaultHeight

    guard let frame = PlaylistWindowComposer.compose(skin, width: width, height: height),
          let image = CGImageConversion.makeImage(from: frame) else {
        throw RenderError.imageCreationFailed
    }

    // Integer nearest-neighbor bitmap + point-sized window: the bitmap renders at
    // the integer factor derived from the presentation scale (1.5 -> 3 on a 2x
    // backing), while the window content rect is the composed frame's size *
    // scale in POINTS. See `PresentationScale`.
    let bitmapScale = PresentationScale.bitmapScale(forPresentationScale: scale)
    let scaled = try scaledImage(image, scale: bitmapScale)

    let contentRect = NSRect(
        x: 0, y: 0,
        width: Double(frame.width) * scale,
        height: Double(frame.height) * scale
    )
    // Compose returns the CLAMPED size; use the frame's actual dimensions so the
    // text layout matches the bitmap exactly.
    let view = PlaylistContentView(
        frameImage: scaled.image,
        skin: skin,
        scale: scale,
        skinWidth: frame.width,
        skinHeight: frame.height,
        frame: contentRect
    )
    // Optional file-URL drop hook (nil for the harness — registers nothing). The
    // base `ScaledImageView` carries the drop machinery; the playlist's click /
    // scroll hooks are independent of it.
    view.onFileDrop = onFileDrop

    // The controller re-derives the interior from the same composed-frame size, so
    // click hit-testing and the draw path share one geometry source. It also keeps
    // the skin so a drag-resize can recompose the frame at the new size.
    let controller = PlaylistWindowController(
        core: core, skin: skin, scale: scale, skinWidth: frame.width, skinHeight: frame.height,
        terminatesAppOnClose: terminatesAppOnClose, onClose: onClose
    )
    controller.attach(view: view)

    // Chromeless: the skin's own title bar is the drag handle and its baked
    // close glyph the close affordance (wired by `PlaylistWindowController`).
    // `.resizable` still lets the user edge-drag the borderless window;
    // `windowDidResize` recomputes the skin-space size (floor(bounds / scale),
    // clamped to the composer minimum), recomposes the frame, and re-runs the
    // layout so more/fewer rows show. `.miniaturizable` adds no visible chrome
    // but keeps `miniaturize(_:)` functional; the subclass keeps the borderless
    // window key-capable.
    let window = ChromelessSkinWindow(
        contentRect: contentRect,
        styleMask: [.borderless, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    // Invisible on a borderless window; kept for accessibility / Mission Control.
    window.title = title
    window.delegate = controller
    // Host handle (harness `liveController` / app `WindowHandle`) is the sole owner;
    // do not let AppKit release the window on close out from under it (ARC
    // double-release footgun on close / re-skin).
    window.isReleasedWhenClosed = false
    window.contentView = view
    // Floor the draggable size at the composer minimum (in points, at the
    // presentation scale), so the user can never drag below where the frame
    // corners stop fitting. The composer also clamps defensively, but this keeps
    // the live drag from showing a clamped frame smaller than the window chrome.
    window.contentMinSize = NSSize(
        width: Double(PlaylistWindowComposer.minimumWidth) * scale,
        height: Double(PlaylistWindowComposer.minimumHeight) * scale
    )
    window.center()
    window.makeKeyAndOrderFront(nil)

    return PlaylistWindowHandle(controller: controller, window: window)
}
