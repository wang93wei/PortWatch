import LocalAuthentication
import Foundation
import XCTest
@testable import PortWatchCore

final class ProcessTerminatorTests: XCTestCase {
    func testLocalAuthenticationClientReturnsFalseForCancellationError() async throws {
        let client = LocalAuthenticationClient(evaluator: MockLocalAuthenticationEvaluator { _ in
            throw LAError(.userCancel)
        })

        let result = try await client.authenticate(reason: "结束测试进程")

        XCTAssertFalse(result)
    }

    func testCurrentUserProcessUsesTermSignalFirst() async throws {
        let executor = MockSignalExecutor()
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(signalExecutor: executor, identityVerifier: verifier, logger: logger)
        let entry = sample(privilege: .currentUser)

        let result = try await terminator.terminate(entry: entry, mode: .graceful)

        let sentSignals = await executor.sentSignals
        let verifiedPIDs = await verifier.verifiedPIDs
        XCTAssertEqual(sentSignals, [SentSignal(pid: entry.pid, signal: .term)])
        XCTAssertEqual(result.status, .signalSent)
        XCTAssertEqual(verifiedPIDs, [entry.pid])
        XCTAssertTrue(logger.infoMessages.contains("termination requested pid=91 signal=term privilege=currentUser"))
        XCTAssertTrue(logger.infoMessages.contains("termination signal sent pid=91 signal=term"))
    }

    func testRootProcessRequiresAuthenticationAndHelper() async throws {
        let auth = MockAuthenticationClient(result: true)
        let helper = MockPrivilegedHelperClient(result: .success(ProcessTerminationResult(status: .signalSent, message: "TERM sent by helper")))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(authenticationClient: auth, helperClient: helper, identityVerifier: verifier, logger: logger)
        let entry = sample(privilege: .rootOrSystem)

        let result = try await terminator.terminate(entry: entry, mode: .graceful)

        let prompts = await auth.prompts
        let requests = await helper.requests
        XCTAssertEqual(result.status, .signalSent)
        XCTAssertEqual(prompts, ["结束 root 进程 nginx (PID 91)"])
        XCTAssertEqual(requests, [PrivilegedTerminationRequest(pid: 91, signal: .term)])
        XCTAssertTrue(logger.infoMessages.contains("authentication result pid=91 granted=true"))
        XCTAssertTrue(logger.infoMessages.contains("helper termination result pid=91 status=signalSent"))
    }

    func testHelperUnavailableStatusPayloadIsNeverLoggedVerbatim() async throws {
        let auth = MockAuthenticationClient(result: true)
        let helper = MockPrivilegedHelperClient(result: .success(ProcessTerminationResult(
            status: .helperUnavailable("node server.js --token=secret"),
            message: "node server.js --token=secret"
        )))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(authenticationClient: auth, helperClient: helper, identityVerifier: verifier, logger: logger)

        _ = try await terminator.terminate(entry: sample(privilege: .rootOrSystem), mode: .graceful)

        let infoText = logger.infoMessages.joined(separator: "\n")
        XCTAssertTrue(infoText.contains("helper termination result pid=91 status=helperUnavailable"))
        XCTAssertFalse(infoText.contains("node server.js --token=secret"))
        XCTAssertFalse(infoText.contains("secret"))
    }

