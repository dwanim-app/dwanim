import AVFoundation
import Foundation

// MARK: - TrackDurationLoader

/// Reads a media file's total duration WITHOUT loading it into the transport
/// engine, so the default face's playlist Time column can fill in for every
/// queued file — not only the one currently playing (the engine only knows the
/// loaded track's length).
///
/// This is the AVFoundation tier's home for the async `AVURLAsset.load(.duration)`
/// metadata read the app fires when files are added to the queue. `PlayerCore`
/// stays `Foundation`-only and never touches AVFoundation; it just receives the
/// resolved seconds back through `setDuration(_:forURL:)`. Keeping the read here
/// (not in `DwanimItUI`, which is pure SwiftUI + PlayerCore) preserves the module
/// tiers.
public enum TrackDurationLoader {

    /// The duration of the media at `url` in seconds, or `nil` when it cannot be
    /// read (unreadable / not a media file) or resolves to a non-finite or
    /// non-positive value.
    ///
    /// The `AVURLAsset.load(.duration)` read runs on AVFoundation's own executor,
    /// not the caller's actor, so `await`-ing it from the main actor never blocks
    /// the UI — it is a plain suspension. Fire-and-forget at the call site: a file
    /// whose duration cannot be read simply keeps its "—".
    public static func duration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let cmDuration = try? await asset.load(.duration) else { return nil }
        let seconds = cmDuration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}
