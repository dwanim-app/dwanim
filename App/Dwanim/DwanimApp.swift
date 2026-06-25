import AppKit
import DwanimUI
import SwiftUI

// MARK: - DwanimApp
//
// The real sandboxed AUDIO player (the default-skin face). It hosts the default
// `DwanimPlayerScene` in a SINGLE window and owns an `AudioSession` — the
// app-layer coordinator that wires the live PlayerCore + AVAudioEnginePlayer,
// the spectrum/clock feed, the security-scoped bookmark persistence, the
// "Open Audio…" panel, and launch-resolve of the last song.
//
// What lives where:
//   - The transport core, the view-model, the engine tap feed, and all of the
//     sandbox/bookmark machinery are inside `AudioSession` (this file just owns
//     and drives it).
//   - The window's content is the unchanged `DwanimPlayerScene`, which observes
//     `session.core` (transport state + actions) and `session.model` (live clock
//     + spectrum). The in-scene transport buttons drive the core directly.
//
// ## Lifecycle ownership (single owner for the shared session)
// The default face is a single `Window` scene (NOT a `WindowGroup`), so the one
// shared `@State AudioSession` has EXACTLY ONE window lifecycle owner. A
// `WindowGroup` is a multi-window template: closing one window/tab of the group
// would tear down the shared session out from under any still-open window. With a
// single `Window` there is no second window of the group to do that.
//
// Session teardown is driven from genuine app TERMINATION, not window
// disappearance: the `AppDelegate` (installed via `@NSApplicationDelegateAdaptor`)
// calls `session.stop()` in `applicationWillTerminate(_:)`, and
// `applicationShouldTerminateAfterLastWindowClosed(_:)` returns `true` so closing
// the single main window quits the app — which then tears the session down exactly
// once. `.onAppear` still starts the feed (and resolves the last song once per
// process); `.onDisappear` no longer stops anything.
//
// The default scene stays the app's PRIMARY window. "Open Skin…" (⌘⇧O) is an
// ADDITIVE path: it hosts the classic `.wsz` MAIN window as an extra AppKit window
// driven by the same shared core (see ClassicSkinPresenter); closing that window
// does NOT quit the app. Those classic cluster windows are independent NSWindows
// that manage their own close and are torn down on real app termination (via the
// session teardown / process exit) — no window-disappear path force-closes them.
// The View menu's "Playlist" (⌘P) / "Equalizer" (⌘G) toggles show/hide the two
// other classic windows of the loaded-skin cluster (when no skin is loaded yet
// they fall back to presenting "Open Skin…", since a playlist / EQ face only exists
// for a loaded skin). NO brand words appear anywhere in the UI text.
@main
struct DwanimApp: App {

    /// The single audio session for the app's lifetime. `@State` so the one
    /// instance (core + engine + feed + scopes) lives as long as the app does.
    @State private var session = AudioSession()

    /// The AppKit delegate that drives session teardown from genuine app
    /// termination (NOT window disappearance) and quits the app when the single
    /// main window closes. SwiftUI owns this instance for the app's lifetime.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SINGLE Window (not WindowGroup): one lifecycle owner for the shared
        // session. `Window` is macOS 13+ — fine for the 14.0 floor.
        Window("Dwanim", id: "main") {
            DwanimPlayerScene(core: session.core, model: session.model)
                .frame(minWidth: 480, minHeight: 220)
                // File-URL DROP onto the default scene window: hand the dropped URLs
                // to the session's one drop handler (the same one every hosted
                // classic window routes to). The handler classifies them — a `.wsz`
                // applies as a skin, audio files play (multiple become the playlist),
                // a mix does both, unsupported types are ignored — minting +
                // persisting a security-scoped bookmark per file exactly as the open
                // panels do (a drop grants sandbox access just like a panel pick).
                // Returning `true` accepts the drop; an empty/unsupported drop is a
                // harmless no-op inside the handler.
                .dropDestination(for: URL.self) { urls, _ in
                    session.handleDroppedURLs(urls)
                    return true
                }
                // Start the feed + launch-resolve (once per process) when the window
                // appears, and hand the delegate the session so it can tear down at
                // real termination. We do NOT stop the session on `.onDisappear`:
                // teardown is driven from `applicationWillTerminate(_:)` so closing
                // (or SwiftUI re-creating) the window never kills the shared audio /
                // spectrum feed or resets the live playlist.
                .onAppear {
                    appDelegate.session = session
                    session.start()
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Replace the standard "New" item with the app's open commands, so
            // File ▸ Open Audio… (⌘O) presents the audio NSOpenPanel and
            // File ▸ Open Skin… (⌘⇧O) presents the .wsz skin panel that hosts the
            // classic main window (driven by the same shared core; closing it does
            // NOT quit the app).
            CommandGroup(replacing: .newItem) {
                Button("Open Audio…") {
                    session.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Skin…") {
                    session.presentOpenSkinPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            // Add the two auxiliary-window toggles into the STANDARD View menu (the
            // one SwiftUI auto-creates for sidebar / toolbar / full-screen items),
            // rather than spawning a SECOND "View" menu. `.toolbar` is the standard
            // View-menu group, so `after: .toolbar` appends our items at the bottom
            // of that one menu — a single coherent View menu.
            //
            // The items are always enabled: with a skin loaded they toggle the
            // hosted Playlist / Equalizer windows show/hide; with no skin loaded yet
            // they fall back to presenting "Open Skin…" (the auxiliary faces only
            // exist for a loaded skin), so the items are never dead.
            CommandGroup(after: .toolbar) {
                // The classic MAIN window may be built BORDERLESS for a region skin
                // (no titlebar, no close button), so this toggle is the only host
                // affordance to close (and reopen) it without a re-skin or quit. Like
                // the others, it falls back to "Open Skin…" when no skin is loaded.
                Button("Skin Window") {
                    session.toggleMainWindow()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Playlist") {
                    session.togglePlaylistWindow()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("Equalizer") {
                    session.toggleEQWindow()
                }
                .keyboardShortcut("g", modifiers: [.command])
            }
        }
    }
}

// MARK: - AppDelegate
//
// A minimal `NSApplicationDelegate` installed via `@NSApplicationDelegateAdaptor`
// so the app's lifecycle is driven by GENUINE termination, not window
// disappearance:
//
//   • `applicationShouldTerminateAfterLastWindowClosed(_:)` returns `true`, so
//     closing the single main `Window` quits the app (instead of leaving a
//     window-less process running).
//   • `applicationWillTerminate(_:)` tears the shared `AudioSession` down EXACTLY
//     ONCE, when the process is actually quitting — releasing the security scope,
//     stopping the feed, and closing the hosted classic-window cluster.
//
// The `session` is handed in from the scene's `.onAppear` (the App owns the one
// `@State` instance; this delegate only holds a weak back-reference to drive
// teardown). Holding it weak avoids a retain cycle and is harmless: if the App's
// `@State` is gone the process is already tearing down.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The shared session to tear down at termination. Set by the scene's
    /// `.onAppear`. Weak: the App's `@State` is the real owner.
    weak var session: AudioSession?

    /// Closing the single main window quits the app (so we tear down once, cleanly,
    /// via `applicationWillTerminate`), rather than leaving a window-less process.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Genuine termination: tear the shared session down exactly once (feed off,
    /// security scope released, hosted classic cluster closed). This is the ONLY
    /// teardown trigger — no window-disappear path stops the session.
    func applicationWillTerminate(_ notification: Notification) {
        session?.stop()
    }
}
