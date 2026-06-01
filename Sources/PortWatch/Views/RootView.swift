import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationSplitView {
            Text("监听端口")
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            ContentUnavailableView("PortWatch", systemImage: "network", description: Text("端口监控准备中"))
        }
        .frame(minWidth: 980, minHeight: 620)
    }
}
