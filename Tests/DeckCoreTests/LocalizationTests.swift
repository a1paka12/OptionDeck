import Testing
@testable import DeckCore

@Test func languageSelectionTranslatesAndFormatsWithoutChangingUserText() {
    let language = DeckLanguage.shared
    defer { language.set(nil) }
    language.set("en")
    #expect(L("밝기") == "Brightness")
    #expect(L("%@ 메뉴 단축키", "Finder") == "Finder menu shortcuts")
    #expect(L("User-defined name") == "User-defined name")
    language.set("ko")
    #expect(L("밝기") == "밝기")
    #expect(L("%@ 메뉴 단축키", "Finder") == "Finder 메뉴 단축키")
}
