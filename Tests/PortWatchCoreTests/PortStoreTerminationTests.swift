import XCTest
@testable import PortWatchCore

final class PortStoreTerminationTests: XCTestCase {
    func testForceTerminationRequiresGracefulAttemptThatLeavesProcessAlive() async {
        let entry = sample(port: 3000)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01)),
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01)),
            .success(PortScanResult(entries: [], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator()
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .force)
        let directForceRequests = await terminator.requests
        XCTAssertTrue(directForceRequests.isEmpty)

        await store.requestForceTermination(for: entry)
        let blockedForceCandidate = await store.forceTerminationCandidate
        let blockedForceEntry = await store.pendingForceTerminationEntry
        XCTAssertNil(blockedForceCandidate)
        XCTAssertNil(blockedForceEntry)

        await store.terminate(entry: entry, mode: .graceful)
        await store.requestForceTermination(for: entry)

        let forceCandidate = await store.forceTerminationCandidate
        let pendingForceEntry = await store.pendingForceTerminationEntry
        XCTAssertEqual(forceCandidate, PortStore.ForceTerminationCandidate(entry: entry))
        XCTAssertEqual(pendingForceEntry?.id, entry.id)

        await store.terminate(entry: entry, mode: .force)
        let confirmedRequests = await terminator.requests
        XCTAssertEqual(confirmedRequests.map(\.1), [.graceful, .force])
    }

    func testHelperUnavailableDoesNotOpenForceTermination() async {
        let entry = sample(port: 80)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator(result: ProcessTerminationResult(status: .helperUnavailable("missing"), message: "helper missing"))
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)

        let forceCandidate = await store.forceTerminationCandidate
        let pendingForceEntry = await store.pendingForceTerminationEntry
        XCTAssertNil(forceCandidate)
        XCTAssertNil(pendingForceEntry)
    }

    func testRefreshFailureAfterGracefulDoesNotOpenForceTermination() async {
        let entry = sample(port: 3000)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01)),
            .failure(PortScannerError.commandFailed(exitCode: 1, stderr: "failed"))
        ])
        let terminator = MockTerminator()
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        let initialRefreshSucceeded = await store.refreshNow()
        XCTAssertTrue(initialRefreshSucceeded)

        await store.terminate(entry: entry, mode: .graceful)

        let forceCandidate = await store.forceTerminationCandidate
        let retainedEntries = await store.entries
        XCTAssertNil(forceCandidate)
        XCTAssertEqual(retainedEntries.map(\.id), [entry.id])
    }

    func testSamePIDDifferentEntryDoesNotOpenForceTermination() async {
        let entry = sample(port: 3000)
        let samePIDDifferentEntry = PortEntry(
            protocolName: .tcp,
            address: "127.0.0.1",
            port: 5173,
            pid: entry.pid,
            processName: entry.processName,
            user: entry.user,
            executablePath: entry.executablePath,
            commandLine: entry.commandLine,
            privilegeLevel: entry.privilegeLevel,
            category: entry.category
        )
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [samePIDDifferentEntry], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator()
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)
        await store.requestForceTermination(for: entry)

        let forceCandidate = await store.forceTerminationCandidate
        let pendingForceEntry = await store.pendingForceTerminationEntry
        XCTAssertNil(forceCandidate)
        XCTAssertNil(pendingForceEntry)
    }

    func testSameIDDifferentIdentityClearsForceTermination() async {
        let entry = sample(port: 3000)
        let sameIDDifferentIdentity = PortEntry(
            protocolName: entry.protocolName,
            address: entry.address,
            port: entry.port,
            pid: entry.pid,
            processName: "python",
            user: entry.user,
            executablePath: "/usr/bin/python3",
            commandLine: "python3 -m http.server 3000",
            privilegeLevel: entry.privilegeLevel,
            category: entry.category
        )
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [sameIDDifferentIdentity], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator()
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)
        await store.requestForceTermination(for: entry)

        let forceCandidate = await store.forceTerminationCandidate
        let pendingForceEntry = await store.pendingForceTerminationEntry
        XCTAssertNil(forceCandidate)
        XCTAssertNil(pendingForceEntry)
    }

    func testSuccessfulRefreshClearsStaleForceState() async {
        let entry = sample(port: 3000)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01)),
            .success(PortScanResult(entries: [], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator()
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)
        await store.requestForceTermination(for: entry)
        let beforeRefreshPendingEntry = await store.pendingForceTerminationEntry
        XCTAssertEqual(beforeRefreshPendingEntry?.id, entry.id)

        let refreshSucceeded = await store.refreshNow()

        let afterRefreshCandidate = await store.forceTerminationCandidate
        let afterRefreshPendingEntry = await store.pendingForceTerminationEntry
        XCTAssertTrue(refreshSucceeded)
        XCTAssertNil(afterRefreshCandidate)
        XCTAssertNil(afterRefreshPendingEntry)
    }

    func testTerminationErrorMessageIsSanitizedForUI() async {
        let entry = sample(port: 3000)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator(error: ProcessTerminationError.signalFailed("node server.js --token=secret"))
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)

        let message = await store.lastTerminationMessage
        XCTAssertEqual(message, "结束进程失败，请刷新后重试。")
        XCTAssertFalse(message?.contains("node server.js") ?? false)
        XCTAssertFalse(message?.contains("secret") ?? false)
    }

    func testHelperUnavailableResultMessageIsSanitizedForUI() async {
        let entry = sample(port: 3000)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator(result: ProcessTerminationResult(
            status: .helperUnavailable("node server.js --token=secret"),
            message: "node server.js --token=secret"
        ))
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)

        let message = await store.lastTerminationMessage
        XCTAssertEqual(message, "需要安装并批准 PortWatch Helper 后才能结束其他用户或系统进程。")
        XCTAssertFalse(message?.contains("node server.js") ?? false)
        XCTAssertFalse(message?.contains("secret") ?? false)
    }

    func testUnexpectedLocalizedErrorMessageIsSanitizedForUI() async {
        let entry = sample(port: 3000)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator(error: SecretLocalizedError())
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)

        let message = await store.lastTerminationMessage
        XCTAssertEqual(message, "结束进程失败，请刷新后重试。")
        XCTAssertFalse(message?.contains("node server.js") ?? false)
        XCTAssertFalse(message?.contains("secret") ?? false)
    }

    func testAuthenticationCancelledClearsPendingForceStateAndShowsMessage() async {
        let entry = sample(port: 3000)
        let scanner = MockScanner(results: [
            .success(PortScanResult(entries: [entry], skippedLineCount: 0, duration: 0.01))
        ])
        let terminator = MockTerminator(results: [
            .success(ProcessTerminationResult(status: .signalSent, message: "TERM sent")),
            .failure(ProcessTerminationError.authenticationCancelled)
        ])
        let store = await PortStore(
            scanner: scanner,
            favoritesStore: InMemoryFavoritesStore(initialFavorites: []),
            refreshIntervalStore: InMemoryRefreshIntervalStore(interval: .paused),
            terminator: terminator
        )

        await store.terminate(entry: entry, mode: .graceful)
        await store.requestForceTermination(for: entry)
        let pendingBeforeCancellation = await store.pendingForceTerminationEntry
        XCTAssertEqual(pendingBeforeCancellation?.id, entry.id)

        await store.terminate(entry: entry, mode: .force)

        let message = await store.lastTerminationMessage
        let forceCandidate = await store.forceTerminationCandidate
        let pendingForceEntry = await store.pendingForceTerminationEntry
        XCTAssertEqual(message, "已取消认证，未结束进程。")
        XCTAssertNil(forceCandidate)
        XCTAssertNil(pendingForceEntry)
    }
}

