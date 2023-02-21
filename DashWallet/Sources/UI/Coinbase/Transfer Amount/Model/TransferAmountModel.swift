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

import Combine
import Foundation

// MARK: - TransferAmountModelDelegate

protocol TransferAmountModelDelegate: CoinbaseTransactionDelegate {
    func coinbaseUserDidChange()

    func initiatePayment(with input: DWPaymentInput)
}

// MARK: - TransferAmountModel


final class TransferAmountModel: CoinbaseAmountModel, CoinbaseTransactionSendable {
    enum TransferDirection {
        case toWallet
        case toCoinbase
    }

    weak var delegate: TransferAmountModelDelegate? {
        didSet {
            transactionDelegate = delegate
        }
    }

    weak var transactionDelegate: CoinbaseTransactionDelegate?

    public var address: String!
    public var direction: TransferDirection = .toWallet

    internal var amountToTransfer: UInt64 { amount.plainAmount }

    private var userDidChangeListenerHandle: UserDidChangeListenerHandle!

    override var isAllowedToContinue: Bool {
        if direction == .toCoinbase {
            return super.isAllowedToContinue
        } else {
            return isAmountValidForProceeding && !canShowInsufficientFunds
        }
    }

    override var canShowInsufficientFunds: Bool {
        if direction == .toCoinbase {
            return super.canShowInsufficientFunds
        } else {
            return amountToTransfer > (Coinbase.shared.lastKnownBalance ?? 0)
        }
    }

    override init() {
        super.init()

        userDidChangeListenerHandle = Coinbase.shared.addUserDidChangeListener { [weak self] user in
            if user != nil {
                self?.delegate?.coinbaseUserDidChange()
            }
        }
    }

    override func selectAllFundsWithoutAuth() {
        if direction == .toCoinbase {
            super.selectAllFundsWithoutAuth()
        } else {
            guard let balance = Coinbase.shared.lastKnownBalance else { return }

            let maxAmount = AmountObject(plainAmount: balance,
                                         fiatCurrencyCode: localCurrencyCode,
                                         localFormatter: localFormatter, currencyExchanger: currencyExchanger)
            updateCurrentAmountObject(with: maxAmount)
        }
    }

    func initializeTransfer() {
        if direction == .toCoinbase {
            transferToCoinbase()
        } else {
            transferFromCoinbase()
        }
    }

    private func transferToCoinbase() {
        // TODO: validate
        let amount = amount.plainAmount

        obtainNewAddress { [weak self] address in
            guard let address else {
                self?.delegate?.transferFromCoinbaseToWalletDidFail(with: .transactionFailed(.failedToObtainNewAddress))
                return
            }

            guard let paymentInput = DWPaymentInputBuilder().pay(toAddress: address, amount: amount) else {
                return
            }

            self?.delegate?.initiatePayment(with: paymentInput)
        }
    }

    private func obtainNewAddress(completion: @escaping ((String?) -> Void)) {
        Task {
            do {
                let address = try await Coinbase.shared.createNewCoinbaseDashAddress()
                self.address = address
                await MainActor.run {
                    completion(address)
                }
            } catch let error {
                await MainActor.run {
                    self.delegate?.transferFromCoinbaseToWalletDidFail(with: error as! Coinbase.Error)
                }
            }
        }
    }

    deinit {
        Coinbase.shared.removeUserDidChangeListener(handle: userDidChangeListenerHandle)
    }
}

// MARK: ConverterViewDataSource

extension TransferAmountModel: ConverterViewDataSource {
    var fromItem: SourceViewDataProvider? {
        direction == .toCoinbase
            ? ConverterViewSourceItem.dash(balanceFormatted: walletBalanceFormatted,
                                           fiatBalanceFormatted: fiatWalletBalanceFormatted)
            : ConverterViewSourceItem(image: .asset("Coinbase"),
                                      title: "Coinbase",
                                      balanceFormatted: Coinbase.shared.dashAccount?.info.balanceFormatted ?? "",
                                      fiatBalanceFormatted: Coinbase.shared.dashAccount?.info.fiatBalanceFormatted ?? "")
    }

    var toItem: SourceViewDataProvider? {
        direction == .toWallet
            ? ConverterViewSourceItem.dash()
            : ConverterViewSourceItem(image: .asset("Coinbase"),
                                      title: "Coinbase",
                                      balanceFormatted: "",
                                      fiatBalanceFormatted: "")
    }

    var coinbaseBalanceFormatted: String {
        guard let balance = Coinbase.shared.lastKnownBalance else {
            return NSLocalizedString("Unknown Balance", comment: "Coinbase")
        }

        return balance.formattedDashAmount
    }
}
