import PlayerCore
import SwiftUI

// MARK: - DwanimPlayerScene

/// The full default-skin scene: the colourful `DwanimBackdrop` with the glass
/// `DefaultPlayerView` floating on top. This is the single view the harness
/// hosts in an `NSHostingView`, so the backdrop and the glass live in the same
/// SwiftUI tree and the materials blur the gradient correctly.
///
/// Keeping the composition here (rather than in the AppKit harness) means the
/// harness only needs to know one public entry point, and the
/// backdrop-behind-glass relationship stays defined in `DwanimUI`.
public struct DwanimPlayerScene: View {

    private let core: PlayerCore
    private let model: PlayerViewModel

    public init(core: PlayerCore, model: PlayerViewModel) {
        self.core = core
        self.model = model
    }

    public var body: some View {
        ZStack {
            DwanimBackdrop()
            DefaultPlayerView(core: core, model: model)
        }
    }
}
