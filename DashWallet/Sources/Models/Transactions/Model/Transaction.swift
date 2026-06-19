//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import SwiftDashSDK

let kConfirmationThreshold = Double(30 * 60)

// MARK: - Transaction

class Transaction: TransactionDataItem, Identifiable {
    enum State {
        case ok
        case invalid
        case locked
        case processing
        case confirming
    }

    enum `Type`: UInt {
        case classic
        case reward
        case masternodeRegistration
        case masternodeUpdate
        case masternodeRevoke
        case blockchainIdentityRegistration
    }

    /// Internal source discriminator. The `.ds` case is the existing rich
    /// path (used by other consumers like CrowdNode, TaxReport that still
    /// read from DashSync). The `.sdk` case is the new path for the home
    /// screen tx list sourced from SwiftDashSDK (function #6).
    ///
    /// The `.sdk` case carries an immutable `SDKSnapshot` value — NOT the live
    /// `PersistentTransaction` @Model. A `Transaction` wrapper is held by the
    /// home tx list across the wallet runtime's stop/start (e.g. an SPV
    /// restart), which tears down the `ModelContainer` and resets its context;
    /// reading any model property afterwards traps ("instance was destroyed by
    /// calling ModelContext.reset"). Snapshotting every UI-read field at wrap
    /// time — on the main actor, while the model is alive — makes the wrapper
    /// immune to that teardown.
    private enum Source {
        case ds(DSTransaction)
        case sdk(SDKSnapshot)
    }

    /// Frozen copy of the `PersistentTransaction` fields the UI reads, captured
    /// once at wrap time. Holding values (not the SwiftData model) is what keeps
    /// a `Transaction` valid after the model's context is reset/rebuilt.
    private struct SDKSnapshot {
        let txid: Data
        /// FFI direction encoding: 0=incoming, 1=outgoing, 2=internal, 3=coinjoin.
        let direction: UInt32
        let netAmount: Int64
        let fee: UInt64?
        /// 0=mempool, 1=instantSend, 2=inBlock, 3=chainLocked.
        let context: UInt32
        /// Owned output addresses (non-empty), pre-deduped.
        let outputAddresses: [String]
        /// Spent-input addresses (non-empty), pre-deduped.
        let inputAddresses: [String]

        /// Must be called on the main actor — reads `p`'s relationships
        /// (`outputs`/`inputs`), which are bound to the model-context actor.
        init(_ p: PersistentTransaction) {
            txid = p.txid
            direction = p.direction
            netAmount = p.netAmount
            fee = p.fee
            context = p.context
            outputAddresses = Array(Set(p.outputs.map { $0.address }.filter { !$0.isEmpty }))
            inputAddresses = Array(Set(p.inputs.map { $0.address }.filter { !$0.isEmpty }))
        }
    }

    private let source: Source

    /// The underlying DashSync transaction, if available. Returns nil for
    /// SDK-sourced transactions. Used by code paths that still depend on
    /// rich `DSTransaction` properties (CrowdNode matchers, CoinJoin
    /// grouping, TaxReportGenerator, send-flow code).
    var tx: DSTransaction? {
        if case .ds(let dsTx) = source { return dsTx }
        return nil
    }

    /// CoinJoin "mixing operation" flag for SwiftDashSDK-sourced txs — drives
    /// grouping into the single "Mixing Transactions" home-screen row.
    ///
    /// Computed and cached on the MAIN actor at wrap time
    /// (`SwiftDashSDKWalletSource.fetchAndWrapOnMain`), because deciding
    /// membership traverses SwiftData relationships (outputs → coreAddress →
    /// account) that are bound to the model-context actor and must not be read
    /// from the background grouping queue. Defaults to false; the home tx source
    /// is the sole producer of `.sdk` wrappers and always populates it.
    /// DS-sourced txs use the legacy `DSCoinJoinWrapper` path, so this stays
    /// false for them.
    var sdkCoinJoinMixing: Bool = false

    /// True only for SwiftDashSDK-sourced CoinJoin mixing transactions. The flag
    /// is computed via CoinJoin-account *role* (a tx that deposits into the
    /// CoinJoin account, or spends a fee/collateral from it without depositing
    /// to a Standard account — see `SwiftDashSDKWalletSource.isCoinJoinMixingTx`),
    /// NOT just the SDK's structural `typedKind`, which only tags the mixing
    /// *rounds* and misses create-denomination / collateral / mixing-fee txs.
    var isCoinJoinMixing: Bool {
        if case .sdk = source { return sdkCoinJoinMixing }
        return false
    }

