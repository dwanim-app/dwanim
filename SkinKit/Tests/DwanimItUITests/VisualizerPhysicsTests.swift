import XCTest

@testable import DwanimItUI

// MARK: - VisualizerPhysicsTests

/// Tests for `VisualizerPhysics`, the pure ballistics of the default (Cadence)
/// spectrum well: attack/decay smoothing, peak-hold fall, the idle drifting-hump
/// target, and the 24 -> 26 feed resample. Every constant is a faithful port of the
/// design prototype's `draw()` loop; the enum touches no View, so the physics are
/// asserted entirely in memory (the `TimelineView`/`Canvas` render is not
/// unit-tested — only these seams are).
final class VisualizerPhysicsTests: XCTestCase {

    /// One 60 fps frame, the calibration point where the dt-normalised α collapses
    /// back to the prototype's raw per-frame constants.
    private let frame60: Double = 1.0 / 60.0

    // MARK: - step: attack vs decay

    func testAttackAtSixtyFpsMatchesPrototypeConstant() {
        // Rising: target > level -> α 0.3. From 0 toward 1: 0 + (1-0)*0.3 = 0.3.
        let result = VisualizerPhysics.step(level: 0, target: 1, dt: frame60)
        XCTAssertEqual(result, 0.3, accuracy: 1e-9,
                       "At 60 fps the rising step reproduces the prototype's 0.3 attack")
    }

    func testDecayAtSixtyFpsMatchesPrototypeConstant() {
        // Falling: target < level -> α 0.08. From 1 toward 0 (clamped to floor 0.03):
        // 1 + (0.03 - 1)*0.08 = 1 - 0.0776 = 0.9224.
        let result = VisualizerPhysics.step(level: 1, target: 0, dt: frame60)
        XCTAssertEqual(result, 0.9224, accuracy: 1e-9,
                       "At 60 fps the falling step reproduces the prototype's 0.08 decay")
    }

    func testAttackIsFasterThanDecayOverEqualDistance() {
        // Symmetric distance of 0.4 around a midpoint, one 60 fps frame each.
        let rose = VisualizerPhysics.step(level: 0.5, target: 0.9, dt: frame60) - 0.5
        let fell = 0.5 - VisualizerPhysics.step(level: 0.5, target: 0.1, dt: frame60)
        XCTAssertGreaterThan(rose, fell,
                             "Attack must cover more ground than decay for the same distance")
    }

    func testAttackMovesTowardTargetWithoutOvershoot() {
        let result = VisualizerPhysics.step(level: 0.1, target: 0.9, dt: frame60)
        XCTAssertGreaterThan(result, 0.1, "A rising step moves up")
        XCTAssertLessThan(result, 0.9, "A single step does not overshoot the target")
    }

    // MARK: - step: clamp floor 0.03

    func testTargetBelowFloorIsClampedToFloor() {
        // target 0 is below the 0.03 floor; the step aims at 0.03, not 0.
        // From level 0.03 with target 0: raw 0 < 0.03 -> decay; clamped target 0.03
        // -> no movement (already at floor).
        let result = VisualizerPhysics.step(level: 0.03, target: 0, dt: frame60)
        XCTAssertEqual(result, 0.03, accuracy: 1e-9,
                       "A bar already at the floor with a sub-floor target does not move")
    }

    func testLevelNeverConvergesBelowFloor() {
        // Drive many frames with target 0; the level must settle at the 0.03 floor.
        var level = 0.8
        for _ in 0 ..< 2000 {
            level = VisualizerPhysics.step(level: level, target: 0, dt: frame60)
        }
        XCTAssertEqual(level, 0.03, accuracy: 1e-6,
                       "With a zero target the bar decays to the floor, never below")
        XCTAssertGreaterThanOrEqual(level, 0.03, "The bar never drops under the floor")
    }

    func testTargetAboveCeilIsClampedToOne() {
        // A hump-crest target above 1 must not push the level past 1.
        var level = 0.5
        for _ in 0 ..< 2000 {
            level = VisualizerPhysics.step(level: level, target: 1.5, dt: frame60)
        }
        XCTAssertEqual(level, 1.0, accuracy: 1e-6,
                       "An over-unity target clamps to 1; the level converges to 1")
        XCTAssertLessThanOrEqual(level, 1.0, "The level never exceeds the ceiling")
    }

    // MARK: - step: frame-rate independence

