import XCTest
@testable import PortWatchCore

final class RefreshIntervalTests: XCTestCase {
    func testCustomIntervalIsClampedAndDistinctFromPreset() {
        XCTAssertEqual(RefreshInterval.validatedCustom(seconds: 0).seconds, 1)
        XCTAssertEqual(RefreshInterval.validatedCustom(seconds: 99).seconds, 60)
        XCTAssertNotEqual(RefreshInterval.validatedCustom(seconds: 3), .preset(seconds: 3))
    }

    func testStorePersistsModeAndCustomSeconds() {
        let defaults = UserDefaults(suiteName: "RefreshIntervalTests")!
        defaults.removePersistentDomain(forName: "RefreshIntervalTests")
        let store = UserDefaultsRefreshIntervalStore(defaults: defaults)

        store.save(.custom(seconds: 12))

        XCTAssertEqual(store.load(), .custom(seconds: 12))
    }
}
