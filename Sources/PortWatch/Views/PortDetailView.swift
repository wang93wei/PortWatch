import SwiftUI
import PortWatchCore

struct PortDetailView: View {
    let entry: PortEntry?
    @Bindable var store: PortStore

    var body: some View {
        Group {
            if let entry {
                PortDetailContent(entry: entry, store: store)
            } else {
                ContentUnavailableView("选择一个端口", systemImage: "cursorarrow.click", description: Text("详情和操作会显示在这里"))
            }
        }
        // entry 切换（或首次出现）时清空 lastTerminationMessage，
        // 避免切到别的 entry 仍显示上次的 PID（"已发送 SIGTERM 到 PID 956" 但当前选中 71733）。
        .onAppear {
            store.entrySelectionChanged()
        }
        .onChange(of: entry?.id) { _, _ in
            store.entrySelectionChanged()
        }
    }
}

private struct PortDetailContent: View {
    let entry: PortEntry
    @Bindable var store: PortStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PortDetailHeader(
                processName: entry.processName,
                pid: entry.pid,
                port: entry.port,
                executablePath: entry.executablePath,
                commandLine: entry.commandLine
            )
            PortDetailActions(entry: entry, store: store)
            PrivilegeNotice(user: entry.user, privilegeLevel: entry.privilegeLevel)
            TerminationMessage(message: store.lastTerminationMessage)
        }
        .padding()
    }
}

private struct PortDetailHeader: View {
    let processName: String
    let pid: Int32
    let port: Int
    let executablePath: String?
    let commandLine: String?

    var body: some View {
        HStack(alignment: .top) {
            AppIconView(path: executablePath, size: 40)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                // Text(verbatim:) 走 String init，完全跳过 LocalizedStringKey 路径，
                // 避免数字被 NumberFormatter 按 locale 加千分位（22372 → 22,372）。
                Text(verbatim: "\(processName) · PID \(pid)")
                    .font(.headline)
                Text(executablePath ?? commandLine ?? "路径不可用")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button("复制 lsof") {
                    PasteboardClient.copy("lsof -nP -iTCP:\(port) -sTCP:LISTEN")
                }
                Button("复制 kill") {
                    PasteboardClient.copy("kill -TERM \(pid)")
                }
            }
        }
    }
}

private struct PortDetailActions: View {
    let entry: PortEntry
    @Bindable var store: PortStore

    var body: some View {
        HStack {
            Button("结束进程") {
                Task { await store.terminate(entry: entry, mode: .graceful) }
            }
            .tint(.red)
            .applyTerminationButtonStyle(prominent: true)

            Button("强制结束") {
                store.requestForceTermination(for: entry)
            }
            .tint(.red)
            .applyTerminationButtonStyle(prominent: false)
            .disabled(store.forceTerminationCandidate != PortStore.ForceTerminationCandidate(entry: entry))
            .confirmationDialog(
                "强制结束 \(entry.processName) (PID \(entry.pid))？",
                isPresented: Binding(
                    get: { store.pendingForceTerminationEntry?.id == entry.id },
                    set: { if !$0 { store.cancelForceTermination() } }
                )
            ) {
                Button("发送 SIGKILL", role: .destructive) {
                    Task { await store.terminate(entry: entry, mode: .force) }
                }
                Button("取消", role: .cancel) {
                    store.cancelForceTermination()
                }
            } message: {
                Text("SIGKILL 不允许进程自行清理资源。确认 PID、用户和路径无误后再继续。")
            }
            Spacer()
        }
    }
}

private struct PrivilegeNotice: View {
    let user: String
    let privilegeLevel: PrivilegeLevel

    var body: some View {
        if privilegeLevel != .currentUser {
            Text("该进程属于 \(user)，结束前需要 Touch ID、Apple Watch 或系统密码认证。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

private struct TerminationMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
