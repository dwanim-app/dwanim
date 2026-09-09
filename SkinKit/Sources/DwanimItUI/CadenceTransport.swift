import PlayerCore
import SwiftUI

// MARK: - CadenceTransport

/// The hero transport row: three left-aligned toggles (Shuffle / Repeat / EQ), the
/// centred playback cluster (◀◀ / play-pause / ■ / ▶▶), and the right-aligned
/// speaker glyph + volume slider.
///
/// Wiring to `PlayerCore`:
/// - Shuffle → `core.isShuffle` (bool toggle).
/// - Repeat → a THREE-state cycle on `core.repeatMode`, `off → all → one → off`,
///   advanced by `RepeatMode.nextInCycle` — the same single definition the classic
///   `.wsz` face's repeat control uses, so both skins cycle identically. It used to
///   be a 2-state `off ↔ .one` flip, which made `.all` (the mode in which `▶▶`
///   wraps) unreachable from the default UI.
///
///   The three states read exactly as they do on the classic face, whose repeat
///   button lights for BOTH on-modes and stamps a "1" for repeat-one:
///     * OFF — the pill is unlit, labelled "Repeat".
///     * ALL — the pill is lit (accent fill), labelled "Repeat".
///     * ONE — the pill is lit, labelled "Repeat", with a "1" badge stamped in its
///       trailing corner.
///   The pill stays a TEXT pill rather than an SF Symbol because the left zone is a
///   row of text pills (Shuffle / Repeat / EQ) and an icon in one of the three would
///   break that row's visual language. The state-carrying part is the BADGE, not the
///   word: the badge is an overlay, so the pill measures the same in all three modes
///   and cycling repeat cannot re-flow the row (see `TransportToggleRow`, and
///   `CadenceTransportRepeatWidthTests` for the measured locale × state table). This
///   used to be done by lengthening the label to "Repeat 1", which in Japanese pushed
///   the row 4 pt past its 176 pt zone and made every label in it shrink the moment
///   the listener entered repeat-one.
///   VoiceOver gets the unambiguous state through a distinct accessibility label per
///   mode ("Repeat off" / "Repeat all" / "Repeat one"), all localized — that is where
///   the three states are SAID, since the visible word no longer distinguishes them.
///
///   `.one` and `.all` differ in AUTO-ADVANCE, not in navigation: on a finished
///   track `.one` replays it and `.all` moves on (`PlayerCore.handlePlaybackFinished`,
///   the same path the classic skin drives). Explicit ◀◀ / ▶▶ wrap under both.
/// - Shuffle and Repeat are MUTUALLY EXCLUSIVE: enabling one disables the other
///   (turning Shuffle on sets `repeatMode = .off`; cycling Repeat into ANY on-state
///   sets `isShuffle = false`), so at most one of the two is lit at any time.
///   Cycling repeat back to `off` leaves Shuffle alone.
/// - EQ → toggles `core.setEQEnabled` (grey ↔ active), kept in sync with the EQ
///   drawer's On checkbox: both read/drive the same `core.equalizer.enabled`. The
///   drawer is always visible (no collapse), so this button only enables/disables.
/// - ◀◀ / ▶▶ → `core.previous()` / `core.next()`, and they are DISABLED (dimmed to
///   `TransportIconButton.disabledOpacity`) exactly when
///   `core.canGoPrevious` / `core.canGoNext` say the press could not act — an empty
///   queue for both, plus the end of the queue for ▶▶ while repeat is off and the
///   queue is not shuffled. The condition is READ from the model, never re-derived
///   here, so the dimming cannot drift from what the transport actually does. With
///   repeat on, ▶▶ wraps and therefore never dims. A press that lands on a file
///   the engine cannot play — one that will not open, or one that opens and
///   renders nothing — keeps walking THE WAY IT WAS PRESSED (see `PlayerCore`'s
///   "Unplayable files"), so ◀◀ never returns the listener to the track they just
///   left.
/// - play-pause → `core.togglePlayPause()`.
/// - ■ (stop) → pause + seek to 0 (`PlayerCore.stop()` is private; this reproduces
///   its user-visible effect: playback halts and the position resets). ■ — not ▶▶ —
///   is how a listener stops at the end of the queue. DISABLED (the same dim as the
///   skips) while `core.currentTrack` is nil: with nothing loaded there is nothing
///   to halt, and a full-strength button that changes nothing is a dead control.
/// - volume → `core.volume` / `core.setVolume(_:)`.
struct CadenceTransport: View {

