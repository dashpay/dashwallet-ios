//
//  AssetLockInputPolicy.swift
//  DashWallet
//
//  An asset lock (Core DASH → Platform credits) may carry at most 100 inputs
//  (`max_asset_lock_transaction_inputs`). Dash Core v23.1.7+ drops a larger
//  one as non-standard without a reject, so it never gets InstantSend-locked,
//  and Platform refuses it if an older node mines it (dashpay/platform#5513).
//  The SDK the app builds against refuses only a whole-balance drain over the
//  cap; a fixed amount held in many small coins is broadcast and lost to the
//  network. So every Core-funded asset-lock route checks the coins first and,
//  when they would need too many inputs, offers to combine them
//  (`CoreCoinConsolidationSheet`) instead of building the lock.
//
//  The policy is pure — its inputs are passed in — so
//  `AssetLockInputPolicyTests` can pin it without a wallet. `AssetLockInputLimit`
//  reads those inputs off the SDK and recognises the SDK's own refusal.
//

import Foundation
import SwiftDashSDK

/// Whether a Core-funded asset lock of a given amount fits in one transaction.
///
/// A pre-flight approximation of key-wallet's selection: asset locks are built
/// with `require_final_inputs()` and BranchAndBound, which sorts coins largest
/// first and, when no change-free match exists, accumulates them largest
/// first. So only final coins (confirmed or InstantSend-locked) are counted,
/// largest first, until they cover the amount plus the fee. The SDK's own
/// refusal (`PlatformWalletError.assetLockTooManyInputs`) stays authoritative.
enum AssetLockInputPolicy {

    enum Verdict: Equatable {
        /// Few enough of the largest final coins cover the lock.
        case fits
        /// The lock needs more inputs than `inputBudget`: combine the coins first.
        case needsConsolidation
        /// The final coins cannot cover the lock at all. Left to the SDK's
        /// own insufficient-funds error, as before this check existed.
        case insufficientFunds
    }

    /// Input budget for a lock whose credits fund an identity or a Platform
    /// address: the network's hard cap (`CoinJoinShieldPlanner.maxAssetLockInputs`).
    static let platformInputBudget = CoinJoinShieldPlanner.maxAssetLockInputs

    /// Input budget for a lock that is shielded right away. Tighter than the
    /// hard cap: the ShieldFromAssetLock transition embeds the whole lock in
    /// its InstantSend proof and outgrows Platform's 20 480-byte limit from
    /// about 65 inputs (see `CoinJoinShieldPlanner.consolidationThreshold`).
    /// Revisit once the ChainLock-proof fallback (dashpay/platform#5460) is in
    /// the SDK the app builds against.
    static let shieldInputBudget = CoinJoinShieldPlanner.consolidationThreshold

    /// Room for the asset-lock special payload (version, one credit output
    /// and its length prefix) on top of a regular two-output transaction.
    static let payloadAllowanceBytes: UInt64 = 40

    /// The fee of an asset lock spending `inputCount` inputs: the 1 duff/byte
    /// size model of a regular send plus the payload.
    static func estimatedFeeDuffs(inputCount: Int) -> UInt64 {
        SwiftDashSDKTransactionSender.estimatedSignalFee(inputCount: inputCount) + payloadAllowanceBytes
    }

    /// The verdict for locking `amountDuffs` from coins worth `utxoValues`.
    ///
    /// - Parameter utxoValues: the values of the FINAL coins only; the
    ///   builder never spends one that is not.
    static func verdict(utxoValues: [UInt64], amountDuffs: UInt64, inputBudget: Int) -> Verdict {
        var total: UInt64 = 0
        for (index, value) in utxoValues.sorted(by: >).enumerated() {
            let (sum, overflow) = total.addingReportingOverflow(value)
            total = overflow ? .max : sum
            let inputCount = index + 1
            let (needed, neededOverflow) = amountDuffs.addingReportingOverflow(estimatedFeeDuffs(inputCount: inputCount))
            guard !neededOverflow else { return .insufficientFunds }
            if total >= needed {
                return inputCount > inputBudget ? .needsConsolidation : .fits
            }
        }
        return .insufficientFunds
    }

    /// The verdict for a whole-balance drain, which spends every final coin.
    static func drainVerdict(finalCount: Int, inputBudget: Int) -> Verdict {
        guard finalCount > 0 else { return .insufficientFunds }
        return finalCount > inputBudget ? .needsConsolidation : .fits
    }
}

/// The asset-lock input limit as the app meets it: the pre-check over the
/// wallet's coins, and the SDK's refusal of a lock over the cap.
enum AssetLockInputLimit {

