//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

// MARK: - CoinbaseTransactionDelegate

protocol CoinbaseTransactionDelegate: AnyObject {
    func transferFromCoinbaseToWalletDidFail(with error: Coinbase.Error)
    func transferFromCoinbaseToWalletDidFail(with reason: Coinbase.Error.TransactionFailureReason)
    func transferFromCoinbaseToWalletDidSucceed()
    func transferFromCoinbaseToWalletDidCancel()
}

// MARK: - CoinbaseTransactionSendable

protocol CoinbaseTransactionSendable {
    var plainAmount: UInt64 { get }
    var transactionDelegate: CoinbaseTransactionDelegate? { get }

    func transferFromCoinbase()
    func continueTransferFromCoinbase(with verificationCode: String)
}

extension CoinbaseTransactionSendable {
    func cancelTransferOperation() {
        transactionDelegate?.transferFromCoinbaseToWalletDidCancel()
    }

    func transferFromCoinbase() {
        let amount = plainAmount

        Task {
            try await transferFromCoinbase(amount: amount, with: nil)
        }
    }

    func continueTransferFromCoinbase(with verificationCode: String) {
        let amount = plainAmount

        Task {
            try await transferFromCoinbase(amount: amount, with: verificationCode)
        }
    }

    func transferFromCoinbase(amount: UInt64, with verificationCode: String?) async throws {
        do {
            let tx = try await Coinbase.shared.transferFromCoinbaseToDashWallet(verificationCode: verificationCode, amount: amount)
            await MainActor.run {
                self.transactionDelegate?.transferFromCoinbaseToWalletDidSucceed()
            }
        } catch Coinbase.Error.transactionFailed(let r) {
            await MainActor.run {
                self.transactionDelegate?.transferFromCoinbaseToWalletDidFail(with: r)
            }
        } catch {
            await MainActor.run {
                self.transactionDelegate?.transferFromCoinbaseToWalletDidFail(with: error as! Coinbase.Error)
            }
        }
    }
}