private struct SecretLocalizedError: LocalizedError {
    var errorDescription: String? {
        "node server.js --token=secret"
    }
}

private actor MockTerminator: ProcessTerminating {
    private(set) var requests: [(PortEntry, TerminationMode)] = []
    private var results: [Result<ProcessTerminationResult, Error>]

    init(
        result: ProcessTerminationResult = ProcessTerminationResult(status: .signalSent, message: "TERM sent"),
        error: Error? = nil
    ) {
        if let error {
            self.results = [.failure(error)]
        } else {
            self.results = [.success(result)]
        }
    }

    init(results: [Result<ProcessTerminationResult, Error>]) {
        self.results = results
    }

    func terminate(entry: PortEntry, mode: TerminationMode) async throws -> ProcessTerminationResult {
        requests.append((entry, mode))
        if results.count > 1 {
            return try results.removeFirst().get()
        }
        return try results[0].get()
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

private func sample(port: Int) -> PortEntry {
    PortEntry(
        protocolName: .tcp,
        address: "127.0.0.1",
        port: port,
        pid: Int32(port),
        processName: "node",
        user: NSUserName(),
        executablePath: "/opt/homebrew/bin/node",
        commandLine: "node server.js",
        privilegeLevel: .currentUser,
        category: .development
    )
}

private final class InMemoryRefreshIntervalStore: RefreshIntervalStoring {
    private let interval: RefreshInterval

    init(interval: RefreshInterval) {
        self.interval = interval
    }

    func load() -> RefreshInterval { interval }
    func save(_ interval: RefreshInterval) {}
}
