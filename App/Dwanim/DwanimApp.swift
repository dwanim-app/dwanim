import DwanimUI
import PlaybackKit
import PlayerCore
import SwiftUI

// MARK: - DwanimApp
//
// The SEED of the real macOS app shell. It is a minimal-but-real SwiftUI
// `App` that launches and shows the Dwanim identity: a single window hosting
// the default-skin idle scene (`DwanimPlayerScene`).
//
// What it intentionally does NOT do yet (those land in increment #6, the app
// shell that proves sandbox/bookmark and the classic-skin window):
//   - No file open / NSOpenPanel, no security-scoped bookmarks.
//   - No playback is started: the engine is constructed but never told to play,
//     and no track is loaded, so the scene renders its idle state (quiet
//     "Dwanim" title, empty progress, empty spectrum).
//   - No `.wsz` loading / classic-skin windows.
//
// The audio engine is the real `AVAudioEnginePlayer`, whose initializer only
// builds the (silent) AVAudioEngine node graph — it does not start the engine
// or touch any file — so constructing it here has no audible side effect. Using
// the real engine (rather than a throwaway stub) keeps this seed honest about
// the wiring the full shell will use.
@main
struct DwanimApp: App {

    /// The UI-agnostic playback core, with a real (idle) audio engine injected.
    /// `@State` so the single instance lives for the lifetime of the app.
    @State private var core = PlayerCore(engine: AVAudioEnginePlayer())

    /// The presentation bridge for the live clock / spectrum levels. Empty here
    /// (no audio flowing), which the scene reads as the idle state.
    @State private var model = PlayerViewModel()

    var body: some Scene {
        WindowGroup {
            DwanimPlayerScene(core: core, model: model)
                .frame(minWidth: 480, minHeight: 220)
        }
        .windowResizability(.contentMinSize)
    }
}
