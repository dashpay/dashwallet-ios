//
//  ShieldedTransferCoordinator.swift
//  DashWallet
//
//  Drives a single user-initiated shielded-funding transfer:
//   - PIN/biometric gate via `DWIdentityAuthorizer`.
//   - Routes to one of the two SDK shielded-funding entry points:
//       * `.core`     → `PlatformWalletManager.shieldedFundFromAssetLock(...)`
//         (BIP44 UTXOs → Type 18 asset-lock → Halo 2 proof → broadcast).
//       * `.platform` → `PlatformWalletManager.shieldedShield(...)`
//         (DIP-17 Platform Payment credits → Type 15 shield).
//   - Publishes a stage `phase` so the confirm sheet can show a multi-step
//     progress checklist. For the asset-lock route, real stage transitions
//     are mirrored from `PersistentAssetLock.statusRaw` (0/1 → .locking,
//     2/3 → .proving, 4 → .broadcasting) — same polling pattern as
//     `DWIdentityRegistrationCoordinator.startAssetLockPolling`.
//   - Best-effort `syncShieldedNow()` after a successful broadcast so the
//     screen's To-card readback refreshes promptly.
//
//  Scope of this v1:
//   - `fundingAccountIndex`, `shieldedAccount`, `paymentAccount` all pinned
//     to 0 (single-account wallet). Mirrors `DWIdentityRegistrationCoordinator
//     .defaultAccountIndex`.
//   - The shielded recipient is the wallet's own default Orchard address —
//     resolved once via `PlatformWalletManager.shieldedDefaultAddress(...)`.
//     A future "send to another shielded address" surface would override this.
//   - No mid-call cancellation. The FFI doesn't expose it; the sheet
//     disables drag-dismiss + Cancel while a transfer is in flight.
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
final class ShieldedTransferCoordinator: ObservableObject {

    enum Phase: Equatable {
        case idle
        case signing
        case locking
        case proving
        case broadcasting
        case success
        case failed(String)
    }

    enum Source {
        case core
        case platform
    }

    @Published private(set) var phase: Phase = .idle

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.shielded-transfer")

    /// Matches `PersistentAssetLock.fundingTypeRaw` for
    /// `AssetLockShieldedAddressTopUp` (see
    /// `rs-platform-wallet-ffi/src/asset_lock_persistence.rs`).
    private static let shieldedAssetLockFundingType: Int = 5

    /// Same 0.5 s cadence as `DWIdentityRegistrationCoordinator` — enough
    /// for the four observable transitions (Built → Broadcast → IS/CL →
    /// Consumed) without burning CPU.
    private static let assetLockPollInterval: TimeInterval = 0.5

    private let authorizer = DWIdentityAuthorizer()
    private var assetLockPollingTask: Task<Void, Never>?

    /// Outpoint (wire-order txid + vout) of the asset lock observed during the
    /// most recent in-flight `performAssetLock`, captured from polling so a
    /// failed attempt's "Try again" can RESUME the existing lock instead of
    /// building a second one. `nil` until an asset lock reaches Broadcast (1+);
    /// cleared on `reset()` and at the start of a fresh `performAssetLock`.
    private(set) var lastAssetLockOutPoint: (txidWire: Data, vout: UInt32)?

    // MARK: - Errors

    enum CoordinatorError: LocalizedError {
        case noWallet
        case noNetwork
        case noModelContainer
        case noManager
        case noShieldedAddress
        case noReceiveAddress
        case noPlatformAddress
        case authCancelled
        case authFailed
        case transferFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noWallet:
                return NSLocalizedString("Wallet is not ready for transfer", comment: "InternalTransfer")
            case .noNetwork:
                return NSLocalizedString("Network is not configured", comment: "InternalTransfer")
            case .noModelContainer:
                return NSLocalizedString("Storage is not configured", comment: "InternalTransfer")
            case .noManager:
                return NSLocalizedString("Platform wallet manager unavailable", comment: "InternalTransfer")
            case .noShieldedAddress:
                return NSLocalizedString("Shielded address is not bound for this wallet", comment: "InternalTransfer")
            case .noReceiveAddress:
                return NSLocalizedString("Could not resolve a destination wallet address", comment: "InternalTransfer")
            case .noPlatformAddress:
                return NSLocalizedString("Could not resolve a destination Platform Payment address", comment: "InternalTransfer")
            case .authCancelled:
                return NSLocalizedString("Authentication cancelled", comment: "InternalTransfer")
            case .authFailed:
                return NSLocalizedString("Authentication failed", comment: "InternalTransfer")
            case .transferFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    // MARK: - Public API

