import Foundation

public enum PortProtocol: String, Codable, Sendable, CaseIterable {
    case tcp
}

public enum PrivilegeLevel: String, Codable, Sendable {
    case currentUser
    case otherUser
    case rootOrSystem
}

public enum PortCategory: String, Codable, Sendable, CaseIterable {
    case listening
    case favorite
    case privileged
    case development
    case externalConnections
}

public struct PortEntry: Identifiable, Hashable, Codable, Sendable {
    public let protocolName: PortProtocol
    public let address: String
    public let port: Int
    public let pid: Int32
    public let processName: String
    public let user: String
    public let executablePath: String?
    public let commandLine: String?
    public let privilegeLevel: PrivilegeLevel
    public let category: PortCategory

    public var id: String {
        "\(protocolName.rawValue)-\(address)-\(port)-\(pid)"
    }

    public var displayEndpoint: String {
        "\(address):\(port)"
    }

    public init(
        protocolName: PortProtocol,
        address: String,
        port: Int,
        pid: Int32,
        processName: String,
        user: String,
        executablePath: String?,
        commandLine: String?,
        privilegeLevel: PrivilegeLevel,
        category: PortCategory
    ) {
        self.protocolName = protocolName
        self.address = address
        self.port = port
        self.pid = pid
        self.processName = processName
        self.user = user
        self.executablePath = executablePath
        self.commandLine = commandLine
        self.privilegeLevel = privilegeLevel
        self.category = category
    }
}
