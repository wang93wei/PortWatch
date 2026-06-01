import Foundation
import Observation

@MainActor
@Observable
public final class PortStore {
    public private(set) var entries: [PortEntry] = []
    public private(set) var isRefreshing = false
    public private(set) var lastErrorMessage: String?
    public private(set) var lastRefreshDate: Date?
    public var selectedFilter: PortFilter = .listening
    public var searchText = ""
    public var refreshInterval: RefreshInterval

    private let scanner: PortScanning
    private let favoritesStore: FavoritesStoring
    private let refreshIntervalStore: RefreshIntervalStoring
    private var refreshTask: Task<Void, Never>?

    public init(
        scanner: PortScanning = PortScannerService(),
        favoritesStore: FavoritesStoring = UserDefaultsFavoritesStore(),
        refreshIntervalStore: RefreshIntervalStoring = UserDefaultsRefreshIntervalStore()
    ) {
        self.scanner = scanner
        self.favoritesStore = favoritesStore
        self.refreshIntervalStore = refreshIntervalStore
        self.refreshInterval = refreshIntervalStore.load()
    }

    public var favoritePorts: Set<Int> {
        favoritesStore.favoritePorts
    }

    public var filteredEntries: [PortEntry] {
        selectedFilter.apply(to: entries, favoritePorts: favoritePorts, searchText: searchText)
    }

    public func setFilter(_ filter: PortFilter) {
        selectedFilter = filter
    }

    public func toggleFavorite(port: Int) {
        favoritesStore.toggle(port: port)
    }

    public func setRefreshInterval(_ interval: RefreshInterval) {
        refreshInterval = interval
        refreshIntervalStore.save(interval)
        startAutoRefresh()
    }

    public func startAutoRefresh() {
        refreshTask?.cancel()
        guard let seconds = refreshInterval.seconds else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.refreshNow()
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    @discardableResult
    public func refreshNow() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await scanner.scanListeningPorts()
            entries = result.entries
            lastErrorMessage = nil
            lastRefreshDate = Date()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }
}
