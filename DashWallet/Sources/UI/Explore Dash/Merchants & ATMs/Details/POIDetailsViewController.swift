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

// MARK: - POIDetailsViewController

class POIDetailsViewController: UIViewController {
    internal var pointOfUse: ExplorePointOfUse
    internal let isShowAllHidden: Bool
    private let searchRadius: Double?
    internal let currentFilters: PointOfUseListFilters?

    @objc public var payWithDashHandler: (()->())?
    @objc var sellDashHandler: (()->())?
    @objc var onGiftCardPurchased: ((Data)->())?

    private var contentView: UIView!
    private var mapView: ExploreMapView!
    private let defaultBottomSheetHeight: CGFloat = 450

    public init(pointOfUse: ExplorePointOfUse, isShowAllHidden: Bool = true, searchRadius: Double? = nil, currentFilters: PointOfUseListFilters? = nil) {
        self.pointOfUse = pointOfUse
        self.isShowAllHidden = isShowAllHidden
        self.searchRadius = searchRadius
        self.currentFilters = currentFilters
        print("🔍 POIDetailsViewController.init: searchRadius=\(String(describing: searchRadius)), currentFilters=\(String(describing: currentFilters))")

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Map inset is now handled by the bottom sheet
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pointOfUse.name
        configureHierarchy()
        refreshTokenAndMerchantInfo()
    }

}

extension POIDetailsViewController {
    @objc
    func payAction() {
        payWithDashHandler?()
    }

