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
import CoreLocation

// MARK: - PointOfUseDetailsView

class PointOfUseDetailsView: UIView, SyncingActivityMonitorObserver, NetworkReachabilityHandling, DWLocationObserver {
    private var disposeBag = Set<AnyCancellable>()
    private let ctxSpendService = CTXSpendService.shared
    private let syncMonitor = SyncingActivityMonitor.shared
    private var grabberContainer: UIView!

    // NetworkReachabilityHandling requirements
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!

    public var payWithDashHandler: (()->())?
    public var sellDashHandler: (()->())?
    public var dashSpendAuthHandler: (()->())?
    public var buyGiftCardHandler: (()->())?
    public var showAllLocationsActionBlock: (() -> ())?
    public var infoButtonActionBlock: (() -> ())? // For parent view controller to handle info button tap

    var containerView: UIStackView!
    var headerContainerView: UIStackView!

    var logoImageView: UIImageView!

    var coverImageView: UIImageView!
    var nameLabel: UILabel!
    var subLabel: UILabel!
    private var payButton: ActionButton!
    private var addressTextLabel: UILabel!

    internal let merchant: ExplorePointOfUse
    internal var isShowAllHidden: Bool
    private let currentFilters: PointOfUseListFilters?
    private let currentMapBounds: ExploreMapBounds?
    private var locationCount: Int = 1

    private let emailLabel: UILabel = {
        let emailLabel = UILabel()
        emailLabel.translatesAutoresizingMaskIntoConstraints = false
        emailLabel.text = PointOfUseDetailsView.getEmailText()
        emailLabel.font = .dw_font(forTextStyle: .caption1) // Smaller font per Figma
        emailLabel.textColor = .dw_secondaryText()
        emailLabel.textAlignment = .left // Left align to prevent truncation

        return emailLabel
    }()

    private lazy var loginStatusView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        emailLabel.lineBreakMode = .byTruncatingHead

        let logoutButton = UIButton(type: .system)
        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.setTitle(NSLocalizedString("Log Out", comment: ""), for: .normal)
        logoutButton.titleLabel?.font = .dw_font(forTextStyle: .caption1) // Smaller font per Figma
        logoutButton.addTarget(self, action: #selector(logoutAction), for: .touchUpInside)

        if let buttonTitle = logoutButton.titleLabel, let titleText = buttonTitle.text {
            let attributeString = NSMutableAttributedString(string: titleText)
            attributeString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attributeString.length))
            attributeString.addAttribute(.foregroundColor, value: UIColor.dw_secondaryText(), range: NSRange(location: 0, length: attributeString.length))
            // Preserve the smaller font size in attributed string
            attributeString.addAttribute(.font, value: UIFont.dw_font(forTextStyle: .caption1), range: NSRange(location: 0, length: attributeString.length))
            logoutButton.setAttributedTitle(attributeString, for: .normal)
        }

        logoutButton.setTitleColor(.dw_secondaryText(), for: .normal)
        logoutButton.tintColor = .dw_secondaryText()

        view.addSubview(emailLabel)
        view.addSubview(logoutButton)

        NSLayoutConstraint.activate([
            emailLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // Align with CTX text, left aligned with merchant logo
            emailLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emailLabel.trailingAnchor.constraint(equalTo: logoutButton.leadingAnchor, constant: -8),

            logoutButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logoutButton.widthAnchor.constraint(lessThanOrEqualToConstant: 100),

            view.heightAnchor.constraint(equalToConstant: 20)
        ])

        return view
    }()

    public init(merchant: ExplorePointOfUse, isShowAllHidden: Bool = false, currentFilters: PointOfUseListFilters? = nil, currentMapBounds: ExploreMapBounds? = nil) {
        self.isShowAllHidden = isShowAllHidden
        self.merchant = merchant
        self.currentFilters = currentFilters
        self.currentMapBounds = currentMapBounds

        super.init(frame: .zero)

        configureHierarchy()
        configureObservers()

        // Fetch actual location count asynchronously
        fetchLocationCount()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        syncMonitor.remove(observer: self)
        DWLocationManager.shared.remove(observer: self)
        stopNetworkMonitoring()
    }

    @objc func callAction() {
        guard let phone = merchant.phone, !phone.isEmpty else { return }

        // Extract only digits for phone call
        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard !digits.isEmpty else { return }

        // Use telprompt: to directly open phone app (tel: shows options)
        let urlString = "telprompt:\(digits)"

        guard let url = URL(string: urlString) else {
            return
        }

        // Check if device can open the URL
        guard UIApplication.shared.canOpenURL(url) else {
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: { success in
        })
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
            if ctxSpendService.isUserSignedIn {
                buyGiftCardHandler?()
            } else {
                dashSpendAuthHandler?()
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
        // Set background color to match Figma design
        backgroundColor = UIColor(red: 0.961, green: 0.965, blue: 0.969, alpha: 1) // #f5f6f7

        // Add grabber at the very top
        addGrabber()

        containerView = UIStackView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.spacing = 16 // 16pt spacing as per Figma
        containerView.axis = .vertical
        addSubview(containerView)

        let padding: CGFloat = 20 // Figma shows 20pt horizontal padding
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 24), // Space for grabber (24pt height)
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor), // Fill entire view like search screen
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
        ])

        configureGiftCardSection()
        configureContactInfoSection()
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

        // Monitor location changes to update distance
        DWLocationManager.shared.add(observer: self)

        // Request location permission if needed
        if DWLocationManager.shared.needsAuthorization {
            DWLocationManager.shared.requestAuthorization()
        }

        // Initial refresh in case location is already available
        refreshSubtitle()
    }

    // MARK: - DWLocationObserver

    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        refreshSubtitle()
    }

    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) {
        // Not needed for distance calculation
    }

    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        refreshSubtitle()
    }
}

