import SwiftUI

// MARK: - EmblemTile

/// The emblem tile on the left of the player bar. It renders the EXACT same
/// bitmap as the app icon — `dwennimmen-emblem.png`, a copy of the committed
/// `icon_256x256.png` (teal ground + gold Dwennimmen glyph) — clipped to a
/// rounded-rect with a subtle edge stroke. Because it is the same PNG (no shape
/// redraw), the in-window emblem matches the dock/Finder icon pixel-for-pixel.
///
/// This is the ONLY heritage element and it appears as imagery only — there is
/// no "Dwennimmen" text anywhere in the running UI. The old vector
/// `DwennimmenMark` stroke (kept in `DwennimmenMark.swift`) is no longer used to
/// draw the emblem.
struct EmblemTile: View {

    /// The tile's side length in points.
    let side: CGFloat

    var body: some View {
        Image("dwennimmen-emblem", bundle: .module)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
            .overlay {
                // A subtle white-ish edge so the teal tile reads as a panel on
                // the glass bar (matches the rest of the dock-bar's edges).
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .stroke(DwanimTheme.glassStrokeStrong, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
