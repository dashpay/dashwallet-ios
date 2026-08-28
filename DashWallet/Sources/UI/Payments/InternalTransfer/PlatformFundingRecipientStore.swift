//
//  PlatformFundingRecipientStore.swift
//  DashWallet
//
//  Durable record of WHO a Core → Platform asset-lock funding pays.
//
//  Rust never learns the destination of an address-funding asset lock — it
//  tracks the L1 outpoint, its status and its proof, and nothing else. The
//  recipient is a PARAMETER of both `fundFromAssetLockExternal` and
//  `resumeFundFromAssetLockExternal`, so the host is solely responsible for
//  round-tripping it across an app restart.
//
//  Without that round-trip a kill between lock broadcast and ST submit is a
//  silent misdirection: every resume surface (tx-detail retry, the home
//  screen's tap-to-finish, `AssetLockRecoveryService`) would resume with no
//  recipient and pay the SENDER's own next address instead of the third party
//  the user actually confirmed. The lock is a bearer input, not a commitment
//  to a destination, so the resume would succeed — just to the wrong party.
//
//  Two records, because the outpoint is not known when the intent is formed:
//
//  1. INTENT — written immediately before the funding call, when all we know
//     is the recipient. Survives a kill in the window where Rust has built and
//     broadcast the lock but the app has not yet observed the row.
//  2. STAMP — outpoint → recipient, written the moment the outpoint is
//     observed (the 0.5 s asset-lock poll sees the row at Broadcast status,
//     which is BEFORE the funding ST is submitted).
//
//  The canonical record is the SwiftData `PersistentAssetLock` row's type-4
//  field family (`recipientPlatformAddressHash` / `recipientPlatformAddressType`
//  / `recipientIsExternal`) — this store is the app-side mirror that covers the
//  pre-stamp window and stays readable without a `ModelContainer`. Reads
//  consult the row first; see `resolve(outPointHex:walletId:container:)`.
//
//  Mirrors `ShieldedWithdrawalStore`'s shape: per-wallet UserDefaults key,
//  NSLock-guarded in-memory cache, and the same wipe/remove lifecycle hooks in
//  `SwiftDashSDKWalletWiper`.
//

import Foundation
import SwiftData
import SwiftDashSDK

/// The Platform destination of a Core → Platform asset-lock funding, in the
/// shape both the SDK's `FundFromAssetLockRecipient` and `PersistentAssetLock`'s
/// funding-type-4 field family speak.
public struct PlatformFundingRecipient: Equatable, Codable, Sendable {
    /// FFI address discriminant: 0 = P2PKH, 1 = P2SH. Only 0 is executable —
    /// the SDK preflight and the Rust `TryFrom<PlatformAddressFFI>` both reject
    /// P2SH, and `SendViewModel` rejects it at address-entry time.
    public let addressType: UInt8
    /// 20-byte address hash.
    public let hash: Data
    /// `true` when `hash` names a THIRD PARTY's address rather than one of this
    /// wallet's own. Consumers read a populated recipient hash as "this lock
    /// topped up an address of mine" — `PlatformAddressActivityStore
    /// .matchesOwnAssetLockTopUp` does exactly that — so without the
    /// discriminator an outgoing payment would render as an incoming credit.
    public let isExternal: Bool
    /// Explicit credit amount this recipient receives, or `nil` for the
    /// remainder output. An external payee ALWAYS carries an explicit amount —
    /// that is what makes the payee whole and pushes the fees onto the
    /// sender's own change output.
    public let credits: UInt64?

    public init(addressType: UInt8, hash: Data, isExternal: Bool, credits: UInt64?) {
        self.addressType = addressType
        self.hash = hash
        self.isExternal = isExternal
        self.credits = credits
    }
}

/// Per-wallet durable store for `PlatformFundingRecipient`s.
///
/// `static let shared` justification (Architecture Guardrail 4): this is a
/// process-wide cache over a single `UserDefaults` domain, read from surfaces
/// that have no dependency-injection seam and no `ModelContainer` — the home
/// screen's background transaction-grouping queue and the tx-detail retry
/// button among them — and written from the transfer coordinator. It carries no
/// published state and no behavior beyond the read/write of that one domain,
/// exactly like the `ShieldedWithdrawalStore` / `CoinJoinWithdrawalStore` pair
/// it is modelled on. An injected instance per call site would fragment the
/// cache without changing the shared UserDefaults backing.
final class PlatformFundingRecipientStore {

