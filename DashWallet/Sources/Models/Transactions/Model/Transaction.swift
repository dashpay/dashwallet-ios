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

// MARK: - Transaction

struct Transaction: TransactionDataItem {
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

    let tx: DSTransaction
    var direction: DSTransactionDirection

    var outputReceiveAddresses: [String]
    var inputSendAddresses: [String]
    var specialInfoAddresses: [String: Int]?
    var dashAmount: UInt64

    var fiatAmount: String {
        (try? CurrencyExchanger.shared.convertDash(amount: dashAmount.dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }

    var transactionType: `Type`
    var state: State!
    var date: Date
    var shortDateString: String

    var stateTitle: String {
        switch transactionType {
        case .classic:
            switch direction {
            case .sent:
                if state == .processing {
                    return NSLocalizedString("Sending", comment: "")
                }
                else {
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
        tx = transaction

        let chain = DWEnvironment.sharedInstance().currentChain
        let currentAccount = DWEnvironment.sharedInstance().currentAccount;
        let account = transaction.accounts.contains(where: { ($0 as! DSAccount) == currentAccount }) ? currentAccount : nil

        dashAmount = transaction.dashAmount
        direction = transaction.direction
        outputReceiveAddresses = transaction.outputReceiveAddresses
        specialInfoAddresses = transaction.specialInfoAddresses
        transactionType = transaction.type
        date = transaction.date

        if transaction is DSCoinbaseTransaction {
            // Don't show input addresses for coinbase
            inputSendAddresses = []
        } else {
            inputSendAddresses = Array(Set(transaction.inputAddresses.compactMap { $0 as? String }))
        }

        let blockHeight = chain.lastTerminalBlockHeight
        let instantSendReceived = transaction.instantSendReceived
        let processingInstantSend = transaction.hasUnverifiedInstantSendLock
        let confirmed = transaction.confirmed
        let confirms = (transaction.blockHeight > blockHeight) ? 0 : (blockHeight - transaction.blockHeight) + 1

        if (direction == .sent || direction == .moved) &&
            confirms == 0 &&
            !account!.transactionIsValid(transaction) {
            state = .invalid
        } else if direction == .received {
            if !instantSendReceived && confirms == 0 && account!.transactionIsPending(transaction) {
                // should be very hard to get here, a miner would have to include a non standard transaction into a block
                state = .locked;
            } else if !instantSendReceived && confirms == 0 && !account!.transactionIsVerified(transaction) {
                state = .processing;
            }
            else if account!.transactionOutputsAreLocked(transaction) {
                state = .locked;
            }
            else if !instantSendReceived && !confirmed {
                let transactionAge = NSDate().timeIntervalSince1970 - transaction
                    .timestamp // we check the transaction age, as we might still be waiting on a transaction lock, 1 second seems like a good wait time
                if confirms == 0 && (processingInstantSend || transactionAge < 1.0) {
                    state = .processing
                } else {
                    state = .confirming
                }
            }
        }
        else if direction != .notAccountFunds {
            if !instantSendReceived && confirms == 0 && !account!.transactionIsVerified(transaction) {
                state = .processing;
            }
        }

        shortDateString = transaction.formattedShortTxDate
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

    var currentBlockHeight: UInt64 {
        let chain = DWEnvironment.sharedInstance().currentChain
        let lastHeight = chain.lastTerminalBlockHeight
        return UInt64(lastHeight)
    }

    var isCoinbaseTransaction: Bool {
        tx is DSCoinbaseTransaction
    }
}
