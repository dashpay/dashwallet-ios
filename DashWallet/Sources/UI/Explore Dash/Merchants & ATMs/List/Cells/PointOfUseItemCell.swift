//
//  Created by Pavel Tikhonenko
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

import CoreLocation
import UIKit

#if DEBUG
import SwiftUI
#endif

private let kReuseIdentifier = "PointOfUseItemCell"

// MARK: - PointOfUseItemCell

class PointOfUseItemCell: UITableViewCell {
    private var logoImageView: UIImageView!
    private var nameLabel: UILabel!
    var subLabel: UILabel!
    var mainStackView: UIStackView!
    var searchCenterCoordinate: CLLocationCoordinate2D?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with pointOfUse: ExplorePointOfUse) {
        nameLabel.text = pointOfUse.name

        if let urlString = pointOfUse.logoLocation, let url = URL(string: urlString) {
            logoImageView.sd_setImage(with: url)
        } else {
            logoImageView.image = UIImage(named: pointOfUse.emptyLogoImageName)
        }
    }

    override class var reuseIdentifier: String {
        kReuseIdentifier
    }
}

extension PointOfUseItemCell {
    @objc
    func configureHierarchy() {
        mainStackView = UIStackView()
        mainStackView.axis = .horizontal
        mainStackView.spacing = 15
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.alignment = .center
        contentView.addSubview(mainStackView)

        logoImageView = UIImageView(image: UIImage(named: "image.explore.dash.wts.item.logo.empty"))
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.layer.cornerRadius = 8.0
        logoImageView.layer.masksToBounds = true
        mainStackView.addArrangedSubview(logoImageView)

        let textStackView = UIStackView()
        textStackView.axis = .vertical
        textStackView.spacing = 2
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.addArrangedSubview(textStackView)

        nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        textStackView.addArrangedSubview(nameLabel)

        subLabel = UILabel()
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.font = UIFont.systemFont(ofSize: 11)
        subLabel.textColor = .dw_secondaryText()
        subLabel.isHidden = true
        textStackView.addArrangedSubview(subLabel)

        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 36),
            logoImageView.heightAnchor.constraint(equalToConstant: 36),

            mainStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
}

// MARK: - Previews

#if DEBUG

extension ExplorePointOfUse {
    static func previewMock(
        name: String = "Merchant",
        logoLocation: String? = nil,
        paymentMethod: Merchant.PaymentMethod = .dash,
        type: Merchant.`Type` = .onlineAndPhysical,
        savingsBasisPoints: Int = 0,
        giftCardProviders: [Merchant.GiftCardProviderInfo] = []
    ) -> ExplorePointOfUse {
        ExplorePointOfUse(
            id: 1,
            name: name,
            category: .merchant(
                Merchant(
                    merchantId: "preview-id",
                    paymentMethod: paymentMethod,
                    type: type,
                    deeplink: nil,
                    savingsBasisPoints: savingsBasisPoints,
                    denominationsType: nil,
                    denominations: [],
                    redeemType: nil,
                    giftCardProviders: giftCardProviders
                )
            ),
            active: true,
            city: nil,
            territory: nil,
            address1: nil,
            address2: nil,
            address3: nil,
            address4: nil,
            latitude: nil,
            longitude: nil,
            website: nil,
            phone: nil,
            logoLocation: logoLocation,
            coverImage: nil,
            source: nil
        )
    }
}

private struct PointOfUseItemCellRepresentable: UIViewRepresentable {
    let pointOfUse: ExplorePointOfUse

    func makeUIView(context: Context) -> UIView {
        let cell = PointOfUseItemCell(style: .default, reuseIdentifier: nil)
        cell.update(with: pointOfUse)
        return cell.contentView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview("With logo") {
    VStack {
        PointOfUseItemCellRepresentable(
            pointOfUse: .previewMock(
                name: "Test Merchant",
                logoLocation: "https://piggy.cards/image/catalog/piggycards/logo2023_mobile.png"
            )
        )
        .frame(width: 375, height: 60)
    }
    .background(Color(.systemBackground))
    .padding()
}

#Preview("Empty logo") {
    VStack {
        PointOfUseItemCellRepresentable(
            pointOfUse: .previewMock(
                name: "No Logo Merchant",
                logoLocation: nil
            )
        )
        .frame(width: 375, height: 60)
    }
    .background(Color(.systemBackground))
    .padding()
}

#endif
