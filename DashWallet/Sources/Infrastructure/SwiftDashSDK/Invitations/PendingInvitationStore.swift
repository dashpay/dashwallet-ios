//
//  PendingInvitationStore.swift
//  DashWallet
//
//  The one DashPay invitation waiting to be accepted, per network + wallet.
//
//  An opened invitation link (or a scanned invitation QR) is stored here and
//  surfaces as the Home card; the card validates it once the chain is synced
//  and hands it to the create-username flow. Android keeps the same single
//  slot (`DashPayConfig.INVITATION_LINK`) and drops a second link while one
//  is pending.
//
//  The link carries the voucher private key (`pk`), so it is a bearer secret:
//  it lives in the Keychain only, never in UserDefaults, and is never logged.
//  It is stored exactly as received and normalized on every read, so a later
//  change of the canonical link form touches `DWInvitationLinkNormalizer`
//  only, never stored data.
//

import Combine
import Foundation
import OSLog
import SwiftDashSDK

/// The network + wallet an invitation belongs to. Explicit on every stored
/// invitation and every mutation, so a result that arrives after a wallet or
/// network switch still names the slot it was about — "the current scope" is
/// read only when something new comes in.
struct InvitationScope: Hashable, CustomStringConvertible {
    let networkRawValue: Int
    /// nil before a wallet exists (an invitation opened during onboarding).
    let walletIdHex: String?

    init(networkRawValue: Int, walletIdHex: String?) {
        self.networkRawValue = networkRawValue
        self.walletIdHex = walletIdHex.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The active network and wallet right now.
    static var current: InvitationScope {
        InvitationScope(
            networkRawValue: WalletEnvironment.networkKind.rawValue,
            walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
    }

    var isUnbound: Bool { walletIdHex == nil }

    /// The pre-wallet slot on the same network.
    var unbound: InvitationScope { InvitationScope(networkRawValue: networkRawValue, walletIdHex: nil) }

    /// `<networkRawValue>.<walletIdHex|unbound>` — the same scoping the Join
    /// DashPay dismissal uses.
    var storageKey: String { "\(networkRawValue).\(walletIdHex ?? "unbound")" }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let network = Int(parts[0]) else { return nil }
        self.init(networkRawValue: network, walletIdHex: parts[1] == "unbound" ? nil : parts[1])
    }

    var description: String { storageKey }
}

/// A stored, not yet accepted invitation.
struct PendingInvitation: Equatable, CustomStringConvertible {
    /// The link as received. Contains the voucher key — never log it.
    let rawLink: String
    let receivedAt: Date
    /// The link arrived before a wallet existed.
    let fromOnboarding: Bool
    /// Where it is stored.
    let scope: InvitationScope

    /// Canonical `dashpay://invite?…` URI, or nil when the stored link is no
    /// longer recognized as an invitation.
    var normalizedURI: String? {
        DWInvitationLinkNormalizer.normalize(rawLink)
    }

    var description: String {
        "PendingInvitation(scope: \(scope), receivedAt: \(receivedAt), fromOnboarding: \(fromOnboarding), link: <redacted>)"
    }
}

/// Where the bearer secret is kept. A seam so the store's decisions can be
/// tested with failing writes and deletes; production is the Keychain.
@MainActor
protocol InvitationSecretStorage: AnyObject {
    func read(_ account: String) -> Data?
    /// false when the item could not be written.
    func write(_ data: Data, account: String) -> Bool
    /// true when the item is gone — deleted, or was never there.
    func delete(_ account: String) -> Bool
    /// Every account starting with `prefix`; nil when they cannot be listed.
    func accounts(withPrefix prefix: String) -> [String]?
}

/// The Keychain, through the SDK's `KeychainManager` service (items are
/// `WhenUnlockedThisDeviceOnly`, never synchronized).
@MainActor
final class KeychainInvitationSecretStorage: InvitationSecretStorage {
    private let keychain: KeychainManager

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    func read(_ account: String) -> Data? {
        keychain.retrieveKeyData(identifier: account)
    }

    func write(_ data: Data, account: String) -> Bool {
        keychain.storeKeyData(data, identifier: account) != nil
    }

    func delete(_ account: String) -> Bool {
        keychain.deleteKeyData(identifier: account)
    }

    func accounts(withPrefix prefix: String) -> [String]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return nil }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }
    }
}

@MainActor
final class PendingInvitationStore: ObservableObject {

    static let shared = PendingInvitationStore()

