import SwiftUI
import PortWatchCore

struct PortDetailView: View {
    let entry: PortEntry?
    @Bindable var store: PortStore

    var body: some View {
        Group {
            if let entry {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(entry.processName) · PID \(entry.pid)")
                            .font(.headline)
                        Text(entry.executablePath ?? "可执行路径不可用")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(entry.commandLine ?? "启动命令不可用")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("复制 lsof") {
                        PasteboardClient.copy("lsof -nP -iTCP:\(entry.port) -sTCP:LISTEN")
                    }
                    Button("复制 kill") {
                        PasteboardClient.copy("kill -TERM \(entry.pid)")
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("选择一个端口", systemImage: "cursorarrow.click", description: Text("详情和操作会显示在这里"))
            }
        }
    }
}