extension PointOfUseDetailsView {
    @objc internal func configureGiftCardSection() {
        guard case .merchant(let m) = merchant.category else { return }

        if m.paymentMethod == .giftCard {
            // Create gift card merchant layout
            configureGiftCardMerchantLayout(merchant: m)
        } else {
            // Create regular merchant layout
            configureRegularMerchantLayout(merchant: m)
        }
    }

    private func configureRegularMerchantLayout(merchant: ExplorePointOfUse.Merchant) {
        // Create simple header block for regular merchants
        let headerBlock = UIView()
        headerBlock.translatesAutoresizingMaskIntoConstraints = false
        headerBlock.backgroundColor = .white
        headerBlock.layer.cornerRadius = 12
        containerView.addArrangedSubview(headerBlock)

        let headerStack = UIStackView()
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.axis = .vertical
        headerStack.spacing = 16
        headerStack.distribution = .fill
        headerStack.alignment = .fill
        headerBlock.addSubview(headerStack)

        // Just header section for regular merchants
        let headerSection = createHeaderSection()
        headerStack.addArrangedSubview(headerSection)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: headerBlock.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: headerBlock.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: headerBlock.trailingAnchor, constant: -16),
            headerStack.bottomAnchor.constraint(equalTo: headerBlock.bottomAnchor, constant: -16)
        ])
    }

    private func configureGiftCardMerchantLayout(merchant: ExplorePointOfUse.Merchant) {
        // Create the first white block containing header + CTX + button + country notice
        let firstBlock = UIView()
        firstBlock.translatesAutoresizingMaskIntoConstraints = false
        firstBlock.backgroundColor = .white // Pure white as per Figma
        firstBlock.layer.cornerRadius = 12
        containerView.addArrangedSubview(firstBlock)

        let firstBlockStack = UIStackView()
        firstBlockStack.translatesAutoresizingMaskIntoConstraints = false
        firstBlockStack.axis = .vertical
        firstBlockStack.spacing = 16
        firstBlockStack.distribution = .fill
        firstBlockStack.alignment = .fill
        firstBlock.addSubview(firstBlockStack)

        // Header section (logo + name + subtitle)
        let headerSection = createHeaderSection()
        firstBlockStack.addArrangedSubview(headerSection)

        // CTX section (no background/border)
        let ctxSection = createCTXSection(merchant: merchant)
        firstBlockStack.addArrangedSubview(ctxSection)

        // Country notice - MOVED ABOVE button as per new design
        let countryNotice = createCountryNotice()
        firstBlockStack.addArrangedSubview(countryNotice)

        // Gift card button
        payButton = ActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        payButton.setTitle(NSLocalizedString("Buy a gift card", comment: "Buy a gift card"), for: .normal)
        // Try the payment gift card icon that should match Figma
        payButton.setImage(UIImage(named: "gift-card-icon")?.withRenderingMode(.alwaysTemplate), for: .normal)
        payButton.accentColor = .dw_orange()

        // Configure icon size and text font
        payButton.titleLabel?.font = UIFont.systemFont(ofSize: 14) // 14px as per Figma
        if var buttonConfig = payButton.configuration {
            buttonConfig.imagePadding = 8 // Space between icon and text
            // Set preferred symbol configuration for proper size
            let imageConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            buttonConfig.preferredSymbolConfigurationForImage = imageConfig
            payButton.configuration = buttonConfig
        }
        firstBlockStack.addArrangedSubview(payButton)

        // Move existing login status to inside first block below button
        firstBlockStack.addArrangedSubview(loginStatusView)

        NSLayoutConstraint.activate([
            firstBlockStack.topAnchor.constraint(equalTo: firstBlock.topAnchor, constant: 16),
            firstBlockStack.leadingAnchor.constraint(equalTo: firstBlock.leadingAnchor, constant: 16),
            firstBlockStack.trailingAnchor.constraint(equalTo: firstBlock.trailingAnchor, constant: -16),
            firstBlockStack.bottomAnchor.constraint(equalTo: firstBlock.bottomAnchor, constant: -16),
            payButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        // Login status now added inside first block
        refreshLoginStatus()

        // Set initial button state
        updateButtonState()
    }

    @objc internal func configureContactInfoSection() {
        // Create second white block for contact information (Address, Phone, Website)
        let contactBlock = UIView()
        contactBlock.translatesAutoresizingMaskIntoConstraints = false
        contactBlock.backgroundColor = .white // Pure white as per Figma
        contactBlock.layer.cornerRadius = 12
        containerView.addArrangedSubview(contactBlock)

        let contactStack = UIStackView()
        contactStack.translatesAutoresizingMaskIntoConstraints = false
        contactStack.axis = .vertical
        contactStack.spacing = 0
        contactBlock.addSubview(contactStack)

        // Address with directions arrow and distance
        let fullAddress = buildFullAddress()
        if !fullAddress.isEmpty {
            let addressContainer = createAddressSection(address: fullAddress)
            contactStack.addArrangedSubview(addressContainer)
        }

        // Phone number as formatted US number
        if let phone = merchant.phone, !phone.isEmpty {
            let phoneContainer = createPhoneSection(phone: phone)
            contactStack.addArrangedSubview(phoneContainer)
        }

        // Website
        if let website = merchant.website, !website.isEmpty {
            let websiteContainer = createWebsiteSection(website: website)
            contactStack.addArrangedSubview(websiteContainer)
        }

        NSLayoutConstraint.activate([
            contactStack.topAnchor.constraint(equalTo: contactBlock.topAnchor, constant: 6),
            contactStack.leadingAnchor.constraint(equalTo: contactBlock.leadingAnchor, constant: 16),
            contactStack.trailingAnchor.constraint(equalTo: contactBlock.trailingAnchor, constant: -16),
            contactStack.bottomAnchor.constraint(equalTo: contactBlock.bottomAnchor, constant: -6)
        ])

        // Create "Show all locations" section with initial count, will be updated after fetch
        if !isShowAllHidden {
            createShowAllLocationsSection()
        }
    }

    private func createAddressSection(address: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 2

        let addressLabel = UILabel()
        addressLabel.text = NSLocalizedString("Address", comment: "Address")
        addressLabel.font = .dw_font(forTextStyle: .caption2)
        addressLabel.textColor = .dw_tertiaryText()

        addressTextLabel = UILabel()
        addressTextLabel.font = .systemFont(ofSize: 14, weight: .regular) // 14px regular as per Figma
        addressTextLabel.textColor = UIColor(red: 0.098, green: 0.110, blue: 0.122, alpha: 1) // #191c1f from Figma
        addressTextLabel.numberOfLines = 0
        addressTextLabel.lineBreakMode = .byWordWrapping

        // Add distance under address as requested
        let addressWithDistance = getAddressWithDistanceAttributedString(address: address)
        addressTextLabel.attributedText = addressWithDistance

        stackView.addArrangedSubview(addressLabel)
        stackView.addArrangedSubview(addressTextLabel)

        // Blue arrow icon for directions - only show for physical merchants
        let isOnlineMerchant = merchant.merchant?.type == .online

        if !isOnlineMerchant {
            let arrowButton = UIButton(type: .system)
            arrowButton.translatesAutoresizingMaskIntoConstraints = false
            arrowButton.setImage(UIImage(systemName: "arrow.triangle.turn.up.right.circle.fill"), for: .normal)
            arrowButton.tintColor = .dw_dashBlue()
            arrowButton.addTarget(self, action: #selector(directionAction), for: .touchUpInside)

            container.addSubview(stackView)
            container.addSubview(arrowButton)

            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
                stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
                stackView.trailingAnchor.constraint(equalTo: arrowButton.leadingAnchor, constant: -10),

                arrowButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                arrowButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                arrowButton.widthAnchor.constraint(equalToConstant: 22),
                arrowButton.heightAnchor.constraint(equalToConstant: 22)
            ])
        } else {
            // For online merchants, don't show arrow button
            container.addSubview(stackView)

            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
                stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
                stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6)
            ])
        }

        return container
    }

    private func createPhoneSection(phone: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 2

        let phoneLabel = UILabel()
        phoneLabel.text = NSLocalizedString("Phone", comment: "Phone")
        phoneLabel.font = .dw_font(forTextStyle: .caption2)
        phoneLabel.textColor = .dw_tertiaryText()

        let phoneButton = UIButton(type: .system)
        phoneButton.setTitle(formatPhoneNumber(phone), for: .normal)
        phoneButton.setTitleColor(UIColor(red: 0.0, green: 0.553, blue: 0.894, alpha: 1), for: .normal) // #008de4 from Figma
        phoneButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular) // 14px as per Figma
        phoneButton.contentHorizontalAlignment = .left
        phoneButton.addTarget(self, action: #selector(callAction), for: .touchUpInside)

        stackView.addArrangedSubview(phoneLabel)
        stackView.addArrangedSubview(phoneButton)

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 62) // Allow it to grow if needed
        ])

        return container
    }

    private func buildFullAddress() -> String {
        var addressComponents: [String] = []

        if let address1 = merchant.address1, !address1.isEmpty {
            addressComponents.append(address1)
        }

        // Build city, state line
        var cityStateLine = ""
        if let city = merchant.city, !city.isEmpty {
            cityStateLine = city
        }
        if let territory = merchant.territory, !territory.isEmpty {
            if !cityStateLine.isEmpty {
                cityStateLine += ", "
            }
            cityStateLine += territory
        }

        if !cityStateLine.isEmpty {
            addressComponents.append(cityStateLine)
        }

        return addressComponents.joined(separator: ", ")
    }

    private func getLocationCount() -> Int {
        return locationCount
    }

    private func fetchLocationCount() {
        // Debug logging for ALL merchants to help identify the issue
        if let merchantData = merchant.merchant {
        }

        // Debug the current filter radius being used
        let kMetersToMilesConversion: Double = 1609.34
        let filterRadius = currentFilters?.currentRadius ?? kDefaultRadius
        if let filterRadiusEnum = currentFilters?.radius {
        }

        // Debug location manager status

        // Fetch the actual location count from the data source
        // Use current map bounds if available (from map interaction), otherwise fall back to filter radius
        let userPoint = DWLocationManager.shared.isAuthorized ? DWLocationManager.shared.currentLocation?.coordinate : nil
        let bounds: ExploreMapBounds?

        if let mapBounds = currentMapBounds {
            // Use the current visible map bounds (when user has zoomed/panned the map)
            bounds = mapBounds
        } else if let userLocation = userPoint {
            // Fall back to filter radius approach when no map bounds available
            let radiusInMeters: Double = filterRadius
            let circle = MKCircle(center: userLocation, radius: radiusInMeters)
            bounds = ExploreMapBounds(rect: circle.boundingMapRect)
        } else {
            bounds = nil
        }

        // Use the exact same logic as AllMerchantLocationsDataProvider
        // Check location permissions and set bounds accordingly
        var finalBounds = bounds
        var finalUserPoint = userPoint

        if DWLocationManager.shared.isPermissionDenied || DWLocationManager.shared.needsAuthorization {
            // When location is denied/not authorized, fetch all locations globally (no bounds filter)
            finalBounds = nil
            finalUserPoint = nil
        } else if DWLocationManager.shared.isAuthorized && (bounds == nil || userPoint == nil) {
            // Location is authorized but current location not available yet, fetch all globally
            finalBounds = nil
            finalUserPoint = nil
        }

        // Debug final parameters being used
        if let userPoint = finalUserPoint {
        } else {
        }

        // Use the same call as AllMerchantLocationsDataProvider
        ExploreDash.shared.allLocations(for: merchant.pointOfUseId, in: finalBounds, userPoint: finalUserPoint) { [weak self] result in
            switch result {
            case .success(let paginationResult):
                DispatchQueue.main.async {
                    // allLocations already returns only locations for this merchant, so no filtering needed
                    // Filter only for active locations to match what "Show all locations" displays
                    let activeLocations = paginationResult.items.filter { $0.active }

                    // Debug logging
                    if let strongSelf = self {
                        let inactiveLocations = paginationResult.items.filter { !$0.active }
                    }

                    // Use the count of active locations (this should match what "Show all locations" shows)
                    let newCount = activeLocations.count
                    self?.locationCount = newCount
                    self?.updateShowAllLocationsButton()
                }
            case .failure(let error):
                // Log error but keep default count of 1
                DSLogger.log("Failed to fetch location count: \(error)")
                DispatchQueue.main.async {
                    // Set count to 1 as fallback when API fails
                    self?.locationCount = 1
                    self?.updateShowAllLocationsButton()
                }
            }
        }
    }

    private func updateShowAllLocationsButton() {
        // Find and update the "Show all locations" button text
        // This is called after the location count is fetched
        guard !isShowAllHidden, let containerView = containerView else {
            return
        }


        // Find the show all locations block (should be the last arranged subview)
        if let showAllBlock = containerView.arrangedSubviews.last {

            // Find the button within the block
            for (index, subview) in showAllBlock.subviews.enumerated() {
                if let button = subview as? UIButton {
                    let newTitle = String.localizedStringWithFormat(
                        NSLocalizedString("Show all locations (%d)", comment: "Show all locations with count"),
                        locationCount
                    )
                    button.setTitle(newTitle, for: .normal)
                    break
                }
            }
        } else {
        }
    }

    private func createShowAllLocationsSection() {
        guard !isShowAllHidden, let containerView = containerView else { return }

        let showAllBlock = UIView()
        showAllBlock.translatesAutoresizingMaskIntoConstraints = false
        showAllBlock.backgroundColor = .white // Pure white as per Figma
        showAllBlock.layer.cornerRadius = 12
        containerView.addArrangedSubview(showAllBlock)

        let showAllButton = UIButton()
        showAllButton.translatesAutoresizingMaskIntoConstraints = false
        showAllButton.setTitle(String.localizedStringWithFormat(NSLocalizedString("Show all locations (%d)", comment: "Show all locations with count"), locationCount), for: .normal)
        showAllButton.setTitleColor(.dw_label(), for: .normal)  // Black text
        showAllButton.titleLabel?.font = .dw_font(forTextStyle: .footnote)
        showAllButton.contentHorizontalAlignment = .left
        showAllButton.addTarget(self, action: #selector(showAllLocationsAction), for: .touchUpInside)

        // Add chevron arrow
        let chevronImage = UIImage(systemName: "chevron.right")
        let chevronImageView = UIImageView(image: chevronImage)
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.tintColor = .dw_tertiaryText()

        showAllBlock.addSubview(showAllButton)
        showAllBlock.addSubview(chevronImageView)

        NSLayoutConstraint.activate([
            showAllButton.topAnchor.constraint(equalTo: showAllBlock.topAnchor, constant: 14),
            showAllButton.leadingAnchor.constraint(equalTo: showAllBlock.leadingAnchor, constant: 10),
            showAllButton.bottomAnchor.constraint(equalTo: showAllBlock.bottomAnchor, constant: -14),
            showAllButton.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -10),

            chevronImageView.centerYAnchor.constraint(equalTo: showAllBlock.centerYAnchor),
            chevronImageView.trailingAnchor.constraint(equalTo: showAllBlock.trailingAnchor, constant: -10),
            chevronImageView.widthAnchor.constraint(equalToConstant: 8),
            chevronImageView.heightAnchor.constraint(equalToConstant: 13),

            showAllBlock.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func createWebsiteSection(website: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 2

        let websiteLabel = UILabel()
        websiteLabel.text = NSLocalizedString("Website", comment: "Website")
        websiteLabel.font = .dw_font(forTextStyle: .caption2)
        websiteLabel.textColor = .dw_tertiaryText()

        let websiteButton = UIButton(type: .system)
        // Show clean domain name instead of full URL
        let displayText = website.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        websiteButton.setTitle(displayText, for: .normal)
        websiteButton.setTitleColor(.dw_dashBlue(), for: .normal)
        websiteButton.titleLabel?.font = .dw_font(forTextStyle: .body)
        websiteButton.contentHorizontalAlignment = .left
        websiteButton.addTarget(self, action: #selector(websiteAction), for: .touchUpInside)

        stackView.addArrangedSubview(websiteLabel)
        stackView.addArrangedSubview(websiteButton)

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.heightAnchor.constraint(equalToConstant: 62)
        ])

        return container
    }

    private func formatPhoneNumber(_ phone: String) -> String {
        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        if digits.count == 10 {
            let areaCode = String(digits.prefix(3))
            let exchange = String(digits.dropFirst(3).prefix(3))
            let number = String(digits.suffix(4))
            return "+1 (\(areaCode)) \(exchange)-\(number)"
        } else if digits.count == 11 && digits.hasPrefix("1") {
            let areaCode = String(digits.dropFirst(1).prefix(3))
            let exchange = String(digits.dropFirst(4).prefix(3))
            let number = String(digits.suffix(4))
            return "+1 (\(areaCode)) \(exchange)-\(number)"
        }

        return phone
    }

    internal func createHeaderSection() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.spacing = 16
        stackView.alignment = .top // Changed from center to top to allow proper text layout
        stackView.distribution = .fill

        // Logo
        logoImageView = UIImageView()
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit // Prevent distortion
        logoImageView.layer.cornerRadius = 8
        logoImageView.layer.masksToBounds = true
        logoImageView.setContentHuggingPriority(.required, for: .horizontal) // Keep fixed size
        logoImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        if let logoLocation = merchant.logoLocation, !logoLocation.isEmpty, let url = URL(string: logoLocation) {
            logoImageView.sd_setImage(with: url, placeholderImage: UIImage(named: merchant.emptyLogoImageName))
        } else {
            logoImageView.image = UIImage(named: merchant.emptyLogoImageName)
        }

        // Text stack
        let textStack = UIStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal) // Allow expansion
        textStack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal) // Resist compression

        nameLabel = UILabel()
        nameLabel.text = merchant.name
        nameLabel.font = .dw_font(forTextStyle: .headline)
        nameLabel.textColor = .dw_label()
        nameLabel.numberOfLines = 0 // Allow multiple lines
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.setContentHuggingPriority(.required, for: .vertical)
        nameLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subLabel = UILabel()
        subLabel.text = subtitleWithDistance()
        subLabel.font = .dw_font(forTextStyle: .footnote)
        subLabel.textColor = .dw_secondaryText()
        subLabel.numberOfLines = 0 // Allow multiple lines
        subLabel.lineBreakMode = .byWordWrapping

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(subLabel)

        stackView.addArrangedSubview(logoImageView)
        stackView.addArrangedSubview(textStack)

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 50),
            logoImageView.heightAnchor.constraint(equalToConstant: 50),
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 60) // Ensure minimum height for header
        ])

        return container
    }

    private func createCTXSection(merchant: ExplorePointOfUse.Merchant) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 0

        // Left side - Text stack
        let leftStack = UIStackView()
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .vertical
        leftStack.spacing = 2
        leftStack.alignment = .leading

        let titleLabel = UILabel()
        titleLabel.text = "CTX"  // Hardcoded as per Figma design showing "PiggyCards"
        titleLabel.font = .dw_font(forTextStyle: .footnote)
        titleLabel.textColor = .dw_label()

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitleForCTX(merchant: merchant)
        subtitleLabel.font = .dw_font(forTextStyle: .caption2)  // Smaller text as per Figma
        subtitleLabel.textColor = self.merchant.active ? .dw_tertiaryText() : .dw_tertiaryText()

        leftStack.addArrangedSubview(titleLabel)
        leftStack.addArrangedSubview(subtitleLabel)

        // Spacer
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stackView.addArrangedSubview(leftStack)
        stackView.addArrangedSubview(spacer)

        // Right side - Discount (if applicable)
        if merchant.savingsBasisPoints > 0 {
            let discountLabel = UILabel()
            discountLabel.text = String(format: "-%.0f%%", merchant.toSavingPercentages())
            discountLabel.font = .dw_font(forTextStyle: .footnote)
            discountLabel.textColor = .dw_label()
            stackView.addArrangedSubview(discountLabel)
        }

        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            // CTX text should align with merchant logo
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func createCountryNotice() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let noticeLabel = UILabel()
        noticeLabel.translatesAutoresizingMaskIntoConstraints = false
        noticeLabel.text = NSLocalizedString("Note: This card works only in the United States.", comment: "DashSpend")
        noticeLabel.font = .dw_font(forTextStyle: .footnote)
        noticeLabel.textColor = .dw_secondaryText()
        noticeLabel.numberOfLines = 0
        noticeLabel.textAlignment = .center

        container.addSubview(noticeLabel)

        NSLayoutConstraint.activate([
            noticeLabel.topAnchor.constraint(equalTo: container.topAnchor),
            noticeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            noticeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            noticeLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
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

        // Check CTX API enabled status first, then fall back to local active status
        let isEnabled = m.enabled ?? merchant.active
        let isOnline = networkStatus == .online
        let isSynced = syncMonitor.state == .syncDone

        payButton.isEnabled = isEnabled && isOnline && isSynced
    }

    // MARK: - New Design Methods

    private func subtitleWithoutDistance() -> String? {
        switch merchant.category {
        case .merchant(let m):
            if m.type == .online {
                return NSLocalizedString("Online Merchant", comment: "Online Merchant")
            } else {
                return m.type == .onlineAndPhysical ? "Physical Merchant, Online" : "Physical Merchant"
            }
        case .atm:
            return nil
        case .unknown:
            return nil
        }
    }

    private func subtitleWithDistance() -> String? {
        let baseSubtitle = subtitleWithoutDistance()

        // Add distance similar to MerchantItemCell logic
        if let currentLocation = DWLocationManager.shared.currentLocation,
           DWLocationManager.shared.isAuthorized,
           let latitude = merchant.latitude,
           let longitude = merchant.longitude {

            // Don't show distance for online merchants
            switch merchant.category {
            case .merchant(let m) where m.type == .online:
                return baseSubtitle
            default:
                break
            }

            let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: currentLocation)
            let distanceText = ExploreDash.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters))

            if let base = baseSubtitle {
                return "\(base)\n\(distanceText)"
            } else {
                return distanceText
            }
        }

        return baseSubtitle
    }

    private func refreshSubtitle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Don't show distance under merchant name anymore - only under address
            self.subLabel.text = self.subtitleWithoutDistance()

            // Update address with distance
            if let addressTextLabel = self.addressTextLabel {
                let currentAddress = self.buildFullAddress()
                addressTextLabel.attributedText = self.getAddressWithDistanceAttributedString(address: currentAddress)
            }
        }
    }

    private func getAddressWithDistance(address: String) -> String {
        // Add distance under address if location is available
        if let currentLocation = DWLocationManager.shared.currentLocation,
           DWLocationManager.shared.isAuthorized,
           let latitude = merchant.latitude,
           let longitude = merchant.longitude {

            // Don't show distance for online merchants (using same logic as MerchantItemCell)
            if let merchantData = merchant.merchant, merchantData.type == .online {
                return address
            }

            let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: currentLocation)
            let distanceText = ExploreDash.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters))

            return "\(address)\n\(distanceText) away"
        }

        return address
    }

    private func getAddressWithDistanceAttributedString(address: String) -> NSAttributedString {
        // Create attributed string with proper font styling
        let addressAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor(red: 0.098, green: 0.110, blue: 0.122, alpha: 1)
        ]

        let distanceAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.dw_font(forTextStyle: .caption2),
            .foregroundColor: UIColor.dw_tertiaryText()
        ]

        let attributedString = NSMutableAttributedString(string: address, attributes: addressAttributes)

        // Add distance if location is available
        if let currentLocation = DWLocationManager.shared.currentLocation,
           DWLocationManager.shared.isAuthorized,
           let latitude = merchant.latitude,
           let longitude = merchant.longitude {

            // Don't show distance for online merchants
            if let merchantData = merchant.merchant, merchantData.type == .online {
                return attributedString
            }

            let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: currentLocation)
            let distanceText = ExploreDash.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters))

            let distanceString = NSAttributedString(string: "\n\(distanceText) away", attributes: distanceAttributes)
            attributedString.append(distanceString)
        }

        return attributedString
    }

    private func subtitleForCTX(merchant: ExplorePointOfUse.Merchant) -> String {
        // Check CTX API enabled status first, then fall back to local active status
        let isEnabled = merchant.enabled ?? self.merchant.active
        if !isEnabled {
            return NSLocalizedString("Temporarily unavailable", comment: "DashSpend")
        }

        // Comprehensive debug logging for merchant fields investigation
        if self.merchant.name.lowercased().contains("gamestop") || self.merchant.name.lowercased().contains("spotify") || self.merchant.name.lowercased().contains("buffalo") {
        }

        // Use denominationsType field to determine if amounts are fixed or flexible
        if let denominationsType = merchant.denominationsType {
            let lowercasedType = denominationsType.lowercased()

            // Debug denominationsType for GameStop specifically
            if self.merchant.name.lowercased().contains("gamestop") {
            }

            switch lowercasedType {
            case "fixed":
                if self.merchant.name.lowercased().contains("gamestop") {
                }
                return NSLocalizedString("Fixed amounts", comment: "DashSpend")
            case "flexible", "min-max":
                if self.merchant.name.lowercased().contains("gamestop") {
                }
                return NSLocalizedString("Flexible amounts", comment: "DashSpend")
            default:
                if self.merchant.name.lowercased().contains("gamestop") {
                }
                return NSLocalizedString("Fixed amounts", comment: "DashSpend")
            }
        }
        return NSLocalizedString("Fixed amounts", comment: "DashSpend")
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

    private func addGrabber() {
        grabberContainer = UIView()
        grabberContainer.translatesAutoresizingMaskIntoConstraints = false
        grabberContainer.backgroundColor = .dw_secondaryBackground()
        grabberContainer.layer.masksToBounds = true
        grabberContainer.layer.cornerRadius = 20
        grabberContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(grabberContainer)

        let grabber = UIView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = .dw_separatorLine() // Match search screen
        grabber.layer.cornerRadius = 2
        grabberContainer.addSubview(grabber)

        NSLayoutConstraint.activate([
            grabberContainer.topAnchor.constraint(equalTo: topAnchor),
            grabberContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            grabberContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            grabberContainer.heightAnchor.constraint(equalToConstant: 24), // Match search screen

            grabber.centerXAnchor.constraint(equalTo: grabberContainer.centerXAnchor),
            grabber.centerYAnchor.constraint(equalTo: grabberContainer.centerYAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 40), // Match search screen
            grabber.heightAnchor.constraint(equalToConstant: 4) // Match search screen
        ])
    }


    func setupGrabberPanGesture(target: Any, action: Selector) {
        guard let grabberContainer = grabberContainer else {
            return
        }
        let panRecognizer = UIPanGestureRecognizer(target: target, action: action)
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        grabberContainer.addGestureRecognizer(panRecognizer)
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
