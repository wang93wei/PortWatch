import SwiftUI
import PortWatchCore

struct RootView: View {
    @Bindable var store: PortStore
    @SceneStorage("selectedPortEntryID") private var selectedPortEntryID: String?

    private var selectedEntry: PortEntry? {
        store.filteredEntries.first { $0.id == selectedPortEntryID }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                PortTableView(store: store, selectedPortEntryID: $selectedPortEntryID)
                Divider()
                PortDetailView(entry: selectedEntry, store: store)
                    .frame(height: 150)
            }
        }
        .searchable(text: $store.searchText, prompt: "搜索端口、进程、PID、用户、路径")
        .frame(minWidth: 980, minHeight: 620)
    }
}
