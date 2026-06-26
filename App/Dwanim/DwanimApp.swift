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
            DwanimPlayerScene(
                core: session.core,
                model: session.model,
                // The gear/overflow menu's open actions route to the SAME session
                // calls the File menu uses — one source of truth. Plumbed as
                // closures so DwanimUI never imports AppKit.
                onOpenAudio: { session.presentOpenPanel() },
                onOpenSkin: { session.presentOpenSkinPanel() },
                // fix-5 dynamic height: the scene measures its own rendered height
                // (pure SwiftUI) and reports it here whenever it changes (queue
                // expand/collapse). The session resizes the captured default window
                // to that height — a SwiftUI `Window` does not reliably grow/shrink
                // itself on runtime content-height changes, so the App layer drives
                // it. The window-poking stays App-side; DwanimUI stays pure.
                onContentHeightChange: { height in session.setDefaultContentHeight(height) }
            )
                // Compact resize floor only. Under `.windowResizability(.contentMinSize)`
                // the definite width on `DefaultPlayerView` (`compactWidth` ~580, with
                // ZERO surrounding margin in fix-5) drives the opening width and the
                // content height drives the opening height — this frame just sets how
                // small the user can drag it. No max height: expanding the in-scene
                // queue (P2-1) grows the window taller (App-layer resize via
                // `onContentHeightChange`); collapsed it shrinks back to the compact
                // dock-bar.
                .frame(minWidth: 440, minHeight: 120)
                // File-URL DROP onto the default scene window: hand the dropped URLs
                // to the session's one drop handler (the same one every hosted
                // classic window routes to). The handler classifies them — a `.wsz`
                // applies as a skin, audio files play (multiple become the playlist),
                // a mix does both, unsupported types are ignored — minting +
                // persisting a security-scoped bookmark per file exactly as the open
                // panels do (a drop grants sandbox access just like a panel pick).
                // Filter to file URLs only (matching the AppKit ScaledImageView
                // path's `urlReadingFileURLsOnly: true`): a dragged web link is not a
                // file and must be rejected. Return `true` only when at least one file
                // URL survives the filter, so the acceptance value is honest; a
                // non-file / empty drop returns `false` and never reaches the handler.
                .dropDestination(for: URL.self) { urls, _ in
                    let files = urls.filter(\.isFileURL)
                    guard !files.isEmpty else { return false }
                    session.handleDroppedURLs(files)
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
                // P2-6 (one-face-at-a-time): capture the default scene's backing
                // NSWindow into the session at launch. A zero-size accessor view in
                // the background reports its enclosing window up to the session, which
                // stores it weakly so the classic-skin presenter can HIDE the default
                // face while a classic `.wsz` main window is shown and RESTORE it when
                // that window closes. The AppKit window-poking stays in the App target
                // (this accessor + the session), so DwanimUI / PlayerCore stay pure.
                .background(WindowAccessor { window in
                    session.setDefaultWindow(window)
                })
        }
        // P2-5: drop the title-bar strip + title text so the glass bar is
        // full-bleed to the top. The traffic lights stay (faint, working) for
        // close/minimise/zoom — `.hiddenTitleBar` hides the chrome, not the
        // window buttons.
        .windowStyle(.hiddenTitleBar)
        // P2-5 / fix-5: the content's fitting size drives the window's MINIMUM (and
        // opening) size — the definite width on `DefaultPlayerView` (~580) plus the
        // compact-bar height open the window hugging the panel. We use
        // `.contentMinSize` rather than `.contentSize` ON PURPOSE: a SwiftUI `Window`
        // hosted in an `NSHostingView` does NOT reliably grow itself when the content
        // height changes at runtime (measured: `.contentSize` pinned the window to the
        // collapsed 580×148 and SNAPPED BACK any App-layer resize). `.contentMinSize`
        // keeps the compact opening size as a floor while letting the App layer GROW
        // the window when the in-scene queue (P2-1) expands and SHRINK it back when it
        // collapses, driven by the scene's `onContentHeightChange` ->
        // `session.setDefaultContentHeight` (see those). Frame restoration to a stale
        // large frame can't reappear: `WindowAccessor.forceCompact` disables the
        // autosave on first capture.
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

            // P2-7: a top-level "Skin" menu. Closing the classic skin's MAIN window
            // now QUITS the app (the user disliked the default face popping back), so
            // this menu is the standard-mac way to leave a classic skin WITHOUT
            // quitting: "Default Skin" (⌘D) closes the classic cluster and restores
            // the default SwiftUI face. The cluster close is programmatic, so the
            // presenter's close→quit guard (an internal switching flag) keeps it from
            // terminating. "Open Skin…" / "Open Audio…" are mirrored here for one
            // coherent home for the skin commands (same session calls the File menu
            // uses — one source of truth). NO brand words (§12).
            CommandMenu("Skin") {
                Button("Default Skin") {
                    session.switchToDefaultSkin()
                }
                .keyboardShortcut("d", modifiers: [.command])

                Divider()

                Button("Open Skin…") {
                    session.presentOpenSkinPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Open Audio…") {
                    session.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
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
//   • `applicationShouldTerminateAfterLastWindowClosed(_:)` returns `true` ONLY
//     when no hosted classic window remains, so closing the single default `Window`
//     quits the app — UNLESS a classic skin / playlist / EQ window is still open, in
//     which case it returns `false` and the app keeps running on that cluster.
//   • `applicationWillTerminate(_:)` tears the shared `AudioSession` down EXACTLY
//     ONCE, when the process is actually quitting — releasing the security scope,
//     stopping the feed, and closing the hosted classic-window cluster.
//
// P2-7 note: this method governs the DEFAULT face's close. Closing the CLASSIC
// MAIN window does NOT go through here — it routes through the presenter's
// `onClose` → `NSApp.terminate(nil)` (the close→quit rule), which then drives
// `applicationWillTerminate` below. So the two faces quit by different paths but
// both end in the same single teardown.
//
// The `session` is handed in from the scene's `.onAppear` (the App owns the one
// `@State` instance; this delegate only holds a weak back-reference to drive
// teardown). Holding it weak avoids a retain cycle and is harmless: if the App's
// `@State` is gone the process is already tearing down.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The shared session to tear down at termination. Set by the scene's
    /// `.onAppear`. Weak: the App's `@State` is the real owner.
    weak var session: AudioSession?

    /// Closing the default SwiftUI `Window` should quit the app — but ONLY when no
    /// hosted classic window remains. If a classic skin / playlist / EQ window is
    /// still open, closing the default window must keep the app alive on that
    /// cluster, so we return `false`; once the last classic window has also closed
    /// (no classic window left), we return `true` and the app quits, tearing the
    /// session down cleanly via `applicationWillTerminate`.
    ///
    /// AppKit calls this whenever the app's window count reaches zero AND when a
    /// window close leaves a window-less SwiftUI scene; gating on
    /// `isAnyClassicWindowOpen` means: closing the LAST remaining window (default
    /// plus all classic) quits, while closing the default with a classic still up
    /// does not. ⌘Q is unaffected — it routes through `terminate(_:)` directly and
    /// never consults this method, so it always quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // No session yet (pre-`.onAppear`) means no classic window is open, so it is
        // safe to quit on the last window close.
        guard let session else { return true }
        return !session.isAnyClassicWindowOpen
    }

    /// Dock-reopen / app-reactivation guard (P2-6, one-face-at-a-time). AppKit's
    /// default reopen behaviour re-fronts a hidden window when the user clicks the
    /// Dock icon or reactivates the app — which would un-hide the default `Window`
    /// that the classic-skin presenter `orderOut`-ed, leaving BOTH faces visible at
    /// once. So while a classic window is open we return `false` (do NOT let AppKit
    /// un-hide / re-front the default window); when no classic window is open the
    /// default IS the face, so we return `true` and normal reopen proceeds.
    ///
    /// Reads the SAME `session.isAnyClassicWindowOpen` signal that drives
    /// `applicationShouldTerminateAfterLastWindowClosed`. No session yet
    /// (pre-`.onAppear`) means no classic window, so normal reopen is allowed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return !(session?.isAnyClassicWindowOpen ?? false)
    }

    /// Genuine termination: tear the shared session down exactly once (feed off,
    /// security scope released, hosted classic cluster closed). This is the ONLY
    /// teardown trigger — no window-disappear path stops the session.
    func applicationWillTerminate(_ notification: Notification) {
        session?.stop()
    }
}
