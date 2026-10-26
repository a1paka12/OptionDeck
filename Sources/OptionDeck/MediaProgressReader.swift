import AppKit
import ApplicationServices

struct MediaProgress: Sendable {
    let pid: Int32
    let path: [Int]
    let label: String
    let identity: String
    let minimum: Double
    let maximum: Double
    let value: Double
    let canSeek: Bool
    var fraction: Double { min(1, max(0, (value - minimum) / (maximum - minimum))) }
}

enum MediaProgressReader {
    private static func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
    }
    private static func children(_ node: AXUIElement) -> [AXUIElement] {
        attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    static func read(pid: Int32, windowFilter: String?, enableAccessibility: Bool = false) -> MediaProgress? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        if enableAccessibility {
            // Chromium web content may be lazy; request the app's accessibility tree.
            if AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) != .success {
                _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.45
        var budget = 350
        func walk(_ node: AXUIElement, path: [Int]) -> MediaProgress? {
            guard budget > 0, path.count < 18, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            budget -= 1
            if attribute(node, kAXRoleAttribute) as? String == kAXSliderRole {
                let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { attribute(node, $0) as? String }.joined(separator: " ").lowercased()
                let terms = ["progress", "seek", "playback position", "재생 위치", "재생 진행", "탐색", "재생헤드", "타임라인"]
                if terms.contains(where: title.contains),
                   let value = (attribute(node, kAXValueAttribute) as? NSNumber)?.doubleValue,
                   let low = (attribute(node, kAXMinValueAttribute) as? NSNumber)?.doubleValue,
                   let high = (attribute(node, kAXMaxValueAttribute) as? NSNumber)?.doubleValue,
                   value.isFinite, low.isFinite, high.isFinite, high > low {
                    var writable = DarwinBoolean(false)
                    AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &writable)
                    let label = attribute(node, kAXValueDescriptionAttribute) as? String ?? ""
                    return .init(pid: pid, path: path, label: label, identity: title, minimum: low, maximum: high, value: value, canSeek: writable.boolValue)
                }
            }
            for (index, child) in children(node).enumerated() {
                if let value = walk(child, path: path + [index]) { return value }
            }
            return nil
        }
        for (index, window) in windows.enumerated() {
            if let windowFilter, !(attribute(window, kAXTitleAttribute) as? String ?? "").localizedCaseInsensitiveContains(windowFilter) { continue }
            if let result = walk(window, path: [index]) { return result }
        }
        return nil
    }
    static func seek(_ progress: MediaProgress, fraction: Double) -> Bool {
        guard progress.canSeek, fraction.isFinite, AXIsProcessTrusted(), let first = progress.path.first else { return false }
        let app = AXUIElementCreateApplication(progress.pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard windows.indices.contains(first) else { return false }
        var node = windows[first]
        for index in progress.path.dropFirst() {
            let items = children(node)
            guard items.indices.contains(index) else { return false }
            node = items[index]
        }
        let identity = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { attribute(node, $0) as? String }.joined(separator: " ").lowercased()
        guard identity == progress.identity, attribute(node, kAXRoleAttribute) as? String == kAXSliderRole,
              (attribute(node, kAXMinValueAttribute) as? NSNumber)?.doubleValue == progress.minimum,
              (attribute(node, kAXMaxValueAttribute) as? NSNumber)?.doubleValue == progress.maximum else { return false }
        let value = progress.minimum + min(1, max(0, fraction)) * (progress.maximum - progress.minimum)
        return AXUIElementSetAttributeValue(node, kAXValueAttribute as CFString, value as CFNumber) == .success
    }
}