    /// Route 1: BIP44 Core UTXOs → asset-lock → Type 18 shield.
    /// Stages: `.signing → .locking → .proving → .broadcasting → .success`.
    /// The intermediate stages are polled from `PersistentAssetLock.statusRaw`;
    /// the SDK returns `Void` only on `Consumed`/success.
    func performAssetLock(amountDuffs: UInt64) async {
        guard beginTransfer() else { return }
        lastAssetLockOutPoint = nil
        Self.logger.info("🛡️ SHIELD-TX :: asset-lock route amount=\(amountDuffs)")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .locking
        let startTime = Date()
        startAssetLockPolling(walletId: env.walletId, modelContainer: env.modelContainer, startTime: startTime)

        do {
            let recipient = ShieldedFundFromAssetLockRecipient(
                recipientRaw43: env.shieldedRecipient,
                credits: nil)
            try await env.manager.shieldedFundFromAssetLock(
                walletId: env.walletId,
                fundingAccountIndex: 0,
                amountDuffs: amountDuffs,
                recipients: [recipient])
        } catch {
            stopAssetLockPolling()
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        stopAssetLockPolling()
        Self.logger.info("🛡️ SHIELD-TX :: asset-lock route completed")
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Resume a stuck "to Shielded" transfer whose asset lock is already
    /// broadcast/locked (statusRaw 1…3) but whose shield state transition never
    /// landed. Picks up the existing outpoint and drives the remaining stages
    /// via `shieldedResumeFundFromAssetLock` — instead of building a SECOND
    /// asset lock (which is what a fresh `performAssetLock` would do, stranding
    /// the first). The recipient is re-derived (the wallet's own default
    /// shielded address), identical to the original attempt; the SDK re-derives
    /// an identical `shield_amount` from the on-chain lock value, so a resume
    /// cannot desync funds and is safe to retry. Re-authorizes — this moves
    /// real funds.
    ///
    /// Used by both the confirm sheet's "Try again" (in-session) and the
    /// home-screen recovery sheet (after relaunch).
    func resumeAssetLock(outPointTxidWire: Data, outPointVout: UInt32) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: resume asset-lock vout=\(outPointVout)")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        // The lock is already broadcast/locked — only the Orchard proof + the
        // shield ST remain, so jump straight to .proving (no .locking stage and
        // no asset-lock polling: there's no new lock to track).
        phase = .proving

        do {
            let recipient = ShieldedFundFromAssetLockRecipient(
                recipientRaw43: env.shieldedRecipient,
                credits: nil)
            try await env.manager.shieldedResumeFundFromAssetLock(
                walletId: env.walletId,
                outPointTxid: outPointTxidWire,
                outPointVout: outPointVout,
                recipients: [recipient])
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: resume completed")
        // The single resume FFI call covered proof + submit; advance through
        // .broadcasting so the step checklist completes naturally (mirrors
        // `performShield`). No intermediate signal exists for this opaque call.
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Parse a `PersistentAssetLock.outPointHex` ("<txid display hex>:<vout>")
    /// into the (wire-order txid, vout) that `shieldedResumeFundFromAssetLock`
    /// expects. The stored txid is display order (reversed wire); the FFI wants
    /// 32-byte little-endian wire order, so hex-decode then reverse. `nil` on
    /// any malformed input.
    static func parseOutPoint(_ outPointHex: String) -> (txidWire: Data, vout: UInt32)? {
        guard let colon = outPointHex.firstIndex(of: ":") else { return nil }
        let txidDisplayHex = outPointHex[..<colon]
        guard let vout = UInt32(outPointHex[outPointHex.index(after: colon)...]) else { return nil }
        guard txidDisplayHex.count == 64 else { return nil }
        var display = Data(capacity: 32)
        var idx = txidDisplayHex.startIndex
        while idx < txidDisplayHex.endIndex {
            let next = txidDisplayHex.index(idx, offsetBy: 2)
            guard let byte = UInt8(txidDisplayHex[idx..<next], radix: 16) else { return nil }
            display.append(byte)
            idx = next
        }
        return (Data(display.reversed()), vout)
    }

    /// Route 2: DIP-17 transparent Platform Payment credits → Type 15 shield.
    /// Stages: `.signing → .proving → .broadcasting → .success`. No
    /// intermediate signals from the FFI — `.proving` covers the whole opaque
    /// ~30 s call; on return we jump to `.success`.
    func performShield(amountCredits: UInt64) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: shield route amount=\(amountCredits) credits")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        let signer = KeychainSigner(
            modelContainer: env.modelContainer,
            network: env.network)

        do {
            try await env.manager.shieldedShield(
                walletId: env.walletId,
                shieldedAccount: 0,
                paymentAccount: 0,
                amount: amountCredits,
                addressSigner: signer)
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: shield route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Route 3 (reverse): shielded Orchard notes → Core L1 transparent
    /// address (Dash Wallet). Stages: `.signing → .proving → .broadcasting →
    /// .success`. Like `shieldedShield`, `shieldedWithdraw` is a single opaque
    /// async call with no intermediate signals — `.proving` covers it until it
    /// returns. `amount` is in credits (1e11 / DASH), same scale as
    /// `shieldedShield`. No signer required.
    func performWithdraw(amountCredits: UInt64) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: withdraw route amount=\(amountCredits) credits")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        // Destination Core (BIP44, Base58Check) receive address. Resolve before
        // advancing the phase — same ordering as `resolveEnvironment()`. The
        // reader is main-actor-safe and we're already on @MainActor, so call it
        // directly (no GCD hop).
        guard let coreAddress = SwiftDashSDKReceiveAddressReader.receiveAddress(
                on: DWEnvironment.sharedInstance().currentChain),
              !coreAddress.isEmpty else {
            handleFailure(CoordinatorError.noReceiveAddress)
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        do {
            try await env.manager.shieldedWithdraw(
                walletId: env.walletId,
                account: 0,
                toCoreAddress: coreAddress,
                amount: amountCredits)
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: withdraw route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Route 4 (reverse): shielded Orchard notes → the wallet's own transparent
    /// Platform Payment balance (DIP-17 credits). Stages: `.signing → .proving →
    /// .broadcasting → .success`. Like `shieldedShield` / `shieldedWithdraw`,
    /// `shieldedUnshield` is a single opaque async call with no intermediate
    /// signals. `amount` is in credits; no signer required.
    func performUnshield(amountCredits: UInt64) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: unshield route amount=\(amountCredits) credits")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        // Destination Platform Payment (bech32m) address — the wallet's own
        // next receive address, mirroring `PaymentsLandingViewModel
        // .pickNextPlatformAddress`. Resolve before advancing the phase.
        guard let platformAddress = Self.pickPlatformAddress(
                from: PlatformAddressSyncCoordinator.shared.derivedAddresses),
              !platformAddress.isEmpty else {
            handleFailure(CoordinatorError.noPlatformAddress)
            return
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .proving

        do {
            try await env.manager.shieldedUnshield(
                walletId: env.walletId,
                account: 0,
                toPlatformAddress: platformAddress,
                amount: amountCredits)
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: unshield route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Lowest-indexed unused Platform Payment address (fallback: lowest-indexed
    /// overall) for the wallet's own receive — mirrors the selection in
    /// `PaymentsLandingViewModel.pickNextPlatformAddress(from:)`. Pure; the
    /// `derivedAddresses` read happens on the `@MainActor` caller.
    private static func pickPlatformAddress(from addresses: [DerivedPlatformAddress]) -> String? {
        if let unused = addresses
            .filter({ !$0.isUsed })
            .min(by: { ($0.accountIndex, $0.addressIndex) < ($1.accountIndex, $1.addressIndex) }) {
            return unused.address
        }
        return addresses
            .min(by: { ($0.accountIndex, $0.addressIndex) < ($1.accountIndex, $1.addressIndex) })?
            .address
    }

    /// Reset to `.idle` so the user can retry from a `.failed` state.
    /// Keeps no in-flight observers — the FFI calls themselves are
    /// uncancellable, so this just resets UI state.
    func reset() {
        stopAssetLockPolling()
        lastAssetLockOutPoint = nil
        phase = .idle
    }

    // MARK: - Internal

    private struct Environment {
        let manager: PlatformWalletManager
        let walletId: Data
        let network: Network
        let modelContainer: ModelContainer
        let shieldedRecipient: Data
    }

    private func resolveEnvironment() throws -> Environment {
        guard let manager = SwiftDashSDKHost.shared.manager else {
            throw CoordinatorError.noManager
        }
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw CoordinatorError.noWallet
        }
        guard let network = SwiftDashSDKHost.shared.runningNetwork else {
            throw CoordinatorError.noNetwork
        }
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer else {
            throw CoordinatorError.noModelContainer
        }
        let walletId = wallet.walletId
        let recipient: Data?
        do {
            recipient = try manager.shieldedDefaultAddress(walletId: walletId, account: 0)
        } catch {
            throw CoordinatorError.transferFailed(error)
        }
        guard let recipient, recipient.count == 43 else {
            throw CoordinatorError.noShieldedAddress
        }
        return Environment(
            manager: manager,
            walletId: walletId,
            network: network,
            modelContainer: modelContainer,
            shieldedRecipient: recipient)
    }

    /// Synchronous single-flight gate. Returns `false` when a transfer is
    /// already in progress (or finished and not yet `reset()`), so a fast
    /// double-tap on Confirm can't queue a second transfer. Because the
    /// coordinator is `@MainActor`, the `phase == .idle` check and the
    /// `.signing` write run with no suspension point between them — the
    /// first caller wins atomically and the second sees `.signing` + bails.
    private func beginTransfer() -> Bool {
        guard phase == .idle else { return false }
        phase = .signing
        return true
    }

    /// PIN/biometric gate. `phase` is already `.signing` (set synchronously
    /// by `beginTransfer()`); this just awaits user authorization and maps
    /// the cancel/fail outcomes onto coordinator errors.
    private func authorize() async throws {
        do {
            try await authorizer.authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            throw CoordinatorError.authCancelled
        } catch {
            throw CoordinatorError.authFailed
        }
    }

    private func handleFailure(_ error: Error) {
        Self.logger.error("🛡️ SHIELD-TX :: failure \(String(describing: error), privacy: .public)")
        let message: String
        if let local = error as? LocalizedError, let description = local.errorDescription {
            message = description
        } else {
            message = error.localizedDescription
        }
        phase = .failed(message)
    }

    /// Fire-and-forget shielded readback refresh after a successful transfer.
    /// Detached from the transfer flow so a slow/blocked sync can't hold the
    /// sheet on a non-dismissible phase after the transfer already landed.
    /// Captures only `manager` (a long-lived singleton) — no retain on the
    /// coordinator past the sheet's lifetime.
    private func scheduleShieldedResync(manager: PlatformWalletManager) {
        Task {
            do {
                try await manager.syncShieldedNow()
            } catch {
                Self.logger.warning("🛡️ SHIELD-TX :: syncShieldedNow failed (ignored): \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Asset-lock polling

    /// Mirror `DWIdentityRegistrationCoordinator.startAssetLockPolling` —
    /// 0.5 s cadence, lifetime-bounded by the in-flight transfer.
    /// Defensive about the row not existing yet (or ever): the FFI emits
    /// the row asynchronously and earlier statuses may already be skipped
    /// past by the time we look.
    private func startAssetLockPolling(walletId: Data, modelContainer: ModelContainer, startTime: Date) {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.assetLockPollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.pollAssetLockStatus(
                    walletId: walletId,
                    modelContainer: modelContainer,
                    startTime: startTime)
            }
        }
    }

    private func stopAssetLockPolling() {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = nil
    }

    private func pollAssetLockStatus(walletId: Data, modelContainer: ModelContainer, startTime: Date) async {
        // Only meaningful while the asset-lock route is in-flight.
        switch phase {
        case .locking, .proving, .broadcasting:
            break
        default:
            return
        }

        let context = modelContainer.mainContext
        let shieldedFundingType = Self.shieldedAssetLockFundingType
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId
                    && row.fundingTypeRaw == shieldedFundingType
                    && row.createdAt >= startTime
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        do {
            let rows = try context.fetch(descriptor)
            guard let row = rows.first else { return }
            // Capture the outpoint once the lock is at least Broadcast (1+) so
            // a failed shield can be resumed on this exact lock rather than
            // building a second one. Display→wire reversal happens in parse.
            if row.statusRaw >= 1, let outPoint = Self.parseOutPoint(row.outPointHex) {
                lastAssetLockOutPoint = outPoint
            }
            advancePhaseForAssetLockStatus(row.statusRaw)
        } catch {
            Self.logger.warning("🛡️ SHIELD-TX :: asset-lock poll failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Map `PersistentAssetLock.statusRaw` to the next phase. Monotonic —
    /// only advances forward (e.g. a late-arriving `Broadcast` after we
    /// already saw `InstantSendLocked` is ignored). The SDK call's return
    /// drives the final `.success` transition, not status 4.
    private func advancePhaseForAssetLockStatus(_ status: Int) {
        switch status {
        case 0, 1: // Built, Broadcast
            // Already at .locking — nothing to do.
            break
        case 2, 3: // InstantSendLocked, ChainLocked
            if phase == .locking {
                phase = .proving
            }
        case 4: // Consumed — the ST has landed, FFI is almost back.
            if phase == .locking || phase == .proving {
                phase = .broadcasting
            }
        default:
            break
        }
    }
}
