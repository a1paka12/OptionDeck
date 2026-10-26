import Foundation
import ApplicationServices
import DeckCore

struct MenuShortcut: Sendable, Identifiable {
    let pid: Int32
    let path: [Int]
    let title: String
    let keys: String
    let category: String
    let enabled: Bool
    var id: String { "\(pid):" + path.map(String.init).joined(separator: "/") }
}

enum MenuShortcutReader {
    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func equivalent(_ element: AXUIElement) -> String? {
        let char = attribute(element, kAXMenuItemCmdCharAttribute) as? String
        let virtual = (attribute(element, kAXMenuItemCmdVirtualKeyAttribute) as? NSNumber)?.intValue
        guard let modifiers = (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue else { return nil }
        return MenuKeyEquivalent.label(character: char, virtualKey: virtual, modifiers: modifiers)
    }

    static func read(pid: Int32, applicationName: String) -> [MenuShortcut] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        guard let raw = attribute(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return [] }
        let bar = unsafeDowncast(raw, to: AXUIElement.self)
        var results: [MenuShortcut] = []
        var count = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        func walk(_ node: AXUIElement, path: [Int], category: String) {
            guard path.count <= 8, count < 400, results.count < 96,
                  ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return }
            count += 1
            let title = attribute(node, kAXTitleAttribute) as? String ?? ""
            if !title.isEmpty, let key = equivalent(node) {
                let enabled = attribute(node, kAXEnabledAttribute) as? Bool ?? false
                results.append(.init(pid: pid, path: path, title: title, keys: key, category: category, enabled: enabled))
            }
            for (index, child) in children(node).enumerated() { walk(child, path: path + [index], category: category) }
        }
        let menus = children(bar)
        for (index, menu) in menus.enumerated() {
            // The first macOS menu is the system Apple menu, not this app's commands.
            guard index > 0 else { continue }
            let title = attribute(menu, kAXTitleAttribute) as? String ?? ""
            // Defer the generic app menu (Hide/Quit) behind task-related menus.
            if !title.isEmpty && applicationName.localizedCaseInsensitiveContains(title) { continue }
            walk(menu, path: [index], category: title)
        }
        // Keep disabled commands visible but prefer commands executable now.
        return results.enumerated().sorted {
            $0.element.enabled == $1.element.enabled ? $0.offset < $1.offset : $0.element.enabled
        }.map(\.element)
    }

    static func perform(_ shortcut: MenuShortcut) -> String? {
        let app = AXUIElementCreateApplication(shortcut.pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let raw = attribute(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return "선택한 앱의 메뉴를 읽지 못했어요" }
        var node = unsafeDowncast(raw, to: AXUIElement.self)
        for index in shortcut.path {
            let items = children(node)
            guard items.indices.contains(index) else { return "메뉴가 바뀌었어요. 단축키를 새로고침해 주세요" }
            node = items[index]
        }
        guard attribute(node, kAXTitleAttribute) as? String == shortcut.title,
              equivalent(node) == shortcut.keys else { return "메뉴가 바뀌었어요. 단축키를 새로고침해 주세요" }
        guard attribute(node, kAXEnabledAttribute) as? Bool == true else { return "이 명령은 현재 앱 상태에서 사용할 수 없어요" }
        return AXUIElementPerformAction(node, kAXPressAction as CFString) == .success ? nil : "앱이 메뉴 명령 실행을 허용하지 않았어요"
    }
}
