import Foundation

public enum MenuKeyEquivalent {
    public static func label(character: String?, virtualKey: Int?, modifiers: Int) -> String? {
        var key = character ?? ""
        if key == " " { key = "Space" }
        if let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 {
            switch scalar.value {
            case 0xF700: key = "↑"
            case 0xF701: key = "↓"
            case 0xF702: key = "←"
            case 0xF703: key = "→"
            case 0xF704...0xF726: key = "F\(scalar.value - 0xF704 + 1)"
            case 0x1B: key = "Esc"
            case 0x09: key = "⇥"
            case 0x0D, 0x03: key = "↩"
            case 0x08, 0x7F: key = "⌫"
            default: break
            }
        }
        if key.isEmpty, let virtualKey {
            // These are keyboard key names, not app-specific shortcut bindings.
            let names = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
                         117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑"]
            key = names[virtualKey] ?? ""
        }
        guard !key.isEmpty else { return nil }
        var parts: [String] = []
        // AX uses Carbon menu modifiers: 1=Shift, 2=Option, 4=Control,
        // 8=NO Command. A zero mask therefore means Command.
        if modifiers & 4 != 0 { parts.append("⌃") }
        if modifiers & 2 != 0 { parts.append("⌥") }
        if modifiers & 1 != 0 { parts.append("⇧") }
        if modifiers & 8 == 0 { parts.append("⌘") }
        parts.append(key.uppercased() == "SPACE" ? "Space" : key.uppercased())
        return parts.joined(separator: " ")
    }
}
