import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinAppKit
import SkinKit
import SkinRender

// The harness's thin playlist-window CLI wrapper: `openPlaylistWindow` constructs
// the lifted `SkinAppKit.PlaylistWindowController` via `SkinAppKit.showPlaylistWindow`,
// holds it for the process lifetime, and drives the run loop. The controller +
// view + window-build logic + default geometry now live in SkinAppKit (so the
// real app can reuse them); this file keeps only the harness-specific lifecycle
// (process-lifetime hold + `app.run()`).

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it). `@MainActor`: only
// assigned inside the `@MainActor` `openPlaylistWindow`, holding a `@MainActor`
// controller, so it is not nonisolated shared mutable state.
@MainActor private var livePlaylistController: PlaylistWindowController?

// MARK: - Window setup

/// Build and show the playlist window via `SkinAppKit.showPlaylistWindow`, hold
/// the controller, then run the app. Never returns.
@MainActor
func openPlaylistWindow(skin: Skin, core: PlayerCore, scale: Int) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let handle: PlaylistWindowHandle
    do {
        handle = try showPlaylistWindow(skin: skin, core: core, scale: scale, title: "Playlist")
    } catch {
        FileHandle.standardError.write(Data("Failed to build the playlist window: \(error)\n".utf8))
        exit(1)
    }
    livePlaylistController = handle.controller

    app.delegate = handle.controller
    app.activate(ignoringOtherApps: true)
    app.run()

    exit(0)
}
