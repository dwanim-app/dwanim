import XCTest

@testable import DwanimItUI

// MARK: - VisualizerEngineTests

/// Tests for `VisualizerEngine`, the retained, stateful glue between the
/// `TimelineView` clock and the pure `VisualizerPhysics` seams. Where
/// `VisualizerPhysicsTests` pins the pure arithmetic (step / peak / resample /
/// idleTarget / bassCompensated) in isolation, these pin the ENGINE's own
/// composition that lives ONLY here and is otherwise unguarded:
///   - the data-vs-idle switch (`playing && maxLevel > signalThreshold`);
///   - the display-side high-frequency roll-off applied to the resampled data;
///   - the first-frame `dt == 0` seeding (time set, nothing moves);
///   - the `maxDt` (0.25 s) clamp on a huge inter-frame gap.
///
/// The engine is View-free and reachable via `@testable`, so every frame is driven
/// in memory with a synthetic wall clock — no `Canvas` / `TimelineView` involved.
final class VisualizerEngineTests: XCTestCase {

    /// One 60 fps frame.
    private let frame: Double = 1.0 / 60.0
    /// The engine's fixed signal gate (mirrors `CadenceVisualizer.signalThreshold`).
    private let threshold: Double = 0.02

    // MARK: - Helpers

    /// A flat 24-band feed at `magnitude`.
    private func feed(_ magnitude: Float) -> [Float] {
        [Float](repeating: magnitude, count: 24)
    }

    /// Seed the engine at t=0 (dt 0, no movement) then drive `frames` further frames
    /// at 60 fps with the given feed / flags, and return the settled bar profile.
    private func settleProfile(
        feed levels: [Float],
        playing: Bool,
        threshold: Double,
        frames: Int = 200
    ) -> [Double] {
        let engine = VisualizerEngine()
        engine.advance(to: 0, levels: levels, playing: playing, signalThreshold: threshold)
        var t = 0.0
        for _ in 0 ..< frames {
            t += frame
            engine.advance(to: t, levels: levels, playing: playing, signalThreshold: threshold)
        }
        return (0 ..< VisualizerPhysics.barCount).map { engine.level(at: $0) }
    }

    /// Whether the probed bar's SETTLED value differs between a quiet and a loud feed
    /// driven through an IDENTICAL clock schedule. In DATA mode the bar tracks the
    /// feed → the two differ; in IDLE mode the feed is ignored (only `now` drives the
    /// humps, which is identical for both) → the two are equal. A `now`-independent
    /// detector of which side of the switch the engine took, robust to the drifting
    /// idle humps.
    private func respondsToFeed(
        playing: Bool,
        threshold: Double,
        low: Float,
        high: Float,
        probe: Int = 5
    ) -> Bool {
        let quiet = settleProfile(feed: feed(low), playing: playing, threshold: threshold)[probe]
        let loud = settleProfile(feed: feed(high), playing: playing, threshold: threshold)[probe]
        return abs(quiet - loud) > 1e-6
    }

    // MARK: - Data path (playing + signal above threshold)

    func testPlayingSignalAboveThresholdDrivesBarsFromData() {
        // A loud broadband feed, playing and above threshold, takes the DATA branch:
        // a low/mid display bar climbs well clear of the 0.03 floor toward its
        // roll-off-tilted data target — not pinned down, not merely idle-drifting.
        let profile = settleProfile(feed: feed(0.9), playing: true, threshold: threshold)
        XCTAssertGreaterThan(profile[2], 0.6,
                             "A loud feed drives the low/mid bar high off the floor (data path)")
        // The flat feed is tilted right-down by the engine's display roll-off
        // (0.6 + 0.4·(1−k)), so the left bar out-reads the right — the DATA shape, not
        // a flat mirror of the feed. (Roll-off lives in the engine, untested elsewhere.)
        XCTAssertGreaterThan(profile[0], profile[VisualizerPhysics.barCount - 1],
                             "The display roll-off tilts the right edge below the left")
    }

    func testLouderDataSettlesBarHigher() {
        // Both feeds are above threshold (data path); the bar follows the DATA
        // magnitude, so louder settles higher rather than at a fixed shape.
        let quiet = settleProfile(feed: feed(0.2), playing: true, threshold: threshold)[2]
        let loud = settleProfile(feed: feed(0.9), playing: true, threshold: threshold)[2]
        XCTAssertGreaterThan(loud, quiet,
                             "A louder feed settles the bar higher (bars track the data level)")
    }

