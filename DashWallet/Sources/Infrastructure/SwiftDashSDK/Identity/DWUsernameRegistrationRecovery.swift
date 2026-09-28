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
    struct Scope: Hashable {
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
/// fall through to a broadcast. Funding is not decided here: whatever `register`
/// does (including topping up an existing identity) runs only after `lookup`
/// found the name still to be registered.
@MainActor
enum UsernameRegistrationRecoveryFlow {
    enum NameState: Equatable {
        case available
        case owned
        case voting
    }

    /// All identity creation lives behind the create closure. An existing
    /// identity always takes the resume branch — it is never created again; at
    /// most it is topped up to cover the name.
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
            // Broadcast success is final even if the UI context changes while awaiting it.
            try await register()
        }
        return state
    }
}

/// User-facing wording for a failed username registration, shared by the create
/// screen's alert and the Home / More registration row.
///
/// Platform surfaces its refusals as a Rust debug dump of the whole state
/// transition — hundreds of characters of `ContestedDocumentResourceVotePoll
/// { … }` that tell the user nothing. Recognised causes get a sentence; an
/// unrecognised one is passed through unchanged rather than swallowed.
enum UsernameRegistrationFailureWording {
    static func message(forRaw raw: String, username: String) -> String {
        // The vote poll ended in a LOCK: masternodes decided nobody gets the
        // name. Re-submitting can only fail the same way.
        if raw.contains("vote_poll_status: Locked") || raw.contains("is currently already locked") {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "“%@” was locked by a masternode vote, so it cannot be registered by anyone. Please choose a different username.",
                    comment: "Usernames"),
                username)
        }
        // The identity's own balance, and only that: "Insufficient identity …
        // balance … required …" (consensus), "identity insufficient balance"
        // (SDK pre-flight) or `PlatformWalletError.insufficientIdentityCredits`
        // ("Identity … has … credits but … are required."). A short wallet,
        // address or shielded balance has its own wording and must not be
        // reported as missing identity credits.
        if raw.localizedCaseInsensitiveContains("insufficient identity")
            || raw.localizedCaseInsensitiveContains("identity insufficient balance")
            || raw.range(of: #"Identity \S+ has \d+ credits but \d+ are required"#, options: .regularExpression) != nil {
            return NSLocalizedString(
                "Not enough identity credits to register this name. Use Top Up in My Profile, then try again. Your existing identity will be reused.",
                comment: "Identity recovery insufficient credits")
        }
        return raw
    }
}

/// A completed purchase may be adopted only in its original context. No await
/// can separate the check from reconciliation, so a wallet switch cannot race it.
@MainActor
enum UsernamePurchaseCompletion {
    static func reconcileIfCurrent(isCurrent: () -> Bool, reconcile: () -> Void) -> Bool {
        guard isCurrent() else { return false }
        reconcile()
        return true
    }
}

/// Per-context name reads are single-flight. Only successful reads establish
/// absence; failures require an explicit retry rather than a polling storm.
@MainActor
final class IdentityNameReadiness {
    private var loaded: Set<UsernameRegistrationDraftStore.Scope> = []
    private var attempts: [UsernameRegistrationDraftStore.Scope: UUID] = [:]

    func begin(_ scope: UsernameRegistrationDraftStore.Scope, refresh: Bool = false) -> UUID? {
        guard attempts[scope] == nil, refresh || !loaded.contains(scope) else { return nil }
        let generation = UUID()
        attempts[scope] = generation
        return generation
    }

    func isCurrent(_ scope: UsernameRegistrationDraftStore.Scope, generation: UUID) -> Bool {
        attempts[scope] == generation
    }

    func finish(_ scope: UsernameRegistrationDraftStore.Scope, generation: UUID, succeeded: Bool) {
        guard isCurrent(scope, generation: generation) else { return }
        if succeeded { loaded.insert(scope) }
    }

    func isLoaded(_ scope: UsernameRegistrationDraftStore.Scope) -> Bool { loaded.contains(scope) }
    // Invalidating generations lets a user replace a hung read; late completion
    // cannot overwrite the replacement. Keep previously established knowledge.
    func retry() { attempts.removeAll() }
    func retry(_ scope: UsernameRegistrationDraftStore.Scope) { attempts.removeValue(forKey: scope) }
}