    @Bindable var core: PlayerCore
    let theme: AppearanceTheme
    /// Test-support geometry probe (see `CadenceControlProbe`); `nil` in production.
    var probe: CadenceControlProbe? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Left zone — the toggles, pinned to the shared side-zone width.
            Self.leftZone(core: core, theme: theme)

            // Centre cluster. It is centred by NOTHING BUT the two side zones
            // being equally wide (it just takes the slack between them), which is
            // why both go through `transportSideZone(alignment:)` and neither
            // carries a width of its own.
            HStack(spacing: 6) {
                TransportIconButton(
                    systemName: "backward.fill",
                    label: "Previous track",
                    isEnabled: core.canGoPrevious
                ) {
                    core.previous()
                }
                .cadenceControl(.previous, probe: probe)
                PlayButton(isPlaying: core.isPlaying) {
                    core.togglePlayPause()
                }
                .cadenceControl(.playPause, probe: probe)
                TransportIconButton(
                    systemName: "stop.fill",
                    label: "Stop",
                    isEnabled: core.currentTrack != nil
                ) {
                    core.pause()
                    core.seek(to: 0)
                }
                .cadenceControl(.stop, probe: probe)
                TransportIconButton(
                    systemName: "forward.fill",
                    label: "Next track",
                    isEnabled: core.canGoNext
                ) {
                    core.next()
                }
                .cadenceControl(.next, probe: probe)
            }
            .frame(maxWidth: .infinity)