    /// One lock to check: `amountDuffs` is what coin selection must cover
    /// (nil for a whole-balance drain), within `inputBudget` inputs.
    struct Check: Equatable {
        let amountDuffs: UInt64?
        let inputBudget: Int

        static func drain(inputBudget: Int) -> Check {
            Check(amountDuffs: nil, inputBudget: inputBudget)
        }
    }

    /// The input limit, as the pre-check or a route that caught the SDK's
    /// refusal reports it: nothing was broadcast. `check` is the refused
    /// lock, re-checked once the coins are combined.
    struct TooManyInputsError: LocalizedError {
        let check: Check

        var errorDescription: String? { AssetLockInputLimit.message }
    }

    static var title: String {
        NSLocalizedString("Too many coins for one transfer", comment: "Asset-lock input limit")
    }

    static var message: String {
        NSLocalizedString(
            "This transfer needs more separate coins than the network accepts in one transfer. Combine your coins first (a small network fee applies), then try again.",
            comment: "Asset-lock input limit")
    }

    /// Whether `error` is the asset-lock input limit — the SDK's typed refusal
    /// (FFI code 60) or `TooManyInputsError` — directly or wrapped by one of
    /// the coordinators that report it.
    static func isTooManyInputs(_ error: Error) -> Bool {
        switch innermost(error) {
        case is TooManyInputsError, PlatformWalletError.assetLockTooManyInputs:
            return true
        default:
            return false
        }
    }

    /// The lock to re-check once the coins are combined, when `error` is the
    /// input limit: the one the refusal carries, else — an SDK refusal no
    /// route mapped — a whole-balance drain within the network's cap.
    static func check(for error: Error) -> Check? {
        guard isTooManyInputs(error) else { return nil }
        return (innermost(error) as? TooManyInputsError)?.check
            ?? .drain(inputBudget: AssetLockInputPolicy.platformInputBudget)
    }

    /// The error the coordinators' wrappers carry, unwrapped all the way.
    private static func innermost(_ error: Error) -> Error {
        switch error {
        case ShieldedTransferCoordinator.CoordinatorError.transferFailed(let underlying):
            return innermost(underlying)
        case let wrapped as DWIdentityRegistrationCoordinator.CoordinatorError:
            switch wrapped {
            case .identityRegistration(let underlying), .identityTopUp(let underlying), .purchase(let underlying):
                return innermost(underlying)
            default:
                return wrapped
            }
        default:
            return error
        }
    }

    /// Runs `work`, the SDK call that builds the lock `check` describes, and
    /// reports the SDK's input-limit refusal as `TooManyInputsError`, so the
    /// surface can re-check that lock after combining coins.
    static func mappingRefusal<T>(_ check: Check, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch PlatformWalletError.assetLockTooManyInputs {
            throw TooManyInputsError(check: check)
        }
    }

    /// `error`'s text, with the shared explanation for the input limit.
    static func userMessage(for error: Error) -> String {
        isTooManyInputs(error) ? message : error.localizedDescription
    }

    /// The verdict for `check` over the wallet's pooled Core coins, or nil
    /// when no wallet is bound — then the caller goes ahead and the SDK
    /// decides, as before this check existed.
    @MainActor
    static func verdict(for check: Check) -> AssetLockInputPolicy.Verdict? {
        guard let utxos = SwiftDashSDKTransactionSender.pooledSpendableUtxos() else { return nil }
        let finalValues = utxos.filter(\.isFinal).map(\.valueDuffs)
        let verdict: AssetLockInputPolicy.Verdict
        if let amountDuffs = check.amountDuffs {
            verdict = AssetLockInputPolicy.verdict(
                utxoValues: finalValues, amountDuffs: amountDuffs, inputBudget: check.inputBudget)
        } else {
            verdict = AssetLockInputPolicy.drainVerdict(finalCount: finalValues.count, inputBudget: check.inputBudget)
        }
        DWLogger.log(
            "🔒 ASSET-LOCK-INPUTS :: amount=\(check.amountDuffs.map(String.init) ?? "drain") budget=\(check.inputBudget) "
                + "coins=\(utxos.count) final=\(finalValues.count) verdict=\(verdict)",
            className: "AssetLockInputLimit")
        return verdict
    }

    /// Throws `TooManyInputsError` when `check` needs more inputs than its
    /// budget. Any other verdict goes ahead: the SDK reports a shortfall itself.
    @MainActor
    static func requireFits(_ check: Check) throws {
        if verdict(for: check) == .needsConsolidation {
            throw TooManyInputsError(check: check)
        }
    }
}
