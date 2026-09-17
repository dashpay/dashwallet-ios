import Foundation

/// A paid Core lock and a created identity need different recovery operations.
enum UsernameRegistrationRecovery: Equatable {
    case none
    case pendingCoreAssetLock
    case identityNeedsUsername(Data)

    var isPending: Bool { self != .none }

    var identityId: Data? {
        if case let .identityNeedsUsername(id) = self { return id }
        return nil
    }
}

/// A form draft, not a transaction journal. Never resumes a spend on launch.
struct UsernameRegistrationDraftStore {
    struct Scope: Equatable {
        let network: String
        let walletId: Data
        let identityId: Data

        fileprivate var key: String {
            let wallet = walletId.map { String(format: "%02x", $0) }.joined()
            let identity = identityId.map { String(format: "%02x", $0) }.joined()
            return "DWUsernameRegistrationDraft.v1.\(network).\(wallet).\(identity)"
        }
    }

    struct Draft: Codable, Equatable {
        let username: String
        let temporaryUsername: String?
    }

    var defaults: UserDefaults = .standard

    func draft(for scope: Scope) -> Draft? {
        guard let data = defaults.data(forKey: scope.key) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    func save(_ draft: Draft, for scope: Scope) throws {
        defaults.set(try JSONEncoder().encode(draft), forKey: scope.key)
    }

    func clear(for scope: Scope) {
        defaults.removeObject(forKey: scope.key)
    }
}

/// Reconciliation and submission share one boundary so a read failure can never
/// fall through to a broadcast. There is deliberately no funding operation here.
@MainActor
enum UsernameRegistrationRecoveryFlow {
    enum NameState: Equatable {
        case available
        case owned
        case voting
    }

    /// All identity creation/funding lives behind the create closure. An existing
    /// identity takes the resume branch regardless of external wallet balances.
    static func route(
        identityId: Data?,
        resume: (Data) async throws -> Data,
        create: () async throws -> Data
    ) async throws -> Data {
        if let identityId { return try await resume(identityId) }
        return try await create()
    }

    static func run(
        authorize: () async throws -> Void,
        validateContext: () throws -> Void,
        lookup: () async throws -> NameState,
        register: () async throws -> Void
    ) async throws -> NameState {
        try await authorize()
        try validateContext()
        let state = try await lookup()
        try validateContext()
        if state == .available {
            try await register()
            try validateContext()
        }
        return state
    }
}