    func testStepIsFrameRateIndependent() {
        // One step at 1/30 s must equal two consecutive steps at 1/60 s.
        let oneBig = VisualizerPhysics.step(level: 0, target: 1, dt: 1.0 / 30.0)
        let first = VisualizerPhysics.step(level: 0, target: 1, dt: frame60)
        let twoSmall = VisualizerPhysics.step(level: first, target: 1, dt: frame60)
        XCTAssertEqual(oneBig, twoSmall, accuracy: 1e-9,
                       "A double-length frame equals two single frames (dt-normalised α)")
    }

    func testStepAtSixtyFpsEqualsRawAlpha() {
        // dt == 1/60 must reproduce the raw prototype α with no scaling error.
        let result = VisualizerPhysics.step(level: 0.2, target: 0.8, dt: frame60)
        let expected = 0.2 + (0.8 - 0.2) * VisualizerPhysics.attackAlpha
        XCTAssertEqual(result, expected, accuracy: 1e-12,
                       "At 60 fps the normalised α is exactly the raw attack α")
    }

    func testZeroDtDoesNotMove() {
        let result = VisualizerPhysics.step(level: 0.4, target: 1, dt: 0)
        XCTAssertEqual(result, 0.4, accuracy: 1e-12,
                       "No elapsed time means no movement (safe first frame)")
    }

    func testNonFiniteDtDoesNotMove() {
        let result = VisualizerPhysics.step(level: 0.4, target: 1, dt: .nan)
        XCTAssertEqual(result, 0.4, accuracy: 1e-12,
                       "A NaN dt is treated as no movement, never a NaN level")
    }

    func testLargeDtConvergesTowardTargetWithoutBlowingUp() {
        // A huge dt (e.g. after the view was offscreen) should snap toward the
        // target, staying within [level, target] — never overshoot or diverge.
        let result = VisualizerPhysics.step(level: 0, target: 1, dt: 5)
        XCTAssertGreaterThan(result, 0.9, "A large dt nearly reaches the target")
        XCTAssertLessThanOrEqual(result, 1.0, "A large dt never overshoots the target")
    }

    // MARK: - peak: hold + fall

    func testPeakFallsAtPrototypeRateAtSixtyFps() {
        let result = VisualizerPhysics.peak(prev: 0.8, level: 0.2, dt: frame60)
        XCTAssertEqual(result, 0.795, accuracy: 1e-9,
                       "At 60 fps the cap falls exactly 0.005 toward the floor")
    }

    func testPeakRisesOnlyToMeetLevel() {
        // The cap tracks up to the level but never above it.
        let result = VisualizerPhysics.peak(prev: 0.2, level: 0.6, dt: frame60)
        XCTAssertEqual(result, 0.6, accuracy: 1e-12,
                       "A level above the cap pulls the cap up exactly to the level")
    }

    func testPeakNeverRisesAboveLevel() {
        // Even with a tiny fall, when level < prev the cap can only fall, never rise.
        let result = VisualizerPhysics.peak(prev: 0.9, level: 0.1, dt: frame60)
        XCTAssertLessThan(result, 0.9, "With level below the cap, the cap falls")
        XCTAssertGreaterThanOrEqual(result, 0.1, "The cap never drops below the level")
    }

    func testPeakFallIsFrameRateIndependent() {
        // One 1/30 s fall equals two 1/60 s falls (linear fall, dt-scaled).
        let oneBig = VisualizerPhysics.peak(prev: 0.9, level: 0.0, dt: 1.0 / 30.0)
        let first = VisualizerPhysics.peak(prev: 0.9, level: 0.0, dt: frame60)
        let twoSmall = VisualizerPhysics.peak(prev: first, level: 0.0, dt: frame60)
        XCTAssertEqual(oneBig, twoSmall, accuracy: 1e-12,
                       "A double-length frame falls as far as two single frames")
    }

    func testPeakZeroDtHolds() {
        let result = VisualizerPhysics.peak(prev: 0.7, level: 0.2, dt: 0)
        XCTAssertEqual(result, 0.7, accuracy: 1e-12,
                       "No elapsed time means the cap holds in place")
    }

    // MARK: - idleTarget

    func testIdleTargetIsBounded() {
        // Sweep k and t; the raw hump target stays within a sane [0, ~1.1] band.
        for step in 0 ... 40 {
            let k = Double(step) / 40.0
            for tStep in 0 ... 40 {
                let t = Double(tStep) * 0.37
                for playing in [true, false] {
                    let v = VisualizerPhysics.idleTarget(k: k, t: t, playing: playing)
                    XCTAssertTrue(v.isFinite, "Idle target is always finite")
                    XCTAssertGreaterThanOrEqual(v, 0, "Idle target is non-negative")
                    XCTAssertLessThanOrEqual(v, 1.1, "Idle target crest stays near 1")
                }
            }
        }
    }

