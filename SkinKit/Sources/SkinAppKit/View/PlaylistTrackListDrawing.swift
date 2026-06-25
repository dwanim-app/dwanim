import AppKit
import CoreGraphics
import CoreText
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The shared track-list text drawing for the classic playlist (PLEDIT) window:
// the `drawPlaylistTrackList` routine plus its private CoreText line helper (per
// §12: one primary type per file). The skin-driven `PlaylistTextStyle` it consumes
// lives in `PlaylistTextStyle.swift` (its own home, §12).
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier (no
// behavior change) so the live playlist view (also in SkinAppKit) AND the harness
// offscreen snapshot draw the list the same way and cannot drift. It is `public`
// so the harness snapshot mode can still call it.

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
/// Each visible row draws its title in the pledit font at `normalText`. The
/// `selectedIndex` row (if visible) gets a `selectedBackground` fill — the user's
/// chosen-but-not-yet-playing highlight; the `currentIndex` row draws its title at
/// `currentText` so the now-playing row reads at a glance. When a row is BOTH
/// selected and current it gets the selection fill and the current text color.
/// Rows are clipped to the interior, and a too-long title is truncated by the
/// clip (no wrapping).
public func drawPlaylistTrackList(
    in context: CGContext,
    skin: Skin,
    tracks: [Track],
    currentIndex: Int?,
    selectedIndex: Int? = nil,
    scrollRow: Int,
    skinWidth: Int,
    skinHeight: Int,
    scale: Int
) {
    let interior = PlaylistWindowComposer.interiorRect(width: skinWidth, height: skinHeight, skin: skin)
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

        let isSelected = (row == selectedIndex)
        let isCurrent = (row == currentIndex)
        if isSelected, let selBG = style.selectedBackground {
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
