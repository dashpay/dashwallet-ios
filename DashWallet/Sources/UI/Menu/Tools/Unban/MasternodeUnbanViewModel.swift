//
//  Created by Claude Code
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import SwiftDashSDK
import SwiftUI

/// Where the operator BLS key for an unban comes from.
enum UnbanOperatorKeySource {
    /// Wallet-owned masternode: the SDK derives the key at the record's
    /// resolved `operatorKeyIndex` through the mnemonic resolver.
    case wallet(operatorKeyIndex: UInt32)
    /// Tracked masternode: the vaulted operator key text signs.
    case tracked(vault: TrackedMasternodeKeyVaulting)
}

/// The unban (ProUpServTx) flow for one PoSe-banned masternode: fee-funding
/// preflight (with the guided shielded-pool top-up when the wallet has no
/// spendable DASH), the evonode P2P port and operator-payout inputs, the
/// authenticated submit, and the persisted pending step that survives the
/// minutes-long withdrawal settlement. Owns every SDK call; the sheet only
/// renders and forwards actions.
@MainActor
final class MasternodeUnbanViewModel: ObservableObject {

    enum Phase: Equatable {
        /// Enough spendable DASH for the network fee — ready to submit.
        case ready
        /// No spendable DASH for the fee; offer the shielded top-up.
        case needsFunds
        /// The shielded→L1 withdrawal is proving/broadcasting.
        case toppingUp
        /// Withdrawal submitted; the L1 payout settles through the Platform
        /// withdrawal queue (minutes). Polling the spendable balance.
        case waitingForFunds
        case submitting
        /// The ProUpServTx was broadcast and accepted (display-order txid).
        case submitted(txidHex: String)
    }

    let record: PlatformMasternode
    let keySource: UnbanOperatorKeySource

    /// Evonode platform P2P port (D4: the masternode list doesn't carry it —
    /// user-editable, defaulting to Tenderdash's standard port).
    @Published var p2pPortText = "26656"
    /// Operator payout address — revealed only when the SDK reports the node
    /// pays an operator reward (D2: the payload replaces the payout script
    /// on-chain, so it must be confirmed explicitly, never defaulted).
    @Published var payoutAddressText = ""
    @Published private(set) var payoutAddressRequired = false

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var errorText: String?
    /// A terminal outcome (unconfirmed broadcast, unsupported entry): the
    /// submit button stays hidden so the flow can't be retried into a
    /// double-spend or a repeat failure.
    @Published private(set) var terminal = false

    @Published private(set) var spendableDuffs: UInt64 = 0
    @Published private(set) var shieldedBalanceCredits: UInt64 = 0

    /// Drives the shielded→L1 top-up; same coordinator the transfer screens
    /// use, constructed per flow.
    let topUpCoordinator = ShieldedTransferCoordinator()

    /// Spendable floor that comfortably covers a ~500-byte ProUpServTx at
    /// the default fee rate, with headroom for the wallet's input shapes.
    static let feeFloorDuffs: UInt64 = 10_000
    /// Shielded top-up amount: 0.001 DASH — small, but far above dust and
    /// enough for many unban fees.
    static let topUpDuffs: UInt64 = 100_000

    static var topUpCredits: UInt64 {
        topUpDuffs * EvonodeWithdrawalViewModel.creditsPerDuff
    }

    private var balancePollTask: Task<Void, Never>?

    init(record: PlatformMasternode, keySource: UnbanOperatorKeySource) {
        self.record = record
        self.keySource = keySource
        if let pending = PendingMasternodeUnbanStore.shared.pending(forProTxHash: record.proTxHash) {
            if let port = pending.platformP2PPort {
                p2pPortText = String(port)
            }
            if let payout = pending.operatorPayoutAddress {
                payoutAddressText = payout
                payoutAddressRequired = true
            }
        }
    }

    var isEvonode: Bool { record.isEvonode }

    var p2pPort: UInt16? {
        UInt16(p2pPortText.trimmingCharacters(in: .whitespaces))
    }

    var canSubmit: Bool {
        guard !terminal else { return false }
        guard phase == .ready else { return false }
        if isEvonode && p2pPort == nil { return false }
        if payoutAddressRequired {
            let payout = payoutAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payout.isEmpty, payout.isValidDashAddressForCurrentNetwork else { return false }
        }
        return true
    }

    var topUpAmountText: String {
        String(format: "%.4f DASH", Double(Self.topUpDuffs) / 100_000_000.0)
    }

    var canTopUp: Bool {
        shieldedBalanceCredits >= Self.topUpCredits
    }

    /// Refresh the funding preflight: spendable L1 balance vs the fee floor,
    /// and the shielded balance the top-up offer is gated on. Re-entered by
    /// the balance poller while waiting for a top-up to land.
    func refreshFunding() {
        let balance = (try? SwiftDashSDKHost.shared.wallet?.balance()) ?? nil
        spendableDuffs = balance?.spendable ?? 0
        shieldedBalanceCredits = PlatformAddressSyncCoordinator.shared.shieldedBalance
        switch phase {
        case .ready, .needsFunds:
            phase = spendableDuffs >= Self.feeFloorDuffs ? .ready : .needsFunds
        case .waitingForFunds where spendableDuffs >= Self.feeFloorDuffs:
            phase = .ready
            balancePollTask?.cancel()
        default:
            break
        }
    }

