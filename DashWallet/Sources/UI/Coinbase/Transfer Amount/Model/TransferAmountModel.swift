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
    func coinbaseUserDidChange()

    func initiatePayment(with input: DWPaymentInput)

    func transferFromCoinbaseToWalletDidFail(with error: Error)
    func transferFromCoinbaseToWalletDidFail(with reason: TransferFromCoinbaseFailureReason)
    func transferFromCoinbaseToWalletDidSucceed()
    func transferFromCoinbaseToWalletDidCancel()
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

    private var userDidChangeListenerHandle: UserDidChangeListenerHandle!

    override init() {
        super.init()

        initializeReachibility()

        userDidChangeListenerHandle = Coinbase.shared.addUserDidChangeListener { [weak self] user in
            if let user {
                self?.delegate?.coinbaseUserDidChange()
            }
        }
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

    func cancelTransferOperation() {
        delegate?.transferFromCoinbaseToWalletDidCancel()
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
        DSLogger.log("Tranfer from coinbase: transferToWallet \(amount) \(address)")
        Task {
            do {
                let _ = try await Coinbase.shared.transferFromCoinbaseToDashWallet(verificationCode: verificationCode,
                                                                                   coinAmountInDash: amount,
                                                                                   dashWalletAddress: address)
                DSLogger.log("Tranfer from coinbase: transferToWallet - success")
                await MainActor.run {
                    self.delegate?.transferFromCoinbaseToWalletDidSucceed()
                }
            } catch HTTPClientError.statusCode(let r) where r.statusCode == 402 {
                DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 402")
                await MainActor.run {
                    self.delegate?.transferFromCoinbaseToWalletDidFail(with: .twoFactorRequired)
                }
            } catch HTTPClientError.statusCode(let r) where r.statusCode == 400 {
                DSLogger.log("Tranfer from coinbase: transferToWallet - failure - statusCode - 400")
                await MainActor.run {
                    self.delegate?.transferFromCoinbaseToWalletDidFail(with: .invalidVerificationCode)
                }
            } catch {
                DSLogger.log("Tranfer from coinbase: transferToWallet - failure - \(error) - \(error.localizedDescription)")
                await MainActor.run {
                    self.delegate?.transferFromCoinbaseToWalletDidFail(with: error)
                }
            }
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
                    self.delegate?.transferFromCoinbaseToWalletDidFail(with: error)
                }
            }
        }
    }

    deinit {
        Coinbase.shared.removeUserDidChangeListener(handle: userDidChangeListenerHandle)
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

