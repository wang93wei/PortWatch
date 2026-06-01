import Foundation
import Observation

@MainActor
@Observable
public final class PortStore {
    public private(set) var entries: [PortEntry] = []
    public private(set) var isRefreshing = false
    public private(set) var lastErrorMessage: String?
    public private(set) var lastRefreshDate: Date?
    public private(set) var lastTerminationMessage: String?
    public private(set) var pendingForceTerminationEntry: PortEntry?
    public private(set) var forceTerminationCandidate: ForceTerminationCandidate?
    public var selectedFilter: PortFilter = .listening
    public var searchText = ""
    public var refreshInterval: RefreshInterval
    public private(set) var colorSchemePreference: ColorSchemePreference

    private let scanner: PortScanning
    private let favoritesStore: FavoritesStoring
    private let refreshIntervalStore: RefreshIntervalStoring
    private let colorSchemePreferenceStore: ColorSchemePreferenceStoring
    private let terminator: ProcessTerminating
    private var refreshTask: Task<Void, Never>?

    public struct ForceTerminationCandidate: Equatable, Sendable {
        public let id: String
        public let pid: Int32
        public let processName: String
        public let user: String
        public let executablePath: String?
        public let commandLine: String?
        public let privilegeLevel: PrivilegeLevel

        public init(entry: PortEntry) {
            self.id = entry.id
            self.pid = entry.pid
            self.processName = entry.processName
            self.user = entry.user
            self.executablePath = entry.executablePath
            self.commandLine = entry.commandLine
            self.privilegeLevel = entry.privilegeLevel
        }

        public func matches(_ entry: PortEntry) -> Bool {
            id == entry.id &&
            pid == entry.pid &&
            processName == entry.processName &&
            user == entry.user &&
            executablePath == entry.executablePath &&
            commandLine == entry.commandLine &&
            privilegeLevel == entry.privilegeLevel
        }
    }

    public init(
        scanner: PortScanning = PortScannerService(),
        favoritesStore: FavoritesStoring = UserDefaultsFavoritesStore(),
        refreshIntervalStore: RefreshIntervalStoring = UserDefaultsRefreshIntervalStore(),
        terminator: ProcessTerminating = ProcessTerminator(),
        colorSchemePreferenceStore: ColorSchemePreferenceStoring = UserDefaultsColorSchemePreferenceStore()
    ) {
        self.scanner = scanner
        self.favoritesStore = favoritesStore
        self.refreshIntervalStore = refreshIntervalStore
        self.refreshInterval = refreshIntervalStore.load()
        self.terminator = terminator
        self.colorSchemePreferenceStore = colorSchemePreferenceStore
        self.colorSchemePreference = colorSchemePreferenceStore.load()
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

    public func setColorSchemePreference(_ preference: ColorSchemePreference) {
        colorSchemePreference = preference
        colorSchemePreferenceStore.save(preference)
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
            reconcileForceStateAfterRefresh()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    public func terminate(entry: PortEntry, mode: TerminationMode) async {
        if mode == .force {
            let candidate = ForceTerminationCandidate(entry: entry)
            guard pendingForceTerminationEntry?.id == entry.id && forceTerminationCandidate == candidate else {
                lastTerminationMessage = "请先发送 SIGTERM，并在进程仍未退出时确认 SIGKILL。"
                return
            }
        }
        do {
            let result = try await terminator.terminate(entry: entry, mode: mode)
            lastTerminationMessage = safeTerminationMessage(for: result, entry: entry, mode: mode)
            pendingForceTerminationEntry = nil
            guard result.status == .signalSent else {
                forceTerminationCandidate = nil
                return
            }
            let refreshSucceeded = await refreshNow()
            let candidate = ForceTerminationCandidate(entry: entry)
            if mode == .graceful && refreshSucceeded && entries.contains(where: { candidate.matches($0) }) {
                forceTerminationCandidate = candidate
                lastTerminationMessage = "已发送 SIGTERM，但进程仍在监听。确认后可使用 SIGKILL。"
            } else {
                forceTerminationCandidate = nil
            }
        } catch ProcessTerminationError.authenticationCancelled {
            clearForceState()
            lastTerminationMessage = "已取消认证，未结束进程。"
        } catch ProcessTerminationError.processIdentityChanged {
            clearForceState()
            lastTerminationMessage = "进程信息已变化，请刷新后重新确认，未发送结束信号。"
        } catch let error as ProcessTerminationError {
            clearForceState()
            lastTerminationMessage = error.localizedDescription
        } catch {
            clearForceState()
            lastTerminationMessage = "结束进程失败，请刷新后重试。"
        }
    }

    public func requestForceTermination(for entry: PortEntry) {
        guard forceTerminationCandidate == ForceTerminationCandidate(entry: entry) else {
            lastTerminationMessage = "请先发送 SIGTERM；进程仍未退出时才允许 SIGKILL。"
            return
        }
        pendingForceTerminationEntry = entry
    }

    public func cancelForceTermination() {
        pendingForceTerminationEntry = nil
    }

    private func reconcileForceStateAfterRefresh() {
        guard let candidate = forceTerminationCandidate else { return }
        if !entries.contains(where: { candidate.matches($0) }) {
            clearForceState()
        }
    }

    private func clearForceState() {
        pendingForceTerminationEntry = nil
        forceTerminationCandidate = nil
    }

    private func safeTerminationMessage(
        for result: ProcessTerminationResult,
        entry: PortEntry,
        mode: TerminationMode
    ) -> String {
        switch result.status {
        case .signalSent:
            let signalName = mode == .force ? "SIGKILL" : "SIGTERM"
            return "已发送 \(signalName) 到 PID \(entry.pid)。"
        case .processAlreadyExited:
            return "进程已退出，请刷新列表。"
        case .helperUnavailable:
            return "需要安装并批准 PortWatch Helper 后才能结束其他用户或系统进程。"
        }
    }
}
