import Darwin
import Foundation

public struct ProcessMetadata: Equatable, Sendable {
    public let processName: String?
    public let executablePath: String?
    public let commandLine: String?

    public init(
        processName: String? = nil,
        executablePath: String?,
        commandLine: String?
    ) {
        self.processName = processName
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
    private let logger: any PortWatchLogging

    public init(logger: any PortWatchLogging = PortWatchLogger(category: "ProcPIDPathResolver")) {
        self.logger = logger
    }

    public func executablePath(for pid: Int32) -> String? {
        let capacity = 4096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        defer {
            buffer.deinitialize(count: capacity)
            buffer.deallocate()
        }

        let result = proc_pidpath(pid, buffer, UInt32(capacity))
        guard result > 0 else {
            logger.error("proc_pidpath failed pid=\(pid) ret=\(result) errno=\(errno)")
            return nil
        }
        return String(cString: buffer)
    }
}

public struct PSProcessMetadataProvider: ProcessMetadataProviding {
    private let executor: CommandExecuting
    private let pathResolver: ProcessPathResolving
    private let logger: any PortWatchLogging

    public init(
        executor: CommandExecuting = LiveCommandExecutor(),
        pathResolver: ProcessPathResolving = ProcPIDPathResolver(),
        logger: any PortWatchLogging = PortWatchLogger(category: "PSProcessMetadataProvider")
    ) {
        self.executor = executor
        self.pathResolver = pathResolver
        self.logger = logger
    }

    public func metadata(for pid: Int32) async -> ProcessMetadata {
        let executablePath = pathResolver.executablePath(for: pid)
        // 一次 ps 拿两个字段：ucomm（canonical processName，由 exec 设置） + args。
        // lsof 的 COMMAND 字段对 .app bundle 内 binary 会从 .app 名字取短名（与 ps 的 p_comm 不一致），
        // 所以扫描时必须用 ps 拿 canonical name，否则 verify 阶段 processName 不匹配误判身份变更。
        let invocation = CommandInvocation(
            executable: "/bin/ps",
            arguments: ["-p", "\(pid)", "-o", "ucomm=", "-o", "args="]
        )
        guard let result = try? await executor.run(invocation), result.exitCode == 0 else {
            return ProcessMetadata(executablePath: executablePath, commandLine: nil)
        }
        let line = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // ucomm 是第一列（binary 短名），args 是后续列。`maxSplits: 1` 拿到两段。
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let processName = parts.first.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        let commandLine = parts.count >= 2 ? String(parts[1]) : nil
        return ProcessMetadata(
            processName: processName,
            executablePath: executablePath,
            commandLine: commandLine
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
        let resolvedPath = pathResolver.executablePath(for: actualPID)
        if resolvedPath == nil {
            // ps 找得到进程但 proc_pidpath 拿不到路径 —— 常见于未签名 / 未启用 Hardened Runtime
            // 二进制在 macOS 14+ 上被 Mach 层限制（task name port right 失败）。
            // 记 warning 让 Xcode Console 可见，便于定位 identity_changed 误判。
            logger.warning("proc_pidpath unavailable pid=\(actualPID) name=\(parts[1]) user=\(parts[2])")
        }
        return ProcessIdentity(
            pid: actualPID,
            processName: parts[1],
            user: parts[2],
            executablePath: resolvedPath
        )
    }
}
