//
//  CoreCoinConsolidationViewModel.swift
//  DashWallet
//
//  Stage machine behind `CoreCoinConsolidationSheet`, shown by every
//  Core-funded asset-lock route when the lock would need more inputs than the
//  network accepts (`AssetLockInputPolicy`). It combines the BIP44 account's
//  final coins onto one fresh receive address of the same wallet
//  (`SwiftDashSDKTransactionSender.consolidateCoreAccount`), waits for the
//  result to be InstantSend-locked or confirmed, and then hands back to the
//  user, who retries the original transfer themselves.
//
//  Failure posture: the consolidation pays the wallet itself, so a failed or
//  interrupted attempt leaves the coins in the wallet, on fewer UTXOs. A
//  broadcast whose outcome is unknown blocks the next attempt until it shows
//  up, so the same coins are never spent twice.
//

import Combine
import Foundation

@MainActor
final class CoreCoinConsolidationViewModel: ObservableObject {

    enum Stage: Equatable {
        /// Why the transfer stopped. `combineFeeDuffs` offers the
        /// consolidation at that estimated fee; nil means combining here
        /// would not help, and the sheet says so.
        case explain(combineFeeDuffs: UInt64?)
        case combining
        /// The coins are combined. `transferFits`: the transfer now fits and
        /// the user can retry it; otherwise the fee left too little for it.
        case done(transferFits: Bool)
        case failed(String)
    }

    @Published private(set) var stage: Stage = .explain(combineFeeDuffs: nil)

    /// From the first line of `combine()` to its end, PIN prompt included,
    /// so a second tap is ignored instead of starting a second run.
    @Published private var isRunning = false

    /// The lock that was refused, re-checked once the coins are combined.
    let check: AssetLockInputLimit.Check

    /// The wallet and network the sheet was opened for. A switch while it is
    /// up stops the consolidation.
    private let binding = SwiftDashSDKTransactionSender.CoinJoinWalletBinding.current()

    /// Wire-order txids of this sheet's consolidations whose broadcast
    /// outcome was unknown: no new attempt runs until each has an output in
    /// the BIP44 account.
    private var unobservedTxids: [Data] = []

    /// Wire-order txids of accepted consolidations whose output is not final
    /// yet. The next consolidation and the re-check wait for them: until then
    /// the asset lock cannot spend that output.
    private var awaitedTxids: [Data] = []

    /// Awaited txids that have had an output in the BIP44 account. One whose
    /// output is gone again was spent by another send before it was final:
    /// it can no longer become final here, so it is not waited for.
    private var observedTxids: Set<Data> = []

    /// How long the wait for the combined coins to become final lasts.
    /// InstantSend normally locks within seconds.
    static let finalityTimeout: TimeInterval = CoinJoinMoveFundsViewModel.finalityTimeout

    init(check: AssetLockInputLimit.Check) {
        self.check = check
        stage = .explain(combineFeeDuffs: AssetLockInputLimit.combiningFeeToFit(check))
    }

    var isInFlight: Bool { isRunning || stage == .combining }

    // MARK: Actions

    /// Asks for the PIN, combines the final BIP44 coins, waits for the result
    /// to be final, and re-checks the refused lock.
    func combine() async {
        guard !isInFlight else { return }
        isRunning = true
        defer { isRunning = false }
        guard let binding, binding == SwiftDashSDKTransactionSender.CoinJoinWalletBinding.current() else {
            Self.log("refused — the active wallet changed")
            stage = .failed(Self.genericFailureMessage)
            return
        }
        do {
            try WalletSendService.ensureOnline()
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }
        if let refusal = unobservedRefusal(binding) {
            stage = .failed(refusal)
            return
        }
        guard await authorize() else { return }

        stage = .combining
        do throws(Stop) {
            // The earlier consolidations settle first, so the new one never
            // spends an output this model still waits for.
            try await awaitFinal(binding)
            awaitedTxids += try await consolidate(binding)
            try await awaitFinal(binding)
        } catch {
            stage = .failed(error.message)
            return
        }
        guard let verdict = AssetLockInputLimit.verdict(for: check) else {
            stage = .failed(Self.genericFailureMessage)
            return
        }
        Self.log("re-check after combining: \(verdict)")
        switch verdict {
        case .fits:
            stage = .done(transferFits: true)
        case .insufficientFunds:
            stage = .done(transferFits: false)
        case .needsConsolidation:
            stage = .explain(combineFeeDuffs: AssetLockInputLimit.combiningFeeToFit(check))
        }
    }

