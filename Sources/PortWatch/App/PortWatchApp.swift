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
            MenuBarStatusView(store: portStore)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: portStore)
        }
    }
}
