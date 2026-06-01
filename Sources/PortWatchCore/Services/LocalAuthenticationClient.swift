import Foundation
import LocalAuthentication

public protocol LocalAuthenticating: Sendable {
    func authenticate(reason: String) async throws -> Bool
}

public protocol LocalAuthenticationEvaluating: Sendable {
    func evaluate(reason: String) async throws -> Bool
}

public struct DeviceOwnerAuthenticationEvaluator: LocalAuthenticationEvaluating {
    public init() {}

    public func evaluate(reason: String) async throws -> Bool {
        let context = LAContext()
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

public struct LocalAuthenticationClient: LocalAuthenticating {
    private let evaluator: LocalAuthenticationEvaluating

    public init(evaluator: LocalAuthenticationEvaluating = DeviceOwnerAuthenticationEvaluator()) {
        self.evaluator = evaluator
    }

    public func authenticate(reason: String) async throws -> Bool {
        do {
            return try await evaluator.evaluate(reason: reason)
        } catch let error as NSError where error.isLocalAuthenticationCancellation {
            return false
        }
    }
}

private extension NSError {
    var isLocalAuthenticationCancellation: Bool {
        guard domain == LAError.errorDomain,
              let laCode = LAError.Code(rawValue: code) else {
            return false
        }
        switch laCode {
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            return true
        default:
            return false
        }
    }
}