            // Right zone — speaker glyph + volume slider, same width as the left.
            Self.rightZone(core: core)
        }
    }

    // MARK: - The two fixed side zones

    /// The LEFT zone as the app builds it: the Shuffle / Repeat / EQ row pinned
    /// to the shared side-zone width.
    ///
    /// Exposed — like `toggleRow` below — so a test measures the zone the app
    /// draws rather than a replica. `CadenceTransportZoneLayoutTests` measures
    /// this and `rightZone` and fails if they differ.
    static func leftZone(core: PlayerCore, theme: AppearanceTheme) -> some View {
        toggleRow(core: core, theme: theme).transportSideZone(alignment: .leading)
    }

    /// The RIGHT zone as the app builds it: the speaker glyph + volume slider,
    /// pinned to the SAME width as `leftZone`.
    ///
    /// This zone used to carry its own `.frame(width: 176)` literal while the
    /// left zone read `TransportToggleRow.zoneWidth`. Two spellings of one
    /// number is how a layout silently de-centres: changing the named constant
    /// moved one zone and not the other, and nothing in the suite noticed.
    static func rightZone(core: PlayerCore) -> some View {
        HStack(spacing: 7) {
            speakerGlyph
            CadenceVolumeSlider(
                value: core.volume,
                onChange: { core.setVolume($0) }
            )
            .frame(width: 84)
        }
        .transportSideZone(alignment: .trailing)
    }

    // MARK: - The left toggle zone

    /// Builds the Shuffle / Repeat / EQ row for the core's CURRENT state.
    ///
    /// Factored out of `body` so the row a test measures is the row the app
    /// draws: `TransportToggleRow` is the production container, and the only
    /// thing a measuring test substitutes is the already-localized label text
    /// (which `swift test` cannot otherwise produce — the String Catalog is not
    /// compiled there, see `LocalizationBundleTests`).
    static func toggleRow(core: PlayerCore, theme: AppearanceTheme) -> TransportToggleRow {
        TransportToggleRow(
            shuffle: TransportToggle(
                label: Text("Shuffle", bundle: .module),
                isActive: core.isShuffle,
                bold: false,
                theme: theme
            ) {
                core.isShuffle.toggle()
                // MUTUALLY EXCLUSIVE with Repeat: turning Shuffle ON turns
                // Repeat off, so at most one is lit at a time.
                if core.isShuffle { core.repeatMode = .off }
            },
            repeatToggle: repeatToggle(core: core, theme: theme),
            equalizer: TransportToggle(
                // "EQ" is a fixed abbreviation kept identical in every locale — verbatim.
                label: Text(verbatim: "EQ"),
                isActive: core.equalizer.enabled,
                bold: true,
                theme: theme
            ) { core.setEQEnabled(!core.equalizer.enabled) }
        )
    }

    // MARK: - The Repeat pill

    /// Builds the Repeat pill for the core's CURRENT mode.
    ///
    /// Factored out of `body` so the three states' rendering inputs — the visible
    /// text, the per-state accessibility label, and the lit flag — are addressable
    /// by a test (`CadenceTransportRepeatAppearanceTests`) rather than buried in a
    /// view builder. Everything a state must be distinguishable BY passes through
    /// this one function.
    static func repeatToggle(core: PlayerCore, theme: AppearanceTheme) -> TransportToggle {
        TransportToggle(
            label: repeatLabel(for: core.repeatMode),
            accessibilityText: repeatAccessibilityLabel(for: core.repeatMode),
            // The "1" the classic face stamps for repeat-one. Declared in every
            // state so the pill's width — and so the whole row's layout — is
            // independent of the mode; only the glyph's opacity changes.
            badge: repeatBadge(for: core.repeatMode),
            // Lit in BOTH on-states: `.all` must not read as "off" — that was the
            // original bug's twin (a reachable mode that looked unreachable).
            isActive: core.repeatMode != .off,
            bold: false,
            theme: theme
        ) {
            // 3-state cycle off -> all -> one -> off (shared with the classic
            // face via `RepeatMode.nextInCycle`), and MUTUALLY EXCLUSIVE with
            // Shuffle: entering ANY on-state turns Shuffle off, while cycling
            // back to off leaves Shuffle alone.
            core.repeatMode = core.repeatMode.nextInCycle
            if core.repeatMode != .off { core.isShuffle = false }
        }
    }

    /// The Repeat pill's visible text for a mode — the SAME word in all three
    /// states (see `repeatLabelKey(for:)`, which is state-independent by design).
    ///
    /// What distinguishes the states visually is NOT this string:
    ///   * `.off` vs the on-states — the pill is lit (`isActive`);
    ///   * `.all` vs `.one` — `repeatBadge(for:)` stamps the classic face's "1"
    ///     into the pill's trailing corner. It is an OVERLAY, so it satisfies
    ///     requirement A's "each state has a distinct, legible visual" without
    ///     adding a point of width.
    ///
    /// So the pill measures identically in every state, and the whole toggle row
    /// never re-flows when the listener cycles repeat. That invariant is asserted
    /// in `CadenceTransportRepeatWidthTests` (the row width is equal across the
    /// cycle, and a visible badge adds zero width) and in
    /// `CadenceTransportRepeatAppearanceTests.testBothOnStatesLightAnIdenticalPillAndOnlyTheBadgeDiffers`.
    /// Making this string state-dependent again would break all of them — and in
    /// Japanese would push the row past its 176 pt zone, which is the defect the
    /// badge exists to fix.
    ///
    /// The state ITSELF is announced by `repeatAccessibilityLabel(for:)`, one
    /// distinct localized string per state, because neither "lit" nor a small
    /// glyph is reachable by VoiceOver.
    static func repeatLabel(for mode: RepeatMode) -> Text {
        Text(LocalizedStringKey(repeatLabelKey(for: mode)), bundle: .module)
    }

    /// The CATALOG KEY behind `repeatLabel(for:)` — the single definition of
    /// "which string does this state put on screen".
    ///
    /// Exposed (rather than inlined into `repeatLabel`) so a width test can ask
    /// production what a state renders and then resolve that key against the
    /// catalog for each shipping locale. Under `swift test` the catalog is not
    /// compiled, so a hosted view can only ever draw English (see
    /// `LocalizationBundleTests`); reading the key here and the value from the
    /// catalog is what lets `CadenceTransportRepeatWidthTests` measure the REAL
    /// pill at ja and zh-Hant widths without replicating the mapping.
    static func repeatLabelKey(for mode: RepeatMode) -> String {
        // STATE-INDEPENDENT BY DESIGN. All three modes show the same word; the
        // repeat-one state is marked by `repeatBadge(for:)` instead, which is an
        // overlay and so cannot change the pill's width. Re-introducing a longer
        // per-state string here re-introduces the row re-flow that
        // `CadenceTransportRepeatWidthTests` exists to catch (in Japanese the
        // old "Repeat 1" pill pushed the row to 180 pt inside a 176 pt zone).
        switch mode {
        case .off, .all, .one: return "Repeat"
        }
    }

    /// The badge stamped on the Repeat pill for a mode: the classic face's "1",
    /// shown only in repeat-one.
    ///
    /// The slot is declared in every state (with `isVisible` false in two of
    /// them) so the pill's view tree is identical across the cycle and the badge
    /// cross-fades. Being an overlay it contributes nothing to the pill's width,
    /// which is what keeps `off → all → one → off` free of horizontal re-flow.
    static func repeatBadge(for mode: RepeatMode) -> TransportToggleBadge {
        TransportToggleBadge(glyph: "1", isVisible: mode == .one)
    }

    /// The Repeat pill's accessibility label — one distinct, localized string per
    /// state, because "lit" alone cannot tell a VoiceOver user `.all` from `.one`
    /// and the visible text is deliberately terse.
    static func repeatAccessibilityLabel(for mode: RepeatMode) -> Text {
        switch mode {
        case .off: return Text("Repeat off", bundle: .module)
        case .all: return Text("Repeat all", bundle: .module)
        case .one: return Text("Repeat one", bundle: .module)
        }
    }

    /// The static two-bar speaker glyph (decorative), 2×5 and 2×9 pt bars.
    private static var speakerGlyph: some View {
        HStack(alignment: .center, spacing: 1.5) {
            Capsule().fill(AppearanceTheme.secondary).frame(width: 2, height: 5)
            Capsule().fill(AppearanceTheme.secondary).frame(width: 2, height: 9)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The side-zone width

extension View {

    /// Pins one of the transport's two SIDE ZONES to the fixed width that keeps
    /// the centre cluster centred.
    ///
    /// The centre cluster has no width of its own — it takes `maxWidth: .infinity`
    /// between the zones — so it is centred if and only if the two zones are
    /// EQUALLY wide. Both therefore go through this one modifier, and
    /// `TransportToggleRow.zoneWidth` is the only place the number exists: a
    /// second literal in one zone (which is how the right zone was written) makes
    /// changing the constant push the cluster off centre by half the difference.
    func transportSideZone(alignment: Alignment) -> some View {
        frame(width: TransportToggleRow.zoneWidth, alignment: alignment)
    }
}

// MARK: - TransportToggleRow

/// The transport's LEFT zone: the Shuffle / Repeat / EQ pills, laid out in one
/// `HStack` inside a fixed-width box.
///
/// ## Why the box is fixed, and what that demands of the pills
/// The centre cluster is centred by giving the left and right zones the SAME
/// fixed width (`zoneWidth`), so anything that changes the left zone's INTRINSIC
/// width re-flows the row: the pills shift, and once the content exceeds the box
/// `minimumScaleFactor` starts shrinking every label at once. That is a layout
/// bug, not a graceful degradation — it fires on a state change the listener
/// just made, so the whole row appears to twitch.
///
/// The rule this type exists to make explicit: **a toggle's width must not
/// depend on its own state.** The Repeat pill therefore keeps the SAME word in
/// all three modes and marks repeat-one with an overlaid badge
/// (`TransportToggle.badge`), which draws inside the pill's existing padding and
/// contributes nothing to layout. `CadenceTransportRepeatWidthTests` measures
/// this row's `fittingSize` for every locale × repeat-state pair and fails on
/// either overflow or a width that moves between states.
struct TransportToggleRow: View {

    /// The fixed width of the left AND the right zone — both applied through
    /// `View.transportSideZone(alignment:)`, so this is the single definition of
    /// the number. The row's intrinsic width must never exceed it.
    ///
    /// It is a DESIGN constant, not a budget to be relaxed: widening it is how a
    /// too-wide control gets "fixed" without fixing it. `CadenceTransportZoneLayoutTests`
    /// pins the value independently and measures the rendered layout, so both
    /// widening it and letting the two zones drift apart fail.
    static let zoneWidth: CGFloat = 176

    /// The gap between pills.
    static let spacing: CGFloat = 4

    let shuffle: TransportToggle
    let repeatToggle: TransportToggle
    let equalizer: TransportToggle

    var body: some View {
        HStack(spacing: Self.spacing) {
            shuffle
            repeatToggle
            equalizer
        }
    }
}

// MARK: - TransportToggleBadge

/// A small glyph stamped in a toggle pill's trailing padding — today only the
/// repeat-one "1".
///
/// It is drawn as an OVERLAY, so it adds nothing to the pill's measured width;
/// that is the whole point (see `TransportToggleRow`). It is also always present
/// in the view tree once a pill declares one, with `isVisible` driving opacity
/// rather than existence, so entering and leaving the state cross-fades instead
/// of re-laying-out.
///
/// The glyph is `verbatim`: it is a numeral stamped on a control, the way the
/// classic `.wsz` face stamps "1" on its repeat button, not a word to translate.
/// The STATE it signals is carried for VoiceOver by the pill's per-mode
/// accessibility label, which is fully localized — the badge itself is
/// `accessibilityHidden`.
struct TransportToggleBadge: Equatable {
    let glyph: String
    let isVisible: Bool
}

// MARK: - TransportToggle

/// A Shuffle / Repeat / EQ toggle pill: 24 pt tall, 11 pt text. Inactive is muted
/// text on transparent (hover raises a faint fill); active is white text on the
/// theme accent at 34% alpha.
struct TransportToggle: View {
    /// The already-localized label. A `Text` (not a `String`) so each call site chooses
    /// its own bundle: Shuffle / Repeat pass `Text("…", bundle: .module)` (translated),
    /// while the fixed-frame "EQ" abbreviation passes `Text(verbatim:)` (never localized).
    /// The same value drives both the visible pill and the accessibility label.
    let label: Text
    /// An accessibility label that differs from the visible text, for a control
    /// whose terse label cannot express its full state. The Repeat pill passes one
    /// per mode ("Repeat off" / "Repeat all" / "Repeat one"); Shuffle and EQ leave
    /// it `nil` and are announced by their own visible text.
    var accessibilityText: Text? = nil
    /// An optional glyph stamped inside the pill's trailing padding. `nil` for a
    /// pill that never carries one (Shuffle, EQ); the Repeat pill declares the
    /// same badge in all three modes and only flips `isVisible`, so entering and
    /// leaving repeat-one cross-fades a "1" rather than re-laying-out the row.
    /// See `TransportToggleBadge` and `TransportToggleRow`.
    var badge: TransportToggleBadge? = nil
    let isActive: Bool
    let bold: Bool
    let theme: AppearanceTheme
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 11, weight: bold ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.white : AppearanceTheme.idleToggle)
                // Defensive safety net: the three toggles size to content inside a
                // fixed 176 pt zone. Every current locale fits with slack, so this is
                // invisible today; it only engages if a future longer string would
                // otherwise overflow the pill into the centre cluster as overlap.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 24)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background)
                )
                .overlay(alignment: .topTrailing) { badgeGlyph }
                .contentShape(Rectangle())
        }
        .buttonStyle(CadencePressStyle())
        .onHover { hovering = $0 }
        .animation(CadenceMotion.hoverEase, value: hovering)
        .accessibilityLabel(announcedText)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// What VoiceOver announces: the state-carrying `accessibilityText` when the
    /// call site supplied one, else the visible label. This is the seam the
    /// appearance tests assert on — the a11y tree of a hosted SwiftUI view is not
    /// reachable in-process, so the CHOICE is pinned here instead.
    var announcedText: Text { accessibilityText ?? label }

    /// The badge, drawn as a superscript numeral in the pill's top-trailing
    /// corner.
    ///
    /// It lives in an `.overlay`, which by definition takes its size from what
    /// it overlays and gives none back — so however wide the glyph is, the pill
    /// measures exactly what its LABEL measures. The corner it sits in is the
    /// pill's own `.padding(.horizontal, 8)`, which is empty by construction, so
    /// the badge never crowds the word next to it.
    ///
    /// Hit testing is off (the whole pill is already one button) and it is
    /// hidden from accessibility: the state it signals reaches VoiceOver through
    /// the pill's localized per-mode `accessibilityText`, and announcing a bare
    /// "1" alongside that would be noise.
    @ViewBuilder
    private var badgeGlyph: some View {
        if let badge {
            Text(verbatim: badge.glyph)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isActive ? Color.white : AppearanceTheme.idleToggle)
                .opacity(badge.isVisible ? 1 : 0)
                .padding(.top, 2.5)
                .padding(.trailing, 1.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .animation(CadenceMotion.hoverEase, value: badge.isVisible)
        }
    }

    private var background: Color {
        if isActive { return theme.accent.opacity(0.34) }
        return hovering ? Color.white.opacity(0.07) : .clear
    }
}

