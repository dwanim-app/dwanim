import PlayerCore
import SwiftUI

// MARK: - ProgressTrack

/// A thin glass progress bar filled gold to the playback fraction (`0...1`) that
/// is also an interactive **seek** control: CLICK anywhere on the bar to seek to
/// that position, or DRAG the gold playhead knob to scrub. Works during playback
/// and while paused.
///
/// A faint translucent capsule is the unfilled track; a gold capsule overlays it
/// from the leading edge to the fraction, and a small gold knob sits at the
/// fraction's leading edge.
///
/// ## Display vs. scrub
/// When not scrubbing, the bar tracks the live `fraction` (derived from
/// `currentTime / duration` by the caller), so the playback tick advances it.
/// While the user is dragging (`isScrubbing`), the bar and knob follow the
/// *cursor* fraction (`scrubFraction`) instead, so the playhead does not snap
/// back to the live clock mid-drag; on release the seek lands and the live tick
/// takes over again.
///
/// ## Seekability gate
/// The gesture (and the knob) are only active when `duration` is a finite,
/// positive value — i.e. something seekable is loaded. With an unknown / zero /
/// non-finite duration the bar renders as an empty passive track with no knob,
/// and clicks/drags do nothing. The fraction -> time mapping is the pure
/// `SeekMath` helper (unit-tested in `PlayerCore`), so the View carries no seek
/// math of its own.
struct ProgressTrack: View {

    /// Live playback progress, expected in `0...1`; clamped defensively at draw
    /// time. Used when **not** scrubbing.
    let fraction: Double

    /// Current track length in seconds. Drives the seekability gate (a finite
    /// `> 0` value enables the gesture) and the `SeekMath` time mapping.
    let duration: TimeInterval

    /// Called on click/drag-end with the absolute seek **time** in seconds
    /// (already mapped + clamped by `SeekMath`). The caller wires this to
    /// `PlayerCore.seek(to:)`. Never called when the bar is not seekable.
    let onSeek: (TimeInterval) -> Void

    /// The bar's thickness in points.
    private let thickness: CGFloat = 4

    /// The diameter of the draggable gold playhead knob.
    private let knobDiameter: CGFloat = 12

    /// Whether a drag/click gesture is currently in progress. While true the bar
    /// follows `scrubFraction` rather than the live `fraction`.
    @State private var isScrubbing = false

    /// The cursor fraction during a scrub, in `0...1`.
    @State private var scrubFraction: Double = 0

    /// Whether the source is seekable right now (something loaded with a known,
    /// positive, finite length).
    private var isSeekable: Bool {
        duration.isFinite && duration > 0
    }

    /// The fraction the bar should display: the cursor while scrubbing, else the
    /// live playback fraction. Always clamped to `0...1`.
    private var displayedFraction: Double {
        let raw = isScrubbing ? scrubFraction : fraction
        return min(max(raw, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let f = displayedFraction
            // The knob centre travels the full bar width; inset by half its
            // diameter at each end so it never clips past the track edges.
            let knobTravel = max(0, width - knobDiameter)
            let knobX = knobDiameter / 2 + knobTravel * f

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(height: thickness)

                Capsule(style: .continuous)
                    .fill(DwanimTheme.goldGradient)
                    .frame(width: max(0, width * f), height: thickness)

                if isSeekable {
                    Circle()
                        .fill(DwanimTheme.goldGradient)
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                        .frame(width: knobDiameter, height: knobDiameter)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .position(x: knobX, y: geometry.size.height / 2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            // A generous hit area: the knob is small, but the whole bar height is
            // clickable/draggable so a plain click anywhere seeks.
            .contentShape(Rectangle())
            .gesture(seekGesture(width: width), including: isSeekable ? .all : .subviews)
        }
        // A taller frame than the 4pt bar so there is a comfortable click/drag
        // target around the thin track and the knob is not clipped.
        .frame(height: max(thickness, knobDiameter) + 8)
        .accessibilityElement()
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text(accessibilityValueText))
        .accessibilityHidden(!isSeekable)
    }

    // MARK: - Gesture

    /// A zero-distance drag so a plain CLICK (a tap with no movement) also seeks,
    /// while a real drag scrubs continuously. `onChanged` tracks the cursor into
    /// `scrubFraction` (and raises `isScrubbing` so the bar follows the cursor);
    /// `onEnded` maps the final fraction to a seek time via `SeekMath` and fires
    /// `onSeek`, then lowers `isScrubbing` so the live tick resumes.
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

    /// Clamp a touch x against the bar width to a `0...1` fraction. A degenerate
    /// (zero / non-finite) width reads as `0` rather than dividing.
    private static func fraction(forX x: CGFloat, width: CGFloat) -> Double {
        guard width.isFinite, width > 0, x.isFinite else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    /// A spoken percentage for VoiceOver (e.g. "42 percent"). Only meaningful when
    /// seekable; otherwise the element is hidden.
    private var accessibilityValueText: String {
        let pct = Int((displayedFraction * 100).rounded())
        return "\(pct) percent"
    }
}
