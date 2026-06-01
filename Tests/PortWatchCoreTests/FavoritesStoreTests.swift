import XCTest
@testable import PortWatchCore

final class FavoritesStoreTests: XCTestCase {
    func testToggleFavoriteAddsAndRemovesPort() {
        let store = InMemoryFavoritesStore(initialFavorites: [])

        store.toggle(port: 3000)
        XCTAssertTrue(store.isFavorite(port: 3000))

        store.toggle(port: 3000)
        XCTAssertFalse(store.isFavorite(port: 3000))
    }
}
