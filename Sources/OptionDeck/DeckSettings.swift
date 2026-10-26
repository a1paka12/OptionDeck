import Foundation
import DeckEngineBridge

struct DeckSettings: Codable, Equatable {
    var apps: [LauncherGuide] = launcherGuides
    var devices: [Int] = [0, 1]
    var media: [Int] = Array(0..<6)
    var automatic_shortcuts = true
    var layouts: DeckLayouts?
    var music_app: LauncherGuide?
    var media_features: [DeckFeature]?
    var launcher_features: [DeckFeature]?
    var mediaFeatures: [DeckFeature] { media_features ?? DeckFeature.groupedDefaults }
    var launcherFeatures: [DeckFeature] { launcher_features ?? apps.map(DeckFeature.app) }
    var resolvedLayouts: DeckLayouts {
        layouts ?? .init(system: (0..<2).map { .init(id: "device:\($0)", columns: 3, rows: 2) }
            + mediaFeatures.enumerated().map { .init(id: "media:\($0.offset)", columns: $0.element.isMediaWidget ? 6 : 2, rows: $0.element.isMediaWidget ? 2 : 1) },
            actions: launcherFeatures.indices.map { .init(id: "app:\($0)", columns: 2, rows: 1) })
    }
    mutating func appendFeature(_ feature: DeckFeature, section: String) -> Int {
        if section == "media" { var values = mediaFeatures; let index = values.count; values.append(feature); media_features = values; return index }
        var values = launcherFeatures; let index = values.count; values.append(feature); launcher_features = values; return index
    }
    mutating func removeFeature(section: String, index: Int) {
        if section == "media" { var values = mediaFeatures; values.remove(at: index); media_features = values }
        else { var values = launcherFeatures; values.remove(at: index); launcher_features = values }
    }
    mutating func setFeature(_ feature: DeckFeature, section: String, index: Int) {
        if section == "media" {
            var values = mediaFeatures; values[index] = feature; media_features = values
        } else {
            var values = launcherFeatures; values[index] = feature; launcher_features = values
        }
    }
    mutating func swapFeatures(_ from: Int, section: String, with to: Int, otherSection: String) {
        let source = section == "media" ? mediaFeatures[from] : launcherFeatures[from]
        let target = otherSection == "media" ? mediaFeatures[to] : launcherFeatures[to]
        setFeature(target, section: section, index: from)
        setFeature(source, section: otherSection, index: to)
    }
}

struct SettingsDocument: Codable {
    var schema: Int
    var revision: UInt64
    var settings: DeckSettings
}

// Swift holds a UI snapshot. Rust owns validation, locking, revision checks and persistence.
enum SettingsEngine {
    private struct Response: Decodable {
        let document: SettingsDocument?
        let error: String?
    }
    private struct Request: Encodable {
        let op: String
        var expected_revision: UInt64? = nil
        var settings: DeckSettings? = nil
    }
    static var path: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OptionDeck/settings.json").path
    }
    private static func request(_ request: Request) throws -> SettingsDocument {
        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)
        let pointer = path.withCString { path in json.withCString { od_engine_request(path, $0) } }
        guard let pointer else { throw SettingsError(message: "Rust 엔진이 응답하지 않았어요") }
        defer { od_engine_free(pointer) }
        let response = try JSONDecoder().decode(Response.self, from: Data(String(cString: pointer).utf8))
        guard let document = response.document else {
            let message = response.error ?? "설정을 읽지 못했어요"
            throw SettingsError(message: message.hasPrefix("conflict:") ? "다른 창이나 프로세스에서 설정이 바뀌었어요. 다시 불러온 뒤 저장해 주세요." : message)
        }
        return document
    }
    static func load() throws -> SettingsDocument { try request(.init(op: "load")) }
    static func save(_ settings: DeckSettings, revision: UInt64) throws -> SettingsDocument {
        try request(.init(op: "save", expected_revision: revision, settings: settings))
    }
}
struct SettingsError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
