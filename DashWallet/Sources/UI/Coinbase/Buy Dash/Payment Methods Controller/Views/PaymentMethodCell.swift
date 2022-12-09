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

final class PaymentMethodCell: UITableViewCell {
    @IBOutlet var paymentIconView: UIImageView!
    @IBOutlet var paymentTypeLabel: UILabel!
    @IBOutlet var paymentNameLabel: UILabel!
    @IBOutlet var checkboxButton: UIButton!

    func update(with paymentMethod: CoinbasePaymentMethod) { }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        checkboxButton.isSelected = selected
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        checkboxButton.isUserInteractionEnabled = false
    }
}
