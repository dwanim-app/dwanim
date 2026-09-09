import SwiftUI

// MARK: - CadenceEmptyWell

/// F1 — the hero well while the queue is EMPTY: the call to action a first-time
/// user (or an App Reviewer with no music files) must see before anything else.
///
/// It occupies exactly the spectrum well's box (same height, corner, `theme.lcd`
/// fill and hairline), so swapping the two never re-flows the hero. Inside: a large
/// headline, one line of guidance, and REAL buttons — **Add files…** and **Add
/// Folder…** wired to the SAME app-tier handlers the queue footer and context menu
/// use (the app injects `session.presentAddFilesPanel` / `presentAddFolderPanel`;
/// `DwanimItUI` never presents a panel itself), plus **Play Sample**, which appends
/// the bundled sample track and plays it. A `nil` handler hides its button (the
/// headless harness; a missing sample resource), and the guidance line drops its
/// mention of the sample when there is none.
///
/// Nothing in here animates: with nothing loaded the well is STILL (F3). The
/// drifting idle humps belong to `CadenceVisualizer`, which only exists once a
/// track is loaded.
struct CadenceEmptyWell: View {

    let theme: AppearanceTheme
    let onAddFiles: (() -> Void)?
    let onAddFolder: (() -> Void)?
    let onPlaySample: (() -> Void)?
    /// Test-support geometry probe (see `CadenceControlProbe`); `nil` in production.
    var probe: CadenceControlProbe? = nil

    /// The well's fixed height — identical to `CadenceVisualizer`'s, so the hero
    /// keeps one height whether or not a track is loaded.
    static let wellHeight: CGFloat = 118

    var body: some View {
        VStack(spacing: 9) {
            Text("No music yet", bundle: .module)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            guidance
                .font(.system(size: 12))
                .foregroundStyle(AppearanceTheme.titleText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            HStack(spacing: 8) {
                if let onAddFiles {
                    CadenceCallToActionButton(
                        label: Text("Add files…", bundle: .module),
                        systemImage: "plus",
                        prominence: .primary,
                        theme: theme,
                        action: onAddFiles
                    )
                    .cadenceControl(.ctaAddFiles, probe: probe)
                }
                if let onAddFolder {
                    CadenceCallToActionButton(
                        label: Text("Add Folder…", bundle: .module),
                        systemImage: "folder",
                        prominence: .secondary,
                        theme: theme,
                        action: onAddFolder
                    )
                    .cadenceControl(.ctaAddFolder, probe: probe)
                }
                if let onPlaySample {
                    CadenceCallToActionButton(
                        label: Text("Play Sample", bundle: .module),
                        systemImage: "play.fill",
                        prominence: .secondary,
                        theme: theme,
                        action: onPlaySample
                    )
                    .cadenceControl(.ctaPlaySample, probe: probe)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.wellHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.lcd)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("No music loaded. Add files, add a folder, or play the sample.", bundle: .module))
    }

    /// The one-line guidance: mentions the sample only when there is one to play.
    private var guidance: Text {
        onPlaySample == nil
            ? Text("Add audio files from your Mac to start listening.", bundle: .module)
            : Text("Add audio files from your Mac, or try the built-in sample.", bundle: .module)
    }
}

// MARK: - CadenceCallToActionButton

/// A real, full-size button for the empty well: 28 pt tall, icon + label, a
/// translucent panel with an inset edge (the play button's language) — the primary
/// one filled with the theme accent so the first thing to do is obvious.
struct CadenceCallToActionButton: View {

    enum Prominence { case primary, secondary }

    let label: Text
    let systemImage: String
    let prominence: Prominence
    let theme: AppearanceTheme
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                label
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(prominence == .primary ? Color.white : AppearanceTheme.primaryText)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppearanceTheme.buttonEdge, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CadencePressStyle())
        .onHover { hovering = $0 }
        .animation(CadenceMotion.hoverEase, value: hovering)
        .accessibilityLabel(label)
    }

    private var fill: Color {
        switch prominence {
        case .primary: return theme.accent.opacity(hovering ? 0.95 : 0.82)
        case .secondary: return Color.white.opacity(hovering ? 0.18 : 0.12)
        }
    }
}
