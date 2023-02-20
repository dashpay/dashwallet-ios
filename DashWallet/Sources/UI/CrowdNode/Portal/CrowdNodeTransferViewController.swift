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

import Combine
import Foundation

// MARK: - CrowdNodeTransferController

final class CrowdNodeTransferController: SendAmountViewController, NetworkReachabilityHandling {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    internal var mode: TransferDirection {
        transferModel.direction
    }

    /// Conform to NetworkReachabilityHandling
    internal var networkStatusDidChange: ((NetworkStatus) -> ())?
    internal var reachabilityObserver: Any!
    internal var transferModel: CrowdNodeTransferModel {
        model as! CrowdNodeTransferModel
    }

    private var networkUnavailableView: UIView!
    private var fromLabel: FromLabel!
    private var dashPriceLabel: UILabel!
    private var minimumDepositBanner: MinimumDepositBanner?

    override var amountInputStyle: AmountInputControl.Style { .oppositeAmount }

    static func controller(mode: TransferDirection) -> CrowdNodeTransferController {
        let model = CrowdNodeTransferModel()
        model.direction = mode

        let vc = CrowdNodeTransferController(model: model)
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .dw_secondaryBackground()

        navigationItem.backButtonDisplayMode = .minimal
        navigationItem.largeTitleDisplayMode = .never

        networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
        startNetworkMonitoring()
        configureObservers()

        if mode == .deposit && viewModel.shouldShowWithdrawalLimitsDialog {
            showWithdrawalLimitsInfo()
            viewModel.shouldShowWithdrawalLimitsDialog = false
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.showNotificationOnResult = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.showNotificationOnResult = true
    }

    override var actionButtonTitle: String? {
        mode.title
    }

    override func actionButtonAction(sender: UIView) {
        let amount = transferModel.amount.plainAmount

        if mode == .deposit && viewModel.shouldShowFirstDepositBanner && amount < CrowdNode.minimumDeposit {
            minimumDepositBanner?.backgroundColor = .systemRed
            minimumDepositBanner?.dw_shakeView()
            return
        }

        showActivityIndicator()

        if mode == .deposit {
            handleDeposit(amount: amount)
        } else {
            handleWithdraw(amount: amount)
        }
    }

    override func configureModel() {
        super.configureModel()

        model.inputsSwappedHandler = { [weak self] _ in
            self?.updateBalanceLabel()
        }
    }

    private func handleDeposit(amount: UInt64) {
        checkLeftoverBalance(isCrowdNodeTransfer: true) { [weak self] canContinue in
            guard canContinue, let wSelf = self else { self?.hideActivityIndicator(); return }

            Task {
                do {
                    if try await wSelf.viewModel.deposit(amount: amount) {
                        wSelf.showSuccessfulStatus()
                    }
                } catch {
                    wSelf.showErrorStatus(err: error)
                }

                wSelf.hideActivityIndicator()
            }
        }
    }

    private func handleWithdraw(amount: UInt64) {
        Task {
            do {
                if try await viewModel.withdraw(amount: amount) {
                    showSuccessfulStatus()
                }
            } catch CrowdNode.Error.withdrawLimit(_, let period) {
                showWithdrawalLimitsError(period: period)
            } catch {
                showErrorStatus(err: error)
            }

            hideActivityIndicator()
        }
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
            NSLayoutConstraint(item: fromLabel!, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 0.38, constant: 0),

            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            NSLayoutConstraint(item: amountView!, attribute: .top, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 0.5, constant: 0),

            networkUnavailableView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            networkUnavailableView.centerYAnchor.constraint(equalTo: numberKeyboard.centerYAnchor),
        ])

        if mode == .deposit && viewModel.shouldShowFirstDepositBanner {
            let minimumDepositBanner = MinimumDepositBanner(frame: .zero)
            contentView.addSubview(minimumDepositBanner)

            NSLayoutConstraint.activate([
                minimumDepositBanner.heightAnchor.constraint(equalToConstant: 32),
                minimumDepositBanner.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                minimumDepositBanner.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0),
                minimumDepositBanner.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
            ])

            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(minimumDepositBannerTapAction))
            minimumDepositBanner.addGestureRecognizer(tapGestureRecognizer)
            self.minimumDepositBanner = minimumDepositBanner
        }
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
        titleLabel.text = mode.title
        titleViewStackView.addArrangedSubview(titleLabel)

        dashPriceLabel = UILabel()
        dashPriceLabel.font = .dw_font(forTextStyle: .footnote)
        dashPriceLabel.textColor = .dw_secondaryText()
        dashPriceLabel.minimumScaleFactor = 0.5
        dashPriceLabel.text = transferModel.dashPriceDisplayString
        titleViewStackView.addArrangedSubview(dashPriceLabel)
    }

    @objc
    func minimumDepositBannerTapAction() {
        let vc = StakingInfoDialogController.controller()
        present(vc, animated: true, completion: nil)
    }
}

