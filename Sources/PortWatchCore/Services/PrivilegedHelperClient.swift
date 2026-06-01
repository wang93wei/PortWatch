import Foundation

public struct PrivilegedTerminationRequest: Equatable, Sendable {
    public let pid: Int32
    public let signal: TerminationSignal

    public init(pid: Int32, signal: TerminationSignal) {
        self.pid = pid
        self.signal = signal
    }
}

public protocol PrivilegedHelperClienting: Sendable {
    func terminate(_ request: PrivilegedTerminationRequest) async throws -> ProcessTerminationResult
}

public struct UnavailablePrivilegedHelperClient: PrivilegedHelperClienting {
    public init() {}

    public func terminate(_ request: PrivilegedTerminationRequest) async throws -> ProcessTerminationResult {
        ProcessTerminationResult(
            status: .helperUnavailable("高权限 helper 尚未安装或未批准"),
            message: "需要安装并批准 PortWatch Helper 后才能结束其他用户或系统进程。"
        )
    }
}
