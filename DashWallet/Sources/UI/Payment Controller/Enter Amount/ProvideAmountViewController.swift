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

// MARK: - ProvideAmountViewControllerDelegate

protocol ProvideAmountViewControllerDelegate: AnyObject {
    func provideAmountViewControllerDidInput(amount: UInt64)
}

// MARK: - ProvideAmountViewController

final class ProvideAmountViewController: SendAmountViewController {
    weak var delegate: ProvideAmountViewControllerDelegate?

    private var balanceLabel: UILabel!

    private let address: String
    private var isBalanceHidden = true

    init(address: String) {
        self.address = address
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func actionButtonAction(sender: UIView) {
        guard validateInputAmount() else { return }

        showActivityIndicator()

        let paymentCurrency: DWPaymentCurrency = sendAmountModel.activeAmountType == .main ? .dash : .fiat
        DWGlobalOptions.sharedInstance().selectedPaymentCurrency = paymentCurrency

        delegate?.provideAmountViewControllerDidInput(amount: model.amount.plainAmount)
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 26
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        let textContainer = UIStackView()
        textContainer.axis = .vertical
        textContainer.spacing = 4
        stackView.addArrangedSubview(textContainer)

        let sendContainer = UIView()
        textContainer.addArrangedSubview(sendContainer)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .dw_font(forTextStyle: .largeTitle).withWeight(UIFont.Weight.bold.rawValue)
        titleLabel.text = NSLocalizedString("Send", comment: "Send Screen")
        sendContainer.addSubview(titleLabel)

        let toLabel = UILabel()
        toLabel.translatesAutoresizingMaskIntoConstraints = false
        toLabel.font = .dw_font(forTextStyle: .body)
        toLabel.textColor = .dw_label()
        toLabel.text = NSLocalizedString("to", comment: "Send Screen: to address")
        sendContainer.addSubview(toLabel)

        let addressLabel = UILabel()
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.font = .dw_font(forTextStyle: .body)
        addressLabel.textColor = .dw_label()
        addressLabel.text = address
        addressLabel.lineBreakMode = .byTruncatingMiddle
        sendContainer.addSubview(addressLabel)

        let balanceStackView = UIStackView()
        balanceStackView.axis = .horizontal
        balanceStackView.spacing = 2
        balanceStackView.alignment = .lastBaseline
        textContainer.addArrangedSubview(balanceStackView)

        let balanceTitleLabel = UILabel()
        balanceTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceTitleLabel.font = .dw_font(forTextStyle: .subheadline)
        balanceTitleLabel.textColor = .dw_secondaryText()
        balanceTitleLabel.text = NSLocalizedString("Balance", comment: "Send Screen: to address") + ":"
        balanceStackView.addArrangedSubview(balanceTitleLabel)

        balanceLabel = UILabel()
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceLabel.font = .dw_font(forTextStyle: .subheadline)
        balanceLabel.textColor = .dw_secondaryText()
        balanceStackView.addArrangedSubview(balanceLabel)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.backgroundColor = .clear
        balanceStackView.addArrangedSubview(spacer)

        let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .regular, scale: .small)
        let showHideBalanceButton = UIButton(type: .custom)
        showHideBalanceButton.translatesAutoresizingMaskIntoConstraints = false
        showHideBalanceButton.backgroundColor = UIColor(red: 0.098, green: 0.11, blue: 0.122, alpha: 0.05)
        showHideBalanceButton.layer.cornerRadius = 12
        showHideBalanceButton.setImage(UIImage(systemName: "eye.fill", withConfiguration: configuration), for: .normal)
        showHideBalanceButton.tintColor = .dw_darkTitle()
        showHideBalanceButton.addTarget(self, action: #selector(toggleBalanceVisibilityAction), for: .touchUpInside)
        balanceStackView.addArrangedSubview(showHideBalanceButton)

        let extraSpaceView = UIView()
        extraSpaceView.backgroundColor = .clear
        balanceStackView.addArrangedSubview(extraSpaceView)

        amountView.removeFromSuperview()
        stackView.addArrangedSubview(amountView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: sendContainer.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: sendContainer.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: sendContainer.bottomAnchor),

            toLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 2),
            toLabel.lastBaselineAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor),

            addressLabel.leadingAnchor.constraint(equalTo: toLabel.trailingAnchor, constant: 2),
            addressLabel.lastBaselineAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: sendContainer.trailingAnchor),

            spacer.widthAnchor.constraint(equalToConstant: 6),

            showHideBalanceButton.widthAnchor.constraint(equalToConstant: 24),
            showHideBalanceButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc
    func walletBalanceDidChangeNotification(notification: Notification) {
        updateBalance()
    }

    @objc
    func toggleBalanceVisibilityAction() {
        isBalanceHidden.toggle()
        updateBalance()
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

        NotificationCenter.default.addObserver(self, selector: #selector(walletBalanceDidChangeNotification(notification:)),
                                               name: .balanceChangeNotification, object: nil)

        updateBalance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension ProvideAmountViewController {
    private func updateBalance() {
        let balance = model.walletBalance

        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: balance.dashAmount, to: App.fiatCurrency) {
            fiat = NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing...", comment: "Balance")
        }

        let dashStr = balance.formattedDashAmount
        let fiatStr = " ≈ \(fiat)"
        let fullStr = "\(dashStr)\(fiatStr)"

        if isBalanceHidden {
            balanceLabel.text = String(repeating: "*", count: fullStr.count + 4)
        } else {
            balanceLabel.text = fullStr
        }
    }
}

extension Notification.Name {
    static var balanceChangeNotification: NSNotification.Name { .init("DSWalletBalanceChangedNotification") }
}
