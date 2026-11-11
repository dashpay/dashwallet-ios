import Foundation
import SwiftDashSDK

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
            return "\(UsernameRegistrationDraftStore.keyPrefix)\(network).\(wallet).\(identity)"
        }
    }

    struct Draft: Codable, Equatable {
        let username: String
        let temporaryUsername: String?
    }

    static let keyPrefix = "DWUsernameRegistrationDraft.v1."

    var defaults: UserDefaults = .standard

    /// Drops the drafts of every identity of `walletIdHex` (lowercase hex) on
    /// every network. For wallet deletion: the wallet id comes back with the
    /// phrase, and so would the draft.
    func clearAll(walletIdHex: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            // <network>.<wallet>.<identity>, read from the end: only the
            // network part is free text.
            let parts = key.dropFirst(Self.keyPrefix.count).split(separator: ".")
            guard parts.count >= 3, parts[parts.count - 2] == walletIdHex else { continue }
            defaults.removeObject(forKey: key)
        }
    }

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

/// The last charged Shielded registration failure of one wallet on one
/// network: what the form's failure dialog and the Home / More row explain,
/// after a relaunch too. A charged failure has no identity, so the scope is
/// (network, wallet) — the same keys as the other registration records, and
/// cleared with them on wallet deletion and the full wipe.
struct ShieldedChargedFailureStore {
    struct Record: Codable, Equatable {
        let username: String
        let isContested: Bool
        let exitDenominationDuffs: UInt64
        /// `[addressType] + addressHash` of the Type-20 fallback. Never logged.
        let fallbackAddress: Data
        /// The fallback address's synced balance just before the Type-20 call.
        let snapshotCredits: UInt64
        /// nil while the wallet is still checking where the money went; set once.
        var returnedDuffs: UInt64?

        /// The record of a charged failure: the returned amount is unknown when it is written.
        static func charged(
            username: String, isContested: Bool, denominationCredits: UInt64,
            fallbackAddress: Data, snapshotCredits: UInt64
        ) -> Record {
            Record(
                username: username, isContested: isContested,
                exitDenominationDuffs: denominationCredits / ContestedUsernameFee.Amounts.creditsPerDuff,
                fallbackAddress: fallbackAddress, snapshotCredits: snapshotCredits, returnedDuffs: nil)
        }
    }

    static let baseKey = "shieldedChargedFailureRecord"

    var defaults: UserDefaults = .standard

