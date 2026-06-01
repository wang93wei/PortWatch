import SwiftUI
import PortWatchCore

struct SettingsView: View {
    @Bindable var store: PortStore
    @State private var customRefreshSeconds = 3

    private var refreshSelection: Binding<RefreshInterval> {
        Binding(
            get: { store.refreshInterval },
            set: { store.setRefreshInterval($0) }
        )
    }

    var body: some View {
        Form {
            Picker("刷新间隔", selection: refreshSelection) {
                ForEach(RefreshInterval.presets, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
                Text("自定义").tag(RefreshInterval.validatedCustom(seconds: customRefreshSeconds))
            }
            Stepper("自定义：\(customRefreshSeconds) 秒", value: $customRefreshSeconds, in: 1...60)
                .onChange(of: customRefreshSeconds) { _, newValue in
                    store.setRefreshInterval(.validatedCustom(seconds: newValue))
                }
            if let error = store.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear {
            if case let .custom(seconds) = store.refreshInterval {
                customRefreshSeconds = seconds
            }
        }
    }
}
