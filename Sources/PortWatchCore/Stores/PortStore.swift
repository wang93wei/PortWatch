import Foundation
import Observation

@MainActor
@Observable
public final class PortStore {
    public private(set) var entries: [PortEntry] = [] {
        didSet { recomputeDerivedState() }
    }
    public private(set) var isRefreshing = false
    public private(set) var lastErrorMessage: String?
    public private(set) var lastRefreshDate: Date?
    public private(set) var lastTerminationMessage: String?
    public private(set) var pendingForceTerminationEntry: PortEntry?
    public private(set) var forceTerminationCandidate: ForceTerminationCandidate?
    public private(set) var favoritePorts: Set<Int> {
        didSet { recomputeDerivedState() }
    }
    public private(set) var filteredEntries: [PortEntry] = []
    public private(set) var menuEntries: [PortEntry] = []
    public private(set) var listeningEntryCount = 0
    public private(set) var privilegedEntryCount = 0
    public var selectedFilter: PortFilter = .listening {
        didSet { recomputeDerivedState() }
    }
    public var searchText = "" {
        didSet { recomputeDerivedState() }
    }
    public var refreshInterval: RefreshInterval {
        didSet {
            guard refreshInterval != oldValue else { return }
            refreshIntervalStore.save(refreshInterval)
            startAutoRefresh()
        }
    }
    public var colorSchemePreference: ColorSchemePreference {
        didSet {
            guard colorSchemePreference != oldValue else { return }
            colorSchemePreferenceStore.save(colorSchemePreference)
        }
    }

    private let scanner: PortScanning
    private let favoritesStore: FavoritesStoring
    private let refreshIntervalStore: RefreshIntervalStoring
    private let colorSchemePreferenceStore: ColorSchemePreferenceStoring
    private let terminator: ProcessTerminating
    private var refreshTask: Task<Void, Never>?
    private var colorSchemePreferenceTask: Task<Void, Never>?
    private var sidebarCounts: [PortFilter: Int] = [:]

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
        self.favoritePorts = favoritesStore.favoritePorts
        self.refreshIntervalStore = refreshIntervalStore
        self.refreshInterval = refreshIntervalStore.load()
        self.terminator = terminator
        self.colorSchemePreferenceStore = colorSchemePreferenceStore
        self.colorSchemePreference = colorSchemePreferenceStore.load()
        recomputeDerivedState()
    }

    public func setFilter(_ filter: PortFilter) {
        selectedFilter = filter
    }

    public func toggleFavorite(port: Int) {
        favoritesStore.toggle(port: port)
        favoritePorts = favoritesStore.favoritePorts
    }

    public func count(for filter: PortFilter) -> Int {
        sidebarCounts[filter, default: 0]
    }

    public func setRefreshInterval(_ interval: RefreshInterval) {
        refreshInterval = interval
    }

    public func setColorSchemePreference(_ preference: ColorSchemePreference) {
        colorSchemePreference = preference
    }

    public func requestColorSchemePreference(_ preference: ColorSchemePreference) {
        guard colorSchemePreference != preference else {
            colorSchemePreferenceTask?.cancel()
            colorSchemePreferenceTask = nil
            return
        }

        colorSchemePreferenceTask?.cancel()
        colorSchemePreferenceTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.setColorSchemePreference(preference)
            self.colorSchemePreferenceTask = nil
        }
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
        // 重入时不静默丢弃：若已有刷新 in-flight（例如 startAutoRefresh 后台任务
        // 正在扫描时用户点"结束进程"），等当前扫描完成后再扫一次，保证 caller 意图被执行。
        // 旧行为是直接 return false，导致 terminate 后端口条目要等下一轮自动刷新才更新。
        while isRefreshing {
            await Task.yield()
        }
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

    /// 用户在列表里切换了选中 entry。用来清空"上次结束操作"的消息，
    /// 避免切到别的 entry 还显示陈旧 PID。
    /// 不清 force state：force 状态本身已与具体 entry 绑定，不匹配 entry 的按钮天然 disabled。
    public func entrySelectionChanged() {
        lastTerminationMessage = nil
    }

    private func recomputeDerivedState() {
        filteredEntries = selectedFilter.apply(to: entries, favoritePorts: favoritePorts, searchText: searchText)
        listeningEntryCount = entries.count
        privilegedEntryCount = PortFilter.privileged.apply(to: entries, favoritePorts: favoritePorts, searchText: "").count
        sidebarCounts = Dictionary(uniqueKeysWithValues: PortFilter.sidebarCases.map { filter in
            (filter, filter.apply(to: entries, favoritePorts: favoritePorts, searchText: "").count)
        })

        let favoriteEntries = entries.filter { favoritePorts.contains($0.port) }
        menuEntries = Array((favoriteEntries.isEmpty ? entries : favoriteEntries).prefix(5))
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
