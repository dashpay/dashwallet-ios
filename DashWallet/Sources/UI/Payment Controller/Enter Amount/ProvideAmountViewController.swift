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

// MARK: - ProvideAmountViewControllerDelegate

protocol ProvideAmountViewControllerDelegate: AnyObject {
    func provideAmountViewControllerDidInput(amount: UInt64, selectedCurrency: String)
}

// MARK: - ProvideAmountScreenState

@MainActor
final class ProvideAmountScreenState: ObservableObject {
    @Published var isLoading = false
}

private struct InlineAmountMessageError: Error, LocalizedError, ColorizedText {
    let message: String
    let textColor: UIColor

    var errorDescription: String? {
        message
    }
}

// MARK: - ProvideAmountViewController

final class ProvideAmountViewController: ActionButtonViewController, AmountProviding, SendAmountFlowSupporting {
    weak var delegate: ProvideAmountViewControllerDelegate?

    public var locksBalance = false

    override var showsActionButton: Bool { false }

    private let address: String
    private let contact: DWDPBasicUserItem?
    private let sendAmountModel = SendAmountModel()
    private let screenState = ProvideAmountScreenState()
    private var details: DSPaymentProtocolDetails?

    var sendAmountSupportModel: BaseAmountModel {
        sendAmountModel
    }

    init(address: String, details: DSPaymentProtocolDetails?, contact: DWDPBasicUserItem?) {
        self.address = address
        self.contact = contact
        self.details = details
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "SecondaryBackground", in: .dashUIKit, compatibleWith: .current)
        configureHierarchy()
        updateInitialAmount()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func showActivityIndicator() {
        screenState.isLoading = true
    }

    override func hideActivityIndicator() {
        screenState.isLoading = false
    }
}

extension ProvideAmountViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }

    var isNavigationBarHidden: Bool { true }
}

extension ProvideAmountViewController {
    private func configureHierarchy() {
        let rootView = ProvideAmountRootView(
            model: sendAmountModel,
            screenState: screenState,
            destination: destination,
            locksBalance: locksBalance,
            avatarView: avatarView(),
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onMax: { [weak self] in
                self?.sendAmountModel.selectAllFunds()
            },
            onSelectCurrency: { [weak self] in
                self?.showCurrencyList()
            },
            onSend: { [weak self] in
                self?.performSend()
            }
        )

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = UIColor(named: "SecondaryBackground", in: .dashUIKit, compatibleWith: .current)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        setupContentView(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private var destination: String {
#if DASHPAY
        if let contact {
            return contact.username
        }
#endif
        return address
    }
    private func avatarView() -> AnyView {
#if DASHPAY
        if let contact {
            let avatarView = DWDPAvatarView()
            avatarView.blockchainIdentity = contact.blockchainIdentity
            avatarView.translatesAutoresizingMaskIntoConstraints = false
            avatarView.backgroundMode = .random
            avatarView.isUserInteractionEnabled = false
            avatarView.isSmall = true
            return AnyView(UIViewWrapper(uiView: avatarView))
        }
#endif
        return AnyView(EmptyView())
    }

    private func performSend() {
        guard validateInputAmount() else { return }

        checkLeftoverBalance { [weak self] canContinue in
            guard canContinue, let self else { return }

            showActivityIndicator()
            let paymentCurrency: DWPaymentCurrency = sendAmountModel.activeAmountType == .main ? .dash : .fiat
            DWGlobalOptions.sharedInstance().selectedPaymentCurrency = paymentCurrency

            delegate?.provideAmountViewControllerDidInput(
                amount: sendAmountModel.amount.plainAmount,
                selectedCurrency: sendAmountModel.supplementaryCurrencyCode
            )
        }
    }

    private func updateInitialAmount() {
        if let details {
            let totalAmount = details.outputAmounts.reduce(UInt64(0)) { sum, element in
                if let number = element as? NSNumber {
                    return sum + number.uint64Value
                }
                return sum
            }
            sendAmountModel.updateCurrentAmountObject(with: totalAmount)
        }
    }

    private func showCurrencyList() {
        let currencyController = DWLocalCurrencyViewController(
            navigationAppearance: .white,
            presentationMode: .dialog,
            currencyCode: sendAmountModel.localCurrencyCode
        )
        currencyController.isGlobal = false
        currencyController.delegate = self
        let navigationController = BaseNavigationController(rootViewController: currencyController)
        present(navigationController, animated: true)
    }
}

// MARK: - DWLocalCurrencyViewControllerDelegate

extension ProvideAmountViewController: DWLocalCurrencyViewControllerDelegate {
    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        sendAmountModel.setupCurrencyCode(currencyCode)
        controller.dismiss(animated: true)
    }

    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        controller.dismiss(animated: true)
    }
}

// MARK: - ErrorPresentable

extension ProvideAmountViewController {
    func present(error: Error) {
        hideActivityIndicator()
        sendAmountModel.error = error
    }

    func present(message: String, level: MessageLevel) {
        hideActivityIndicator()
        sendAmountModel.error = InlineAmountMessageError(message: message, textColor: level.textColor)
    }
}

private struct ProvideAmountRootView: View {
    @ObservedObject var model: SendAmountModel
    @ObservedObject var screenState: ProvideAmountScreenState
    let destination: String
    let locksBalance: Bool
    let avatarView: AnyView
    let onBack: () -> Void
    let onMax: () -> Void
    let onSelectCurrency: () -> Void
    let onSend: () -> Void

    private var dashBalance: UInt64 {
        CoinJoinService.shared.mixingState.isInProgress ? model.coinJoinBalance : model.walletBalance
    }

    private var balanceLabel: String {
        CoinJoinService.shared.mixingState.isInProgress
            ? NSLocalizedString("Mixed balance", comment: "")
            : NSLocalizedString("Dash balance", comment: "")
    }

    var body: some View {
        SendAmountView(
            model: model,
            onBack: onBack,
            destination: destination,
            dashBalance: dashBalance,
            balanceLabel: balanceLabel,
            balanceAuthCallback: locksBalance ? model.auth : nil,
            isLoading: screenState.isLoading,
            onMax: onMax,
            onSelectCurrency: onSelectCurrency,
            onSend: onSend,
            avatarView: { avatarView }
        )
    }
}
