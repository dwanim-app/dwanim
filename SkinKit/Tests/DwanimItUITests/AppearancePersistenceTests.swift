import SwiftUI
import XCTest

@testable import DwanimItUI

// MARK: - AppearancePersistenceTests
//
// F16: `AppearanceStore` must be able to (1) EMIT its current selection as a
// persisted value whenever the selection changes (so the App tier can write it to
// UserDefaults) and (2) RESTORE from such a value at init (so a relaunch reproduces
// the chosen theme). The value type is `AppearancePersistedState`
// { name, sourceText?, filename? }: a nil `sourceText` is a built-in selected by
// name; a non-nil `sourceText` is a loaded theme to re-parse via the same
// `load(text:filename:)` path (so collision-suffixing etc. reproduce).
//
// Robustness contract exercised here: restoring a built-in name that no longer
// exists, or a `sourceText` that fails to parse, falls back to the Graphite default
// WITHOUT crashing and WITHOUT emitting a broken persisted state; and the restore
// path itself must NOT re-fire `onPersist` (else every launch churns the store).
//
// `@MainActor` because `AppearanceStore` is.
@MainActor
final class AppearancePersistenceTests: XCTestCase {

    // MARK: Emit

    func testSelectingBuiltInEmitsBuiltInState() {
        var emitted: [AppearancePersistedState] = []
        let store = AppearanceStore(restoring: nil, onPersist: { emitted.append($0) })

        store.select(.amberDeck)

        XCTAssertEqual(emitted, [AppearancePersistedState(name: "Amber Deck", sourceText: nil, filename: nil)])
    }

    func testSelectingBuiltInByNameEmitsBuiltInState() {
        var emitted: [AppearancePersistedState] = []
        let store = AppearanceStore(restoring: nil, onPersist: { emitted.append($0) })

        store.select(name: "Indigo Glass")

        XCTAssertEqual(emitted, [AppearancePersistedState(name: "Indigo Glass", sourceText: nil, filename: nil)])
    }

    func testLoadingThemeEmitsLoadedStateWithSourceAndFilename() {
        var emitted: [AppearancePersistedState] = []
        let store = AppearanceStore(restoring: nil, onPersist: { emitted.append($0) })

        let source = ##"{ "name": "Sunset", "accent": "#e0a341" }"##
        store.load(text: source, filename: "Sunset.dwtheme")

        XCTAssertEqual(emitted, [AppearancePersistedState(name: "Sunset", sourceText: source, filename: "Sunset.dwtheme")])
    }

    func testSelectingAPreviouslyLoadedThemeEmitsLoadedState() {
        var emitted: [AppearancePersistedState] = []
        let store = AppearanceStore(restoring: nil, onPersist: { emitted.append($0) })

        let source = ##"{ "name": "Sunset", "accent": "#e0a341" }"##
        store.load(text: source, filename: "Sunset.dwtheme")
        store.select(.graphite)      // built-in
        emitted.removeAll()

        // Switching BACK to the loaded theme via the popover must re-emit the LOADED
        // state (with its source text) — not a built-in name that would fall back to
        // Graphite on the next launch.
        store.select(store.loaded[0])

        XCTAssertEqual(emitted, [AppearancePersistedState(name: "Sunset", sourceText: source, filename: "Sunset.dwtheme")])
    }

    func testFailedLoadDoesNotEmit() {
        var emitted: [AppearancePersistedState] = []
        let store = AppearanceStore(restoring: nil, onPersist: { emitted.append($0) })

        store.load(text: "nothing useful here", filename: "broken.json")

        XCTAssertTrue(store.isError)
        XCTAssertTrue(emitted.isEmpty, "a failed load must not persist a broken state")
    }

    // MARK: Restore

