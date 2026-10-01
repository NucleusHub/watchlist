import Foundation

/// A signed-in Nucleus ID session, kept in the keychain. Same fields the first app stored,
/// so a session carried over from it keeps working.
struct NucleusSession: Codable, Equatable {
    struct User: Codable, Equatable {
        var sub: String
        var handle: String
        var name: String
        var email: String?
    }

    var accessToken: String
    var refreshToken: String
    /// Milliseconds since 1970, as the first app wrote it.
    var expiresAt: Double
    var user: User

    var expiresDate: Date { Date(timeIntervalSince1970: expiresAt / 1000) }

    static func load() -> NucleusSession? {
        Keychain.get(.nucleusSession).flatMap { try? JSONDecoder().decode(NucleusSession.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Keychain.set(data, for: .nucleusSession) }
    }

    static func clear() { Keychain.delete(.nucleusSession) }
}

/// Where sync left off: the account copy's version and whether this device has unsent changes.
struct SyncState: Codable, Equatable {
    var version: Int?
    var lastSyncedAt: String?
    var dirty: Bool = false

    private static let key = "syncState"

    static func load(_ defaults: UserDefaults = .standard) -> SyncState {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SyncState.self, from: $0) } ?? SyncState()
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    static func clear(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}
