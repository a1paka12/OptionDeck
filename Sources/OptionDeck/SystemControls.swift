import AppKit
import ApplicationServices
import CoreAudio
import SystemBridge
import DeckCore

@MainActor
final class SystemControls {
    private var device = AudioDeviceID(0)
    private var volumeElements: [AudioObjectPropertyElement] = []
    private(set) var display = CGMainDisplayID()

    func targetDisplay(_ screen: NSScreen?) {
        if let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            display = number.uint32Value
        }
    }

    func brightness() -> Double? {
        var value: Float = 0
        return ODGetBrightness(display, &value) ? Double(value) : nil
    }
    func setBrightness(_ value: Double) -> Bool { ODSetBrightness(display, Float(value)) }

    func audio() -> (volume: Double?, muted: Bool?) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            volumeElements = []; return (nil, nil)
        }
        volumeElements = [0, 1, 2].filter { element in
            var property = volumeProperty(element)
            var settable = DarwinBoolean(false)
            return AudioObjectHasProperty(device, &property) &&
                AudioObjectIsPropertySettable(device, &property, &settable) == noErr && settable.boolValue
        }
        if volumeElements.contains(0) { volumeElements = [0] }
        let values = volumeElements.compactMap { element -> Float? in
            var property = volumeProperty(element), value: Float = 0
            var bytes = UInt32(MemoryLayout<Float>.size)
            return AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &value) == noErr ? value : nil
        }
        var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted) == noErr
        let volume = values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
        return (volume, hasMute ? muted != 0 : nil)
    }

    func setVolume(_ value: Double) -> Bool {
        guard !volumeElements.isEmpty else { return false }
        var newValue = Float(value)
        var succeeded = true
        for element in volumeElements {
            var property = volumeProperty(element)
            let result = AudioObjectSetPropertyData(device, &property, 0, nil,
                UInt32(MemoryLayout<Float>.size), &newValue)
            succeeded = succeeded && result == noErr
        }
        return succeeded
    }
    func setMute(_ muted: Bool) -> Bool {
        var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &property, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
    private func volumeProperty(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    func openSystemMedia() async -> Bool {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.4)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
        }
        func find(_ element: AXUIElement, identifier: String, depth: Int = 0) -> AXUIElement? {
            guard depth < 5 else { return nil }
            if attribute(element, "AXIdentifier") as? String == identifier { return element }
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let result = find(child, identifier: identifier, depth: depth + 1) { return result }
            }
            return nil
        }
        if let nowPlaying = find(root, identifier: "com.apple.menuextra.nowplaying") {
            return AXUIElementPerformAction(nowPlaying, kAXPressAction as CFString) == .success
        }
        guard let controlCenter = find(root, identifier: "com.apple.menuextra.controlcenter") else { return false }
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if windows.isEmpty && AXUIElementPerformAction(controlCenter, kAXPressAction as CFString) != .success { return false }
        try? await Task.sleep(for: .milliseconds(180))
        // Prefer the native expanded Now Playing module if the OS exposes it.
        if let module = find(root, identifier: "controlcenter-nowplaying") {
            _ = AXUIElementPerformAction(module, kAXPressAction as CFString)
        }
        return !(attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).isEmpty
    }

    func sendShortcut(_ hint: MenuShortcut, to bundleIdentifier: String) async -> String? {
        guard AXIsProcessTrusted() else { return L("메뉴를 실행하려면 손쉬운 사용 권한이 필요해요") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { $0.processIdentifier == hint.pid }) else { return L("앱이 재실행됐어요. 단축키를 새로고침해 주세요") }
        app.activate()
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            return L("선택한 앱이 활성화되지 않아 명령을 보내지 않았어요")
        }
        return await Task.detached(priority: .userInitiated) { MenuShortcutReader.perform(hint) }.value
    }

}
