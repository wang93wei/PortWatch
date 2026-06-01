import Foundation

public protocol SignalExecuting: Sendable {
    func send(signal: TerminationSignal, to pid: Int32) async throws
}

public struct LiveSignalExecutor: SignalExecuting {
    public init() {}

    public func send(signal: TerminationSignal, to pid: Int32) async throws {
        let result = Darwin.kill(pid, signal.systemValue)
        if result != 0 {
            throw ProcessTerminationError.signalFailed(String(cString: strerror(errno)))
        }
    }
}

public protocol ProcessTerminating: Sendable {
    func terminate(entry: PortEntry, mode: TerminationMode) async throws -> ProcessTerminationResult
}

public struct ProcessTerminator: Sendable {
    private let signalExecutor: SignalExecuting
    private let authenticationClient: LocalAuthenticating
    private let helperClient: PrivilegedHelperClienting
    private let identityVerifier: ProcessIdentityVerifying
    private let logger: any PortWatchLogging

    public init(
        signalExecutor: SignalExecuting = LiveSignalExecutor(),
        authenticationClient: LocalAuthenticating = LocalAuthenticationClient(),
        helperClient: PrivilegedHelperClienting = UnavailablePrivilegedHelperClient(),
        identityVerifier: ProcessIdentityVerifying = ProcessIdentityVerifier(),
        logger: any PortWatchLogging = PortWatchLogger(category: "ProcessTerminator")
    ) {
        self.signalExecutor = signalExecutor
        self.authenticationClient = authenticationClient
        self.helperClient = helperClient
        self.identityVerifier = identityVerifier
        self.logger = logger
    }

    public func terminate(entry: PortEntry, mode: TerminationMode) async throws -> ProcessTerminationResult {
        let signal = mode.signal
        logger.info("termination requested pid=\(entry.pid) signal=\(signal.rawValue) privilege=\(entry.privilegeLevel.rawValue)")
        switch await identityVerifier.verify(entry: entry) {
        case .matched:
            break
        case .mismatched(let reason):
            logger.error("termination blocked reason=identity_changed pid=\(entry.pid) detail=\(reason)")
            throw ProcessTerminationError.processIdentityChanged
        }
        switch entry.privilegeLevel {
        case .currentUser:
            do {
                try await signalExecutor.send(signal: signal, to: entry.pid)
            } catch {
                logger.error("termination signal failed pid=\(entry.pid) signal=\(signal.rawValue) error=\(sanitizedErrorDescription(error))")
                throw error
            }
            logger.info("termination signal sent pid=\(entry.pid) signal=\(signal.rawValue)")
            return ProcessTerminationResult(status: .signalSent, message: "\(signal.rawValue.uppercased()) sent to PID \(entry.pid)")
        case .otherUser, .rootOrSystem:
            let reason = "结束 \(entry.user) 进程 \(entry.processName) (PID \(entry.pid))"
            let authenticated: Bool
            do {
                authenticated = try await authenticationClient.authenticate(reason: reason)
            } catch ProcessTerminationError.authenticationCancelled {
                logger.info("authentication result pid=\(entry.pid) granted=false")
                logger.error("termination cancelled reason=authentication_cancelled pid=\(entry.pid)")
                throw ProcessTerminationError.authenticationCancelled
            }
            logger.info("authentication result pid=\(entry.pid) granted=\(authenticated)")
            guard authenticated else {
                logger.error("termination cancelled reason=authentication_cancelled pid=\(entry.pid)")
                throw ProcessTerminationError.authenticationCancelled
            }
            do {
                let result = try await helperClient.terminate(PrivilegedTerminationRequest(pid: entry.pid, signal: signal))
                logger.info("helper termination result pid=\(entry.pid) status=\(sanitizedTerminationStatus(result.status))")
                return result
            } catch {
                logger.error("helper termination failed pid=\(entry.pid) signal=\(signal.rawValue) error=\(sanitizedErrorDescription(error))")
                throw error
            }
        }
    }

    private func sanitizedErrorDescription(_ error: Error) -> String {
        guard let terminationError = error as? ProcessTerminationError else {
            return String(describing: type(of: error))
        }
        switch terminationError {
        case .authenticationCancelled:
            return "authenticationCancelled"
        case .processIdentityChanged:
            return "processIdentityChanged"
        case .unsupportedSignal:
            return "unsupportedSignal"
        case let .signalFailed(message):
            return "signalFailed(reason=\(ProcessTerminationError.signalFailureReason(from: message)))"
        }
    }

    private func sanitizedTerminationStatus(_ status: TerminationStatus) -> String {
        switch status {
        case .signalSent:
            return "signalSent"
        case .processAlreadyExited:
            return "processAlreadyExited"
        case .helperUnavailable:
            return "helperUnavailable"
        }
    }
}

extension ProcessTerminator: ProcessTerminating {}
