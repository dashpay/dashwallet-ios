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

import UIKit
import MapKit

class MerchantDetailsView: UIView {
    var showAllLocationsActionBlock: (() -> ())?
    
    var containerView: UIStackView!
    var logoImageView: UIImageView!
    var nameLabel: UILabel!
    var subLabel: UILabel!
    var addressLabel: UILabel!
    
    private let merchant: Merchant
    private let isShowAllHidden: Bool
    
    init(merchant: Merchant, isShowAllHidden: Bool) {
        
        self.isShowAllHidden = isShowAllHidden
        self.merchant = merchant
        
        super.init(frame: .zero)
        
        configureHierarchy()
    }
        
    @objc func showAllLocationsAction() {
        showAllLocationsActionBlock?()
    }
    
    @objc func callAction() {
        guard let phone = merchant.phone else { return }
        
        let fixedPhone = phone.replacingOccurrences(of: " ", with: "")
        
        guard let url = URL(string: "telprompt://\(fixedPhone)") else { return }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @objc func directionAction() {
        guard let longitude = merchant.longitude, let latitude = merchant.latitude else { return }
        
        let coordinate = CLLocationCoordinate2DMake(latitude, longitude)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate, addressDictionary:nil))
        mapItem.name = merchant.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey : MKLaunchOptionsDirectionsModeDriving])
    }
    
    @objc func websiteAction() {
        guard let website = merchant.website, let url = URL(string: website) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @objc func payAction() {
        guard let deeplink = merchant.deeplink, let url = URL(string: deeplink) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension MerchantDetailsView {
    private func configureHeaderView() {
        let stackView = UIStackView()
        stackView.spacing = 10
        stackView.alignment = .center
        containerView.addArrangedSubview(stackView)
        
        logoImageView = UIImageView()
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.layer.cornerRadius = 25
        logoImageView.layer.masksToBounds = true
        stackView.addArrangedSubview(logoImageView)
        
        if let str = merchant.logoLocation, let url = URL(string: str)
        {
            logoImageView.sd_setImage(with: url, completed: nil)
        }else{
            logoImageView.image = UIImage(named: "image.explore.dash.wts.item.logo.empty")
        }
        
        let subStackView = UIStackView()
        subStackView.spacing = 0
        subStackView.axis = .vertical
        stackView.addArrangedSubview(subStackView)
        
        nameLabel = UILabel()
        nameLabel.text = merchant.name;
        nameLabel.font = .dw_font(forTextStyle: .headline)
        subStackView.addArrangedSubview(nameLabel)
        
        subLabel = UILabel()
        subLabel.font = .dw_font(forTextStyle: .footnote)
        
        if let currentLocation = DWLocationManager.shared.currentLocation, DWLocationManager.shared.isAuthorized {
            
            let distance = CLLocation(latitude: merchant.latitude!, longitude: merchant.longitude!).distance(from: currentLocation)
            subLabel.text = "\(App.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters))) · Physical Merchant"
        }else{
            subLabel.text = "Physical Merchant"
        }
        
        subLabel.textColor = .dw_secondaryText()
        subStackView.addArrangedSubview(subLabel)
        
        let imageSize: CGFloat = 50
        
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: imageSize),
            logoImageView.heightAnchor.constraint(equalToConstant: imageSize),
        ])
    }
    
    private func configureHierarchy() {
        clipsToBounds = false
        layer.masksToBounds = true
        layer.cornerRadius = 20.0
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        backgroundColor = UIColor.dw_background()
        
        containerView = UIStackView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.spacing = 20
        containerView.axis = .vertical
        addSubview(containerView)
        
        configureHeaderView()
        
        let addressStackView = UIStackView()
        addressStackView.translatesAutoresizingMaskIntoConstraints = false
        addressStackView.spacing = 5
        addressStackView.axis = .vertical
        containerView.addArrangedSubview(addressStackView)
        
        addressLabel = UILabel()
        addressLabel.font = .dw_font(forTextStyle: .body)
        addressLabel.textColor = .label
        addressLabel.numberOfLines = 0
        addressLabel.lineBreakMode = .byWordWrapping
        addressStackView.addArrangedSubview(addressLabel)
        
        if !isShowAllHidden
        {
            let showAllLocations = UIButton()
            showAllLocations.setTitle(NSLocalizedString("View all locations", comment: "View all locations"), for: .normal)
            showAllLocations.setTitleColor(.dw_dashBlue(), for: .normal)
            showAllLocations.contentHorizontalAlignment = .left
            showAllLocations.addTarget(self, action: #selector(showAllLocationsAction), for: .touchUpInside)
            addressStackView.addArrangedSubview(showAllLocations)
        }else{
            containerView.addArrangedSubview(UIView())
        }
        
        let buttonsStackView = UIStackView()
        buttonsStackView.distribution = .fillEqually
        buttonsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonsStackView.spacing = 8
        buttonsStackView.axis = .horizontal
        containerView.addArrangedSubview(buttonsStackView)
        
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)
        
        //TODO: refactor this piece of code
        var callButton = VerticalButton(frame: .zero)
        callButton.translatesAutoresizingMaskIntoConstraints = false
        callButton.setTitle(NSLocalizedString("Call", comment: "Call"), for: .normal)
        callButton.setImage(UIImage(systemName: "phone.circle.fill", withConfiguration: largeConfig), for: .normal)
        callButton.addTarget(self, action: #selector(callAction), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(callButton)
        
        callButton = VerticalButton(frame: .zero)
        callButton.translatesAutoresizingMaskIntoConstraints = false
        callButton.setTitle(NSLocalizedString("Direction", comment: "Direction"), for: .normal)
        callButton.setImage(UIImage(systemName: "arrow.triangle.turn.up.right.circle.fill", withConfiguration: largeConfig), for: .normal)
        callButton.addTarget(self, action: #selector(directionAction), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(callButton)
        
        callButton = VerticalButton(frame: .zero)
        callButton.translatesAutoresizingMaskIntoConstraints = false
        callButton.setTitle(NSLocalizedString("Website", comment: "Website"), for: .normal)
        callButton.setImage(UIImage(systemName: "safari.fill", withConfiguration: largeConfig), for: .normal)
        callButton.addTarget(self, action: #selector(websiteAction), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(callButton)
        
        let payButton = DWActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        payButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        containerView.addArrangedSubview(payButton)
        
        if merchant.paymentMethod == .giftCard {
            payButton.setTitle(NSLocalizedString("Buy a Gift Card", comment: "Buy a Gift Card"), for: .normal)
            payButton.setImage(UIImage(named: "image.explore.dash.gift-card"), for: .normal)
            payButton.accentColor = .dw_orange()
        }else{
            payButton.setTitle(NSLocalizedString("Pay with Dash", comment: "Pay with Dash"), for: .normal)
            payButton.setImage(UIImage(named: "image.explore.dash.circle"), for: .normal)
        }
        
        addressLabel.text = merchant.address1
        
        let padding: CGFloat = 15
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            
            buttonsStackView.heightAnchor.constraint(equalToConstant: 51),
            
            payButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
}

class VerticalButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        //TODO: create a color
        backgroundColor = UIColor(red: 0.961, green: 0.961, blue: 0.965, alpha: 1)
        imageView?.contentMode = .scaleAspectFit;
        layer.cornerRadius = 9
        setTitleColor(.dw_dashBlue(), for: .normal)
        titleLabel?.font = .dw_mediumFont(ofSize: 11)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.contentHorizontalAlignment = .left
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        centerVertically(padding: 3)
    }
}

extension UIButton {
    func centerVertically(padding: CGFloat = 6.0) {
        guard
            let imageViewSize = self.imageView?.frame.size,
            let titleLabelSize = self.titleLabel?.frame.size else {
                return
            }
        
        self.imageEdgeInsets = UIEdgeInsets(
            top: 0.0,
            left: 0.0,
            bottom: 20.0,
            right: -titleLabelSize.width
        )
        
        self.titleEdgeInsets = UIEdgeInsets(
            top: 14.0,
            left: -imageViewSize.width,
            bottom: -5.0,
            right: 0.0
        )
        
        self.contentEdgeInsets = UIEdgeInsets(
            top: 0.0,
            left: 0.0,
            bottom: -7.0,
            right: 0.0
        )
    }
}