    static let shared = PlatformFundingRecipientStore()

    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    /// Per-wallet key prefixes; effective keys are `<prefix>_<walletIdHex>` so a
    /// recipient recorded under wallet A is never served while wallet B is
    /// active. `WalletEnvironment.activeWalletIdHex` reads only UserDefaults,
    /// so it is safe from background queues.
    private let stampPrefix = "platformFunding.v1.recipients"
    private let intentPrefix = "platformFunding.v1.intent"

    /// An intent older than this is not adopted for an unstamped lock. The
    /// window bounds the misattribution risk of the timestamp heuristic: a
    /// stale intent from a previous, abandoned attempt must not be applied to
    /// an unrelated lock built much later.
    private static let intentAdoptionWindow: TimeInterval = 60 * 60 * 24

    /// Cache keyed by the resolved (per-wallet) stamp key, so a wallet switch
    /// between accesses re-reads the new wallet's map.
    private var cacheKey: String?
    private var cache: [String: PlatformFundingRecipient]?

    private init() {}

    // MARK: - Key resolution

    private func resolvedKey(_ prefix: String) -> String {
        guard let walletIdHex = WalletEnvironment.activeWalletIdHex as String?,
              !walletIdHex.isEmpty else {
            return prefix
        }
        return "\(prefix)_\(walletIdHex)"
    }

    // MARK: - Outpoint formatting

    /// `PersistentAssetLock.outPointHex` form: display-order txid hex + ":" +
    /// vout. The SDK stores the txid in DISPLAY order (reversed wire bytes),
    /// which is the inverse of `ShieldedTransferCoordinator.parseOutPoint`.
    static func outPointHex(txidWire: Data, vout: UInt32) -> String? {
        guard txidWire.count == 32 else { return nil }
        let display = txidWire.reversed().map { String(format: "%02x", $0) }.joined()
        return "\(display):\(vout)"
    }

    // MARK: - Intent (pre-outpoint)

    /// Record the recipient the user confirmed, immediately before the funding
    /// call. Overwrites any previous intent — only one funding is in flight at
    /// a time (`ShieldedTransferCoordinator.beginTransfer` enforces that).
    func recordIntent(_ recipient: PlatformFundingRecipient) {
        lock.lock(); defer { lock.unlock() }
        let payload = IntentPayload(recipient: recipient, createdAt: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: resolvedKey(intentPrefix))
    }