    /// Raw signed wallet net change (duffs) for SDK-sourced txs; nil for DS.
    /// Used to total a CoinJoin mixing group's cost: summing this across the
    /// group yields the net wallet change (mixing rounds net ~0; denomination /
    /// fee txs net `-fee`), i.e. the total mixing fee paid (negative).
    var sdkNetAmount: Int64? {
        if case .sdk(let snap) = source { return snap.netAmount }
        return nil
    }

    /// True when this tx is the app's CoinJoin offload (sweep) tx — tagged on
    /// sweep success in `CoinJoinWithdrawalStore`. Drives grouping into the
    /// single "CoinJoin Withdrawals" home cell. Source-agnostic txid lookup
    /// (cheap, thread-safe, no SwiftData traversal — unlike `isCoinJoinMixing`).
    var isCoinJoinWithdrawal: Bool {
        CoinJoinWithdrawalStore.shared.contains(txHashData)
    }

    var id: String {
        switch source {
        case .ds(let dsTx): return dsTx.txHashHexString
        case .sdk(let snap): return Self.internalHex(snap.txid)
        }
    }

    var direction: DSTransactionDirection { _direction }
    private lazy var _direction: DSTransactionDirection = {
        switch source {
        case .ds(let dsTx): return dsTx.direction
        case .sdk(let snap):
            // FFI direction encoding: 0=incoming, 1=outgoing, 2=internal,
            // 3=coinjoin. Promote outgoing→moved when the wallet's net
            // change equals just the fee (self-send) — mirrors DashSync's
            // `received + fee == sent` check so the legacy code path that
            // still relies on `.moved` (e.g. CrowdNode top-up matcher,
            // "Internal Transfer" labelling) keeps working uniformly.
            switch snap.direction {
            case 0: return .received
            case 2: return .moved
            case 3: return .sent
            case 1:
                let fee = Int64(snap.fee ?? 0)
                if fee > 0 && snap.netAmount == -fee {
                    return .moved
                }
                return .sent
            default:
                return snap.netAmount >= 0 ? .received : .sent
            }
        }
    }()

    var outputReceiveAddresses: [String] { _outputReceiveAddresses }
    private lazy var _outputReceiveAddresses: [String] = {
        switch source {
        case .ds(let dsTx): return dsTx.outputReceiveAddresses
        case .sdk(let snap):
            // Persistence only stores owned outputs (the FFI emits
            // `acc.utxos*` arrays — wallet UTXOs only — and external
            // recipient outputs aren't surfaced). For received txs that
            // matches DSTransaction's "addresses receiving in this tx"
            // semantics; for sent txs the external destination is
            // unrecoverable from the row alone.
            if direction == .received || direction == .moved {
                return snap.outputAddresses
            }
            return []
        }
    }()

    var inputSendAddresses: [String] { _inputSendAddresses }
    private lazy var _inputSendAddresses: [String] = {
        switch source {
        case .ds(let dsTx):
            if dsTx is DSCoinbaseTransaction {
                return []
            } else {
                return Array(Set(dsTx.inputAddresses.compactMap { $0 as? String }))
            }
        case .sdk(let snap):
            // Reachable only when the FFI links spent UTXOs back to the
            // spending tx. Today the spent-utxo notification carries only
            // the outpoint, so `inputs` is usually empty — fine, callers
            // already tolerate empty arrays.
            return snap.inputAddresses
        }
    }()

    var specialInfoAddresses: [String: Int]?

    /// Locked amount (duffs) when this L1 transaction is the funding tx of a
    /// "to Shielded" internal transfer — a Type-18 asset lock that tops up
    /// the private shielded balance. Sourced from the SDK's
    /// `PersistentAssetLock` store (funding type 5), NOT from DashSync:
    /// neither DashSync nor the SDK net-change view models the lock, so both
    /// report a self-directed move of 0. `nil` for every other transaction.
    ///
    /// Joined by the display-order txid (reversed `txHashData`) to match the
    /// txid component of `PersistentAssetLock.outPointHex`. Drives both the
    /// "Shielded transfer" label (`stateTitle`) and the on-screen amount
    /// (`_dashAmount`).
    private lazy var shieldedTransferAmountDuffs: UInt64? = {
        let displayTxid = txHashData.reversed().map { String(format: "%02x", $0) }.joined()
        return ShieldedTxLookup.shared.amountDuffs(forTxidHex: displayTxid)
    }()

    /// True when this is the funding tx of a "to Shielded" transfer.
    var isShieldedTransfer: Bool { shieldedTransferAmountDuffs != nil }

