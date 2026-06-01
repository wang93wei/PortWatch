import Foundation

public protocol FavoritesStoring: AnyObject {
    var favoritePorts: Set<Int> { get }
    func isFavorite(port: Int) -> Bool
    func toggle(port: Int)
}

public final class InMemoryFavoritesStore: FavoritesStoring {
    public private(set) var favoritePorts: Set<Int>

    public init(initialFavorites: Set<Int>) {
        self.favoritePorts = initialFavorites
    }

    public func isFavorite(port: Int) -> Bool {
        favoritePorts.contains(port)
    }

    public func toggle(port: Int) {
        if favoritePorts.contains(port) {
            favoritePorts.remove(port)
        } else {
            favoritePorts.insert(port)
        }
    }
}

public final class UserDefaultsFavoritesStore: FavoritesStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "favoritePorts") {
        self.defaults = defaults
        self.key = key
    }

    public var favoritePorts: Set<Int> {
        Set(defaults.array(forKey: key) as? [Int] ?? [])
    }

    public func isFavorite(port: Int) -> Bool {
        favoritePorts.contains(port)
    }

    public func toggle(port: Int) {
        var ports = favoritePorts
        if ports.contains(port) {
            ports.remove(port)
        } else {
            ports.insert(port)
        }
        defaults.set(Array(ports).sorted(), forKey: key)
    }
}
