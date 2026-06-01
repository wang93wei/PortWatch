import SwiftUI
import PortWatchCore

struct SidebarView: View {
    @Bindable var store: PortStore

    var body: some View {
        List(selection: $store.selectedFilter) {
            ForEach(PortFilter.sidebarCases) { filter in
                Label(filter.title, systemImage: icon(for: filter))
                    .badge(count(for: filter))
                    .tag(filter)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PortWatch")
    }

    private func icon(for filter: PortFilter) -> String {
        switch filter {
        case .listening: return "network"
        case .favorites: return "star"
        case .privileged: return "lock.shield"
        case .development: return "hammer"
        case .externalConnections: return "point.3.connected.trianglepath.dotted"
        }
    }

    private func count(for filter: PortFilter) -> Int {
        filter.apply(to: store.entries, favoritePorts: store.favoritePorts, searchText: "").count
    }
}