// MARK: - TransportIconButton

/// A secondary transport button (◀◀ / ■ / ▶▶): 32×28 pt, quiet glyph that brightens
/// on hover.
///
/// ## The disabled state
/// A skip button whose press could not act is dimmed to 0.3 and `.disabled`. It
/// used to be 0.5, which App Review read as STYLING rather than "disabled" on a
/// fresh install (F6) — at 0.3 the glyph is unmistakably a ghost of its live self
/// while still legible enough to say what it would do. The dim is applied ONCE, to
/// the whole button, rather than by darkening the glyph colour, so the glyph and
/// its (empty) background stay in proportion, and the ENABLED look is untouched.
///
/// A disabled button also drops its live affordances: the hover brighten and hover
/// fill are gated on `isEnabled`, and `.disabled` stops `CadencePressStyle`'s press
/// scale/dim from ever firing. Without that gating the control would still light up
/// under the pointer and push in on click — the exact "looks live but is inert"
/// impression the disabled state exists to remove. The `.onHover` tracking itself is
/// left running so the button brightens the instant it becomes enabled again with
/// the pointer already resting on it.
struct TransportIconButton: View {
    let systemName: String
    /// The accessibility label key, resolved against `Bundle.module`'s catalog.
    let label: LocalizedStringKey
    /// Whether a press would do anything. Supplied by the model's `canGoNext` /
    /// `canGoPrevious`; ■ and the other always-live buttons leave it at `true`.
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    /// The dimming applied to a button that cannot act, named once so the view
    /// and the tests that measure the rendered pixels agree on the number. 0.3:
    /// low enough to read as disabled at a glance (0.5 read as styling), high
    /// enough that the glyph still says what the button would do.
    static let disabledOpacity: Double = 0.3

