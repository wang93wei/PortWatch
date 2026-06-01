import SwiftUI

/// Applies the Liquid Glass button style on macOS 26+ and falls back to the
/// pre-Tahoe appearance on older runtimes. Apple HIG ("Adopting Liquid Glass")
/// recommends using the system button styles instead of layering custom
/// materials, so we just swap `.glass*` for `.bordered*` on older systems.
extension View {
    @ViewBuilder
    func applyTerminationButtonStyle(prominent: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Liquid Glass 菜单栏/工具栏风格的轻量按钮（macOS 26+），旧系统退到 `.borderless`。
    @ViewBuilder
    func applyMenuBarButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}

