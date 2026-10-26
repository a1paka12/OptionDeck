// swift-tools-version: 6.0
import PackageDescription
import Foundation

let engineLibrary = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("engine/target/release").path

let package = Package(
    name: "OptionDeck",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OptionDeck", targets: ["OptionDeck"])],
    targets: [
        .target(name: "SystemBridge", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("Cocoa"), .linkedFramework("CoreGraphics")]),
        .target(name: "DeckCore"),
        .target(name: "DeckEngineBridge", publicHeadersPath: "include",
                linkerSettings: [.unsafeFlags(["-L", engineLibrary]), .linkedLibrary("deck_engine"), .linkedLibrary("iconv")]),
        .executableTarget(name: "OptionDeck", dependencies: ["SystemBridge", "DeckCore", "DeckEngineBridge"],
                          linkerSettings: [.linkedFramework("CoreAudio"), .linkedFramework("ApplicationServices")]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"])
    ]
)
