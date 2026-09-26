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

/// A stored, not yet accepted invitation.
struct PendingInvitation: Equatable, CustomStringConvertible {
    /// The link as received. Contains the voucher key — never log it.
    let rawLink: String
    let receivedAt: Date
    /// The link arrived before a wallet existed.
    let fromOnboarding: Bool

    /// Canonical `dashpay://invite?…` URI, or nil when the stored link is no
    /// longer recognized as an invitation.
    var normalizedURI: String? {
        DWInvitationLinkNormalizer.normalize(rawLink)
    }

    var description: String {
        "PendingInvitation(receivedAt: \(receivedAt), fromOnboarding: \(fromOnboarding), link: <redacted>)"
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

    enum ClearReason: String {
        case hidden
        case definitiveOutcome
        case claimed
        case wiped
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
    private let scope: () -> String
    private let hasRegisteredUsername: @MainActor () -> Bool
    private var observers: [NSObjectProtocol] = []

    init(storage: InvitationSecretStorage? = nil,
         defaults: UserDefaults = .standard,
         scope: @escaping () -> String = PendingInvitationStore.currentScope,
         hasRegisteredUsername: (@MainActor () -> Bool)? = nil) {
        self.storage = storage ?? KeychainInvitationSecretStorage()
        self.defaults = defaults
        self.scope = scope
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

    // MARK: - Scope

    /// `<networkRawValue>.<walletIdHex|unbound>` — the same scoping the
    /// Join DashPay dismissal uses, so a Testnet invitation never shows on
    /// Mainnet and one wallet's invitation never shows under another.
    nonisolated static func currentScope() -> String {
        scope(networkRawValue: WalletEnvironment.networkKind.rawValue,
              walletIdHex: WalletEnvironment.activeWalletIdHex as String?)
    }

    nonisolated static func scope(networkRawValue: Int, walletIdHex: String?) -> String {
        let wallet = walletIdHex.flatMap { $0.isEmpty ? nil : $0 } ?? "unbound"
        return "\(networkRawValue).\(wallet)"
    }

    /// The scope's network part, for the matching `unbound` slot.
    private static func unboundScope(for scope: String) -> String {
        let network = scope.split(separator: ".", maxSplits: 1).first.map(String.init) ?? scope
        return "\(network).unbound"
    }

    private func account(_ scope: String) -> String { Self.keychainPrefix + scope }
    private func metadataKey(_ scope: String) -> String { Self.metadataPrefix + scope }

    // MARK: - Reading

    /// Re-read the slot for the current scope (network or wallet may have
    /// changed underneath).
    func reload() {
        let loaded = load(scope())
        if loaded != pending {
            pending = loaded
        }
    }

    private func load(_ scope: String) -> PendingInvitation? {
        guard let data = storage.read(account(scope)),
              let rawLink = String(data: data, encoding: .utf8) else {
            return nil
        }
        let meta = defaults.dictionary(forKey: metadataKey(scope)) ?? [:]
        let receivedAt = (meta["receivedAt"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
        let fromOnboarding = meta["fromOnboarding"] as? Bool ?? false
        return PendingInvitation(rawLink: rawLink, receivedAt: receivedAt, fromOnboarding: fromOnboarding)
    }

    // MARK: - Writing

    /// Take in an opened link or a scanned QR payload.
    func receive(_ raw: String) -> ReceiveOutcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = DWInvitationLinkNormalizer.normalize(trimmed) else {
            return .notAnInvitation
        }
        let currentScope = scope()
        let hasWallet = !currentScope.hasSuffix(".unbound")
        // Only answerable once a wallet exists; before that the card reports
        // it after sync, as Android does. An identity without a username is
        // not enough to refuse: it may be the one this invitation already
        // created, and the card's check settles that.
        if hasWallet && hasRegisteredUsername() {
            return .alreadyHasIdentity
        }
        if let existing = load(currentScope) {
            if existing.rawLink == trimmed || existing.normalizedURI == normalized {
                pending = existing
                return .duplicate
            }
            return .busy
        }
        guard storage.write(Data(trimmed.utf8), account: account(currentScope)) else {
            Self.logger.error("🎟️ INVITE :: could not store the pending invitation in the Keychain")
            return .storageFailed
        }
        let invitation = PendingInvitation(rawLink: trimmed, receivedAt: Date(), fromOnboarding: !hasWallet)
        writeMetadata(invitation, scope: currentScope)
        pending = invitation
        Self.logger.info("🎟️ INVITE :: stored pending invitation (scope \(currentScope, privacy: .public))")
        return .stored
    }

    func receive(_ url: URL) -> ReceiveOutcome {
        receive(url.absoluteString)
    }

    /// Forget the invitation in the current scope. false when the Keychain
    /// item could not be deleted — the invitation is then still pending.
    @discardableResult
    func clear(reason: ClearReason) -> Bool {
        remove(scope: scope(), reason: reason)
    }

    /// Forget one specific invitation wherever it is stored — for a result
    /// that arrives after the user may have switched wallet or network, so
    /// "the current scope" is no longer the one the claim ran in. Another
    /// invitation is never touched. false when a matching item could not be
    /// deleted or the stored items could not be listed.
    @discardableResult
    func clear(normalizedURI: String, reason: ClearReason) -> Bool {
        guard let accounts = storage.accounts(withPrefix: Self.keychainPrefix) else {
            Self.logger.error("🎟️ INVITE :: could not list stored invitations to clear one")
            return false
        }
        var removedAll = true
        for account in accounts {
            let itemScope = String(account.dropFirst(Self.keychainPrefix.count))
            guard load(itemScope)?.normalizedURI == normalizedURI else { continue }
            removedAll = remove(scope: itemScope, reason: reason) && removedAll
        }
        return removedAll
    }

    private func remove(scope itemScope: String, reason: ClearReason) -> Bool {
        guard storage.delete(account(itemScope)) else {
            Self.logger.error("🎟️ INVITE :: could not delete the pending invitation (\(reason.rawValue, privacy: .public))")
            return false
        }
        defaults.removeObject(forKey: metadataKey(itemScope))
        if itemScope == scope(), pending != nil {
            pending = nil
        }
        Self.logger.info("🎟️ INVITE :: cleared pending invitation (\(reason.rawValue, privacy: .public))")
        return true
    }

    /// Move an invitation received before the wallet existed under the newly
    /// created wallet's scope. The unbound copy is removed only once the
    /// invitation is safely under the wallet (or the wallet already has one
    /// pending, which wins); on a failed write it stays for the next attempt,
    /// and false is returned.
    @discardableResult
    func bindUnboundToCurrentWallet() -> Bool {
        let currentScope = scope()
        let unbound = Self.unboundScope(for: currentScope)
        guard currentScope != unbound, let invitation = load(unbound) else {
            reload()
            return true
        }
        if load(currentScope) == nil {
            guard storage.write(Data(invitation.rawLink.utf8), account: account(currentScope)) else {
                Self.logger.error("🎟️ INVITE :: could not move the pre-onboarding invitation under the wallet")
                reload()
                return false
            }
            writeMetadata(
                PendingInvitation(rawLink: invitation.rawLink, receivedAt: invitation.receivedAt, fromOnboarding: true),
                scope: currentScope)
        }
        _ = remove(scope: unbound, reason: .movedToWallet)
        reload()
        return true
    }

    private func writeMetadata(_ invitation: PendingInvitation, scope: String) {
        defaults.set([
            "receivedAt": invitation.receivedAt.timeIntervalSince1970,
            "fromOnboarding": invitation.fromOnboarding,
        ], forKey: metadataKey(scope))
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
        guard let accounts = storage.accounts(withPrefix: Self.keychainPrefix) else {
            Self.logger.error("🎟️ INVITE :: could not list stored invitations to wipe them")
            return false
        }
        var removedAll = true
        for account in accounts {
            let itemScope = String(account.dropFirst(Self.keychainPrefix.count))
            removedAll = remove(scope: itemScope, reason: .wiped) && removedAll
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
