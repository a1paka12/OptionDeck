import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DeckCore

struct DeckSettingsView: View {
    @Bindable var model: DeckModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = DeckSettings()
    @State private var revision: UInt64 = 0
    @State private var status: String?
    @State private var failed = false
    private var editorPage: Int { model.settingsTab }
    @State private var dropTarget: String?
    @State private var dragSource: String?
    @State private var dragLocation: CGPoint?
    @State private var resizeSource: String?
    @State private var resizeBase: [DeckTile] = []
    @State private var resizeCell = CGSize(width: 1, height: 1)
    @State private var slotFrames: [String: CGRect] = [:]
    @State private var configuration: FeatureConfiguration?
    @State private var cachedPacking: PackedDeckPage?
    @State private var previewPacking: PackedDeckPage?
    @State private var previewTarget: String?
    @State private var ghostTile: String?
    @State private var dragBase: [DeckTile] = []
    @State private var dragFrames: [String: CGRect] = [:]
    @State private var cachedIcons: [String: NSImage] = [:]
    @State private var resizeRequest: String?
    @State private var selectedDestination: String?

    init(model: DeckModel, page: Int = 0) {
        self.model = model
        model.settingsTab = page
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("나만의 OptionDeck").font(.title2.bold())
                    Text("끌어서 배치하고, 칸 오른쪽 아래를 당겨 크기를 조절하세요.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("기본 구성") { draft = .init(); refreshEditorCache(); status = "저장하면 기본 구성으로 돌아갑니다."; failed = false }
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
            Picker("편집할 페이지", selection: $model.settingsTab) {
                Text("1페이지 · 시스템").tag(0)
                Text("2페이지 · 기능").tag(1)
                Text("단축키 연결").tag(2)
                Text("음악 앱").tag(3)
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    if editorPage < 2 {
                        HStack(alignment: .top, spacing: 20) {
                            featureLibrary
                            VStack(spacing: 14) {
                                canvas
                                Label("왼쪽 기능을 원하는 자리에 놓으세요 · 카드를 클릭해 대상 변경", systemImage: "hand.draw")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }.coordinateSpace(name: "deckEditor")
                            .onPreferenceChange(EditorSlotFrames.self) { slotFrames = $0 }
                            .overlay(alignment: .topLeading) {
                                if let source = dragSource, let location = dragLocation {
                                    Label(dropTarget == nil && !source.hasPrefix("library:") ? "놓으면 제거" : dragTitle(source), systemImage: dropTarget == nil && !source.hasPrefix("library:") ? "trash" : "hand.draw.fill")
                                        .font(.system(size: 12, weight: .semibold)).padding(12)
                                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                                        .shadow(radius: 8, y: 3).position(location).allowsHitTesting(false)
                                }
                            }
                    } else if editorPage == 2 {
                        shortcutSettings
                    } else {
                        musicSettings
                    }
                }.padding(20).frame(maxWidth: .infinity)
            }.scrollDisabled(dragSource != nil || resizeSource != nil)
            Divider()
            HStack {
                Text(status ?? model.settingsError ?? "미리보기에서 배치한 뒤 저장 및 적용을 누르세요.")
                    .font(.caption).foregroundStyle(failed || model.settingsError != nil ? Color.red : Color.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button("다시 불러오기") { reload() }
                Button("저장 및 적용") {
                    do {
                        try model.saveSettings(draft, revision: revision)
                        revision = model.settingsRevision; status = "저장했어요. 패널과 트랙패드에 적용됐습니다."; failed = false
                    } catch { status = error.localizedDescription; failed = true }
                }.buttonStyle(.borderedProminent).disabled(draft == model.settings && model.settingsError == nil)
            }.padding(20)
        }.frame(minWidth: 960, minHeight: 660).background(Color(nsColor: .windowBackgroundColor)).onAppear { reload() }
            .onChange(of: model.settingsTab) { _, _ in selectedDestination = nil; dropTarget = nil; refreshEditorCache() }
            .sheet(item: $configuration) { config in
                FeatureConfigurationView(configuration: config) { feature in
                    assign(feature, to: config.destination)
                }
            }
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28).fill(.primary.opacity(0.035))
            HStack(spacing: 12) {
                Image(systemName: "option").font(.title2)
                Text("OptionDeck").font(.headline)
                Spacer()
                Text("배치 편집 중").foregroundStyle(.secondary)
                Text("\(editorPage + 1) / 2").foregroundStyle(.secondary)
            }.frame(width: 624, height: 40).position(x: 340, y: 32)
            if editorPage == 0 { systemCanvas }
            else { appCanvas }
            if pageTiles.isEmpty && dragSource == nil {
                Text("왼쪽 기능을 끌어 넣으세요").foregroundStyle(.secondary).position(x: 340, y: 210)
            }
            if let ghostTile, !pageTiles.contains(where: { $0.id == ghostTile }), let previewPacking {
                let rect = previewPacking.rect(ghostTile, page: editorPage)
                RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.13))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6,4])))
                    .overlay(Text("여기에 추가").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor))
                    .frame(width: rect.width, height: rect.height).position(x: rect.x+rect.width/2,y:rect.y+rect.height/2).allowsHitTesting(false)
            }
            HStack {
                Image(systemName: "chevron.left")
                Spacer()
                Text("끌어서 이동 · 모서리로 크기 조절 · 주변 칸 자동 정렬").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
            }.frame(width: 620, height: 30).position(x: 340, y: 428)
        }.frame(width: 680, height: 460)
            .background(GeometryReader { geometry in Color.clear.preference(key: EditorSlotFrames.self, value: ["__canvas": geometry.frame(in: .named("deckEditor"))]) })
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.1)).allowsHitTesting(false))
    }
    private var systemCanvas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(draft.devices.indices, id: \.self) { index in
                let control: DeckControl = draft.devices[index] == 0 ? .brightness : .volume
                if editorRect("device:\(index)").width > 0 {
                slot(control.title, token: "device:\(index)", rect: editorRect("device:\(index)")) {
                    HStack(spacing: 30) {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: control.symbol).font(.system(size: 28))
                            Text(control.title).font(.headline)
                            Label("끌어서 이동", systemImage: "hand.draw").font(.caption).foregroundStyle(.secondary)
                            if control == .volume {
                                Label("음소거", systemImage: "speaker.slash").font(.caption)
                                    .padding(8).background(.primary.opacity(0.06), in: Capsule())
                            }
                        }
                        Capsule().fill(.primary.opacity(0.1)).frame(width: 38, height: 110)
                            .overlay(alignment: .bottom) { Capsule().fill(.primary.opacity(0.65)).frame(width: 38, height: 55) }
                    }
                }
                }
            }
            ForEach(draft.mediaFeatures.indices, id: \.self) { index in
                let feature = draft.mediaFeatures[index]
                let rect = editorRect("media:\(index)")
                slot(feature.name, token: "media:\(index)", rect: rect, action: { configure(feature, destination: "media:\(index)") }) {
                    if feature.isMediaWidget { MediaWidgetPreview(width: rect.width, height: rect.height) }
                    else {
                        HStack(spacing: 7) {
                            Image(systemName: feature.symbol).font(.system(size: 18))
                            if rect.width > 140 { Text(feature.name).font(.caption).lineLimit(1) }
                        }
                    }
                }
            }
        }.frame(width: 680, height: 460, alignment: .topLeading)
    }
    private var appCanvas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(draft.devices.indices, id: \.self) { index in
                let control: DeckControl = draft.devices[index] == 0 ? .brightness : .volume
                let rect = editorRect("device:\(index)")
                if rect.width > 0 {
                    slot(control.title, token: "device:\(index)", rect: rect) {
                        VStack(spacing: 12) {
                            Image(systemName: control.symbol).font(.title)
                            Text(control.title).font(.headline)
                            Capsule().fill(.primary.opacity(0.15)).frame(width: min(120,rect.width-24), height: 5)
                        }
                    }
                }
            }
            ForEach(draft.launcherFeatures.indices, id: \.self) { index in
                let app = draft.launcherFeatures[index]
                slot(app.name, token: "app:\(index)", rect: editorRect("app:\(index)"), action: { configure(app, destination: "app:\(index)") }) {
                    if app.isMediaWidget { MediaWidgetPreview(width: editorRect("app:\(index)").width, height: editorRect("app:\(index)").height) }
                    else {
                    HStack(spacing: 10) {
                        Image(nsImage: cachedIcons[app.cacheKey] ?? NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil)!).resizable().frame(width: 36, height: 36)
                        if editorRect("app:\(index)").width > 140 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(app.kind == .empty ? "기능을 놓으세요" : "클릭해서 설정").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12)
                    }
                }
            }
            VStack(spacing: 8) {
                Label("선택한 앱의 실제 메뉴 단축키", systemImage: "command").font(.subheadline.weight(.medium))
                Text(draft.automatic_shortcuts ? "앱을 지정하면 자동 연결됩니다." : "앱 선택 또는 새로고침으로 읽습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(width: 640, height: 92).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                .position(x: 340, y: 350)
        }.frame(width: 680, height: 460, alignment: .topLeading)
    }
    private var shortcutSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "command").font(.largeTitle).foregroundStyle(.tint)
                Toggle("선택한 앱의 메뉴 단축키 자동 연결", isOn: $draft.automatic_shortcuts)
                Text("앱을 할당하면 macOS 손쉬운 사용 API로 실제 메뉴 단축키를 읽습니다. 패널이 열린 동안 선택한 앱의 실행·활성화와 5초 간격으로 갱신합니다. 끄면 앱 선택 및 새로고침으로 읽을 수 있습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("실행 중인 앱과 손쉬운 사용 권한이 필요합니다. 메뉴에 공개되지 않은 앱 내부 단축키는 표시할 수 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.frame(width: 680).padding(.top, 20)
    }
    private var musicSettings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                Label("기본 음악 앱", systemImage: "music.note").font(.title2.bold())
                HStack(spacing: 16) {
                    Image(nsImage: draft.music_app.map { DeckFeature.app($0).icon } ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!)
                        .resizable().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.music_app?.name ?? (model.media.defaultMusicAppURL == nil ? "음악 앱을 선택하세요" : "YouTube Music")).font(.headline)
                        Text(draft.music_app?.path ?? (model.media.defaultMusicAppURL == nil ? "Chrome에서 YouTube Music을 설치하거나 앱을 직접 선택하세요" : "기본값 · Chrome에 설치된 YouTube Music"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("음악 앱 선택…") { chooseApp("music") }
                }
                Text("재생 중인 항목이 없을 때 재생 버튼을 누르면 이 앱을 엽니다. 앱에서 곡을 선택하면 시스템 미디어로 재생·일시정지와 이전·다음을 조절합니다.")
                    .foregroundStyle(.secondary)
                Text("이미 재생 중인 항목이 있으면 macOS가 정한 시스템 미디어 대상을 조절합니다. 선택한 앱으로 강제로 재생 대상을 바꾸는 설정은 아닙니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("기본 음악 앱 자동 감지") { draft.music_app = nil }
            }.padding(20)
        }.frame(width: 740).padding(.top, 20)
    }
    private func slot<Content: View>(_ title: String, token: String, rect: DeckRect,
                                    action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) -> some View {
        let card = content().frame(width: rect.width, height: rect.height)
            .background(dropTarget == token ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder((dropTarget == token || selectedDestination == token) ? Color.accentColor : .primary.opacity(0.08), lineWidth: dropTarget == token ? 3 : 1))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold))
                    .padding(5).background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5)).padding(4)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { selectedDestination = token; action?() }
        return card
            .background(GeometryReader { geometry in
                Color.clear.preference(key: EditorSlotFrames.self, value: [token: geometry.frame(in: .named("deckEditor"))])
            })
            .opacity(dragSource == token || ghostTile == token ? 0.18 : 1)
            .overlay {
                if ghostTile == token {
                    RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.13))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        .overlay(Text("여기에 놓기").font(.caption.weight(.medium)).foregroundStyle(Color.accentColor))
                        .allowsHitTesting(false)
                }
            }
            .highPriorityGesture(editorDrag(token))
            .contextMenu { slotMenu(token: token, action: action) }
            .accessibilityElement(children: .combine).accessibilityLabel(title)
            .accessibilityHint(action == nil ? "드래그하거나 컨텍스트 메뉴로 위치를 변경합니다" : "클릭하면 앱을 변경하고 드래그하면 위치를 변경합니다")
            .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: previewTarget)
    }
    @ViewBuilder private func slotMenu(token: String, action: (() -> Void)?) -> some View {
        if let action { Button("대상 설정…", action: action) }
        Button("제거") { removeTile(token) }
        Menu("크기") {
            Button("작게") { resizeTile(token, columns: 2, rows: 1) }
            Button("중간") { resizeTile(token, columns: 3, rows: 2) }
            Button("크게") { resizeTile(token, columns: 4, rows: 2) }
        }
        ForEach(pageTiles, id: \.id) { tile in
            Button("\(dragTitle(tile.id)) 자리로 이동") { _ = swap(token, tile.id) }
        }
    }

    private func slotCount(_ token: String) -> Int {
        token.hasPrefix("app:") ? draft.launcherFeatures.count : (token.hasPrefix("device:") ? 2 : draft.mediaFeatures.count)
    }
    private var featureLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("기능 보관함", systemImage: "square.grid.2x2").font(.headline)
            Text("끌거나 눌러서 추가 · 밖으로 빼서 제거").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(DeckFeature.library.indices, id: \.self) { index in
                        let feature = DeckFeature.library[index]
                        HStack(spacing: 9) {
                            Image(systemName: feature.symbol).frame(width: 22)
                            Text(feature.name).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 0)
                        }.padding(10).frame(maxWidth: .infinity)
                            .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                            .highPriorityGesture(editorDrag("library:\(index)"))
                            .onTapGesture {
                                _ = drop("library:\(index)", onto: selectedDestination ?? "append")
                            }
                            .accessibilityLabel(feature.name)
                    }
                }
            }
            Text("아래로 스크롤하면 더 많은 기능이 있어요. 크기는 칸 모서리에서 조절합니다.").font(.caption).foregroundStyle(.secondary)
        }.frame(width: 170, height: 460)
    }
    private var pageTiles: [DeckTile] {
        let layouts = draft.resolvedLayouts
        return editorPage == 0 ? layouts.system : layouts.actions
    }
    private var packedPage: PackedDeckPage? { previewPacking ?? cachedPacking }
    private func refreshEditorCache() {
        cachedPacking = editorPage < 2 ? try? LayoutEngine.fit(pageTiles) : nil
        previewPacking = nil; previewTarget = nil; ghostTile = nil
        for feature in draft.launcherFeatures + draft.mediaFeatures where cachedIcons[feature.cacheKey] == nil {
            cachedIcons[feature.cacheKey] = feature.icon
        }
    }
    private func editorRect(_ token: String) -> DeckRect {
        packedPage?.rect(token, page: editorPage) ?? .init(0, 0, 0, 0)
    }
    private func setTiles(_ tiles: [DeckTile], packed: PackedDeckPage? = nil) {
        var layouts = draft.resolvedLayouts
        if editorPage == 0 { layouts.system = tiles } else { layouts.actions = tiles }
        draft.layouts = layouts
        cachedPacking = packed ?? (try? LayoutEngine.pack(tiles))
    }
    private func resizeTile(_ token: String, columns: Int, rows: Int, base: [DeckTile]? = nil) {
        do {
            let result = try LayoutEngine.resize(base ?? pageTiles, id: token, columns: columns, rows: rows)
            setTiles(result.tiles, packed: result)
            status = "크기 변경 · 주변 칸을 자동 정렬했어요. 저장하면 적용됩니다."; failed = false
        } catch { status = error.localizedDescription; failed = true }
    }
    private func editorDrag(_ token: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("deckEditor"))
            .onChanged { value in
                if dragSource == nil && resizeSource == nil, !token.hasPrefix("library:"), let frame = slotFrames[token],
                   CGRect(x: frame.maxX - 24, y: frame.maxY - 24, width: 24, height: 24).contains(value.startLocation) {
                    resizeSource = token; resizeBase = pageTiles; resizeRequest = nil
                    resizeCell = packedPage?.cellSize(page: editorPage) ?? .init(width: 100, height: 80)
                }
                if resizeSource == token, let tile = resizeBase.first(where: { $0.id == token }) {
                    let columns = tile.columns + Int((value.translation.width / resizeCell.width).rounded())
                    let rows = tile.rows + Int((value.translation.height / resizeCell.height).rounded())
                    let request = "\(columns):\(rows)"
                    if resizeRequest != request {
                        resizeRequest = request
                        resizeTile(token, columns: columns, rows: rows, base: resizeBase)
                    }
                    return
                }
                if dragSource == nil { dragBase = pageTiles; dragFrames = slotFrames }
                dragSource = token; dragLocation = value.location
                let target = destination(at: value.location, source: token)
                dropTarget = target
                updatePreview(source: token, target: target)
            }
            .onEnded { value in
                if resizeSource == nil, let destination = destination(at: value.location, source: token) {
                    if !token.hasPrefix("library:"), let previewPacking { setTiles(previewPacking.tiles, packed: previewPacking) }
                    else { _ = drop(token, onto: destination) }
                } else if resizeSource == nil, !token.hasPrefix("library:"), let canvas = dragFrames["__canvas"], !canvas.contains(value.location) {
                    removeTile(token)
                }
                dragSource = nil; dragLocation = nil; dropTarget = nil; resizeSource = nil; resizeBase = []
                previewPacking = nil; previewTarget = nil; ghostTile = nil; dragBase = []; dragFrames = [:]
            }
    }
    private func destination(at location: CGPoint, source: String) -> String? {
        let frames = dragFrames.isEmpty ? slotFrames : dragFrames
        guard let canvas = frames["__canvas"], canvas.contains(location) else { return nil }
        return frames.first { token, frame in token != "__canvas" && frame.contains(location) }?.key ?? "append"
    }
    private func updatePreview(source: String, target: String?) {
        guard target != previewTarget else { return }
        previewTarget = target
        guard let target else { previewPacking = nil; ghostTile = nil; return }
        if source.hasPrefix("library:"), let index = Int(source.dropFirst(8)), DeckFeature.library.indices.contains(index) {
            if let plan = try? insertionPlan(DeckFeature.library[index], target: target, base: dragBase) {
                previewPacking = plan.0; ghostTile = plan.1
            } else { previewPacking = nil; ghostTile = nil }
        } else {
            ghostTile = source
            let destination = target == "append" ? (dragBase.last?.id ?? source) : target
            previewPacking = try? LayoutEngine.move(dragBase, from: source, to: destination)
        }
    }
    private func dragTitle(_ token: String) -> String {
        let parts = token.split(separator: ":")
        guard parts.count == 2, let index = Int(parts[1]) else { return "기능 이동" }
        switch parts[0] {
        case "library": return DeckFeature.library[index].name
        case "media": return draft.mediaFeatures[index].name
        case "app": return draft.launcherFeatures[index].name
        default: return draft.devices[index] == 0 ? "밝기" : "볼륨"
        }
    }
    private func drop(_ source: String, onto destination: String) -> Bool {
        if source.hasPrefix("library:") {
            guard let index = Int(source.dropFirst(8)), DeckFeature.library.indices.contains(index) else { return false }
            let feature = DeckFeature.library[index]
            dropTarget = nil
            if feature.kind == .builtin { insertFeature(feature, before: destination) }
            else { configure(feature, destination: "new:" + destination) }
            return true
        }
        return swap(source, destination)
    }
    private func insertionPlan(_ feature: DeckFeature, target: String, base: [DeckTile]) throws -> (PackedDeckPage, String) {
        var tiles = base
        let id: String
        let columns: Int
        let rows: Int
        if feature.kind == .builtin && ["brightness", "volume"].contains(feature.value) {
            let index = draft.devices.firstIndex(of: feature.value == "brightness" ? 0 : 1) ?? 0
            id = "device:\(index)"; columns = 3; rows = 2
        } else {
            id = editorPage == 0 ? "media:\(draft.mediaFeatures.count)" : "app:\(draft.launcherFeatures.count)"
            columns = feature.isMediaWidget ? 3 : 2; rows = feature.isMediaWidget ? 2 : 1
        }
        if !tiles.contains(where: { $0.id == id }) {
            guard tiles.count < 24 else { throw SettingsError(message: "페이지가 가득 찼어요. 다른 기능을 제거하거나 다음 페이지에 넣어 주세요.") }
            tiles.append(.init(id: id, columns: columns, rows: rows))
        }
        var packed = try LayoutEngine.resize(tiles, id: id, columns: columns, rows: rows)
        if target != "append", target != id, tiles.contains(where: { $0.id == target }) {
            packed = try LayoutEngine.move(packed.tiles, from: id, to: target)
        }
        return (packed, id)
    }
    private func insertFeature(_ feature: DeckFeature, before destination: String) {
        do {
            let (packed, id) = try insertionPlan(feature, target: destination, base: pageTiles)
            var next = draft
            if !id.hasPrefix("device:") { _ = next.appendFeature(feature, section: editorPage == 0 ? "media" : "app") }
            var layouts = next.resolvedLayouts
            if editorPage == 0 { layouts.system = packed.tiles } else { layouts.actions = packed.tiles }
            next.layouts = layouts; draft = next; cachedPacking = packed
            cachedIcons[feature.cacheKey] = feature.icon; selectedDestination = id
            status = "\(feature.name) 추가 · 저장하면 적용됩니다."; failed = false
        } catch { status = error.localizedDescription; failed = true }
    }
    private func removeTile(_ token: String) {
        let parts = token.split(separator: ":")
        guard parts.count == 2, let index = Int(parts[1]), pageTiles.contains(where: { $0.id == token }) else { return }
        var next = draft
        if parts[0] != "device" { next.removeFeature(section: String(parts[0]), index: index) }
        let tiles = pageTiles.filter { $0.id != token }.map { tile -> DeckTile in
            var tile = tile
            let other = tile.id.split(separator: ":")
            if parts[0] != "device", other.count == 2, other[0] == parts[0], let old = Int(other[1]), old > index { tile.id = "\(parts[0]):\(old - 1)" }
            return tile
        }
        do {
            let packed = try LayoutEngine.fit(tiles)
            var layouts = next.resolvedLayouts
            if editorPage == 0 { layouts.system = packed.tiles } else { layouts.actions = packed.tiles }
            next.layouts = layouts; draft = next; cachedPacking = packed; selectedDestination = nil
            status = "기능을 제거하고 남은 공간을 정리했어요. 저장하면 적용됩니다."; failed = false
        } catch { status = error.localizedDescription; failed = true }
    }
    private func swap(_ source: String, _ destination: String) -> Bool {
        let lhs = source.split(separator: ":"), rhs = destination.split(separator: ":")
        guard lhs.count == 2, rhs.count == 2,
              let from = Int(lhs[1]), let to = Int(rhs[1]),
              ["app", "media", "device"].contains(String(lhs[0])), ["app", "media", "device"].contains(String(rhs[0])),
              (0..<slotCount(source)).contains(from), (0..<slotCount(destination)).contains(to) else { return false }
        if (lhs[0] == "app") == (rhs[0] == "app") {
            do { setTiles(try LayoutEngine.move(pageTiles, from: source, to: destination).tiles) }
            catch { status = error.localizedDescription; failed = true; return false }
        } else {
            guard lhs[0] != "device", rhs[0] != "device" else { return false }
            draft.swapFeatures(from, section: String(lhs[0]), with: to, otherSection: String(rhs[0]))
        }
        selectedDestination = destination; dropTarget = nil
        status = "배치를 바꿨어요. 저장하면 패널에 적용됩니다."; failed = false
        return true
    }
    private func assign(_ feature: DeckFeature, to destination: String) {
        if destination.hasPrefix("new:") { insertFeature(feature, before: String(destination.dropFirst(4))); return }
        let parts = destination.split(separator: ":")
        guard parts.count == 2, ["app", "media"].contains(String(parts[0])),
              let index = Int(parts[1]), (0..<slotCount(destination)).contains(index) else { return }
        draft.setFeature(feature, section: String(parts[0]), index: index)
        cachedIcons[feature.cacheKey] = feature.icon
        if feature.isMediaWidget { resizeTile(destination, columns: 3, rows: 2) }
        status = "\(feature.name) 추가 · 저장하면 적용됩니다."; failed = false
    }
    private func configure(_ feature: DeckFeature, destination: String) {
        switch feature.kind {
        case .app: chooseApp(destination)
        case .file: chooseFile(destination)
        case .url, .shortcut: configuration = .init(destination: destination, feature: feature)
        case .builtin, .empty: break
        }
    }
    private func chooseFile(_ destination: String) {
        let picker = NSOpenPanel()
        picker.title = "열 파일 또는 폴더 선택"
        picker.canChooseFiles = true; picker.canChooseDirectories = true; picker.allowsMultipleSelection = false
        picker.begin { response in
            guard response == .OK, let url = picker.url else { return }
            assign(.init(kind: .file, value: url.path, name: url.lastPathComponent), to: destination)
        }
    }
    private func reload() {
        do {
            try model.reloadSettings()
            draft = model.settings; revision = model.settingsRevision; status = nil; failed = false; refreshEditorCache()
        } catch { status = error.localizedDescription; failed = true }
    }
    private func chooseApp(_ destination: String) {
        let picker = NSOpenPanel()
        picker.title = "할당할 앱 선택"
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseFiles = true; picker.canChooseDirectories = false
        picker.treatsFilePackagesAsDirectories = false; picker.allowsMultipleSelection = false
        picker.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        picker.prompt = "할당"
        picker.begin { response in
            guard response == .OK, let url = picker.url else { return }
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.isEmpty else {
                status = "번들 식별자가 있는 macOS 앱을 선택해 주세요."; failed = true; return
            }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            if destination == "music" {
                draft.music_app = .init(id: id, name: name, path: url.path)
                status = "기본 음악 앱: \(name) · 저장하면 적용됩니다."; failed = false
            } else {
                assign(.init(kind: .app, value: id, name: name, path: url.path), to: destination)
                status = "\(name) 할당 · 저장하면 단축키가 자동 연결됩니다."; failed = false
            }
        }
    }
}


