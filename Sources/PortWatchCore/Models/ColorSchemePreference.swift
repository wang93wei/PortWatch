import Foundation
import SwiftUI

/// 用户对应用外观颜色模式的偏好。
public enum ColorSchemePreference: String, CaseIterable, Codable, Sendable {
    case automatic
    case light
    case dark

    public static let defaultValue: ColorSchemePreference = .automatic

    public var label: String {
        switch self {
        case .automatic: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// 映射到 SwiftUI 的 `ColorScheme?`：`automatic` 为 nil 表示跟随系统。
    public var swiftUIScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
