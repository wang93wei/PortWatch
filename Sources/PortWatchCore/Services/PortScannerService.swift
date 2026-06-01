import Foundation

public struct PortScanResult: Equatable, Sendable {
    public let entries: [PortEntry]
    public let skippedLineCount: Int
    public let duration: TimeInterval
}

public enum PortScannerError: LocalizedError, Equatable {
    case commandFailed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(exitCode, stderr):
            return "lsof failed with exit code \(exitCode): \(stderr)"
        }
    }
}

public struct PortScannerService: Sendable {
    private let executor: CommandExecuting
    private let parser: LsofParser
    private let metadataProvider: ProcessMetadataProviding
    private let logger: PortWatchLogger

    public init(
        executor: CommandExecuting = LiveCommandExecutor(),
        parser: LsofParser = LsofParser(),
        metadataProvider: ProcessMetadataProviding = PSProcessMetadataProvider(),
        logger: PortWatchLogger = PortWatchLogger(category: "PortScanner")
    ) {
        self.executor = executor
        self.parser = parser
        self.metadataProvider = metadataProvider
        self.logger = logger
    }

    public func scanListeningPorts() async throws -> PortScanResult {
        let start = Date()
        let invocation = CommandInvocation(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"]
        )
        let result = try await executor.run(invocation)
        guard result.exitCode == 0 else {
            logger.error("lsof failed with exit code \(result.exitCode)")
            throw PortScannerError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        let parsed = parser.parse(result.stdout)
        var enrichedEntries: [PortEntry] = []
        for entry in parsed.entries {
            let metadata = await metadataProvider.metadata(for: entry.pid)
            enrichedEntries.append(entry.withMetadata(metadata))
        }
        let duration = Date().timeIntervalSince(start)
        logger.info("scan finished entries=\(enrichedEntries.count) skipped=\(parsed.skippedLineCount) duration=\(duration)")

        return PortScanResult(entries: enrichedEntries, skippedLineCount: parsed.skippedLineCount, duration: duration)
    }
}
