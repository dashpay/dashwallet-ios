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
import Combine

// MARK: - PointOfUseDetailsView

class PointOfUseDetailsView: UIView, SyncingActivityMonitorObserver, NetworkReachabilityHandling {
    private var disposeBag = Set<AnyCancellable>()
    private let ctxSpendService = CTXSpendService.shared
    private let syncMonitor = SyncingActivityMonitor.shared
    
    // NetworkReachabilityHandling requirements
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!
    
    public var payWithDashHandler: (()->())?
    public var sellDashHandler: (()->())?
    public var dashSpendAuthHandler: ((GiftCardProvider)->())?
    public var buyGiftCardHandler: ((GiftCardProvider)->())?
    public var showAllLocationsActionBlock: (() -> ())?

    var containerView: UIStackView!
    var headerContainerView: UIStackView!
    var locationContainerView: UIStackView!

    var logoImageView: UIImageView!

    var coverImageView: UIImageView!
    var nameLabel: UILabel!
    var subLabel: UILabel!
    var addressLabel: UILabel!
    private var payButton: ActionButton!
    private var piggyCardsCheckbox: UISwitch?
    private var selectedProvider: GiftCardProvider = .piggyCards

    internal let merchant: ExplorePointOfUse
    internal var isShowAllHidden: Bool
    
    private let emailLabel: UILabel = {
        let emailLabel = UILabel()
        emailLabel.translatesAutoresizingMaskIntoConstraints = false
        emailLabel.text = getEmailText()
        emailLabel.font = .dw_font(forTextStyle: .footnote)
        emailLabel.textColor = .dw_secondaryText()
        emailLabel.textAlignment = .right
        
        return emailLabel
    }()
    
    private lazy var loginStatusView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        
        emailLabel.lineBreakMode = .byTruncatingHead
        
        let logoutButton = UIButton(type: .system)
        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.setTitle(NSLocalizedString("Log Out", comment: ""), for: .normal)
        logoutButton.addTarget(self, action: #selector(logoutAction), for: .touchUpInside)
        
        if let buttonTitle = logoutButton.titleLabel {
            let attributeString = NSMutableAttributedString(string: buttonTitle.text!)
            attributeString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
            attributeString.addAttribute(.foregroundColor, value: UIColor.dw_secondaryText(), range: NSRange(location: 0, length: attributeString.length))
            logoutButton.setAttributedTitle(attributeString, for: .normal)
        }
        
        logoutButton.setTitleColor(.dw_secondaryText(), for: .normal)
        logoutButton.tintColor = .dw_secondaryText()
        
        view.addSubview(emailLabel)
        view.addSubview(logoutButton)
        
        NSLayoutConstraint.activate([
            emailLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emailLabel.trailingAnchor.constraint(equalTo: logoutButton.leadingAnchor, constant: -8),
            
            logoutButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logoutButton.widthAnchor.constraint(lessThanOrEqualToConstant: 100),

            view.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        return view
    }()

    public init(merchant: ExplorePointOfUse, isShowAllHidden: Bool = false) {
        self.isShowAllHidden = isShowAllHidden
        self.merchant = merchant

        super.init(frame: .zero)

        configureHierarchy()
        configureObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        syncMonitor.remove(observer: self)
        stopNetworkMonitoring()
    }

    @objc
    func callAction() {
        guard let phone = merchant.phone, !phone.isEmpty else { return }
        guard let url = URL(string: "telprompt://\(phone)") else { return }

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
        } else if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            if selectedProvider.isUserSignedIn() {
                buyGiftCardHandler?(selectedProvider)
            } else {
                dashSpendAuthHandler?(selectedProvider)
            }
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

    private func configureObservers() {
        ctxSpendService.$isUserSignedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSignedIn in
                self?.refreshLoginStatus()
                self?.updateButtonState()
            }
            .store(in: &disposeBag)
        
        // Monitor network status
        networkStatusDidChange = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateButtonState()
            }
        }
        startNetworkMonitoring()
        
        // Monitor sync status
        syncMonitor.add(observer: self)
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
            logoImageView.image = UIImage(named: merchant.emptyLogoImageName)
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

        if let phone = merchant.phone, !phone.isEmpty {
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

        let button = VerticalButton()
        button.configuration?.buttonSize = .mini
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: icon, withConfiguration: largeConfig), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc
    internal func configureBottomButton() {
        // Add PiggyCards checkbox for CTXSpend merchants (temporary UI element)
        if case .merchant(let m) = merchant.category, m.paymentMethod == .giftCard {
            configurePiggyCardsCheckbox()
        }
        
        payButton = ActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        containerView.addArrangedSubview(payButton)
        containerView.addArrangedSubview(loginStatusView)
        refreshLoginStatus()

        if case .merchant(let m) = merchant.category {
            if m.paymentMethod == .giftCard {
                payButton.setTitle(NSLocalizedString("Buy a Gift Card", comment: "Buy a Gift Card"), for: .normal)
                payButton.setImage(UIImage(named: "image.explore.dash.gift-card"), for: .normal)
                payButton.accentColor = .dw_orange()

                if m.savingsBasisPoints > 0 {
                    let savingsTag = SavingsTagView()
                    savingsTag.backgroundColor = .clear
                    savingsTag.translatesAutoresizingMaskIntoConstraints = false
                    savingsTag.setText(String(format: NSLocalizedString("Save %.2f%%", comment: "DashSpend"), m.toSavingPercentages()))
                    containerView.addSubview(savingsTag)

                    NSLayoutConstraint.activate([
                        savingsTag.trailingAnchor.constraint(equalTo: payButton.trailingAnchor, constant: -30),
                        savingsTag.bottomAnchor.constraint(equalTo: payButton.topAnchor, constant: 13),
                        savingsTag.heightAnchor.constraint(equalToConstant: 26),
                    ])
                }
            } else {
                payButton.setTitle(NSLocalizedString("Pay with Dash", comment: "Pay with Dash"), for: .normal)
                payButton.setImage(UIImage(named: "image.explore.dash.circle"), for: .normal)
            }
        }

        NSLayoutConstraint.activate([
            payButton.heightAnchor.constraint(equalToConstant: 48),
        ])
        
        // Set initial button state
        updateButtonState()
    }
    
