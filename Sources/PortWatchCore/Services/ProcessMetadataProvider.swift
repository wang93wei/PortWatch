import Darwin
import Foundation

public struct ProcessMetadata: Equatable, Sendable {
    public let executablePath: String?
    public let commandLine: String?

    public init(executablePath: String?, commandLine: String?) {
        self.executablePath = executablePath
        self.commandLine = commandLine
    }
}

public struct ProcessIdentity: Equatable, Sendable {
    public let pid: Int32
    public let processName: String
    public let user: String
    public let executablePath: String?

    public init(pid: Int32, processName: String, user: String, executablePath: String?) {
        self.pid = pid
        self.processName = processName
        self.user = user
        self.executablePath = executablePath
    }
}

extension PortEntry {
    public func withMetadata(_ metadata: ProcessMetadata) -> PortEntry {
        PortEntry(
            protocolName: protocolName,
            address: address,
            port: port,
            pid: pid,
            processName: processName,
            user: user,
            executablePath: metadata.executablePath,
            commandLine: metadata.commandLine,
            privilegeLevel: privilegeLevel,
            category: category
        )
    }
}

public protocol ProcessMetadataProviding: Sendable {
    func metadata(for pid: Int32) async -> ProcessMetadata
    func identity(for pid: Int32) async -> ProcessIdentity?
}

public protocol ProcessPathResolving: Sendable {
    func executablePath(for pid: Int32) -> String?
}

public struct ProcPIDPathResolver: ProcessPathResolving {
    public init() {}

    public func executablePath(for pid: Int32) -> String? {
        let capacity = 4096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        defer {
            buffer.deinitialize(count: capacity)
            buffer.deallocate()
        }

        let result = proc_pidpath(pid, buffer, UInt32(capacity))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }
}

public struct PSProcessMetadataProvider: ProcessMetadataProviding {
    private let executor: CommandExecuting
    private let pathResolver: ProcessPathResolving

    public init(
        executor: CommandExecuting = LiveCommandExecutor(),
        pathResolver: ProcessPathResolving = ProcPIDPathResolver()
    ) {
        self.executor = executor
        self.pathResolver = pathResolver
    }

    public func metadata(for pid: Int32) async -> ProcessMetadata {
        let executablePath = pathResolver.executablePath(for: pid)
        let invocation = CommandInvocation(
            executable: "/bin/ps",
            arguments: ["-p", "\(pid)", "-o", "args="]
        )
        guard let result = try? await executor.run(invocation), result.exitCode == 0 else {
            return ProcessMetadata(executablePath: executablePath, commandLine: nil)
        }
        let line = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessMetadata(
            executablePath: executablePath,
            commandLine: trimmed.isEmpty ? nil : trimmed
        )
    }

    public func identity(for pid: Int32) async -> ProcessIdentity? {
        let invocation = CommandInvocation(
            executable: "/bin/ps",
            arguments: ["-p", "\(pid)", "-o", "pid=", "-o", "ucomm=", "-o", "user="]
        )
        guard let result = try? await executor.run(invocation), result.exitCode == 0 else {
            return nil
        }
        let parts = result.stdout
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        guard parts.count >= 3, let actualPID = Int32(parts[0]) else {
            return nil
        }
        return ProcessIdentity(
            pid: actualPID,
            processName: parts[1],
            user: parts[2],
            executablePath: pathResolver.executablePath(for: actualPID)
        )
    }
}
