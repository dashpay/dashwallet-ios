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
    private enum Source {
        case ds(DSTransaction)
        case sdk(WalletTransaction)
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
        case .sdk(let wtx): return wtx.txid
        }
    }

    var direction: DSTransactionDirection { _direction }
    private lazy var _direction: DSTransactionDirection = {
        switch source {
        case .ds(let dsTx): return dsTx.direction
        case .sdk(let wtx):
            // Use the FFI-provided direction (0=incoming, 1=outgoing, 2=internal, 3=coinJoin)
            switch wtx.direction {
            case 0: return .received
            case 1: return .sent
            case 2: return .moved
            case 3: return .sent  // CoinJoin mapped to sent
            default: return wtx.netAmount >= 0 ? .received : .sent
            }
        }
    }()

    var outputReceiveAddresses: [String] { _outputReceiveAddresses }
    private lazy var _outputReceiveAddresses: [String] = {
        switch source {
        case .ds(let dsTx): return dsTx.outputReceiveAddresses
        case .sdk(let wtx): return wtx.outputs.map { $0.address }.filter { !$0.isEmpty }
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
        case .sdk(let wtx):
            return Array(Set(wtx.inputs.map { $0.address }.filter { !$0.isEmpty }))
        }
    }()

    var specialInfoAddresses: [String: Int]?

    private lazy var _dashAmount: UInt64 = {
        switch source {
        case .ds(let dsTx): return dsTx.dashAmount
        case .sdk(let wtx): return UInt64(abs(wtx.netAmount))
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
        case .sdk(let wtx):
            switch wtx.txType {
            case 1: return .reward  // coinbase
            case 2: return .masternodeRegistration
            case 3: return .masternodeUpdate
            case 4: return .masternodeRevoke
            case 5: return .blockchainIdentityRegistration
            default: return .classic
            }
        }
    }()

    var state: State! { _state }
    private lazy var _state: State! = {
        switch source {
        case .ds(let dsTx):
            return computeStateFromDSTransaction(dsTx)
        case .sdk(let wtx):
            if wtx.instantSendLocked || wtx.height > 0 { return .ok }
            return .processing
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

    init(walletTransaction: WalletTransaction) {
        self.source = .sdk(walletTransaction)
        // `WalletTransaction.timestamp` is the block timestamp (0 until the
        // tx is mined). Fall back to `Date()` for mempool/pending txs so the
        // home screen doesn't group them into a 1970 section. Re-evaluates
        // on relaunch — acceptable for typical mainnet confirmation latency.
        self.date = walletTransaction.timestamp == 0
            ? Date()
            : Date(timeIntervalSince1970: TimeInterval(walletTransaction.timestamp))
    }
}

extension Transaction {
    var feeUsed: UInt64 {
        switch source {
        case .ds(let dsTx): return dsTx.feeUsed
        case .sdk(let wtx): return wtx.fee ?? 0
        }
    }

    var dashAmountTintColor: UIColor {
        direction.dashAmountTintColor
    }

    var txHashHexString: String {
        switch source {
        case .ds(let dsTx): return dsTx.txHashHexString
        case .sdk(let wtx): return wtx.txid
        }
    }

    var txHashData: Data {
        switch source {
        case .ds(let dsTx): return dsTx.txHashData
        case .sdk(let wtx):
            // WalletTransaction.txid is a hex string in internal byte order
            // (same as DSTransaction.txHashData). Convert directly.
            return Data(hexString: wtx.txid) ?? Data()
        }
    }

    var isCoinbaseTransaction: Bool {
        switch source {
        case .ds(let dsTx): return dsTx is DSCoinbaseTransaction
        case .sdk(let wtx): return wtx.txType == 1
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
