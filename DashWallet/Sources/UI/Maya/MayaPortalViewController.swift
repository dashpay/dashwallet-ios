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

class MayaPortalViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.dw_secondaryBackground()
        navigationItem.largeTitleDisplayMode = .never

        let portalView = MayaPortalView(onConvertDash: { [weak self] in
            self?.navigateToSelectCoin()
        })

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
        let selectCoinVC = SelectCoinHostingController()
        selectCoinVC.onCoinSelected = { [weak self] coin in
            DSLogger.log("Maya: Selected coin \(coin.code) (\(coin.name))")
            self?.navigateToEnterAddress(for: coin)
        }
        navigationController?.pushViewController(selectCoinVC, animated: true)
    }

    private func navigateToEnterAddress(for coin: MayaCryptoCurrency) {
        let enterAddressVC = EnterAddressHostingController(coin: coin)
        enterAddressVC.onAddressConfirmed = { coin, address in
            DSLogger.log("Maya: Address confirmed for \(coin.code): \(address)")
            // TODO: Navigate to Enter Amount (Requirement 5)
        }
        navigationController?.pushViewController(enterAddressVC, animated: true)
    }
}
