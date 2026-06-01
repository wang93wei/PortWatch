import SwiftUI
import PortWatchCore

struct PortTableView: View {
    @Bindable var store: PortStore
    @Binding var selectedPortEntryID: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Table(store.filteredEntries, selection: $selectedPortEntryID) {
                TableColumn("标记") { entry in
                    Button(store.favoritePorts.contains(entry.port) ? "★" : "☆") {
                        store.toggleFavorite(port: entry.port)
                    }
                    .buttonStyle(.plain)
                    .help(store.favoritePorts.contains(entry.port) ? "取消常用端口" : "标记为常用端口")
                }
                TableColumn("端口") { entry in Text("\(entry.port)").fontWeight(.semibold) }
                TableColumn("协议") { entry in Text(entry.protocolName.rawValue.uppercased()) }
                TableColumn("地址") { entry in Text(entry.address) }
                TableColumn("进程") { entry in Text(entry.processName) }
                TableColumn("PID") { entry in Text("\(entry.pid)") }
                TableColumn("用户") { entry in Text(entry.user) }
                TableColumn("路径") { entry in Text(entry.executablePath ?? "不可用").foregroundStyle(.secondary) }
                TableColumn("操作") { entry in
                    Button("复制") {
                        PasteboardClient.copy("lsof -nP -iTCP:\(entry.port) -sTCP:LISTEN")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .contextMenu(forSelectionType: String.self) { selection in
                Button("标记/取消常用") {
                    selection.compactMap(entry(for:)).forEach { store.toggleFavorite(port: $0.port) }
                }
                Button("结束进程") {
                    selection.compactMap(entry(for:)).first.map { selectedEntry in
                        Task { await store.terminate(entry: selectedEntry, mode: .graceful) }
                    }
                }
                Button("复制 lsof 命令") {
                    selection.compactMap(entry(for:)).first.map {
                        PasteboardClient.copy("lsof -nP -iTCP:\($0.port) -sTCP:LISTEN")
                    }
                }
                Button("复制 TERM 命令") {
                    selection.compactMap(entry(for:)).first.map {
                        PasteboardClient.copy("kill -TERM \($0.pid)")
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text(store.selectedFilter.title)
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Picker("刷新间隔", selection: Binding(
                get: { store.refreshInterval },
                set: { store.setRefreshInterval($0) }
            )) {
                ForEach(RefreshInterval.presets, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
                if case let .custom(seconds) = store.refreshInterval {
                    Text("自定义 \(seconds) 秒").tag(RefreshInterval.custom(seconds: seconds))
                }
            }
            .labelsHidden()
            .frame(width: 120)
            Button("刷新") {
                Task { await store.refreshNow() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding()
    }

    private func entry(for id: String) -> PortEntry? {
        store.entries.first { $0.id == id }
    }
}
