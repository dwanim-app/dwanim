import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The playlist window's default geometry + the `openPlaylistWindow` setup that
// builds the view/controller/window and runs the app. Split out of
// `PlaylistView.swift` (the geometry/openPlaylistWindow concern, §12). No logic
// change — pure reorganization.

// MARK: - Default window geometry

/// Default unscaled playlist-window size (skin pixels). Kept in a plain,
/// non-actor-isolated namespace so the headless snapshot path can read it too
/// (the controller is `@MainActor`; these constants are not UI state). Wide
/// enough for a readable title column and tall enough for ~14 rows.
enum PlaylistWindowGeometry {
    static let defaultWidth = 275
    static let defaultHeight = 232
}

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it).
private var livePlaylistController: PlaylistWindowController?

// MARK: - Window setup

/// Build and show the playlist window, then run the app. Never returns.
@MainActor
func openPlaylistWindow(skin: Skin, core: PlayerCore, scale: Int) -> Never {
    let width = PlaylistWindowGeometry.defaultWidth
    let height = PlaylistWindowGeometry.defaultHeight

    guard let frame = PlaylistWindowComposer.compose(skin, width: width, height: height),
          let image = CGImageConversion.makeImage(from: frame) else {
        FileHandle.standardError.write(Data("Could not build the playlist frame image.\n".utf8))
        exit(1)
    }

    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        FileHandle.standardError.write(Data("Failed to scale the playlist frame: \(error)\n".utf8))
        exit(1)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
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

    // The controller re-derives the interior from the same composed-frame size, so
    // click hit-testing and the draw path share one geometry source.
    let controller = PlaylistWindowController(
        core: core, scale: scale, skinWidth: frame.width, skinHeight: frame.height
    )
    controller.attach(view: view)
    livePlaylistController = controller

    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Playlist"
    window.delegate = controller
    window.contentView = view
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.delegate = controller
    app.activate(ignoringOtherApps: true)
    app.run()

    exit(0)
}
