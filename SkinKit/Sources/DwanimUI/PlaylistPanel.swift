import PlayerCore
import SwiftUI

// MARK: - PlaylistPanel

/// The expandable queue list that fills the area below the now-playing row when
/// the disclosure in `DefaultPlayerView` is open. A scrollable list over
/// `core.playlist`, one row per track:
///
/// - The currently-playing row (`index == core.currentIndex`) is highlighted and
///   carries a leading play glyph; every other row shows a quiet track-number.
/// - Double-clicking a row — or pressing its trailing ▶ button — calls
///   `core.select(index)`, which selects AND plays that track (bounds-checked in
///   `PlayerCore`). There is intentionally no select-without-play path: the
///   default skin does not add new `PlayerCore` API.
///
/// `@Bindable` so SwiftUI re-renders the highlight when `currentIndex` changes
/// (e.g. the track advances) and the list when `playlist` changes. The caller
/// (`DefaultPlayerView`) is responsible for only mounting this when the queue is
/// expanded AND non-empty, and for clipping it to the panel's rounded-rect.
struct PlaylistPanel: View {

    @Bindable var core: PlayerCore

    /// Caps how tall the list can grow before it scrolls, so a long queue does
    /// not push the window arbitrarily tall. Short queues stay compact (the list
    /// sizes to its content under this ceiling).
    private let maxListHeight: CGFloat = 220

    /// ESTIMATED height of one queue row, used to give the panel a DEFINITE ideal
    /// height so the window actually GROWS when the queue expands — see `listHeight`.
    ///
    /// IMPORTANT — kept in sync with `PlaylistRow` BY HAND (this is an estimate, not a
    /// measurement): it must track `PlaylistRow`'s actual font + padding metrics, i.e.
    /// the title `Text`'s `.font(.system(size: 13, …))` line (~16pt rendered) plus its
    /// `.padding(.vertical, 6)` (6 top + 6 bottom = 12pt) → ~28pt. If you change the
    /// `PlaylistRow` font SIZE or its vertical padding, UPDATE this constant to match,
    /// or the queue-expand window growth will be slightly off (rows clipped or a small
    /// gap). There is no compile-time link between the two.
    private static let rowHeight: CGFloat = 28
    /// Vertical spacing between rows in the `LazyVStack`.
    private static let rowSpacing: CGFloat = 2
    /// The `LazyVStack`'s own top+bottom padding inside the scroll content.
    private static let listVerticalPadding: CGFloat = 12

    /// A DEFINITE height for the list: the content's natural height (rows + spacing
    /// + padding), CLAMPED to `maxListHeight`. Part of the fix-5 dynamic-height fix.
    ///
    /// A bare `ScrollView` has NO intrinsic/ideal height — it is vertically greedy
    /// but resolves to ~0 under the scene's `.fixedSize(vertical: true)`, so the
    /// expanded VStack would NOT get taller and the scene's measured rendered height
    /// (which `DwanimPlayerScene` reports up to drive the window resize) would not
    /// change. Giving the panel a definite, content-derived height makes the
    /// expanded scene measurably taller, so the window grows when the queue expands
    /// and shrinks back when it collapses; once the content exceeds `maxListHeight`
    /// the height pins at the cap and the `ScrollView` scrolls the overflow.
    private var listHeight: CGFloat {
        let count = CGFloat(core.playlist.count)
        guard count > 0 else { return 0 }
        let content = count * Self.rowHeight
            + max(0, count - 1) * Self.rowSpacing
            + Self.listVerticalPadding
        return min(content, maxListHeight)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Self.rowSpacing) {
                ForEach(Array(core.playlist.enumerated()), id: \.offset) { index, track in
                    PlaylistRow(
                        index: index,
                        title: rowTitle(for: track, at: index),
                        isCurrent: index == core.currentIndex
                    ) {
                        core.select(index)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        // DEFINITE height (clamped to the cap) so the window grows with the queue.
        .frame(height: listHeight)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Row title

    /// The track's title, already set to the file stem by the loader when no tag
    /// title exists. Falls back once more to a 1-based track number so a row is
    /// never blank.
    private func rowTitle(for track: Track, at index: Int) -> String {
        if let title = track.title, !title.isEmpty {
            return title
        }
        return "Track \(index + 1)"
    }
}

// MARK: - PlaylistRow

/// One row of the queue. Leading glyph (play for the current row, track-number
/// otherwise), the title, and a trailing ▶ button. The whole row is a button
/// (so a click anywhere plays) and also takes a double-tap, both routing to the
/// same `play` closure.
private struct PlaylistRow: View {

    let index: Int
    let title: String
    let isCurrent: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                leadingGlyph
                    .frame(width: 18, alignment: .center)

                Text(title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.98 : 0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Double-click also plays the row (matches classic playlist muscle
        // memory); the single-click on the row button already plays, so this is
        // simply a redundant, friendly affordance.
        .onTapGesture(count: 2, perform: play)
        .accessibilityLabel(Text(isCurrent ? "Now playing: \(title)" : title))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if isCurrent {
            Image(systemName: "play.fill")
                .font(.system(size: 11))
                .foregroundStyle(DwanimTheme.goldGradient)
        } else {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
