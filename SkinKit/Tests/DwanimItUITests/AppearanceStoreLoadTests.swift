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

        store.load(text: ##"{ "name": "Sunset", "accent": "#e0a341" }"##, filename: "Sunset.dwskin")

        XCTAssertFalse(store.isError)
        XCTAssertEqual(store.current.name, "Sunset")
        XCTAssertEqual(store.current.accent, Color(hex: 0xe0a341))
        XCTAssertEqual(store.loaded.count, 1)
        // Built-ins first, then the loaded theme.
        XCTAssertEqual(store.themes.map(\.name), ["Graphite", "Amber Deck", "Indigo Glass", "Sunset"])
        XCTAssertEqual(store.hint, "Current: Sunset — A skin is a .dwskin or .json file of colors.")
    }

    func testFailedLoadKeepsThemeAndSetsErrorHint() {
        let store = AppearanceStore()
        // Select a non-default first so we can prove the current theme is untouched.
        store.select(.amberDeck)

        store.load(text: "nothing useful here", filename: "broken.json")

        XCTAssertTrue(store.isError)
        XCTAssertEqual(store.current.name, "Amber Deck", "a failed load must not change the theme")
        XCTAssertTrue(store.loaded.isEmpty)
        XCTAssertEqual(store.hint, "\"broken.json\" isn't a readable skin. Needs keys like accent, bg1, panel.")
    }

    func testEmptyTextFailsWithErrorHint() {
        let store = AppearanceStore()
        store.load(text: "", filename: "empty.dwskin")
        XCTAssertTrue(store.isError)
        XCTAssertEqual(store.current.name, "Graphite")
        XCTAssertEqual(store.hint, "\"empty.dwskin\" isn't a readable skin. Needs keys like accent, bg1, panel.")
    }

    func testReloadingSameNameReplacesRatherThanDuplicates() {
        let store = AppearanceStore()
        store.load(text: ##"{ "name": "Sunset", "accent": "#e0a341" }"##, filename: "a.dwskin")
        store.load(text: ##"{ "name": "Sunset", "accent": "#112233" }"##, filename: "b.dwskin")

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
        XCTAssertEqual(store.hint, "Current: Indigo Glass — A skin is a .dwskin or .json file of colors.")
    }

    func testSelectByNameReachesLoadedThemes() {
        let store = AppearanceStore()
        store.load(text: ##"{ "name": "Sunset", "accent": "#e0a341" }"##, filename: "Sunset.dwskin")
        store.select(.graphite)
        XCTAssertEqual(store.current.name, "Graphite")

        store.select(name: "Sunset")
        XCTAssertEqual(store.current.name, "Sunset", "select(name:) resolves loaded themes too")
    }
}
