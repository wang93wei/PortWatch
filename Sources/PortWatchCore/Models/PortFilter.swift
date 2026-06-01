import Foundation

public enum PortFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case listening
    case favorites
    case privileged
    case development
    case externalConnections

    public var id: String { rawValue }

    public static let sidebarCases: [PortFilter] = [
        .listening,
        .favorites,
        .privileged,
        .development
    ]

    public var title: String {
        switch self {
        case .listening: return "监听端口"
        case .favorites: return "常用端口"
        case .privileged: return "高权限进程"
        case .development: return "开发服务"
        case .externalConnections: return "外连连接"
        }
    }

    public func apply(to entries: [PortEntry], favoritePorts: Set<Int>, searchText: String) -> [PortEntry] {
        let scoped = entries.filter { entry in
            switch self {
            case .listening:
                return true
            case .favorites:
                return favoritePorts.contains(entry.port)
            case .privileged:
                return entry.privilegeLevel == .rootOrSystem || entry.privilegeLevel == .otherUser
            case .development:
                return entry.category == .development
            case .externalConnections:
                return false
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return scoped.sortedByPort() }
        return scoped.filter { entry in
            [
                "\(entry.port)",
                entry.protocolName.rawValue,
                entry.address,
                "\(entry.pid)",
                entry.processName,
                entry.user,
                entry.executablePath ?? "",
                entry.commandLine ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
        .sortedByPort()
    }
}

private extension Array where Element == PortEntry {
    func sortedByPort() -> [PortEntry] {
        sorted { lhs, rhs in
            if lhs.port == rhs.port { return lhs.processName < rhs.processName }
            return lhs.port < rhs.port
        }
    }
}
