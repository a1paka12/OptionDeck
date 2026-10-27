import AppKit
import SwiftUI
import ApplicationServices
import DeckCore
import SystemBridge

private let syntheticEventTag: Int64 = 0x4F444543

private struct InputSnapshot: Sendable {
    let type: UInt32
    let flags: UInt64
    let keycode: Int64
    let button: Int
    let synthetic: Bool
}

private let eventCallback: CGEventTapCallBack = { _, type, event, _ in
    // Snapshot values before entering the actor. No borrowed C pointer or CGEvent
    // crosses an isolation boundary; the run-loop callback itself stays synchronous.
    let input = InputSnapshot(type: type.rawValue, flags: event.flags.rawValue,
        keycode: event.getIntegerValueField(.keyboardEventKeycode),
        button: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
        synthetic: event.getIntegerValueField(.eventSourceUserData) == syntheticEventTag)
    let suppress = MainActor.assumeIsolated {
        AppController.shared.event(input)
    }
    return suppress ? nil : Unmanaged.passUnretained(event)
}

private let contactCallback: ODFrameCallback = { pointer, count, time in
    // SystemBridge copies driver memory and delivers exclusively on the main queue.
    let contacts: [DeckContact]
    if let pointer, count > 0 {
        contacts = UnsafeBufferPointer(start: pointer, count: Int(count)).map {
            DeckContact(id: Int($0.identifier), point: DeckPoint($0.x, $0.y))
        }
    } else { contacts = [] }
    MainActor.assumeIsolated {
        AppController.shared.receive(contacts, time: time)
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()
    let model = DeckModel()
    private var panel: NSPanel?
    private var setup: NSWindow?
    private var settingsWindow: NSWindow?
    private var appObservers: [NSObjectProtocol] = []
    private var statusItem: NSStatusItem?
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var timer: Timer?
    private var engine = GestureEngine()
    private let cursorHold = CursorHold()
    private var pendingShow: Task<Void, Never>?
    private var holding = false
    private var clickedUntilLift = false
    private var cancelledUntilRelease = false
    private var suppressedMouseButtons: Set<Int> = []
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        model.onLanguageChange = { [weak self] in
            guard let self else { return }
            self.buildMenu()
            self.settingsWindow?.title = L("OptionDeck 설정")
            self.panel?.setAccessibilityLabel(L("OptionDeck 조절 패널"))
        }
        model.rawAvailable = ODTrackpadStart(contactCallback)
        model.onMusicSettings = { [weak self] in
            self?.showSettings(); self?.model.settingsTab = 3
        }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onClose = { [weak self] in self?.hide(commit: false) }
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            appObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { notification in
                let id = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                Task { @MainActor in AppController.shared.model.automaticShortcutRefresh(changedApp: id) }
            })
        }
        installEventTap()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            MainActor.assumeIsolated { AppController.shared.watchdog() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppController.shared.hide(commit: false) }
            }
        if !AXIsProcessTrusted() { showSetup() }
        else { showPreview() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cursorHold.end()
        pendingShow?.cancel(); timer?.invalidate()
        ODTrackpadStop()
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        for observer in appObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func buildMenu() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "option", accessibilityDescription: "OptionDeck")
        let menu = NSMenu()
        let title = NSMenuItem(title: "OptionDeck", action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        for (title, selector) in [(L("앱 및 배치 설정…"), #selector(showSettings)), (L("조절 패널 열기"), #selector(showPreview)), (L("입력 권한 및 사용 방법…"), #selector(showSetup))] {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("OptionDeck 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu; statusItem = item
    }

    private func installEventTap() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        eventTap = tap
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventSource { CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        model.inputReady = true
    }

    fileprivate func event(_ input: InputSnapshot) -> Bool {
        guard let type = CGEventType(rawValue: input.type) else { return false }
        let flags = CGEventFlags(rawValue: input.flags)
        if input.synthetic { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            hide(commit: false)
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }
        if type == .flagsChanged {
            let option = flags.contains(.maskAlternate)
            let conflicting = !flags.intersection([.maskCommand, .maskControl, .maskShift]).isEmpty
            if !option {
                cancelledUntilRelease = false
                pendingShow?.cancel(); pendingShow = nil
                if holding { hide(commit: true) }
            } else if conflicting {
                cancelledUntilRelease = true; hide(commit: false)
            } else if !cancelledUntilRelease && !holding && pendingShow == nil {
                pendingShow = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(160))
                    guard !Task.isCancelled, let self else { return }
                    self.pendingShow = nil
                    guard CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) else { return }
                    self.show(held: true)
                }
            }
            return false
        }
        if type == .keyDown {
            let code = input.keycode
            if holding && code == 53 { cancelledUntilRelease = true; hide(commit: false); return true }
            if holding && (code == 123 || code == 124) {
                engine.cancel(); model.changePage(model.page + (code == 123 ? -1 : 1)); return true
            }
            // Preserve Option-letter and other system/application shortcuts.
            if pendingShow != nil || holding { cancelledUntilRelease = true; hide(commit: false) }
            return false
        }
        let button = input.button
        if [.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(type), suppressedMouseButtons.remove(button) != nil { return true }
        guard holding, model.rawAvailable else { return false }
        if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) { cursorHold.pin() }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            suppressedMouseButtons.insert(button)
            if type == .leftMouseDown, let point = model.touchPoint,
               let target = DeckLayout.target(at: point, page: model.page, arrangement: model.arrangement), !target.isContinuous {
                clickedUntilLift = true; engine.cancel(); model.tap(target)
            }
            return true
        }
        return [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel].contains(type)
    }

    func receive(_ contacts: [DeckContact], time: Double) {
        guard holding else { return }
        model.touchPoint = contacts.count == 1 ? contacts.first?.point : nil
        if clickedUntilLift {
            if contacts.isEmpty { clickedUntilLift = false; engine.cancel() }
            return
        }
        for action in engine.update(contacts, time: time, page: model.page, arrangement: model.arrangement) { model.handle(action) }
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: DeckView(model: model))
        panel.setAccessibilityLabel(L("OptionDeck 조절 패널"))
        return panel
    }

    private func show(held: Bool) {
        let screen = currentScreen()
        model.refresh(screen: screen); model.preview = !held
        if panel == nil { panel = makePanel() }
        if let frame = screen?.visibleFrame {
            panel?.setFrameOrigin(NSPoint(x: frame.midX - 340, y: frame.midY - 230))
        }
        engine.cancel(); clickedUntilLift = false; holding = held
        if held && model.rawAvailable { cursorHold.begin() }
        ODTrackpadEnable(held && model.rawAvailable)
        model.panelVisible = true
        panel?.orderFrontRegardless()
    }

    @objc func showPreview() { hide(commit: false); show(held: false) }

    func hide(commit: Bool) {
        cursorHold.end()
        pendingShow?.cancel(); pendingShow = nil
        if commit { model.completeSession() }
        else { model.cancelSelection() }
        holding = false; clickedUntilLift = false; engine.cancel(); ODTrackpadEnable(false)
        model.touchPoint = nil; model.focused = nil
        model.panelVisible = false
        model.endPanelSession()
        panel?.orderOut(nil)
    }

    private func watchdog() {
        model.automaticShortcutRefresh()
        model.refreshMediaProgress()
        if !AXIsProcessTrusted() {
            if holding { hide(commit: false) }
            model.inputReady = false
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap)
                if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
                eventTap = nil; eventSource = nil
            }
        } else if eventTap == nil { installEventTap() }
        if holding && !CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) { hide(commit: true) }
        // Do not let a lost mouse-up suppress a later ordinary click indefinitely.
        suppressedMouseButtons = suppressedMouseButtons.filter {
            CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0)) ?? .left)
        }
    }

    @objc func showSettings() {
        hide(commit: false)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 740),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = L("OptionDeck 설정"); window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 980, height: 700)
            window.contentView = NSHostingView(rootView: DeckSettingsView(model: model))
            window.center(); settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate()
    }

    @objc func showSetup() {
        hide(commit: false)
        if setup == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 490),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "OptionDeck"; window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SetupView(model: model))
            window.center(); setup = window
        }
        setup?.makeKeyAndOrderFront(nil); NSApp.activate()
    }

    func renderPreview(to directory: String) throws {
        model.preview = true; model.rendering = true; model.refresh(screen: NSScreen.main)
        model.rawAvailable = false
        // Rendering performs no writes to audio, brightness, media or application state.
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            // ImageRenderer omits NSScrollView/native controls; cache the actual hosting view instead.
            for editorPage in 0..<4 {
                let settingsHost = NSHostingView(rootView: DeckSettingsView(model: model, page: editorPage)
                    .environment(\.colorScheme, dark ? .dark : .light))
                let settingsFrame = NSRect(x: 0, y: 0, width: 1000, height: 740)
                let settingsSnapshotWindow = NSWindow(contentRect: settingsFrame, styleMask: [.titled], backing: .buffered, defer: false)
                settingsSnapshotWindow.contentView = settingsHost
                settingsHost.frame = settingsFrame
                settingsHost.layoutSubtreeIfNeeded()
                settingsHost.displayIfNeeded()
                if let bitmap = settingsHost.bitmapImageRepForCachingDisplay(in: settingsHost.bounds) {
                    settingsHost.cacheDisplay(in: settingsHost.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: output.appendingPathComponent("settings-\(editorPage + 1)-\(dark ? "dark" : "light").png"))
                        if editorPage == 0 { try png.write(to: output.appendingPathComponent("settings-\(dark ? "dark" : "light").png")) }
                    }
                }
            }
            for page in 0..<2 {
                model.page = page
                if page == 1 { model.readPreviewShortcuts() }
                let view = DeckView(model: model).environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw ScriptFailure.failed(L("미리보기 이미지를 만들지 못했어요"))
                }
                try png.write(to: output.appendingPathComponent("page-\(page + 1)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    func diagnostics() {
        model.refresh(screen: NSScreen.main)
        let raw = ODTrackpadStart(contactCallback)
        let info: [String: Any] = [
            "accessibility": AXIsProcessTrusted(), "trackpadAPI": raw,
            "trackpadDeviceCount": ODTrackpadDeviceCount(),
            "displayBrightness": model.brightnessAvailable,
            "outputVolume": model.volumeAvailable, "outputMute": model.muteAvailable,
            "availableLaunchers": model.favorites.filter { $0.url != nil }.count,
            "preferredMusicApp": model.media.preferredAppURL?.path ?? "not found",
            "audioOutputActive": model.media.outputActive().map { $0 as Any } ?? "unknown",
            "note": "Read-only capability probe; no system values were changed."
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
        ODTrackpadStop()
    }

    func shortcutDiagnostics() {
        let data: [[String: Any]] = model.settings.launcherFeatures.compactMap(\.guide).map { guide in
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: guide.id).first
            let items = app.map { MenuShortcutReader.read(pid: $0.processIdentifier, applicationName: $0.localizedName ?? guide.name) } ?? []
            return ["app": guide.name, "running": app != nil, "count": items.count,
                    "examples": items.prefix(4).map { ["title": $0.title, "keys": $0.keys, "enabled": $0.enabled] }]
        }
        if let output = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: output, as: UTF8.self))
        }
    }
}

