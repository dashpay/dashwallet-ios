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

// MARK: - PaymentMethodCell

final class PaymentMethodCell: UITableViewCell {
    @IBOutlet var paymentIconView: UIImageView!
    @IBOutlet var paymentTypeLabel: UILabel!
    @IBOutlet var paymentNameLabel: UILabel!
    @IBOutlet var checkboxButton: UIButton!

    func update(with paymentMethod: CoinbasePaymentMethod) {
        paymentIconView.image = UIImage(named: paymentMethod.icon)

        paymentTypeLabel.text = paymentMethod.type.displayString

        paymentNameLabel.text = paymentMethod.name
        paymentNameLabel.isHidden = !paymentMethod.type.showNameLabel
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        checkboxButton.isSelected = selected
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        paymentIconView.layer.cornerRadius = 15
        checkboxButton.isUserInteractionEnabled = false
    }
}

extension CoinbasePaymentMethod {
    var icon: String {
        switch type {
        case .achBankAccount, .sepaBankAccount, .idealBankAccount, .bankWire, .eftBankAccount, .interac:
            return "coinbase.payment-method.bank.icon"
        case .fiatAccount:
            return "coinbase.payment-method.wallet.icon"
        case .creditCard, .secure3dCard:
            return "coinbase.payment-method.credit-card.icon"
        case .applePay:
            return "coinbase.payment-method.applepay.icon"
        case .googlePay:
            return "coinbase.payment-method.gpay.icon"
        case .payPal:
            return "coinbase.payment-method.paypal.icon"
        }
    }
}
