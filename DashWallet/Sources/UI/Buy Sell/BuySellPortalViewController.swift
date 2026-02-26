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

import AuthenticationServices
import SwiftUI
import UIKit
import CoreLocation
import Combine

// MARK: - BuySellPortalViewController

@objc
final class BuySellPortalViewController: UIViewController, NavigationBarDisplayable, NavigationStackControllable {

    var isBackButtonHidden: Bool { false }

    private let topperViewModel = TopperViewModel.shared
    private var locationRequested = false

    @objc var showCloseButton = false

    func shouldPopViewController() -> Bool {
        if navigationController?.viewControllers.first == self {
            dismiss(animated: true)
            return false
        }
        return true
    }

    @objc
    func upholdAction() {
        let vc = IntegrationViewController.controller(model: UpholdPortalModel())
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc
    func coinbaseAction() {
        Task {
            if !DWLocationManager.shared.isAuthorized {
                requestLocation()
                return
            }

            if DWLocationManager.shared.currentLocation == nil {
                self.locationRequested = true
                return
            }

            if await isGeoblocked() {
                informGeoblocked()
                return
            }

            navigateToCoinbase()
        }
    }

    func navigateToCoinbase() {
        if Coinbase.shared.isAuthorized {
            let vc = IntegrationViewController.controller(model: CoinbaseEntryPointModel())
            vc.userSignedOutBlock = { [weak self] isNeedToShowSignOutError in
                guard let self else { return }

                self.navigationController!.popToViewController(self, animated: true)

                if isNeedToShowSignOutError {
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now().advanced(by: .milliseconds(500))) {
                        self.showAlert(with: NSLocalizedString("Error", comment: ""),
                                       message: Coinbase.Error.userSessionRevoked.localizedDescription,
                                       presentingViewController: self)
                    }
                }
            }
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        } else {
            let vc = ServiceOverviewViewController.controller()
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    @objc
    func topperAction() {
        let urlString = topperViewModel.topperBuyUrl(walletName: Bundle.main.infoDictionary!["CFBundleDisplayName"] as! String)
        if let url = URL(string: urlString) {
            let safariViewController = SFSafariViewController.dw_controller(with: url)
            present(safariViewController, animated: true)
        }
    }

    func mayaAction() {
        let vc = MayaPortalViewController()
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.dw_secondaryBackground()

        title = nil
        navigationItem.largeTitleDisplayMode = .never

        setupSwiftUIView()
    }

    private func setupSwiftUIView() {
        let portalView = BuySellPortalView(
            showCoinbase: CoinbaseDataSource.shouldShow(),
            onUphold: { [weak self] in self?.upholdAction() },
            onCoinbase: { [weak self] in self?.coinbaseAction() },
            onTopper: { [weak self] in self?.topperAction() },
            onMaya: { [weak self] in self?.mayaAction() }
        )

        let hostingController = UIHostingController(rootView: portalView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc
    class func controller() -> BuySellPortalViewController {
        BuySellPortalViewController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DWLocationManager.shared.add(observer: self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        DWLocationManager.shared.remove(observer: self)
    }
}

// MARK: Geoblock

private let geoblockedCountries = [ "GB" ]

extension BuySellPortalViewController: DWLocationObserver {
    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) { }

    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) {
        if self.locationRequested {
            self.locationRequested = false

            Task {
                if await isGeoblocked() {
                    informGeoblocked()
                } else {
                    navigateToCoinbase()
                }
            }
        }
    }

    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        let status = DWLocationManager.shared.authorizationStatus

        if status == .denied && self.locationRequested {
            informGeoblocked()
        }
    }

    private func requestLocation() {
        showModalDialog(
            style: .regular,
            icon: .system("location.fill"),
            heading: NSLocalizedString("Location", comment: ""),
            textBlock1: NSLocalizedString("Due to regulatory constraints, we need to verify that you are not in the UK.  We only check your location when you enter the Coinbase features.", comment: "Geoblock"),
            positiveButtonText: NSLocalizedString("Continue", comment: ""),
            positiveButtonAction: { [weak self] in
                self?.locationRequested = true

                if DWLocationManager.shared.isPermissionDenied {
                    let settingsUrl = URL(string: UIApplication.openSettingsURLString)!

                    if UIApplication.shared.canOpenURL(settingsUrl) {
                        UIApplication.shared.open(settingsUrl, options: [:], completionHandler: nil)
                    }
                } else {
                    DWLocationManager.shared.requestAuthorization()
                }
            },
            negativeButtonText: NSLocalizedString("Cancel", comment: ""),
            buttonsOrientation: .horizontal
        )
    }

    private func informGeoblocked() {
        let title = NSLocalizedString("Location", comment: "")

        if DWLocationManager.shared.authorizationStatus == .denied {
            showModalDialog(
                style: .regular,
                icon: .system("location.fill"),
                heading: title,
                textBlock1: NSLocalizedString("If you choose to grant permissions at a later time and you are not in the UK, you can use Coinbase", comment: "Geoblock"),
                positiveButtonText: NSLocalizedString("OK", comment: "")
            )
        } else {
            showModalDialog(
                style: .warning,
                icon: .system("exclamationmark.triangle.fill"),
                heading: NSLocalizedString("Due to regulatory constraints, you cannot use the Coinbase features while you are in the UK", comment: "Geoblock"),
                positiveButtonText: NSLocalizedString("OK", comment: "")
            )
        }
    }

    private func isGeoblocked() async -> Bool {
        let locationManager = DWLocationManager.shared

        if let placemark = locationManager.currentPlacemark {
            return geoblockedCountries.contains(placemark.isoCountryCode ?? "")
        } else if locationManager.currentLocation != nil {
            let placemark = await nextEmittedPlacemark()
            return geoblockedCountries.contains(placemark.isoCountryCode ?? "")
        } else {
            return true
        }
    }

    private func nextEmittedPlacemark() async -> CLPlacemark {
        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = DWLocationManager.shared.$currentPlacemark
                .compactMap { $0 }
                .sink { placemark in
                    continuation.resume(returning: placemark)
                    cancellable?.cancel()
                }
        }
    }
}
