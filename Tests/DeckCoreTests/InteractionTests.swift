import Testing
@testable import DeckCore

private func touch(_ x: Double, _ y: Double, id: Int = 1) -> DeckContact {
    DeckContact(id: id, point: DeckPoint(x / 680, y / 460))
}
private func target(_ x: Double, _ y: Double, page: Int = 0) -> DeckControl? {
    DeckLayout.target(at: .init(x / 680, y / 460), page: page)
}

@Test func largerDeviceTargetsAndMediaButtonsHaveDistinctRegions() {
    #expect(target(250, 150) == .brightness)
    #expect(target(500, 150) == .volume)
    #expect(target(500, 245) == .mute)
    #expect(target(340, 150) == nil)
    #expect(target(80, 365) == .backwardSkip)
    #expect(target(400, 365) == .forwardSkip)
    #expect(target(550, 315) == .systemMedia)
    #expect(target(100, 50) == nil)
    #expect(DeckLayout.target(at: .init(.nan, 0.4), page: 0) == nil)
    #expect(DeckLayout.target(at: .init(-0.1, 0.4), page: 0) == nil)
}

@Test func allNineLaunchersAndFourShortcutsMatchTheirDisplayedCenters() {
    for index in 0..<9 {
        let rect = DeckLayout.launcher(index)
        #expect(target(rect.x + rect.width / 2, rect.y + rect.height / 2, page: 1) == .launch(index))
    }
    for index in 0..<4 {
        let rect = DeckLayout.shortcut(index)
        #expect(target(rect.x + rect.width / 2, rect.y + rect.height / 2, page: 1) == .shortcut(index))
    }
}

