import AppKit

@MainActor
final class Haptics {
    private var lastTime = 0.0
    private func emit(_ pattern: NSHapticFeedbackManager.FeedbackPattern, interval: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTime >= interval else { return }
        lastTime = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
    func selection() { emit(.alignment, interval: 0.07) }
    func action() { emit(.generic, interval: 0.07) }
    func adjustment(from oldValue: Double, to newValue: Double) {
        if Int((oldValue * 20).rounded()) != Int((newValue * 20).rounded()) {
            emit(.levelChange, interval: 0.045)
        }
    }
}