    private func configurePiggyCardsCheckbox() {
        // TODO: This is a temporary UI element for testing PiggyCards
        // Change to false to enable service selection
        
        let checkboxContainer = UIStackView()
        checkboxContainer.axis = .horizontal
        checkboxContainer.spacing = 8
        checkboxContainer.alignment = .center
        
        piggyCardsCheckbox = UISwitch()
        piggyCardsCheckbox?.isOn = true
        piggyCardsCheckbox?.addTarget(self, action: #selector(piggyCardsCheckboxTapped), for: .touchUpInside)
        
        let label = UILabel()
        label.text = "Open PiggyCards"
        label.font = .dw_font(forTextStyle: .footnote)
        label.textColor = .dw_secondaryText()
        
        checkboxContainer.addArrangedSubview(piggyCardsCheckbox!)
        checkboxContainer.addArrangedSubview(label)
        checkboxContainer.addArrangedSubview(UIView()) // Spacer
        
        containerView.addArrangedSubview(checkboxContainer)
    }
    
    @objc
    private func piggyCardsCheckboxTapped() {
        selectedProvider = piggyCardsCheckbox?.isOn == true ? .piggyCards : .ctx
    }
    
    private static func getEmailText() -> String {
        if let email = CTXSpendService.shared.userEmail, !email.isEmpty {
            let maskedEmail = maskEmail(email)
            return String.localizedStringWithFormat(NSLocalizedString("Logged in as %@", comment: "DashSpend"), maskedEmail)
        } else {
            return NSLocalizedString("Logged in", comment: "")
        }
    }
    
    private static func maskEmail(_ email: String) -> String {
        let components = email.components(separatedBy: "@")
        guard components.count == 2 else { return email }
        
        let username = components[0]
        let domain = components[1]
        
        if username.count <= 1 {
            return "******@\(domain)"
        }
        
        let firstChar = String(username.prefix(1))
        return "\(firstChar)******@\(domain)"
    }
    
    @objc
    func logoutAction() {
        ctxSpendService.logout()
        loginStatusView.isHidden = true
    }
    
    func refreshLoginStatus() {
        if ctxSpendService.isUserSignedIn,
            case .merchant(let m) = merchant.category,
            m.paymentMethod == .giftCard {
            emailLabel.text = PointOfUseDetailsView.getEmailText()
            loginStatusView.isHidden = false
        } else {
            loginStatusView.isHidden = true
        }
    }
    
    private func updateButtonState() {
        guard let payButton = payButton,
              case .merchant(let m) = merchant.category, 
              m.paymentMethod == .giftCard else {
            return
        }
        
        let isActive = merchant.active
        let isOnline = networkStatus == .online
        let isSynced = syncMonitor.state == .syncDone
        
        payButton.isEnabled = isActive && isOnline && isSynced
    }
}

// MARK: - SyncingActivityMonitorObserver

extension PointOfUseDetailsView {
    func syncingActivityMonitorProgressDidChange(_ progress: Double) { }
    
    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        DispatchQueue.main.async { [weak self] in
            self?.updateButtonState()
        }
    }
}

// MARK: - VerticalButton

final class VerticalButton: TintedButton {
    override func updateConfiguration() {
        super.updateConfiguration()

        guard let configuration else {
            return
        }

        var updatedConfiguration = configuration
        updatedConfiguration.imagePlacement = .top
        updatedConfiguration.titleAlignment = .center
        updatedConfiguration.imagePadding = 3
        self.configuration = updatedConfiguration
    }
}

// MARK: - SavingsTagView

final class SavingsTagView: UIView {
    private let label = UILabel()
    private let tailSize: CGFloat = 8
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = UIColor.dw_background()
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }
    
    func setText(_ text: String) {
        label.text = text
    }
    
    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        
        let mainRect = rect.inset(by: UIEdgeInsets(top: 0, left: tailSize, bottom: 0, right: 0))
        let roundedRect = UIBezierPath(roundedRect: mainRect, cornerRadius: 4)
        path.append(roundedRect)

        path.move(to: CGPoint(x: tailSize, y: 3))
        path.addLine(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: tailSize, y: rect.midY))
        path.close()
        
        UIColor.dw_label().withAlphaComponent(0.7).setFill()
        path.fill()
    }
}
