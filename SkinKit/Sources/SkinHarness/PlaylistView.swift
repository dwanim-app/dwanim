import AppKit
import CoreGraphics
import CoreText
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The playlist window's content view + controller + the shared track-list text
// drawing. Split out of `PlaylistMode.swift` to keep each file small (the
// harness's "thin shell, small files" convention). The text drawing is factored
// into a free function so the live view AND the offscreen snapshot draw the list
// the same way.

// MARK: - Track-list text drawing (shared by live view + snapshot)

/// Draw the visible track titles via CoreText into `context`, clipped to the
/// frame's interior. This is the ONE place platform text is produced for the
/// playlist; the live view and the headless snapshot both call it so they cannot
/// drift.
///
/// Coordinates: `context` is the view/bitmap context whose origin is BOTTOM-left
/// (y up), already scaled so 1 context unit == 1 scaled pixel. `skinWidth` /
/// `skinHeight` are the UNSCALED composed-frame dimensions; `scale` maps skin
/// pixels to context units. The interior rect (top-left origin, skin pixels) is
/// flipped into the bottom-left context space here.
///
/// Each visible row draws its title in the pledit font at `normalText`, except
/// the current track which draws at `currentText` over a `selectedBackground`
/// fill (so the now-playing row reads at a glance). Rows are clipped to the
/// interior, and a too-long title is truncated by the clip (no wrapping).
func drawPlaylistTrackList(
    in context: CGContext,
    skin: Skin,
    tracks: [Track],
    currentIndex: Int?,
    scrollRow: Int,
    skinWidth: Int,
    skinHeight: Int,
    scale: Int
) {
    let interior = PlaylistWindowComposer.interiorRect(width: skinWidth, height: skinHeight)
    guard interior.w > 0, interior.h > 0 else { return }

    let rowHeight = PlaylistTextStyle.rowHeight
    let layout = PlaylistLayout.visibleRows(
        trackCount: tracks.count,
        scrollRow: scrollRow,
        interiorHeight: interior.h,
        rowHeight: rowHeight
    )
    guard layout.count > 0 else { return }

    let style = PlaylistTextStyle(skin: skin, scale: scale)

    context.saveGState()
    defer { context.restoreGState() }

    // Clip to the interior, converted from top-left skin space to bottom-left
    // context space and multiplied by scale. Everything below is drawn inside
    // this clip so a long title or a partial bottom row never bleeds onto chrome.
    let clip = scaledFlippedRect(
        x: interior.x, y: interior.y, w: interior.w, h: interior.h,
        skinHeight: skinHeight, scale: scale
    )
    context.clip(to: clip)

    for row in layout.firstVisible..<layout.lastVisible {
        guard tracks.indices.contains(row) else { break }
        let title = tracks[row].title ?? tracks[row].url.lastPathComponent

        // Row rect in skin space (top-left origin): rows stack down from the
        // interior top, offset by how far we have scrolled.
        let rowTopY = interior.y + (row - layout.firstVisible) * rowHeight
        let rowRectSkin = (x: interior.x, y: rowTopY, w: interior.w, h: rowHeight)
        let rowRect = scaledFlippedRect(
            x: rowRectSkin.x, y: rowRectSkin.y, w: rowRectSkin.w, h: rowRectSkin.h,
            skinHeight: skinHeight, scale: scale
        )

        let isCurrent = (row == currentIndex)
        if isCurrent, let selBG = style.selectedBackground {
            context.setFillColor(selBG)
            context.fill(rowRect)
        }

        let color = isCurrent ? style.currentText : style.normalText
        drawLine(
            title,
            in: context,
            rect: rowRect,
            font: style.font,
            color: color,
            leftPaddingScaled: CGFloat(PlaylistTextStyle.leftPadding * scale)
        )
    }
}

/// Draw one line of text left-aligned and vertically centered within `rect`
/// (bottom-left origin), via a CoreText line. The caller's clip bounds the line;
/// CoreText itself does not truncate, so an over-long title simply runs into the
/// clip edge.
private func drawLine(
    _ string: String,
    in context: CGContext,
    rect: CGRect,
    font: CTFont,
    color: CGColor,
    leftPaddingScaled: CGFloat
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)

    // Vertical centering: place the text baseline so the cap-height band sits in
    // the middle of the row. Using ascent/descent keeps it visually centered
    // regardless of the chosen point size.
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    let textHeight = ascent + descent
    let baselineY = rect.minY + (rect.height - textHeight) / 2 + descent

    context.textPosition = CGPoint(x: rect.minX + leftPaddingScaled, y: baselineY)
    CTLineDraw(line, context)
}