private struct SetupView: View {
    @Bindable var model: DeckModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "option").font(.system(size: 32, weight: .medium))
                .frame(width: 64, height: 64).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 7) {
                Text(L("손끝에서, 바로.")).font(.system(size: 27, weight: .bold))
                Text(L("Option을 누르는 동안 트랙패드가\n나만의 조절판으로 바뀝니다."))
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(3)
            }
            VStack(alignment: .leading, spacing: 13) {
                Label(L("한 손가락으로 위치를 골라 위아래로 조절"), systemImage: "hand.point.up")
                Label(L("두 손가락을 좌우로 밀어 페이지 전환"), systemImage: "hand.draw")
                Label(L("Option을 놓으면 원래 작업으로"), systemImage: "arrow.uturn.backward")
            }.font(.system(size: 12))
            Divider()
            HStack(spacing: 9) {
                Image(systemName: model.inputReady ? "checkmark.circle.fill" : "lock.shield")
                    .foregroundStyle(model.inputReady ? .green : .secondary)
                Text(model.inputReady ? L("입력 준비 완료") : L("전역 입력과 선택한 앱의 메뉴를 읽으려면 손쉬운 사용 권한이 필요해요"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button(L("패널 둘러보기")) { AppController.shared.showPreview() }
                Spacer()
                Button(model.inputReady ? L("시작하기") : L("권한 설정 열기")) {
                    if model.inputReady { NSApp.keyWindow?.close() }
                    else {
                        _ = ODRequestAccessibility()
                    }
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(30).frame(width: 440, height: 490).background(.background)
    }
}
