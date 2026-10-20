//
//  ShieldedAssetLocksInFlight.swift
//  DashWallet
//
//  The shared registry of asset locks a running transfer is consuming, and
//  the gate that keeps transfers and wallet-reloading removals apart. Read
//  by the Home row, the transaction details, `AssetLockRecoveryService`,
//  `UnconfirmedTransactionRemover` and the Core Sync screen; claimed by
//  `ShieldedTransferCoordinator`.
//

import Combine
import Foundation

/// Asset locks a `ShieldedTransferCoordinator` is consuming right now, across
/// every coordinator instance.
///
/// A Core-funded transfer can stay in flight for minutes (a lock funded by
/// many inputs waits for its ChainLock before the SDK can submit it), and its
/// lock row looks exactly like a stuck one meanwhile. The Home row reads this
/// to show the transfer as an ordinary internal transfer instead of offering
/// "tap to finish"; the tx detail sheet and the bulk recovery pass read it to
/// skip the lock; every resume entry point reads it to refuse a second attempt.
///
/// A fresh transfer's new lock is claimed by the SDK's built-lock callback,
/// before the lock's row is persisted. The registry also counts the fresh
/// transfers that will build a new lock, from before their authorization
/// until the transfer's attempt ends, so `hasActivity` covers one that has not
/// built its lock yet; a bulk recovery pass counts the same way.
///
/// A removal that deletes rows and reloads the wallet runtime is admitted
/// here only while nothing is active (`beginRemoval`), and holds the reload
/// until `endRemoval`; meanwhile no funding call starts and no resume claims a
/// lock.
///
/// Claims are counted per lock, so one coordinator's release cannot clear a
/// claim another coordinator still holds. Reads are thread-safe, like
/// `ShieldedTxLookup`; claims and releases happen on the main actor, where the
/// coordinators run, and publish from there, except `claimBuiltLock`, which
/// the SDK calls on its worker thread.
final class ShieldedAssetLocksInFlight: ObservableObject, @unchecked Sendable {
    struct OutPoint: Hashable, Sendable {
        let txidWire: Data
        let vout: UInt32
    }

    static let shared = ShieldedAssetLocksInFlight()

    private let lock = NSLock()
    private var claims: [OutPoint: Int] = [:]
    /// Fresh transfers that will build or are building a new asset lock, and
    /// bulk recovery passes.
    private var fundingCalls = 0
    /// A removal is deleting rows and reloading the wallet runtime; see
    /// `beginRemoval`.
    private var removalHeld = false

    /// Production code uses `shared`; tests build their own registries.
    init() {}

    func contains(_ outPoint: OutPoint) -> Bool {
        lock.withLock { claims[outPoint, default: 0] > 0 }
    }

    /// Whether any output of the transaction is claimed — for callers that act
    /// on the whole transaction, such as removing it.
    func containsTransaction(txidWire: Data) -> Bool {
        lock.withLock { claims.keys.contains { $0.txidWire == txidWire } }
    }

    /// Whether any transfer is building a new asset lock or consuming one.
    var hasActivity: Bool {
        lock.withLock { !claims.isEmpty || fundingCalls > 0 }
    }

    /// Whether a removal holds the runtime reload (`beginRemoval`), so no
    /// transfer may start.
    var isRemovalInProgress: Bool {
        lock.withLock { removalHeld }
    }

    /// What `beginRemoval` would answer now, without holding anything.
    var removalAdmission: RemovalAdmission {
        lock.withLock { currentRemovalAdmission() }
    }

    /// What a transfer, a recovery or a removal refused during a removal's
    /// reload tells the user.
    static var walletReloadingMessage: String {
        NSLocalizedString(
            "The wallet is reloading after a transaction was removed. Try again in a moment, or restart the app if it never finishes.",
            comment: "Refused while the wallet reloads after a removed transaction")
    }

    // Only the first claim and the last release change what `contains`
    // answers, only the first and the last funding call change `hasActivity`,
    // and only `beginRemoval`/`endRemoval` change `isRemovalInProgress`, so
    // only those publish. Each operation decides that in the same critical
    // section as its change.
    //
    // Claims and releases are for `ShieldedTransferCoordinator` (`claim` for
    // the tests) only: claims are counted, not owned, so a release from
    // anywhere else would drop a running transfer's claim. Funding calls are
    // also held by `AssetLockRecoveryService`'s bulk pass, and removals by
    // `UnconfirmedTransactionRemover`.

