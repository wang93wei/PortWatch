import Foundation

/// Identity 校验失败的具体原因。带 payload 让调用方 / 日志能精确指出哪个字段不匹配。
public enum IdentityMismatchReason: Equatable, Sendable {
    case processMissing
    case processNameMismatch(expected: String, actual: String)
    case userMismatch(expected: String, actual: String)
    case executablePathMismatch(expected: String, actual: String)
    case commandLineMismatch(expected: String, actual: String)
    case missingIdentityForComparison
}

extension IdentityMismatchReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .processMissing:
            return "processMissing"
        case let .processNameMismatch(expected, actual):
            return "processNameMismatch(expected=\(expected), actual=\(actual))"
        case let .userMismatch(expected, actual):
            return "userMismatch(expected=\(expected), actual=\(actual))"
        case let .executablePathMismatch(expected, actual):
            return "executablePathMismatch(expected=\(expected), actual=\(actual))"
        case let .commandLineMismatch(expected, actual):
            return "commandLineMismatch(expected=\(expected), actual=\(actual))"
        case .missingIdentityForComparison:
            return "missingIdentityForComparison"
        }
    }
}

public enum IdentityVerificationResult: Equatable, Sendable {
    case matched
    case mismatched(IdentityMismatchReason)
}

public protocol ProcessIdentityVerifying: Sendable {
    func verify(entry: PortEntry) async -> IdentityVerificationResult
}

public struct ProcessIdentityVerifier: ProcessIdentityVerifying {
    private let metadataProvider: ProcessMetadataProviding

    public init(metadataProvider: ProcessMetadataProviding = PSProcessMetadataProvider()) {
        self.metadataProvider = metadataProvider
    }

    public func verify(entry: PortEntry) async -> IdentityVerificationResult {
        // 1. ps 必须找得到进程
        guard let identity = await metadataProvider.identity(for: entry.pid) else {
            return .mismatched(.processMissing)
        }
        // 2. pid / processName / user 三项必须严格一致
        guard identity.pid == entry.pid else { return .mismatched(.processMissing) }
        if identity.processName != entry.processName {
            return .mismatched(.processNameMismatch(expected: entry.processName, actual: identity.processName))
        }
        if identity.user != entry.user {
            return .mismatched(.userMismatch(expected: entry.user, actual: identity.user))
        }
        // 3. 路径对比（沙盒降级：拿不到 actualPath 但其他三项一致 → 放行）
        if let expectedPath = entry.executablePath {
            let metadata = await metadataProvider.metadata(for: entry.pid)
            if let actualPath = metadata.executablePath ?? identity.executablePath {
                return expectedPath == actualPath
                    ? .matched
                    : .mismatched(.executablePathMismatch(expected: expectedPath, actual: actualPath))
            }
            // proc_pidpath 在 verify 时刻静默失败，但 pid/name/user 全一致 → 降级放行
            return .matched
        }
        // 4. commandLine 对比（拿不到 actualCommand 算 mismatch，宁严勿松）
        if let expectedCommand = entry.commandLine {
            let metadata = await metadataProvider.metadata(for: entry.pid)
            guard let actualCommand = metadata.commandLine else {
                return .mismatched(.commandLineMismatch(expected: expectedCommand, actual: "<unavailable>"))
            }
            return expectedCommand == actualCommand
                ? .matched
                : .mismatched(.commandLineMismatch(expected: expectedCommand, actual: actualCommand))
        }
        // 5. 两者皆无 → 无法安全比较
        return .mismatched(.missingIdentityForComparison)
    }
}
