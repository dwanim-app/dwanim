import DwanimItUI
import Foundation

// MARK: - AppearancePersistenceStore
//
// The app-layer persistence sink for `DwanimItUI`'s pure `AppearancePersistedState`
// value (F16) — the chosen built-in / loaded colour THEME, remembered across
// launches (like `.lastAudio` / `.lastSkin`, unlike the previously scene-private
// `AppearanceStore`). `AppearancePersistedState` only *holds* the selection (a name,
// plus a loaded theme's raw source text + filename) and stays SwiftUI/Foundation
// Codable; this type is the I/O the pure UI layer deliberately does not own — it
// JSON-encodes the value into the app's sandbox container via `UserDefaults` and
// decodes it back at launch.
//
// Mirrors `BookmarkStore`: one JSON `Data` blob under a single stable, versioned
// key in `UserDefaults.standard` (the sandbox container's plist). `load()` never
// throws — a missing key (first launch) or corrupt / stale bytes both yield `nil`,
// so the app always boots into the Graphite default and simply re-records on the
// next theme change.
final class AppearancePersistenceStore {

    /// The stable UserDefaults key the encoded `AppearancePersistedState` JSON lives
    /// under. Versioned so a future schema change can bump it without colliding.
    private static let defaultsKey = "appearance.persisted.v1"

    private let defaults: UserDefaults

    /// - Parameter defaults: the backing store; defaults to `.standard` (the sandbox
    ///   container's plist). Injectable for symmetry with `BookmarkStore`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Load

    /// Decode the persisted appearance selection. Returns `nil` when the key is
    /// absent (first launch) or the stored bytes fail to decode (corrupt / stale
    /// schema) — never throws, so launch is always recoverable (the store falls back
    /// to the Graphite default).
    func load() -> AppearancePersistedState? {
        guard let data = defaults.data(forKey: AppearancePersistenceStore.defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppearancePersistedState.self, from: data)
    }

    // MARK: Save

    /// JSON-encode and persist `state`. A failure to encode (not expected for this
    /// all-`Codable` value) is swallowed: the prior persisted state is left intact.
    func save(_ state: AppearancePersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: AppearancePersistenceStore.defaultsKey)
    }
}
