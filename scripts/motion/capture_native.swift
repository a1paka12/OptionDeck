import AppKit
import SwiftUI
import AVFoundation
import DeckCore

// This executable never orders a window onscreen and never installs an event tap.
// Device values below are preview inputs. Layout edits run the actual editor/Rust
// functions in a temporary source copy; capture_native.py isolates settings IO.
@main struct NativeFilm {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        let model = DeckModel()
        model.rendering = true; model.preview = false
        model.rawAvailable = true; model.inputReady = true
        model.refresh(screen: NSScreen.main)
        model.brightnessAvailable = true; model.volumeAvailable = true; model.muteAvailable = true
        model.brightness = 0.42; model.volume = 0.35
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 740), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let panel = NSHostingView(rootView: DeckView(model: model).environment(\.colorScheme, .dark))
        let editor = NSHostingView(rootView: DeckSettingsView(model: model).environment(\.colorScheme, .dark))
        panel.frame = NSRect(x: 160, y: 140, width: 680, height: 460)
        editor.frame = NSRect(x: 0, y: 0, width: 1000, height: 740)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 740))
        root.wantsLayer = true; root.layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.042, blue: 0.056, alpha: 1).cgColor
        window.contentView = root
        root.addSubview(panel)
        var editorVisible = false
        var events: [[String: Any]] = []
        func replay(_ command: String, _ more: [String: Any] = [:]) {
            var info = more; info["command"] = command
            NotificationCenter.default.post(name: .init("NativeFilmReplay"), object: nil, userInfo: info)
        }
        func step(_ command: String, at time: Double) { events.append(["time": time, "command": command]) }
        let frames = output.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        for index in 0..<450 {
            let t = Double(index) / 15
            if t < 8 {
                model.focused = t < 4.5 ? .brightness : .volume
                let progress = min(1, max(0, (t - 1.2) / 2.8))
                model.brightness = 0.42 + 0.36 * progress
                let volumeProgress = min(1, max(0, (t - 4.8) / 2.2))
                model.volume = 0.35 + 0.30 * volumeProgress
                if let rect = model.geometry?.rect(t < 4.5 ? "device:0" : "device:1", page: 0) {
                    let p = t < 4.5 ? progress : volumeProgress
                    model.touchPoint = .init((rect.x + rect.width * 0.55) / 680, (rect.y + rect.height * (0.68 - p * 0.35)) / 460)
                }
            }
            if index == 120 {
                model.page = 1; model.focused = .launch(6); model.selectedLauncher = 6; model.touchPoint = nil
                model.readPreviewShortcuts()
                // Only stable generic commands: exclude document/window titles.
                let generic: Set<String> = ["새로운 Finder 윈도우", "새 Finder 윈도우", "새로운 폴더", "정보 가져오기", "복사", "붙여넣기", "New Finder Window", "New Folder", "Get Info", "Copy", "Paste"]
                model.shortcuts = model.shortcuts.filter { generic.contains($0.title) }
                step("native second page", at: t)
            }
            if index == 180 {
                panel.removeFromSuperview(); root.addSubview(editor); editorVisible = true
                step("native layout editor", at: t)
            }
            if (210..<240).contains(index) {
                let p = Double(index - 210) / 29
                replay("ghost", ["x": 80 + p * 460, "y": 190.0, "target": "media:0"])
            }
            if index == 240 { replay("drop"); step("insert mute via actual drop function", at: t) }
            if index == 264 { replay("resize", ["columns": 3, "rows": 1]); step("resize via Rust layout", at: t) }
            if index == 282 { replay("resize", ["columns": 4, "rows": 1]) }
            if (300..<324).contains(index) {
                let p = Double(index - 300) / 23
                replay("outside", ["x": 600 - p * 540, "y": 190.0])
            }
            if index == 324 { replay("remove"); step("remove via actual editor function", at: t) }
            if index == 345 { model.settingsTab = 1; step("native second-page editor", at: t) }
            if index == 375 { model.settingsTab = 3; step("native music-app settings", at: t) }
            if index == 420 {
                editor.removeFromSuperview(); root.addSubview(panel); editorVisible = false
                model.page = 0; model.focused = .playback; model.touchPoint = nil
                step("native media panel", at: t)
            }
            // Advance only this process's run loop. The window remains offscreen.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0 / 60))
            root.layoutSubtreeIfNeeded()
            (editorVisible ? editor as NSView : panel as NSView).displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1480, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Native view capture unavailable") }
            bitmap.size = root.bounds.size
            root.cacheDisplay(in: root.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
            try png.write(to: frames.appendingPathComponent(String(format: "%04d.png", index)))
            if index % 75 == 0 { print("Native UI capture \(index)/450"); fflush(stdout) }
        }
        let manifest: [String: Any] = ["duration": 30, "fps": 15, "frames": 450, "capture": "Actual DeckView and DeckSettingsView offscreen; scripted preview inputs; no OS actions", "events": events]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("capture.json"))
        print("Captured 450 native SwiftUI frames without activating a window.")
    }
}