    /// Clear the pending intent once the funding reached a terminal state.
    func clearIntent() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: resolvedKey(intentPrefix))
    }

    /// The pending intent, if one was recorded within `intentAdoptionWindow`.
    func pendingIntent() -> PlatformFundingRecipient? {
        lock.lock(); defer { lock.unlock() }
        return loadedIntent()?.recipient
    }

    private func loadedIntent() -> IntentPayload? {
        guard let data = defaults.data(forKey: resolvedKey(intentPrefix)),
              let payload = try? JSONDecoder().decode(IntentPayload.self, from: data),
              Date().timeIntervalSince(payload.createdAt) <= Self.intentAdoptionWindow
        else { return nil }
        return payload
    }

    private struct IntentPayload: Codable {
        let recipient: PlatformFundingRecipient
        let createdAt: Date
    }

    // MARK: - Stamp (outpoint known)

    /// Persisted form of the outpoint → recipient map. A named wrapper rather
    /// than a bare dictionary so the payload has somewhere to grow a version
    /// field without invalidating what is already on disk.
    private struct StampPayload: Codable {
        var entries: [String: PlatformFundingRecipient]
    }

    private func loadedStamps() -> [String: PlatformFundingRecipient] {
        let key = resolvedKey(stampPrefix)
        if cacheKey == key, let cache { return cache }
        var stored: [String: PlatformFundingRecipient] = [:]
        if let data = defaults.data(forKey: key) {
            let decoded = try? JSONDecoder().decode(StampPayload.self, from: data)
            stored = decoded?.entries ?? [:]
        }
        cacheKey = key
        cache = stored
        return stored
    }

    /// Bind `recipient` to a now-known outpoint. Idempotent; the FIRST stamp
    /// wins so a later resume that resolved a fallback can never overwrite the
    /// recipient the user actually confirmed.
    func stamp(outPointHex: String, recipient: PlatformFundingRecipient) {
        guard !outPointHex.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var map = loadedStamps()
        guard map[outPointHex] == nil else { return }
        map[outPointHex] = recipient
        cache = map
        guard let data = try? JSONEncoder().encode(StampPayload(entries: map)) else { return }
        defaults.set(data, forKey: resolvedKey(stampPrefix))
    }

    /// Recipient bound to `outPointHex`, or the pending intent when the lock
    /// was never stamped (killed between broadcast and the first poll tick).
    /// `nil` means "no recorded recipient" — callers MUST fall back to legacy
    /// own-address behavior, never to a guess.
    func recipient(forOutPointHex outPointHex: String) -> PlatformFundingRecipient? {
        lock.lock(); defer { lock.unlock() }
        if let stamped = loadedStamps()[outPointHex] { return stamped }
        return loadedIntent()?.recipient
    }

    // MARK: - Canonical resolution

    /// Resolve the recipient of a tracked type-4 lock, preferring the canonical
    /// `PersistentAssetLock` row over this store's mirror.
    ///
    /// A row carrying a hash but a `nil` `recipientIsExternal` predates the
    /// discriminator and can only have come from the own-address flow, so it
    /// resolves as `isExternal: false` — the same rule the SDK documents on the
    /// property. `nil` overall means the lock has no recorded recipient at all
    /// and the caller keeps legacy own-next-address behavior.
    @MainActor
    static func resolve(
        outPointHex: String,
        walletId: Data,
        container: ModelContainer
    ) -> PlatformFundingRecipient? {
        let topUpType = 4 // AssetLockAddressTopUp
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId
                    && row.fundingTypeRaw == topUpType
                    && row.outPointHex == outPointHex
            })
        descriptor.fetchLimit = 1
        let mirrored = shared.recipient(forOutPointHex: outPointHex)
        guard let row = try? container.mainContext.fetch(descriptor).first,
              let hash = row.recipientPlatformAddressHash,
              hash.count == 20
        else { return mirrored }

        let isExternal = row.recipientIsExternal ?? false
        // The type-4 field family carries no credit amount, so prefer the
        // mirror's when it agrees on the destination. If the mirror is gone
        // (an explicit per-wallet clear), derive the payee amount back out of
        // the recorded lock value, which was built as amount + headroom.
        let credits: UInt64?
        if let mirrored, mirrored.hash == hash {
            credits = mirrored.credits
        } else if isExternal {
            let headroom = CoreToPlatformAmountPolicy.externalHeadroomDuffs
            guard let lockDuffs = UInt64(exactly: row.amountDuffs), lockDuffs > headroom
            else { return nil }
            credits = CoreToPlatformAmountPolicy.payeeCredits(forAmountDuffs: lockDuffs - headroom)
        } else {
            credits = nil
        }
        return PlatformFundingRecipient(
            addressType: row.recipientPlatformAddressType ?? 0,
            hash: hash,
            isExternal: isExternal,
            credits: credits)
    }

    /// Write the recipient onto the canonical `PersistentAssetLock` row AND
    /// mirror it into this store. Called as soon as the outpoint is observed,
    /// which the 0.5 s poll makes happen at Broadcast status — before the
    /// funding ST is submitted.
    ///
    /// First-write-wins on the row too: a row that already names a recipient is
    /// left alone, so a resume can never rewrite the original destination.
    @MainActor
    static func persist(
        recipient: PlatformFundingRecipient,
        outPointHex: String,
        walletId: Data,
        container: ModelContainer
    ) {
        shared.stamp(outPointHex: outPointHex, recipient: recipient)

        let topUpType = 4 // AssetLockAddressTopUp
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId
                    && row.fundingTypeRaw == topUpType
                    && row.outPointHex == outPointHex
            })
        descriptor.fetchLimit = 1
        let context = container.mainContext
        guard let row = try? context.fetch(descriptor).first,
              row.recipientPlatformAddressHash == nil
        else { return }
        row.recipientPlatformAddressHash = recipient.hash
        row.recipientPlatformAddressType = recipient.addressType
        row.recipientIsExternal = recipient.isExternal
        row.updatedAt = Date()
        try? context.save()
    }

    // MARK: - Lifecycle

    /// Clear a SINGLE wallet's records (per-wallet Remove flow — the removed
    /// wallet may not be the active one).
    func clearForWallet(walletIdHex: String) {
        guard !walletIdHex.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let key = "\(stampPrefix)_\(walletIdHex)"
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: "\(intentPrefix)_\(walletIdHex)")
        if cacheKey == key {
            cacheKey = nil
            cache = nil
        }
    }

    /// Clear ALL records on a full wallet wipe (walletIds are gone by wipe
    /// time, so enumerate by prefix).
    func resetForWipe() {
        lock.lock(); defer { lock.unlock() }
        for key in defaults.dictionaryRepresentation().keys {
            if key == stampPrefix || key.hasPrefix("\(stampPrefix)_")
                || key == intentPrefix || key.hasPrefix("\(intentPrefix)_") {
                defaults.removeObject(forKey: key)
            }
        }
        cacheKey = nil
        cache = nil
    }
}
