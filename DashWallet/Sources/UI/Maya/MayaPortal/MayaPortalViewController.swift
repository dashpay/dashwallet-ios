//
//  MayaPortalViewController.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import SwiftUI
import UIKit

// MARK: - Maya Flow Architecture Note
//
// The Maya feature uses one UIViewController per screen rather than a single SwiftUI NavigationStack
// container. This is intentional: EnterAddressHostingController requires UIKit for
// ASWebAuthenticationSession (Uphold OAuth), Coinbase.shared.signIn, and QR scanner presentation,
// all of which need a UIViewController as presentation context. Consolidating into a pure SwiftUI
// NavigationStack would require non-trivial UIViewControllerRepresentable bridges for those flows.
//
// Navigation coordination: MayaPortalViewController orchestrates the full flow
// (portal → select coin → enter address → convert). MayaConvertHostingController independently
// pushes OrderPreviewHostingController because it owns the OrderPreviewViewModel factory.
// Both approaches use NavigationBarDisplayable to hide the UIKit nav bar and render their own
// SwiftUI NavigationBar, ensuring a consistent look across all screens.

class MayaPortalViewController: UIViewController, NavigationBarDisplayable {
    var isNavigationBarHidden: Bool { true }

    private let swapProvider: SwapProvider

    init(backend: SwapBackend = .maya) {
        self.swapProvider = backend.makeProvider()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.dw_secondaryBackground()

        let portalView = MayaPortalView(
            onBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onConvertDash: { [weak self] in
                self?.navigateToSelectCoin()
            }
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
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func navigateToSelectCoin() {
        let selectCoinVC = SelectCoinHostingController(swapProvider: swapProvider)
        selectCoinVC.onCoinSelected = { [weak self] coin in
            DSLogger.log("Maya: Selected coin \(coin.code) (\(coin.name))")
            self?.navigateToEnterAddress(for: coin)
        }
        navigationController?.pushViewController(selectCoinVC, animated: true)
    }

    private func navigateToEnterAddress(for coin: MayaCryptoCurrency) {
        let enterAddressVC = EnterAddressHostingController(coin: coin, swapProvider: swapProvider)
        enterAddressVC.onAddressConfirmed = { [weak self] coin, address in
            self?.navigateToConvert(coin: coin, address: address)
        }
        navigationController?.pushViewController(enterAddressVC, animated: true)
    }

    private func navigateToConvert(coin: MayaCryptoCurrency, address: String) {
        let convertVC = MayaConvertHostingController(coin: coin, address: address, swapProvider: swapProvider)
        navigationController?.pushViewController(convertVC, animated: true)
    }
}
