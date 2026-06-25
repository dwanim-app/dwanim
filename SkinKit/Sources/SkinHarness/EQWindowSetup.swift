import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinAppKit
import SkinKit
import SkinRender

// The harness's thin EQ-window CLI wrapper: `openEQWindow` constructs the lifted
// `SkinAppKit.EQController` via `SkinAppKit.showEQWindow`, holds it for the
// process lifetime, and drives the run loop. The controller + view + window-build
// logic now live in SkinAppKit (so the real app can reuse them); this file keeps
// only the harness-specific lifecycle (process-lifetime hold + `app.run()`).

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it). `@MainActor`: only
// assigned inside the `@MainActor` `openEQWindow`, holding a `@MainActor` controller.
@MainActor private var liveEQController: EQController?

// MARK: - Window setup

/// Build and show the EQ window via `SkinAppKit.showEQWindow`, hold the
/// controller, then run the app. Never returns.
///
/// `@MainActor` because it builds the window (main-actor AppKit) and drives the
/// main-actor `NSApplication`. The whole harness runs on the main thread.
@MainActor
func openEQWindow(skin: Skin, core: PlayerCore, scale: Int) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let handle: EQWindowHandle
    do {
        handle = try showEQWindow(skin: skin, core: core, scale: scale, title: "SkinHarness EQ")
    } catch {
        eqFail("Failed to render the EQ window: \(error)")
    }
    liveEQController = handle.controller

    app.delegate = handle.controller

    app.activate(ignoringOtherApps: true)
    app.run()

    // app.run() does not return in normal use; treat a return as a clean stop.
    exit(0)
}