    enum ReceiveOutcome: Equatable {
        /// Stored; the Home card shows it.
        case stored
        /// The same link is already pending; nothing changed.
        case duplicate
        /// A different invitation is already pending; the new one is dropped.
        case busy
        /// Not an invitation link.
        case notAnInvitation
        /// This wallet already has a DashPay username; nothing stored.
        case alreadyHasIdentity
        /// A valid invitation that could not be written to the Keychain.
        /// Nothing is stored; opening the link again retries.
        case storageFailed
    }

    enum RemovalReason: String {
        case hidden
        case definitiveOutcome
        case claimed
        case wiped
        case walletRemoved
        /// The pre-onboarding copy, once it is safely under the new wallet.
        case movedToWallet
    }

    /// The invitation pending in the current network + wallet scope.
    @Published private(set) var pending: PendingInvitation?

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.invitations")

    /// Keychain account prefix; every stored invitation lives under it.
    static let keychainPrefix = "invitation.pending."
    private static let metadataPrefix = "pendingInvitationMeta."

    private let storage: InvitationSecretStorage
    private let defaults: UserDefaults
    private let currentScope: () -> InvitationScope
    private let hasRegisteredUsername: @MainActor () -> Bool
    private var observers: [NSObjectProtocol] = []

    init(storage: InvitationSecretStorage? = nil,
         defaults: UserDefaults = .standard,
         currentScope: @escaping () -> InvitationScope = { InvitationScope.current },
         hasRegisteredUsername: (@MainActor () -> Bool)? = nil) {
        self.storage = storage ?? KeychainInvitationSecretStorage()
        self.defaults = defaults
        self.currentScope = currentScope
        self.hasRegisteredUsername = hasRegisteredUsername
            ?? { DWCurrentUserIdentityInfo.shared.username?.isEmpty == false }
        reload()
        observers.append(NotificationCenter.default.addObserver(
            forName: SwiftDashSDKWalletState.activeWalletDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func account(_ scope: InvitationScope) -> String { Self.keychainPrefix + scope.storageKey }
    private func metadataKey(_ scope: InvitationScope) -> String { Self.metadataPrefix + scope.storageKey }

    // MARK: - Reading

    /// Re-read the slot for the current scope (network or wallet may have
    /// changed underneath). Once a wallet exists, an invitation opened before
    /// it is moved under it first — every reload is a retry of that move.
    func reload() {
        let scope = currentScope()
        if !scope.isUnbound {
            bindUnbound(into: scope)
        }
        let loaded = load(scope)
        if loaded != pending {
            pending = loaded
        }
    }

    private func load(_ scope: InvitationScope) -> PendingInvitation? {
        guard let data = storage.read(account(scope)),
              let rawLink = String(data: data, encoding: .utf8) else {
            return nil
        }
        let meta = defaults.dictionary(forKey: metadataKey(scope)) ?? [:]
        let receivedAt = (meta["receivedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        let fromOnboarding = meta["fromOnboarding"] as? Bool ?? false
        return PendingInvitation(rawLink: rawLink, receivedAt: receivedAt, fromOnboarding: fromOnboarding, scope: scope)
    }

    private func storedScopes() -> [InvitationScope]? {
        storage.accounts(withPrefix: Self.keychainPrefix)?
            .compactMap { InvitationScope(storageKey: String($0.dropFirst(Self.keychainPrefix.count))) }
    }

    // MARK: - Writing

    /// Take in an opened link or a scanned QR payload, for the current scope.
    func receive(_ raw: String) -> ReceiveOutcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = DWInvitationLinkNormalizer.normalize(trimmed) else {
            return .notAnInvitation
        }
        let scope = currentScope()
        // Only answerable once a wallet exists; before that the card reports
        // it after sync, as Android does. An identity without a username is
        // not enough to refuse: it may be the one this invitation already
        // created, and the card's check settles that.
        if !scope.isUnbound && hasRegisteredUsername() {
            return .alreadyHasIdentity
        }
        if let existing = load(scope) {
            if existing.rawLink == trimmed || existing.normalizedURI == normalized {
                pending = existing
                return .duplicate
            }
            return .busy
        }
        guard storage.write(Data(trimmed.utf8), account: account(scope)) else {
            Self.logger.error("🎟️ INVITE :: could not store the pending invitation in the Keychain")
            return .storageFailed
        }
        let invitation = PendingInvitation(
            rawLink: trimmed, receivedAt: Date(), fromOnboarding: scope.isUnbound, scope: scope)
        writeMetadata(invitation)
        pending = invitation
        Self.logger.info("🎟️ INVITE :: stored pending invitation (scope \(scope.storageKey, privacy: .public))")
        return .stored
    }

    func receive(_ url: URL) -> ReceiveOutcome {
        receive(url.absoluteString)
    }

    /// Forget this invitation in its own scope — a fact about that wallet
    /// (hidden there, or refused for that wallet). A different invitation
    /// stored there since is left alone. false when the Keychain item could
    /// not be deleted; the invitation is then still pending.
    @discardableResult
    func remove(_ invitation: PendingInvitation, reason: RemovalReason) -> Bool {
        guard let stored = load(invitation.scope), stored.rawLink == invitation.rawLink else {
            return true
        }
        return remove(scope: invitation.scope, reason: reason)
    }

    /// Forget an invitation wherever it is stored — for facts about the
    /// voucher itself (claimed, spent, malformed), which hold in every wallet.
    /// Another invitation is never touched. false when a matching item could
    /// not be deleted or the stored items could not be listed.
    @discardableResult
    func removeEverywhere(normalizedURI: String, reason: RemovalReason) -> Bool {
        guard let scopes = storedScopes() else {
            Self.logger.error("🎟️ INVITE :: could not list stored invitations to remove one")
            return false
        }
        var removedAll = true
        for scope in scopes where load(scope)?.normalizedURI == normalizedURI {
            removedAll = remove(scope: scope, reason: reason) && removedAll
        }
        return removedAll
    }

    /// Forget every invitation stored for a wallet that is being removed
    /// (wallet ids are per network, so this is at most one slot). false when
    /// one could not be deleted or the stored items could not be listed.
    @discardableResult
    func removeAll(walletIdHex: String) -> Bool {
        guard let scopes = storedScopes() else {
            Self.logger.error("🎟️ INVITE :: could not list stored invitations for a removed wallet")
            return false
        }
        var removedAll = true
        for scope in scopes where scope.walletIdHex == walletIdHex {
            removedAll = remove(scope: scope, reason: .walletRemoved) && removedAll
        }
        return removedAll
    }

    private func remove(scope: InvitationScope, reason: RemovalReason) -> Bool {
        guard storage.delete(account(scope)) else {
            Self.logger.error("🎟️ INVITE :: could not delete the pending invitation (\(reason.rawValue, privacy: .public))")
            return false
        }
        defaults.removeObject(forKey: metadataKey(scope))
        if scope == currentScope(), pending != nil {
            pending = nil
        }
        Self.logger.info("🎟️ INVITE :: removed pending invitation (\(reason.rawValue, privacy: .public))")
        return true
    }

    /// Move an invitation received before the wallet existed under `wallet`.
    /// The unbound copy is removed only once the invitation is safely there
    /// (or the wallet already has one pending, which wins); on a failed write
    /// it stays and the next reload tries again.
    @discardableResult
    private func bindUnbound(into wallet: InvitationScope) -> Bool {
        guard let invitation = load(wallet.unbound) else { return true }
        if load(wallet) == nil {
            guard storage.write(Data(invitation.rawLink.utf8), account: account(wallet)) else {
                Self.logger.error("🎟️ INVITE :: could not move the pre-onboarding invitation under the wallet")
                return false
            }
            writeMetadata(PendingInvitation(
                rawLink: invitation.rawLink, receivedAt: invitation.receivedAt, fromOnboarding: true, scope: wallet))
        }
        return remove(scope: wallet.unbound, reason: .movedToWallet)
    }

    private func writeMetadata(_ invitation: PendingInvitation) {
        defaults.set([
            "receivedAt": invitation.receivedAt.timeIntervalSince1970,
            "fromOnboarding": invitation.fromOnboarding,
        ], forKey: metadataKey(invitation.scope))
    }

    /// Delete every stored invitation, across networks and wallets (wallet
    /// wipe). false when any could not be deleted.
    @discardableResult
    static func wipeAll() -> Bool {
        shared.wipeAllScopes()
    }

    /// `wipeAll` for this store's storage and defaults. Metadata is removed
    /// only for items that are gone, so a failure leaves a consistent slot.
    @discardableResult
    func wipeAllScopes() -> Bool {
        guard let scopes = storedScopes() else {
            Self.logger.error("🎟️ INVITE :: could not list stored invitations to wipe them")
            return false
        }
        var removedAll = true
        for scope in scopes {
            removedAll = remove(scope: scope, reason: .wiped) && removedAll
        }
        // Metadata whose secret is already gone (a crash between the two
        // writes) is harmless, but nothing should outlive a wipe.
        if removedAll {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.metadataPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
        reload()
        return removedAll
    }
}
