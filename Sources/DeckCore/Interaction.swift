import Foundation

public struct DeckPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public struct DeckRect: Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func contains(_ p: DeckPoint) -> Bool {
        p.x >= x && p.x < x + width && p.y >= y && p.y < y + height
    }
}

public enum DeckControl: Hashable, Sendable {
    case brightness, volume, mute, mediaSeek
    case previous, playback, next, backwardSkip, forwardSkip, systemMedia
    case feature(Int), launch(Int), shortcut(Int), moreShortcuts, refreshShortcuts
    case previousPage, nextPage
    public var isContinuous: Bool {
        switch self {
        case .brightness, .volume, .mediaSeek: true
        default: false
        }
    }
}

public struct DeckArrangement: Sendable {
    public var pageRegions: [[(DeckControl, DeckRect)]]?
    public var devices: [DeckControl]
    public var media: [DeckControl]
    public init(devices: [DeckControl] = [.brightness, .volume], media: [DeckControl] = [.previous, .playback, .next, .systemMedia, .backwardSkip, .forwardSkip], pageRegions: [[(DeckControl, DeckRect)]]? = nil) {
        self.pageRegions = pageRegions
        self.devices = Set(devices) == Set([.brightness, .volume]) && devices.count == 2 ? devices : [.brightness, .volume]
        let defaults: [DeckControl] = [.previous, .playback, .next, .systemMedia, .backwardSkip, .forwardSkip]
        self.media = media.count == 6 && (Set(media) == Set(defaults) || Set(media) == Set((0..<6).map { DeckControl.feature($0) })) ? media : defaults
    }
}

public enum DeckLayout {
    public static let width = 680.0
    public static let height = 460.0
    public static let deviceControls: [DeckControl] = [.brightness, .volume]
    public static func deviceColumn(_ index: Int) -> DeckRect {
        DeckRect(20 + Double(index) * 326, 68, 314, 200)
    }
    public static func column(_ index: Int, y: Double, height: Double) -> DeckRect {
        DeckRect(20 + Double(index) * 163, y, 151, height)
    }
    public static func launcher(_ index: Int) -> DeckRect {
        DeckRect(20 + Double(index % 3) * (652.0 / 3), 68 + Double(index / 3) * 78, 616.0 / 3, 68)
    }
    public static func shortcut(_ index: Int) -> DeckRect {
        DeckRect(32 + Double(index % 2) * 320, 329 + Double(index / 2) * 30, 296, 28)
    }
    public static let mediaSlots: [DeckRect] = [
        .init(247, 293, 48, 48), .init(310, 289, 56, 56), .init(381, 293, 48, 48),
        .init(480, 293, 160, 44), .init(40, 350, 284, 36), .init(356, 350, 284, 36)
    ]
    public static func muteRect(arrangement: DeckArrangement) -> DeckRect {
        let column = arrangement.devices.firstIndex(of: .volume) ?? 1
        return DeckRect(104 + Double(column) * 326, 228, 146, 32)
    }
    public static func regions(page: Int, arrangement: DeckArrangement = .init()) -> [(DeckControl, DeckRect)] {
        var result: [(DeckControl, DeckRect)] = [
            (.previousPage, DeckRect(20, 414, 40, 30)),
            (.nextPage, DeckRect(620, 414, 40, 30))
        ]
        if let pages = arrangement.pageRegions, pages.indices.contains(page) {
            result += pages[page]
            if page == 1 {
                result += (0..<4).map { (.shortcut($0), shortcut($0)) }
                result += [(.refreshShortcuts, DeckRect(576, 306, 30, 22)), (.moreShortcuts, DeckRect(612, 306, 32, 22))]
            }
            return result
        }
        if page == 0 {
            result += [(.mute, muteRect(arrangement: arrangement))]
            result += arrangement.media.enumerated().map { ($0.element, mediaSlots[$0.offset]) }
            result += arrangement.devices.enumerated().map { ($0.element, deviceColumn($0.offset)) }
        } else {
            result += (0..<9).map { (.launch($0), launcher($0)) }
            result += (0..<4).map { (.shortcut($0), shortcut($0)) }
            result += [(.refreshShortcuts, DeckRect(576, 306, 30, 22)), (.moreShortcuts, DeckRect(612, 306, 32, 22))]
        }
        return result
    }
    public static func target(at normalized: DeckPoint, page: Int, arrangement: DeckArrangement = .init()) -> DeckControl? {
        guard normalized.x.isFinite, normalized.y.isFinite,
              (0..<1).contains(normalized.x), (0..<1).contains(normalized.y) else { return nil }
        let point = DeckPoint(normalized.x * width, normalized.y * height)
        return regions(page: page, arrangement: arrangement).first { $0.1.contains(point) }?.0
    }
}

