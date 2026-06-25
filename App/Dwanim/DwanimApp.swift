import DwanimUI
import SwiftUI

// MARK: - DwanimApp
//
// The real sandboxed AUDIO player (the default-skin face). It hosts the default
// `DwanimPlayerScene` in a single window and owns an `AudioSession` — the
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
// The default scene stays the app's PRIMARY window. "Open Skin…" (⌘⇧O) is an
// ADDITIVE path: it hosts the classic `.wsz` MAIN window as an extra window
// driven by the same shared core (see ClassicSkinPresenter); closing that window
// does NOT quit the app. The View menu's "Playlist" (⌘P) / "Equalizer" (⌘G)
// toggles show/hide the two other classic windows of the loaded-skin cluster
// (when no skin is loaded yet they fall back to presenting "Open Skin…", since a
// playlist / EQ face only exists for a loaded skin). NO brand words appear
// anywhere in the UI text.
@main
struct DwanimApp: App {

    /// The single audio session for the app's lifetime. `@State` so the one
    /// instance (core + engine + feed + scopes) lives as long as the app does.
    @State private var session = AudioSession()

    var body: some Scene {
        WindowGroup {
            DwanimPlayerScene(core: session.core, model: session.model)
                .frame(minWidth: 480, minHeight: 220)
                // Start the feed + launch-resolve once the window appears; tear the
                // session (feed + held security scope) down when it goes away.
                .onAppear { session.start() }
                .onDisappear { session.stop() }
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
