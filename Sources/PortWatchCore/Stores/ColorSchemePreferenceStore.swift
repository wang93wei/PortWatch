import Foundation

public protocol ColorSchemePreferenceStoring: AnyObject {
    func load() -> ColorSchemePreference
    func save(_ preference: ColorSchemePreference)
}

public final class UserDefaultsColorSchemePreferenceStore: ColorSchemePreferenceStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "colorSchemePreference"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ColorSchemePreference {
        guard let raw = defaults.string(forKey: key),
              let preference = ColorSchemePreference(rawValue: raw) else {
            return .defaultValue
        }
        return preference
    }

    public func save(_ preference: ColorSchemePreference) {
        defaults.set(preference.rawValue, forKey: key)
    }
}
