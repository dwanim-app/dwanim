import Foundation

// MARK: - RepeatMode

/// How playback proceeds when a track ends or the listener skips past a boundary.
public enum RepeatMode: Sendable, Equatable {
    /// Stop after the last track; do not wrap.
    case off
    /// Wrap around the playlist end-to-end.
    case all
    /// Repeat the current track indefinitely.
    ///
    /// This governs AUTO-ADVANCE only (a finished track replays). For EXPLICIT
    /// `next`/`previous` it behaves like `.all` — repeat is on, so the ends wrap.
    case one

    // MARK: - Button cycle

    /// The next mode a repeat BUTTON press should select: `off -> all -> one -> off`.
    ///
    /// Both faces cycle the same three states, so the order is defined ONCE here
    /// rather than in either view: the classic `.wsz` face reaches it through
    /// `PlayerControl.nextRepeatMode` (its `.toggleRepeat` control) and the Cadence
    /// face's Repeat pill calls it directly. Keeping one definition is what makes
    /// the two faces coherent — a listener who presses Repeat twice gets `.one` in
    /// either skin.
    public var nextInCycle: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}
