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
import SwiftUI

// MARK: - PointOfUseDetailsViewController

class PointOfUseDetailsViewController: UIViewController {
    internal var pointOfUse: ExplorePointOfUse
    internal let isShowAllHidden: Bool
    private let currentFilters: PointOfUseListFilters?
    private let currentMapBounds: ExploreMapBounds?

    @objc public var payWithDashHandler: (()->())?
    @objc var sellDashHandler: (()->())?
    @objc var onGiftCardPurchased: ((Data)->())?

    private var contentView: UIView!
    private var detailsView: PointOfUseDetailsView!
    private var mapView: ExploreMapView!
    private var contentViewTopConstraint: NSLayoutConstraint?
    private var showMapButton: UIButton!

    public init(pointOfUse: ExplorePointOfUse, isShowAllHidden: Bool = true, currentFilters: PointOfUseListFilters? = nil, currentMapBounds: ExploreMapBounds? = nil) {
        self.pointOfUse = pointOfUse
        self.isShowAllHidden = isShowAllHidden
        self.currentFilters = currentFilters
        self.currentMapBounds = currentMapBounds

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Prevent crash when mapView or detailsView is nil
        if let mapView = mapView, let detailsView = detailsView {
            mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: mapView.frame.height - detailsView.frame.height - 10,
                                               right: 0)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pointOfUse.name
        setupInfoButton()
        configureHierarchy()
        refreshTokenAndMerchantInfo()
    }
}