    /// Restore the waiting state for a persisted pending unban (funds may
    /// still be in the withdrawal queue) — unless they already arrived.
    func resumePendingIfAny() {
        guard PendingMasternodeUnbanStore.shared.pending(forProTxHash: record.proTxHash) != nil else {
            refreshFunding()
            return
        }
        refreshFunding()
        if phase == .needsFunds {
            phase = .waitingForFunds
            startBalancePolling()
        }
    }

    // MARK: Top-up (D3: guided, resumable)

    /// Withdraw the buffer from the shielded pool to the wallet's own
    /// receive address and wait for the L1 payout. The intent is persisted
    /// first so a relaunch mid-queue resumes at "Complete unban".
    func topUpFromShielded() async {
        errorText = nil
        phase = .toppingUp
        persistPending()

        await topUpCoordinator.performWithdraw(amountCredits: Self.topUpCredits)

        switch topUpCoordinator.phase {
        case .success, .submittedUnconfirmed:
            // `.submittedUnconfirmed` is non-retryable but the payout can
            // still arrive — same waiting posture, the poller decides.
            phase = .waitingForFunds
            startBalancePolling()
        case .failed(let message):
            PendingMasternodeUnbanStore.shared.clear(forProTxHash: record.proTxHash)
            errorText = message
            phase = .needsFunds
        default:
            // Cancelled auth leaves the coordinator idle.
            PendingMasternodeUnbanStore.shared.clear(forProTxHash: record.proTxHash)
            phase = .needsFunds
        }
    }

    /// Polls until the top-up lands (the ViewModel deallocating ends the
    /// task at its next tick via the weak capture — no deinit needed).
    private func startBalancePolling() {
        balancePollTask?.cancel()
        balancePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.refreshFunding()
                if self.phase != .waitingForFunds { return }
            }
        }
    }

    private func persistPending() {
        PendingMasternodeUnbanStore.shared.record(PendingMasternodeUnban(
            proTxHashHex: record.proTxHash.map { String(format: "%02x", $0) }.joined(),
            platformP2PPort: isEvonode ? p2pPort : nil,
            operatorPayoutAddress: payoutAddressRequired
                ? payoutAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            createdAt: Date()))
    }

    // MARK: Submit

    /// Authenticate and broadcast the ProUpServTx. On success the node
    /// returns to the valid list within a few blocks — the DML refresh flips
    /// the status badge.
    func submit() async {
        guard canSubmit else { return }
        guard let manager = SwiftDashSDKHost.shared.manager,
              let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            errorText = NSLocalizedString("Wallet is not ready. Try again in a moment.", comment: "Masternode unban")
            return
        }
        errorText = nil

        let outcome = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled)
        guard outcome == .ok else { return }

        let port = isEvonode ? p2pPort : nil
        let payout = payoutAddressRequired
            ? payoutAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        phase = .submitting
        do {
            let txid: Data
            switch keySource {
            case .wallet(let operatorKeyIndex):
                txid = try await manager.masternodeUpdateService(
                    walletId: walletId,
                    proTxHash: record.proTxHash,
                    operatorKeyIndex: operatorKeyIndex,
                    platformP2PPort: port,
                    operatorPayoutAddress: payout)
            case .tracked(let vault):
                guard let keyText = vault.key(for: record.proTxHash, role: .operator) else {
                    errorText = NSLocalizedString(
                        "The operator key is missing from the keychain — re-add it and try again.",
                        comment: "Masternode unban")
                    phase = .ready
                    return
                }
                txid = try await manager.trackedMasternodeUpdateService(
                    walletId: walletId,
                    proTxHash: record.proTxHash,
                    operatorKey: keyText,
                    platformP2PPort: port,
                    operatorPayoutAddress: payout)
            }
            PendingMasternodeUnbanStore.shared.clear(forProTxHash: record.proTxHash)
            let displayHex = txid.reversed().map { String(format: "%02x", $0) }.joined()
            phase = .submitted(txidHex: displayHex)
        } catch let error as PlatformWalletError {
            handleSubmitError(error)
        } catch {
            errorText = error.localizedDescription
            phase = .ready
        }
    }

    private func handleSubmitError(_ error: PlatformWalletError) {
        switch error {
        case .transactionBroadcastUnconfirmed:
            // Ambiguous outcome: the transaction may be on the network, so a
            // retry risks paying twice. Terminal — the DML refresh tells.
            PendingMasternodeUnbanStore.shared.clear(forProTxHash: record.proTxHash)
            errorText = NSLocalizedString(
                "The unban was sent but its result couldn't be confirmed. Don't retry — check the masternode's status again in a few minutes.",
                comment: "Masternode unban")
            terminal = true
            phase = .ready
        case .masternodeListUnavailable:
            errorText = NSLocalizedString(
                "The masternode list hasn't synced yet. Wait for sync to finish and try again.",
                comment: "Masternode unban")
            phase = .ready
        case .invalidParameter(let message) where message.contains("operator reward"):
            // D2: the node pays an operator reward, so the payout address
            // must be confirmed explicitly. Reveal the field; the Rust
            // message carries the reward percentage.
            payoutAddressRequired = true
            errorText = message
            phase = .ready
        case .invalidParameter(let message) where message.contains("extended network info"):
            // v3 extended entries can't be re-asserted by a v2 payload —
            // fail closed rather than downgrade the node's endpoint map.
            errorText = NSLocalizedString(
                "This masternode uses extended (v3) network info, which this wallet can't re-assert yet. Unban it with dash-cli instead.",
                comment: "Masternode unban")
            terminal = true
            phase = .ready
        default:
            errorText = error.errorDescription
            phase = .ready
        }
    }
}
