import XCTest
import Observation
@testable import PortWatchCore

final class PortStoreTests: XCTestCase {
    func testRefreshKeepsPreviousEntriesWhenScanFails() async {
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [sample(port: 3000)], skippedLineCount: 0, duration: 0.01)),
            .failure(PortScannerError.commandFailed(exitCode: 1, stderr: "failed"))
        ])
        let store = await PortStore(scanner: scanner, favoritesStore: InMemoryFavoritesStore(initialFavorites: []))

        await store.refreshNow()
        let firstEntries = await store.entries
        let firstPorts = firstEntries.map(\.port)
        XCTAssertEqual(firstPorts, [3000])

        await store.refreshNow()
        let retainedEntries = await store.entries
        let retainedPorts = retainedEntries.map(\.port)
        let errorMessage = await store.lastErrorMessage
        XCTAssertEqual(retainedPorts, [3000])
        XCTAssertNotNil(errorMessage)
    }

    /// 重入时 refreshNow 不再静默丢弃：等当前扫描完成后再扫一次，保证 caller 意图被执行。
    /// 旧语义是直接 return false（"skip"），导致 terminate 后端口条目要等下一轮自动刷新才更新。
    func testRefreshReentrancyStillRescans() async {
        let scanner = SlowScanner()
        let store = await PortStore(scanner: scanner, favoritesStore: InMemoryFavoritesStore(initialFavorites: []))

        async let first: Bool = store.refreshNow()
        async let second: Bool = store.refreshNow()
        _ = await (first, second)

        let callCount = await scanner.callCount
        XCTAssertEqual(callCount, 2, "第二个 refreshNow 应等当前扫描完成后再触发一次新扫描")
    }

    func testFilteredEntriesUseFilterSearchAndFavorites() async {
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [sample(port: 3000), sample(port: 5432, processName: "postgres")], skippedLineCount: 0, duration: 0.01))
        ])
        let favorites = InMemoryFavoritesStore(initialFavorites: [5432])
        let store = await PortStore(scanner: scanner, favoritesStore: favorites)

        await store.refreshNow()
        await store.setFilter(.favorites)

        let filteredEntries = await store.filteredEntries
        let filteredPorts = filteredEntries.map(\.port)
        XCTAssertEqual(filteredPorts, [5432])
    }

    @MainActor
    func testToggleFavoriteNotifiesFilteredEntriesObservers() async {
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [sample(port: 3000)], skippedLineCount: 0, duration: 0.01))
        ])
        let store = PortStore(scanner: scanner, favoritesStore: InMemoryFavoritesStore(initialFavorites: []))

        await store.refreshNow()
        store.setFilter(.favorites)

        let changeObserved = expectation(description: "filteredEntries observation should update when favorites change")
        withObservationTracking {
            _ = store.filteredEntries.map(\.port)
        } onChange: {
            changeObserved.fulfill()
        }

        store.toggleFavorite(port: 3000)

        await fulfillment(of: [changeObserved], timeout: 0.2)
        XCTAssertEqual(store.filteredEntries.map(\.port), [3000])
    }

    @MainActor
    func testToggleFavoriteNotifiesSidebarCountObservers() async {
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [sample(port: 3000)], skippedLineCount: 0, duration: 0.01))
        ])
        let store = PortStore(scanner: scanner, favoritesStore: InMemoryFavoritesStore(initialFavorites: []))

        await store.refreshNow()

        let changeObserved = expectation(description: "sidebar count observation should update when favorites change")
        withObservationTracking {
            _ = store.count(for: .favorites)
        } onChange: {
            changeObserved.fulfill()
        }

        store.toggleFavorite(port: 3000)

        await fulfillment(of: [changeObserved], timeout: 0.2)
        XCTAssertEqual(store.count(for: .favorites), 1)
    }

    func testDerivedCountsAndMenuEntriesUpdateAfterRefreshAndFavorites() async {
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [
                sample(port: 3000),
                sample(port: 5432, processName: "postgres", privilegeLevel: .rootOrSystem),
                sample(port: 5173),
                sample(port: 8080),
                sample(port: 9000),
                sample(port: 10000)
            ], skippedLineCount: 0, duration: 0.01))
        ])
        let store = await PortStore(scanner: scanner, favoritesStore: InMemoryFavoritesStore(initialFavorites: [5432]))

        await store.refreshNow()

        let listeningCount = await store.listeningEntryCount
        let privilegedCount = await store.privilegedEntryCount
        let favoritesCount = await store.count(for: .favorites)
        let initialMenuPorts = await store.menuEntries.map(\.port)
        XCTAssertEqual(listeningCount, 6)
        XCTAssertEqual(privilegedCount, 1)
        XCTAssertEqual(favoritesCount, 1)
        XCTAssertEqual(initialMenuPorts, [5432])

        await store.toggleFavorite(port: 3000)

        let updatedFavoritesCount = await store.count(for: .favorites)
        let updatedMenuPorts = await store.menuEntries.map(\.port)
        XCTAssertEqual(updatedFavoritesCount, 2)
        XCTAssertEqual(updatedMenuPorts, [3000, 5432])
    }

    func testMenuEntriesFallBackToFirstFiveEntriesWithoutFavorites() async {
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [
                sample(port: 3000),
                sample(port: 5432),
                sample(port: 5173),
                sample(port: 8080),
                sample(port: 9000),
                sample(port: 10000)
            ], skippedLineCount: 0, duration: 0.01))
        ])
        let store = await PortStore(scanner: scanner, favoritesStore: InMemoryFavoritesStore(initialFavorites: []))

        await store.refreshNow()

        let menuPorts = await store.menuEntries.map(\.port)
        XCTAssertEqual(menuPorts, [3000, 5432, 5173, 8080, 9000])
    }

    @MainActor
    func testRequestedColorSchemePreferenceIsAppliedOnNextMainActorTurn() async {
        let preferenceSaved = expectation(description: "color scheme preference should be saved asynchronously")
        let colorSchemeStore = RecordingColorSchemePreferenceStore(initialPreference: .automatic)
        colorSchemeStore.onSave = { preferenceSaved.fulfill() }
        let store = PortStore(
            scanner: MockScanner(results: []),
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            colorSchemePreferenceStore: colorSchemeStore
        )

        store.requestColorSchemePreference(.dark)

        XCTAssertEqual(store.colorSchemePreference, .automatic)

        await fulfillment(of: [preferenceSaved], timeout: 0.5)

        XCTAssertEqual(store.colorSchemePreference, .dark)
        XCTAssertEqual(colorSchemeStore.savedPreferences, [.dark])
    }

    @MainActor
    func testRequestedColorSchemePreferenceCoalescesMultipleSameTurnRequests() async {
        let preferenceSaved = expectation(description: "last color scheme preference should be saved asynchronously")
        let colorSchemeStore = RecordingColorSchemePreferenceStore(initialPreference: .automatic)
        colorSchemeStore.onSave = { preferenceSaved.fulfill() }
        let store = PortStore(
            scanner: MockScanner(results: []),
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            colorSchemePreferenceStore: colorSchemeStore
        )

        store.requestColorSchemePreference(.light)
        store.requestColorSchemePreference(.dark)

        XCTAssertEqual(store.colorSchemePreference, .automatic)

        await fulfillment(of: [preferenceSaved], timeout: 0.5)

        XCTAssertEqual(store.colorSchemePreference, .dark)
        XCTAssertEqual(colorSchemeStore.savedPreferences, [.dark])
    }

    @MainActor
    func testRequestedColorSchemePreferenceCancelsPendingRequestWhenPreferenceReturnsToCurrentValue() async {
        let preferenceSaved = expectation(description: "color scheme preference should not be saved")
        preferenceSaved.isInverted = true
        let colorSchemeStore = RecordingColorSchemePreferenceStore(initialPreference: .automatic)
        colorSchemeStore.onSave = { preferenceSaved.fulfill() }
        let store = PortStore(
            scanner: MockScanner(results: []),
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            colorSchemePreferenceStore: colorSchemeStore
        )

        store.requestColorSchemePreference(.dark)
        store.requestColorSchemePreference(.automatic)

        await fulfillment(of: [preferenceSaved], timeout: 0.2)

        XCTAssertEqual(store.colorSchemePreference, .automatic)
        XCTAssertEqual(colorSchemeStore.savedPreferences, [])
    }
}

