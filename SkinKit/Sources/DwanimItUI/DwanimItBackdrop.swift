import SwiftUI

// MARK: - DwanimItBackdrop

/// The colourful desktop backdrop that sits BEHIND the glass player panel so the
/// translucent material has something to blur — without it the frosted panel reads
/// as flat grey.
///
/// Per the design it is a vertical `bg1 → bg2` gradient with two soft radial glows
/// (`glow` upper-left, `glow2` upper-right). Every colour comes from the current
/// `AppearanceTheme`, so switching the theme retints the backdrop along with the
/// panel.
///
/// It fills exactly the space its parent gives it — used as a BOUNDED `.background`
/// of the pinned panel in `DwanimItPlayerScene`, not a full-bleed `ignoresSafeArea`
/// fill — so the scene keeps a compact intrinsic size for the window to hug.
public struct DwanimItBackdrop: View {

    private let theme: AppearanceTheme

    public init(theme: AppearanceTheme) {
        self.theme = theme
    }

    public var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack {
                LinearGradient(
                    colors: [theme.bg1, theme.bg2],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [theme.glow, .clear],
                    center: UnitPoint(x: 0.2, y: 0.08),
                    startRadius: 0,
                    endRadius: max(1, w * 0.55)
                )
                RadialGradient(
                    colors: [theme.glow2, .clear],
                    center: UnitPoint(x: 0.85, y: 0.18),
                    startRadius: 0,
                    endRadius: max(1, w * 0.5)
                )
            }
        }
    }
}
