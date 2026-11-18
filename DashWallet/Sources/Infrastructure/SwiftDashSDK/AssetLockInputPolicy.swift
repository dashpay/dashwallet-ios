//
//  AssetLockInputPolicy.swift
//  DashWallet
//
//  An asset lock (Core DASH → Platform credits) may carry at most 100 inputs
//  (`max_asset_lock_transaction_inputs`). Dash Core v23.1.7+ drops a larger
//  one as non-standard without a reject, so it never gets InstantSend-locked,
//  and Platform refuses it if an older node mines it (dashpay/platform#5513).
//  The SDK refuses to build such a lock — a drain or a fixed amount — before
//  broadcast (`PlatformWalletError.assetLockTooManyInputs`, dashpay/platform#5712),
//  and every Core-funded asset-lock route shows that refusal as an offer to
//  combine the coins (`CoreCoinConsolidationSheet`). Where the amount is known
//  up front, the route also checks the coins itself first, so a lock no
//  selection could fit is refused before the PIN prompt.
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
/// largest first, until they cover the amount plus the lowest fee any
/// selection of that many inputs could pay (`minimumFeeDuffs`). Then no
/// selection within the budget exists when the count is over it, so a refusal
/// is never one the SDK would have built within the cap. A lock it lets
/// through can still need more inputs — BranchAndBound may pick a change-free
/// set of many small coins — and the SDK's own refusal
/// (`PlatformWalletError.assetLockTooManyInputs`) catches that.
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

    /// Input budget for every Core-funded asset lock: the network's hard cap
    /// (`CoinJoinShieldPlanner.maxAssetLockInputs`). A shielded lock gets the
    /// same budget: when its InstantSend proof makes the transition too large,
    /// the SDK resubmits it with a ChainLock proof (dashpay/platform#5460).
    static let platformInputBudget = CoinJoinShieldPlanner.maxAssetLockInputs

    /// Room for the asset-lock special payload (version, one credit output
    /// and its length prefix) on top of a regular two-output transaction.
    static let payloadAllowanceBytes: UInt64 = 40

    /// The size of a one-credit asset lock without inputs and without change:
    /// key-wallet's base (version, type, locktime, counts, the burn output)
    /// plus the payload. A selection that needs no change pays only this and
    /// its inputs; any other pays more.
    static let noChangeBaseBytes: UInt64 = 81

    /// The fee of an asset lock spending `inputCount` inputs with a change
    /// output: the 1 duff/byte size model of a regular send plus the payload.
    /// An upper estimate, used where a shortfall would cost the user a fee.
    static func estimatedFeeDuffs(inputCount: Int) -> UInt64 {
        SwiftDashSDKTransactionSender.estimatedFee(inputCount: inputCount) + payloadAllowanceBytes
    }

    /// The lowest fee an asset lock spending `inputCount` inputs can pay at
    /// 1 duff/byte: no change output (`noChangeBaseBytes`).
    static func minimumFeeDuffs(inputCount: Int) -> UInt64 {
        noChangeBaseBytes + UInt64(inputCount) * 148
    }

    /// The verdict for locking `amountDuffs` from coins worth `utxoValues`,
    /// with the lowest fee (`minimumFeeDuffs`): the input count it finds is
    /// the fewest any selection could use.
    ///
    /// - Parameter utxoValues: the values of the FINAL coins only; the
    ///   builder never spends one that is not.
    static func verdict(utxoValues: [UInt64], amountDuffs: UInt64, inputBudget: Int) -> Verdict {
        verdict(utxoValues: utxoValues, amountDuffs: amountDuffs, inputBudget: inputBudget, fee: minimumFeeDuffs)
    }

    private static func verdict(
        utxoValues: [UInt64], amountDuffs: UInt64, inputBudget: Int, fee: (Int) -> UInt64
    ) -> Verdict {
        var total: UInt64 = 0
        for (index, value) in utxoValues.sorted(by: >).enumerated() {
            let (sum, overflow) = total.addingReportingOverflow(value)
            total = overflow ? .max : sum
            let inputCount = index + 1
            let (needed, neededOverflow) = amountDuffs.addingReportingOverflow(fee(inputCount))
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

    /// The verdict for a lock of `amountDuffs` (nil: a whole-balance drain)
    /// once the Core consolidation has combined the `combinable` coins — the
    /// final coins of BIP44 account 0, the only account it spends. The other
    /// final coins (`other`) stay as they are. The lock is priced with a
    /// change output (`estimatedFeeDuffs`): the combined coin is usually
    /// larger than the amount, and Combine must not be offered for a lock
    /// that would then fall short.
    static func verdictAfterCombining(
        combinable: [UInt64], other: [UInt64], amountDuffs: UInt64?, inputBudget: Int
    ) -> Verdict {
        let values = other + combinedValues(combinable)
        guard let amountDuffs else {
            return drainVerdict(finalCount: values.count, inputBudget: inputBudget)
        }
        return verdict(utxoValues: values, amountDuffs: amountDuffs, inputBudget: inputBudget, fee: estimatedFeeDuffs)
    }

    /// The fee of combining `coinCount` coins: one transaction per chunk
    /// (`combinedValues`), each priced like a regular send. An upper estimate:
    /// the consolidation has one output, not two.
    static func consolidationFeeDuffs(coinCount: Int) -> UInt64 {
        guard coinCount >= 2 else { return 0 }
        return SwiftDashSDKTransactionSender.balancedChunks(
            Array(repeating: 0, count: coinCount), maxPerChunk: SwiftDashSDKTransactionSender.maxInputsPerSweep
        ).reduce(0) { $0 + SwiftDashSDKTransactionSender.estimatedFee(inputCount: $1.count) }
    }

    /// The coins the consolidation leaves for `values`: one per transaction
    /// (`SwiftDashSDKTransactionSender.maxInputsPerSweep` inputs at most),
    /// each worth its inputs less the transaction's fee. Fewer than two coins
    /// are not combined.
    static func combinedValues(_ values: [UInt64]) -> [UInt64] {
        guard values.count >= 2 else { return values }
        return SwiftDashSDKTransactionSender.balancedChunks(
            values, maxPerChunk: SwiftDashSDKTransactionSender.maxInputsPerSweep
        ).map { chunk in
            let total = chunk.reduce(UInt64(0)) { sum, value in
                let (next, overflow) = sum.addingReportingOverflow(value)
                return overflow ? .max : next
            }
            let fee = SwiftDashSDKTransactionSender.estimatedFee(inputCount: chunk.count)
            return total > fee ? total - fee : 0
        }
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
    /// `ShieldedTransferCoordinator.failureMessage(for:)` unwraps the
    /// recipient-mismatch refusal through it too.
    static func innermost(_ error: Error) -> Error {
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
    /// when no wallet is bound or its coins cannot be read — then the caller
    /// goes ahead and the SDK decides, as before this check existed.
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

    /// The estimated fee of combining the coins (`CoreCoinConsolidationSheet`)
    /// when that would let `check` fit: the BIP44 account has at least two
    /// final coins, and the lock fits once they are one
    /// (`verdictAfterCombining`). Nil when it would not, or when the wallet's
    /// coins cannot be read.
    @MainActor
    static func combiningFeeToFit(_ check: Check) -> UInt64? {
        guard let utxos = SwiftDashSDKTransactionSender.pooledSpendableUtxos() else { return nil }
        let finals = utxos.filter(\.isFinal)
        let combinable = finals.filter(\.isCombinable).map(\.valueDuffs)
        guard combinable.count >= 2 else { return nil }
        let verdict = AssetLockInputPolicy.verdictAfterCombining(
            combinable: combinable,
            other: finals.filter { !$0.isCombinable }.map(\.valueDuffs),
            amountDuffs: check.amountDuffs,
            inputBudget: check.inputBudget)
        DWLogger.log(
            "🔒 ASSET-LOCK-INPUTS :: after combining \(combinable.count) BIP44 coin(s): verdict=\(verdict)",
            className: "AssetLockInputLimit")
        guard verdict == .fits else { return nil }
        return AssetLockInputPolicy.consolidationFeeDuffs(coinCount: combinable.count)
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
