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
    internal let pointOfUse: ExplorePointOfUse
    internal let isShowAllHidden: Bool

    @objc public var payWithDashHandler: (()->())?
    @objc var sellDashHandler: (()->())?

    private var contentView: UIView!
    private var detailsView: PointOfUseDetailsView!
    private var mapView: ExploreMapView!

    public init(pointOfUse: ExplorePointOfUse, isShowAllHidden: Bool = true) {
        self.pointOfUse = pointOfUse
        self.isShowAllHidden = isShowAllHidden

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        mapView?.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: mapView.frame.height - detailsView.frame.height - 10,
                                             right: 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pointOfUse.name
        configureHierarchy()
        tryRefreshCtxToken()
    }
}

extension PointOfUseDetailsViewController {
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
            constraint = [
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
        detailsView = detailsView(for: pointOfUse)
        detailsView.payWithDashHandler = payWithDashHandler
        detailsView.sellDashHandler = sellDashHandler
        detailsView.showAllLocationsActionBlock = { [weak self] in
            guard let wSelf = self else { return }

            let vc = AllMerchantLocationsViewController(pointOfUse: wSelf.pointOfUse)
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
            detailsView.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor),
            detailsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            detailsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
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
            return PointOfUseDetailsView(merchant: pointOfUse, isShowAllHidden: isShowAllHidden)
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
                self?.navigationController?.popToRootViewController(animated: true)
                
                // Show gift card details after navigation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .showGiftCardDetails,
                        object: nil,
                        userInfo: ["txId": txId]
                    )
                }
            }
        )
        
        self.navigationController?.pushViewController(hostingController, animated: true)
    }
    
    private func tryRefreshCtxToken() {
        Task {
            do {
                try await CTXSpendService.shared.refreshToken()
            } catch CTXSpendError.tokenRefreshFailed {
                await showModalDialog(style: .warning, icon: .system("exclamationmark.triangle.fill"), heading: NSLocalizedString("Your session expired", comment: "DashSpend"), textBlock1: NSLocalizedString("It looks like you haven’t used DashSpend in a while. For security reasons, you’ve been logged out.\n\nPlease sign in again to continue exploring where to spend your Dash.", comment: "DashSpend"), positiveButtonText: NSLocalizedString("Dismiss", comment: ""))
            }
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
            } else if let currentLocation = DWLocationManager.shared.currentLocation, DWLocationManager.shared.isAuthorized {
                let distance = CLLocation(latitude: latitude!, longitude: longitude!).distance(from: currentLocation)
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
