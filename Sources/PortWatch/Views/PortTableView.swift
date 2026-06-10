import SwiftUI
import PortWatchCore

struct PortTableView: View {
    @Bindable var store: PortStore
    @Binding var selectedPortEntryID: String?

    var body: some View {
        VStack(spacing: 0) {
            Table(store.filteredEntries, selection: $selectedPortEntryID) {
                TableColumn("端口") { entry in Text(String(entry.port)).fontWeight(.semibold) }
                TableColumn("协议") { entry in Text(entry.protocolName.rawValue.uppercased()) }
                TableColumn("地址") { entry in Text(entry.address) }
                TableColumn("进程") { entry in Text(entry.processName) }
                TableColumn("PID") { entry in Text(String(entry.pid)) }
                TableColumn("用户") { entry in Text(entry.user) }
                TableColumn("路径") { entry in
                    HStack(spacing: 6) {
                        AppIconView(path: entry.executablePath, size: 16)
                        Text(entry.executablePath ?? "不可用")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 列宽要声明在 TableColumn 上，cell 的 frame 不会稳定影响启动时的默认列宽。
                .width(min: 360, ideal: 500, max: .infinity)
            }
            .contextMenu(forSelectionType: String.self) { selection in
                Button("结束进程") {
                    if let selectedEntry = selection.compactMap(entry(for:)).first {
                        Task { await store.terminate(entry: selectedEntry, mode: .graceful) }
                    }
                }
                Button("复制 lsof 命令") {
                    if let selectedEntry = selection.compactMap(entry(for:)).first {
                        PasteboardClient.copy("lsof -nP -iTCP:\(selectedEntry.port) -sTCP:LISTEN")
                    }
                }
                Button("复制 TERM 命令") {
                    if let selectedEntry = selection.compactMap(entry(for:)).first {
                        PasteboardClient.copy("kill -TERM \(selectedEntry.pid)")
                    }
                }
            }
        }
        // 使用系统 toolbar API，让 SwiftUI 自动渲染 Liquid Glass 风格的工具栏
        // (Adopting Liquid Glass 文档：reduce custom backgrounds in toolbars)。
        .toolbar {
            // 控件集中在 trailing，Picker 用 .menu 风格让下拉箭头自然显示
            ToolbarItemGroup(placement: .primaryAction) {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                Picker("刷新间隔", selection: $store.refreshInterval) {
                    ForEach(RefreshInterval.presets, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                    if case let .custom(seconds) = store.refreshInterval {
                        Text("自定义 \(seconds) 秒").tag(RefreshInterval.custom(seconds: seconds))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help("设置自动刷新间隔")
                Button("刷新") {
                    Task { await store.refreshNow() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("立即刷新当前端口列表 (⌘R)")
            }
        }
    }

    private func entry(for id: String) -> PortEntry? {
        store.entries.first { $0.id == id }
    }
}