@Test func horizontalDiscoveryRetargetsWithoutChangingAnyValue() {
    var engine = GestureEngine()
    #expect(engine.update([touch(80, 180)], time: 0, page: 0) == [.focus(.brightness)])
    #expect(engine.update([touch(500, 180)], time: 0.1, page: 0) == [.focus(.volume)])
    #expect(engine.update([touch(500, 165)], time: 0.2, page: 0).isEmpty)
    let changes = engine.update([touch(500, 147)], time: 0.3, page: 0)
    if case .adjust(.volume, let amount) = changes.first { #expect(abs(amount - 0.1) < 0.00001) }
    else { Issue.record("Expected volume adjustment after vertical acquisition") }
}

@Test func verticalAdjustmentStaysLockedWhenCrossingAnotherRegion() {
    var engine = GestureEngine()
    _ = engine.update([touch(80, 200)], time: 0, page: 0)
    #expect(engine.update([touch(80, 180)], time: 0.1, page: 0).isEmpty)
    let actions = engine.update([touch(400, 0)], time: 0.2, page: 0)
    if case .adjust(.brightness, let delta) = actions.first { #expect(abs(delta - 1) < 0.00001) }
    else { Issue.record("Brightness should stay locked after acquiring it") }
    #expect(!engine.update([], time: 0.3, page: 0).contains(.tap(.brightness)))
}

@Test func sidewaysMotionReleasesSliderSoAnotherControlCanBeFoundWithoutLifting() {
    var engine = GestureEngine()
    _ = engine.update([touch(80, 200)], time: 0, page: 0)
    _ = engine.update([touch(80, 180)], time: 0.1, page: 0)
    _ = engine.update([touch(80, 162)], time: 0.2, page: 0)
    #expect(engine.update([touch(150, 162)], time: 0.3, page: 0) == [.focus(.brightness)])
    #expect(engine.update([touch(500, 162)], time: 0.4, page: 0) == [.focus(.volume)])
    #expect(engine.update([touch(500, 147)], time: 0.5, page: 0).isEmpty)
    let change = engine.update([touch(500, 129)], time: 0.6, page: 0)
    if case .adjust(.volume, let amount) = change.first { #expect(abs(amount - 0.1) < 0.00001) }
    else { Issue.record("Expected a new volume adjustment without lifting") }
}

@Test func sidewaysBrowsingDoesNotApplySmallVerticalJitterToSlider() {
    var engine = GestureEngine()
    _ = engine.update([touch(80, 200)], time: 0, page: 0)
    _ = engine.update([touch(80, 180)], time: 0.1, page: 0)
    #expect(engine.update([touch(90, 181)], time: 0.2, page: 0).isEmpty)
    #expect(engine.update([touch(100, 182)], time: 0.3, page: 0).isEmpty)
    let result = engine.update([touch(150, 183)], time: 0.4, page: 0)
    #expect(result == [.focus(.brightness)])
}

@Test func appDiscoveryUpdatesSelectionWithoutLaunching() {
    var engine = GestureEngine()
    #expect(engine.update([touch(90, 95)], time: 0, page: 1) == [.focus(.launch(0))])
    #expect(engine.update([touch(550, 250)], time: 0.1, page: 1) == [.focus(.launch(8))])
    let end = engine.update([], time: 0.2, page: 1)
    #expect(!end.contains(.tap(.launch(8))))
}

@Test func shortTapWorksButLongHoldAndTravelNeverLaunch() {
    var engine = GestureEngine()
    _ = engine.update([touch(90, 95)], time: 0, page: 1)
    #expect(engine.update([], time: 0.1, page: 1).contains(.tap(.launch(0))))
    _ = engine.update([touch(90, 95)], time: 1, page: 1)
    #expect(!engine.update([], time: 2, page: 1).contains(.tap(.launch(0))))
}

@Test func twoFingerSwipeCancelsAdjustmentAndChangesPageOnce() {
    var engine = GestureEngine()
    _ = engine.update([touch(80, 180)], time: 0, page: 0)
    #expect(engine.update([touch(300, 180), touch(400, 180, id: 2)], time: 0.1, page: 0) == [.cancel])
    #expect(engine.update([touch(190, 180), touch(290, 180, id: 2)], time: 0.2, page: 0) == [.page(1)])
    #expect(engine.update([touch(80, 180), touch(180, 180, id: 2)], time: 0.3, page: 1).isEmpty)
    #expect(engine.update([touch(80, 180)], time: 0.4, page: 1).isEmpty)
    #expect(engine.update([], time: 0.5, page: 1) == [.focus(nil), .end])
}

@Test func pageBoundariesNeverWrap() {
    var engine = GestureEngine()
    _ = engine.update([touch(250, 180), touch(350, 180, id: 2)], time: 0, page: 0)
    #expect(engine.update([touch(370, 180), touch(470, 180, id: 2)], time: 0.1, page: 0).isEmpty)
    engine.cancel()
    _ = engine.update([touch(250, 180), touch(350, 180, id: 2)], time: 0, page: 1)
    #expect(engine.update([touch(370, 180), touch(470, 180, id: 2)], time: 0.1, page: 1) == [.page(0)])
}

@Test func invalidContactAndChangedIdentityCancelInsteadOfTapping() {
    var engine = GestureEngine()
    _ = engine.update([touch(330, 315)], time: 0, page: 0)
    #expect(engine.update([touch(330, 315, id: 9)], time: 0.1, page: 0) == [.cancel])
    #expect(engine.update([], time: 0.2, page: 0).isEmpty)
    _ = engine.update([touch(330, 315)], time: 1, page: 0)
    #expect(engine.update([.init(id: 1, point: .init(.nan, 0.5))], time: 1.1, page: 0) == [.cancel])
}

@Test func accessibilityMenuModifiersUseTheCarbonMaskRatherThanEventFlags() {
    #expect(MenuKeyEquivalent.label(character: "p", virtualKey: nil, modifiers: 0) == "⌘ P")
    #expect(MenuKeyEquivalent.label(character: "p", virtualKey: nil, modifiers: 1) == "⇧ ⌘ P")
    #expect(MenuKeyEquivalent.label(character: "c", virtualKey: nil, modifiers: 12) == "⌃ C")
    #expect(MenuKeyEquivalent.label(character: " ", virtualKey: nil, modifiers: 8) == "Space")
    #expect(MenuKeyEquivalent.label(character: "", virtualKey: 123, modifiers: 0) == "⌘ ←")
    #expect(MenuKeyEquivalent.label(character: "\u{F704}", virtualKey: nil, modifiers: 8) == "F1")
    #expect(MenuKeyEquivalent.label(character: nil, virtualKey: nil, modifiers: 0) == nil)
}

@Test func rearrangedControlsUseTheSameGeometryForTouchAndDisplay() {
    let media: [DeckControl] = [.forwardSkip, .systemMedia, .backwardSkip, .next, .playback, .previous]
    let arrangement = DeckArrangement(devices: [.volume, .brightness], media: media)
    func hit(_ x: Double, _ y: Double) -> DeckControl? {
        DeckLayout.target(at: .init(x / 680, y / 460), page: 0, arrangement: arrangement)
    }
    #expect(hit(80, 150) == .volume)
    #expect(hit(500, 150) == .brightness)
    #expect(hit(175, 245) == .mute)
    #expect(hit(500, 245) == .brightness)
    for (index, control) in media.enumerated() {
        let rect = DeckLayout.mediaSlots[index]
        #expect(hit(rect.x + rect.width / 2, rect.y + rect.height / 2) == control)
    }
    var engine = GestureEngine()
    #expect(engine.update([touch(80, 200)], time: 0, page: 0, arrangement: arrangement) == [.focus(.volume)])
    _ = engine.update([touch(80, 180)], time: 0.1, page: 0, arrangement: arrangement)
    let actions = engine.update([touch(80, 162)], time: 0.2, page: 0, arrangement: arrangement)
    if case .adjust(.volume, let delta) = actions.first { #expect(abs(delta - 0.1) < 0.00001) }
    else { Issue.record("Reordered slider must adjust its displayed function") }
}

@Test func malformedArrangementFallsBackToCompleteDefaultRegions() {
    let arrangement = DeckArrangement(devices: [.volume, .volume], media: [.next])
    #expect(arrangement.devices == [.brightness, .volume])
    #expect(arrangement.media == DeckArrangement().media)
}

@Test func configurableActionSlotsKeepTouchIdentitySeparateFromTheirAssignedFunction() {
    let actions = (0..<6).map { DeckControl.feature($0) }
    let arrangement = DeckArrangement(media: actions)
    for index in 0..<6 {
        let rect = DeckLayout.mediaSlots[index]
        #expect(DeckLayout.target(at: .init((rect.x + rect.width / 2) / 680, (rect.y + rect.height / 2) / 460), page: 0, arrangement: arrangement) == .feature(index))
    }
}

@Test func groupedMediaControlsAndSeekMatchTheWidgetAtCompactAndLargeSizes() {
    for size in [(315.0, 159.0), (98.0, 49.0)] {
        let rect = DeckRect(20, 68, size.0, size.1)
        let buttons = MediaWidgetLayout.buttons(in: rect)
        let seek = MediaWidgetLayout.seek(in: rect)
        let arrangement = DeckArrangement(pageRegions: [buttons + [(.mediaSeek, seek)], []])
        for (control, target) in buttons + [(.mediaSeek, seek)] {
            #expect(DeckLayout.target(at: .init((target.x + target.width / 2) / 680, (target.y + target.height / 2) / 460), page: 0, arrangement: arrangement) == control)
            #expect(target.x >= rect.x && target.x + target.width <= rect.x + rect.width + 0.001)
        }
        #expect(DeckControl.mediaSeek.isContinuous)
    }
}