public struct DeckContact: Sendable {
    public let id: Int
    public let point: DeckPoint
    public init(id: Int, point: DeckPoint) { self.id = id; self.point = point }
}

public enum DeckAction: Equatable, Sendable {
    case focus(DeckControl?)
    case adjust(DeckControl, Double)
    case tap(DeckControl)
    case page(Int)
    case end
    case cancel
}

public struct GestureEngine: Sendable {
    private var id: Int?
    private var origin = DeckPoint(0, 0)
    private var previous = DeckPoint(0, 0)
    private var started = 0.0
    private var movement = 0.0
    private var target: DeckControl?
    private var multi = false
    private var multiOrigin: Double?
    private var pageChanged = false
    private var adjustmentLocked = false
    private var navigationAnchor = DeckPoint(0, 0)
    private var horizontalTravel = 0.0

    public init() {}
    public mutating func cancel() { self = GestureEngine() }

    public mutating func update(_ contacts: [DeckContact], time: Double, page: Int, arrangement: DeckArrangement = .init()) -> [DeckAction] {
        let valid = contacts.filter { $0.point.x.isFinite && $0.point.y.isFinite &&
            (0...1).contains($0.point.x) && (0...1).contains($0.point.y) }
        guard valid.count == contacts.count else { cancel(); return [.cancel] }
        if valid.isEmpty {
            defer { cancel() }
            guard id != nil || multi else { return [] }
            var actions: [DeckAction] = []
            if !multi, let target, !target.isContinuous,
               time - started < 0.5, movement < 0.025,
               DeckLayout.target(at: previous, page: page, arrangement: arrangement) == target {
                actions.append(.tap(target))
            }
            actions += [.focus(nil), .end]
            return actions
        }
        if valid.count > 1 {
            let x = valid.map(\.point.x).reduce(0, +) / Double(valid.count)
            if !multi {
                multi = true; multiOrigin = x; target = nil
                return [.cancel]
            }
            if valid.count == 2, !pageChanged, let start = multiOrigin, abs(x - start) > 0.12 {
                pageChanged = true
                let destination = min(1, max(0, page + (x < start ? 1 : -1)))
                return destination == page ? [] : [.page(destination)]
            }
            return []
        }
        guard !multi, let contact = valid.first else { return [] }
        if id == nil {
            id = contact.id; origin = contact.point; previous = contact.point
            started = time; target = DeckLayout.target(at: contact.point, page: page, arrangement: arrangement)
            navigationAnchor = contact.point
            return [.focus(target)]
        }
        guard id == contact.id else {
            cancel()
            // A changed identity is a cancellation, never a tap.
            return [.cancel]
        }
        let point = contact.point
        movement = max(movement, hypot(point.x - origin.x, point.y - origin.y))
        let delta = DeckPoint(point.x - previous.x, point.y - previous.y)
        previous = point
        if !adjustmentLocked {
            let candidate = DeckLayout.target(at: point, page: page, arrangement: arrangement)
            let vertical = point.y - navigationAnchor.y
            let horizontal = point.x - navigationAnchor.x
            if let target, target.isContinuous, abs(vertical) > 0.018, abs(vertical) > abs(horizontal) * 1.25 {
                adjustmentLocked = true
                horizontalTravel = 0
                return [] // Acquire the slider without applying the acquisition movement.
            }
            if abs(horizontal) >= abs(vertical) || candidate != target {
                navigationAnchor = point
            }
            if candidate != target {
                target = candidate
                return [.focus(candidate)]
            }
            return []
        }
        guard let target else { return [] }
        guard target.isContinuous else { return [] }
        if abs(delta.x) > abs(delta.y) * 2 {
            horizontalTravel += abs(delta.x)
            if horizontalTravel > 0.045 {
                adjustmentLocked = false
                horizontalTravel = 0
                navigationAnchor = point
                let candidate = DeckLayout.target(at: point, page: page, arrangement: arrangement)
                self.target = candidate
                return [.focus(candidate)]
            }
            // Ignore vertical jitter while the finger is moving sideways to browse.
            return []
        }
        horizontalTravel = 0
        let value = -delta.y * DeckLayout.height / 180
        return abs(value) > 0.0001 ? [.adjust(target, value)] : []
    }

}
