//  
//  Created by tkhp, Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

class CrowdNodeAPYView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        addCrowdNodeAPYLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 24.0)
    }

    private func addCrowdNodeAPYLabel() {
        let systemGreen = UIColor(red: 98.0 / 255.0, green: 182.0 / 255.0, blue: 125.0 / 255.0, alpha: 1.0)

        let apyStackView = UIStackView()
        apyStackView.translatesAutoresizingMaskIntoConstraints = false
        apyStackView.axis = .horizontal
        apyStackView.spacing = 4
        apyStackView.backgroundColor = systemGreen.withAlphaComponent(0.1)
        apyStackView.layer.cornerRadius = 6.0
        apyStackView.layer.masksToBounds = true
        apyStackView.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        apyStackView.isLayoutMarginsRelativeArrangement = true
        addSubview(apyStackView)

        let iconImageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
        iconImageView.contentMode = .center
        iconImageView.image = UIImage(named: "image.crowdnode.apy")
        apyStackView.addArrangedSubview(iconImageView)

        let apiLabel = UILabel()
        apiLabel.textColor = systemGreen
        apiLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        apiLabel.text = String.localizedStringWithFormat(NSLocalizedString("Current APY = %@", comment: "CrowdNode"), apy)
        apyStackView.addArrangedSubview(apiLabel)

        NSLayoutConstraint.activate([
            apyStackView.topAnchor.constraint(equalTo: topAnchor),
            apyStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            apyStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            apyStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            apyStackView.heightAnchor.constraint(equalToConstant: 24.0)
        ])
    }

    private var apy: String {
        let apyValue = CrowdNode.shared.crowdnodeAPY

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .percent
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.multiplier = 1
        return numberFormatter.string(from: NSNumber(value: apyValue)) ?? ""
    }
}
