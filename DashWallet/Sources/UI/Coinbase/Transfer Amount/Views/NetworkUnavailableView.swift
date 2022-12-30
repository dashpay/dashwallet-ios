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

final class NetworkUnavailableView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)

        let mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.alignment = .center
        mainStackView.spacing = 15
        addSubview(mainStackView)

        let icon = UIImageView(image: UIImage(named: "network.unavailable"))
        mainStackView.addArrangedSubview(icon)

        let textStackView = UIStackView()
        textStackView.axis = .vertical
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        textStackView.alignment = .center
        textStackView.spacing = 7
        mainStackView.addArrangedSubview(textStackView)

        let title = UILabel()
        title.font = .dw_font(forTextStyle: .body).withWeight(500)
        title.textColor = .dw_label()
        title.text = NSLocalizedString("Network Unavailable", comment: "Network Unavailable")
        textStackView.addArrangedSubview(title)

        let subtitle = UILabel()
        subtitle.font = .dw_font(forTextStyle: .footnote)
        subtitle.textColor = .dw_secondaryText()
        subtitle.text = NSLocalizedString("Please check your network connection", comment: "Network Unavailable")
        textStackView.addArrangedSubview(subtitle)

        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