extension PointOfUseDetailsViewController {
    private func setupInfoButton() {
        let infoImage = UIImage(systemName: "info.circle")?.withRenderingMode(.alwaysOriginal).withTintColor(.systemBlue)
        let infoButton = UIBarButtonItem(image: infoImage, style: .plain, target: self, action: #selector(infoButtonAction))
        navigationItem.rightBarButtonItem = infoButton
    }

    @objc
    func infoButtonAction() {
        let hostingController = UIHostingController(rootView: MerchantTypesDialog())
        hostingController.setDetent(640)
        present(hostingController, animated: true)
    }

    @objc
    func payAction() {
        payWithDashHandler?()
    }

    @objc
    func callAction() {
        guard let phone = pointOfUse.phone, !phone.isEmpty else { return }
        // Extract only digits for phone call
        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard !digits.isEmpty else { return }

        // Use telprompt: to directly open phone app (tel: shows options)
        let urlString = "telprompt:\(digits)"
        guard let url = URL(string: urlString) else { return }

        // Check if device can open the URL
        guard UIApplication.shared.canOpenURL(url) else { return }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc
    private func handlePanGesture(_ sender: UIPanGestureRecognizer) {
        print("DEBUG: Pan gesture triggered - state: \(sender.state.rawValue)")
        guard let contentViewTopConstraint = contentViewTopConstraint else {
            print("DEBUG: contentViewTopConstraint is nil!")
            return
        }

        let translatedPoint: CGPoint = sender.translation(in: view)
        let currentY = contentViewTopConstraint.constant

        switch sender.state {
        case .changed:
            // Only handle vertical movement and constrain within bounds
            let newY = currentY + translatedPoint.y

            // Constrain movement between closed position and maximum expanded position
            let screenHeight = view.frame.size.height
            let kDefaultClosedMapPosition = screenHeight * 0.75 // Mostly closed (more map visible)
            let kDefaultBottomHalfPosition = screenHeight * 0.35 // Default position to show content including button
            let kDefaultOpenedMapPosition = screenHeight * 0.2 // Mostly open (less map visible, more content)
            // Allow dragging between open position (top) and closed position (bottom)
            let maxY = kDefaultClosedMapPosition // Don't allow dragging below closed position
            let minY = kDefaultOpenedMapPosition // Don't allow dragging above open position

            contentViewTopConstraint.constant = max(minY, min(maxY, newY))
            sender.setTranslation(.zero, in: view)

        case .ended:
            let velocityInView = sender.velocity(in: view)
            let velocityY: CGFloat = velocityInView.y
            let finalCurrentY = contentViewTopConstraint.constant
            let screenHeight = view.frame.size.height
            let kDefaultClosedMapPosition = screenHeight * 0.75 // Mostly closed (more map visible)
            let kDefaultBottomHalfPosition = screenHeight * 0.35 // Default position to show content including button
            let kDefaultOpenedMapPosition = screenHeight * 0.2

            var finalY: CGFloat

            if velocityY > 300 {
                // Fast downward swipe - snap to closed position (more map visible)
                finalY = kDefaultClosedMapPosition
            } else if velocityY < -300 {
                // Fast upward swipe - snap to open position (less map visible)
                finalY = kDefaultOpenedMapPosition
            } else {
                // No strong velocity, snap to nearest position based on current position
                let midPoint1 = (kDefaultOpenedMapPosition + kDefaultBottomHalfPosition) / 2
                let midPoint2 = (kDefaultBottomHalfPosition + kDefaultClosedMapPosition) / 2

                if finalCurrentY < midPoint1 {
                    finalY = kDefaultOpenedMapPosition
                } else if finalCurrentY < midPoint2 {
                    finalY = kDefaultBottomHalfPosition
                } else {
                    finalY = kDefaultClosedMapPosition
                }
            }

            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseOut) {
                contentViewTopConstraint.constant = finalY
                self.view.layoutIfNeeded()
            } completion: { [weak self] _ in
                // Map button visibility update removed since button is removed
                // self?.updateMapButtonVisibility()
            }

        default:
            break
        }
    }

    @objc
    func websiteAction() {
        guard let website = pointOfUse.website else { return }

        // Normalize URL by adding https scheme if missing
        let normalizedWebsite: String
        if website.hasPrefix("http://") || website.hasPrefix("https://") {
            normalizedWebsite = website
        } else {
            normalizedWebsite = "https://" + website
        }

        guard let url = URL(string: normalizedWebsite) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func setupMapButton() {
        showMapButton = UIButton(type: .custom)
        showMapButton.translatesAutoresizingMaskIntoConstraints = false
        showMapButton.isHidden = true // Initially hidden
        showMapButton.tintColor = .white
        showMapButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        showMapButton.addTarget(self, action: #selector(showMapAction), for: .touchUpInside)
        showMapButton.setImage(UIImage(systemName: "map.fill"), for: .normal)
        showMapButton.setTitle(NSLocalizedString("Map", comment: ""), for: .normal)
        showMapButton.layer.masksToBounds = true
        showMapButton.layer.cornerRadius = 20
        showMapButton.layer.backgroundColor = UIColor.black.cgColor
        contentView.addSubview(showMapButton)

        let showMapButtonWidth: CGFloat = 92
        let showMapButtonHeight: CGFloat = 40

        NSLayoutConstraint.activate([
            showMapButton.widthAnchor.constraint(equalToConstant: showMapButtonWidth),
            showMapButton.heightAnchor.constraint(equalToConstant: showMapButtonHeight),
            showMapButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            showMapButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
        ])
    }

    @objc
    private func showMapAction() {
        // Animate to show more map (closed position)
        let kDefaultClosedMapPosition: CGFloat = 100.0
        guard let contentViewTopConstraint = contentViewTopConstraint else { return }

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseOut) {
            contentViewTopConstraint.constant = kDefaultClosedMapPosition
            self.view.layoutIfNeeded()
        }

        updateMapButtonVisibility()
    }

    private func updateMapButtonVisibility() {
        guard let contentViewTopConstraint = contentViewTopConstraint else { return }
        // Show map button when content is mostly expanded (less map visible)
        let shouldShow = contentViewTopConstraint.constant > 350
        showMapButton.isHidden = !shouldShow
    }

    private func showMapIfNeeded() {
        guard pointOfUse.showMap else { return }

        mapView = ExploreMapView()
        mapView.show(merchants: [pointOfUse])
        mapView.centerRadius = 1
        if let latitude = pointOfUse.latitude, let longitude = pointOfUse.longitude {
            mapView.initialCenterLocation = .init(latitude: latitude, longitude: longitude)
        }
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func prepareContentView() {
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        view.addSubview(contentView)

        let constraint: [NSLayoutConstraint]

        if pointOfUse.showMap {
            contentView.clipsToBounds = false
            contentView.layer.masksToBounds = true
            contentView.layer.cornerRadius = 20.0
            contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

            // Create the top constraint and store reference to it
            // Position to ensure "Show all locations" button is fully visible at bottom
            let screenHeight = UIScreen.main.bounds.height
            let kDefaultBottomHalfPosition = screenHeight * 0.35 // Position higher to show more content including button
            contentViewTopConstraint = contentView.topAnchor.constraint(equalTo: view.topAnchor, constant: kDefaultBottomHalfPosition)

            constraint = [
                contentViewTopConstraint!,
                contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ]
        } else {
            constraint = [
                contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ]
        }

        NSLayoutConstraint.activate(constraint)
    }

    private func showDetailsView() {
        guard let createdDetailsView = detailsView(for: pointOfUse) else {
            print("Warning: Failed to create detailsView for pointOfUse category: \(pointOfUse.category)")
            return
        }

        detailsView = createdDetailsView
        detailsView.payWithDashHandler = payWithDashHandler
        detailsView.sellDashHandler = sellDashHandler
        detailsView.showAllLocationsActionBlock = { [weak self] in
            guard let wSelf = self else { return }

            let vc = AllMerchantLocationsViewController(pointOfUse: wSelf.pointOfUse, currentFilters: wSelf.currentFilters, currentMapBounds: wSelf.currentMapBounds)
            vc.payWithDashHandler = wSelf.payWithDashHandler
            vc.sellDashHandler = wSelf.sellDashHandler
            wSelf.navigationController?.pushViewController(vc, animated: true)
        }
        detailsView.buyGiftCardHandler = { [weak self] in
            self?.showDashSpendPayScreen()
        }
        detailsView.dashSpendAuthHandler = { [weak self] in
            self?.showCTXSpendLoginInfo()
        }

        detailsView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailsView)

        NSLayoutConstraint.activate([
            detailsView.topAnchor.constraint(equalTo: contentView.topAnchor),
            // Remove bottom constraint to prevent compression - let content maintain natural height
            detailsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            detailsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        // Add pan gesture to handle grabber dragging - only for map view
        // Attach to specific grabber area, not entire view
        if pointOfUse.showMap {
            detailsView.setupGrabberPanGesture(target: self, action: #selector(handlePanGesture(_:)))
            // Map button removed as requested
            // setupMapButton()
        }
    }

    private func configureHierarchy() {
        showMapIfNeeded()
        prepareContentView()
        showDetailsView()
    }
}

extension PointOfUseDetailsViewController {
    func detailsView(for pointOfUse: ExplorePointOfUse) -> PointOfUseDetailsView? {
        switch pointOfUse.category {
        case .merchant:
            return PointOfUseDetailsView(merchant: pointOfUse, isShowAllHidden: isShowAllHidden, currentFilters: currentFilters, currentMapBounds: currentMapBounds)
        case .atm:
            return AtmDetailsView(merchant: pointOfUse, isShowAllHidden: isShowAllHidden)
        case .unknown:
            return nil
        }
    }
}


// Mark: DashSpend

extension PointOfUseDetailsViewController {
    private func showCTXSpendLoginInfo() {
        let swiftUIView = CTXSpendLoginInfoView(
            onCreateNewAccount: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.showCTXSpendTerms()
                }
            },
            onLogIn: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.showCTXSpendAuth(authType: .signIn)
                }
            },
            onTermsAndConditions: {
                UIApplication.shared.open(URL(string: CTXConstants.ctxGiftCardAgreementUrl)!, options: [:], completionHandler: nil)
            }
        )
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(450)
        self.present(hostingController, animated: true)
    }

    private func showCTXSpendTerms() {
        let hostingController = UIHostingController(
            rootView: CTXSpendTermsScreen {
                self.navigationController?.popToViewController(ofType: PointOfUseDetailsViewController.self, animated: false)
                self.showDashSpendPayScreen(justAuthenticated: true)
            }
        )
        hostingController.modalPresentationStyle = .fullScreen
        self.navigationController?.pushViewController(hostingController, animated: true)
    }

    private func showCTXSpendAuth(authType: CTXSpendUserAuthType) {
        let hostingController = UIHostingController(
            rootView: CTXSpendUserAuthScreen(authType: authType) {
                self.navigationController?.popViewController(animated: false)
                self.showDashSpendPayScreen(justAuthenticated: true)
            }
        )

        self.navigationController?.pushViewController(hostingController, animated: true)
    }

    private func showDashSpendPayScreen(justAuthenticated: Bool = false) {
        let hostingController = UIHostingController(
            rootView: DashSpendPayScreen(merchant: self.pointOfUse, justAuthenticated: justAuthenticated) { [weak self] txId in
                // Navigate back to home and show gift card details
                self?.onGiftCardPurchased?(txId)
            }
        )

        self.navigationController?.pushViewController(hostingController, animated: true)
    }

    private func refreshTokenAndMerchantInfo() {
        Task {
            if try await tryRefreshCtxToken(), let merchantId = pointOfUse.merchant?.merchantId {
                let merchantInfo = try await CTXSpendService.shared.getMerchant(merchantId: merchantId)

                // Debug logging for CTX merchant info
                if pointOfUse.name.lowercased().contains("buffalo") || pointOfUse.name.lowercased().contains("gamestop") {
                    print("🎯 CTX MERCHANT INFO DEBUG: \(pointOfUse.name)")
                    print("   CTX enabled: \(merchantInfo.enabled)")
                    print("   Local active: \(pointOfUse.active)")
                    print("   Will update view with enabled: \(merchantInfo.enabled)")
                }

                pointOfUse = pointOfUse.updatingMerchant(
                    denominationsType: merchantInfo.denominationsType,
                    denominations: merchantInfo.denominations.compactMap { Int($0) },
                    enabled: merchantInfo.enabled
                )

                // Update the view with the new merchant information
                await MainActor.run {
                    refreshDetailsViewWithUpdatedMerchant()
                }
            }
        }
    }

    private func refreshDetailsViewWithUpdatedMerchant() {
        // Remove the old details view
        detailsView?.removeFromSuperview()

        // Recreate with updated merchant data
        showDetailsView()
    }

    private func tryRefreshCtxToken() async throws -> Bool {
        do {
            try await CTXSpendService.shared.refreshToken()
            return true
        } catch CTXSpendError.tokenRefreshFailed {
            await showModalDialog(style: .warning, icon: .system("exclamationmark.triangle.fill"), heading: NSLocalizedString("Your session expired", comment: "DashSpend"), textBlock1: NSLocalizedString("It looks like you haven’t used DashSpend in a while. For security reasons, you’ve been logged out.\n\nPlease sign in again to continue exploring where to spend your Dash.", comment: "DashSpend"), positiveButtonText: NSLocalizedString("Dismiss", comment: ""))
            return false
        }
    }
}


extension ExplorePointOfUse {
    var showMap: Bool {
        guard case .merchant(let m) = category, m.type == .online else { return true }

        return false
    }

