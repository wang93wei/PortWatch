import Foundation

public enum RefreshInterval: Hashable, Codable, Sendable {
    case preset(seconds: Int)
    case custom(seconds: Int)
    case paused

    public static let defaultValue: RefreshInterval = .preset(seconds: 3)
    public static let presets: [RefreshInterval] = [.preset(seconds: 1), .preset(seconds: 3), .preset(seconds: 5), .preset(seconds: 10), .paused]

    public var seconds: Int? {
        switch self {
        case let .preset(value), let .custom(value): return value
        case .paused: return nil
        }
    }

    public var label: String {
        switch self {
        case let .preset(value): return "\(value) 秒"
        case let .custom(value): return "自定义 \(value) 秒"
        case .paused: return "暂停"
        }
    }

    public static func validatedCustom(seconds: Int) -> RefreshInterval {
        .custom(seconds: min(max(seconds, 1), 60))
    }
}
