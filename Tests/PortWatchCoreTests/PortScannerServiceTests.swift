import XCTest
@testable import PortWatchCore

final class PortScannerServiceTests: XCTestCase {
    func testScannerExecutesLsofAndReturnsParsedEntries() async throws {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        node     8421 alan   21u  IPv4 0x1    0t0      TCP 127.0.0.1:3000 (LISTEN)
        """
        let executor = MockCommandExecutor(result: .success(CommandResult(stdout: output, stderr: "", exitCode: 0)))
        let metadata = MockProcessMetadataProvider(metadata: [
            8421: ProcessMetadata(executablePath: "/opt/homebrew/bin/node", commandLine: "node server.js")
        ])
        let scanner = PortScannerService(
            executor: executor,
            parser: LsofParser(currentUserName: "alan"),
            metadataProvider: metadata
        )

        let result = try await scanner.scanListeningPorts()

        let commands = await executor.commands
        XCTAssertEqual(commands, [CommandInvocation(executable: "/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN"])])
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].port, 3000)
        XCTAssertEqual(result.entries[0].executablePath, "/opt/homebrew/bin/node")
        XCTAssertEqual(result.entries[0].commandLine, "node server.js")
    }

    func testScannerReportsCommandFailure() async {
        let executor = MockCommandExecutor(result: .success(CommandResult(stdout: "", stderr: "permission denied", exitCode: 1)))
        let scanner = PortScannerService(executor: executor, parser: LsofParser(currentUserName: "alan"))

        do {
            _ = try await scanner.scanListeningPorts()
            XCTFail("Expected scan failure")
        } catch let error as PortScannerError {
            XCTAssertEqual(error.localizedDescription, "lsof failed with exit code 1: permission denied")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLiveCommandExecutorDrainsLargeOutputBeforeWaiting() async throws {
        let executor = LiveCommandExecutor()
        let command = """
        i=1
        while [ $i -le 20000 ]; do
          printf 'out-%05d\\n' "$i"
          printf 'err-%05d\\n' "$i" >&2
          i=$((i+1))
        done
        """

        let result = try await executor.run(CommandInvocation(executable: "/bin/sh", arguments: ["-c", command]))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("out-20000"))
        XCTAssertTrue(result.stderr.contains("err-20000"))
    }

    func testMetadataProviderUsesProcPIDPathAndUcommAndArgs() async {
        // 一次 ps 同时拿 ucomm（canonical processName）+ args，避免 lsof 的 COMMAND 字段
        // 对 .app bundle 取短名导致扫描时 processName 与 verify 阶段不一致。
        let executor = MockCommandExecutor(result: .success(CommandResult(stdout: "node /opt/homebrew/bin/node server.js\n", stderr: "", exitCode: 0)))
        let pathResolver = MockProcessPathResolver(paths: [8421: "/opt/homebrew/bin/node"])
        let provider = PSProcessMetadataProvider(executor: executor, pathResolver: pathResolver)

        let metadata = await provider.metadata(for: 8421)

        let commands = await executor.commands
        XCTAssertEqual(commands, [CommandInvocation(executable: "/bin/ps", arguments: ["-p", "8421", "-o", "ucomm=", "-o", "args="])])
        XCTAssertEqual(metadata.executablePath, "/opt/homebrew/bin/node")
        XCTAssertEqual(metadata.commandLine, "/opt/homebrew/bin/node server.js")
        XCTAssertEqual(metadata.processName, "node")
    }

    func testMetadataProviderHandlesUcommUnavailable() async {
        // ps 失败或空输出时 processName 应为 nil（不强行猜测）
        let executor = MockCommandExecutor(result: .success(CommandResult(stdout: "", stderr: "", exitCode: 1)))
        let provider = PSProcessMetadataProvider(executor: executor, pathResolver: MockProcessPathResolver(paths: [:]))

        let metadata = await provider.metadata(for: 8421)

        XCTAssertNil(metadata.processName)
        XCTAssertNil(metadata.commandLine)
    }

    func testScannerOverwritesProcessNameWithPSUcomm() async throws {
        // lsof 给 ApifoxApp（.app 短名），ps -o ucomm= 给 ApifoxAppAgent（binary 短名）
        // 扫描时必须用 ps 的版本覆盖，否则 verify 阶段 processName 误判。
        let lsofOutput = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        ApifoxApp 956 alan   21u  IPv4 0x1    0t0      TCP 127.0.0.1:42950 (LISTEN)
        """
        let executor = MockCommandExecutor(result: .success(CommandResult(stdout: lsofOutput, stderr: "", exitCode: 0)))
        let metadata = MockProcessMetadataProvider(metadata: [
            956: ProcessMetadata(
                processName: "ApifoxAppAgent",
                executablePath: "/Applications/ApifoxApp.app/Contents/MacOS/ApifoxAppAgent",
                commandLine: "/Applications/ApifoxApp.app/Contents/MacOS/ApifoxAppAgent"
            )
        ])
        let scanner = PortScannerService(
            executor: executor,
            parser: LsofParser(currentUserName: "alan"),
            metadataProvider: metadata
        )

        let result = try await scanner.scanListeningPorts()

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].processName, "ApifoxAppAgent", "必须用 ps 拿的 ucomm 覆盖 lsof 的 COMMAND")
    }

    func testScannerKeepsLsofProcessNameWhenPSUcommUnavailable() async throws {
        // ps 拿不到 processName 时，保留 lsof 的（fail-closed，行为可预测）
        let lsofOutput = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        mysqld    123 root   21u  IPv4 0x1    0t0      TCP 127.0.0.1:3306 (LISTEN)
        """
        let executor = MockCommandExecutor(result: .success(CommandResult(stdout: lsofOutput, stderr: "", exitCode: 0)))
        let metadata = MockProcessMetadataProvider(metadata: [
            123: ProcessMetadata(processName: nil, executablePath: nil, commandLine: "mysqld")
        ])
        let scanner = PortScannerService(
            executor: executor,
            parser: LsofParser(currentUserName: "alan"),
            metadataProvider: metadata
        )

        let result = try await scanner.scanListeningPorts()

        XCTAssertEqual(result.entries[0].processName, "mysqld")
    }

    func testIdentityProviderUsesUcommForLsofCommandName() async {
        let executor = MockCommandExecutor(result: .success(CommandResult(stdout: "8421 node alan\n", stderr: "", exitCode: 0)))
        let pathResolver = MockProcessPathResolver(paths: [8421: "/opt/homebrew/bin/node"])
        let provider = PSProcessMetadataProvider(executor: executor, pathResolver: pathResolver)

        let identity = await provider.identity(for: 8421)

        let commands = await executor.commands
        XCTAssertEqual(commands, [CommandInvocation(executable: "/bin/ps", arguments: ["-p", "8421", "-o", "pid=", "-o", "ucomm=", "-o", "user="])])
        XCTAssertEqual(identity, ProcessIdentity(pid: 8421, processName: "node", user: "alan", executablePath: "/opt/homebrew/bin/node"))
    }
}

private actor MockCommandExecutor: CommandExecuting {
    private(set) var commands: [CommandInvocation] = []
    private let result: Result<CommandResult, Error>

    init(result: Result<CommandResult, Error>) {
        self.result = result
    }

    func run(_ invocation: CommandInvocation) async throws -> CommandResult {
        commands.append(invocation)
        return try result.get()
    }
}

private struct MockProcessMetadataProvider: ProcessMetadataProviding {
    let metadata: [Int32: ProcessMetadata]
    var identities: [Int32: ProcessIdentity] = [:]

    func metadata(for pid: Int32) async -> ProcessMetadata {
        metadata[pid] ?? ProcessMetadata(executablePath: nil, commandLine: nil)
    }

    func identity(for pid: Int32) async -> ProcessIdentity? {
        identities[pid]
    }
}

private struct MockProcessPathResolver: ProcessPathResolving {
    let paths: [Int32: String]

    func executablePath(for pid: Int32) -> String? {
        paths[pid]
    }
}
