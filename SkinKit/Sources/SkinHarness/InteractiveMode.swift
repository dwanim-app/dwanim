import AppKit
import CoreGraphics
import Foundation
import PlaybackKit
import PlayerControl
import PlayerCore
import SkinKit
import SkinKitImageIO
import SkinRender
import SpectrumKit

// SkinHarness interactive mode: a dev-only path that wires the rendered skin
// window to the audio core so clicking the transport buttons actually controls
// playback. This lives in its own file (per the harness's "thin shell, small
// functions" convention); `main.swift` dispatches here when `--interactive` is
// present.
//
// Usage:
//   SkinHarness --interactive <skin.wsz> <audiofile> [<audiofile>...] [--scale N]
//
// Flow:
//   1. Load the skin (SkinLoader + ImageIOBitmapDecoder) and confirm it composes.
//   2. Build a PlayerCore over the concrete engine; load the given audio files as
//      a playlist (each Track.title is the file-name stem — the user's own file,
//      so it is fine to display; NO brand title is invented).
//   3. Open the skin window, reusing the same scale + region-mask pipeline as the
//      plain window mode. The content view accepts mouse clicks.
//   4. mouseDown -> skin-space coords -> ControlHitTest -> a PlayerCore action.
//   5. A ~0.2s repeating main-run-loop timer recomposes the window from the live
//      PlayerCore state (time + title overlays, optional pressed-button feedback)
//      and swaps the view's image.
//
// The ONLY text drawn is the audio file's own name (the title) and the MM:SS time
// — no brand names anywhere.

// MARK: - Argument parsing

/// Parsed interactive-mode arguments: the skin path, one-or-more audio files, and
/// the integer zoom.
private struct InteractiveArguments {
    var skinPath: String
    var audioPaths: [String]
    var scale: Int
}

private let interactiveUsage =
    "Usage: SkinHarness --interactive <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"

/// Parse the interactive-mode argument vector. `argv` is the full process
/// argument list; the `--interactive` flag and everything after it is consumed
/// here. The first non-option positional is the skin path; the rest are audio
/// files. `--scale N` may appear anywhere after the flag.
private func parseInteractiveArguments(_ argv: [String]) -> InteractiveArguments {
    guard let flagIndex = argv.firstIndex(of: "--interactive") else {
        interactiveFail("Internal: --interactive dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2

    var index = flagIndex + 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), (1...16).contains(value) else {
                interactiveFail(
                    "--scale requires an integer in 1...16 (larger values overflow the "
                        + "scaled-image dimensions). \(interactiveUsage)"
                )
            }
            scale = value
            index += 2
        default:
            positionals.append(arg)
            index += 1
        }
    }

    guard let skinPath = positionals.first else {
        interactiveFail("Missing required skin path. \(interactiveUsage)")
    }
    let audioPaths = Array(positionals.dropFirst())
    guard !audioPaths.isEmpty else {
        interactiveFail("Missing required audio file(s). \(interactiveUsage)")
    }

    return InteractiveArguments(skinPath: skinPath, audioPaths: audioPaths, scale: scale)
}

// MARK: - Live mutable content view

/// A content view that draws a `CGImage` with nearest-neighbor scaling (like
/// `SkinImageView`) but whose image can be SWAPPED each timer tick, and which
/// forwards mouse-down / mouse-up to a controller.
///
/// Coordinate note: this is a default (NON-flipped) `NSView`, so an
/// `NSEvent.locationInWindow` converted into this view has origin at the
/// BOTTOM-left with y increasing UPWARD. The composed skin image is top-left
/// origin (y down). The view forwards the raw view-space point (plus its own
/// height) on mouse-down; mapping that back to skin space (undo scale + y-flip)
/// is the pure `ControlHitTest.skinPoint(...)`, which the controller drives —
/// the view itself carries no coordinate math.
final class InteractiveSkinView: NSView {
    private var image: CGImage

    /// Called on mouse-down with the click point in this view's coordinate space
    /// (non-flipped, bottom-left origin, scaled points) plus the view's height,
    /// so the controller can map it to skin space via `ControlHitTest`.
    var onMouseDown: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double) -> Void)?
    var onMouseUp: (() -> Void)?

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Swap the displayed image and request a redraw. Same pixel size each tick,
    /// so the frame is unchanged.
    func update(image: CGImage) {
        self.image = image
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        onMouseDown?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }
}

