import AppKit
import SwiftUI
import PortWatchCore

@main
struct PortWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("PortWatch", id: "main") {
            RootView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("刷新") {}
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra("PortWatch", systemImage: "network") {
            Text("PortWatch")
            Button("打开主窗口") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }
}
