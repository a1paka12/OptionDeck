import SwiftUI
import AppKit
import DeckCore

struct DeckView: View {
    @Bindable var model: DeckModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .topLeading) {
            if reduceTransparency || model.rendering { Color(nsColor: .windowBackgroundColor) }
            else { PanelMaterial() }
            header.frame(width: 640, height: 40).position(x: 340, y: 32)
            Group {
                if model.page == 0 { devicePage }
                else { launcherPage }
            }.animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: model.page)
            footer.frame(width: 640, height: 36).position(x: 340, y: 428)
            if let point = model.touchPoint {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.18)).frame(width: 46, height: 46)
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 24, height: 24)
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                }.shadow(color: .black.opacity(0.25), radius: 5, y: 1)
                    .position(x: point.x * 680, y: point.y * 460).allowsHitTesting(false)
            }
        }.frame(width: 680, height: 460)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.primary.opacity(0.13), lineWidth: 0.75))
            .font(.system(size: 12))
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "option").font(.system(size: 19, weight: .medium))
                .frame(width: 34, height: 34).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text("OptionDeck").font(.system(size: 14, weight: .semibold))
                Text(model.page == 0 ? "밝기 · 볼륨 · 시스템 미디어" : "앱 · 기능 바로가기")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.preview ? "미리보기" : "⌥ 누르는 동안").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("\(model.page + 1) / 2").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary).padding(.horizontal, 8)
            Button { model.onMusicSettings?() } label: {
                Image(systemName: "music.note").frame(width: 25, height: 25)
            }.buttonStyle(.plain).accessibilityLabel("음악 앱 선택")
            Button { model.onSettings?() } label: {
                Image(systemName: "gearshape").frame(width: 25, height: 25)
            }.buttonStyle(.plain).accessibilityLabel("앱 및 배치 설정")
            Button { model.onClose?() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .frame(width: 25, height: 25).background(.primary.opacity(0.06), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("패널 닫기")
        }
    }
    private var devicePage: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { index in
                let control: DeckControl = model.settings.devices[index] == 0 ? .brightness : .volume
                let rect = model.geometry?.rect("device:\(index)", page: 0) ?? DeckLayout.deviceColumn(index)
                if rect.width > 0 {
                DeviceTile(model: model, control: control, title: control.title, symbol: control.symbol,
                           value: control == .brightness ? model.brightness : model.volume,
                           available: control == .brightness ? model.brightnessAvailable : model.volumeAvailable, compact: rect.height < 150)
                    .frame(width: rect.width, height: rect.height).position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                if control == .volume {
                    controlButton(.mute, symbol: model.muted ? "speaker.slash.fill" : "speaker.wave.2", label: "음소거",
                                  rect: DeckGeometry.muteRect(rect), enabled: model.muteAvailable)
                }
                }
            }
            ForEach(model.settings.mediaFeatures.indices, id: \.self) { index in
                let feature = model.settings.mediaFeatures[index]
                let rect = model.geometry?.rect("media:\(index)", page: 0) ?? DeckLayout.mediaSlots[index]
                if feature.isMediaWidget {
                    MediaWidgetView(model: model, rect: rect).position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                } else if feature.kind != .empty {
                controlButton(.feature(index), symbol: feature.symbol, label: feature.name, rect: rect)
                    .contextMenu {
                        if feature.value == "playback" { Button("음악 앱 선택…") { model.onMusicSettings?() } }
                    }
                }
            }
        }.frame(width: 680, height: 460, alignment: .topLeading)
    }
    private var launcherPage: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { index in
                let control: DeckControl = model.settings.devices[index] == 0 ? .brightness : .volume
                let rect = model.geometry?.rect("device:\(index)", page: 1) ?? .init(0,0,0,0)
                if rect.width > 0 {
                    DeviceTile(model: model, control: control, title: control.title, symbol: control.symbol,
                               value: control == .brightness ? model.brightness : model.volume,
                               available: control == .brightness ? model.brightnessAvailable : model.volumeAvailable, compact: rect.height < 150)
                        .frame(width: rect.width, height: rect.height).position(x: rect.x + rect.width/2, y: rect.y + rect.height/2)
                    if control == .volume { controlButton(.mute, symbol: "speaker.slash", label: "음소거", rect: DeckGeometry.muteRect(rect), enabled: model.muteAvailable) }
                }
            }
            ForEach(Array(model.favorites.enumerated()), id: \.offset) { index, app in
                let rect = model.geometry?.rect("app:\(index)", page: 1) ?? DeckLayout.launcher(index)
                if model.settings.launcherFeatures[index].isMediaWidget {
                    MediaWidgetView(model: model, rect: rect).position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                } else if model.settings.launcherFeatures[index].kind != .empty {
                Button { model.tap(.launch(index)) } label: {
                    HStack(spacing: 12) {
                        Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 38, height: 38)
                        if rect.width > 140 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.system(size: 12, weight: .semibold))
                            Text(app.subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).frame(width: rect.width, height: rect.height)
                        .background(ModuleBackground(highlighted: model.selectedLauncher == index))
                }.buttonStyle(.plain).onHover { if $0 { model.focus(.launch(index)) } }
                    .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                    .accessibilityHint("선택하면 아래에 이 앱의 단축키를 표시합니다")
                }
            }
            ModuleBackground().frame(width: 640, height: 92).position(x: 340, y: 350)
            HStack {
                Text(model.shortcutHeading).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(model.shortcuts.isEmpty ? "" : "\(model.shortcutPage + 1) / \((model.shortcuts.count + 3) / 4)")
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.trailing, 80).frame(width: 606).position(x: 340, y: 317)
            Button { model.tap(.refreshShortcuts) } label: {
                Image(systemName: "arrow.clockwise").frame(width: 30, height: 22)
            }.buttonStyle(.plain).position(x: 591, y: 317).accessibilityLabel("앱 메뉴에서 다시 읽기")
            Button { model.tap(.moreShortcuts) } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 22)
            }.buttonStyle(.plain).disabled(model.shortcuts.count <= 4).position(x: 628, y: 317)
                .accessibilityLabel("다른 메뉴 단축키 보기")
            if model.visibleShortcuts.isEmpty {
                Text(model.shortcutStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(width: 600, height: 52).position(x: 340, y: 360)
            }
            ForEach(Array(model.visibleShortcuts.enumerated()), id: \.element.id) { index, hint in
                let rect = DeckLayout.shortcut(index)
                Button { model.tap(.shortcut(index)) } label: {
                    HStack {
                        Text(hint.title).font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        Text(hint.keys).font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 3).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }.padding(.horizontal, 8).frame(width: rect.width, height: rect.height)
                        .background(model.focused == .shortcut(index) ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).disabled(!hint.enabled).opacity(hint.enabled ? 1 : 0.4)
                    .onHover { hovering in
                        if hovering { model.focus(.shortcut(index)) }
                        else if model.focused == .shortcut(index) { model.focus(nil) }
                    }
                    .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
                    .accessibilityLabel("\(model.selectedGuide.name): \(hint.title), \(hint.keys)")
            }
        }.frame(width: 680, height: 460, alignment: .topLeading)
    }
    private func controlButton(_ control: DeckControl, symbol: String, label: String, rect: DeckRect, enabled: Bool = true) -> some View {
        Button { model.tap(control) } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                if rect.width > 140 { Text(label).font(.system(size: 11)).lineLimit(1) }
            }.frame(width: rect.width, height: rect.height)
                .background(model.focused == control ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
            .onHover { if $0 { model.focus(control) } }.accessibilityLabel(label)
            .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }
    private var footer: some View {
        HStack {
            Button { model.changePage(model.page - 1) } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 30).background(.primary.opacity(0.06), in: Capsule())
            }.buttonStyle(.plain).disabled(model.page == 0).accessibilityLabel("이전 페이지")
            Spacer()
            VStack(spacing: 5) {
                Text(model.message ?? model.focusedTitle).font(.system(size: 11, weight: model.focused == nil ? .regular : .semibold))
                    .foregroundStyle(model.focused == nil ? Color.secondary : Color.primary).lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(0..<2) { page in
                        Capsule().fill(model.page == page ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                            .frame(width: model.page == page ? 16 : 5, height: 4)
                    }
                    Text("두 손가락 좌우로 페이지 전환").font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 3)
                }
            }
            Spacer()
            Button { model.changePage(model.page + 1) } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 30).background(.primary.opacity(0.06), in: Capsule())
            }.buttonStyle(.plain).disabled(model.page == 1).accessibilityLabel("다음 페이지")
        }
    }
}

