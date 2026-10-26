import AppKit
import ApplicationServices
import Observation
import DeckCore
import SystemBridge
import DeckEngineBridge

struct AppItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let url: URL?
    let subtitle: String
}

@MainActor
@Observable
final class DeckModel {
    var settings = DeckSettings()
    var geometry: DeckGeometry?
    var settingsRevision: UInt64 = 0
    var settingsError: String?
    var panelVisible = false
    var mediaProgress: MediaProgress?
    var pendingSeek: Double?
    private var progressTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var lastProgressRead = 0.0
    private var accessibilityRequested: Set<Int32> = []
    var settingsTab = 0
    var onMusicSettings: (() -> Void)?
    var onSettings: (() -> Void)?
    private var lastAutomaticRefresh = 0.0
    init() {
        do {
            let document = try SettingsEngine.load()
            settings = document.settings; settingsRevision = document.revision
            media.preferredApp = settings.music_app
            geometry = try DeckGeometry(settings: settings)
        } catch { settingsError = error.localizedDescription }
    }
    var arrangement: DeckArrangement {
        geometry?.arrangement(settings: settings) ?? .init()
    }
    func feature(for control: DeckControl) -> DeckFeature? {
        if case .feature(let index) = control { return settings.mediaFeatures[index] }
        if case .launch(let index) = control { return settings.launcherFeatures[index] }
        return nil
    }
    func reloadSettings() throws {
        let document = try SettingsEngine.load()
        applySettings(document)
    }
    func saveSettings(_ value: DeckSettings, revision: UInt64) throws {
        applySettings(try SettingsEngine.save(value, revision: revision))
    }
    private func applySettings(_ document: SettingsDocument) {
        shortcutTask?.cancel(); shortcutTask = nil; _ = od_shortcut_advance(); pendingShortcut = nil; pendingFeature = nil; shortcutCache = [:]
        settings = document.settings; settingsRevision = document.revision; settingsError = nil
        progressTask?.cancel(); progressTask = nil; seekTask?.cancel(); pendingSeek = nil; mediaProgress = nil; lastProgressRead = 0
        media.preferredApp = settings.music_app
        geometry = try? DeckGeometry(settings: settings)
        focused = nil; touchPoint = nil; shortcuts = []; shortcutPage = 0
        refresh(screen: NSScreen.main)
    }
    func automaticShortcutRefresh(changedApp: String? = nil) {
        guard settings.automatic_shortcuts else { return }
        if let changedApp { shortcutCache[changedApp] = nil }
        guard panelVisible, page == 1, pendingShortcut == nil, pendingFeature == nil else { return }
        if case .shortcut = focused { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard shortcutTask == nil, changedApp == selectedGuide.id || now - lastAutomaticRefresh >= 5 else { return }
        lastAutomaticRefresh = now
        loadShortcuts(force: true, background: true)
    }
    var page = 0
    var focused: DeckControl?
    var touchPoint: DeckPoint?
    var brightness = 0.0
    var volume = 0.0
    var muted = false
    var brightnessAvailable = false
    var volumeAvailable = false
    var muteAvailable = false
    var rawAvailable = false
    var inputReady = false
    var preview = false
    var rendering = false
    var message: String?
    var favorites: [AppItem] = []
    var selectedLauncher = 0
    var shortcuts: [MenuShortcut] = []
    var shortcutPage = 0
    var shortcutStatus = "선택한 앱의 메뉴를 읽는 중…"
    let media = MediaController()
    let system = SystemControls()
    let haptics = Haptics()
    var onClose: (() -> Void)?
    private var messageGeneration = 0
    private let featureRunner = FeatureRunner()
    private var pendingFeature: DeckFeature?
    private var pendingShortcut: (guide: LauncherGuide, hint: MenuShortcut)?
    private var shortcutTask: Task<Void, Never>?
    private var shortcutCache: [String: (pid: Int32, time: Double, items: [MenuShortcut])] = [:]

    var selectedGuide: LauncherGuide {
        guard settings.launcherFeatures.indices.contains(selectedLauncher) else { return .init(id: "", name: "빠른 동작") }
        return settings.launcherFeatures[selectedLauncher].guide ?? .init(id: "", name: "빠른 동작")
    }
    var shortcutHeading: String { selectedGuide.id.isEmpty ? "앱을 선택하면 메뉴 단축키가 표시됩니다" : "\(selectedGuide.name) 메뉴 단축키" }
    var visibleShortcuts: [MenuShortcut] { Array(shortcuts.dropFirst(shortcutPage * 4).prefix(4)) }

    func refresh(screen: NSScreen?) {
        system.targetDisplay(screen)
        if let value = system.brightness() { brightness = value; brightnessAvailable = true }
        else { brightnessAvailable = false }
        let audio = system.audio()
        volumeAvailable = audio.volume != nil; muteAvailable = audio.muted != nil
        volume = audio.volume ?? 0; muted = audio.muted ?? false
        favorites = settings.launcherFeatures.map { feature in
            let url = feature.appURL
            let subtitle = feature.kind == .app ? (url == nil ? "설치되지 않음" : "탭하여 열기") : (feature.kind == .empty ? "설정에서 기능 추가" : "탭하여 실행")
            return AppItem(id: feature.value, name: feature.name, icon: feature.icon, url: url, subtitle: subtitle)
        }
        if page == 1 { loadShortcuts() }
    }

    func focus(_ control: DeckControl?) {
        if focused != control, control != nil { haptics.selection() }
        focused = control
        if case .shortcut = control { shortcutTask?.cancel(); shortcutTask = nil; _ = od_shortcut_advance() }
        if case .launch(let index) = control, index != selectedLauncher {
            selectedLauncher = index; pendingShortcut = nil; pendingFeature = nil; loadShortcuts()
        }
    }
    func changePage(_ destination: Int) {
        let next = min(1, max(0, destination))
        if next != page { haptics.selection() }
        page = next; focused = nil; pendingShortcut = nil; pendingFeature = nil
        if page == 1 { loadShortcuts() }
    }
    func handle(_ action: DeckAction) {
        switch action {
        case .focus(let control): focus(control)
        case .adjust(let control, let delta): adjust(control, by: delta)
        case .tap(let control): tap(control)
        case .page(let destination): changePage(destination)
        case .end: break
        case .cancel: cancelSelection()
        }
    }
    func adjust(_ control: DeckControl, by delta: Double) {
        switch control {
        case .brightness where brightnessAvailable:
            let next = min(1, max(0, brightness + delta))
            if system.setBrightness(next) { haptics.adjustment(from: brightness, to: next); brightness = next }
            else { notify("이 화면의 밝기를 변경하지 못했어요") }
        case .mediaSeek:
            if let progress = mediaProgress, progress.canSeek { queueSeek((pendingSeek ?? progress.fraction) + delta) }
        case .volume where volumeAvailable:
            let next = min(1, max(0, volume + delta))
            if system.setVolume(next) { haptics.adjustment(from: volume, to: next); volume = next }
            else { notify("이 출력 장치의 볼륨을 변경하지 못했어요") }
        default: break
        }
    }
    func tap(_ control: DeckControl) {
        haptics.action()
        switch control {
        case .mute:
            if muteAvailable && system.setMute(!muted) { muted.toggle() }
            else { notify("이 출력 장치는 음소거를 지원하지 않아요") }
        case .previous: mediaCommand(5)
        case .playback: mediaCommand(2)
        case .next: mediaCommand(4)
        case .backwardSkip: mediaCommand(12)
        case .forwardSkip: mediaCommand(13)
        case .systemMedia:
            onClose?()
            Task { if !(await system.openSystemMedia()) { notify("제어 센터를 열지 못했어요. 손쉬운 사용 권한을 확인해 주세요") } }
        case .previousPage: changePage(page - 1)
        case .nextPage: changePage(page + 1)
        case .feature(let index):
            if settings.mediaFeatures.indices.contains(index) { executeFeature(settings.mediaFeatures[index]) }
        case .launch(let index):
            guard settings.launcherFeatures.indices.contains(index) else { return }
            selectedLauncher = index; pendingShortcut = nil; loadShortcuts()
            executeFeature(settings.launcherFeatures[index])
        case .shortcut(let index):
            guard visibleShortcuts.indices.contains(index), visibleShortcuts[index].enabled else { return }
            pendingFeature = nil
            pendingShortcut = (selectedGuide, visibleShortcuts[index])
            if preview { completeSession() }
            else { notify("⌥ 놓으면 \(selectedGuide.name)에 실행 · Esc로 취소") }
        case .moreShortcuts:
            shortcutPage = (shortcutPage + 1) % max(1, (shortcuts.count + 3) / 4)
        case .refreshShortcuts: loadShortcuts(force: true)
        default: break
        }
    }

    private func executeFeature(_ feature: DeckFeature) {
        pendingShortcut = nil; pendingFeature = nil
        if let control = feature.control { tap(control); return }
        guard feature.kind != .empty else { return }
        pendingFeature = feature
        if preview { completeSession(); onClose?() }
        else { notify("⌥ 놓으면 \(feature.name) 실행 · Esc로 취소") }
    }
    func completeSession() {
        if let feature = pendingFeature {
            pendingFeature = nil
            Task {
                if let error = await featureRunner.perform(feature) { notify(error) }
                if feature.kind == .app, selectedGuide.id == feature.value { loadShortcuts(force: true) }
            }
            return
        }
        guard let pending = pendingShortcut else { return }
        pendingShortcut = nil
        Task {
            if let error = await system.sendShortcut(pending.hint, to: pending.guide.id) { notify(error) }
        }
    }
    func cancelSelection() { pendingShortcut = nil; pendingFeature = nil; focused = nil; touchPoint = nil }
    func loadShortcuts(force: Bool = false, background: Bool = false) {
        shortcutTask?.cancel()
        let ticket = od_shortcut_advance()
        if !background { shortcutPage = 0 }
        let guide = selectedGuide
        guard !guide.id.isEmpty else { shortcutTask = nil; shortcuts = []; shortcutStatus = "앱 실행이 할당된 칸을 가리키면 메뉴 단축키가 표시돼요"; return }
        guard AXIsProcessTrusted() else { shortcutTask = nil; shortcuts = []; shortcutStatus = "손쉬운 사용을 허용하면 실제 메뉴 단축키를 읽어요"; return }
        guard let app = runningApplication(for: guide) else {
            shortcutTask = nil; shortcuts = []; shortcutStatus = "\(guide.name)을 열면 실제 메뉴 단축키를 읽어요"; return
        }
        let pid = app.processIdentifier
        let name = app.localizedName ?? guide.name
        let now = ProcessInfo.processInfo.systemUptime
        if !force, let cached = shortcutCache[guide.id], cached.pid == pid, now - cached.time < 15 {
            shortcutTask = nil; shortcuts = cached.items; shortcutStatus = cached.items.isEmpty ? "앱이 메뉴 단축키를 제공하지 않아요" : ""; return
        }
        if !background { shortcuts = []; shortcutStatus = "\(guide.name)의 메뉴를 읽는 중…" }
        shortcutTask = Task {
            // Delay work briefly while the finger travels across launcher tiles.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let items = await Task.detached(priority: .userInitiated) {
                MenuShortcutReader.read(pid: pid, applicationName: name)
            }.value
            guard !Task.isCancelled, od_shortcut_is_current(ticket), selectedGuide == guide else { return }
            shortcutTask = nil
            shortcutCache[guide.id] = (pid, ProcessInfo.processInfo.systemUptime, items)
            shortcuts = items
            shortcutPage = min(shortcutPage, max(0, (items.count - 1) / 4))
            shortcutStatus = items.isEmpty ? "앱이 메뉴 단축키를 제공하지 않아요" : ""
        }
    }
    func refreshMediaProgress() {
        guard settings.mediaFeatures.contains(where: \.isMediaWidget) || settings.launcherFeatures.contains(where: \.isMediaWidget) else { return }
        guard panelVisible, !rendering, progressTask == nil,
              ProcessInfo.processInfo.systemUptime - lastProgressRead > 1 else { return }
        lastProgressRead = ProcessInfo.processInfo.systemUptime
        guard let url = media.preferredAppURL, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { mediaProgress = nil; return }
        var candidates: [(Int32, String?)] = NSRunningApplication.runningApplications(withBundleIdentifier: id).map { ($0.processIdentifier, nil) }
        if let shortcutURL = bundle.object(forInfoDictionaryKey: "CrAppModeShortcutURL") as? String,
           URL(string: shortcutURL)?.host == "music.youtube.com" {
            candidates += NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").map { ($0.processIdentifier, "YouTube Music") }
        }
        let appID = settings.music_app?.id
        let targets = candidates.map { pid, filter in (pid, filter, filter != nil && accessibilityRequested.insert(pid).inserted) }
        progressTask = Task {
            let value = await Task.detached(priority: .utility) { () -> MediaProgress? in
                for (pid, filter, enable) in targets {
                    if let value = MediaProgressReader.read(pid: pid, windowFilter: filter, enableAccessibility: enable) { return value }
                }
                return nil as MediaProgress?
            }.value
            guard !Task.isCancelled, settings.music_app?.id == appID else { return }
            mediaProgress = value; progressTask = nil
        }
    }
    func queueSeek(_ fraction: Double) {
        guard let progress = mediaProgress, progress.canSeek, fraction.isFinite else { return }
        pendingSeek = min(1, max(0, fraction))
        seekTask?.cancel()
        let target = pendingSeek ?? progress.fraction
        seekTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let success = await Task.detached(priority: .userInitiated) { MediaProgressReader.seek(progress, fraction: target) }.value
            guard !Task.isCancelled else { return }
            pendingSeek = nil
            if !success { notify("음악 앱이 재생 위치 변경을 허용하지 않았어요") }
            lastProgressRead = 0
        }
    }
    func endPanelSession() {
        progressTask?.cancel(); progressTask = nil
        shortcutTask?.cancel(); shortcutTask = nil; _ = od_shortcut_advance()
    }
    private func runningApplication(for guide: LauncherGuide) -> NSRunningApplication? {
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: guide.id)
        guard let assigned = guide.path else { return candidates.first }
        let target = URL(fileURLWithPath: assigned).standardizedFileURL.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: assigned) {
            return candidates.first { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == target }
        }
        return candidates.first
    }
    func readPreviewShortcuts() {
        guard let app = runningApplication(for: selectedGuide) else { return }
        shortcuts = MenuShortcutReader.read(pid: app.processIdentifier, applicationName: app.localizedName ?? selectedGuide.name)
        shortcutStatus = shortcuts.isEmpty ? "앱이 메뉴 단축키를 제공하지 않아요" : ""
    }
    func notify(_ text: String) {
        message = text; messageGeneration += 1
        let generation = messageGeneration
        Task {
            try? await Task.sleep(for: .seconds(3))
            if generation == messageGeneration { message = nil }
        }
    }
    private func mediaCommand(_ command: Int) {
        Task {
            if let message = await media.perform(command, beforeOpening: { self.onClose?() }) { notify(message) }
        }
    }
    var focusedTitle: String {
        switch focused {
        case .brightness: "밝기 · 위아래로 조절"
        case .volume: "볼륨 · 위아래로 조절"
        case .mediaSeek: "재생 위치 · 위아래로 탐색"
        case .mute: "음소거 · 탭"
        case .previous: "이전 · 탭"
        case .playback: "재생 / 일시정지 · 탭"
        case .next: "다음 · 탭"
        case .backwardSkip: "15초 뒤로 · 탭"
        case .forwardSkip: "15초 앞으로 · 탭"
        case .systemMedia: "제어 센터 재생바 · 탭"
        case .feature(let index): settings.mediaFeatures.indices.contains(index) ? "\(settings.mediaFeatures[index].name) · 탭" : "기능"
        case .launch(let index): favorites.indices.contains(index) ? "\(favorites[index].name) · 탭" : "빠른 동작"
        case .shortcut(let index): visibleShortcuts.indices.contains(index) ? "\(selectedGuide.name) · \(visibleShortcuts[index].title)" : "단축키"
        case .moreShortcuts: "다른 단축키 보기 · 탭"
        case .refreshShortcuts: "앱 메뉴 새로고침 · 탭"
        case .previousPage: "이전 페이지 · 탭"
        case .nextPage: "다음 페이지 · 탭"
        case nil: page == 0 ? "좌우로 찾아서 위아래로 조절 · 옆으로 밀어 항목 변경" : "앱을 가리키면 단축키 표시 · 눌러서 실행"
        }
    }
}
