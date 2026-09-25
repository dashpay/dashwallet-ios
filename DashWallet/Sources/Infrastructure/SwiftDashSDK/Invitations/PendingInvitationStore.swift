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
    }

    enum ClearReason: String {
        case hidden
        case definitiveOutcome
        case claimed
        case wiped
    }

    /// The invitation pending in the current network + wallet scope.
    @Published private(set) var pending: PendingInvitation?

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.invitations")

    /// Keychain account prefix; every stored invitation lives under it.
    static let keychainPrefix = "invitation.pending."
    private static let metadataPrefix = "pendingInvitationMeta."

    private let keychain: KeychainManager
    private let defaults: UserDefaults
    private let scope: () -> String
    private let hasRegisteredUsername: @MainActor () -> Bool
    private var observers: [NSObjectProtocol] = []

    init(keychain: KeychainManager = .shared,
         defaults: UserDefaults = .standard,
         scope: @escaping () -> String = PendingInvitationStore.currentScope,
         hasRegisteredUsername: (@MainActor () -> Bool)? = nil) {
        self.keychain = keychain
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

    private func keychainAccount(_ scope: String) -> String { Self.keychainPrefix + scope }
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
        guard let data = keychain.retrieveKeyData(identifier: keychainAccount(scope)),
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
        guard keychain.storeKeyData(Data(trimmed.utf8), identifier: keychainAccount(currentScope)) != nil else {
            Self.logger.error("🎟️ INVITE :: could not store the pending invitation in the Keychain")
            return .notAnInvitation
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

    /// Forget the invitation in the current scope.
    func clear(reason: ClearReason) {
        let currentScope = scope()
        keychain.deleteKeyData(identifier: keychainAccount(currentScope))
        defaults.removeObject(forKey: metadataKey(currentScope))
        if pending != nil {
            pending = nil
        }
        Self.logger.info("🎟️ INVITE :: cleared pending invitation (\(reason.rawValue, privacy: .public))")
    }

    /// Move an invitation received before the wallet existed under the newly
    /// created wallet's scope.
    func bindUnboundToCurrentWallet() {
        let currentScope = scope()
        let unbound = Self.scope(networkRawValue: WalletEnvironment.networkKind.rawValue, walletIdHex: nil)
        guard currentScope != unbound, let invitation = load(unbound) else {
            reload()
            return
        }
        if load(currentScope) == nil,
           keychain.storeKeyData(Data(invitation.rawLink.utf8), identifier: keychainAccount(currentScope)) != nil {
            writeMetadata(
                PendingInvitation(rawLink: invitation.rawLink, receivedAt: invitation.receivedAt, fromOnboarding: true),
                scope: currentScope)
        }
        keychain.deleteKeyData(identifier: keychainAccount(unbound))
        defaults.removeObject(forKey: metadataKey(unbound))
        reload()
    }

    private func writeMetadata(_ invitation: PendingInvitation, scope: String) {
        defaults.set([
            "receivedAt": invitation.receivedAt.timeIntervalSince1970,
            "fromOnboarding": invitation.fromOnboarding,
        ], forKey: metadataKey(scope))
    }

    /// Delete every stored invitation, across networks and wallets (wallet
    /// wipe).
    static func wipeAll() {
        let service = KeychainManager.shared.serviceName
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let items = result as? [[String: Any]] {
            for item in items {
                guard let account = item[kSecAttrAccount as String] as? String,
                      account.hasPrefix(keychainPrefix) else { continue }
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                ]
                SecItemDelete(deleteQuery as CFDictionary)
            }
        }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(metadataPrefix) {
            defaults.removeObject(forKey: key)
        }
        shared.reload()
    }
}
