import AppKit
import CoreGraphics
import Foundation
import PlayerCore
import SkinKit
import SkinRender

// The EQ window controller (one primary type per file, §12): it owns the skin,
// the core, and the view; recomposes the EQ face from the live equalizer state;
// and routes mouse-down / drag / up to the right slider (or the ON button).
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier (no
// logic change) so BOTH the dev harness AND the real app target can host it. The
// CLI mode entry (arg parsing + the window-build + process-lifetime hold) stays
// in the harness, which now CONSTRUCTS this controller via `showEQWindow`.
//
// It sits on `SkinAppKit.SkinWindowController` (the shared NSWindowDelegate +
// NSApplicationDelegate teardown pair) and draws into the shared
// `SkinAppKit.ScaledImageView`. The EQ window is static (no animation timer), so
// it inherits the base's default no-op `tearDown()`.

// MARK: - Controller

/// Owns the live EQ window: the skin, the core, the view. It recomposes the EQ
/// face from the current `PlayerCore.equalizer` values and swaps the view's image
/// whenever a gesture changes the state, and routes mouse-down / drag to the
/// right slider (or the ON button).
///
/// The drag math is the payoff: a view-space point becomes a skin-space point via
/// the SAME verified flip as the main window (`ControlHitTest.skinPoint`); the
/// skin x AND y pick the slider column, y-gated to the thumb-travel band
/// (`EQWindowLayout.slider(atSkinX:skinY:)`) so a press in the graph/label area
/// does not grab a slider; the skin y,
/// adjusted to the thumb's TOP-LEFT the same way the draw places it (cursor under
/// the thumb's vertical centre), is inverted to a gain
/// (`EQWindowLayout.thumbGain(forThumbTopY:)`); and that gain is pushed to
/// `PlayerCore`, which drives the real `AVAudioUnitEQ`.
public final class EQController: SkinWindowController {
    private let skin: Skin
    private let core: PlayerCore
    private let view: ScaledImageView
    private let scale: Int

    /// The slider currently being dragged (set on a mouse-down that grabbed a
    /// slider), so a subsequent drag keeps adjusting THAT slider even if the
    /// cursor wanders horizontally off its column. `nil` when the gesture started
    /// on the ON button or empty face, and cleared on mouse-up.
    private var draggingSlider: EQWindowLayout.EQSlider?

    public init(
        skin: Skin,
        core: PlayerCore,
        view: ScaledImageView,
        scale: Int,
        terminatesAppOnClose: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.skin = skin
        self.core = core
        self.view = view
        self.scale = scale
        super.init(terminatesAppOnClose: terminatesAppOnClose, onClose: onClose)

        // Mouse-down is a fresh gesture (isDown: true); a drag continues it
        // (isDown: false). The shared view's clickCount is ignored here (the EQ
        // window does not distinguish single vs double click).
        view.onMouseDown = { [weak self] viewX, viewY, viewHeight, _ in
            self?.handleMouse(viewX: viewX, viewY: viewY, viewHeight: viewHeight, isDown: true)
        }
        view.onMouseDragged = { [weak self] viewX, viewY, viewHeight in
            self?.handleMouse(viewX: viewX, viewY: viewY, viewHeight: viewHeight, isDown: false)
        }
        view.onMouseUp = { [weak self] in
            self?.endDrag()
        }
    }

    /// Draw the first frame from the current state. (The EQ face only changes in
    /// response to a gesture, so there is no animation timer — unlike the main
    /// window's spectrum.)
    public func start() {
        redraw()
    }

    // MARK: Mouse -> DSP

    /// Map a view-space point to skin space (the SAME verified flip used by the
    /// main window) and act on it: a mouse-down on the ON button toggles enable; a
    /// mouse-down on a slider column begins a drag; a drag (or down) on a slider
    /// sets that slider's gain from the cursor y and pushes it to the engine.
    private func handleMouse(viewX: Double, viewY: Double, viewHeight: Double, isDown: Bool) {
        let point = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        )

        if isDown {
            // A fresh gesture: first check the ON button, then a slider column.
            if hitsOnButton(skinX: point.x, skinY: point.y) {
                core.setEQEnabled(!core.equalizer.enabled)
                draggingSlider = nil
                redraw()
                return
            }
            // Y-gated: a down in the response-curve graph area (above the track) or
            // the label area (below it) does NOT grab a slider, even though its x
            // overlaps the band columns — only a press inside the thumb-travel band
            // begins a drag.
            draggingSlider = EQWindowLayout.slider(atSkinX: point.x, skinY: point.y)
        }

        // For a down or a drag, adjust the slider grabbed at mouse-down (if any).
        guard let slider = draggingSlider else { return }
        applyGain(to: slider, fromSkinY: point.y)
        redraw()
    }

    /// End the current drag gesture: clear the latched slider so a later stray
    /// drag (without a fresh mouse-down) cannot keep adjusting it. Explicit gesture
    /// lifecycle — the next gesture re-grabs on its own mouse-down.
    private func endDrag() {
        draggingSlider = nil
    }

    /// Whether a skin-space point lands on the ON button's footprint (its layout
    /// origin + the ON sprite size; falls back to the canonical 25x12 if the
    /// sprite is absent so the toggle still works on a sparse skin).
    private func hitsOnButton(skinX: Int, skinY: Int) -> Bool {
        let origin = EQWindowLayout.onButtonOrigin
        let size = SpriteCoordinates.equalizerWindow["eqmain.bmp"]?
            .first { $0.name == "onButtonOff" }
        let width = size?.width ?? 25
        let height = size?.height ?? 12
        return skinX >= origin.x && skinX < origin.x + width
            && skinY >= origin.y && skinY < origin.y + height
    }

    /// Convert a cursor skin-space y to a gain and push it to the engine for the
    /// given slider. The cursor sits at the thumb's VERTICAL CENTRE (matching how
    /// `thumbTopY` places the body), so the thumb top-left y is `skinY -
    /// thumbHeight/2`; `thumbGain(forThumbTopY:)` clamps that into ±12 dB. The
    /// resulting gain drives the real `AVAudioUnitEQ` through `PlayerCore`.
    private func applyGain(to slider: EQWindowLayout.EQSlider, fromSkinY skinY: Int) {
        let thumbTopY = skinY - EQWindowLayout.thumbHeight / 2
        let gain = EQWindowLayout.thumbGain(forThumbTopY: thumbTopY)
        switch slider {
        case .preamp:
            core.setEQPreamp(gain)
        case .band(let index):
            core.setEQBand(index, dB: gain)
        }
    }

    // MARK: Redraw

    /// Recompose the EQ face from the live `PlayerCore.equalizer` state and swap
    /// the view image. Pure compose (no text overlay — the preset display is
    /// deferred), bridged to a CGImage and nearest-neighbor scaled.
    private func redraw() {
        let eq = core.equalizer
        guard let composed = EQWindowComposer.compose(
            skin,
            enabled: eq.enabled,
            preamp: eq.preamp,
            bands: eq.bands
        ) else {
            return
        }
        guard let image = CGImageConversion.makeImage(from: composed) else { return }
        let scaled: (image: CGImage, width: Int, height: Int)
        do {
            scaled = try scaledImage(image, scale: scale)
        } catch {
            return
        }
        view.update(image: scaled.image)
    }
}
