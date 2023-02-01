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

import MapKit
import UIKit

// MARK: - PointOfUseDetailsView

class PointOfUseDetailsView: UIView {
    @objc public var payWithDashHandler: (()->())?
    @objc public var sellDashHandler: (()->())?
    @objc public var showAllLocationsActionBlock: (() -> ())?

    var containerView: UIStackView!
    var headerContainerView: UIStackView!
    var locationContainerView: UIStackView!

    var logoImageView: UIImageView!

    var coverImageView: UIImageView!
    var nameLabel: UILabel!
    var subLabel: UILabel!
    var addressLabel: UILabel!

    internal let merchant: ExplorePointOfUse
    internal var isShowAllHidden: Bool

    public init(merchant: ExplorePointOfUse, isShowAllHidden: Bool = false) {
        self.isShowAllHidden = isShowAllHidden
        self.merchant = merchant

        super.init(frame: .zero)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func callAction() {
        guard let phone = merchant.phone else { return }

        let fixedPhone = phone.replacingOccurrences(of: " ", with: "")

        guard let url = URL(string: "telprompt://\(fixedPhone)") else { return }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc
    func directionAction() {
        guard let longitude = merchant.longitude, let latitude = merchant.latitude else { return }

        let coordinate = CLLocationCoordinate2DMake(latitude, longitude)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate, addressDictionary:nil))
        mapItem.name = merchant.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey : MKLaunchOptionsDirectionsModeDriving])
    }

    @objc
    func showAllLocationsAction() {
        showAllLocationsActionBlock?()
    }

    @objc
    func websiteAction() {
        guard let website = merchant.website, let url = URL(string: website) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc
    func payAction() {
        if case .merchant(let m) = merchant.category, let deeplink = m.deeplink, let url = URL(string: deeplink),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            payWithDashHandler?()
        }
    }

    @objc
    func sellAction() {
        sellDashHandler?()
    }

    internal func configureHierarchy() {
        containerView = UIStackView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.spacing = 20
        containerView.axis = .vertical
        addSubview(containerView)

        let padding: CGFloat = 15
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
        ])

        configureHeaderView()
        configureLocationBlock()
        configureActionBlock()
        configureBottomButton()
    }
}

