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
import SQLite

@objc class ExploreOnlineMerchantViewController: ExploreMerchantViewController {
    
    @objc public var payWithDashHandler: (()->())?
    
    private var containerView: UIStackView!
    private var logoImageView: UIImageView!
    private var nameLabel: UILabel!
    private var subLabel: UILabel!
    private var addressLabel: UILabel!
    
    @objc func payAction() {
        payWithDashHandler?()
    }
    
    @objc func callAction() {
        guard let phone = merchant.phone else { return }
        
        let fixedPhone = phone.replacingOccurrences(of: " ", with: "")
        
        guard let url = URL(string: "telprompt://\(fixedPhone)") else { return }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @objc func websiteAction() {
        guard let website = merchant.website, let url = URL(string: website) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
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
        subLabel.text = "Online Merchant"
        subLabel.textColor = .dw_secondaryText()
        subStackView.addArrangedSubview(subLabel)
        
        let imageSize: CGFloat = 50
        
        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: imageSize),
            logoImageView.heightAnchor.constraint(equalToConstant: imageSize),
        ])
    }
    
    override func configureHierarchy() {
        containerView = UIStackView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.spacing = 20
        containerView.axis = .vertical
        view.addSubview(containerView)
        
        configureHeaderView()
        
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
        callButton.setTitle(NSLocalizedString("Website", comment: "Website"), for: .normal)
        callButton.setImage(UIImage(systemName: "safari.fill", withConfiguration: largeConfig), for: .normal)
        callButton.addTarget(self, action: #selector(websiteAction), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(callButton)
        
        containerView.addArrangedSubview(UIView())
        
        let payButton = DWActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        payButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        containerView.addArrangedSubview(payButton)
        
        if case let .merchant(m) = merchant.category {
            if m.paymentMethod == .giftCard {
                payButton.setTitle(NSLocalizedString("Buy a Gift Card", comment: "Buy a Gift Card"), for: .normal)
                payButton.setImage(UIImage(named: "image.explore.dash.gift-card"), for: .normal)
                payButton.accentColor = .dw_orange()
            }else{
                payButton.setTitle(NSLocalizedString("Pay with Dash", comment: "Pay with Dash"), for: .normal)
                payButton.setImage(UIImage(named: "image.explore.dash.circle"), for: .normal)
            }
        }
        
        
        let padding: CGFloat = 15
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: padding),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
          
            buttonsStackView.heightAnchor.constraint(equalToConstant: 51),
            
            payButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

@objc class ExploreOfflineMerchantViewController: ExploreMerchantViewController {

    private var detailsView: MerchantDetailsView!
    private var isShowAllHidden: Bool
    private var mapView: ExploreMapView!
    
    public init(merchant: ExplorePointOfUse, isShowAllHidden: Bool = false) {
        
        self.isShowAllHidden = isShowAllHidden
        super.init(merchant: merchant)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func showAllLocations() {
        let vc = ExploreMerchantAllLocationsViewController()
        vc.model = .init(merchant: merchant)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    override func configureHierarchy() {
        mapView = ExploreMapView()
        mapView.show(merchants: [merchant])
        mapView.centerRadius = 5
        mapView.initialCenterLocation = .init(latitude: merchant.latitude!, longitude: merchant.longitude!)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)
        
        detailsView = MerchantDetailsView(merchant: merchant, isShowAllHidden: isShowAllHidden)
        detailsView.translatesAutoresizingMaskIntoConstraints = false
        detailsView.showAllLocationsActionBlock = { [weak self] in
            self?.showAllLocations()
        }
        view.addSubview(detailsView)
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            detailsView.heightAnchor.constraint(equalToConstant: 310),
            detailsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            detailsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            detailsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: mapView.frame.height - 310, right: 0)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

@objc class ExploreMerchantViewController: UIViewController {
    internal let merchant: ExplorePointOfUse
    
    public init(merchant: ExplorePointOfUse) {
        self.merchant = merchant
        super.init(nibName: nil, bundle: nil)
        
        configureHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    internal func configureHierarchy() {
        fatalError("must be overriden")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.dw_background()
        title = merchant.name
    }
}