    func record(networkRawValue: Int, walletIdHex: String?) -> Record? {
        guard let key = Self.key(networkRawValue: networkRawValue, walletIdHex: walletIdHex),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// Replaces any earlier record: a second failure never sums with the first.
    func save(_ record: Record, networkRawValue: Int, walletIdHex: String?) {
        guard let key = Self.key(networkRawValue: networkRawValue, walletIdHex: walletIdHex),
              let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    func clear(networkRawValue: Int, walletIdHex: String?) {
        guard let key = Self.key(networkRawValue: networkRawValue, walletIdHex: walletIdHex) else { return }
        defaults.removeObject(forKey: key)
    }

    /// The returned amount, once stated, never changes: the first value wins.
    func fixReturnedAmount(_ duffs: UInt64, networkRawValue: Int, walletIdHex: String?) {
        guard var stored = record(networkRawValue: networkRawValue, walletIdHex: walletIdHex),
              stored.returnedDuffs == nil else { return }
        stored.returnedDuffs = duffs
        save(stored, networkRawValue: networkRawValue, walletIdHex: walletIdHex)
    }

    /// nil for the `unbound` scope, which is no wallet's.
    private static func key(networkRawValue: Int, walletIdHex: String?) -> String? {
        guard let walletIdHex, !walletIdHex.isEmpty else { return nil }
        return JoinDashPayDismissalScope.scopedKey(baseKey, networkRawValue: networkRawValue, walletIdHex: walletIdHex)
    }
}

/// The words for a charged Shielded registration failure: a fixed first sentence, plus a second block that
/// says the wallet is still checking, or states the returned amount and, once it is known, what to add.
enum ShieldedChargedFailureExplanation {
    static var plain: String {
        NSLocalizedString("The registration did not go through.", comment: "Usernames")
    }

    static func text(returnedDuffs: UInt64?, amountToAddDuffs: UInt64?) -> (block1: String, block2: String?) {
        guard let returnedDuffs else {
            return (plain, NSLocalizedString("Checking where the money went…", comment: "Usernames"))
        }
        let returned = returnedDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol
        guard let amountToAddDuffs else {
            // A returned amount once stated stays stated; no advice until the amount to add is known.
            let format = NSLocalizedString("%@ Dash came back to your Platform balance.", comment: "Usernames")
            return (plain, String.localizedStringWithFormat(format, returned))
        }
        if amountToAddDuffs == 0 {
            let format = NSLocalizedString(
                "%@ Dash came back to your Platform balance — enough to register this username from it now.",
                comment: "Usernames")
            return (plain, String.localizedStringWithFormat(format, returned))
        }
        let format = NSLocalizedString(
            "%@ Dash came back to your Platform balance. Add %@ Dash there to try again.", comment: "Usernames")
        let toAdd = amountToAddDuffs.dashAmount.formattedDashAmountWithoutCurrencySymbol
        return (plain, String.localizedStringWithFormat(format, returned, toAdd))
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
/// unrecognised one reads "did not go through" when the registration was paid
/// from Shielded, and is passed through unchanged otherwise.
enum UsernameRegistrationFailureWording {
    /// The words for a failed registration's `error`. A coordinator error with a text of its own
    /// keeps it after a Shielded payment too; only raw platform or technical text reads plain.
    static func message(for error: Error, username: String, paidFromShielded: Bool) -> String {
        message(
            forRaw: error.localizedDescription, username: username,
            paidFromShielded: paidFromShielded && !hasOwnText(error))
    }

    /// A wrapper whose description is the wrapped error's text is judged by that error.
    static func hasOwnText(_ error: Error) -> Bool {
        guard let coordinatorError = error as? DWIdentityRegistrationCoordinator.CoordinatorError else {
            return false
        }
        switch coordinatorError {
        case let .identityRegistration(underlying), let .dpnsRegistration(underlying),
             let .keyDerivation(underlying), let .identityTopUp(underlying), let .availabilityCheck(underlying):
            return hasOwnText(underlying)
        default:
            return true
        }
    }

    static func message(forRaw raw: String, username: String, paidFromShielded: Bool = false) -> String {
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
        // DPNS document rejections, from the platform's consensus error texts.
        if raw.contains("has duplicate unique properties") || raw.contains("is already present") {
            return String.localizedStringWithFormat(
                NSLocalizedString("“%@” was just taken. Please choose a different username.", comment: "Usernames"),
                username)
        }
        if raw.contains("is not joinable") {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "Requests for “%@” are closed — its vote has started. Please choose a different username.",
                    comment: "Usernames"),
                username)
        }
        if raw.contains("contenders, the most a contest accepts") {
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "“%@” already has the most requests a vote accepts. Please choose a different username.",
                    comment: "Usernames"),
                username)
        }
        if raw.contains("is already a contestant for the vote_poll") {
            return String.localizedStringWithFormat(
                NSLocalizedString("You have already requested “%@”.", comment: "Usernames"),
                username)
        }
        if raw.contains("are out of block time window") {
            return NSLocalizedString("Check the date and time on your device, then try again.", comment: "Usernames")
        }
        return paidFromShielded ? ShieldedChargedFailureExplanation.plain : raw
    }
}

/// What a failed Type-20 create (`shieldedIdentityCreateFromPool`, after the
/// readiness pre-flight passed) means for the money that left the pool.
///
/// Charged when the platform wallet SDK proved, at the node the create went to,
/// that its inputs are spent and its identity was not created
/// (`PlatformWalletError.shieldedIdentityCreateInputsConsumed`, ADR-0035). The
/// usual cause is the paid failure path, which credits the rest to the fallback
/// address; the returned amount is stated only once that address is seen to rise
/// (ADR-0036). A node's rejection text proves nothing and is never read. A miss
/// can only fall to `.notClassified` or `.unknownOutcome`, never to a wrong
/// "money came back".
enum ShieldedCreateFailureKind: Equatable {
    /// No decided result yet: keeps the existing "still confirming" handling.
    case unknownOutcome
    case charged
    case notClassified

    static func classify(_ error: Error) -> ShieldedCreateFailureKind {
        if error is ShieldedIdentityCreateUnconfirmedError { return .unknownOutcome }
        if case .shieldedCreateUnconfirmed? = error as? DWIdentityRegistrationCoordinator.CoordinatorError {
            return .unknownOutcome
        }
        if case .stateTransitionResultUnconfirmed? = error as? SDKError { return .unknownOutcome }
        switch error as? PlatformWalletError {
        case .shieldedIdentityCreateInputsConsumed?: return .charged
        case .shieldedBroadcastUnconfirmed?, .transactionBroadcastUnconfirmed?, .shieldedSpendUnconfirmed?:
            return .unknownOutcome
        default: return .notClassified
        }
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
