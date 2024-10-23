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

import UIKit
import SwiftUI
import Combine

// MARK: - ProvideAmountViewControllerDelegate

protocol ProvideAmountViewControllerDelegate: AnyObject {
    func provideAmountViewControllerDidInput(amount: UInt64, selectedCurrency: String)
}

// MARK: - ProvideAmountViewController

final class ProvideAmountViewController: SendAmountViewController {
    weak var delegate: ProvideAmountViewControllerDelegate?

    public var locksBalance = false

    private let address: String
    private let contact: DWDPBasicUserItem?
    private var details: DSPaymentProtocolDetails?
    private var isBalanceHidden = true

    init(address: String, details: DSPaymentProtocolDetails?, contact: DWDPBasicUserItem?) {
        self.address = address
        self.contact = contact
        self.details = details
        super.init(model: SendAmountModel())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func actionButtonAction(sender: UIView) {
        guard validateInputAmount() else { return }

        checkLeftoverBalance { [weak self] canContinue in
            guard canContinue, let wSelf = self else { return }

            wSelf.showActivityIndicator()
            let paymentCurrency: DWPaymentCurrency = wSelf.sendAmountModel.activeAmountType == .main ? .dash : .fiat
            DWGlobalOptions.sharedInstance().selectedPaymentCurrency = paymentCurrency

            wSelf.delegate?.provideAmountViewControllerDidInput(amount: wSelf.model.amount.plainAmount,
                                                                selectedCurrency: wSelf.model.supplementaryCurrencyCode)
        }
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 26
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        
        var destination = address
        let balanceLabel = CoinJoinService.shared.mode == .none ? NSLocalizedString("Dash balance", comment: "") : NSLocalizedString("Mixed balance", comment: "");
        var avatarView: DWDPAvatarView? = nil
        
#if DASHPAY
        if let contact = contact {
            avatarView = DWDPAvatarView()
            destination = contact.username
            avatarView!.blockchainIdentity = contact.blockchainIdentity
            avatarView!.translatesAutoresizingMaskIntoConstraints = false
            avatarView!.backgroundMode = .random
            avatarView!.isUserInteractionEnabled = false
            avatarView!.isSmall = true
        }
#endif
        
        let intro = ProvideAmountIntro(
            destination: destination,
            balanceLabel: balanceLabel,
            model: self.model as! SendAmountModel,
            avatarView: { UIViewWrapper(uiView: avatarView ?? EmptyUIView()) }
        )
        let swiftUIController = UIHostingController(rootView: intro)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        
        addChild(swiftUIController)
        stackView.addArrangedSubview(swiftUIController.view)
        swiftUIController.view.translatesAutoresizingMaskIntoConstraints = false
        swiftUIController.didMove(toParent: self)

        amountView.removeFromSuperview()
        stackView.addArrangedSubview(amountView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            swiftUIController.view.heightAnchor.constraint(equalToConstant: 100)
        ])
    }

    @objc
    func toggleBalanceVisibilityAction() {
        let toggleBalance = { [weak self] in
            guard let self else { return }

            self.isBalanceHidden.toggle()
        }

        if locksBalance && isBalanceHidden {
            DSAuthenticationManager.sharedInstance().authenticate(withPrompt: nil, usingBiometricAuthentication: false, alertIfLockout: true) { authenticatedOrSuccess, _, _ in

                guard authenticatedOrSuccess else { return }
                toggleBalance()
            }
        } else {
            toggleBalance()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let standardAppearance = UINavigationBarAppearance()
        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.backgroundColor = .dw_secondaryBackground()
        standardAppearance.shadowColor = .clear

        let compactAppearance = standardAppearance.copy()

        let navigationBar = navigationController!.navigationBar
        navigationBar.isTranslucent = true
        navigationBar.standardAppearance = standardAppearance
        navigationBar.scrollEdgeAppearance = standardAppearance
        navigationBar.compactAppearance = compactAppearance
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = compactAppearance
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateInitialAmount()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension ProvideAmountViewController {
    private func updateInitialAmount() {
        if let details = details {
            let totalAmount = details.outputAmounts.reduce(UInt64(0)) { sum, element in
                if let number = element as? NSNumber {
                    return sum + number.uint64Value
                }
                return sum
            }
            model.updateCurrentAmountObject(with: totalAmount)
        }
    }
}

extension Notification.Name {
    static var balanceChangeNotification: NSNotification.Name { .init("DSWalletBalanceChangedNotification") }
}

struct ProvideAmountIntro<Content: View>: View {
    var destination: String? = nil
    var balanceLabel: String
    @StateObject var model: SendAmountModel
    @ViewBuilder var avatarView: () -> Content
    
    var body: some View {
        SendIntro(
            title: NSLocalizedString("Send", comment: "Send Screen"),
            destination: destination,
            dashBalance: CoinJoinService.shared.mode == .none ? model.walletBalance : model.coinJoinBalance,
            balanceLabel: balanceLabel + ":",
            avatarView: avatarView
        )
    }
}
