import Foundation

public enum MediaWidgetLayout {
    public static func seek(in rect: DeckRect) -> DeckRect {
        .init(rect.x + 12, rect.y + (rect.height > 100 ? 48 : 5), max(20, rect.width - 24), 16)
    }
    public static func buttons(in rect: DeckRect) -> [(DeckControl, DeckRect)] {
        let controls: [DeckControl] = rect.width > 260 ? [.backwardSkip, .previous, .playback, .next, .forwardSkip] : [.previous, .playback, .next]
        let width = min(48, (rect.width - 12) / Double(controls.count))
        let start = rect.x + (rect.width - width * Double(controls.count)) / 2
        return controls.enumerated().map { index, control in
            (control, .init(start + Double(index) * width, rect.y + rect.height - (rect.height < 80 ? 25 : 42), width, rect.height < 80 ? 22 : 34))
        }
    }
}
