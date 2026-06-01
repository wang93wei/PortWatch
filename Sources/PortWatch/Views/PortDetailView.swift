import SwiftUI
import PortWatchCore

struct PortDetailView: View {
    let entry: PortEntry?
    @Bindable var store: PortStore

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        AppIconView(path: entry.executablePath, size: 40)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(entry.processName) · PID \(entry.pid)")
                                .font(.headline)
                            Text(entry.executablePath ?? "可执行路径不可用")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(entry.commandLine ?? "启动命令不可用")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Button("复制 lsof") {
                                PasteboardClient.copy("lsof -nP -iTCP:\(entry.port) -sTCP:LISTEN")
                            }
                            Button("复制 kill") {
                                PasteboardClient.copy("kill -TERM \(entry.pid)")
                            }
                        }
                    }
                    HStack {
                        Button("结束进程") {
                            Task { await store.terminate(entry: entry, mode: .graceful) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button("强制结束") {
                            store.requestForceTermination(for: entry)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
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
                    if entry.privilegeLevel != .currentUser {
                        Text("该进程属于 \(entry.user)，结束前需要 Touch ID、Apple Watch 或系统密码认证。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let message = store.lastTerminationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("选择一个端口", systemImage: "cursorarrow.click", description: Text("详情和操作会显示在这里"))
            }
        }
    }
}
