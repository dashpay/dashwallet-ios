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

final class AppliedFiltersView: UIView {
    var filtersLabel: UILabel!

    override var intrinsicContentSize: CGSize {
        .init(width: AppliedFiltersView.noIntrinsicMetric, height: 46)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureHierarchy() {
        backgroundColor = .systemBackground

        let hairline = HairlineView(frame: .zero)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        let iconView = UIImageView(image: .init(systemName: "line.3.horizontal.decrease.circle.fill"))
        iconView.tintColor = .dw_dashBlue()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.axis = .vertical
        stackView.spacing = 2
        addSubview(stackView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = NSLocalizedString("Filtered by:", comment: "Explore Dash/Merchants/Filters")
        titleLabel.font = .dw_font(forTextStyle: .footnote)
        stackView.addArrangedSubview(titleLabel)

        filtersLabel = UILabel()
        filtersLabel.translatesAutoresizingMaskIntoConstraints = false
        filtersLabel.textAlignment = .center
        filtersLabel.font = .dw_font(forTextStyle: .footnote)
        stackView.addArrangedSubview(filtersLabel)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -48),
        ])
    }
}
