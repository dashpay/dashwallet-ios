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

enum ConfirmOrderItem: PreviewOrderItem {
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
            return .dw_font(forTextStyle: .subheadline).withWeight(UIFont.Weight.medium.rawValue)
        } else {
            return .dw_font(forTextStyle: .subheadline)
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

        return NSLocalizedString("You will receive %@ Dash on your Dash Wallet on this device. Please note that it can take up to 2-3 minutes to complete a transfer.",
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

final class ConfirmOrderController: OrderPreviewViewController {

    private let sections: [ConfirmOrderSection] = [.generalInfo, .amountIntDash]
    private let items: [[ConfirmOrderItem]] = [
        [.paymentMethod, .purchaseAmount, .feeAmount, .totalAmount],
        [.amountInDash],
    ]

    private var confirmationModel: ConfirmOrderModel {
        model as! ConfirmOrderModel
    }

    init(order: CoinbasePlaceBuyOrder, paymentMethod: CoinbasePaymentMethod, plainAmount: UInt64) {
        super.init(nibName: nil, bundle: nil)

        model = ConfirmOrderModel(order: order, paymentMethod: paymentMethod, plainAmount: plainAmount)
        model.transactionDelegate = self
        configureModel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        tableView.register(ConfirmOrderAmountInDashCell.self, forCellReuseIdentifier: ConfirmOrderAmountInDashCell.dw_reuseIdentifier)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

// MARK: UITableViewDataSource, UITableViewDelegate

extension ConfirmOrderController {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items[section].count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.section][indexPath.row]

        let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier, for: indexPath) as! ConfirmOrderGeneralInfoCell
        cell.selectionStyle = .none
        let value = confirmationModel.formattedValue(for: item)
        cell.update(with: item, value: value)

        cell.infoHandle = { [weak self] in
            self?.feeInfoAction()
        }
        return cell
    }
}
