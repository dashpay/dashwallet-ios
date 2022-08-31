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

class AtmDetailsView: UIView {
    @objc public var payWithDashHandler: (()->())?
    @objc public var sellDashHandler: (()->())?
    
    var containerView: UIStackView!
    var logoImageView: UIImageView!
    
    var coverImageView: UIImageView!
    var nameLabel: UILabel!
    var subLabel: UILabel!
    var addressLabel: UILabel!
    
    private let merchant: ExplorePointOfUse
    
    init(merchant: ExplorePointOfUse) {
        self.merchant = merchant
        
        super.init(frame: .zero)
        
        configureHierarchy()
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
        payWithDashHandler?()
    }
    
    @objc func sellAction() {
        sellDashHandler?()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension AtmDetailsView {
    private func configureAtmHeaderView() {
        
        let headerContainerView = UIStackView()
        headerContainerView.translatesAutoresizingMaskIntoConstraints = false
        headerContainerView.spacing = 15
        headerContainerView.axis = .vertical
        containerView.addArrangedSubview(headerContainerView)
        
        let stackView = UIStackView()
        stackView.spacing = 10
        stackView.alignment = .center
        headerContainerView.addArrangedSubview(stackView)
        
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
        nameLabel.text = merchant.source;
        nameLabel.font = .dw_font(forTextStyle: .headline)
        subStackView.addArrangedSubview(nameLabel)
        
        subLabel = UILabel()
        subLabel.font = .dw_font(forTextStyle: .footnote)
        subLabel.textColor = .dw_secondaryText()
        subLabel.isHidden = true
        subStackView.addArrangedSubview(subLabel)
        
        let buttonsStackView = UIStackView()
        buttonsStackView.spacing = 5
        buttonsStackView.axis = .horizontal
        buttonsStackView.distribution = .fillEqually
        headerContainerView.addArrangedSubview(buttonsStackView)
        
        let payButton = DWActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        payButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        payButton.setTitle(NSLocalizedString("Buy Dash", comment: "Buy Dash"), for: .normal)
        payButton.accentColor = UIColor(red: 0.235, green: 0.722, blue: 0.471, alpha: 1)
        buttonsStackView.addArrangedSubview(payButton)
        
        if let atm = merchant.atm, (atm.type == .buySell || atm.type == .sell)
        {
            let sellButton = DWActionButton()
            sellButton.translatesAutoresizingMaskIntoConstraints = false
            sellButton.addTarget(self, action: #selector(sellAction), for: .touchUpInside)
            sellButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
            sellButton.setTitle(NSLocalizedString("Sell Dash", comment: "Buy Dash"), for: .normal)
            sellButton.accentColor = .dw_dashBlue()
            buttonsStackView.addArrangedSubview(sellButton)
        }
        
        
        
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .black.withAlphaComponent(0.3)
        containerView.addArrangedSubview(separator)
        
        let imageSize: CGFloat = 50
        let buttonHeight: CGFloat = 48
        
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: imageSize),
            logoImageView.heightAnchor.constraint(equalToConstant: imageSize),
            
            payButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            separator.heightAnchor.constraint(equalToConstant: 1/UIScreen.main.scale),
        ])
    }
        
    private func configureLocationBlock() {
        let stackView = UIStackView()
        stackView.spacing = 15
        stackView.alignment = .top
        stackView.axis = .horizontal
        containerView.addArrangedSubview(stackView)
        
        coverImageView = UIImageView()
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.layer.cornerRadius = 8
        coverImageView.layer.masksToBounds = true
        stackView.addArrangedSubview(coverImageView)
        
        if let str = merchant.coverImage, let url = URL(string: str)
        {
            coverImageView.sd_setImage(with: url, completed: nil)
        }else{
            coverImageView.isHidden = true
        }
        
        let locationInfoStackView = UIStackView()
        locationInfoStackView.spacing = 5
        locationInfoStackView.axis = .vertical
        
        stackView.addArrangedSubview(locationInfoStackView)
        
        let subStackView = UIStackView()
        subStackView.spacing = 2
        subStackView.axis = .vertical
        locationInfoStackView.addArrangedSubview(subStackView)
        
        let subLabel = UILabel()
        subLabel.font = .dw_font(forTextStyle: .footnote)
        subLabel.textColor = .dw_secondaryText()
        subLabel.text = NSLocalizedString("This ATM is located in the", comment: "This ATM is located in the")
        subStackView.addArrangedSubview(subLabel)
        
        let nameLabel = UILabel()
        nameLabel.text = merchant.name;
        nameLabel.font = .dw_font(forTextStyle: .headline)
        subStackView.addArrangedSubview(nameLabel)
        
        addressLabel = UILabel()
        addressLabel.font = .dw_font(forTextStyle: .body)
        addressLabel.textColor = .label
        addressLabel.numberOfLines = 0
        addressLabel.lineBreakMode = .byWordWrapping
        locationInfoStackView.addArrangedSubview(addressLabel)
     
        if let currentLocation = DWLocationManager.shared.currentLocation, DWLocationManager.shared.isAuthorized {
            let distanceStackView = UIStackView()
            distanceStackView.spacing = 5
            distanceStackView.axis = .horizontal
            locationInfoStackView.addArrangedSubview(distanceStackView)
            
            let iconImageView = UIImageView(image: .init(named: "image.explore.dash.distance"))
            distanceStackView.addArrangedSubview(iconImageView)
            
            let distance = CLLocation(latitude: merchant.latitude!, longitude: merchant.longitude!).distance(from: currentLocation)
            let subLabel = UILabel()
            subLabel.font = .dw_font(forTextStyle: .footnote)
            subLabel.textColor = .dw_secondaryText()
            subLabel.text = NSLocalizedString("This ATM is located in the", comment: "This ATM is located in the")
            distanceStackView.addArrangedSubview(subLabel)
            subLabel.text = "\(App.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters)))"
            
            distanceStackView.addArrangedSubview(UIView())
        }
        
        NSLayoutConstraint.activate([
            coverImageView.widthAnchor.constraint(equalToConstant: 88),
            coverImageView.heightAnchor.constraint(equalToConstant: 50),
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
        
        configureAtmHeaderView()
        configureLocationBlock()
        
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
        
    
        addressLabel.text = merchant.address1
        
        let padding: CGFloat = 15
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            
            buttonsStackView.heightAnchor.constraint(equalToConstant: 51),
        
        ])
    }
}


class SeparatorView: UIView {
    @IBInspectable var separatorColor: UIColor = .separator
    
    func drawHairline(in context: CGContext, scale: CGFloat, color: CGColor) {
        
        let center: CGFloat
        if Int(scale) % 2 == 0 {
            center = 1/(scale * 2)
        } else {
            center = 0
        }
        
        let offset = 0.5 - center
        let p1 = CGPoint(x: offset, y: offset)
        let p2 = CGPoint(x: offset, y: offset)
        
        let width = 1/scale
        context.setLineWidth(width)
        context.setStrokeColor(color)
        context.beginPath()
        context.move(to: p1)
        context.addLine(to: p2)
        context.strokePath()
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        drawHairline(in: context!, scale: UIScreen.main.scale, color: UIColor.separator.cgColor)
    }
}

