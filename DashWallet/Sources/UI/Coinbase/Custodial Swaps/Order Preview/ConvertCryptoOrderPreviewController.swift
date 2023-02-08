//
//  Created by tkhp
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

// MARK: - ConvertCryptoOrderItem

enum ConvertCryptoOrderItem: PreviewOrderItem {
    case origin
    case destination
    case purchaseAmount
    case feeAmount
    case totalAmount

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
        case .origin:
            return NSLocalizedString("You send", comment: "Coinbase")
        case .destination:
            return NSLocalizedString("You receive", comment: "Coinbase")
        case .purchaseAmount:
            return NSLocalizedString("Purchase", comment: "Coinbase/Buy Dash")
        case .feeAmount:
            return NSLocalizedString("Coinbase Fee", comment: "Coinbase/Buy Dash")
        case .totalAmount:
            return NSLocalizedString("Total", comment: "Coinbase/Buy Dash")
        }
    }

    var localizedDescription: String? {
        switch self {
        case .origin:
            return NSLocalizedString("from your Coinbase account", comment: "Coinbase")
        case .destination:
            return NSLocalizedString("to Dash Wallet on this device", comment: "Coinbase")
        default:
            return nil
        }
    }

    var cellIdentifier: String {
        if self == .origin || self == .destination {
            return ConvertCryptoOrderPreviewSourceCell.reuseIdentifier
        } else {
            return ConfirmOrderGeneralInfoCell.reuseIdentifier
        }
    }

    var isInfoButtonHidden: Bool {
        self != .feeAmount
    }
}

// MARK: - ConvertCryptoOrderPreviewController

final class ConvertCryptoOrderPreviewController: OrderPreviewViewController {

    private let items: [ConvertCryptoOrderItem] = [.origin, .destination, .purchaseAmount, .feeAmount, .totalAmount]

    init(selectedAccount: CBAccount, plainAmount: UInt64, order: CoinbaseSwapeTrade) {
        super.init(nibName: nil, bundle: nil)

        model = ConvertCryptoOrderPreviewModel(selectedAccount: selectedAccount, plainAmount: plainAmount, order: order)
        model.transactionDelegate = self
        configureModel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var convertCryptoOrderPreviewModel: ConvertCryptoOrderPreviewModel {
        model as! ConvertCryptoOrderPreviewModel
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        tableView.register(ConvertCryptoOrderPreviewSourceCell.self, forCellReuseIdentifier: ConvertCryptoOrderPreviewSourceCell.reuseIdentifier)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

extension ConvertCryptoOrderPreviewController {
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        let value = convertCryptoOrderPreviewModel.formattedValue(for: item)

        switch item {
        case .origin, .destination:
            let account = item == .origin ? convertCryptoOrderPreviewModel.selectedAccount : convertCryptoOrderPreviewModel.dashAccount
            let cell = tableView.dequeueReusableCell(type: ConvertCryptoOrderPreviewSourceCell.self, for: indexPath)
            cell.update(with: item, account: account, value: value)
            return cell
        default:
            let cell = tableView.dequeueReusableCell(type: ConfirmOrderGeneralInfoCell.self, for: indexPath)
            cell.selectionStyle = .none
            let value = convertCryptoOrderPreviewModel.formattedValue(for: item)
            cell.update(with: item, value: value)

            cell.infoHandle = { [weak self] in
                self?.feeInfoAction()
            }
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }
}
