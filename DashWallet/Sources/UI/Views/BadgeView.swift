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

// MARK: - BadgeView

final class BadgeView: UIView {

    private(set) var label: UILabel!
    var text: String? {
        get { label.text }
        set {
            label.text = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var font: UIFont? {
        get { label.font }
        set { label.font = newValue }
    }

    var textColor: UIColor? {
        get { self.label.textColor }
        set { self.label.textColor = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupBadgeView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBadgeView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2.0
    }

    override var backgroundColor: UIColor? {
        didSet {
            label?.backgroundColor = backgroundColor
        }
    }

    private func setupBadgeView() {
        backgroundColor = .dw_tint()
        layer.masksToBounds = true
        isUserInteractionEnabled = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = backgroundColor
        label.font = UIFont.dw_font(forTextStyle: UIFont.TextStyle.caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor.dw_dashBlue()
        label.textAlignment = .center
        addSubview(label)
        self.label = label

        let verticalPadding: CGFloat = 5.0
        let horizontalPadding: CGFloat = 14.0

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: verticalPadding),
            trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: horizontalPadding),
        ])
    }
}

