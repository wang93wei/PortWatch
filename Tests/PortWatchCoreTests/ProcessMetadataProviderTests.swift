import Foundation
import XCTest
@testable import PortWatchCore

final class ProcessMetadataProviderTests: XCTestCase {
    func testIdentityLogsWarningWhenProcPidpathIsUnavailable() async {
        // 模拟"ps 找得到进程但 proc_pidpath 拿不到路径"——这是未签名 app 在 macOS 14+ 上
        // 触发 identity_changed 误判的根因路径，必须在日志里可见。
        let executor = StubCommandExecutor(result: CommandResult(
            stdout: "956 ApifoxAppAgent alanwang\n",
            stderr: "",
            exitCode: 0
        ))
        let pathResolver = AlwaysNilPathResolver()
        let logger = CapturingLogger()
        let provider = PSProcessMetadataProvider(executor: executor, pathResolver: pathResolver, logger: logger)

        _ = await provider.identity(for: 956)

        XCTAssertTrue(
            logger.warningMessages.contains(where: { $0.contains("proc_pidpath unavailable pid=956") }),
            "期望 warning 包含 'proc_pidpath unavailable pid=956'，实际: \(logger.warningMessages)"
        )
    }

    func testIdentityDoesNotLogWarningWhenPathIsAvailable() async {
        let executor = StubCommandExecutor(result: CommandResult(
            stdout: "956 ApifoxAppAgent alanwang\n",
            stderr: "",
            exitCode: 0
        ))
        let pathResolver = FixedPathResolver(path: "/Applications/ApifoxAppAgent.app/Contents/MacOS/ApifoxAppAgent")
        let logger = CapturingLogger()
        let provider = PSProcessMetadataProvider(executor: executor, pathResolver: pathResolver, logger: logger)

        _ = await provider.identity(for: 956)

        XCTAssertFalse(
            logger.warningMessages.contains(where: { $0.contains("proc_pidpath unavailable") }),
            "不应打 warning，实际: \(logger.warningMessages)"
        )
    }
}

// MARK: - Test doubles

private struct StubCommandExecutor: CommandExecuting {
    let result: CommandResult
    func run(_ invocation: CommandInvocation) async throws -> CommandResult { result }
}

private struct AlwaysNilPathResolver: ProcessPathResolving {
    func executablePath(for pid: Int32) -> String? { nil }
}

private struct FixedPathResolver: ProcessPathResolving {
    let path: String
    func executablePath(for pid: Int32) -> String? { path }
}

private final class CapturingLogger: PortWatchLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedInfo: [String] = []
    private var capturedWarning: [String] = []
    private var capturedError: [String] = []

    var infoMessages: [String] { lock.withLock { capturedInfo } }
    var warningMessages: [String] { lock.withLock { capturedWarning } }
    var errorMessages: [String] { lock.withLock { capturedError } }

    func info(_ message: String) { lock.withLock { capturedInfo.append(message) } }
    func warning(_ message: String) { lock.withLock { capturedWarning.append(message) } }
    func error(_ message: String) { lock.withLock { capturedError.append(message) } }
}
