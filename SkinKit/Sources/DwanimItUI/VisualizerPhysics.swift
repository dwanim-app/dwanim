import Foundation

// MARK: - VisualizerPhysics

/// The pure, view-agnostic ballistics of the default (Cadence) spectrum well:
/// per-bar attack/decay smoothing, peak-hold fall, the idle drifting-hump target,
/// and the incoming-feed resample. These are a faithful port of the design
/// prototype's `draw()` loop (see `design_handoff_cadence_player`), lifted OUT of
/// the `TimelineView`/`Canvas` render so every constant is unit-testable in memory
/// without drawing a pixel (the `EQSliderMath` / `SeekMath` pattern).
///
/// ## Pragmatic architecture
/// This is a Cadence-ONLY animation layer. It drives its OWN ~60 fps smoothing
/// over the incoming `PlayerViewModel.levels` (treated as per-frame TARGET
/// magnitudes) and never touches the shared `SpectrumAnalyzer` / `SpectrumFeed`
/// that the classic `.wsz` skin also reads. `DwanimItUI` stays SwiftUI + PlayerCore.
///
/// ## Frame-rate independence
/// The prototype's per-frame smoothing constants assume a fixed 60 fps
/// (`requestAnimationFrame`). Here every step takes the real elapsed `dt` and
/// converts the per-frame α to `1 - pow(1 - α, dt * 60)`, so the motion looks the
/// same on a 60 Hz, 120 Hz ProMotion, or a stuttering display. At `dt == 1/60`
/// this collapses back to the prototype's exact constants.
enum VisualizerPhysics {

    // MARK: - Constants (faithful to the prototype)

    /// Display bar count. The prototype maps its FFT to 26 bars; the incoming
    /// 24-band feed is linearly resampled to this width.
    static let barCount = 26

    /// Per-frame smoothing α while a bar is RISING toward its target (fast attack).
    static let attackAlpha: Double = 0.3
    /// Per-frame smoothing α while a bar is FALLING toward its target (slow decay).
    static let decayAlpha: Double = 0.08

    /// The clamp floor applied to every target: a bar never aims below this, so an
    /// idle / silent well settles to a faint baseline rather than a dead 0 line.
    static let floorLevel: Double = 0.03
    /// The clamp ceiling applied to every target.
    static let ceilLevel: Double = 1.0

    /// How far a peak-hold cap falls per 60 fps frame (no dwell — faithful to the
    /// prototype's `pk = max(lv, pk - 0.005)`).
    static let peakFallPerFrame: Double = 0.005

    // MARK: - Bass-fill (Cadence display-only low-band revival)

    /// How many of the LOWEST feed bands the bass-fill may lift. The shared
    /// `SpectrumAnalyzer` groups its `fftSize`-512 magnitude bins onto a
    /// log-frequency scale, and at that resolution the first positive FFT bin
    /// (≈86 Hz at 44.1 kHz) already lands in band ~5 of 24 — so the lowest handful
    /// of bands (and the odd interior gap like band 6) receive NO bin and read a
    /// structurally dead ~0 no matter the audio. Only bands below this index are
    /// eligible to borrow energy; everything above is passed through untouched so
    /// the crisp mid/high spectral detail is preserved. Sized with a margin over
    /// the observed dead zone (≈5–6 bands) so higher sample rates stay covered.
    static let bassFillBands = 8

    /// How many higher neighbours a low band may borrow from. Bounds the reach of
    /// the downward bleed so a dead low bar is lit by the nearest LIVE bass band
    /// rather than by distant mids.
    static let bassFillSpread = 8

    /// Per-step geometric decay of the borrowed energy. A low band takes the MAX of
    /// its own value and each higher neighbour scaled by `falloff^distance`, so the
    /// revived bars form a gently descending bass slope driven by the real low-end
    /// energy — and, because it is a decayed MAX of existing bands, a revived bar can
    /// never exceed the source band's level (no runaway low-end amplification).
    static let bassFillFalloff: Double = 0.85

    // MARK: - Ballistics

    /// One attack/decay smoothing step for a single bar.
    ///
    /// The DIRECTION (attack vs decay) is chosen from the raw `target` vs the
    /// current `level` — exactly as the prototype does — while the MAGNITUDE uses
    /// the target clamped into `floorLevel ... ceilLevel`. `dt` is the real elapsed
    /// seconds; the per-frame α is normalised to it so the result is frame-rate
    /// independent (`dt == 1/60` reproduces the prototype's 0.3 / 0.08 exactly).
    static func step(level: Double, target: Double, dt: Double) -> Double {
        let rising = target > level
        let clamped = min(max(target, floorLevel), ceilLevel)
        let alpha = normalizedAlpha(rising ? attackAlpha : decayAlpha, dt: dt)
        return level + (clamped - level) * alpha
    }

    /// One peak-hold step: the cap tracks the bar UP instantly (it can only rise to
    /// meet `level`, never above it) and falls linearly at `peakFallPerFrame` per
    /// 60 fps frame. The fall is scaled by the real elapsed `dt` so the cap drifts
    /// down at the same wall-clock rate on any refresh rate.
    static func peak(prev: Double, level: Double, dt: Double) -> Double {
        let fall = peakFallPerFrame * frameScale(dt)
        return max(level, prev - fall)
    }

