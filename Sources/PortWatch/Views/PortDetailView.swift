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
                            // Text(verbatim:) 走 String init，完全跳过 LocalizedStringKey 路径，
                            // 避免数字被 NumberFormatter 按 locale 加千分位（22372 → 22,372）。
                            // 和 ca1c75f 修端口/PID 列的思路一致：禁用本地化数字格式。
                            Text(verbatim: "\(entry.processName) · PID \(entry.pid)")
                                .font(.headline)
                            // 只显示一行：可执行路径优先，缺失时回退到启动命令，再缺失显示占位文案。
                            Text(entry.executablePath ?? entry.commandLine ?? "路径不可用")
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
