import Foundation

public enum TerminationSignal: String, Codable, Sendable {
    case term
    case kill

    public var systemValue: Int32 {
        switch self {
        case .term: return SIGTERM
        case .kill: return SIGKILL
        }
    }
}

public enum TerminationMode: Equatable, Sendable {
    case graceful
    case force

    public var signal: TerminationSignal {
        switch self {
        case .graceful: return .term
        case .force: return .kill
        }
    }
}

public enum TerminationStatus: Equatable, Sendable {
    case signalSent
    case processAlreadyExited
    case helperUnavailable(String)
}

public struct ProcessTerminationResult: Equatable, Sendable {
    public let status: TerminationStatus
    public let message: String

    public init(status: TerminationStatus, message: String) {
        self.status = status
        self.message = message
    }
}

public enum ProcessTerminationError: LocalizedError, Equatable {
    case authenticationCancelled
    case processIdentityChanged
    case unsupportedSignal
    case signalFailed(String)

    public var errorDescription: String? {
        switch self {
        case .authenticationCancelled:
            return "已取消认证，未结束进程。"
        case .processIdentityChanged:
            return "进程信息已变化，请刷新后重新确认，未发送结束信号。"
        case .unsupportedSignal:
            return "不支持的结束信号。"
        case let .signalFailed(message):
            switch Self.signalFailureReason(from: message) {
            case "eperm":
                return "结束进程失败：权限不足。"
            case "esrch":
                return "进程已退出，请刷新列表。"
            case "einval":
                return "系统拒绝该结束信号。"
            default:
                return "结束进程失败，请刷新后重试。"
            }
        }
    }

    static func signalFailureReason(from message: String) -> String {
        let normalized = message.lowercased()
        if normalized.contains("eperm") || normalized.contains("operation not permitted") {
            return "eperm"
        }
        if normalized.contains("esrch") || normalized.contains("no such process") {
            return "esrch"
        }
        if normalized.contains("einval") || normalized.contains("invalid argument") {
            return "einval"
        }
        return "other"
    }
}
