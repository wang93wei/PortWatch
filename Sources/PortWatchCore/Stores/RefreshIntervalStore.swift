import Foundation

public protocol RefreshIntervalStoring: AnyObject {
    func load() -> RefreshInterval
    func save(_ interval: RefreshInterval)
}

public final class UserDefaultsRefreshIntervalStore: RefreshIntervalStoring {
    private let defaults: UserDefaults
    private let modeKey: String
    private let secondsKey: String

    public init(
        defaults: UserDefaults = .standard,
        modeKey: String = "refreshIntervalMode",
        secondsKey: String = "refreshIntervalSeconds"
    ) {
        self.defaults = defaults
        self.modeKey = modeKey
        self.secondsKey = secondsKey
    }

    public func load() -> RefreshInterval {
        let seconds = defaults.integer(forKey: secondsKey)
        switch defaults.string(forKey: modeKey) {
        case "paused":
            return .paused
        case "custom":
            return .validatedCustom(seconds: seconds == 0 ? 3 : seconds)
        case "preset":
            return .preset(seconds: seconds == 0 ? 3 : seconds)
        default:
            return .defaultValue
        }
    }

    public func save(_ interval: RefreshInterval) {
        switch interval {
        case let .preset(seconds):
            defaults.set("preset", forKey: modeKey)
            defaults.set(seconds, forKey: secondsKey)
        case let .custom(seconds):
            defaults.set("custom", forKey: modeKey)
            defaults.set(seconds, forKey: secondsKey)
        case .paused:
            defaults.set("paused", forKey: modeKey)
        }
    }
}
