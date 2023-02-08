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

// MARK: - OrderPreviewViewController

class OrderPreviewViewController: BaseViewController, NetworkReachabilityHandling {
    internal var networkStatusDidChange: ((NetworkStatus) -> ())?
    internal var reachabilityObserver: Any!

    internal var tableView: UITableView!
    internal var actionButton: DWActionButton!
    internal var retryButton: DWTintedButton!
    internal var networkUnavailableView: UIView!
    internal var buttonsStackView: UIStackView!

    internal var model: OrderPreviewModel!

    private var timer: Timer!
    private var timeRemaining = 10

    internal weak var codeConfirmationController: TwoFactorAuthViewController?

    let measurementFormatter: MeasurementFormatter = {
        let measurementFormatter = MeasurementFormatter()
        measurementFormatter.locale = Locale.current
        measurementFormatter.unitOptions = .providedUnit
        measurementFormatter.unitStyle = .short
        return measurementFormatter
    }()

    // MARK: Actions
    @objc
    func confirmAction() {
        stopCounting()

        actionButton.showActivityIndicator()
        actionButton.isEnabled = false

        model.placeOrder()
    }

    @objc
    func cancelAction() {
        let alert = UIAlertController(title: nil, message: NSLocalizedString("Are you sure you want to cancel this order?", comment: "Coinbase/Buy Dash/Cancel Order    "),
                                      preferredStyle: .alert)
        let noAction = UIAlertAction(title: NSLocalizedString("No", comment: ""), style: .cancel)
        alert.addAction(noAction)
        let yesAction = UIAlertAction(title: NSLocalizedString("Yes", comment: ""), style: .default) { [weak self] _ in
            self?.cancelTransaction()
        }
        alert.addAction(yesAction)
        present(alert, animated: true)
    }

    @objc
    func feeInfoAction() {
        let vc = BasicInfoController()
        vc.mainAction = { UIApplication.shared.open(kCoinbaseFeeInfoURL) }
        vc.icon = "coinbase.fee.info"
        vc.headerText = NSLocalizedString("Fees in crypto purchases", comment: "Coinbase/Buy Dash/Fee Info")
        vc.descriptionText = NSLocalizedString("""
            In addition to the displayed Coinbase fee, we include a spread in the price. When using Advanced Trade, no spread is included because you are interacting directly with the order book.\n
            Cryptocurrency markets are volatile, and this allows us to temporarily lock in a price for trade execution.
            """, comment: "Coinbase/Buy Dash/Fee Info")
        vc.actionButtonText = NSLocalizedString("Learn More...", comment: "Coinbase")
        
        let nvc = BaseNavigationController(rootViewController: vc)
        present(nvc, animated: true)
    }

    @objc
    func retryAction() {
        retryButton.showActivityIndicator()
        retryButton.isEnabled = false
        model.retry()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        startCounting()

        networkStatusDidChange = { [weak self] _ in
            self?.reloadView()
        }
        startNetworkMonitoring()
    }
}

// MARK: Private

extension OrderPreviewViewController {
    private func reloadView() {
        let isOnline = networkStatus == .online
        networkUnavailableView.isHidden = isOnline
        buttonsStackView.isHidden = !isOnline
    }

    private func cancelTransaction() {
        navigationController?.popViewController(animated: true)
    }

    internal func stopCounting() {
        timer?.invalidate()
        timer = nil
    }

    internal func startCounting() {
        timeRemaining = 10
        startTimer()
        updateActionButton()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            guard let wSelf = self else { return }

            wSelf.timeRemaining -= 1

            if wSelf.timeRemaining == 0 {
                wSelf.updateActionButton()
                wSelf.timer.invalidate()
                return
            }

            wSelf.updateActionButton()
        })
    }

    private func updateActionButton() {
        retryButton.isHidden = timeRemaining != 0
        actionButton.isHidden = timeRemaining == 0

        let title = String(format: NSLocalizedString("Confirm (%d%@)", comment: "Coinbase/Buy Dash/Confirm Order"), timeRemaining,
                           measurementFormatter.string(from: UnitDuration.seconds))
        actionButton.setTitle(title, for: .normal)
    }
}

