import XCTest
@testable import PortWatchCore

final class ColorSchemePreferenceTests: XCTestCase {
    func testSwiftUISchemeMapsAutomaticToNil() {
        XCTAssertNil(ColorSchemePreference.automatic.swiftUIScheme)
        XCTAssertEqual(ColorSchemePreference.light.swiftUIScheme, .light)
        XCTAssertEqual(ColorSchemePreference.dark.swiftUIScheme, .dark)
    }

    func testStorePersistsAndLoadsPreference() {
        let defaults = UserDefaults(suiteName: "ColorSchemePreferenceTests")!
        defaults.removePersistentDomain(forName: "ColorSchemePreferenceTests")
        let store = UserDefaultsColorSchemePreferenceStore(defaults: defaults)

        store.save(.dark)

        XCTAssertEqual(store.load(), .dark)
    }

    func testStoreLoadsAutomaticAsDefault() {
        let defaults = UserDefaults(suiteName: "ColorSchemePreferenceTestsEmpty")!
        defaults.removePersistentDomain(forName: "ColorSchemePreferenceTestsEmpty")
        let store = UserDefaultsColorSchemePreferenceStore(defaults: defaults)

        XCTAssertEqual(store.load(), .automatic)
    }
}