private struct ModuleBackground: View {
    var highlighted = false
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(highlighted ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(highlighted ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.05), lineWidth: highlighted ? 2 : 1))
    }
}

private struct DeviceTile: View {
    @Bindable var model: DeckModel
    let control: DeckControl, title: String, symbol: String, value: Double, available: Bool
    var compact = false
    @State private var previousTranslation = 0.0
    var body: some View {
        ZStack {
            ModuleBackground(highlighted: model.focused == control)
            HStack(spacing: compact ? 16 : 27) {
                VStack(alignment: .leading, spacing: compact ? 4 : 10) {
                    Image(systemName: symbol).font(.system(size: compact ? 18 : 26, weight: .medium))
                    Text(title).font(.system(size: compact ? 12 : 16, weight: .semibold))
                    Text(available ? "\(Int((value * 100).rounded()))%" : "지원되지 않음")
                        .font(.system(size: available ? (compact ? 18 : 25) : 12, weight: .medium).monospacedDigit())
                    if !compact { Text("위아래로 조절").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                ZStack(alignment: .bottom) {
                    Capsule().fill(.primary.opacity(0.1))
                    Capsule().fill(.white.opacity(0.95)).frame(height: max(8, (compact ? 55 : 110) * value))
                }.frame(width: compact ? 28 : 38, height: compact ? 55 : 110).shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }.padding(.bottom, control == .volume ? (compact ? 30 : 36) : 0).opacity(available ? 1 : 0.45)
        }.contentShape(RoundedRectangle(cornerRadius: 18))
            .onHover { if $0 { model.focus(control) } }
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                guard available else { return }
                model.focus(control)
                let current = gesture.translation.height
                model.adjust(control, by: -(current - previousTranslation) / 180)
                previousTranslation = current
            }.onEnded { _ in previousTranslation = 0; model.focus(nil) })
            .accessibilityElement(children: .ignore).accessibilityLabel(title)
            .accessibilityValue(available ? "\(Int(value * 100))퍼센트" : "지원되지 않음")
            .accessibilityAdjustableAction { model.adjust(control, by: $0 == .increment ? 0.05 : -0.05) }
    }
}

private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension DeckControl {
    var title: String {
        switch self {
        case .mute: "음소거"
        case .brightness: "밝기"
        case .volume: "볼륨"
        case .previous: "이전"
        case .playback: "재생 / 일시정지"
        case .next: "다음"
        case .systemMedia: "제어 센터 재생바"
        case .backwardSkip: "15초 뒤로"
        case .forwardSkip: "15초 앞으로"
        default: ""
        }
    }
    var symbol: String {
        switch self {
        case .mute: "speaker.slash"
        case .brightness: "sun.max.fill"
        case .volume: "speaker.wave.2.fill"
        case .previous: "backward.end.fill"
        case .playback: "playpause.fill"
        case .next: "forward.end.fill"
        case .systemMedia: "slider.horizontal.3"
        case .backwardSkip: "gobackward.15"
        case .forwardSkip: "goforward.15"
        default: "app"
        }
    }
}