    func testIdleTargetVariesWithTime() {
        let a = VisualizerPhysics.idleTarget(k: 0.4, t: 0, playing: true)
        let b = VisualizerPhysics.idleTarget(k: 0.4, t: 3.1, playing: true)
        XCTAssertNotEqual(a, b, accuracy: 1e-6,
                          "The humps drift over time, so the same bar changes")
    }

    func testIdlePlayingAmplitudeExceedsPaused() {
        // amp 0.95 (playing) scales the whole target above amp 0.7 (paused) wherever
        // the base is positive.
        let playing = VisualizerPhysics.idleTarget(k: 0.3, t: 1.2, playing: true)
        let paused = VisualizerPhysics.idleTarget(k: 0.3, t: 1.2, playing: false)
        XCTAssertGreaterThan(playing, paused,
                             "A playing (silent) well drifts livelier than a paused one")
    }

    func testIdleTargetRollsOffToTheRight() {
        // The (1 - 0.4k) tilt makes the far-right bar dimmer than the far-left at a
        // moment when both humps are near the left/centre.
        let t = 0.0
        let left = VisualizerPhysics.idleTarget(k: 0, t: t, playing: true)
        let right = VisualizerPhysics.idleTarget(k: 1, t: t, playing: true)
        XCTAssertGreaterThan(left, right,
                             "The right edge is tilted down relative to the left")
    }

    // MARK: - resample

    func testResampleLength() {
        let out = VisualizerPhysics.resample(Array(repeating: 0.5, count: 24), to: 26)
        XCTAssertEqual(out.count, 26, "Resample yields exactly the requested count")
    }

    func testResamplePreservesEndpoints() {
        let input = (0 ..< 24).map { Double($0) }
        let out = VisualizerPhysics.resample(input, to: 26)
        XCTAssertEqual(out.first, input.first, "The left endpoint is preserved")
        XCTAssertEqual(out.last, input.last, "The right endpoint is preserved")
    }

    func testResampleOfLinearRampStaysLinear() {
        // A straight ramp 0...1 over 24 must resample to a straight ramp over 26.
        let input = (0 ..< 24).map { Double($0) / 23.0 }
        let out = VisualizerPhysics.resample(input, to: 26)
        for i in 0 ..< 26 {
            let expected = Double(i) / 25.0
            XCTAssertEqual(out[i], expected, accuracy: 1e-9,
                           "A linear ramp resamples to a linear ramp at bar \(i)")
        }
    }

    func testResamplePreservesMonotonicity() {
        let input = (0 ..< 24).map { Double($0) * Double($0) }  // strictly increasing
        let out = VisualizerPhysics.resample(input, to: 26)
        for i in 1 ..< out.count {
            XCTAssertGreaterThanOrEqual(out[i], out[i - 1],
                                        "Monotonic input resamples to monotonic output")
        }
    }

    func testResampleEmptyInputYieldsZeros() {
        let out = VisualizerPhysics.resample([], to: 26)
        XCTAssertEqual(out.count, 26, "Empty input still yields the requested count")
        XCTAssertTrue(out.allSatisfy { $0 == 0 }, "Empty input yields all zeros")
    }

    func testResampleSingleValueFills() {
        let out = VisualizerPhysics.resample([0.42], to: 26)
        XCTAssertEqual(out.count, 26)
        XCTAssertTrue(out.allSatisfy { $0 == 0.42 }, "A single value fills the output")
    }

    func testResampleToZeroIsEmpty() {
        XCTAssertTrue(VisualizerPhysics.resample([1, 2, 3], to: 0).isEmpty,
                      "A non-positive count yields an empty array")
    }

    func testResampleIdentityWhenCountMatches() {
        let input = (0 ..< 26).map { Double($0) * 0.01 }
        let out = VisualizerPhysics.resample(input, to: 26)
        for i in 0 ..< 26 {
            XCTAssertEqual(out[i], input[i], accuracy: 1e-12,
                           "Resampling to the same count is the identity")
        }
    }

    // MARK: - bassCompensated (Cadence low-band revival)

