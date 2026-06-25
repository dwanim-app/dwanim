import Foundation
import PlayerCore
import SkinRender

// MARK: - PlayerControl
//
// The pure mapping from a hit-tested `SkinControl` to a `PlayerCore` transport
// action, lifted out of the interactive harness so it is importable and
// unit-testable. It is `Foundation`-only over `SkinRender` (the control enum)
// and `PlayerCore` (the transport) — NO AppKit / AVFoundation, no platform
// types — so every mapping can be driven and asserted with a fake engine.

public enum PlayerControl {

    // MARK: - Apply a control

    /// Map a hit-tested `SkinControl` to the matching `PlayerCore` transport
    /// action, in one place so the mapping is clear and easy to audit:
    ///   .play          -> play()
    ///   .pause         -> pause()
    ///   .stop          -> pause() then seek(to: 0)
    ///   .next          -> next()
    ///   .previous      -> previous()
    ///   .toggleShuffle -> isShuffle.toggle()
    ///   .toggleRepeat  -> cycle repeatMode off -> all -> one -> off
    ///
    /// `@MainActor` because it touches the now-main-actor `PlayerCore`; every
    /// caller (the window controllers) is already on the main actor, so this is a
    /// no-op at runtime and just makes the isolation explicit.
    @MainActor
    public static func apply(_ control: SkinControl, to core: PlayerCore) {
        switch control {
        case .play:
            core.play()
        case .pause:
            core.pause()
        case .stop:
            // No dedicated engine "stop": pause and rewind to the start so a
            // later play() restarts from 0.
            core.pause()
            core.seek(to: 0)
        case .next:
            core.next()
        case .previous:
            core.previous()
        case .toggleShuffle:
            core.isShuffle.toggle()
        case .toggleRepeat:
            core.repeatMode = nextRepeatMode(core.repeatMode)
        }
    }

    // MARK: - Repeat cycle

    /// The next repeat mode in the off -> all -> one -> off cycle.
    public static func nextRepeatMode(_ mode: RepeatMode) -> RepeatMode {
        switch mode {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}