extension CrowdNodeTransferController {
    private func reloadView() {
        let isOnline = networkStatus == .online
        networkUnavailableView.isHidden = isOnline
        keyboardContainer.isHidden = !isOnline
        if let btn = actionButton as? UIButton { btn.superview?.isHidden = !isOnline }
    }

    private func showSuccessfulStatus() {
        let vc = SuccessfulOperationStatusViewController.initiate(from: sb("OperationStatus"))
        vc.closeHandler = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.navigationController?.popToViewController(wSelf.previousControllerOnNavigationStack!, animated: true)
        }
        vc.headerText = mode.successfulTransfer
        vc.descriptionText = mode.successfulTransferDetails

        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showErrorStatus(err: Error) {
        let vc = FailedOperationStatusViewController.initiate(from: sb("OperationStatus"))
        vc.headerText = mode.failedTransfer
        vc.descriptionText = err.localizedDescription
        vc.supportButtonText = NSLocalizedString("Send Report", comment: "CrowdNode")
        vc.retryHandler = { [weak self] in self?.navigationController?.popViewController(animated: true) }
        vc.cancelHandler = { [weak self] in
            guard let wSelf = self else { return }
            wSelf.navigationController?.popToViewController(wSelf.previousControllerOnNavigationStack!, animated: true)
        }
        vc.supportHandler = {
            let url = DWAboutModel.supportURL()
            let safariViewController = SFSafariViewController.dw_controller(with: url)
            self.present(safariViewController, animated: true)
        }
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showWithdrawalLimitsError(period: WithdrawalLimitPeriod) {
        let vc = WithdrawalLimitsController()
        var buttonText: String? = nil
        let isOnlineAccountDone = viewModel.onlineAccountState == .done

        if period == .perTransaction {
            if isOnlineAccountDone {
                buttonText = NSLocalizedString("Read Withdrawal Policy", comment: "CrowdNode")
            } else {
                buttonText = NSLocalizedString("Create Online Account", comment: "CrowdNode")
            }
        }

        vc.model = WithdrawalLimitDialogModel(icon: "image.crowdnode.error", buttonText: buttonText, limits: viewModel.withdrawalLimits, highlightedLimit: period.rawValue)
        vc.actionHandler = {
            if isOnlineAccountDone {
                UIApplication.shared.open(URL(string: CrowdNode.withdrawalLimitsUrl)!)
            } else {
                vc.dismiss(animated: true)
                self.navigationController?.pushViewController(OnlineAccountEmailController.controller(), animated: true)
            }
        }

        let nvc = BaseNavigationController(rootViewController: vc)
        present(nvc, animated: true)
    }

    private func showWithdrawalLimitsInfo() {
        let vc = WithdrawalLimitsController()
        vc.model = WithdrawalLimitDialogModel(icon: "image.crowdnode.info", buttonText: nil, limits: viewModel.withdrawalLimits, highlightedLimit: -1)
        let nvc = BaseNavigationController(rootViewController: vc)
        present(nvc, animated: true)
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

    override func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        super.localCurrencyViewController(controller, didSelectCurrency: currencyCode)

        updateBalanceLabel()
        dashPriceLabel.text = transferModel.dashPriceDisplayString
    }

    private func updateBalanceLabel() {
        let amount = mode == .deposit ? viewModel.walletBalance : viewModel.crowdNodeBalance
        let formatted = model.activeAmountType == .main
            ? amount.formattedDashAmount
            : CurrencyExchanger.shared.fiatAmountString(in: model.localCurrencyCode, for: amount.dashAmount)
        fromLabel.balanceText = NSLocalizedString("Balance: ", comment: "CrowdNode") + formatted
    }
}

// MARK: PaymentControllerPresentationContextProviding

extension CrowdNodeTransferController: PaymentControllerPresentationContextProviding {
    func presentationAnchorForPaymentController(_ controller: PaymentController) -> PaymentControllerPresentationAnchor {
        self
    }
}
