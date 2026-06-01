import XCTest
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

private func sample(port: Int, processName: String = "node") -> PortEntry {
    PortEntry(
        protocolName: .tcp,
        address: "127.0.0.1",
        port: port,
        pid: Int32(port),
        processName: processName,
        user: "alan",
        executablePath: nil,
        commandLine: nil,
        privilegeLevel: .currentUser,
        category: .development
    )
}
