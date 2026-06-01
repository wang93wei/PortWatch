import AppKit
import SwiftUI
import PortWatchCore

@main
struct PortWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var portStore = PortStore()

    var body: some Scene {
        WindowGroup("PortWatch", id: "main") {
            RootView(store: portStore)
                .task {
                    portStore.startAutoRefresh()
                    await portStore.refreshNow()
                }
        }

        MenuBarExtra("PortWatch", systemImage: "network") {
            Text("PortWatch")
            Button("打开主窗口") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("刷新") {
                Task { await portStore.refreshNow() }
            }
            Divider()
            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }
}