/// Map a top-left-origin skin-pixel rect into the bottom-left-origin, scaled
/// context space. `skinHeight` is the unscaled composed-frame height.
private func scaledFlippedRect(
    x: Int, y: Int, w: Int, h: Int,
    skinHeight: Int, scale: Int
) -> CGRect {
    let s = CGFloat(scale)
    // Flip y: a skin-space top edge at `y` is `skinHeight - y - h` from the
    // bottom. Multiply through by scale.
    let bottomY = CGFloat(skinHeight - y - h) * s
    return CGRect(x: CGFloat(x) * s, y: bottomY, width: CGFloat(w) * s, height: CGFloat(h) * s)
}

// MARK: - Text style (font + colors from the skin)

/// Resolves the pledit font + colors into CoreText / CoreGraphics types once per
/// draw. The classic playlist text uses the SYSTEM font named in `pledit.txt`;
/// when the skin names no usable font we fall back to a sane monospaced system
/// font so the list is always legible.
struct PlaylistTextStyle {
    /// Unscaled per-row height in skin pixels. The classic list is a compact
    /// fixed row; 12px reads well at the typical small base point size and tiles
    /// the interior cleanly.
    static let rowHeight = 12
    /// Unscaled point size for the list text (skin pixels).
    static let fontPointSize = 9
    /// Unscaled left inset before each title so text does not hug the edge.
    static let leftPadding = 3

    let font: CTFont
    let normalText: CGColor
    let currentText: CGColor
    let selectedBackground: CGColor?

    init(skin: Skin, scale: Int) {
        let pointSize = CGFloat(PlaylistTextStyle.fontPointSize * scale)
        self.font = PlaylistTextStyle.resolveFont(named: skin.playlist?.font, pointSize: pointSize)

        // Classic defaults: green-on-black list, brighter white for the current
        // row, no selection fill unless the skin declares one.
        self.normalText = PlaylistTextStyle.cgColor(
            skin.playlist?.normalText, fallback: SkinKit.RGBColor(r: 0, g: 255, b: 0)
        )
        self.currentText = PlaylistTextStyle.cgColor(
            skin.playlist?.currentText, fallback: SkinKit.RGBColor(r: 255, g: 255, b: 255)
        )
        self.selectedBackground = skin.playlist?.selectedBackground.map { PlaylistTextStyle.cgColor($0) }
    }

    /// Build a `CTFont` for the named system font at `pointSize`, falling back to
    /// a monospaced system font when the name is missing or unresolvable (so the
    /// classic fixed-pitch look is preserved and the list never fails to draw).
    private static func resolveFont(named name: String?, pointSize: CGFloat) -> CTFont {
        if let name, !name.isEmpty {
            let named = CTFontCreateWithName(name as CFString, pointSize, nil)
            // CTFontCreateWithName substitutes a default when the name is unknown;
            // that is acceptable here (we still get a legible font at our size).
            return named
        }
        let monospaced = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        return monospaced as CTFont
    }

    private static func cgColor(
        _ rgb: SkinKit.RGBColor?,
        fallback: SkinKit.RGBColor = SkinKit.RGBColor(r: 0, g: 255, b: 0)
    ) -> CGColor {
        let c = rgb ?? fallback
        return CGColor(
            srgbRed: CGFloat(c.r) / 255,
            green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255,
            alpha: 1
        )
    }
}

// MARK: - Live content view

/// The playlist window's content view: draws the scaled frame bitmap (nearest
/// neighbor) and the visible track list (CoreText), and forwards mouse-wheel
/// scrolls to the controller. NON-flipped (bottom-left origin), like
/// `SkinImageView`; the text drawing flips into this space itself.
final class PlaylistContentView: NSView {
    private var frameImage: CGImage
    private let skin: Skin
    private let scale: Int
    private let skinWidth: Int
    private let skinHeight: Int

    /// Pulled fresh each redraw so the list reflects the live core.
    var tracksProvider: () -> [Track] = { [] }
    var currentIndexProvider: () -> Int? = { nil }
    var scrollRowProvider: () -> Int = { 0 }
    /// Called on a wheel scroll with the signed row delta; the controller clamps
    /// and stores it, then triggers a redraw.
    var onScroll: ((_ rowDelta: Int) -> Void)?

