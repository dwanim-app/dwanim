import SwiftUI
import XCTest

@testable import DwanimItUI

// MARK: - AppearanceStoreLoadTests

/// Tests for `AppearanceStore`'s file-loading + hint state: a successful `load`
/// appends + selects the parsed theme and shows the normal hint, a failed `load`
/// leaves the current theme untouched and shows the error hint, a same-named reload
/// de-dupes, and `select` clears a prior error. `@MainActor` because the store is.
@MainActor
final class AppearanceStoreLoadTests: XCTestCase {

    func testSuccessfulLoadAppendsSelectsAndClearsError() {
        let store = AppearanceStore()
        XCTAssertEqual(store.current.name, "Graphite")

        store.load(text: ##"{ "name": "Sunset", "accent": "#e0a341" }"##, filename: "Sunset.dwtheme")

        XCTAssertFalse(store.isError)
        XCTAssertEqual(store.current.name, "Sunset")
        XCTAssertEqual(store.current.accent, Color(hex: 0xe0a341))
        XCTAssertEqual(store.loaded.count, 1)
        // Built-ins first, then the loaded theme.
        XCTAssertEqual(store.themes.map(\.name), ["Graphite", "Amber Deck", "Indigo Glass", "Sunset"])
        XCTAssertEqual(store.hint, "Current: Sunset — A theme is a .dwtheme or .json color file.")
    }

    /// Backward-compat regression: a LEGACY `.dwskin` theme file still loads through the
    /// store exactly like a `.dwtheme` one (the theme extension was renamed but the
    /// owner's existing `.dwskin` files must keep opening). Same JSON content, only the
    /// filename extension differs — and nothing in the load path keys on it.
    func testLegacyDwskinThemeFileStillLoads() {
        let store = AppearanceStore()

        store.load(text: ##"{ "name": "Legacy", "accent": "#e0a341" }"##, filename: "Legacy.dwskin")

        XCTAssertFalse(store.isError, "a legacy .dwskin file must still load")
        XCTAssertEqual(store.current.name, "Legacy")
        XCTAssertEqual(store.current.accent, Color(hex: 0xe0a341))
        XCTAssertEqual(store.loaded.count, 1)
    }

    func testFailedLoadKeepsThemeAndSetsErrorHint() {
        let store = AppearanceStore()
        // Select a non-default first so we can prove the current theme is untouched.
        store.select(.amberDeck)

        store.load(text: "nothing useful here", filename: "broken.json")

        XCTAssertTrue(store.isError)
        XCTAssertEqual(store.current.name, "Amber Deck", "a failed load must not change the theme")
        XCTAssertTrue(store.loaded.isEmpty)
        XCTAssertEqual(store.hint, "\"broken.json\" isn't a readable theme. Needs keys like accent, bg1, panel.")
    }

    func testEmptyTextFailsWithErrorHint() {
        let store = AppearanceStore()
        store.load(text: "", filename: "empty.dwtheme")
        XCTAssertTrue(store.isError)
        XCTAssertEqual(store.current.name, "Graphite")
        XCTAssertEqual(store.hint, "\"empty.dwtheme\" isn't a readable theme. Needs keys like accent, bg1, panel.")
    }

    func testReloadingSameNameReplacesRatherThanDuplicates() {
        let store = AppearanceStore()
        store.load(text: ##"{ "name": "Sunset", "accent": "#e0a341" }"##, filename: "a.dwtheme")
        store.load(text: ##"{ "name": "Sunset", "accent": "#112233" }"##, filename: "b.dwtheme")

        XCTAssertEqual(store.loaded.count, 1, "a same-named reload replaces, not duplicates")
        XCTAssertEqual(store.current.accent, Color(hex: 0x112233), "the reload's colours win")
        XCTAssertEqual(store.themes.filter { $0.name == "Sunset" }.count, 1)
    }

    func testSelectClearsPriorError() {
        let store = AppearanceStore()
        store.load(text: "garbage", filename: "bad.json")
        XCTAssertTrue(store.isError)

        store.select(.indigoGlass)

        XCTAssertFalse(store.isError)
        XCTAssertEqual(store.current.name, "Indigo Glass")
        XCTAssertEqual(store.hint, "Current: Indigo Glass — A theme is a .dwtheme or .json color file.")
    }

    func testLoadingBuiltInNamedThemeStaysReachableAndSelected() {
        let store = AppearanceStore()
        // A loaded theme whose name collides with the built-in "Graphite".
        store.load(text: ##"{ "name": "Graphite", "accent": "#ff0000" }"##, filename: "mine.dwtheme")

        XCTAssertFalse(store.isError)
        XCTAssertEqual(store.loaded.count, 1)
        let loadedName = store.loaded[0].name
        // It is renamed off the built-in's id so it does not shadow it…
        XCTAssertNotEqual(loadedName, "Graphite")
        // …and is the current (selected) theme with its own colours.
        XCTAssertEqual(store.current.name, loadedName)
        XCTAssertEqual(store.current.accent, Color(hex: 0xff0000))
        // Both the built-in Graphite and the loaded theme are reachable + distinct.
        XCTAssertTrue(store.themes.contains { $0.name == "Graphite" })
        XCTAssertTrue(store.themes.contains { $0.name == loadedName })
        XCTAssertEqual(store.themes.first { $0.name == "Graphite" }?.accent,
                       AppearanceTheme.graphite.accent, "the built-in keeps its own colours")
        // The list keeps unique ids (the ForEach requirement the de-dupe protects).
        XCTAssertEqual(store.themes.map(\.name).count, Set(store.themes.map(\.name)).count)
    }

    func testSelectByNameReachesLoadedThemes() {
        let store = AppearanceStore()
        store.load(text: ##"{ "name": "Sunset", "accent": "#e0a341" }"##, filename: "Sunset.dwtheme")
        store.select(.graphite)
        XCTAssertEqual(store.current.name, "Graphite")

        store.select(name: "Sunset")
        XCTAssertEqual(store.current.name, "Sunset", "select(name:) resolves loaded themes too")
    }
}
