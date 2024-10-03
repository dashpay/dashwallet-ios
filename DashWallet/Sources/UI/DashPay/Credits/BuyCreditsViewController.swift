//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import SwiftUI

final class BuyCreditsModel: SendAmountModel {
    static let opCost: UInt64 = 1000000 // TODO: temp MOCK_DASHPAY
    static var currentCredits: Double = 0.5 // TODO: temp MOCK_DASHPAY
    
    override var isAllowedToContinue: Bool {
        return super.isAllowedToContinue && amount.dashAmount.plainAmount / BuyCreditsModel.opCost > 0
    }
    
    override func selectAllFundsWithoutAuth() {
        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = account.maxOutputAmount

        if allAvailableFunds > 0 {
            let maxMultiple = allAvailableFunds / BuyCreditsModel.opCost
            let max = maxMultiple * BuyCreditsModel.opCost
            updateCurrentAmountObject(with: max)
        }
    }
}

final class BuyCreditsViewController: SendAmountViewController, ObservableObject  {
    private var onDismissed: (() -> ())? = nil
    
    init(onDismissed: (() -> ())?) {
        super.init(model: BuyCreditsModel())
        self.onDismissed = onDismissed
    }
    
    private let rateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = NSTextAlignment.center
        label.numberOfLines = 2
        label.font = .dw_font(forTextStyle: .caption1)
        label.textColor = .dw_secondaryText()
        
        return label
    }()
    
    override var actionButtonTitle: String {
        NSLocalizedString("Buy", comment: "Buy")
    }
    
    override func configureModel() {
        super.configureModel()
        
        model.$amount
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amount in
                self?.updateRate(amount: amount)
            }
            .store(in: &cancellableBag)
    }
    
    override func configureHierarchy() {
        super.configureHierarchy()
        
        let rootView = UIView()
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.preservesSuperviewLayoutMargins = true

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 26
        stackView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stackView)
        
        let intro = SendIntro(
            title: NSLocalizedString("Buy credits", comment: "Credits"),
            dashBalance: model.walletBalance,
            balanceLabel: NSLocalizedString("Dash balance", comment: "") + ":",
            avatarView: { }
        )
        let swiftUIController = UIHostingController(rootView: intro)
        swiftUIController.view.backgroundColor = UIColor.dw_secondaryBackground()
        
        addChild(swiftUIController)
        stackView.addArrangedSubview(swiftUIController.view)
        swiftUIController.view.translatesAutoresizingMaskIntoConstraints = false
        swiftUIController.didMove(toParent: self)
        
        amountView.removeFromSuperview()
        stackView.addArrangedSubview(amountView)
        
        let rateContainer = UIView()
        rateContainer.translatesAutoresizingMaskIntoConstraints = false
        rateContainer.backgroundColor = .dw_gray300().withAlphaComponent(0.2)
        rateContainer.layer.cornerRadius = 8
        rateContainer.layer.masksToBounds = true

        rateContainer.addSubview(rateLabel)
        rootView.addSubview(rateContainer)
        contentView.addSubview(rootView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: rootView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            
            rootView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootView.bottomAnchor.constraint(equalTo: keyboardContainer.topAnchor),
            rootView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            
            rateContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -22),
            rateContainer.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            
            rateContainer.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 10).withPriority(.defaultHigh),
            rootView.trailingAnchor.constraint(greaterThanOrEqualTo: rateContainer.trailingAnchor, constant: 10).withPriority(.defaultHigh),
            rateContainer.widthAnchor.constraint(lessThanOrEqualTo: rootView.widthAnchor, constant: -20),
            
            rateLabel.topAnchor.constraint(equalTo: rateContainer.topAnchor, constant: 4),
            rateLabel.leadingAnchor.constraint(equalTo: rateContainer.leadingAnchor, constant: 8),
            rateLabel.trailingAnchor.constraint(equalTo: rateContainer.trailingAnchor, constant: -8),
            rateLabel.bottomAnchor.constraint(equalTo: rateContainer.bottomAnchor, constant: -4),
            
            swiftUIController.view.heightAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    override func actionButtonAction(sender: UIView) {
        guard validateInputAmount() else { return }

        checkLeftoverBalance { [weak self] canContinue in
            guard canContinue, let self = self else { return }

            self.showActivityIndicator()
            
            Task { // TODO: Temp MOCK_DASHPAY
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.hideActivityIndicator()
                let dashAmount = self.model.amount.dashAmount.plainAmount
                let opAmount = dashAmount / BuyCreditsModel.opCost
                BuyCreditsModel.currentCredits += Double(opAmount) * 0.25
                self.dismiss(animated: true)
                self.onDismissed?()
            }
        }
    }
    
    private func updateRate(amount: AmountObject?) {
        guard let amount = amount else { return }
        
        let dashAmount = max(BuyCreditsModel.opCost, amount.dashAmount.plainAmount)
        let opAmount = dashAmount / BuyCreditsModel.opCost
        self.rateLabel.text = String.localizedStringWithFormat(NSLocalizedString("%@ ~ %lu contacts / %lu profile updates", comment: "Credits"), dashAmount.formattedDashAmount, opAmount, opAmount)
    }
}
