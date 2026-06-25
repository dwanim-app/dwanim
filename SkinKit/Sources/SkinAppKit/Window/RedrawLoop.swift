import Foundation
import PlayerCore
import SpectrumKit

// MARK: - RedrawLoop
//
// The reusable ~25 Hz redraw cadence + audio-tap wiring shared by the live,
// animating skin windows (the main bitmap window and the default-skin player).
// It owns the repeating main-run-loop timer and the tap install/remove, and
// stashes the latest PCM into a `SpectrumFeed` (the audio thread does the
// minimum: store + return). The window's per-tick work is injected as a closure.
//
// The two non-animating windows (playlist, EQ) do NOT use this — they redraw
// only in response to a gesture, so they own no timer and install no tap.

/// Drives a repeating main-run-loop timer and (optionally) an audio tap that
/// feeds a `SpectrumFeed`. Construction does nothing; `start` installs the tap
/// and schedules the timer, `stop` tears both down.
public final class RedrawLoop {
    private let interval: TimeInterval
    private let tap: AudioTapProviding?
    private let feed: SpectrumFeed
    private let onTick: () -> Void
    private var timer: Timer?

    /// - Parameters:
    ///   - interval: the timer period (seconds). The harness uses 0.04 for the
    ///     bitmap window (~25 Hz) and 0.045 for the default-skin player (~22 Hz).
    ///   - tap: the engine's opt-in PCM tap, or `nil` when no audio is wired.
    ///   - feed: the lock-guarded latest-samples box the tap writes and the tick
    ///     reads.
    ///   - onTick: the per-tick work (advance + recompose + swap image). Runs on
    ///     the main run loop.
    public init(
        interval: TimeInterval,
        tap: AudioTapProviding?,
        feed: SpectrumFeed,
        onTick: @escaping () -> Void
    ) {
        self.interval = interval
        self.tap = tap
        self.feed = feed
        self.onTick = onTick
    }

    /// Install the audio tap (audio thread: stash the latest samples into the
    /// feed and return), fire one immediate tick, then schedule the repeating
    /// timer on `.common` so it keeps firing during window interaction.
    public func start() {
        tap?.installTap { [feed] samples, sampleRate in
            // AUDIO THREAD: minimum work — stash and return.
            feed.store(samples, sampleRate: sampleRate)
        }

        onTick()
        let timer = Timer(timeInterval: interval, repeats: true) { [onTick] _ in
            onTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Invalidate the timer and remove the tap. Safe if nothing was installed.
    public func stop() {
        timer?.invalidate()
        timer = nil
        tap?.removeTap()
    }
}