    init(frameImage: CGImage, skin: Skin, scale: Int, skinWidth: Int, skinHeight: Int, frame: NSRect) {
        self.frameImage = frameImage
        self.skin = skin
        self.scale = scale
        self.skinWidth = skinWidth
        self.skinHeight = skinHeight
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(frameImage, in: bounds)

        drawPlaylistTrackList(
            in: context,
            skin: skin,
            tracks: tracksProvider(),
            currentIndex: currentIndexProvider(),
            scrollRow: scrollRowProvider(),
            skinWidth: skinWidth,
            skinHeight: skinHeight,
            scale: scale
        )
    }

    override func scrollWheel(with event: NSEvent) {
        // One wheel notch ~= scroll by a row. `scrollingDeltaY > 0` is an upward
        // scroll (content moves down -> toward the top of the list), so a positive
        // delta DECREASES the scroll row. Quantize to at least one row per event
        // so a small trackpad nudge still moves the list.
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        let rows = max(1, Int(abs(dy).rounded(.up) / 10))
        onScroll?(dy > 0 ? -rows : rows)
    }
}

// MARK: - Default window geometry

/// Default unscaled playlist-window size (skin pixels). Kept in a plain,
/// non-actor-isolated namespace so the headless snapshot path can read it too
/// (the controller is `@MainActor`; these constants are not UI state). Wide
/// enough for a readable title column and tall enough for ~14 rows.
enum PlaylistWindowGeometry {
    static let defaultWidth = 275
    static let defaultHeight = 232
}

// MARK: - Controller

/// Owns the playlist window: the view, the core, the scroll position, and
/// teardown. The list is static (no playback timer needed for the list view);
/// scroll events drive a redraw. Kept minimal — click-to-play and resize are
/// deferred to later increments.
@MainActor
final class PlaylistWindowController: NSObject, NSWindowDelegate, NSApplicationDelegate {
    private let core: PlayerCore
    private weak var view: PlaylistContentView?
    private let interiorHeight: Int
    private var scrollRow = 0

    init(core: PlayerCore, interiorHeight: Int) {
        self.core = core
        self.interiorHeight = interiorHeight
        super.init()
    }

    func attach(view: PlaylistContentView) {
        self.view = view
        view.tracksProvider = { [weak self] in self?.core.playlist ?? [] }
        view.currentIndexProvider = { [weak self] in self?.core.currentIndex }
        view.scrollRowProvider = { [weak self] in self?.scrollRow ?? 0 }
        view.onScroll = { [weak self] rowDelta in self?.scrollBy(rowDelta) }
    }

    /// Apply a row delta, clamped by the pure helper, and redraw if it moved.
    private func scrollBy(_ rowDelta: Int) {
        let layout = PlaylistLayout.visibleRows(
            trackCount: core.playlist.count,
            scrollRow: scrollRow + rowDelta,
            interiorHeight: interiorHeight,
            rowHeight: PlaylistTextStyle.rowHeight
        )
        guard layout.scrollRow != scrollRow else { return }
        scrollRow = layout.scrollRow
        view?.needsDisplay = true
    }

    // MARK: NSWindowDelegate / NSApplicationDelegate

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it).
private var livePlaylistController: PlaylistWindowController?

// MARK: - Window setup

/// Build and show the playlist window, then run the app. Never returns.
@MainActor
func openPlaylistWindow(skin: Skin, core: PlayerCore, scale: Int) -> Never {
    let width = PlaylistWindowGeometry.defaultWidth
    let height = PlaylistWindowGeometry.defaultHeight

    guard let frame = PlaylistWindowComposer.compose(skin, width: width, height: height),
          let image = CGImageConversion.makeImage(from: frame) else {
        FileHandle.standardError.write(Data("Could not build the playlist frame image.\n".utf8))
        exit(1)
    }

    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        FileHandle.standardError.write(Data("Failed to scale the playlist frame: \(error)\n".utf8))
        exit(1)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    // Compose returns the CLAMPED size; use the frame's actual dimensions so the
    // text layout matches the bitmap exactly.
    let view = PlaylistContentView(
        frameImage: scaled.image,
        skin: skin,
        scale: scale,
        skinWidth: frame.width,
        skinHeight: frame.height,
        frame: contentRect
    )

    let interior = PlaylistWindowComposer.interiorRect(width: frame.width, height: frame.height)
    let controller = PlaylistWindowController(core: core, interiorHeight: interior.h)
    controller.attach(view: view)
    livePlaylistController = controller

    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Playlist"
    window.delegate = controller
    window.contentView = view
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.delegate = controller
    app.activate(ignoringOtherApps: true)
    app.run()

    exit(0)
}
