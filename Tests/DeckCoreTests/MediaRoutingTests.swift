import Testing
@testable import DeckCore

@Test func idleAndUnknownPlayNeverSendGlobalPlay() {
    #expect(MediaRoute.select(command: 2, outputActive: false) == .preferredApp)
    #expect(MediaRoute.select(command: 2, outputActive: nil) == .preferredApp)
}

@Test func existingOutputKeepsSystemControls() {
    for command in [2, 4, 5, 12, 13] {
        #expect(MediaRoute.select(command: command, outputActive: true) == .system)
    }
}

@Test func idleSkipCommandsCannotLaunchDefaultMusicApp() {
    for command in [4, 5, 12, 13] {
        #expect(MediaRoute.select(command: command, outputActive: false) == .unavailable)
        #expect(MediaRoute.select(command: command, outputActive: nil) == .unavailable)
    }
    #expect(MediaRoute.select(command: -1, outputActive: true) == .unavailable)
}
