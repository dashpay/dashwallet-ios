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

final class KeyboardHeader: UIView {
    private var icon = ""
    private var text = ""

    override var intrinsicContentSize: CGSize {
        CGSize(width: KeyboardHeader.noIntrinsicMetric, height: 56)
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

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    private func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 8
        addSubview(stackView)

        let icon = UIImageView(image: UIImage(named: icon))
        icon.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(icon)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .dw_label()
        label.font = .dw_regularFont(ofSize: 14)
        label.text = NSLocalizedString(text, comment: "CrowdNode")
        stackView.addArrangedSubview(label)

        let hairline = HairlineView(frame: .zero)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
        ])
    }
}
