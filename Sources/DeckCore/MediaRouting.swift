public enum MediaRoute: Equatable, Sendable {
    case system
    case preferredApp
    case unavailable

    public static func select(command: Int, outputActive: Bool?) -> MediaRoute {
        guard [2, 4, 5, 12, 13].contains(command) else { return .unavailable }
        if outputActive == true { return .system }
        // Never send a generic Play key without an output session: macOS may
        // launch its own default music app. Unknown state uses the same guard.
        return command == 2 ? .preferredApp : .unavailable
    }
}
