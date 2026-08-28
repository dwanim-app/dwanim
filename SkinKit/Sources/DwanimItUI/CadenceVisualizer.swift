import SwiftUI

// MARK: - CadenceVisualizer

/// The hero "LCD" visualiser well: a recessed rounded panel (`theme.lcd` fill,
/// inner hairline) holding a full-bleed row of spectrum bars.
///
/// ## Phase-4 — self-driven physics (pragmatic, Cadence-only)
/// The bars are no longer a static reflection of the incoming `levels`. A
/// `TimelineView(.animation)` runs a smooth ~60 fps loop that treats each frame's
/// `levels` as per-frame TARGET magnitudes and drives its OWN attack/decay
/// ballistics, peak-hold caps, and — when there is no real signal — a pair of
/// drifting sine humps so the well is never a dead line. All the math is a faithful
/// port of the design prototype's `draw()` (see `VisualizerPhysics`).
///
/// This animation layer is **Cadence-only**: it consumes the already-published
/// `PlayerViewModel.levels` and never touches the shared `SpectrumAnalyzer` /
/// `SpectrumFeed` that the classic `.wsz` skin also reads. `DwanimItUI` stays pure
/// SwiftUI + `PlayerCore` — `TimelineView` and `Canvas` are both SwiftUI-native, so
/// no AppKit / AVFoundation is pulled in.
///
/// ### Incoming feed
/// `levels` is the 24-band log-frequency peak feed (`0...1`). It is linearly
/// resampled to the prototype's 26 display bars each frame, then a display-side
/// high-frequency roll-off (`0.6 + 0.4·(1−k)`) tilts the right edge down.
///
/// ### Idle vs data
/// A bar follows the resampled DATA only while `playing` AND the feed carries real
/// energy (its resampled max exceeds `signalThreshold`); otherwise every bar
/// follows the drifting idle humps. Paused, stopped, or a silent passage therefore
/// all drift. The ballistics smoothing itself blends the switch, so transitions are
/// never abrupt.
struct CadenceVisualizer: View {

    let theme: AppearanceTheme
    /// The live 24-band spectrum peak feed, each `0...1`.
    let levels: [Float]
    /// Whether transport is currently playing — selects the idle amplitude and
    /// gates the data-vs-idle decision.
    let playing: Bool

    /// Retained per-bar animation state (levels, peaks, last frame time). A plain
    /// reference type in `@State` so the `TimelineView` schedule — not a body
    /// observation — drives the redraw; mutating it inside `Canvas` never triggers a
    /// re-render loop.
    @State private var engine = VisualizerEngine()

    /// The well's fixed height (design: 118 px).
    private let wellHeight: CGFloat = 118
    /// Inner padding around the bars inside the well (design: 8 px).
    private let wellPadding: CGFloat = 8
    /// A bar follows live data only once the resampled feed peak clears this; below
    /// it (or while paused) the idle humps take over. A tuning knob.
    private let signalThreshold: Double = 0.02

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                engine.advance(
                    to: now,
                    levels: levels,
                    playing: playing,
                    signalThreshold: signalThreshold
                )
                paint(context: context, size: size)
            }
        }
        .padding(wellPadding)
        .frame(height: wellHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.lcd)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    // MARK: - Paint

    /// Draw the current bar levels + peak caps, faithful to the prototype's bar
    /// branch: `barW = max(2, w/26 − 2.5)`, `bh = max(2, lv·(h−4))`, corner radius
    /// 1.2, a vertical `accent@0.95 → accent@0.34` gradient, and a 1.2 px white@0.3
    /// peak cap at `pk·(h−4)`.
    private func paint(context: GraphicsContext, size: CGSize) {
        let n = VisualizerPhysics.barCount
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return }

        let bw = w / CGFloat(n)
        let barW = max(2, bw - 2.5)
        let accent = theme.accent
        // C3 — the bar gradient (`accent@0.95 → accent@0.34`, vertical) is identical
        // for every bar and every frame's accent, so build it ONCE here rather than
        // re-allocating it 26× inside the per-bar loop. Per-bar the shading only
        // re-anchors its start/end points to that bar's rect.
        let barGradient = Gradient(colors: [accent.opacity(0.95), accent.opacity(0.34)])

        for i in 0 ..< n {
            let level = CGFloat(engine.level(at: i))
            let peak = CGFloat(engine.peak(at: i))

            let x = CGFloat(i) * bw + (bw - barW) / 2
            let bh = max(2, level * (h - 4))
            let barRect = CGRect(x: x, y: h - bh, width: barW, height: bh)

            context.fill(
                Path(roundedRect: barRect, cornerRadius: 1.2, style: .continuous),
                with: .linearGradient(
                    barGradient,
                    startPoint: CGPoint(x: barRect.midX, y: barRect.minY),
                    endPoint: CGPoint(x: barRect.midX, y: barRect.maxY)
                )
            )

            let py = max(0.5, h - peak * (h - 4) - 1.2)
            context.fill(
                Path(CGRect(x: x, y: py, width: barW, height: 1.2)),
                with: .color(.white.opacity(0.3))
            )
        }
    }
}