extension PointOfUseDetailsView {
    @objc
    internal func configureHeaderView() {
        headerContainerView = UIStackView()
        headerContainerView.translatesAutoresizingMaskIntoConstraints = false
        headerContainerView.spacing = 15
        headerContainerView.axis = .vertical
        containerView.addArrangedSubview(headerContainerView)

        let stackView = UIStackView()
        stackView.spacing = 10
        stackView.alignment = .center
        stackView.axis = .horizontal
        headerContainerView.addArrangedSubview(stackView)

        logoImageView = UIImageView()
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.layer.cornerRadius = 25
        logoImageView.layer.masksToBounds = true
        stackView.addArrangedSubview(logoImageView)

        if let str = merchant.logoLocation, let url = URL(string: str) {
            logoImageView.sd_setImage(with: url, completed: nil)
        } else {
            logoImageView.image = UIImage(named: "image.explore.dash.wts.item.logo.empty")
        }

        let subStackView = UIStackView()
        subStackView.spacing = 0
        subStackView.axis = .vertical
        stackView.addArrangedSubview(subStackView)

        nameLabel = UILabel()
        nameLabel.text = merchant.title
        nameLabel.font = .dw_font(forTextStyle: .headline)
        subStackView.addArrangedSubview(nameLabel)

        if let subtitle = merchant.subtitle {
            subLabel = UILabel()
            subLabel.font = .dw_font(forTextStyle: .footnote)
            subLabel.textColor = .dw_secondaryText()
            subLabel.text = subtitle
            subStackView.addArrangedSubview(subLabel)
        }

        let imageSize: CGFloat = 50
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: imageSize),
            logoImageView.heightAnchor.constraint(equalToConstant: imageSize),
        ])
    }

    @objc
    func configureLocationBlock() {
        locationContainerView = UIStackView()
        locationContainerView.translatesAutoresizingMaskIntoConstraints = false
        locationContainerView.spacing = 5
        locationContainerView.axis = .vertical
        containerView.addArrangedSubview(locationContainerView)

        addressLabel = UILabel()
        addressLabel.font = .dw_font(forTextStyle: .body)
        addressLabel.textColor = .dw_label()
        addressLabel.numberOfLines = 0
        addressLabel.lineBreakMode = .byWordWrapping
        addressLabel.text = merchant.address1
        locationContainerView.addArrangedSubview(addressLabel)

        if !isShowAllHidden {
            let showAllLocations = UIButton()
            showAllLocations.setTitle(NSLocalizedString("View all locations", comment: "View all locations"), for: .normal)
            showAllLocations.setTitleColor(.dw_dashBlue(), for: .normal)
            showAllLocations.contentHorizontalAlignment = .left
            showAllLocations.addTarget(self, action: #selector(showAllLocationsAction), for: .touchUpInside)
            locationContainerView.addArrangedSubview(showAllLocations)
        } else {
            containerView.addArrangedSubview(UIView())
        }
    }

    @objc
    func configureActionBlock() {
        let buttonsStackView = UIStackView()
        buttonsStackView.distribution = .fillEqually
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.spacing = 8
        buttonsStackView.axis = .horizontal
        containerView.addArrangedSubview(buttonsStackView)

        if merchant.phone != nil {
            let button = actionButton(title: NSLocalizedString("Call", comment: "Call"), icon: "phone.circle.fill",
                                      action: #selector(callAction))
            buttonsStackView.addArrangedSubview(button)
        }

        if merchant.showMap {
            let button = actionButton(title: NSLocalizedString("Direction", comment: "Direction"),
                                      icon: "arrow.triangle.turn.up.right.circle.fill", action: #selector(directionAction))
            buttonsStackView.addArrangedSubview(button)
        }

        if merchant.website != nil {
            let button = actionButton(title: NSLocalizedString("Website", comment: "Website"), icon: "safari.fill",
                                      action: #selector(websiteAction))
            buttonsStackView.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            buttonsStackView.heightAnchor.constraint(equalToConstant: 51),
        ])
    }

    private func actionButton(title: String, icon: String, action: Selector) -> UIButton {
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)

        let button = VerticalButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: icon, withConfiguration: largeConfig), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc
    internal func configureBottomButton() {
        let payButton = DWActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        payButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        containerView.addArrangedSubview(payButton)

        if case .merchant(let m) = merchant.category {
            if m.paymentMethod == .giftCard {
                payButton.setTitle(NSLocalizedString("Buy a Gift Card", comment: "Buy a Gift Card"), for: .normal)
                payButton.setImage(UIImage(named: "image.explore.dash.gift-card"), for: .normal)
                payButton.accentColor = .dw_orange()

                if let deeplink = m.deeplink, let url = URL(string: deeplink) {
                    payButton.isEnabled = UIApplication.shared.canOpenURL(url)
                } else {
                    payButton.isEnabled = false
                }

            } else {
                payButton.setTitle(NSLocalizedString("Pay with Dash", comment: "Pay with Dash"), for: .normal)
                payButton.setImage(UIImage(named: "image.explore.dash.circle"), for: .normal)
            }
        }

        NSLayoutConstraint.activate([
            payButton.heightAnchor.constraint(equalToConstant: 48),
        ])
    }
}

// MARK: - VerticalButton

class VerticalButton: DWTintedButton {
    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView?.contentMode = .scaleAspectFit;
        layer.cornerRadius = 9
        titleLabel?.font = .dw_mediumFont(ofSize: 11)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        contentHorizontalAlignment = .left
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        centerVertically(padding: 3)
    }
}

extension UIButton {
    func centerVertically(padding: CGFloat = 6.0) {
        guard let imageViewSize = imageView?.frame.size,
              let titleLabelSize = titleLabel?.frame.size else {
            return
        }

        imageEdgeInsets = UIEdgeInsets(top: 0.0,
                                       left: 0.0,
                                       bottom: 20.0,
                                       right: -titleLabelSize.width)

        titleEdgeInsets = UIEdgeInsets(top: 14.0,
                                       left: -imageViewSize.width,
                                       bottom: -5.0,
                                       right: 0.0)

        contentEdgeInsets = UIEdgeInsets(top: 0.0,
                                         left: 0.0,
                                         bottom: -7.0,
                                         right: 0.0)
    }
}
