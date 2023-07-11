//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - ConfirmPaymentViewControllerDelegate

@objc
protocol ConfirmPaymentViewControllerDelegate: AnyObject {
    func confirmPaymentViewControllerDidConfirm(_ controller: ConfirmPaymentViewController)
    func confirmPaymentViewControllerDidCancel(_ controller: ConfirmPaymentViewController)
}

// MARK: - ConfirmPaymentViewController

final class ConfirmPaymentViewController: SheetViewController {
    public var delegate: ConfirmPaymentViewControllerDelegate?
    public var isSendingEnabled = true

    private var balanceView: BalanceView!
    private var tableView: UITableView!
    private var confirmButton: ActionButton!

    private let model: ConfirmPaymentModel

    init(dataSource: ConfirmPaymentDataSource) {
        model = .init(dataSource: dataSource)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public func update(with dataSource: ConfirmPaymentDataSource) {
        model.update(with: dataSource)
    }

    override func contentViewHeight() -> CGFloat {
        190 + CGFloat(model.items.count)*46 + view.safeAreaInsets.bottom
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureModel()
        configureHierarchy()
    }
}

extension ConfirmPaymentViewController {
    private func configureModel() {
        model.dataSourceDidChange = { [weak self] in
            self?.balanceView.reloadData()
            self?.tableView.reloadData()
        }
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        presentationController?.delegate = self

        balanceView = BalanceView()
        balanceView.dataSource = model
        balanceView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(balanceView)

        tableView = DWIntrinsicTableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.preservesSuperviewLayoutMargins = true
        tableView.isScrollEnabled = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = UIColor.dw_secondaryBackground()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.layoutMargins = view.layoutMargins
        tableView.registerClass(for: TitleValueCell.self)
        tableView.tableHeaderView = EmptyView(frame: .init(x: 0, y: 0, width: 1, height: CGFloat.leastNonzeroMagnitude))
        tableView.tableFooterView = EmptyView(frame: .init(x: 0, y: 0, width: 1, height: CGFloat.leastNonzeroMagnitude))
        view.addSubview(tableView)

        let bottomButtonsStack = UIStackView()
        bottomButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonsStack.axis = .horizontal
        bottomButtonsStack.spacing = 10
        bottomButtonsStack.distribution = .fillEqually
        view.addSubview(bottomButtonsStack)

        let cancelButton = GrayButton()
        cancelButton.addAction(.touchUpInside) { [weak self] _ in
            guard let self else { return }

            self.dismiss(animated: true)
            self.delegate?.confirmPaymentViewControllerDidCancel(self)
        }

        cancelButton.setTitle(NSLocalizedString("Cancel", comment: "Payment confirmation"), for: .normal)
        bottomButtonsStack.addArrangedSubview(cancelButton)

        confirmButton = ActionButton()
        confirmButton.setTitle(NSLocalizedString("Confirm", comment: "Payment confirmation"), for: .normal)
        bottomButtonsStack.addArrangedSubview(confirmButton)

        NSLayoutConstraint.activate([
            balanceView.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: balanceView.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            bottomButtonsStack.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 30),
            bottomButtonsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -15),
            bottomButtonsStack.heightAnchor.constraint(equalToConstant: 46),
            bottomButtonsStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            bottomButtonsStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension ConfirmPaymentViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = model.items[indexPath.row]

        let cell = tableView.dequeueReusableCell(type: TitleValueCell.self, for: indexPath)
        cell.update(with: item)
        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.items.count
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        nil
    }

    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNonzeroMagnitude
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        CGFloat.leastNonzeroMagnitude
    }
}

// MARK: UIAdaptivePresentationControllerDelegate

extension ConfirmPaymentViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        delegate?.confirmPaymentViewControllerDidCancel(self)
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        true
    }
}