    @objc
    func callAction() {
        guard let phone = pointOfUse.phone else { return }
        guard let url = URL(string: "telprompt://\(phone)") else { return }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc
    func websiteAction() {
        guard let website = pointOfUse.website, let url = URL(string: website) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func showMapIfNeeded() {
        guard pointOfUse.showMap else { return }

        mapView = ExploreMapView()
        mapView.show(merchants: [pointOfUse])
        mapView.centerRadius = 5
        mapView.initialCenterLocation = .init(latitude: pointOfUse.latitude!, longitude: pointOfUse.longitude!)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
    
    private func adjustMapCenterForBottomSheet() {
        updateMapForSheetHeight(defaultBottomSheetHeight)
    }
    
    private func updateMapForSheetHeight(_ sheetHeight: CGFloat) {
        guard let mapView = mapView, let location = mapView.initialCenterLocation else { return }
        
        // Set content insets to push the map center up based on sheet height
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: sheetHeight, right: 0)
        mapView.setContentInsets(contentInsets, animated: true)
        
        // Re-center the location
        mapView.setCenter(location, animated: true)
    }

    private func prepareContentView() {
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_secondaryBackground()
        
        if pointOfUse.showMap {
            // Create a bottom sheet container
            let sheetViewController = BottomSheetViewController()
            sheetViewController.contentView = contentView
            sheetViewController.view.backgroundColor = .clear
            
            // Set up height change callback to update map
            sheetViewController.onHeightChanged = { [weak self] height in
                self?.updateMapForSheetHeight(height)
            }
            
            // Add sheet as child view controller
            addChild(sheetViewController)
            view.addSubview(sheetViewController.view)
            sheetViewController.view.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                sheetViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                sheetViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                sheetViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                sheetViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            
            sheetViewController.didMove(toParent: self)
        } else {
            // Non-map view: use regular layout
            view.addSubview(contentView)
            
            NSLayoutConstraint.activate([
                contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
    }

    private func showDetailsView() {
        if case .unknown = pointOfUse.category { return }
        
        // Get current search radius from parent controller if available
        let effectiveRadius: Double
        if let parentVC = navigationController?.viewControllers.dropLast().last as? ExplorePointOfUseListViewController {
            effectiveRadius = parentVC.model.filters?.currentRadius ?? searchRadius ?? kDefaultRadius
        } else {
            effectiveRadius = searchRadius ?? kDefaultRadius
        }

        var detailsView = POIDetailsView(merchant: pointOfUse, isShowAllHidden: isShowAllHidden, searchRadius: effectiveRadius)
        detailsView.payWithDashHandler = payWithDashHandler
        detailsView.sellDashHandler = sellDashHandler
        detailsView.showAllLocationsActionBlock = { [weak self] in
            guard let wSelf = self else { return }

            // Use the same effective radius for both POIDetailsView and AllMerchantLocationsViewController
            let vc = AllMerchantLocationsViewController(pointOfUse: wSelf.pointOfUse, searchRadius: effectiveRadius, currentFilters: wSelf.currentFilters)
            vc.payWithDashHandler = wSelf.payWithDashHandler
            vc.sellDashHandler = wSelf.sellDashHandler
            wSelf.navigationController?.pushViewController(vc, animated: true)
        }
        detailsView.buyGiftCardHandler = { [weak self] provider in
            self?.showDashSpendPayScreen(provider: provider)
        }
        detailsView.dashSpendAuthHandler = { [weak self] provider in
            self?.showDashSpendLoginInfo(provider: provider)
        }
        
        let hostingController = UIHostingController(rootView: detailsView)
        hostingController.view.backgroundColor = .dw_secondaryBackground()
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(hostingController.view)
        guard let hostingView = hostingController.view else { return }
    
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    private func configureHierarchy() {
        showMapIfNeeded()
        prepareContentView()
        showDetailsView()
        
        // Adjust map center after layout is complete
        if pointOfUse.showMap {
            DispatchQueue.main.async { [weak self] in
                self?.adjustMapCenterForBottomSheet()
            }
        }
    }
}


// Mark: DashSpend

extension POIDetailsViewController {
    private func showDashSpendLoginInfo(provider: GiftCardProvider) {
        let swiftUIView = DashSpendLoginInfoView(
            provider: provider,
            onCreateNewAccount: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.showDashSpendTerms(provider: provider)
                }
            },
            onLogIn: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.showDashSpendAuth(authType: .signIn, provider: provider)
                }
            },
            onTermsAndConditions: {
                UIApplication.shared.open(URL(string: provider.termsUrl)!, options: [:], completionHandler: nil)
            }
        )
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.setDetent(450)
        self.present(hostingController, animated: true)
    }
    
    private func showDashSpendTerms(provider: GiftCardProvider) {
        let hostingController = UIHostingController(
            rootView: DashSpendTermsScreen(provider: provider) {
                self.navigationController?.popToViewController(ofType: POIDetailsViewController.self, animated: false)
                self.showDashSpendPayScreen(provider: provider, justAuthenticated: true)
            }
        )
        hostingController.modalPresentationStyle = .fullScreen
        self.navigationController?.pushViewController(hostingController, animated: true)
    }

    private func showDashSpendAuth(authType: DashSpendUserAuthType, provider: GiftCardProvider) {
        let hostingController = UIHostingController(
            rootView: DashSpendUserAuthScreen(authType: authType, provider: provider) {
                self.navigationController?.popViewController(animated: false)
                self.showDashSpendPayScreen(provider: provider, justAuthenticated: true)
            }
        )
        
        self.navigationController?.pushViewController(hostingController, animated: true)
    }
    
    private func showDashSpendPayScreen(provider: GiftCardProvider, justAuthenticated: Bool = false) {
        let hostingController = UIHostingController(
            rootView: DashSpendPayScreen(merchant: self.pointOfUse, provider: provider, justAuthenticated: justAuthenticated) { [weak self] txId in
                // Navigate back to home and show gift card details
                self?.onGiftCardPurchased?(txId)
            }
        )
        
        self.navigationController?.pushViewController(hostingController, animated: true)
    }
    
    private func refreshTokenAndMerchantInfo() {
        Task {
            if try await tryRefreshCtxToken(), let merchantId = pointOfUse.merchant?.merchantId {
                let merchantInfo = try await CTXSpendRepository.shared.getMerchant(merchantId: merchantId)
                pointOfUse = pointOfUse.updatingMerchant(
                    denominationsType: merchantInfo.denominationsType,
                    denominations: merchantInfo.denominations.compactMap { Int($0) }
                )
            }
        }
    }
    
    private func tryRefreshCtxToken() async throws -> Bool {
        do {
            try await CTXSpendRepository.shared.refreshToken()
            return true
        } catch DashSpendError.tokenRefreshFailed {
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
    func updatingMerchant(denominationsType: String?, denominations: [Int]) -> ExplorePointOfUse {
        guard case .merchant(let currentMerchant) = category else { return self }
        
        let updatedMerchant = ExplorePointOfUse.Merchant(
            merchantId: currentMerchant.merchantId,
            paymentMethod: currentMerchant.paymentMethod,
            type: currentMerchant.type,
            deeplink: currentMerchant.deeplink,
            savingsBasisPoints: currentMerchant.savingsBasisPoints,
            denominationsType: denominationsType,
            denominations: denominations,
            redeemType: currentMerchant.redeemType
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

// MARK: - BottomSheetViewController

class BottomSheetViewController: UIViewController {
    var contentView: UIView!
    var onHeightChanged: ((CGFloat) -> Void)?
    
    private var sheetContainerView: UIView!
    private var dragHandleView: UIView!
    private var scrollView: UIScrollView!
    private var contentHeightConstraint: NSLayoutConstraint!
    
    private let defaultHeight: CGFloat = 450
    private let dragHandleHeight: CGFloat = 36
    private let dragHandleWidth: CGFloat = 36
    private let dragHandleCornerRadius: CGFloat = 3
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupGestures()
        updateScrollViewScrollability()
    }
    
    private func setupViews() {
        // Sheet container
        sheetContainerView = UIView()
        sheetContainerView.translatesAutoresizingMaskIntoConstraints = false
        sheetContainerView.backgroundColor = .dw_secondaryBackground()
        sheetContainerView.layer.cornerRadius = 20.0
        sheetContainerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetContainerView.clipsToBounds = true
        view.addSubview(sheetContainerView)
        
        // Drag handle
        dragHandleView = UIView()
        dragHandleView.translatesAutoresizingMaskIntoConstraints = false
        dragHandleView.backgroundColor = UIColor(white: 0.6, alpha: 0.3)
        dragHandleView.layer.cornerRadius = dragHandleCornerRadius
        sheetContainerView.addSubview(dragHandleView)
        
        // Scroll view
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        sheetContainerView.addSubview(scrollView)
        
        // Add content view to scroll view
        scrollView.addSubview(contentView)
        
        // Setup constraints
        contentHeightConstraint = sheetContainerView.heightAnchor.constraint(equalToConstant: defaultHeight)
        
        NSLayoutConstraint.activate([
            // Sheet container
            sheetContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentHeightConstraint,
            
            // Drag handle
            dragHandleView.centerXAnchor.constraint(equalTo: sheetContainerView.centerXAnchor),
            dragHandleView.topAnchor.constraint(equalTo: sheetContainerView.topAnchor, constant: 8),
            dragHandleView.widthAnchor.constraint(equalToConstant: dragHandleWidth),
            dragHandleView.heightAnchor.constraint(equalToConstant: 5),
            
            // Scroll view
            scrollView.topAnchor.constraint(equalTo: dragHandleView.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: sheetContainerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sheetContainerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sheetContainerView.bottomAnchor),
            
            // Content view in scroll view
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        panGesture.delegate = self
        sheetContainerView.addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        
        let minHeight: CGFloat = dragHandleHeight + 20
        let maxHeight = view.frame.height - view.safeAreaInsets.top - 20
        
        switch gesture.state {
        case .changed:
            let newHeight = contentHeightConstraint.constant - translation.y
            contentHeightConstraint.constant = min(max(newHeight, minHeight), maxHeight)
            gesture.setTranslation(.zero, in: view)
            updateScrollViewScrollability()
            onHeightChanged?(contentHeightConstraint.constant)
            
        case .ended:
            let currentHeight = contentHeightConstraint.constant
            let targetHeight: CGFloat
            
            // Determine target height based on velocity and position
            if velocity.y > 500 {
                // Fast downward swipe - minimize
                targetHeight = minHeight
            } else if velocity.y < -500 {
                // Fast upward swipe - maximize
                targetHeight = maxHeight
            } else {
                // Based on position
                let threshold = (maxHeight - minHeight) / 2 + minHeight
                targetHeight = currentHeight > threshold ? maxHeight : defaultHeight
            }
            
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
                self.contentHeightConstraint.constant = targetHeight
                self.view.layoutIfNeeded()
                self.updateScrollViewScrollability()
                self.onHeightChanged?(targetHeight)
            }
            
        default:
            break
        }
    }
    
    private func updateScrollViewScrollability() {
        let maxHeight = view.frame.height - view.safeAreaInsets.top - 20
        let isFullyExpanded = contentHeightConstraint.constant >= maxHeight - 10
        
        // Enable scrolling only when fully expanded
        scrollView.isScrollEnabled = isFullyExpanded
        
        // If not fully expanded, ensure scroll is at top
        if !isFullyExpanded && scrollView.contentOffset.y > 0 {
            scrollView.setContentOffset(.zero, animated: false)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension BottomSheetViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous recognition with scroll view
        if otherGestureRecognizer.view == scrollView {
            let velocity = (gestureRecognizer as? UIPanGestureRecognizer)?.velocity(in: view) ?? .zero
            let isScrollingDown = velocity.y > 0
            let isAtTop = scrollView.contentOffset.y <= 0
            
            // Only allow sheet dragging when scrolling down and at top of content
            return isScrollingDown && isAtTop
        }
        return false
    }
}
