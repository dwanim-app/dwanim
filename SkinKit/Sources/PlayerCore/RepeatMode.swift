import Foundation

// MARK: - RepeatMode

/// How playback proceeds when a track ends or the listener skips past a boundary.
public enum RepeatMode: Sendable, Equatable {
    /// Stop after the last track; do not wrap.
    case off
    /// Wrap around the playlist end-to-end.
    case all
    /// Repeat the current track indefinitely.
    case one
}
