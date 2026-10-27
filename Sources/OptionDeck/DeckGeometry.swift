import Foundation
import DeckCore
import DeckEngineBridge

struct DeckTile: Codable, Equatable {
    var id: String
    var columns: Int
    var rows: Int
}
struct DeckLayouts: Codable, Equatable {
    var system: [DeckTile]
    var actions: [DeckTile]
    static var defaults: DeckLayouts {
        .init(system: (0..<2).map { .init(id: "device:\($0)", columns: 3, rows: 2) }
              + [.init(id: "media:0", columns: 6, rows: 2)],
              actions: (0..<9).map { .init(id: "app:\($0)", columns: 2, rows: 1) })
    }
}
struct PackedDeckPage: Decodable {
    struct Placement: Decodable {
        let id: String
        let column: Int
        let row: Int
        let columns: Int
        let rows: Int
    }
    let tiles: [DeckTile]
    let placements: [Placement]
    let rows: Int
    func rect(_ id: String, page: Int) -> DeckRect {
        guard let item = placements.first(where: { $0.id == id }) else { return .init(0, 0, 0, 0) }
        let usedColumns = max(1, placements.map { $0.column + $0.columns }.max() ?? 1)
        let cellWidth = (640.0 - Double(usedColumns - 1) * 10) / Double(usedColumns)
        let cellHeight = ((page == 0 ? 328.0 : 228.0) - Double(rows - 1) * 10) / Double(rows)
        return .init(20 + Double(item.column) * (cellWidth + 10), 68 + Double(item.row) * (cellHeight + 10),
                     Double(item.columns) * (cellWidth + 10) - 10, Double(item.rows) * (cellHeight + 10) - 10)
    }
    func cellSize(page: Int) -> CGSize {
        let usedColumns = max(1, placements.map { $0.column + $0.columns }.max() ?? 1)
        return .init(width: (640.0 - Double(usedColumns - 1) * 10) / Double(usedColumns) + 10,
              height: ((page == 0 ? 328.0 : 228.0) - Double(rows - 1) * 10) / Double(rows) + 10)
    }
}
enum LayoutEngine {
    private struct Request: Encodable {
        let op: String
        let tiles: [DeckTile]
        var id: String?
        var columns: Int?
        var rows: Int?
        var from: String?
        var to: String?
    }
    private struct Response: Decodable { let layout: PackedDeckPage?; let error: String? }
    private static func perform(_ request: Request) throws -> PackedDeckPage {
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        guard let pointer = json.withCString({ od_layout_request($0) }) else { throw SettingsError(message: L("배치 엔진이 응답하지 않았어요")) }
        defer { od_engine_free(pointer) }
        let response = try JSONDecoder().decode(Response.self, from: Data(String(cString: pointer).utf8))
        guard let layout = response.layout else { throw SettingsError(message: response.error ?? L("배치를 계산하지 못했어요")) }
        return layout
    }
    static func pack(_ tiles: [DeckTile]) throws -> PackedDeckPage { try perform(.init(op: "pack", tiles: tiles)) }
    static func fit(_ tiles: [DeckTile]) throws -> PackedDeckPage {
        if let result = try? pack(tiles) { return result }
        guard let first = tiles.first else { return try pack([]) }
        return try resize(tiles, id: first.id, columns: first.columns, rows: first.rows)
    }
    static func resize(_ tiles: [DeckTile], id: String, columns: Int, rows: Int) throws -> PackedDeckPage {
        try perform(.init(op: "resize", tiles: tiles, id: id, columns: min(6, max(1, columns)), rows: min(4, max(1, rows))))
    }
    static func move(_ tiles: [DeckTile], from: String, to: String) throws -> PackedDeckPage {
        try perform(.init(op: "move", tiles: tiles, from: from, to: to))
    }
}
struct DeckGeometry {
    let pages: [PackedDeckPage]
    init(settings: DeckSettings) throws {
        let layouts = settings.resolvedLayouts
        pages = try [LayoutEngine.fit(layouts.system), LayoutEngine.fit(layouts.actions)]
    }
    func rect(_ id: String, page: Int) -> DeckRect { pages[page].rect(id, page: page) }
    func arrangement(settings: DeckSettings) -> DeckArrangement {
        let regions = pages.enumerated().map { page, packed in
            var result: [(DeckControl, DeckRect)] = []
            for tile in packed.tiles {
                let parts = tile.id.split(separator: ":")
                guard parts.count == 2, let index = Int(parts[1]) else { continue }
                let rect = packed.rect(tile.id, page: page)
                if parts[0] == "device" {
                    let control: DeckControl = settings.devices[index] == 0 ? .brightness : .volume
                    if control == .volume { result.append((.mute, Self.muteRect(rect))) }
                    result.append((control, rect))
                } else {
                    let feature = page == 0 ? settings.mediaFeatures[index] : settings.launcherFeatures[index]
                    if feature.isMediaWidget {
                        result += MediaWidgetLayout.buttons(in: rect)
                        result.append((.mediaSeek, MediaWidgetLayout.seek(in: rect)))
                    } else if feature.kind != .empty { result.append((page == 0 ? .feature(index) : .launch(index), rect)) }
                }
            }
            return result
        }
        return .init(pageRegions: regions)
    }
    static func muteRect(_ rect: DeckRect) -> DeckRect {
        .init(rect.x + (rect.width - 146) / 2, rect.y + rect.height - 36, 146, 32)
    }
}
