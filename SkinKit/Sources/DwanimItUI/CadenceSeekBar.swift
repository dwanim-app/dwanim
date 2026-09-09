import PlayerCore
import SwiftUI

// MARK: - CadenceSeekBar

/// The hero seek row: an elapsed label, a thin draggable track, and a remaining
/// label (prefixed `−`). CLICK anywhere on the track to seek, or DRAG to scrub.
/// While scrubbing the track follows the cursor; on release the seek lands via
/// `SeekMath` and the live clock takes over again.
///
/// The gesture is only active when something seekable is loaded (`duration` finite
/// and `> 0`); otherwise the track renders as an inert empty rail. The
/// fraction→time mapping is the pure, unit-tested `SeekMath` (in `PlayerCore`), so
/// this view carries no seek math of its own.
struct CadenceSeekBar: View {

    let theme: AppearanceTheme
    /// Live playback position in seconds.
    let currentTime: TimeInterval
    /// Current track length in seconds (drives the seekability gate + time mapping).
    let duration: TimeInterval
    /// Called on click / drag-end with the absolute seek time in seconds.
    let onSeek: (TimeInterval) -> Void
    /// F4 — whether ANY track is loaded. With nothing loaded the time readouts show
    /// dashes rather than a fake `0:00` / `−0:00` clock (see `timeLabel`).
    var hasTrack: Bool = true

    /// The text a seek readout shows: the formatted clock while a track is loaded,
    /// a dash when nothing is. Pure, so the empty-queue readout is unit-tested
    /// without rendering. `remaining` adds the leading `−` to the clock form only.
    static func timeLabel(_ seconds: TimeInterval, hasTrack: Bool, remaining: Bool = false) -> String {
        guard hasTrack else { return "—" }
        return (remaining ? "−" : "") + CadenceTime.format(seconds)
    }

    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0

    private var isSeekable: Bool { duration.isFinite && duration > 0 }

    /// The live fraction from the clock, clamped to `0...1`.
    private var liveFraction: Double {
        SeekMath.fraction(currentTime: currentTime, duration: duration)
    }

    /// The fraction to display: the cursor while scrubbing, else the live clock.
    private var displayedFraction: Double {
        min(max(isScrubbing ? scrubFraction : liveFraction, 0), 1)
    }

    /// The elapsed time to show — the scrub position while dragging so the label
    /// tracks the cursor, else the live clock.
    private var shownElapsed: TimeInterval {
        isScrubbing ? scrubFraction * duration : currentTime
    }

    private var remaining: TimeInterval {
        max(0, duration - shownElapsed)
    }

    var body: some View {
        HStack(spacing: 9) {
            Text(Self.timeLabel(shownElapsed, hasTrack: hasTrack))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(AppearanceTheme.secondary)
                .frame(width: 30, alignment: .leading)

            track

            Text(Self.timeLabel(remaining, hasTrack: hasTrack, remaining: true))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(AppearanceTheme.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let f = displayedFraction
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(AppearanceTheme.railFill)
                    .frame(height: 4)
                Capsule(style: .continuous)
                    .fill(AppearanceTheme.seekFill)
                    .frame(width: max(0, width * f), height: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(seekGesture(width: width), including: isSeekable ? .all : .subviews)
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel(Text("Playback position", bundle: .module))
        // Locale-aware percentage read-out (shared "%lld percent" catalog key).
        .accessibilityValue(Text("\(Int((displayedFraction * 100).rounded())) percent", bundle: .module))
        .accessibilityHidden(!isSeekable)
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isScrubbing = true
                scrubFraction = Self.fraction(forX: value.location.x, width: width)
            }
            .onEnded { value in
                let endFraction = Self.fraction(forX: value.location.x, width: width)
                scrubFraction = endFraction
                if let time = SeekMath.time(forFraction: endFraction, duration: duration) {
                    onSeek(time)
                }
                isScrubbing = false
            }
    }

    private static func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        guard width.isFinite, width > 0, x.isFinite else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }
}
