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
    /// screen tx list sourced from SwiftDashSDK (function #6) — backed
    /// directly by the SwiftData row so the input/output graph and
    /// FFI-supplied direction are reachable without a lossy adapter.
    private enum Source {
        case ds(DSTransaction)
        case sdk(PersistentTransaction)
    }

    private let source: Source

    /// True for transactions sourced from SwiftDashSDK only. The tx detail
    /// screen shows reduced information for these — input/output addresses,
    /// instant-send flags, and account-validity state are not available
    /// from `WalletTransaction` yet.
    var isMinimal: Bool {
        if case .sdk = source { return true }
        return false
    }

    /// The underlying DashSync transaction, if available. Returns nil for
    /// SDK-sourced transactions. Used by code paths that still depend on
    /// rich `DSTransaction` properties (CrowdNode matchers, CoinJoin
    /// grouping, TaxReportGenerator, send-flow code).
    var tx: DSTransaction? {
        if case .ds(let dsTx) = source { return dsTx }
        return nil
    }

    var id: String {
        switch source {
        case .ds(let dsTx): return dsTx.txHashHexString
        case .sdk(let p): return Self.internalHex(p.txid)
        }
    }

    var direction: DSTransactionDirection { _direction }
    private lazy var _direction: DSTransactionDirection = {
        switch source {
        case .ds(let dsTx): return dsTx.direction
        case .sdk(let p):
            // FFI direction encoding: 0=incoming, 1=outgoing, 2=internal,
            // 3=coinjoin. Promote outgoing→moved when the wallet's net
            // change equals just the fee (self-send) — mirrors DashSync's
            // `received + fee == sent` check so the legacy code path that
            // still relies on `.moved` (e.g. CrowdNode top-up matcher,
            // "Internal Transfer" labelling) keeps working uniformly.
            switch p.direction {
            case 0: return .received
            case 2: return .moved
            case 3: return .sent
            case 1:
                let fee = Int64(p.fee ?? 0)
                if fee > 0 && p.netAmount == -fee {
                    return .moved
                }
                return .sent
            default:
                return p.netAmount >= 0 ? .received : .sent
            }
        }
    }()

    var outputReceiveAddresses: [String] { _outputReceiveAddresses }
    private lazy var _outputReceiveAddresses: [String] = {
        switch source {
        case .ds(let dsTx): return dsTx.outputReceiveAddresses
        case .sdk(let p):
            // Persistence only stores owned outputs (the FFI emits
            // `acc.utxos*` arrays — wallet UTXOs only — and external
            // recipient outputs aren't surfaced). For received txs that
            // matches DSTransaction's "addresses receiving in this tx"
            // semantics; for sent txs the external destination is
            // unrecoverable from the row alone.
            if direction == .received || direction == .moved {
                return Array(Set(p.outputs.map { $0.address }.filter { !$0.isEmpty }))
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
        case .sdk(let p):
            // Reachable only when the FFI links spent UTXOs back to the
            // spending tx. Today the spent-utxo notification carries only
            // the outpoint, so `inputs` is usually empty — fine, callers
            // already tolerate empty arrays.
            return Array(Set(p.inputs.map { $0.address }.filter { !$0.isEmpty }))
        }
    }()

    var specialInfoAddresses: [String: Int]?

    private lazy var _dashAmount: UInt64 = {
        switch source {
        case .ds(let dsTx): return dsTx.dashAmount
        case .sdk(let p):
            let fee = Int64(p.fee ?? 0)
            switch direction {
            case .received:
                return p.netAmount > 0 ? UInt64(p.netAmount) : 0
            case .sent:
                // Gross amount paid to external recipients. For an
                // external send `netAmount = -(amount + fee)`, so the
                // user-visible amount = `-netAmount - fee`. abs(netAmount)
                // (the previous fallback) double-counted the fee and
                // collapsed self-sends to a fee-sized number on screen.
                return UInt64(max(0, -p.netAmount - fee))
            case .moved:
                return 0
            case .notAccountFunds:
                return 0
            @unknown default:
                return UInt64(abs(p.netAmount))
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
        case .sdk(let p):
            // PersistentTransaction.context: 0=mempool, 1=instantSend,
            // 2=inBlock, 3=chainLocked. Anything past mempool counts as
            // "ok" — instant-send is a strong-enough confirmation for
            // home-screen UX (matches the legacy DSTransaction codepath
            // which exits `.processing` once `instantSendReceived` flips).
            return p.context == 0 ? .processing : .ok
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
        self.source = .sdk(p)
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
        case .sdk(let p): return p.fee ?? 0
        }
    }

    var dashAmountTintColor: UIColor {
        direction.dashAmountTintColor
    }

    var txHashHexString: String {
        switch source {
        case .ds(let dsTx): return dsTx.txHashHexString
        case .sdk(let p): return Self.internalHex(p.txid)
        }
    }

    var txHashData: Data {
        switch source {
        case .ds(let dsTx): return dsTx.txHashData
        case .sdk(let p): return p.txid
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
