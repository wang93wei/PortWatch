import SwiftUI
import PortWatchCore

struct SettingsView: View {
    @Bindable var store: PortStore
    @State private var selectedColorSchemePreference: ColorSchemePreference = .automatic
    @State private var customRefreshSeconds = 3

    var body: some View {
        Form {
            Picker("外观", selection: $selectedColorSchemePreference) {
                ForEach(ColorSchemePreference.allCases, id: \.self) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            Picker("刷新间隔", selection: $store.refreshInterval) {
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
            selectedColorSchemePreference = store.colorSchemePreference
            if case let .custom(seconds) = store.refreshInterval {
                customRefreshSeconds = seconds
            }
        }
        .onChange(of: selectedColorSchemePreference) { _, newValue in
            store.requestColorSchemePreference(newValue)
        }
        .onChange(of: store.colorSchemePreference) { _, newValue in
            guard selectedColorSchemePreference != newValue else { return }
            selectedColorSchemePreference = newValue
        }
    }
}
