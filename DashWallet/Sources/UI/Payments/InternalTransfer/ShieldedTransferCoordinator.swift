//
//  ShieldedTransferCoordinator.swift
//  DashWallet
//
//  Drives a single user-initiated transfer: the six internal
//  InternalTransferRoute legs between the wallet's own balances, plus the
//  external Send routes (the withdraw/unshield/platform-withdraw legs with a
//  recipient destination override, shielded → shielded `shieldedTransfer`,
//  and platform → platform `PlatformSendExecutor.transfer`):
//   - PIN/biometric gate via `DWIdentityAuthorizer`.
//   - Shielded-centric legs call `PlatformWalletManager` directly:
//       * Core → Shielded   `shieldedFundFromAssetLock` (Type 18 lock,
//         Halo 2 proof); Platform → Shielded `shieldedShield` (Type 15);
//       * Shielded → Core   `shieldedWithdraw`; Shielded → Platform
//         `shieldedUnshield`.
//   - Core ↔ Platform legs go through `PlatformAddressSyncCoordinator`
//     (the app's platform address-wallet seam): `fundFromCore` (asset-lock
//     address top-up) and `withdrawAllToCore` (full-balance withdrawal).
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
//   - The internal legs' shielded recipient is the wallet's own default
//     Orchard address — resolved once via
//     `PlatformWalletManager.shieldedDefaultAddress(...)`. The Send screen's
//     external legs pass the recipient's address/raw bytes instead.
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
        /// Broadcast was accepted by relay but its result couldn't be
        /// confirmed (SDK `shieldedSpendUnconfirmed`). Terminal + NON-retryable:
        /// re-submitting risks a double-spend / wasted fee. The effect lands via
        /// the next shielded sync.
        case submittedUnconfirmed
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

    /// `PersistentAssetLock.fundingTypeRaw` for `AssetLockAddressTopUp` —
    /// the Core → Platform address-funding lock (same Rust source).
    private static let addressAssetLockFundingType: Int = 4

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
            // Last-ditch outpoint capture: if the FFI threw before polling
            // observed the persisted lock row, fetch it now so "Try again"
            // RESUMES the committed lock instead of building a second one.
            captureLatestAssetLockOutPoint(
                walletId: env.walletId,
                modelContainer: env.modelContainer,
                since: startTime)
            handleSpendError(error, manager: env.manager)
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
            handleSpendError(error, manager: env.manager)
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

    /// Best-effort capture of the in-flight asset lock's outpoint when polling
    /// didn't get it — i.e. the FFI failed before a 0.5s poll tick observed the
    /// persisted row. Fetches the newest matching shielded asset lock at
    /// Broadcast+ (statusRaw ≥ 1) for this attempt and records its outpoint so a
    /// retry resumes that lock rather than building a second one. No-op if the
    /// outpoint is already captured or none is found yet.
    private func captureLatestAssetLockOutPoint(
        walletId: Data,
        modelContainer: ModelContainer,
        since startTime: Date,
        fundingType: Int = ShieldedTransferCoordinator.shieldedAssetLockFundingType
    ) {
        guard lastAssetLockOutPoint == nil else { return }
        let shieldedFundingType = fundingType
        var descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId
                    && row.fundingTypeRaw == shieldedFundingType
                    && row.createdAt >= startTime
                    && row.statusRaw >= 1
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        if let row = try? modelContainer.mainContext.fetch(descriptor).first,
           let outPoint = Self.parseOutPoint(row.outPointHex) {
            lastAssetLockOutPoint = outPoint
        }
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
            handleSpendError(error, manager: env.manager)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: shield route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
        // Shield debits the Platform-address balance; refresh it too (the
        // shielded resync above only updates the shielded side).
        schedulePlatformResync()
    }

    /// Route 3 (reverse): shielded Orchard notes → Core L1 transparent
    /// address. Stages: `.signing → .proving → .broadcasting →
    /// .success`. Like `shieldedShield`, `shieldedWithdraw` is a single opaque
    /// async call with no intermediate signals — `.proving` covers it until it
    /// returns. `amount` is in credits (1e11 / DASH), same scale as
    /// `shieldedShield`. No signer required.
    ///
    /// `toCoreAddress` nil = the wallet's own receive address (the internal
    /// transfer); an external Send passes the recipient's address. The
    /// withdrawal-store tag (which classifies the incoming L1 tx as
    /// "Shielded received") only applies to the own-wallet payout.
    func performWithdraw(amountCredits: UInt64, toCoreAddress destinationOverride: String? = nil) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: withdraw route amount=\(amountCredits) credits external=\(destinationOverride != nil)")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        // Destination Core (BIP44, Base58Check) address. For the internal
        // transfer, resolve the wallet's own receive address before advancing
        // the phase — same ordering as `resolveEnvironment()`. The reader is
        // main-actor-safe and we're already on @MainActor, so call it
        // directly (no GCD hop).
        let coreAddress: String
        let paysOwnWallet: Bool
        if let destinationOverride, !destinationOverride.isEmpty {
            coreAddress = destinationOverride
            paysOwnWallet = false
        } else {
            guard let ownAddress = SwiftDashSDKReceiveAddressReader.receiveAddress(),
                  !ownAddress.isEmpty else {
                handleFailure(CoordinatorError.noReceiveAddress)
                return
            }
            coreAddress = ownAddress
            paysOwnWallet = true
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
                // Per-operation Orchard spend authority (seedless shielded
                // bind, platform #4125/#4126); the SDK holds the resolver
                // alive across the FFI call via withExtendedLifetime.
                resolver: MnemonicResolver(),
                account: 0,
                toCoreAddress: coreAddress,
                amount: amountCredits)
        } catch {
            // shieldedSpendUnconfirmed means the spend may already be on
            // chain (non-retryable), so its payout can still arrive — tag
            // the destination so the incoming tx classifies as a shielded
            // withdrawal either way. External payouts never land in this
            // wallet, so there is nothing to tag.
            if paysOwnWallet, case PlatformWalletError.shieldedSpendUnconfirmed = error {
                ShieldedWithdrawalStore.shared.record(address: coreAddress)
            }
            handleSpendError(error, manager: env.manager)
            return
        }

        // Tag the payout destination so the home list can classify the
        // incoming L1 tx as "Shielded received" (the SDK call returns no txid).
        if paysOwnWallet {
            ShieldedWithdrawalStore.shared.record(address: coreAddress)
        }

        Self.logger.info("🛡️ SHIELD-TX :: withdraw route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// Route 4 (reverse): shielded Orchard notes → a transparent Platform
    /// Payment balance (DIP-17 credits). Stages: `.signing → .proving →
    /// .broadcasting → .success`. Like `shieldedShield` / `shieldedWithdraw`,
    /// `shieldedUnshield` is a single opaque async call with no intermediate
    /// signals. `amount` is in credits; no signer required.
    ///
    /// `toPlatformAddress` nil = the wallet's own next receive address (the
    /// internal transfer); an external Send passes the recipient's bech32m
    /// Platform address.
    func performUnshield(amountCredits: UInt64, toPlatformAddress destinationOverride: String? = nil) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: unshield route amount=\(amountCredits) credits external=\(destinationOverride != nil)")

        let env: Environment
        do {
            env = try resolveEnvironment()
        } catch {
            handleFailure(error)
            return
        }

        // Destination Platform Payment (bech32m) address — for the internal
        // transfer, the wallet's own next receive address. Resolve before
        // advancing the phase.
        let platformAddress: String
        if let destinationOverride, !destinationOverride.isEmpty {
            platformAddress = destinationOverride
        } else {
            guard let ownAddress = PlatformAddressSyncCoordinator.shared
                    .derivedAddresses.nextReceiveAddress?.address,
                  !ownAddress.isEmpty else {
                handleFailure(CoordinatorError.noPlatformAddress)
                return
            }
            platformAddress = ownAddress
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
                // Per-operation Orchard spend authority — see above.
                resolver: MnemonicResolver(),
                account: 0,
                toPlatformAddress: platformAddress,
                amount: amountCredits)
        } catch {
            handleSpendError(error, manager: env.manager)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: unshield route completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
        // Unshield credits the Platform-address balance; the shielded resync
        // above only refreshes the shielded side, so kick the Platform-address
        // (BLAST) sync to surface the credit promptly.
        schedulePlatformResync()
    }

    /// Route 5: BIP44 Core UTXOs → asset lock → the wallet's own Platform
    /// address credits (funding type 4, `AssetLockAddressTopUp`). Stages:
    /// `.signing → .locking → .broadcasting → .success` — no Orchard proof,
    /// so `.proving` may only appear transiently via the lock-status polling
    /// (IS/CL-locked) before the funding ST lands. On failure after the lock
    /// committed, `lastAssetLockOutPoint` is captured so "Try again" resumes
    /// that lock via `resumeFundPlatform` instead of stranding it.
    func performFundPlatform(amountDuffs: UInt64) async {
        guard beginTransfer() else { return }
        lastAssetLockOutPoint = nil
        Self.logger.info("🛡️ SHIELD-TX :: core→platform fund route amount=\(amountDuffs)")

        let env: BasicEnvironment
        do {
            env = try resolveBasicEnvironment()
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
        startAssetLockPolling(
            walletId: env.walletId,
            modelContainer: env.modelContainer,
            startTime: startTime,
            fundingType: Self.addressAssetLockFundingType)

        do {
            try await PlatformAddressSyncCoordinator.shared.fundFromCore(amountDuffs: amountDuffs)
        } catch {
            stopAssetLockPolling()
            captureLatestAssetLockOutPoint(
                walletId: env.walletId,
                modelContainer: env.modelContainer,
                since: startTime,
                fundingType: Self.addressAssetLockFundingType)
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        stopAssetLockPolling()
        Self.logger.info("🛡️ SHIELD-TX :: core→platform fund route completed")
        phase = .broadcasting
        phase = .success
        schedulePlatformResync()
    }

    /// Resume of route 5 after its asset lock committed but the address-
    /// funding ST never landed — drives the remaining stages on the SAME
    /// outpoint. Mirrors `resumeAssetLock` on the shielded route.
    func resumeFundPlatform(outPointTxidWire: Data, outPointVout: UInt32) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: resume core→platform fund vout=\(outPointVout)")

        do {
            _ = try resolveBasicEnvironment()
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

        // The lock is already on-chain; only the funding ST remains.
        phase = .broadcasting

        do {
            try await PlatformAddressSyncCoordinator.shared.resumeFundFromCore(
                outPointTxid: outPointTxidWire,
                outPointVout: outPointVout)
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: resume core→platform fund completed")
        phase = .success
        schedulePlatformResync()
    }

    /// Route 6: Platform address credits → Core L1 payout
    /// (`AddressCreditWithdrawalTransition`). Stages: `.signing →
    /// .broadcasting → .success` — a single opaque call, no proof and no
    /// asset lock. `fullBalance` picks the execution form: the AUTO
    /// withdrawal (every non-dust address, payout = balance − fee) when the
    /// user withdrew Max, else an explicit partial withdrawal paying out
    /// exactly `amountCredits` from the largest funded address. The L1
    /// payout arrives asynchronously once the chain processes the
    /// withdrawal; it shows as a regular incoming transaction.
    ///
    /// `toCoreAddress` nil = the wallet's own receive address (the internal
    /// transfer); an external Send passes the recipient's L1 address.
    func performPlatformWithdraw(
        amountCredits: UInt64,
        fullBalance: Bool,
        feeHeadroomCredits: UInt64?,
        toCoreAddress destinationOverride: String? = nil
    ) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: platform→core withdraw route full=\(fullBalance) amount=\(amountCredits) external=\(destinationOverride != nil)")

        // Destination Core (BIP44, Base58Check) address — for the internal
        // transfer, the wallet's own receive address (same resolution as the
        // shielded withdraw route).
        let coreAddress: String
        if let destinationOverride, !destinationOverride.isEmpty {
            coreAddress = destinationOverride
        } else {
            guard let ownAddress = SwiftDashSDKReceiveAddressReader.receiveAddress(),
                  !ownAddress.isEmpty else {
                handleFailure(CoordinatorError.noReceiveAddress)
                return
            }
            coreAddress = ownAddress
        }

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .broadcasting

        do {
            if fullBalance {
                try await PlatformAddressSyncCoordinator.shared.withdrawAllToCore(address: coreAddress)
            } else {
                try await PlatformAddressSyncCoordinator.shared.withdrawToCore(
                    amountCredits: amountCredits,
                    address: coreAddress,
                    feeHeadroomCredits: feeHeadroomCredits)
            }
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: platform→core withdraw completed")
        phase = .success
        schedulePlatformResync()
    }

    /// External send: shielded Orchard notes → a third-party shielded
    /// payment address (`recipientRaw43` = the recipient's raw 43-byte
    /// Orchard address, decoded from their bech32m display form). Stages:
    /// `.signing → .proving → .broadcasting → .success` — same opaque-call
    /// shape as `performWithdraw`/`performUnshield`.
    func performShieldedTransfer(amountCredits: UInt64, recipientRaw43: Data) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: shielded→shielded send amount=\(amountCredits) credits")

        let env: BasicEnvironment
        do {
            env = try resolveBasicEnvironment()
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

        do {
            try await env.manager.shieldedTransfer(
                walletId: env.walletId,
                // Per-operation Orchard spend authority — see `performWithdraw`.
                resolver: MnemonicResolver(),
                account: 0,
                recipientRaw43: recipientRaw43,
                amount: amountCredits)
        } catch {
            handleSpendError(error, manager: env.manager)
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: shielded→shielded send completed")
        phase = .broadcasting
        phase = .success
        scheduleShieldedResync(manager: env.manager)
    }

    /// External send: DIP-17 Platform credits → a third-party Platform
    /// bech32m address, via `PlatformSendExecutor` (credit transfer, inputs
    /// auto-selected largest-first). Stages: `.signing → .broadcasting →
    /// .success` — a single opaque transition, no proof and no asset lock.
    func performPlatformSend(destination: String, amountCredits: UInt64) async {
        guard beginTransfer() else { return }
        Self.logger.info("🛡️ SHIELD-TX :: platform→platform send amount=\(amountCredits) credits")

        do {
            try await authorize()
        } catch {
            handleFailure(error)
            return
        }

        phase = .broadcasting

        do {
            try await PlatformSendExecutor.shared.transfer(
                destination: destination,
                amount: amountCredits)
        } catch {
            handleFailure(CoordinatorError.transferFailed(error))
            return
        }

        Self.logger.info("🛡️ SHIELD-TX :: platform→platform send completed")
        phase = .success
        schedulePlatformResync()
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

    private struct BasicEnvironment {
        let manager: PlatformWalletManager
        let walletId: Data
        let network: Network
        let modelContainer: ModelContainer
    }

    private struct Environment {
        let manager: PlatformWalletManager
        let walletId: Data
        let network: Network
        let modelContainer: ModelContainer
        let shieldedRecipient: Data
    }

    /// Host readiness shared by every route. The Core↔Platform legs stop
    /// here; the shielded legs also require the bound Orchard address
    /// (`resolveEnvironment`).
    private func resolveBasicEnvironment() throws -> BasicEnvironment {
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
        return BasicEnvironment(
            manager: manager,
            walletId: wallet.walletId,
            network: network,
            modelContainer: modelContainer)
    }

    private func resolveEnvironment() throws -> Environment {
        let basic = try resolveBasicEnvironment()
        let recipient: Data?
        do {
            recipient = try basic.manager.shieldedDefaultAddress(walletId: basic.walletId, account: 0)
        } catch {
            throw CoordinatorError.transferFailed(error)
        }
        guard let recipient, recipient.count == 43 else {
            throw CoordinatorError.noShieldedAddress
        }
        return Environment(
            manager: basic.manager,
            walletId: basic.walletId,
            network: basic.network,
            modelContainer: basic.modelContainer,
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

    /// Map a shielded-spend FFI error to the right terminal phase. The SDK
    /// throws `PlatformWalletError.shieldedSpendUnconfirmed` when the broadcast
    /// was accepted by relay but its result couldn't be confirmed — the host
    /// must NOT re-submit (a retry risks a double-spend / wasted fee). Surface
    /// that as the distinct, non-retryable `.submittedUnconfirmed` and kick a
    /// shielded sync so the effect lands; everything else is a normal failure.
    private func handleSpendError(_ error: Error, manager: PlatformWalletManager) {
        if case PlatformWalletError.shieldedSpendUnconfirmed = error {
            Self.logger.info("🛡️ SHIELD-TX :: broadcast unconfirmed — awaiting sync, retry suppressed")
            phase = .submittedUnconfirmed
            scheduleShieldedResync(manager: manager)
        } else {
            handleFailure(CoordinatorError.transferFailed(error))
        }
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

    /// Kick the Platform-address (BLAST) sync after a transfer that changes the
    /// DIP-17 Platform balance — `performShield` debits it, `performUnshield`
    /// credits it. `scheduleShieldedResync` only refreshes the shielded side, so
    /// without this the "Platform Payment" balance stays stale until the next
    /// periodic BLAST pass. A few spaced kicks cover the brief indexing lag
    /// before the credit is visible past the BLAST watermark (`syncNow()` no-ops
    /// while a pass is already running, so a single immediate call can miss it).
    /// `performPlatformSend` relies on the same kick after a Platform send.
    private func schedulePlatformResync() {
        Task {
            for delayNanos in [UInt64(0), 4_000_000_000, 12_000_000_000] {
                if delayNanos > 0 {
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
                await PlatformAddressSyncCoordinator.shared.syncNow()
            }
        }
    }

    // MARK: - Asset-lock polling

    /// Mirror `DWIdentityRegistrationCoordinator.startAssetLockPolling` —
    /// 0.5 s cadence, lifetime-bounded by the in-flight transfer.
    /// Defensive about the row not existing yet (or ever): the FFI emits
    /// the row asynchronously and earlier statuses may already be skipped
    /// past by the time we look.
    private func startAssetLockPolling(
        walletId: Data,
        modelContainer: ModelContainer,
        startTime: Date,
        fundingType: Int = ShieldedTransferCoordinator.shieldedAssetLockFundingType
    ) {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.assetLockPollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.pollAssetLockStatus(
                    walletId: walletId,
                    modelContainer: modelContainer,
                    startTime: startTime,
                    fundingType: fundingType)
            }
        }
    }

    private func stopAssetLockPolling() {
        assetLockPollingTask?.cancel()
        assetLockPollingTask = nil
    }

    private func pollAssetLockStatus(
        walletId: Data,
        modelContainer: ModelContainer,
        startTime: Date,
        fundingType: Int = ShieldedTransferCoordinator.shieldedAssetLockFundingType
    ) async {
        // Only meaningful while the asset-lock route is in-flight.
        switch phase {
        case .locking, .proving, .broadcasting:
            break
        default:
            return
        }

        let context = modelContainer.mainContext
        let shieldedFundingType = fundingType
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