    func testRestoringBuiltInAppliesThatBuiltIn() {
        let store = AppearanceStore(restoring: AppearancePersistedState(name: "Amber Deck", sourceText: nil, filename: nil))
        XCTAssertEqual(store.current.name, "Amber Deck")
        XCTAssertEqual(store.current.accent, AppearanceTheme.amberDeck.accent)
    }

    // Backward-compat (F16): the persisted `filename` here is a LEGACY `.dwskin` — a
    // theme first loaded before the `.dwskin` → `.dwtheme` rename. Launch-restore
    // re-parses the persisted `sourceText` (never re-opens the file) and the `filename`
    // is only a display-name source, so a `.dwskin`-sourced selection still restores
    // exactly like a `.dwtheme` one.
    func testRestoringLoadedStateReparsesAndAppearsInLoaded() {
        let source = ##"{ "name": "Sunset", "accent": "#e0a341" }"##
        let store = AppearanceStore(restoring: AppearancePersistedState(name: "Sunset", sourceText: source, filename: "Sunset.dwskin"))

        XCTAssertFalse(store.isError)
        XCTAssertEqual(store.current.name, "Sunset", "the re-parsed loaded theme is current")
        XCTAssertEqual(store.current.accent, Color(hex: 0xe0a341))
        XCTAssertEqual(store.loaded.map(\.name), ["Sunset"], "and it re-appears in the loaded list")
        XCTAssertEqual(store.themes.map(\.name), ["Graphite", "Amber Deck", "Indigo Glass", "Sunset"])
    }

    func testRestoringBogusBuiltInNameFallsBackToGraphite() {
        let store = AppearanceStore(restoring: AppearancePersistedState(name: "No Such Theme", sourceText: nil, filename: nil))
        XCTAssertEqual(store.current.name, "Graphite", "an unknown built-in name falls back to Graphite")
        XCTAssertFalse(store.isError)
    }

    func testRestoringUnparseableSourceTextFallsBackGracefully() {
        let store = AppearanceStore(restoring: AppearancePersistedState(name: "Broken", sourceText: "not a theme at all", filename: "broken.dwskin"))
        XCTAssertEqual(store.current.name, "Graphite", "an unparseable source falls back to Graphite")
        XCTAssertFalse(store.isError, "and does not surface an error hint at launch")
        XCTAssertTrue(store.loaded.isEmpty)
    }

    func testRestoreDoesNotItselfFireOnPersist() {
        var emitted: [AppearancePersistedState] = []
        // A built-in restore…
        _ = AppearanceStore(
            restoring: AppearancePersistedState(name: "Amber Deck", sourceText: nil, filename: nil),
            onPersist: { emitted.append($0) }
        )
        XCTAssertTrue(emitted.isEmpty, "restoring a built-in must not re-persist")

        // …and a loaded restore.
        let source = ##"{ "name": "Sunset", "accent": "#e0a341" }"##
        _ = AppearanceStore(
            restoring: AppearancePersistedState(name: "Sunset", sourceText: source, filename: "Sunset.dwskin"),
            onPersist: { emitted.append($0) }
        )
        XCTAssertTrue(emitted.isEmpty, "restoring a loaded theme must not re-persist")
    }

    func testRestoredLoadedThemeStillEmitsWhenLaterReselected() {
        var emitted: [AppearancePersistedState] = []
        let source = ##"{ "name": "Sunset", "accent": "#e0a341" }"##
        let store = AppearanceStore(
            restoring: AppearancePersistedState(name: "Sunset", sourceText: source, filename: "Sunset.dwskin"),
            onPersist: { emitted.append($0) }
        )
        // The restore did not persist, but a subsequent user switch does — and the
        // restored loaded theme keeps its source so re-selecting it persists the
        // LOADED state (proving the restore path repopulated the source seam).
        store.select(.graphite)
        emitted.removeAll()
        store.select(store.loaded[0])

        XCTAssertEqual(emitted, [AppearancePersistedState(name: "Sunset", sourceText: source, filename: "Sunset.dwskin")])
    }
}