    // MARK: - Idle drift

    /// The idle / no-signal target for a bar at normalised position `k` (`0` = left,
    /// `1` = right) and wall-clock `t` seconds. Two drifting Gaussian humps keep the
    /// well alive when there is no real audio; `playing` selects the amplitude
    /// (`0.95` while playing a silent passage, `0.7` while paused) so a paused well
    /// still breathes rather than reading as a dead line.
    ///
    /// A faithful port of the prototype's else-branch. The result is NOT clamped
    /// here (it can reach ~1.04 at a hump crest); `step` applies the `0.03 ... 1`
    /// clamp when it consumes this as a target.
    static func idleTarget(k: Double, t: Double, playing: Bool) -> Double {
        let amp = playing ? 0.95 : 0.7
        let hump = exp(-pow((k - (0.45 + 0.32 * sin(t * 0.33))) / 0.27, 2))
        let hump2 = exp(-pow((k - (0.20 + 0.16 * sin(t * 0.57 + 1.6))) / 0.20, 2))
        return amp * (0.24 + 0.76 * (0.62 * hump + 0.5 * hump2)) * (1 - 0.4 * k)
    }

    // MARK: - Bass-fill

    /// Revive the structurally-dead leading feed bands so the Cadence well's LEFT
    /// bars respond to bass, WITHOUT touching the shared `SpectrumAnalyzer` /
    /// `SpectrumFeed` (the classic `.wsz` skin keeps its original, weaker low end).
    ///
    /// The shared feed's lowest ~5–6 log-frequency bands carry no FFT bin at
    /// `fftSize` 512 (the first positive bin already falls in band ~5), so they read
    /// a dead ~0 during playback and their display bars sit pinned at the `floorLevel`
    /// clamp. This pure display-side transform lets each of the lowest `bassFillBands`
    /// bands take the MAX of its own value and a geometrically-decayed sample of its
    /// higher neighbours (up to `bassFillSpread` away), so a dead low band borrows a
    /// descending fraction of the nearest LIVE bass band. Properties:
    ///
    /// - A live band is never dimmed — the `max` with its own value (offset 0,
    ///   weight 1) only ever LIFTS a band toward a livelier neighbour above it.
    /// - A revived band never exceeds the source band's level (decayed max ⇒ no
    ///   runaway low-end amplification), so the overall dynamic range is unchanged.
    /// - Silence stays silent (all-zero in ⇒ all-zero out), so the idle-vs-data gate
    ///   in `VisualizerEngine` still flips to the drifting humps on a quiet passage.
    /// - Only the lowest `bassFillBands` are eligible; higher bands pass through
    ///   verbatim, keeping the mid/high spectral detail crisp.
    ///
    /// An input shorter than two elements is returned unchanged.
    static func bassCompensated(_ levels: [Double]) -> [Double] {
        guard levels.count > 1 else { return levels }
        let lowRegion = min(bassFillBands, levels.count)
        var out = levels
        for i in 0 ..< lowRegion {
            var lifted = levels[i]
            var weight = bassFillFalloff
            var distance = 1
            while distance <= bassFillSpread, i + distance < levels.count {
                lifted = max(lifted, levels[i + distance] * weight)
                weight *= bassFillFalloff
                distance += 1
            }
            out[i] = lifted
        }
        return out
    }

    // MARK: - Resample

    /// Linearly resample `input` to exactly `n` samples, preserving both endpoints
    /// (`out[0] == input.first`, `out[n-1] == input.last`). Used to map the 24-band
    /// incoming feed onto the 26 display bars. An empty / single-value input fills
    /// the output with that value (or `0`); `n <= 0` yields an empty array.
    static func resample(_ input: [Double], to n: Int) -> [Double] {
        guard n > 0 else { return [] }
        guard let first = input.first else { return Array(repeating: 0, count: n) }
        guard input.count > 1, n > 1 else { return Array(repeating: first, count: n) }

        let last = input.count - 1
        var out = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            let pos = Double(i) / Double(n - 1) * Double(last)
            let lo = Int(pos.rounded(.down))
            let hi = min(lo + 1, last)
            let frac = pos - Double(lo)
            out[i] = input[lo] * (1 - frac) + input[hi] * frac
        }
        return out
    }

    // MARK: - dt scaling

    /// The per-frame α (calibrated at 60 fps) converted to the real elapsed `dt`:
    /// `1 - pow(1 - α, dt * 60)`. A non-finite or non-positive `dt` yields `0` (no
    /// movement this frame — safe for the first frame and for a paused clock).
    private static func normalizedAlpha(_ alpha: Double, dt: Double) -> Double {
        guard dt.isFinite, dt > 0 else { return 0 }
        let a = min(max(alpha, 0), 1)
        return 1 - pow(1 - a, dt * 60)
    }

    /// The number of 60 fps frames represented by `dt` seconds (`dt * 60`), used to
    /// scale the linear peak fall. A non-finite / negative `dt` falls back to one
    /// frame; `dt == 0` yields `0` (the cap holds).
    private static func frameScale(_ dt: Double) -> Double {
        guard dt.isFinite, dt >= 0 else { return 1 }
        return dt * 60
    }
}