    private lazy var _dashAmount: UInt64 = {
        // A "to Shielded" transfer's L1 funding tx is a Type-18 asset lock;
        // surface the real locked amount the SDK recorded instead of the 0
        // the generic per-source logic below derives for a self-directed move.
        if let shielded = shieldedTransferAmountDuffs { return shielded }
        switch source {
        case .ds(let dsTx): return dsTx.dashAmount
        case .sdk(let snap):
            let fee = Int64(snap.fee ?? 0)
            switch direction {
            case .received:
                return snap.netAmount > 0 ? UInt64(snap.netAmount) : 0
            case .sent:
                // Gross amount paid to external recipients. For an
                // external send `netAmount = -(amount + fee)`, so the
                // user-visible amount = `-netAmount - fee`. abs(netAmount)
                // (the previous fallback) double-counted the fee and
                // collapsed self-sends to a fee-sized number on screen.
                return UInt64(max(0, -snap.netAmount - fee))
            case .moved:
                return 0
            case .notAccountFunds:
                return 0
            @unknown default:
                return UInt64(abs(snap.netAmount))
            }
        }
    }()

    var dashAmount: UInt64 { _dashAmount }
    var signedDashAmount: Int64 {
        if dashAmount == UInt64.max {
            return Int64.max
        }

        return direction == .sent ? -Int64(dashAmount) : Int64(dashAmount)
    }

    var fiatAmount: String {
        storedFiatAmount
    }

    var iconName: String {
        state == .invalid ? "tx.invalid.icon" : direction.iconName
    }

    private lazy var storedFiatAmount = userInfo?.fiatAmountString(from: _dashAmount) ?? NSLocalizedString("Not available", comment: "");

    lazy var userInfo: TransactionMetadata? = TransactionMetadataDAOImpl.shared.get(by: txHashData)

    var transactionType: `Type` { _transactionType }
    private lazy var _transactionType: `Type` = {
        switch source {
        case .ds(let dsTx): return dsTx.type
        // TODO(core-spv-neuter): WalletTransaction no longer exposes txType.
        case .sdk: return .classic
        }
    }()

    var state: State! { _state }
    private lazy var _state: State! = {
        switch source {
        case .ds(let dsTx):
            return computeStateFromDSTransaction(dsTx)
        case .sdk(let snap):
            // PersistentTransaction.context: 0=mempool, 1=instantSend,
            // 2=inBlock, 3=chainLocked. Anything past mempool counts as
            // "ok" — instant-send is a strong-enough confirmation for
            // home-screen UX (matches the legacy DSTransaction codepath
            // which exits `.processing` once `instantSendReceived` flips).
            return snap.context == 0 ? .processing : .ok
        }
    }()

    private func computeStateFromDSTransaction(_ dsTx: DSTransaction) -> State {
        if dsTx is DWTransactionStub {
            return .ok
        }

        let chain = DWEnvironment.sharedInstance().currentChain
        let currentAccount = DWEnvironment.sharedInstance().currentAccount
        let account = dsTx.accounts.contains(where: { ($0 as! DSAccount) == currentAccount }) ? currentAccount : nil
        if account == nil {
            return .invalid
        }

        let blockHeight = chain.lastTerminalBlockHeight
        let instantSendReceived = dsTx.instantSendReceived
        let processingInstantSend = dsTx.hasUnverifiedInstantSendLock
        let confirmed = dsTx.confirmed
        let confirms = (dsTx.blockHeight > blockHeight) ? 0 : (blockHeight - dsTx.blockHeight) + 1

        if (direction == .sent || direction == .moved)
            && confirms == 0
            && !account!.transactionIsValid(dsTx) {
            return .invalid
        } else if direction == .received {
            if !instantSendReceived && confirms == 0 && isPending(account, dsTx) {
                return .locked
            } else if !instantSendReceived && confirms == 0 && !isVerified(account, dsTx) {
                return .processing
            } else if outputsAreLocked(account, dsTx) {
                return .locked
            } else if !instantSendReceived && !confirmed {
                let transactionAge = NSDate().timeIntervalSince1970 - dsTx
                    .timestamp
                if confirms == 0 && (processingInstantSend || transactionAge < 1.0) {
                    return .processing
                } else {
                    return .confirming
                }
            }
        } else if direction == .notAccountFunds || instantSendReceived || confirms > 0 {
            return .ok
        }

        return isVerified(account, dsTx) ? .ok : .processing
    }

    private func outputsAreLocked(_ account: DSAccount?, _ tx: DSTransaction) -> Bool {
        return account!.transactionOutputsAreLocked(tx)
    }

