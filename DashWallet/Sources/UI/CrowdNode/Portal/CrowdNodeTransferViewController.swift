//
//  Created by Andrei Ashikhmin
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
import Combine

final class CrowdNodeTransferController: SendAmountViewController, NetworkReachabilityHandling {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()
    
    internal var mode: TransferDirection = .deposit
    
    /// Conform to NetworkReachabilityHandling
    internal var networkStatusDidChange: ((NetworkStatus) -> ())?
    internal var reachabilityObserver: Any!
    internal var depositWithdrawModel: DepositWithdrawModel {
        model as! DepositWithdrawModel
    }
    
    private var networkUnavailableView: UIView!
    private var fromLabel: FromLabel!
    
    override var amountInputStyle: AmountInputControl.Style { .oppositeAmount }
    
    static func controller(mode: TransferDirection) -> CrowdNodeTransferController {
        let vc = CrowdNodeTransferController()
        vc.mode = mode
        
        return vc
    }

    override var actionButtonTitle: String? {
        NSLocalizedString(mode.title, comment: "CrowdNode")
    }

    override func actionButtonAction(sender: UIView) {
        Task {
            showActivityIndicator()
            
            do {
                if mode == .deposit {
                    try await viewModel.deposit(amount: depositWithdrawModel.amount.plainAmount)
                } else {
                    // TODO: temporary action, does full withdrawal
                    try await viewModel.withdraw(permil: 1000)
                }
                
                hideActivityIndicator()
            } catch {
                // TODO: errors
                hideActivityIndicator()
            }
        }
    }

    override func initializeModel() {
        model = DepositWithdrawModel()
    }

    override func configureModel() {
        super.configureModel()
        
        model.inputsSwappedHandler = { [weak self] type in
            self?.updateBalanceLabel()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_background()
        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
        startNetworkMonitoring()
        configureObservers()
    }

    deinit {
        stopNetworkMonitoring()
        
    }
}

extension CrowdNodeTransferController {
    override func configureHierarchy() {
        super.configureHierarchy()
        
        configureTitleBar()
        fromLabel = FromLabel(icon: mode.imageName, text: mode.direction)
        contentView.addSubview(fromLabel)
        
        let keyboardHeader = KeyboardHeader(icon: mode.keyboardHeaderIcon, text: mode.keyboardHeader)
        keyboardHeader.translatesAutoresizingMaskIntoConstraints = false
        topKeyboardView = keyboardHeader

        networkUnavailableView = NetworkUnavailableView(frame: .zero)
        networkUnavailableView.translatesAutoresizingMaskIntoConstraints = false
        networkUnavailableView.isHidden = true
        contentView.addSubview(networkUnavailableView)

        NSLayoutConstraint.activate([
            fromLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            NSLayoutConstraint(item: fromLabel!, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 0.35, constant: 0),
            
            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            NSLayoutConstraint(item: amountView!, attribute: .top, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 0.47, constant: 0),
            
            networkUnavailableView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            networkUnavailableView.centerYAnchor.constraint(equalTo: numberKeyboard.centerYAnchor),
        ])
    }
    
    private func configureTitleBar() {
        let titleViewStackView = UIStackView()
        titleViewStackView.alignment = .center
        titleViewStackView.translatesAutoresizingMaskIntoConstraints = false
        titleViewStackView.axis = .vertical
        titleViewStackView.spacing = 1
        navigationItem.titleView = titleViewStackView

        let titleLabel = UILabel()
        titleLabel.font = .dw_mediumFont(ofSize: 16)
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.text = NSLocalizedString(mode.title, comment: "CrowdNode")
        titleViewStackView.addArrangedSubview(titleLabel)

        let dashPriceLabel = UILabel()
        dashPriceLabel.font = .dw_font(forTextStyle: .footnote)
        dashPriceLabel.textColor = .dw_secondaryText()
        dashPriceLabel.minimumScaleFactor = 0.5
        dashPriceLabel.text = depositWithdrawModel.dashPriceDisplayString
        titleViewStackView.addArrangedSubview(dashPriceLabel)
    }
}

extension CrowdNodeTransferController {
    private func reloadView() {
        let isOnline = networkStatus == .online
        networkUnavailableView.isHidden = isOnline
        keyboardContainer.isHidden = !isOnline
        if let btn = actionButton as? UIButton { btn.superview?.isHidden = !isOnline }
    }

    private func showSuccessTransactionStatus() {
        showSuccessTransactionStatus(text: NSLocalizedString("It could take up to 10 minutes to transfer Dash from Coinbase to Dash Wallet on this device", comment: "Coinbase"))
    }
}

extension CrowdNodeTransferController {
    func configureObservers() {
        viewModel.$crowdNodeBalance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] _ in
                self?.updateBalanceLabel()
            })
            .store(in: &cancellableBag)

        viewModel.$walletBalance
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink(receiveValue: { [weak self] _ in
                self?.updateBalanceLabel()
            })
            .store(in: &cancellableBag)
    }
    
    func updateBalanceLabel() {
        let amount = mode == .deposit ? viewModel.walletBalance : viewModel.crowdNodeBalance
        let priceManager = DSPriceManager.sharedInstance()
        let formatted = model.activeAmountType == .main ? priceManager.string(forDashAmount: Int64(amount)) : priceManager.localCurrencyString(forDashAmount: Int64(amount))
        fromLabel.balanceText = NSLocalizedString("Balance: ", comment: "CrowdNode") + (formatted ?? NSLocalizedString("Syncing", comment: "CrowdNode"))
    }
}

extension CrowdNodeTransferController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}
