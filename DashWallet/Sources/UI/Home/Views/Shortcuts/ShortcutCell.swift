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

class ShortcutCell: UICollectionViewCell {

    @IBOutlet private weak var centeredView: UIView!
    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!

    private var gradientLayer: CAGradientLayer?

    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.font = UIFont.dw_font(forTextStyle: .caption2)
        centeredView.backgroundColor = .clear
    }

    var model: ShortcutAction! {
        didSet {
            titleLabel.text = model.title
            titleLabel.textColor = model.textColor
            iconImageView.image = model.icon
            gradientLayer?.isHidden = model.showsGradientLayer
            let alpha = model.alpha
            titleLabel.alpha = alpha
            iconImageView.alpha = alpha
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard model.enabled == true else { return }
            dw_pressedAnimation(.heavy, pressed: isHighlighted)
        }
    }
}

