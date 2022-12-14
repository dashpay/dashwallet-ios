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

// MARK: - ConfirmOrderItem

enum ConfirmOrderItem {
    case paymentMethod
    case purchaseAmount
    case feeAmount
    case totalAmount
    case amountInDash

    var showInfoButton: Bool {
        self == .feeAmount
    }

    var valueFont: UIFont {
        if self == .totalAmount {
            return .dw_font(forTextStyle: .body)
        } else {
            return .dw_font(forTextStyle: .footnote)
        }
    }

    var localizedTitle: String {
        switch self {
        case .paymentMethod:
            return NSLocalizedString("Payment method", comment: "Coinbase/Buy Dash")
        case .purchaseAmount:
            return NSLocalizedString("Purchase", comment: "Coinbase/Buy Dash")
        case .feeAmount:
            return NSLocalizedString("Coinbase Fee", comment: "Coinbase/Buy Dash")
        case .totalAmount:
            return NSLocalizedString("Total", comment: "Coinbase/Buy Dash")
        case .amountInDash:
            return NSLocalizedString("Amount in Dash", comment: "Coinbase/Buy Dash")
        }
    }

    var localizedDescription: String? {
        guard self == .amountInDash else {
            return nil
        }

        return NSLocalizedString("You will receive 0.99 Dash on your Dash Wallet on this device. Please note that it can take up to 2-3 minutes to complete a transfer.",
                                 comment: "Coinbase/Buy Dash/Confirm Order")
    }

    var cellIdentifier: String {
        if self == .amountInDash {
            return ConfirmOrderAmountInDashCell.dw_reuseIdentifier
        } else {
            return ConfirmOrderGeneralInfoCell.dw_reuseIdentifier
        }
    }

    var isInfoButtonHidden: Bool {
        self != .feeAmount
    }
}

// MARK: - ConfirmOrderSection

enum ConfirmOrderSection: Int {
    case generalInfo
    case amountIntDash
}

// MARK: - ConfirmOrderController

final class ConfirmOrderController: BaseViewController {
    private var tableView: UITableView!
    private var actionButton: DWActionButton!
    private var retryButton: DWTintedButton!

    private let model: ConfirmOrderModel

    private let sections: [ConfirmOrderSection] = [.generalInfo, .amountIntDash]
    private let items: [[ConfirmOrderItem]] = [
        [.paymentMethod, .purchaseAmount, .feeAmount, .totalAmount],
        [.amountInDash],
    ]

    private var timer: Timer!
    private var timeRemaining = 10
    let measurementFormatter: MeasurementFormatter = {
        let measurementFormatter = MeasurementFormatter()
        measurementFormatter.locale = Locale.current
        measurementFormatter.unitOptions = .providedUnit
        measurementFormatter.unitStyle = .short
        return measurementFormatter
    }()

    init(order: CoinbasePlaceBuyOrder, paymentMethod: CoinbasePaymentMethod, plainAmount: UInt64) {
        model = ConfirmOrderModel(order: order, paymentMethod: paymentMethod, plainAmount: plainAmount)

        super.init(nibName: nil, bundle: nil)

        configureModel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Actions
    @objc func confirmAction() {
        actionButton.showActivityIndicator()
        actionButton.isEnabled = false

        model.placeOrder()
    }

    @objc func cancelAction() {
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

    @objc func feeInfoAction() {
        let nvc = BaseNavigationController(rootViewController: CoinbaseFeeInfoController())
        present(nvc, animated: true)
    }

    @objc func retryAction() {
        retryButton.showActivityIndicator()
        retryButton.isEnabled = false
        model.retry()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        startCounting()
    }
}

// MARK: Private

extension ConfirmOrderController {
    private func cancelTransaction() {
        dismiss(animated: true)
    }

    private func startCounting() {
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
extension ConfirmOrderController {
    private func configureModel() {
        model.orderChangeHandle = { [weak self] in
            self?.tableView.reloadData()
            self?.retryButton.hideActivityIndicator()
            self?.retryButton.isEnabled = true
            self?.startCounting()
        }

        model.completionHandle = { [weak self] in
            self?
                .showSuccessTransactionStatus(text: NSLocalizedString("It could take up to 2-3 minutes for the Dash to be transfered to your Dash Wallet on this device.",
                                                                      comment: "Coinbase/Buy Dash/Confirm Order"))
        }

        model.failureHandle = { [weak self] _ in
            self?
                .showFailedTransactionStatus(text: NSLocalizedString("The Dash was successfully deposited to your Coinbase account. But there was a problem transfering it to Dash Wallet on this device.",
                                                                     comment: "Coinbase/Buy Dash/Confirm Order"))
        }
    }

    private func configureHierarchy() {
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
        tableView.register(ConfirmOrderGeneralInfoCell.self, forCellReuseIdentifier: ConfirmOrderGeneralInfoCell.dw_reuseIdentifier)
        tableView.register(ConfirmOrderAmountInDashCell.self, forCellReuseIdentifier: ConfirmOrderAmountInDashCell.dw_reuseIdentifier)
        view.addSubview(tableView)

        let buttonStackView = UIStackView()
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 10
        buttonStackView.alignment = .fill
        view.addSubview(buttonStackView)

        let cancelButton = UIButton(type: .custom)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.backgroundColor = .clear
        cancelButton.layer.cornerRadius = 6
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: "Coinbase"), for: .normal)
        cancelButton.setTitleColor(.dw_label(), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        buttonStackView.addArrangedSubview(cancelButton)

        actionButton = DWActionButton(frame: .zero)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitle(NSLocalizedString("Confirm (%@)", comment: "Coinbase/Buy Dash/Confirm Order"), for: .normal)
        actionButton.addTarget(self, action: #selector(confirmAction), for: .touchUpInside)
        actionButton.isHidden = true
        buttonStackView.addArrangedSubview(actionButton)

        retryButton = DWTintedButton(frame: .zero)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(retryAction), for: .touchUpInside)
        retryButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        // retryButton.setImage(nil, for: .disabled)
        retryButton.setTitle(NSLocalizedString("Retry", comment: "Coinbase"), for: .normal)
        retryButton.isHidden = false
        buttonStackView.addArrangedSubview(retryButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: buttonStackView.topAnchor),
            buttonStackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: buttonStackView.bottomAnchor, constant: 15),

            actionButton.heightAnchor.constraint(equalToConstant: 46),
            actionButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor, multiplier: 1.4),

            retryButton.heightAnchor.constraint(equalToConstant: 46),
            retryButton.widthAnchor.constraint(equalTo: actionButton.widthAnchor),
        ])
    }
}

// MARK: UITableViewDataSource, UITableViewDelegate

extension ConfirmOrderController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.section][indexPath.row]

        let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier, for: indexPath) as! ConfirmOrderGeneralInfoCell
        cell.selectionStyle = .none
        let value = model.formattedValue(for: item)
        if let cell = cell as? ConfirmOrderAmountInDashCell {
            cell.update(with: item, value: value, amountString: model.order.amount.amount)
        } else {
            cell.update(with: item, value: value)
        }

        cell.infoHandle = { [weak self] in
            self?.feeInfoAction()
        }
        return cell
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
