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

// MARK: - ConfirmOrderGeneralInfoCell

class ConfirmOrderGeneralInfoCell: UITableViewCell {
    var nameLabel: UILabel!
    var valueLabel: UILabel!

    func update(with item: ConfirmOrderItem, value: String) {
        nameLabel?.text = item.localizedTitle
        valueLabel?.text = value
    }

    internal func configureHierarchy() { }
}

// MARK: - ConfirmOrderAmountInDashCell

final class ConfirmOrderAmountInDashCell: ConfirmOrderGeneralInfoCell {
    var desciptionLabel: UILabel!

    override func update(with item: ConfirmOrderItem, value: String) {
        super.update(with: item, value: value)
    }
}