// MARK: - Latest-samples holder
//
// The single point of contact between the audio render thread (which produces
// PCM in the tap) and the main thread (which consumes it in the redraw timer).
// The tap does the MINIMUM on the audio thread: it just stashes the most recent
// mono frame + sample rate under a lock. No analysis, no allocation beyond the
// frame copy, no UI. The main thread reads the latest snapshot and runs the FFT.
//
// An `NSLock` (not a serial queue) keeps the audio-thread critical section tiny
// and non-blocking-ish — store/read a small struct and return. Only the latest
// frame is kept (older frames are simply overwritten); the analyzer always wants
// the most recent window, so dropping stale frames is correct, not lossy.
private final class LatestSamples {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 44_100

    /// Audio-thread entry point: overwrite the stashed frame. Tiny critical
    /// section — copy the array reference and the rate, then return.
    func store(_ samples: [Float], sampleRate: Double) {
        lock.lock()
        self.samples = samples
        self.sampleRate = sampleRate
        lock.unlock()
    }

    /// Main-thread entry point: read the latest stashed frame + rate.
    func latest() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (samples, sampleRate)
    }
}

// MARK: - Controller

/// Owns the live window: the skin, the core, the view, and the redraw timer. It
/// recomposes the window each tick from the current `PlayerCore` state and swaps
/// the view's image, and routes mouse-down hits to `apply(_:to:)`.
///
/// It also owns the spectrum visualizer wiring: an audio tap stashes the latest
/// mono samples into a lock-guarded `LatestSamples` (audio thread, minimum work),
/// and the redraw timer (main thread) reads that snapshot, runs the
/// `SpectrumAnalyzer`, and draws the bars via `SpectrumRenderer`. The analyzer and
/// all SkinRender drawing stay on the main thread.
private final class InteractiveController {
    private let skin: Skin
    private let core: PlayerCore
    private let view: InteractiveSkinView
    private let scale: Int

    /// The control currently held down (for pressed-sprite feedback), or `nil`.
    private var pressedControl: SkinControl?

    private var timer: Timer?

    // MARK: Spectrum wiring

    /// The engine's PCM tap source (the same object backing `core`). Kept so the
    /// tap can be installed in `start()` and removed in `stop()`.
    private let tap: AudioTapProviding?
    /// Lock-guarded latest mono samples, written by the audio thread and read by
    /// the main-thread redraw timer.
    private let latestSamples = LatestSamples()
    /// FFT spectrum analyzer (main-thread only). `barCount` is chosen to fit the
    /// visualization frame width.
    private let analyzer: SpectrumAnalyzer

    /// Number of spectrum bars. Chosen so each bar gets a few pixels across the
    /// provisional vis frame width (~76px): 19 bars ≈ 4px/slot.
    private static let barCount = 19

    init(skin: Skin, core: PlayerCore, view: InteractiveSkinView, scale: Int, tap: AudioTapProviding?) {
        self.skin = skin
        self.core = core
        self.view = view
        self.scale = scale
        self.tap = tap
        self.analyzer = SpectrumAnalyzer(barCount: InteractiveController.barCount)

        view.onMouseDown = { [weak self] viewX, viewY, viewHeight in
            self?.handleMouseDown(viewX: viewX, viewY: viewY, viewHeight: viewHeight)
        }
        view.onMouseUp = { [weak self] in self?.handleMouseUp() }
    }