    /// Hover styling applies only while the button can actually act. A pure
    /// function of the two inputs so the GATE itself is unit-testable: real
    /// hover cannot be synthesized in-process (SwiftUI reads the live cursor,
    /// not the event's location), so the truth table is pinned here.
    static func showsHoverStyling(hovering: Bool, isEnabled: Bool) -> Bool {
        hovering && isEnabled
    }

    private var showsHover: Bool {
        Self.showsHoverStyling(hovering: hovering, isEnabled: isEnabled)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(showsHover ? Color.white : AppearanceTheme.idleTransport)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(showsHover ? Color.white.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(CadencePressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Self.disabledOpacity)
        .onHover { hovering = $0 }
        .animation(CadenceMotion.hoverEase, value: showsHover)
        .animation(CadenceMotion.hoverEase, value: isEnabled)
        .accessibilityLabel(Text(label, bundle: .module))
    }
}

// MARK: - PlayButton

/// The primary play/pause button: 44×34 pt, a translucent panel with an inset
/// edge; the glyph swaps play.fill ↔ pause.fill from the live transport state.
private struct PlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppearanceTheme.primaryText)
                .frame(width: 44, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.16 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppearanceTheme.windowEdge, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(CadencePressStyle())
        .onHover { hovering = $0 }
        .animation(CadenceMotion.hoverEase, value: hovering)
        .accessibilityLabel(Text(isPlaying ? "Pause" : "Play", bundle: .module))
    }
}

