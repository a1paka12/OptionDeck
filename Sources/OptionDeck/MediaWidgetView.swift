import SwiftUI
import DeckCore

struct MediaWidgetView: View {
    @Bindable var model: DeckModel
    let rect: DeckRect
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18).fill(.primary.opacity(0.055))
            if rect.height > 100 {
                Button { model.onMusicSettings?() } label: {
                    HStack {
                        Image(systemName: "music.note")
                        Text(model.media.preferredAppName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }.font(.system(size: 12, weight: .semibold))
                }.buttonStyle(.plain).frame(width: rect.width - 64, alignment: .leading).position(x: (rect.width - 40) / 2, y: 22)
                Button { model.tap(.systemMedia) } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).position(x: rect.width - 22, y: 22).accessibilityLabel(L("시스템 재생바 열기"))
            }
            let seek = MediaWidgetLayout.seek(in: .init(0, 0, rect.width, rect.height))
            let fraction = model.pendingSeek ?? model.mediaProgress?.fraction ?? 0
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12)).frame(height: 4)
                if model.mediaProgress != nil {
                    Capsule().fill(.primary.opacity(0.75)).frame(width: max(2, seek.width * fraction), height: 4)
                    if model.mediaProgress?.canSeek == true {
                        Circle().fill(.primary).frame(width: 8, height: 8).offset(x: max(0, (seek.width - 8) * fraction))
                    }
                }
            }.frame(width: seek.width, height: seek.height).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in model.queueSeek(value.location.x / seek.width) })
                .allowsHitTesting(model.mediaProgress?.canSeek == true)
                .position(x: seek.x + seek.width / 2, y: seek.y + seek.height / 2)
                .accessibilityElement(children: .ignore).accessibilityLabel(L("재생 위치"))
                .accessibilityValue(model.mediaProgress?.label ?? L("정보 없음"))
                .accessibilityAdjustableAction { direction in
                    if let progress = model.mediaProgress { model.queueSeek(progress.fraction + (direction == .increment ? 0.02 : -0.02)) }
                }
            if rect.height > 120 {
                Text(model.mediaProgress.map { $0.label.isEmpty ? L("재생 위치") : $0.label } ?? L("재생 중인 곡의 위치를 읽을 수 없어요"))
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: rect.width - 24, alignment: .leading).position(x: rect.width / 2, y: seek.y + 26)
            }
            ForEach(Array(MediaWidgetLayout.buttons(in: .init(0, 0, rect.width, rect.height)).enumerated()), id: \.offset) { _, item in
                Button { model.tap(item.0) } label: {
                    Image(systemName: item.0.symbol).font(.system(size: rect.height < 80 ? 12 : 17))
                        .frame(width: item.1.width, height: item.1.height)
                        .background(model.focused == item.0 ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).position(x: item.1.x + item.1.width / 2, y: item.1.y + item.1.height / 2)
                    .accessibilityLabel(item.0.title)
            }
        }.frame(width: rect.width, height: rect.height)
    }
}
