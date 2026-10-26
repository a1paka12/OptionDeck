import AppKit
import DeckCore

struct DeckFeature: Codable, Equatable {
    enum Kind: String, Codable { case builtin, app, file, url, shortcut, empty }
    var kind: Kind
    var value: String
    var name: String
    var path: String?
    static let mediaDefaults: [DeckFeature] = [DeckControl.previous, .playback, .next, .systemMedia, .backwardSkip, .forwardSkip].map {
        .init(kind: .builtin, value: $0.featureKey, name: $0.title)
    }
    var isMediaWidget: Bool { kind == .builtin && value == "mediaWidget" }
    var cacheKey: String { "\(kind.rawValue):\(value):\(path ?? "")" }
    static let widget = DeckFeature(kind: .builtin, value: "mediaWidget", name: "미디어 재생")
    static let groupedDefaults: [DeckFeature] = [widget]
    static let library: [DeckFeature] = [
        .init(kind: .builtin, value: "brightness", name: "밝기"),
        .init(kind: .builtin, value: "volume", name: "볼륨"),
        .init(kind: .builtin, value: "mediaWidget", name: "미디어 재생"),
        .init(kind: .builtin, value: "mute", name: "음소거"),
        .init(kind: .builtin, value: "screenshot", name: "스크린샷 도구"),
        .init(kind: .app, value: "", name: "앱 실행"),
        .init(kind: .file, value: "", name: "파일 · 폴더"),
        .init(kind: .url, value: "", name: "웹사이트"),
        .init(kind: .shortcut, value: "", name: "macOS 단축어")
    ]
    static func app(_ guide: LauncherGuide) -> DeckFeature {
        .init(kind: .app, value: guide.id, name: guide.name, path: guide.path)
    }
    var guide: LauncherGuide? { kind == .app ? .init(id: value, name: name, path: path) : nil }
    var control: DeckControl? {
        guard kind == .builtin else { return nil }
        return [DeckControl.previous, .playback, .next, .systemMedia, .backwardSkip, .forwardSkip, .mute].first { $0.featureKey == value }
    }
    var symbol: String {
        switch kind {
        case .app: "app"
        case .file: "folder"
        case .url: "globe"
        case .shortcut: "square.stack.3d.up"
        case .empty: "plus"
        case .builtin: value == "brightness" ? "sun.max.fill" : (value == "volume" ? "speaker.wave.2.fill" : (value == "mediaWidget" ? "play.rectangle.fill" : (value == "screenshot" ? "camera.viewfinder" : (control?.symbol ?? "speaker.slash"))))
        }
    }
    @MainActor var appURL: URL? {
        guard kind == .app else { return nil }
        if let path, let bundle = Bundle(url: URL(fileURLWithPath: path)), bundle.bundleIdentifier == value {
            return bundle.bundleURL
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
    }
    @MainActor var icon: NSImage {
        if let url = appURL { return NSWorkspace.shared.icon(forFile: url.path) }
        if kind == .file { return NSWorkspace.shared.icon(forFile: value) }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
    }
}
extension DeckControl {
    var featureKey: String {
        switch self {
        case .previous: "previous"
        case .playback: "playback"
        case .next: "next"
        case .systemMedia: "systemMedia"
        case .backwardSkip: "backwardSkip"
        case .forwardSkip: "forwardSkip"
        case .mute: "mute"
        default: ""
        }
    }
}

@MainActor
final class FeatureRunner {
    private var runningShortcuts: Set<String> = []
    func perform(_ feature: DeckFeature) async -> String? {
        switch feature.kind {
        case .app:
            guard let url = feature.appURL else { return "앱을 찾지 못했어요. 설정에서 다시 할당해 주세요" }
            return await openApp(url)
        case .file:
            guard FileManager.default.fileExists(atPath: feature.value) else { return "파일이나 폴더를 찾지 못했어요" }
            return NSWorkspace.shared.open(URL(fileURLWithPath: feature.value)) ? nil : "파일을 열지 못했어요"
        case .url:
            guard let url = URL(string: feature.value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return "웹사이트 주소를 확인해 주세요" }
            return NSWorkspace.shared.open(url) ? nil : "웹사이트를 열지 못했어요"
        case .shortcut:
            guard !runningShortcuts.contains(feature.value) else { return "이 단축어는 이미 실행 중이에요" }
            runningShortcuts.insert(feature.value)
            defer { runningShortcuts.remove(feature.value) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", feature.value]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            let status: Int32 = await withCheckedContinuation { continuation in
                process.terminationHandler = { task in continuation.resume(returning: task.terminationStatus) }
                do { try process.run() } catch { continuation.resume(returning: -1) }
            }
            return status == 0 ? nil : "단축어를 실행하지 못했어요. 단축어 앱에서 이름과 권한을 확인해 주세요"
        case .builtin:
            guard feature.value == "screenshot", let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screenshot.launcher") else { return "이 기능을 실행하지 못했어요" }
            return await openApp(url)
        case .empty: return nil
        }
    }
    private func openApp(_ url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                continuation.resume(returning: error == nil ? nil : "앱을 실행하지 못했어요")
            }
        }
    }
}
