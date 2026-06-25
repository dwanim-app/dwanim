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
public final class InteractiveController: SkinWindowController {
    private let skin: Skin
    private let core: PlayerCore
    private let view: ScaledImageView
    private let scale: Int

    /// The control currently held down (for pressed-sprite feedback), or `nil`.
    private var pressedControl: SkinControl?

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
    /// `RedrawLoop`, which installs and removes it.)
    private let format: TrackFormatProviding?
    /// Lock-guarded latest mono samples, written by the audio thread and read by
    /// the main-thread redraw timer (the shared `SpectrumKit.SpectrumFeed`).
    private let latestSamples = SpectrumFeed()
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

    public init(
        skin: Skin,
        core: PlayerCore,
        view: ScaledImageView,
        scale: Int,
        tap: AudioTapProviding?,
        format: TrackFormatProviding?
    ) {
        self.skin = skin
        self.core = core
        self.view = view
        self.scale = scale
        self.format = format

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

        super.init()

        // The shared view carries the event's clickCount for windows that
        // distinguish single vs double click; the main window does not, so it is
        // ignored here.
        view.onMouseDown = { [weak self] viewX, viewY, viewHeight, _ in
            self?.handleMouseDown(viewX: viewX, viewY: viewY, viewHeight: viewHeight)
        }
        view.onMouseUp = { [weak self] in self?.handleMouseUp() }

        // ~25 Hz: full-window recompose per tick (acceptable for the dev harness;
        // the static/dynamic patch seam is a tracked M5 item). The per-tick work
        // advances the title marquee at the timer cadence (NOT on the mouse-driven
        // redraws, so a click does not jerk the scroll) and recomposes.
        redrawLoop = RedrawLoop(
            interval: 0.04,
            tap: tap,
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
    /// the tap) before the process exits. Without this, closing the titled
    /// fallback window would leave the ~25 Hz `redraw()` timer firing against a
    /// dead view and the audio tap still installed. The base then terminates the
    /// app so the run loop exits cleanly. (The borderless region window has no
    /// close button, but wiring the delegate there too keeps teardown correct if
    /// it is ever closed.)
    public override func tearDown() {
        redrawLoop?.stop()
    }

    // MARK: Mouse

    /// A click hits a control -> apply its action. The view-space point is mapped
    /// to a control by the pure `ControlHitTest` (undo scale + y-flip), and the
    /// action by the pure `PlayerControl`. A pressed transport button is recorded
    /// so the next redraw can show its pressed sprite.
    private func handleMouseDown(viewX: Double, viewY: Double, viewHeight: Double) {
        guard let control = ControlHitTest.control(
            atViewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        ) else {
            return
        }
        pressedControl = control
        PlayerControl.apply(control, to: core)
        redraw()
    }

    private func handleMouseUp() {
        guard pressedControl != nil else { return }
        pressedControl = nil
        redraw()
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

        // Pressed-button feedback: while a transport/toggle button is held, draw
        // its pressed sprite over the released one at the control's draw origin.
        overlayPressedSprite(onto: &composed)

        guard let image = CGImageConversion.makeImage(from: composed) else { return }
        let scaled: (image: CGImage, width: Int, height: Int)
        do {
            scaled = try scaledImage(image, scale: scale)
        } catch {
            return // a transient scale failure just skips this frame
        }
        view.update(image: scaled.image)
    }

    /// If a control is held, overlay its pressed sprite at its hit-rect origin
    /// (the same origin the hit rect is derived from). The pressed sprite name
    /// comes from the unified `SkinControl.spriteName(pressed:)` — the single
    /// source of truth shared with the hit-test layout, so the released/pressed
    /// tables cannot drift. A missing pressed sprite is simply skipped.
    private func overlayPressedSprite(onto base: inout DecodedBitmap) {
        guard let control = pressedControl,
              let rect = ControlHitTest.hitRect(for: control) else {
            return
        }
        let key = control.spriteName(pressed: true)
        guard let sprite = skin.sprite(sheet: key.sheet, name: key.name) else {
            return
        }
        SkinCanvas.overlay(sprite, onto: &base, x: rect.x, y: rect.y)
    }
}