    var title: String? {
        switch category {
        case .merchant:
            return name
        case .atm:
            return source
        case .unknown:
            return nil
        }
    }

    var subtitle: String? {
        switch category {
        case .merchant(let m):
            if m.type == .online {
                return NSLocalizedString("Online Merchant", comment: "Online Merchant")
            } else if let currentLocation = DWLocationManager.shared.currentLocation, DWLocationManager.shared.isAuthorized,
                      let latitude = latitude, let longitude = longitude {
                let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from: currentLocation)
                let distanceString = ExploreDash.distanceFormatter
                    .string(from: Measurement(value: floor(distance), unit: UnitLength.meters))
                return "\(distanceString) · Physical Merchant" + (m.type == .onlineAndPhysical ? ", Online" : "")
            } else {
                return m.type == .onlineAndPhysical ? "Physical Merchant, Online" : "Physical Merchant"
            }
        case .atm:
            return nil
        case .unknown:
            return nil
        }
    }
}

extension UIHostingController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}

extension ExplorePointOfUse {
    func updatingMerchant(denominationsType: String?, denominations: [Int], enabled: Bool? = nil) -> ExplorePointOfUse {
        guard case .merchant(let currentMerchant) = category else { return self }

        let updatedMerchant = ExplorePointOfUse.Merchant(
            merchantId: currentMerchant.merchantId,
            paymentMethod: currentMerchant.paymentMethod,
            type: currentMerchant.type,
            deeplink: currentMerchant.deeplink,
            savingsBasisPoints: currentMerchant.savingsBasisPoints,
            denominationsType: denominationsType,
            denominations: denominations,
            redeemType: currentMerchant.redeemType,
            enabled: enabled ?? currentMerchant.enabled
        )

        return ExplorePointOfUse(
            id: id,
            name: name,
            category: .merchant(updatedMerchant),
            active: active,
            city: city,
            territory: territory,
            address1: address1,
            address2: address2,
            address3: address3,
            address4: address4,
            latitude: latitude,
            longitude: longitude,
            website: website,
            phone: phone,
            logoLocation: logoLocation,
            coverImage: coverImage,
            source: source
        )
    }
}
