import Foundation
import Observation

// MARK: - PlayerViewModel

/// The observable presentation state that is **not** part of `PlayerCore`'s
/// transport: the live playback clock (`currentTime` / `duration`) and the
/// spectrum bar `levels`.
///
/// `PlayerCore` deliberately keeps `currentTime` / `duration` as computed
/// pass-throughs to its engine (not stored `@Observable` properties) and never
/// touches PCM, so a SwiftUI view cannot observe them changing. This view-model
/// is the bridge: the harness drives a main-thread timer that copies the engine
/// clock into `currentTime` / `duration` and pushes analyzer output into
/// `levels`, and the view observes this object for those values while observing
/// the core directly for transport state (`isPlaying`, `currentTrack`, …).
///
/// It is `@MainActor` because every writer is the main-thread timer / tap hop
/// and every reader is the SwiftUI view; keeping it main-actor-isolated means no
/// locking is needed and the `@Observable` mutations are always on the actor the
/// view renders on.
@MainActor
@Observable
public final class PlayerViewModel {

    /// Live playback position in seconds. Sanitised to a finite, non-negative
    /// value on write so a transient engine `NaN`/`inf` can never reach the
    /// progress math.
    public var currentTime: TimeInterval = 0

    /// Length of the current track in seconds. Sanitised to finite, non-negative.
    public var duration: TimeInterval = 0

    /// The latest spectrum bar levels, each in `0...1`. Empty until audio flows.
    public var levels: [Float] = []

    public init(currentTime: TimeInterval = 0, duration: TimeInterval = 0, levels: [Float] = []) {
        self.currentTime = PlayerViewModel.sanitize(currentTime)
        self.duration = PlayerViewModel.sanitize(duration)
        self.levels = levels
    }

    // MARK: - Updates

    /// Copy the engine clock into the model in one call (the harness timer's
    /// entry point), sanitising both values. Keeping the sanitise in one place
    /// means the view's `progress` never has to defend against bad input.
    public func updateClock(currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = PlayerViewModel.sanitize(currentTime)
        self.duration = PlayerViewModel.sanitize(duration)
    }

    // MARK: - Derived

    /// Playback progress in `0...1`: `currentTime / duration`, clamped. `0` when
    /// the duration is not yet known (or zero), so the progress bar reads empty
    /// rather than dividing by zero.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    // MARK: - Helpers

    /// Clamp a time value to a finite, non-negative number; non-finite input
    /// (`NaN`/`±inf`) becomes `0`.
    private static func sanitize(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}