// MARK: Life cycle
extension OrderPreviewViewController {
    @objc
    internal func configureModel() {
        model.transactionDelegate = self

        model.orderChangeHandle = { [weak self] in
            self?.tableView.reloadData()
            self?.retryButton.hideActivityIndicator()
            self?.retryButton.isEnabled = true
            self?.startCounting()
        }

        model.failureHandle = { [weak self] _ in
            self?
                .showFailedTransactionStatus(text: NSLocalizedString("The Dash was successfully deposited to your Coinbase account. But there was a problem transfering it to Dash Wallet on this device.",
                                                                     comment: "Coinbase/Buy Dash/Confirm Order"))
        }
    }

    @objc
    internal func configureHierarchy() {
        title = NSLocalizedString("Order Preview", comment: "Coinbase/Buy Dash/Confirm Order")
        view.backgroundColor = .dw_secondaryBackground()

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.backgroundColor = .dw_secondaryBackground()
        tableView.preservesSuperviewLayoutMargins = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.layoutMargins = .init(top: 0.0, left: 15, bottom: 0.0, right: 0)
        tableView.separatorInset = tableView.layoutMargins
        tableView.register(ConfirmOrderGeneralInfoCell.self, forCellReuseIdentifier: ConfirmOrderGeneralInfoCell.reuseIdentifier)
        view.addSubview(tableView)

        buttonsStackView = UIStackView()
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.axis = .horizontal
        buttonsStackView.spacing = 10
        buttonsStackView.alignment = .fill
        view.addSubview(buttonsStackView)

        let cancelButton = UIButton(type: .custom)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.backgroundColor = .clear
        cancelButton.layer.cornerRadius = 6
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: "Coinbase"), for: .normal)
        cancelButton.setTitleColor(.dw_label(), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(cancelButton)

        actionButton = DWActionButton(frame: .zero)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitle(NSLocalizedString("Confirm (%@)", comment: "Coinbase/Buy Dash/Confirm Order"), for: .normal)
        actionButton.addTarget(self, action: #selector(confirmAction), for: .touchUpInside)
        actionButton.isHidden = true
        buttonsStackView.addArrangedSubview(actionButton)

        retryButton = DWTintedButton(frame: .zero)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryAction), for: .touchUpInside)
        retryButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        retryButton.setTitle(NSLocalizedString("Retry", comment: "Coinbase"), for: .normal)
        retryButton.isHidden = false
        buttonsStackView.addArrangedSubview(retryButton)

        networkUnavailableView = NetworkUnavailableView(frame: .init(x: 0, y: 0, width: view.bounds.width, height: 200))
        networkUnavailableView.translatesAutoresizingMaskIntoConstraints = false
        networkUnavailableView.isHidden = true
        tableView.tableFooterView = networkUnavailableView

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: buttonsStackView.topAnchor),
            buttonsStackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            buttonsStackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: buttonsStackView.bottomAnchor, constant: 15),

            actionButton.heightAnchor.constraint(equalToConstant: 46),
            actionButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor, multiplier: 1.4),

            retryButton.heightAnchor.constraint(equalToConstant: 46),
            retryButton.widthAnchor.constraint(equalTo: actionButton.widthAnchor),
        ])
    }
}

// MARK: UITableViewDataSource, UITableViewDelegate

extension OrderPreviewViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell()
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        nil
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        7
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        8
    }
}

// MARK: NavigationStackControllable

extension OrderPreviewViewController: NavigationStackControllable {
    func shouldPopViewController() -> Bool {
        cancelAction()

        return false
    }
}

// MARK: CoinbaseCodeConfirmationPreviewing, CoinbaseTransactionHandling

extension OrderPreviewViewController: CoinbaseCodeConfirmationPreviewing, CoinbaseTransactionHandling {
    var isCancelingToFail: Bool { true }

    func showActivityIndicator() {
        actionButton?.showActivityIndicator()
    }

    func hideActivityIndicator() {
        actionButton?.hideActivityIndicator()
    }

    func codeConfirmationControllerDidContinue(with code: String) {
        model.continueTransferFromCoinbase(with: code)
    }

    func codeConfirmationControllerDidCancel() {
        hideActivityIndicator()
        showFailedTransactionStatus(text: NSLocalizedString("The Dash was successfully deposited to your Coinbase account. But there was a problem transfering it to Dash Wallet on this device.",
                                                            comment: "Coinbase/Buy Dash/Confirm Order"))
    }
}
