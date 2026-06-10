import AppKit
import SwiftUI
import PortWatchCore

struct MenuBarStatusView: View {
    @Bindable var store: PortStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("监听端口")
                Spacer()
                Text(verbatim: "\(store.listeningEntryCount)")
                    .fontWeight(.semibold)
            }
            HStack {
                Text("高权限进程")
                Spacer()
                Text(verbatim: "\(store.privilegedEntryCount)")
                    .fontWeight(.semibold)
            }
            Divider()
            ForEach(store.menuEntries) { entry in
                HStack {
                    Text(verbatim: "\(entry.port)")
                        .fontWeight(.semibold)
                    Text(entry.processName)
                    Spacer()
                    Text(verbatim: "PID \(entry.pid)")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Button("打开主窗口") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .applyMenuBarButtonStyle()
            Button(store.refreshInterval == .paused ? "恢复刷新" : "暂停刷新") {
                if store.refreshInterval == .paused {
                    store.setRefreshInterval(.defaultValue)
                } else {
                    store.setRefreshInterval(.paused)
                }
            }
            .applyMenuBarButtonStyle()
            Button("手动刷新") {
                Task { await store.refreshNow() }
            }
            .applyMenuBarButtonStyle()
            Button("退出") {
                NSApp.terminate(nil)
            }
            .applyMenuBarButtonStyle()
        }
        .padding(8)
        .frame(width: 320)
    }
}
