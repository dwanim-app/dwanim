import Foundation

// MARK: - PlaylistBarLayout

/// PURE hit geometry for the classic playlist (PLEDIT) window's BOTTOM BAR:
/// the five pop-up menu buttons (ADD / REM / SEL / MISC / LIST OPTS) and the
/// six mini-transport buttons (previous / play / pause / stop / next / eject).
///
/// The art for all of these is BAKED into the `bottomLeftCorner` /
/// `bottomFill` / `bottomRightCorner` pieces that `PlaylistWindowComposer`
/// already composites — there are no per-button sprites and no pressed states
/// in the classic format's playlist bar. So, exactly like the title-bar close
/// button (`PlaylistWindowComposer.closeButtonRect`), this table declares HIT
/// RECTS only, parametrized by the LIVE composed size so every rect stays
/// glued to its corner across a drag-resize:
///   * the four left menu buttons are glued to the bottom-LEFT corner
///     (fixed x, y measured up from the bottom edge);
///   * LIST OPTS and the mini transport are glued to the bottom-RIGHT corner
///     (x measured back from the right edge).
///
/// MEASURED GROUND TRUTH (canonical 280x186 `pledit.bmp`, decoded pixel-exact):
/// the menu buttons are 22x18 faces whose bottoms sit 12px above the window's
/// bottom edge (window y = H-30), at x = 14 / 43 / 72 / 101 (29px pitch) on the
/// left and x = W-43 on the right (the LIST OPTS face inside the composed
/// right-corner piece as the compositor draws it today). The mini-transport
/// glyphs are ~5px-wide micro icons on rows y = H-14..H-9; each hit rect below
/// covers its glyph with the neighbouring dead space split between adjacent
/// buttons (adjacent, non-overlapping — a fit/overlap test pins this).
///
/// Convention: top-left origin, x rightward / y downward, unscaled skin pixels,
/// half-open bounds — the same as every other hit table in this tier.
public enum PlaylistBarLayout {

    // MARK: - Controls

    /// One clickable element of the playlist bottom bar. `menuButtons` pop up
    /// a menu; `miniTransport` fire a transport/host action directly.
    public enum Control: CaseIterable, Sendable, Equatable {
        // Pop-up menu buttons (left-glued ADD/REM/SEL/MISC; right-glued LIST).
        case addMenu, removeMenu, selectionMenu, miscMenu, listMenu
        // Mini transport row (right-glued, inside the bottom-right corner art).
        case miniPrevious, miniPlay, miniPause, miniStop, miniNext, miniEject

        /// Whether this control pops up a menu (vs firing an action directly).
        public var isMenuButton: Bool {
            switch self {
            case .addMenu, .removeMenu, .selectionMenu, .miscMenu, .listMenu:
                return true
            case .miniPrevious, .miniPlay, .miniPause, .miniStop, .miniNext, .miniEject:
                return false
            }
        }
    }

    // MARK: - Geometry constants (measured)

    /// Menu-button face size (all five buttons).
    private static let menuButtonWidth = 22
    private static let menuButtonHeight = 18
    /// Menu-button top edge, measured UP from the window's bottom edge.
    private static let menuButtonTopFromBottom = 30
    /// Left-glued menu-button x positions (ADD / REM / SEL / MISC, 29px pitch).
    private static let leftMenuButtonX = [14, 43, 72, 101]
    /// LIST OPTS x, measured BACK from the right edge (right-glued).
    private static let listMenuInsetFromRight = 43

    /// Mini-transport rects: top edge from the bottom, shared height, and each
    /// button's (inset-from-right, width). The x boundaries split the dead
    /// space between adjacent glyphs so the rects tile without overlap.
    private static let miniTransportTopFromBottom = 17
    private static let miniTransportHeight = 12
    private static let miniTransport: [(control: Control, insetFromRight: Int, width: Int)] = [
        (.miniPrevious, 147, 10),
        (.miniPlay,     137, 10),
        (.miniPause,    127, 10),
        (.miniStop,     117, 10),
        (.miniNext,     107, 8),
        (.miniEject,    99,  10)
    ]

    // MARK: - Rects (public)

    /// The hit rect for `control` on a composed window of `canvasWidth` x
    /// `canvasHeight` (skin space, top-left origin). Glued to its corner: the
    /// left menu buttons keep a fixed x, everything else follows the right
    /// edge; all rects follow the bottom edge — matching how `composeBar` pins
    /// the corner pieces, so the rects track the baked art across a resize.
    public static func rect(
        for control: Control,
        canvasWidth: Int,
        canvasHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        switch control {
        case .addMenu, .removeMenu, .selectionMenu, .miscMenu:
            let index = [Control.addMenu, .removeMenu, .selectionMenu, .miscMenu]
                .firstIndex(of: control) ?? 0
            return (
                x: leftMenuButtonX[index],
                y: canvasHeight - menuButtonTopFromBottom,
                width: menuButtonWidth,
                height: menuButtonHeight
            )
        case .listMenu:
            return (
                x: canvasWidth - listMenuInsetFromRight,
                y: canvasHeight - menuButtonTopFromBottom,
                width: menuButtonWidth,
                height: menuButtonHeight
            )
        case .miniPrevious, .miniPlay, .miniPause, .miniStop, .miniNext, .miniEject:
            let entry = miniTransport.first { $0.control == control } ?? miniTransport[0]
            return (
                x: canvasWidth - entry.insetFromRight,
                y: canvasHeight - miniTransportTopFromBottom,
                width: entry.width,
                height: miniTransportHeight
            )
        }
    }

    // MARK: - Hit test (public)

    /// The bar control whose hit rect contains the point, or `nil` when none.
    /// Half-open bounds. `Control.allCases` order is the tie-break (menu
    /// buttons win over mini transport): at the classic width (>= 275) no two
    /// rects overlap (a test pins this pairwise); below it the baked corner art
    /// itself collides, so a defined precedence is all that is possible there.
    public static func control(
        atX x: Int,
        y: Int,
        canvasWidth: Int,
        canvasHeight: Int
    ) -> Control? {
        for control in Control.allCases {
            let r = rect(for: control, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            if x >= r.x, x < r.x + r.width, y >= r.y, y < r.y + r.height {
                return control
            }
        }
        return nil
    }
}
