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

// MARK: - TerritoriesListCurrentLocationCell

final class TerritoriesListCurrentLocationCell: UITableViewCell {
    @IBOutlet var iconView: UIImageView!
    @IBOutlet var label: UILabel!

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        let color: UIColor = selected ? .dw_dashBlue() : .label

        label.textColor = color
        iconView.tintColor = color

        accessoryType = selected ? .checkmark : .none
        tintColor = selected ? .dw_dashBlue() : .label
    }
}


// MARK: - TerritoriesListItemCell

final class TerritoriesListItemCell: UITableViewCell {
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        guard var configuration = contentConfiguration as? UIListContentConfiguration else { return }
        configuration.textProperties.color = selected ? .dw_dashBlue() : .label
        contentConfiguration = configuration

        accessoryType = selected ? .checkmark : .none
        tintColor = selected ? .dw_dashBlue() : .label
    }
}

