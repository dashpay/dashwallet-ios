//
//  Created by Andrei Ashikhmin
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

final class FromLabel: UIStackView {
    private var icon = ""
    private var text = ""
    private var balanceLabel: UILabel!

    public var balanceText = "" {
        didSet {
            balanceLabel.text = balanceText
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: FromLabel.noIntrinsicMetric, height: 40)
    }

    init(icon: String, text: String) {
        super.init(frame: .zero)

        self.icon = icon
        self.text = text

        configureHierarchy()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    private func configureHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        spacing = 10
        axis = .horizontal

        let iconView = UIImageView(image: UIImage(named: icon))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        addArrangedSubview(iconView)

        let vertical = UIStackView()
        vertical.translatesAutoresizingMaskIntoConstraints = false
        vertical.axis = .vertical
        addArrangedSubview(vertical)

        let fromLabel = UILabel()
        fromLabel.textColor = .dw_label()
        fromLabel.font = .dw_regularFont(ofSize: 14)
        fromLabel.text = NSLocalizedString(text, comment: "CrowdNode")
        vertical.addArrangedSubview(fromLabel)

        balanceLabel = UILabel()
        balanceLabel.textColor = .dw_tertiaryText()
        balanceLabel.font = .systemFont(ofSize: 12)
        vertical.addArrangedSubview(balanceLabel)
    }
}
