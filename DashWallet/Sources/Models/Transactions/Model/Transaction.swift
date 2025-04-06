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
        case assetLock
        case assetUnlock
    }
    
    var id: String {
        tx.txHashHexString
    }

    let tx: DSTransaction
    var direction: DSTransactionDirection { _direction }
    private lazy var _direction: DSTransactionDirection = tx.direction

    var outputReceiveAddresses: [String] { _outputReceiveAddresses }
    private lazy var _outputReceiveAddresses: [String] = tx.outputReceiveAddresses

    var inputSendAddresses: [String] { _inputSendAddresses }
    private lazy var _inputSendAddresses: [String] = {
        if tx is DSCoinbaseTransaction {
            // Don't show input addresses for coinbase
            return []
        } else {
            return Array(Set(tx.inputAddresses.compactMap { $0 as? String }))
        }
    }()

    var specialInfoAddresses: [String: Int]?

    private lazy var _dashAmount: UInt64 = tx.dashAmount
    
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

    lazy var userInfo: TxUserInfo? = TxUserInfoDAOImpl.shared.get(by: tx.txHashData)

    var transactionType: `Type` { _transactionType }
    private lazy var _transactionType: `Type` = tx.type

    var state: State! { _state }
    private lazy var _state: State! = {
        if tx is DWTransactionStub {
            return .ok
        }
        
        let chain = DWEnvironment.sharedInstance().currentChain
        let currentAccount = DWEnvironment.sharedInstance().currentAccount
        let account = tx.accounts.contains(where: { ($0 as! DSAccount) == currentAccount }) ? currentAccount : nil
        if account == nil {
            return .invalid
        }
        
        let blockHeight = chain.lastTerminalBlockHeight
        let instantSendReceived = tx.instantSendReceived
        let processingInstantSend = tx.hasUnverifiedInstantSendLock
        let confirmed = tx.confirmed
        let confirms = (tx.blockHeight > blockHeight) ? 0 : (blockHeight - tx.blockHeight) + 1
        
        if (direction == .sent || direction == .moved)
            && confirms == 0
            && !account!.transactionIsValid(tx) {
            return .invalid
        } else if direction == .received {
            if !instantSendReceived && confirms == 0 && isPending(account, tx) {
                // should be very hard to get here, a miner would have to include a non standard transaction into a block
                return .locked
            } else if !instantSendReceived && confirms == 0 && !isVerified(account, tx) {
                return .processing
            } else if outputsAreLocked(account, tx) {
                return .locked
            } else if !instantSendReceived && !confirmed {
                let transactionAge = NSDate().timeIntervalSince1970 - tx
                    .timestamp // we check the transaction age, as we might still be waiting on a transaction lock, 1 second seems like a good wait time
                if confirms == 0 && (processingInstantSend || transactionAge < 1.0) {
                    return .processing
                } else {
                    return .confirming
                }
            }
        } else if direction == .notAccountFunds || instantSendReceived || confirms > 0 {
            return .ok
        }
        
        return isVerified(account, tx) ? .ok : .processing
    }()
    
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

    private lazy var _shortDateString: String = tx.formattedShortTxDate
    var date: Date
    var shortDateString: String {
        _shortDateString
    }
    
    private lazy var _shortTimeString: String = tx.formattedShortTxTime
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
        case .assetLock:
            return NSLocalizedString("DashPay Upgrade Fee", comment: "")
        case .assetUnlock:
            return NSLocalizedString("DashPay Upgrade Fee", comment: "")
        }
    }
    
    init(transaction: DSTransaction) {
        tx = transaction
        date = transaction.date
    }
}

extension Transaction {
    var feeUsed: UInt64 {
        tx.feeUsed
    }

    var dashAmountTintColor: UIColor {
        direction.dashAmountTintColor
    }

    var txHashHexString: String {
        tx.txHashHexString
    }

    var txHashData: Data {
        tx.txHashData
    }

    var isCoinbaseTransaction: Bool {
        tx is DSCoinbaseTransaction
    }
}

extension Transaction: Hashable {
    // MARK: - Equatable
    static func == (lhs: Transaction, rhs: Transaction) -> Bool {
        return lhs.tx.txHashData == rhs.tx.txHashData
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(dashAmount)
        hasher.combine(direction)
        hasher.combine(transactionType)
        hasher.combine(date)
    }
}