    @MainActor
    func claim(_ outPoint: OutPoint) {
        if addClaim(outPoint) { objectWillChange.send() }
    }

    /// `claim` for the SDK's built-lock callback, which runs on the FFI worker
    /// thread: the claim is recorded before the callback returns, and the
    /// change is published on the main queue afterwards.
    func claimBuiltLock(_ outPoint: OutPoint) {
        guard addClaim(outPoint) else { return }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    /// Adds a claim; true when it is the first one for `outPoint`.
    private func addClaim(_ outPoint: OutPoint) -> Bool {
        lock.withLock {
            claims[outPoint, default: 0] += 1
            return claims[outPoint] == 1
        }
    }

    @MainActor
    func release(_ outPoint: OutPoint) {
        let wasLast = lock.withLock { () -> Bool in
            guard let count = claims[outPoint] else { return false }
            claims[outPoint] = count > 1 ? count - 1 : nil
            return count == 1
        }
        if wasLast { objectWillChange.send() }
    }

    /// Why `admitResume` refused, or that it claimed the lock.
    enum ResumeAdmission {
        case admitted
        /// Another attempt has the lock claimed.
        case claimedElsewhere
        /// A removal holds the runtime reload (`beginRemoval`).
        case walletReloading
    }

    /// Claims `outPoint` for a resume, in the same critical section as the
    /// checks that may refuse it, so no removal is admitted in between.
    @MainActor
    func admitResume(_ outPoint: OutPoint) -> ResumeAdmission {
        let admission = lock.withLock { () -> ResumeAdmission in
            if removalHeld { return .walletReloading }
            if claims[outPoint, default: 0] > 0 { return .claimedElsewhere }
            claims[outPoint] = 1
            return .admitted
        }
        if case .admitted = admission { objectWillChange.send() }
        return admission
    }

    /// Counts a fresh transfer, or a bulk recovery pass, as activity until
    /// `endFundingCall`. False, with nothing counted, while a removal holds
    /// the runtime reload.
    @MainActor
    func beginFundingCall() -> Bool {
        let admitted = lock.withLock { () -> (admitted: Bool, isFirst: Bool) in
            guard !removalHeld else { return (false, false) }
            fundingCalls += 1
            return (true, fundingCalls == 1)
        }
        if admitted.isFirst { objectWillChange.send() }
        return admitted.admitted
    }

    @MainActor
    func endFundingCall() {
        let wasLast = lock.withLock { () -> Bool in
            guard fundingCalls > 0 else { return false }
            fundingCalls -= 1
            return fundingCalls == 0
        }
        if wasLast { objectWillChange.send() }
    }

    /// Why `beginRemoval` refused, or that it admitted the removal.
    enum RemovalAdmission {
        case admitted
        /// A transfer is building or consuming an asset lock.
        case transferActive
        /// Another removal holds the runtime reload.
        case removalHeld
    }

    /// Admits a removal that deletes transaction rows and reloads the wallet
    /// runtime, which would stop a running transfer's SDK call. Refused while
    /// any transfer is active or another removal holds it. Until
    /// `endRemoval`, `beginFundingCall` and `admitResume` refuse, so no
    /// transfer of a `ShieldedTransferCoordinator` and no bulk recovery pass
    /// starts during the reload. Identity registrations and top-ups do not use
    /// this registry yet.
    @MainActor
    func beginRemoval() -> RemovalAdmission {
        let admission = lock.withLock { () -> RemovalAdmission in
            let admission = currentRemovalAdmission()
            if case .admitted = admission { removalHeld = true }
            return admission
        }
        if case .admitted = admission { objectWillChange.send() }
        return admission
    }

    /// The removal admission rule; call with `lock` held.
    private func currentRemovalAdmission() -> RemovalAdmission {
        if removalHeld { return .removalHeld }
        return claims.isEmpty && fundingCalls == 0 ? .admitted : .transferActive
    }

    @MainActor
    func endRemoval() {
        let wasHeld = lock.withLock { () -> Bool in
            defer { removalHeld = false }
            return removalHeld
        }
        if wasHeld { objectWillChange.send() }
    }
}
