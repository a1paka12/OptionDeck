import Foundation

struct LauncherGuide: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var path: String? = nil
}

// Initial defaults only; user assignments are persisted by the Rust engine.
let launcherGuides: [LauncherGuide] = [
    .init(id: "com.google.Chrome", name: "Chrome"),
    .init(id: "com.microsoft.VSCode", name: "VS Code"),
    .init(id: "com.cmuxterm.app", name: "cmux"),
    .init(id: "com.apple.Safari", name: "Safari"),
    .init(id: "notion.id", name: "Notion"),
    .init(id: "com.apple.Terminal", name: "터미널"),
    .init(id: "com.apple.finder", name: "Finder"),
    .init(id: "com.apple.VoiceMemos", name: "음성 메모"),
    .init(id: "md.obsidian", name: "Obsidian")
]