    /// Start the redraw loop on the main run loop and install the audio tap.
    ///
    /// The tap block runs on the AUDIO render thread and does the minimum: stash
    /// the latest mono samples + sample rate under a lock. The redraw timer (main
    /// thread) does the analysis + drawing. The timer runs at ~25 Hz so the
    /// spectrum animates smoothly (full-window recompose per tick is acceptable
    /// for the dev harness; the static/dynamic patch seam is a tracked M5 item).
    func start() {
        tap?.installTap { [weak self] samples, sampleRate in
            // AUDIO THREAD: minimum work — stash and return.
            self?.latestSamples.store(samples, sampleRate: sampleRate)
        }

        redraw()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.redraw()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stop the redraw loop and remove the audio tap. Optional teardown; safe if
    /// nothing was installed.
    func stop() {
        timer?.invalidate()
        timer = nil
        tap?.removeTap()
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
        BitmapText.draw(
            core.currentTrack?.title ?? "",
            from: skin,
            onto: &composed,
            x: MainWindowLayout.titleTextOrigin.x,
            y: MainWindowLayout.titleTextOrigin.y,
            maxWidth: MainWindowLayout.titleTextWidth
        )

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

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it).
private var liveController: InteractiveController?

// MARK: - Entry point

/// Run the interactive mode and never return: it opens the window, starts the
/// redraw loop, and drives the main run loop (exits the process itself).
func runInteractiveMode() -> Never {
    let arguments = parseInteractiveArguments(CommandLine.arguments)

    // Load + compose the skin (fault checks mirror the plain window path).
    let skinURL = URL(fileURLWithPath: arguments.skinPath)
    let skinData: Data
    do {
        skinData = try Data(contentsOf: skinURL)
    } catch {
        interactiveFail("Could not read skin file at \(arguments.skinPath): \(error.localizedDescription)")
    }

    let skin: Skin
    do {
        skin = try SkinLoader.load(skinData, decoder: ImageIOBitmapDecoder())
    } catch {
        interactiveFail("Could not load skin at \(arguments.skinPath): \(error)")
    }

    guard MainWindowComposer.compose(skin) != nil else {
        interactiveFail(
            "Could not compose main window for skin at \(arguments.skinPath): "
                + "no main-window background (main.bmp/background)."
        )
    }

    // Build the core and load the audio files. Each Track.title is the file's own
    // name stem (the user's file — fine to display); NO brand title is invented.
    let tracks = arguments.audioPaths.map { path -> Track in
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        return Track(url: url, title: stem)
    }
    // Keep the concrete engine so it can be opt-in cast to `AudioTapProviding`
    // for the spectrum tap (PCM must never flow through PlayerCore's transport).
    let engine = AVAudioEnginePlayer()
    let core = PlayerCore(engine: engine)
    core.load(tracks)

    // Open the window, reusing the existing scale + region-mask pipeline.
    let region = skin.region.flatMap { $0.polygons.isEmpty ? nil : $0 }
    openInteractiveWindow(skin: skin, core: core, tap: engine, region: region, scale: arguments.scale)
}

/// Build and show the skin window, reusing the same opaque-content + window-level
/// region-mask approach as `runWindowMode`, then start the redraw loop and run
/// the app. Never returns.
private func openInteractiveWindow(
    skin: Skin,
    core: PlayerCore,
    tap: AudioTapProviding?,
    region: SkinRegion?,
    scale: Int
) -> Never {
    // Compose an initial frame just to size the window (the controller will keep
    // it updated). compose() already succeeded above.
    guard let base = MainWindowComposer.compose(skin),
          let image = CGImageConversion.makeImage(from: base) else {
        interactiveFail("Could not build an image from the composed main window.")
    }

    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        interactiveFail("Failed to render skin: \(error)")
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    let contentView = InteractiveSkinView(image: scaled.image, frame: contentRect)

    // Window-level region mask (same as the plain window path): the content stays
    // opaque and the shape is carried by a CAShapeLayer mask.
    let maskLayer: CAShapeLayer? = region.flatMap { region in
        RegionMaskLayer.make(
            for: region,
            skinHeight: base.height,
            scale: scale,
            scaledWidth: scaled.width,
            scaledHeight: scaled.height
        )
    }

    let window: NSWindow
    if let maskLayer {
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        contentView.wantsLayer = true
        contentView.layer?.mask = maskLayer
    } else {
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SkinHarness"
    }
    window.contentView = contentView
    window.center()
    window.makeKeyAndOrderFront(nil)

    let controller = InteractiveController(skin: skin, core: core, view: contentView, scale: scale, tap: tap)
    liveController = controller
    controller.start()

    app.activate(ignoringOtherApps: true)
    app.run()

    // app.run() does not return in normal use; treat a return as a clean stop.
    exit(0)
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors `main.swift`'s `fail`,
/// kept local so the interactive mode is self-contained.
private func interactiveFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