    func testCancelledAuthenticationDoesNotCallHelper() async {
        let auth = MockAuthenticationClient(result: false)
        let helper = MockPrivilegedHelperClient(result: .success(ProcessTerminationResult(status: .signalSent, message: "TERM sent by helper")))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(authenticationClient: auth, helperClient: helper, identityVerifier: verifier, logger: logger)

        do {
            _ = try await terminator.terminate(entry: sample(privilege: .rootOrSystem), mode: .graceful)
            XCTFail("Expected authentication error")
        } catch ProcessTerminationError.authenticationCancelled {
            let requests = await helper.requests
            XCTAssertTrue(requests.isEmpty)
            XCTAssertTrue(logger.infoMessages.contains("authentication result pid=91 granted=false"))
            XCTAssertTrue(logger.errorMessages.contains("termination cancelled reason=authentication_cancelled pid=91"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthenticationCancellationErrorDoesNotCallHelper() async {
        let auth = MockAuthenticationClient(result: true, error: ProcessTerminationError.authenticationCancelled)
        let helper = MockPrivilegedHelperClient(result: .success(ProcessTerminationResult(status: .signalSent, message: "TERM sent by helper")))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(authenticationClient: auth, helperClient: helper, identityVerifier: verifier, logger: logger)

        do {
            _ = try await terminator.terminate(entry: sample(privilege: .rootOrSystem), mode: .graceful)
            XCTFail("Expected authentication error")
        } catch ProcessTerminationError.authenticationCancelled {
            let requests = await helper.requests
            XCTAssertTrue(requests.isEmpty)
            XCTAssertTrue(logger.infoMessages.contains("authentication result pid=91 granted=false"))
            XCTAssertTrue(logger.errorMessages.contains("termination cancelled reason=authentication_cancelled pid=91"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIdentityMismatchStopsBeforeSignal() async {
        let executor = MockSignalExecutor()
        let verifier = MockProcessIdentityVerifier(result: false)
        let logger = MockLogger()
        let terminator = ProcessTerminator(signalExecutor: executor, identityVerifier: verifier, logger: logger)

        do {
            _ = try await terminator.terminate(entry: sample(privilege: .currentUser), mode: .graceful)
            XCTFail("Expected identity mismatch")
        } catch ProcessTerminationError.processIdentityChanged {
            let sentSignals = await executor.sentSignals
            XCTAssertTrue(sentSignals.isEmpty)
            XCTAssertTrue(logger.errorMessages.contains("termination blocked reason=identity_changed pid=91"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSignalFailureIsLoggedWithoutCommandLine() async {
        let executor = MockSignalExecutor(error: ProcessTerminationError.signalFailed("EPERM"))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(signalExecutor: executor, identityVerifier: verifier, logger: logger)

        do {
            _ = try await terminator.terminate(entry: sample(privilege: .currentUser), mode: .graceful)
            XCTFail("Expected signal failure")
        } catch ProcessTerminationError.signalFailed {
            let errorText = logger.errorMessages.joined(separator: "\n")
            XCTAssertTrue(errorText.contains("termination signal failed pid=91 signal=term error=signalFailed(reason=eperm)"))
            XCTAssertFalse(errorText.contains("nginx: master process"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSignalFailurePayloadIsNeverLoggedVerbatim() async {
        let entry = sample(privilege: .currentUser)
        let executor = MockSignalExecutor(error: ProcessTerminationError.signalFailed(entry.commandLine!))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(signalExecutor: executor, identityVerifier: verifier, logger: logger)

        do {
            _ = try await terminator.terminate(entry: entry, mode: .graceful)
            XCTFail("Expected signal failure")
        } catch ProcessTerminationError.signalFailed {
            let errorText = logger.errorMessages.joined(separator: "\n")
            XCTAssertTrue(errorText.contains("termination signal failed pid=91 signal=term error=signalFailed(reason=other)"))
            XCTAssertFalse(errorText.contains(entry.commandLine!))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHelperFailureIsLoggedWithoutCommandLine() async {
        let auth = MockAuthenticationClient(result: true)
        let helper = MockPrivilegedHelperClient(result: .failure(ProcessTerminationError.signalFailed("helper failed")))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(authenticationClient: auth, helperClient: helper, identityVerifier: verifier, logger: logger)

        do {
            _ = try await terminator.terminate(entry: sample(privilege: .rootOrSystem), mode: .graceful)
            XCTFail("Expected helper failure")
        } catch ProcessTerminationError.signalFailed {
            let errorText = logger.errorMessages.joined(separator: "\n")
            XCTAssertTrue(errorText.contains("helper termination failed pid=91 signal=term error=signalFailed(reason=other)"))
            XCTAssertFalse(errorText.contains("nginx: master process"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHelperFailurePayloadIsNeverLoggedVerbatim() async {
        let auth = MockAuthenticationClient(result: true)
        let helper = MockPrivilegedHelperClient(result: .failure(ProcessTerminationError.signalFailed("node server.js --token=secret")))
        let verifier = MockProcessIdentityVerifier(result: true)
        let logger = MockLogger()
        let terminator = ProcessTerminator(authenticationClient: auth, helperClient: helper, identityVerifier: verifier, logger: logger)

        do {
            _ = try await terminator.terminate(entry: sample(privilege: .rootOrSystem), mode: .graceful)
            XCTFail("Expected helper failure")
        } catch ProcessTerminationError.signalFailed {
            let errorText = logger.errorMessages.joined(separator: "\n")
            XCTAssertTrue(errorText.contains("helper termination failed pid=91 signal=term error=signalFailed(reason=other)"))
            XCTAssertFalse(errorText.contains("node server.js --token=secret"))
            XCTAssertFalse(errorText.contains("secret"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIdentityVerifierFailsClosedWhenMetadataIsMissing() async {
        let provider = MockMetadataProvider(metadata: [:], identities: [:])
        let verifier = ProcessIdentityVerifier(metadataProvider: provider)

        let result = await verifier.verify(entry: sample(privilege: .currentUser))

        XCTAssertFalse(result)
    }

    func testIdentityVerifierRequiresSamePIDProcessNameUserAndPath() async {
        let entry = sample(privilege: .currentUser)
        let commandOnlyEntry = PortEntry(
            protocolName: entry.protocolName,
            address: entry.address,
            port: entry.port,
            pid: entry.pid,
            processName: entry.processName,
            user: entry.user,
            executablePath: nil,
            commandLine: entry.commandLine,
            privilegeLevel: entry.privilegeLevel,
            category: entry.category
        )
        let matching = MockMetadataProvider(
            metadata: [entry.pid: ProcessMetadata(executablePath: entry.executablePath, commandLine: entry.commandLine)],
            identities: [entry.pid: ProcessIdentity(pid: entry.pid, processName: entry.processName, user: entry.user, executablePath: entry.executablePath)]
        )
        let mismatchedName = MockMetadataProvider(
            metadata: [entry.pid: ProcessMetadata(executablePath: entry.executablePath, commandLine: entry.commandLine)],
            identities: [entry.pid: ProcessIdentity(pid: entry.pid, processName: "python", user: entry.user, executablePath: entry.executablePath)]
        )
        let mismatchedUser = MockMetadataProvider(
            metadata: [entry.pid: ProcessMetadata(executablePath: entry.executablePath, commandLine: entry.commandLine)],
            identities: [entry.pid: ProcessIdentity(pid: entry.pid, processName: entry.processName, user: "root", executablePath: entry.executablePath)]
        )
        let mismatchedPath = MockMetadataProvider(
            metadata: [entry.pid: ProcessMetadata(executablePath: "/usr/bin/python3", commandLine: entry.commandLine)],
            identities: [entry.pid: ProcessIdentity(pid: entry.pid, processName: entry.processName, user: entry.user, executablePath: "/usr/bin/python3")]
        )
        let missingActualPath = MockMetadataProvider(
            metadata: [entry.pid: ProcessMetadata(executablePath: nil, commandLine: entry.commandLine)],
            identities: [entry.pid: ProcessIdentity(pid: entry.pid, processName: entry.processName, user: entry.user, executablePath: nil)]
        )
        let partialCommand = MockMetadataProvider(
            metadata: [entry.pid: ProcessMetadata(executablePath: nil, commandLine: "nginx")],
            identities: [entry.pid: ProcessIdentity(pid: entry.pid, processName: entry.processName, user: entry.user, executablePath: nil)]
        )

        let matchingResult = await ProcessIdentityVerifier(metadataProvider: matching).verify(entry: entry)
        let mismatchedNameResult = await ProcessIdentityVerifier(metadataProvider: mismatchedName).verify(entry: entry)
        let mismatchedUserResult = await ProcessIdentityVerifier(metadataProvider: mismatchedUser).verify(entry: entry)
        let mismatchedPathResult = await ProcessIdentityVerifier(metadataProvider: mismatchedPath).verify(entry: entry)
        let missingActualPathResult = await ProcessIdentityVerifier(metadataProvider: missingActualPath).verify(entry: entry)
        let partialCommandResult = await ProcessIdentityVerifier(metadataProvider: partialCommand).verify(entry: commandOnlyEntry)
        XCTAssertTrue(matchingResult)
        XCTAssertFalse(mismatchedNameResult)
        XCTAssertFalse(mismatchedUserResult)
        XCTAssertFalse(mismatchedPathResult)
        XCTAssertFalse(missingActualPathResult)
        XCTAssertFalse(partialCommandResult)
    }
}

private actor MockSignalExecutor: SignalExecuting {
    private(set) var sentSignals: [SentSignal] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func send(signal: TerminationSignal, to pid: Int32) async throws {
        if let error {
            throw error
        }
        sentSignals.append(SentSignal(pid: pid, signal: signal))
    }
}

private actor MockAuthenticationClient: LocalAuthenticating {
    private(set) var prompts: [String] = []
    private let result: Bool
    private let error: Error?

    init(result: Bool, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func authenticate(reason: String) async throws -> Bool {
        prompts.append(reason)
        if let error {
            throw error
        }
        return result
    }
}

private struct MockLocalAuthenticationEvaluator: LocalAuthenticationEvaluating {
    private let handler: @Sendable (String) async throws -> Bool

    init(_ handler: @escaping @Sendable (String) async throws -> Bool) {
        self.handler = handler
    }

    func evaluate(reason: String) async throws -> Bool {
        try await handler(reason)
    }
}

private actor MockPrivilegedHelperClient: PrivilegedHelperClienting {
    private(set) var requests: [PrivilegedTerminationRequest] = []
    private let result: Result<ProcessTerminationResult, Error>

    init(result: Result<ProcessTerminationResult, Error>) {
        self.result = result
    }

    func terminate(_ request: PrivilegedTerminationRequest) async throws -> ProcessTerminationResult {
        requests.append(request)
        return try result.get()
    }
}

private actor MockProcessIdentityVerifier: ProcessIdentityVerifying {
    private(set) var verifiedPIDs: [Int32] = []
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func verify(entry: PortEntry) async -> Bool {
        verifiedPIDs.append(entry.pid)
        return result
    }
}

private struct MockMetadataProvider: ProcessMetadataProviding {
    let metadata: [Int32: ProcessMetadata]
    let identities: [Int32: ProcessIdentity]

    func metadata(for pid: Int32) async -> ProcessMetadata {
        metadata[pid] ?? ProcessMetadata(executablePath: nil, commandLine: nil)
    }

    func identity(for pid: Int32) async -> ProcessIdentity? {
        identities[pid]
    }
}

private final class MockLogger: PortWatchLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedInfoMessages: [String] = []
    private var capturedErrorMessages: [String] = []

    var infoMessages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedInfoMessages
    }

    var errorMessages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedErrorMessages
    }

    func info(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        capturedInfoMessages.append(message)
    }

    func error(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        capturedErrorMessages.append(message)
    }
}

private struct SentSignal: Equatable {
    let pid: Int32
    let signal: TerminationSignal
}

private func sample(privilege: PrivilegeLevel) -> PortEntry {
    PortEntry(
        protocolName: .tcp,
        address: "0.0.0.0",
        port: 80,
        pid: 91,
        processName: "nginx",
        user: privilege == .currentUser ? NSUserName() : "root",
        executablePath: "/usr/local/nginx/sbin/nginx",
        commandLine: "nginx: master process",
        privilegeLevel: privilege,
        category: privilege == .currentUser ? .development : .privileged
    )
}
