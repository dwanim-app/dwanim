import AppKit
import CoreGraphics
import Foundation
import PlayerControl
import PlayerCore
import SkinKit
import SkinRender
import SpectrumKit

// The classic main-window controller (one primary type per file, §12): it owns
// the skin, the core, the view, the redraw timer, the title marquee, and the
// spectrum-analyzer wiring; recomposes the window each tick from the live
// `PlayerCore` state and swaps the view's image; and routes mouse-down hits to
// `PlayerControl.apply`.
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier (no
// logic change) so BOTH the dev harness AND the real app target can host it. The
// CLI mode entry (arg parsing + skin/audio load + the process-lifetime hold)
// stays in the harness, which now CONSTRUCTS this controller via
// `showInteractiveWindow`.

// MARK: - Controller

/// Owns the live window: the skin, the core, the view, and the redraw timer. It
/// recomposes the window each tick from the current `PlayerCore` state and swaps
/// the view's image, and routes mouse-down hits to `PlayerControl.apply(_:to:)`.
///
/// It also owns the spectrum visualizer wiring: an audio tap stashes the latest
/// mono samples into a lock-guarded `SpectrumKit.SpectrumFeed` (audio thread,
/// minimum work), and the redraw timer (main thread) reads that snapshot, runs the
/// `SpectrumAnalyzer`, and draws the bars via `SpectrumRenderer`. The analyzer and
/// all SkinRender drawing stay on the main thread.
///
/// `@MainActor` (the M5 unification): all four window controllers are now uniformly
/// main-actor-isolated. Every method here already ran on the main thread by
/// convention (mouse callbacks, the RedrawLoop tick, the `@MainActor` `PlayerCore`
/// it drives); the annotation makes that the compiler's contract. The only seam
/// that genuinely crosses threads — the audio tap writing the `SpectrumFeed` — is
/// owned by the `RedrawLoop` and never touches this controller, so it is unaffected.
@MainActor
public final class InteractiveController: SkinWindowController {
    private let skin: Skin
    private let core: PlayerCore
    private let view: ScaledImageView
    /// PRESENTATION scale: points per skin pixel (possibly fractional — e.g. 1.5).
    /// Used for the view-point <-> skin-point hit-test mapping.
    private let scale: Double
    /// INTEGER nearest-neighbor factor the composed bitmap is rendered at, derived
    /// from `scale` by the pure `PresentationScale` (integer scale -> itself;
    /// fractional 1.5 -> the 2x-backing device factor 3).
    private let bitmapScale: Int

    /// The control currently held down (for pressed-sprite feedback), or `nil`.
    private var pressedControl: SkinControl?

    /// `true` while a posbar (seek) drag is in progress: set on a mouse-down that
    /// grabbed the posbar track, kept across drags so the cursor can wander off the
    /// track vertically and still scrub, and cleared on mouse-up. Mirrors
    /// `EQController.draggingSlider`'s gesture latch.
    private var isSeeking = false

    /// Which slider, if any, a mouse-down latched for a continuous scrub (volume
    /// or balance). Like `isSeeking`, it is kept across drags so the cursor can
    /// wander vertically off the slider and still scrub, and cleared on mouse-up.
    /// `nil` when the gesture did not start on a slider. Volume and balance are
    /// mutually exclusive (their rects do not overlap), so one latch covers both.
    private enum DraggingSlider { case volume, balance }
    private var draggingSlider: DraggingSlider?

    // MARK: Host-action callbacks (injected)
    //
    // The EQ / PL / eject / minimize / close buttons are HOST/window actions, not
    // `PlayerCore` transport, so the controller routes their clicks to these
    // injected closures rather than `PlayerControl.apply`. Each defaults to `nil`
    // (the harness path, where these buttons are inert), and the setup / app
    // supplies them via `showInteractiveWindow` (toggle the EQ / playlist window,
    // open a file, miniaturize the window, close the window).

    /// Toggle the equalizer window (the EQ button). `nil` -> the button is inert.
    private let onToggleEQ: (() -> Void)?
    /// Toggle the playlist window (the PL button). `nil` -> inert.
    private let onTogglePlaylist: (() -> Void)?
    /// Open the audio open-file panel (the eject button). `nil` -> inert.
    private let onEject: (() -> Void)?
    /// Miniaturize the window (the title-bar minimize button). `nil` -> inert.
    private let onMinimize: (() -> Void)?
    /// Close the window (the title-bar close button). `showInteractiveWindow`
    /// defaults it to `window.close()` — which routes through `windowWillClose`
    /// → `tearDown()` → `onClose`, the SAME funnel as any other window close, so
    /// a host's close-time policy (e.g. the app's close-quits guards) is never
    /// bypassed. `nil` -> inert.
    private let onCloseWindow: (() -> Void)?

    /// Live "is the EQ window open?" / "is the playlist window open?" queries, so
    /// the EQ / PL buttons can light their ON sprite while their window is open.
    /// Default to `{ false }` (the harness path: the buttons never light). The app
    /// supplies closures reading the presenter's `eqHandle != nil` /
    /// `playlistHandle != nil`.
    private let isEQWindowOpen: () -> Bool
    private let isPlaylistWindowOpen: () -> Bool

    /// The shared ~25 Hz redraw cadence + audio-tap wiring (timer + tap install /
    /// remove + the `SpectrumFeed` write). Built in `init` and started/stopped by
    /// `start()` / `tearDown()`.
    private var redrawLoop: RedrawLoop?

    // MARK: Title marquee

    /// Horizontal scroll offset (pixels) for the title marquee, advanced each
    /// redraw tick when the title overflows its display region. Kept bounded by
    /// `BitmapText.scrollCycleWidth` at draw time so it never grows without limit.
    private var titleScrollOffset = 0
    /// Redraw-tick counter, used to slow the marquee to a readable pace: the
    /// offset advances one pixel every `titleScrollTickInterval` ticks rather than
    /// every tick (25 Hz would scroll far too fast at 1px/tick).
    private var titleScrollTick = 0
    /// Advance the marquee one pixel every Nth tick. At the ~25 Hz redraw this is
    /// ~8 px/sec — a readable classic-marquee pace.
    private static let titleScrollTickInterval = 3

    // MARK: Spectrum wiring

    /// The engine's track-format source (the same object backing `core`), opt-in
    /// cast like the PCM tap. Read each redraw for the kbps / kHz number boxes;
    /// `nil` when the engine does not expose format facts. Format metadata never
    /// flows through `PlayerCore`'s transport. (The PCM tap itself is owned by the
    /// `RedrawLoop`, which installs and removes it — UNLESS an external feed is
    /// injected, see `latestSamples`.)
    private let format: TrackFormatProviding?
    /// Lock-guarded latest mono samples, read by the main-thread redraw timer.
    ///
    /// Two ownership modes:
    ///   • OWNED (harness): no external feed injected → this controller owns its
    ///     own `SpectrumFeed`, and the `RedrawLoop` installs THIS controller's tap
    ///     to write it. Behavior is exactly as before — one window, one process,
    ///     one tap.
    ///   • SHARED (app): an external feed is injected → this is that injected feed
    ///     (already fed by the single host-owned tap, e.g. `AudioSession`). The
    ///     `RedrawLoop` is then TIMER-ONLY (`tap: nil`): it installs / removes NO
    ///     tap and just ticks, reading this externally-fed snapshot. This is what
    ///     lets the host run ONE tap shared across every spectrum consumer rather
    ///     than each hosted window stealing the single per-node tap.
    private let latestSamples: SpectrumFeed
    /// FFT spectrum analyzer (main-thread only). `barCount` is chosen to fit the
    /// visualization frame width.
    private let analyzer: SpectrumAnalyzer

    /// Number of spectrum bars, DERIVED from the visualization-frame width so the
    /// two stay coupled: ~4px per bar across the frame (`max(1, width / 4)` →
    /// 19 bars at the provisional 76px). Deriving it (rather than hardcoding 19
    /// against a provisional 76) means that if the frame is later retuned the bar
    /// count follows, instead of `slotWidth` silently rounding to 0 and the vis
    /// area going blank. The lower bound of 1 keeps the analyzer well-formed even
    /// for a degenerate frame.
    private static func barCount(forVisWidth width: Int) -> Int {
        max(1, width / 4)
    }

    /// - Parameters:
    ///   - tap: the engine's opt-in PCM tap. Used ONLY when `externalFeed` is
    ///     `nil` (the harness's owned-tap mode); ignored when an external feed is
    ///     injected (the host owns the single tap).
    ///   - externalFeed: a host-owned, already-fed `SpectrumFeed` to read from. When
    ///     non-`nil` (the app) the redraw loop is timer-only and installs NO tap, so
    ///     the single host tap is never stolen. When `nil` (the harness) the
    ///     controller owns its own feed and the loop installs `tap` exactly as
    ///     before.
    public init(
        skin: Skin,
        core: PlayerCore,
        view: ScaledImageView,
        scale: Double,
        tap: AudioTapProviding?,
        format: TrackFormatProviding?,
        externalFeed: SpectrumFeed? = nil,
        terminatesAppOnClose: Bool = true,
        onClose: (() -> Void)? = nil,
        onToggleEQ: (() -> Void)? = nil,
        onTogglePlaylist: (() -> Void)? = nil,
        onEject: (() -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        onCloseWindow: (() -> Void)? = nil,
        isEQWindowOpen: @escaping () -> Bool = { false },
        isPlaylistWindowOpen: @escaping () -> Bool = { false }
    ) {
        self.skin = skin
        self.core = core
        self.view = view
        self.scale = scale
        self.bitmapScale = PresentationScale.bitmapScale(forPresentationScale: scale)
        self.format = format
        self.onToggleEQ = onToggleEQ
        self.onTogglePlaylist = onTogglePlaylist
        self.onEject = onEject
        self.onMinimize = onMinimize
        self.onCloseWindow = onCloseWindow
        self.isEQWindowOpen = isEQWindowOpen
        self.isPlaylistWindowOpen = isPlaylistWindowOpen
        // SHARED mode reads the injected feed; OWNED mode makes its own.
        self.latestSamples = externalFeed ?? SpectrumFeed()

        let visWidth = MainWindowLayout.visualizationFrame.width
        let bars = InteractiveController.barCount(forVisWidth: visWidth)
        // Guard: if the frame is so narrow that even a single bar can't get a
        // full pixel slot, the vis area would draw blank. Surface it rather than
        // failing silently (one-line stderr note; the host keeps running).
        if visWidth < bars {
            FileHandle.standardError.write(Data(
                ("Warning: visualization frame width (\(visWidth)px) is narrower than the "
                    + "derived bar count (\(bars)); the spectrum may render blank.\n").utf8
            ))
        }
        self.analyzer = SpectrumAnalyzer(barCount: bars)

        super.init(terminatesAppOnClose: terminatesAppOnClose, onClose: onClose)

        // The shared view carries the event's clickCount for windows that
        // distinguish single vs double click; the main window does not, so it is
        // ignored here.
        view.onMouseDown = { [weak self] viewX, viewY, viewHeight, _ in
            self?.handleMouseDown(viewX: viewX, viewY: viewY, viewHeight: viewHeight)
        }
        // Title-bar drag gate (the window is borderless, so the skin's own
        // title-bar strip is the drag handle): a press in the top strip that is
        // NOT on a control (minimize / close win over drag) moves the window.
        // The pure `ControlHitTest.hitsTitleBarDragArea` carries the geometry;
        // this closure only maps the view point to skin space at our scale.
        view.shouldDragWindow = { [weak self] viewX, viewY, viewHeight in
            guard let self else { return false }
            let point = ControlHitTest.skinPoint(
                viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: self.scale
            )
            return ControlHitTest.hitsTitleBarDragArea(skinX: point.x, skinY: point.y)
        }
        // Dragging the posbar scrubs continuously: wire the drag callback (the EQ
        // sliders are the only other draggable surface). A drag only acts when a
        // mouse-down latched a seek; otherwise it is ignored (transport/toggle
        // buttons are click-only).
        view.onMouseDragged = { [weak self] viewX, viewY, viewHeight in
            self?.handleMouseDragged(viewX: viewX, viewY: viewY, viewHeight: viewHeight)
        }
        view.onMouseUp = { [weak self] in self?.handleMouseUp() }

        // ~25 Hz: full-window recompose per tick (acceptable for the dev harness;
        // the static/dynamic patch seam is a tracked M5 item). The per-tick work
        // advances the title marquee at the timer cadence (NOT on the mouse-driven
        // redraws, so a click does not jerk the scroll) and recomposes.
        //
        // Tap ownership: in OWNED mode (no external feed) the loop installs THIS
        // controller's `tap` to write the owned feed. In SHARED mode (external feed
        // injected) the loop is TIMER-ONLY — `loopTap` is forced `nil` so it
        // installs / removes NO tap and just ticks, reading the host-fed shared
        // feed. That keeps the host's single per-node tap from being stolen when a
        // hosted main window opens (and from being torn down when it closes).
        let loopTap: AudioTapProviding? = externalFeed == nil ? tap : nil
        redrawLoop = RedrawLoop(
            interval: 0.04,
            tap: loopTap,
            feed: latestSamples
        ) { [weak self] in
            self?.advanceTitleScroll()
            self?.redraw()
        }
    }

    /// Start the redraw loop on the main run loop and install the audio tap. The
    /// shared `RedrawLoop` installs the tap (audio thread: stash the latest mono
    /// samples into the `SpectrumFeed` and return), fires one immediate tick, then
    /// schedules the ~25 Hz timer; the per-tick work (marquee + recompose) was
    /// supplied at construction.
    public func start() {
        redrawLoop?.start()
    }

    // MARK: Teardown

    /// The window is closing — stop the redraw loop (invalidate the timer + remove
    /// the tap) before the process exits. Without this, closing the window (the
    /// skin's title-bar close button or a programmatic close) would leave the
    /// ~25 Hz `redraw()` timer firing against a dead view and the audio tap still
    /// installed. The base then terminates the app (harness mode) so the run loop
    /// exits cleanly.
    ///
    /// A plain `@MainActor override`: the base `SkinWindowController` is now
    /// `@MainActor`, so `tearDown()` is main-isolated and can touch the main-actor
    /// `redrawLoop` directly. AppKit calls it via `windowWillClose` on the main
    /// thread, so this is sound with no `assumeIsolated` hop.
    public override func tearDown() {
        redrawLoop?.stop()
    }

    // MARK: Mouse

    /// A press routes to a button, a slider, or the posbar. A button hit either
    /// applies its transport action via the pure `PlayerControl` (transport
    /// buttons + toggles) or fires its injected host callback (EQ / PL / eject /
    /// minimize / close), and records the pressed control for feedback; a press on a slider
    /// (volume / balance) latches a scrub drag and applies the pressed value; a
    /// press on the posbar latches a seek drag and seeks. Buttons take precedence
    /// (the control rects do not overlap the sliders / posbar). The view-space
    /// point is mapped to skin space by the pure `ControlHitTest` (undo scale +
    /// y-flip).
    private func handleMouseDown(viewX: Double, viewY: Double, viewHeight: Double) {
        if let control = ControlHitTest.control(
            atViewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        ) {
            switch control.kind {
            case .transport:
                // Held-pressed feedback: the pressed sprite shows until mouse-up.
                pressedControl = control
                PlayerControl.apply(control, to: core)
            case .hostAction:
                // One-shot host/window action. We do NOT latch a held-pressed state:
                // a host action may open a MODAL panel (eject) that swallows the
                // matching mouse-up, which would otherwise leave the button stuck in
                // its pressed art. The EQ / PL on-state is reflected separately by
                // `overlayActiveToggles` (window-open), so no pressed latch is needed.
                pressedControl = nil
                applyHostAction(control)
            }
            redraw()
            return
        }

        let point = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        )

        // Not a button: a press on the volume / balance slider begins a scrub.
        if ControlHitTest.hitsVolume(skinX: point.x, skinY: point.y) {
            draggingSlider = .volume
            scrubVolume(toSkinX: point.x)
            return
        }
        if ControlHitTest.hitsBalance(skinX: point.x, skinY: point.y) {
            draggingSlider = .balance
            scrubBalance(toSkinX: point.x)
            return
        }

        // Else a press on the posbar track begins a seek drag.
        if ControlHitTest.hitsPosbar(skinX: point.x, skinY: point.y) {
            isSeeking = true
            seek(toSkinX: point.x)
        }
    }

    /// Fire the injected host callback for a host-action control. A `nil` callback
    /// (the harness path) leaves the button inert. The EQ / PL toggles re-light
    /// their ON sprite on the next redraw (driven by the window-open queries), so
    /// no extra state is tracked here.
    private func applyHostAction(_ control: SkinControl) {
        switch control {
        case .eqButton:  onToggleEQ?()
        case .plButton:  onTogglePlaylist?()
        case .eject:     onEject?()
        case .minimize:  onMinimize?()
        case .close:     onCloseWindow?()
        default:         break // transport controls never reach here
        }
    }

    /// A drag continues whichever gesture a mouse-down latched: a posbar seek, a
    /// volume scrub, or a balance scrub. The drag y is intentionally ignored so the
    /// cursor can wander vertically off the slider/track and still scrub, mirroring
    /// the EQ slider drag. Buttons are click-only, so a drag that did not latch a
    /// slider/posbar is a no-op.
    private func handleMouseDragged(viewX: Double, viewY: Double, viewHeight: Double) {
        let point = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        )
        if isSeeking {
            seek(toSkinX: point.x)
        } else if draggingSlider == .volume {
            scrubVolume(toSkinX: point.x)
        } else if draggingSlider == .balance {
            scrubBalance(toSkinX: point.x)
        }
    }

    /// Map a skin-space x on the volume slider to a `0...1` volume and push it to
    /// the core. Routes through the pure `ControlHitTest.volumeFraction` (clamps to
    /// `0...1`) and `PlayerCore.setVolume` (finite-guarded + clamped), so no
    /// non-finite value reaches the audio unit. Redraws so the baked-knob frame
    /// tracks the cursor.
    private func scrubVolume(toSkinX skinX: Int) {
        guard let fraction = ControlHitTest.volumeFraction(skinX: skinX) else { return }
        core.setVolume(Float(fraction))
        redraw()
    }

    /// Map a skin-space x on the balance slider to a `-1...1` pan and push it to the
    /// core via the pure `ControlHitTest.balanceFraction` + `PlayerCore.setBalance`
    /// (finite-guarded + clamped). Redraws so the baked-knob frame tracks the cursor.
    private func scrubBalance(toSkinX skinX: Int) {
        guard let pan = ControlHitTest.balanceFraction(skinX: skinX) else { return }
        core.setBalance(Float(pan))
        redraw()
    }

    /// Map a skin-space x on the posbar to a seek time and apply it. Routes through
    /// the pure helpers so the value reaching `core.seek(to:)` is finite and in
    /// range: `ControlHitTest.posbarFraction` clamps the x to `0...1`, and
    /// `SeekMath.time(forFraction:duration:)` is the finite / zero-duration trap
    /// (a `nil` time — nothing loaded or a non-seekable source — does not seek, so
    /// no `NaN` can reach the engine). Redraws so the thumb tracks the cursor.
    private func seek(toSkinX skinX: Int) {
        guard let fraction = ControlHitTest.posbarFraction(skinX: skinX),
              let time = SeekMath.time(forFraction: fraction, duration: core.duration) else {
            return
        }
        core.seek(to: time)
        redraw()
    }

    private func handleMouseUp() {
        let wasInteracting = pressedControl != nil || isSeeking || draggingSlider != nil
        pressedControl = nil
        isSeeking = false
        draggingSlider = nil
        if wasInteracting { redraw() }
    }

    // MARK: Redraw

    /// Advance the title marquee for one redraw tick. Only scrolls when the title
    /// actually overflows its display region (`pixelWidth > titleTextWidth`);
    /// otherwise the offset is reset to 0 so a short title stays static and a
    /// later long title starts from the left. The offset moves one pixel every
    /// `titleScrollTickInterval` ticks (a readable pace) and is kept bounded by the
    /// scroll cycle so it never grows without limit.
    private func advanceTitleScroll() {
        let title = core.currentTrack?.title ?? ""
        guard BitmapText.pixelWidth(of: title) > MainWindowLayout.titleTextWidth else {
            titleScrollOffset = 0
            titleScrollTick = 0
            return
        }
        titleScrollTick += 1
        guard titleScrollTick >= InteractiveController.titleScrollTickInterval else { return }
        titleScrollTick = 0
        let cycle = BitmapText.scrollCycleWidth(of: title)
        titleScrollOffset = (titleScrollOffset + 1) % max(1, cycle)
    }

    /// Recompose the window from the live core state and swap the view image.
    ///
    /// Pipeline mirrors the plain window/--png path: compose the base, overlay the
    /// dynamic time + title via `BitmapText`, optionally overlay the pressed-button
    /// sprite, bridge to a CGImage, then nearest-neighbor scale. The region mask is
    /// a window-level layer mask applied ONCE at window setup, so the per-tick
    /// image stays opaque and unmasked here (the layer mask keeps clipping it).
    private func redraw() {
        guard var composed = MainWindowComposer.compose(skin) else { return }

        // Time overlay: MM:SS from the live playback position.
        let seconds = max(0, core.currentTime.isFinite ? core.currentTime : 0)
        let totalSeconds = Int(seconds.rounded(.down))
        BitmapText.drawTime(
            minutes: totalSeconds / 60,
            seconds: totalSeconds % 60,
            from: skin,
            onto: &composed,
            x: MainWindowLayout.timeDisplayOrigin.x,
            y: MainWindowLayout.timeDisplayOrigin.y
        )

        // Title overlay: the current track's title (the user's file-name stem),
        // clipped to the title display width. Empty when nothing is selected.
        // `drawScrolling` is static when the title fits and a marquee when it
        // overflows, so we always route through it and let the current scroll
        // offset ride; for a short title the offset is simply ignored.
        BitmapText.drawScrolling(
            core.currentTrack?.title ?? "",
            from: skin,
            onto: &composed,
            x: MainWindowLayout.titleTextOrigin.x,
            y: MainWindowLayout.titleTextOrigin.y,
            maxWidth: MainWindowLayout.titleTextWidth,
            offset: titleScrollOffset
        )

        // kbps / kHz overlay: when a track is loaded, draw the bitrate and
        // sample-rate number boxes from the engine's opt-in `TrackFormatProviding`
        // facts (cast like the PCM tap; format metadata never flows through
        // PlayerCore's transport). kbps is drawn straight; kHz is round(Hz/1000).
        // `drawNumber` is right-aligned and clips to its field, so a large
        // uncompressed bitrate (e.g. ~1411 kbps) never overflows the 3-cell box.
        // The kbps box is drawn only when the bitrate is known (> 0); it is
        // currently deferred (always 0 until async asset loading lands at M5), so
        // the box stays blank rather than showing "0". With nothing loaded both
        // boxes are left blank (no draw).
        if let format, core.currentTrack != nil {
            if format.bitrateKbps > 0 {
                BitmapText.drawNumber(
                    format.bitrateKbps,
                    from: skin,
                    onto: &composed,
                    x: MainWindowLayout.kbpsDisplayOrigin.x,
                    y: MainWindowLayout.kbpsDisplayOrigin.y,
                    digits: MainWindowLayout.kbpsDisplayDigits
                )
            }
            // Guard the Double->Int conversion: `Int(NaN/Inf)` traps, matching the
            // isFinite guards on every other Double->Int in the codebase.
            let khz = format.sampleRateHz.isFinite
                ? Int((format.sampleRateHz / 1000).rounded())
                : 0
            BitmapText.drawNumber(
                khz,
                from: skin,
                onto: &composed,
                x: MainWindowLayout.khzDisplayOrigin.x,
                y: MainWindowLayout.khzDisplayOrigin.y,
                digits: MainWindowLayout.khzDisplayDigits
            )
        }

        // Spectrum overlay: read the latest stashed samples (audio thread wrote
        // them), run the analyzer (main thread), and draw the bars into the vis
        // frame. With no audio flowing the samples are empty -> all-zero levels ->
        // the vis area is left as background. Drawn before the pressed-sprite so a
        // button press still reads on top.
        let snapshot = latestSamples.latest()
        let levels = analyzer.process(snapshot.samples, sampleRate: snapshot.sampleRate)
        let vis = MainWindowLayout.visualizationFrame
        SpectrumRenderer.draw(
            levels,
            into: &composed,
            x: vis.x,
            y: vis.y,
            width: vis.width,
            height: vis.height,
            palette: skin.visColors
        )

        // Volume / balance frames: the static composer draws ONE default frame
        // (volume `level27`, balance `level13`). Overlay the frame chosen from the
        // live `core.volume` / `core.balance` at the same origin so the baked knob
        // reflects the actual value (the same-size opaque frame fully covers the
        // default). Drawn before the pressed overlay so a future pressed slider art
        // could still read on top.
        overlayVolumeFrame(onto: &composed)
        overlayBalanceFrame(onto: &composed)

        // Mono / stereo indicator: the static composer lights BOTH indicators
        // (always-on art). Overlay the correct lit/dim pair from the live track's
        // channel count so the display reflects the model — mono lit for a 1-channel
        // file, stereo lit for >= 2 channels. With nothing loaded (channelCount 0)
        // the static both-lit art is left as-is. Done in the LIVE redraw only, so
        // the static composer / harness snapshots are unchanged.
        overlayMonoStereo(onto: &composed)

        // Posbar thumb: draw the draggable knob at the live playback position so
        // the bar shows progress and a grabbable handle. Position comes from the
        // pure SeekMath fraction (currentTime/duration, finite/zero-duration safe)
        // mapped to the thumb's draw origin by ControlHitTest. The pressed thumb
        // art is used while scrubbing. Drawn over the static `track`; with nothing
        // loaded (duration 0) the fraction is 0, so the thumb seats at the left.
        overlayPosbarThumb(onto: &composed)

        // Toggle / button on-state: shuffle/repeat and the EQ/PL window-toggle
        // buttons are composited in their OFF art; when one is live (shuffle on,
        // repeat != off, the EQ / playlist window open) overlay its ON sprite so
        // the button visibly lights up. Drawn before the pressed overlay so a held
        // button still reads its pressed art on top.
        overlayActiveToggles(onto: &composed)

        // Pressed-button feedback: while a transport/toggle button is held, draw
        // its pressed sprite over the released one at the control's draw origin.
        overlayPressedSprite(onto: &composed)

        guard let image = CGImageConversion.makeImage(from: composed) else { return }
        let scaled: (image: CGImage, width: Int, height: Int)
        do {
            // Integer nearest-neighbor bitmap; the view's point-sized bounds place
            // it 1:1 in device pixels at a fractional presentation scale.
            scaled = try scaledImage(image, scale: bitmapScale)
        } catch {
            return // a transient scale failure just skips this frame
        }
        view.update(image: scaled.image)
    }

    /// If a control is held, overlay its pressed sprite at its hit-rect origin
    /// (the same origin the hit rect is derived from). The pressed sprite name
    /// comes from `SkinControl.spriteName(pressed:active:)`, so a held toggle shows
    /// its on-pressed art when live (`shuffleOnPressed` / `repeatOnPressed`) and its
    /// off-pressed art otherwise; a transport button ignores `active`. A missing
    /// pressed sprite is simply skipped.
    private func overlayPressedSprite(onto base: inout DecodedBitmap) {
        guard let control = pressedControl,
              let rect = ControlHitTest.hitRect(for: control) else {
            return
        }
        let key = control.spriteName(pressed: true, active: isToggleActive(control))
        guard let sprite = skin.sprite(sheet: key.sheet, name: key.name) else {
            return
        }
        SkinCanvas.overlay(sprite, onto: &base, x: rect.x, y: rect.y)
    }

    /// Overlay the ON sprite for each toggle/button that is live — shuffle on,
    /// repeat != off, the EQ window open, or the playlist window open — at its
    /// hit-rect origin, so an active control visibly lights up over the static
    /// composited OFF art. The released (not pressed) on sprite is used here; a
    /// press is layered on top by `overlayPressedSprite`. A control that is off,
    /// or whose on sprite is missing, is left as the composed off art.
    private func overlayActiveToggles(onto base: inout DecodedBitmap) {
        let toggles: [SkinControl] = [.toggleShuffle, .toggleRepeat, .eqButton, .plButton]
        for control in toggles where isToggleActive(control) {
            guard let rect = ControlHitTest.hitRect(for: control) else { continue }
            let key = control.spriteName(pressed: false, active: true)
            guard let sprite = skin.sprite(sheet: key.sheet, name: key.name) else { continue }
            SkinCanvas.overlay(sprite, onto: &base, x: rect.x, y: rect.y)
        }
    }

    /// Whether a control's live toggle state is "on": shuffle reflects
    /// `core.isShuffle`; repeat is on for any mode other than `.off` (both `.all`
    /// and `.one` light the button — a distinct repeat-one indicator is a later
    /// refinement, deferred); the EQ / PL buttons light while their window is open
    /// (the injected `isEQWindowOpen` / `isPlaylistWindowOpen` queries). The other
    /// host actions (eject / minimize) and the transport buttons have no on/off
    /// state, so they are never "active".
    private func isToggleActive(_ control: SkinControl) -> Bool {
        switch control {
        case .toggleShuffle: return core.isShuffle
        case .toggleRepeat:  return core.repeatMode != .off
        case .eqButton:      return isEQWindowOpen()
        case .plButton:      return isPlaylistWindowOpen()
        default:             return false
        }
    }

    /// Draw the posbar thumb at the live playback position. The fraction is the
    /// pure `SeekMath.fraction(currentTime:duration:)` (zero when nothing is
    /// loaded), mapped to the thumb's top-left draw origin by
    /// `ControlHitTest.posbarThumbOrigin`. The pressed thumb art (`thumbPressed`)
    /// is used while scrubbing, the normal `thumb` otherwise. Skipped if the posbar
    /// region cannot be derived or the thumb sprite is absent (a short-strip skin),
    /// so the static track still renders alone.
    private func overlayPosbarThumb(onto base: inout DecodedBitmap) {
        let fraction = SeekMath.fraction(currentTime: core.currentTime, duration: core.duration)
        guard let origin = ControlHitTest.posbarThumbOrigin(fraction: fraction) else { return }
        let name = isSeeking ? "thumbPressed" : "thumb"
        guard let sprite = skin.sprite(sheet: "posbar.bmp", name: name) else { return }
        SkinCanvas.overlay(sprite, onto: &base, x: origin.x, y: origin.y)
    }

    /// Overlay the volume slider frame chosen from the live `core.volume` at the
    /// slider's draw origin, replacing the static default frame (`level27`). The
    /// frame name comes from the pure `ControlHitTest.volumeLevelFrame(forVolume:)`
    /// (`level0`..`level27`); the same-size opaque frame fully covers the default.
    /// Skipped if the region or the chosen frame sprite is absent (a sparse skin),
    /// leaving the static frame in place.
    private func overlayVolumeFrame(onto base: inout DecodedBitmap) {
        guard let rect = ControlHitTest.volumeRect() else { return }
        let name = ControlHitTest.volumeLevelFrame(forVolume: Double(core.volume))
        guard let sprite = skin.sprite(sheet: "volume.bmp", name: name) else { return }
        SkinCanvas.overlay(sprite, onto: &base, x: rect.x, y: rect.y)
    }

    /// Overlay the balance slider frame chosen from the live `core.balance` pan
    /// (`-1...1`, center = balanced) at the slider's draw origin, replacing the
    /// static default frame (`level13`). The frame name comes from the pure
    /// `ControlHitTest.balanceLevelFrame(forBalance:)`. Skipped if the region or the
    /// chosen frame sprite is absent.
    private func overlayBalanceFrame(onto base: inout DecodedBitmap) {
        guard let rect = ControlHitTest.balanceRect() else { return }
        let name = ControlHitTest.balanceLevelFrame(forBalance: Double(core.balance))
        guard let sprite = skin.sprite(sheet: "balance.bmp", name: name) else { return }
        SkinCanvas.overlay(sprite, onto: &base, x: rect.x, y: rect.y)
    }

    /// Overlay the correct mono / stereo indicator pair from the live track's
    /// channel count, so the display reflects the model instead of the static
    /// always-both-lit art:
    ///   • mono (1 channel)   -> mono lit + stereo dim
    ///   • stereo (>= 2)      -> stereo lit + mono dim
    ///   • nothing loaded (0) -> leave the static both-lit art (no overlay)
    /// Each lit/dim sprite is overlaid at its own static layout origin (read from
    /// `MainWindowLayout.elements`), so the indicators stay pinned to the same spot
    /// the composer drew them. A missing sprite for a given state is simply skipped.
    /// This runs ONLY in the live redraw — the static composer keeps drawing both
    /// lit, so the harness snapshots are unchanged.
    private func overlayMonoStereo(onto base: inout DecodedBitmap) {
        guard let format, core.currentTrack != nil else { return }
        let channels = format.channelCount
        guard channels > 0 else { return }
        let isStereo = channels >= 2
        overlayMonoStereoSprite(name: isStereo ? "stereoActive" : "stereoInactive", onto: &base)
        overlayMonoStereoSprite(name: isStereo ? "monoInactive" : "monoActive", onto: &base)
    }

    /// Overlay one `monoster.bmp` sprite at the layout origin of its sheet/state.
    /// The origin is read from the matching `MainWindowLayout.elements` entry: the
    /// lit `monoActive` / `stereoActive` states each have a static element, and the
    /// dim `monoInactive` / `stereoInactive` states reuse the SAME origin as their
    /// lit counterpart (the indicator does not move, only its lit/dim art changes).
    private func overlayMonoStereoSprite(name: String, onto base: inout DecodedBitmap) {
        // The lit element name a given state draws at: a dim state reuses its lit
        // counterpart's origin (same on-window slot).
        let originName: String
        switch name {
        case "monoActive", "monoInactive":     originName = "monoActive"
        case "stereoActive", "stereoInactive": originName = "stereoActive"
        default:                                originName = name
        }
        guard let element = MainWindowLayout.elements.first(where: {
            $0.sheet == "monoster.bmp" && $0.sprite == originName
        }) else {
            return
        }
        guard let sprite = skin.sprite(sheet: "monoster.bmp", name: name) else { return }
        SkinCanvas.overlay(sprite, onto: &base, x: element.x, y: element.y)
    }
}