private actor MockScanner: PortScanning {
    private var results: [Result<PortScanResult, Error>]

    init(results: [Result<PortScanResult, Error>]) {
        self.results = results
    }

    func scanListeningPorts() async throws -> PortScanResult {
        try results.removeFirst().get()
    }
}

private actor SlowScanner: PortScanning {
    private(set) var callCount = 0

    func scanListeningPorts() async throws -> PortScanResult {
        callCount += 1
        try await Task.sleep(for: .milliseconds(50))
        return PortScanResult(entries: [sample(port: 3000)], skippedLineCount: 0, duration: 0.05)
    }
}

private final class RecordingColorSchemePreferenceStore: ColorSchemePreferenceStoring {
    private let initialPreference: ColorSchemePreference
    private(set) var savedPreferences: [ColorSchemePreference] = []
    var onSave: (() -> Void)?

    init(initialPreference: ColorSchemePreference) {
        self.initialPreference = initialPreference
    }

    func load() -> ColorSchemePreference {
        initialPreference
    }

    func save(_ preference: ColorSchemePreference) {
        savedPreferences.append(preference)
        onSave?()
    }
}

private func sample(
    port: Int,
    processName: String = "node",
    privilegeLevel: PrivilegeLevel = .currentUser,
    category: PortCategory = .development
) -> PortEntry {
    PortEntry(
        protocolName: .tcp,
        address: "127.0.0.1",
        port: port,
        pid: Int32(port),
        processName: processName,
        user: "alan",
        executablePath: nil,
        commandLine: nil,
        privilegeLevel: privilegeLevel,
        category: category
    )
}
