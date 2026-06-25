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
@MainActor
public final class RedrawLoop {
    private let interval: TimeInterval
    private let tap: AudioTapProviding?
    private let feed: SpectrumFeed
    private let onTick: @Sendable @MainActor () -> Void
    private var timer: Timer?

    /// - Parameters:
    ///   - interval: the timer period (seconds). The harness uses 0.04 for the
    ///     bitmap window (~25 Hz) and 0.045 for the default-skin player (~22 Hz).
    ///   - tap: the engine's opt-in PCM tap, or `nil` when no audio is wired.
    ///   - feed: the lock-guarded latest-samples box the tap writes and the tick
    ///     reads.
    ///   - onTick: the per-tick work (advance + recompose + swap image). Runs on
    ///     the main run loop, hence `@MainActor` — the timer is scheduled on
    ///     `RunLoop.main`, so the tick fires on the main thread.
    ///
    /// `@MainActor`: the loop is created, started, and stopped on the main actor
    /// (by the window controllers), and its `Timer` is added to `RunLoop.main`. The
    /// ONLY thing that legitimately runs off-actor is the audio tap closure, which
    /// is built `@Sendable` in `start()` and writes only the `Sendable` feed.
    public init(
        interval: TimeInterval,
        tap: AudioTapProviding?,
        feed: SpectrumFeed,
        onTick: @escaping @Sendable @MainActor () -> Void
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
        // Idempotent: a second start() must not orphan the first timer (leak +
        // double-rate ticks) or stack a second tap. Tear down any prior loop
        // first so the normal single-start path is unchanged.
        stop()

        // The tap closure runs on the AUDIO render thread, hence `@Sendable`; it
        // captures only the `Sendable` `feed` and does the minimum (store + return).
        tap?.installTap { [feed] samples, sampleRate in
            // AUDIO THREAD: minimum work — stash and return.
            feed.store(samples, sampleRate: sampleRate)
        }

        onTick()
        // The `Timer` body is `@Sendable` (it may run off the creating context), so
        // it cannot capture `self` or the `@MainActor onTick` directly. It captures
        // the `@MainActor`-isolated `onTick` (itself `Sendable`) and re-enters the
        // main actor via `assumeIsolated` — sound because the timer is added to
        // `RunLoop.main`, so it always fires on the main thread.
        let timer = Timer(timeInterval: interval, repeats: true) { [onTick] _ in
            MainActor.assumeIsolated { onTick() }
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