    /// Ends an attempt with the message to show.
    private struct Stop: Error {
        let message: String
    }

    /// The PIN prompt the CoinJoin move uses. False when it was cancelled
    /// (the explanation stays) or failed (the failure is shown).
    private func authorize() async -> Bool {
        do {
            try await DWIdentityAuthorizer().authorize()
            return true
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            Self.log("authorization cancelled")
            return false
        } catch {
            Self.log("authorization failed")
            stage = .failed(
                ShieldedTransferCoordinator.CoordinatorError.authFailed.errorDescription ?? Self.genericFailureMessage)
            return false
        }
    }

    /// Why an earlier consolidation whose outcome was unknown blocks a new
    /// one, or nil once each has an output in the account (it is then waited
    /// on like an accepted one).
    private func unobservedRefusal(_ binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding) -> String? {
        guard !unobservedTxids.isEmpty else { return nil }
        guard let state = SwiftDashSDKTransactionSender.bip44UtxoState(expecting: binding) else {
            return Self.genericFailureMessage
        }
        // Any output counts, final or not: it shows the wallet applied it.
        guard Set(state.entries.map(\.txid)).isSuperset(of: unobservedTxids) else {
            Self.log("an earlier consolidation is not in the wallet yet, not combining again")
            return Self.stillCombiningMessage
        }
        observedTxids.formUnion(unobservedTxids)
        awaitedTxids += unobservedTxids
        unobservedTxids = []
        return nil
    }

    /// Broadcasts the consolidation of the final BIP44 coins and returns its
    /// txids; none when fewer than two are final.
    private func consolidate(
        _ binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding
    ) async throws(Stop) -> [Data] {
        guard let state = SwiftDashSDKTransactionSender.bip44UtxoState(expecting: binding) else {
            Self.log("the active wallet changed, or its coins could not be read")
            throw Stop(message: Self.genericFailureMessage)
        }
        let outpoints = state.finalOutpoints
        guard outpoints.count >= 2 else {
            Self.log("n=\(state.count) final=\(state.finalCount), nothing to combine")
            return []
        }
        guard let destination = SwiftDashSDKReceiveAddressReader.receiveDestination(),
              destination.walletId == binding.walletId
        else {
            Self.log("no receive address for the consolidation")
            throw Stop(message: Self.genericFailureMessage)
        }
        let chunks = SwiftDashSDKTransactionSender.balancedChunks(
            Array(repeating: 0, count: outpoints.count),
            maxPerChunk: SwiftDashSDKTransactionSender.maxInputsPerSweep
        ).map(\.count)
        Self.log("combining \(outpoints.count) final of n=\(state.count) coins into \(chunks.count) tx(s) \(chunks)")

        let outcome: SwiftDashSDKTransactionSender.SweepOutcome
        do {
            // Off the main actor so the progress renders first; the sender
            // hops back to main for the SDK calls themselves.
            let address = destination.address
            outcome = try await Task.detached(priority: .userInitiated) {
                try SwiftDashSDKTransactionSender.consolidateCoreAccount(
                    to: address, expecting: binding, outpoints: outpoints)
            }.value
        } catch let error as SwiftDashSDKTransactionSender.CoinJoinSweepUnknownError {
            // The broadcasts may have reached peers; the next attempt waits
            // until their outputs show.
            unobservedTxids = error.unknownTxids
            Self.log("consolidation outcome unknown")
            throw Stop(message: Self.stillCombiningMessage)
        } catch {
            Self.log("consolidation failed, nothing accepted: \(WalletSendService.logSummary(of: error))")
            throw Stop(message: Self.genericFailureMessage)
        }
        unobservedTxids = outcome.unknownTxids
        let failure = outcome.firstFailure.map { ", one: \(WalletSendService.logSummary(of: $0))" } ?? ""
        Self.log("consolidation broadcast \(outcome.txids.count) tx(s), \(outcome.failedChunkCount) failed\(failure)")
        // A failed chunk may still have reached peers; the next attempt plans
        // from the coins as the wallet reads them then.
        if outcome.isPartial {
            awaitedTxids += outcome.txids
            throw Stop(message: Self.stillCombiningMessage)
        }
        return outcome.txids
    }