    /// The bug: the shared analyzer leaves the lowest ~5 feed bands structurally
    /// dead (no FFT bin lands there at fftSize 512), so the Cadence well's LEFT bars
    /// pin to the floor even while bass plays. The fix must let those dead low bands
    /// borrow the real low-end energy sitting in the first LIVE band.
    func testBassCompensationLiftsDeadLowBandsFromLiveBass() {
        // Feed with a realistic dead low edge: bands 0–4 are 0 (no bin), band 5 is a
        // strong kick, everything else quiet.
        var levels = [Double](repeating: 0, count: 24)
        levels[5] = 0.8

        let out = VisualizerPhysics.bassCompensated(levels)

        // Every dead low band is now lifted well clear of the 0.03 idle floor.
        for i in 0 ..< 5 {
            XCTAssertGreaterThan(out[i], VisualizerPhysics.floorLevel,
                                 "Dead low band \(i) is revived above the idle floor")
        }
        // The revival forms a descending slope toward the left (each nearer to the
        // live band 5 is brighter than the one further away).
        for i in 1 ..< 5 {
            XCTAssertGreaterThan(out[i], out[i - 1],
                                 "Revived bands rise toward the live bass band (slope)")
        }
        // The live band itself is untouched (nothing above it to borrow from).
        XCTAssertEqual(out[5], 0.8, accuracy: 1e-12,
                       "The live bass band keeps its own level")
    }

    func testBassCompensationRevivesAnInteriorGapBand() {
        // Bin spacing also skips the odd interior band (e.g. band 6 at 44.1 kHz):
        // band 5 and band 7 are live, band 6 is a dead gap between them.
        var levels = [Double](repeating: 0, count: 24)
        levels[5] = 0.6
        levels[7] = 0.7
        let out = VisualizerPhysics.bassCompensated(levels)
        XCTAssertGreaterThan(out[6], VisualizerPhysics.floorLevel,
                             "An interior dead gap band is revived from its live neighbour")
    }

    func testBassCompensationNeverExceedsSourceEnergy() {
        // A decayed max can only borrow DOWN from an existing band, so no output bar
        // may exceed the loudest input band (no runaway low-end amplification).
        let levels: [Double] = [0, 0, 0, 0, 0, 0.8, 0.5, 0.9, 0.3] + [Double](repeating: 0.2, count: 15)
        let out = VisualizerPhysics.bassCompensated(levels)
        let inputMax = levels.max() ?? 0
        for (i, v) in out.enumerated() {
            XCTAssertLessThanOrEqual(v, inputMax + 1e-12,
                                     "Revived band \(i) never exceeds the source energy")
        }
    }

    func testBassCompensationLeavesHighBandsUntouched() {
        // Bands at/above bassFillBands pass through verbatim (crisp mid/high detail).
        let levels = (0 ..< 24).map { Double($0) / 23.0 }
        let out = VisualizerPhysics.bassCompensated(levels)
        for i in VisualizerPhysics.bassFillBands ..< 24 {
            XCTAssertEqual(out[i], levels[i], accuracy: 1e-12,
                           "High band \(i) is passed through unchanged")
        }
    }

    func testBassCompensationOfSilenceStaysZero() {
        // All-zero in → all-zero out, so the idle-vs-data gate still flips to the
        // drifting humps on a genuinely silent passage.
        let out = VisualizerPhysics.bassCompensated([Double](repeating: 0, count: 24))
        XCTAssertTrue(out.allSatisfy { $0 == 0 }, "Silence stays silent after bass-fill")
    }

    func testBassCompensationDoesNotDimLiveLowBands() {
        // A live low band is never pulled DOWN by the fill (the max keeps its own
        // value when nothing above it is louder after decay).
        let levels: [Double] = [0.4, 0.3, 0.2, 0.1, 0.05, 0.02] + [Double](repeating: 0, count: 18)
        let out = VisualizerPhysics.bassCompensated(levels)
        for i in 0 ..< 6 {
            XCTAssertGreaterThanOrEqual(out[i], levels[i] - 1e-12,
                                        "A live low band is never dimmed by the fill")
        }
    }

    /// End-to-end for the actual engine order: bass-fill THEN resample must leave the
    /// leftmost DISPLAY bars off the floor when only the low feed carries energy —
    /// the exact regression the owner reported.
    func testBassFilledLowFeedProducesNonFloorLeftDisplayBars() {
        var levels = [Double](repeating: 0, count: 24)
        levels[5] = 0.8 // a lone kick in the lowest live band
        let compensated = VisualizerPhysics.bassCompensated(levels)
        let resampled = VisualizerPhysics.resample(compensated, to: VisualizerPhysics.barCount)
        // The far-left display bars now carry real, non-floor magnitude.
        XCTAssertGreaterThan(resampled[0], VisualizerPhysics.floorLevel,
                             "Left display bar 0 tracks bass instead of pinning to the floor")
        XCTAssertGreaterThan(resampled[2], VisualizerPhysics.floorLevel,
                             "Left display bar 2 tracks bass instead of pinning to the floor")
    }
}