    private func isPending(_ account: DSAccount?, _ tx: DSTransaction) -> Bool {
        if tx.timestamp + kConfirmationThreshold < Date().timeIntervalSince1970 {
            return false
        }

        return account!.transactionIsPending(tx)
    }

    private func isVerified(_ account: DSAccount?, _ tx: DSTransaction) -> Bool {
        if tx.timestamp + kConfirmationThreshold < Date().timeIntervalSince1970 {
            return true
        }

        return account!.transactionIsVerified(tx)
    }

    private static func internalHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private lazy var _shortDateString: String = {
        switch source {
        case .ds(let dsTx): return dsTx.formattedShortTxDate
        case .sdk: return DWDateFormatter.sharedInstance.shortStringFromDate(date)
        }
    }()

    var date: Date

    var shortDateString: String {
        _shortDateString
    }

    private lazy var _shortTimeString: String = {
        switch source {
        case .ds(let dsTx): return dsTx.formattedShortTxTime
        case .sdk: return DWDateFormatter.sharedInstance.timeOnly(from: date)
        }
    }()

    var shortTimeString: String {
        _shortTimeString
    }

    var stateTitle: String {
        // A "to Shielded" transfer surfaces as a Type-18 asset lock that the
        // generic logic would label "Internal Transfer"; relabel it from the
        // SDK-sourced shielded lookup (see `shieldedTransferAmountDuffs`).
        if isShieldedTransfer {
            return NSLocalizedString("Shielded transfer",
                                     comment: "Transfer of own funds into the private shielded balance")
        }
        switch transactionType {
        case .classic:
            switch direction {
            case .sent:
                if state == .processing {
                    return NSLocalizedString("Sending", comment: "")
                } else if state == .invalid {
                    return NSLocalizedString("Invalid", comment: "")
                } else {
                    return NSLocalizedString("Sent", comment: "")
                }
            case .received, .notAccountFunds:
                return NSLocalizedString("Received", comment: "")
            case .moved:
                return NSLocalizedString("Internal Transfer", comment:"Transaction within the wallet, transfer of own funds");
            default:
                fatalError()
            }
        case .reward:
            return NSLocalizedString("Reward", comment: "")
        case .masternodeRegistration:
            return NSLocalizedString("Masternode Registration", comment: "")
        case .masternodeUpdate:
            return NSLocalizedString("Masternode Update", comment: "")
        case .masternodeRevoke:
            return NSLocalizedString("Masternode Revocation", comment: "")
        case .blockchainIdentityRegistration:
            return NSLocalizedString("DashPay Upgrade Fee", comment: "")
        }
    }

    init(transaction: DSTransaction) {
        self.source = .ds(transaction)
        self.date = transaction.date
    }

    init(persistentTransaction p: PersistentTransaction) {
        // Freeze every UI-read field now, on the main actor where `p`'s model
        // context is alive. After this the wrapper never dereferences `p`
        // again, so it stays valid after a ModelContext reset (see SDKSnapshot).
        self.source = .sdk(SDKSnapshot(p))
        // PersistentTransaction.blockTimestamp is 0 until mined; firstSeen
        // is set when the tx is first observed (mempool entry). Use it as
        // the mempool fallback so the home screen doesn't group these
        // into a 1970 section. Re-evaluates on relaunch — acceptable for
        // typical mainnet confirmation latency.
        let ts: UInt64 = p.blockTimestamp == 0 ? p.firstSeen : UInt64(p.blockTimestamp)
        self.date = ts == 0
            ? Date()
            : Date(timeIntervalSince1970: TimeInterval(ts))
    }
}

extension Transaction {
    var feeUsed: UInt64 {
        switch source {
        case .ds(let dsTx): return dsTx.feeUsed
        case .sdk(let snap): return snap.fee ?? 0
        }
    }

    var dashAmountTintColor: UIColor {
        direction.dashAmountTintColor
    }

    var txHashHexString: String {
        switch source {
        case .ds(let dsTx): return dsTx.txHashHexString
        case .sdk(let snap): return Self.internalHex(snap.txid)
        }
    }

    var txHashData: Data {
        switch source {
        case .ds(let dsTx): return dsTx.txHashData
        case .sdk(let snap): return snap.txid
        }
    }

    var isCoinbaseTransaction: Bool {
        switch source {
        case .ds(let dsTx): return dsTx is DSCoinbaseTransaction
        case .sdk: return false
        }
    }
}

extension Transaction: Hashable {
    // MARK: - Equatable
    static func == (lhs: Transaction, rhs: Transaction) -> Bool {
        return lhs.txHashData == rhs.txHashData
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(dashAmount)
        hasher.combine(direction)
        hasher.combine(transactionType)
        hasher.combine(date)
    }
}
