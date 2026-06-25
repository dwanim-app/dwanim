import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinAppKit
import SkinKit
import SkinRender

// The EQ window setup: the `openEQWindow` routine that builds the view +
// controller + window and runs the app, plus the process-lifetime hold on the
// controller. Split out of `EQMode.swift` (the openEQWindow concern, §12),
// mirroring `PlaylistWindowSetup.swift`. No logic change.

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it).
private var liveEQController: EQController?

// MARK: - Window setup

/// Build and show the EQ window (a plain titled window — the EQ face is a fixed
/// 275x116 rectangle, so no region mask is needed), then start the redraw and run
/// the app. Never returns.
func openEQWindow(skin: Skin, core: PlayerCore, scale: Int) -> Never {
    let eq = core.equalizer
    guard let base = EQWindowComposer.compose(
            skin, enabled: eq.enabled, preamp: eq.preamp, bands: eq.bands
          ),
          let image = CGImageConversion.makeImage(from: base) else {
        eqFail("Could not build an image from the composed EQ window.")
    }

    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        eqFail("Failed to render the EQ window: \(error)")
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    let contentView = ScaledImageView(image: scaled.image, frame: contentRect)

    let controller = EQController(skin: skin, core: core, view: contentView, scale: scale)
    liveEQController = controller

    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "SkinHarness EQ"
    window.delegate = controller
    window.contentView = contentView
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.delegate = controller
    controller.start()

    app.activate(ignoringOtherApps: true)
    app.run()

    // app.run() does not return in normal use; treat a return as a clean stop.
    exit(0)
}