    /// Waits until every awaited consolidation has a final output in the
    /// BIP44 account, so the asset lock can spend it — or, once seen, has no
    /// output left (`stillAwaited`).
    private func awaitFinal(
        _ binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding
    ) async throws(Stop) {
        let txids = awaitedTxids
        guard !txids.isEmpty else { return }
        let waitStart = Date()
        let observed = TxidSet(observedTxids)
        defer { observedTxids = observed.txids }
        let result: (state: SwiftDashSDKTransactionSender.CoinJoinUtxoState, satisfied: Bool)?
        do {
            result = try await SwiftDashSDKTransactionSender.waitForBip44UtxoState(
                binding: binding, timeout: Self.finalityTimeout
            ) { state in
                let present = Set(state.entries.map(\.txid))
                observed.txids.formUnion(present.intersection(txids))
                return CoinJoinShieldPlanner.consolidationSettled(
                    consolidationTxids: Self.stillAwaited(txids, present: present, observed: observed.txids),
                    utxos: state.txidFinality)
            }
        } catch {
            Self.log("cancelled while waiting for finality")
            throw Stop(message: Self.stillCombiningMessage)
        }
        guard let result else {
            Self.log("the active wallet changed, or its coins could not be read, while waiting for finality")
            throw Stop(message: Self.genericFailureMessage)
        }
        let waitedSeconds = Int(Date().timeIntervalSince(waitStart).rounded())
        Self.log(
            "finality wait \(result.satisfied ? "settled" : "timed out") after \(waitedSeconds)s "
                + "(cap \(Int(Self.finalityTimeout))s): n=\(result.state.count) final=\(result.state.finalCount)")
        guard result.satisfied else { throw Stop(message: Self.stillCombiningMessage) }
        awaitedTxids = []
    }

    /// The awaited txids still worth waiting for: all but those seen with an
    /// output (`observed`) whose output is gone (`present` holds the txids
    /// with an output now).
    nonisolated static func stillAwaited(_ awaited: [Data], present: Set<Data>, observed: Set<Data>) -> [Data] {
        awaited.filter { present.contains($0) || !observed.contains($0) }
    }

    /// The observed txids, updated by the finality poll.
    private final class TxidSet {
        var txids: Set<Data>
        init(_ txids: Set<Data>) { self.txids = txids }
    }

    // MARK: Strings

    static var combineButtonTitle: String {
        NSLocalizedString("Combine coins", comment: "Asset-lock input limit")
    }

    static var combiningLabel: String {
        NSLocalizedString("Combining coins…", comment: "Asset-lock input limit")
    }

    static var doneMessage: String {
        NSLocalizedString("Your coins are combined. You can try again now.", comment: "Asset-lock input limit")
    }

    static var doneShortMessage: String {
        NSLocalizedString(
            "Your coins are combined, but the network fee leaves too little for this amount. Try a smaller amount.",
            comment: "Asset-lock input limit")
    }

    /// The estimated fee of combining, shown before the PIN prompt.
    static func feeLine(duffs: UInt64) -> String {
        String(format: NSLocalizedString("Network fee: %@ DASH", comment: ""), duffs.formattedDashAmountWithoutCurrencySymbol)
    }

    static var cannotCombineMessage: String {
        NSLocalizedString(
            "Combining the coins in this wallet won't make this transfer fit. Try a smaller amount.",
            comment: "Asset-lock input limit")
    }

    private static var stillCombiningMessage: String {
        NSLocalizedString(
            "Your coins are still being combined. Please try again in a few minutes.",
            comment: "Asset-lock input limit")
    }

    private static var genericFailureMessage: String {
        NSLocalizedString("Couldn't combine your coins. Please try again.", comment: "Asset-lock input limit")
    }

    /// Exported-log line (DWLogger reaches "Share logs"; os.Logger does not).
    private static func log(_ message: String) {
        DWLogger.log("🔒 COMBINE-COINS :: \(message)", className: "CoreCoinConsolidationViewModel")
    }
}

#if DEBUG
extension CoreCoinConsolidationViewModel {

    /// Preview-only: the model parked at `stage`.
    static func preview(stage: Stage) -> CoreCoinConsolidationViewModel {
        let model = CoreCoinConsolidationViewModel(
            check: AssetLockInputLimit.Check(amountDuffs: 100_000_000, inputBudget: AssetLockInputPolicy.platformInputBudget))
        model.stage = stage
        return model
    }
}
#endif