// MARK: - VisualizerEngine

/// The retained, stateful glue between the `TimelineView` clock and the pure
/// `VisualizerPhysics` seams: it holds the per-bar level (`lv`) and peak (`pk`)
/// arrays and the last frame timestamp, and advances them one frame per redraw.
///
/// Deliberately a plain (non-`@Observable`) `final class` held in `@State`: SwiftUI
/// keeps it alive across renders but does not observe its fields, so the per-frame
/// mutation the `Canvas` closure performs cannot spin a render loop — the
/// `TimelineView(.animation)` schedule is the sole driver. It contains no pixel /
/// AppKit code; all arithmetic delegates to `VisualizerPhysics`, which is what the
/// unit tests exercise.
final class VisualizerEngine {

    private var lv: [Double]
    private var pk: [Double]
    private var lastTime: Double?

    /// Clamp on the per-frame `dt` so a long gap (view offscreen, clock jump) snaps
    /// smoothly instead of producing a pathological step.
    private let maxDt: Double = 0.25

    init() {
        let n = VisualizerPhysics.barCount
        lv = [Double](repeating: 0, count: n)
        pk = [Double](repeating: 0, count: n)
    }

    /// The smoothed level for bar `i` (`0...1`).
    func level(at i: Int) -> Double { lv[i] }
    /// The peak-hold cap for bar `i` (`0...1`).
    func peak(at i: Int) -> Double { pk[i] }

    /// Advance every bar one frame toward its target for the wall-clock `now`
    /// (seconds). The first call only seeds `lastTime` (dt 0, no movement).
    func advance(to now: Double, levels: [Float], playing: Bool, signalThreshold: Double) {
        let dt: Double
        if let last = lastTime {
            dt = min(max(now - last, 0), maxDt)
        } else {
            dt = 0
        }
        lastTime = now

        let n = VisualizerPhysics.barCount
        // Revive the structurally-dead leading feed bands (the shared analyzer leaves
        // the lowest ~5–6 log-frequency bands with no FFT bin at fftSize 512) so the
        // LEFT bars track real bass, then resample the 24-band feed onto the 26 bars.
        // Display-only: the shared feed the classic skin reads is untouched.
        let compensated = VisualizerPhysics.bassCompensated(levels.map(Double.init))
        let resampled = VisualizerPhysics.resample(compensated, to: n)
        let maxLevel = resampled.max() ?? 0
        let useData = playing && maxLevel > signalThreshold

        for i in 0 ..< n {
            let k = Double(i) / Double(n - 1)
            let target: Double
            if useData {
                // Display-side high-frequency roll-off, faithful to the prototype.
                target = resampled[i] * (0.6 + 0.4 * (1 - k))
            } else {
                target = VisualizerPhysics.idleTarget(k: k, t: now, playing: playing)
            }
            lv[i] = VisualizerPhysics.step(level: lv[i], target: target, dt: dt)
            pk[i] = VisualizerPhysics.peak(prev: pk[i], level: lv[i], dt: dt)
        }
    }
}