private struct FeatureConfiguration: Identifiable {
    let id = UUID()
    let destination: String
    let feature: DeckFeature
}
private struct FeatureConfigurationView: View {
    let configuration: FeatureConfiguration
    let onSave: (DeckFeature) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var value: String
    init(configuration: FeatureConfiguration, onSave: @escaping (DeckFeature) -> Void) {
        self.configuration = configuration; self.onSave = onSave
        _name = State(initialValue: configuration.feature.name)
        _value = State(initialValue: configuration.feature.value)
    }
    private var valid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if configuration.feature.kind == .url {
            guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return false }
            return true
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 256
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(configuration.feature.kind == .url ? "웹사이트 연결" : "macOS 단축어 연결").font(.title2.bold())
            TextField("표시 이름", text: $name)
            TextField(configuration.feature.kind == .url ? "https://example.com" : "단축어 앱에 있는 이름", text: $value)
            if configuration.feature.kind == .shortcut {
                Text("단축어 앱에 저장된 이름을 정확히 입력하세요. 패널에서 선택하고 Option을 놓으면 해당 단축어가 실행됩니다.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("추가") {
                    onSave(.init(kind: configuration.feature.kind, value: value, name: name))
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 440)
    }
}


private struct EditorSlotFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}


private struct MediaWidgetPreview: View {
    let width: Double
    let height: Double
    var body: some View {
        VStack(spacing: height < 100 ? 6 : 14) {
            if height > 100 { Label("미디어 재생", systemImage: "music.note").font(.caption.weight(.medium)) }
            Capsule().fill(.primary.opacity(0.15)).frame(height: 4)
            HStack(spacing: width < 150 ? 8 : 24) {
                Image(systemName: "backward.end.fill")
                Image(systemName: "playpause.fill")
                Image(systemName: "forward.end.fill")
            }.font(.system(size: height < 80 ? 11 : 17))
        }.padding(12).allowsHitTesting(false)
    }
}
