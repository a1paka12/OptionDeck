import AppKit
import CoreAudio
import DeckCore
import SystemBridge

enum ScriptFailure: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let message) = self { message } else { nil } }
}

/// Existing audio uses system controls. An idle Play opens the user's music app.
@MainActor
final class MediaController {
    private var openingPreferredApp = false
    var preferredApp: LauncherGuide?
    var preferredAppName: String { preferredApp?.name ?? (defaultMusicAppURL == nil ? "음악 앱 선택" : "YouTube Music") }

    var preferredAppURL: URL? {
        if let preferredApp {
            return DeckFeature.app(preferredApp).appURL
        }
        return defaultMusicAppURL
    }

    var defaultMusicAppURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Applications/Chrome Apps.localized/YouTube Music.app"),
            home.appendingPathComponent("Applications/YouTube Music.app"),
            URL(fileURLWithPath: "/Applications/YouTube Music.app")
        ]
        return candidates.first { url in
            guard let bundle = Bundle(url: url),
                  bundle.bundleIdentifier?.hasPrefix("com.google.Chrome.app.") == true,
                  let shortcut = bundle.object(forInfoDictionaryKey: "CrAppModeShortcutURL") as? String else { return false }
            return URL(string: shortcut)?.host == "music.youtube.com"
        }
    }

    /// This reads process output activity, not audio samples or protected Now Playing metadata.
    func outputActive() -> Bool? {
        guard #available(macOS 14.2, *) else { return nil }
        var list = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &list, 0, nil, &size) == noErr else { return nil }
        if size == 0 { return false }
        let capacity = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard capacity > 0, capacity < 8192 else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: capacity)
        let result = processes.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &list, 0, nil, &size, bytes.baseAddress!)
        }
        guard result == noErr else { return nil }
        var unknown = false
        for process in processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride) {
            var property = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var bytes = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(process, &property, 0, nil, &bytes, &value) != noErr { unknown = true; continue }
            if value != 0 { return true }
        }
        return unknown ? nil : false
    }

    func perform(_ command: Int, beforeOpening: () -> Void) async -> String? {
        switch MediaRoute.select(command: command, outputActive: outputActive()) {
        case .system:
            return ODMediaCommand(Int32(command)) ? nil : "현재 재생 앱이 이 조작을 지원하지 않아요"
        case .unavailable:
            return "재생 중인 항목이 없어요. 재생 버튼으로 \(preferredAppName)을 열 수 있어요"
        case .preferredApp:
            guard !openingPreferredApp else { return nil }
            guard let url = preferredAppURL else { return "\(preferredAppName) 앱을 찾지 못했어요. 음악 앱 설정에서 다시 선택해 주세요" }
            openingPreferredApp = true
            defer { openingPreferredApp = false }
            beforeOpening()
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
                return nil
            } catch { return "\(preferredAppName) 앱을 열지 못했어요" }
        }
    }
}