// MARK: - CadenceVolumeSlider

/// A thin horizontal volume slider: a 3 pt rail with a filled portion and a round
/// knob. CLICK or DRAG sets the volume in `0...1` continuously.
private struct CadenceVolumeSlider: View {
    /// The live volume in `0...1`.
    let value: Float
    /// Called with a new `0...1` volume on click / drag.
    let onChange: (Float) -> Void

    private let knobDiameter: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let f = CGFloat(min(max(value, 0), 1))
            let knobTravel = max(0, width - knobDiameter)
            let knobX = knobDiameter / 2 + knobTravel * f

            ZStack(alignment: .leading) {
                Capsule().fill(AppearanceTheme.railFill).frame(height: 3)
                Capsule().fill(AppearanceTheme.volumeFill)
                    .frame(width: max(0, width * f), height: 3)
                Circle()
                    .fill(AppearanceTheme.volumeKnob)
                    .frame(width: knobDiameter, height: knobDiameter)
                    // P7 — handoff §1b: 0 0.5px 2px rgba(0,0,0,0.5) (≈ radius 2).
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 0.5)
                    .position(x: knobX, y: geometry.size.height / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    onChange(Float(Self.fraction(forX: g.location.x, width: width, knobDiameter: knobDiameter)))
                }
            )
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel(Text("Volume", bundle: .module))
        // Locale-aware percentage read-out (shared "%lld percent" catalog key).
        .accessibilityValue(Text("\(Int((min(max(value, 0), 1)) * 100)) percent", bundle: .module))
    }

    /// The `0...1` volume for a cursor `x`, mapped through the SAME knob-travel inset
    /// the knob renders with (its centre travels `knobDiameter/2 … width−knobDiameter/2`,
    /// not the full width), so the knob sits under the pointer at both extremes —
    /// mirroring the seek bar's self-consistent mapping. A width at/under the knob
    /// diameter (zero travel) reads as 0.
    private static func fraction(forX x: CGFloat, width: CGFloat, knobDiameter: CGFloat) -> Double {
        let knobTravel = max(0, width - knobDiameter)
        guard knobTravel > 0 else { return 0 }
        return min(max(Double((x - knobDiameter / 2) / knobTravel), 0), 1)
    }
}
