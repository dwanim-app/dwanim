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
// What this increment does NOT do (those land in 6b): no `.wsz` classic-skin
// windows. NO brand words appear anywhere in the UI text.
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
            // Replace the standard "New" item with the app's open-audio command,
            // so ⌘O / File ▸ Open Audio… presents the NSOpenPanel.
            CommandGroup(replacing: .newItem) {
                Button("Open Audio…") {
                    session.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
