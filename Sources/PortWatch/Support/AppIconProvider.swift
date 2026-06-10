import AppKit
import SwiftUI

/// 提供按文件路径获取 macOS 文件/App 图标的能力。
enum AppIconProvider {
    private static let iconCache = NSCache<NSString, NSImage>()

    /// 将可执行文件路径解析为对应的 .app bundle 路径（若可推断）。
    /// 例：`/Applications/QQ.app/Contents/MacOS/QQ` → `/Applications/QQ.app`
    static func appBundlePath(for executablePath: String) -> String? {
        let candidates = [
            executablePath,
            (executablePath as NSString).deletingLastPathComponent,
        ]
        for candidate in candidates where candidate.hasSuffix(".app") {
            return candidate
        }
        // 路径形如 .../Foo.app/Contents/MacOS/QQ ：回溯到 .app
        if let range = executablePath.range(of: ".app/") {
            return String(executablePath[..<range.upperBound])
        }
        return nil
    }

    /// 同步获取文件或 .app 的 NSImage 图标（主线程调用，系统有缓存）。
    static func icon(for path: String, size: CGFloat = 32) -> NSImage? {
        let lookupPath = appBundlePath(for: path) ?? path
        let cacheKey = "\(lookupPath)#\(size)" as NSString
        if let cachedImage = iconCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let image = (NSWorkspace.shared.icon(forFile: lookupPath).copy() as? NSImage)
        image?.size = NSSize(width: size, height: size)
        if let image {
            iconCache.setObject(image, forKey: cacheKey)
        }
        return image
    }
}

/// SwiftUI 便利视图：找不到图标时回退到 SF Symbol。
struct AppIconView: View {
    let path: String?
    var size: CGFloat = 32

    var body: some View {
        if let path, let nsImage = AppIconProvider.icon(for: path, size: size) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
