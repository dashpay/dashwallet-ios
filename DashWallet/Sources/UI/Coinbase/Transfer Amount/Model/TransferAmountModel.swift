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

protocol TransferAmountModelDelegate: AnyObject {
    func initiatePayment(with input: DWPaymentInput)

    func transferFromCoinbaseToWalletDidFail(with reason: TransferFromCoinbaseFailureReason)
    func transferFromCoinbaseToWalletDidSucceed()
}

// MARK: - TransferFromCoinbaseFailureReason

enum TransferFromCoinbaseFailureReason {
    case twoFactorRequired
    case invalidVerificationCode
    case unknown
}

// MARK: - TransferAmountModel

final class TransferAmountModel: SendAmountModel {
    enum TransferDirection {
        case toWallet
        case toCoinbase
    }

    public weak var delegate: TransferAmountModelDelegate?

    private var cancellables: Set<AnyCancellable> = []

    public var address: String!
    public var direction: TransferDirection = .toCoinbase

    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var networkStatus: NetworkStatus!

    private var reachability: DSReachabilityManager { DSReachabilityManager.shared() }
    private var reachabilityObserver: Any!

    override init() {
        super.init()

        initializeReachibility()
    }

    override func selectAllFunds(_ preparationHandler: () -> Void) {
        if direction == .toCoinbase {
            super.selectAllFunds(preparationHandler)
        } else {
            guard let balance = Coinbase.shared.lastKnownBalance else { return }

            let maxAmount = AmountObject(plainAmount: Int64(balance), fiatCurrencyCode: localCurrencyCode,
                                         localFormatter: localFormatter)
            updateCurrentAmountObject(with: maxAmount)
        }
    }

    func initializeTransfer() {
        if direction == .toCoinbase {
            transferToCoinbase()
        } else {
            transferToWallet()
        }
    }

    func continueTransferFromCoinbase(with verificationCode: String) {
        transferToWallet(with: verificationCode)
    }

    private func transferToCoinbase() {
        // TODO: validate
        let amount = UInt64(amount.plainAmount)

        obtainNewAddress { [weak self] address in
            guard let address else {
                self?.delegate?.transferFromCoinbaseToWalletDidFail(with: .unknown)
                return
            }

            guard let paymentInput = DWPaymentInputBuilder().pay(toAddress: address, amount: amount) else {
                return
            }

            self?.delegate?.initiatePayment(with: paymentInput)
        }
    }

    private func transferToWallet(with verificationCode: String? = nil) {
        guard let address = DWEnvironment.sharedInstance().currentAccount.receiveAddress else { return }

        let amount = amount.amountInternalRepresentation
        Task {
            do {
                let _ = try await Coinbase.shared.transferFromCoinbaseToDashWallet(verificationCode: verificationCode,
                                                                                   coinAmountInDash: amount,
                                                                                   dashWalletAddress: address)
                await MainActor.run {
                    self.delegate?.transferFromCoinbaseToWalletDidSucceed()
                }
            } catch HTTPClientError.statusCode(let response) {
                await MainActor.run {
                    switch response.statusCode {
                    case 402:
                        self.delegate?.transferFromCoinbaseToWalletDidFail(with: .twoFactorRequired)
                    case 400:
                        self.delegate?.transferFromCoinbaseToWalletDidFail(with: .invalidVerificationCode)
                    default:
                        self.delegate?.transferFromCoinbaseToWalletDidFail(with: .unknown)
                    }
                }
            } catch {
                await MainActor.run {
                    self.delegate?.transferFromCoinbaseToWalletDidFail(with: .unknown)
                }
            }
        }
    }

    private func obtainNewAddress(completion: @escaping ((String?) -> Void)) {
        Task {
            let address = try await Coinbase.shared.createNewCoinbaseDashAddress()
            self.address = address
            completion(address)
        }
    }
}

extension TransferAmountModel {
    private func initializeReachibility() {
        if !reachability.isMonitoring {
            reachability.startMonitoring()
        }

        reachabilityObserver = NotificationCenter.default
            .addObserver(forName: NSNotification.Name(rawValue: "org.dash.networking.reachability.change"),
                         object: nil,
                         queue: nil,
                         using: { [weak self] _ in
                             self?.updateNetworkStatus()
                         })

        updateNetworkStatus()
    }

    private func updateNetworkStatus() {
        networkStatus = reachability.networkStatus
        networkStatusDidChange?(networkStatus)
    }
}

