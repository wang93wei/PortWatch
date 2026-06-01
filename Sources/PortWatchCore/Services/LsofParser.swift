import Foundation

public struct LsofParseResult: Equatable, Sendable {
    public let entries: [PortEntry]
    public let skippedLineCount: Int
}

public struct LsofParser: Sendable {
    private let currentUserName: String

    public init(currentUserName: String = NSUserName()) {
        self.currentUserName = currentUserName
    }

    public func parse(_ output: String) -> LsofParseResult {
        var entries: [PortEntry] = []
        var skipped = 0

        for line in output.split(separator: "\n").dropFirst() {
            guard let entry = parseLine(String(line)) else {
                skipped += 1
                continue
            }
            entries.append(entry)
        }

        return LsofParseResult(entries: entries, skippedLineCount: skipped)
    }

    private func parseLine(_ line: String) -> PortEntry? {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard fields.count >= 9 else { return nil }
        guard let pid = Int32(fields[1]) else { return nil }
        let processName = fields[0]
        let user = fields[2]
        let endpoint = fields[8]
        guard endpoint.contains(":") else { return nil }

        let endpointParts = endpoint.split(separator: ":", omittingEmptySubsequences: false)
        guard let portText = endpointParts.last, let port = Int(portText) else { return nil }
        let address = endpointParts.dropLast().joined(separator: ":")
        let normalizedAddress = address.isEmpty ? "*" : address

        return PortEntry(
            protocolName: .tcp,
            address: normalizedAddress,
            port: port,
            pid: pid,
            processName: processName,
            user: user,
            executablePath: nil,
            commandLine: nil,
            privilegeLevel: privilegeLevel(for: user),
            category: inferCategory(processName: processName, port: port, user: user)
        )
    }

    private func privilegeLevel(for user: String) -> PrivilegeLevel {
        if user == "root" || user == "_daemon" || user == "daemon" {
            return .rootOrSystem
        }
        if user == currentUserName {
            return .currentUser
        }
        return .otherUser
    }

    private func inferCategory(processName: String, port: Int, user: String) -> PortCategory {
        if privilegeLevel(for: user) == .rootOrSystem {
            return .privileged
        }
        let developmentProcesses = ["node", "vite", "python", "ruby", "java", "postgres", "redis-server"]
        let developmentPorts = [3000, 5000, 5173, 5432, 6379, 8000, 8080]
        if developmentProcesses.contains(processName) || developmentPorts.contains(port) {
            return .development
        }
        return .listening
    }
}