    // MARK: - Idle path (paused OR silent → humps, not data-zero)

    func testPausedFollowsIdleHumpsNotDataZero() {
        // Paused with a dead-zero feed: the switch must take the IDLE branch, so the
        // well drifts on the humps instead of pinning every bar to the data-zero
        // floor. At least one bar sits well above the 0.03 floor.
        let profile = settleProfile(feed: feed(0), playing: false, threshold: threshold)
        XCTAssertGreaterThan(profile.max() ?? 0, 0.2,
                             "A paused well drifts on the idle humps, not pinned to the floor")
    }

    func testSilentPlayingFollowsIdleHumpsNotDataZero() {
        // Playing but silent (max ≤ threshold): still the IDLE branch (the humps use
        // the livelier playing amplitude), never a flat data-zero floor.
        let profile = settleProfile(feed: feed(0.01), playing: true, threshold: threshold)
        XCTAssertGreaterThan(profile.max() ?? 0, 0.2,
                             "A silent (sub-threshold) playing well drifts on the humps, not the floor")
    }

    // MARK: - First frame seeds time only (dt == 0)

    func testFirstAdvanceSeedsTimeAndMovesNothing() {
        // The very first advance has no prior timestamp, so dt is 0: it seeds the
        // clock and moves no bar (levels stay at the init 0, peaks at 0), even with a
        // maxed feed that would otherwise slam the bars up.
        let engine = VisualizerEngine()
        engine.advance(to: 123.456, levels: feed(1.0), playing: true, signalThreshold: threshold)
        for i in 0 ..< VisualizerPhysics.barCount {
            XCTAssertEqual(engine.level(at: i), 0, accuracy: 1e-12,
                           "First advance seeds time only (dt 0) — bar \(i) does not move")
            XCTAssertEqual(engine.peak(at: i), 0, accuracy: 1e-12,
                           "First advance leaves peak cap \(i) at 0")
        }
    }

    // MARK: - Huge inter-frame gap is clamped to maxDt (engine-level)

    func testHugeInterFrameGapIsClampedToMaxDt() {
        // The "huge dt after backgrounding" guard lives in the ENGINE (min(_, maxDt)),
        // not the pure `step`. A loud broadband DATA feed makes the per-bar target
        // independent of `now`, so ONLY dt can differ between the two runs — isolating
        // the clamp.
        let loud = feed(1.0)

        // A 10 s gap after seeding.
        let bigGap = VisualizerEngine()
        bigGap.advance(to: 0, levels: loud, playing: true, signalThreshold: threshold)
        bigGap.advance(to: 10, levels: loud, playing: true, signalThreshold: threshold)

        // Exactly one maxDt (0.25 s) gap after seeding.
        let clampRef = VisualizerEngine()
        clampRef.advance(to: 0, levels: loud, playing: true, signalThreshold: threshold)
        clampRef.advance(to: 0.25, levels: loud, playing: true, signalThreshold: threshold)

        for i in 0 ..< VisualizerPhysics.barCount {
            XCTAssertEqual(bigGap.level(at: i), clampRef.level(at: i), accuracy: 1e-9,
                           "A 10 s gap advances no further than a single 0.25 s (maxDt) step — bar \(i)")
        }
        // And the clamped single step genuinely MOVED (guards a degenerate all-zero
        // match): the bars are off the init floor.
        XCTAssertGreaterThan(bigGap.level(at: 0), 0.1,
                             "The clamped step still advances the bars (not a frozen no-op)")
    }

    // MARK: - The switch honors BOTH playing and the threshold

    func testSwitchHonorsPlayingAndThreshold() {
        // Above threshold + playing → DATA: the bar responds to the feed.
        XCTAssertTrue(respondsToFeed(playing: true, threshold: threshold, low: 0.3, high: 0.9),
                      "Playing + above threshold takes the DATA branch (feed changes the bar)")
        // Below threshold + playing → IDLE: the feed is ignored (both sub-threshold
        // feeds land on the same humps).
        XCTAssertFalse(respondsToFeed(playing: true, threshold: threshold, low: 0.005, high: 0.015),
                       "Playing but sub-threshold takes the IDLE branch (feed ignored)")
        // Above threshold but NOT playing → IDLE: `playing` gates it regardless of
        // signal, so the feed is again ignored.
        XCTAssertFalse(respondsToFeed(playing: false, threshold: threshold, low: 0.3, high: 0.9),
                       "Above threshold but paused takes the IDLE branch (playing gates it)")
    }
}
